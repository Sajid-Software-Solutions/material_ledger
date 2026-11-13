import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/router.dart';
import '../../../../shared/models/yorks_v1_logistics.dart';
import '../../../../shared/models/yorks_v1_material_request.dart';
import '../../../../shared/models/yorks_v1_people.dart';
import '../../../../shared/models/yorks_v1_permission_management.dart';
import '../../../../shared/models/yorks_v1_project_portfolio.dart';
import '../../../../shared/models/yorks_v1_role.dart';
import '../../../../shared/models/yorks_v1_rental.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/permissions_provider.dart';
import '../../../../shared/providers/yorks_v1_audit_provider.dart';
import '../../../../shared/providers/yorks_v1_feature_flags_provider.dart';
import '../../../../shared/providers/yorks_v1_people_provider.dart';
import '../../../../shared/providers/yorks_v1_rental_provider.dart';
import '../../../../shared/providers/session_provider.dart';
import '../../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../../../shared/providers/yorks_v1_logistics_provider.dart';
import '../../../../shared/providers/yorks_v1_material_request_provider.dart';
import '../../../../shared/providers/yorks_v1_permission_provider.dart';
import '../../../../shared/providers/yorks_v1_project_portfolio_provider.dart';
import '../../../materials/presentation/yorks_v1_feature_action_access.dart';
import '../../../people_records/presentation/people_kit.dart'
    show peopleNewPath, peoplePath, peoplePersonPath;
import '../../../workforce/application/attendance_providers.dart';
import '../../../workforce/domain/crew_request_models.dart';
import '../../../workforce/presentation/requests/crew_request_common.dart'
    show crewRequestPath;
import 'yorks_v1_role_overview_builders.dart';
import 'yorks_v1_role_overview_layout.dart';

/// Role-based Overview (`YORKS_V1_ROLE_OVERVIEW_V2`).
///
/// Each exact role reads only the protected projections its cards need, then
/// [buildYorksRoleOverviewSpec] shapes them into the approved prototype
/// layout. The screen is a navigation surface: every row opens the record
/// that owns its workflow transition.
class YorksV1RoleOverviewScreen extends ConsumerStatefulWidget {
  const YorksV1RoleOverviewScreen({super.key});

  @override
  ConsumerState<YorksV1RoleOverviewScreen> createState() =>
      _YorksV1RoleOverviewScreenState();
}

/// Bounded queries. The server caps a page at 100 rows.
final _myWorkQuery = YorksV1MaterialRequestSummaryQuery(
  registerView: YorksV1MaterialRequestRegisterView.myWork,
  newestFirst: false,
  limit: 100,
);
final _exceptionsQuery = YorksV1MaterialRequestSummaryQuery(
  registerView: YorksV1MaterialRequestRegisterView.exceptions,
  newestFirst: false,
  limit: 100,
);
final _activeQuery = YorksV1MaterialRequestSummaryQuery(
  states: yorksOverviewOpenStates,
  limit: 100,
);
final _mineQuery = YorksV1MaterialRequestSummaryQuery(
  registerView: YorksV1MaterialRequestRegisterView.mine,
  states: yorksOverviewOpenStates,
  limit: 100,
);

/// Deliveries in flight, oldest first, so a long-waiting dispatch is never
/// pushed out by newer activity.
final _deliveryQuery = YorksV1MaterialRequestSummaryQuery(
  states: const [
    YorksV1MaterialRequestState.approved,
    YorksV1MaterialRequestState.partiallyDispatched,
    YorksV1MaterialRequestState.dispatched,
    YorksV1MaterialRequestState.partiallyReceived,
  ],
  newestFirst: false,
  limit: 100,
);

YorksV1MaterialRequestSummaryQuery _closedQuery(DateTime now) {
  final day = DateTime(now.year, now.month, now.day);
  return YorksV1MaterialRequestSummaryQuery(
    states: const [YorksV1MaterialRequestState.closed],
    updatedAfter: day.subtract(const Duration(days: 7)),
    limit: 20,
  );
}

class _YorksV1RoleOverviewScreenState
    extends ConsumerState<YorksV1RoleOverviewScreen> {
  DateTime? _updatedAt;
  bool _refreshing = false;

  // Fixed for the life of the screen so the provider family key is stable.
  late final DateTime _openedAt = DateTime.now();
  late final YorksV1MaterialRequestSummaryQuery _closed = _closedQuery(
    _openedAt,
  );

  @override
  Widget build(BuildContext context) {
    ref.watch(yorksV1MaterialRequestLiveRefreshProvider);
    final language = ref.watch(languageProvider);
    final role = ref.watch(yorksV1CurrentRoleProvider);
    final permissions = ref.watch(yorksV1CurrentPermissionSnapshotProvider);
    final user = ref.watch(currentUserProvider);
    final authUserId = ref.watch(yorksV1AuthUserIdProvider);
    final flags = ref.watch(yorksV1FeatureFlagsProvider);

    // PR's Overview is people, crews and rentals; it reads no Material
    // Request or project projection.
    final pr = role == YorksV1Role.pr;
    final canViewPeople =
        pr &&
        flags.peopleRecords &&
        permissions.hybridAllows(
          YorksV1CapabilityKeys.peopleRecordsView,
          legacyAllowed: false,
          organizationSummary: true,
        );
    final canManagePeople =
        canViewPeople &&
        permissions.hybridAllows(
          YorksV1CapabilityKeys.peopleRecordsManage,
          legacyAllowed: false,
          organizationSummary: true,
        );
    final needsCrewRequests = pr && flags.workforceCenter;

    // Each role loads only the projections its cards use.
    final needsActive = switch (role) {
      YorksV1Role.projectEngineer ||
      YorksV1Role.projectManager ||
      YorksV1Role.admin ||
      null => true,
      _ => false,
    };
    final needsDelivery =
        role == YorksV1Role.siteEngineer || role == YorksV1Role.procurement;
    final needsPortfolio = switch (role) {
      YorksV1Role.projectEngineer ||
      YorksV1Role.projectManager ||
      YorksV1Role.seniorMechanicalEngineer ||
      YorksV1Role.admin ||
      null => true,
      _ => false,
    };
    final needsMine =
        role == YorksV1Role.siteEngineer ||
        role == YorksV1Role.workshopInCharge;
    final canBrowseInventory = permissions.hybridAllows(
      YorksV1CapabilityKeys.inventoryView,
      legacyAllowed: role?.canBrowseInventory == true,
      organizationSummary: true,
    );
    final needsInventory =
        canBrowseInventory &&
        (role == YorksV1Role.procurement ||
            role == YorksV1Role.seniorMechanicalEngineer ||
            role == YorksV1Role.admin);
    final createProject = yorksV1FeatureActionAccess(
      permissions,
      YorksV1CapabilityKeys.projectsCreate,
      legacyAllowed: role?.canCreateProject == true,
    );
    final createRequest = yorksV1FeatureActionAccess(
      permissions,
      YorksV1CapabilityKeys.materialRequestsCreate,
      legacyAllowed: role?.canCreateMaterialRequest == true,
      anyProject: true,
    );
    final canManageUsers = permissions.hybridAllows(
      YorksV1CapabilityKeys.usersView,
      legacyAllowed: role?.canConfigureUsers ?? false,
    );

    final projects = pr
        ? const AsyncLoading<YorksV1ProjectOverview>()
        : ref.watch(yorksV1ProjectOverviewProvider);
    final portfolio = needsPortfolio
        ? ref.watch(yorksV1ProjectPortfolioProvider)
        : const AsyncData<List<YorksV1ProjectPortfolioItem>>([]);
    final requests = pr
        ? const AsyncLoading<YorksV1MaterialRequestOverview>()
        : ref.watch(yorksV1MaterialRequestOverviewProvider(6));
    final myWork = pr
        ? const AsyncLoading<YorksV1MaterialRequestSummaryPage>()
        : ref.watch(yorksV1MaterialRequestSummaryPageProvider(_myWorkQuery));
    final exceptions = pr
        ? const AsyncLoading<YorksV1MaterialRequestSummaryPage>()
        : ref.watch(
            yorksV1MaterialRequestSummaryPageProvider(_exceptionsQuery),
          );
    final people = canViewPeople
        ? ref.watch(yorksV1PeopleOverviewProvider)
        : null;
    final crewRequests = needsCrewRequests
        ? ref.watch(yorksCrewRequestsProvider)
        : null;
    final active = needsActive
        ? ref.watch(yorksV1MaterialRequestSummaryPageProvider(_activeQuery))
        : null;
    final delivery = needsDelivery
        ? ref.watch(yorksV1MaterialRequestSummaryPageProvider(_deliveryQuery))
        : null;
    final mine = needsMine
        ? ref.watch(yorksV1MaterialRequestSummaryPageProvider(_mineQuery))
        : null;
    final closed = role == YorksV1Role.documentController
        ? ref.watch(yorksV1MaterialRequestSummaryPageProvider(_closed))
        : null;
    final inventory = needsInventory
        ? ref
              .watch(yorksV1InventoryWorkspaceProvider(null))
              .whenData<YorksV1InventoryWorkspace?>((value) => value)
        : null;
    final operations = role == YorksV1Role.procurement
        ? ref.watch(yorksV1MaterialRequestOperationsDashboardProvider(null))
        : null;
    final drafts = role == YorksV1Role.siteEngineer && authUserId != null
        ? ref.watch(yorksV1MaterialRequestPrivateDraftsProvider(authUserId))
        : null;

    // Admin keeps the rental and audit summaries from the retained command
    // centre; both providers enforce their own Admin-only access.
    final admin = role == YorksV1Role.admin;
    final canAccessRentals = admin
        ? ref.watch(canAccessRentalsProvider)
        : pr &&
              permissions.hybridAllows(
                YorksV1CapabilityKeys.rentalsView,
                legacyAllowed: true,
                organizationSummary: true,
              );
    final rentals = canAccessRentals
        ? ref
              .watch(yorksV1RentalPortfolioProvider)
              .whenData<YorksV1RentalPortfolio?>((value) => value)
        : null;
    final audit = admin ? ref.watch(yorksV1AuditControllerProvider) : null;

    final core = pr
        ? <AsyncValue<Object?>>[?people, ?crewRequests]
        : [projects, requests, myWork, exceptions];
    final ready = core.every((value) => value.hasValue || value.hasError);
    if (ready && _updatedAt == null) {
      _updatedAt = DateTime.now();
    }

    final input = YorksRoleOverviewInputs(
      role: role,
      language: language,
      now: DateTime.now(),
      displayName: user?.fullName,
      projects: projects,
      portfolio: portfolio,
      requests: requests,
      myWork: myWork,
      exceptions: exceptions,
      active: active,
      delivery: delivery,
      mine: mine,
      closed: closed,
      inventory: inventory,
      operations: operations,
      drafts: drafts,
      rentals: rentals,
      audit: audit?.workspace,
      auditLoading: audit?.isLoading ?? false,
      auditFailed: audit?.error != null && audit?.workspace == null,
      people: people,
      crewRequests: crewRequests,
      canCreateProject: createProject.isVisible,
      canCreateRequest: createRequest.isVisible,
      canBrowseInventory: canBrowseInventory,
      canManageUsers: canManageUsers,
      canReadProject: (projectId) => yorksV1CanReadProjectRecord(
        permissions,
        YorksV1CapabilityKeys.projectsView,
        legacyAllowed: true,
        projectId: projectId,
      ),
      canReadRequest: (projectId) => yorksV1CanReadProjectRecord(
        permissions,
        YorksV1CapabilityKeys.materialRequestsView,
        legacyAllowed: true,
        projectId: projectId,
      ),
    );

    final nav = YorksRoleOverviewNavigation(
      openRequest: (request) => context.push(_requestPath(request)),
      openRequests: () => context.go(RoutePaths.yorksV1MaterialRequests),
      openProjects: () => context.go(RoutePaths.yorksV1Projects),
      openProject: (id) => context.push(RoutePaths.yorksV1ProjectPath(id)),
      newRequest: createRequest.canWrite
          ? () => context.push(
              RoutePaths.yorksV1MaterialRequestDraftPath(
                const Uuid().v4(),
                entryMode: YorksV1MaterialRequestDraftEntryMode.newDraft,
              ),
            )
          : null,
      newProject: createProject.canWrite
          ? () => context.push(RoutePaths.engineerCreateProject)
          : null,
      openDraft: (record) => context.push(
        RoutePaths.yorksV1MaterialRequestDraftPath(record.draftId),
      ),
      openInventory: canBrowseInventory
          ? () => context.go(RoutePaths.yorksV1Inventory)
          : null,
      openDispatches: role == YorksV1Role.procurement
          ? () => context.go(RoutePaths.yorksV1Dispatches)
          : null,
      openReturns: () => context.go(RoutePaths.yorksV1Returns),
      newReturn: role?.canCreateMaterialRequest == true
          ? () => context.push(RoutePaths.yorksV1MaterialReturnNew)
          : null,
      openUsers: canManageUsers ? () => context.go(RoutePaths.users) : null,
      openDuctSizer: () => context.push(RoutePaths.yorksV1DuctSizer),
      openEspCalculator: () => context.push(RoutePaths.yorksV1EspCalculator),
      openRentals: canAccessRentals
          ? () => context.go(RoutePaths.rentals)
          : null,
      openAudit: admin ? () => context.go(RoutePaths.activityLog) : null,
      openPeople: canViewPeople ? () => context.go(peoplePath) : null,
      newPerson: canManagePeople ? () => context.push(peopleNewPath) : null,
      openPerson: canViewPeople
          ? (id) => context.push(peoplePersonPath(id))
          : null,
      openWorkforce: pr && flags.workforce
          ? () => context.go(RoutePaths.yorksV1Workforce)
          : null,
      openCrewRequest: needsCrewRequests
          ? (id) => context.push(crewRequestPath(id))
          : null,
      retry: () => _refresh(
        includeActive: needsActive,
        includeDelivery: needsDelivery,
        includePortfolio: needsPortfolio,
        includeMine: needsMine,
        includeInventory: needsInventory,
        includePeople: canViewPeople,
        includeCrewRequests: needsCrewRequests,
        includeRentals: canAccessRentals,
        role: role,
        authUserId: authUserId,
      ),
      retryAudit: admin
          ? () => ref.read(yorksV1AuditControllerProvider.notifier).load()
          : null,
    );

    final spec = buildYorksRoleOverviewSpec(input, nav);
    return YorksRoleOverviewLayout(
      spec: spec,
      language: language,
      updatedAt: _updatedAt,
      refreshing: _refreshing || !ready,
      onRefresh: () => _refresh(
        includeActive: needsActive,
        includeDelivery: needsDelivery,
        includePortfolio: needsPortfolio,
        includeMine: needsMine,
        includeInventory: needsInventory,
        includePeople: canViewPeople,
        includeCrewRequests: needsCrewRequests,
        includeRentals: canAccessRentals,
        role: role,
        authUserId: authUserId,
      ),
    );
  }

  Future<void> _refresh({
    required bool includeActive,
    required bool includeDelivery,
    required bool includePortfolio,
    required bool includeMine,
    required bool includeInventory,
    required bool includePeople,
    required bool includeCrewRequests,
    required bool includeRentals,
    required YorksV1Role? role,
    required String? authUserId,
  }) async {
    setState(() => _refreshing = true);
    final pr = role == YorksV1Role.pr;
    final futures = <Future<Object?>>[
      if (!pr) ...[
        ref.refresh(yorksV1ProjectOverviewProvider.future),
        ref.refresh(yorksV1MaterialRequestOverviewProvider(6).future),
        ref.refresh(
          yorksV1MaterialRequestSummaryPageProvider(_myWorkQuery).future,
        ),
        ref.refresh(
          yorksV1MaterialRequestSummaryPageProvider(_exceptionsQuery).future,
        ),
      ],
      if (includePortfolio) ref.refresh(yorksV1ProjectPortfolioProvider.future),
      if (includePeople)
        ref.refresh<Future<PeopleOverview>>(
          yorksV1PeopleOverviewProvider.future,
        ),
      if (includeCrewRequests)
        ref.refresh<Future<CrewRequestRegister>>(
          yorksCrewRequestsProvider.future,
        ),
      if (includeActive)
        ref.refresh(
          yorksV1MaterialRequestSummaryPageProvider(_activeQuery).future,
        ),
      if (includeDelivery)
        ref.refresh(
          yorksV1MaterialRequestSummaryPageProvider(_deliveryQuery).future,
        ),
      if (includeMine)
        ref.refresh(
          yorksV1MaterialRequestSummaryPageProvider(_mineQuery).future,
        ),
      if (role == YorksV1Role.documentController)
        ref.refresh(yorksV1MaterialRequestSummaryPageProvider(_closed).future),
      if (includeInventory)
        ref.refresh(yorksV1InventoryWorkspaceProvider(null).future),
      if (role == YorksV1Role.procurement)
        ref.refresh(
          yorksV1MaterialRequestOperationsDashboardProvider(null).future,
        ),
      if (includeRentals) ref.refresh(yorksV1RentalPortfolioProvider.future),
      if (role == YorksV1Role.admin)
        ref.read(yorksV1AuditControllerProvider.notifier).load(),
      if (role == YorksV1Role.siteEngineer && authUserId != null)
        ref.refresh(
          yorksV1MaterialRequestPrivateDraftsProvider(authUserId).future,
        ),
    ];
    await Future.wait(futures.map((f) => f.catchError((_) => null)));
    if (!mounted) return;
    setState(() {
      _refreshing = false;
      _updatedAt = DateTime.now();
    });
  }
}

/// Opens the workspace that owns the record's current step.
String _requestPath(YorksV1MaterialRequestSummary request) {
  if (!request.actorCanAct) {
    return RoutePaths.yorksV1MaterialRequestPath(request.id);
  }
  return switch (yorksOverviewWorkKind(request)) {
    YorksOverviewWorkKind.arrange =>
      RoutePaths.yorksV1MaterialRequestArrangementPath(request.id),
    YorksOverviewWorkKind.dispatch || YorksOverviewWorkKind.replacement =>
      RoutePaths.yorksV1MaterialRequestLogisticsPath(request.id),
    YorksOverviewWorkKind.receipt =>
      RoutePaths.yorksV1MaterialRequestLogisticsPath(
        request.id,
        focusReceiptReview: true,
      ),
    _ => RoutePaths.yorksV1MaterialRequestPath(request.id),
  };
}

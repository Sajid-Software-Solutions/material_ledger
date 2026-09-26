import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_project.dart';
import '../../../../shared/models/yorks_v1_boq.dart';
import '../../../../shared/models/yorks_v1_document.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/models/yorks_v1_project_portfolio.dart';
import '../../../../shared/models/yorks_v1_project_strings.dart';
import '../../../../shared/models/yorks_v1_project_team_directory_member.dart';
import '../../../../shared/models/yorks_v1_role.dart';
import '../../../../shared/models/yorks_v1_material_request.dart';
import '../../../../shared/models/yorks_v1_logistics.dart';
import '../../../../shared/models/yorks_v1_configuration.dart';
import '../../../../shared/models/yorks_v1_material_request_strings.dart';
import '../../../../shared/models/yorks_v1_overview_strings.dart';
import '../../../../shared/models/yorks_v1_permission_management.dart';
import '../../../../shared/models/yorks_v1_rental.dart';
import '../../../../shared/models/yorks_v1_shell_strings.dart';
import '../../../../shared/models/yorks_v1_team_chat.dart';
import '../../../../shared/models/yorks_v1_team_chat_strings.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/permissions_provider.dart';
import '../../../../shared/providers/session_provider.dart';
import '../../../../shared/providers/yorks_v1_audit_provider.dart';
import '../../../../shared/providers/yorks_v1_configuration_provider.dart';
import '../../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../../../shared/providers/yorks_v1_feature_flags_provider.dart';
import '../../../../shared/providers/yorks_v1_material_request_provider.dart';
import '../../../../shared/providers/yorks_v1_boq_provider.dart';
import '../../../../shared/providers/yorks_v1_documents_provider.dart';
import '../../../../shared/providers/yorks_v1_logistics_provider.dart';
import '../../../../shared/providers/yorks_v1_project_controller_provider.dart';
import '../../../../shared/providers/yorks_v1_project_portfolio_provider.dart';
import '../../../../shared/providers/yorks_v1_project_team_directory_provider.dart';
import '../../../../shared/providers/yorks_v1_permission_provider.dart';
import '../../../../shared/providers/yorks_v1_rental_provider.dart';
import '../../../../shared/providers/yorks_v1_team_chat_provider.dart';
import 'yorks_v1_boq_screens.dart';
import 'yorks_v1_documents_screen.dart';
import 'yorks_v1_executive_overview.dart';
import '../../../company_overview/application/company_analytics_providers.dart';
import '../../../company_overview/domain/company_analytics_models.dart';
import '../../../materials/presentation/yorks_v1_feature_action_access.dart';
import '../../../materials/presentation/screens/yorks_v1_material_request_screens.dart';
import '../../../accounts/presentation/screens/yorks_accounts_screens.dart';

/// The normalized, R35-aligned project portfolio.
///
/// It intentionally replaces the retained local project register only inside
/// the Yorks V1 rollout. Its rows are server-authorized non-commercial V1
/// projections and route into connected BOQ, request and document flows.
class YorksV1ProjectsScreen extends ConsumerStatefulWidget {
  const YorksV1ProjectsScreen({
    super.key,
    this.initialState,
    this.initialSearch,
  });

  final YorksV1ProjectLifecycle? initialState;
  final String? initialSearch;

  @override
  ConsumerState<YorksV1ProjectsScreen> createState() =>
      _YorksV1ProjectsScreenState();
}

/// R35's role-aware operational overview.
///
/// It replaces the retained V7 dashboard only while the normalized Yorks V1
/// rollout is active. Every number and card comes from a safe V1 projection;
/// the overview is deliberately a navigation surface and never owns workflow
/// transitions itself.
class YorksV1OverviewScreen extends ConsumerWidget {
  const YorksV1OverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final role = ref.watch(yorksV1CurrentRoleProvider);
    // Accountant is a provisionable R39 identity before the Accounts module is
    // enabled. Keep the retained technical overview fail-closed and, crucially,
    // return before subscribing to any project, MR, inventory, realtime or
    // administration provider.
    if (role == YorksV1Role.accountant) {
      return _AccountantRolloutLockedState(language: language);
    }

    ref.watch(yorksV1MaterialRequestLiveRefreshProvider);
    final permissions = ref.watch(yorksV1CurrentPermissionSnapshotProvider);
    final user = ref.watch(currentUserProvider);
    final featureFlags = ref.watch(yorksV1FeatureFlagsProvider);
    final executive =
        role == YorksV1Role.admin || (role?.isGlobalProjectEngineer ?? false);
    final admin = role == YorksV1Role.admin;
    final AsyncValue<YorksV1ProjectOverview> projectOverview = ref.watch(
      yorksV1ProjectOverviewProvider,
    );
    final projects = projectOverview.whenData(
      (overview) => overview.items
          .where(
            (item) => yorksV1CanReadProjectRecord(
              permissions,
              YorksV1CapabilityKeys.projectsView,
              legacyAllowed: true,
              projectId: item.project.id,
            ),
          )
          .toList(growable: false),
    );
    final AsyncValue<YorksV1MaterialRequestOverview> requestOverview = ref
        .watch(yorksV1MaterialRequestOverviewProvider(6));
    final requests = requestOverview.whenData(
      (overview) => overview.items
          .where(
            (item) => yorksV1CanReadProjectRecord(
              permissions,
              YorksV1CapabilityKeys.materialRequestsView,
              legacyAllowed: true,
              projectId: item.projectId,
            ),
          )
          .toList(growable: false),
    );
    final createProjectAccess = yorksV1FeatureActionAccess(
      permissions,
      YorksV1CapabilityKeys.projectsCreate,
      legacyAllowed: role?.canCreateProject == true,
    );
    final createRequestAccess = yorksV1FeatureActionAccess(
      permissions,
      YorksV1CapabilityKeys.materialRequestsCreate,
      legacyAllowed: role?.canCreateMaterialRequest == true,
      anyProject: true,
    );
    final canCreateProject = createProjectAccess.isVisible;
    final canCreateRequest = createRequestAccess.isVisible;
    final procurement = role == YorksV1Role.procurement;
    final canBrowseInventory = permissions.hybridAllows(
      YorksV1CapabilityKeys.inventoryView,
      legacyAllowed: role?.canBrowseInventory == true,
      organizationSummary: true,
    );
    final canOpenAnalytics =
        featureFlags.analytics &&
        permissions.hybridAllows(
          YorksV1CapabilityKeys.analyticsView,
          legacyAllowed: false,
          organizationSummary: true,
        );
    final AsyncValue<CompanyAnalyticsProjection?> companyAnalytics =
        admin && canOpenAnalytics
        ? ref
              .watch(
                companyAnalyticsProjectionProvider(
                  const CompanyAnalyticsFilters(months: 6),
                ),
              )
              .whenData<CompanyAnalyticsProjection?>((value) => value)
        : const AsyncData<CompanyAnalyticsProjection?>(null);
    final canAccessRentals = admin && ref.watch(canAccessRentalsProvider);
    final shouldLoadInventory = canBrowseInventory;
    final AsyncValue<YorksV1InventoryWorkspace?> inventory = shouldLoadInventory
        ? ref
              .watch(yorksV1InventoryWorkspaceProvider(null))
              .whenData<YorksV1InventoryWorkspace?>((value) => value)
        : const AsyncData<YorksV1InventoryWorkspace?>(null);

    final projectCounts = projectOverview.valueOrNull;
    final requestCounts = requestOverview.valueOrNull;
    final openRequests = requestCounts?.open ?? 0;
    final needsAction = requestCounts?.needsAction ?? 0;
    final dispatchReady = requestCounts?.dispatchReady ?? 0;

    if (executive && role != null) {
      final configuration = admin
          ? ref
                .watch(yorksV1ConfigurationCentreProvider)
                .whenData<YorksV1ConfigurationCentre?>((value) => value)
          : const AsyncData<YorksV1ConfigurationCentre?>(null);
      final rentals = canAccessRentals
          ? ref
                .watch(yorksV1RentalPortfolioProvider)
                .whenData<YorksV1RentalPortfolio?>((value) => value)
          : const AsyncData<YorksV1RentalPortfolio?>(null);
      final audit = admin ? ref.watch(yorksV1AuditControllerProvider) : null;
      final activeUsers = admin ? audit?.workspace?.summary.activeUsers : null;
      return YorksV1ExecutiveOverview(
        language: language,
        role: role,
        displayName: user?.fullName,
        projects: projects,
        projectOverview: projectCounts,
        requests: requests,
        requestOverview: requestCounts,
        inventory: inventory,
        configuration: configuration,
        rentals: rentals,
        audit: audit,
        activeUsers: activeUsers,
        canBrowseInventory: canBrowseInventory,
        canAccessRentals: canAccessRentals,
        canOpenAnalytics: canOpenAnalytics,
        companyAnalytics: companyAnalytics,
        featureFlags: featureFlags,
        onRefresh: () async {
          final operations = <Future<Object?>>[
            ref.refresh(yorksV1ProjectOverviewProvider.future),
            ref.refresh(yorksV1MaterialRequestOverviewProvider(6).future),
            if (shouldLoadInventory)
              ref.refresh(yorksV1InventoryWorkspaceProvider(null).future),
            if (admin) ref.refresh(yorksV1ConfigurationCentreProvider.future),
            if (canAccessRentals)
              ref.refresh(yorksV1RentalPortfolioProvider.future),
            if (admin && canOpenAnalytics)
              ref.refresh(
                companyAnalyticsProjectionProvider(
                  const CompanyAnalyticsFilters(months: 6),
                ).future,
              ),
          ];
          await Future.wait(
            operations.map((future) => future.catchError((_) => null)),
          );
          if (admin) {
            await ref.read(yorksV1AuditControllerProvider.notifier).load();
          }
        },
      );
    }

    return _R35OverviewPage(
      language: language,
      role: role,
      displayName: user?.fullName,
      projects: projects,
      projectOverview: projectCounts,
      requests: requests,
      requestOverview: requestCounts,
      projectCount: projectCounts?.total ?? 0,
      openRequests: openRequests,
      needsAction: needsAction,
      dispatchReady: dispatchReady,
      canCreateProject: canCreateProject,
      canCreateRequest: canCreateRequest,
      procurement: procurement,
      canBrowseInventory: canBrowseInventory,
      inventory: inventory,
      onCreateProject: createProjectAccess.canWrite
          ? () => context.push(RoutePaths.engineerCreateProject)
          : null,
      onCreateRequest: createRequestAccess.canWrite
          ? () => context.push(
              RoutePaths.yorksV1MaterialRequestDraftPath(
                const Uuid().v4(),
                entryMode: YorksV1MaterialRequestDraftEntryMode.newDraft,
              ),
            )
          : null,
      onOpenProjects: () => context.go(RoutePaths.yorksV1Projects),
      onOpenRequests: () => context.go(RoutePaths.yorksV1MaterialRequests),
      onRetryProjects: () => ref.invalidate(yorksV1ProjectOverviewProvider),
      onRetryRequests: () =>
          ref.invalidate(yorksV1MaterialRequestOverviewProvider),
    );
  }
}

class _R35OverviewPage extends StatelessWidget {
  const _R35OverviewPage({
    required this.language,
    required this.role,
    required this.displayName,
    required this.projects,
    required this.projectOverview,
    required this.requests,
    required this.requestOverview,
    required this.projectCount,
    required this.openRequests,
    required this.needsAction,
    required this.dispatchReady,
    required this.canCreateProject,
    required this.canCreateRequest,
    required this.procurement,
    required this.canBrowseInventory,
    required this.inventory,
    required this.onCreateProject,
    required this.onCreateRequest,
    required this.onOpenProjects,
    required this.onOpenRequests,
    required this.onRetryProjects,
    required this.onRetryRequests,
  });

  final AppLanguage language;
  final YorksV1Role? role;
  final String? displayName;
  final AsyncValue<List<YorksV1ProjectPortfolioItem>> projects;
  final YorksV1ProjectOverview? projectOverview;
  final AsyncValue<List<YorksV1MaterialRequest>> requests;
  final YorksV1MaterialRequestOverview? requestOverview;
  final int projectCount;
  final int openRequests;
  final int needsAction;
  final int dispatchReady;
  final bool canCreateProject;
  final bool canCreateRequest;
  final bool procurement;
  final bool canBrowseInventory;
  final AsyncValue<YorksV1InventoryWorkspace?> inventory;
  final VoidCallback? onCreateProject;
  final VoidCallback? onCreateRequest;
  final VoidCallback onOpenProjects;
  final VoidCallback onOpenRequests;
  final VoidCallback onRetryProjects;
  final VoidCallback onRetryRequests;

  @override
  Widget build(BuildContext context) {
    if (YorksMobileUi.isActive(context)) {
      return _YorksMobileOverview(
        language: language,
        role: role,
        displayName: displayName,
        projects: projects,
        projectOverview: projectOverview,
        requests: requests,
        requestOverview: requestOverview,
        projectCount: projectCount,
        openRequests: openRequests,
        needsAction: needsAction,
        dispatchReady: dispatchReady,
        canCreateProject: canCreateProject,
        canCreateRequest: canCreateRequest,
        canBrowseInventory: canBrowseInventory,
        inventory: inventory,
        onCreateProject: onCreateProject,
        onCreateRequest: onCreateRequest,
        onOpenProjects: onOpenProjects,
        onOpenRequests: onOpenRequests,
        onRetryProjects: onRetryProjects,
        onRetryRequests: onRetryRequests,
      );
    }
    if (procurement) {
      return _R35ProcurementOverview(
        requests: requests,
        requestOverview: requestOverview,
        inventory: inventory,
        onOpenRequests: onOpenRequests,
        onOpenProjects: onOpenProjects,
      );
    }
    return _R35RoleAwareOverview(
      language: language,
      role: role,
      displayName: displayName,
      projects: projects,
      projectOverview: projectOverview,
      requests: requests,
      requestOverview: requestOverview,
      inventory: inventory,
      projectCount: projectCount,
      openRequests: openRequests,
      needsAction: needsAction,
      dispatchReady: dispatchReady,
      canCreateProject: canCreateProject,
      canCreateRequest: canCreateRequest,
      canBrowseInventory: canBrowseInventory,
      onCreateProject: onCreateProject,
      onCreateRequest: onCreateRequest,
      onOpenProjects: onOpenProjects,
      onOpenRequests: onOpenRequests,
      onRetryProjects: onRetryProjects,
      onRetryRequests: onRetryRequests,
    );
  }
}

class _YorksMobileOverview extends StatelessWidget {
  const _YorksMobileOverview({
    required this.language,
    required this.role,
    required this.displayName,
    required this.projects,
    required this.projectOverview,
    required this.requests,
    required this.requestOverview,
    required this.projectCount,
    required this.openRequests,
    required this.needsAction,
    required this.dispatchReady,
    required this.canCreateProject,
    required this.canCreateRequest,
    required this.canBrowseInventory,
    required this.inventory,
    required this.onCreateProject,
    required this.onCreateRequest,
    required this.onOpenProjects,
    required this.onOpenRequests,
    required this.onRetryProjects,
    required this.onRetryRequests,
  });

  final AppLanguage language;
  final YorksV1Role? role;
  final String? displayName;
  final AsyncValue<List<YorksV1ProjectPortfolioItem>> projects;
  final YorksV1ProjectOverview? projectOverview;
  final AsyncValue<List<YorksV1MaterialRequest>> requests;
  final YorksV1MaterialRequestOverview? requestOverview;
  final int projectCount;
  final int openRequests;
  final int needsAction;
  final int dispatchReady;
  final bool canCreateProject;
  final bool canCreateRequest;
  final bool canBrowseInventory;
  final AsyncValue<YorksV1InventoryWorkspace?> inventory;
  final VoidCallback? onCreateProject;
  final VoidCallback? onCreateRequest;
  final VoidCallback onOpenProjects;
  final VoidCallback onOpenRequests;
  final VoidCallback onRetryProjects;
  final VoidCallback onRetryRequests;

  @override
  Widget build(BuildContext context) => _R35RoleAwareOverview(
    language: language,
    role: role,
    displayName: displayName,
    projects: projects,
    projectOverview: projectOverview,
    requests: requests,
    requestOverview: requestOverview,
    inventory: inventory,
    projectCount: projectCount,
    openRequests: openRequests,
    needsAction: needsAction,
    dispatchReady: dispatchReady,
    canCreateProject: canCreateProject,
    canCreateRequest: canCreateRequest,
    canBrowseInventory: canBrowseInventory,
    onCreateProject: onCreateProject,
    onCreateRequest: onCreateRequest,
    onOpenProjects: onOpenProjects,
    onOpenRequests: onOpenRequests,
    onRetryProjects: onRetryProjects,
    onRetryRequests: onRetryRequests,
    compact: true,
  );
}

enum _OverviewMetricKind {
  projects,
  openRequests,
  needsAction,
  approvals,
  deliveryExceptions,
  receiptPending,
  draftsAndChanges,
  closedRequests,
  inventoryAttention,
  projectsOnHold,
  dispatchReady,
  newToArrange,
}

enum _OverviewActionKind {
  projects,
  materialRequests,
  inventory,
  returns,
  users,
  configuration,
  audit,
  rentals,
}

class _OverviewRoleProfile {
  const _OverviewRoleProfile({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.priorityTitle,
    required this.metrics,
    required this.actions,
  });

  final TranslatableString eyebrow;
  final TranslatableString title;
  final TranslatableString description;
  final TranslatableString priorityTitle;
  final List<_OverviewMetricKind> metrics;
  final List<_OverviewActionKind> actions;

  static _OverviewRoleProfile forRole(YorksV1Role? role) => switch (role) {
    YorksV1Role.admin => const _OverviewRoleProfile(
      eyebrow: YorksV1OverviewStrings.companyCommandCentre,
      title: YorksV1OverviewStrings.adminTitle,
      description: YorksV1OverviewStrings.adminDescription,
      priorityTitle: YorksV1OverviewStrings.adminAttention,
      metrics: [
        _OverviewMetricKind.projects,
        _OverviewMetricKind.needsAction,
        _OverviewMetricKind.openRequests,
        _OverviewMetricKind.dispatchReady,
        _OverviewMetricKind.inventoryAttention,
      ],
      actions: [
        _OverviewActionKind.users,
        _OverviewActionKind.configuration,
        _OverviewActionKind.inventory,
        _OverviewActionKind.audit,
        _OverviewActionKind.rentals,
      ],
    ),
    YorksV1Role.seniorMechanicalEngineer => const _OverviewRoleProfile(
      eyebrow: YorksV1OverviewStrings.technicalPortfolio,
      title: YorksV1OverviewStrings.seniorMechanicalTitle,
      description: YorksV1OverviewStrings.seniorMechanicalDescription,
      priorityTitle: YorksV1OverviewStrings.managementAttention,
      metrics: [
        _OverviewMetricKind.projects,
        _OverviewMetricKind.approvals,
        _OverviewMetricKind.deliveryExceptions,
        _OverviewMetricKind.inventoryAttention,
        _OverviewMetricKind.openRequests,
      ],
      actions: [
        _OverviewActionKind.projects,
        _OverviewActionKind.materialRequests,
        _OverviewActionKind.inventory,
        _OverviewActionKind.users,
      ],
    ),
    YorksV1Role.projectManager => const _OverviewRoleProfile(
      eyebrow: YorksV1OverviewStrings.managementOverview,
      title: YorksV1OverviewStrings.managerTitle,
      description: YorksV1OverviewStrings.managerDescription,
      priorityTitle: YorksV1OverviewStrings.managementAttention,
      metrics: [
        _OverviewMetricKind.projects,
        _OverviewMetricKind.projectsOnHold,
        _OverviewMetricKind.approvals,
        _OverviewMetricKind.deliveryExceptions,
        _OverviewMetricKind.openRequests,
      ],
      actions: [
        _OverviewActionKind.projects,
        _OverviewActionKind.materialRequests,
        _OverviewActionKind.returns,
      ],
    ),
    YorksV1Role.workshopInCharge => const _OverviewRoleProfile(
      eyebrow: YorksV1OverviewStrings.workshopOverview,
      title: YorksV1OverviewStrings.workshopTitle,
      description: YorksV1OverviewStrings.workshopDescription,
      priorityTitle: YorksV1OverviewStrings.priorityWork,
      metrics: [
        _OverviewMetricKind.projects,
        _OverviewMetricKind.approvals,
        _OverviewMetricKind.dispatchReady,
        _OverviewMetricKind.receiptPending,
        _OverviewMetricKind.deliveryExceptions,
      ],
      actions: [
        _OverviewActionKind.projects,
        _OverviewActionKind.materialRequests,
        _OverviewActionKind.returns,
      ],
    ),
    YorksV1Role.documentController => const _OverviewRoleProfile(
      eyebrow: YorksV1OverviewStrings.recordsOverview,
      title: YorksV1OverviewStrings.documentControllerTitle,
      description: YorksV1OverviewStrings.documentControllerDescription,
      priorityTitle: YorksV1OverviewStrings.recentOperationalRecords,
      metrics: [
        _OverviewMetricKind.projects,
        _OverviewMetricKind.openRequests,
        _OverviewMetricKind.approvals,
        _OverviewMetricKind.closedRequests,
        _OverviewMetricKind.deliveryExceptions,
      ],
      actions: [
        _OverviewActionKind.projects,
        _OverviewActionKind.materialRequests,
        _OverviewActionKind.returns,
      ],
    ),
    YorksV1Role.siteEngineer => const _OverviewRoleProfile(
      eyebrow: YorksV1OverviewStrings.siteOperations,
      title: YorksV1OverviewStrings.siteEngineerTitle,
      description: YorksV1OverviewStrings.siteEngineerDescription,
      priorityTitle: YorksV1OverviewStrings.priorityWork,
      metrics: [
        _OverviewMetricKind.projects,
        _OverviewMetricKind.needsAction,
        _OverviewMetricKind.draftsAndChanges,
        _OverviewMetricKind.receiptPending,
        _OverviewMetricKind.openRequests,
      ],
      actions: [
        _OverviewActionKind.materialRequests,
        _OverviewActionKind.projects,
        _OverviewActionKind.returns,
      ],
    ),
    YorksV1Role.procurement => const _OverviewRoleProfile(
      eyebrow: YorksV1ShellStrings.procurementGreeting,
      title: YorksV1ShellStrings.procurementHero,
      description: YorksV1ShellStrings.procurementHeroDescription,
      priorityTitle: YorksV1ShellStrings.needsProcurementAction,
      metrics: [
        _OverviewMetricKind.newToArrange,
        _OverviewMetricKind.dispatchReady,
        _OverviewMetricKind.inventoryAttention,
        _OverviewMetricKind.receiptPending,
        _OverviewMetricKind.openRequests,
      ],
      actions: [
        _OverviewActionKind.materialRequests,
        _OverviewActionKind.inventory,
        _OverviewActionKind.projects,
        _OverviewActionKind.returns,
      ],
    ),
    YorksV1Role.accountant => const _OverviewRoleProfile(
      eyebrow: YorksV1OverviewStrings.accountantRolloutTitle,
      title: YorksV1OverviewStrings.accountantRolloutTitle,
      description: YorksV1OverviewStrings.accountantRolloutDescription,
      priorityTitle: YorksV1OverviewStrings.accountantRolloutTitle,
      metrics: [],
      actions: [],
    ),
    YorksV1Role.projectEngineer || null => const _OverviewRoleProfile(
      eyebrow: YorksV1OverviewStrings.engineeringWorkspace,
      title: YorksV1OverviewStrings.projectEngineerTitle,
      description: YorksV1OverviewStrings.projectEngineerDescription,
      priorityTitle: YorksV1OverviewStrings.priorityWork,
      metrics: [
        _OverviewMetricKind.projects,
        _OverviewMetricKind.approvals,
        _OverviewMetricKind.openRequests,
        _OverviewMetricKind.receiptPending,
        _OverviewMetricKind.draftsAndChanges,
      ],
      actions: [
        _OverviewActionKind.materialRequests,
        _OverviewActionKind.projects,
        _OverviewActionKind.returns,
      ],
    ),
  };
}

class _AccountantRolloutLockedState extends StatelessWidget {
  const _AccountantRolloutLockedState({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surface,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: NexusSectionCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    key: ValueKey('accountant-rollout-locked-icon'),
                    size: 44,
                    color: AppColors.onSurfaceVariant,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  BilingualText(
                    english:
                        YorksV1OverviewStrings.accountantRolloutTitle.primary,
                    secondary: YorksV1OverviewStrings.accountantRolloutTitle
                        .secondary(language),
                    englishStyle: AppTypography.headlineSmall,
                    crossAxisAlignment: CrossAxisAlignment.center,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    YorksV1OverviewStrings.accountantRolloutDescription.active(
                      language,
                    ),
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyLarge.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OverviewStats {
  const _OverviewStats({
    required this.projects,
    required this.activeProjects,
    required this.projectsOnHold,
    required this.completedProjects,
    required this.openRequests,
    required this.needsAction,
    required this.approvals,
    required this.deliveryExceptions,
    required this.receiptPending,
    required this.draftsAndChanges,
    required this.closedRequests,
    required this.dispatchReady,
    required this.newToArrange,
  });

  final int projects;
  final int activeProjects;
  final int projectsOnHold;
  final int completedProjects;
  final int openRequests;
  final int needsAction;
  final int approvals;
  final int deliveryExceptions;
  final int receiptPending;
  final int draftsAndChanges;
  final int closedRequests;
  final int dispatchReady;
  final int newToArrange;

  factory _OverviewStats.fromRecords({
    required List<YorksV1ProjectPortfolioItem> projects,
    required List<YorksV1MaterialRequest> requests,
    required YorksV1Role? role,
    YorksV1ProjectOverview? projectOverview,
    YorksV1MaterialRequestOverview? overview,
  }) => _OverviewStats(
    projects: projectOverview?.total ?? projects.length,
    activeProjects:
        projectOverview?.active ??
        projects
            .where(
              (item) => item.project.state == YorksV1ProjectLifecycle.active,
            )
            .length,
    projectsOnHold:
        projectOverview?.onHold ??
        projects
            .where(
              (item) => item.project.state == YorksV1ProjectLifecycle.onHold,
            )
            .length,
    completedProjects:
        projectOverview?.completed ??
        projects
            .where(
              (item) => item.project.state == YorksV1ProjectLifecycle.completed,
            )
            .length,
    openRequests:
        overview?.open ?? requests.where(_isOpenOverviewRequest).length,
    needsAction:
        overview?.needsAction ??
        requests
            .where((item) => yorksV1MaterialRequestNeedsAction(item, role))
            .length,
    approvals:
        overview?.approvals ??
        requests
            .where(
              (item) =>
                  item.state ==
                      YorksV1MaterialRequestState.awaitingRequestApproval ||
                  item.state == YorksV1MaterialRequestState.awaitingApproval,
            )
            .length,
    deliveryExceptions:
        overview?.deliveryExceptions ??
        requests
            .where(
              (item) =>
                  item.state == YorksV1MaterialRequestState.changesRequested ||
                  item.state ==
                      YorksV1MaterialRequestState.partiallyDispatched ||
                  item.state == YorksV1MaterialRequestState.partiallyReceived,
            )
            .length,
    receiptPending:
        overview?.receiptPending ??
        requests
            .where(
              (item) =>
                  item.state == YorksV1MaterialRequestState.dispatched ||
                  item.state == YorksV1MaterialRequestState.partiallyReceived,
            )
            .length,
    draftsAndChanges:
        overview?.draftsAndChanges ??
        requests
            .where(
              (item) =>
                  item.state == YorksV1MaterialRequestState.draft ||
                  item.state == YorksV1MaterialRequestState.changesRequested,
            )
            .length,
    closedRequests:
        overview?.closed ??
        requests
            .where((item) => item.state == YorksV1MaterialRequestState.closed)
            .length,
    dispatchReady:
        overview?.dispatchReady ??
        requests
            .where(
              (item) =>
                  item.state == YorksV1MaterialRequestState.approved ||
                  item.state == YorksV1MaterialRequestState.partiallyDispatched,
            )
            .length,
    newToArrange:
        overview?.newToArrange ??
        requests
            .where(
              (item) =>
                  item.state ==
                      YorksV1MaterialRequestState.approvedForArrangement ||
                  item.state == YorksV1MaterialRequestState.arranging,
            )
            .length,
  );
}

bool _isOpenOverviewRequest(YorksV1MaterialRequest item) =>
    item.state != YorksV1MaterialRequestState.draft &&
    item.state != YorksV1MaterialRequestState.received &&
    item.state != YorksV1MaterialRequestState.closed &&
    item.state != YorksV1MaterialRequestState.cancelled;

class _R35RoleAwareOverview extends StatelessWidget {
  const _R35RoleAwareOverview({
    required this.language,
    required this.role,
    required this.displayName,
    required this.projects,
    required this.projectOverview,
    required this.requests,
    required this.requestOverview,
    required this.inventory,
    required this.projectCount,
    required this.openRequests,
    required this.needsAction,
    required this.dispatchReady,
    required this.canCreateProject,
    required this.canCreateRequest,
    required this.canBrowseInventory,
    required this.onCreateProject,
    required this.onCreateRequest,
    required this.onOpenProjects,
    required this.onOpenRequests,
    required this.onRetryProjects,
    required this.onRetryRequests,
    this.compact = false,
  });

  final AppLanguage language;
  final YorksV1Role? role;
  final String? displayName;
  final AsyncValue<List<YorksV1ProjectPortfolioItem>> projects;
  final YorksV1ProjectOverview? projectOverview;
  final AsyncValue<List<YorksV1MaterialRequest>> requests;
  final YorksV1MaterialRequestOverview? requestOverview;
  final AsyncValue<YorksV1InventoryWorkspace?> inventory;
  final int projectCount;
  final int openRequests;
  final int needsAction;
  final int dispatchReady;
  final bool canCreateProject;
  final bool canCreateRequest;
  final bool canBrowseInventory;
  final VoidCallback? onCreateProject;
  final VoidCallback? onCreateRequest;
  final VoidCallback onOpenProjects;
  final VoidCallback onOpenRequests;
  final VoidCallback onRetryProjects;
  final VoidCallback onRetryRequests;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final profile = _OverviewRoleProfile.forRole(role);
    final projectItems =
        projects.valueOrNull ?? const <YorksV1ProjectPortfolioItem>[];
    final requestItems =
        requests.valueOrNull ?? const <YorksV1MaterialRequest>[];
    final stats = _OverviewStats.fromRecords(
      projects: projectItems,
      requests: requestItems,
      role: role,
      projectOverview: projectOverview,
      overview: requestOverview,
    );
    assert(stats.projects == projectCount);
    assert(stats.openRequests == openRequests);
    assert(stats.needsAction == needsAction);
    assert(stats.dispatchReady == dispatchReady);
    final firstName = (displayName ?? '').trim().split(RegExp(r'\s+')).first;
    final safeName = firstName.isEmpty
        ? YorksV1ShellStrings.companyName.active(language)
        : firstName;
    final priorityItems = _overviewPriorities(requestItems, role);
    final horizontal = compact ? 14.0 : 26.0;

    return ColoredBox(
      color: compact ? AppColors.mobileSurface : AppColors.surface,
      child: RefreshIndicator(
        onRefresh: () async {
          onRetryProjects();
          onRetryRequests();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            horizontal,
            compact ? 16 : 24,
            horizontal,
            compact ? 32 : 96,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSpacing.pageMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RoleOverviewHeader(
                    language: language,
                    profile: profile,
                    role: role,
                    name: safeName,
                    compact: compact,
                    canCreateProject: canCreateProject,
                    canCreateRequest: canCreateRequest,
                    onCreateProject: onCreateProject,
                    onCreateRequest: onCreateRequest,
                    onOpenRequests: onOpenRequests,
                  ),
                  SizedBox(height: compact ? 18 : AppSpacing.xl),
                  _OverviewMetricStrip(
                    language: language,
                    metrics: profile.metrics,
                    stats: stats,
                    inventory: inventory,
                    canBrowseInventory: canBrowseInventory,
                    compact: compact,
                    onOpenProjects: onOpenProjects,
                    onOpenRequests: onOpenRequests,
                  ),
                  SizedBox(height: compact ? 20 : AppSpacing.xl),
                  _OverviewPrimaryGrid(
                    language: language,
                    role: role,
                    profile: profile,
                    requests: requests,
                    priorityItems: priorityItems,
                    inventory: inventory,
                    compact: compact,
                    onOpenProjects: onOpenProjects,
                    onOpenRequests: onOpenRequests,
                    onRetryRequests: onRetryRequests,
                  ),
                  SizedBox(height: compact ? 20 : AppSpacing.xl),
                  _OverviewSupportingGrid(
                    language: language,
                    projects: projects,
                    requests: requests,
                    stats: stats,
                    compact: compact,
                    onOpenProjects: onOpenProjects,
                    onOpenRequests: onOpenRequests,
                    onRetryProjects: onRetryProjects,
                    onRetryRequests: onRetryRequests,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleOverviewHeader extends StatelessWidget {
  const _RoleOverviewHeader({
    required this.language,
    required this.profile,
    required this.role,
    required this.name,
    required this.compact,
    required this.canCreateProject,
    required this.canCreateRequest,
    required this.onCreateProject,
    required this.onCreateRequest,
    required this.onOpenRequests,
  });

  final AppLanguage language;
  final _OverviewRoleProfile profile;
  final YorksV1Role? role;
  final String name;
  final bool compact;
  final bool canCreateProject;
  final bool canCreateRequest;
  final VoidCallback? onCreateProject;
  final VoidCallback? onCreateRequest;
  final VoidCallback onOpenRequests;

  @override
  Widget build(BuildContext context) {
    final roleLabel = YorksV1ProjectStrings.roleLabel(
      role?.claimValue,
    ).active(language);
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          profile.eyebrow.active(language).toUpperCase(),
          style: AppTypography.eyebrow.copyWith(
            color: AppColors.blue,
            letterSpacing: 1.35,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          profile.title.active(language),
          key: const ValueKey('role-overview-title'),
          style: AppTypography.headlineLarge.copyWith(
            color: AppColors.ink,
            fontSize: compact ? 27 : 34,
            height: 1.08,
            fontWeight: FontWeight.w800,
            letterSpacing: compact ? -.65 : -1.0,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          profile.description.active(language),
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.muted,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _OverviewScopeChip(
              icon: Icons.verified_user_outlined,
              label: roleLabel,
            ),
            _OverviewScopeChip(icon: Icons.person_outline_rounded, label: name),
          ],
        ),
      ],
    );
    final isAdmin = role == YorksV1Role.admin;
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: compact ? WrapAlignment.start : WrapAlignment.end,
      children: [
        if (isAdmin && canCreateProject)
          _R35PrimaryAction(
            label: YorksV1ProjectStrings.newProject.active(language),
            icon: Icons.create_new_folder_outlined,
            onPressed: onCreateProject,
          )
        else if (canCreateRequest)
          _R35PrimaryAction(
            label: YorksV1MaterialRequestStrings.newRequest.active(language),
            icon: Icons.add_rounded,
            onPressed: onCreateRequest,
          )
        else
          _R35PrimaryAction(
            label: YorksV1ShellStrings.viewAllRequests.active(language),
            icon: Icons.assignment_outlined,
            onPressed: onOpenRequests,
          ),
        if (isAdmin)
          _R35SecondaryAction(
            label: YorksV1ShellStrings.viewAllRequests.active(language),
            icon: Icons.assignment_outlined,
            onPressed: onOpenRequests,
          )
        else if (canCreateProject)
          _R35SecondaryAction(
            label: YorksV1ProjectStrings.newProject.active(language),
            icon: Icons.create_new_folder_outlined,
            onPressed: onCreateProject,
          ),
      ],
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [copy, const SizedBox(height: 16), actions],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(flex: 7, child: copy),
        const SizedBox(width: AppSpacing.xl),
        Flexible(flex: 4, child: actions),
      ],
    );
  }
}

class _OverviewScopeChip extends StatelessWidget {
  const _OverviewScopeChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 32),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.blueContainer,
      border: Border.all(color: AppColors.blueContainerStrong),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.blue),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.navy,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _OverviewMetricStrip extends StatelessWidget {
  const _OverviewMetricStrip({
    required this.language,
    required this.metrics,
    required this.stats,
    required this.inventory,
    required this.canBrowseInventory,
    required this.compact,
    required this.onOpenProjects,
    required this.onOpenRequests,
  });

  final AppLanguage language;
  final List<_OverviewMetricKind> metrics;
  final _OverviewStats stats;
  final AsyncValue<YorksV1InventoryWorkspace?> inventory;
  final bool canBrowseInventory;
  final bool compact;
  final VoidCallback onOpenProjects;
  final VoidCallback onOpenRequests;

  @override
  Widget build(BuildContext context) {
    final cards = [
      for (final metric in metrics)
        _OverviewMetricCard(
          data: _metricData(
            metric,
            language,
            stats,
            inventory,
            canBrowseInventory,
            onOpenProjects,
            onOpenRequests,
            context,
          ),
          compact: compact,
        ),
    ];
    if (compact) {
      return SizedBox(
        height: 126,
        child: ListView.separated(
          key: const ValueKey('role-overview-metrics'),
          scrollDirection: Axis.horizontal,
          itemCount: cards.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, index) => SizedBox(width: 170, child: cards[index]),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1050 ? 5 : 2;
        const spacing = 12.0;
        final cardWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;
        return Wrap(
          key: const ValueKey('role-overview-metrics'),
          spacing: spacing,
          runSpacing: spacing,
          alignment: WrapAlignment.center,
          children: [
            for (final card in cards)
              SizedBox(width: cardWidth, height: 132, child: card),
          ],
        );
      },
    );
  }
}

class _OverviewMetricData {
  const _OverviewMetricData({
    required this.label,
    required this.value,
    required this.helper,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.onTap,
  });

  final String label;
  final String value;
  final String helper;
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final VoidCallback onTap;
}

_OverviewMetricData _metricData(
  _OverviewMetricKind kind,
  AppLanguage language,
  _OverviewStats stats,
  AsyncValue<YorksV1InventoryWorkspace?> inventory,
  bool canBrowseInventory,
  VoidCallback onOpenProjects,
  VoidCallback onOpenRequests,
  BuildContext context,
) {
  final inventoryValue = inventory.when(
    data: (value) => value == null ? '—' : '${value.summary.attentionCount}',
    loading: () => '…',
    error: (_, _) => '—',
  );
  final routeInventory = canBrowseInventory
      ? () => context.go(RoutePaths.yorksV1Inventory)
      : onOpenRequests;
  return switch (kind) {
    _OverviewMetricKind.projects => _OverviewMetricData(
      label: YorksV1OverviewStrings.assignedProjects.active(language),
      value: '${stats.projects}',
      helper:
          '${stats.activeProjects} ${YorksV1ProjectStrings.activeState.active(language).toLowerCase()}',
      icon: Icons.folder_outlined,
      iconColor: AppColors.blue,
      iconBackground: AppColors.blueContainer,
      onTap: onOpenProjects,
    ),
    _OverviewMetricKind.openRequests => _OverviewMetricData(
      label: YorksV1OverviewStrings.openMaterialRequests.active(language),
      value: '${stats.openRequests}',
      helper: YorksV1ShellStrings.viewAllRequests.active(language),
      icon: Icons.assignment_outlined,
      iconColor: AppColors.blue,
      iconBackground: AppColors.blueContainer,
      onTap: onOpenRequests,
    ),
    _OverviewMetricKind.needsAction => _OverviewMetricData(
      label: YorksV1ShellStrings.needsYourAction.active(language),
      value: '${stats.needsAction}',
      helper: YorksV1OverviewStrings.priorityDescription.active(language),
      icon: Icons.priority_high_rounded,
      iconColor: AppColors.error,
      iconBackground: AppColors.errorContainer,
      onTap: onOpenRequests,
    ),
    _OverviewMetricKind.approvals => _OverviewMetricData(
      label: YorksV1OverviewStrings.approvalsWaiting.active(language),
      value: '${stats.approvals}',
      helper: YorksV1ShellStrings.engineerReviewDescription.active(language),
      icon: Icons.fact_check_outlined,
      iconColor: AppColors.warning,
      iconBackground: AppColors.warningContainer,
      onTap: onOpenRequests,
    ),
    _OverviewMetricKind.deliveryExceptions => _OverviewMetricData(
      label: YorksV1OverviewStrings.deliveryExceptions.active(language),
      value: '${stats.deliveryExceptions}',
      helper: YorksV1OverviewStrings.priorityDescription.active(language),
      icon: Icons.report_problem_outlined,
      iconColor: AppColors.warning,
      iconBackground: AppColors.warningContainer,
      onTap: onOpenRequests,
    ),
    _OverviewMetricKind.receiptPending => _OverviewMetricData(
      label: YorksV1OverviewStrings.receiptPending.active(language),
      value: '${stats.receiptPending}',
      helper: YorksV1ShellStrings.awaitingReceiptDescription.active(language),
      icon: Icons.inventory_2_outlined,
      iconColor: AppColors.blue,
      iconBackground: AppColors.blueContainer,
      onTap: onOpenRequests,
    ),
    _OverviewMetricKind.draftsAndChanges => _OverviewMetricData(
      label: YorksV1OverviewStrings.draftsAndChanges.active(language),
      value: '${stats.draftsAndChanges}',
      helper: YorksV1ShellStrings.openRequests.active(language),
      icon: Icons.edit_note_outlined,
      iconColor: AppColors.warning,
      iconBackground: AppColors.warningContainer,
      onTap: onOpenRequests,
    ),
    _OverviewMetricKind.closedRequests => _OverviewMetricData(
      label: YorksV1OverviewStrings.closedRequests.active(language),
      value: '${stats.closedRequests}',
      helper: YorksV1ShellStrings.viewAllRequests.active(language),
      icon: Icons.inventory_outlined,
      iconColor: AppColors.success,
      iconBackground: AppColors.successContainer,
      onTap: onOpenRequests,
    ),
    _OverviewMetricKind.inventoryAttention => _OverviewMetricData(
      label: YorksV1OverviewStrings.inventoryAttention.active(language),
      value: inventoryValue,
      helper: YorksV1ShellStrings.browseInventory.active(language),
      icon: Icons.warehouse_outlined,
      iconColor: AppColors.warning,
      iconBackground: AppColors.warningContainer,
      onTap: routeInventory,
    ),
    _OverviewMetricKind.projectsOnHold => _OverviewMetricData(
      label: YorksV1OverviewStrings.projectsOnHold.active(language),
      value: '${stats.projectsOnHold}',
      helper: YorksV1OverviewStrings.portfolioHealth.active(language),
      icon: Icons.pause_circle_outline_rounded,
      iconColor: AppColors.warning,
      iconBackground: AppColors.warningContainer,
      onTap: onOpenProjects,
    ),
    _OverviewMetricKind.dispatchReady => _OverviewMetricData(
      label: YorksV1OverviewStrings.readyForDispatch.active(language),
      value: '${stats.dispatchReady}',
      helper: YorksV1ShellStrings.approvedDescription.active(language),
      icon: Icons.local_shipping_outlined,
      iconColor: AppColors.success,
      iconBackground: AppColors.successContainer,
      onTap: onOpenRequests,
    ),
    _OverviewMetricKind.newToArrange => _OverviewMetricData(
      label: YorksV1ShellStrings.newToArrange.active(language),
      value: '${stats.newToArrange}',
      helper: YorksV1ShellStrings.newRequestsDescription.active(language),
      icon: Icons.shopping_cart_checkout_outlined,
      iconColor: AppColors.warning,
      iconBackground: AppColors.warningContainer,
      onTap: onOpenRequests,
    ),
  };
}

class _OverviewMetricCard extends StatelessWidget {
  const _OverviewMetricCard({required this.data, required this.compact});

  final _OverviewMetricData data;
  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${data.label}: ${data.value}. ${data.helper}',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: EdgeInsets.all(compact ? 13 : 15),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      data.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: data.iconBackground,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(data.icon, size: 19, color: data.iconColor),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                data.value,
                style: AppTypography.headlineMedium.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                data.helper,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _OverviewPrimaryGrid extends StatelessWidget {
  const _OverviewPrimaryGrid({
    required this.language,
    required this.role,
    required this.profile,
    required this.requests,
    required this.priorityItems,
    required this.inventory,
    required this.compact,
    required this.onOpenProjects,
    required this.onOpenRequests,
    required this.onRetryRequests,
  });

  final AppLanguage language;
  final YorksV1Role? role;
  final _OverviewRoleProfile profile;
  final AsyncValue<List<YorksV1MaterialRequest>> requests;
  final List<YorksV1MaterialRequest> priorityItems;
  final AsyncValue<YorksV1InventoryWorkspace?> inventory;
  final bool compact;
  final VoidCallback onOpenProjects;
  final VoidCallback onOpenRequests;
  final VoidCallback onRetryRequests;

  @override
  Widget build(BuildContext context) {
    final priority = _OverviewPriorityPanel(
      language: language,
      title: profile.priorityTitle.active(language),
      requests: requests,
      items: priorityItems,
      onOpenRequests: onOpenRequests,
      onRetry: onRetryRequests,
    );
    final workspace = _OverviewWorkspacePanel(
      language: language,
      admin: role == YorksV1Role.admin,
      actions: profile.actions,
      inventory: inventory,
      onOpenProjects: onOpenProjects,
      onOpenRequests: onOpenRequests,
    );
    if (compact) {
      return Column(
        children: [priority, const SizedBox(height: 14), workspace],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            children: [priority, const SizedBox(height: 14), workspace],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 13, child: priority),
            const SizedBox(width: 14),
            Expanded(flex: 8, child: workspace),
          ],
        );
      },
    );
  }
}

List<YorksV1MaterialRequest> _overviewPriorities(
  List<YorksV1MaterialRequest> records,
  YorksV1Role? role,
) {
  bool eligible(YorksV1MaterialRequest item) {
    if (item.state == YorksV1MaterialRequestState.cancelled ||
        item.state == YorksV1MaterialRequestState.closed) {
      return false;
    }
    return switch (role) {
      YorksV1Role.admin =>
        item.state == YorksV1MaterialRequestState.changesRequested ||
            item.state == YorksV1MaterialRequestState.partiallyDispatched ||
            item.state == YorksV1MaterialRequestState.partiallyReceived,
      YorksV1Role.documentController => !item.state.isDraft,
      YorksV1Role.workshopInCharge =>
        yorksV1MaterialRequestNeedsAction(item, role) ||
            item.state == YorksV1MaterialRequestState.approved ||
            item.state == YorksV1MaterialRequestState.partiallyDispatched ||
            item.state == YorksV1MaterialRequestState.dispatched ||
            item.state == YorksV1MaterialRequestState.partiallyReceived,
      YorksV1Role.siteEngineer =>
        yorksV1MaterialRequestNeedsAction(item, role) ||
            item.state == YorksV1MaterialRequestState.draft ||
            item.state == YorksV1MaterialRequestState.changesRequested ||
            item.state == YorksV1MaterialRequestState.dispatched ||
            item.state == YorksV1MaterialRequestState.partiallyReceived,
      _ => yorksV1MaterialRequestNeedsAction(item, role),
    };
  }

  final items = records.where(eligible).toList()
    ..sort((a, b) {
      final state = _overviewPriorityWeight(
        b.state,
      ).compareTo(_overviewPriorityWeight(a.state));
      return state != 0 ? state : b.updatedAt.compareTo(a.updatedAt);
    });
  return items.take(6).toList(growable: false);
}

int _overviewPriorityWeight(YorksV1MaterialRequestState state) =>
    switch (state) {
      YorksV1MaterialRequestState.changesRequested => 9,
      YorksV1MaterialRequestState.partiallyReceived => 8,
      YorksV1MaterialRequestState.partiallyDispatched => 7,
      YorksV1MaterialRequestState.awaitingRequestApproval => 6,
      YorksV1MaterialRequestState.approvedForArrangement => 5,
      YorksV1MaterialRequestState.arranging => 4,
      YorksV1MaterialRequestState.approved => 3,
      YorksV1MaterialRequestState.dispatched => 2,
      _ => 1,
    };

class _OverviewPriorityPanel extends StatelessWidget {
  const _OverviewPriorityPanel({
    required this.language,
    required this.title,
    required this.requests,
    required this.items,
    required this.onOpenRequests,
    required this.onRetry,
  });

  final AppLanguage language;
  final String title;
  final AsyncValue<List<YorksV1MaterialRequest>> requests;
  final List<YorksV1MaterialRequest> items;
  final VoidCallback onOpenRequests;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _R35Card(
    minHeight: 320,
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 17, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      YorksV1OverviewStrings.priorityWork
                          .active(language)
                          .toUpperCase(),
                      style: AppTypography.eyebrow.copyWith(
                        color: AppColors.blue,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: AppTypography.titleLarge.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onOpenRequests,
                child: Text(YorksV1ShellStrings.viewAll.active(language)),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        requests.when(
          loading: () => const _OverviewLoadingRows(),
          error: (_, _) => _OverviewRetry(onRetry: onRetry),
          data: (_) {
            if (items.isEmpty) {
              return _OverviewAllClear(language: language);
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (var index = 0; index < items.length; index++) ...[
                    _OverviewPriorityRow(
                      item: items[index],
                      language: language,
                    ),
                    if (index != items.length - 1) const Divider(height: 1),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    ),
  );
}

class _OverviewLoadingRows extends StatelessWidget {
  const _OverviewLoadingRows();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        for (var index = 0; index < 3; index++) ...[
          Container(
            height: 58,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          if (index != 2) const SizedBox(height: 10),
        ],
      ],
    ),
  );
}

class _OverviewAllClear extends StatelessWidget {
  const _OverviewAllClear({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: AppColors.successContainer,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: AppColors.success),
          ),
          const SizedBox(height: 12),
          Text(
            YorksV1OverviewStrings.allClear.active(language),
            textAlign: TextAlign.center,
            style: AppTypography.titleMedium.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            YorksV1OverviewStrings.allClearDescription.active(language),
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.muted,
              height: 1.45,
            ),
          ),
        ],
      ),
    ),
  );
}

class _OverviewPriorityRow extends StatelessWidget {
  const _OverviewPriorityRow({required this.item, required this.language});

  final YorksV1MaterialRequest item;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 520;
      final icon = _OverviewRecordIcon(
        icon: item.state == YorksV1MaterialRequestState.changesRequested
            ? Icons.priority_high_rounded
            : Icons.assignment_outlined,
      );
      final details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${item.requestNumber ?? YorksV1MaterialRequestStrings.draft.active(language)}${item.title?.trim().isNotEmpty == true ? ' · ${item.title!.trim()}' : ''}',
            maxLines: compact ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelLarge.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${item.projectReference} · ${item.scopeName} · ${DateFormat.MMMd().add_jm().format(item.updatedAt.toLocal())}',
            maxLines: compact ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
        ],
      );
      final stateLabel = yorksV1MaterialRequestStateCopy(
        item.state,
      ).active(language);
      final stateTone = _requestTone(item.state);
      final state = StatusChip(
        label: stateLabel,
        tone: stateTone,
        showDot: true,
      );
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push(_materialRequestOpenPath(item)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              crossAxisAlignment: compact
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                icon,
                const SizedBox(width: 12),
                Expanded(
                  child: compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            details,
                            const SizedBox(height: 8),
                            _OverviewCompactStatus(
                              label: stateLabel,
                              tone: stateTone,
                            ),
                          ],
                        )
                      : details,
                ),
                if (!compact) ...[const SizedBox(width: 10), state],
                const SizedBox(width: 4),
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _OverviewCompactStatus extends StatelessWidget {
  const _OverviewCompactStatus({required this.label, required this.tone});

  final String label;
  final NexusStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = NexusStatusPalette.forTone(tone);
    return Semantics(
      label: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 28),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: palette.foreground,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelSmall.copyWith(
                  color: palette.foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewWorkspacePanel extends StatelessWidget {
  const _OverviewWorkspacePanel({
    required this.language,
    required this.admin,
    required this.actions,
    required this.inventory,
    required this.onOpenProjects,
    required this.onOpenRequests,
  });

  final AppLanguage language;
  final bool admin;
  final List<_OverviewActionKind> actions;
  final AsyncValue<YorksV1InventoryWorkspace?> inventory;
  final VoidCallback onOpenProjects;
  final VoidCallback onOpenRequests;

  @override
  Widget build(BuildContext context) => _R35Card(
    minHeight: 320,
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 17, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (admin
                        ? YorksV1ShellStrings.administration
                        : YorksV1OverviewStrings.quickWorkspace)
                    .active(language)
                    .toUpperCase(),
                style: AppTypography.eyebrow.copyWith(
                  color: AppColors.blue,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                (admin
                        ? YorksV1OverviewStrings.controlCentre
                        : YorksV1OverviewStrings.quickWorkspace)
                    .active(language),
                style: AppTypography.titleLarge.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              for (final action in actions) ...[
                _OverviewWorkspaceAction(
                  data: _actionData(
                    action,
                    language,
                    context,
                    inventory,
                    onOpenProjects,
                    onOpenRequests,
                  ),
                ),
                if (action != actions.last) const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _OverviewActionData {
  const _OverviewActionData({
    required this.label,
    required this.detail,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String detail;
  final IconData icon;
  final VoidCallback onTap;
}

_OverviewActionData _actionData(
  _OverviewActionKind kind,
  AppLanguage language,
  BuildContext context,
  AsyncValue<YorksV1InventoryWorkspace?> inventory,
  VoidCallback onOpenProjects,
  VoidCallback onOpenRequests,
) => switch (kind) {
  _OverviewActionKind.projects => _OverviewActionData(
    label: YorksV1ProjectStrings.projects.active(language),
    detail: YorksV1OverviewStrings.assignedPortfolio.active(language),
    icon: Icons.folder_outlined,
    onTap: onOpenProjects,
  ),
  _OverviewActionKind.materialRequests => _OverviewActionData(
    label: YorksV1ShellStrings.materialRequests.active(language),
    detail: YorksV1ShellStrings.viewAllRequests.active(language),
    icon: Icons.assignment_outlined,
    onTap: onOpenRequests,
  ),
  _OverviewActionKind.inventory => _OverviewActionData(
    label: YorksV1OverviewStrings.inventoryControl.active(language),
    detail: inventory.when(
      data: (value) => value == null
          ? YorksV1ShellStrings.browseInventory.active(language)
          : '${value.summary.attentionCount} ${YorksV1OverviewStrings.inventoryAttention.active(language).toLowerCase()}',
      loading: () => YorksV1ShellStrings.preparingWorkspace.active(language),
      error: (_, _) => YorksV1ShellStrings.workspaceFailed.active(language),
    ),
    icon: Icons.inventory_2_outlined,
    onTap: () => context.go(RoutePaths.yorksV1Inventory),
  ),
  _OverviewActionKind.returns => _OverviewActionData(
    label: YorksV1ShellStrings.materialReturns.active(language),
    detail: YorksV1OverviewStrings.openWorkspace.active(language),
    icon: Icons.assignment_return_outlined,
    onTap: () => context.go(RoutePaths.yorksV1Returns),
  ),
  _OverviewActionKind.users => _OverviewActionData(
    label: YorksV1OverviewStrings.userAndAccess.active(language),
    detail: YorksV1OverviewStrings.controlHealthy.active(language),
    icon: Icons.manage_accounts_outlined,
    onTap: () => context.go(RoutePaths.users),
  ),
  _OverviewActionKind.configuration => _OverviewActionData(
    label: YorksV1OverviewStrings.systemConfiguration.active(language),
    detail: YorksV1OverviewStrings.controlHealthy.active(language),
    icon: Icons.tune_rounded,
    onTap: () => context.go(RoutePaths.yorksV1Configuration),
  ),
  _OverviewActionKind.audit => _OverviewActionData(
    label: YorksV1OverviewStrings.auditIntegrity.active(language),
    detail: YorksV1OverviewStrings.controlHealthy.active(language),
    icon: Icons.history_rounded,
    onTap: () => context.go(RoutePaths.activityLog),
  ),
  _OverviewActionKind.rentals => _OverviewActionData(
    label: YorksV1OverviewStrings.rentalOversight.active(language),
    detail: YorksV1OverviewStrings.openWorkspace.active(language),
    icon: Icons.apartment_outlined,
    onTap: () => context.go(RoutePaths.rentals),
  ),
};

class _OverviewWorkspaceAction extends StatelessWidget {
  const _OverviewWorkspaceAction({required this.data});

  final _OverviewActionData data;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${data.label}. ${data.detail}',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.blueContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(data.icon, color: AppColors.blue, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.label,
                      style: AppTypography.labelLarge.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    ),
  );
}

class _OverviewSupportingGrid extends StatelessWidget {
  const _OverviewSupportingGrid({
    required this.language,
    required this.projects,
    required this.requests,
    required this.stats,
    required this.compact,
    required this.onOpenProjects,
    required this.onOpenRequests,
    required this.onRetryProjects,
    required this.onRetryRequests,
  });

  final AppLanguage language;
  final AsyncValue<List<YorksV1ProjectPortfolioItem>> projects;
  final AsyncValue<List<YorksV1MaterialRequest>> requests;
  final _OverviewStats stats;
  final bool compact;
  final VoidCallback onOpenProjects;
  final VoidCallback onOpenRequests;
  final VoidCallback onRetryProjects;
  final VoidCallback onRetryRequests;

  @override
  Widget build(BuildContext context) {
    final portfolio = _OverviewPortfolioPanel(
      language: language,
      projects: projects,
      stats: stats,
      onOpenProjects: onOpenProjects,
      onRetry: onRetryProjects,
    );
    final recent = _OverviewRecentPanel(
      language: language,
      requests: requests,
      onOpenRequests: onOpenRequests,
      onRetry: onRetryRequests,
    );
    if (compact) {
      return Column(children: [portfolio, const SizedBox(height: 14), recent]);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            children: [portfolio, const SizedBox(height: 14), recent],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 12, child: portfolio),
            const SizedBox(width: 14),
            Expanded(flex: 9, child: recent),
          ],
        );
      },
    );
  }
}

class _OverviewPortfolioPanel extends StatelessWidget {
  const _OverviewPortfolioPanel({
    required this.language,
    required this.projects,
    required this.stats,
    required this.onOpenProjects,
    required this.onRetry,
  });

  final AppLanguage language;
  final AsyncValue<List<YorksV1ProjectPortfolioItem>> projects;
  final _OverviewStats stats;
  final VoidCallback onOpenProjects;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _R35Card(
    minHeight: 280,
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OverviewPanelHeader(
          eyebrow: YorksV1OverviewStrings.assignedPortfolio.active(language),
          title: YorksV1OverviewStrings.portfolioHealth.active(language),
          action: YorksV1ShellStrings.viewAll.active(language),
          onAction: onOpenProjects,
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: _OverviewHealthBar(
                  label: YorksV1ProjectStrings.activeState.active(language),
                  value: stats.activeProjects,
                  total: stats.projects,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _OverviewHealthBar(
                  label: YorksV1ProjectStrings.onHoldState.active(language),
                  value: stats.projectsOnHold,
                  total: stats.projects,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _OverviewHealthBar(
                  label: YorksV1ProjectStrings.completedState.active(language),
                  value: stats.completedProjects,
                  total: stats.projects,
                  color: AppColors.blue,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        projects.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => _OverviewRetry(onRetry: onRetry),
          data: (items) {
            if (items.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    YorksV1ProjectStrings.noProjects.active(language),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ),
              );
            }
            final sorted = [...items]
              ..sort(
                (a, b) => b.project.updatedAt.compareTo(a.project.updatedAt),
              );
            return Column(
              children: [
                for (final item in sorted.take(3))
                  _OverviewProjectRow(item: item),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _OverviewHealthBar extends StatelessWidget {
  const _OverviewHealthBar({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  final String label;
  final int value;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '$value',
            style: AppTypography.labelMedium.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      const SizedBox(height: 7),
      ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          minHeight: 5,
          value: total == 0 ? 0 : value / total,
          backgroundColor: AppColors.surfaceContainerHigh,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
    ],
  );
}

class _OverviewRecentPanel extends StatelessWidget {
  const _OverviewRecentPanel({
    required this.language,
    required this.requests,
    required this.onOpenRequests,
    required this.onRetry,
  });

  final AppLanguage language;
  final AsyncValue<List<YorksV1MaterialRequest>> requests;
  final VoidCallback onOpenRequests;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _R35Card(
    minHeight: 280,
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OverviewPanelHeader(
          eyebrow: YorksV1OverviewStrings.recentOperationalRecords.active(
            language,
          ),
          title: YorksV1ShellStrings.materialRequests.active(language),
          action: YorksV1ShellStrings.viewAll.active(language),
          onAction: onOpenRequests,
        ),
        const Divider(height: 1),
        requests.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => _OverviewRetry(onRetry: onRetry),
          data: (items) {
            if (items.isEmpty) return _OverviewAllClear(language: language);
            final sorted = [...items]
              ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
            return Column(
              children: [
                for (final item in sorted.take(4))
                  _OverviewRequestRow(item: item, language: language),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _OverviewPanelHeader extends StatelessWidget {
  const _OverviewPanelHeader({
    required this.eyebrow,
    required this.title,
    required this.action,
    required this.onAction,
  });

  final String eyebrow;
  final String title;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 15, 10, 11),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.eyebrow.copyWith(
                  color: AppColors.blue,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                title,
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        TextButton(onPressed: onAction, child: Text(action)),
      ],
    ),
  );
}

class _R35ProcurementOverview extends StatelessWidget {
  const _R35ProcurementOverview({
    required this.requests,
    required this.requestOverview,
    required this.inventory,
    required this.onOpenRequests,
    required this.onOpenProjects,
  });

  final AsyncValue<List<YorksV1MaterialRequest>> requests;
  final YorksV1MaterialRequestOverview? requestOverview;
  final AsyncValue<YorksV1InventoryWorkspace?> inventory;
  final VoidCallback onOpenRequests;
  final VoidCallback onOpenProjects;

  @override
  Widget build(BuildContext context) {
    final records = requests.valueOrNull ?? const <YorksV1MaterialRequest>[];
    final toArrange = records
        .where(
          (item) =>
              item.state ==
                  YorksV1MaterialRequestState.approvedForArrangement ||
              item.state == YorksV1MaterialRequestState.arranging,
        )
        .toList();
    final needsAction =
        requestOverview?.needsAction ??
        records
            .where(
              (item) => yorksV1MaterialRequestNeedsAction(
                item,
                YorksV1Role.procurement,
              ),
            )
            .length;
    final awaitingApproval =
        requestOverview?.approvals ??
        records
            .where(
              (item) =>
                  item.state == YorksV1MaterialRequestState.awaitingApproval,
            )
            .length;
    final approved =
        requestOverview?.dispatchReady ??
        records
            .where(
              (item) =>
                  item.state == YorksV1MaterialRequestState.approved ||
                  item.state == YorksV1MaterialRequestState.partiallyDispatched,
            )
            .length;
    final awaitingReceipt =
        requestOverview?.receiptPending ??
        records
            .where(
              (item) =>
                  item.state == YorksV1MaterialRequestState.dispatched ||
                  item.state == YorksV1MaterialRequestState.partiallyReceived,
            )
            .length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop =
            MediaQuery.sizeOf(context).width >=
            AppSpacing.yorksV1ShellDesktopBreakpoint;
        final horizontal = desktop
            ? AppSpacing.xxxl + AppSpacing.xs
            : AppSpacing.lg;
        return ColoredBox(
          color: AppColors.surface,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontal,
              AppSpacing.xxxl,
              horizontal,
              72,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSpacing.pageMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, inner) {
                      final stacked = inner.maxWidth < 820;
                      final hero = _R35Card(
                        minHeight: stacked ? null : 286,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              YorksV1ShellStrings.procurementGreeting.primary
                                  .toUpperCase(),
                              style: AppTypography.eyebrow.copyWith(
                                color: AppColors.blueContainerStrong,
                                letterSpacing: 1.45,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              YorksV1ShellStrings.procurementHero.primary,
                              style: AppTypography.headlineLarge.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.05,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              YorksV1ShellStrings
                                  .procurementHeroDescription
                                  .primary,
                              style: AppTypography.bodyLarge.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxxl),
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.sm,
                              children: [
                                _R35PrimaryAction(
                                  label: YorksV1ShellStrings
                                      .materialRequests
                                      .primary,
                                  icon: Icons.assignment_outlined,
                                  onPressed: onOpenRequests,
                                ),
                                _R35SecondaryAction(
                                  label: YorksV1ShellStrings
                                      .browseInventory
                                      .primary,
                                  icon: Icons.inventory_2_outlined,
                                  onPressed: () =>
                                      context.go(RoutePaths.yorksV1Inventory),
                                ),
                                _R35SecondaryAction(
                                  label:
                                      YorksV1ShellStrings.viewProjects.primary,
                                  icon: Icons.visibility_outlined,
                                  onPressed: onOpenProjects,
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                      final snapshot = _R35Card(
                        minHeight: stacked ? null : 286,
                        child: Column(
                          children: [
                            _R35SnapshotTile(
                              label: YorksV1ShellStrings.newToArrange.primary,
                              value: '${toArrange.length}',
                            ),
                            const SizedBox(height: AppSpacing.md),
                            _R35SnapshotTile(
                              label:
                                  YorksV1ShellStrings.readyToDispatch.primary,
                              value: '$approved',
                            ),
                            const SizedBox(height: AppSpacing.md),
                            _R35SnapshotTile(
                              label: YorksV1ShellStrings.lowOutOfStock.primary,
                              value: inventory.when(
                                data: (workspace) => workspace == null
                                    ? '—'
                                    : '${workspace.summary.attentionCount}',
                                loading: () => '…',
                                error: (_, _) => '—',
                              ),
                            ),
                          ],
                        ),
                      );
                      return stacked
                          ? Column(
                              children: [
                                hero,
                                const SizedBox(height: AppSpacing.md),
                                snapshot,
                              ],
                            )
                          : IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(flex: 3, child: hero),
                                  const SizedBox(width: AppSpacing.lg),
                                  Expanded(flex: 2, child: snapshot),
                                ],
                              ),
                            );
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _ProcurementWorkflowStrip(),
                  const SizedBox(height: AppSpacing.lg),
                  _ProcurementStatusGrid(
                    newRequests: toArrange.length,
                    awaitingApproval: awaitingApproval,
                    approved: approved,
                    awaitingReceipt: awaitingReceipt,
                  ),
                  const SizedBox(height: AppSpacing.xxxl),
                  Row(
                    children: [
                      Expanded(
                        child: _R35SectionHeading(
                          title: YorksV1ShellStrings
                              .needsProcurementAction
                              .primary,
                          description: YorksV1ShellStrings
                              .procurementActionDescription
                              .primary,
                          attentionCount: needsAction,
                        ),
                      ),
                      SizedBox(
                        height: AppSpacing.minTapTarget,
                        child: OutlinedButton(
                          onPressed: onOpenRequests,
                          child: Text(
                            YorksV1ShellStrings.viewAllRequests.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ProcurementRequestQueue(
                    requests: requests,
                    queued: toArrange,
                    onOpenRequests: onOpenRequests,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProcurementWorkflowStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final steps = [
          (
            YorksV1ShellStrings.request.primary,
            YorksV1ShellStrings.requestStepDescription.primary,
          ),
          (
            YorksV1ShellStrings.approve.primary,
            YorksV1ShellStrings.approveStepDescription.primary,
          ),
          (
            YorksV1ShellStrings.arrange.primary,
            YorksV1ShellStrings.arrangeStepDescription.primary,
          ),
          (
            YorksV1ShellStrings.dispatch.primary,
            YorksV1ShellStrings.dispatchStepDescription.primary,
          ),
          (
            YorksV1ShellStrings.receipt.primary,
            YorksV1ShellStrings.receiptStepDescription.primary,
          ),
        ];
        final compact = constraints.maxWidth < 760;
        return compact
            ? Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  for (var index = 0; index < steps.length; index++)
                    _ProcurementWorkflowStep(
                      number: index + 1,
                      title: steps[index].$1,
                      detail: steps[index].$2,
                      compact: true,
                    ),
                ],
              )
            : Row(
                children: [
                  for (var index = 0; index < steps.length; index++) ...[
                    Expanded(
                      child: _ProcurementWorkflowStep(
                        number: index + 1,
                        title: steps[index].$1,
                        detail: steps[index].$2,
                      ),
                    ),
                    if (index != steps.length - 1)
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: AppColors.lineStrong,
                      ),
                  ],
                ],
              );
      },
    ),
  );
}

class _ProcurementWorkflowStep extends StatelessWidget {
  const _ProcurementWorkflowStep({
    required this.number,
    required this.title,
    required this.detail,
    this.compact = false,
  });

  final int number;
  final String title;
  final String detail;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    constraints: compact ? const BoxConstraints(minWidth: 150) : null,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLow,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.blueContainer,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Text(
            '$number',
            style: AppTypography.labelLarge.copyWith(
              color: AppColors.blue,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          title,
          style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          detail,
          style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
        ),
      ],
    ),
  );
}

class _ProcurementStatusGrid extends StatelessWidget {
  const _ProcurementStatusGrid({
    required this.newRequests,
    required this.awaitingApproval,
    required this.approved,
    required this.awaitingReceipt,
  });

  final int newRequests;
  final int awaitingApproval;
  final int approved;
  final int awaitingReceipt;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final count = constraints.maxWidth >= 1000
          ? 4
          : constraints.maxWidth >= 640
          ? 2
          : 1;
      final metrics = [
        (
          YorksV1ShellStrings.newRequests.primary,
          '$newRequests',
          YorksV1ShellStrings.newRequestsDescription.primary,
        ),
        (
          YorksV1ShellStrings.engineerReview.primary,
          '$awaitingApproval',
          YorksV1ShellStrings.engineerReviewDescription.primary,
        ),
        (
          YorksV1ShellStrings.approved.primary,
          '$approved',
          YorksV1ShellStrings.approvedDescription.primary,
        ),
        (
          YorksV1ShellStrings.awaitingReceipt.primary,
          '$awaitingReceipt',
          YorksV1ShellStrings.awaitingReceiptDescription.primary,
        ),
      ];
      return GridView.count(
        crossAxisCount: count,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        childAspectRatio: switch (count) {
          1 => 2.5,
          2 => 2.1,
          _ => 1.8,
        },
        children: [
          for (final metric in metrics)
            _R35Card(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    metric.$1.toUpperCase(),
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .85,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    metric.$2,
                    style: AppTypography.headlineMedium.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    metric.$3,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

class _ProcurementRequestQueue extends StatelessWidget {
  const _ProcurementRequestQueue({
    required this.requests,
    required this.queued,
    required this.onOpenRequests,
  });

  final AsyncValue<List<YorksV1MaterialRequest>> requests;
  final List<YorksV1MaterialRequest> queued;
  final VoidCallback onOpenRequests;

  @override
  Widget build(BuildContext context) => _R35Card(
    minHeight: 150,
    child: requests.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(
        child: Text(
          YorksV1ShellStrings.requestsUnavailable.primary,
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        ),
      ),
      data: (_) {
        if (queued.isEmpty) {
          return Center(
            child: Text(
              YorksV1ShellStrings.noProcurementAction.primary,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
            ),
          );
        }
        final request = queued.first;
        final requestTitle = request.title?.trim();
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onOpenRequests,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: AppColors.blueContainer,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: const Icon(
                      Icons.assignment_outlined,
                      color: AppColors.blue,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${request.requestNumber ?? YorksV1MaterialRequestStrings.draft.primary}${requestTitle == null || requestTitle.isEmpty ? '' : ' · $requestTitle'}',
                          style: AppTypography.labelLarge.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          '${request.projectReference} · ${request.scopeName} · ${request.displayItemCount} ${YorksV1MaterialRequestStrings.items.primary.toLowerCase()}',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.muted,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _R35Card extends StatelessWidget {
  const _R35Card({
    required this.child,
    this.minHeight,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final Widget child;
  final double? minHeight;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(minHeight: minHeight ?? 0),
    padding: padding,
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(15),
      boxShadow: const [
        BoxShadow(
          color: AppColors.shadow,
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: child,
  );
}

class _R35SnapshotTile extends StatelessWidget {
  const _R35SnapshotTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLow,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.muted,
            fontWeight: FontWeight.w800,
            fontSize: 8.5,
            height: 1.2,
            letterSpacing: .85,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.ink,
            fontSize: 13,
            height: 1.35,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _R35PrimaryAction extends StatelessWidget {
  const _R35PrimaryAction({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).width <= AppSpacing.compactBreakpoint
        ? AppSpacing.minTapTarget
        : 38,
    child: FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon ?? Icons.arrow_forward_rounded, size: 20),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.navy,
        padding: EdgeInsets.symmetric(
          horizontal:
              MediaQuery.sizeOf(context).width <= AppSpacing.compactBreakpoint
              ? 11
              : 13,
        ),
        textStyle: AppTypography.labelLarge.copyWith(fontSize: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        elevation: 2,
        shadowColor: AppColors.navy.withValues(alpha: .28),
      ),
    ),
  );
}

class _R35SecondaryAction extends StatelessWidget {
  const _R35SecondaryAction({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).width <= AppSpacing.compactBreakpoint
        ? AppSpacing.minTapTarget
        : 38,
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 19),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.inkSecondary,
        side: const BorderSide(color: AppColors.line),
        padding: EdgeInsets.symmetric(
          horizontal:
              MediaQuery.sizeOf(context).width <= AppSpacing.compactBreakpoint
              ? 11
              : 13,
        ),
        textStyle: AppTypography.labelLarge.copyWith(fontSize: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
      ),
    ),
  );
}

class _R35SectionHeading extends StatelessWidget {
  const _R35SectionHeading({
    required this.title,
    this.description,
    this.attentionCount = 0,
  });

  final String title;
  final String? description;
  final int attentionCount;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTypography.titleLarge.copyWith(
                color: AppColors.ink,
                fontSize: 17,
                letterSpacing: -.255,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (description != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                description!,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.muted,
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
      if (attentionCount > 0) ...[
        const SizedBox(width: AppSpacing.sm),
        _NeedsActionBadge(count: attentionCount),
      ],
    ],
  );
}

class _NeedsActionBadge extends StatelessWidget {
  const _NeedsActionBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$count records need your action',
    child: Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: .10),
        border: Border.all(color: AppColors.error.withValues(alpha: .32)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.error,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.error,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );
}

class _OverviewProjectRow extends StatelessWidget {
  const _OverviewProjectRow({required this.item});

  final YorksV1ProjectPortfolioItem item;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 520;
      final details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.project.name,
            maxLines: compact ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.titleSmall.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '${item.project.reference} · ${item.project.siteLocation ?? '—'}',
            maxLines: compact ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
        ],
      );
      final state = _ProjectStateChip(state: item.project.state);
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () =>
              context.push(RoutePaths.yorksV1ProjectPath(item.project.id)),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              crossAxisAlignment: compact
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                _OverviewRecordIcon(icon: Icons.account_tree_outlined),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [details, const SizedBox(height: 8), state],
                        )
                      : details,
                ),
                if (!compact) ...[state, const SizedBox(width: AppSpacing.sm)],
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _OverviewRequestRow extends StatelessWidget {
  const _OverviewRequestRow({required this.item, required this.language});

  final YorksV1MaterialRequest item;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 520;
      final details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.requestNumber ??
                YorksV1MaterialRequestStrings.draft.active(language),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.titleSmall.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '${item.projectReference} · ${item.scopeName} · ${item.displayItemCount}',
            maxLines: compact ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
        ],
      );
      final stateLabel = yorksV1MaterialRequestStateCopy(
        item.state,
      ).active(language);
      final stateTone = _requestTone(item.state);
      final state = StatusChip(
        label: stateLabel,
        tone: stateTone,
        showDot: true,
      );
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push(_materialRequestOpenPath(item)),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              crossAxisAlignment: compact
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                _OverviewRecordIcon(icon: Icons.assignment_outlined),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            details,
                            const SizedBox(height: 8),
                            _OverviewCompactStatus(
                              label: stateLabel,
                              tone: stateTone,
                            ),
                          ],
                        )
                      : details,
                ),
                if (!compact) state,
              ],
            ),
          ),
        ),
      );
    },
  );
}

String _materialRequestOpenPath(YorksV1MaterialRequest request) {
  if (request.state.isDraft) {
    return RoutePaths.yorksV1MaterialRequestDraftPath(
      request.id,
      projectId: request.projectId,
      entryMode: YorksV1MaterialRequestDraftEntryMode.resumeSavedDraft,
    );
  }
  return RoutePaths.yorksV1MaterialRequestPath(request.id);
}

class _OverviewRecordIcon extends StatelessWidget {
  const _OverviewRecordIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: AppSpacing.minTapTarget,
    height: AppSpacing.minTapTarget,
    decoration: BoxDecoration(
      color: AppColors.blueContainer,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Icon(icon, color: AppColors.blue, size: 21),
  );
}

class _OverviewRetry extends StatelessWidget {
  const _OverviewRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.xl),
    child: OutlinedButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh_rounded),
      label: Text(YorksV1MaterialRequestStrings.refresh.primary),
    ),
  );
}

NexusStatusTone _requestTone(YorksV1MaterialRequestState state) {
  switch (state) {
    case YorksV1MaterialRequestState.approved:
    case YorksV1MaterialRequestState.approvedForArrangement:
    case YorksV1MaterialRequestState.received:
    case YorksV1MaterialRequestState.closed:
      return NexusStatusTone.success;
    case YorksV1MaterialRequestState.awaitingApproval:
    case YorksV1MaterialRequestState.awaitingRequestApproval:
    case YorksV1MaterialRequestState.changesRequested:
    case YorksV1MaterialRequestState.partiallyDispatched:
    case YorksV1MaterialRequestState.dispatched:
    case YorksV1MaterialRequestState.partiallyReceived:
      return NexusStatusTone.warning;
    case YorksV1MaterialRequestState.cancelled:
      return NexusStatusTone.danger;
    case YorksV1MaterialRequestState.submitted:
    case YorksV1MaterialRequestState.arranging:
      return NexusStatusTone.info;
    case YorksV1MaterialRequestState.draft:
      return NexusStatusTone.neutral;
  }
}

class _YorksV1ProjectsScreenState extends ConsumerState<YorksV1ProjectsScreen> {
  late String _search;
  late YorksV1ProjectLifecycle? _stateFilter;

  @override
  void initState() {
    super.initState();
    _search = widget.initialSearch?.trim() ?? '';
    _stateFilter = widget.initialState;
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final role = ref.watch(yorksV1CurrentRoleProvider);
    final portfolio = ref.watch(yorksV1AuthorizedProjectPortfolioProvider);
    final createAccess = yorksV1FeatureActionAccess(
      ref.watch(yorksV1CurrentPermissionSnapshotProvider),
      YorksV1CapabilityKeys.projectsCreate,
      legacyAllowed: role?.canCreateProject == true,
    );
    final canCreate = createAccess.isVisible;
    final onCreate = createAccess.canWrite
        ? () => context.push(RoutePaths.engineerCreateProject)
        : null;

    if (YorksMobileUi.isActive(context)) {
      return Scaffold(
        backgroundColor: AppColors.mobileSurface,
        body: portfolio.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _PortfolioError(
            language: language,
            onRetry: () => ref.invalidate(yorksV1ProjectPortfolioProvider),
          ),
          data: (items) => _YorksMobileProjectsPage(
            items: items,
            visible: _filter(items),
            language: language,
            stateFilter: _stateFilter,
            search: _search,
            canCreate: canCreate,
            onSearchChanged: (value) => setState(() => _search = value),
            onStateChanged: (value) => setState(() => _stateFilter = value),
            onCreate: onCreate,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        top: false,
        child: NexusPageShell(
          eyebrow: YorksV1ProjectStrings.projects.primary,
          title: YorksV1ProjectStrings.projects.primary,
          description: role == YorksV1Role.procurement
              ? YorksV1ProjectStrings.viewOnlyPortfolio.primary
              : YorksV1ProjectStrings.portfolioDescription.primary,
          actions: [
            if (canCreate)
              SizedBox(
                height: AppSpacing.minTapTarget,
                child: FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(YorksV1ProjectStrings.createProject.primary),
                ),
              ),
          ],
          child: portfolio.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.huge),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (_, _) => _PortfolioError(
              language: language,
              onRetry: () => ref.invalidate(yorksV1ProjectPortfolioProvider),
            ),
            data: (items) {
              final visible = _filter(items);
              return _PortfolioBody(
                items: items,
                visible: visible,
                language: language,
                stateFilter: _stateFilter,
                search: _search,
                canCreate: canCreate,
                onSearchChanged: (value) => setState(() => _search = value),
                onStateChanged: (value) => setState(() => _stateFilter = value),
                onCreate: onCreate,
              );
            },
          ),
        ),
      ),
    );
  }

  List<YorksV1ProjectPortfolioItem> _filter(
    List<YorksV1ProjectPortfolioItem> items,
  ) {
    final query = _search.trim().toLowerCase();
    return [
      for (final item in items)
        if ((_stateFilter == null || item.project.state == _stateFilter) &&
            (query.isEmpty ||
                item.project.reference.toLowerCase().contains(query) ||
                item.project.name.toLowerCase().contains(query) ||
                (item.project.siteLocation ?? '').toLowerCase().contains(
                  query,
                ) ||
                (item.clientName ?? '').toLowerCase().contains(query)))
          item,
    ];
  }
}

enum YorksV1ProjectWorkspaceTab {
  overview,
  boq,
  requests,
  accounts,
  documents,
  materialMovement,
}

enum _MobileProjectDetailTab { information, team, buildings }

class YorksV1ProjectWorkspaceScreen extends ConsumerStatefulWidget {
  const YorksV1ProjectWorkspaceScreen({
    super.key,
    required this.projectId,
    this.initialTab = YorksV1ProjectWorkspaceTab.overview,
    this.initialAccountsTab = YorksProjectAccountsTab.overview,
  });

  final String projectId;
  final YorksV1ProjectWorkspaceTab initialTab;
  final YorksProjectAccountsTab initialAccountsTab;

  @override
  ConsumerState<YorksV1ProjectWorkspaceScreen> createState() =>
      _YorksV1ProjectWorkspaceScreenState();
}

class _YorksV1ProjectWorkspaceScreenState
    extends ConsumerState<YorksV1ProjectWorkspaceScreen> {
  late YorksV1ProjectWorkspaceTab _tab;
  bool _showMobileDetails = false;
  _MobileProjectDetailTab _mobileDetailTab = _MobileProjectDetailTab.team;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
  }

  @override
  void didUpdateWidget(covariant YorksV1ProjectWorkspaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      _tab = widget.initialTab;
    }
    if (oldWidget.projectId != widget.projectId) {
      _showMobileDetails = false;
      _mobileDetailTab = _MobileProjectDetailTab.team;
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final role = ref.watch(yorksV1CurrentRoleProvider);
    final authUserId = ref.watch(yorksV1AuthUserIdProvider);
    final permissionState = ref.watch(yorksV1CurrentPermissionSnapshotProvider);
    final portfolio = ref.watch(yorksV1AuthorizedProjectPortfolioProvider);
    final canReadRequests = yorksV1CanReadProjectRecord(
      permissionState,
      YorksV1CapabilityKeys.materialRequestsView,
      legacyAllowed: true,
      projectId: widget.projectId,
    );
    final canReadBoq = yorksV1CanReadProjectRecord(
      permissionState,
      YorksV1CapabilityKeys.boqView,
      legacyAllowed: true,
      projectId: widget.projectId,
    );
    final featureFlags = ref.watch(yorksV1FeatureFlagsProvider);
    final canReadProjectAccounts =
        featureFlags.accounts &&
        yorksV1CanReadProjectRecord(
          permissionState,
          YorksV1CapabilityKeys.viewProjectAccounts,
          legacyAllowed: false,
          projectId: widget.projectId,
        );
    final canReadSupplierAccounts =
        featureFlags.accounts &&
        yorksV1CanReadProjectRecord(
          permissionState,
          YorksV1CapabilityKeys.viewSupplierCosts,
          legacyAllowed: false,
          projectId: widget.projectId,
        );
    final showAccounts = canReadProjectAccounts || canReadSupplierAccounts;
    final AsyncValue<List<YorksV1MaterialRequest>> requests = canReadRequests
        ? ref.watch(yorksV1MaterialRequestListProvider(widget.projectId))
        : const AsyncData<List<YorksV1MaterialRequest>>([]);
    final scopes = ref.watch(
      yorksV1MaterialRequestScopesProvider(widget.projectId),
    );
    final AsyncValue<List<YorksV1BoqGroup>> groups = canReadBoq
        ? ref.watch(yorksV1BoqGroupsProvider(widget.projectId))
        : const AsyncData<List<YorksV1BoqGroup>>([]);
    final documents = ref.watch(
      yorksV1DocumentWorkspaceProvider(widget.projectId),
    );
    final mobile = YorksMobileUi.isActive(context);

    Widget mobileFrame({
      required String title,
      required Widget child,
      bool details = false,
      bool showMenu = false,
      VoidCallback? onOpenChat,
      VoidCallback? onBack,
    }) {
      if (!mobile) return child;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          YorksMobileAppBar(
            title: title,
            leading: details || onBack != null
                ? YorksMobileIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    onPressed:
                        onBack ??
                        () => setState(() => _showMobileDetails = false),
                  )
                : YorksMobileIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go(RoutePaths.yorksV1Projects),
                  ),
            trailing: showMenu || onOpenChat != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onOpenChat != null)
                        YorksMobileIconButton(
                          icon: Icons.forum_outlined,
                          tooltip: YorksV1TeamChatStrings.openChat.primary,
                          onPressed: onOpenChat,
                        ),
                      if (showMenu)
                        YorksMobileIconButton(
                          icon: Icons.menu_rounded,
                          tooltip: YorksV1ProjectStrings.projectDetails.primary,
                          onPressed: () => setState(() {
                            _mobileDetailTab = _MobileProjectDetailTab.team;
                            _showMobileDetails = true;
                          }),
                        ),
                    ],
                  )
                : null,
          ),
          Expanded(child: child),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        top: false,
        child: portfolio.when(
          loading: () => mobileFrame(
            title: YorksV1ProjectStrings.projectWorkspace.primary,
            child: const Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => mobileFrame(
            title: YorksV1ProjectStrings.projectWorkspace.primary,
            child: _PortfolioError(
              language: language,
              onRetry: () => ref.invalidate(yorksV1ProjectPortfolioProvider),
            ),
          ),
          data: (items) {
            YorksV1ProjectPortfolioItem? project;
            for (final item in items) {
              if (item.project.id == widget.projectId) {
                project = item;
                break;
              }
            }
            if (project == null) {
              return mobileFrame(
                title: YorksV1ProjectStrings.projectWorkspace.primary,
                child: _PortfolioError(
                  language: language,
                  onRetry: () =>
                      ref.invalidate(yorksV1ProjectPortfolioProvider),
                ),
              );
            }
            final selectedProject = project;
            final teamChatEnabled = featureFlags.teamChat;
            final projectStateIsEditable =
                selectedProject.project.state ==
                    YorksV1ProjectLifecycle.draft ||
                selectedProject.project.state == YorksV1ProjectLifecycle.active;
            final activeMember =
                authUserId != null &&
                selectedProject.activeMembers.any(
                  (member) => member.memberAuthUserId == authUserId,
                );
            final isCreator =
                authUserId != null &&
                selectedProject.project.createdByAuthUserId == authUserId;
            final hasProjectEngineerMembership =
                authUserId != null &&
                selectedProject.activeMembers.any(
                  (member) =>
                      member.memberAuthUserId == authUserId &&
                      member.projectRole ==
                          YorksV1ProjectMembershipRole.projectEngineer,
                );
            final legacyCanManageProject =
                role == YorksV1Role.admin ||
                (role?.isGlobalProjectEngineer ?? false) ||
                hasProjectEngineerMembership;
            final legacyCanEdit =
                projectStateIsEditable &&
                (role == YorksV1Role.admin ||
                    (role?.isGlobalProjectEngineer ?? false) ||
                    activeMember ||
                    isCreator);
            final editAccess = yorksV1FeatureActionAccess(
              permissionState,
              YorksV1CapabilityKeys.projectsEdit,
              legacyAllowed: legacyCanEdit,
              projectId: selectedProject.project.id,
            );
            final archiveAccess = yorksV1FeatureActionAccess(
              permissionState,
              YorksV1CapabilityKeys.projectsArchive,
              legacyAllowed: role == YorksV1Role.admin,
              projectId: selectedProject.project.id,
            );
            final requestCreateAccess = yorksV1FeatureActionAccess(
              permissionState,
              YorksV1CapabilityKeys.materialRequestsCreate,
              legacyAllowed: role?.canCreateMaterialRequest == true,
              projectId: selectedProject.project.id,
            );
            final requestApproveAccess = yorksV1FeatureActionAccess(
              permissionState,
              YorksV1CapabilityKeys.materialRequestsApprove,
              legacyAllowed: legacyCanManageProject,
              projectId: selectedProject.project.id,
            );
            final VoidCallback? activateAction =
                selectedProject.project.state ==
                        YorksV1ProjectLifecycle.draft &&
                    legacyCanManageProject
                ? () => _activateProject(selectedProject.project)
                : null;
            final VoidCallback? newRequestAction =
                projectStateIsEditable && requestCreateAccess.canWrite
                ? () => context.push(
                    RoutePaths.yorksV1MaterialRequestDraftPath(
                      const Uuid().v4(),
                      projectId: selectedProject.project.id,
                      entryMode: YorksV1MaterialRequestDraftEntryMode.newDraft,
                    ),
                  )
                : null;
            final VoidCallback? editAction = editAccess.canWrite
                ? () => context.push(
                    RoutePaths.yorksV1ProjectEditPath(
                      selectedProject.project.id,
                    ),
                  )
                : null;
            final VoidCallback? archiveAction =
                archiveAccess.canWrite &&
                    selectedProject.project.state !=
                        YorksV1ProjectLifecycle.archived
                ? () => _confirmSafeArchive(selectedProject.project)
                : null;
            final VoidCallback? openChatAction = teamChatEnabled
                ? () => _openProjectChat(selectedProject.project.id)
                : null;
            final workspace = _showMobileDetails && mobile
                ? _MobileProjectDetails(
                    item: selectedProject,
                    scopes: scopes,
                    selected: _mobileDetailTab,
                    onSelected: (value) =>
                        setState(() => _mobileDetailTab = value),
                    onActivate: activateAction,
                    showNewRequest:
                        projectStateIsEditable && requestCreateAccess.isVisible,
                    onNewRequest: newRequestAction,
                    showEdit: editAccess.isVisible,
                    onEdit: editAction,
                    showArchive:
                        archiveAccess.isVisible &&
                        selectedProject.project.state !=
                            YorksV1ProjectLifecycle.archived,
                    onArchive: archiveAction,
                  )
                : _ProjectWorkspaceBody(
                    item: selectedProject,
                    tab: _tab,
                    language: language,
                    requests: requests,
                    scopes: scopes,
                    groups: groups,
                    documents: documents,
                    actorRole: role,
                    activeMember: activeMember,
                    canActAsProjectEngineer: requestApproveAccess.isVisible,
                    showAccounts: showAccounts,
                    initialAccountsTab: widget.initialAccountsTab,
                    onActivate: activateAction,
                    showNewRequest:
                        projectStateIsEditable && requestCreateAccess.isVisible,
                    onNewRequest: newRequestAction,
                    showEdit: editAccess.isVisible,
                    onEdit: editAction,
                    showArchive:
                        archiveAccess.isVisible &&
                        selectedProject.project.state !=
                            YorksV1ProjectLifecycle.archived,
                    onArchive: archiveAction,
                    onOpenChat: openChatAction,
                    onRetryRequests: () => ref.invalidate(
                      yorksV1MaterialRequestListProvider(widget.projectId),
                    ),
                    onTabChanged: (value) {
                      if (value == YorksV1ProjectWorkspaceTab.accounts) {
                        context.go(
                          canReadProjectAccounts
                              ? RoutePaths.yorksV1ProjectAccountsOverviewPath(
                                  selectedProject.project.id,
                                )
                              : RoutePaths.yorksV1ProjectAccountsSupplierBillsPath(
                                  selectedProject.project.id,
                                ),
                        );
                        return;
                      }
                      setState(() => _tab = value);
                    },
                  );
            return mobileFrame(
              title: _showMobileDetails
                  ? YorksV1ProjectStrings.projectDetails.primary
                  : switch (_tab) {
                      YorksV1ProjectWorkspaceTab.overview =>
                        selectedProject.project.reference,
                      YorksV1ProjectWorkspaceTab.boq =>
                        '${selectedProject.project.reference} · ${YorksV1ProjectStrings.boq.primary}',
                      YorksV1ProjectWorkspaceTab.requests =>
                        YorksV1ProjectStrings.materialRequests.primary,
                      YorksV1ProjectWorkspaceTab.accounts =>
                        YorksV1ProjectStrings.accounts.primary,
                      YorksV1ProjectWorkspaceTab.documents =>
                        YorksV1ProjectStrings.documents.primary,
                      YorksV1ProjectWorkspaceTab.materialMovement =>
                        YorksV1ProjectStrings.materialMovement.primary,
                    },
              details: _showMobileDetails,
              showMenu:
                  !_showMobileDetails &&
                  _tab == YorksV1ProjectWorkspaceTab.overview,
              onOpenChat: _showMobileDetails ? null : openChatAction,
              onBack:
                  !_showMobileDetails &&
                      _tab != YorksV1ProjectWorkspaceTab.overview
                  ? () => setState(
                      () => _tab = YorksV1ProjectWorkspaceTab.overview,
                    )
                  : null,
              child: workspace,
            );
          },
        ),
      ),
    );
  }

  Future<void> _openProjectChat(String projectId) async {
    final conversation = await ref
        .read(yorksV1TeamChatProvider.notifier)
        .createConversation(
          YorksV1ChatCreateInput(
            kind: YorksV1ChatKind.project,
            idempotencyKey: const Uuid().v4(),
            projectId: projectId,
          ),
        );
    if (!mounted || conversation == null) return;
    context.go(RoutePaths.yorksV1TeamChatPath(conversation.id));
  }

  Future<void> _activateProject(YorksV1Project project) async {
    try {
      await ref
          .read(yorksV1ProjectCommandControllerProvider.notifier)
          .setProjectState(
            YorksV1SetProjectStateInput(
              idempotencyKey: const Uuid().v4(),
              projectId: project.id,
              currentState: project.state,
              targetState: YorksV1ProjectLifecycle.active,
              expectedProjectVersion: project.recordVersion,
            ),
          );
      ref.invalidate(yorksV1ProjectPortfolioProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(YorksV1ProjectStrings.projectActivated.primary)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(YorksV1ProjectStrings.projectActivationFailed.primary),
        ),
      );
    }
  }

  Future<void> _confirmSafeArchive(YorksV1Project project) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(YorksV1ProjectStrings.safeDeleteProject.primary),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(YorksV1ProjectStrings.safeDeleteProjectDescription.primary),
            const SizedBox(height: AppSpacing.lg),
            LedgerTextField(
              controller: reasonController,
              label: YorksV1ProjectStrings.archiveReason.primary,
              hintText: YorksV1ProjectStrings.archiveReason.primary,
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(YorksV1ProjectStrings.cancel.primary),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(reasonController.text.trim()),
            child: Text(YorksV1ProjectStrings.confirmArchive.primary),
          ),
        ],
      ),
    );
    reasonController.dispose();
    if (reason == null || reason.trim().isEmpty) return;
    try {
      await ref
          .read(yorksV1ProjectCommandControllerProvider.notifier)
          .archiveProject(
            YorksV1ArchiveProjectInput(
              idempotencyKey: const Uuid().v4(),
              projectId: project.id,
              expectedProjectVersion: project.recordVersion,
              reason: reason,
            ),
          );
      ref.invalidate(yorksV1ProjectPortfolioProvider);
      if (!mounted) return;
      context.go(RoutePaths.yorksV1Projects);
    } on YorksV1DomainException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(YorksV1ProjectStrings.errorFor(error.code).primary),
        ),
      );
    }
  }
}

class _YorksMobileProjectsPage extends StatelessWidget {
  const _YorksMobileProjectsPage({
    required this.items,
    required this.visible,
    required this.language,
    required this.stateFilter,
    required this.search,
    required this.canCreate,
    required this.onSearchChanged,
    required this.onStateChanged,
    required this.onCreate,
  });

  final List<YorksV1ProjectPortfolioItem> items;
  final List<YorksV1ProjectPortfolioItem> visible;
  final AppLanguage language;
  final YorksV1ProjectLifecycle? stateFilter;
  final String search;
  final bool canCreate;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<YorksV1ProjectLifecycle?> onStateChanged;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.mobileSurface,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    YorksV1ProjectStrings.projects.primary,
                    style: AppTypography.headlineMedium.copyWith(
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    (canCreate
                            ? YorksV1ProjectStrings.portfolioDescription
                            : YorksV1ProjectStrings.viewOnlyPortfolio)
                        .primary,
                    maxLines: 2,
                    style: AppTypography.bodySmall,
                  ),
                ],
              ),
            ),
            if (canCreate)
              SizedBox.square(
                dimension: AppSpacing.minTapTarget,
                child: FilledButton(
                  onPressed: onCreate,
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Icon(Icons.add_rounded),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        TextFormField(
          initialValue: search,
          onChanged: onSearchChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            hintText: YorksV1ProjectStrings.searchProjects.primary,
            filled: true,
            fillColor: AppColors.surfaceContainerLowest,
            contentPadding: const EdgeInsets.symmetric(vertical: 11),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.line),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: YorksMobilePill(
                label: YorksV1ProjectStrings.allStates.primary,
                selected: stateFilter == null,
                onTap: () => onStateChanged(null),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: YorksMobilePill(
                label: YorksV1ProjectStrings.activeState.primary,
                selected: stateFilter == YorksV1ProjectLifecycle.active,
                onTap: () => onStateChanged(YorksV1ProjectLifecycle.active),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: YorksMobilePill(
                label: YorksV1ProjectStrings.completedState.primary,
                selected: stateFilter == YorksV1ProjectLifecycle.completed,
                onTap: () => onStateChanged(YorksV1ProjectLifecycle.completed),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (items.isEmpty)
          _PortfolioEmpty(
            language: language,
            canCreate: canCreate,
            onCreate: onCreate,
          )
        else if (visible.isEmpty)
          _NoMatchingProjects(language: language)
        else
          _MobileProjectList(items: visible, language: language),
      ],
    ),
  );
}

class _PortfolioBody extends StatelessWidget {
  const _PortfolioBody({
    required this.items,
    required this.visible,
    required this.language,
    required this.stateFilter,
    required this.search,
    required this.canCreate,
    required this.onSearchChanged,
    required this.onStateChanged,
    required this.onCreate,
  });

  final List<YorksV1ProjectPortfolioItem> items;
  final List<YorksV1ProjectPortfolioItem> visible;
  final AppLanguage language;
  final YorksV1ProjectLifecycle? stateFilter;
  final String search;
  final bool canCreate;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<YorksV1ProjectLifecycle?> onStateChanged;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _PortfolioEmpty(
        language: language,
        canCreate: canCreate,
        onCreate: onCreate,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop =
            constraints.maxWidth >= AppSpacing.yorksV1DesktopBreakpoint;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PortfolioControls(
              language: language,
              stateFilter: stateFilter,
              search: search,
              onSearchChanged: onSearchChanged,
              onStateChanged: onStateChanged,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (visible.isEmpty)
              _NoMatchingProjects(language: language)
            else if (desktop)
              _DesktopProjectList(items: visible, language: language)
            else
              _MobileProjectList(items: visible, language: language),
          ],
        );
      },
    );
  }
}

class _PortfolioControls extends StatelessWidget {
  const _PortfolioControls({
    required this.language,
    required this.stateFilter,
    required this.search,
    required this.onSearchChanged,
    required this.onStateChanged,
  });

  final AppLanguage language;
  final YorksV1ProjectLifecycle? stateFilter;
  final String search;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<YorksV1ProjectLifecycle?> onStateChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final searchField = TextFormField(
          initialValue: search,
          onChanged: onSearchChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            labelText: YorksV1ProjectStrings.searchProjects.primary,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
          ),
        );
        final filter = DropdownButtonFormField<YorksV1ProjectLifecycle?>(
          initialValue: stateFilter,
          decoration: InputDecoration(
            labelText: YorksV1ProjectStrings.allStates.primary,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
          ),
          items: [
            DropdownMenuItem<YorksV1ProjectLifecycle?>(
              value: null,
              child: Text(YorksV1ProjectStrings.allStates.primary),
            ),
            for (final value in YorksV1ProjectLifecycle.values)
              DropdownMenuItem(
                value: value,
                child: Text(YorksV1ProjectStrings.stateLabel(value).primary),
              ),
          ],
          onChanged: onStateChanged,
        );
        if (constraints.maxWidth < AppSpacing.compactBreakpoint) {
          return Column(
            children: [
              searchField,
              const SizedBox(height: AppSpacing.md),
              filter,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: searchField),
            const SizedBox(width: AppSpacing.md),
            SizedBox(width: 220, child: filter),
          ],
        );
      },
    );
  }
}

class _DesktopProjectList extends StatelessWidget {
  const _DesktopProjectList({required this.items, required this.language});

  final List<YorksV1ProjectPortfolioItem> items;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    return LedgerCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          const _DesktopProjectHeader(),
          const Divider(height: 1, color: AppColors.line),
          for (var index = 0; index < items.length; index++) ...[
            _DesktopProjectRow(item: items[index], language: language),
            if (index + 1 < items.length)
              const Divider(height: 1, color: AppColors.line),
          ],
        ],
      ),
    );
  }
}

class _DesktopProjectHeader extends StatelessWidget {
  const _DesktopProjectHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: _TableHeader(copy: YorksV1ProjectStrings.projects),
          ),
          Expanded(
            flex: 2,
            child: _TableHeader(copy: YorksV1ProjectStrings.state),
          ),
          Expanded(
            flex: 3,
            child: _TableHeader(copy: YorksV1ProjectStrings.site),
          ),
          Expanded(
            flex: 2,
            child: _TableHeader(copy: YorksV1ProjectStrings.activeTeam),
          ),
          Expanded(
            flex: 2,
            child: _TableHeader(copy: YorksV1ProjectStrings.updated),
          ),
          SizedBox(width: AppSpacing.minTapTarget),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.copy});

  final TranslatableString copy;

  @override
  Widget build(BuildContext context) => Text(
    copy.primary,
    style: AppTypography.labelMedium.copyWith(
      color: AppColors.muted,
      fontWeight: FontWeight.w800,
    ),
  );
}

class _DesktopProjectRow extends StatelessWidget {
  const _DesktopProjectRow({required this.item, required this.language});

  final YorksV1ProjectPortfolioItem item;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final project = item.project;
    return Semantics(
      button: true,
      label: YorksV1ProjectStrings.openProject.primary,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push(RoutePaths.yorksV1ProjectPath(project.id)),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: _ProjectIdentity(item: item, language: language),
                ),
                Expanded(
                  flex: 2,
                  child: _ProjectStateChip(state: project.state),
                ),
                Expanded(
                  flex: 3,
                  child: _ValueText(value: project.siteLocation),
                ),
                Expanded(
                  flex: 2,
                  child: _TeamAndBuildings(item: item, compact: true),
                ),
                Expanded(flex: 2, child: _UpdatedText(date: project.updatedAt)),
                SizedBox(
                  width: AppSpacing.minTapTarget,
                  height: AppSpacing.minTapTarget,
                  child: IconButton(
                    tooltip: YorksV1ProjectStrings.openProject.primary,
                    onPressed: () =>
                        context.push(RoutePaths.yorksV1ProjectPath(project.id)),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileProjectList extends StatelessWidget {
  const _MobileProjectList({required this.items, required this.language});

  final List<YorksV1ProjectPortfolioItem> items;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final item in items) ...[
        _MobileProjectCard(item: item, language: language),
        const SizedBox(height: AppSpacing.md),
      ],
    ],
  );
}

class _MobileProjectCard extends StatelessWidget {
  const _MobileProjectCard({required this.item, required this.language});

  final YorksV1ProjectPortfolioItem item;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final project = item.project;
    return LedgerCard(
      onTap: () => context.push(RoutePaths.yorksV1ProjectPath(project.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ProjectIdentity(item: item, language: language),
              ),
              const SizedBox(width: AppSpacing.sm),
              _ProjectStateChip(state: project.state),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _ValueLine(
            copy: YorksV1ProjectStrings.site,
            value: project.siteLocation,
          ),
          if (item.clientName != null)
            _ValueLine(
              copy: YorksV1ProjectStrings.clientLabel,
              value: item.clientName,
            ),
          const SizedBox(height: AppSpacing.sm),
          _TeamAndBuildings(item: item),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: _UpdatedText(date: project.updatedAt)),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: AppColors.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectIdentity extends StatelessWidget {
  const _ProjectIdentity({required this.item, required this.language});

  final YorksV1ProjectPortfolioItem item;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        item.project.reference,
        style: AppTypography.labelMedium.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        item.project.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w800),
      ),
      if (item.clientName != null) ...[
        const SizedBox(height: AppSpacing.xxs),
        Text(
          item.clientName!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        ),
      ],
    ],
  );
}

class _ProjectStateChip extends StatelessWidget {
  const _ProjectStateChip({required this.state});

  final YorksV1ProjectLifecycle state;

  @override
  Widget build(BuildContext context) => StatusChip(
    label: YorksV1ProjectStrings.stateLabel(state).primary,
    tone: switch (state) {
      YorksV1ProjectLifecycle.draft => NexusStatusTone.neutral,
      YorksV1ProjectLifecycle.active => NexusStatusTone.success,
      YorksV1ProjectLifecycle.onHold => NexusStatusTone.warning,
      YorksV1ProjectLifecycle.completed => NexusStatusTone.info,
      YorksV1ProjectLifecycle.archived => NexusStatusTone.neutral,
    },
    icon: switch (state) {
      YorksV1ProjectLifecycle.draft => Icons.edit_note_outlined,
      YorksV1ProjectLifecycle.active => Icons.play_circle_outline_rounded,
      YorksV1ProjectLifecycle.onHold => Icons.pause_circle_outline_rounded,
      YorksV1ProjectLifecycle.completed => Icons.task_alt_rounded,
      YorksV1ProjectLifecycle.archived => Icons.archive_outlined,
    },
  );
}

class _TeamAndBuildings extends StatelessWidget {
  const _TeamAndBuildings({required this.item, this.compact = false});

  final YorksV1ProjectPortfolioItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final team =
        '${item.activeTeamCount} ${YorksV1ProjectStrings.activeTeam.primary}';
    final buildings =
        '${item.activeBuildingCount} ${YorksV1ProjectStrings.buildings.primary}';
    if (compact) {
      return Text(
        '$team · $buildings',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.bodySmall.copyWith(color: AppColors.inkSecondary),
      );
    }
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      children: [
        _MetricChip(icon: Icons.groups_outlined, label: team),
        _MetricChip(icon: Icons.apartment_outlined, label: buildings),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: AppColors.muted),
      const SizedBox(width: AppSpacing.xs),
      Text(label, style: AppTypography.labelMedium),
    ],
  );
}

class _UpdatedText extends StatelessWidget {
  const _UpdatedText({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) => Text(
    DateFormat.yMMMd().format(date.toLocal()),
    style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
  );
}

class _ValueText extends StatelessWidget {
  const _ValueText({required this.value});

  final String? value;

  @override
  Widget build(BuildContext context) => Text(
    value?.trim().isNotEmpty == true ? value! : '—',
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: AppTypography.bodySmall.copyWith(color: AppColors.inkSecondary),
  );
}

class _ValueLine extends StatelessWidget {
  const _ValueLine({required this.copy, required this.value});

  final TranslatableString copy;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if (value?.trim().isNotEmpty != true) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${copy.primary}: ',
              style: AppTypography.labelMedium.copyWith(color: AppColors.muted),
            ),
            TextSpan(
              text: value,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.inkSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PortfolioEmpty extends StatelessWidget {
  const _PortfolioEmpty({
    required this.language,
    required this.canCreate,
    required this.onCreate,
  });

  final AppLanguage language;
  final bool canCreate;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) => LedgerCard(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.account_tree_outlined,
              size: 44,
              color: AppColors.muted,
            ),
            const SizedBox(height: AppSpacing.lg),
            _CopyText(
              copy: YorksV1ProjectStrings.noProjects,
              language: language,
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w800,
              ),
              center: true,
            ),
            const SizedBox(height: AppSpacing.sm),
            _CopyText(
              copy: YorksV1ProjectStrings.noProjectsDescription,
              language: language,
              center: true,
            ),
            if (canCreate) ...[
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: AppSpacing.minTapTarget,
                child: FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(YorksV1ProjectStrings.createProject.primary),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _NoMatchingProjects extends StatelessWidget {
  const _NoMatchingProjects({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) => LedgerCard(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: _CopyText(
        copy: YorksV1ProjectStrings.noMatchingProjects,
        language: language,
        center: true,
      ),
    ),
  );
}

class _PortfolioError extends StatelessWidget {
  const _PortfolioError({required this.language, required this.onRetry});

  final AppLanguage language;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: LedgerCard(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                size: 42,
                color: AppColors.warning,
              ),
              const SizedBox(height: AppSpacing.lg),
              _CopyText(
                copy: YorksV1ProjectStrings.portfolioUnavailable,
                language: language,
                center: true,
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: AppSpacing.minTapTarget,
                child: OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(YorksV1ProjectStrings.retry.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ProjectWorkspaceBody extends StatelessWidget {
  const _ProjectWorkspaceBody({
    required this.item,
    required this.tab,
    required this.language,
    required this.requests,
    required this.scopes,
    required this.groups,
    required this.documents,
    required this.actorRole,
    required this.activeMember,
    required this.canActAsProjectEngineer,
    required this.showAccounts,
    required this.initialAccountsTab,
    required this.onActivate,
    required this.showNewRequest,
    required this.onNewRequest,
    required this.showEdit,
    required this.onEdit,
    required this.showArchive,
    required this.onArchive,
    required this.onOpenChat,
    required this.onRetryRequests,
    required this.onTabChanged,
  });

  final YorksV1ProjectPortfolioItem item;
  final YorksV1ProjectWorkspaceTab tab;
  final AppLanguage language;
  final AsyncValue<List<YorksV1MaterialRequest>> requests;
  final AsyncValue<List<YorksV1MaterialRequestScopeOption>> scopes;
  final AsyncValue<List<YorksV1BoqGroup>> groups;
  final AsyncValue<YorksV1DocumentWorkspace> documents;
  final YorksV1Role? actorRole;
  final bool activeMember;
  final bool canActAsProjectEngineer;
  final bool showAccounts;
  final YorksProjectAccountsTab initialAccountsTab;
  final VoidCallback? onActivate;
  final bool showNewRequest;
  final VoidCallback? onNewRequest;
  final bool showEdit;
  final VoidCallback? onEdit;
  final bool showArchive;
  final VoidCallback? onArchive;
  final VoidCallback? onOpenChat;
  final VoidCallback onRetryRequests;
  final ValueChanged<YorksV1ProjectWorkspaceTab> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final project = item.project;
    if (YorksMobileUi.isActive(context)) {
      return _MobileProjectWorkspace(
        item: item,
        language: language,
        tab: tab,
        requests: requests,
        scopes: scopes,
        groups: groups,
        documents: documents,
        actorRole: actorRole,
        activeMember: activeMember,
        canActAsProjectEngineer: canActAsProjectEngineer,
        showAccounts: showAccounts,
        initialAccountsTab: initialAccountsTab,
        showNewRequest: showNewRequest,
        onNewRequest: onNewRequest,
        onTabChanged: onTabChanged,
        onOpenRequests: () => onTabChanged(YorksV1ProjectWorkspaceTab.requests),
        onOpenRequest: (request) =>
            context.push(_materialRequestOpenPath(request)),
        onRetryRequests: onRetryRequests,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop =
            constraints.maxWidth >= AppSpacing.yorksV1DesktopBreakpoint;
        final horizontal = desktop ? AppSpacing.xl : AppSpacing.lg;
        if (tab == YorksV1ProjectWorkspaceTab.requests ||
            tab == YorksV1ProjectWorkspaceTab.accounts ||
            tab == YorksV1ProjectWorkspaceTab.documents) {
          return ColoredBox(
            color: AppColors.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProjectR35Hero(
                  project: project,
                  selected: tab,
                  onSelected: onTabChanged,
                  showAccounts: showAccounts,
                  onActivate: onActivate,
                  showNewRequest: showNewRequest,
                  onNewRequest: onNewRequest,
                  showEdit: showEdit,
                  onEdit: onEdit,
                  showArchive: showArchive,
                  onArchive: onArchive,
                  onOpenChat: onOpenChat,
                ),
                Expanded(
                  child: tab == YorksV1ProjectWorkspaceTab.accounts
                      ? YorksProjectAccountsScreen(
                          projectId: project.id,
                          initialTab: initialAccountsTab,
                        )
                      : Padding(
                          padding: EdgeInsets.fromLTRB(
                            horizontal,
                            AppSpacing.xl,
                            horizontal,
                            0,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: AppSpacing.pageMaxWidth,
                            ),
                            child: tab == YorksV1ProjectWorkspaceTab.requests
                                ? YorksV1MaterialRequestsScreen(
                                    projectId: project.id,
                                    embedded: true,
                                  )
                                : YorksV1DocumentsScreen(
                                    projectId: project.id,
                                    embedded: true,
                                  ),
                          ),
                        ),
                ),
              ],
            ),
          );
        }
        return ColoredBox(
          color: AppColors.surface,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 72),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProjectR35Hero(
                  project: project,
                  selected: tab,
                  onSelected: onTabChanged,
                  showAccounts: showAccounts,
                  onActivate: onActivate,
                  showNewRequest: showNewRequest,
                  onNewRequest: onNewRequest,
                  showEdit: showEdit,
                  onEdit: onEdit,
                  showArchive: showArchive,
                  onArchive: onArchive,
                  onOpenChat: onOpenChat,
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontal,
                    tab == YorksV1ProjectWorkspaceTab.overview
                        ? AppSpacing.md
                        : AppSpacing.xl,
                    horizontal,
                    0,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppSpacing.pageMaxWidth,
                    ),
                    child: switch (tab) {
                      YorksV1ProjectWorkspaceTab.overview =>
                        _ProjectR35Overview(
                          item: item,
                          language: language,
                          groups: groups,
                          requests: requests,
                          scopes: scopes,
                          documents: documents,
                          onOpenRequests: () =>
                              onTabChanged(YorksV1ProjectWorkspaceTab.requests),
                          onOpenRequest: (request) =>
                              context.push(_materialRequestOpenPath(request)),
                          onOpenDocuments: () => onTabChanged(
                            YorksV1ProjectWorkspaceTab.documents,
                          ),
                        ),
                      YorksV1ProjectWorkspaceTab.boq => YorksV1BoqGroupsScreen(
                        projectId: project.id,
                        embedded: true,
                      ),
                      YorksV1ProjectWorkspaceTab.requests =>
                        const SizedBox.shrink(),
                      YorksV1ProjectWorkspaceTab.accounts => _LinkedRecordCard(
                        icon: Icons.account_balance_wallet_outlined,
                        title: YorksV1ProjectStrings.accounts,
                        action: YorksV1ProjectStrings.accounts,
                        onOpen: () => context.go(
                          RoutePaths.yorksV1ProjectAccountsOverviewPath(
                            project.id,
                          ),
                        ),
                      ),
                      YorksV1ProjectWorkspaceTab.documents =>
                        const SizedBox.shrink(),
                      YorksV1ProjectWorkspaceTab.materialMovement =>
                        _ProjectMaterialMovementPanel(
                          projectId: project.id,
                          language: language,
                        ),
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MobileProjectDetails extends ConsumerWidget {
  const _MobileProjectDetails({
    required this.item,
    required this.scopes,
    required this.selected,
    required this.onSelected,
    required this.onActivate,
    required this.showNewRequest,
    required this.onNewRequest,
    required this.showEdit,
    required this.onEdit,
    required this.showArchive,
    required this.onArchive,
  });

  final YorksV1ProjectPortfolioItem item;
  final AsyncValue<List<YorksV1MaterialRequestScopeOption>> scopes;
  final _MobileProjectDetailTab selected;
  final ValueChanged<_MobileProjectDetailTab> onSelected;
  final VoidCallback? onActivate;
  final bool showNewRequest;
  final VoidCallback? onNewRequest;
  final bool showEdit;
  final VoidCallback? onEdit;
  final bool showArchive;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(yorksV1CurrentRoleProvider);
    final authUserId = ref.watch(yorksV1AuthUserIdProvider);
    final hasProjectEngineerMembership =
        authUserId != null &&
        item.activeMembers.any(
          (member) =>
              member.memberAuthUserId == authUserId &&
              member.projectRole ==
                  YorksV1ProjectMembershipRole.projectEngineer,
        );
    final canManage =
        role == YorksV1Role.admin ||
        (role?.isGlobalProjectEngineer ?? false) ||
        hasProjectEngineerMembership;
    final directory = canManage
        ? ref.watch(yorksV1ActiveProjectTeamDirectoryProvider)
        : null;
    return ColoredBox(
      color: AppColors.mobileSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MobileProjectDetailTabs(selected: selected, onSelected: onSelected),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
              child: switch (selected) {
                _MobileProjectDetailTab.information =>
                  _MobileProjectInformation(
                    item: item,
                    onActivate: onActivate,
                    showNewRequest: showNewRequest,
                    onNewRequest: onNewRequest,
                    showEdit: showEdit,
                    onEdit: onEdit,
                    showArchive: showArchive,
                    onArchive: onArchive,
                  ),
                _MobileProjectDetailTab.team => _MobileProjectTeam(
                  item: item,
                  authUserId: authUserId,
                  directory: directory,
                  canManage: canManage,
                  onRetryDirectory: () =>
                      ref.invalidate(yorksV1ActiveProjectTeamDirectoryProvider),
                ),
                _MobileProjectDetailTab.buildings => _MobileProjectBuildings(
                  item: item,
                  scopes: scopes,
                ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileProjectDetailTabs extends StatelessWidget {
  const _MobileProjectDetailTabs({
    required this.selected,
    required this.onSelected,
  });

  final _MobileProjectDetailTab selected;
  final ValueChanged<_MobileProjectDetailTab> onSelected;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      children: [
        for (final tab in _MobileProjectDetailTab.values)
          Expanded(
            child: Semantics(
              selected: selected == tab,
              button: true,
              child: InkWell(
                key: ValueKey('yorks-mobile-project-detail-${tab.name}'),
                onTap: () => onSelected(tab),
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: AppSpacing.minTapTarget,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        width: 2,
                        color: selected == tab
                            ? AppColors.blue
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Text(
                    switch (tab) {
                      _MobileProjectDetailTab.information =>
                        YorksV1ProjectStrings.information.primary,
                      _MobileProjectDetailTab.team =>
                        YorksV1ProjectStrings.team.primary,
                      _MobileProjectDetailTab.buildings =>
                        YorksV1ProjectStrings.buildings.primary,
                    },
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelMedium.copyWith(
                      color: selected == tab ? AppColors.navy : AppColors.muted,
                      fontWeight: selected == tab
                          ? FontWeight.w800
                          : FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _MobileProjectInformation extends StatelessWidget {
  const _MobileProjectInformation({
    required this.item,
    required this.onActivate,
    required this.showNewRequest,
    required this.onNewRequest,
    required this.showEdit,
    required this.onEdit,
    required this.showArchive,
    required this.onArchive,
  });

  final YorksV1ProjectPortfolioItem item;
  final VoidCallback? onActivate;
  final bool showNewRequest;
  final VoidCallback? onNewRequest;
  final bool showEdit;
  final VoidCallback? onEdit;
  final bool showArchive;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    final project = item.project;
    final notProvided = YorksV1ProjectStrings.notProvided.primary;
    final client =
        _safeVisibleText(project.clientName) ??
        _safeVisibleText(item.clientName) ??
        notProvided;
    final rows = <_MobileProjectFact>[
      _MobileProjectFact(
        label: YorksV1ProjectStrings.yorksReference.primary,
        value: project.reference,
      ),
      _MobileProjectFact(
        label: YorksV1ProjectStrings.projectName.primary,
        value: project.name,
      ),
      _MobileProjectFact(
        label: YorksV1ProjectStrings.client.primary,
        value: client,
      ),
      _MobileProjectFact(
        label: YorksV1ProjectStrings.jobOrContractReference.primary,
        value: _safeVisibleText(project.jobOrContractReference) ?? notProvided,
      ),
      _MobileProjectFact(
        label: YorksV1ProjectStrings.siteLocation.primary,
        value: _safeVisibleText(project.siteLocation) ?? notProvided,
      ),
      _MobileProjectFact(
        label: YorksV1ProjectStrings.state.primary,
        value: YorksV1ProjectStrings.stateLabel(project.state).primary,
      ),
    ];
    final actions = <Widget>[
      if (onActivate != null)
        OutlinedButton.icon(
          onPressed: onActivate,
          icon: const Icon(Icons.play_circle_outline_rounded),
          label: Text(YorksV1ProjectStrings.activateProject.primary),
        ),
      if (showNewRequest)
        FilledButton.icon(
          onPressed: onNewRequest,
          icon: const Icon(Icons.add_rounded),
          label: Text(YorksV1MaterialRequestStrings.newRequest.primary),
        ),
      if (showEdit)
        OutlinedButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
          label: Text(YorksV1ProjectStrings.editProject.primary),
        ),
      if (showArchive)
        TextButton.icon(
          onPressed: onArchive,
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          icon: const Icon(Icons.archive_outlined),
          label: Text(YorksV1ProjectStrings.safeDeleteProject.primary),
        ),
    ];
    return _MobileProjectDetailCard(
      title: YorksV1ProjectStrings.projectInformation.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in rows)
            _MobileProjectFactRow(label: row.label, value: row.value),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (var index = 0; index < actions.length; index++) ...[
              SizedBox(height: AppSpacing.minTapTarget, child: actions[index]),
              if (index != actions.length - 1) const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

class _MobileProjectTeam extends StatelessWidget {
  const _MobileProjectTeam({
    required this.item,
    required this.authUserId,
    required this.directory,
    required this.canManage,
    required this.onRetryDirectory,
  });

  final YorksV1ProjectPortfolioItem item;
  final String? authUserId;
  final AsyncValue<List<YorksV1ProjectTeamDirectoryMember>>? directory;
  final bool canManage;
  final VoidCallback onRetryDirectory;

  @override
  Widget build(BuildContext context) {
    final directoryNames = <String, String>{
      for (final member
          in directory?.valueOrNull ??
              const <YorksV1ProjectTeamDirectoryMember>[])
        member.authUserId: member.displayName,
    };
    final projectEngineers = item.activeMembers
        .where(
          (member) =>
              member.projectRole ==
              YorksV1ProjectMembershipRole.projectEngineer,
        )
        .toList(growable: false);
    final siteEngineers = item.activeMembers
        .where(
          (member) =>
              member.projectRole == YorksV1ProjectMembershipRole.siteEngineer,
        )
        .toList(growable: false);
    VoidCallback? manage;
    if (canManage) {
      manage = () => showDialog<void>(
        context: context,
        builder: (_) => _ProjectTeamAssignmentDialog(item: item),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (directory?.isLoading == true) ...[
          _MobileProjectStateCard(
            icon: Icons.sync_rounded,
            copy: YorksV1ProjectStrings.loadingTeamDirectory,
          ),
          const SizedBox(height: 11),
        ] else if (directory?.hasError == true) ...[
          _MobileProjectStateCard(
            icon: Icons.cloud_off_outlined,
            copy: YorksV1ProjectStrings.teamDirectoryUnavailable,
            actionLabel: YorksV1ProjectStrings.retry.primary,
            onAction: onRetryDirectory,
          ),
          const SizedBox(height: 11),
        ],
        _MobileProjectTeamCard(
          title: YorksV1ProjectStrings.projectEngineers.primary,
          members: projectEngineers,
          directoryNames: directoryNames,
          authUserId: authUserId,
          onManage: manage,
        ),
        const SizedBox(height: 11),
        _MobileProjectTeamCard(
          title: YorksV1ProjectStrings.siteEngineers.primary,
          members: siteEngineers,
          directoryNames: directoryNames,
          authUserId: authUserId,
          onManage: manage,
          showHistoryNote: true,
        ),
      ],
    );
  }
}

class _MobileProjectTeamCard extends StatelessWidget {
  const _MobileProjectTeamCard({
    required this.title,
    required this.members,
    required this.directoryNames,
    required this.authUserId,
    required this.onManage,
    this.showHistoryNote = false,
  });

  final String title;
  final List<YorksV1ProjectMember> members;
  final Map<String, String> directoryNames;
  final String? authUserId;
  final VoidCallback? onManage;
  final bool showHistoryNote;

  @override
  Widget build(BuildContext context) => _MobileProjectDetailCard(
    title: title,
    action: onManage == null
        ? null
        : TextButton(
            onPressed: onManage,
            child: Text(YorksV1ProjectStrings.manage.primary),
          ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (members.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              YorksV1ProjectStrings.noActiveAssignments.primary,
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
          )
        else
          for (var index = 0; index < members.length; index++) ...[
            _MobileProjectPerson(
              member: members[index],
              displayName: _safeTeamMemberName(
                members[index],
                directoryNames[members[index].memberAuthUserId],
              ),
              isCurrentUser:
                  authUserId != null &&
                  members[index].memberAuthUserId == authUserId,
            ),
            if (index != members.length - 1) const SizedBox(height: 8),
          ],
        if (showHistoryNote) ...[
          const SizedBox(height: 9),
          Text(
            YorksV1ProjectStrings.membershipHistoryRetained.primary,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
        ],
      ],
    ),
  );
}

class _MobileProjectPerson extends StatelessWidget {
  const _MobileProjectPerson({
    required this.member,
    required this.displayName,
    required this.isCurrentUser,
  });

  final YorksV1ProjectMember member;
  final String displayName;
  final bool isCurrentUser;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat.yMMMd().format(member.effectiveFrom.toLocal());
    final role = switch (member.projectRole) {
      YorksV1ProjectMembershipRole.projectEngineer =>
        YorksV1ProjectStrings.projectEngineerRole.primary,
      YorksV1ProjectMembershipRole.siteEngineer =>
        YorksV1ProjectStrings.siteEngineerRole.primary,
    };
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: AppSpacing.minTapTarget,
            height: AppSpacing.minTapTarget,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.blueContainerStrong,
              shape: BoxShape.circle,
            ),
            child: Text(
              _memberInitials(displayName),
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.navy,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$role · ${YorksV1ProjectStrings.assigned.primary.replaceFirst('{date}', date)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _MobilePersonStatus(isCurrentUser: isCurrentUser),
        ],
      ),
    );
  }
}

class _MobilePersonStatus extends StatelessWidget {
  const _MobilePersonStatus({required this.isCurrentUser});

  final bool isCurrentUser;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 26),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: isCurrentUser
          ? AppColors.blueContainer
          : AppColors.successContainer,
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
    ),
    child: Text(
      (isCurrentUser ? YorksV1ProjectStrings.you : YorksV1ProjectStrings.active)
          .primary,
      style: AppTypography.labelSmall.copyWith(
        color: isCurrentUser ? AppColors.blue : AppColors.success,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _MobileProjectBuildings extends StatelessWidget {
  const _MobileProjectBuildings({required this.item, required this.scopes});

  final YorksV1ProjectPortfolioItem item;
  final AsyncValue<List<YorksV1MaterialRequestScopeOption>> scopes;

  @override
  Widget build(BuildContext context) {
    if (item.buildings.isNotEmpty) {
      return _MobileProjectDetailCard(
        title: YorksV1ProjectStrings.buildings.primary,
        child: Column(
          children: [
            for (var index = 0; index < item.buildings.length; index++) ...[
              _MobileBuildingRow.fromBuilding(item.buildings[index]),
              if (index != item.buildings.length - 1) const SizedBox(height: 8),
            ],
          ],
        ),
      );
    }
    return scopes.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _MobileProjectStateCard(
        icon: Icons.cloud_off_outlined,
        copy: YorksV1ProjectStrings.recordsUnavailable,
      ),
      data: (items) => _MobileProjectDetailCard(
        title: YorksV1ProjectStrings.buildings.primary,
        child: items.isEmpty
            ? Text(
                YorksV1ProjectStrings.noBuildingsAdded.primary,
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              )
            : Column(
                children: [
                  for (var index = 0; index < items.length; index++) ...[
                    _MobileBuildingRow.fromScope(items[index]),
                    if (index != items.length - 1) const SizedBox(height: 8),
                  ],
                ],
              ),
      ),
    );
  }
}

class _MobileBuildingRow extends StatelessWidget {
  const _MobileBuildingRow({
    required this.title,
    required this.subtitle,
    required this.common,
  });

  factory _MobileBuildingRow.fromBuilding(
    YorksV1ProjectBuildingInput building,
  ) => _MobileBuildingRow(
    title: building.name,
    subtitle: [
      if (building.code.trim().isNotEmpty) building.code.trim(),
      ?_safeVisibleText(building.deliveryAddress),
    ].join(' · '),
    common: false,
  );

  factory _MobileBuildingRow.fromScope(
    YorksV1MaterialRequestScopeOption scope,
  ) => _MobileBuildingRow(
    title: scope.name,
    subtitle: _safeVisibleText(scope.deliveryAddress) ?? '',
    common: scope.isCommon,
  );

  final String title;
  final String subtitle;
  final bool common;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 58),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Container(
          width: AppSpacing.minTapTarget,
          height: AppSpacing.minTapTarget,
          decoration: BoxDecoration(
            color: common
                ? AppColors.warningContainer
                : AppColors.blueContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            common ? Icons.hub_outlined : Icons.business_outlined,
            color: common ? AppColors.warning : AppColors.blue,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.labelLarge.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _MobileProjectDetailCard extends StatelessWidget {
  const _MobileProjectDetailCard({
    required this.title,
    required this.child,
    this.action,
  });

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(15),
      boxShadow: const [
        BoxShadow(
          color: AppColors.shadow,
          blurRadius: 20,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTypography.titleLarge.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ?action,
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class _MobileProjectFact {
  const _MobileProjectFact({required this.label, required this.value});

  final String label;
  final String value;
}

class _MobileProjectFactRow extends StatelessWidget {
  const _MobileProjectFactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.muted,
            letterSpacing: .7,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _MobileProjectWorkspace extends StatelessWidget {
  const _MobileProjectWorkspace({
    required this.item,
    required this.language,
    required this.tab,
    required this.requests,
    required this.scopes,
    required this.groups,
    required this.documents,
    required this.actorRole,
    required this.activeMember,
    required this.canActAsProjectEngineer,
    required this.showAccounts,
    required this.initialAccountsTab,
    required this.showNewRequest,
    required this.onNewRequest,
    required this.onTabChanged,
    required this.onOpenRequests,
    required this.onOpenRequest,
    required this.onRetryRequests,
  });

  final YorksV1ProjectPortfolioItem item;
  final AppLanguage language;
  final YorksV1ProjectWorkspaceTab tab;
  final AsyncValue<List<YorksV1MaterialRequest>> requests;
  final AsyncValue<List<YorksV1MaterialRequestScopeOption>> scopes;
  final AsyncValue<List<YorksV1BoqGroup>> groups;
  final AsyncValue<YorksV1DocumentWorkspace> documents;
  final YorksV1Role? actorRole;
  final bool activeMember;
  final bool canActAsProjectEngineer;
  final bool showAccounts;
  final YorksProjectAccountsTab initialAccountsTab;
  final bool showNewRequest;
  final VoidCallback? onNewRequest;
  final ValueChanged<YorksV1ProjectWorkspaceTab> onTabChanged;
  final VoidCallback onOpenRequests;
  final ValueChanged<YorksV1MaterialRequest> onOpenRequest;
  final VoidCallback onRetryRequests;

  @override
  Widget build(BuildContext context) {
    final tabs = _MobileProjectWorkspaceTabs(
      selected: tab,
      onSelected: onTabChanged,
      showAccounts: showAccounts,
    );
    if (tab == YorksV1ProjectWorkspaceTab.boq) {
      return ColoredBox(
        color: AppColors.mobileSurface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tabs,
            Expanded(
              child: YorksV1BoqGroupsScreen(
                projectId: item.project.id,
                embedded: true,
              ),
            ),
          ],
        ),
      );
    }
    if (tab == YorksV1ProjectWorkspaceTab.accounts) {
      return ColoredBox(
        color: AppColors.mobileSurface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tabs,
            Expanded(
              child: YorksProjectAccountsScreen(
                projectId: item.project.id,
                initialTab: initialAccountsTab,
              ),
            ),
          ],
        ),
      );
    }
    if (tab == YorksV1ProjectWorkspaceTab.requests ||
        tab == YorksV1ProjectWorkspaceTab.documents) {
      return ColoredBox(
        color: AppColors.mobileSurface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tabs,
            Expanded(
              child: tab == YorksV1ProjectWorkspaceTab.requests
                  ? YorksV1MaterialRequestsScreen(
                      projectId: item.project.id,
                      embedded: true,
                    )
                  : YorksV1DocumentsScreen(
                      projectId: item.project.id,
                      embedded: true,
                    ),
            ),
          ],
        ),
      );
    }
    return ColoredBox(
      color: AppColors.mobileSurface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          YorksMobileUi.horizontalPadding,
          YorksMobileUi.horizontalPadding,
          YorksMobileUi.horizontalPadding,
          28,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (tab == YorksV1ProjectWorkspaceTab.overview) ...[
              _MobileProjectHero(item: item, scopes: scopes),
              const SizedBox(height: 10),
              if (showNewRequest) ...[
                SizedBox(
                  height: AppSpacing.minTapTarget,
                  child: FilledButton.icon(
                    onPressed: onNewRequest,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(
                      YorksV1MaterialRequestStrings.newRequest.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
            tabs,
            const SizedBox(height: 13),
            switch (tab) {
              YorksV1ProjectWorkspaceTab.overview => _MobileProjectOverview(
                requests: requests,
                scopes: scopes,
                groups: groups,
                documents: documents,
                actorRole: actorRole,
                activeMember: activeMember,
                canActAsProjectEngineer: canActAsProjectEngineer,
                onOpenRequests: onOpenRequests,
                onOpenRequest: onOpenRequest,
                onRetryRequests: onRetryRequests,
              ),
              YorksV1ProjectWorkspaceTab.requests => const SizedBox.shrink(),
              YorksV1ProjectWorkspaceTab.accounts => _LinkedRecordCard(
                icon: Icons.account_balance_wallet_outlined,
                title: YorksV1ProjectStrings.accounts,
                action: YorksV1ProjectStrings.accounts,
                onOpen: () => context.go(
                  RoutePaths.yorksV1ProjectAccountsOverviewPath(
                    item.project.id,
                  ),
                ),
              ),
              YorksV1ProjectWorkspaceTab.documents => const SizedBox.shrink(),
              YorksV1ProjectWorkspaceTab.materialMovement =>
                _ProjectMaterialMovementPanel(
                  projectId: item.project.id,
                  language: language,
                ),
              YorksV1ProjectWorkspaceTab.boq => const SizedBox.shrink(),
            },
          ],
        ),
      ),
    );
  }
}

class _MobileProjectHero extends StatelessWidget {
  const _MobileProjectHero({required this.item, required this.scopes});

  final YorksV1ProjectPortfolioItem item;
  final AsyncValue<List<YorksV1MaterialRequestScopeOption>> scopes;

  @override
  Widget build(BuildContext context) {
    final project = item.project;
    final loadedScopes = scopes.valueOrNull;
    final buildingCount = loadedScopes == null
        ? item.activeBuildingCount
        : loadedScopes.where((scope) => !scope.isCommon).length;
    final location = _safeVisibleText(project.siteLocation);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  project.reference.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _MobileProjectStatus(state: project.state),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            project.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.headlineSmall.copyWith(
              color: AppColors.navy,
              fontSize: 22,
              height: 1.18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 16,
                color: AppColors.muted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  [
                    ?location,
                    '$buildingCount ${YorksV1ProjectStrings.buildings.primary}',
                  ].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MobileProjectStatus extends StatelessWidget {
  const _MobileProjectStatus({required this.state});

  final YorksV1ProjectLifecycle state;

  @override
  Widget build(BuildContext context) {
    final success =
        state == YorksV1ProjectLifecycle.active ||
        state == YorksV1ProjectLifecycle.completed;
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: success
            ? AppColors.successContainer
            : AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        YorksV1ProjectStrings.stateLabel(state).primary,
        style: AppTypography.labelSmall.copyWith(
          color: success ? AppColors.success : AppColors.inkSecondary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MobileProjectWorkspaceTabs extends StatelessWidget {
  const _MobileProjectWorkspaceTabs({
    required this.selected,
    required this.onSelected,
    required this.showAccounts,
  });

  final YorksV1ProjectWorkspaceTab selected;
  final ValueChanged<YorksV1ProjectWorkspaceTab> onSelected;
  final bool showAccounts;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tab in YorksV1ProjectWorkspaceTab.values)
            if (tab != YorksV1ProjectWorkspaceTab.accounts || showAccounts)
              SizedBox(
                width: tab == YorksV1ProjectWorkspaceTab.materialMovement
                    ? 132
                    : 92,
                child: Semantics(
                  button: true,
                  selected: selected == tab,
                  child: InkWell(
                    key: ValueKey('yorks-mobile-project-tab-${tab.name}'),
                    onTap: () => onSelected(tab),
                    child: Container(
                      constraints: const BoxConstraints(
                        minHeight: AppSpacing.minTapTarget,
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            width: 2,
                            color: selected == tab
                                ? AppColors.blue
                                : Colors.transparent,
                          ),
                        ),
                      ),
                      child: Text(
                        _mobileProjectTabLabel(tab),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelSmall.copyWith(
                          color: selected == tab
                              ? AppColors.navy
                              : AppColors.muted,
                          fontWeight: selected == tab
                              ? FontWeight.w800
                              : FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    ),
  );
}

String _mobileProjectTabLabel(YorksV1ProjectWorkspaceTab tab) => switch (tab) {
  YorksV1ProjectWorkspaceTab.overview => YorksV1ProjectStrings.overview.primary,
  YorksV1ProjectWorkspaceTab.boq => YorksV1ProjectStrings.boq.primary,
  YorksV1ProjectWorkspaceTab.requests => YorksV1ProjectStrings.requests.primary,
  YorksV1ProjectWorkspaceTab.accounts => YorksV1ProjectStrings.accounts.primary,
  YorksV1ProjectWorkspaceTab.documents => YorksV1ProjectStrings.docs.primary,
  YorksV1ProjectWorkspaceTab.materialMovement =>
    YorksV1ProjectStrings.materialMovement.primary,
};

class _MobileProjectOverview extends StatelessWidget {
  const _MobileProjectOverview({
    required this.requests,
    required this.scopes,
    required this.groups,
    required this.documents,
    required this.actorRole,
    required this.activeMember,
    required this.canActAsProjectEngineer,
    required this.onOpenRequests,
    required this.onOpenRequest,
    required this.onRetryRequests,
  });

  final AsyncValue<List<YorksV1MaterialRequest>> requests;
  final AsyncValue<List<YorksV1MaterialRequestScopeOption>> scopes;
  final AsyncValue<List<YorksV1BoqGroup>> groups;
  final AsyncValue<YorksV1DocumentWorkspace> documents;
  final YorksV1Role? actorRole;
  final bool activeMember;
  final bool canActAsProjectEngineer;
  final VoidCallback onOpenRequests;
  final ValueChanged<YorksV1MaterialRequest> onOpenRequest;
  final VoidCallback onRetryRequests;

  @override
  Widget build(BuildContext context) {
    final requestItems = requests.valueOrNull;
    final approved = requestItems
        ?.where(
          (request) => request.state == YorksV1MaterialRequestState.approved,
        )
        .length;
    final pending = requestItems
        ?.where(
          (request) =>
              request.state == YorksV1MaterialRequestState.awaitingApproval ||
              request.state ==
                  YorksV1MaterialRequestState.awaitingRequestApproval,
        )
        .length;
    final inProgress = requestItems
        ?.where((request) => _isRequestInProgress(request.state))
        .length;
    final attentionItems =
        requestItems
            ?.where(
              (request) => _requestNeedsAttention(
                request,
                actorRole: actorRole,
                activeMember: activeMember,
                canActAsProjectEngineer: canActAsProjectEngineer,
              ),
            )
            .take(2)
            .toList(growable: false) ??
        const <YorksV1MaterialRequest>[];
    final recentItems = requestItems == null
        ? const <YorksV1MaterialRequest>[]
        : ([...requestItems]..sort(
                (left, right) => right.updatedAt.compareTo(left.updatedAt),
              ))
              .take(3)
              .toList(growable: false);
    final recordUnavailable =
        groups.hasError || scopes.hasError || documents.hasError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (requests.isLoading)
          const LinearProgressIndicator(minHeight: 2)
        else if (requests.hasError)
          _MobileProjectStateCard(
            icon: Icons.cloud_off_outlined,
            copy: YorksV1ProjectStrings.requestsUnavailable,
            actionLabel: YorksV1ProjectStrings.retry.primary,
            onAction: onRetryRequests,
          ),
        if (!requests.hasError) ...[
          _MobileProjectKpiGrid(
            entries: [
              _MobileProjectKpi(
                label: YorksV1ProjectStrings.materialRequests.primary,
                value: requestItems == null ? '—' : '${requestItems.length}',
              ),
              _MobileProjectKpi(
                label: YorksV1ProjectStrings.approvedRequests.primary,
                value: approved == null ? '—' : '$approved',
              ),
              _MobileProjectKpi(
                label: YorksV1ProjectStrings.pendingApproval.primary,
                value: pending == null ? '—' : '$pending',
              ),
              _MobileProjectKpi(
                label: YorksV1ProjectStrings.inProgress.primary,
                value: inProgress == null ? '—' : '$inProgress',
              ),
            ],
          ),
          const SizedBox(height: 15),
          _MobileProjectSectionHeader(
            title: YorksV1ProjectStrings.needsAttention.primary,
            onViewAll: onOpenRequests,
          ),
          const SizedBox(height: 8),
          if (requestItems == null)
            const _MobileProjectListLoading()
          else if (attentionItems.isEmpty)
            _MobileProjectStateCard(
              icon: Icons.check_rounded,
              copy: YorksV1ProjectStrings.noAttentionRequired,
            )
          else
            _MobileProjectRequestList(
              items: attentionItems,
              onTap: onOpenRequest,
              showOwner: true,
            ),
          const SizedBox(height: 15),
          _MobileProjectSectionHeader(
            title: YorksV1ProjectStrings.recentMaterialRequests.primary,
            onViewAll: onOpenRequests,
          ),
          const SizedBox(height: 8),
          if (requestItems == null)
            const _MobileProjectListLoading()
          else if (recentItems.isEmpty)
            _MobileProjectStateCard(
              icon: Icons.history_rounded,
              copy: YorksV1ProjectStrings.noRecentRequests,
            )
          else
            _MobileProjectRequestList(items: recentItems, onTap: onOpenRequest),
        ],
        const SizedBox(height: 15),
        Text(
          YorksV1ProjectStrings.projectRecords.primary,
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        _MobileProjectRecordGrid(
          entries: [
            _MobileProjectKpi(
              label: YorksV1ProjectStrings.boqGroups.primary,
              value: _asyncCount(groups, (value) => value.length),
            ),
            _MobileProjectKpi(
              label: YorksV1ProjectStrings.buildings.primary,
              value: _asyncCount(
                scopes,
                (value) => value.where((scope) => !scope.isCommon).length,
              ),
            ),
            _MobileProjectKpi(
              label: YorksV1ProjectStrings.documents.primary,
              value: _asyncCount(documents, (value) => value.documents.length),
            ),
          ],
        ),
        if (recordUnavailable) ...[
          const SizedBox(height: 8),
          Text(
            YorksV1ProjectStrings.recordsUnavailable.primary,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
        ],
      ],
    );
  }
}

class _MobileProjectKpi {
  const _MobileProjectKpi({required this.label, required this.value});

  final String label;
  final String value;
}

class _MobileProjectKpiGrid extends StatelessWidget {
  const _MobileProjectKpiGrid({required this.entries});

  final List<_MobileProjectKpi> entries;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final tileHeight = 82.0 + ((textScale - 1) * 32).clamp(0.0, 48.0);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: entries.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 9,
        mainAxisSpacing: 9,
        mainAxisExtent: tileHeight,
      ),
      itemBuilder: (context, index) =>
          _MobileProjectKpiTile(entry: entries[index], large: true),
    );
  }
}

class _MobileProjectRecordGrid extends StatelessWidget {
  const _MobileProjectRecordGrid({required this.entries});

  final List<_MobileProjectKpi> entries;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var index = 0; index < entries.length; index++) ...[
        Expanded(child: _MobileProjectKpiTile(entry: entries[index])),
        if (index != entries.length - 1) const SizedBox(width: 7),
      ],
    ],
  );
}

class _MobileProjectKpiTile extends StatelessWidget {
  const _MobileProjectKpiTile({required this.entry, this.large = false});

  final _MobileProjectKpi entry;
  final bool large;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(minHeight: large ? 82 : 66),
    padding: EdgeInsets.symmetric(
      horizontal: large ? 12 : 9,
      vertical: large ? 10 : 8,
    ),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLow,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          entry.label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.muted,
            fontSize: large ? 9 : 8,
            letterSpacing: .75,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          entry.value,
          style:
              (large ? AppTypography.headlineMedium : AppTypography.titleMedium)
                  .copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _MobileProjectSectionHeader extends StatelessWidget {
  const _MobileProjectSectionHeader({
    required this.title,
    required this.onViewAll,
  });

  final String title;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      TextButton(onPressed: onViewAll, child: Text(AppStrings.viewAll.primary)),
    ],
  );
}

class _MobileProjectRequestList extends StatelessWidget {
  const _MobileProjectRequestList({
    required this.items,
    required this.onTap,
    this.showOwner = false,
  });

  final List<YorksV1MaterialRequest> items;
  final ValueChanged<YorksV1MaterialRequest> onTap;
  final bool showOwner;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceContainerLowest,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: AppColors.line),
      borderRadius: BorderRadius.circular(15),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var index = 0; index < items.length; index++) ...[
          _MobileProjectRequestRow(
            request: items[index],
            onTap: () => onTap(items[index]),
            showOwner: showOwner,
          ),
          if (index != items.length - 1)
            const Divider(height: 1, color: AppColors.line),
        ],
      ],
    ),
  );
}

class _MobileProjectRequestRow extends StatelessWidget {
  const _MobileProjectRequestRow({
    required this.request,
    required this.onTap,
    required this.showOwner,
  });

  final YorksV1MaterialRequest request;
  final VoidCallback onTap;
  final bool showOwner;

  @override
  Widget build(BuildContext context) {
    final owner = YorksV1ProjectStrings.roleLabel(
      request.currentActionOwnerRole,
    ).primary;
    return InkWell(
      key: ValueKey('mobile-project-request-${request.id}'),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 70),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: AppSpacing.minTapTarget,
                height: AppSpacing.minTapTarget,
                decoration: BoxDecoration(
                  color: AppColors.blueContainer.withValues(alpha: .65),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.assignment_outlined,
                  size: 20,
                  color: AppColors.blue,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      request.requestNumber ??
                          YorksV1MaterialRequestStrings.draft.primary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${request.scopeName} · ${request.lines.length} ${YorksV1MaterialRequestStrings.items.primary.toLowerCase()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      showOwner
                          ? '${YorksV1ProjectStrings.currentOwner.primary}: $owner'
                          : DateFormat.yMMMd().add_jm().format(
                              request.updatedAt.toLocal(),
                            ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.mutedLight,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _MobileRequestStatePill(state: request.state),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileRequestStatePill extends StatelessWidget {
  const _MobileRequestStatePill({required this.state});

  final YorksV1MaterialRequestState state;

  @override
  Widget build(BuildContext context) {
    final attention =
        state == YorksV1MaterialRequestState.awaitingApproval ||
        state == YorksV1MaterialRequestState.awaitingRequestApproval;
    final label = yorksV1MaterialRequestStateCopy(state).primary;
    return Tooltip(
      message: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 25, maxWidth: 112),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: attention
              ? AppColors.warningContainer
              : AppColors.blueContainer,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelSmall.copyWith(
            color: attention ? AppColors.warning : AppColors.blue,
            fontSize: 8,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _MobileProjectStateCard extends StatelessWidget {
  const _MobileProjectStateCard({
    required this.icon,
    required this.copy,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final TranslatableString copy;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 82),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Row(
      children: [
        Container(
          width: AppSpacing.minTapTarget,
          height: AppSpacing.minTapTarget,
          decoration: BoxDecoration(
            color: AppColors.blueContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.blue),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            copy.primary,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(width: 8),
          SizedBox(
            height: AppSpacing.minTapTarget,
            child: TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ),
        ],
      ],
    ),
  );
}

class _MobileProjectListLoading extends StatelessWidget {
  const _MobileProjectListLoading();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 82,
    child: Center(child: CircularProgressIndicator()),
  );
}

bool _isRequestInProgress(YorksV1MaterialRequestState state) => switch (state) {
  YorksV1MaterialRequestState.submitted ||
  YorksV1MaterialRequestState.arranging ||
  YorksV1MaterialRequestState.partiallyDispatched ||
  YorksV1MaterialRequestState.dispatched ||
  YorksV1MaterialRequestState.partiallyReceived => true,
  _ => false,
};

bool _requestNeedsAttention(
  YorksV1MaterialRequest request, {
  required YorksV1Role? actorRole,
  required bool activeMember,
  required bool canActAsProjectEngineer,
}) {
  final owner = request.currentActionOwnerRole?.trim();
  return switch (owner) {
    'project_engineer' => canActAsProjectEngineer,
    'senior_mechanical_engineer' =>
      actorRole == YorksV1Role.admin ||
          actorRole == YorksV1Role.seniorMechanicalEngineer,
    'project_manager' =>
      actorRole == YorksV1Role.admin || actorRole == YorksV1Role.projectManager,
    'workshop_in_charge' =>
      actorRole == YorksV1Role.admin ||
          actorRole == YorksV1Role.workshopInCharge,
    'document_controller' =>
      actorRole == YorksV1Role.admin ||
          actorRole == YorksV1Role.documentController,
    'site_engineer' =>
      actorRole == YorksV1Role.admin ||
          (activeMember &&
              (actorRole == YorksV1Role.siteEngineer ||
                  actorRole == YorksV1Role.projectEngineer ||
                  (actorRole?.isGlobalProjectEngineer ?? false))),
    'procurement' =>
      actorRole == YorksV1Role.admin || actorRole == YorksV1Role.procurement,
    'admin' => actorRole == YorksV1Role.admin,
    _ => false,
  };
}

String _asyncCount<T>(AsyncValue<T> value, int Function(T value) count) {
  final data = value.valueOrNull;
  return data == null ? '—' : '${count(data)}';
}

class _ProjectR35Hero extends StatelessWidget {
  const _ProjectR35Hero({
    required this.project,
    required this.selected,
    required this.onSelected,
    required this.showAccounts,
    required this.onActivate,
    required this.showNewRequest,
    required this.onNewRequest,
    required this.showEdit,
    required this.onEdit,
    required this.showArchive,
    required this.onArchive,
    required this.onOpenChat,
  });

  final YorksV1Project project;
  final YorksV1ProjectWorkspaceTab selected;
  final ValueChanged<YorksV1ProjectWorkspaceTab> onSelected;
  final bool showAccounts;
  final VoidCallback? onActivate;
  final bool showNewRequest;
  final VoidCallback? onNewRequest;
  final bool showEdit;
  final VoidCallback? onEdit;
  final bool showArchive;
  final VoidCallback? onArchive;
  final VoidCallback? onOpenChat;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.xl,
      AppSpacing.lg,
      AppSpacing.xl,
      0,
    ),
    decoration: const BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 860;
            final copy = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project.reference.toUpperCase(),
                  style: AppTypography.eyebrow.copyWith(
                    color: AppColors.muted,
                    letterSpacing: .6,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  project.name,
                  style: AppTypography.headlineMedium.copyWith(
                    color: AppColors.navy,
                    height: 1.08,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (project.siteLocation?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 17,
                        color: AppColors.muted,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          project.siteLocation!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            );
            final actions = Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (showNewRequest)
                  SizedBox(
                    height: AppSpacing.minTapTarget,
                    child: FilledButton.icon(
                      onPressed: onNewRequest,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(
                        YorksV1MaterialRequestStrings.newRequest.primary,
                      ),
                    ),
                  ),
                if (onOpenChat != null)
                  SizedBox(
                    height: AppSpacing.minTapTarget,
                    child: OutlinedButton.icon(
                      onPressed: onOpenChat,
                      icon: const Icon(Icons.forum_outlined),
                      label: Text(YorksV1TeamChatStrings.openChat.primary),
                    ),
                  ),
                if (onActivate != null)
                  SizedBox(
                    height: AppSpacing.minTapTarget,
                    child: OutlinedButton.icon(
                      onPressed: onActivate,
                      icon: const Icon(Icons.play_circle_outline_rounded),
                      label: Text(
                        YorksV1ProjectStrings.activateProject.primary,
                      ),
                    ),
                  ),
                if (showEdit)
                  SizedBox(
                    height: AppSpacing.minTapTarget,
                    child: OutlinedButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(YorksV1ProjectStrings.editProject.primary),
                    ),
                  ),
                if (showArchive)
                  SizedBox(
                    width: AppSpacing.minTapTarget,
                    height: AppSpacing.minTapTarget,
                    child: PopupMenuButton<String>(
                      tooltip: YorksV1ProjectStrings.safeDeleteProject.primary,
                      icon: const Icon(Icons.more_horiz_rounded),
                      onSelected: (_) => onArchive?.call(),
                      itemBuilder: (_) => [
                        PopupMenuItem<String>(
                          value: 'archive',
                          child: Row(
                            children: [
                              const Icon(
                                Icons.archive_outlined,
                                color: AppColors.error,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                YorksV1ProjectStrings.safeDeleteProject.primary,
                                style: const TextStyle(color: AppColors.error),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
            return stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      copy,
                      const SizedBox(height: AppSpacing.md),
                      actions,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: copy),
                      actions,
                    ],
                  );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        _ProjectWorkspaceTabs(
          selected: selected,
          onSelected: onSelected,
          showAccounts: showAccounts,
        ),
      ],
    ),
  );
}

class _ProjectWorkspaceTabs extends StatelessWidget {
  const _ProjectWorkspaceTabs({
    required this.selected,
    required this.onSelected,
    required this.showAccounts,
  });

  final YorksV1ProjectWorkspaceTab selected;
  final ValueChanged<YorksV1ProjectWorkspaceTab> onSelected;
  final bool showAccounts;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final tab in YorksV1ProjectWorkspaceTab.values)
          if (tab != YorksV1ProjectWorkspaceTab.accounts || showAccounts)
            _ProjectWorkspaceTabButton(
              label: _tabCopy(tab).primary,
              selected: selected == tab,
              onPressed: () => onSelected(tab),
            ),
      ],
    ),
  );

  TranslatableString _tabCopy(YorksV1ProjectWorkspaceTab tab) {
    return switch (tab) {
      YorksV1ProjectWorkspaceTab.overview => YorksV1ProjectStrings.overview,
      YorksV1ProjectWorkspaceTab.boq => YorksV1ProjectStrings.boq,
      YorksV1ProjectWorkspaceTab.requests =>
        YorksV1ProjectStrings.materialRequests,
      YorksV1ProjectWorkspaceTab.accounts => YorksV1ProjectStrings.accounts,
      YorksV1ProjectWorkspaceTab.documents => YorksV1ProjectStrings.documents,
      YorksV1ProjectWorkspaceTab.materialMovement =>
        YorksV1ProjectStrings.materialMovement,
    };
  }
}

class _ProjectMaterialMovementPanel extends ConsumerWidget {
  const _ProjectMaterialMovementPanel({
    required this.projectId,
    required this.language,
  });

  final String projectId;
  final AppLanguage language;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movements = ref.watch(
      yorksV1ProjectMaterialMovementsProvider(projectId),
    );
    return LedgerCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  YorksV1ProjectStrings.materialMovement.active(language),
                  style: AppTypography.titleLarge.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  YorksV1ProjectStrings.materialMovementDescription.active(
                    language,
                  ),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          movements.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.xxxl),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: OutlinedButton.icon(
                onPressed: () => ref.invalidate(
                  yorksV1ProjectMaterialMovementsProvider(projectId),
                ),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(
                  YorksV1MaterialRequestStrings.tryAgain.active(language),
                ),
              ),
            ),
            data: (items) => items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxxl),
                    child: Text(
                      YorksV1ProjectStrings.noMaterialMovements.active(
                        language,
                      ),
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  )
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 520),
                    child: Scrollbar(
                      child: ListView.separated(
                        primary: false,
                        padding: EdgeInsets.zero,
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) =>
                            _ProjectMaterialMovementRow(
                              movement: items[index],
                              language: language,
                            ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProjectMaterialMovementRow extends StatelessWidget {
  const _ProjectMaterialMovementRow({
    required this.movement,
    required this.language,
  });

  final YorksV1ProjectMaterialMovement movement;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final dispatched =
        movement.kind == YorksV1ProjectMaterialMovementKind.dispatched;
    final tone = dispatched ? AppColors.blue : AppColors.success;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      leading: CircleAvatar(
        backgroundColor: tone.withValues(alpha: .1),
        foregroundColor: tone,
        child: Icon(
          dispatched ? Icons.north_east_rounded : Icons.south_west_rounded,
        ),
      ),
      title: Text(
        movement.itemDescription,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${movement.reference} · ${movement.requestNumber}\n'
        '${movement.actorDisplayName} · '
        '${DateFormat.yMMMd().add_jm().format(movement.occurredAt.toLocal())}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${movement.quantity} ${movement.unit}',
            style: AppTypography.labelLarge.copyWith(
              color: tone,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            (dispatched
                    ? YorksV1ProjectStrings.dispatchedMovement
                    : YorksV1ProjectStrings.returnedMovement)
                .active(language),
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _ProjectWorkspaceTabButton extends StatelessWidget {
  const _ProjectWorkspaceTabButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onPressed,
      hoverColor: AppColors.blueContainer.withValues(alpha: .45),
      focusColor: AppColors.blueContainer,
      highlightColor: AppColors.blueContainer.withValues(alpha: .55),
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? AppColors.blue : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          label,
          style: AppTypography.labelLarge.copyWith(
            color: selected ? AppColors.blue : AppColors.inkSecondary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ),
  );
}

class _ProjectR35Overview extends StatelessWidget {
  const _ProjectR35Overview({
    required this.item,
    required this.language,
    required this.groups,
    required this.requests,
    required this.scopes,
    required this.documents,
    required this.onOpenRequests,
    required this.onOpenRequest,
    required this.onOpenDocuments,
  });

  final YorksV1ProjectPortfolioItem item;
  final AppLanguage language;
  final AsyncValue<List<YorksV1BoqGroup>> groups;
  final AsyncValue<List<YorksV1MaterialRequest>> requests;
  final AsyncValue<List<YorksV1MaterialRequestScopeOption>> scopes;
  final AsyncValue<YorksV1DocumentWorkspace> documents;
  final VoidCallback onOpenRequests;
  final ValueChanged<YorksV1MaterialRequest> onOpenRequest;
  final VoidCallback onOpenDocuments;

  @override
  Widget build(BuildContext context) {
    final groupItems = groups.valueOrNull;
    final requestItems = requests.valueOrNull;
    final scopeItems = scopes.valueOrNull;
    final documentWorkspace = documents.valueOrNull;
    final boqItems = groupItems?.fold<int>(
      0,
      (total, group) => total + group.rowCount,
    );
    final openRequests = requestItems
        ?.where((request) => !_projectRequestIsClosed(request.state))
        .length;
    final buildingCount = scopeItems?.where((scope) => !scope.isCommon).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final split = constraints.maxWidth >= 1000;
        final railWidth = constraints.maxWidth >= 1180 ? 322.0 : 292.0;
        final main = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ProjectActionRequiredPanel(
              requests: requests,
              language: language,
              onOpenRequests: onOpenRequests,
            ),
            const SizedBox(height: AppSpacing.md),
            _ProjectRecentRequestsPanel(
              requests: requests,
              language: language,
              onOpenRequest: onOpenRequest,
              onViewAll: onOpenRequests,
            ),
            const SizedBox(height: AppSpacing.md),
            _ProjectRecentActivityPanel(
              requests: requests,
              groups: groups,
              documents: documents,
              language: language,
              onViewAll: onOpenRequests,
            ),
          ],
        );
        final rail = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ProjectOverviewTeamPanel(item: item, language: language),
            const SizedBox(height: AppSpacing.md),
            _ProjectOverviewScopesPanel(
              scopes: scopes,
              fallbackBuildingCount: item.activeBuildingCount,
              language: language,
            ),
            const SizedBox(height: AppSpacing.md),
            _ProjectOverviewDocumentsPanel(
              documents: documents,
              language: language,
              onOpen: onOpenDocuments,
            ),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ProjectOverviewMetricGrid(
              metrics: [
                _ProjectOverviewMetric(
                  icon: Icons.assignment_outlined,
                  label: YorksV1ProjectStrings.materialRequests.active(
                    language,
                  ),
                  value: requestItems == null ? '—' : '${requestItems.length}',
                  detail: openRequests == null
                      ? '—'
                      : '$openRequests ${YorksV1ProjectStrings.currentlyOpen.active(language)}',
                  emphasizedDetail: openRequests != null,
                ),
                _ProjectOverviewMetric(
                  icon: Icons.inventory_2_outlined,
                  label: YorksV1ProjectStrings.boqGroups.active(language),
                  value: groupItems == null ? '—' : '${groupItems.length}',
                  detail: YorksV1ProjectStrings.foldersOfMaterials.active(
                    language,
                  ),
                ),
                _ProjectOverviewMetric(
                  icon: Icons.format_list_bulleted_rounded,
                  label: YorksV1ProjectStrings.boqItems.active(language),
                  value: boqItems == null ? '—' : '$boqItems',
                  detail: YorksV1ProjectStrings.availableToRequest.active(
                    language,
                  ),
                ),
                _ProjectOverviewMetric(
                  icon: Icons.apartment_rounded,
                  label: YorksV1ProjectStrings.buildings.active(language),
                  value: buildingCount == null ? '—' : '$buildingCount',
                  detail: YorksV1ProjectStrings.plusCommonScope.active(
                    language,
                  ),
                ),
                _ProjectOverviewMetric(
                  icon: Icons.description_outlined,
                  label: YorksV1ProjectStrings.documents.active(language),
                  value: documentWorkspace == null
                      ? '—'
                      : '${documentWorkspace.documents.length}',
                  detail: YorksV1ProjectStrings.projectLevelFiles.active(
                    language,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (split)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: main),
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(width: railWidth, child: rail),
                ],
              )
            else ...[
              main,
              const SizedBox(height: AppSpacing.md),
              rail,
            ],
          ],
        );
      },
    );
  }
}

bool _projectRequestIsClosed(YorksV1MaterialRequestState state) =>
    state == YorksV1MaterialRequestState.received ||
    state == YorksV1MaterialRequestState.closed ||
    state == YorksV1MaterialRequestState.cancelled;

class _ProjectOverviewMetric {
  const _ProjectOverviewMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    this.emphasizedDetail = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final bool emphasizedDetail;
}

class _ProjectOverviewMetricGrid extends StatelessWidget {
  const _ProjectOverviewMetricGrid({required this.metrics});

  final List<_ProjectOverviewMetric> metrics;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1020
          ? 5
          : constraints.maxWidth >= 680
          ? 3
          : 2;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: metrics.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: AppSpacing.sm,
          mainAxisSpacing: AppSpacing.sm,
          mainAxisExtent: 100,
        ),
        itemBuilder: (context, index) {
          final metric = metrics[index];
          return Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 12,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: AppSpacing.minTapTarget,
                  height: AppSpacing.minTapTarget,
                  decoration: BoxDecoration(
                    color: AppColors.blueContainer,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Icon(metric.icon, color: AppColors.blue, size: 23),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        metric.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        metric.value,
                        style: AppTypography.headlineMedium.copyWith(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        metric.detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelSmall.copyWith(
                          color: metric.emphasizedDetail
                              ? AppColors.blue
                              : AppColors.muted,
                          fontWeight: metric.emphasizedDetail
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class _ProjectOverviewPanel extends StatelessWidget {
  const _ProjectOverviewPanel({
    required this.title,
    required this.child,
    this.description,
    this.action,
    this.padding = const EdgeInsets.all(AppSpacing.md),
  });

  final String title;
  final String? description;
  final Widget? action;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.titleMedium.copyWith(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        description!,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: AppSpacing.sm),
                action!,
              ],
            ],
          ),
        ),
        Padding(padding: padding, child: child),
      ],
    ),
  );
}

class _ProjectActionRequiredPanel extends StatelessWidget {
  const _ProjectActionRequiredPanel({
    required this.requests,
    required this.language,
    required this.onOpenRequests,
  });

  final AsyncValue<List<YorksV1MaterialRequest>> requests;
  final AppLanguage language;
  final VoidCallback onOpenRequests;

  @override
  Widget build(BuildContext context) {
    final items = requests.valueOrNull;
    final approvalCount = items
        ?.where(
          (request) =>
              request.state ==
                  YorksV1MaterialRequestState.awaitingRequestApproval ||
              request.state == YorksV1MaterialRequestState.awaitingApproval,
        )
        .length;
    final deliveryCount = items
        ?.where(
          (request) =>
              request.state == YorksV1MaterialRequestState.dispatched ||
              request.state == YorksV1MaterialRequestState.partiallyReceived,
        )
        .length;
    return _ProjectOverviewPanel(
      title: YorksV1ProjectStrings.actionRequired.active(language),
      description: YorksV1ProjectStrings.actionRequiredDescription.active(
        language,
      ),
      action: SizedBox(
        height: AppSpacing.minTapTarget,
        child: OutlinedButton(
          onPressed: onOpenRequests,
          child: Text(YorksV1ProjectStrings.viewAllActions.active(language)),
        ),
      ),
      child: requests.when(
        loading: () => const SizedBox(
          height: 68,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => _ProjectOverviewMessage(
          icon: Icons.cloud_off_outlined,
          message: YorksV1ProjectStrings.requestsUnavailable.active(language),
        ),
        data: (_) {
          final actions = <Widget>[
            if ((approvalCount ?? 0) > 0)
              _ProjectActionTile(
                icon: Icons.priority_high_rounded,
                tone: AppColors.warning,
                background: AppColors.warningContainer,
                title:
                    '$approvalCount ${YorksV1ProjectStrings.requestsAwaitingApproval.active(language)}',
                description: YorksV1ProjectStrings
                    .requestsAwaitingApprovalDescription
                    .active(language),
                actionLabel: YorksV1ProjectStrings.reviewRequests.active(
                  language,
                ),
                onPressed: onOpenRequests,
              ),
            if ((deliveryCount ?? 0) > 0)
              _ProjectActionTile(
                icon: Icons.local_shipping_outlined,
                tone: AppColors.blue,
                background: AppColors.blueContainer,
                title:
                    '$deliveryCount ${YorksV1ProjectStrings.deliveriesReadyForReceipt.active(language)}',
                description: YorksV1ProjectStrings
                    .deliveriesReadyForReceiptDescription
                    .active(language),
                actionLabel: YorksV1ProjectStrings.reviewDeliveries.active(
                  language,
                ),
                onPressed: onOpenRequests,
              ),
          ];
          if (actions.isEmpty) {
            return _ProjectOverviewMessage(
              icon: Icons.check_circle_outline_rounded,
              message: YorksV1ProjectStrings.noAttentionRequired.active(
                language,
              ),
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 700
                ? Row(
                    children: [
                      for (var index = 0; index < actions.length; index++) ...[
                        Expanded(child: actions[index]),
                        if (index != actions.length - 1)
                          const SizedBox(width: AppSpacing.sm),
                      ],
                    ],
                  )
                : Column(
                    children: [
                      for (var index = 0; index < actions.length; index++) ...[
                        actions[index],
                        if (index != actions.length - 1)
                          const SizedBox(height: AppSpacing.sm),
                      ],
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _ProjectActionTile extends StatelessWidget {
  const _ProjectActionTile({
    required this.icon,
    required this.tone,
    required this.background,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final Color tone;
  final Color background;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 68),
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
    ),
    child: Row(
      children: [
        Container(
          width: AppSpacing.minTapTarget,
          height: AppSpacing.minTapTarget,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Icon(icon, color: tone, size: 24),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          height: AppSpacing.minTapTarget,
          child: OutlinedButton(
            onPressed: onPressed,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(actionLabel),
                const SizedBox(width: AppSpacing.xs),
                const Icon(Icons.arrow_forward_rounded, size: 16),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _ProjectRecentRequestsPanel extends StatelessWidget {
  const _ProjectRecentRequestsPanel({
    required this.requests,
    required this.language,
    required this.onOpenRequest,
    required this.onViewAll,
  });

  final AsyncValue<List<YorksV1MaterialRequest>> requests;
  final AppLanguage language;
  final ValueChanged<YorksV1MaterialRequest> onOpenRequest;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) => _ProjectOverviewPanel(
    title: YorksV1ProjectStrings.recentMaterialRequests.active(language),
    description: YorksV1ProjectStrings.recentRequestsDescription.active(
      language,
    ),
    action: SizedBox(
      height: AppSpacing.minTapTarget,
      child: OutlinedButton(
        onPressed: onViewAll,
        child: Text(AppStrings.viewAll.active(language)),
      ),
    ),
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      0,
      AppSpacing.md,
      AppSpacing.md,
    ),
    child: requests.when(
      loading: () => const SizedBox(
        height: 150,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => _ProjectOverviewMessage(
        icon: Icons.cloud_off_outlined,
        message: YorksV1ProjectStrings.requestsUnavailable.active(language),
      ),
      data: (items) {
        final recent = [...items]
          ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
        final visible = recent.take(4).toList(growable: false);
        if (visible.isEmpty) {
          return _ProjectOverviewMessage(
            icon: Icons.assignment_outlined,
            message: YorksV1ProjectStrings.noRecentRequests.active(language),
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 700
              ? _ProjectRequestTable(
                  items: visible,
                  language: language,
                  onOpen: onOpenRequest,
                )
              : Column(
                  children: [
                    for (var index = 0; index < visible.length; index++) ...[
                      _ProjectCompactRequestRow(
                        request: visible[index],
                        language: language,
                        onTap: () => onOpenRequest(visible[index]),
                      ),
                      if (index != visible.length - 1)
                        const Divider(height: 1, color: AppColors.line),
                    ],
                  ],
                ),
        );
      },
    ),
  );
}

class _ProjectRequestTable extends StatelessWidget {
  const _ProjectRequestTable({
    required this.items,
    required this.language,
    required this.onOpen,
  });

  final List<YorksV1MaterialRequest> items;
  final AppLanguage language;
  final ValueChanged<YorksV1MaterialRequest> onOpen;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        Container(
          color: AppColors.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              _ProjectTableHeading(
                flex: 20,
                label: YorksV1ProjectStrings.request.active(language),
              ),
              _ProjectTableHeading(
                flex: 22,
                label: YorksV1ProjectStrings.buildingOrScope.active(language),
              ),
              _ProjectTableHeading(
                flex: 20,
                label: YorksV1ProjectStrings.status.active(language),
              ),
              _ProjectTableHeading(
                flex: 18,
                label: YorksV1ProjectStrings.nextOwner.active(language),
              ),
              _ProjectTableHeading(
                flex: 16,
                label: YorksV1ProjectStrings.updated.active(language),
              ),
              const SizedBox(width: 24),
            ],
          ),
        ),
        for (var index = 0; index < items.length; index++) ...[
          _ProjectRequestTableRow(
            request: items[index],
            language: language,
            onTap: () => onOpen(items[index]),
          ),
          if (index != items.length - 1)
            const Divider(height: 1, color: AppColors.line),
        ],
      ],
    ),
  );
}

class _ProjectTableHeading extends StatelessWidget {
  const _ProjectTableHeading({required this.flex, required this.label});

  final int flex;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.labelSmall.copyWith(
        color: AppColors.muted,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _ProjectRequestTableRow extends StatelessWidget {
  const _ProjectRequestTableRow({
    required this.request,
    required this.language,
    required this.onTap,
  });

  final YorksV1MaterialRequest request;
  final AppLanguage language;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            flex: 20,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.requestNumber ??
                      YorksV1MaterialRequestStrings.draft.active(language),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${request.displayItemCount} ${YorksV1ProjectStrings.items.active(language).toLowerCase()}',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 22,
            child: Text(
              request.scopeName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.inkSecondary,
              ),
            ),
          ),
          Expanded(
            flex: 20,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _ProjectRequestStateBadge(
                state: request.state,
                language: language,
              ),
            ),
          ),
          Expanded(
            flex: 18,
            child: Text(
              YorksV1ProjectStrings.roleLabel(
                request.currentActionOwnerRole,
              ).active(language),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.inkSecondary,
              ),
            ),
          ),
          Expanded(
            flex: 16,
            child: Text(
              _projectOverviewDate(request.updatedAt, language),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
          ),
          const SizedBox(
            width: 24,
            child: Icon(
              Icons.chevron_right_rounded,
              size: 19,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ProjectCompactRequestRow extends StatelessWidget {
  const _ProjectCompactRequestRow({
    required this.request,
    required this.language,
    required this.onTap,
  });

  final YorksV1MaterialRequest request;
  final AppLanguage language;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    contentPadding: EdgeInsets.zero,
    minVerticalPadding: AppSpacing.sm,
    title: Text(
      request.requestNumber ??
          YorksV1MaterialRequestStrings.draft.active(language),
      style: AppTypography.labelLarge.copyWith(
        color: AppColors.navy,
        fontWeight: FontWeight.w800,
      ),
    ),
    subtitle: Text(
      '${request.scopeName} · ${YorksV1ProjectStrings.roleLabel(request.currentActionOwnerRole).active(language)}',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: _ProjectRequestStateBadge(
      state: request.state,
      language: language,
    ),
  );
}

class _ProjectRequestStateBadge extends StatelessWidget {
  const _ProjectRequestStateBadge({
    required this.state,
    required this.language,
  });

  final YorksV1MaterialRequestState state;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final (tone, background) = switch (state) {
      YorksV1MaterialRequestState.awaitingRequestApproval ||
      YorksV1MaterialRequestState.awaitingApproval => (
        AppColors.warning,
        AppColors.warningContainer,
      ),
      YorksV1MaterialRequestState.received ||
      YorksV1MaterialRequestState.closed => (
        AppColors.success,
        AppColors.successContainer,
      ),
      YorksV1MaterialRequestState.changesRequested ||
      YorksV1MaterialRequestState.cancelled => (
        AppColors.error,
        AppColors.errorContainer,
      ),
      YorksV1MaterialRequestState.draft => (
        AppColors.neutralText,
        AppColors.neutralContainer,
      ),
      _ => (AppColors.blue, AppColors.blueContainer),
    };
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        yorksV1MaterialRequestStateCopy(state).active(language),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelSmall.copyWith(
          color: tone,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ProjectActivityEntry {
  const _ProjectActivityEntry({
    required this.icon,
    required this.title,
    required this.detail,
    required this.actor,
    required this.occurredAt,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String actor;
  final DateTime occurredAt;
}

class _ProjectRecentActivityPanel extends StatelessWidget {
  const _ProjectRecentActivityPanel({
    required this.requests,
    required this.groups,
    required this.documents,
    required this.language,
    required this.onViewAll,
  });

  final AsyncValue<List<YorksV1MaterialRequest>> requests;
  final AsyncValue<List<YorksV1BoqGroup>> groups;
  final AsyncValue<YorksV1DocumentWorkspace> documents;
  final AppLanguage language;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final entries = <_ProjectActivityEntry>[
      for (final request in requests.valueOrNull ?? const [])
        _ProjectActivityEntry(
          icon: Icons.assignment_outlined,
          title:
              '${request.requestNumber ?? YorksV1MaterialRequestStrings.draft.active(language)} '
              '${request.state == YorksV1MaterialRequestState.awaitingRequestApproval ? YorksV1ProjectStrings.requestSubmittedForApproval.active(language) : yorksV1MaterialRequestStateCopy(request.state).active(language)}',
          detail:
              '${request.displayItemCount} ${YorksV1ProjectStrings.items.active(language).toLowerCase()} · ${request.scopeName}',
          actor:
              _safeVisibleText(request.requesterDisplayName) ??
              YorksV1ProjectStrings.notProvided.active(language),
          occurredAt: request.submittedAt ?? request.updatedAt,
        ),
      for (final group in groups.valueOrNull ?? const [])
        _ProjectActivityEntry(
          icon: Icons.inventory_2_outlined,
          title: YorksV1ProjectStrings.boqUpdated.active(language),
          detail:
              '${group.name} · ${group.rowCount} ${YorksV1ProjectStrings.items.active(language).toLowerCase()}',
          actor:
              _safeVisibleText(group.lastEditedBy) ??
              YorksV1ProjectStrings.notProvided.active(language),
          occurredAt: group.lastEditedAt ?? group.updatedAt,
        ),
      for (final document in documents.valueOrNull?.documents ?? const [])
        _ProjectActivityEntry(
          icon: Icons.description_outlined,
          title: YorksV1ProjectStrings.documentUploaded.active(language),
          detail: document.currentVersion.fileName,
          actor: document.currentVersion.uploadedByDisplayName,
          occurredAt: document.currentVersion.uploadedAt,
        ),
    ]..sort((left, right) => right.occurredAt.compareTo(left.occurredAt));
    final visible = entries.take(4).toList(growable: false);
    final loading =
        requests.isLoading || groups.isLoading || documents.isLoading;
    return _ProjectOverviewPanel(
      title: YorksV1ProjectStrings.recentActivity.active(language),
      description: YorksV1ProjectStrings.recentActivityDescription.active(
        language,
      ),
      action: SizedBox(
        height: AppSpacing.minTapTarget,
        child: OutlinedButton(
          onPressed: onViewAll,
          child: Text(AppStrings.viewAll.active(language)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: loading && visible.isEmpty
          ? const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            )
          : visible.isEmpty
          ? _ProjectOverviewMessage(
              icon: Icons.history_rounded,
              message: YorksV1ProjectStrings.noRecentActivity.active(language),
            )
          : Column(
              children: [
                for (var index = 0; index < visible.length; index++) ...[
                  _ProjectActivityRow(
                    entry: visible[index],
                    language: language,
                  ),
                  if (index != visible.length - 1)
                    const Divider(height: 1, color: AppColors.line),
                ],
              ],
            ),
    );
  }
}

class _ProjectActivityRow extends StatelessWidget {
  const _ProjectActivityRow({required this.entry, required this.language});

  final _ProjectActivityEntry entry;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.blueContainer,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Icon(entry.icon, size: 19, color: AppColors.blue),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '${entry.detail}\n${entry.actor} · ${_projectOverviewDate(entry.occurredAt, language)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ProjectOverviewTeamPanel extends ConsumerWidget {
  const _ProjectOverviewTeamPanel({required this.item, required this.language});

  final YorksV1ProjectPortfolioItem item;
  final AppLanguage language;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(yorksV1CurrentRoleProvider);
    final authUserId = ref.watch(yorksV1AuthUserIdProvider);
    final hasProjectEngineerMembership =
        authUserId != null &&
        item.activeMembers.any(
          (member) =>
              member.memberAuthUserId == authUserId &&
              member.projectRole ==
                  YorksV1ProjectMembershipRole.projectEngineer,
        );
    final canManage =
        role == YorksV1Role.admin ||
        (role?.isGlobalProjectEngineer ?? false) ||
        hasProjectEngineerMembership;
    final directory = canManage
        ? ref.watch(yorksV1ActiveProjectTeamDirectoryProvider)
        : null;
    final names = {
      for (final member
          in directory?.valueOrNull ??
              const <YorksV1ProjectTeamDirectoryMember>[])
        member.authUserId: member.displayName,
    };
    final projectEngineers = item.activeMembers
        .where(
          (member) =>
              member.projectRole ==
              YorksV1ProjectMembershipRole.projectEngineer,
        )
        .toList(growable: false);
    final siteEngineers = item.activeMembers
        .where(
          (member) =>
              member.projectRole == YorksV1ProjectMembershipRole.siteEngineer,
        )
        .toList(growable: false);
    return _ProjectOverviewPanel(
      title: YorksV1ProjectStrings.projectTeam.active(language),
      action: canManage
          ? SizedBox(
              height: AppSpacing.minTapTarget,
              child: TextButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _ProjectTeamAssignmentDialog(item: item),
                ),
                icon: const Icon(Icons.group_add_outlined, size: 18),
                label: Text(YorksV1ProjectStrings.manage.active(language)),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProjectTeamGroup(
            label: YorksV1ProjectStrings.projectEngineers.active(language),
            members: projectEngineers,
            fallbackCount: item.activeProjectEngineerCount,
            names: names,
            language: language,
          ),
          const SizedBox(height: AppSpacing.md),
          _ProjectTeamGroup(
            label: YorksV1ProjectStrings.siteEngineers.active(language),
            members: siteEngineers,
            fallbackCount: item.activeSiteEngineerCount,
            names: names,
            language: language,
          ),
          const Divider(height: AppSpacing.xl, color: AppColors.line),
          Text(
            YorksV1ProjectStrings.procurementOwner.active(language),
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.navy,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: AppColors.warningContainer,
                foregroundColor: AppColors.warning,
                child: Text(
                  'NA',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  YorksV1ProjectStrings.notAssigned.active(language),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectTeamGroup extends StatelessWidget {
  const _ProjectTeamGroup({
    required this.label,
    required this.members,
    required this.fallbackCount,
    required this.names,
    required this.language,
  });

  final String label;
  final List<YorksV1ProjectMember> members;
  final int fallbackCount;
  final Map<String, String> names;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: AppTypography.labelSmall.copyWith(
          color: AppColors.navy,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      if (members.isEmpty)
        Text(
          fallbackCount > 0
              ? '$fallbackCount'
              : YorksV1ProjectStrings.notAssigned.active(language),
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        )
      else
        for (final member in members)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: AppColors.blueContainer,
                  foregroundColor: AppColors.blue,
                  child: Text(
                    _memberInitials(
                      _safeTeamMemberName(
                        member,
                        names[member.memberAuthUserId],
                      ),
                    ),
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.blue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _safeTeamMemberName(member, names[member.memberAuthUserId]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.inkSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
    ],
  );
}

class _ProjectOverviewScopesPanel extends StatelessWidget {
  const _ProjectOverviewScopesPanel({
    required this.scopes,
    required this.fallbackBuildingCount,
    required this.language,
  });

  final AsyncValue<List<YorksV1MaterialRequestScopeOption>> scopes;
  final int fallbackBuildingCount;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final loaded = scopes.valueOrNull;
    final count = loaded?.where((scope) => !scope.isCommon).length;
    return _ProjectOverviewPanel(
      title: YorksV1ProjectStrings.buildingsAndScope.active(language),
      action: _ProjectBadge(
        label:
            '${count ?? fallbackBuildingCount} ${YorksV1ProjectStrings.buildings.active(language).toLowerCase()}',
      ),
      child: scopes.when(
        loading: () => const SizedBox(
          height: 78,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => Text(
          YorksV1ProjectStrings.recordsUnavailable.active(language),
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Text(
              YorksV1ProjectStrings.noBuildingsAdded.active(language),
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            );
          }
          final ordered = [
            ...items.where((scope) => !scope.isCommon),
            ...items.where((scope) => scope.isCommon),
          ];
          return Column(
            children: [
              for (var index = 0; index < ordered.length; index++) ...[
                _ProjectScopeRow(scope: ordered[index], language: language),
                if (index != ordered.length - 1)
                  const SizedBox(height: AppSpacing.xs),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ProjectScopeRow extends StatelessWidget {
  const _ProjectScopeRow({required this.scope, required this.language});

  final YorksV1MaterialRequestScopeOption scope;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.sm,
    ),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
    ),
    child: Row(
      children: [
        Icon(
          scope.isCommon ? Icons.layers_outlined : Icons.apartment_rounded,
          size: 21,
          color: AppColors.blue,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                scope.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (scope.isCommon)
                Text(
                  YorksV1ProjectStrings.sharedScopeForProject.active(language),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
            ],
          ),
        ),
        if (scope.isCommon)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.neutralContainer,
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            ),
            child: Text(
              YorksV1ProjectStrings.commonBadge.active(language).toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.neutralText,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    ),
  );
}

class _ProjectOverviewDocumentsPanel extends StatelessWidget {
  const _ProjectOverviewDocumentsPanel({
    required this.documents,
    required this.language,
    required this.onOpen,
  });

  final AsyncValue<YorksV1DocumentWorkspace> documents;
  final AppLanguage language;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => _ProjectOverviewPanel(
    title: YorksV1ProjectStrings.documents.active(language),
    action: SizedBox(
      height: AppSpacing.minTapTarget,
      child: TextButton(
        onPressed: onOpen,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppStrings.viewAll.active(language)),
            const Icon(Icons.chevron_right_rounded, size: 18),
          ],
        ),
      ),
    ),
    child: documents.when(
      loading: () => const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Text(
        YorksV1ProjectStrings.recordsUnavailable.active(language),
        style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
      ),
      data: (workspace) {
        if (workspace.documents.isEmpty) {
          return Column(
            children: [
              const Icon(
                Icons.description_outlined,
                size: 36,
                color: AppColors.muted,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                YorksV1ProjectStrings.noProjectDocumentsYet.active(language),
                textAlign: TextAlign.center,
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                YorksV1ProjectStrings.documentsModuleDescription.active(
                  language,
                ),
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: AppSpacing.minTapTarget,
                child: OutlinedButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.upload_outlined),
                  label: Text(
                    YorksV1ProjectStrings.uploadDocument.active(language),
                  ),
                ),
              ),
            ],
          );
        }
        final recent = [...workspace.documents]
          ..sort(
            (left, right) => right.currentVersion.uploadedAt.compareTo(
              left.currentVersion.uploadedAt,
            ),
          );
        return Column(
          children: [
            for (final document in recent.take(3))
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                onTap: onOpen,
                leading: const Icon(
                  Icons.description_outlined,
                  color: AppColors.blue,
                ),
                title: Text(
                  document.currentVersion.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.navy,
                  ),
                ),
                subtitle: Text(
                  _projectOverviewDate(
                    document.currentVersion.uploadedAt,
                    language,
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _ProjectOverviewMessage extends StatelessWidget {
  const _ProjectOverviewMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 70),
    alignment: Alignment.center,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: AppColors.muted),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
        ),
      ],
    ),
  );
}

String _projectOverviewDate(DateTime value, AppLanguage language) {
  final local = value.toLocal();
  final now = DateTime.now();
  final sameDay =
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  if (sameDay) {
    return '${AppStrings.today.active(language)}, ${DateFormat.jm().format(local)}';
  }
  return DateFormat('d MMM yyyy').format(local);
}

class _ProjectTeamAssignmentDialog extends ConsumerStatefulWidget {
  const _ProjectTeamAssignmentDialog({required this.item});

  final YorksV1ProjectPortfolioItem item;

  @override
  ConsumerState<_ProjectTeamAssignmentDialog> createState() =>
      _ProjectTeamAssignmentDialogState();
}

class _ProjectTeamAssignmentDialogState
    extends ConsumerState<_ProjectTeamAssignmentDialog> {
  Map<String, YorksV1ProjectMembershipRole?> _selectedRoles = const {};
  bool _seeded = false;
  bool _saving = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final directory = ref.watch(yorksV1ActiveProjectTeamDirectoryProvider);
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.lg,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          YorksV1ProjectStrings.manageProjectTeamTitle.primary,
                          style: AppTypography.titleLarge.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          '${widget.item.project.reference} · ${YorksV1ProjectStrings.teamChangesAudited.primary}',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.line),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: directory.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, _) => Text(
                    YorksV1ProjectStrings.teamDirectoryUnavailable.primary,
                  ),
                  data: (members) {
                    final current = {
                      for (final member in widget.item.activeMembers)
                        member.memberAuthUserId: member.projectRole,
                    };
                    if (!_seeded) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() {
                            _selectedRoles = current;
                            _seeded = true;
                          });
                        }
                      });
                    }
                    final selected = _seeded ? _selectedRoles : current;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _ProjectTeamPermissionBanner(),
                        const SizedBox(height: AppSpacing.lg),
                        for (final member in members) ...[
                          _ProjectTeamRoleRow(
                            member: member,
                            value: selected[member.authUserId],
                            enabled: !_saving,
                            onChanged: (value) => setState(() {
                              _selectedRoles = {
                                ...selected,
                                member.authUserId: value,
                              };
                              _error = null;
                            }),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                        if (members.isEmpty)
                          Text(
                            YorksV1ProjectStrings.noEligibleTeamMembers.primary,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                        if (_error != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            _error!,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.line),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: Text(YorksV1ProjectStrings.cancel.primary),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(YorksV1ProjectStrings.saveProjectTeam.primary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final current = {
      for (final member in widget.item.activeMembers)
        member.memberAuthUserId: member.projectRole,
    };
    if (widget.item.project.state == YorksV1ProjectLifecycle.active &&
        !_selectedRoles.values.contains(
          YorksV1ProjectMembershipRole.projectEngineer,
        )) {
      setState(
        () => _error = YorksV1ProjectStrings.initialProjectEngineerHint.primary,
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      var version = widget.item.project.recordVersion;
      final controller = ref.read(
        yorksV1ProjectCommandControllerProvider.notifier,
      );
      for (final entry in _selectedRoles.entries) {
        final targetRole = entry.value;
        if (targetRole == null || current[entry.key] == targetRole) continue;
        final result = await controller.assignProjectMember(
          YorksV1AssignProjectMemberInput(
            idempotencyKey: const Uuid().v4(),
            projectId: widget.item.project.id,
            memberAuthUserId: entry.key,
            projectRole: targetRole,
            expectedProjectVersion: version,
            reason: YorksV1ProjectStrings.projectTeamChangeReason.primary,
          ),
        );
        version = result.project.recordVersion;
      }
      for (final entry in current.entries) {
        if (_selectedRoles[entry.key] != null) continue;
        final result = await controller.revokeProjectMember(
          YorksV1RevokeProjectMemberInput(
            idempotencyKey: const Uuid().v4(),
            projectId: widget.item.project.id,
            memberAuthUserId: entry.key,
            projectRole: entry.value,
            expectedProjectVersion: version,
            reason: YorksV1ProjectStrings.projectTeamChangeReason.primary,
          ),
        );
        version = result.project.recordVersion;
      }
      ref.invalidate(yorksV1ProjectPortfolioProvider);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(YorksV1ProjectStrings.projectTeamUpdated.primary),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = YorksV1ProjectStrings.teamDirectoryUnavailable.primary;
        });
      }
    }
  }
}

class _ProjectTeamPermissionBanner extends StatelessWidget {
  const _ProjectTeamPermissionBanner();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.blueContainer.withValues(alpha: .48),
      border: Border.all(color: AppColors.blueContainerStrong),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.verified_user_outlined, color: AppColors.blue),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                YorksV1ProjectStrings.projectTeamPermissionRule.primary,
                style: AppTypography.labelLarge.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                YorksV1ProjectStrings.projectTeamPermissionDescription.primary,
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ProjectTeamRoleRow extends StatelessWidget {
  const _ProjectTeamRoleRow({
    required this.member,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final YorksV1ProjectTeamDirectoryMember member;
  final YorksV1ProjectMembershipRole? value;
  final bool enabled;
  final ValueChanged<YorksV1ProjectMembershipRole?> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final identity = Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.blueContainer,
              foregroundColor: AppColors.blue,
              child: Text(_memberInitials(member.displayName)),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.displayName,
                    style: AppTypography.labelLarge.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    YorksV1ProjectStrings.roleLabel(
                      member.eligibleRole.claimValue,
                    ).primary,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        final selector = DropdownButtonFormField<YorksV1ProjectMembershipRole?>(
          key: ValueKey('${member.authUserId}-${value?.wireValue ?? 'none'}'),
          initialValue: value,
          decoration: const InputDecoration(isDense: true),
          items: [
            DropdownMenuItem(
              value: null,
              child: Text(YorksV1ProjectStrings.noProjectAccess.primary),
            ),
            DropdownMenuItem(
              value: YorksV1ProjectMembershipRole.projectEngineer,
              child: Text(YorksV1ProjectStrings.projectEngineerRole.primary),
            ),
            DropdownMenuItem(
              value: YorksV1ProjectMembershipRole.siteEngineer,
              child: Text(YorksV1ProjectStrings.siteEngineerRole.primary),
            ),
          ],
          onChanged: enabled ? onChanged : null,
        );
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              identity,
              const SizedBox(height: AppSpacing.md),
              selector,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: identity),
            const SizedBox(width: AppSpacing.lg),
            SizedBox(width: 290, child: selector),
          ],
        );
      },
    ),
  );
}

String _memberInitials(String displayName) {
  final parts = displayName
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return '?';
  return parts.take(2).map((part) => part[0].toUpperCase()).join();
}

String? _safeVisibleText(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  if (_looksLikeUuid(normalized) ||
      YorksV1ProjectTeamDirectoryMember.isEmailLikeDisplayName(normalized)) {
    return null;
  }
  return normalized;
}

String _safeTeamMemberName(YorksV1ProjectMember member, String? directoryName) {
  return _safeVisibleText(member.displayName) ??
      _safeVisibleText(directoryName) ??
      YorksV1ProjectStrings.profileId.primary;
}

bool _looksLikeUuid(String value) => RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
).hasMatch(value.trim());

class _ProjectBadge extends StatelessWidget {
  const _ProjectBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: AppSpacing.sm),
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: AppColors.blueContainer,
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
    ),
    child: Text(
      label,
      style: AppTypography.labelSmall.copyWith(
        color: AppColors.blue,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _LinkedRecordCard extends StatelessWidget {
  const _LinkedRecordCard({
    required this.icon,
    required this.title,
    required this.action,
    required this.onOpen,
  });

  final IconData icon;
  final TranslatableString title;
  final TranslatableString action;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => LedgerCard(
    child: Row(
      children: [
        Container(
          width: AppSpacing.minTapTarget,
          height: AppSpacing.minTapTarget,
          decoration: BoxDecoration(
            color: AppColors.blueContainer,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Icon(icon, color: AppColors.primary),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            title.primary,
            style: AppTypography.titleMedium.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          height: AppSpacing.minTapTarget,
          child: OutlinedButton(onPressed: onOpen, child: Text(action.primary)),
        ),
      ],
    ),
  );
}

class _CopyText extends StatelessWidget {
  const _CopyText({
    required this.copy,
    required this.language,
    this.style,
    this.center = false,
  });

  final TranslatableString copy;
  final AppLanguage language;
  final TextStyle? style;
  final bool center;

  @override
  Widget build(BuildContext context) => YorksV1ActiveText(
    copy: copy,
    language: language,
    style: style ?? AppTypography.bodyMedium,
    textAlign: center ? TextAlign.center : null,
  );
}

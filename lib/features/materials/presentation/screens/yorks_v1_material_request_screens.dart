import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/controllers/yorks_v1_material_request_draft_controller.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_boq.dart';
import '../../../../shared/models/yorks_v1_boq_strings.dart';
import '../../../../shared/models/yorks_v1_boq_workbook.dart';
import '../../../../shared/models/yorks_v1_configuration.dart';
import '../../../../shared/models/yorks_v1_arrangement_strings.dart';
import '../../../../shared/models/yorks_v1_arrangement.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/models/yorks_v1_logistics.dart';
import '../../../../shared/models/yorks_v1_logistics_strings.dart';
import '../../../../shared/models/yorks_v1_material_request.dart';
import '../../../../shared/models/yorks_v1_material_request_document.dart';
import '../../../../shared/models/yorks_v1_material_request_strings.dart';
import '../../../../shared/models/yorks_v1_project.dart';
import '../../../../shared/models/yorks_v1_project_strings.dart';
import '../../../../shared/models/yorks_v1_permission_management.dart';
import '../../../../shared/models/yorks_v1_quantity.dart';
import '../../../../shared/models/yorks_v1_role.dart';
import '../../../../shared/models/yorks_v1_shell_strings.dart';
import '../../../../shared/models/yorks_v1_team_chat.dart';
import '../../../../shared/models/yorks_v1_team_chat_strings.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/yorks_v1_boq_repository_provider.dart';
import '../../../../shared/providers/yorks_v1_boq_workbook_provider.dart';
import '../../../../shared/providers/yorks_v1_configuration_provider.dart';
import '../../../../shared/providers/yorks_v1_feature_flags_provider.dart';
import '../../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../../../shared/providers/yorks_v1_logistics_provider.dart';
import '../../../../shared/providers/yorks_v1_material_request_provider.dart';
import '../../../../shared/providers/yorks_v1_material_request_repository_provider.dart';
import '../../../../shared/providers/yorks_v1_material_workflow_command_provider.dart';
import '../../../../shared/providers/yorks_v1_permission_provider.dart';
import '../../../../shared/providers/yorks_v1_team_chat_provider.dart';
import '../../../../shared/providers/yorks_v1_workspace_presentation_provider.dart';
import '../../../../shared/providers/yorks_v1_arrangement_provider.dart';
import '../../../../shared/services/yorks_v1_material_request_document_service.dart';
import 'yorks_v1_dispatch_centre.dart';
import '../../../../shared/services/yorks_v1_boq_workbook_service.dart';
import '../../../../shared/services/yorks_v1_logistics_document_service.dart';
import '../../../../shared/providers/session_provider.dart';
import '../../../../shared/repositories/yorks_v1_material_request_repository.dart';

import 'yorks_v1_arrangement_screen.dart';
import 'yorks_v1_controlled_unit_field.dart';
import 'yorks_v1_logistics_screen.dart';
import 'yorks_v1_material_request_centre.dart';
import 'yorks_v1_returns_documents_screen.dart';
import '../yorks_v1_feature_action_access.dart';
import '../widgets/yorks_v1_request_information.dart';
import '../widgets/yorks_v1_material_request_history.dart';

final yorksV1MaterialRequestInspectorExpandedProvider =
    StateProvider.autoDispose<bool>((ref) => false);

/// Presentation-only state for the committed-request inspector. It never
/// changes request data or workflow authority, and is isolated per request.
final yorksV1MaterialRequestWorkspaceInspectorExpandedProvider = StateProvider
    .autoDispose
    .family<bool, String>((ref, requestId) => false);

/// V1 material request overview. It reads only the server projection; drafts
/// are returned only to their creator by the database contract.
class YorksV1MaterialRequestsScreen extends ConsumerWidget {
  const YorksV1MaterialRequestsScreen({
    super.key,
    this.projectId,
    this.embedded = false,
  });

  final String? projectId;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The phone register keeps a focused card editor while the responsive
    // centre below provides the project-aware desktop/tablet operational view.
    if (YorksMobileUi.isActive(context)) {
      return _YorksMobileMaterialRequestsPage(
        projectId: projectId,
        embedded: embedded,
      );
    }
    final language = ref.watch(languageProvider);
    final role = ref.watch(yorksV1CurrentRoleProvider);
    final permissionState = ref.watch(yorksV1CurrentPermissionSnapshotProvider);
    final createAccess = yorksV1FeatureActionAccess(
      permissionState,
      YorksV1CapabilityKeys.materialRequestsCreate,
      legacyAllowed: role?.canCreateMaterialRequest == true,
      projectId: projectId,
      anyProject: projectId == null,
    );
    final repository = ref.watch(yorksV1MaterialRequestRepositoryProvider);
    final phase2Repository =
        repository is YorksV1MaterialRequestPhase2Repository
        ? repository as YorksV1MaterialRequestPhase2Repository
        : null;
    final operationsRepository =
        repository is YorksV1MaterialRequestOperationsRepository
        ? repository as YorksV1MaterialRequestOperationsRepository
        : null;
    final requestRefreshRevision = ref.watch(
      yorksV1MaterialRequestRealtimeRevisionProvider,
    );
    final refreshRevision = Object.hash(
      requestRefreshRevision,
      permissionState.snapshot?.revision,
    );
    final canCreate = createAccess.isVisible;
    final ownerAuthUserId = ref.watch(yorksV1AuthUserIdProvider);
    final deviceDrafts = ownerAuthUserId == null || ownerAuthUserId.isEmpty
        ? const <YorksV1MaterialRequestDraft>[]
        : ref
              .watch(yorksV1MaterialRequestLocalDraftsProvider(ownerAuthUserId))
              .where(
                (draft) => projectId == null || draft.projectId == projectId,
              )
              .toList(growable: false);
    final accountDrafts =
        ownerAuthUserId == null ||
            ownerAuthUserId.isEmpty ||
            phase2Repository == null
        ? const <YorksV1PrivateMaterialRequestDraftRecord>[]
        : ref
                  .watch(
                    yorksV1MaterialRequestPrivateDraftsProvider(
                      ownerAuthUserId,
                    ),
                  )
                  .valueOrNull ??
              const <YorksV1PrivateMaterialRequestDraftRecord>[];
    final savedDrafts = _mergeRecoverableDrafts(
      deviceDrafts,
      accountDrafts.map((record) => record.draft),
      projectId: projectId,
    );
    final localDraftNotice = canCreate && savedDrafts.isNotEmpty
        ? _RecoverableMaterialDraftNotice(
            drafts: savedDrafts,
            onResume: (draft) => context.push(
              RoutePaths.yorksV1MaterialRequestDraftPath(
                draft.id,
                projectId: draft.projectId,
              ),
            ),
            onDelete: ownerAuthUserId == null
                ? null
                : (draft) => _deleteRecoverableDraft(
                    context,
                    ref,
                    ownerAuthUserId,
                    draft,
                  ),
          )
        : null;
    if (phase2Repository != null) {
      final body = SafeArea(
        top: false,
        child: YorksV1MaterialRequestCentre(
          key: ValueKey<int?>(permissionState.snapshot?.revision),
          requests: const [],
          language: language,
          canCreate: canCreate,
          fixedProjectId: projectId,
          summaryPageLoader: phase2Repository.listRequestSummaries,
          operationsDashboardLoader: operationsRepository == null
              ? null
              : (projectId) => operationsRepository.getOperationsDashboard(
                  projectId: projectId,
                ),
          refreshRevision: refreshRevision,
          onCreate: createAccess.canWrite
              ? () => context.push(
                  RoutePaths.yorksV1MaterialRequestDraftPath(
                    const Uuid().v4(),
                    projectId: projectId,
                  ),
                )
              : null,
          onOpen: (request) => context.push(_materialRequestOpenPath(request)),
          onRefresh: () {},
          localDraftNotice: localDraftNotice,
        ),
      );
      if (embedded) return body;
      return Scaffold(backgroundColor: AppColors.surface, body: body);
    }
    final requests = ref.watch(yorksV1MaterialRequestListProvider(projectId));
    final body = SafeArea(
      top: false,
      child: requests.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _RequestError(
          language: language,
          onRetry: () => ref.invalidate(yorksV1MaterialRequestListProvider),
        ),
        data: (items) => YorksV1MaterialRequestCentre(
          requests: items
              .where(
                (item) => yorksV1CanReadProjectRecord(
                  permissionState,
                  YorksV1CapabilityKeys.materialRequestsView,
                  legacyAllowed: true,
                  projectId: item.projectId,
                ),
              )
              .toList(growable: false),
          language: language,
          canCreate: canCreate,
          fixedProjectId: projectId,
          onCreate: createAccess.canWrite
              ? () => context.push(
                  RoutePaths.yorksV1MaterialRequestDraftPath(
                    const Uuid().v4(),
                    projectId: projectId,
                  ),
                )
              : null,
          onOpen: (request) => context.push(_materialRequestOpenPath(request)),
          onRefresh: () => ref.invalidate(yorksV1MaterialRequestListProvider),
          localDraftNotice: localDraftNotice,
        ),
      ),
    );
    if (embedded) return body;
    return Scaffold(backgroundColor: AppColors.surface, body: body);
  }
}

enum _MobileMaterialRequestFilter { all, draft, submitted, approved }

/// Phone-only, status-led register for the authorized MR projection.
///
/// Counts, owner labels and state chips are deliberately derived from the
/// records returned by [yorksV1MaterialRequestListProvider].  In particular,
/// a transport failure is not rendered as an empty register or a zero count.
class _YorksMobileMaterialRequestsPage extends ConsumerStatefulWidget {
  const _YorksMobileMaterialRequestsPage({
    this.projectId,
    this.embedded = false,
  });

  final String? projectId;
  final bool embedded;

  @override
  ConsumerState<_YorksMobileMaterialRequestsPage> createState() =>
      _YorksMobileMaterialRequestsPageState();
}

class _YorksMobileMaterialRequestsPageState
    extends ConsumerState<_YorksMobileMaterialRequestsPage> {
  _MobileMaterialRequestFilter _filter = _MobileMaterialRequestFilter.all;
  YorksV1MaterialRequestRegisterView _registerView =
      YorksV1MaterialRequestRegisterView.myWork;
  String _search = '';
  Timer? _searchDebounce;
  int _page = 0;

  YorksV1MaterialRequestSummaryQuery get _summaryQuery =>
      YorksV1MaterialRequestSummaryQuery(
        projectId: widget.projectId,
        search: _search,
        registerView: _registerView,
        states: switch (_filter) {
          _MobileMaterialRequestFilter.all => const [],
          _MobileMaterialRequestFilter.draft => const [
            YorksV1MaterialRequestState.draft,
          ],
          _MobileMaterialRequestFilter.submitted => const [
            ...yorksV1MaterialRequestSubmittedRegisterStates,
          ],
          _MobileMaterialRequestFilter.approved => const [
            ...yorksV1MaterialRequestApprovedRegisterStates,
          ],
        },
        limit: 15,
        offset: _page * 15,
      );

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _updateSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      final next = value.trim();
      if (next == _search) return;
      setState(() {
        _search = next;
        _page = 0;
      });
    });
  }

  Future<void> _refreshRequests() async {
    final repository = ref.read(yorksV1MaterialRequestRepositoryProvider);
    if (repository is YorksV1MaterialRequestOperationsRepository) {
      ref.invalidate(
        yorksV1MaterialRequestOperationsDashboardProvider(widget.projectId),
      );
    }
    if (repository is YorksV1MaterialRequestPhase2Repository) {
      final provider = yorksV1MaterialRequestSummaryPageProvider(_summaryQuery);
      ref.invalidate(provider);
      ref.invalidate(yorksV1MaterialRequestListProvider(widget.projectId));
      try {
        await ref.read(provider.future);
      } catch (_) {
        // The register's AsyncValue renders the existing retry experience.
      }
      return;
    }
    final provider = yorksV1MaterialRequestListProvider(widget.projectId);
    ref.invalidate(provider);
    try {
      await ref.read(provider.future);
    } catch (_) {
      // The register's AsyncValue renders the existing retry experience.
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final role = ref.watch(yorksV1CurrentRoleProvider);
    final permissionState = ref.watch(yorksV1CurrentPermissionSnapshotProvider);
    final createAccess = yorksV1FeatureActionAccess(
      permissionState,
      YorksV1CapabilityKeys.materialRequestsCreate,
      legacyAllowed: role?.canCreateMaterialRequest == true,
      projectId: widget.projectId,
      anyProject: widget.projectId == null,
    );
    final canCreate = createAccess.isVisible;
    final ownerAuthUserId = ref.watch(yorksV1AuthUserIdProvider);
    final deviceDrafts = ownerAuthUserId == null || ownerAuthUserId.isEmpty
        ? const <YorksV1MaterialRequestDraft>[]
        : ref
              .watch(yorksV1MaterialRequestLocalDraftsProvider(ownerAuthUserId))
              .where(
                (draft) =>
                    widget.projectId == null ||
                    draft.projectId == widget.projectId,
              )
              .toList(growable: false);
    final repository = ref.watch(yorksV1MaterialRequestRepositoryProvider);
    final phase2 = repository is YorksV1MaterialRequestPhase2Repository;
    final operations = repository is YorksV1MaterialRequestOperationsRepository
        ? ref.watch(
            yorksV1MaterialRequestOperationsDashboardProvider(widget.projectId),
          )
        : null;
    final accountDrafts =
        ownerAuthUserId == null || ownerAuthUserId.isEmpty || !phase2
        ? const <YorksV1PrivateMaterialRequestDraftRecord>[]
        : ref
                  .watch(
                    yorksV1MaterialRequestPrivateDraftsProvider(
                      ownerAuthUserId,
                    ),
                  )
                  .valueOrNull ??
              const <YorksV1PrivateMaterialRequestDraftRecord>[];
    final savedDrafts = _mergeRecoverableDrafts(
      deviceDrafts,
      accountDrafts.map((record) => record.draft),
      projectId: widget.projectId,
    );
    final summary = phase2
        ? ref.watch(yorksV1MaterialRequestSummaryPageProvider(_summaryQuery))
        : null;
    final requests =
        (summary == null || summary.hasError
                ? ref.watch(
                    yorksV1MaterialRequestListProvider(widget.projectId),
                  )
                : summary.whenData(
                    (page) => page.items
                        .map((request) => request.toRegisterProjection())
                        .toList(growable: false),
                  ))
            .whenData(
              (items) => items
                  .where(
                    (item) => yorksV1CanReadProjectRecord(
                      permissionState,
                      YorksV1CapabilityKeys.materialRequestsView,
                      legacyAllowed: true,
                      projectId: item.projectId,
                    ),
                  )
                  .toList(growable: false),
            );
    final body = Directionality(
      textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: ColoredBox(
        color: AppColors.mobileSurface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.embedded)
              YorksMobileAppBar(
                title: YorksV1MaterialRequestStrings.requests.active(language),
                leading: YorksMobileIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go(RoutePaths.engineerHome),
                ),
                trailing: YorksMobileIconButton(
                  icon: Icons.refresh_rounded,
                  tooltip: YorksV1MaterialRequestStrings.refresh.active(
                    language,
                  ),
                  onPressed: () => unawaited(_refreshRequests()),
                ),
              ),
            Expanded(
              child: requests.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => _MobileMaterialRequestError(
                  language: language,
                  onRetry: () => unawaited(_refreshRequests()),
                ),
                data: (items) => _MobileMaterialRequestRegister(
                  items: items,
                  language: language,
                  totalCount: summary?.hasError == true
                      ? null
                      : summary?.valueOrNull?.totalCount,
                  page: _page,
                  canCreate: canCreate,
                  localDrafts: savedDrafts,
                  operationsDashboard: operations,
                  onRetryOperations: operations == null
                      ? null
                      : () => ref.invalidate(
                          yorksV1MaterialRequestOperationsDashboardProvider(
                            widget.projectId,
                          ),
                        ),
                  registerView: _registerView,
                  onRegisterViewChanged: (value) => setState(() {
                    _registerView = value;
                    _page = 0;
                  }),
                  filter: _filter,
                  search: _search,
                  onSearchChanged: _updateSearch,
                  onFiltersChanged: (selection) => setState(() {
                    _registerView = selection.registerView;
                    _filter = selection.status;
                    _page = 0;
                  }),
                  onPageChanged: phase2 && summary?.hasError != true
                      ? (value) => setState(() => _page = value)
                      : null,
                  onCreate: createAccess.canWrite
                      ? () => context.push(
                          RoutePaths.yorksV1MaterialRequestDraftPath(
                            const Uuid().v4(),
                            projectId: widget.projectId,
                          ),
                        )
                      : null,
                  onOpen: (request) =>
                      context.push(_materialRequestOpenPath(request)),
                  onAction: (request) =>
                      context.push(_mobileMaterialRequestActionPath(request)),
                  onResume: (draft) => context.push(
                    RoutePaths.yorksV1MaterialRequestDraftPath(
                      draft.id,
                      projectId: draft.projectId,
                    ),
                  ),
                  onDeleteDraft: ownerAuthUserId == null
                      ? null
                      : (draft) => _deleteRecoverableDraft(
                          context,
                          ref,
                          ownerAuthUserId,
                          draft,
                        ),
                  onRefresh: _refreshRequests,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (widget.embedded) return body;
    return Scaffold(backgroundColor: AppColors.mobileSurface, body: body);
  }
}

class _MobileMaterialRequestFilterSelection {
  const _MobileMaterialRequestFilterSelection({
    required this.registerView,
    required this.status,
  });

  final YorksV1MaterialRequestRegisterView registerView;
  final _MobileMaterialRequestFilter status;
}

class _MobileMaterialRequestRegister extends StatelessWidget {
  const _MobileMaterialRequestRegister({
    required this.items,
    required this.language,
    this.totalCount,
    this.page = 0,
    required this.canCreate,
    required this.localDrafts,
    this.operationsDashboard,
    this.onRetryOperations,
    required this.registerView,
    required this.onRegisterViewChanged,
    required this.filter,
    required this.search,
    required this.onSearchChanged,
    required this.onFiltersChanged,
    this.onPageChanged,
    required this.onCreate,
    required this.onOpen,
    required this.onAction,
    required this.onResume,
    this.onDeleteDraft,
    required this.onRefresh,
  });

  final List<YorksV1MaterialRequest> items;
  final AppLanguage language;
  final int? totalCount;
  final int page;
  final bool canCreate;
  final List<YorksV1MaterialRequestDraft> localDrafts;
  final AsyncValue<YorksV1MaterialRequestOperationsDashboard>?
  operationsDashboard;
  final VoidCallback? onRetryOperations;
  final YorksV1MaterialRequestRegisterView registerView;
  final ValueChanged<YorksV1MaterialRequestRegisterView> onRegisterViewChanged;
  final _MobileMaterialRequestFilter filter;
  final String search;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_MobileMaterialRequestFilterSelection> onFiltersChanged;
  final ValueChanged<int>? onPageChanged;
  final VoidCallback? onCreate;
  final ValueChanged<YorksV1MaterialRequest> onOpen;
  final ValueChanged<YorksV1MaterialRequest> onAction;
  final ValueChanged<YorksV1MaterialRequestDraft> onResume;
  final Future<void> Function(YorksV1MaterialRequestDraft draft)? onDeleteDraft;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final visible = items
        .where(_matches)
        .where(_matchesSearch)
        .toList(growable: false);
    final activeFilterCount =
        (filter == _MobileMaterialRequestFilter.all ? 0 : 1) +
        ((registerView == YorksV1MaterialRequestRegisterView.myWork ||
                registerView == YorksV1MaterialRequestRegisterView.total)
            ? 0
            : 1);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const ValueKey('mobile-material-request-register'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 104),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      YorksV1MaterialRequestStrings.requests.active(language),
                      style: AppTypography.headlineMedium.copyWith(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      YorksV1MaterialRequestStrings.mobileRequestsDescription
                          .active(language),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (canCreate)
                FilledButton.icon(
                  key: const ValueKey('mobile-mr-new-request'),
                  onPressed: onCreate,
                  icon: const Icon(Icons.add_rounded, size: 19),
                  label: Text(
                    YorksV1MaterialRequestStrings.newRequestShort.active(
                      language,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, AppSpacing.minTapTarget),
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<YorksV1MaterialRequestRegisterView>(
              key: const ValueKey('mobile-mr-primary-views'),
              segments: [
                ButtonSegment(
                  value: YorksV1MaterialRequestRegisterView.myWork,
                  label: Text(
                    YorksV1MaterialRequestStrings.myWork.active(language),
                  ),
                  icon: const Icon(Icons.task_alt_rounded, size: 18),
                ),
                ButtonSegment(
                  value: YorksV1MaterialRequestRegisterView.total,
                  label: Text(
                    YorksV1MaterialRequestStrings.allRequests.active(language),
                  ),
                  icon: const Icon(Icons.list_alt_rounded, size: 18),
                ),
              ],
              selected:
                  registerView == YorksV1MaterialRequestRegisterView.myWork ||
                      registerView == YorksV1MaterialRequestRegisterView.total
                  ? {registerView}
                  : const {},
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                if (selection.isNotEmpty) {
                  onRegisterViewChanged(selection.first);
                }
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MobileMaterialRequestSearchField(
                  language: language,
                  initialValue: search,
                  onChanged: onSearchChanged,
                ),
              ),
              const SizedBox(width: 8),
              _MobileMaterialRequestFilterButton(
                language: language,
                activeCount: activeFilterCount,
                onPressed: () async {
                  final selection = await _showMobileMaterialRequestFilters(
                    context,
                    language: language,
                    initial: _MobileMaterialRequestFilterSelection(
                      registerView: registerView,
                      status: filter,
                    ),
                  );
                  if (selection != null) onFiltersChanged(selection);
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (canCreate && localDrafts.isNotEmpty) ...[
            _RecoverableMaterialDraftNotice(
              drafts: localDrafts,
              onResume: onResume,
              onDelete: onDeleteDraft,
              compact: true,
            ),
            const SizedBox(height: 14),
          ],
          if (items.isEmpty &&
              search.isEmpty &&
              filter == _MobileMaterialRequestFilter.all &&
              registerView == YorksV1MaterialRequestRegisterView.total)
            _MobileMaterialRequestEmpty(
              canCreate: canCreate,
              onCreate: onCreate,
            )
          else if (visible.isEmpty)
            _MobileMaterialRequestNoMatches()
          else
            for (final request in visible) ...[
              _MobileMaterialRequestCard(
                request: request,
                language: language,
                onTap: () => onOpen(request),
                onAction: () => onAction(request),
              ),
              const SizedBox(height: 10),
            ],
          if (onPageChanged != null && (totalCount ?? items.length) > 15) ...[
            const SizedBox(height: AppSpacing.xs),
            _MobileMaterialRequestPager(
              page: page,
              totalCount: totalCount ?? items.length,
              onPageChanged: onPageChanged!,
            ),
          ],
          if (operationsDashboard != null) ...[
            const SizedBox(height: AppSpacing.md),
            YorksV1MaterialRequestOperationalInsightsPanel(
              language: language,
              dashboard: operationsDashboard!.valueOrNull,
              loading: operationsDashboard!.isLoading,
              failed: operationsDashboard!.hasError,
              onRetry: onRetryOperations ?? onRefresh,
            ),
          ],
        ],
      ),
    );
  }

  bool _matches(YorksV1MaterialRequest request) => switch (filter) {
    _MobileMaterialRequestFilter.all => true,
    _MobileMaterialRequestFilter.draft => request.state.isDraft,
    _MobileMaterialRequestFilter.submitted =>
      yorksV1MaterialRequestSubmittedRegisterStates.contains(request.state),
    _MobileMaterialRequestFilter.approved =>
      yorksV1MaterialRequestApprovedRegisterStates.contains(request.state),
  };

  bool _matchesSearch(YorksV1MaterialRequest request) {
    final query = search.trim().toLowerCase();
    if (query.isEmpty) return true;
    return [
      request.requestNumber,
      request.title,
      request.projectReference,
      request.projectName,
      request.scopeName,
      request.deliveryNote,
      ...request.lines.map((line) => line.description),
    ].whereType<String>().any((value) => value.toLowerCase().contains(query));
  }
}

Future<_MobileMaterialRequestFilterSelection?>
_showMobileMaterialRequestFilters(
  BuildContext context, {
  required AppLanguage language,
  required _MobileMaterialRequestFilterSelection initial,
}) {
  var registerView = initial.registerView;
  var status = initial.status;
  return showModalBottomSheet<_MobileMaterialRequestFilterSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => FractionallySizedBox(
        heightFactor: 0.88,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      YorksV1MaterialRequestStrings.filters.active(language),
                      style: AppTypography.titleLarge.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setSheetState(() {
                      registerView = YorksV1MaterialRequestRegisterView.total;
                      status = _MobileMaterialRequestFilter.all;
                    }),
                    child: Text(
                      YorksV1MaterialRequestStrings.clearAll.active(language),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                    child: Text(
                      YorksV1MaterialRequestStrings.requestView.active(
                        language,
                      ),
                      style: AppTypography.labelLarge.copyWith(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  RadioGroup<YorksV1MaterialRequestRegisterView>(
                    groupValue: registerView,
                    onChanged: (value) {
                      if (value == null) return;
                      setSheetState(() => registerView = value);
                    },
                    child: Column(
                      children: [
                        for (final option
                            in YorksV1MaterialRequestRegisterView.values)
                          RadioListTile<YorksV1MaterialRequestRegisterView>(
                            value: option,
                            title: Text(
                              _mobileRegisterViewCopy(option).active(language),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 28),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                    child: Text(
                      YorksV1MaterialRequestStrings.requestStatusFilter.active(
                        language,
                      ),
                      style: AppTypography.labelLarge.copyWith(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  RadioGroup<_MobileMaterialRequestFilter>(
                    groupValue: status,
                    onChanged: (value) {
                      if (value == null) return;
                      setSheetState(() => status = value);
                    },
                    child: Column(
                      children: [
                        for (final option
                            in _MobileMaterialRequestFilter.values)
                          RadioListTile<_MobileMaterialRequestFilter>(
                            value: option,
                            title: Text(
                              _mobileRequestStatusFilterCopy(
                                option,
                              ).active(language),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            YorksMobileStickyActions(
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: Text(
                    YorksV1MaterialRequestStrings.cancel.active(language),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(
                    sheetContext,
                    _MobileMaterialRequestFilterSelection(
                      registerView: registerView,
                      status: status,
                    ),
                  ),
                  icon: const Icon(Icons.filter_alt_rounded, size: 18),
                  label: Text(
                    YorksV1MaterialRequestStrings.applyFilters.active(language),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

TranslatableString _mobileRegisterViewCopy(
  YorksV1MaterialRequestRegisterView value,
) => switch (value) {
  YorksV1MaterialRequestRegisterView.total =>
    YorksV1MaterialRequestStrings.allRequests,
  YorksV1MaterialRequestRegisterView.mine =>
    YorksV1MaterialRequestStrings.myMaterialRequests,
  YorksV1MaterialRequestRegisterView.assigned =>
    YorksV1MaterialRequestStrings.assignedMaterialRequests,
  YorksV1MaterialRequestRegisterView.myWork =>
    YorksV1MaterialRequestStrings.myWork,
  YorksV1MaterialRequestRegisterView.exceptions =>
    YorksV1MaterialRequestStrings.exceptions,
};

TranslatableString _mobileRequestStatusFilterCopy(
  _MobileMaterialRequestFilter value,
) => switch (value) {
  _MobileMaterialRequestFilter.all => YorksV1MaterialRequestStrings.allStatuses,
  _MobileMaterialRequestFilter.draft => YorksV1MaterialRequestStrings.draft,
  _MobileMaterialRequestFilter.submitted =>
    YorksV1MaterialRequestStrings.submitted,
  _MobileMaterialRequestFilter.approved =>
    YorksV1MaterialRequestStrings.approved,
};

class _MobileMaterialRequestSearchField extends StatefulWidget {
  const _MobileMaterialRequestSearchField({
    required this.language,
    required this.initialValue,
    required this.onChanged,
  });

  final AppLanguage language;
  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  State<_MobileMaterialRequestSearchField> createState() =>
      _MobileMaterialRequestSearchFieldState();
}

class _MobileMaterialRequestSearchFieldState
    extends State<_MobileMaterialRequestSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant _MobileMaterialRequestSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue &&
        widget.initialValue != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.initialValue,
        selection: TextSelection.collapsed(offset: widget.initialValue.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: const ValueKey('mobile-mr-search'),
    controller: _controller,
    onChanged: (value) {
      setState(() {});
      widget.onChanged(value);
    },
    onSubmitted: widget.onChanged,
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      hintText: YorksV1MaterialRequestStrings.searchRequests.active(
        widget.language,
      ),
      prefixIcon: const Icon(Icons.search_rounded),
      suffixIcon: _controller.text.isEmpty
          ? null
          : IconButton(
              tooltip: YorksV1MaterialRequestStrings.clearAll.active(
                widget.language,
              ),
              onPressed: () {
                _controller.clear();
                setState(() {});
                widget.onChanged('');
              },
              icon: const Icon(Icons.close_rounded),
            ),
    ),
  );
}

class _MobileMaterialRequestFilterButton extends StatelessWidget {
  const _MobileMaterialRequestFilterButton({
    required this.language,
    required this.activeCount,
    required this.onPressed,
  });

  final AppLanguage language;
  final int activeCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: AppSpacing.minTapTarget + 4,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: OutlinedButton(
            key: const ValueKey('mobile-mr-filters'),
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
            child: const Icon(Icons.tune_rounded),
          ),
        ),
        if (activeCount > 0)
          PositionedDirectional(
            top: -4,
            end: -4,
            child: Semantics(
              label:
                  '${YorksV1MaterialRequestStrings.filters.active(language)}: $activeCount',
              child: Container(
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: const BoxDecoration(
                  color: AppColors.blue,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$activeCount',
                  style: AppTypography.labelSmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _MobileMaterialRequestPager extends StatelessWidget {
  const _MobileMaterialRequestPager({
    required this.page,
    required this.totalCount,
    required this.onPageChanged,
  });

  final int page;
  final int totalCount;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final start = page * 15 + 1;
    final end = (start + 14).clamp(0, totalCount);
    final hasNext = end < totalCount;
    return Row(
      children: [
        Expanded(
          child: Text(
            '$start–$end / $totalCount',
            style: AppTypography.labelMedium.copyWith(color: AppColors.muted),
          ),
        ),
        SizedBox.square(
          dimension: AppSpacing.minTapTarget,
          child: IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: MaterialLocalizations.of(context).previousPageTooltip,
            onPressed: page > 0 ? () => onPageChanged(page - 1) : null,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        SizedBox.square(
          dimension: AppSpacing.minTapTarget,
          child: IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: MaterialLocalizations.of(context).nextPageTooltip,
            onPressed: hasNext ? () => onPageChanged(page + 1) : null,
          ),
        ),
      ],
    );
  }
}

/// The server request queue intentionally excludes incomplete records.  This
/// explicit owner/device-local recovery notice makes those drafts discoverable
/// without presenting them as Procurement-visible workflow records.
class _RecoverableMaterialDraftNotice extends StatelessWidget {
  const _RecoverableMaterialDraftNotice({
    required this.drafts,
    required this.onResume,
    this.onDelete,
    this.compact = false,
  });

  final List<YorksV1MaterialRequestDraft> drafts;
  final ValueChanged<YorksV1MaterialRequestDraft> onResume;
  final Future<void> Function(YorksV1MaterialRequestDraft draft)? onDelete;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final visibleDrafts = compact ? drafts.take(3) : drafts.take(5);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: compact ? 36 : 42,
              height: compact ? 36 : 42,
              decoration: BoxDecoration(
                color: AppColors.blueContainer,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: const Icon(Icons.restore_rounded, color: AppColors.blue),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    YorksV1MaterialRequestStrings.localDraftCount(
                      drafts.length,
                    ).primary,
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 2),
                    Text(
                      YorksV1MaterialRequestStrings.localDraftPrivate.primary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
        const SizedBox(height: AppSpacing.sm),
        for (final draft in visibleDrafts)
          _RecoverableDraftRow(
            draft: draft,
            compact: compact,
            onResume: () => onResume(draft),
            onDelete: onDelete == null ? null : () => onDelete!(draft),
          ),
      ],
    );
    return LedgerCard(
      color: AppColors.surfaceContainerLow,
      padding: EdgeInsets.all(compact ? 12 : AppSpacing.md),
      child: body,
    );
  }
}

class _RecoverableDraftRow extends StatelessWidget {
  const _RecoverableDraftRow({
    required this.draft,
    required this.compact,
    required this.onResume,
    this.onDelete,
  });

  final YorksV1MaterialRequestDraft draft;
  final bool compact;
  final VoidCallback onResume;
  final Future<void> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    final title = draft.title?.trim();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Material(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: InkWell(
          onTap: onResume,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                const Icon(Icons.edit_note_rounded, color: AppColors.blue),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    title == null || title.isEmpty
                        ? YorksV1MaterialRequestStrings
                              .materialRequestDraft
                              .primary
                        : title,
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge,
                  ),
                ),
                TextButton(
                  onPressed: onResume,
                  child: Text(
                    YorksV1MaterialRequestStrings.resumeSavedDraft.primary,
                  ),
                ),
                if (onDelete != null)
                  IconButton(
                    tooltip: YorksV1MaterialRequestStrings.deleteDraft.primary,
                    onPressed: () => unawaited(onDelete!()),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

List<YorksV1MaterialRequestDraft> _mergeRecoverableDrafts(
  Iterable<YorksV1MaterialRequestDraft> deviceDrafts,
  Iterable<YorksV1MaterialRequestDraft> accountDrafts, {
  String? projectId,
}) {
  final byId = <String, YorksV1MaterialRequestDraft>{};
  for (final draft in [...deviceDrafts, ...accountDrafts]) {
    if (projectId != null && draft.projectId != projectId) continue;
    final current = byId[draft.id];
    if (current == null || draft.updatedAt.isAfter(current.updatedAt)) {
      byId[draft.id] = draft;
    }
  }
  final result = byId.values.toList(growable: false)
    ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  return List.unmodifiable(result);
}

Future<void> _deleteRecoverableDraft(
  BuildContext context,
  WidgetRef ref,
  String ownerAuthUserId,
  YorksV1MaterialRequestDraft draft,
) async {
  final language = ref.read(languageProvider);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(YorksV1MaterialRequestStrings.deleteDraft.active(language)),
      content: Text(
        YorksV1MaterialRequestStrings.deleteDraftBody.active(language),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(YorksV1MaterialRequestStrings.cancel.active(language)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            YorksV1MaterialRequestStrings.deleteDraft.active(language),
          ),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final key = YorksV1MaterialRequestDraftKey(
    ownerAuthUserId: ownerAuthUserId,
    draftId: draft.id,
  );
  try {
    final controller = ref.read(
      yorksV1MaterialRequestDraftControllerProvider(key).notifier,
    );
    await controller.hydratePrivateDraft();
    await controller.discardLocal(requireServerConfirmation: true);
    ref.invalidate(
      yorksV1MaterialRequestPrivateDraftsProvider(ownerAuthUserId),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          YorksV1MaterialRequestStrings.draftDeleted.active(language),
        ),
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          YorksV1MaterialRequestStrings.draftDeleteFailed.active(language),
        ),
      ),
    );
  }
}

class _MobileMaterialRequestCard extends StatelessWidget {
  const _MobileMaterialRequestCard({
    required this.request,
    required this.language,
    required this.onTap,
    required this.onAction,
  });

  final YorksV1MaterialRequest request;
  final AppLanguage language;
  final VoidCallback onTap;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final action = _mobileMaterialRequestCardAction(request, language);
    return YorksMobileCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  request.requestNumber ??
                      YorksV1MaterialRequestStrings.draft.primary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.blue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _MobileRequestStateChip(request: request),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            request.title?.trim().isNotEmpty == true
                ? request.title!
                : request.projectName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.titleSmall.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${request.projectReference} · ${request.scopeName}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 9),
          _MobileRequestWorkflowFact(
            icon: Icons.person_outline_rounded,
            label: YorksV1MaterialRequestStrings.currentOwner.active(language),
            value: yorksV1MaterialRequestOwnerRoleCopy(
              request.currentActionOwnerRole,
            ).active(language),
          ),
          const SizedBox(height: 5),
          _MobileRequestWorkflowFact(
            icon: Icons.arrow_forward_rounded,
            label: YorksV1MaterialRequestStrings.nextAction.active(language),
            value: yorksV1MaterialRequestNextActionCopy(
              request,
            ).active(language),
          ),
          if (request.scheduledDate != null) ...[
            const SizedBox(height: 5),
            _MobileRequestWorkflowFact(
              icon: request.requiredOnSiteOverdue
                  ? Icons.event_busy_outlined
                  : Icons.event_outlined,
              label: YorksV1MaterialRequestStrings.requiredOnSite.active(
                language,
              ),
              value: MaterialLocalizations.of(
                context,
              ).formatMediumDate(request.scheduledDate!.toLocal()),
              alert: request.requiredOnSiteOverdue,
            ),
          ],
          if (request.currentActionAgeHours > 0) ...[
            const SizedBox(height: 5),
            _MobileRequestWorkflowFact(
              icon: Icons.schedule_outlined,
              label: YorksV1MaterialRequestStrings.actionAge.active(language),
              value: _formatMaterialRequestActionAge(
                request.currentActionAgeHours,
              ),
            ),
          ],
          if (request.exceptionCodes.isNotEmpty) ...[
            const SizedBox(height: 9),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final code in request.exceptionCodes)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warningContainer,
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusFull,
                      ),
                    ),
                    child: Text(
                      yorksV1MaterialRequestExceptionCopy(
                        code,
                      ).active(language),
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.onWarningContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  size: 17,
                  color: AppColors.blue,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    YorksV1MaterialRequestStrings.itemsCount(
                      request.displayItemCount,
                    ).active(language),
                    style: AppTypography.labelMedium,
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: ValueKey('mobile-mr-card-action-${request.id}'),
                onPressed: onAction,
                icon: Icon(action.icon, size: 18),
                label: Text(action.label),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MobileRequestWorkflowFact extends StatelessWidget {
  const _MobileRequestWorkflowFact({
    required this.icon,
    required this.label,
    required this.value,
    this.alert = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool alert;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 16, color: alert ? AppColors.error : AppColors.muted),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          '$label: $value',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelSmall.copyWith(
            color: alert ? AppColors.error : AppColors.inkSecondary,
            fontWeight: alert ? FontWeight.w700 : null,
          ),
        ),
      ),
    ],
  );
}

String _formatMaterialRequestActionAge(double hours) {
  if (hours >= 48) return '${(hours / 24).floor()} d';
  if (hours >= 1) return '${hours.floor()} h';
  return '<1 h';
}

class _MobileRequestStateChip extends StatelessWidget {
  const _MobileRequestStateChip({required this.request});

  final YorksV1MaterialRequest request;

  @override
  Widget build(BuildContext context) {
    final done =
        request.state == YorksV1MaterialRequestState.received ||
        request.state == YorksV1MaterialRequestState.closed;
    final cancelled = request.state == YorksV1MaterialRequestState.cancelled;
    final background = cancelled
        ? AppColors.errorContainer
        : done
        ? AppColors.successContainer
        : AppColors.blueContainer;
    final foreground = cancelled
        ? AppColors.onErrorContainer
        : done
        ? AppColors.onSuccessContainer
        : AppColors.onPrimaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        yorksV1MaterialRequestStateCopy(request.state).primary,
        style: AppTypography.labelSmall.copyWith(
          color: foreground,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MobileMaterialRequestEmpty extends StatelessWidget {
  const _MobileMaterialRequestEmpty({required this.canCreate, this.onCreate});

  final bool canCreate;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) => YorksMobileCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          const Icon(Icons.inbox_outlined, size: 38, color: AppColors.muted),
          const SizedBox(height: 10),
          Text(
            YorksV1MaterialRequestStrings.noRequests.primary,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
          ),
          if (canCreate) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded),
              label: Text(YorksV1MaterialRequestStrings.newRequest.primary),
            ),
          ],
        ],
      ),
    ),
  );
}

class _MobileMaterialRequestNoMatches extends StatelessWidget {
  @override
  Widget build(BuildContext context) => YorksMobileCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Text(
        YorksV1MaterialRequestStrings.noRequests.primary,
        textAlign: TextAlign.center,
        style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
      ),
    ),
  );
}

class _MobileMaterialRequestError extends StatelessWidget {
  const _MobileMaterialRequestError({
    required this.language,
    required this.onRetry,
  });

  final AppLanguage language;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: YorksMobileCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.sync_problem_rounded,
              size: 38,
              color: AppColors.error,
            ),
            const SizedBox(height: 12),
            _CopyText(
              copy: YorksV1MaterialRequestStrings.saveFailed,
              language: language,
              center: true,
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(YorksV1MaterialRequestStrings.refresh.primary),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Route-level R35 queues make the sidebar Dispatches and Material Returns
/// destinations usable without first opening a specific material request.
/// They are safe server projections only; selection simply opens the existing
/// request-scoped workflow that owns all transition commands.
enum YorksV1WorkflowQueueKind { dispatches, returns }

class YorksV1WorkflowQueueScreen extends ConsumerWidget {
  const YorksV1WorkflowQueueScreen({super.key, required this.kind});

  final YorksV1WorkflowQueueKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final requests = ref.watch(yorksV1MaterialRequestListProvider(null));
    if (kind == YorksV1WorkflowQueueKind.dispatches) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          top: false,
          child: requests.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => _RequestError(
              language: language,
              onRetry: () => ref.invalidate(yorksV1MaterialRequestListProvider),
            ),
            data: (items) => YorksV1DispatchCentre(
              requests: items,
              language: language,
              onOpen: (request) => context.push(
                RoutePaths.yorksV1MaterialRequestLogisticsPath(request.id),
              ),
              onRefresh: () =>
                  ref.invalidate(yorksV1MaterialRequestListProvider),
            ),
          ),
        ),
      );
    }
    final title = switch (kind) {
      YorksV1WorkflowQueueKind.dispatches => YorksV1ShellStrings.dispatches,
      YorksV1WorkflowQueueKind.returns => YorksV1ShellStrings.materialReturns,
    };
    final description = switch (kind) {
      YorksV1WorkflowQueueKind.dispatches =>
        YorksV1LogisticsStrings.dispatchAndReceipt,
      YorksV1WorkflowQueueKind.returns =>
        YorksV1LogisticsStrings.deliveryOrdersAndReturns,
    };

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        top: false,
        child: NexusPageShell(
          eyebrow: YorksV1ShellStrings.operationalWorkspace.primary,
          title: title.primary,
          description: description.primary,
          actions: [
            SizedBox(
              height: AppSpacing.controlHeight,
              child: OutlinedButton.icon(
                onPressed: () =>
                    ref.invalidate(yorksV1MaterialRequestListProvider),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(YorksV1MaterialRequestStrings.refresh.primary),
              ),
            ),
          ],
          child: requests.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.huge),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (_, _) => _RequestError(
              language: language,
              onRetry: () => ref.invalidate(yorksV1MaterialRequestListProvider),
            ),
            data: (items) {
              final visible = [
                for (final request in items)
                  if (_isVisibleInQueue(request, kind)) request,
              ];
              if (visible.isEmpty) {
                return _WorkflowQueueEmpty(kind: kind, language: language);
              }
              return LedgerCard(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        AppSpacing.lg,
                        AppSpacing.xl,
                        AppSpacing.md,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title.primary,
                              style: AppTypography.titleMedium.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          StatusChip.info(
                            '${visible.length}',
                            icon: Icons.format_list_numbered_rounded,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.line),
                    for (var index = 0; index < visible.length; index++) ...[
                      _WorkflowQueueRow(
                        request: visible[index],
                        kind: kind,
                        language: language,
                      ),
                      if (index + 1 < visible.length)
                        const Divider(height: 1, color: AppColors.line),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  bool _isVisibleInQueue(
    YorksV1MaterialRequest request,
    YorksV1WorkflowQueueKind value,
  ) {
    return switch (value) {
      YorksV1WorkflowQueueKind.dispatches => switch (request.state) {
        YorksV1MaterialRequestState.approved ||
        YorksV1MaterialRequestState.partiallyDispatched ||
        YorksV1MaterialRequestState.dispatched ||
        YorksV1MaterialRequestState.partiallyReceived ||
        YorksV1MaterialRequestState.received ||
        YorksV1MaterialRequestState.closed => true,
        _ => false,
      },
      YorksV1WorkflowQueueKind.returns => switch (request.state) {
        YorksV1MaterialRequestState.partiallyReceived ||
        YorksV1MaterialRequestState.received ||
        YorksV1MaterialRequestState.closed => true,
        _ => false,
      },
    };
  }
}

class _WorkflowQueueRow extends StatelessWidget {
  const _WorkflowQueueRow({
    required this.request,
    required this.kind,
    required this.language,
  });

  final YorksV1MaterialRequest request;
  final YorksV1WorkflowQueueKind kind;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final action = switch (kind) {
      YorksV1WorkflowQueueKind.dispatches =>
        YorksV1LogisticsStrings.dispatchAndReceipt,
      YorksV1WorkflowQueueKind.returns =>
        YorksV1LogisticsStrings.deliveryOrdersAndReturns,
    };
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push(
          kind == YorksV1WorkflowQueueKind.dispatches
              ? RoutePaths.yorksV1MaterialRequestLogisticsPath(request.id)
              : RoutePaths.yorksV1MaterialRequestReturnsDocumentsPath(
                  request.id,
                ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 620;
                final identity = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.requestNumber ??
                          YorksV1MaterialRequestStrings.draft.primary,
                      style: AppTypography.labelLarge.copyWith(
                        color: AppColors.blue,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      request.title ?? request.projectName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${request.projectReference} · ${request.scopeName} · ${YorksV1MaterialRequestStrings.itemsCount(request.displayItemCount).active(language)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '${YorksV1MaterialRequestStrings.currentOwner.active(language)}: ${yorksV1MaterialRequestOwnerRoleCopy(request.currentActionOwnerRole).active(language)} · ${YorksV1MaterialRequestStrings.nextAction.active(language)}: ${yorksV1MaterialRequestNextActionCopy(request).active(language)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.inkSecondary,
                      ),
                    ),
                  ],
                );
                final controls = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StateChip(request: request, language: AppLanguage.english),
                    const SizedBox(width: AppSpacing.sm),
                    Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                  ],
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      identity,
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              action.primary,
                              style: AppTypography.labelMedium.copyWith(
                                color: AppColors.inkSecondary,
                              ),
                            ),
                          ),
                          controls,
                        ],
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: identity),
                    const SizedBox(width: AppSpacing.lg),
                    Text(
                      action.primary,
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.inkSecondary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    controls,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkflowQueueEmpty extends StatelessWidget {
  const _WorkflowQueueEmpty({required this.kind, required this.language});

  final YorksV1WorkflowQueueKind kind;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final copy = switch (kind) {
      YorksV1WorkflowQueueKind.dispatches =>
        YorksV1LogisticsStrings.noDeliveryOrders,
      YorksV1WorkflowQueueKind.returns =>
        YorksV1MaterialRequestStrings.noRequests,
    };
    return LedgerCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              kind == YorksV1WorkflowQueueKind.dispatches
                  ? Icons.local_shipping_outlined
                  : Icons.assignment_return_outlined,
              size: 42,
              color: AppColors.muted,
            ),
            const SizedBox(height: AppSpacing.lg),
            _CopyText(copy: copy, language: language, center: true),
          ],
        ),
      ),
    );
  }
}

class YorksV1MaterialRequestDraftScreen extends ConsumerStatefulWidget {
  const YorksV1MaterialRequestDraftScreen({
    super.key,
    required this.draftId,
    this.boqGroupId,
    this.projectId,
    this.boqVersion,
  });

  final String draftId;
  final String? boqGroupId;
  final String? projectId;
  final int? boqVersion;

  @override
  ConsumerState<YorksV1MaterialRequestDraftScreen> createState() =>
      _YorksV1MaterialRequestDraftScreenState();
}

class _YorksV1MaterialRequestDraftScreenState
    extends ConsumerState<YorksV1MaterialRequestDraftScreen> {
  bool _seededFromBoq = false;
  bool _seededProjectFromRoute = false;
  bool _hydratedFromServer = false;
  bool _runtimePolicyResolutionScheduled = false;
  bool _runtimePolicyResolved = false;
  bool _workspacePresentationPrepared = false;
  bool? _sidebarWasExpanded;
  StateController<bool>? _sidebarController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_workspacePresentationPrepared ||
        MediaQuery.sizeOf(context).width <
            AppSpacing.yorksV1ShellDesktopBreakpoint) {
      return;
    }
    _workspacePresentationPrepared = true;
    _sidebarWasExpanded = ref.read(yorksV1WorkspaceSidebarExpandedProvider);
    _sidebarController = ref.read(
      yorksV1WorkspaceSidebarExpandedProvider.notifier,
    );
    if (_sidebarWasExpanded == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _sidebarController?.state = false;
      });
    }
  }

  @override
  void dispose() {
    final previous = _sidebarWasExpanded;
    final sidebarController = _sidebarController;
    if (previous != null && sidebarController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (sidebarController.mounted) {
          sidebarController.state = previous;
        }
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(yorksV1AuthUserIdProvider);
    final language = ref.watch(languageProvider);
    if (owner == null || owner.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(backgroundColor: AppColors.surface),
        body: _RequestError(language: language, onRetry: () {}),
      );
    }
    final key = YorksV1MaterialRequestDraftKey(
      ownerAuthUserId: owner,
      draftId: widget.draftId,
    );
    final state = ref.watch(yorksV1MaterialRequestDraftControllerProvider(key));
    final controller = ref.read(
      yorksV1MaterialRequestDraftControllerProvider(key).notifier,
    );
    final runtimeConfiguration = ref.watch(yorksV1RuntimeConfigurationProvider);
    final shouldHydrateFromServer =
        state.draft.serverRecordVersion == 0 &&
        state.draft.updatedAt.millisecondsSinceEpoch == 0;
    final serverDraft = shouldHydrateFromServer
        ? ref.watch(yorksV1MaterialRequestDetailProvider(widget.draftId))
        : null;
    if (!_hydratedFromServer &&
        serverDraft is AsyncData<YorksV1MaterialRequest>) {
      final request = serverDraft.value;
      if (request.state.isDraft || request.canEditBeforeApproval) {
        _hydratedFromServer = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) controller.hydrateFromServer(request);
        });
      }
    }
    final runtimeDefaultCanBeApplied =
        runtimeConfiguration is AsyncData<YorksV1RuntimeConfiguration> &&
        _serverDraftIsAbsent(serverDraft) &&
        _isPristineForRuntimeDefault(state.draft);
    if (!_runtimePolicyResolved &&
        !_runtimePolicyResolutionScheduled &&
        runtimeDefaultCanBeApplied) {
      _runtimePolicyResolutionScheduled = true;
      final configuration = runtimeConfiguration.value;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _resolveRuntimePolicy(controller, configuration);
      });
    }
    final runtimePolicyAllowsAutomaticSeeding =
        _runtimePolicyResolved ||
        !_isPristineForRuntimeDefault(state.draft) ||
        runtimeConfiguration is AsyncError ||
        (runtimeConfiguration is AsyncData<YorksV1RuntimeConfiguration> &&
            serverDraft is AsyncError &&
            !_serverDraftIsAbsent(serverDraft));
    final routeProjectId = widget.projectId?.trim();
    final canSeedProjectFromRoute =
        routeProjectId != null &&
        routeProjectId.isNotEmpty &&
        state.draft.projectId == null &&
        runtimePolicyAllowsAutomaticSeeding &&
        (!_shouldHydrateFromServer(state) || serverDraft is AsyncError);
    if (!_seededProjectFromRoute && canSeedProjectFromRoute) {
      _seededProjectFromRoute = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.setProject(routeProjectId);
      });
    }
    if (!_seededFromBoq &&
        widget.boqGroupId != null &&
        runtimePolicyAllowsAutomaticSeeding) {
      _seededFromBoq = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _seedDraftFromBoq(controller, state.draft);
      });
    }
    return _DraftForm(
      state: state,
      controller: controller,
      draftKey: key,
      language: language,
    );
  }

  bool _shouldHydrateFromServer(YorksV1MaterialRequestDraftState state) =>
      state.draft.serverRecordVersion == 0 &&
      state.draft.updatedAt.millisecondsSinceEpoch == 0;

  bool _serverDraftIsAbsent(AsyncValue<YorksV1MaterialRequest>? serverDraft) {
    if (serverDraft is! AsyncError<YorksV1MaterialRequest>) return false;
    final error = serverDraft.error;
    return error is YorksV1DomainException &&
        error.code == YorksV1DomainErrorCode.unauthorized;
  }

  bool _isPristineForRuntimeDefault(YorksV1MaterialRequestDraft draft) =>
      draft.serverRecordVersion == 0 &&
      draft.updatedAt.millisecondsSinceEpoch == 0 &&
      !draft.hasRecoverableContent &&
      draft.timing == YorksV1MaterialRequestTiming.normal &&
      draft.scheduledDate == null;

  Future<void> _resolveRuntimePolicy(
    YorksV1MaterialRequestDraftController controller,
    YorksV1RuntimeConfiguration configuration,
  ) async {
    try {
      // The owner-only recovery copy must win over a published default.
      // Calling hydration here also closes the short race between the
      // controller's startup reconciliation and the independent policy call.
      await controller.hydratePrivateDraft();
      if (!mounted) return;
      final current = controller.currentDraft;
      if (_isPristineForRuntimeDefault(current)) {
        final configured = YorksV1MaterialRequestTiming.fromWireValue(
          configuration.defaultTiming,
        );
        final defaultTiming =
            configured == YorksV1MaterialRequestTiming.urgent &&
                configuration.urgentEnabled != true
            ? YorksV1MaterialRequestTiming.normal
            : configured ?? YorksV1MaterialRequestTiming.normal;
        if (defaultTiming != current.timing) {
          await controller.setTiming(defaultTiming);
        }
      }
    } catch (_) {
      // A runtime default is a convenience, never an editing authority. Keep
      // the model's safe Normal default if local recovery/storage is unable to
      // accept the published preference during initialization.
    } finally {
      if (mounted) {
        setState(() {
          _runtimePolicyResolved = true;
        });
      }
    }
  }

  Future<void> _seedDraftFromBoq(
    YorksV1MaterialRequestDraftController controller,
    YorksV1MaterialRequestDraft draft,
  ) async {
    final groupId = widget.boqGroupId?.trim();
    final projectId = widget.projectId?.trim();
    if (groupId == null || groupId.isEmpty || draft.lines.isNotEmpty) return;
    try {
      final worksheet = await ref
          .read(yorksV1BoqRepositoryProvider)
          .getWorksheet(groupId);
      if (widget.boqVersion != null &&
          worksheet.group.version != widget.boqVersion) {
        throw const YorksV1DomainException(YorksV1DomainErrorCode.conflict);
      }
      final worksheetProjectId = worksheet.group.projectId.trim();
      if (projectId != null &&
          projectId.isNotEmpty &&
          worksheetProjectId != projectId) {
        throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
      }
      final selectedProjectId = projectId?.isNotEmpty == true
          ? projectId!
          : worksheetProjectId;
      if (!await controller.setProject(selectedProjectId)) {
        throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
      }
      final worksheetScopeId = worksheet.group.scopeId?.trim();
      if (worksheetScopeId == null ||
          worksheetScopeId.isEmpty ||
          !await controller.setScope(worksheetScopeId)) {
        throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
      }
      final requestReadyRowIds = worksheet.rows
          .where((row) => _boqRowCanSeedMaterialRequest(worksheet, row))
          .map((row) => row.id)
          .toList(growable: false);
      if (requestReadyRowIds.isEmpty) {
        throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
      }
      await controller.addBoqRows(
        worksheet: worksheet,
        rowIds: requestReadyRowIds,
      );
    } on YorksV1DomainException catch (error) {
      if (!mounted) return;
      YorksAppToast.show(
        context,
        title: YorksV1MaterialRequestStrings.commandFailure(error.code).primary,
        tone: YorksAppToastTone.error,
      );
    } catch (_) {
      if (!mounted) return;
      YorksAppToast.show(
        context,
        title: YorksV1MaterialRequestStrings.actionFailed.primary,
        tone: YorksAppToastTone.error,
      );
    }
  }
}

bool _boqRowCanSeedMaterialRequest(
  YorksV1BoqWorksheet worksheet,
  YorksV1BoqRow row,
) {
  for (final column in worksheet.columns) {
    final isIdentity = switch (column.canonicalField) {
      YorksV1BoqCanonicalField.description ||
      YorksV1BoqCanonicalField.equipmentTag => true,
      _ => RegExp(
        r'description|item|equipment|serving\s*area|location|tag',
        caseSensitive: false,
      ).hasMatch(column.heading),
    };
    if (isIdentity && '${row.valueFor(column.id) ?? ''}'.trim().isNotEmpty) {
      return true;
    }
  }
  return false;
}

String _materialRequestOpenPath(YorksV1MaterialRequest request) {
  if (request.state.isDraft) {
    return RoutePaths.yorksV1MaterialRequestDraftPath(
      request.id,
      projectId: request.projectId,
    );
  }
  return RoutePaths.yorksV1MaterialRequestPath(request.id);
}

String _mobileMaterialRequestActionPath(YorksV1MaterialRequest request) {
  if (request.state.isDraft ||
      request.state == YorksV1MaterialRequestState.changesRequested) {
    return RoutePaths.yorksV1MaterialRequestDraftPath(
      request.id,
      projectId: request.projectId,
    );
  }
  if (request.state == YorksV1MaterialRequestState.approvedForArrangement ||
      request.state == YorksV1MaterialRequestState.arranging) {
    return RoutePaths.yorksV1MaterialRequestArrangementPath(request.id);
  }
  if (request.currentActionCode == 'receipt_review_required' ||
      request.state == YorksV1MaterialRequestState.dispatched) {
    return RoutePaths.yorksV1MaterialRequestLogisticsPath(
      request.id,
      focusReceiptReview: true,
    );
  }
  if (request.state == YorksV1MaterialRequestState.approved ||
      request.state == YorksV1MaterialRequestState.partiallyDispatched ||
      request.state == YorksV1MaterialRequestState.partiallyReceived) {
    return RoutePaths.yorksV1MaterialRequestLogisticsPath(request.id);
  }
  return RoutePaths.yorksV1MaterialRequestPath(request.id);
}

({String label, IconData icon})? _mobileMaterialRequestCardAction(
  YorksV1MaterialRequest request,
  AppLanguage language,
) {
  if (request.state.isDraft) {
    return (
      label: YorksV1MaterialRequestStrings.continueDraft.active(language),
      icon: Icons.edit_note_rounded,
    );
  }
  if (!request.actorCanAct) return null;
  if (request.state == YorksV1MaterialRequestState.changesRequested) {
    return (
      label: YorksV1MaterialRequestStrings.updateRequest.active(language),
      icon: Icons.edit_rounded,
    );
  }
  if (request.state == YorksV1MaterialRequestState.submitted ||
      request.state == YorksV1MaterialRequestState.awaitingRequestApproval) {
    return (
      label: YorksV1MaterialRequestStrings.reviewRequest.active(language),
      icon: Icons.fact_check_outlined,
    );
  }
  if (request.state == YorksV1MaterialRequestState.approvedForArrangement ||
      request.state == YorksV1MaterialRequestState.arranging) {
    return (
      label: YorksV1MaterialRequestStrings.arrangeItems.active(language),
      icon: Icons.inventory_2_outlined,
    );
  }
  if (request.state == YorksV1MaterialRequestState.awaitingApproval) {
    return (
      label: YorksV1MaterialRequestStrings.reviewArrangement.active(language),
      icon: Icons.approval_outlined,
    );
  }
  if (request.currentActionCode == 'receipt_review_required' ||
      request.state == YorksV1MaterialRequestState.dispatched) {
    return (
      label: YorksV1LogisticsStrings.reviewDelivery.active(language),
      icon: Icons.fact_check_outlined,
    );
  }
  if (request.currentActionCode == 'material_request_close_review' ||
      request.currentActionCode == 'close_request' ||
      request.state == YorksV1MaterialRequestState.received) {
    return (
      label: YorksV1MaterialRequestStrings.closeRequest.active(language),
      icon: Icons.task_alt_outlined,
    );
  }
  if (request.state == YorksV1MaterialRequestState.approved ||
      request.state == YorksV1MaterialRequestState.partiallyDispatched ||
      request.state == YorksV1MaterialRequestState.partiallyReceived) {
    return (
      label: YorksV1LogisticsStrings.dispatchApprovedItems.active(language),
      icon: Icons.local_shipping_outlined,
    );
  }
  return (
    label: YorksV1MaterialRequestStrings.viewRequest.active(language),
    icon: Icons.arrow_forward_rounded,
  );
}

/// The single prominent action in a Material Request record follows the
/// server-owned R35 workflow.  This only governs presentation; each command
/// still checks role, membership, version and quantities in its RPC.
///
/// Keeping this resolver small and explicit prevents an old Arrange action
/// from leaking into the approved/dispatch stage simply because the viewer is
/// a Procurement user.
enum YorksV1MaterialRequestDetailPrimaryAction {
  arrange,
  dispatch,
  receiptReview,
  close,
  generateDeliveryOrder,
}

/// Presentation preflight for the server-authorized close command. An exact
/// Site Engineer still needs an active membership in the request project;
/// that authoritative check is performed by the trusted RPC.
@visibleForTesting
bool yorksV1CanOfferMaterialRequestClose({
  required YorksV1MaterialRequestState state,
  required YorksV1Role? role,
}) {
  return state == YorksV1MaterialRequestState.received &&
      ((role?.isEngineering ?? false) || role == YorksV1Role.admin);
}

@visibleForTesting
YorksV1MaterialRequestDetailPrimaryAction?
yorksV1MaterialRequestDetailPrimaryAction({
  required YorksV1MaterialRequestState state,
  required YorksV1Role? role,
  required bool canArrange,
  required bool canDispatch,
  required bool canConfirmReceipt,
  required bool canGenerateDeliveryOrder,
  bool canClose = false,
}) {
  final isProcurement =
      role == YorksV1Role.procurement || role == YorksV1Role.admin;
  final isReceivingEngineer =
      (role?.isEngineering ?? false) || role == YorksV1Role.admin;

  if (isProcurement &&
      canArrange &&
      (state == YorksV1MaterialRequestState.approvedForArrangement ||
          state == YorksV1MaterialRequestState.arranging)) {
    return YorksV1MaterialRequestDetailPrimaryAction.arrange;
  }
  if (isProcurement &&
      canDispatch &&
      (state == YorksV1MaterialRequestState.approved ||
          state == YorksV1MaterialRequestState.partiallyDispatched ||
          state == YorksV1MaterialRequestState.partiallyReceived)) {
    return YorksV1MaterialRequestDetailPrimaryAction.dispatch;
  }
  if (isReceivingEngineer &&
      canConfirmReceipt &&
      (state == YorksV1MaterialRequestState.partiallyDispatched ||
          state == YorksV1MaterialRequestState.dispatched ||
          state == YorksV1MaterialRequestState.partiallyReceived)) {
    return YorksV1MaterialRequestDetailPrimaryAction.receiptReview;
  }
  if (canClose && state == YorksV1MaterialRequestState.received) {
    return YorksV1MaterialRequestDetailPrimaryAction.close;
  }
  if (canGenerateDeliveryOrder &&
      (state == YorksV1MaterialRequestState.partiallyDispatched ||
          state == YorksV1MaterialRequestState.dispatched ||
          state == YorksV1MaterialRequestState.partiallyReceived ||
          state == YorksV1MaterialRequestState.received ||
          state == YorksV1MaterialRequestState.closed)) {
    return YorksV1MaterialRequestDetailPrimaryAction.generateDeliveryOrder;
  }
  return null;
}

class YorksV1MaterialRequestDetailScreen extends ConsumerWidget {
  const YorksV1MaterialRequestDetailScreen({
    super.key,
    required this.requestId,
    this.commentId,
  });

  final String requestId;
  final String? commentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final request = ref.watch(yorksV1MaterialRequestDetailProvider(requestId));
    final permissionState = ref.watch(yorksV1CurrentPermissionSnapshotProvider);
    final compactRoute =
        MediaQuery.sizeOf(context).width < AppSpacing.yorksV1DesktopBreakpoint;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: compactRoute && !YorksMobileUi.isActive(context)
          ? AppBar(
              backgroundColor: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              title: _CopyText(
                copy: YorksV1MaterialRequestStrings.requests,
                language: language,
                style: AppTypography.titleLarge.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              actions: [
                IconButton(
                  tooltip: YorksV1MaterialRequestStrings.refresh.primary,
                  onPressed: () => ref.invalidate(
                    yorksV1MaterialRequestDetailProvider(requestId),
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            )
          : null,
      body: request.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _RequestError(
          language: language,
          onRetry: () =>
              ref.invalidate(yorksV1MaterialRequestDetailProvider(requestId)),
        ),
        data: (value) => YorksV1ProjectReadBoundary(
          allowed: yorksV1CanReadProjectRecord(
            permissionState,
            YorksV1CapabilityKeys.materialRequestsView,
            legacyAllowed: true,
            projectId: value.projectId,
          ),
          language: language,
          child: _RequestDetailBody(
            request: value,
            language: language,
            showPageHeader: !compactRoute,
            commentId: commentId,
            onRefresh: () =>
                ref.invalidate(yorksV1MaterialRequestDetailProvider(requestId)),
          ),
        ),
      ),
    );
  }
}

List<YorksV1MaterialRequestTiming> _allowedRequestTimings(
  YorksV1MaterialRequestDraft draft,
  AsyncValue<YorksV1RuntimeConfiguration> runtimeConfiguration,
) {
  // Runtime policy is fail-closed: a loading or unavailable policy never
  // exposes Urgent as a new selection. An existing urgent draft remains
  // representable so opening it cannot silently rewrite workflow data.
  final urgentEnabled = runtimeConfiguration.valueOrNull?.urgentEnabled == true;
  return [
    for (final timing in YorksV1MaterialRequestTiming.values)
      if (timing != YorksV1MaterialRequestTiming.urgent ||
          urgentEnabled ||
          draft.timing == YorksV1MaterialRequestTiming.urgent)
        timing,
  ];
}

TranslatableString? _materialRequestSubmitValidationMessage(
  YorksV1MaterialRequestDraft draft,
) {
  if (draft.projectId?.trim().isNotEmpty != true) {
    return YorksV1MaterialRequestStrings.chooseProjectRequired;
  }
  if (draft.scopeId?.trim().isNotEmpty != true) {
    return YorksV1MaterialRequestStrings.chooseScopeRequired;
  }
  if (draft.timing == YorksV1MaterialRequestTiming.scheduled &&
      draft.scheduledDate == null) {
    return YorksV1MaterialRequestStrings.scheduledDateRequired;
  }
  if (draft.lines.isEmpty) {
    return YorksV1MaterialRequestStrings.addItemRequired;
  }
  final invalidCount = draft.lines
      .where((line) => !line.hasValidOperationalValues)
      .length;
  if (invalidCount > 0) {
    return YorksV1MaterialRequestStrings.rowsNeedAttention(invalidCount);
  }
  return null;
}

GlobalObjectKey<State<StatefulWidget>> _materialRequestLineKey(String lineId) =>
    GlobalObjectKey<State<StatefulWidget>>('material-request-line-$lineId');

Future<void> _revealFirstInvalidMaterialRequestLine(
  YorksV1MaterialRequestDraft draft,
) async {
  final firstInvalid = draft.lines
      .where((line) => !line.hasValidOperationalValues)
      .firstOrNull;
  if (firstInvalid == null) return;
  await Future<void>.delayed(const Duration(milliseconds: 40));
  final target = _materialRequestLineKey(firstInvalid.id).currentContext;
  if (target == null || !target.mounted) return;
  await Scrollable.ensureVisible(
    target,
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeOutCubic,
    alignment: 0.25,
  );
}

class _MaterialRequestKeyboardShortcuts extends StatelessWidget {
  const _MaterialRequestKeyboardShortcuts({
    required this.child,
    this.onSave,
    this.onAddCustom,
    this.onSubmit,
  });

  final Widget child;
  final VoidCallback? onSave;
  final VoidCallback? onAddCustom;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: <ShortcutActivator, VoidCallback>{
      if (onSave != null) ...{
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): onSave!,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): onSave!,
      },
      if (onAddCustom != null) ...{
        const SingleActivator(
          LogicalKeyboardKey.keyC,
          control: true,
          shift: true,
        ): onAddCustom!,
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true, shift: true):
            onAddCustom!,
      },
      if (onSubmit != null) ...{
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            onSubmit!,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): onSubmit!,
      },
    },
    child: child,
  );
}

class _DraftForm extends ConsumerWidget {
  const _DraftForm({
    required this.state,
    required this.controller,
    required this.draftKey,
    required this.language,
  });

  final YorksV1MaterialRequestDraftState state;
  final YorksV1MaterialRequestDraftController controller;
  final YorksV1MaterialRequestDraftKey draftKey;
  final AppLanguage language;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = state.draft;
    final role = ref.watch(yorksV1CurrentRoleProvider);
    final permissionState = ref.watch(yorksV1CurrentPermissionSnapshotProvider);
    final editAccess = yorksV1FeatureActionAccess(
      permissionState,
      draft.serverRecordVersion > 0
          ? YorksV1CapabilityKeys.materialRequestsEdit
          : YorksV1CapabilityKeys.materialRequestsCreate,
      legacyAllowed: role?.canCreateMaterialRequest == true,
      projectId: draft.projectId,
      anyProject: draft.projectId == null,
    );
    final submitAccess = yorksV1FeatureActionAccess(
      permissionState,
      YorksV1CapabilityKeys.materialRequestsSubmit,
      legacyAllowed: role?.canCreateMaterialRequest == true,
      projectId: draft.projectId,
      anyProject: draft.projectId == null,
    );
    final runtimeConfiguration = ref.watch(yorksV1RuntimeConfigurationProvider);
    final controlledUnitsAsync = ref.watch(
      yorksV1ConfigurationUnitCodesProvider,
    );
    final controlledUnitsReady = yorksV1ControlledUnitsReady(
      controlledUnitsAsync,
    );
    final allowedTimings = _allowedRequestTimings(draft, runtimeConfiguration);
    final projects = ref.watch(yorksV1MaterialRequestDraftProjectsProvider);
    final scopes = draft.projectId == null
        ? const AsyncData<List<YorksV1MaterialRequestScopeOption>>([])
        : ref.watch(yorksV1MaterialRequestScopesProvider(draft.projectId!));
    // R35 starts every new request at the server-created Common / All
    // Buildings scope.  Keep that convenience without making the scope a
    // client-side authority: the ordered RPC response is still the source of
    // truth and the submit RPC validates the selected scope again.
    if (draft.projectId != null &&
        draft.scopeId == null &&
        scopes is AsyncData<List<YorksV1MaterialRequestScopeOption>> &&
        scopes.value.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final current = controller.currentDraft;
        if (current.projectId == draft.projectId && current.scopeId == null) {
          controller.setScope(scopes.value.first.id);
        }
      });
    }
    final selectedProject = projects.valueOrNull
        ?.where((item) => item.id == draft.projectId)
        .firstOrNull;
    final selectedScope = scopes.valueOrNull
        ?.where((item) => item.id == draft.scopeId)
        .firstOrNull;
    final projectIsActive =
        selectedProject?.state == YorksV1ProjectLifecycle.active.wireValue;
    // Keep the final action available to explain incomplete data. A disabled
    // button leaves engineers guessing which row is blocking submission.
    final canAttemptSubmit =
        submitAccess.canWrite &&
        state.status != YorksV1MaterialRequestDraftSyncStatus.submitting;
    final isBusy =
        !editAccess.canWrite ||
        state.status == YorksV1MaterialRequestDraftSyncStatus.saving ||
        state.status == YorksV1MaterialRequestDraftSyncStatus.submitting;
    final excelEnabled = ref.watch(yorksV1FeatureFlagsProvider).excel;
    final workbookFileService = ref.watch(
      yorksV1BoqWorkbookFileServiceProvider,
    );
    final documentService = YorksV1MaterialRequestDocumentService();
    final serverBackedRequest = draft.serverRecordVersion > 0
        ? ref.watch(yorksV1MaterialRequestDetailProvider(draft.id))
        : null;
    final compactRoute =
        MediaQuery.sizeOf(context).width < AppSpacing.yorksV1DesktopBreakpoint;
    final inspectorExpanded = ref.watch(
      yorksV1MaterialRequestInspectorExpandedProvider,
    );

    if (YorksMobileUi.isActive(context)) {
      return _MaterialRequestDraftExitGuard(
        state: state,
        controller: controller,
        language: language,
        canSave: editAccess.canWrite,
        child: _YorksMobileMaterialRequestDraftFlow(
          state: state,
          controller: controller,
          projects: projects,
          scopes: scopes,
          allowedTimings: allowedTimings,
          canEdit: editAccess.canWrite,
          canSubmit: submitAccess.canWrite,
          onSave: () => _save(context, ref, controller, draft),
          onSubmit: () => _submitForMobile(context, ref, controller),
        ),
      );
    }

    return _MaterialRequestDraftExitGuard(
      state: state,
      controller: controller,
      language: language,
      canSave: editAccess.canWrite,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: compactRoute
            ? AppBar(
                backgroundColor: AppColors.surface,
                surfaceTintColor: Colors.transparent,
                leading: IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                title: _CopyText(
                  copy: draft.serverRecordVersion == 0
                      ? YorksV1MaterialRequestStrings.newRequest
                      : YorksV1MaterialRequestStrings.editDraft,
                  language: language,
                  style: AppTypography.titleLarge.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            : null,
        bottomNavigationBar: compactRoute
            ? _TabletMrDraftActions(
                onCancel: () => context.pop(),
                onSave: isBusy
                    ? null
                    : () => _save(context, ref, controller, draft),
                onSubmit: canAttemptSubmit
                    ? () => _submit(context, ref, controller)
                    : null,
                submitting:
                    state.status ==
                    YorksV1MaterialRequestDraftSyncStatus.submitting,
              )
            : null,
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final desktop =
                  constraints.maxWidth >= AppSpacing.yorksV1DesktopBreakpoint;
              final horizontal = desktop
                  ? AppSpacing.xxxl + AppSpacing.xs
                  : AppSpacing.lg;
              final submit = canAttemptSubmit
                  ? () => _submit(context, ref, controller)
                  : null;
              final save = isBusy
                  ? null
                  : () => _save(context, ref, controller, draft);
              final requestNumber = _previewRequestNumber(selectedProject);
              final form = _R35RequestCard(
                title: YorksV1MaterialRequestStrings.requestInformation.primary,
                description: YorksV1MaterialRequestStrings
                    .requestInformationDescription
                    .primary,
                child: _RequestFormFields(
                  draft: draft,
                  projects: projects,
                  scopes: scopes,
                  controller: controller,
                  allowedTimings: allowedTimings,
                ),
              );
              final items = _R35RequestCard(
                sectionNumber: 2,
                title: YorksV1MaterialRequestStrings.materialItems.primary,
                description: YorksV1MaterialRequestStrings
                    .materialItemsDescription
                    .primary,
                actions: [
                  _R35MaterialActionBar(
                    canEdit: !isBusy && draft.projectId != null,
                    canUseBoq:
                        !isBusy &&
                        draft.projectId != null &&
                        draft.scopeId != null,
                    excelEnabled: excelEnabled,
                    onAddCustom: controller.addCustomLine,
                    onAddBoq: () => _addBoqRows(
                      context,
                      ref,
                      controller,
                      draft,
                      language: language,
                      projectReference: selectedProject?.reference,
                      scopeName: selectedScope?.name,
                    ),
                    onImport: () => _importExcel(context, ref, controller),
                    onExport: () => _exportDraft(
                      context,
                      workbookFileService,
                      documentService,
                      draft,
                      projectReference: selectedProject?.reference,
                    ),
                  ),
                ],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (draft.projectId == null) ...[
                      _InlineMessage(
                        copy: YorksV1MaterialRequestStrings
                            .chooseProjectBeforeAdding,
                        language: language,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    _RequestLinesEditor(
                      lines: draft.lines,
                      controller: controller,
                      enabled: !isBusy,
                      projectId: draft.projectId,
                      scopeId: draft.scopeId,
                    ),
                  ],
                ),
              );
              final notices = [
                if (state.status ==
                    YorksV1MaterialRequestDraftSyncStatus.savedToAccount)
                  _InlineMessage(
                    copy: YorksV1MaterialRequestStrings.savedToYourAccount,
                    language: language,
                  ),
                if (state.status ==
                        YorksV1MaterialRequestDraftSyncStatus.failed ||
                    state.status ==
                        YorksV1MaterialRequestDraftSyncStatus.conflict)
                  _InlineMessage(
                    copy:
                        state.status ==
                            YorksV1MaterialRequestDraftSyncStatus.conflict
                        ? YorksV1MaterialRequestStrings.saveFailed
                        : YorksV1MaterialRequestStrings.submitFailed,
                    language: language,
                  ),
                if (draft.projectId == null)
                  _InlineMessage(
                    copy: YorksV1MaterialRequestStrings.chooseProjectRequired,
                    language: language,
                  )
                else if (draft.scopeId == null)
                  _InlineMessage(
                    copy: YorksV1MaterialRequestStrings.chooseScopeRequired,
                    language: language,
                  ),
                if (!controlledUnitsReady)
                  _InlineMessage(
                    copy: YorksV1ControlledUnitStrings.unavailable,
                    language: language,
                  ),
                if (draft.projectId != null &&
                    selectedProject != null &&
                    !projectIsActive)
                  _InlineMessage(
                    copy: YorksV1MaterialRequestStrings.projectMustBeActive,
                    language: language,
                  ),
              ];
              return _MaterialRequestKeyboardShortcuts(
                onSave: save,
                onAddCustom: !isBusy && draft.projectId != null
                    ? controller.addCustomLine
                    : null,
                onSubmit: submit,
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
                        if (!compactRoute) ...[
                          _R35RequestHero(
                            title: requestNumber,
                            requesterName: ref.watch(actorNameProvider),
                            projectName: selectedProject?.name,
                            lineCount: draft.lines.length,
                            onCancel: () => context.pop(),
                            onSave: save,
                            onSubmit: submit,
                            submitting:
                                state.status ==
                                YorksV1MaterialRequestDraftSyncStatus
                                    .submitting,
                            inspectorExpanded: inspectorExpanded,
                            onToggleInspector: () =>
                                ref
                                        .read(
                                          yorksV1MaterialRequestInspectorExpandedProvider
                                              .notifier,
                                        )
                                        .state =
                                    !inspectorExpanded,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                        if (desktop)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    form,
                                    const SizedBox(height: AppSpacing.xxxl),
                                    items,
                                    for (final notice in notices) ...[
                                      const SizedBox(height: AppSpacing.lg),
                                      notice,
                                    ],
                                  ],
                                ),
                              ),
                              if (inspectorExpanded) ...[
                                const SizedBox(width: AppSpacing.lg),
                                SizedBox(
                                  key: const ValueKey(
                                    'mr-request-context-panel',
                                  ),
                                  width: 360,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _R35RequestReview(
                                        draft: draft,
                                        projects: projects,
                                        scopes: scopes,
                                        requesterName: ref.watch(
                                          actorNameProvider,
                                        ),
                                      ),
                                      const SizedBox(height: AppSpacing.lg),
                                      if (serverBackedRequest != null)
                                        serverBackedRequest.when(
                                          loading: () =>
                                              const _DraftDiscussionLoading(),
                                          error: (_, _) =>
                                              _DraftDiscussionPrompt(
                                                canSave: save != null,
                                                onSave: save,
                                              ),
                                          data: (request) =>
                                              _MaterialRequestDiscussion(
                                                request: request,
                                                compact: true,
                                              ),
                                        )
                                      else
                                        _DraftDiscussionPrompt(
                                          canSave: save != null,
                                          onSave: save,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          )
                        else ...[
                          form,
                          const SizedBox(height: AppSpacing.lg),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: _R35RequestAction(
                              key: const ValueKey('mr-request-context-toggle'),
                              label:
                                  (inspectorExpanded
                                          ? YorksV1MaterialRequestStrings
                                                .hideRequestContext
                                          : YorksV1MaterialRequestStrings
                                                .showRequestContext)
                                      .primary,
                              icon: Icons.view_sidebar_outlined,
                              onPressed: () =>
                                  ref
                                          .read(
                                            yorksV1MaterialRequestInspectorExpandedProvider
                                                .notifier,
                                          )
                                          .state =
                                      !inspectorExpanded,
                            ),
                          ),
                          if (inspectorExpanded) ...[
                            const SizedBox(height: AppSpacing.lg),
                            _R35RequestReview(
                              draft: draft,
                              projects: projects,
                              scopes: scopes,
                              requesterName: ref.watch(actorNameProvider),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            if (serverBackedRequest != null)
                              serverBackedRequest.when(
                                loading: () => const _DraftDiscussionLoading(),
                                error: (_, _) => _DraftDiscussionPrompt(
                                  canSave: save != null,
                                  onSave: save,
                                ),
                                data: (request) => _MaterialRequestDiscussion(
                                  request: request,
                                  compact: true,
                                ),
                              )
                            else
                              _DraftDiscussionPrompt(
                                canSave: save != null,
                                onSave: save,
                              ),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                          items,
                          for (final notice in notices) ...[
                            const SizedBox(height: AppSpacing.lg),
                            notice,
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    YorksV1MaterialRequestDraftController controller,
    YorksV1MaterialRequestDraft draft,
  ) async {
    // Grid cells keep their editing buffer locally for responsive web input.
    // Commit the active cell before a deliberate workflow action reads the
    // draft, so Save always includes the visible value.
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(Duration.zero);
    final wasServerReady = controller.currentDraft.canSubmitLocally;
    final saved = await controller.saveDraft();
    if (!context.mounted) return;
    if (saved == null) {
      _snack(
        context,
        wasServerReady
            ? YorksV1MaterialRequestStrings.saveFailed.primary
            : YorksV1MaterialRequestStrings.savedLocally.primary,
      );
      return;
    }
    _snack(context, YorksV1MaterialRequestStrings.saved.primary);
    ref.invalidate(yorksV1MaterialRequestListProvider);
  }

  Future<void> _submit(
    BuildContext context,
    WidgetRef ref,
    YorksV1MaterialRequestDraftController controller,
  ) async {
    final submitted = await _submitForMobile(context, ref, controller);
    if (!context.mounted || submitted == null) return;
    context.go(RoutePaths.yorksV1MaterialRequestPath(submitted.id));
  }

  Future<YorksV1MaterialRequest?> _submitForMobile(
    BuildContext context,
    WidgetRef ref,
    YorksV1MaterialRequestDraftController controller,
  ) async {
    // See _save: Submit must validate the value the engineer can still see in
    // the active local editor instead of a stale draft snapshot.
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(Duration.zero);
    final draft = controller.currentDraft;
    final validationMessage = _materialRequestSubmitValidationMessage(draft);
    if (validationMessage != null) {
      if (context.mounted) {
        _snack(context, validationMessage.primary);
        await _revealFirstInvalidMaterialRequestLine(draft);
      }
      return null;
    }
    if (!yorksV1ControlledUnitsReady(
      ref.read(yorksV1ConfigurationUnitCodesProvider),
    )) {
      if (context.mounted) {
        _snack(context, YorksV1ControlledUnitStrings.unavailable.primary);
      }
      return null;
    }
    final project = ref
        .read(yorksV1MaterialRequestDraftProjectsProvider)
        .valueOrNull
        ?.where((item) => item.id == draft.projectId)
        .firstOrNull;
    if (project == null ||
        project.state != YorksV1ProjectLifecycle.active.wireValue) {
      if (context.mounted) {
        _snack(
          context,
          YorksV1MaterialRequestStrings.projectMustBeActive.primary,
        );
      }
      return null;
    }
    final submitted = await controller.submit();
    if (!context.mounted) return null;
    if (submitted == null) {
      final errorCode = controller.lastErrorCode;
      final message = errorCode == null
          ? YorksV1MaterialRequestStrings.submitFailed.primary
          : YorksV1MaterialRequestStrings.commandFailure(errorCode).primary;
      _snack(context, message);
      return null;
    }
    ref.invalidate(yorksV1MaterialRequestListProvider);
    return submitted;
  }
}

enum _MaterialRequestDraftExitChoice { save, discard }

String _materialRequestDraftContentFingerprint(
  YorksV1MaterialRequestDraft draft,
) {
  final content = Map<String, dynamic>.from(draft.toJson())
    ..remove('submissionIdempotencyKey')
    ..remove('serverRecordVersion')
    ..remove('updatedAt');
  return jsonEncode(content);
}

/// Guards route-level Back without interfering with the phone composer's
/// internal Back steps. A restored draft becomes the visit baseline; only
/// edits made after that point prompt the user.
class _MaterialRequestDraftExitGuard extends ConsumerStatefulWidget {
  const _MaterialRequestDraftExitGuard({
    required this.state,
    required this.controller,
    required this.language,
    required this.canSave,
    required this.child,
  });

  final YorksV1MaterialRequestDraftState state;
  final YorksV1MaterialRequestDraftController controller;
  final AppLanguage language;
  final bool canSave;
  final Widget child;

  @override
  ConsumerState<_MaterialRequestDraftExitGuard> createState() =>
      _MaterialRequestDraftExitGuardState();
}

class _MaterialRequestDraftExitGuardState
    extends ConsumerState<_MaterialRequestDraftExitGuard> {
  late YorksV1MaterialRequestDraft _baseline;
  late String _baselineFingerprint;
  bool _allowPop = false;
  bool _decisionOpen = false;

  @override
  void initState() {
    super.initState();
    _setBaseline(widget.controller.acceptedDraft);
  }

  @override
  void didUpdateWidget(covariant _MaterialRequestDraftExitGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.draft.id != widget.state.draft.id) {
      _allowPop = false;
      _setBaseline(widget.state.draft);
      return;
    }
    final accepted = widget.controller.acceptedDraft;
    final acceptedFingerprint = _materialRequestDraftContentFingerprint(
      accepted,
    );
    if (acceptedFingerprint != _baselineFingerprint &&
        acceptedFingerprint ==
            _materialRequestDraftContentFingerprint(widget.state.draft)) {
      _setBaseline(accepted);
    }
  }

  void _setBaseline(YorksV1MaterialRequestDraft draft) {
    _baseline = draft;
    _baselineFingerprint = _materialRequestDraftContentFingerprint(draft);
  }

  bool get _hasUnsavedChanges =>
      widget.state.status != YorksV1MaterialRequestDraftSyncStatus.submitted &&
      _materialRequestDraftContentFingerprint(widget.state.draft) !=
          _baselineFingerprint;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop || !_hasUnsavedChanges,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop || _allowPop || _decisionOpen) return;
      await _requestExit();
    },
    child: widget.child,
  );

  Future<void> _requestExit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    if (!_hasUnsavedChanges) {
      _leave();
      return;
    }
    _decisionOpen = true;
    final choice = await showDialog<_MaterialRequestDraftExitChoice>(
      context: context,
      barrierDismissible: false,
      animationStyle: AnimationStyle.noAnimation,
      builder: (dialogContext) => _MaterialRequestDraftExitDialog(
        language: widget.language,
        onSave: _saveBeforeLeaving,
        onDiscard: _discardBeforeLeaving,
      ),
    );
    _decisionOpen = false;
    if (!mounted || choice == null) return;
    _leave();
  }

  Future<bool> _saveBeforeLeaving() async {
    if (!widget.canSave) return false;
    final canSaveOnServer = widget.controller.currentDraft.canSubmitLocally;
    try {
      final saved = await widget.controller.saveDraft();
      if (canSaveOnServer && saved == null) return false;
      ref.invalidate(yorksV1MaterialRequestListProvider);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _discardBeforeLeaving() async {
    try {
      if (_baseline.hasRecoverableContent ||
          _baseline.serverRecordVersion > 0) {
        await widget.controller.restoreLocalSnapshot(_baseline);
      } else {
        await widget.controller.discardLocal();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  void _leave() {
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }
}

class _MaterialRequestDraftExitDialog extends StatefulWidget {
  const _MaterialRequestDraftExitDialog({
    required this.language,
    required this.onSave,
    required this.onDiscard,
  });

  final AppLanguage language;
  final Future<bool> Function() onSave;
  final Future<bool> Function() onDiscard;

  @override
  State<_MaterialRequestDraftExitDialog> createState() =>
      _MaterialRequestDraftExitDialogState();
}

class _MaterialRequestDraftExitDialogState
    extends State<_MaterialRequestDraftExitDialog> {
  bool _busy = false;
  TranslatableString? _error;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 560;
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.xl),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DecoratedBox(
                      decoration: const BoxDecoration(
                        color: AppColors.blueContainer,
                        shape: BoxShape.circle,
                      ),
                      child: const SizedBox.square(
                        dimension: 48,
                        child: Icon(
                          Icons.edit_note_rounded,
                          color: AppColors.blue,
                          size: 27,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          YorksV1ActiveText(
                            copy: YorksV1MaterialRequestStrings.leaveDraftTitle,
                            language: widget.language,
                            style: AppTypography.headlineSmall.copyWith(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          YorksV1ActiveText(
                            copy: YorksV1MaterialRequestStrings.leaveDraftBody,
                            language: widget.language,
                            style: AppTypography.bodyMedium.copyWith(
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
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      style: IconButton.styleFrom(
                        minimumSize: const Size.square(AppSpacing.minTapTarget),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.lock_outline_rounded,
                            size: 20,
                            color: AppColors.muted,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: YorksV1ActiveText(
                              copy: YorksV1MaterialRequestStrings
                                  .draftRecoveryAssurance,
                              language: widget.language,
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        key: const ValueKey('mr-draft-exit-error'),
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.errorContainer,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMd,
                          ),
                        ),
                        child: YorksV1ActiveText(
                          copy: _error!,
                          language: widget.language,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _actions(context, vertical: true),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: _actions(context),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(BuildContext context, {bool vertical = false}) {
    final gap = vertical
        ? const SizedBox(height: AppSpacing.sm)
        : const SizedBox(width: AppSpacing.sm);
    return [
      TextButton(
        key: const ValueKey('mr-draft-keep-editing'),
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: Text(AppStrings.keepEditing.active(widget.language)),
      ),
      gap,
      OutlinedButton(
        key: const ValueKey('mr-draft-discard-and-leave'),
        onPressed: _busy ? null : _discard,
        style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
        child: Text(
          YorksV1MaterialRequestStrings.discardChangesAndLeave.active(
            widget.language,
          ),
        ),
      ),
      gap,
      FilledButton.icon(
        key: const ValueKey('mr-draft-save-and-leave'),
        onPressed: _busy ? null : _save,
        icon: _busy
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save_outlined),
        label: Text(
          YorksV1MaterialRequestStrings.saveDraftAndLeave.active(
            widget.language,
          ),
        ),
      ),
    ];
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final saved = await widget.onSave();
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context, _MaterialRequestDraftExitChoice.save);
      return;
    }
    setState(() {
      _busy = false;
      _error = YorksV1MaterialRequestStrings.draftExitSaveFailed;
    });
  }

  Future<void> _discard() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final discarded = await widget.onDiscard();
    if (!mounted) return;
    if (discarded) {
      Navigator.pop(context, _MaterialRequestDraftExitChoice.discard);
      return;
    }
    setState(() {
      _busy = false;
      _error = YorksV1MaterialRequestStrings.draftExitDiscardFailed;
    });
  }
}

enum _MobileMaterialRequestDraftStep { information, materials, review }

enum _MobileMaterialRequestSourcePage { none, boqFolders, boqRows, custom }

/// The phone request composer is a presentation-only state machine layered on
/// the existing draft controller. It never owns a second draft or command:
/// all edits flow through [YorksV1MaterialRequestDraftController], and the
/// success panel appears only after its connected submit returns a request.
class _YorksMobileMaterialRequestDraftFlow extends ConsumerStatefulWidget {
  const _YorksMobileMaterialRequestDraftFlow({
    required this.state,
    required this.controller,
    required this.projects,
    required this.scopes,
    required this.allowedTimings,
    required this.canEdit,
    required this.canSubmit,
    required this.onSave,
    required this.onSubmit,
  });

  final YorksV1MaterialRequestDraftState state;
  final YorksV1MaterialRequestDraftController controller;
  final AsyncValue<List<YorksV1MaterialRequestProjectOption>> projects;
  final AsyncValue<List<YorksV1MaterialRequestScopeOption>> scopes;
  final List<YorksV1MaterialRequestTiming> allowedTimings;
  final bool canEdit;
  final bool canSubmit;
  final Future<void> Function() onSave;
  final Future<YorksV1MaterialRequest?> Function() onSubmit;

  @override
  ConsumerState<_YorksMobileMaterialRequestDraftFlow> createState() =>
      _YorksMobileMaterialRequestDraftFlowState();
}

class _YorksMobileMaterialRequestDraftFlowState
    extends ConsumerState<_YorksMobileMaterialRequestDraftFlow> {
  _MobileMaterialRequestDraftStep _step =
      _MobileMaterialRequestDraftStep.information;
  _MobileMaterialRequestSourcePage _sourcePage =
      _MobileMaterialRequestSourcePage.none;
  List<YorksV1BoqGroup>? _groups;
  YorksV1BoqWorksheet? _worksheet;
  final Set<String> _selectedBoqRows = <String>{};
  bool _loadingSource = false;
  bool _reviewConfirmed = false;
  YorksV1MaterialRequest? _submitted;
  late final TextEditingController _customDescription;
  late final TextEditingController _customBrand;
  late final TextEditingController _customSize;
  late final TextEditingController _customModel;
  late final TextEditingController _customQuantity;
  String? _editingCustomLineId;
  bool _discardCustomLineOnClose = false;
  YorksV1MaterialRequestInventorySuggestion? _customSuggestion;
  String _customUnit = '';
  bool _customValidationAttempted = false;

  @override
  void initState() {
    super.initState();
    _customDescription = TextEditingController();
    _customBrand = TextEditingController();
    _customSize = TextEditingController();
    _customModel = TextEditingController();
    _customQuantity = TextEditingController(text: '1');
  }

  @override
  void dispose() {
    _customDescription.dispose();
    _customBrand.dispose();
    _customSize.dispose();
    _customModel.dispose();
    _customQuantity.dispose();
    super.dispose();
  }

  YorksV1MaterialRequestDraft get _draft => widget.state.draft;

  bool get _busy =>
      !widget.canEdit ||
      widget.state.status == YorksV1MaterialRequestDraftSyncStatus.saving ||
      widget.state.status == YorksV1MaterialRequestDraftSyncStatus.submitting;

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    if (_submitted != null) {
      return Directionality(
        textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          backgroundColor: AppColors.mobileSurface,
          body: _successPage(context, _submitted!),
        ),
      );
    }
    final sourceTitle = switch (_sourcePage) {
      _MobileMaterialRequestSourcePage.none => null,
      _MobileMaterialRequestSourcePage.boqFolders =>
        YorksV1MaterialRequestStrings.addFromBoq.active(language),
      _MobileMaterialRequestSourcePage.boqRows =>
        YorksV1MaterialRequestStrings.selectedItems.active(language),
      _MobileMaterialRequestSourcePage.custom =>
        _editingCustomLineId != null && !_discardCustomLineOnClose
            ? AppStrings.editMaterial.active(language)
            : YorksV1MaterialRequestStrings.unplannedMaterial.active(language),
    };
    return Directionality(
      textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.mobileSurface,
        body: ColoredBox(
          color: AppColors.mobileSurface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              YorksMobileAppBar(
                title: sourceTitle ?? _stepTitle,
                leading: YorksMobileIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: _back,
                ),
              ),
              if (widget.state.status ==
                  YorksV1MaterialRequestDraftSyncStatus.syncingToAccount)
                const LinearProgressIndicator(minHeight: 2),
              if (widget.state.status ==
                  YorksV1MaterialRequestDraftSyncStatus.savedToAccount)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.xs,
                    AppSpacing.md,
                    0,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.cloud_done_outlined,
                        size: 16,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: YorksV1ActiveText(
                          copy:
                              YorksV1MaterialRequestStrings.savedToYourAccount,
                          language: language,
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.success,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: switch (_sourcePage) {
                  _MobileMaterialRequestSourcePage.none => _draftStepBody(),
                  _MobileMaterialRequestSourcePage.boqFolders =>
                    _boqFoldersBody(),
                  _MobileMaterialRequestSourcePage.boqRows => _boqRowsBody(),
                  _MobileMaterialRequestSourcePage.custom =>
                    _customMaterialBody(),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _stepTitle => switch (_step) {
    _MobileMaterialRequestDraftStep.information =>
      YorksV1MaterialRequestStrings.requestInformation.active(_language),
    _MobileMaterialRequestDraftStep.materials =>
      YorksV1MaterialRequestStrings.materialItems.active(_language),
    _MobileMaterialRequestDraftStep.review =>
      YorksV1MaterialRequestStrings.review.active(_language),
  };

  AppLanguage get _language => ref.watch(languageProvider);

  Widget _draftStepBody() => switch (_step) {
    _MobileMaterialRequestDraftStep.information => _informationBody(),
    _MobileMaterialRequestDraftStep.materials => _materialsBody(),
    _MobileMaterialRequestDraftStep.review => _reviewBody(),
  };

  Widget _informationBody() => Column(
    children: [
      Expanded(
        child: ListView(
          key: const ValueKey('mobile-mr-information'),
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
          children: [
            _MobileMrProgress(step: _step, language: _language),
            const SizedBox(height: 20),
            Text(
              YorksV1MaterialRequestStrings.whereNeeded.active(_language),
              style: AppTypography.headlineMedium.copyWith(
                fontSize: 25,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              YorksV1MaterialRequestStrings.whereNeededDescription.active(
                _language,
              ),
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            YorksMobileCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _mobileProjectField(),
                  const SizedBox(height: 12),
                  _mobileScopeField(),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('mobile-mr-title'),
                    initialValue: _draft.title ?? '',
                    onChanged: widget.controller.setTitle,
                    decoration: InputDecoration(
                      labelText: YorksV1MaterialRequestStrings.requestTitle
                          .active(_language),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    YorksV1MaterialRequestStrings.requestTiming.active(
                      _language,
                    ),
                    style: AppTypography.labelLarge.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  KeyedSubtree(
                    key: const ValueKey('mobile-mr-timing-control'),
                    child:
                        YorksMobileSegmentedControl<
                          YorksV1MaterialRequestTiming
                        >(
                          options: [
                            for (final timing in widget.allowedTimings)
                              YorksMobileSegmentOption(
                                value: timing,
                                label: yorksV1MaterialRequestTimingCopy(
                                  timing,
                                ).active(_language),
                              ),
                          ],
                          selected: _draft.timing,
                          enabled: !_busy,
                          onSelected: widget.controller.setTiming,
                        ),
                  ),
                  if (_draft.timing ==
                      YorksV1MaterialRequestTiming.scheduled) ...[
                    const SizedBox(height: 12),
                    _mobileScheduledDate(),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('mobile-mr-delivery-note'),
                    initialValue: _draft.deliveryNote ?? '',
                    minLines: 2,
                    maxLines: 3,
                    onChanged: widget.controller.setDeliveryNote,
                    decoration: InputDecoration(
                      labelText: YorksV1MaterialRequestStrings.deliveryNote
                          .active(_language),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _MobileMrNotice(
              icon: Icons.lock_outline_rounded,
              text: YorksV1MaterialRequestStrings.draftPrivate.active(
                _language,
              ),
            ),
          ],
        ),
      ),
      _MobileMrStickyActions(
        primaryLabel: YorksV1MaterialRequestStrings.continueAction.active(
          _language,
        ),
        primaryIcon: Icons.arrow_forward_rounded,
        onPrimary: _busy ? null : _continueToMaterials,
      ),
    ],
  );

  Widget _mobileProjectField() => widget.projects.when(
    loading: () => const LinearProgressIndicator(),
    error: (_, _) => _MobileMrNotice(
      icon: Icons.sync_problem_rounded,
      text: YorksV1MaterialRequestStrings.saveFailed.primary,
      error: true,
    ),
    data: (items) => _SearchableProjectPicker(
      fieldKey: const ValueKey('mobile-mr-project'),
      value: _draft.projectId,
      items: items,
      enabled: !_busy,
      labelText: YorksV1MaterialRequestStrings.project.active(_language),
      onChanged: _changeProject,
    ),
  );

  Widget _mobileScopeField() => widget.scopes.when(
    loading: () => const LinearProgressIndicator(),
    error: (_, _) => _MobileMrNotice(
      icon: Icons.sync_problem_rounded,
      text: YorksV1MaterialRequestStrings.saveFailed.primary,
      error: true,
    ),
    data: (items) => DropdownButtonFormField<String>(
      key: const ValueKey('mobile-mr-scope'),
      initialValue: items.any((item) => item.id == _draft.scopeId)
          ? _draft.scopeId
          : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: YorksV1MaterialRequestStrings.scope.active(_language),
      ),
      items: [
        for (final item in items)
          DropdownMenuItem(value: item.id, child: Text(item.name)),
      ],
      onChanged: _busy ? null : _changeScope,
    ),
  );

  Widget _mobileScheduledDate() => OutlinedButton.icon(
    icon: const Icon(Icons.calendar_today_outlined, size: 18),
    label: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        _draft.scheduledDate == null
            ? YorksV1MaterialRequestStrings.scheduledDate.active(_language)
            : MaterialLocalizations.of(
                context,
              ).formatMediumDate(_draft.scheduledDate!),
      ),
    ),
    onPressed: _busy ? null : _pickScheduledDate,
  );

  Widget _materialsBody() => Column(
    children: [
      Expanded(
        child: ListView(
          key: const ValueKey('mobile-mr-materials'),
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
          children: [
            _MobileMrProgress(step: _step, language: _language),
            const SizedBox(height: 20),
            Text(
              YorksV1MaterialRequestStrings.materialBasket.active(_language),
              style: AppTypography.headlineMedium.copyWith(
                fontSize: 25,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              YorksV1MaterialRequestStrings.materialBasketDescription.active(
                _language,
              ),
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 14),
            if (_draft.projectId?.trim().isNotEmpty != true) ...[
              _MobileMrNotice(
                icon: Icons.info_outline_rounded,
                text: YorksV1MaterialRequestStrings
                    .chooseProjectBeforeAdding
                    .primary,
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    key: const ValueKey('mobile-mr-add-from-boq'),
                    onPressed:
                        _busy || _draft.projectId?.trim().isNotEmpty != true
                        ? null
                        : _openBoqFolders,
                    icon: const Icon(Icons.folder_outlined, size: 19),
                    label: Text(
                      YorksV1MaterialRequestStrings.addFromBoq.active(
                        _language,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('mobile-mr-add-custom'),
                    onPressed:
                        _busy || _draft.projectId?.trim().isNotEmpty != true
                        ? null
                        : () => setState(() {
                            _customValidationAttempted = false;
                            _sourcePage =
                                _MobileMaterialRequestSourcePage.custom;
                          }),
                    icon: const Icon(Icons.add_box_outlined, size: 19),
                    label: Text(
                      YorksV1MaterialRequestStrings.addCustomItem.active(
                        _language,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            YorksMobileSectionHeader(
              title: YorksV1MaterialRequestStrings.selectedItems.active(
                _language,
              ),
              subtitle:
                  '${_draft.lines.length} ${YorksV1MaterialRequestStrings.items.active(_language).toLowerCase()}',
            ),
            const SizedBox(height: 10),
            if (_draft.lines.isEmpty)
              _MobileMrBasketEmpty(language: _language)
            else ...[
              if (_draft.lines.any((line) => line.quantityIsSuggested))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _MobileMrNotice(
                    icon: Icons.info_outline_rounded,
                    text: YorksV1MaterialRequestStrings
                        .suggestedQuantityReview
                        .primary,
                  ),
                ),
              for (final line in _draft.lines) ...[
                _MobileMrDraftLineCard(
                  line: line,
                  enabled: !_busy,
                  onEdit: () => _editMaterial(line),
                  onAddSimilar: () => _addSimilarMaterial(line),
                  onAddCustom: () => _addCustomMaterialAfter(line),
                  onRemove: () => widget.controller.removeLine(line.id),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ],
        ),
      ),
      _MobileMrStickyActions(
        secondaryLabel: YorksV1MaterialRequestStrings.back.active(_language),
        onSecondary: () =>
            setState(() => _step = _MobileMaterialRequestDraftStep.information),
        primaryLabel: YorksV1MaterialRequestStrings.review.active(_language),
        primaryIcon: Icons.arrow_forward_rounded,
        onPrimary: _busy || _draft.lines.isEmpty
            ? null
            : () {
                widget.controller.recordReviewReached();
                setState(() => _step = _MobileMaterialRequestDraftStep.review);
              },
      ),
    ],
  );

  Widget _reviewBody() {
    final controlledUnitsReady = yorksV1ControlledUnitsReady(
      ref.watch(yorksV1ConfigurationUnitCodesProvider),
    );
    final project = widget.projects.valueOrNull
        ?.where((item) => item.id == _draft.projectId)
        .firstOrNull;
    final scope = widget.scopes.valueOrNull
        ?.where((item) => item.id == _draft.scopeId)
        .firstOrNull;
    final active = project?.state == YorksV1ProjectLifecycle.active.wireValue;
    final canAttemptSubmit = widget.canSubmit && _reviewConfirmed && !_busy;
    final invalidLineCount = _draft.lines
        .where((line) => !line.hasValidOperationalValues)
        .length;
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('mobile-mr-review'),
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
            children: [
              _MobileMrProgress(step: _step, language: _language),
              const SizedBox(height: 20),
              Text(
                YorksV1MaterialRequestStrings.reviewAndSubmit.active(_language),
                style: AppTypography.headlineMedium.copyWith(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                YorksV1MaterialRequestStrings.reviewDescription.active(
                  _language,
                ),
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              YorksMobileCard(
                child: Column(
                  children: [
                    _MobileMrFact(
                      label: YorksV1MaterialRequestStrings.project.primary,
                      value: project == null
                          ? YorksV1MaterialRequestStrings.notProvided.primary
                          : '${project.reference} · ${project.name}',
                    ),
                    _MobileMrFact(
                      label: YorksV1MaterialRequestStrings.scopeLabel.primary,
                      value:
                          scope?.name ??
                          YorksV1MaterialRequestStrings.notProvided.primary,
                    ),
                    _MobileMrFact(
                      label: YorksV1MaterialRequestStrings.delivery.primary,
                      value: yorksV1MaterialRequestTimingCopy(
                        _draft.timing,
                      ).primary,
                    ),
                    _MobileMrFact(
                      label: YorksV1MaterialRequestStrings.items.primary,
                      value: _draft.lines.length.toString(),
                      last: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (_draft.lines.any((line) => line.quantityIsSuggested))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _MobileMrNotice(
                    icon: Icons.info_outline_rounded,
                    text: YorksV1MaterialRequestStrings
                        .suggestedQuantityReview
                        .primary,
                  ),
                ),
              if (!active)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _MobileMrNotice(
                    icon: Icons.error_outline_rounded,
                    text: YorksV1MaterialRequestStrings
                        .projectMustBeActive
                        .primary,
                    error: true,
                  ),
                ),
              if (!controlledUnitsReady)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _MobileMrNotice(
                    icon: Icons.cloud_off_outlined,
                    text: YorksV1ControlledUnitStrings.unavailable.primary,
                    error: true,
                  ),
                ),
              if (invalidLineCount > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _MobileMrNotice(
                    icon: Icons.error_outline_rounded,
                    text: YorksV1MaterialRequestStrings.rowsNeedAttention(
                      invalidLineCount,
                    ).primary,
                    error: true,
                  ),
                ),
              YorksMobileSectionHeader(
                title: YorksV1MaterialRequestStrings.selectedItems.primary,
                subtitle:
                    '${_draft.lines.length} ${YorksV1MaterialRequestStrings.items.primary.toLowerCase()}',
              ),
              const SizedBox(height: 10),
              for (var index = 0; index < _draft.lines.length; index++) ...[
                _MobileMrReviewLineCard(
                  number: index + 1,
                  line: _draft.lines[index],
                ),
                if (index != _draft.lines.length - 1)
                  const SizedBox(height: 10),
              ],
              const SizedBox(height: 4),
              Material(
                color: Colors.transparent,
                child: CheckboxListTile(
                  value: _reviewConfirmed,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: _busy
                      ? null
                      : (value) =>
                            setState(() => _reviewConfirmed = value ?? false),
                  title: Text(
                    YorksV1MaterialRequestStrings.confirmScopeAndLines.active(
                      _language,
                    ),
                    style: AppTypography.bodySmall,
                  ),
                ),
              ),
            ],
          ),
        ),
        _MobileMrStickyActions(
          secondaryLabel: YorksV1MaterialRequestStrings.saveDraft.active(
            _language,
          ),
          onSecondary: _busy ? null : widget.onSave,
          primaryLabel: YorksV1MaterialRequestStrings.submitToProcurement
              .active(_language),
          primaryIcon: Icons.send_rounded,
          loading:
              _busy &&
              widget.state.status ==
                  YorksV1MaterialRequestDraftSyncStatus.submitting,
          onPrimary: canAttemptSubmit ? _submit : null,
        ),
      ],
    );
  }

  Widget _boqFoldersBody() {
    if (_loadingSource) return const Center(child: CircularProgressIndicator());
    final groups = _groups ?? const <YorksV1BoqGroup>[];
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('mobile-mr-boq-folders'),
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
            children: [
              Text(
                YorksV1MaterialRequestStrings.addFromBoq.primary,
                style: AppTypography.headlineMedium.copyWith(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                YorksV1MaterialRequestStrings.selectScopeToAddBoq.primary,
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              if (groups.isEmpty)
                _MobileMrNotice(
                  icon: Icons.folder_off_outlined,
                  text: YorksV1MaterialRequestStrings.noBoqItems.primary,
                )
              else
                for (final group in groups) ...[
                  YorksMobileCard(
                    onTap: group.rowCount > 0
                        ? () => _openWorksheet(group)
                        : null,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.folder_outlined,
                          color: AppColors.blue,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                group.effectiveTitle,
                                style: AppTypography.titleSmall.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${group.rowCount} ${YorksV1MaterialRequestStrings.items.primary.toLowerCase()}',
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (group.rowCount == 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusFull,
                              ),
                            ),
                            child: Text(
                              YorksV1BoqStrings.emptyFolders.primary,
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.muted,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          )
                        else
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.muted,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _boqRowsBody() {
    final worksheet = _worksheet;
    if (_loadingSource || worksheet == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('mobile-mr-boq-rows'),
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
            children: [
              Text(
                worksheet.group.effectiveTitle,
                style: AppTypography.headlineSmall.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_selectedBoqRows.length} ${YorksV1MaterialRequestStrings.selectedItems.primary.toLowerCase()}',
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              for (final row in worksheet.rows) ...[
                YorksMobileCard(
                  onTap: () => setState(() {
                    if (_selectedBoqRows.contains(row.id)) {
                      _selectedBoqRows.remove(row.id);
                    } else {
                      _selectedBoqRows.add(row.id);
                    }
                  }),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _selectedBoqRows.contains(row.id),
                        onChanged: (_) => setState(() {
                          if (_selectedBoqRows.contains(row.id)) {
                            _selectedBoqRows.remove(row.id);
                          } else {
                            _selectedBoqRows.add(row.id);
                          }
                        }),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _boqDisplayValue(
                                    worksheet,
                                    row,
                                    YorksV1BoqCanonicalField.description,
                                  ).isEmpty
                                  ? YorksV1MaterialRequestStrings
                                        .notProvided
                                        .primary
                                  : _boqDisplayValue(
                                      worksheet,
                                      row,
                                      YorksV1BoqCanonicalField.description,
                                    ),
                              style: AppTypography.titleSmall.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_boqDisplayValue(worksheet, row, YorksV1BoqCanonicalField.quantity)} ${_boqDisplayValue(worksheet, row, YorksV1BoqCanonicalField.unit)}',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        _MobileMrStickyActions(
          secondaryLabel: YorksV1MaterialRequestStrings.back.primary,
          onSecondary: () => setState(
            () => _sourcePage = _MobileMaterialRequestSourcePage.boqFolders,
          ),
          primaryLabel: YorksV1MaterialRequestStrings.addFromBoq.primary,
          primaryIcon: Icons.add_rounded,
          onPrimary: _selectedBoqRows.isEmpty || _busy
              ? null
              : _addSelectedBoqRows,
        ),
      ],
    );
  }

  Widget _customMaterialBody() {
    final unitsAsync = ref.watch(yorksV1ConfigurationUnitCodesProvider);
    final controlledUnits = yorksV1LoadedControlledUnits(unitsAsync);
    final descriptionReady = _customDescription.text.trim().isNotEmpty;
    final quantityReady =
        YorksV1DecimalQuantity.tryParse(_customQuantity.text)?.isPositive ==
        true;
    final unitReady = controlledUnits.contains(_customUnit.trim());
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('mobile-mr-custom-material'),
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
            children: [
              Text(
                _editingCustomLineId != null && !_discardCustomLineOnClose
                    ? AppStrings.editMaterial.active(_language)
                    : YorksV1MaterialRequestStrings.unplannedMaterial.active(
                        _language,
                      ),
                style: AppTypography.headlineMedium.copyWith(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _editingCustomLineId != null && !_discardCustomLineOnClose
                    ? YorksV1MaterialRequestStrings.editMaterialDescription
                          .active(_language)
                    : YorksV1MaterialRequestStrings.requestScopeDescription
                          .active(_language),
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              YorksMobileCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    KeyedSubtree(
                      key: const ValueKey('mobile-custom-description'),
                      child: _MobileInventoryDescriptionField(
                        controller: _customDescription,
                        projectId: _draft.projectId,
                        scopeId: _draft.scopeId,
                        enabled: !_busy,
                        onEdited: (_) {
                          if (_customSuggestion != null) {
                            setState(() => _customSuggestion = null);
                          }
                        },
                        onSelected: (suggestion) => setState(() {
                          _customValidationAttempted = false;
                          _customSuggestion = suggestion;
                          _customBrand.text = suggestion.brandOrigin ?? '';
                          _customSize.text = suggestion.size ?? '';
                          _customModel.text = suggestion.model ?? '';
                          _customUnit = suggestion.unit;
                        }),
                        errorText:
                            _customValidationAttempted && !descriptionReady
                            ? YorksV1MaterialRequestStrings
                                  .itemDescriptionRequired
                                  .active(_language)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('mobile-custom-quantity'),
                            controller: _customQuantity,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: YorksV1MaterialRequestStrings.quantity
                                  .active(_language),
                              errorText:
                                  _customValidationAttempted && !quantityReady
                                  ? YorksV1MaterialRequestStrings
                                        .quantityRequired
                                        .active(_language)
                                  : null,
                            ),
                            onChanged: (_) {
                              if (_customValidationAttempted) setState(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: YorksV1ControlledUnitDropdown(
                            fieldKey: const ValueKey(
                              'mobile-custom-material-unit',
                            ),
                            label: YorksV1MaterialRequestStrings.unit.active(
                              _language,
                            ),
                            value: _customUnit,
                            enabled: !_busy,
                            showDependencyStatus: true,
                            onChanged: (value) =>
                                setState(() => _customUnit = value),
                            errorText: _customValidationAttempted && !unitReady
                                ? YorksV1MaterialRequestStrings.unitRequired
                                      .active(_language)
                                : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('mobile-custom-brand'),
                      controller: _customBrand,
                      decoration: InputDecoration(
                        labelText: YorksV1MaterialRequestStrings.brandOrigin
                            .active(_language),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('mobile-custom-size'),
                      controller: _customSize,
                      decoration: InputDecoration(
                        labelText: YorksV1MaterialRequestStrings.size.active(
                          _language,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('mobile-custom-model'),
                      controller: _customModel,
                      decoration: InputDecoration(
                        labelText: YorksV1MaterialRequestStrings
                            .planningModelTag
                            .active(_language),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _MobileMrStickyActions(
          secondaryLabel: YorksV1MaterialRequestStrings.back.primary,
          onSecondary: () => unawaited(_closeCustomMaterialEditor()),
          primaryLabel: _editingCustomLineId == null
              ? YorksV1MaterialRequestStrings.addCustomItem.primary
              : AppStrings.saveChanges.primary,
          primaryIcon: _editingCustomLineId == null
              ? Icons.add_rounded
              : Icons.check_rounded,
          onPrimary: _busy ? null : _addCustomMaterial,
        ),
      ],
    );
  }

  Widget _successPage(BuildContext context, YorksV1MaterialRequest request) =>
      ColoredBox(
        color: AppColors.mobileSurface,
        child: Column(
          children: [
            YorksMobileAppBar(
              title: YorksV1MaterialRequestStrings.submitted.active(_language),
              leading: YorksMobileIconButton(
                icon: Icons.close_rounded,
                tooltip: YorksV1MaterialRequestStrings.backToRequests.active(
                  _language,
                ),
                onPressed: () => context.go(RoutePaths.yorksV1MaterialRequests),
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: YorksMobileCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 28,
                        horizontal: 8,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DecoratedBox(
                            decoration: const BoxDecoration(
                              color: AppColors.successContainer,
                              shape: BoxShape.circle,
                            ),
                            child: const SizedBox.square(
                              dimension: 64,
                              child: Icon(
                                Icons.check_rounded,
                                color: AppColors.success,
                                size: 34,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            YorksV1MaterialRequestStrings.submitted.active(
                              _language,
                            ),
                            textAlign: TextAlign.center,
                            style: AppTypography.headlineSmall.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            YorksV1MaterialRequestStrings.serverConfirmed
                                .active(_language),
                            textAlign: TextAlign.center,
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            request.requestNumber ??
                                YorksV1MaterialRequestStrings.assignedOnSubmit
                                    .active(_language),
                            style: AppTypography.labelLarge.copyWith(
                              color: AppColors.blue,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _MobileMrStickyActions(
              secondaryLabel: YorksV1MaterialRequestStrings.backToRequests
                  .active(_language),
              onSecondary: () => context.go(RoutePaths.yorksV1MaterialRequests),
              primaryLabel: YorksV1MaterialRequestStrings.viewRequest.active(
                _language,
              ),
              primaryIcon: Icons.arrow_forward_rounded,
              onPrimary: () =>
                  context.go(RoutePaths.yorksV1MaterialRequestPath(request.id)),
            ),
          ],
        ),
      );

  Future<void> _continueToMaterials() async {
    if (_draft.projectId == null || _draft.scopeId == null) {
      _snack(context, YorksV1MaterialRequestStrings.missingRequired.primary);
      return;
    }
    setState(() => _step = _MobileMaterialRequestDraftStep.materials);
  }

  Future<void> _changeProject(String? projectId) async {
    final preservesExistingLines =
        _draft.lines.isNotEmpty && projectId != _draft.projectId;
    await widget.controller.setProject(
      projectId,
      preserveExistingLines: preservesExistingLines,
    );
    if (preservesExistingLines && mounted) {
      _snack(
        context,
        YorksV1MaterialRequestStrings.changeProjectPreservesLines.primary,
      );
    }
  }

  Future<void> _changeScope(String? scopeId) async {
    final boqRows = _draft.lines
        .where((line) => line.source == YorksV1MaterialRequestLineSource.boq)
        .length;
    final requiresConfirmation = scopeId != _draft.scopeId && boqRows > 0;
    if (requiresConfirmation &&
        !await _confirmDiscard(
          YorksV1MaterialRequestStrings.changeScope.primary,
          YorksV1MaterialRequestStrings.changeScopeDiscardBoqRows.primary
              .replaceFirst('{count}', boqRows.toString()),
        )) {
      return;
    }
    await widget.controller.setScope(
      scopeId,
      discardIncompatibleBoqRows: requiresConfirmation,
    );
  }

  Future<bool> _confirmDiscard(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        animationStyle: AnimationStyle.noAnimation,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(YorksV1MaterialRequestStrings.cancel.primary),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(title),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _pickScheduledDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
      initialDate: _draft.scheduledDate ?? now,
    );
    if (selected != null) await widget.controller.setScheduledDate(selected);
  }

  Future<void> _openBoqFolders() async {
    if (_draft.projectId == null || _draft.scopeId == null) {
      _snack(
        context,
        YorksV1MaterialRequestStrings.selectScopeToAddBoq.primary,
      );
      return;
    }
    setState(() {
      _loadingSource = true;
      _sourcePage = _MobileMaterialRequestSourcePage.boqFolders;
    });
    try {
      final groups = await ref
          .read(yorksV1BoqRepositoryProvider)
          .listGroupsForScope(_draft.projectId!, scopeId: _draft.scopeId!);
      if (mounted) {
        setState(() => _groups = groups);
      }
    } catch (_) {
      if (mounted) {
        _snack(context, YorksV1MaterialRequestStrings.saveFailed.primary);
      }
    } finally {
      if (mounted) {
        setState(() => _loadingSource = false);
      }
    }
  }

  Future<void> _openWorksheet(YorksV1BoqGroup group) async {
    setState(() => _loadingSource = true);
    try {
      final worksheet = await ref
          .read(yorksV1BoqRepositoryProvider)
          .getWorksheet(group.id);
      if (!mounted) return;
      final existing = _draft.lines
          .map((line) => line.sourceBoqRowId)
          .whereType<String>();
      setState(() {
        _worksheet = worksheet;
        _selectedBoqRows
          ..clear()
          ..addAll(
            existing.where((id) => worksheet.rows.any((row) => row.id == id)),
          );
        _sourcePage = _MobileMaterialRequestSourcePage.boqRows;
      });
    } catch (_) {
      if (mounted) {
        _snack(context, YorksV1MaterialRequestStrings.saveFailed.primary);
      }
    } finally {
      if (mounted) {
        setState(() => _loadingSource = false);
      }
    }
  }

  Future<void> _addSelectedBoqRows() async {
    final worksheet = _worksheet;
    if (worksheet == null) return;
    try {
      await widget.controller.addBoqRows(
        worksheet: worksheet,
        rowIds: _selectedBoqRows,
      );
      if (!mounted) return;
      setState(() {
        _sourcePage = _MobileMaterialRequestSourcePage.none;
        _selectedBoqRows.clear();
      });
      _snack(context, YorksV1MaterialRequestStrings.itemAdded.primary);
    } on YorksV1DomainException {
      if (mounted) {
        _snack(
          context,
          YorksV1MaterialRequestStrings.selectScopeToAddBoq.primary,
        );
      }
    } catch (_) {
      if (mounted) {
        _snack(context, YorksV1MaterialRequestStrings.saveFailed.primary);
      }
    }
  }

  Future<void> _addCustomMaterial() async {
    final controlledUnits = yorksV1LoadedControlledUnits(
      ref.read(yorksV1ConfigurationUnitCodesProvider),
    );
    if (_customDescription.text.trim().isEmpty ||
        YorksV1DecimalQuantity.tryParse(_customQuantity.text)?.isPositive !=
            true ||
        !controlledUnits.contains(_customUnit.trim())) {
      setState(() => _customValidationAttempted = true);
      final message = _customDescription.text.trim().isEmpty
          ? YorksV1MaterialRequestStrings.itemDescriptionRequired
          : YorksV1DecimalQuantity.tryParse(_customQuantity.text)?.isPositive !=
                true
          ? YorksV1MaterialRequestStrings.quantityRequired
          : YorksV1MaterialRequestStrings.unitRequired;
      _snack(context, message.primary);
      return;
    }
    final editingLineId = _editingCustomLineId;
    final editedExistingLine =
        editingLineId != null && !_discardCustomLineOnClose;
    if (editingLineId == null) await widget.controller.addCustomLine();
    final line = editingLineId == null
        ? widget.controller.currentDraft.lines.lastOrNull
        : widget.controller.currentDraft.lines
              .where((item) => item.id == editingLineId)
              .firstOrNull;
    if (line == null) return;
    await widget.controller.updateLine(line.id, (current) {
      final selected = _customSuggestion;
      final correlated = selected == null
          ? current
          : _applyMaterialSuggestion(current, selected);
      return correlated.copyWith(
        description: _customDescription.text,
        brandOrigin: _customBrand.text.trim().isEmpty
            ? null
            : _customBrand.text,
        size: _customSize.text.trim().isEmpty ? null : _customSize.text,
        model: _customModel.text.trim().isEmpty ? null : _customModel.text,
        quantity: _customQuantity.text,
        unit: _customUnit,
      );
    });
    if (!mounted) return;
    setState(() {
      _sourcePage = _MobileMaterialRequestSourcePage.none;
      _editingCustomLineId = null;
      _discardCustomLineOnClose = false;
      _customSuggestion = null;
      _customDescription.clear();
      _customBrand.clear();
      _customSize.clear();
      _customModel.clear();
      _customQuantity.text = '1';
      _customUnit = '';
      _customValidationAttempted = false;
    });
    _snack(
      context,
      editedExistingLine
          ? YorksV1MaterialRequestStrings.itemUpdated.primary
          : YorksV1MaterialRequestStrings.itemAdded.primary,
    );
  }

  void _editMaterial(YorksV1MaterialRequestLine line) {
    setState(() {
      _editingCustomLineId = line.id;
      _discardCustomLineOnClose = false;
      _customSuggestion = null;
      _customDescription.text = line.description;
      _customBrand.text = line.brandOrigin ?? '';
      _customSize.text = line.size ?? '';
      _customModel.text = line.model ?? line.planningModelTag ?? '';
      _customQuantity.text = line.quantity;
      _customUnit = line.unit;
      _customValidationAttempted = false;
      _sourcePage = _MobileMaterialRequestSourcePage.custom;
    });
  }

  Future<void> _addSimilarMaterial(YorksV1MaterialRequestLine source) async {
    await widget.controller.addSimilarLine(afterLineId: source.id);
    final lines = widget.controller.currentDraft.lines;
    final sourceIndex = lines.indexWhere((line) => line.id == source.id);
    if (sourceIndex < 0 || sourceIndex + 1 >= lines.length || !mounted) return;
    final similar = lines[sourceIndex + 1];
    setState(() {
      _editingCustomLineId = similar.id;
      _discardCustomLineOnClose = true;
      _customSuggestion = null;
      _customDescription.text = similar.description;
      _customBrand.text = similar.brandOrigin ?? '';
      _customSize.text = similar.size ?? '';
      _customModel.text = similar.model ?? similar.planningModelTag ?? '';
      _customQuantity.clear();
      _customUnit = similar.unit;
      _customValidationAttempted = false;
      _sourcePage = _MobileMaterialRequestSourcePage.custom;
    });
  }

  Future<void> _addCustomMaterialAfter(
    YorksV1MaterialRequestLine source,
  ) async {
    await widget.controller.addCustomLine(afterLineId: source.id);
    final lines = widget.controller.currentDraft.lines;
    final sourceIndex = lines.indexWhere((line) => line.id == source.id);
    if (sourceIndex < 0 || sourceIndex + 1 >= lines.length || !mounted) return;
    final custom = lines[sourceIndex + 1];
    setState(() {
      _editingCustomLineId = custom.id;
      _discardCustomLineOnClose = true;
      _customSuggestion = null;
      _customDescription.clear();
      _customBrand.clear();
      _customSize.clear();
      _customModel.clear();
      _customQuantity.text = '1';
      _customUnit = '';
      _customValidationAttempted = false;
      _sourcePage = _MobileMaterialRequestSourcePage.custom;
    });
  }

  Future<void> _closeCustomMaterialEditor() async {
    final provisionalLineId = _discardCustomLineOnClose
        ? _editingCustomLineId
        : null;
    if (provisionalLineId != null) {
      await widget.controller.removeLine(provisionalLineId);
    }
    if (!mounted) return;
    setState(() {
      _sourcePage = _MobileMaterialRequestSourcePage.none;
      _editingCustomLineId = null;
      _discardCustomLineOnClose = false;
      _customSuggestion = null;
      _customDescription.clear();
      _customBrand.clear();
      _customSize.clear();
      _customModel.clear();
      _customQuantity.text = '1';
      _customUnit = '';
      _customValidationAttempted = false;
    });
  }

  Future<void> _submit() async {
    final validationMessage = _materialRequestSubmitValidationMessage(_draft);
    if (validationMessage != null) {
      setState(() => _step = _MobileMaterialRequestDraftStep.materials);
      _snack(context, validationMessage.primary);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_revealFirstInvalidMaterialRequestLine(_draft));
      });
      return;
    }
    final submitted = await widget.onSubmit();
    if (submitted != null && mounted) setState(() => _submitted = submitted);
  }

  void _back() {
    if (_sourcePage == _MobileMaterialRequestSourcePage.boqRows) {
      setState(() => _sourcePage = _MobileMaterialRequestSourcePage.boqFolders);
      return;
    }
    if (_sourcePage != _MobileMaterialRequestSourcePage.none) {
      unawaited(_closeCustomMaterialEditor());
      return;
    }
    if (_step == _MobileMaterialRequestDraftStep.review) {
      setState(() => _step = _MobileMaterialRequestDraftStep.materials);
      return;
    }
    if (_step == _MobileMaterialRequestDraftStep.materials) {
      setState(() => _step = _MobileMaterialRequestDraftStep.information);
      return;
    }
    context.pop();
  }
}

class _MobileMrProgress extends StatelessWidget {
  const _MobileMrProgress({required this.step, required this.language});

  final _MobileMaterialRequestDraftStep step;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    const labels = [
      YorksV1MaterialRequestStrings.detailsStep,
      YorksV1MaterialRequestStrings.items,
      YorksV1MaterialRequestStrings.review,
    ];
    return Row(
      children: [
        for (var index = 0; index < labels.length; index++) ...[
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: index <= step.index
                        ? AppColors.blue
                        : AppColors.surfaceContainerHigh,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: index < step.index
                      ? const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: AppColors.onPrimary,
                        )
                      : Text(
                          '${index + 1}',
                          style: AppTypography.labelSmall.copyWith(
                            color: index <= step.index
                                ? AppColors.onPrimary
                                : AppColors.muted,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
                const SizedBox(height: 4),
                Text(
                  labels[index].active(language),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTypography.labelSmall.copyWith(
                    color: index == step.index
                        ? AppColors.blue
                        : AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          if (index + 1 < labels.length)
            Expanded(
              child: Container(
                height: 1,
                margin: const EdgeInsets.only(bottom: 22),
                color: index < step.index ? AppColors.blue : AppColors.line,
              ),
            ),
        ],
      ],
    );
  }
}

class _MobileMrStickyActions extends StatelessWidget {
  const _MobileMrStickyActions({
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.loading = false,
  });

  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool loading;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          if (secondaryLabel != null) ...[
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('mobile-mr-secondary-action'),
                onPressed: onSecondary,
                child: Text(secondaryLabel!),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            flex: secondaryLabel == null ? 1 : 2,
            child: FilledButton.icon(
              key: const ValueKey('mobile-mr-primary-action'),
              onPressed: onPrimary,
              icon: loading
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      ),
                    )
                  : Icon(primaryIcon),
              label: Text(primaryLabel),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MobileMrBasketEmpty extends StatelessWidget {
  const _MobileMrBasketEmpty({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) => YorksMobileCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.shopping_basket_outlined,
            size: 24,
            color: AppColors.muted,
          ),
          const SizedBox(width: 10),
          Text(
            YorksV1MaterialRequestStrings.materialBasketEmpty.active(language),
            style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}

class _MobileMrDraftLineCard extends StatelessWidget {
  const _MobileMrDraftLineCard({
    required this.line,
    required this.enabled,
    required this.onEdit,
    required this.onAddSimilar,
    required this.onAddCustom,
    required this.onRemove,
  });

  final YorksV1MaterialRequestLine line;
  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onAddSimilar;
  final VoidCallback onAddCustom;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final errors = <String>[
      if (!line.hasDescription)
        YorksV1MaterialRequestStrings.itemDescriptionRequired.primary,
      if (!line.hasValidQuantity)
        YorksV1MaterialRequestStrings.quantityRequired.primary,
      if (!line.hasControlledUnit)
        YorksV1MaterialRequestStrings.unitRequired.primary,
    ];
    return YorksMobileCard(
      key: _materialRequestLineKey(line.id),
      color: errors.isEmpty
          ? AppColors.surfaceContainerLowest
          : AppColors.errorContainer,
      onTap: enabled ? onEdit : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${line.displayOrder}',
                  style: AppTypography.labelMedium.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (errors.isNotEmpty) ...[
                const SizedBox(width: 6),
                _MrValidationMarker(
                  markerKey: ValueKey('${line.id}-mobile-validation-error'),
                  message: errors.join(' · '),
                ),
              ],
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.description.isEmpty
                          ? YorksV1MaterialRequestStrings.notProvided.primary
                          : line.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${yorksV1DisplayQuantity(line.quantity)} ${line.unit}${line.brandOrigin?.trim().isNotEmpty == true ? ' · ${line.brandOrigin}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MrEditButton(
                  buttonKey: ValueKey('${line.id}-mobile-edit'),
                  enabled: enabled,
                  onPressed: onEdit,
                ),
                const SizedBox(width: 6),
                _MrSimilarButton(
                  buttonKey: ValueKey('${line.id}-mobile-similar'),
                  enabled: enabled,
                  onPressed: onAddSimilar,
                ),
                const SizedBox(width: 6),
                _MrCustomButton(
                  buttonKey: ValueKey('${line.id}-mobile-custom'),
                  enabled: enabled,
                  onPressed: onAddCustom,
                ),
                const SizedBox(width: 6),
                _MrDeleteButton(
                  buttonKey: ValueKey('${line.id}-mobile-delete'),
                  enabled: enabled,
                  onPressed: onRemove,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileMrReviewLineCard extends StatelessWidget {
  const _MobileMrReviewLineCard({required this.number, required this.line});

  final int number;
  final YorksV1MaterialRequestLine line;

  @override
  Widget build(BuildContext context) {
    final details = <(String, String)>[
      if (line.brandOrigin?.trim().isNotEmpty == true)
        (
          YorksV1MaterialRequestStrings.brandOrigin.primary,
          line.brandOrigin!.trim(),
        ),
      if (line.size?.trim().isNotEmpty == true)
        (YorksV1MaterialRequestStrings.size.primary, line.size!.trim()),
      if ((line.model ?? line.planningModelTag)?.trim().isNotEmpty == true)
        (
          YorksV1MaterialRequestStrings.planningModelTag.primary,
          (line.model ?? line.planningModelTag)!.trim(),
        ),
    ];
    return YorksMobileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.blueContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$number',
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.blue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  line.description,
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _MobileMrReviewFact(
            label: YorksV1MaterialRequestStrings.quantity.primary,
            value: '${yorksV1DisplayQuantity(line.quantity)} ${line.unit}',
          ),
          for (final detail in details)
            _MobileMrReviewFact(label: detail.$1, value: detail.$2),
        ],
      ),
    );
  }
}

class _MobileMrReviewFact extends StatelessWidget {
  const _MobileMrReviewFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 104,
          child: Text(
            label,
            style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _MobileMrFact extends StatelessWidget {
  const _MobileMrFact({
    required this.label,
    required this.value,
    this.last = false,
  });

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: last ? 0 : 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.muted,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        if (!last)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Divider(height: 1, color: AppColors.line),
          ),
      ],
    ),
  );
}

class _MobileMrNotice extends StatelessWidget {
  const _MobileMrNotice({
    required this.icon,
    required this.text,
    this.error = false,
  });

  final IconData icon;
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: error ? AppColors.errorContainer : AppColors.blueContainer,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: error ? AppColors.errorContainer : AppColors.blueContainerStrong,
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: error ? AppColors.error : AppColors.blue),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.inkSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Display-only preview matching the R35 prototype. The server assigns the
/// authoritative request number during Submit; this value must never be used
/// as an identifier for a write or workflow transition.
String _previewRequestNumber(YorksV1MaterialRequestProjectOption? project) =>
    YorksV1MaterialRequestStrings.assignedOnSubmit.primary;

int _materialRequestStage(YorksV1MaterialRequestState state) => switch (state) {
  YorksV1MaterialRequestState.draft => 1,
  YorksV1MaterialRequestState.submitted ||
  YorksV1MaterialRequestState.awaitingRequestApproval ||
  YorksV1MaterialRequestState.changesRequested => 2,
  YorksV1MaterialRequestState.approvedForArrangement ||
  YorksV1MaterialRequestState.arranging ||
  YorksV1MaterialRequestState.awaitingApproval => 3,
  YorksV1MaterialRequestState.approved => 4,
  YorksV1MaterialRequestState.partiallyDispatched ||
  YorksV1MaterialRequestState.dispatched => 5,
  YorksV1MaterialRequestState.partiallyReceived ||
  YorksV1MaterialRequestState.received => 6,
  // Closed sits beyond the seventh visible stage so every lifecycle marker
  // renders complete. The stage badge clamps this back to the user-facing
  // "Stage 7 of 7" label.
  YorksV1MaterialRequestState.closed => 8,
  YorksV1MaterialRequestState.cancelled => 1,
};

List<TranslatableString> get _materialRequestStageLabels => const [
  YorksV1MaterialRequestStrings.requestCreated,
  YorksV1MaterialRequestStrings.engineeringApproval,
  YorksV1MaterialRequestStrings.procurementArrangement,
  YorksV1MaterialRequestStrings.readyForDeliveryStage,
  YorksV1MaterialRequestStrings.dispatch,
  YorksV1MaterialRequestStrings.receivedStage,
  YorksV1MaterialRequestStrings.completedStage,
];

List<TranslatableString> get _materialRequestCompactStageLabels => const [
  YorksV1MaterialRequestStrings.requestCreated,
  YorksV1MaterialRequestStrings.engineeringApprovalShort,
  YorksV1MaterialRequestStrings.procurementArrangementShort,
  YorksV1MaterialRequestStrings.readyForDeliveryShort,
  YorksV1MaterialRequestStrings.dispatch,
  YorksV1MaterialRequestStrings.receivedStage,
  YorksV1MaterialRequestStrings.completedStage,
];

String _materialRequestNextAction(
  YorksV1MaterialRequest value,
  AppLanguage language,
) {
  return yorksV1MaterialRequestNextActionCopy(value).active(language);
}

class _TabletMrDraftActions extends StatelessWidget {
  const _TabletMrDraftActions({
    required this.onCancel,
    required this.onSave,
    required this.onSubmit,
    required this.submitting,
  });

  final VoidCallback onCancel;
  final VoidCallback? onSave;
  final VoidCallback? onSubmit;
  final bool submitting;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border(top: BorderSide(color: AppColors.line)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 12,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: onCancel,
            child: Text(YorksV1MaterialRequestStrings.cancel.primary),
          ),
          const SizedBox(width: AppSpacing.sm),
          OutlinedButton.icon(
            key: const ValueKey('tablet-mr-save'),
            onPressed: onSave,
            icon: const Icon(Icons.save_outlined),
            label: Text(YorksV1MaterialRequestStrings.saveDraft.primary),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton.icon(
            key: const ValueKey('tablet-mr-submit'),
            onPressed: onSubmit,
            icon: submitting
                ? const SizedBox.square(
                    dimension: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onPrimary,
                    ),
                  )
                : const Icon(Icons.arrow_forward_rounded),
            label: Text(
              YorksV1MaterialRequestStrings.submitToProcurement.primary,
            ),
          ),
        ],
      ),
    ),
  );
}

class _R35RequestHero extends StatelessWidget {
  const _R35RequestHero({
    required this.title,
    required this.requesterName,
    required this.projectName,
    required this.lineCount,
    required this.onCancel,
    required this.onSave,
    required this.onSubmit,
    required this.submitting,
    required this.inspectorExpanded,
    required this.onToggleInspector,
  });

  final String title;
  final String requesterName;
  final String? projectName;
  final int lineCount;
  final VoidCallback onCancel;
  final VoidCallback? onSave;
  final VoidCallback? onSubmit;
  final bool submitting;
  final bool inspectorExpanded;
  final VoidCallback onToggleInspector;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked = constraints.maxWidth < 920;
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            YorksV1MaterialRequestStrings.requests.primary.toUpperCase(),
            style: AppTypography.eyebrow,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                YorksV1MaterialRequestStrings.newRequest.primary,
                style: AppTypography.headlineMedium.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              _IndustrialStageChip(stage: 1),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            YorksV1MaterialRequestStrings.requestScopeDescription.primary,
            style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.xs,
            children: [
              _IndustrialMeta(icon: Icons.tag_rounded, value: title),
              _IndustrialMeta(
                icon: Icons.person_outline_rounded,
                value: requesterName.trim().isEmpty
                    ? YorksV1MaterialRequestStrings.requester.primary
                    : requesterName,
              ),
              if (projectName?.trim().isNotEmpty == true)
                _IndustrialMeta(
                  icon: Icons.business_outlined,
                  value: projectName!,
                ),
              _IndustrialMeta(
                icon: Icons.inventory_2_outlined,
                value:
                    '$lineCount ${YorksV1MaterialRequestStrings.items.primary.toLowerCase()}',
              ),
            ],
          ),
        ],
      );
      final actions = ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: stacked
              ? constraints.maxWidth
              : math.min(680, constraints.maxWidth * .58),
        ),
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          alignment: stacked ? WrapAlignment.start : WrapAlignment.end,
          children: [
            _R35RequestAction(
              key: const ValueKey('mr-request-context-toggle'),
              label:
                  (inspectorExpanded
                          ? YorksV1MaterialRequestStrings.hideRequestContext
                          : YorksV1MaterialRequestStrings.showRequestContext)
                      .primary,
              icon: Icons.view_sidebar_outlined,
              onPressed: onToggleInspector,
            ),
            _R35RequestAction(
              label: YorksV1MaterialRequestStrings.saveDraft.primary,
              icon: Icons.save_outlined,
              onPressed: onSave,
            ),
            _R35RequestAction(
              label: YorksV1MaterialRequestStrings.cancel.primary,
              onPressed: onCancel,
            ),
            _R35RequestAction(
              label: YorksV1MaterialRequestStrings.submitToProcurement.primary,
              icon: Icons.arrow_forward_rounded,
              primary: true,
              onPressed: onSubmit,
              loading: submitting,
            ),
          ],
        ),
      );
      return Container(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  heading,
                  const SizedBox(height: AppSpacing.lg),
                  actions,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: AppSpacing.xl),
                  actions,
                ],
              ),
      );
    },
  );
}

class _IndustrialStageChip extends StatelessWidget {
  const _IndustrialStageChip({required this.stage});

  final int stage;

  @override
  Widget build(BuildContext context) {
    final visibleStage = stage > 7 ? 7 : stage;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.successContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: AppColors.success.withValues(alpha: .18)),
      ),
      child: Text(
        YorksV1MaterialRequestStrings.stageOfSeven(visibleStage).primary,
        style: AppTypography.labelSmall.copyWith(
          color: AppColors.onSuccessContainer,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _IndustrialMeta extends StatelessWidget {
  const _IndustrialMeta({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 260),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.muted),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
        ),
      ],
    ),
  );
}

class _IndustrialSectionNumber extends StatelessWidget {
  const _IndustrialSectionNumber({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: AppColors.blue,
      shape: BoxShape.circle,
    ),
    child: Text(
      '$value',
      style: AppTypography.labelSmall.copyWith(
        color: AppColors.onPrimary,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _IndustrialWorkflowStrip extends StatelessWidget {
  const _IndustrialWorkflowStrip({
    super.key,
    required this.stage,
    this.condensed = false,
  });

  final int stage;
  final bool condensed;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Long approval/arrangement labels cannot remain legible in a narrow
      // mobile viewport when all seven are squeezed into equal columns. The
      // desktop inspector keeps the familiar single-row lifecycle, while the
      // same seven-stage truth becomes a compact timeline on mobile.
      if (MediaQuery.sizeOf(context).width <
          AppSpacing.yorksV1DesktopBreakpoint) {
        return Column(
          children: [
            for (
              var index = 0;
              index < _materialRequestStageLabels.length;
              index++
            )
              _CompactWorkflowStage(
                number: index + 1,
                label: _materialRequestStageLabels[index].primary,
                stage: stage,
                last: index == _materialRequestStageLabels.length - 1,
              ),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (
            var index = 0;
            index < _materialRequestStageLabels.length;
            index++
          )
            Expanded(
              child: _IndustrialWorkflowStage(
                number: index + 1,
                label:
                    (condensed
                            ? _materialRequestCompactStageLabels[index]
                            : _materialRequestStageLabels[index])
                        .primary,
                stage: stage,
                first: index == 0,
                last: index == _materialRequestStageLabels.length - 1,
                condensed: condensed,
              ),
            ),
        ],
      );
    },
  );
}

class _CompactWorkflowStage extends StatelessWidget {
  const _CompactWorkflowStage({
    required this.number,
    required this.label,
    required this.stage,
    required this.last,
  });

  final int number;
  final String label;
  final int stage;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final complete = number < stage;
    final active = number == stage;
    return SizedBox(
      height: last ? 34 : 42,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: complete
                        ? AppColors.success
                        : active
                        ? AppColors.blue
                        : AppColors.surfaceContainerLowest,
                    border: Border.all(
                      color: active
                          ? AppColors.blue
                          : complete
                          ? AppColors.success
                          : AppColors.lineStrong,
                    ),
                  ),
                  child: complete
                      ? const Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: AppColors.onSuccess,
                        )
                      : Text(
                          '$number',
                          style: AppTypography.labelSmall.copyWith(
                            color: active
                                ? AppColors.onPrimary
                                : AppColors.muted,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: complete ? AppColors.success : AppColors.line,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelMedium.copyWith(
                  color: active || complete ? AppColors.ink : AppColors.muted,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IndustrialWorkflowStage extends StatelessWidget {
  const _IndustrialWorkflowStage({
    required this.number,
    required this.label,
    required this.stage,
    required this.first,
    required this.last,
    required this.condensed,
  });

  final int number;
  final String label;
  final int stage;
  final bool first;
  final bool last;
  final bool condensed;

  @override
  Widget build(BuildContext context) {
    final complete = number < stage;
    final active = number == stage;
    final color = complete
        ? AppColors.success
        : active
        ? AppColors.blue
        : AppColors.lineStrong;
    final diameter = condensed ? 22.0 : 26.0;
    return Column(
      children: [
        SizedBox(
          height: diameter,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PositionedDirectional(
                start: first ? diameter / 2 : 0,
                end: last ? diameter / 2 : 0,
                child: Container(
                  height: 1.5,
                  color: number <= stage
                      ? AppColors.success.withValues(alpha: .55)
                      : AppColors.line,
                ),
              ),
              Container(
                width: diameter,
                height: diameter,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: complete
                      ? AppColors.success
                      : active
                      ? AppColors.blue
                      : AppColors.surfaceContainerLowest,
                  border: Border.all(color: color, width: active ? 2 : 1.2),
                ),
                child: complete
                    ? const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: AppColors.onSuccess,
                      )
                    : Text(
                        '$number',
                        style: AppTypography.labelSmall.copyWith(
                          color: active ? AppColors.onPrimary : AppColors.muted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: condensed ? 22 : 26,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: Text(
              condensed ? label.replaceFirst(' ', '\n') : label,
              textAlign: TextAlign.center,
              maxLines: 2,
              softWrap: false,
              style: AppTypography.labelSmall.copyWith(
                fontSize: condensed ? 7.8 : 9,
                color: complete || active
                    ? AppColors.inkSecondary
                    : AppColors.muted,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _IndustrialNotice extends StatelessWidget {
  const _IndustrialNotice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.warningContainer.withValues(alpha: .62),
      border: Border.all(color: AppColors.warning.withValues(alpha: .2)),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.warning),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.inkSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

class _IndustrialFactRow extends StatelessWidget {
  const _IndustrialFactRow({
    required this.label,
    required this.value,
    this.last = false,
  });

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    decoration: BoxDecoration(
      border: last
          ? null
          : const Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 104,
          child: Text(
            label,
            style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            value,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _R35RequestCard extends StatelessWidget {
  const _R35RequestCard({
    required this.title,
    required this.child,
    this.sectionNumber,
    this.description,
    this.actions = const [],
  });

  final String title;
  final int? sectionNumber;
  final String? description;
  final List<Widget> actions;
  final Widget child;

  @override
  Widget build(BuildContext context) => _R35RequestSurface(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final heading = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sectionNumber != null) ...[
              _IndustrialSectionNumber(value: sectionNumber!),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.titleMedium.copyWith(
                      color: AppColors.ink,
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
          ],
        );
        final actionWrap = Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: actions,
        );
        // The action row is intentionally stacked until there is enough room
        // for the title to retain a readable width.  Without this guard the
        // Material Items heading is squeezed into one character per line on
        // medium desktop windows when the review panel shares the row.  The
        // card threshold is intentionally wider than the app breakpoint
        // because this card has its own constrained column.
        final compact = constraints.maxWidth < 1320;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (compact) ...[
              heading,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                actionWrap,
              ],
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: heading),
                  if (actions.isNotEmpty) actionWrap,
                ],
              ),
            const SizedBox(height: AppSpacing.lg),
            child,
          ],
        );
      },
    ),
  );
}

class _R35RequestReview extends StatelessWidget {
  const _R35RequestReview({
    required this.draft,
    required this.projects,
    required this.scopes,
    required this.requesterName,
  });

  final YorksV1MaterialRequestDraft draft;
  final AsyncValue<List<YorksV1MaterialRequestProjectOption>> projects;
  final AsyncValue<List<YorksV1MaterialRequestScopeOption>> scopes;
  final String requesterName;

  @override
  Widget build(BuildContext context) {
    final projectMatches = (projects.valueOrNull ?? const [])
        .where((item) => item.id == draft.projectId)
        .toList(growable: false);
    final project = projectMatches.isEmpty ? null : projectMatches.first;
    final scopeMatches = (scopes.valueOrNull ?? const [])
        .where((item) => item.id == draft.scopeId)
        .toList(growable: false);
    final scope = scopeMatches.isEmpty ? null : scopeMatches.first;
    final ready =
        draft.canSubmitLocally &&
        project?.state == YorksV1ProjectLifecycle.active.wireValue;
    return _R35RequestSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_tree_outlined,
                size: 19,
                color: AppColors.blue,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  YorksV1MaterialRequestStrings.requestStatus.primary,
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _ReviewStatusChip(ready: ready),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const _IndustrialWorkflowStrip(stage: 1, condensed: true),
          const SizedBox(height: AppSpacing.lg),
          _IndustrialNotice(
            icon: Icons.info_outline_rounded,
            text: YorksV1MaterialRequestStrings.requestApprovalPrompt.primary,
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.lg),
          Text(
            YorksV1MaterialRequestStrings.review.primary,
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _IndustrialFactRow(
            label: YorksV1MaterialRequestStrings.requestNumber.primary,
            value: _previewRequestNumber(project),
          ),
          _IndustrialFactRow(
            label: YorksV1MaterialRequestStrings.project.primary,
            value: project == null
                ? YorksV1MaterialRequestStrings.project.primary
                : '${project.reference} · ${project.name}',
          ),
          _IndustrialFactRow(
            label: YorksV1MaterialRequestStrings.scopeLabel.primary,
            value: scope?.name ?? YorksV1MaterialRequestStrings.scope.primary,
          ),
          _IndustrialFactRow(
            label: YorksV1MaterialRequestStrings.delivery.primary,
            value: yorksV1MaterialRequestTimingCopy(draft.timing).primary,
          ),
          _IndustrialFactRow(
            label: YorksV1MaterialRequestStrings.requestedBy.primary,
            value: requesterName.trim().isEmpty
                ? YorksV1MaterialRequestStrings.notProvided.primary
                : requesterName,
            last: true,
          ),
        ],
      ),
    );
  }
}

class _R35RequestSurface extends StatelessWidget {
  const _R35RequestSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.xl),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      boxShadow: const [
        BoxShadow(
          color: AppColors.shadow,
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );
}

class _ReviewStatusChip extends StatelessWidget {
  const _ReviewStatusChip({required this.ready});

  final bool ready;

  @override
  Widget build(BuildContext context) {
    final background = ready
        ? AppColors.successContainer
        : AppColors.warningContainer;
    final foreground = ready
        ? AppColors.onSuccessContainer
        : AppColors.onWarningContainer;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        (ready
                ? YorksV1MaterialRequestStrings.ready
                : YorksV1MaterialRequestStrings.addItems)
            .primary,
        style: AppTypography.labelMedium.copyWith(
          color: foreground,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DraftDiscussionLoading extends StatelessWidget {
  const _DraftDiscussionLoading();

  @override
  Widget build(BuildContext context) => _R35RequestSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          YorksV1MaterialRequestStrings.discussion.primary,
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const LinearProgressIndicator(),
      ],
    ),
  );
}

class _DraftDiscussionPrompt extends StatelessWidget {
  const _DraftDiscussionPrompt({required this.canSave, required this.onSave});

  final bool canSave;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) => _R35RequestSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.forum_outlined, size: 19, color: AppColors.blue),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                YorksV1MaterialRequestStrings.discussion.primary,
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Icon(
          Icons.chat_bubble_outline_rounded,
          size: 34,
          color: AppColors.muted.withValues(alpha: .7),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          YorksV1MaterialRequestStrings.saveDraftToDiscuss.primary,
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        ),
        if (canSave && onSave != null) ...[
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: Text(YorksV1MaterialRequestStrings.saveDraft.primary),
          ),
        ],
      ],
    ),
  );
}

class _R35RequestAction extends StatelessWidget {
  const _R35RequestAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.leading,
    this.primary = false,
    this.loading = false,
    this.tooltip,
  });

  final String label;
  final IconData? icon;
  final Widget? leading;
  final VoidCallback? onPressed;
  final bool primary;
  final bool loading;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final child = SizedBox(
      height: AppSpacing.minTapTarget,
      child: primary
          ? FilledButton.icon(
              onPressed: loading ? null : onPressed,
              icon: loading
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : leading ??
                        Icon(icon ?? Icons.arrow_forward_rounded, size: 19),
              label: Text(label),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.blue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd + 2),
                ),
              ),
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              icon:
                  leading ??
                  (icon == null
                      ? const SizedBox.shrink()
                      : Icon(icon, size: 18)),
              label: Text(label),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.inkSecondary,
                side: const BorderSide(color: AppColors.line),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd + 2),
                ),
              ),
            ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

/// Keeps source/import actions in the primary visual lane while preserving the
/// spreadsheet row tools required for fast desktop entry. The two concerns no
/// longer compete in one unstructured wrap at medium desktop widths.
class _R35MaterialActionBar extends StatelessWidget {
  const _R35MaterialActionBar({
    required this.canEdit,
    required this.canUseBoq,
    required this.excelEnabled,
    required this.onAddCustom,
    required this.onAddBoq,
    required this.onImport,
    required this.onExport,
  });

  final bool canEdit;
  final bool canUseBoq;
  final bool excelEnabled;
  final VoidCallback onAddCustom;
  final VoidCallback onAddBoq;
  final VoidCallback onImport;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    children: [
      _R35RequestAction(
        label: YorksV1MaterialRequestStrings.addCustomItem.primary,
        icon: Icons.add_rounded,
        primary: true,
        tooltip: YorksV1MaterialRequestStrings.customItemShortcut.primary,
        onPressed: canEdit ? onAddCustom : null,
      ),
      _R35RequestAction(
        label: YorksV1MaterialRequestStrings.addFromBoq.primary,
        icon: Icons.folder_outlined,
        onPressed: canUseBoq ? onAddBoq : null,
      ),
      if (excelEnabled)
        _R35RequestAction(
          label: YorksV1MaterialRequestStrings.importExcel.primary,
          leading: YorksFileTypeIcon(
            fileName: 'import.xlsx',
            size: 24,
            badgeIcon: YorksDataTransferIcons.importData,
            enabled: canEdit,
          ),
          onPressed: canEdit ? onImport : null,
        ),
      if (excelEnabled)
        _R35RequestAction(
          label: YorksV1MaterialRequestStrings.exportExcel.primary,
          leading: YorksFileTypeIcon(
            fileName: 'export.xlsx',
            size: 24,
            badgeIcon: YorksDataTransferIcons.exportData,
            enabled: canEdit,
          ),
          onPressed: canEdit ? onExport : null,
        ),
    ],
  );
}

class _RequestFormFields extends StatelessWidget {
  const _RequestFormFields({
    required this.draft,
    required this.projects,
    required this.scopes,
    required this.controller,
    required this.allowedTimings,
  });

  final YorksV1MaterialRequestDraft draft;
  final AsyncValue<List<YorksV1MaterialRequestProjectOption>> projects;
  final AsyncValue<List<YorksV1MaterialRequestScopeOption>> scopes;
  final YorksV1MaterialRequestDraftController controller;
  final List<YorksV1MaterialRequestTiming> allowedTimings;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final title = _RequestFieldBlock(
        label: YorksV1MaterialRequestStrings.requestTitle.primary,
        child: TextFormField(
          key: const ValueKey('mr-title'),
          initialValue: draft.title ?? '',
          onChanged: controller.setTitle,
          decoration: InputDecoration(
            hintText: YorksV1MaterialRequestStrings.requestTitle.primary,
          ),
        ),
      );
      final project = _RequestFieldBlock(
        label: YorksV1MaterialRequestStrings.project.primary,
        child: _ProjectDropdown(
          fieldKey: const ValueKey('mr-project'),
          value: draft.projectId,
          projects: projects,
          enabled: !controller.isEditingBeforeApproval,
          onChanged: (projectId) async {
            final preservesExistingLines =
                controller.currentDraft.lines.isNotEmpty &&
                projectId != controller.currentDraft.projectId;
            await controller.setProject(
              projectId,
              preserveExistingLines: preservesExistingLines,
            );
            if (preservesExistingLines && context.mounted) {
              _snack(
                context,
                YorksV1MaterialRequestStrings
                    .changeProjectPreservesLines
                    .primary,
              );
            }
          },
        ),
      );
      final scope = _RequestFieldBlock(
        label: YorksV1MaterialRequestStrings.buildingOther.primary,
        child: _ScopeDropdown(
          value: draft.scopeId,
          scopes: scopes,
          onChanged: (scopeId) async {
            final boqLineCount = controller.currentDraft.lines
                .where(
                  (line) => line.source == YorksV1MaterialRequestLineSource.boq,
                )
                .length;
            final requiresConfirmation =
                scopeId != controller.currentDraft.scopeId && boqLineCount > 0;
            if (requiresConfirmation) {
              final confirmed = await showDialog<bool>(
                context: context,
                animationStyle: AnimationStyle.noAnimation,
                builder: (dialogContext) => AlertDialog(
                  title: Text(
                    YorksV1MaterialRequestStrings.changeScope.primary,
                  ),
                  content: Text(
                    YorksV1MaterialRequestStrings
                        .changeScopeDiscardBoqRows
                        .primary
                        .replaceFirst('{count}', boqLineCount.toString()),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text(YorksV1MaterialRequestStrings.cancel.primary),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text(
                        YorksV1MaterialRequestStrings.changeScope.primary,
                      ),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
            }
            await controller.setScope(
              scopeId,
              discardIncompatibleBoqRows: requiresConfirmation,
            );
          },
        ),
      );
      final timing = _RequestFieldBlock(
        label: YorksV1MaterialRequestStrings.requestTiming.primary,
        child: _TimingPicker(
          draft: draft,
          controller: controller,
          allowedTimings: allowedTimings,
        ),
      );
      final scheduledDate = _RequestFieldBlock(
        label: YorksV1MaterialRequestStrings.scheduledDate.primary,
        child: _ScheduledDateField(draft: draft, controller: controller),
      );
      final contentWidth = math.min(constraints.maxWidth, 1320.0);
      final wide = contentWidth >= 820;
      return Align(
        alignment: AlignmentDirectional.topStart,
        child: SizedBox(
          width: contentWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: AppSpacing.xl),
              if (wide) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: project),
                    const SizedBox(width: AppSpacing.xl),
                    Expanded(flex: 5, child: scope),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: timing),
                    const SizedBox(width: AppSpacing.xl),
                    Expanded(
                      flex: 5,
                      child:
                          draft.timing == YorksV1MaterialRequestTiming.scheduled
                          ? scheduledDate
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ] else ...[
                project,
                const SizedBox(height: AppSpacing.xl),
                scope,
                const SizedBox(height: AppSpacing.xl),
                timing,
                if (draft.timing == YorksV1MaterialRequestTiming.scheduled) ...[
                  const SizedBox(height: AppSpacing.xl),
                  scheduledDate,
                ],
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _RequestFieldBlock extends StatelessWidget {
  const _RequestFieldBlock({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: AppTypography.labelMedium.copyWith(
          color: AppColors.inkSecondary,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: child,
      ),
    ],
  );
}

class _ProjectDropdown extends StatelessWidget {
  const _ProjectDropdown({
    this.fieldKey,
    required this.value,
    required this.projects,
    required this.onChanged,
    this.enabled = true,
  });

  final Key? fieldKey;
  final String? value;
  final AsyncValue<List<YorksV1MaterialRequestProjectOption>> projects;
  final Future<void> Function(String?) onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => projects.when(
    loading: () => KeyedSubtree(
      key: fieldKey,
      child: const SizedBox(
        height: 56,
        child: Align(
          alignment: Alignment.center,
          child: LinearProgressIndicator(minHeight: 2),
        ),
      ),
    ),
    error: (_, _) => KeyedSubtree(
      key: fieldKey,
      child: InputDecorator(
        decoration: const InputDecoration(),
        child: Text(
          YorksV1ProjectStrings.portfolioUnavailable.primary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodyMedium.copyWith(color: AppColors.error),
        ),
      ),
    ),
    data: (items) => _SearchableProjectPicker(
      fieldKey: fieldKey,
      value: value,
      items: items,
      enabled: enabled,
      onChanged: onChanged,
    ),
  );
}

class _SearchableProjectPicker extends StatefulWidget {
  const _SearchableProjectPicker({
    required this.value,
    required this.items,
    required this.enabled,
    required this.onChanged,
    this.fieldKey,
    this.labelText,
  });

  final Key? fieldKey;
  final String? value;
  final List<YorksV1MaterialRequestProjectOption> items;
  final bool enabled;
  final Future<void> Function(String?) onChanged;
  final String? labelText;

  @override
  State<_SearchableProjectPicker> createState() =>
      _SearchableProjectPickerState();
}

class _SearchableProjectPickerState extends State<_SearchableProjectPicker> {
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _anchorKey = GlobalKey();
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _textController = TextEditingController();
  final Object _tapRegionGroupId = Object();
  OverlayEntry? _overlayEntry;
  List<YorksV1MaterialRequestProjectOption> _visibleItems = const [];
  int _highlightedIndex = 0;
  bool _editing = false;
  bool _committing = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
    _syncCommittedLabel();
  }

  @override
  void didUpdateWidget(covariant _SearchableProjectPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled) _cancelSearch();
    if (!_editing && !_committing) _syncCommittedLabel();
  }

  YorksV1MaterialRequestProjectOption? get _selectedProject =>
      widget.items.where((item) => item.id == widget.value).firstOrNull;

  String _projectLabel(YorksV1MaterialRequestProjectOption item) =>
      '${item.reference} · ${item.name}';

  void _syncCommittedLabel() {
    final label = _selectedProject == null
        ? ''
        : _projectLabel(_selectedProject!);
    if (_textController.text == label) return;
    _textController.value = TextEditingValue(
      text: label,
      selection: TextSelection.collapsed(offset: label.length),
    );
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus && !_committing) _cancelSearch();
  }

  void _beginSearch() {
    if (!widget.enabled || _committing) return;
    if (!_editing) {
      setState(() {
        _editing = true;
        _textController.clear();
        _visibleItems = _rankedProjects(widget.items, '');
        _highlightedIndex = 0;
      });
    }
    _focusNode.requestFocus();
    _showOptions();
  }

  void _filter(String query) {
    _visibleItems = _rankedProjects(widget.items, query);
    _highlightedIndex = 0;
    if (_focusNode.hasFocus) _showOptions();
  }

  Future<void> _select(YorksV1MaterialRequestProjectOption item) async {
    if (_committing) return;
    setState(() {
      _committing = true;
      _textController.value = TextEditingValue(
        text: _projectLabel(item),
        selection: TextSelection.collapsed(offset: _projectLabel(item).length),
      );
    });
    _hideOptions();
    await widget.onChanged(item.id);
    if (!mounted) return;
    setState(() {
      _committing = false;
      _editing = false;
      _syncCommittedLabel();
    });
    _focusNode.unfocus();
  }

  void _cancelSearch() {
    if (!_editing && _overlayEntry == null) return;
    _hideOptions();
    if (!mounted) return;
    setState(() {
      _editing = false;
      _visibleItems = const [];
      _syncCommittedLabel();
    });
  }

  void _showOptions() {
    final anchorContext = _anchorKey.currentContext;
    final overlayState = Overlay.maybeOf(context, rootOverlay: true);
    if (anchorContext == null || overlayState == null) return;
    final geometry = _MaterialSuggestionOverlayGeometry.resolve(
      fieldContext: anchorContext,
      overlayContext: overlayState.context,
      preferredWidth: 680,
      preferredHeight: 420,
    );
    _overlayEntry ??= OverlayEntry(
      builder: (_) => Positioned.fill(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              targetAnchor: geometry.opensBelow
                  ? Alignment.bottomLeft
                  : Alignment.topLeft,
              followerAnchor: geometry.opensBelow
                  ? Alignment.topLeft
                  : Alignment.bottomLeft,
              offset: geometry.offset,
              child: SizedBox(
                width: geometry.width,
                child: TextFieldTapRegion(
                  groupId: _tapRegionGroupId,
                  child: _ProjectSuggestionPanel(
                    values: _visibleItems,
                    selectedId: widget.value,
                    maxHeight: geometry.height,
                    highlightedId: _visibleItems.isEmpty
                        ? null
                        : _visibleItems[_highlightedIndex].id,
                    onSelected: _select,
                    onHovered: (item) {
                      final index = _visibleItems.indexOf(item);
                      if (index < 0 || index == _highlightedIndex) return;
                      _highlightedIndex = index;
                      _overlayEntry?.markNeedsBuild();
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (_overlayEntry!.mounted) {
      _overlayEntry!.markNeedsBuild();
    } else {
      overlayState.insert(_overlayEntry!);
    }
  }

  void _hideOptions() {
    _overlayEntry?.remove();
    _overlayEntry?.dispose();
    _overlayEntry = null;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !_editing || _overlayEntry == null) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _focusNode.unfocus();
      return KeyEventResult.handled;
    }
    if (_visibleItems.isEmpty) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _highlightedIndex = (_highlightedIndex + 1) % _visibleItems.length;
      _overlayEntry?.markNeedsBuild();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _highlightedIndex =
          (_highlightedIndex - 1 + _visibleItems.length) % _visibleItems.length;
      _overlayEntry?.markNeedsBuild();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _hideOptions();
    _focusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: _handleKeyEvent,
    child: CompositedTransformTarget(
      key: _anchorKey,
      link: _layerLink,
      child: TextFormField(
        key: widget.fieldKey,
        groupId: _tapRegionGroupId,
        controller: _textController,
        focusNode: _focusNode,
        enabled: widget.enabled,
        readOnly: !_editing,
        showCursor: _editing,
        enableInteractiveSelection: _editing,
        textInputAction: TextInputAction.search,
        onTap: _beginSearch,
        onChanged: _filter,
        onFieldSubmitted: (_) {
          if (_visibleItems.isNotEmpty) {
            unawaited(_select(_visibleItems[_highlightedIndex]));
          }
        },
        onTapOutside: (_) => _focusNode.unfocus(),
        decoration: InputDecoration(
          labelText: widget.labelText,
          hintText: YorksV1MaterialRequestStrings.searchProjects.primary,
          prefixIcon: _editing
              ? const Icon(Icons.search_rounded)
              : const Icon(Icons.business_outlined),
          suffixIcon: _committing
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Icon(
                  _editing
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                ),
        ),
      ),
    ),
  );
}

List<YorksV1MaterialRequestProjectOption> _rankedProjects(
  List<YorksV1MaterialRequestProjectOption> projects,
  String rawQuery,
) {
  final query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) return List.of(projects, growable: false);
  final compactQuery = query.replaceAll(
    RegExp(r'[^\p{L}\p{N}]+', unicode: true),
    '',
  );
  final tokens = query
      .replaceAll(RegExp(r'[-_/.,·]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toList(growable: false);
  final ranked = <(YorksV1MaterialRequestProjectOption, int)>[];
  for (final project in projects) {
    final reference = project.reference.toLowerCase();
    final name = project.name.toLowerCase();
    final haystack = '$reference $name'.replaceAll(RegExp(r'[-_/.,·]+'), ' ');
    final compactHaystack = '$reference$name'.replaceAll(
      RegExp(r'[^\p{L}\p{N}]+', unicode: true),
      '',
    );
    if (!tokens.every(haystack.contains) &&
        !compactHaystack.contains(compactQuery)) {
      continue;
    }
    final score = reference == query
        ? 0
        : reference.startsWith(query)
        ? 1
        : name.startsWith(query)
        ? 2
        : tokens.every(
            (token) => reference.startsWith(token) || name.startsWith(token),
          )
        ? 3
        : 4;
    ranked.add((project, score));
  }
  ranked.sort((left, right) {
    final byScore = left.$2.compareTo(right.$2);
    if (byScore != 0) return byScore;
    return left.$1.reference.compareTo(right.$1.reference);
  });
  return [for (final entry in ranked) entry.$1];
}

class _ProjectSuggestionPanel extends StatelessWidget {
  const _ProjectSuggestionPanel({
    required this.values,
    required this.selectedId,
    required this.highlightedId,
    required this.maxHeight,
    required this.onSelected,
    required this.onHovered,
  });

  final List<YorksV1MaterialRequestProjectOption> values;
  final String? selectedId;
  final String? highlightedId;
  final double maxHeight;
  final Future<void> Function(YorksV1MaterialRequestProjectOption) onSelected;
  final ValueChanged<YorksV1MaterialRequestProjectOption> onHovered;

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('mr-project-suggestion-panel'),
    color: AppColors.surfaceContainerLowest,
    elevation: 14,
    shadowColor: AppColors.shadow,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.business_outlined,
                  size: 18,
                  color: AppColors.blue,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    YorksV1MaterialRequestStrings.projects.primary,
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.inkSecondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${values.length}',
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (values.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text(
                YorksV1ProjectStrings.noMatchingProjects.primary,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.muted,
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: values.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final project = values[index];
                  final selected = project.id == selectedId;
                  final highlighted = project.id == highlightedId;
                  final label = '${project.reference} · ${project.name}';
                  return Semantics(
                    button: true,
                    selected: selected,
                    label: label,
                    child: MouseRegion(
                      onEnter: (_) => onHovered(project),
                      child: InkWell(
                        onTap: () => unawaited(onSelected(project)),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 60),
                          child: ColoredBox(
                            color: highlighted
                                ? AppColors.blueContainer.withValues(alpha: .55)
                                : Colors.transparent,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.sm,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: AppColors.blueContainer,
                                      borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusSm,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.apartment_rounded,
                                      size: 20,
                                      color: AppColors.blue,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          project.reference,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTypography.titleSmall
                                              .copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          project.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTypography.bodySmall
                                              .copyWith(color: AppColors.muted),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (selected)
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: AppColors.success,
                                    )
                                  else
                                    const Icon(
                                      Icons.chevron_right_rounded,
                                      color: AppColors.muted,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    ),
  );
}

class _ScopeDropdown extends StatelessWidget {
  const _ScopeDropdown({
    required this.value,
    required this.scopes,
    required this.onChanged,
  });

  final String? value;
  final AsyncValue<List<YorksV1MaterialRequestScopeOption>> scopes;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => scopes.when(
    loading: () => const LinearProgressIndicator(),
    error: (_, _) => Text(YorksV1MaterialRequestStrings.saveFailed.primary),
    data: (items) => DropdownButtonFormField<String>(
      initialValue: items.any((item) => item.id == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        hintText: YorksV1MaterialRequestStrings.buildingOther.primary,
      ),
      items: [
        for (final item in items)
          DropdownMenuItem(value: item.id, child: Text(item.name)),
      ],
      onChanged: onChanged,
    ),
  );
}

class _TimingPicker extends StatelessWidget {
  const _TimingPicker({
    required this.draft,
    required this.controller,
    required this.allowedTimings,
  });

  final YorksV1MaterialRequestDraft draft;
  final YorksV1MaterialRequestDraftController controller;
  final List<YorksV1MaterialRequestTiming> allowedTimings;

  @override
  Widget build(BuildContext context) =>
      DropdownButtonFormField<YorksV1MaterialRequestTiming>(
        key: const ValueKey('mr-timing-picker'),
        initialValue: draft.timing,
        decoration: InputDecoration(
          hintText: YorksV1MaterialRequestStrings.requestTiming.primary,
        ),
        items: [
          for (final timing in allowedTimings)
            DropdownMenuItem(
              key: ValueKey('mr-timing-${timing.wireValue}'),
              value: timing,
              child: Text(yorksV1MaterialRequestTimingCopy(timing).primary),
            ),
        ],
        onChanged: (value) {
          if (value != null) controller.setTiming(value);
        },
      );
}

class _ScheduledDateField extends StatelessWidget {
  const _ScheduledDateField({required this.draft, required this.controller});

  final YorksV1MaterialRequestDraft draft;
  final YorksV1MaterialRequestDraftController controller;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    icon: const Icon(Icons.calendar_today_outlined),
    label: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        draft.scheduledDate == null
            ? YorksV1MaterialRequestStrings.chooseScheduledDate.primary
            : MaterialLocalizations.of(
                context,
              ).formatMediumDate(draft.scheduledDate!),
      ),
    ),
    onPressed: () async {
      final now = DateTime.now();
      final selected = await showDatePicker(
        context: context,
        firstDate: DateTime(now.year - 1),
        lastDate: DateTime(now.year + 10),
        initialDate: draft.scheduledDate ?? now,
      );
      if (selected != null) await controller.setScheduledDate(selected);
    },
  );
}

TranslatableString _materialSuggestionSourceCopy(
  YorksV1MaterialRequestSuggestionSource source,
) => switch (source) {
  YorksV1MaterialRequestSuggestionSource.selectedScopeBoq =>
    YorksV1MaterialRequestStrings.selectedScopeBoq,
  YorksV1MaterialRequestSuggestionSource.projectBoq =>
    YorksV1MaterialRequestStrings.projectBoq,
  YorksV1MaterialRequestSuggestionSource.inventory =>
    YorksV1MaterialRequestStrings.inventoryCatalogue,
};

IconData _materialSuggestionIcon(
  YorksV1MaterialRequestSuggestionSource source,
) => switch (source) {
  YorksV1MaterialRequestSuggestionSource.selectedScopeBoq =>
    Icons.folder_special_outlined,
  YorksV1MaterialRequestSuggestionSource.projectBoq => Icons.folder_outlined,
  YorksV1MaterialRequestSuggestionSource.inventory =>
    Icons.inventory_2_outlined,
};

Color _materialSuggestionColor(YorksV1MaterialRequestSuggestionSource source) =>
    switch (source) {
      YorksV1MaterialRequestSuggestionSource.selectedScopeBoq =>
        AppColors.success,
      YorksV1MaterialRequestSuggestionSource.projectBoq => AppColors.warning,
      YorksV1MaterialRequestSuggestionSource.inventory => AppColors.blue,
    };

List<String> _materialSuggestionMetadataLines(
  YorksV1MaterialRequestInventorySuggestion item,
) => [
  <String>[
    if (item.size?.trim().isNotEmpty == true)
      '${YorksV1MaterialRequestStrings.size.primary}: ${item.size}',
    if (item.model?.trim().isNotEmpty == true)
      '${YorksV1MaterialRequestStrings.planningModelTag.primary}: ${item.model}',
    if (item.itemCode?.trim().isNotEmpty == true) item.itemCode!,
  ].join(' · '),
  <String>[
    '${YorksV1MaterialRequestStrings.unit.primary}: ${item.unit}',
    if (item.brandOrigin?.trim().isNotEmpty == true)
      '${YorksV1MaterialRequestStrings.brandOrigin.primary}: ${item.brandOrigin}',
    if (item.sourceScopeName?.trim().isNotEmpty == true) item.sourceScopeName!,
  ].join(' · '),
].where((line) => line.isNotEmpty).toList(growable: false);

class _MaterialSuggestionPanel extends StatelessWidget {
  const _MaterialSuggestionPanel({
    required this.values,
    required this.onSelected,
    required this.maxWidth,
    required this.maxHeight,
    this.customQuery,
    this.onKeepCustom,
    this.highlightedId,
    this.onHovered,
  });

  final List<YorksV1MaterialRequestInventorySuggestion> values;
  final ValueChanged<YorksV1MaterialRequestInventorySuggestion> onSelected;
  final double maxWidth;
  final double maxHeight;
  final String? customQuery;
  final VoidCallback? onKeepCustom;
  final String? highlightedId;
  final ValueChanged<YorksV1MaterialRequestInventorySuggestion>? onHovered;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final source in YorksV1MaterialRequestSuggestionSource.values) {
      final group = values
          .where((item) => item.source == source)
          .toList(growable: false);
      if (group.isEmpty) continue;
      children.add(
        Container(
          key: ValueKey('mr-suggestion-group-${source.wireValue}'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          color: AppColors.surfaceContainerLow,
          child: Row(
            children: [
              Icon(
                _materialSuggestionIcon(source),
                size: 16,
                color: _materialSuggestionColor(source),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _materialSuggestionSourceCopy(source).primary.toUpperCase(),
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.inkSecondary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              Text(
                '${group.length}',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
      for (final item in group) {
        final metadata = _materialSuggestionMetadataLines(item);
        final badge = source == YorksV1MaterialRequestSuggestionSource.inventory
            ? YorksV1MaterialRequestStrings.catalogueMatch.primary
            : YorksV1MaterialRequestStrings.inBoq.primary;
        children.add(
          InkWell(
            key: ValueKey('mr-suggestion-${item.id}'),
            canRequestFocus: false,
            onTap: () => onSelected(item),
            onHover: (hovering) {
              if (hovering) onHovered?.call(item);
            },
            child: Container(
              constraints: const BoxConstraints(
                minHeight: AppSpacing.minTapTarget,
              ),
              padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
              decoration: BoxDecoration(
                color: highlightedId == item.id
                    ? AppColors.blue.withValues(alpha: 0.06)
                    : null,
                border: const Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _materialSuggestionColor(
                        source,
                      ).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Icon(
                      _materialSuggestionIcon(source),
                      size: 20,
                      color: _materialSuggestionColor(source),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelLarge.copyWith(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        for (final line in metadata)
                          Text(
                            line,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _materialSuggestionColor(
                        source,
                      ).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusFull,
                      ),
                    ),
                    child: Text(
                      badge,
                      style: AppTypography.labelSmall.copyWith(
                        color: _materialSuggestionColor(source),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 19,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }
    final query = customQuery?.trim() ?? '';
    if (query.isNotEmpty && onKeepCustom != null) {
      children.add(
        InkWell(
          key: const ValueKey('mr-keep-custom-suggestion'),
          canRequestFocus: false,
          onTap: onKeepCustom,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                const Icon(Icons.add_rounded, size: 19, color: AppColors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${YorksV1MaterialRequestStrings.keepCustomItem.primary}: “$query”',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.blue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Material(
      key: const ValueKey('mr-suggestion-panel'),
      elevation: 8,
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: ListView(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          children: children,
        ),
      ),
    );
  }
}

class _MaterialSuggestionOverlayGeometry {
  const _MaterialSuggestionOverlayGeometry({
    required this.width,
    required this.height,
    required this.offset,
    required this.opensBelow,
  });

  final double width;
  final double height;
  final Offset offset;
  final bool opensBelow;

  static _MaterialSuggestionOverlayGeometry resolve({
    required BuildContext fieldContext,
    required BuildContext overlayContext,
    required double preferredWidth,
    required double preferredHeight,
  }) {
    final fieldBox = fieldContext.findRenderObject()! as RenderBox;
    final overlayBox = overlayContext.findRenderObject()! as RenderBox;
    final viewport = overlayBox.size;
    final origin = fieldBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    const margin = 16.0;
    const gap = 6.0;
    final width = math
        .min(preferredWidth, math.max(280, viewport.width - (margin * 2)))
        .toDouble();
    final below = viewport.height - origin.dy - fieldBox.size.height - margin;
    final above = origin.dy - margin;
    final opensBelow =
        below >= math.min(220, preferredHeight) || below >= above;
    final availableHeight = opensBelow ? below : above;
    final height = math
        .min(preferredHeight, math.max(140, availableHeight))
        .toDouble();
    final desiredX = origin.dx;
    final clampedX = desiredX
        .clamp(margin, viewport.width - margin - width)
        .toDouble();
    return _MaterialSuggestionOverlayGeometry(
      width: width,
      height: height,
      offset: Offset(clampedX - origin.dx, opensBelow ? gap : -gap),
      opensBelow: opensBelow,
    );
  }
}

YorksV1MaterialRequestLine _applyMaterialSuggestion(
  YorksV1MaterialRequestLine line,
  YorksV1MaterialRequestInventorySuggestion suggestion,
) => line.copyWith(
  source: suggestion.retainsBoqProvenance
      ? YorksV1MaterialRequestLineSource.boq
      : YorksV1MaterialRequestLineSource.custom,
  sourceBoqGroupId: suggestion.retainsBoqProvenance
      ? suggestion.sourceBoqGroupId
      : null,
  sourceBoqRowId: suggestion.retainsBoqProvenance
      ? suggestion.sourceBoqRowId
      : null,
  description: suggestion.description,
  brandOrigin: suggestion.brandOrigin,
  size: suggestion.size,
  model: suggestion.model,
  equipmentTag: suggestion.equipmentTag,
  planningModelTag: null,
  unit: suggestion.unit,
  quantityIsSuggested: false,
);

class _AnchoredMaterialDescriptionAutocomplete extends ConsumerStatefulWidget {
  const _AnchoredMaterialDescriptionAutocomplete({
    required this.textController,
    required this.focusNode,
    required this.enabled,
    required this.projectId,
    required this.scopeId,
    required this.onSelected,
    this.onChanged,
    this.onCommitted,
    this.errorText,
    this.fieldKey,
    this.labelText,
    this.hintText,
    this.isDense = false,
    this.contentPadding,
    this.preferredWidth = 560,
    this.preferredHeight = 410,
    this.showSuffixIcon = true,
    this.desktopCell = false,
  });

  final TextEditingController textController;
  final FocusNode focusNode;
  final bool enabled;
  final String? projectId;
  final String? scopeId;
  final ValueChanged<YorksV1MaterialRequestInventorySuggestion> onSelected;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onCommitted;
  final String? errorText;
  final Key? fieldKey;
  final String? labelText;
  final String? hintText;
  final bool isDense;
  final EdgeInsetsGeometry? contentPadding;
  final double preferredWidth;
  final double preferredHeight;
  final bool showSuffixIcon;
  final bool desktopCell;

  @override
  ConsumerState<_AnchoredMaterialDescriptionAutocomplete> createState() =>
      _AnchoredMaterialDescriptionAutocompleteState();
}

class _AnchoredMaterialDescriptionAutocompleteState
    extends ConsumerState<_AnchoredMaterialDescriptionAutocomplete> {
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _anchorKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  List<YorksV1MaterialRequestInventorySuggestion> _values = const [];
  int _highlightedIndex = 0;
  int _searchEpoch = 0;
  final Object _tapRegionGroupId = Object();

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(
    covariant _AnchoredMaterialDescriptionAutocomplete oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChanged);
      widget.focusNode.addListener(_handleFocusChanged);
    }
    if (!widget.enabled && oldWidget.enabled) _hideOptions();
  }

  void _handleFocusChanged() {
    if (!widget.focusNode.hasFocus) {
      widget.onCommitted?.call();
      _hideOptions();
    }
  }

  Future<void> _search(String rawQuery) async {
    final epoch = ++_searchEpoch;
    final query = rawQuery.trim();
    final projectId = widget.projectId?.trim();
    final scopeId = widget.scopeId?.trim();
    if (!widget.enabled ||
        projectId == null ||
        projectId.isEmpty ||
        scopeId == null ||
        scopeId.isEmpty ||
        query.length < 2) {
      _values = const [];
      _hideOptions();
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted || epoch != _searchEpoch) return;
    try {
      final results = await ref.read(
        yorksV1MaterialRequestInventorySearchProvider(
          YorksV1MaterialRequestInventorySearchKey(
            projectId: projectId,
            scopeId: scopeId,
            query: query,
          ),
        ).future,
      );
      if (!mounted || epoch != _searchEpoch) return;
      _values = results;
      _highlightedIndex = 0;
      if (_values.isEmpty || !widget.focusNode.hasFocus) {
        _hideOptions();
      } else {
        _showOptions();
      }
    } catch (_) {
      if (!mounted || epoch != _searchEpoch) return;
      _values = const [];
      _hideOptions();
    }
  }

  void _showOptions() {
    final anchorContext = _anchorKey.currentContext;
    final overlayState = Overlay.maybeOf(context, rootOverlay: true);
    if (anchorContext == null || overlayState == null) return;
    final geometry = _MaterialSuggestionOverlayGeometry.resolve(
      fieldContext: anchorContext,
      overlayContext: overlayState.context,
      preferredWidth: widget.preferredWidth,
      preferredHeight: widget.preferredHeight,
    );
    _overlayEntry ??= OverlayEntry(
      builder: (_) {
        return Positioned.fill(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CompositedTransformFollower(
                link: _layerLink,
                showWhenUnlinked: false,
                targetAnchor: geometry.opensBelow
                    ? Alignment.bottomLeft
                    : Alignment.topLeft,
                followerAnchor: geometry.opensBelow
                    ? Alignment.topLeft
                    : Alignment.bottomLeft,
                offset: geometry.offset,
                child: SizedBox(
                  width: geometry.width,
                  child: TextFieldTapRegion(
                    groupId: _tapRegionGroupId,
                    child: _MaterialSuggestionPanel(
                      values: _values,
                      onSelected: _select,
                      maxWidth: geometry.width,
                      maxHeight: geometry.height,
                      customQuery: widget.textController.text,
                      onKeepCustom: _keepCustom,
                      highlightedId: _values.isEmpty
                          ? null
                          : _values[_highlightedIndex].id,
                      onHovered: (item) {
                        final index = _values.indexOf(item);
                        if (index < 0 || index == _highlightedIndex) return;
                        _highlightedIndex = index;
                        _overlayEntry?.markNeedsBuild();
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (_overlayEntry!.mounted) {
      _overlayEntry!.markNeedsBuild();
    } else {
      overlayState.insert(_overlayEntry!);
    }
  }

  void _select(YorksV1MaterialRequestInventorySuggestion suggestion) {
    widget.textController.value = TextEditingValue(
      text: suggestion.description,
      selection: TextSelection.collapsed(offset: suggestion.description.length),
    );
    widget.onSelected(suggestion);
    _hideOptions();
  }

  void _keepCustom() {
    widget.onChanged?.call(widget.textController.text);
    widget.onCommitted?.call();
    _hideOptions();
    widget.focusNode.unfocus();
  }

  void _hideOptions() {
    _overlayEntry?.remove();
    _overlayEntry?.dispose();
    _overlayEntry = null;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _overlayEntry == null) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _hideOptions();
      return KeyEventResult.handled;
    }
    if (_values.isEmpty) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _highlightedIndex = (_highlightedIndex + 1) % _values.length;
      _overlayEntry?.markNeedsBuild();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _highlightedIndex =
          (_highlightedIndex - 1 + _values.length) % _values.length;
      _overlayEntry?.markNeedsBuild();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChanged);
    _hideOptions();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: const ValueKey('mr-material-description-autocomplete'),
    child: Focus(
      canRequestFocus: false,
      onKeyEvent: _handleKeyEvent,
      child: CompositedTransformTarget(
        key: _anchorKey,
        link: _layerLink,
        child: TextFormField(
          key: widget.fieldKey,
          groupId: _tapRegionGroupId,
          controller: widget.textController,
          focusNode: widget.focusNode,
          enabled: widget.enabled,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (value) {
            widget.onChanged?.call(value);
            unawaited(_search(value));
          },
          onFieldSubmitted: (_) {
            if (_values.isNotEmpty && _overlayEntry != null) {
              _select(_values[_highlightedIndex]);
            } else {
              widget.onCommitted?.call();
            }
          },
          onTapOutside: (_) => widget.focusNode.unfocus(),
          decoration: InputDecoration(
            isDense: widget.isDense,
            labelText: widget.labelText,
            hintText: widget.hintText,
            suffixIcon:
                widget.showSuffixIcon &&
                    widget.enabled &&
                    widget.projectId != null &&
                    widget.scopeId != null
                ? Icon(Icons.search_rounded, size: 19, color: AppColors.muted)
                : null,
            contentPadding: widget.contentPadding,
            errorText: widget.errorText,
            border: widget.desktopCell ? InputBorder.none : null,
            enabledBorder: widget.desktopCell ? InputBorder.none : null,
            focusedBorder: widget.desktopCell
                ? const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: AppColors.blue, width: 2),
                  )
                : null,
          ),
        ),
      ),
    ),
  );
}

class _MobileInventoryDescriptionField extends StatefulWidget {
  const _MobileInventoryDescriptionField({
    required this.controller,
    required this.projectId,
    required this.scopeId,
    required this.enabled,
    required this.onSelected,
    this.onEdited,
    this.errorText,
  });

  final TextEditingController controller;
  final String? projectId;
  final String? scopeId;
  final bool enabled;
  final ValueChanged<YorksV1MaterialRequestInventorySuggestion> onSelected;
  final ValueChanged<String>? onEdited;
  final String? errorText;

  @override
  State<_MobileInventoryDescriptionField> createState() =>
      _MobileInventoryDescriptionFieldState();
}

class _MobileInventoryDescriptionFieldState
    extends State<_MobileInventoryDescriptionField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _AnchoredMaterialDescriptionAutocomplete(
        textController: widget.controller,
        focusNode: _focusNode,
        enabled: widget.enabled,
        projectId: widget.projectId,
        scopeId: widget.scopeId,
        onSelected: widget.onSelected,
        onChanged: widget.onEdited,
        labelText: YorksV1MaterialRequestStrings.itemDescription.primary,
        errorText: widget.errorText,
        preferredWidth: 480,
        preferredHeight: 390,
      );
}

Future<void> _chooseInventorySuggestion(
  BuildContext context,
  WidgetRef _, {
  required String projectId,
  required String scopeId,
  required YorksV1MaterialRequestLine line,
  required YorksV1MaterialRequestDraftController controller,
}) async {
  final suggestion =
      await showDialog<YorksV1MaterialRequestInventorySuggestion>(
        context: context,
        animationStyle: AnimationStyle.noAnimation,
        builder: (_) => _InventorySuggestionDialog(
          projectId: projectId,
          scopeId: scopeId,
          initialQuery: line.description,
        ),
      );
  if (suggestion == null) return;
  await controller.updateLine(
    line.id,
    (current) => _applyMaterialSuggestion(current, suggestion),
  );
}

class _InventorySuggestionDialog extends ConsumerStatefulWidget {
  const _InventorySuggestionDialog({
    required this.projectId,
    required this.scopeId,
    required this.initialQuery,
  });

  final String projectId;
  final String scopeId;
  final String initialQuery;

  @override
  ConsumerState<_InventorySuggestionDialog> createState() =>
      _InventorySuggestionDialogState();
}

class _InventorySuggestionDialogState
    extends ConsumerState<_InventorySuggestionDialog> {
  late final TextEditingController _queryController;
  Timer? _debounce;
  late String _query = widget.initialQuery.trim();

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = _query.length < 2
        ? const AsyncData<List<YorksV1MaterialRequestInventorySuggestion>>([])
        : ref.watch(
            yorksV1MaterialRequestInventorySearchProvider(
              YorksV1MaterialRequestInventorySearchKey(
                projectId: widget.projectId,
                scopeId: widget.scopeId,
                query: _query,
              ),
            ),
          );
    return AlertDialog(
      title: Text(YorksV1MaterialRequestStrings.searchInventory.primary),
      content: SizedBox(
        width: 620,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _queryController,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                labelText:
                    YorksV1MaterialRequestStrings.itemDescription.primary,
              ),
              onChanged: (value) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 280), () {
                  if (mounted) setState(() => _query = value.trim());
                });
              },
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: results.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => _RequestError(
                  language: AppLanguage.english,
                  onRetry: () => ref.invalidate(
                    yorksV1MaterialRequestInventorySearchProvider(
                      YorksV1MaterialRequestInventorySearchKey(
                        projectId: widget.projectId,
                        scopeId: widget.scopeId,
                        query: _query,
                      ),
                    ),
                  ),
                ),
                data: (items) => _MaterialSuggestionPanel(
                  values: items,
                  onSelected: (item) => Navigator.of(context).pop(item),
                  maxWidth: 620,
                  maxHeight: 390,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(YorksV1MaterialRequestStrings.cancel.primary),
        ),
      ],
    );
  }
}

class _RequestLinesEditor extends ConsumerWidget {
  const _RequestLinesEditor({
    required this.lines,
    required this.controller,
    required this.enabled,
    required this.projectId,
    required this.scopeId,
  });

  final List<YorksV1MaterialRequestLine> lines;
  final YorksV1MaterialRequestDraftController controller;
  final bool enabled;
  final String? projectId;
  final String? scopeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (lines.isEmpty) {
      return Text(
        YorksV1MaterialRequestStrings.addItemRequired.primary,
        style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
      );
    }
    final invalidLines = lines
        .where((line) => !line.hasValidOperationalValues)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (invalidLines.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.errorContainer,
              border: Border.all(color: AppColors.error),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 19,
                  color: AppColors.error,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    YorksV1MaterialRequestStrings.rowsNeedAttention(
                      invalidLines.length,
                    ).primary,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final target = _materialRequestLineKey(
                      invalidLines.first.id,
                    ).currentContext;
                    if (target == null) return;
                    await Scrollable.ensureVisible(
                      target,
                      duration: const Duration(milliseconds: 220),
                      alignment: 0.2,
                    );
                  },
                  child: Text(YorksV1MaterialRequestStrings.review.primary),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (lines.any((line) => line.quantityIsSuggested)) ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.warningContainer,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: AppColors.warning,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    YorksV1MaterialRequestStrings
                        .suggestedQuantityReview
                        .primary,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        LayoutBuilder(
          builder: (context, constraints) =>
              MediaQuery.sizeOf(context).width >=
                  AppSpacing.yorksV1DesktopBreakpoint
              ? _DesktopLinesTable(
                  lines: lines,
                  controller: controller,
                  enabled: enabled,
                  projectId: projectId,
                  scopeId: scopeId,
                )
              : Column(
                  children: [
                    for (final line in lines) ...[
                      _FocusedLineEditor(
                        line: line,
                        controller: controller,
                        enabled: enabled,
                        onSearchInventory: projectId == null || scopeId == null
                            ? null
                            : () => _chooseInventorySuggestion(
                                context,
                                ref,
                                projectId: projectId!,
                                scopeId: scopeId!,
                                line: line,
                                controller: controller,
                              ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _DesktopLinesTable extends StatelessWidget {
  const _DesktopLinesTable({
    required this.lines,
    required this.controller,
    required this.enabled,
    required this.projectId,
    required this.scopeId,
  });

  final List<YorksV1MaterialRequestLine> lines;
  final YorksV1MaterialRequestDraftController controller;
  final bool enabled;
  final String? projectId;
  final String? scopeId;

  @override
  Widget build(BuildContext context) {
    // The UI intentionally mirrors the familiar Yorks material form.  The
    // controlled Excel/PDF contract remains role-safe, but the editable web
    // grid keeps size and model/tag visible as first-class columns so an
    // engineer can scan and correct a row without opening a secondary editor.
    final headerStyle = AppTypography.labelSmall.copyWith(
      color: AppColors.muted,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.8,
    );
    final rows = <TableRow>[
      TableRow(
        decoration: const BoxDecoration(color: AppColors.surfaceContainerLow),
        children: [
          _MrTableCell(
            child: Text(
              YorksV1MaterialRequestStrings.serialNumber.primary,
              style: headerStyle,
            ),
          ),
          _MrTableCell(
            child: Text(
              YorksV1MaterialRequestStrings.itemDescription.primary
                  .toUpperCase(),
              style: headerStyle,
            ),
          ),
          _MrTableCell(
            child: Text(
              YorksV1MaterialRequestStrings.size.primary.toUpperCase(),
              style: headerStyle,
            ),
          ),
          _MrTableCell(
            child: Text(
              YorksV1MaterialRequestStrings.planningModelTag.primary
                  .toUpperCase(),
              style: headerStyle,
            ),
          ),
          _MrTableCell(
            child: Text(
              YorksV1MaterialRequestStrings.brandOrigin.primary.toUpperCase(),
              style: headerStyle,
            ),
          ),
          _MrTableCell(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                YorksV1MaterialRequestStrings.quantity.primary.toUpperCase(),
                style: headerStyle,
              ),
            ),
          ),
          _MrTableCell(
            child: Text(
              YorksV1MaterialRequestStrings.unit.primary.toUpperCase(),
              style: headerStyle,
            ),
          ),
          _MrTableCell(
            child: Text(
              AppStrings.action.primary.toUpperCase(),
              style: headerStyle,
            ),
          ),
        ],
      ),
    ];
    for (final line in lines) {
      final invalid = !line.hasValidOperationalValues;
      final descriptionError = line.hasDescription
          ? null
          : YorksV1MaterialRequestStrings.itemDescriptionRequired.primary;
      final quantityError = line.hasValidQuantity
          ? null
          : YorksV1MaterialRequestStrings.quantityRequired.primary;
      final unitError = line.hasControlledUnit
          ? null
          : YorksV1MaterialRequestStrings.unitRequired.primary;
      rows.add(
        TableRow(
          decoration: invalid
              ? BoxDecoration(
                  color: AppColors.errorContainer.withValues(alpha: 0.45),
                  border: const Border(
                    left: BorderSide(color: AppColors.error, width: 3),
                  ),
                )
              : null,
          children: [
            _MrTableCell(
              key: _materialRequestLineKey(line.id),
              child: Text(
                line.displayOrder.toString(),
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.inkSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _MrTableCell(
              child: _MrValidatedCell(
                markerKey: ValueKey('${line.id}-description-error'),
                errorMessage: descriptionError,
                child: _InventoryDescriptionField(
                  line: line,
                  controller: controller,
                  enabled: enabled,
                  projectId: projectId,
                  scopeId: scopeId,
                ),
              ),
            ),
            _MrTableCell(
              child: _LineTextField(
                fieldKey: ValueKey('${line.id}-size'),
                initialValue: line.size ?? '',
                enabled: enabled,
                hintText: YorksV1MaterialRequestStrings.size.primary,
                onChanged: (value) => controller.updateLine(
                  line.id,
                  (current) => current.copyWith(
                    size: value.trim().isEmpty ? null : value,
                  ),
                ),
              ),
            ),
            _MrTableCell(
              child: _LineTextField(
                fieldKey: ValueKey('${line.id}-planning-model-tag'),
                initialValue: line.model ?? line.planningModelTag ?? '',
                enabled: enabled,
                hintText:
                    YorksV1MaterialRequestStrings.planningModelTag.primary,
                onChanged: (value) => controller.updateLine(
                  line.id,
                  (current) => current.copyWith(
                    model: value.trim().isEmpty ? null : value,
                  ),
                ),
              ),
            ),
            _MrTableCell(
              child: _LineTextField(
                fieldKey: ValueKey('${line.id}-brand-origin'),
                initialValue: line.brandOrigin ?? '',
                enabled: enabled,
                onChanged: (value) => controller.updateLine(
                  line.id,
                  (current) => current.copyWith(
                    brandOrigin: value.trim().isEmpty ? null : value,
                  ),
                ),
              ),
            ),
            _MrTableCell(
              child: _MrValidatedCell(
                markerKey: ValueKey('${line.id}-quantity-error'),
                errorMessage: quantityError,
                child: _LineTextField(
                  fieldKey: ValueKey('${line.id}-quantity'),
                  initialValue: yorksV1DisplayQuantity(line.quantity),
                  enabled: enabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.end,
                  onChanged: (value) => controller.updateLine(
                    line.id,
                    (current) => current.copyWith(quantity: value),
                  ),
                ),
              ),
            ),
            _MrTableCell(
              child: _MrValidatedCell(
                markerKey: ValueKey('${line.id}-unit-error'),
                errorMessage: unitError,
                child: _LineUnitDropdown(
                  fieldKey: ValueKey('${line.id}-unit'),
                  initialValue: line.unit,
                  enabled: enabled,
                  onChanged: (value) => controller.updateLine(
                    line.id,
                    (current) => current.copyWith(unit: value),
                  ),
                ),
              ),
            ),
            _MrTableCell(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _MrSimilarButton(
                    buttonKey: ValueKey('${line.id}-desktop-similar'),
                    enabled: enabled,
                    onPressed: () =>
                        controller.addSimilarLine(afterLineId: line.id),
                  ),
                  const SizedBox(width: 6),
                  _MrCustomButton(
                    buttonKey: ValueKey('${line.id}-desktop-custom'),
                    enabled: enabled,
                    onPressed: () =>
                        controller.addCustomLine(afterLineId: line.id),
                  ),
                  const SizedBox(width: 6),
                  _MrDeleteButton(
                    buttonKey: ValueKey('${line.id}-desktop-delete'),
                    enabled: enabled,
                    onPressed: () => controller.removeLine(line.id),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Table(
          columnWidths: const {
            0: FixedColumnWidth(62),
            1: FlexColumnWidth(2.8),
            2: FlexColumnWidth(1.55),
            3: FlexColumnWidth(1.7),
            4: FlexColumnWidth(1.75),
            5: FlexColumnWidth(1.05),
            6: FixedColumnWidth(126),
            7: FixedColumnWidth(184),
          },
          border: TableBorder(
            horizontalInside: BorderSide(color: AppColors.line),
            verticalInside: BorderSide(color: AppColors.line),
            top: BorderSide(color: AppColors.line),
            bottom: BorderSide(color: AppColors.line),
            left: BorderSide(color: AppColors.line),
            right: BorderSide(color: AppColors.line),
          ),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: rows,
        ),
      ),
    );
  }
}

class _MrTableCell extends StatelessWidget {
  const _MrTableCell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.xs,
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 68),
      child: Align(alignment: Alignment.centerLeft, child: child),
    ),
  );
}

/// Keeps dense spreadsheet rows at one stable height while retaining an exact
/// accessible error association. The visible dot is deliberately compact; a
/// pointer tooltip and screen-reader label still name the remediation.
class _MrValidatedCell extends StatelessWidget {
  const _MrValidatedCell({
    required this.child,
    required this.errorMessage,
    required this.markerKey,
  });

  final Widget child;
  final String? errorMessage;
  final Key markerKey;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      child,
      if (errorMessage != null)
        PositionedDirectional(
          top: 0,
          end: 0,
          child: _MrValidationMarker(
            markerKey: markerKey,
            message: errorMessage!,
          ),
        ),
    ],
  );
}

class _MrValidationMarker extends StatelessWidget {
  const _MrValidationMarker({required this.markerKey, required this.message});

  final Key markerKey;
  final String message;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: message,
    excludeFromSemantics: true,
    child: Semantics(
      label: message,
      liveRegion: true,
      child: SizedBox.square(
        key: markerKey,
        dimension: 20,
        child: Center(
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.error,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Ranked BOQ/inventory suggestions belong to the description cell so an
/// engineer gets useful matches while typing, without leaving the row.
/// Selecting a result copies only the trusted non-commercial descriptive
/// projection; quantity remains deliberate user input.
class _InventoryDescriptionField extends StatefulWidget {
  const _InventoryDescriptionField({
    required this.line,
    required this.controller,
    required this.enabled,
    required this.projectId,
    required this.scopeId,
  });

  final YorksV1MaterialRequestLine line;
  final YorksV1MaterialRequestDraftController controller;
  final bool enabled;
  final String? projectId;
  final String? scopeId;

  @override
  State<_InventoryDescriptionField> createState() =>
      _InventoryDescriptionFieldState();
}

class _InventoryDescriptionFieldState
    extends State<_InventoryDescriptionField> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  late String _lastCommitted;

  @override
  void initState() {
    super.initState();
    _lastCommitted = widget.line.description;
    _textController = TextEditingController(text: widget.line.description);
    _focusNode = FocusNode()..addListener(_commitOnBlur);
  }

  @override
  void didUpdateWidget(covariant _InventoryDescriptionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus &&
        widget.line.description != _textController.text) {
      _lastCommitted = widget.line.description;
      _textController.value = TextEditingValue(
        text: widget.line.description,
        selection: TextSelection.collapsed(
          offset: widget.line.description.length,
        ),
      );
    }
  }

  void _commitOnBlur() {
    if (!_focusNode.hasFocus) _commit();
  }

  void _commit() {
    final value = _textController.text;
    if (value == _lastCommitted) return;
    _lastCommitted = value;
    widget.controller.updateLine(
      widget.line.id,
      (current) => current.copyWith(description: value),
    );
  }

  void _select(YorksV1MaterialRequestInventorySuggestion suggestion) {
    _lastCommitted = suggestion.description;
    widget.controller.updateLine(
      widget.line.id,
      (current) => _applyMaterialSuggestion(current, suggestion),
    );
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_commitOnBlur)
      ..dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _AnchoredMaterialDescriptionAutocomplete(
        textController: _textController,
        focusNode: _focusNode,
        enabled: widget.enabled,
        projectId: widget.projectId,
        scopeId: widget.scopeId,
        onSelected: _select,
        onCommitted: _commit,
        fieldKey: ValueKey('${widget.line.id}-description'),
        hintText: YorksV1MaterialRequestStrings.itemDescription.primary,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
        preferredWidth: 560,
        preferredHeight: 410,
        showSuffixIcon: false,
        desktopCell: true,
      );
}

class _MrDeleteButton extends StatelessWidget {
  const _MrDeleteButton({
    this.buttonKey,
    required this.enabled,
    required this.onPressed,
  });

  final Key? buttonKey;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    key: buttonKey,
    tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
    icon: const Icon(Icons.close_rounded, color: AppColors.error),
    style: IconButton.styleFrom(
      side: const BorderSide(color: AppColors.error),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      minimumSize: const Size(44, 44),
    ),
    onPressed: enabled ? onPressed : null,
  );
}

class _MrEditButton extends StatelessWidget {
  const _MrEditButton({
    this.buttonKey,
    required this.enabled,
    required this.onPressed,
  });

  final Key? buttonKey;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    key: buttonKey,
    tooltip: AppStrings.editMaterial.primary,
    icon: const Icon(Icons.edit_outlined, color: AppColors.blue),
    style: IconButton.styleFrom(
      side: const BorderSide(color: AppColors.line),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      minimumSize: const Size(44, 44),
    ),
    onPressed: enabled ? onPressed : null,
  );
}

class _MrSimilarButton extends StatelessWidget {
  const _MrSimilarButton({
    this.buttonKey,
    required this.enabled,
    required this.onPressed,
  });

  final Key? buttonKey;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    key: buttonKey,
    tooltip: YorksV1MaterialRequestStrings.addSimilarRow.primary,
    icon: const Icon(Icons.copy_all_outlined, color: AppColors.blue),
    style: IconButton.styleFrom(
      side: const BorderSide(color: AppColors.blue),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      minimumSize: const Size(44, 44),
    ),
    onPressed: enabled ? onPressed : null,
  );
}

class _MrCustomButton extends StatelessWidget {
  const _MrCustomButton({
    this.buttonKey,
    required this.enabled,
    required this.onPressed,
  });

  final Key? buttonKey;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    key: buttonKey,
    tooltip: YorksV1MaterialRequestStrings.addCustomRow.primary,
    icon: const Icon(Icons.add_box_outlined, color: AppColors.blue),
    style: IconButton.styleFrom(
      side: const BorderSide(color: AppColors.line),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      minimumSize: const Size(44, 44),
    ),
    onPressed: enabled ? onPressed : null,
  );
}

class _LineUnitDropdown extends ConsumerWidget {
  const _LineUnitDropdown({
    required this.fieldKey,
    required this.initialValue,
    required this.enabled,
    required this.onChanged,
  });

  final Key fieldKey;
  final String initialValue;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return YorksV1ControlledUnitDropdown(
      fieldKey: fieldKey,
      label: YorksV1MaterialRequestStrings.unit.primary,
      value: initialValue,
      enabled: enabled,
      isDense: true,
      desktopCell: true,
      onChanged: onChanged,
    );
  }
}

class _FocusedLineEditor extends StatelessWidget {
  const _FocusedLineEditor({
    required this.line,
    required this.controller,
    required this.enabled,
    required this.onSearchInventory,
  });

  final YorksV1MaterialRequestLine line;
  final YorksV1MaterialRequestDraftController controller;
  final bool enabled;
  final VoidCallback? onSearchInventory;

  @override
  Widget build(BuildContext context) {
    final invalid = !line.hasValidOperationalValues;
    return Container(
      key: _materialRequestLineKey(line.id),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: invalid ? AppColors.errorContainer.withValues(alpha: 0.3) : null,
        border: Border.all(
          color: invalid ? AppColors.error : AppColors.line,
          width: invalid ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('${line.displayOrder}', style: AppTypography.titleSmall),
              const Spacer(),
              _MrSimilarButton(
                buttonKey: ValueKey('${line.id}-focused-similar'),
                enabled: enabled,
                onPressed: () =>
                    controller.addSimilarLine(afterLineId: line.id),
              ),
              const SizedBox(width: 6),
              _MrCustomButton(
                buttonKey: ValueKey('${line.id}-focused-custom'),
                enabled: enabled,
                onPressed: () => controller.addCustomLine(afterLineId: line.id),
              ),
              const SizedBox(width: 6),
              _MrDeleteButton(
                buttonKey: ValueKey('${line.id}-focused-delete'),
                enabled: enabled,
                onPressed: () => controller.removeLine(line.id),
              ),
            ],
          ),
          _MrValidatedCell(
            markerKey: ValueKey('${line.id}-focused-description-error'),
            errorMessage: line.hasDescription
                ? null
                : YorksV1MaterialRequestStrings.itemDescriptionRequired.primary,
            child: _LineLabeledField(
              fieldKey: ValueKey('${line.id}-description'),
              label: YorksV1MaterialRequestStrings.itemDescription.primary,
              initialValue: line.description,
              enabled: enabled,
              onChanged: (value) => controller.updateLine(
                line.id,
                (current) => current.copyWith(description: value),
              ),
            ),
          ),
          if (enabled && onSearchInventory != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onSearchInventory,
                icon: const Icon(Icons.search_rounded, size: 18),
                label: Text(
                  YorksV1MaterialRequestStrings.searchInventory.primary,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          _LineLabeledField(
            fieldKey: ValueKey('${line.id}-brand-origin'),
            label: YorksV1MaterialRequestStrings.brandOrigin.primary,
            initialValue: line.brandOrigin ?? '',
            enabled: enabled,
            onChanged: (value) => controller.updateLine(
              line.id,
              (current) => current.copyWith(
                brandOrigin: value.trim().isEmpty ? null : value,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _LineLabeledField(
            fieldKey: ValueKey('${line.id}-size'),
            label: YorksV1MaterialRequestStrings.size.primary,
            initialValue: line.size ?? '',
            enabled: enabled,
            onChanged: (value) => controller.updateLine(
              line.id,
              (current) =>
                  current.copyWith(size: value.trim().isEmpty ? null : value),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _LineLabeledField(
            fieldKey: ValueKey('${line.id}-planning-model-tag'),
            label: YorksV1MaterialRequestStrings.planningModelTag.primary,
            initialValue: line.model ?? line.planningModelTag ?? '',
            enabled: enabled,
            onChanged: (value) => controller.updateLine(
              line.id,
              (current) =>
                  current.copyWith(model: value.trim().isEmpty ? null : value),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _MrValidatedCell(
                  markerKey: ValueKey('${line.id}-focused-quantity-error'),
                  errorMessage: line.hasValidQuantity
                      ? null
                      : YorksV1MaterialRequestStrings.quantityRequired.primary,
                  child: _LineLabeledField(
                    fieldKey: ValueKey('${line.id}-quantity'),
                    label: YorksV1MaterialRequestStrings.quantity.primary,
                    initialValue: yorksV1DisplayQuantity(line.quantity),
                    enabled: enabled,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (value) => controller.updateLine(
                      line.id,
                      (current) => current.copyWith(quantity: value),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _MrValidatedCell(
                  markerKey: ValueKey('${line.id}-focused-unit-error'),
                  errorMessage: line.hasControlledUnit
                      ? null
                      : YorksV1MaterialRequestStrings.unitRequired.primary,
                  child: _LineLabeledUnitDropdown(
                    fieldKey: ValueKey('${line.id}-unit'),
                    label: YorksV1MaterialRequestStrings.unit.primary,
                    initialValue: line.unit,
                    enabled: enabled,
                    onChanged: (value) => controller.updateLine(
                      line.id,
                      (current) => current.copyWith(unit: value),
                    ),
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

/// A local edit buffer for a dense material grid cell.  Calling the Riverpod
/// controller from [TextField.onChanged] used to replace the complete draft
/// line list for every character.  On desktop browsers that made long sheets
/// feel noticeably sluggish.  We instead commit validated user intent when
/// the cell loses focus or the user presses Enter.
class _LineTextField extends StatefulWidget {
  const _LineTextField({
    required this.fieldKey,
    required this.initialValue,
    required this.onChanged,
    required this.enabled,
    this.keyboardType,
    this.textAlign = TextAlign.start,
    this.hintText,
  });

  final Key fieldKey;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final TextInputType? keyboardType;
  final TextAlign textAlign;
  final String? hintText;

  @override
  State<_LineTextField> createState() => _LineTextFieldState();
}

class _LineTextFieldState extends State<_LineTextField> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  late String _lastCommitted;

  @override
  void initState() {
    super.initState();
    _lastCommitted = widget.initialValue;
    _textController = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
    _focusNode.addListener(_commitOnBlur);
  }

  @override
  void didUpdateWidget(covariant _LineTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Preserve the in-progress browser input.  Server/local draft updates are
    // reflected only after the field is no longer active.
    if (!_focusNode.hasFocus && widget.initialValue != _textController.text) {
      _lastCommitted = widget.initialValue;
      _textController.value = TextEditingValue(
        text: widget.initialValue,
        selection: TextSelection.collapsed(offset: widget.initialValue.length),
      );
    }
  }

  void _commitOnBlur() {
    if (!_focusNode.hasFocus) _commit();
  }

  void _commit() {
    final value = _textController.text;
    if (value == _lastCommitted) return;
    _lastCommitted = value;
    widget.onChanged(value);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_commitOnBlur)
      ..dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    key: widget.fieldKey,
    controller: _textController,
    focusNode: _focusNode,
    enabled: widget.enabled,
    keyboardType: widget.keyboardType,
    textAlign: widget.textAlign,
    onFieldSubmitted: (_) => _commit(),
    decoration: const InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: AppColors.blue, width: 2),
      ),
    ).copyWith(hintText: widget.hintText),
  );
}

class _LineLabeledUnitDropdown extends ConsumerWidget {
  const _LineLabeledUnitDropdown({
    required this.fieldKey,
    required this.label,
    required this.initialValue,
    required this.onChanged,
    required this.enabled,
  });

  final Key fieldKey;
  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return YorksV1ControlledUnitDropdown(
      fieldKey: fieldKey,
      label: label,
      value: initialValue,
      enabled: enabled,
      onChanged: onChanged,
    );
  }
}

class _LineLabeledField extends StatefulWidget {
  const _LineLabeledField({
    required this.fieldKey,
    required this.label,
    required this.initialValue,
    required this.onChanged,
    required this.enabled,
    this.keyboardType,
  });

  final Key fieldKey;
  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final TextInputType? keyboardType;

  @override
  State<_LineLabeledField> createState() => _LineLabeledFieldState();
}

class _LineLabeledFieldState extends State<_LineLabeledField> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  late String _lastCommitted;

  @override
  void initState() {
    super.initState();
    _lastCommitted = widget.initialValue;
    _textController = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
    _focusNode.addListener(_commitOnBlur);
  }

  @override
  void didUpdateWidget(covariant _LineLabeledField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.initialValue != _textController.text) {
      _lastCommitted = widget.initialValue;
      _textController.value = TextEditingValue(
        text: widget.initialValue,
        selection: TextSelection.collapsed(offset: widget.initialValue.length),
      );
    }
  }

  void _commitOnBlur() {
    if (!_focusNode.hasFocus) _commit();
  }

  void _commit() {
    final value = _textController.text;
    if (value == _lastCommitted) return;
    _lastCommitted = value;
    widget.onChanged(value);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_commitOnBlur)
      ..dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    key: widget.fieldKey,
    controller: _textController,
    focusNode: _focusNode,
    enabled: widget.enabled,
    keyboardType: widget.keyboardType,
    onFieldSubmitted: (_) => _commit(),
    decoration: InputDecoration(labelText: widget.label),
  );
}

class _RequestDetailBody extends ConsumerWidget {
  const _RequestDetailBody({
    required this.request,
    required this.language,
    required this.showPageHeader,
    required this.onRefresh,
    this.commentId,
  });

  final YorksV1MaterialRequest request;
  final AppLanguage language;
  final bool showPageHeader;
  final VoidCallback onRefresh;
  final String? commentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(yorksV1CurrentRoleProvider);
    final permissionState = ref.watch(yorksV1CurrentPermissionSnapshotProvider);
    final featureFlags = ref.watch(yorksV1FeatureFlagsProvider);
    final arrangementEnabled = featureFlags.arrangement;
    final logisticsEnabled = featureFlags.logistics;
    final returnsDocumentsEnabled = featureFlags.returnsDocuments;
    final fileService = ref.watch(yorksV1BoqWorkbookFileServiceProvider);
    final documentService = YorksV1MaterialRequestDocumentService();
    final AsyncValue<YorksV1ArrangementWorkspace?> arrangement =
        arrangementEnabled
        ? ref.watch(yorksV1ArrangementWorkspaceProvider(request.id))
        : const AsyncData(null);
    // These are role-safe server projections.  The client uses their action
    // flags to choose the correct hand-off in the record header; it never
    // treats the local role label as authority for dispatch, receipt or DO.
    final logisticsWorkspace = logisticsEnabled
        ? ref.watch(yorksV1LogisticsWorkspaceProvider(request.id)).valueOrNull
        : null;
    final returnsDocumentsWorkspace = returnsDocumentsEnabled
        ? ref
              .watch(yorksV1ReturnsDocumentsWorkspaceProvider(request.id))
              .valueOrNull
        : null;
    final documentModel = ref.watch(
      yorksV1MaterialRequestDocumentProvider(request.id),
    );
    final phase3Policy = ref
        .watch(yorksV1MaterialRequestPhase3PolicyProvider(request.id))
        .valueOrNull;
    final replacementCard =
        phase3Policy != null &&
            (phase3Policy.canCreateReplacement ||
                phase3Policy.replacementExists)
        ? _MaterialRequestReplacementCard(
            request: request,
            policy: phase3Policy,
            language: language,
          )
        : null;
    final desktop =
        MediaQuery.sizeOf(context).width >= AppSpacing.yorksV1DesktopBreakpoint;
    final isProcurement =
        role == YorksV1Role.procurement || role == YorksV1Role.admin;
    final legacyCanArrange =
        arrangementEnabled &&
        isProcurement &&
        (request.state == YorksV1MaterialRequestState.approvedForArrangement ||
            request.state == YorksV1MaterialRequestState.arranging);
    final arrangeAccess = yorksV1FeatureActionAccess(
      permissionState,
      YorksV1CapabilityKeys.procurementArrange,
      legacyAllowed: legacyCanArrange,
      projectId: request.projectId,
    );
    // Cancellation is a Project Engineer/Admin command. A Site Engineer who
    // also holds a Project Engineer membership is authorized by the server,
    // but the role-safe request projection does not expose that composite
    // capability yet, so do not surface an action that can be rejected.
    final legacyCanCancel =
        ((role?.isGlobalProjectEngineer ?? false) ||
            role == YorksV1Role.projectEngineer ||
            role == YorksV1Role.admin) &&
        (request.state == YorksV1MaterialRequestState.submitted ||
            request.state ==
                YorksV1MaterialRequestState.awaitingRequestApproval ||
            request.state == YorksV1MaterialRequestState.changesRequested ||
            request.state ==
                YorksV1MaterialRequestState.approvedForArrangement ||
            request.state == YorksV1MaterialRequestState.arranging ||
            request.state == YorksV1MaterialRequestState.awaitingApproval ||
            request.state == YorksV1MaterialRequestState.approved);
    final cancelAccess = yorksV1FeatureActionAccess(
      permissionState,
      YorksV1CapabilityKeys.materialRequestsCancel,
      legacyAllowed: legacyCanCancel,
      projectId: request.projectId,
    );
    final editAccess = yorksV1FeatureActionAccess(
      permissionState,
      YorksV1CapabilityKeys.materialRequestsEdit,
      legacyAllowed: request.canEditBeforeApproval,
      projectId: request.projectId,
    );
    final approveAccess = yorksV1FeatureActionAccess(
      permissionState,
      YorksV1CapabilityKeys.materialRequestsApprove,
      legacyAllowed: request.canDecideRequest,
      projectId: request.projectId,
    );
    final returnForChangesAccess = yorksV1FeatureActionAccess(
      permissionState,
      YorksV1CapabilityKeys.materialRequestsReturnForChanges,
      legacyAllowed: request.canDecideRequest,
      projectId: request.projectId,
    );
    final canOpenLogistics =
        logisticsEnabled &&
        request.state != YorksV1MaterialRequestState.draft &&
        request.state != YorksV1MaterialRequestState.submitted &&
        request.state != YorksV1MaterialRequestState.awaitingRequestApproval &&
        request.state != YorksV1MaterialRequestState.changesRequested &&
        request.state != YorksV1MaterialRequestState.approvedForArrangement &&
        request.state != YorksV1MaterialRequestState.cancelled;
    final canOpenReturnsDocuments =
        returnsDocumentsEnabled &&
        request.state != YorksV1MaterialRequestState.draft &&
        request.state != YorksV1MaterialRequestState.cancelled;
    final arrangementWorkspace = arrangement.valueOrNull;
    final arrangementForApproval = featureFlags.legacyArrangementReview
        ? arrangementWorkspace?.currentArrangement
        : null;
    final receiptDispatch = _firstReceiptDispatch(logisticsWorkspace);
    final deliveryOrderDispatch = _firstDeliveryOrderDispatch(
      returnsDocumentsWorkspace,
    );
    final deliveryOrderAccess = yorksV1FeatureActionAccess(
      permissionState,
      YorksV1CapabilityKeys.deliveryOrdersGenerate,
      legacyAllowed: deliveryOrderDispatch != null,
      projectId: request.projectId,
    );
    final receiptAccess = yorksV1FeatureActionAccess(
      permissionState,
      YorksV1CapabilityKeys.receiptsConfirm,
      legacyAllowed: receiptDispatch != null,
      projectId: request.projectId,
    );
    final dispatchAccess = yorksV1FeatureActionAccess(
      permissionState,
      YorksV1CapabilityKeys.dispatchCreate,
      legacyAllowed: logisticsWorkspace?.canDispatch == true,
      projectId: request.projectId,
    );
    final closeAccess = yorksV1FeatureActionAccess(
      permissionState,
      YorksV1CapabilityKeys.materialRequestsClose,
      legacyAllowed: yorksV1CanOfferMaterialRequestClose(
        state: request.state,
        role: role,
      ),
      projectId: request.projectId,
    );
    final canGenerateDeliveryOrder =
        deliveryOrderDispatch != null && deliveryOrderAccess.isVisible;
    final canClose = closeAccess.isVisible;
    final onGenerateDeliveryOrder =
        returnsDocumentsWorkspace != null &&
            deliveryOrderDispatch != null &&
            deliveryOrderAccess.canWrite
        ? () => _generateDeliveryOrder(
            context,
            ref,
            request,
            returnsDocumentsWorkspace,
            deliveryOrderDispatch,
          )
        : null;
    final onReviewReceipt =
        logisticsWorkspace == null ||
            receiptDispatch == null ||
            !receiptAccess.canWrite
        ? null
        : () => _reviewReceipt(
            context,
            ref,
            request,
            logisticsWorkspace,
            receiptDispatch,
          );
    final primaryAction = yorksV1MaterialRequestDetailPrimaryAction(
      state: request.state,
      role: role,
      canArrange:
          arrangeAccess.isVisible &&
          arrangementWorkspace != null &&
          (arrangementWorkspace.canBegin || arrangementWorkspace.canSave),
      canDispatch:
          logisticsWorkspace?.canDispatch == true && dispatchAccess.isVisible,
      canConfirmReceipt: receiptDispatch != null && receiptAccess.isVisible,
      canGenerateDeliveryOrder: canGenerateDeliveryOrder,
      canClose: canClose,
    );
    final onPrimaryAction = switch (primaryAction) {
      YorksV1MaterialRequestDetailPrimaryAction.arrange
          when arrangeAccess.canWrite =>
        () => _openArrangement(context, ref, request.id, arrangementWorkspace),
      YorksV1MaterialRequestDetailPrimaryAction.dispatch
          when dispatchAccess.canWrite =>
        () => context.push(
          RoutePaths.yorksV1MaterialRequestLogisticsPath(request.id),
        ),
      YorksV1MaterialRequestDetailPrimaryAction.receiptReview
          when receiptAccess.canWrite =>
        onReviewReceipt,
      YorksV1MaterialRequestDetailPrimaryAction.close
          when closeAccess.canWrite =>
        () => _close(context, ref, request),
      YorksV1MaterialRequestDetailPrimaryAction.generateDeliveryOrder
          when deliveryOrderAccess.canWrite =>
        onGenerateDeliveryOrder,
      _ => null,
    };
    // The decision controls remain in the one top-right action group. Editing
    // is deliberately a utility action below it, so an approving Engineer
    // does not have to scroll through a long record to find the next command.
    final Widget? approvalActions =
        request.canDecideRequest &&
            (approveAccess.isVisible || returnForChangesAccess.isVisible)
        ? _RequestApprovalActions(
            request: request,
            showEdit: false,
            showApprove: approveAccess.isVisible,
            showReturnForChanges: returnForChangesAccess.isVisible,
            canEdit: false,
            canApprove: approveAccess.canWrite,
            canReturnForChanges: returnForChangesAccess.canWrite,
            showEditAction: false,
          )
        : featureFlags.legacyArrangementReview &&
              arrangementWorkspace?.canDecide == true &&
              arrangementForApproval != null
        ? _RequestArrangementApprovalActions(
            workspace: arrangementWorkspace!,
            arrangement: arrangementForApproval,
          )
        : null;
    final Widget? editAction =
        request.canEditBeforeApproval && editAccess.isVisible
        ? _RecordActionButton(
            label: YorksV1MaterialRequestStrings.editRequest.active(language),
            icon: Icons.edit_outlined,
            onPressed: editAccess.canWrite
                ? () => context.push(
                    RoutePaths.yorksV1MaterialRequestDraftPath(
                      request.id,
                      projectId: request.projectId,
                    ),
                  )
                : null,
          )
        : null;
    // Measure the effective record canvas, not just the browser width. This
    // keeps a 14-inch office layout from squeezing the controlled item table
    // when the persistent sidebar is open, while a collapsed sidebar can
    // immediately use the recovered workspace for the inspector.
    final sidebarExpanded = desktop
        ? ref.watch(yorksV1WorkspaceSidebarExpandedProvider)
        : false;
    final pageHorizontalPadding = desktop
        ? (AppSpacing.xxxl + AppSpacing.xs) * 2
        : AppSpacing.lg * 2;
    final effectiveCanvasWidth =
        MediaQuery.sizeOf(context).width -
        (sidebarExpanded
            ? AppSpacing.sidebarWidth
            : AppSpacing.sidebarCollapsedWidth) -
        pageHorizontalPadding;
    final canDockInspector =
        desktop &&
        effectiveCanvasWidth >=
            800 + AppSpacing.inspectorWidth + AppSpacing.xxl;
    final inspectorExpanded =
        canDockInspector &&
        ref.watch(
          yorksV1MaterialRequestWorkspaceInspectorExpandedProvider(request.id),
        );
    if (YorksMobileUi.isActive(context)) {
      final mobileInlineApprovalActions =
          request.canEditBeforeApproval && editAccess.isVisible
          ? _RequestApprovalActions(
              request: request,
              showEdit: editAccess.isVisible,
              showApprove: false,
              showReturnForChanges: false,
              canEdit: editAccess.canWrite,
              canApprove: false,
              canReturnForChanges: false,
              showDecisionActions: false,
            )
          : featureFlags.legacyArrangementReview &&
                arrangementWorkspace?.canDecide == true &&
                arrangementForApproval != null
          ? _RequestArrangementApprovalActions(
              workspace: arrangementWorkspace!,
              arrangement: arrangementForApproval,
            )
          : null;
      return _MobileMaterialRequestLifecycle(
        request: request,
        language: language,
        commentId: commentId,
        primaryAction: primaryAction,
        onPrimaryAction: onPrimaryAction,
        onRefresh: onRefresh,
        approvalActions: mobileInlineApprovalActions,
        stickyApprovalActions:
            request.canDecideRequest &&
                (approveAccess.isVisible || returnForChangesAccess.isVisible)
            ? _RequestApprovalActions(
                request: request,
                showEdit: false,
                showApprove: approveAccess.isVisible,
                showReturnForChanges: returnForChangesAccess.isVisible,
                canEdit: false,
                canApprove: approveAccess.canWrite,
                canReturnForChanges: returnForChangesAccess.canWrite,
                showEditAction: false,
                mobileSticky: true,
              )
            : null,
        showCancel: cancelAccess.isVisible,
        onCancel: cancelAccess.canWrite
            ? () => _cancel(context, ref, request)
            : null,
        onOpenLogistics: canOpenLogistics
            ? () => context.push(
                RoutePaths.yorksV1MaterialRequestLogisticsPath(request.id),
              )
            : null,
        onOpenDocuments: canOpenReturnsDocuments
            ? () => context.push(
                RoutePaths.yorksV1MaterialRequestReturnsDocumentsPath(
                  request.id,
                ),
              )
            : null,
        showGenerateDeliveryOrder: canGenerateDeliveryOrder,
        onGenerateDeliveryOrder: onGenerateDeliveryOrder,
        documentModel: documentModel,
        onPdf: documentModel.valueOrNull == null
            ? null
            : () =>
                  documentService.shareDocumentPdf(documentModel.valueOrNull!),
        onPrint: documentModel.valueOrNull == null
            ? null
            : () =>
                  documentService.printDocumentPdf(documentModel.valueOrNull!),
        replacementCard: replacementCard,
      );
    }
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                desktop ? AppSpacing.xxxl + AppSpacing.xs : AppSpacing.lg,
                AppSpacing.xxl,
                desktop ? AppSpacing.xxxl + AppSpacing.xs : AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSpacing.pageMaxWidth,
                ),
                child: _RequestRecordHeader(
                  request: request,
                  language: language,
                  onRefresh: onRefresh,
                  primaryAction: primaryAction,
                  onPrimaryAction: onPrimaryAction,
                  onExport: () async {
                    final saved = await fileService.saveWorkbook(
                      bytes: documentService.buildExcel(request),
                      suggestedName: documentService.suggestedExcelName(
                        request,
                      ),
                    );
                    if (context.mounted && saved) {
                      _snack(
                        context,
                        YorksV1MaterialRequestStrings.saved.primary,
                      );
                    }
                  },
                  onPdf: documentModel.valueOrNull == null
                      ? null
                      : () => documentService.shareDocumentPdf(
                          documentModel.valueOrNull!,
                        ),
                  onPrint: documentModel.valueOrNull == null
                      ? null
                      : () => documentService.printDocumentPdf(
                          documentModel.valueOrNull!,
                        ),
                  onRequestInformation: () {
                    if (canDockInspector) {
                      final controller = ref.read(
                        yorksV1MaterialRequestWorkspaceInspectorExpandedProvider(
                          request.id,
                        ).notifier,
                      );
                      controller.state = !controller.state;
                      return;
                    }
                    _showRequestWorkspaceInspector(
                      context,
                      request: request,
                      language: language,
                    );
                  },
                  requestInformationActive: inspectorExpanded,
                  editAction: editAction,
                  approvalActions: approvalActions,
                  showCancel: cancelAccess.isVisible,
                  onCancel: cancelAccess.canWrite
                      ? () => _cancel(context, ref, request)
                      : null,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                desktop ? AppSpacing.xxxl + AppSpacing.xs : AppSpacing.lg,
                0,
                desktop ? AppSpacing.xxxl + AppSpacing.xs : AppSpacing.lg,
                72,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSpacing.pageMaxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (replacementCard != null) ...[
                      replacementCard,
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    if (desktop) ...[
                      _RequestDecisionBanner(
                        request: request,
                        language: language,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    if (desktop)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _RequestRecordContent(
                              request: request,
                              language: language,
                              arrangement: arrangement,
                              documentModel: documentModel,
                              canOpenLogistics: canOpenLogistics,
                              canOpenReturnsDocuments: canOpenReturnsDocuments,
                              logisticsWorkspace: logisticsWorkspace,
                              returnsDocumentsWorkspace:
                                  returnsDocumentsWorkspace,
                              showReceiptReview: receiptAccess.isVisible,
                              onReviewReceipt:
                                  logisticsWorkspace == null ||
                                      !receiptAccess.canWrite
                                  ? null
                                  : (dispatch) => _reviewReceipt(
                                      context,
                                      ref,
                                      request,
                                      logisticsWorkspace,
                                      dispatch,
                                    ),
                              showGenerateDeliveryOrder:
                                  deliveryOrderAccess.isVisible,
                              onGenerateDeliveryOrder:
                                  returnsDocumentsWorkspace == null ||
                                      !deliveryOrderAccess.canWrite
                                  ? null
                                  : (dispatch) => _generateDeliveryOrder(
                                      context,
                                      ref,
                                      request,
                                      returnsDocumentsWorkspace,
                                      dispatch,
                                    ),
                              onOpenLogistics: () => context.push(
                                RoutePaths.yorksV1MaterialRequestLogisticsPath(
                                  request.id,
                                ),
                              ),
                              onOpenReturns: () => context.push(
                                RoutePaths.yorksV1MaterialRequestReturnsDocumentsPath(
                                  request.id,
                                ),
                              ),
                            ),
                          ),
                          if (inspectorExpanded) ...[
                            const SizedBox(width: AppSpacing.xxl),
                            SizedBox(
                              width: AppSpacing.inspectorWidth,
                              child: _RequestWorkspaceInspector(
                                request: request,
                                language: language,
                                onClose: () =>
                                    ref
                                            .read(
                                              yorksV1MaterialRequestWorkspaceInspectorExpandedProvider(
                                                request.id,
                                              ).notifier,
                                            )
                                            .state =
                                        false,
                              ),
                            ),
                          ],
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _RequestDecisionBanner(
                            request: request,
                            language: language,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _RequestRecordContent(
                            request: request,
                            language: language,
                            arrangement: arrangement,
                            documentModel: documentModel,
                            canOpenLogistics: canOpenLogistics,
                            canOpenReturnsDocuments: canOpenReturnsDocuments,
                            logisticsWorkspace: logisticsWorkspace,
                            returnsDocumentsWorkspace:
                                returnsDocumentsWorkspace,
                            showReceiptReview: receiptAccess.isVisible,
                            onReviewReceipt:
                                logisticsWorkspace == null ||
                                    !receiptAccess.canWrite
                                ? null
                                : (dispatch) => _reviewReceipt(
                                    context,
                                    ref,
                                    request,
                                    logisticsWorkspace,
                                    dispatch,
                                  ),
                            showGenerateDeliveryOrder:
                                deliveryOrderAccess.isVisible,
                            onGenerateDeliveryOrder:
                                returnsDocumentsWorkspace == null ||
                                    !deliveryOrderAccess.canWrite
                                ? null
                                : (dispatch) => _generateDeliveryOrder(
                                    context,
                                    ref,
                                    request,
                                    returnsDocumentsWorkspace,
                                    dispatch,
                                  ),
                            onOpenLogistics: () => context.push(
                              RoutePaths.yorksV1MaterialRequestLogisticsPath(
                                request.id,
                              ),
                            ),
                            onOpenReturns: () => context.push(
                              RoutePaths.yorksV1MaterialRequestReturnsDocumentsPath(
                                request.id,
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: AppSpacing.xxl),
                    _MaterialRequestDiscussion(
                      request: request,
                      highlightCommentId: commentId,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openArrangement(
    BuildContext context,
    WidgetRef ref,
    String requestId,
    YorksV1ArrangementWorkspace? workspace,
  ) async {
    // Entering an arrangement is an explicit server command.  Start the first
    // version here so the Arrange action opens the editor directly, rather
    // than exposing a second, visually unrelated start screen.  The trusted
    // RPC remains the authority for the state transition and idempotency.
    if (workspace?.canBegin == true && workspace?.workingArrangement == null) {
      final rootNavigator = Navigator.of(context, rootNavigator: true);
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      try {
        await ref
            .read(yorksV1MaterialWorkflowCommandControllerProvider)
            .beginArrangement(
              YorksV1BeginArrangementInput(
                requestId: requestId,
                expectedRequestVersion: workspace!.requestRecordVersion,
                idempotencyKey: const Uuid().v4(),
              ),
            );
        ref.invalidate(yorksV1ArrangementWorkspaceProvider(requestId));
        ref.invalidate(yorksV1MaterialRequestDetailProvider(requestId));
        ref.invalidate(yorksV1MaterialRequestListProvider);
      } on YorksV1DomainException catch (error) {
        if (context.mounted) {
          _snack(
            context,
            YorksV1MaterialRequestStrings.commandFailure(error.code).primary,
          );
        }
        return;
      } catch (_) {
        if (context.mounted) {
          _snack(context, YorksV1ArrangementStrings.savingFailed.primary);
        }
        return;
      } finally {
        if (rootNavigator.canPop()) rootNavigator.pop();
      }
    }
    if (!context.mounted) return;
    if (MediaQuery.sizeOf(context).width <
        AppSpacing.yorksV1DesktopBreakpoint) {
      context.push(RoutePaths.yorksV1MaterialRequestArrangementPath(requestId));
      return;
    }
    await showDialog<void>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      barrierColor: AppColors.scrim.withValues(alpha: .42),
      builder: (dialogContext) {
        final size = MediaQuery.sizeOf(dialogContext);
        return Dialog(
          insetPadding: const EdgeInsets.all(AppSpacing.xxxl),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          ),
          child: SizedBox(
            width: 1320,
            height: (size.height - AppSpacing.colossal * 2)
                .clamp(520.0, 820.0)
                .toDouble(),
            child: YorksV1ArrangementScreen(
              requestId: requestId,
              embedded: true,
              onClose: () => Navigator.of(dialogContext).pop(),
              onCompleted: () => Navigator.of(dialogContext).pop(),
            ),
          ),
        );
      },
    );
  }

  YorksV1MaterialDispatch? _firstReceiptDispatch(
    YorksV1LogisticsWorkspace? workspace,
  ) {
    if (workspace == null || !workspace.canConfirmReceipt) return null;
    for (final dispatch in workspace.dispatches) {
      if (dispatch.canConfirmReceipt) return dispatch;
    }
    return null;
  }

  YorksV1DeliveryOrderDispatch? _firstDeliveryOrderDispatch(
    YorksV1ReturnsDocumentsWorkspace? workspace,
  ) {
    if (workspace == null || !workspace.canGenerateDeliveryOrder) return null;
    for (final dispatch in workspace.deliveryOrderDispatches) {
      if (dispatch.canGenerate) return dispatch;
    }
    return null;
  }

  Future<void> _reviewReceipt(
    BuildContext context,
    WidgetRef ref,
    YorksV1MaterialRequest request,
    YorksV1LogisticsWorkspace workspace,
    YorksV1MaterialDispatch dispatch,
  ) async {
    final changed = await showYorksV1ReceiptReviewDialog(
      context,
      workspace: workspace,
      dispatch: dispatch,
      onChanged: () => _refreshWorkflow(ref, request),
    );
    if (changed == true) _refreshWorkflow(ref, request);
  }

  Future<void> _generateDeliveryOrder(
    BuildContext context,
    WidgetRef ref,
    YorksV1MaterialRequest request,
    YorksV1ReturnsDocumentsWorkspace workspace,
    YorksV1DeliveryOrderDispatch dispatch,
  ) async {
    final changed = await showYorksV1DeliveryOrderGenerationDialog(
      context,
      workspace: workspace,
      dispatch: dispatch,
      documents: const YorksV1LogisticsDocumentService(),
      canGenerate: true,
    );
    if (changed == true) _refreshWorkflow(ref, request);
  }

  void _refreshWorkflow(WidgetRef ref, YorksV1MaterialRequest request) {
    ref.invalidate(yorksV1MaterialRequestDetailProvider(request.id));
    ref.invalidate(yorksV1MaterialRequestDocumentProvider(request.id));
    ref.invalidate(yorksV1ArrangementWorkspaceProvider(request.id));
    ref.invalidate(yorksV1LogisticsWorkspaceProvider(request.id));
    ref.invalidate(yorksV1ReturnsDocumentsWorkspaceProvider(request.id));
    ref.invalidate(yorksV1MaterialRequestListProvider(null));
    ref.invalidate(yorksV1MaterialRequestListProvider(request.projectId));
  }

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    YorksV1MaterialRequest request,
  ) async {
    final reason = await _cancelReason(context, ref.read(languageProvider));
    if (reason == null || reason.trim().isEmpty) return;
    try {
      await ref
          .read(yorksV1MaterialWorkflowCommandControllerProvider)
          .cancelMaterialRequest(
            YorksV1CancelMaterialRequestInput(
              requestId: request.id,
              expectedVersion: request.recordVersion,
              reason: reason,
              idempotencyKey: const Uuid().v4(),
            ),
          );
      if (!context.mounted) return;
      ref.invalidate(yorksV1MaterialRequestDetailProvider(request.id));
      ref.invalidate(yorksV1MaterialRequestListProvider);
      _snack(context, YorksV1MaterialRequestStrings.cancelled.primary);
    } on YorksV1DomainException catch (error) {
      if (context.mounted) {
        _snack(
          context,
          YorksV1MaterialRequestStrings.commandFailure(error.code).primary,
        );
      }
    } catch (_) {
      if (context.mounted) {
        _snack(context, YorksV1MaterialRequestStrings.saveFailed.primary);
      }
    }
  }

  Future<void> _close(
    BuildContext context,
    WidgetRef ref,
    YorksV1MaterialRequest request,
  ) async {
    try {
      await ref
          .read(yorksV1MaterialWorkflowCommandControllerProvider)
          .closeMaterialRequest(
            YorksV1CloseMaterialRequestInput(
              requestId: request.id,
              expectedVersion: request.recordVersion,
              idempotencyKey: '',
            ),
          );
      if (!context.mounted) return;
      _refreshWorkflow(ref, request);
      _snack(context, YorksV1MaterialRequestStrings.requestClosed.primary);
    } on YorksV1DomainException catch (error) {
      if (context.mounted) {
        _snack(
          context,
          YorksV1MaterialRequestStrings.commandFailure(error.code).primary,
        );
      }
    } catch (_) {
      if (context.mounted) {
        _snack(context, YorksV1MaterialRequestStrings.saveFailed.primary);
      }
    }
  }
}

/// Compact lifecycle surface for a committed request.  It intentionally uses
/// only the role-safe request projection and the already-resolved existing
/// command callbacks supplied by [_RequestDetailBody].
class _MaterialRequestReplacementCard extends ConsumerStatefulWidget {
  const _MaterialRequestReplacementCard({
    required this.request,
    required this.policy,
    required this.language,
  });

  final YorksV1MaterialRequest request;
  final YorksV1MaterialRequestPhase3Policy policy;
  final AppLanguage language;

  @override
  ConsumerState<_MaterialRequestReplacementCard> createState() =>
      _MaterialRequestReplacementCardState();
}

class _MaterialRequestReplacementCardState
    extends ConsumerState<_MaterialRequestReplacementCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 620;
      final action = _action(context);
      final body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.warningContainer,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: const Icon(
              Icons.content_copy_rounded,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.policy.replacementExists
                      ? YorksV1MaterialRequestStrings.replacementDraftCreated
                            .active(widget.language)
                      : YorksV1MaterialRequestStrings.createReplacementRequest
                            .active(widget.language),
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  YorksV1MaterialRequestStrings.replacementRequestHelp.active(
                    widget.language,
                  ),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          if (!compact && action != null) ...[
            const SizedBox(width: AppSpacing.sm),
            action,
          ],
        ],
      );
      return Container(
        key: const ValueKey('material-request-replacement-card'),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.warningContainer.withValues(alpha: .42),
          border: Border.all(color: AppColors.warning.withValues(alpha: .35)),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: compact && action != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  body,
                  const SizedBox(height: AppSpacing.md),
                  action,
                ],
              )
            : body,
      );
    },
  );

  Widget? _action(BuildContext context) {
    if (widget.policy.canCreateReplacement) {
      return OutlinedButton.icon(
        key: const ValueKey('create-replacement-material-request'),
        onPressed: _busy ? null : _create,
        icon: _busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.note_add_outlined),
        label: Text(
          YorksV1MaterialRequestStrings.createReplacementRequest.active(
            widget.language,
          ),
        ),
      );
    }
    final replacementRequestId = widget.policy.replacementRequestId;
    if (replacementRequestId == null) return null;
    return OutlinedButton.icon(
      onPressed: () => context.push(
        RoutePaths.yorksV1MaterialRequestPath(replacementRequestId),
      ),
      icon: const Icon(Icons.open_in_new_rounded),
      label: Text(
        YorksV1MaterialRequestStrings.openReplacementRequest.active(
          widget.language,
        ),
      ),
    );
  }

  Future<void> _create() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          YorksV1MaterialRequestStrings.createReplacementRequest.active(
            widget.language,
          ),
        ),
        content: Text(
          YorksV1MaterialRequestStrings.replacementRequestHelp.active(
            widget.language,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              YorksV1MaterialRequestStrings.createReplacementRequest.active(
                widget.language,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final created = await ref
          .read(yorksV1MaterialWorkflowCommandControllerProvider)
          .createReplacementMaterialRequest(
            YorksV1CreateReplacementMaterialRequestInput(
              sourceRequestId: widget.request.id,
              expectedSourceVersion: widget.request.recordVersion,
              idempotencyKey: const Uuid().v4(),
            ),
          );
      ref.invalidate(
        yorksV1MaterialRequestPhase3PolicyProvider(widget.request.id),
      );
      ref.invalidate(yorksV1MaterialRequestListProvider);
      if (!mounted) return;
      _snack(
        context,
        YorksV1MaterialRequestStrings.replacementDraftCreated.active(
          widget.language,
        ),
      );
      context.push(
        RoutePaths.yorksV1MaterialRequestDraftPath(
          created.id,
          projectId: created.projectId,
        ),
      );
    } catch (_) {
      if (mounted) {
        _snack(context, YorksV1MaterialRequestStrings.saveFailed.primary);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _MobileMaterialRequestLifecycle extends StatefulWidget {
  const _MobileMaterialRequestLifecycle({
    required this.request,
    required this.language,
    this.commentId,
    required this.primaryAction,
    required this.onPrimaryAction,
    required this.onRefresh,
    required this.approvalActions,
    required this.stickyApprovalActions,
    required this.showCancel,
    required this.onCancel,
    required this.onOpenLogistics,
    required this.onOpenDocuments,
    required this.showGenerateDeliveryOrder,
    required this.onGenerateDeliveryOrder,
    required this.documentModel,
    required this.onPdf,
    required this.onPrint,
    required this.replacementCard,
  });

  final YorksV1MaterialRequest request;
  final AppLanguage language;
  final String? commentId;
  final YorksV1MaterialRequestDetailPrimaryAction? primaryAction;
  final VoidCallback? onPrimaryAction;
  final VoidCallback onRefresh;
  final Widget? approvalActions;
  final Widget? stickyApprovalActions;
  final bool showCancel;
  final VoidCallback? onCancel;
  final VoidCallback? onOpenLogistics;
  final VoidCallback? onOpenDocuments;
  final bool showGenerateDeliveryOrder;
  final VoidCallback? onGenerateDeliveryOrder;
  final AsyncValue<YorksV1MaterialRequestDocumentModel> documentModel;
  final VoidCallback? onPdf;
  final VoidCallback? onPrint;
  final Widget? replacementCard;

  @override
  State<_MobileMaterialRequestLifecycle> createState() =>
      _MobileMaterialRequestLifecycleState();
}

class _MobileMaterialRequestLifecycleState
    extends State<_MobileMaterialRequestLifecycle> {
  bool _showFullDetails = false;

  YorksV1MaterialRequest get request => widget.request;
  AppLanguage get language => widget.language;
  String? get commentId => widget.commentId;
  YorksV1MaterialRequestDetailPrimaryAction? get primaryAction =>
      widget.primaryAction;
  VoidCallback? get onPrimaryAction => widget.onPrimaryAction;
  VoidCallback get onRefresh => widget.onRefresh;
  Widget? get approvalActions => widget.approvalActions;
  Widget? get stickyApprovalActions => widget.stickyApprovalActions;
  bool get showCancel => widget.showCancel;
  VoidCallback? get onCancel => widget.onCancel;
  VoidCallback? get onOpenLogistics => widget.onOpenLogistics;
  VoidCallback? get onOpenDocuments => widget.onOpenDocuments;
  bool get showGenerateDeliveryOrder => widget.showGenerateDeliveryOrder;
  VoidCallback? get onGenerateDeliveryOrder => widget.onGenerateDeliveryOrder;
  AsyncValue<YorksV1MaterialRequestDocumentModel> get documentModel =>
      widget.documentModel;
  VoidCallback? get onPdf => widget.onPdf;
  VoidCallback? get onPrint => widget.onPrint;
  Widget? get replacementCard => widget.replacementCard;

  @override
  Widget build(BuildContext context) {
    final title =
        request.requestNumber ??
        YorksV1MaterialRequestStrings.materialRequest.active(language);
    final requestTitle = request.title?.trim();
    final displayedTitle = requestTitle == null || requestTitle.isEmpty
        ? title
        : '$title · $requestTitle';
    final controlledModel = documentModel.valueOrNull;
    final (actionLabel, actionIcon) = _primaryActionCopy(primaryAction);
    return Directionality(
      textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.mobileSurface,
        body: ColoredBox(
          color: AppColors.mobileSurface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              YorksMobileAppBar(
                title: title,
                leading: YorksMobileIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go(RoutePaths.yorksV1MaterialRequests),
                ),
                trailing: YorksMobileIconButton(
                  icon: Icons.refresh_rounded,
                  tooltip: YorksV1MaterialRequestStrings.refresh.active(
                    language,
                  ),
                  onPressed: onRefresh,
                ),
              ),
              Expanded(
                child: ListView(
                  key: const ValueKey('mobile-mr-lifecycle'),
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 104),
                  children: [
                    Text(
                      request.projectReference.toUpperCase(),
                      style: AppTypography.eyebrow.copyWith(
                        color: AppColors.blue,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      displayedTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.headlineMedium.copyWith(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${request.projectName} · ${request.scopeName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 14),
                    YorksMobileCard(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      YorksV1MaterialRequestStrings
                                          .requestStatus
                                          .primary,
                                      style: AppTypography.labelMedium.copyWith(
                                        color: AppColors.muted,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      yorksV1MaterialRequestStateCopy(
                                        request.state,
                                      ).primary,
                                      style: AppTypography.titleMedium.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _MobileRequestStateChip(request: request),
                            ],
                          ),
                          const Divider(height: 22),
                          _MobileMrFact(
                            label: YorksV1MaterialRequestStrings
                                .currentOwner
                                .primary,
                            value: _mobileOwner(request),
                          ),
                          _MobileMrFact(
                            label: YorksV1MaterialRequestStrings
                                .nextAction
                                .primary,
                            value: _mobileNextAction(request),
                            last: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: YorksV1RequestInformationButton(
                        request: request,
                        language: language,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Semantics(
                      label: YorksV1MaterialRequestStrings.requestView.active(
                        language,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: AppSpacing.minTapTarget,
                        child: SegmentedButton<bool>(
                          key: const ValueKey('mobile-mr-detail-mode'),
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(
                              value: false,
                              icon: const Icon(
                                Icons.view_agenda_outlined,
                                size: 18,
                              ),
                              label: Text(
                                YorksV1MaterialRequestStrings.simpleView.active(
                                  language,
                                ),
                              ),
                            ),
                            ButtonSegment(
                              value: true,
                              icon: const Icon(Icons.tune_rounded, size: 18),
                              label: Text(
                                YorksV1MaterialRequestStrings.fullDetails
                                    .active(language),
                              ),
                            ),
                          ],
                          selected: {_showFullDetails},
                          onSelectionChanged: (selection) => setState(
                            () => _showFullDetails = selection.single,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      (_showFullDetails
                              ? YorksV1MaterialRequestStrings
                                    .fullDetailsDescription
                              : YorksV1MaterialRequestStrings
                                    .simpleViewDescription)
                          .active(language),
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                    _MaterialRequestPhase2CollaborationSection(
                      request: request,
                      language: language,
                      compact: true,
                    ),
                    if (replacementCard != null) ...[
                      const SizedBox(height: 10),
                      replacementCard!,
                    ],
                    if (showGenerateDeliveryOrder &&
                        primaryAction !=
                            YorksV1MaterialRequestDetailPrimaryAction
                                .generateDeliveryOrder) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          key: const ValueKey(
                            'mobile-mr-generate-delivery-order',
                          ),
                          onPressed: onGenerateDeliveryOrder,
                          icon: const Icon(Icons.receipt_long_outlined),
                          label: Text(
                            YorksV1LogisticsStrings
                                .generateDeliveryOrder
                                .primary,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    YorksMobileSectionHeader(
                      title: YorksV1MaterialRequestStrings.items.primary,
                      subtitle: YorksV1MaterialRequestStrings
                          .controlledTableDescription
                          .primary,
                    ),
                    const SizedBox(height: 10),
                    for (
                      var index = 0;
                      index < request.lines.length;
                      index++
                    ) ...[
                      _MobileMrLifecycleLineCard(
                        number: index + 1,
                        line: request.lines[index],
                        showFullDetails: _showFullDetails,
                        lifecycle: controlledModel
                            ?.lineLifecycles[request.lines[index].id],
                      ),
                      if (index != request.lines.length - 1)
                        const SizedBox(height: 10),
                    ],
                    if (_showFullDetails &&
                        controlledModel != null &&
                        (controlledModel.arrangement != null ||
                            controlledModel.approval != null ||
                            controlledModel.dispatch != null)) ...[
                      const SizedBox(height: 14),
                      _MobileMrActorHistory(model: controlledModel),
                    ],
                    if (_showFullDetails) ...[
                      const SizedBox(height: 14),
                      YorksMobileSectionHeader(
                        title: YorksV1MaterialRequestStrings.workflowTimeline
                            .active(language),
                        subtitle: YorksV1MaterialRequestStrings
                            .requestStatusDescription
                            .active(language),
                      ),
                      const SizedBox(height: 10),
                      _MobileMrLifecycleTimeline(request: request),
                      const SizedBox(height: 14),
                      _MaterialRequestDiscussion(
                        request: request,
                        compact: true,
                        highlightCommentId: commentId,
                      ),
                      const SizedBox(height: 14),
                      YorksMobileSectionHeader(
                        title: YorksV1MaterialRequestStrings.recentActivity
                            .active(language),
                      ),
                      const SizedBox(height: 10),
                      YorksMobileCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              yorksV1MaterialRequestStateCopy(
                                request.state,
                              ).active(language),
                              style: AppTypography.titleSmall.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              MaterialLocalizations.of(
                                context,
                              ).formatMediumDate(request.updatedAt.toLocal()),
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (approvalActions != null) ...[
                      const SizedBox(height: 14),
                      approvalActions!,
                    ],
                    if (_showFullDetails &&
                        (onOpenLogistics != null ||
                            onOpenDocuments != null ||
                            showCancel)) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (onOpenLogistics != null)
                            OutlinedButton.icon(
                              onPressed: onOpenLogistics,
                              icon: const Icon(
                                Icons.local_shipping_outlined,
                                size: 18,
                              ),
                              label: Text(
                                YorksV1LogisticsStrings
                                    .dispatchAndReceipt
                                    .primary,
                              ),
                            ),
                          if (onOpenDocuments != null)
                            OutlinedButton.icon(
                              onPressed: onOpenDocuments,
                              icon: const Icon(
                                Icons.folder_open_outlined,
                                size: 18,
                              ),
                              label: Text(
                                YorksV1LogisticsStrings
                                    .deliveryOrdersAndReturns
                                    .primary,
                              ),
                            ),
                          if (onPdf != null)
                            OutlinedButton.icon(
                              onPressed: onPdf,
                              icon: const YorksFileTypeIcon(
                                fileName: 'material-request.pdf',
                                size: 24,
                              ),
                              label: Text(
                                YorksV1LogisticsStrings.downloadPdf.primary,
                              ),
                            ),
                          if (onPrint != null)
                            OutlinedButton.icon(
                              onPressed: onPrint,
                              icon: const Icon(Icons.print_outlined, size: 18),
                              label: Text(
                                YorksV1LogisticsStrings.printDocument.primary,
                              ),
                            ),
                          if (showCancel)
                            OutlinedButton.icon(
                              key: const ValueKey(
                                'mobile-material-request-cancel-action',
                              ),
                              onPressed: onCancel,
                              icon: const Icon(Icons.close_rounded, size: 18),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.error,
                                backgroundColor: AppColors.surface,
                                side: const BorderSide(color: AppColors.error),
                              ),
                              label: Text(
                                YorksV1MaterialRequestStrings
                                    .cancelRequest
                                    .primary,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (stickyApprovalActions != null)
                stickyApprovalActions!
              else if (actionLabel != null)
                _MobileMrStickyActions(
                  primaryLabel: actionLabel,
                  primaryIcon: actionIcon!,
                  onPrimary: onPrimaryAction,
                ),
            ],
          ),
        ),
      ),
    );
  }

  (String?, IconData?) _primaryActionCopy(
    YorksV1MaterialRequestDetailPrimaryAction? action,
  ) => switch (action) {
    YorksV1MaterialRequestDetailPrimaryAction.arrange => (
      YorksV1MaterialRequestStrings.arrangeItems.active(language),
      Icons.inventory_2_outlined,
    ),
    YorksV1MaterialRequestDetailPrimaryAction.dispatch => (
      YorksV1LogisticsStrings.dispatchApprovedItems.active(language),
      Icons.local_shipping_outlined,
    ),
    YorksV1MaterialRequestDetailPrimaryAction.receiptReview => (
      YorksV1LogisticsStrings.reviewAndMarkReceived.active(language),
      Icons.fact_check_outlined,
    ),
    YorksV1MaterialRequestDetailPrimaryAction.close => (
      YorksV1MaterialRequestStrings.closeRequest.active(language),
      Icons.task_alt_outlined,
    ),
    YorksV1MaterialRequestDetailPrimaryAction.generateDeliveryOrder => (
      YorksV1LogisticsStrings.generateDeliveryOrder.active(language),
      Icons.receipt_long_outlined,
    ),
    null => (null, null),
  };

  String _mobileOwner(YorksV1MaterialRequest value) {
    return yorksV1MaterialRequestOwnerRoleCopy(
      value.currentActionOwnerRole,
    ).active(language);
  }

  String _mobileNextAction(YorksV1MaterialRequest value) {
    return yorksV1MaterialRequestNextActionCopy(value).active(language);
  }
}

class _MobileMrLifecycleLineCard extends StatelessWidget {
  const _MobileMrLifecycleLineCard({
    required this.number,
    required this.line,
    required this.lifecycle,
    required this.showFullDetails,
  });

  final int number;
  final YorksV1MaterialRequestLine line;
  final YorksV1MaterialRequestLineLifecycle? lifecycle;
  final bool showFullDetails;

  @override
  Widget build(BuildContext context) {
    final progress = lifecycle;
    final arrangementReason = progress?.arrangementReason;
    final requestedFact = (
      YorksV1ArrangementStrings.requested.primary,
      '${yorksV1DisplayQuantity(line.quantity)} ${line.unit}',
    );
    final facts = <(String, String)>[
      requestedFact,
      if (!showFullDetails && progress != null) ...[
        if (_isPositive(progress.goodQuantity))
          (
            YorksV1LogisticsStrings.goodReceived.primary,
            '${yorksV1DisplayQuantity(progress.goodQuantity)} ${line.unit}',
          ),
        if (_isPositive(progress.missingQuantity))
          (
            yorksV1ReceiptOutcomeCopy(YorksV1ReceiptOutcome.missing).primary,
            '${yorksV1DisplayQuantity(progress.missingQuantity)} ${line.unit}',
          ),
        if (_isPositive(progress.damagedQuantity))
          (
            yorksV1ReceiptOutcomeCopy(YorksV1ReceiptOutcome.damaged).primary,
            '${yorksV1DisplayQuantity(progress.damagedQuantity)} ${line.unit}',
          ),
        if (_isPositive(progress.returnedQuantity))
          (
            YorksV1MaterialRequestStrings.returnedQuantity.primary,
            '${yorksV1DisplayQuantity(progress.returnedQuantity)} ${line.unit}',
          ),
        (
          YorksV1LogisticsStrings.stillNeeded.primary,
          '${yorksV1DisplayQuantity(progress.stillNeededQuantity)} ${line.unit}',
        ),
      ],
      if (showFullDetails && progress != null) ...[
        (
          YorksV1ArrangementStrings.arranged.primary,
          '${yorksV1DisplayQuantity(progress.arrangedQuantity)} ${line.unit}',
        ),
        (
          YorksV1MaterialRequestStrings.approved.primary,
          '${yorksV1DisplayQuantity(progress.approvedQuantity)} ${line.unit}',
        ),
        (
          YorksV1LogisticsStrings.reserved.primary,
          '${yorksV1DisplayQuantity(progress.reservedQuantity)} ${line.unit}',
        ),
        (
          YorksV1MaterialRequestStrings.dispatchedQuantity.primary,
          '${yorksV1DisplayQuantity(progress.dispatchedQuantity)} ${line.unit}',
        ),
        (
          YorksV1LogisticsStrings.goodReceived.primary,
          '${yorksV1DisplayQuantity(progress.goodQuantity)} ${line.unit}',
        ),
        (
          yorksV1ReceiptOutcomeCopy(YorksV1ReceiptOutcome.missing).primary,
          '${yorksV1DisplayQuantity(progress.missingQuantity)} ${line.unit}',
        ),
        (
          yorksV1ReceiptOutcomeCopy(YorksV1ReceiptOutcome.damaged).primary,
          '${yorksV1DisplayQuantity(progress.damagedQuantity)} ${line.unit}',
        ),
        (
          YorksV1MaterialRequestStrings.returnedQuantity.primary,
          '${yorksV1DisplayQuantity(progress.returnedQuantity)} ${line.unit}',
        ),
        (
          YorksV1LogisticsStrings.stillNeeded.primary,
          '${yorksV1DisplayQuantity(progress.stillNeededQuantity)} ${line.unit}',
        ),
        if (YorksV1DecimalQuantity.tryParse(
              progress.replacementEligibleQuantity,
            )?.isPositive ==
            true)
          (
            YorksV1LogisticsStrings.replacementEligible.primary,
            '${yorksV1DisplayQuantity(progress.replacementEligibleQuantity)} ${line.unit}',
          ),
      ],
    ];
    return YorksMobileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$number.', style: AppTypography.titleSmall),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  line.description,
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (progress?.status.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(
              progress!.status,
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              for (final fact in facts)
                SizedBox(
                  width: 142,
                  child: _MobileMrFact(label: fact.$1, value: fact.$2),
                ),
            ],
          ),
          if (arrangementReason != null && arrangementReason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '${YorksV1ArrangementStrings.reason.primary}: $arrangementReason',
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }

  bool _isPositive(String value) =>
      YorksV1DecimalQuantity.tryParse(value)?.isPositive == true;
}

class _MobileMrActorHistory extends StatelessWidget {
  const _MobileMrActorHistory({required this.model});

  final YorksV1MaterialRequestDocumentModel model;

  @override
  Widget build(BuildContext context) => YorksMobileCard(
    child: Column(
      children: [
        if (model.arrangement != null)
          _MobileMrActorFact(
            label: YorksV1ArrangementStrings.arrangement.primary,
            actor: model.arrangement!,
          ),
        if (model.approval != null)
          _MobileMrActorFact(
            label: YorksV1MaterialRequestStrings.approved.primary,
            actor: model.approval!,
          ),
        if (model.dispatch != null)
          _MobileMrActorFact(
            label: YorksV1LogisticsStrings.dispatched.primary,
            actor: model.dispatch!,
            last: true,
          ),
      ],
    ),
  );
}

class _MobileMrActorFact extends StatelessWidget {
  const _MobileMrActorFact({
    required this.label,
    required this.actor,
    this.last = false,
  });

  final String label;
  final YorksV1MaterialRequestDocumentActor actor;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final role = actor.role.isEmpty
        ? ''
        : YorksV1ProjectStrings.roleLabel(actor.role).primary;
    final date = actor.actedAt == null
        ? ''
        : MaterialLocalizations.of(
            context,
          ).formatMediumDate(actor.actedAt!.toLocal());
    final detail = [
      if (role.isNotEmpty) role,
      if (actor.reference.isNotEmpty) actor.reference,
      if (date.isNotEmpty) date,
    ].join(' · ');
    return _MobileMrFact(
      label: label,
      value: detail.isEmpty
          ? actor.displayName
          : '${actor.displayName} · $detail',
      last: last,
    );
  }
}

class _MobileMrLifecycleTimeline extends StatelessWidget {
  const _MobileMrLifecycleTimeline({required this.request});

  final YorksV1MaterialRequest request;

  @override
  Widget build(BuildContext context) {
    final stage = _materialRequestStage(request.state);
    final labels = _materialRequestStageLabels;
    return YorksMobileCard(
      key: const ValueKey('material-request-mobile-workflow'),
      child: Column(
        children: [
          for (var index = 0; index < labels.length; index++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: index + 1 <= stage
                            ? AppColors.successContainer
                            : AppColors.surfaceContainerHigh,
                        shape: BoxShape.circle,
                      ),
                      child: index + 1 < stage
                          ? const Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: AppColors.success,
                            )
                          : Text(
                              '${index + 1}',
                              style: AppTypography.labelSmall.copyWith(
                                color: index + 1 == stage
                                    ? AppColors.blue
                                    : AppColors.muted,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                    if (index + 1 < labels.length)
                      Container(
                        width: 1,
                        height: 21,
                        color: index + 1 < stage
                            ? AppColors.success
                            : AppColors.line,
                      ),
                  ],
                ),
                const SizedBox(width: 11),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    labels[index].primary,
                    style: AppTypography.labelLarge.copyWith(
                      color: index + 1 == stage
                          ? AppColors.ink
                          : AppColors.muted,
                      fontWeight: index + 1 == stage ? FontWeight.w800 : null,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RequestApprovalActions extends ConsumerStatefulWidget {
  const _RequestApprovalActions({
    required this.request,
    required this.showEdit,
    required this.showApprove,
    required this.showReturnForChanges,
    required this.canEdit,
    required this.canApprove,
    required this.canReturnForChanges,
    this.showEditAction = true,
    this.showDecisionActions = true,
    this.mobileSticky = false,
  });

  final YorksV1MaterialRequest request;
  final bool showEdit;
  final bool showApprove;
  final bool showReturnForChanges;
  final bool canEdit;
  final bool canApprove;
  final bool canReturnForChanges;
  final bool showEditAction;
  final bool showDecisionActions;
  final bool mobileSticky;

  @override
  ConsumerState<_RequestApprovalActions> createState() =>
      _RequestApprovalActionsState();
}

class _RequestApprovalActionsState
    extends ConsumerState<_RequestApprovalActions> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      if (widget.showEditAction &&
          widget.showEdit &&
          widget.request.canEditBeforeApproval)
        _RecordActionButton(
          label: YorksV1MaterialRequestStrings.editRequest.primary,
          icon: Icons.edit_outlined,
          onPressed: _busy || !widget.canEdit
              ? null
              : () => context.push(
                  RoutePaths.yorksV1MaterialRequestDraftPath(
                    widget.request.id,
                    projectId: widget.request.projectId,
                  ),
                ),
        ),
      if (widget.showDecisionActions &&
          widget.showApprove &&
          widget.request.canDecideRequest)
        _RecordActionButton(
          label: YorksV1MaterialRequestStrings.approveForProcurement.primary,
          icon: Icons.verified_rounded,
          primary: true,
          onPressed: _busy || !widget.canApprove
              ? null
              : () => _decide(YorksV1MaterialRequestReviewDecision.approved),
        ),
      if (widget.showDecisionActions &&
          widget.showReturnForChanges &&
          widget.request.canDecideRequest)
        _RecordActionButton(
          label: YorksV1MaterialRequestStrings.returnForChanges.primary,
          icon: Icons.reply_rounded,
          onPressed: _busy || !widget.canReturnForChanges
              ? null
              : () => _decide(YorksV1MaterialRequestReviewDecision.returned),
        ),
    ];
    if (widget.mobileSticky) {
      return YorksMobileStickyActions(
        key: const ValueKey('mobile-mr-request-approval-actions'),
        summary: YorksV1MaterialRequestStrings.nextAction.primary,
        children: actions,
      );
    }
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: actions,
    );
  }

  Future<void> _decide(YorksV1MaterialRequestReviewDecision decision) async {
    String? reason;
    if (decision == YorksV1MaterialRequestReviewDecision.returned) {
      final controller = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        animationStyle: AnimationStyle.noAnimation,
        builder: (dialogContext) => AlertDialog(
          title: Text(YorksV1MaterialRequestStrings.returnForChanges.primary),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: YorksV1ArrangementStrings.returnReason.primary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(YorksV1MaterialRequestStrings.cancel.primary),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) Navigator.of(dialogContext).pop(value);
              },
              child: Text(
                YorksV1MaterialRequestStrings.returnForChanges.primary,
              ),
            ),
          ],
        ),
      );
      controller.dispose();
      if (reason == null) return;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        animationStyle: AnimationStyle.noAnimation,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            YorksV1MaterialRequestStrings.approveForProcurement.primary,
          ),
          content: Text(
            YorksV1MaterialRequestStrings.requestApprovalPrompt.primary,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(YorksV1MaterialRequestStrings.cancel.primary),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.verified_rounded),
              label: Text(
                YorksV1MaterialRequestStrings.approveForProcurement.primary,
              ),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(yorksV1MaterialWorkflowCommandControllerProvider)
          .decideMaterialRequest(
            YorksV1DecideMaterialRequestInput(
              requestId: widget.request.id,
              expectedVersion: widget.request.recordVersion,
              decision: decision,
              reason: reason,
              idempotencyKey: const Uuid().v4(),
            ),
          );
      ref.invalidate(yorksV1MaterialRequestDetailProvider(widget.request.id));
      ref.invalidate(yorksV1MaterialRequestListProvider);
    } on YorksV1DomainException catch (error) {
      if (mounted) {
        _snack(
          context,
          YorksV1MaterialRequestStrings.commandFailure(error.code).primary,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _MaterialRequestWorkAssignmentCard extends ConsumerStatefulWidget {
  const _MaterialRequestWorkAssignmentCard({
    required this.request,
    required this.language,
    this.compact = false,
  });

  final YorksV1MaterialRequest request;
  final AppLanguage language;
  final bool compact;

  @override
  ConsumerState<_MaterialRequestWorkAssignmentCard> createState() =>
      _MaterialRequestWorkAssignmentCardState();
}

class _MaterialRequestPhase2CollaborationSection extends ConsumerWidget {
  const _MaterialRequestPhase2CollaborationSection({
    required this.request,
    required this.language,
    this.compact = false,
  });

  final YorksV1MaterialRequest request;
  final AppLanguage language;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(yorksV1MaterialRequestRepositoryProvider);
    if (repository is! YorksV1MaterialRequestPhase2Repository) {
      return const SizedBox.shrink();
    }
    final assignment = ref.watch(
      yorksV1MaterialRequestWorkAssignmentProvider(request.id),
    );
    final changeSummary = ref.watch(
      yorksV1MaterialRequestChangeSummaryProvider(request.id),
    );
    final hasAssignment = assignment.valueOrNull != null;
    final hasChangeSummary = changeSummary.valueOrNull?.hasChanges ?? false;
    if (!hasAssignment && !hasChangeSummary) return const SizedBox.shrink();

    final gap = compact ? 10.0 : AppSpacing.lg;
    return Padding(
      padding: EdgeInsets.only(top: compact ? gap : 0, bottom: gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasAssignment)
            _MaterialRequestWorkAssignmentCard(
              request: request,
              language: language,
              compact: compact,
            ),
          if (hasAssignment && hasChangeSummary) SizedBox(height: gap),
          if (hasChangeSummary)
            _MaterialRequestChangeSummaryCard(
              requestId: request.id,
              language: language,
              compact: compact,
            ),
        ],
      ),
    );
  }
}

class _MaterialRequestWorkAssignmentCardState
    extends ConsumerState<_MaterialRequestWorkAssignmentCard> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(yorksV1MaterialRequestRepositoryProvider);
    if (repository is! YorksV1MaterialRequestPhase2Repository) {
      return const SizedBox.shrink();
    }
    final assignment = ref.watch(
      yorksV1MaterialRequestWorkAssignmentProvider(widget.request.id),
    );
    if (assignment.isLoading || assignment.hasError) {
      // Responsibility is an additive coordination aid. During a staggered
      // backend rollout or a temporary read failure it must not displace or
      // obstruct the authoritative Material Request workflow.
      return const SizedBox.shrink();
    }
    final content = assignment.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.blueContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: const Icon(
                  Icons.assignment_ind_outlined,
                  color: AppColors.blue,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    YorksV1ActiveText(
                      copy: YorksV1MaterialRequestStrings.coordinator,
                      language: widget.language,
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value.assigneeDisplayName ??
                          YorksV1MaterialRequestStrings.unassigned.active(
                            widget.language,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (value.assigneeExactRole != null)
                      Text(
                        _displayWorkflowRole(
                          value.assigneeExactRole,
                          widget.language,
                        ),
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    const SizedBox(height: 2),
                    YorksV1ActiveText(
                      copy: YorksV1MaterialRequestStrings.coordinatorMeaning,
                      language: widget.language,
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
          if (value.canManage) ...[
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: AppSpacing.minTapTarget,
              child: OutlinedButton.icon(
                key: ValueKey(
                  value.isAssigned
                      ? 'material-request-reassign'
                      : 'material-request-claim',
                ),
                onPressed: _saving
                    ? null
                    : value.isAssigned
                    ? () => _showReassign(value)
                    : () => _claim(value),
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        value.isAssigned
                            ? Icons.manage_accounts_outlined
                            : Icons.pan_tool_alt_outlined,
                        size: 18,
                      ),
                label: YorksV1ActiveText(
                  copy: value.isAssigned
                      ? YorksV1MaterialRequestStrings.reassign
                      : YorksV1MaterialRequestStrings.claimRequest,
                  language: widget.language,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    return RepaintBoundary(
      key: const ValueKey('material-request-work-assignment-card'),
      child: widget.compact
          ? YorksMobileCard(child: content)
          : _R35RecordSurface(child: content),
    );
  }

  Future<void> _claim(YorksV1MaterialRequestWorkAssignment current) async {
    final authUserId = ref.read(yorksV1AuthUserIdProvider);
    if (authUserId == null || authUserId.isEmpty) return;
    await _assign(
      current: current,
      assigneeAuthUserId: authUserId,
      reason: null,
    );
  }

  Future<void> _showReassign(
    YorksV1MaterialRequestWorkAssignment current,
  ) async {
    final repository = ref.read(yorksV1MaterialRequestRepositoryProvider);
    if (repository is! YorksV1MaterialRequestPhase2Repository) return;
    final phase2Repository =
        repository as YorksV1MaterialRequestPhase2Repository;
    List<YorksV1MaterialRequestMention> candidates;
    try {
      candidates = await phase2Repository.listWorkCandidates(widget.request.id);
    } catch (_) {
      if (mounted) _showAssignmentFailure();
      return;
    }
    if (!mounted || candidates.isEmpty) return;
    var selected = current.assigneeAuthUserId ?? candidates.first.authUserId;
    final reasonController = TextEditingController();
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: YorksV1ActiveText(
            copy: YorksV1MaterialRequestStrings.reassign,
            language: widget.language,
            style: AppTypography.titleLarge,
          ),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: YorksV1MaterialRequestStrings.selectAssignee
                        .active(widget.language),
                  ),
                  items: [
                    for (final candidate in candidates)
                      DropdownMenuItem(
                        value: candidate.authUserId,
                        child: Text(
                          '${candidate.displayName} · ${_displayWorkflowRole(candidate.exactRole, widget.language)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => selected = value);
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: reasonController,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: YorksV1MaterialRequestStrings.reassignmentReason
                        .active(widget.language),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: YorksV1ActiveText(
                copy: YorksV1MaterialRequestStrings.cancel,
                language: widget.language,
              ),
            ),
            FilledButton(
              onPressed: () {
                final reason = reasonController.text.trim();
                if (selected != current.assigneeAuthUserId && reason.isEmpty) {
                  return;
                }
                Navigator.of(dialogContext).pop((selected, reason));
              },
              child: YorksV1ActiveText(
                copy: YorksV1MaterialRequestStrings.reassign,
                language: widget.language,
              ),
            ),
          ],
        ),
      ),
    );
    reasonController.dispose();
    if (result == null) return;
    await _assign(
      current: current,
      assigneeAuthUserId: result.$1,
      reason: result.$2,
    );
  }

  Future<void> _assign({
    required YorksV1MaterialRequestWorkAssignment current,
    required String assigneeAuthUserId,
    required String? reason,
  }) async {
    final repository = ref.read(yorksV1MaterialRequestRepositoryProvider);
    if (repository is! YorksV1MaterialRequestPhase2Repository) return;
    final phase2Repository =
        repository as YorksV1MaterialRequestPhase2Repository;
    setState(() => _saving = true);
    try {
      await phase2Repository.assignWork(
        YorksV1AssignMaterialRequestWorkInput(
          requestId: widget.request.id,
          expectedRequestVersion: widget.request.recordVersion,
          expectedAssignmentVersion: current.assignmentVersion,
          assigneeAuthUserId: assigneeAuthUserId,
          reason: reason,
          idempotencyKey: const Uuid().v4(),
        ),
      );
      ref.invalidate(
        yorksV1MaterialRequestWorkAssignmentProvider(widget.request.id),
      );
      ref.invalidate(yorksV1MaterialRequestSummaryPageProvider);
    } catch (_) {
      if (mounted) _showAssignmentFailure();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showAssignmentFailure() => YorksAppToast.show(
    context,
    title: YorksV1MaterialRequestStrings.actionFailed.active(widget.language),
    tone: YorksAppToastTone.error,
  );
}

class _MaterialRequestChangeSummaryCard extends ConsumerWidget {
  const _MaterialRequestChangeSummaryCard({
    required this.requestId,
    required this.language,
    this.compact = false,
  });

  final String requestId;
  final AppLanguage language;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(yorksV1MaterialRequestRepositoryProvider);
    if (repository is! YorksV1MaterialRequestPhase2Repository) {
      return const SizedBox.shrink();
    }
    final summary = ref.watch(
      yorksV1MaterialRequestChangeSummaryProvider(requestId),
    );
    final value = summary.valueOrNull;
    if (value == null || !value.hasChanges) return const SizedBox.shrink();
    final changes = <TranslatableString>[
      if (value.itemsAdded > 0)
        YorksV1MaterialRequestStrings.itemsAdded(value.itemsAdded),
      if (value.itemsRemoved > 0)
        YorksV1MaterialRequestStrings.itemsRemoved(value.itemsRemoved),
      if (value.quantityOrUnitChanged > 0)
        YorksV1MaterialRequestStrings.quantitiesChanged(
          value.quantityOrUnitChanged,
        ),
      if (value.descriptionChanged > 0 ||
          value.titleChanged ||
          value.timingChanged)
        YorksV1MaterialRequestStrings.requestDetailsUpdated,
      if (value.deliveryNoteChanged)
        YorksV1MaterialRequestStrings.deliveryNoteUpdated,
    ];
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.difference_outlined, color: AppColors.blue),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: YorksV1ActiveText(
                copy: YorksV1MaterialRequestStrings.changesSinceReturn,
                language: language,
                style: AppTypography.titleSmall.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final change in changes)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.blueContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: YorksV1ActiveText(
                  copy: change,
                  language: language,
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.blue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
    return RepaintBoundary(
      key: const ValueKey('material-request-return-change-summary'),
      child: compact
          ? YorksMobileCard(child: content)
          : _R35RecordSurface(child: content),
    );
  }
}

class _MaterialRequestDiscussion extends ConsumerStatefulWidget {
  const _MaterialRequestDiscussion({
    required this.request,
    this.compact = false,
    this.highlightCommentId,
  });

  final YorksV1MaterialRequest request;
  final bool compact;
  final String? highlightCommentId;

  @override
  ConsumerState<_MaterialRequestDiscussion> createState() =>
      _MaterialRequestDiscussionState();
}

class _MaterialRequestDiscussionState
    extends ConsumerState<_MaterialRequestDiscussion> {
  final _commentController = TextEditingController();
  final _commentFocusNode = FocusNode();
  final Set<String> _mentions = {};
  final List<YorksV1PendingChatAttachment> _pendingAttachments = [];
  String? _mentionQuery;
  int? _mentionStart;
  String? _conversationId;
  YorksV1MaterialRequestComment? _replyingTo;
  String? _highlightedCommentId;
  String? _composerError;
  bool _commentPosted = false;
  bool _hasCommentBody = false;
  bool _posting = false;
  bool _uploading = false;
  late List<YorksV1MaterialRequestComment> _comments;
  late bool _hasEarlierComments;
  bool _loadingEarlierComments = false;

  @override
  void initState() {
    super.initState();
    _comments = List.of(widget.request.comments);
    _hasEarlierComments = _comments.length >= 20;
    _conversationId = _comments.firstOrNull?.conversationId;
    _commentController.addListener(_handleCommentChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealAnchor());
  }

  @override
  void didUpdateWidget(covariant _MaterialRequestDiscussion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.comments != widget.request.comments) {
      final merged =
          <String, YorksV1MaterialRequestComment>{
            for (final comment in _comments) comment.id: comment,
            for (final comment in widget.request.comments) comment.id: comment,
          }.values.toList(growable: false)..sort((a, b) {
            final byTime = a.createdAt.compareTo(b.createdAt);
            return byTime != 0 ? byTime : a.id.compareTo(b.id);
          });
      _comments = merged;
      _conversationId ??= _comments.firstOrNull?.conversationId;
    }
    if (oldWidget.highlightCommentId != widget.highlightCommentId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealAnchor());
    }
  }

  @override
  void dispose() {
    _commentController.removeListener(_handleCommentChanged);
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  void _handleCommentChanged() {
    final hasCommentBody = _commentController.text.trim().isNotEmpty;
    final selection = _commentController.selection;
    RegExpMatch? match;
    if (selection.isValid && selection.isCollapsed) {
      final cursor = selection.baseOffset;
      final before = _commentController.text.substring(0, cursor);
      match = RegExp(
        r'(^|\s)@([\p{L}\p{N}._-]*)$',
        unicode: true,
      ).firstMatch(before);
    }
    final nextQuery = match?.group(2)?.toLowerCase();
    final nextStart = match == null
        ? null
        : match.start + match.group(1)!.length;
    if (hasCommentBody == _hasCommentBody &&
        nextQuery == _mentionQuery &&
        nextStart == _mentionStart) {
      return;
    }
    setState(() {
      _hasCommentBody = hasCommentBody;
      _mentionQuery = nextQuery;
      _mentionStart = nextStart;
      if (hasCommentBody) _commentPosted = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final teamChatEnabled = ref.watch(yorksV1FeatureFlagsProvider).teamChat;
    final candidates = ref.watch(
      yorksV1MaterialRequestMentionCandidatesProvider(widget.request.id),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 640;
            final heading = Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.blueContainer,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: const Icon(
                    Icons.forum_outlined,
                    size: 18,
                    color: AppColors.blue,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    YorksV1MaterialRequestStrings.discussion.active(language),
                    style: AppTypography.titleMedium.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                  child: Text(
                    '${_comments.length}${_hasEarlierComments ? '+' : ''} ${(_comments.length == 1 ? YorksV1MaterialRequestStrings.commentSingular : AppStrings.comments).active(language).toLowerCase()}',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.inkSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            );
            final helper = Text(
              YorksV1MaterialRequestStrings.discussionDescription.active(
                language,
              ),
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            );
            final startChat = OutlinedButton.icon(
              key: const ValueKey('material-request-start-team-conversation'),
              onPressed: teamChatEnabled && !_posting
                  ? _startTeamConversation
                  : null,
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
              label: Text(
                YorksV1MaterialRequestStrings.startTeamConversation.active(
                  language,
                ),
              ),
            );
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  heading,
                  const SizedBox(height: AppSpacing.xs),
                  helper,
                  if (teamChatEnabled) ...[
                    const SizedBox(height: AppSpacing.md),
                    startChat,
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      heading,
                      const SizedBox(height: AppSpacing.xs),
                      helper,
                    ],
                  ),
                ),
                if (teamChatEnabled) ...[
                  const SizedBox(width: AppSpacing.lg),
                  startChat,
                ],
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        const Divider(height: 1),
        if (_comments.isEmpty)
          const _MaterialRequestDiscussionEmptyState()
        else ...[
          if (_hasEarlierComments)
            Center(
              child: TextButton.icon(
                key: const ValueKey('material-request-load-earlier-comments'),
                onPressed: _loadingEarlierComments
                    ? null
                    : _loadEarlierComments,
                icon: _loadingEarlierComments
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.history_rounded, size: 18),
                label: Text(
                  YorksV1MaterialRequestStrings.loadEarlierComments.active(
                    language,
                  ),
                ),
              ),
            ),
          for (var index = 0; index < _comments.length; index++) ...[
            if (index > 0) const Divider(height: 1),
            _MaterialRequestCommentCard(
              key: GlobalObjectKey(
                'material-request-comment-${_comments[index].id}',
              ),
              comment: _comments[index],
              language: language,
              request: widget.request,
              highlighted: _comments[index].id == _highlightedCommentId,
              onReply: () {
                setState(() => _replyingTo = _comments[index]);
                _focusComposer();
              },
              onOpenAttachment: _openAttachment,
            ),
          ],
        ],
        if (_comments.isNotEmpty) const Divider(height: 1),
        const SizedBox(height: AppSpacing.md),
        candidates.when(
          loading: () => _mentionQuery == null
              ? const SizedBox.shrink()
              : const LinearProgressIndicator(),
          error: (_, _) => const SizedBox.shrink(),
          data: (users) => _MentionSuggestions(
            users: users,
            query: _mentionQuery,
            onSelected: _insertMention,
          ),
        ),
        Container(
          key: const ValueKey('material-request-comment-composer'),
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            border: Border.all(color: AppColors.lineStrong),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_replyingTo != null) ...[
                Container(
                  key: const ValueKey('material-request-reply-preview'),
                  padding: const EdgeInsetsDirectional.only(
                    start: AppSpacing.sm,
                    end: AppSpacing.xxs,
                    top: AppSpacing.xs,
                    bottom: AppSpacing.xs,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.blueContainer,
                    border: BorderDirectional(
                      start: BorderSide(color: AppColors.blue, width: 3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.reply_rounded,
                        size: 18,
                        color: AppColors.blue,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          '${YorksV1MaterialRequestStrings.replyingTo.active(language)} ${_replyingTo!.authorDisplayName}: ${_replyingTo!.body}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.inkSecondary,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).closeButtonTooltip,
                        onPressed: _posting
                            ? null
                            : () => setState(() => _replyingTo = null),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              TextField(
                key: const ValueKey('material-request-comment-text'),
                controller: _commentController,
                focusNode: _commentFocusNode,
                minLines: 1,
                maxLines: 6,
                enabled: !_posting,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: YorksV1MaterialRequestStrings.commentComposerHint
                      .active(language),
                  hintStyle: AppTypography.bodySmall.copyWith(
                    color: AppColors.muted,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.xs,
                  ),
                ),
              ),
              if (_pendingAttachments.isNotEmpty || _uploading) ...[
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final attachment in _pendingAttachments)
                      _MaterialRequestAttachmentTile(
                        key: ValueKey(
                          'pending-comment-attachment-${attachment.id}',
                        ),
                        fileName: attachment.fileName,
                        mimeType: attachment.mimeType,
                        byteSize: attachment.byteSize,
                        onRemove: _posting
                            ? null
                            : () => setState(
                                () => _pendingAttachments.remove(attachment),
                              ),
                      ),
                    if (_uploading)
                      Chip(
                        avatar: const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        label: Text(
                          YorksV1MaterialRequestStrings.preparingAttachments
                              .active(language),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
              if (_composerError != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Container(
                  key: const ValueKey('material-request-comment-error'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.errorContainer,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 18,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          _composerError!,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_commentPosted) ...[
                const SizedBox(height: AppSpacing.xs),
                Container(
                  key: const ValueKey('material-request-comment-success'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.successContainer,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline_rounded,
                        size: 18,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          YorksV1MaterialRequestStrings.commentPosted.active(
                            language,
                          ),
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.onSuccessContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  IconButton(
                    key: const ValueKey('material-request-mention-action'),
                    tooltip: YorksV1MaterialRequestStrings.mentionTeammates
                        .active(language),
                    onPressed: _posting ? null : _beginMention,
                    icon: const Icon(Icons.alternate_email_rounded, size: 20),
                    color: AppColors.inkSecondary,
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(AppSpacing.minTapTarget),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('material-request-attachment-action'),
                    tooltip: teamChatEnabled
                        ? YorksV1MaterialRequestStrings.attachFiles.active(
                            language,
                          )
                        : YorksV1MaterialRequestStrings
                              .commentAttachmentsUnavailable
                              .active(language),
                    onPressed: teamChatEnabled && !_posting && !_uploading
                        ? _attachFiles
                        : null,
                    icon: const Icon(Icons.attach_file_rounded, size: 20),
                    disabledColor: AppColors.mutedLight,
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(AppSpacing.minTapTarget),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    key: const ValueKey('material-request-send-comment'),
                    onPressed: _posting || _uploading || !_hasCommentBody
                        ? null
                        : _post,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(128, AppSpacing.minTapTarget),
                      backgroundColor: AppColors.blue,
                      foregroundColor: AppColors.onPrimary,
                      disabledBackgroundColor: AppColors.blueContainerStrong,
                    ),
                    child: _posting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.onPrimary,
                            ),
                          )
                        : Text(
                            YorksV1MaterialRequestStrings.postComment.active(
                              language,
                            ),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              size: 15,
              color: AppColors.muted,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                YorksV1MaterialRequestStrings.discussionVisibility.active(
                  language,
                ),
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ),
          ],
        ),
      ],
    );
    return RepaintBoundary(
      key: const ValueKey('material-request-discussion-card'),
      child: widget.compact
          ? YorksMobileCard(child: content)
          : _R35RequestSurface(child: content),
    );
  }

  void _focusComposer() => _commentFocusNode.requestFocus();

  Future<void> _revealAnchor() async {
    final anchor = widget.highlightCommentId?.trim();
    if (!mounted || anchor == null || anchor.isEmpty) return;
    if (!_comments.any((comment) => comment.id == anchor)) {
      final repository = ref.read(yorksV1MaterialRequestRepositoryProvider);
      if (repository is YorksV1MaterialRequestPhase2Repository) {
        try {
          final phase2Repository =
              repository as YorksV1MaterialRequestPhase2Repository;
          final window = await phase2Repository.getCommentWindow(
            requestId: widget.request.id,
            commentId: anchor,
          );
          if (!mounted) return;
          setState(() {
            final merged =
                <String, YorksV1MaterialRequestComment>{
                  for (final comment in _comments) comment.id: comment,
                  for (final comment in window) comment.id: comment,
                }.values.toList(growable: false)..sort((a, b) {
                  final byTime = a.createdAt.compareTo(b.createdAt);
                  return byTime != 0 ? byTime : a.id.compareTo(b.id);
                });
            _comments = merged;
          });
        } catch (_) {
          return;
        }
      }
    }
    if (!mounted || !_comments.any((comment) => comment.id == anchor)) return;
    setState(() => _highlightedCommentId = anchor);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final target = GlobalObjectKey<State<StatefulWidget>>(
      'material-request-comment-$anchor',
    ).currentContext;
    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(
        target,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.18,
      );
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted && _highlightedCommentId == anchor) {
      setState(() => _highlightedCommentId = null);
    }
  }

  Future<void> _loadEarlierComments() async {
    if (_comments.isEmpty || _loadingEarlierComments) return;
    final repository = ref.read(yorksV1MaterialRequestRepositoryProvider);
    if (repository is! YorksV1MaterialRequestPhase2Repository) {
      setState(() => _hasEarlierComments = false);
      return;
    }
    final phase2Repository =
        repository as YorksV1MaterialRequestPhase2Repository;
    setState(() => _loadingEarlierComments = true);
    try {
      final oldest = _comments.first;
      final page = await phase2Repository.listComments(
        requestId: widget.request.id,
        beforeCreatedAt: oldest.createdAt,
        beforeId: oldest.id,
      );
      final merged =
          <String, YorksV1MaterialRequestComment>{
            for (final comment in page.items) comment.id: comment,
            for (final comment in _comments) comment.id: comment,
          }.values.toList(growable: false)..sort((a, b) {
            final byTime = a.createdAt.compareTo(b.createdAt);
            return byTime != 0 ? byTime : a.id.compareTo(b.id);
          });
      if (!mounted) return;
      setState(() {
        _comments = merged;
        _hasEarlierComments = page.hasMore;
      });
    } catch (_) {
      if (mounted) {
        YorksAppToast.show(
          context,
          title: YorksV1MaterialRequestStrings.actionFailed.active(
            ref.read(languageProvider),
          ),
          tone: YorksAppToastTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _loadingEarlierComments = false);
    }
  }

  void _beginMention() {
    _commentFocusNode.requestFocus();
    final text = _commentController.text;
    final selection = _commentController.selection;
    final cursor = selection.isValid ? selection.baseOffset : text.length;
    final prefix = cursor > 0 && !RegExp(r'\s').hasMatch(text[cursor - 1])
        ? ' @'
        : '@';
    final next = text.replaceRange(cursor, cursor, prefix);
    _commentController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: cursor + prefix.length),
    );
  }

  void _insertMention(YorksV1MaterialRequestMention user) {
    final start = _mentionStart;
    final selection = _commentController.selection;
    if (start == null || !selection.isValid) return;
    final current = _commentController.text;
    final handle = _mentionHandle(user.displayName);
    final next = current.replaceRange(start, selection.baseOffset, '@$handle ');
    final cursor = start + handle.length + 2;
    _mentions.add(user.authUserId);
    _commentController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: cursor),
    );
    setState(() {
      _mentionQuery = null;
      _mentionStart = null;
    });
  }

  Future<void> _post() async {
    final body = _commentController.text.trim();
    if (_posting || _uploading || body.isEmpty) {
      return;
    }
    setState(() {
      _posting = true;
      _composerError = null;
      _commentPosted = false;
    });
    try {
      await ref
          .read(yorksV1MaterialWorkflowCommandControllerProvider)
          .addMaterialRequestComment(
            YorksV1AddMaterialRequestCommentInput(
              requestId: widget.request.id,
              body: body,
              mentionedAuthUserIds: _mentions.toList(growable: false),
              attachmentIds: _pendingAttachments
                  .map((attachment) => attachment.id)
                  .toList(growable: false),
              parentCommentId: _replyingTo?.id,
              contextType: 'material_request',
              contextEntityId: widget.request.id,
              idempotencyKey: const Uuid().v4(),
            ),
          );
      if (!mounted) return;
      _commentController.clear();
      _mentions.clear();
      _pendingAttachments.clear();
      _replyingTo = null;
      ref.invalidate(yorksV1MaterialRequestDetailProvider(widget.request.id));
      setState(() => _commentPosted = true);
    } on YorksV1DomainException catch (error) {
      if (mounted) {
        setState(() {
          _composerError =
              '${YorksV1MaterialRequestStrings.commentNotPosted.active(ref.read(languageProvider))} ${YorksV1MaterialRequestStrings.commandFailure(error.code).active(ref.read(languageProvider))}';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _composerError = YorksV1MaterialRequestStrings.commentNotPosted
              .active(ref.read(languageProvider));
        });
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _startTeamConversation() async {
    final conversation = await ref
        .read(yorksV1TeamChatProvider.notifier)
        .createConversation(
          YorksV1ChatCreateInput(
            kind: YorksV1ChatKind.materialRequest,
            idempotencyKey: const Uuid().v4(),
            materialRequestId: widget.request.id,
          ),
        );
    if (!mounted || conversation == null) return;
    _conversationId = conversation.id;
    context.go(RoutePaths.yorksV1TeamChatPath(conversation.id));
  }

  Future<String?> _ensureConversation() async {
    if (_conversationId != null) return _conversationId;
    final conversation = await ref
        .read(yorksV1TeamChatProvider.notifier)
        .ensureMaterialRequestDiscussion(
          requestId: widget.request.id,
          idempotencyKey: const Uuid().v4(),
        );
    return _conversationId = conversation?.id;
  }

  Future<void> _attachFiles() async {
    try {
      final files = await ref
          .read(yorksV1ChatFileServiceProvider)
          .selectFiles();
      if (files.isEmpty || !mounted) return;
      if (_pendingAttachments.length + files.length > 10) {
        throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
      }
      setState(() => _uploading = true);
      final conversationId = await _ensureConversation();
      if (conversationId == null) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.backendUnavailable,
        );
      }
      final uploaded = await ref
          .read(yorksV1TeamChatProvider.notifier)
          .uploadFiles(conversationId, files);
      if (!mounted) return;
      setState(() {
        _pendingAttachments.addAll(uploaded);
        _uploading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploading = false);
      YorksAppToast.show(
        context,
        title: YorksV1TeamChatStrings.attachmentFailed.active(
          ref.read(languageProvider),
        ),
        tone: YorksAppToastTone.error,
      );
    }
  }

  Future<void> _openAttachment(YorksV1ChatAttachment attachment) async {
    try {
      final file = await ref
          .read(yorksV1TeamChatProvider.notifier)
          .downloadAttachment(attachment.id);
      if (!mounted) return;
      await ref
          .read(yorksV1ChatFileServiceProvider)
          .saveFile(
            bytes: file.bytes,
            fileName: file.fileName,
            mimeType: file.mimeType,
          );
    } catch (_) {
      if (!mounted) return;
      YorksAppToast.show(
        context,
        title: YorksV1TeamChatStrings.attachmentFailed.active(
          ref.read(languageProvider),
        ),
        tone: YorksAppToastTone.error,
      );
    }
  }
}

class _MaterialRequestCommentCard extends StatelessWidget {
  const _MaterialRequestCommentCard({
    super.key,
    required this.comment,
    required this.language,
    required this.request,
    required this.highlighted,
    required this.onReply,
    required this.onOpenAttachment,
  });

  final YorksV1MaterialRequestComment comment;
  final AppLanguage language;
  final YorksV1MaterialRequest request;
  final bool highlighted;
  final VoidCallback onReply;
  final ValueChanged<YorksV1ChatAttachment> onOpenAttachment;

  @override
  Widget build(BuildContext context) {
    final contextLabel = _contextLabel();
    final localTime = comment.createdAt.toLocal();
    final timestamp =
        '${MaterialLocalizations.of(context).formatMediumDate(localTime)}, ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(localTime))}';
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: highlighted ? AppColors.blueContainer : Colors.transparent,
        border: highlighted
            ? Border.all(color: AppColors.blue, width: 2)
            : null,
        borderRadius: highlighted
            ? BorderRadius.circular(AppSpacing.radiusMd)
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.blueContainerStrong,
            child: Text(
              comment.authorDisplayName.characters.first.toUpperCase(),
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.blue,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final author = Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpacing.xs,
                      children: [
                        Text(
                          comment.authorDisplayName,
                          style: AppTypography.labelMedium.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '· ${_displayWorkflowRole(comment.authorExactRole, language)}',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    );
                    final time = Text(
                      timestamp,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    );
                    final reply = TextButton(
                      key: ValueKey(
                        'reply-to-material-request-comment-${comment.id}',
                      ),
                      onPressed: onReply,
                      child: Text(
                        YorksV1MaterialRequestStrings.reply.active(language),
                      ),
                    );
                    if (constraints.maxWidth < 520) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          author,
                          const SizedBox(height: AppSpacing.xxs),
                          Row(
                            children: [
                              Expanded(child: time),
                              reply,
                            ],
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: author),
                        time,
                        const SizedBox(width: AppSpacing.xs),
                        reply,
                      ],
                    );
                  },
                ),
                if (comment.replyPreview != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      border: BorderDirectional(
                        start: BorderSide(color: AppColors.blue, width: 3),
                      ),
                    ),
                    child: Text(
                      '${comment.replyPreview!.senderDisplayName}: ${comment.replyPreview!.body}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.inkSecondary,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                Text(comment.body, style: AppTypography.bodyMedium),
                if (contextLabel != null || comment.attachments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        if (contextLabel != null)
                          Chip(
                            avatar: const Icon(
                              Icons.description_outlined,
                              size: 16,
                            ),
                            label: Text(contextLabel),
                            visualDensity: VisualDensity.compact,
                          ),
                        for (final attachment in comment.attachments)
                          _MaterialRequestAttachmentTile(
                            fileName: attachment.fileName,
                            mimeType: attachment.mimeType,
                            byteSize: attachment.byteSize,
                            onPressed: () => onOpenAttachment(attachment),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _contextLabel() {
    if (comment.contextType == null ||
        comment.contextType == 'material_request') {
      return null;
    }
    if (comment.contextType == 'request_line') {
      final line = request.lines
          .where((line) => line.id == comment.contextEntityId)
          .firstOrNull;
      if (line != null) {
        return '${YorksV1MaterialRequestStrings.aboutItem.active(language)} ${line.displayOrder}';
      }
    }
    return null;
  }
}

class _MaterialRequestAttachmentTile extends StatelessWidget {
  const _MaterialRequestAttachmentTile({
    super.key,
    required this.fileName,
    required this.mimeType,
    required this.byteSize,
    this.onPressed,
    this.onRemove,
  });

  final String fileName;
  final String mimeType;
  final int byteSize;
  final VoidCallback? onPressed;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      constraints: const BoxConstraints(minWidth: 168, maxWidth: 300),
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.xxs,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          YorksFileTypeIcon(fileName: fileName, mimeType: mimeType, size: 30),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.inkSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatAttachmentSize(byteSize),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (onPressed != null) ...[
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.download_rounded, size: 18, color: AppColors.blue),
          ],
          if (onRemove != null)
            IconButton(
              tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
              onPressed: onRemove,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
        ],
      ),
    );
    if (onPressed == null) return content;
    return Semantics(
      button: true,
      label: fileName,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: content,
      ),
    );
  }
}

String _formatAttachmentSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kilobytes = bytes / 1024;
  if (kilobytes < 1024) return '${kilobytes.toStringAsFixed(1)} KB';
  return '${(kilobytes / 1024).toStringAsFixed(1)} MB';
}

class _MaterialRequestDiscussionEmptyState extends StatelessWidget {
  const _MaterialRequestDiscussionEmptyState();

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('material-request-discussion-empty'),
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
    child: Column(
      children: [
        const Icon(Icons.forum_outlined, size: 44, color: AppColors.mutedLight),
        const SizedBox(height: AppSpacing.sm),
        Text(
          YorksV1MaterialRequestStrings.noComments.primary,
          textAlign: TextAlign.center,
          style: AppTypography.labelLarge.copyWith(
            color: AppColors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          YorksV1MaterialRequestStrings.startDiscussion.primary,
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        ),
      ],
    ),
  );
}

String _mentionHandle(String displayName) => displayName
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

class _MentionSuggestions extends StatelessWidget {
  const _MentionSuggestions({
    required this.users,
    required this.query,
    required this.onSelected,
  });

  final List<YorksV1MaterialRequestMention> users;
  final String? query;
  final ValueChanged<YorksV1MaterialRequestMention> onSelected;

  @override
  Widget build(BuildContext context) {
    if (query == null) return const SizedBox.shrink();
    final normalized = query!.toLowerCase();
    final matches = users
        .where((user) {
          final name = user.displayName.toLowerCase();
          return name.contains(normalized) ||
              _mentionHandle(user.displayName).contains(normalized);
        })
        .take(6)
        .toList(growable: false);
    if (matches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(
          YorksV1MaterialRequestStrings.mentionNoMatches.primary,
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.line),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var index = 0; index < matches.length; index++) ...[
              ListTile(
                dense: true,
                minTileHeight: AppSpacing.minTapTarget,
                leading: CircleAvatar(
                  radius: 15,
                  backgroundColor: AppColors.blueContainer,
                  child: Text(
                    matches[index].displayName.trim().isEmpty
                        ? '@'
                        : matches[index].displayName.trim()[0].toUpperCase(),
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.blue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                title: Text(matches[index].displayName),
                subtitle: Text(
                  '@${_mentionHandle(matches[index].displayName)}',
                ),
                onTap: () => onSelected(matches[index]),
              ),
              if (index != matches.length - 1) const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }
}

/// The submitted-request canvas follows the final R35 prototype: record
/// context and actions are separated from the immutable controlled form, and
/// the role-safe detail rail remains visible while engineers work through the
/// request.  It deliberately reads the existing server projections instead of
/// manufacturing workflow state in the widget tree.
class _RequestRecordHeader extends StatelessWidget {
  const _RequestRecordHeader({
    required this.request,
    required this.language,
    required this.onRefresh,
    required this.primaryAction,
    required this.onPrimaryAction,
    required this.onExport,
    required this.onPdf,
    required this.onPrint,
    required this.onRequestInformation,
    required this.requestInformationActive,
    this.editAction,
    required this.approvalActions,
    required this.showCancel,
    required this.onCancel,
  });

  final YorksV1MaterialRequest request;
  final AppLanguage language;
  final VoidCallback onRefresh;
  final YorksV1MaterialRequestDetailPrimaryAction? primaryAction;
  final VoidCallback? onPrimaryAction;
  final VoidCallback onExport;
  final VoidCallback? onPdf;
  final VoidCallback? onPrint;
  final VoidCallback onRequestInformation;
  final bool requestInformationActive;
  final Widget? editAction;
  final Widget? approvalActions;
  final bool showCancel;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final hasWorkflowActions =
          primaryAction != null || approvalActions != null;
      // Keep the decision group in the familiar top-right position whenever
      // the record canvas can still leave a useful title column. Supporting
      // utilities occupy their own row, so their combined width no longer
      // forces a 14-inch office layout into the stacked action treatment.
      final decisionsInline = hasWorkflowActions && constraints.maxWidth >= 760;
      final utilitiesInline = constraints.maxWidth >= 900;
      final title =
          request.requestNumber ??
          YorksV1MaterialRequestStrings.materialRequest.primary;
      final requestTitle = request.title?.trim();
      final heading = KeyedSubtree(
        key: const ValueKey('material-request-record-heading'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              request.projectReference.toUpperCase(),
              style: AppTypography.eyebrow.copyWith(
                color: AppColors.blueContainerStrong,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.35,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  requestTitle == null || requestTitle.isEmpty
                      ? title
                      : '$title · $requestTitle',
                  style: AppTypography.headlineMedium.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.65,
                  ),
                ),
                _IndustrialStageChip(
                  stage: _materialRequestStage(request.state),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${request.projectName} · ${request.scopeName}',
              style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
            ),
          ],
        ),
      );
      final workflowActions = Wrap(
        key: const ValueKey('material-request-workflow-actions'),
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        alignment: decisionsInline ? WrapAlignment.end : WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (primaryAction != null)
            _RequestPrimaryActionButton(
              action: primaryAction!,
              onPressed: onPrimaryAction,
            ),
          ?approvalActions,
        ],
      );
      final supportingActionItems = <Widget>[
        ?editAction,
        _RecordActionButton(
          label: YorksV1MaterialRequestStrings.exportExcel.primary,
          leading: const YorksFileTypeIcon(
            fileName: 'material-request.xlsx',
            size: 24,
            badgeIcon: YorksDataTransferIcons.exportData,
          ),
          onPressed: onExport,
        ),
        if (onPdf != null)
          _RecordActionButton(
            label: YorksV1MaterialRequestStrings.pdf.primary,
            leading: const YorksFileTypeIcon(
              fileName: 'material-request.pdf',
              size: 24,
            ),
            onPressed: onPdf!,
          ),
        if (onPrint != null)
          _RecordActionButton(
            label: YorksV1MaterialRequestStrings.print.primary,
            icon: Icons.print_outlined,
            onPressed: onPrint!,
          ),
        if (showCancel)
          _RecordActionButton(
            key: const ValueKey('material-request-cancel-action'),
            label: YorksV1MaterialRequestStrings.cancelRequest.active(language),
            icon: Icons.close_rounded,
            onPressed: onCancel,
            destructive: true,
          ),
        IconButton(
          tooltip: YorksV1MaterialRequestStrings.refresh.primary,
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ];
      final requestInformationAction = _RecordActionButton(
        key: const ValueKey('material-request-information-action'),
        label: YorksV1MaterialRequestStrings.requestInformation.active(
          language,
        ),
        icon: Icons.view_sidebar_outlined,
        onPressed: onRequestInformation,
        selected: requestInformationActive,
      );
      final supportingActions = Wrap(
        key: const ValueKey('material-request-supporting-actions'),
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        alignment: WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [...supportingActionItems, requestInformationAction],
      );
      final headingAndDecisions = decisionsInline
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: heading),
                const SizedBox(width: AppSpacing.xl),
                Align(
                  alignment: AlignmentDirectional.topEnd,
                  child: workflowActions,
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                if (hasWorkflowActions) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: workflowActions,
                  ),
                ],
              ],
            );
      final utilityRow = utilitiesInline
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: supportingActionItems,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                requestInformationAction,
              ],
            )
          : supportingActions;
      return Column(
        key: const ValueKey('material-request-record-header'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          headingAndDecisions,
          const SizedBox(height: AppSpacing.lg),
          utilityRow,
        ],
      );
    },
  );
}

class _RecordActionButton extends StatelessWidget {
  const _RecordActionButton({
    super.key,
    required this.label,
    this.icon,
    this.leading,
    required this.onPressed,
    this.primary = false,
    this.selected = false,
    this.destructive = false,
  }) : assert(icon != null || leading != null);

  final String label;
  final IconData? icon;
  final Widget? leading;
  final VoidCallback? onPressed;
  final bool primary;
  final bool selected;
  final bool destructive;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: AppSpacing.minTapTarget,
    child: primary
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: leading ?? Icon(icon!, size: 19),
            label: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: leading ?? Icon(icon!, size: 19),
            label: Text(label),
            style: destructive
                ? OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    backgroundColor: AppColors.surface,
                    side: const BorderSide(color: AppColors.error),
                  )
                : selected
                ? OutlinedButton.styleFrom(
                    backgroundColor: AppColors.blueContainer,
                    side: const BorderSide(
                      color: AppColors.blueContainerStrong,
                    ),
                  )
                : null,
          ),
  );
}

/// A stage-specific command stays in one predictable position in the record
/// header.  The label deliberately reflects the next permitted workflow step,
/// rather than a generic workspace name that can be mistaken for an earlier
/// stage (for example, "Procurement arrangement" after approval).
class _RequestPrimaryActionButton extends StatelessWidget {
  const _RequestPrimaryActionButton({
    required this.action,
    required this.onPressed,
  });

  final YorksV1MaterialRequestDetailPrimaryAction action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (action) {
      YorksV1MaterialRequestDetailPrimaryAction.arrange => (
        YorksV1MaterialRequestStrings.arrangeItems.primary,
        Icons.inventory_2_outlined,
      ),
      YorksV1MaterialRequestDetailPrimaryAction.dispatch => (
        YorksV1LogisticsStrings.dispatchApprovedItems.primary,
        Icons.local_shipping_outlined,
      ),
      YorksV1MaterialRequestDetailPrimaryAction.receiptReview => (
        YorksV1LogisticsStrings.reviewAndMarkReceived.primary,
        Icons.fact_check_outlined,
      ),
      YorksV1MaterialRequestDetailPrimaryAction.close => (
        YorksV1MaterialRequestStrings.closeRequest.primary,
        Icons.task_alt_outlined,
      ),
      YorksV1MaterialRequestDetailPrimaryAction.generateDeliveryOrder => (
        YorksV1LogisticsStrings.generateDeliveryOrder.primary,
        Icons.receipt_long_outlined,
      ),
    };
    return _RecordActionButton(
      label: label,
      icon: icon,
      primary: true,
      onPressed: onPressed,
    );
  }
}

/// The primary project engineer reviews the same immutable arrangement shown
/// in the request record. This keeps the next action visible without making
/// the procurement editor writable by an engineer.
class _RequestArrangementApprovalActions extends ConsumerStatefulWidget {
  const _RequestArrangementApprovalActions({
    required this.workspace,
    required this.arrangement,
  });

  final YorksV1ArrangementWorkspace workspace;
  final YorksV1ProcurementArrangement arrangement;

  @override
  ConsumerState<_RequestArrangementApprovalActions> createState() =>
      _RequestArrangementApprovalActionsState();
}

class _RequestArrangementApprovalActionsState
    extends ConsumerState<_RequestArrangementApprovalActions> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    children: [
      SizedBox(
        height: AppSpacing.minTapTarget,
        child: FilledButton.icon(
          onPressed: _busy ? null : _reviewAndApprove,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.verified_rounded, size: 19),
          label: Text(YorksV1ArrangementStrings.reviewAndApprove.primary),
        ),
      ),
      SizedBox(
        height: AppSpacing.minTapTarget,
        child: OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _decide(YorksV1ArrangementReviewDecision.returned),
          icon: const Icon(Icons.reply_rounded, size: 19),
          label: Text(YorksV1ArrangementStrings.returnToProcurement.primary),
        ),
      ),
    ],
  );

  Future<void> _reviewAndApprove() async {
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: !_busy,
      builder: (dialogContext) {
        final size = MediaQuery.sizeOf(dialogContext);
        return Dialog(
          insetPadding: const EdgeInsets.all(AppSpacing.xl),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 1120,
              maxHeight: (size.height - AppSpacing.colossal)
                  .clamp(440.0, 760.0)
                  .toDouble(),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              YorksV1ArrangementStrings
                                  .reviewAndApprove
                                  .primary,
                              style: AppTypography.titleLarge.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              '${widget.workspace.requestNumber ?? ''} · ${widget.arrangement.lines.length} ${YorksV1MaterialRequestStrings.items.primary.toLowerCase()}',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: MaterialLocalizations.of(
                          dialogContext,
                        ).closeButtonTooltip,
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppColors.blueContainer,
                            border: Border.all(
                              color: AppColors.blueContainerStrong,
                            ),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusMd,
                            ),
                          ),
                          child: Text(
                            YorksV1MaterialRequestStrings
                                .arrangementDescription
                                .primary,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        for (final line in widget.arrangement.lines) ...[
                          _ArrangementApprovalReviewLine(line: line),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text(AppStrings.cancel.primary),
                      ),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        icon: const Icon(Icons.verified_rounded, size: 19),
                        label: Text(
                          YorksV1ArrangementStrings.approveArrangement.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (approved == true && mounted) {
      await _decide(YorksV1ArrangementReviewDecision.approved);
    }
  }

  Future<void> _decide(YorksV1ArrangementReviewDecision decision) async {
    String? reason;
    if (decision == YorksV1ArrangementReviewDecision.returned) {
      reason = await _arrangementReturnReason(context);
      if (reason == null || reason.trim().isEmpty) return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(yorksV1MaterialWorkflowCommandControllerProvider)
          .decideArrangement(
            YorksV1DecideArrangementInput(
              requestId: widget.workspace.requestId,
              arrangementId: widget.arrangement.id,
              expectedRequestVersion: widget.workspace.requestRecordVersion,
              expectedArrangementVersion: widget.arrangement.recordVersion,
              decision: decision,
              reason: reason,
              idempotencyKey: const Uuid().v4(),
            ),
          );
      ref.invalidate(
        yorksV1ArrangementWorkspaceProvider(widget.workspace.requestId),
      );
      ref.invalidate(
        yorksV1MaterialRequestDetailProvider(widget.workspace.requestId),
      );
      ref.invalidate(yorksV1MaterialRequestListProvider);
      if (mounted) {
        _snack(
          context,
          decision == YorksV1ArrangementReviewDecision.approved
              ? YorksV1ArrangementStrings.approveArrangement.primary
              : YorksV1ArrangementStrings.returnToProcurement.primary,
        );
      }
    } on YorksV1DomainException catch (error) {
      if (mounted) {
        _snack(
          context,
          YorksV1MaterialRequestStrings.commandFailure(error.code).primary,
        );
      }
    } catch (_) {
      if (mounted) {
        _snack(context, YorksV1ArrangementStrings.savingFailed.primary);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ArrangementApprovalReviewLine extends StatelessWidget {
  const _ArrangementApprovalReviewLine({required this.line});

  final YorksV1ArrangementLine line;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: line.decision == YorksV1ArrangementDecision.unavailable
          ? AppColors.errorContainer
          : line.decision == YorksV1ArrangementDecision.partial
          ? AppColors.warningContainer
          : AppColors.surfaceContainerLow,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Builder(
      builder: (_) {
        final facts = [
          _ArrangementApprovalFact(
            YorksV1ArrangementStrings.decision.primary,
            line.decision == null
                ? YorksV1MaterialRequestStrings.notProvided.primary
                : yorksV1ArrangementDecisionCopy(line.decision!).primary,
          ),
          _ArrangementApprovalFact(
            YorksV1ArrangementStrings.source.primary,
            line.source == YorksV1ArrangementSource.externalSupplier
                ? (line.externalSupplier ??
                      YorksV1ArrangementStrings.externalSupplier.primary)
                : YorksV1ArrangementStrings.warehouse.primary,
          ),
          _ArrangementApprovalFact(
            YorksV1ArrangementStrings.requested.primary,
            '${yorksV1DisplayQuantity(line.requestedQuantity)} ${line.unit}',
          ),
          _ArrangementApprovalFact(
            YorksV1ArrangementStrings.arranged.primary,
            '${yorksV1DisplayQuantity(line.arrangedQuantity ?? '0')} ${line.unit}',
          ),
          if (line.reason != null && line.reason!.trim().isNotEmpty)
            _ArrangementApprovalFact(
              YorksV1ArrangementStrings.reason.primary,
              line.reason!,
            ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${line.displayOrder}. ${line.description}',
              style: AppTypography.titleSmall.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (line.brandOrigin != null && line.brandOrigin!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                line.brandOrigin!,
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.sm,
              children: facts,
            ),
          ],
        );
      },
    ),
  );
}

class _ArrangementApprovalFact extends StatelessWidget {
  const _ArrangementApprovalFact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(value, style: AppTypography.bodySmall),
      ],
    ),
  );
}

class _RequestDecisionBanner extends StatelessWidget {
  const _RequestDecisionBanner({required this.request, required this.language});

  final YorksV1MaterialRequest request;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final decision = request.requestDecision;
    final approved = decision?.decision == 'approved';
    final returned = decision?.decision == 'returned';
    final tone = approved
        ? AppColors.success
        : returned
        ? AppColors.error
        : AppColors.blue;
    final background = approved
        ? AppColors.successContainer
        : returned
        ? AppColors.errorContainer
        : AppColors.blueContainer;
    final title = approved
        ? YorksV1MaterialRequestStrings.approvedByEngineer.active(language)
        : returned
        ? YorksV1MaterialRequestStrings.changesRequested.active(language)
        : yorksV1MaterialRequestStateCopy(request.state).active(language);
    final meta = decision == null
        ? '${YorksV1MaterialRequestStrings.currentOwner.active(language)}: ${_displayWorkflowRole(request.currentActionOwnerRole, language)}'
        : [
            decision.decidedByDisplayName,
            _displayWorkflowRole(decision.decidedByExactRole, language),
            MaterialLocalizations.of(
              context,
            ).formatMediumDate(decision.decidedAt.toLocal()),
          ].join(' · ');
    final stage = _materialRequestStage(request.state);
    final visibleStage = stage > 7 ? 7 : stage;
    return Container(
      key: const ValueKey('material-request-decision-banner'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: tone,
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: background,
                shape: BoxShape.circle,
              ),
              child: Icon(
                approved
                    ? Icons.check_rounded
                    : returned
                    ? Icons.reply_rounded
                    : Icons.schedule_rounded,
                size: 19,
                color: tone,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: AppTypography.titleSmall.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    meta,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                  if (decision?.reason?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      decision!.reason!,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.inkSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const VerticalDivider(width: AppSpacing.xxl),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    YorksV1MaterialRequestStrings.stageOfSeven(
                      visibleStage,
                    ).active(language),
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.blue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    YorksV1MaterialRequestStrings.nextAction.active(language),
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    _materialRequestNextAction(request, language),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestedItemsSurface extends StatelessWidget {
  const _RequestedItemsSurface({required this.request});

  final YorksV1MaterialRequest request;

  @override
  Widget build(BuildContext context) => _R35RecordSurface(
    padding: EdgeInsets.zero,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            key: const ValueKey('material-request-items-table'),
            constraints: BoxConstraints(
              minWidth: math.max(680, constraints.maxWidth),
            ),
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              border: const TableBorder(
                horizontalInside: BorderSide(color: AppColors.line),
                verticalInside: BorderSide(color: AppColors.line),
              ),
              columnWidths: const {
                0: FixedColumnWidth(46),
                1: FlexColumnWidth(1.75),
                2: FlexColumnWidth(1.05),
                3: FlexColumnWidth(1.15),
                4: FlexColumnWidth(1.1),
                5: FixedColumnWidth(68),
                6: FixedColumnWidth(58),
              },
              children: [
                TableRow(
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                  ),
                  children: [
                    _FormalCell(
                      YorksV1MaterialRequestStrings.serialNumber.primary,
                      header: true,
                    ),
                    _FormalCell(
                      YorksV1MaterialRequestStrings.itemDescription.primary,
                      header: true,
                    ),
                    _FormalCell(
                      YorksV1MaterialRequestStrings.size.primary,
                      header: true,
                    ),
                    _FormalCell(
                      YorksV1MaterialRequestStrings.modelSerialNumber.primary,
                      header: true,
                    ),
                    _FormalCell(
                      YorksV1MaterialRequestStrings.brandOrigin.primary,
                      header: true,
                    ),
                    _FormalCell(
                      YorksV1MaterialRequestStrings.quantity.primary,
                      header: true,
                    ),
                    _FormalCell(
                      YorksV1MaterialRequestStrings.unit.primary,
                      header: true,
                    ),
                  ],
                ),
                for (var index = 0; index < request.lines.length; index++)
                  TableRow(
                    decoration: BoxDecoration(
                      color: index.isEven
                          ? AppColors.surfaceContainerLowest
                          : AppColors.surfaceContainerLow.withValues(
                              alpha: .35,
                            ),
                    ),
                    children: [
                      _FormalCell('${index + 1}'),
                      _FormalCell(request.lines[index].description),
                      _FormalCell(request.lines[index].size ?? '—'),
                      _FormalCell(
                        request.lines[index].model ??
                            request.lines[index].equipmentTag ??
                            request.lines[index].planningModelTag ??
                            '—',
                      ),
                      _FormalCell(request.lines[index].brandOrigin ?? '—'),
                      _FormalCell(
                        yorksV1DisplayQuantity(request.lines[index].quantity),
                        alignEnd: true,
                      ),
                      _FormalCell(request.lines[index].unit),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _RequestLineLifecycleLedger extends StatelessWidget {
  const _RequestLineLifecycleLedger({
    required this.request,
    required this.documentModel,
  });

  final YorksV1MaterialRequest request;
  final AsyncValue<YorksV1MaterialRequestDocumentModel> documentModel;

  @override
  Widget build(BuildContext context) => _R35RecordSurface(
    padding: EdgeInsets.zero,
    child: Material(
      type: MaterialType.transparency,
      child: ExpansionTile(
        key: const ValueKey('material-request-quantity-history'),
        initiallyExpanded: _materialRequestStage(request.state) >= 3,
        maintainState: true,
        tilePadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        leading: const Icon(Icons.bar_chart_outlined, color: AppColors.blue),
        title: Text(
          YorksV1MaterialRequestStrings.quantityHistory.primary,
          style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          YorksV1MaterialRequestStrings.lineLedgerDescription.primary,
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        ),
        children: [
          documentModel.when(
            loading: () => const _R35RecordSurface(
              child: LinearProgressIndicator(minHeight: 2),
            ),
            error: (_, _) => _R35RecordSurface(
              child: Text(
                YorksV1MaterialRequestStrings
                    .controlledDocumentUnavailable
                    .primary,
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ),
            data: (model) => _R35RecordSurface(
              padding: EdgeInsets.zero,
              child: LayoutBuilder(
                builder: (context, constraints) => Scrollbar(
                  scrollbarOrientation: ScrollbarOrientation.bottom,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      key: const ValueKey(
                        'material-request-quantity-history-table',
                      ),
                      constraints: BoxConstraints(
                        minWidth: math.max(680, constraints.maxWidth),
                      ),
                      child: Table(
                        border: TableBorder.all(color: AppColors.line),
                        columnWidths: const {
                          0: FlexColumnWidth(),
                          1: FixedColumnWidth(68),
                          2: FixedColumnWidth(64),
                          3: FixedColumnWidth(60),
                          4: FixedColumnWidth(72),
                          5: FixedColumnWidth(86),
                          6: FixedColumnWidth(54),
                          7: FixedColumnWidth(62),
                          8: FixedColumnWidth(60),
                          9: FixedColumnWidth(75),
                        },
                        children: [
                          TableRow(
                            decoration: const BoxDecoration(
                              color: AppColors.surfaceContainerHigh,
                            ),
                            children: [
                              _FormalCell(
                                YorksV1MaterialRequestStrings.item.primary,
                                header: true,
                              ),
                              _FormalCell(
                                YorksV1ArrangementStrings.requested.primary,
                                header: true,
                                alignEnd: true,
                              ),
                              _FormalCell(
                                YorksV1ArrangementStrings.arranged.primary,
                                header: true,
                                alignEnd: true,
                              ),
                              _FormalCell(
                                YorksV1LogisticsStrings.reserved.primary,
                                header: true,
                                alignEnd: true,
                              ),
                              _FormalCell(
                                YorksV1MaterialRequestStrings
                                    .dispatchedQuantity
                                    .primary,
                                header: true,
                                alignEnd: true,
                              ),
                              _FormalCell(
                                YorksV1LogisticsStrings.goodReceived.primary,
                                header: true,
                                alignEnd: true,
                              ),
                              _FormalCell(
                                yorksV1ReceiptOutcomeCopy(
                                  YorksV1ReceiptOutcome.missing,
                                ).primary,
                                header: true,
                                alignEnd: true,
                              ),
                              _FormalCell(
                                yorksV1ReceiptOutcomeCopy(
                                  YorksV1ReceiptOutcome.damaged,
                                ).primary,
                                header: true,
                                alignEnd: true,
                              ),
                              _FormalCell(
                                YorksV1MaterialRequestStrings
                                    .returnedQuantity
                                    .primary,
                                header: true,
                                alignEnd: true,
                              ),
                              _FormalCell(
                                YorksV1LogisticsStrings.stillNeeded.primary,
                                header: true,
                                alignEnd: true,
                              ),
                            ],
                          ),
                          for (final line in request.lines)
                            _lineRow(line, model.lineLifecycles[line.id]),
                        ],
                      ),
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

  TableRow _lineRow(
    YorksV1MaterialRequestLine line,
    YorksV1MaterialRequestLineLifecycle? progress,
  ) {
    String quantity(String value) =>
        '${yorksV1DisplayQuantity(value)} ${line.unit}';
    return TableRow(
      children: [
        _FormalCell(line.description, supporting: line.brandOrigin),
        _FormalCell(quantity(line.quantity), alignEnd: true),
        _FormalCell(
          quantity(progress?.arrangedQuantity ?? '0'),
          alignEnd: true,
        ),
        _FormalCell(
          quantity(progress?.reservedQuantity ?? '0'),
          alignEnd: true,
        ),
        _FormalCell(
          quantity(progress?.dispatchedQuantity ?? '0'),
          alignEnd: true,
        ),
        _FormalCell(quantity(progress?.goodQuantity ?? '0'), alignEnd: true),
        _FormalCell(quantity(progress?.missingQuantity ?? '0'), alignEnd: true),
        _FormalCell(quantity(progress?.damagedQuantity ?? '0'), alignEnd: true),
        _FormalCell(
          quantity(progress?.returnedQuantity ?? '0'),
          alignEnd: true,
        ),
        _FormalCell(
          quantity(progress?.stillNeededQuantity ?? line.quantity),
          alignEnd: true,
        ),
      ],
    );
  }
}

class _RequestRecordContent extends StatelessWidget {
  const _RequestRecordContent({
    required this.request,
    required this.language,
    required this.arrangement,
    required this.documentModel,
    required this.canOpenLogistics,
    required this.canOpenReturnsDocuments,
    required this.logisticsWorkspace,
    required this.returnsDocumentsWorkspace,
    required this.showReceiptReview,
    required this.onReviewReceipt,
    required this.showGenerateDeliveryOrder,
    required this.onGenerateDeliveryOrder,
    required this.onOpenLogistics,
    required this.onOpenReturns,
  });

  final YorksV1MaterialRequest request;
  final AppLanguage language;
  final AsyncValue<YorksV1ArrangementWorkspace?> arrangement;
  final AsyncValue<YorksV1MaterialRequestDocumentModel> documentModel;
  final bool canOpenLogistics;
  final bool canOpenReturnsDocuments;
  final YorksV1LogisticsWorkspace? logisticsWorkspace;
  final YorksV1ReturnsDocumentsWorkspace? returnsDocumentsWorkspace;
  final bool showReceiptReview;
  final ValueChanged<YorksV1MaterialDispatch>? onReviewReceipt;
  final bool showGenerateDeliveryOrder;
  final ValueChanged<YorksV1DeliveryOrderDispatch>? onGenerateDeliveryOrder;
  final VoidCallback onOpenLogistics;
  final VoidCallback onOpenReturns;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _R35RecordSectionHeading(
        title: YorksV1MaterialRequestStrings.materialItems.primary,
        description:
            YorksV1MaterialRequestStrings.controlledTableDescription.primary,
      ),
      const SizedBox(height: AppSpacing.sm),
      _RequestedItemsSurface(request: request),
      const SizedBox(height: AppSpacing.lg),
      _RequestLineLifecycleLedger(
        request: request,
        documentModel: documentModel,
      ),
      const SizedBox(height: AppSpacing.lg),
      _R35RecordSurface(
        padding: EdgeInsets.zero,
        child: Material(
          type: MaterialType.transparency,
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xs,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.md,
            ),
            leading: const Icon(
              Icons.description_outlined,
              color: AppColors.blue,
            ),
            title: Text(
              YorksV1MaterialRequestStrings.materialRequest.primary,
              style: AppTypography.titleSmall.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: Text(
              YorksV1MaterialRequestStrings
                  .controlledDocumentDescription
                  .primary,
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
            children: [
              _ControlledRequestPreview(
                request: request,
                documentModel: documentModel,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      _ProcurementDeliveryReturnsDisclosure(
        request: request,
        language: language,
        arrangement: arrangement,
        logisticsWorkspace: logisticsWorkspace,
        returnsDocumentsWorkspace: returnsDocumentsWorkspace,
        canOpenLogistics: canOpenLogistics,
        canOpenReturnsDocuments: canOpenReturnsDocuments,
        showReceiptReview: showReceiptReview,
        onReviewReceipt: onReviewReceipt,
        showGenerateDeliveryOrder: showGenerateDeliveryOrder,
        onGenerateDeliveryOrder: onGenerateDeliveryOrder,
        onOpenLogistics: onOpenLogistics,
        onOpenReturns: onOpenReturns,
      ),
    ],
  );
}

class _ProcurementDeliveryReturnsDisclosure extends StatelessWidget {
  const _ProcurementDeliveryReturnsDisclosure({
    required this.request,
    required this.language,
    required this.arrangement,
    required this.logisticsWorkspace,
    required this.returnsDocumentsWorkspace,
    required this.canOpenLogistics,
    required this.canOpenReturnsDocuments,
    required this.showReceiptReview,
    required this.onReviewReceipt,
    required this.showGenerateDeliveryOrder,
    required this.onGenerateDeliveryOrder,
    required this.onOpenLogistics,
    required this.onOpenReturns,
  });

  final YorksV1MaterialRequest request;
  final AppLanguage language;
  final AsyncValue<YorksV1ArrangementWorkspace?> arrangement;
  final YorksV1LogisticsWorkspace? logisticsWorkspace;
  final YorksV1ReturnsDocumentsWorkspace? returnsDocumentsWorkspace;
  final bool canOpenLogistics;
  final bool canOpenReturnsDocuments;
  final bool showReceiptReview;
  final ValueChanged<YorksV1MaterialDispatch>? onReviewReceipt;
  final bool showGenerateDeliveryOrder;
  final ValueChanged<YorksV1DeliveryOrderDispatch>? onGenerateDeliveryOrder;
  final VoidCallback onOpenLogistics;
  final VoidCallback onOpenReturns;

  @override
  Widget build(BuildContext context) {
    final arrangementWorkspace = arrangement.valueOrNull;
    final hasOperationalRecord =
        arrangementWorkspace?.workingArrangement != null ||
        arrangementWorkspace?.currentArrangement != null ||
        (logisticsWorkspace?.dispatches.isNotEmpty ?? false) ||
        (returnsDocumentsWorkspace?.deliveryOrderDispatches.isNotEmpty ??
            false) ||
        arrangement.hasError;
    return _R35RecordSurface(
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: KeyedSubtree(
          key: const ValueKey('material-request-operational-workflow'),
          child: ExpansionTile(
            // Recreate only this presentation tile when an asynchronously
            // loaded operational record first arrives. This makes a real
            // Delivery Order/receipt/action visible without keeping empty
            // future phases open at Steps 2 and 3.
            key: ValueKey(
              'material-request-operational-workflow-${hasOperationalRecord ? 'records' : 'empty'}',
            ),
            initiallyExpanded: hasOperationalRecord,
            maintainState: true,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xs,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            leading: const Icon(
              Icons.inventory_2_outlined,
              color: AppColors.blue,
            ),
            title: Text(
              YorksV1MaterialRequestStrings.procurementDeliveryReturns.active(
                language,
              ),
              style: AppTypography.titleSmall.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: Text(
              _materialRequestStage(request.state) < 3
                  ? YorksV1MaterialRequestStrings.procurementStartsAfterApproval
                        .active(language)
                  : _materialRequestNextAction(request, language),
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
            children: [
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),
              _OperationalWorkflowHeading(
                icon: Icons.inventory_2_outlined,
                title: YorksV1ArrangementStrings.arrangement.primary,
                description: YorksV1MaterialRequestStrings
                    .arrangementDescription
                    .primary,
              ),
              const SizedBox(height: AppSpacing.sm),
              arrangement.when(
                loading: () => const _R35RecordSurface(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: LinearProgressIndicator(),
                  ),
                ),
                error: (_, _) => _PendingWorkflowSurface(
                  icon: Icons.inventory_2_outlined,
                  title: YorksV1MaterialRequestStrings
                      .arrangementUnavailable
                      .primary,
                  description: YorksV1MaterialRequestStrings
                      .arrangementUnavailableDescription
                      .primary,
                ),
                data: (workspace) => _ArrangementSummarySurface(
                  request: request,
                  workspace: workspace,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _OperationalWorkflowHeading(
                icon: Icons.local_shipping_outlined,
                title: YorksV1LogisticsStrings.dispatchAndReceipt.primary,
                description:
                    YorksV1MaterialRequestStrings.dispatchDescription.primary,
              ),
              const SizedBox(height: AppSpacing.sm),
              _DispatchReceiptSummarySurface(
                request: request,
                workspace: logisticsWorkspace,
                canOpenLogistics: canOpenLogistics,
                onOpenLogistics: onOpenLogistics,
                showReceiptReview: showReceiptReview,
                onReviewReceipt: onReviewReceipt,
              ),
              const SizedBox(height: AppSpacing.lg),
              _OperationalWorkflowHeading(
                icon: Icons.assignment_return_outlined,
                title: YorksV1LogisticsStrings.deliveryOrdersAndReturns.primary,
                description:
                    YorksV1MaterialRequestStrings.returnsDescription.primary,
              ),
              const SizedBox(height: AppSpacing.sm),
              _DeliveryOrderSummarySurface(
                request: request,
                workspace: returnsDocumentsWorkspace,
                canOpenReturnsDocuments: canOpenReturnsDocuments,
                showGenerateDeliveryOrder: showGenerateDeliveryOrder,
                onGenerateDeliveryOrder: onGenerateDeliveryOrder,
                onOpenReturns: onOpenReturns,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps each lifecycle phase visually aligned without turning future work
/// into another oversized card. The surrounding disclosure owns expansion;
/// these headings provide a familiar Windows-style reading order inside it.
class _OperationalWorkflowHeading extends StatelessWidget {
  const _OperationalWorkflowHeading({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.blueContainer,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Icon(icon, size: 19, color: AppColors.blue),
      ),
      const SizedBox(width: AppSpacing.md),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTypography.titleSmall.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              description,
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
          ],
        ),
      ),
    ],
  );
}

class _DispatchReceiptSummarySurface extends StatelessWidget {
  const _DispatchReceiptSummarySurface({
    required this.request,
    required this.workspace,
    required this.canOpenLogistics,
    required this.onOpenLogistics,
    required this.showReceiptReview,
    required this.onReviewReceipt,
  });

  final YorksV1MaterialRequest request;
  final YorksV1LogisticsWorkspace? workspace;
  final bool canOpenLogistics;
  final VoidCallback onOpenLogistics;
  final bool showReceiptReview;
  final ValueChanged<YorksV1MaterialDispatch>? onReviewReceipt;

  @override
  Widget build(BuildContext context) {
    final dispatches =
        workspace?.dispatches ?? const <YorksV1MaterialDispatch>[];
    if (dispatches.isEmpty) {
      final ready =
          request.state == YorksV1MaterialRequestState.approved ||
          request.state == YorksV1MaterialRequestState.partiallyDispatched;
      return _PendingWorkflowSurface(
        icon: Icons.local_shipping_outlined,
        title: ready
            ? YorksV1MaterialRequestStrings.readyForDispatch.primary
            : YorksV1MaterialRequestStrings.noDispatchYet.primary,
        description: ready
            ? YorksV1MaterialRequestStrings.dispatchReadyDescription.primary
            : YorksV1MaterialRequestStrings.dispatchPendingDescription.primary,
        action: canOpenLogistics
            ? _RecordActionButton(
                label: YorksV1LogisticsStrings.dispatchAndReceipt.primary,
                icon: Icons.local_shipping_outlined,
                onPressed: onOpenLogistics,
              )
            : null,
      );
    }
    return _R35RecordSurface(
      child: Column(
        children: [
          for (var index = 0; index < dispatches.length; index++) ...[
            _DispatchReceiptRow(
              dispatch: dispatches[index],
              onReviewReceipt:
                  dispatches[index].canConfirmReceipt && showReceiptReview
                  ? onReviewReceipt == null
                        ? null
                        : () => onReviewReceipt!(dispatches[index])
                  : null,
              showReceiptReview:
                  dispatches[index].canConfirmReceipt && showReceiptReview,
            ),
            if (index != dispatches.length - 1)
              const Divider(height: AppSpacing.xxl),
          ],
        ],
      ),
    );
  }
}

class _DispatchReceiptRow extends StatelessWidget {
  const _DispatchReceiptRow({
    required this.dispatch,
    required this.showReceiptReview,
    this.onReviewReceipt,
  });

  final YorksV1MaterialDispatch dispatch;
  final bool showReceiptReview;
  final VoidCallback? onReviewReceipt;

  @override
  Widget build(BuildContext context) {
    final role = dispatch.dispatchedByRole == null
        ? null
        : YorksV1ProjectStrings.roleLabel(dispatch.dispatchedByRole!).primary;
    final meta = [
      yorksV1DispatchStateCopy(dispatch.state).primary,
      dispatch.dispatchedByDisplayName,
      if (role != null && role.isNotEmpty) role,
      if (dispatch.deliveryReference != null) dispatch.deliveryReference!,
      MaterialLocalizations.of(
        context,
      ).formatMediumDate(dispatch.dispatchedAt.toLocal()),
    ].join(' · ');
    return Row(
      children: [
        const Icon(Icons.local_shipping_outlined, color: AppColors.primary),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dispatch.number, style: AppTypography.titleSmall),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                meta,
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
        if (showReceiptReview)
          _RecordActionButton(
            label: YorksV1LogisticsStrings.reviewAndMarkReceived.primary,
            icon: Icons.fact_check_outlined,
            onPressed: onReviewReceipt,
            primary: true,
          ),
      ],
    );
  }
}

class _DeliveryOrderSummarySurface extends StatelessWidget {
  const _DeliveryOrderSummarySurface({
    required this.request,
    required this.workspace,
    required this.canOpenReturnsDocuments,
    required this.showGenerateDeliveryOrder,
    required this.onGenerateDeliveryOrder,
    required this.onOpenReturns,
  });

  final YorksV1MaterialRequest request;
  final YorksV1ReturnsDocumentsWorkspace? workspace;
  final bool canOpenReturnsDocuments;
  final bool showGenerateDeliveryOrder;
  final ValueChanged<YorksV1DeliveryOrderDispatch>? onGenerateDeliveryOrder;
  final VoidCallback onOpenReturns;

  bool get _receiptReviewed =>
      request.state == YorksV1MaterialRequestState.partiallyReceived ||
      request.state == YorksV1MaterialRequestState.received ||
      request.state == YorksV1MaterialRequestState.closed;

  @override
  Widget build(BuildContext context) {
    final dispatches =
        workspace?.deliveryOrderDispatches ??
        const <YorksV1DeliveryOrderDispatch>[];
    if (dispatches.isEmpty) {
      return _PendingWorkflowSurface(
        icon: _receiptReviewed
            ? Icons.receipt_long_outlined
            : Icons.assignment_return_outlined,
        title: _receiptReviewed
            ? YorksV1LogisticsStrings.deliveryOrderTitle.primary
            : YorksV1MaterialRequestStrings.noReturnedMaterial.primary,
        description: _receiptReviewed
            ? YorksV1MaterialRequestStrings.deliveryOrderAfterReceipt.primary
            : YorksV1MaterialRequestStrings.returnAfterReceipt.primary,
        action: _fallbackAction(),
      );
    }
    return _R35RecordSurface(
      child: Column(
        children: [
          for (var index = 0; index < dispatches.length; index++) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final dispatch = dispatches[index];
                final action = dispatch.canGenerate && showGenerateDeliveryOrder
                    ? _RecordActionButton(
                        label: YorksV1LogisticsStrings
                            .generateDeliveryOrder
                            .primary,
                        icon: Icons.receipt_long_outlined,
                        onPressed: onGenerateDeliveryOrder == null
                            ? null
                            : () => onGenerateDeliveryOrder!(dispatch),
                        primary: true,
                      )
                    : null;
                final summary = Row(
                  children: [
                    const Icon(
                      Icons.receipt_long_outlined,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dispatch.deliveryOrder?.reference ??
                                dispatch.dispatchNumber,
                            style: AppTypography.titleSmall,
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            dispatch.deliveryOrder == null
                                ? YorksV1MaterialRequestStrings
                                      .deliveryOrderAfterReceipt
                                      .primary
                                : YorksV1LogisticsStrings.deliveryOrder.primary,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                if (constraints.maxWidth < 560 && action != null) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      summary,
                      const SizedBox(height: AppSpacing.md),
                      Align(alignment: Alignment.centerLeft, child: action),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: summary),
                    if (action != null) ...[
                      const SizedBox(width: AppSpacing.md),
                      action,
                    ],
                  ],
                );
              },
            ),
            if (index != dispatches.length - 1)
              const Divider(height: AppSpacing.xxl),
          ],
        ],
      ),
    );
  }

  Widget? _fallbackAction() {
    if (!canOpenReturnsDocuments) return null;
    return _RecordActionButton(
      label: YorksV1LogisticsStrings.deliveryOrdersAndReturns.primary,
      icon: Icons.assignment_return_outlined,
      onPressed: onOpenReturns,
    );
  }
}

class _R35RecordSectionHeading extends StatelessWidget {
  const _R35RecordSectionHeading({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        description,
        style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
      ),
    ],
  );
}

class _R35RecordSurface extends StatelessWidget {
  const _R35RecordSurface({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      boxShadow: const [
        BoxShadow(
          color: AppColors.shadow,
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );
}

String _displayWorkflowRole(String? value, AppLanguage language) {
  final role = value?.trim();
  if (role == null || role.isEmpty) return '—';
  final normalized = role
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return YorksV1ProjectStrings.roleLabel(normalized).active(language);
}

class _RequestWorkflowCard extends StatelessWidget {
  const _RequestWorkflowCard({required this.request, required this.language});

  final YorksV1MaterialRequest request;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final stage = _materialRequestStage(request.state);
    return _R35RecordSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final copy = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.account_tree_outlined,
                        size: 19,
                        color: AppColors.blue,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          YorksV1MaterialRequestStrings.requestStatus.primary,
                          style: AppTypography.titleMedium.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    YorksV1MaterialRequestStrings
                        .requestStatusDescription
                        .primary,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ],
              );
              final state = _StateChip(request: request, language: language);
              if (constraints.maxWidth < 440) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    copy,
                    const SizedBox(height: AppSpacing.sm),
                    state,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: copy),
                  const SizedBox(width: AppSpacing.sm),
                  state,
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          _IndustrialWorkflowStrip(
            key: const ValueKey('material-request-workflow-strip'),
            stage: stage,
            condensed: true,
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              border: Border.all(color: AppColors.blueContainerStrong),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _ownerHeading(request),
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '${YorksV1MaterialRequestStrings.currentOwner.primary}: ${_displayWorkflowRole(request.currentActionOwnerRole, language)}',
                  style: AppTypography.bodySmall.copyWith(
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

  String _ownerHeading(YorksV1MaterialRequest value) => switch (value.state) {
    YorksV1MaterialRequestState.submitted ||
    YorksV1MaterialRequestState.awaitingRequestApproval =>
      YorksV1MaterialRequestStrings.awaitingRequestApproval.primary,
    YorksV1MaterialRequestState.changesRequested =>
      YorksV1MaterialRequestStrings.changesRequested.primary,
    YorksV1MaterialRequestState.approvedForArrangement ||
    YorksV1MaterialRequestState.arranging =>
      YorksV1MaterialRequestStrings.procurementArranging.primary,
    YorksV1MaterialRequestState.awaitingApproval =>
      YorksV1MaterialRequestStrings.waitingForApproval.primary,
    YorksV1MaterialRequestState.approved =>
      YorksV1MaterialRequestStrings.readyForDispatch.primary,
    YorksV1MaterialRequestState.partiallyDispatched ||
    YorksV1MaterialRequestState.dispatched =>
      YorksV1MaterialRequestStrings.awaitingReceipt.primary,
    YorksV1MaterialRequestState.partiallyReceived =>
      request.currentActionCode == 'receipt_review_required'
          ? YorksV1MaterialRequestStrings.awaitingReceipt.primary
          : YorksV1MaterialRequestStrings.replacementDispatchRequired.primary,
    YorksV1MaterialRequestState.received =>
      YorksV1MaterialRequestStrings.closeReviewRequired.primary,
    YorksV1MaterialRequestState.closed =>
      YorksV1MaterialRequestStrings.receiptCompleted.primary,
    YorksV1MaterialRequestState.draft =>
      YorksV1MaterialRequestStrings.draftPrivate.primary,
    YorksV1MaterialRequestState.cancelled =>
      YorksV1MaterialRequestStrings.cancelled.primary,
  };
}

class _RequestDetailsRail extends StatelessWidget {
  const _RequestDetailsRail({
    required this.request,
    required this.language,
    this.surface = true,
  });

  final YorksV1MaterialRequest request;
  final AppLanguage language;
  final bool surface;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              Icons.assignment_outlined,
              size: 19,
              color: AppColors.blue,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                YorksV1MaterialRequestStrings.requestDetails.primary,
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _RequestRailFact(
          label: YorksV1MaterialRequestStrings.requestedBy.active(language),
          value:
              '${request.requesterDisplayName ?? '—'} · ${_displayWorkflowRole(request.requesterExactRole ?? request.requesterProjectRole, language)}',
        ),
        _RequestRailFact(
          label: YorksV1MaterialRequestStrings.project.active(language),
          value: request.projectName,
        ),
        _RequestRailFact(
          label: YorksV1MaterialRequestStrings.scopeLabel.active(language),
          value: request.scopeName,
        ),
        _RequestRailFact(
          label: YorksV1MaterialRequestStrings.requiredOnSite.active(language),
          value: request.scheduledDate == null
              ? YorksV1MaterialRequestStrings.notSpecified.active(language)
              : MaterialLocalizations.of(
                  context,
                ).formatMediumDate(request.scheduledDate!.toLocal()),
        ),
      ],
    );
    return surface ? _R35RecordSurface(child: content) : content;
  }
}

Future<void> _showRequestWorkspaceInspector(
  BuildContext context, {
  required YorksV1MaterialRequest request,
  required AppLanguage language,
}) {
  final media = MediaQuery.of(context);
  final panelWidth = media.size.width * .92 < 430
      ? media.size.width * .92
      : 430.0;
  final rtl = Directionality.of(context) == TextDirection.rtl;
  return showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: AppColors.scrim.withValues(alpha: .18),
    transitionDuration: media.disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, _, _) => SafeArea(
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Material(
          key: const ValueKey('material-request-information-panel'),
          color: Colors.transparent,
          child: SizedBox(
            width: panelWidth,
            height: double.infinity,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: _RequestWorkspaceInspector(
                request: request,
                language: language,
                onClose: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (dialogContext, animation, _, child) {
      if (media.disableAnimations) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: Offset(rtl ? -0.08 : 0.08, 0),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

/// Details, request-scoped history and follow-up assignment live together in
/// the optional inspector. The panel is presentation state only: opening or
/// closing it cannot write, refresh or widen access to the request.
class _RequestWorkspaceInspector extends StatelessWidget {
  const _RequestWorkspaceInspector({
    required this.request,
    required this.language,
    required this.onClose,
  });

  final YorksV1MaterialRequest request;
  final AppLanguage language;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('material-request-workspace-inspector'),
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      boxShadow: const [
        BoxShadow(
          color: AppColors.shadow,
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.view_sidebar_outlined, color: AppColors.blue),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                YorksV1MaterialRequestStrings.requestInformation.active(
                  language,
                ),
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('material-request-inspector-close'),
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.md),
        _RequestDetailsRail(
          request: request,
          language: language,
          surface: false,
        ),
        const SizedBox(height: AppSpacing.lg),
        YorksV1MaterialRequestHistorySection(
          requestId: request.id,
          language: language,
        ),
        const SizedBox(height: AppSpacing.lg),
        _RequestWorkflowCard(request: request, language: language),
        const SizedBox(height: AppSpacing.lg),
        _MaterialRequestPhase2CollaborationSection(
          request: request,
          language: language,
          compact: true,
        ),
      ],
    ),
  );
}

class _RequestRailFact extends StatelessWidget {
  const _RequestRailFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(
            label,
            style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            value,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ControlledRequestPreview extends StatelessWidget {
  const _ControlledRequestPreview({
    required this.request,
    required this.documentModel,
  });

  final YorksV1MaterialRequest request;
  final AsyncValue<YorksV1MaterialRequestDocumentModel> documentModel;

  @override
  Widget build(BuildContext context) => _R35RecordSurface(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: SizedBox(
      key: const ValueKey('yorks-v1-controlled-material-request-preview'),
      height:
          MediaQuery.sizeOf(context).width < AppSpacing.yorksV1DesktopBreakpoint
          ? 620
          : 900,
      child: documentModel.when(
        data: (model) => PdfPreview(
          build: (_) => YorksV1MaterialRequestDocumentService()
              .buildDocumentPdf(model, PdfPageFormat.a4),
          allowPrinting: false,
          allowSharing: false,
          canChangeOrientation: false,
          canChangePageFormat: false,
          initialPageFormat: PdfPageFormat.a4,
          useActions: false,
        ),
        loading: () => const _ControlledDocumentAvailability(loading: true),
        error: (_, _) => const _ControlledDocumentAvailability(),
      ),
    ),
  );
}

class _ControlledDocumentAvailability extends StatelessWidget {
  const _ControlledDocumentAvailability({this.loading = false});

  final bool loading;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            loading ? Icons.description_outlined : Icons.sync_problem_rounded,
            color: loading ? AppColors.muted : AppColors.error,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            loading
                ? YorksV1MaterialRequestStrings
                      .controlledDocumentLoading
                      .primary
                : YorksV1MaterialRequestStrings
                      .controlledDocumentUnavailable
                      .primary,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}

class _FormalCell extends StatelessWidget {
  const _FormalCell(
    this.value, {
    this.header = false,
    this.supporting,
    this.alignEnd = false,
  });

  final String value;
  final bool header;
  final String? supporting;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final primary = Text(
      value,
      textAlign: alignEnd ? TextAlign.end : TextAlign.start,
      maxLines: header ? 1 : null,
      softWrap: !header,
      style: (header ? AppTypography.labelSmall : AppTypography.bodySmall)
          .copyWith(fontWeight: header ? FontWeight.w800 : null),
    );
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: header ? AppSpacing.xs : AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: alignEnd
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (header)
            Align(
              alignment: alignEnd
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              child: FittedBox(fit: BoxFit.scaleDown, child: primary),
            )
          else
            primary,
          if (supporting != null && supporting!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              supporting!,
              style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _ArrangementSummarySurface extends StatelessWidget {
  const _ArrangementSummarySurface({
    required this.request,
    required this.workspace,
  });

  final YorksV1MaterialRequest request;
  final YorksV1ArrangementWorkspace? workspace;

  @override
  Widget build(BuildContext context) {
    final current = workspace?.currentArrangement;
    if (current == null) {
      return _PendingWorkflowSurface(
        icon: Icons.inventory_2_outlined,
        title: YorksV1MaterialRequestStrings.notArrangedYet.primary,
        description:
            YorksV1MaterialRequestStrings.arrangementPendingDescription.primary,
      );
    }
    return _R35RecordSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 650),
              child: Table(
                border: TableBorder.all(color: AppColors.line),
                columnWidths: const {
                  0: FlexColumnWidth(2.2),
                  1: FlexColumnWidth(1),
                  2: FlexColumnWidth(1.5),
                  3: FixedColumnWidth(90),
                  4: FixedColumnWidth(94),
                },
                children: [
                  TableRow(
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                    ),
                    children: [
                      _FormalCell(
                        YorksV1MaterialRequestStrings.item.primary,
                        header: true,
                      ),
                      _FormalCell(
                        YorksV1ArrangementStrings.decision.primary,
                        header: true,
                      ),
                      _FormalCell(
                        YorksV1ArrangementStrings.source.primary,
                        header: true,
                      ),
                      _FormalCell(
                        YorksV1ArrangementStrings.requested.primary,
                        header: true,
                      ),
                      _FormalCell(
                        YorksV1ArrangementStrings.arranged.primary,
                        header: true,
                      ),
                    ],
                  ),
                  for (final line in current.lines)
                    TableRow(
                      children: [
                        _FormalCell(
                          line.description,
                          supporting: line.brandOrigin,
                        ),
                        _FormalCell(
                          line.decision == null
                              ? '—'
                              : yorksV1ArrangementDecisionCopy(
                                  line.decision!,
                                ).primary,
                        ),
                        _FormalCell(
                          line.source == YorksV1ArrangementSource.warehouse
                              ? YorksV1MaterialRequestStrings.warehouse.primary
                              : line.externalSupplier ??
                                    YorksV1MaterialRequestStrings
                                        .externalSupplier
                                        .primary,
                        ),
                        _FormalCell(
                          '${yorksV1DisplayQuantity(line.requestedQuantity)} ${line.unit}',
                          alignEnd: true,
                        ),
                        _FormalCell(
                          '${yorksV1DisplayQuantity(line.arrangedQuantity ?? '0')} ${line.unit}',
                          alignEnd: true,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.blueContainer.withValues(alpha: .58),
              border: Border.all(color: AppColors.blueContainerStrong),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Text(
              [
                '${current.lines.length} ${YorksV1MaterialRequestStrings.items.primary.toLowerCase()}',
                current.savedByDisplayName ?? current.startedByDisplayName,
                if (current.decidedByDisplayName != null)
                  current.decidedByDisplayName!,
                if (current.decidedByRole != null)
                  YorksV1ProjectStrings.roleLabel(
                    current.decidedByRole,
                  ).primary,
                if (current.decidedAt != null)
                  MaterialLocalizations.of(
                    context,
                  ).formatMediumDate(current.decidedAt!.toLocal()),
              ].join(' · '),
              style: AppTypography.bodySmall.copyWith(color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingWorkflowSurface extends StatelessWidget {
  const _PendingWorkflowSurface({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLow.withValues(alpha: .58),
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final summary = Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                border: Border.all(color: AppColors.blueContainerStrong),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Icon(icon, size: 19, color: AppColors.blueContainerStrong),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    description,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        if (compact && action != null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              summary,
              const SizedBox(height: AppSpacing.md),
              action!,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: summary),
            if (action != null) ...[
              const SizedBox(width: AppSpacing.md),
              action!,
            ],
          ],
        );
      },
    ),
  );
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.request, required this.language});

  final YorksV1MaterialRequest request;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: request.state == YorksV1MaterialRequestState.cancelled
          ? AppColors.errorContainer
          : AppColors.blueContainer,
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
    ),
    child: Text(
      yorksV1MaterialRequestStateCopy(request.state).primary,
      style: AppTypography.labelLarge,
    ),
  );
}

class _RequestError extends StatelessWidget {
  const _RequestError({required this.language, required this.onRetry});
  final AppLanguage language;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: NexusSectionCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 42,
            color: AppColors.error,
          ),
          const SizedBox(height: AppSpacing.md),
          _CopyText(
            copy: YorksV1MaterialRequestStrings.saveFailed,
            language: language,
            center: true,
          ),
          const SizedBox(height: AppSpacing.lg),
          SecondaryButton(
            label: YorksV1MaterialRequestStrings.refresh.primary,
            isExpanded: false,
            icon: Icons.refresh_rounded,
            onPressed: onRetry,
          ),
        ],
      ),
    ),
  );
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.copy, required this.language});
  final TranslatableString copy;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: _CopyText(
      copy: copy,
      language: language,
      style: AppTypography.bodyMedium.copyWith(color: AppColors.error),
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

Future<void> _addBoqRows(
  BuildContext context,
  WidgetRef ref,
  YorksV1MaterialRequestDraftController controller,
  YorksV1MaterialRequestDraft draft, {
  required AppLanguage language,
  String? projectReference,
  String? scopeName,
}) async {
  final scopeId = draft.scopeId;
  final projectId = draft.projectId;
  if (scopeId == null || projectId == null) {
    _snack(context, YorksV1MaterialRequestStrings.selectScopeToAddBoq.primary);
    return;
  }
  final repository = ref.read(yorksV1BoqRepositoryProvider);
  final worksheets = () async {
    final groups = await repository.listGroupsForScope(
      projectId,
      scopeId: scopeId,
    );
    final started =
        groups
            .where(
              (group) =>
                  !group.isArchived &&
                  group.isScopeAssigned &&
                  group.scopeId == scopeId &&
                  group.rowCount > 0,
            )
            .toList(growable: false)
          ..sort(
            (left, right) => left.displayOrder.compareTo(right.displayOrder),
          );
    return Future.wait([
      for (final group in started) repository.getWorksheet(group.id),
    ]);
  }();
  final selected = await showDialog<_BoqPickerSelection>(
    context: context,
    animationStyle: AnimationStyle.noAnimation,
    builder: (context) => _R35BoqItemPickerDialog(
      worksheets: worksheets,
      language: language,
      projectReference: projectReference,
      scopeName: scopeName,
      existingSourceRowIds: draft.lines
          .map((line) => line.sourceBoqRowId)
          .whereType<String>()
          .toSet(),
    ),
  );
  if (selected == null || selected.rowIdsByGroup.isEmpty) return;
  try {
    final loaded = await worksheets;
    for (final worksheet in loaded) {
      final rowIds = selected.rowIdsByGroup[worksheet.group.id];
      if (rowIds == null || rowIds.isEmpty) continue;
      await controller.addBoqRows(worksheet: worksheet, rowIds: rowIds);
    }
  } catch (_) {
    if (context.mounted) {
      _snack(context, YorksV1MaterialRequestStrings.saveFailed.primary);
    }
  }
}

class _BoqPickerSelection {
  const _BoqPickerSelection(this.rowIdsByGroup);

  final Map<String, Set<String>> rowIdsByGroup;
}

class _R35BoqItemPickerDialog extends StatefulWidget {
  const _R35BoqItemPickerDialog({
    required this.worksheets,
    required this.language,
    required this.existingSourceRowIds,
    this.projectReference,
    this.scopeName,
  });

  final Future<List<YorksV1BoqWorksheet>> worksheets;
  final AppLanguage language;
  final Set<String> existingSourceRowIds;
  final String? projectReference;
  final String? scopeName;

  @override
  State<_R35BoqItemPickerDialog> createState() =>
      _R35BoqItemPickerDialogState();
}

class _R35BoqItemPickerDialogState extends State<_R35BoqItemPickerDialog> {
  final Set<String> _selectedRowIds = <String>{};

  String get _scopeName {
    final value = widget.scopeName?.trim();
    return value == null || value.isEmpty
        ? YorksV1MaterialRequestStrings.scope.primary
        : value;
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1160,
          maxHeight: viewport.height - (AppSpacing.lg * 2),
        ),
        child: FutureBuilder<List<YorksV1BoqWorksheet>>(
          future: widget.worksheets,
          builder: (context, snapshot) {
            final worksheets = snapshot.data ?? const <YorksV1BoqWorksheet>[];
            final loading = snapshot.connectionState != ConnectionState.done;
            final failed = snapshot.hasError;
            return PopScope(
              canPop: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _boqPickerHeader(context),
                  const Divider(height: 1),
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : failed
                        ? _boqPickerError()
                        : _boqPickerBody(worksheets),
                  ),
                  const Divider(height: 1),
                  _boqPickerFooter(context, enabled: !loading && !failed),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _boqPickerHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.xl,
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.lg,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                YorksV1MaterialRequestStrings.addItemsFromBoq(
                  _scopeName,
                ).active(widget.language),
                style: AppTypography.headlineSmall.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                [
                  if (widget.projectReference?.trim().isNotEmpty == true)
                    widget.projectReference!.trim(),
                  _scopeName,
                  YorksV1MaterialRequestStrings.boqScopeOnly.active(
                    widget.language,
                  ),
                ].join(' · '),
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.surfaceContainerLow,
            minimumSize: const Size.square(AppSpacing.minTapTarget),
          ),
        ),
      ],
    ),
  );

  Widget _boqPickerBody(List<YorksV1BoqWorksheet> worksheets) {
    final withRows = worksheets
        .where((worksheet) => worksheet.rows.isNotEmpty)
        .toList(growable: false);
    return ListView(
      key: const ValueKey('desktop-mr-boq-picker'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _BoqPickerScopeBanner(scopeName: _scopeName, language: widget.language),
        const SizedBox(height: AppSpacing.md),
        if (withRows.isEmpty)
          _BoqPickerEmptyState(scopeName: _scopeName, language: widget.language)
        else
          for (final worksheet in withRows) ...[
            _BoqPickerWorksheetSection(
              worksheet: worksheet,
              language: widget.language,
              selectedRowIds: _selectedRowIds,
              existingSourceRowIds: widget.existingSourceRowIds,
              onChanged: _setRowSelected,
              onSelectAll: _setWorksheetSelected,
            ),
            if (worksheet != withRows.last)
              const SizedBox(height: AppSpacing.md),
          ],
      ],
    );
  }

  Widget _boqPickerError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            color: AppColors.error,
            size: 36,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            YorksV1MaterialRequestStrings.saveFailed.active(widget.language),
            textAlign: TextAlign.center,
            style: AppTypography.titleMedium.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _boqPickerFooter(BuildContext context, {required bool enabled}) =>
      Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Text(
                YorksV1MaterialRequestStrings.selectedItemCount(
                  _selectedRowIds.length,
                ).active(widget.language),
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                YorksV1MaterialRequestStrings.cancel.active(widget.language),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(
              key: const ValueKey('desktop-mr-add-selected-boq-items'),
              onPressed: enabled && _selectedRowIds.isNotEmpty
                  ? _submitSelection
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.navy,
                minimumSize: const Size(0, AppSpacing.minTapTarget),
              ),
              child: Text(
                YorksV1MaterialRequestStrings.addSelectedItems.active(
                  widget.language,
                ),
              ),
            ),
          ],
        ),
      );

  void _setRowSelected(String rowId, bool selected) => setState(() {
    if (selected) {
      _selectedRowIds.add(rowId);
    } else {
      _selectedRowIds.remove(rowId);
    }
  });

  void _setWorksheetSelected(YorksV1BoqWorksheet worksheet, bool selected) {
    final eligible = worksheet.rows
        .map((row) => row.id)
        .where((id) => !widget.existingSourceRowIds.contains(id));
    setState(() {
      if (selected) {
        _selectedRowIds.addAll(eligible);
      } else {
        _selectedRowIds.removeAll(eligible);
      }
    });
  }

  void _submitSelection() {
    final byGroup = <String, Set<String>>{};
    widget.worksheets.then((worksheets) {
      if (!mounted) return;
      for (final worksheet in worksheets) {
        final selected = worksheet.rows
            .map((row) => row.id)
            .where(_selectedRowIds.contains)
            .toSet();
        if (selected.isNotEmpty) byGroup[worksheet.group.id] = selected;
      }
      Navigator.of(context).pop(_BoqPickerSelection(byGroup));
    });
  }
}

class _BoqPickerScopeBanner extends StatelessWidget {
  const _BoqPickerScopeBanner({
    required this.scopeName,
    required this.language,
  });

  final String scopeName;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    decoration: BoxDecoration(
      color: AppColors.blueContainer.withValues(alpha: 0.55),
      border: Border.all(color: AppColors.blueContainerStrong),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                scopeName,
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                YorksV1MaterialRequestStrings.changeScopeToBrowseBoq.active(
                  language,
                ),
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              border: Border.all(color: AppColors.blueContainerStrong),
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            ),
            child: Text(
              scopeName.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.blue,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _BoqPickerEmptyState extends StatelessWidget {
  const _BoqPickerEmptyState({required this.scopeName, required this.language});

  final String scopeName;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 300,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.folder_open_outlined,
            color: AppColors.blue,
            size: 40,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            YorksV1MaterialRequestStrings.noMaterialsInBoq(
              scopeName,
            ).active(language),
            textAlign: TextAlign.center,
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(
              YorksV1MaterialRequestStrings.noBoqMaterialsHelp.active(language),
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
            ),
          ),
        ],
      ),
    ),
  );
}

class _BoqPickerWorksheetSection extends StatelessWidget {
  const _BoqPickerWorksheetSection({
    required this.worksheet,
    required this.language,
    required this.selectedRowIds,
    required this.existingSourceRowIds,
    required this.onChanged,
    required this.onSelectAll,
  });

  final YorksV1BoqWorksheet worksheet;
  final AppLanguage language;
  final Set<String> selectedRowIds;
  final Set<String> existingSourceRowIds;
  final void Function(String rowId, bool selected) onChanged;
  final void Function(YorksV1BoqWorksheet worksheet, bool selected) onSelectAll;

  @override
  Widget build(BuildContext context) {
    final eligibleIds = worksheet.rows
        .map((row) => row.id)
        .where((id) => !existingSourceRowIds.contains(id))
        .toSet();
    final selectedInWorksheet = eligibleIds.where(selectedRowIds.contains);
    final allSelected =
        eligibleIds.isNotEmpty &&
        selectedInWorksheet.length == eligibleIds.length;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${worksheet.group.displayOrder.toString().padLeft(2, '0')} · ${worksheet.group.effectiveTitle}',
                        style: AppTypography.titleMedium.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${worksheet.rows.length} ${YorksV1BoqStrings.materials.active(language)}',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Checkbox(
                  value: allSelected,
                  onChanged: eligibleIds.isEmpty
                      ? null
                      : (value) => onSelectAll(worksheet, value ?? false),
                ),
                Text(
                  YorksV1MaterialRequestStrings.selectAll.active(language),
                  style: AppTypography.labelLarge,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 1060,
              child: Table(
                columnWidths: const {
                  0: FixedColumnWidth(56),
                  1: FixedColumnWidth(380),
                  2: FixedColumnWidth(140),
                  3: FixedColumnWidth(170),
                  4: FixedColumnWidth(170),
                  5: FixedColumnWidth(72),
                  6: FixedColumnWidth(72),
                },
                border: const TableBorder(
                  horizontalInside: BorderSide(color: AppColors.line),
                ),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                    ),
                    children: [
                      const SizedBox.shrink(),
                      _BoqPickerHeaderCell(
                        YorksV1MaterialRequestStrings.itemDescription.active(
                          language,
                        ),
                      ),
                      _BoqPickerHeaderCell(
                        YorksV1MaterialRequestStrings.size.active(language),
                      ),
                      _BoqPickerHeaderCell(
                        YorksV1MaterialRequestStrings.planningModelTag.active(
                          language,
                        ),
                      ),
                      _BoqPickerHeaderCell(
                        YorksV1MaterialRequestStrings.brandOrigin.active(
                          language,
                        ),
                      ),
                      _BoqPickerHeaderCell(
                        YorksV1MaterialRequestStrings.quantity.active(language),
                      ),
                      _BoqPickerHeaderCell(
                        YorksV1MaterialRequestStrings.unit.active(language),
                      ),
                    ],
                  ),
                  for (final row in worksheet.rows) _row(context, row),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  TableRow _row(BuildContext context, YorksV1BoqRow row) {
    final alreadyAdded = existingSourceRowIds.contains(row.id);
    final selected = selectedRowIds.contains(row.id);
    final description = _boqDisplayValue(
      worksheet,
      row,
      YorksV1BoqCanonicalField.description,
    );
    return TableRow(
      decoration: BoxDecoration(
        color: alreadyAdded
            ? AppColors.surfaceContainerLow.withValues(alpha: 0.6)
            : null,
      ),
      children: [
        Center(
          child: Checkbox(
            key: ValueKey('desktop-mr-boq-row-${row.id}'),
            value: alreadyAdded || selected,
            onChanged: alreadyAdded
                ? null
                : (value) => onChanged(row.id, value ?? false),
          ),
        ),
        _BoqPickerDataCell(
          description.isEmpty ? '—' : description,
          trailing: alreadyAdded
              ? YorksV1MaterialRequestStrings.alreadyAdded.active(language)
              : null,
          emphasized: true,
        ),
        _BoqPickerDataCell(
          _boqDisplayValue(worksheet, row, YorksV1BoqCanonicalField.size),
        ),
        _BoqPickerDataCell(
          _boqDisplayValue(
            worksheet,
            row,
            YorksV1BoqCanonicalField.planningModelTag,
          ),
        ),
        _BoqPickerDataCell(
          _boqDisplayValue(
            worksheet,
            row,
            YorksV1BoqCanonicalField.brandOrigin,
          ),
        ),
        _BoqPickerDataCell(
          _boqDisplayValue(worksheet, row, YorksV1BoqCanonicalField.quantity),
          alignEnd: true,
        ),
        _BoqPickerDataCell(
          _boqDisplayValue(worksheet, row, YorksV1BoqCanonicalField.unit),
        ),
      ],
    );
  }
}

class _BoqPickerHeaderCell extends StatelessWidget {
  const _BoqPickerHeaderCell(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.sm,
    ),
    child: Text(
      label.toUpperCase(),
      style: AppTypography.labelSmall.copyWith(
        color: AppColors.muted,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      ),
    ),
  );
}

class _BoqPickerDataCell extends StatelessWidget {
  const _BoqPickerDataCell(
    this.value, {
    this.trailing,
    this.emphasized = false,
    this.alignEnd = false,
  });

  final String value;
  final String? trailing;
  final bool emphasized;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.md,
    ),
    child: Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          value.trim().isEmpty ? '—' : value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.ink,
            fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(height: 2),
          Text(
            trailing!,
            style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
          ),
        ],
      ],
    ),
  );
}

String _boqDisplayValue(
  YorksV1BoqWorksheet worksheet,
  YorksV1BoqRow row,
  YorksV1BoqCanonicalField field,
) {
  final canonical = row.canonicalValues[field.wireValue];
  if (canonical != null && '$canonical'.trim().isNotEmpty) {
    return '$canonical'.trim();
  }
  final column = worksheet.columns
      .where((item) => item.canonicalField == field)
      .firstOrNull;
  final value = column == null ? null : row.valueFor(column.id);
  return value?.toString().trim() ?? '';
}

Future<void> _importExcel(
  BuildContext context,
  WidgetRef ref,
  YorksV1MaterialRequestDraftController controller,
) async {
  try {
    final selected = await ref
        .read(yorksV1BoqWorkbookFileServiceProvider)
        .selectWorkbook();
    if (selected == null) return;
    final codec = ref.read(yorksV1BoqWorkbookCodecProvider);
    final workbook = codec.decode(
      bytes: selected.bytes,
      fileName: selected.fileName,
    );
    if (!context.mounted) return;
    final sheet = await _chooseWorkbookSheet(context, workbook);
    if (sheet == null) return;
    if (!context.mounted) return;
    final preview = codec.preview(
      workbook: workbook,
      sheet: sheet,
      fallbackTitle: selected.fileName,
    );
    final fields = <YorksV1BoqCanonicalField, int>{};
    for (final column in preview.columns) {
      final canonical = column.canonicalField;
      if (canonical != null) {
        fields.putIfAbsent(canonical, () => column.sourceIndex);
      }
    }
    final description =
        fields[YorksV1BoqCanonicalField.description] ??
        _mrFallbackDescriptionIndex(preview);
    final quantity = fields[YorksV1BoqCanonicalField.quantity];
    final unit = fields[YorksV1BoqCanonicalField.unit];
    if (description == null) {
      throw StateError('required columns');
    }
    final brand = fields[YorksV1BoqCanonicalField.brandOrigin];
    final model = fields[YorksV1BoqCanonicalField.model];
    final equipmentTag = fields[YorksV1BoqCanonicalField.equipmentTag];
    final planningModelTag = fields[YorksV1BoqCanonicalField.planningModelTag];
    final size =
        fields[YorksV1BoqCanonicalField.size] ??
        preview.columns
            .where(
              (column) => RegExp(
                r'(^|\b)(size|dimension|dimensions)(\b|$)',
                caseSensitive: false,
              ).hasMatch(column.heading.trim()),
            )
            .map((column) => column.sourceIndex)
            .firstOrNull;
    final unitCost = _mrHeaderIndex(
      preview,
      RegExp(r'unit\s*cost|cost\s*per\s*unit', caseSensitive: false),
    );
    final totalCost = _mrHeaderIndex(
      preview,
      RegExp(r'total\s*cost|amount', caseSensitive: false),
    );
    final addRows = await _previewMaterialRequestImport(
      context,
      preview: preview,
      descriptionIndex: description,
      brandIndex: brand,
      quantityIndex: quantity,
      unitIndex: unit,
      unitCostIndex: unitCost,
      totalCostIndex: totalCost,
    );
    if (!addRows || !context.mounted) return;
    // Import is an editing operation, not a submit operation. Preserve rows
    // that are incomplete (for example a draft export with an empty Qty) so
    // the engineer can correct them in the same spreadsheet editor instead
    // of silently losing the row during round-trip.
    final lines = [
      for (var index = 0; index < preview.rows.length; index++)
        (() {
          final technical = _splitExportedDescription(
            preview.rows[index].valueFor(description),
          );
          final tag = equipmentTag == null
              ? ''
              : preview.rows[index].valueFor(equipmentTag).trim();
          final explicitQuantity = quantity == null
              ? ''
              : preview.rows[index].valueFor(quantity);
          final rawModel = model == null
              ? ''
              : preview.rows[index].valueFor(model).trim();
          final contextualDescription = technical.$1.trim();
          return YorksV1MaterialRequestLine(
            id: const Uuid().v4(),
            displayOrder: index + 1,
            source: YorksV1MaterialRequestLineSource.excel,
            description: contextualDescription.isEmpty
                ? (tag.isEmpty ? 'Imported equipment' : tag)
                : _composeImportedMrDescription(tag, contextualDescription),
            brandOrigin: brand == null
                ? _mrFallbackBrandValue(preview, preview.rows[index])
                : preview.rows[index].valueFor(brand),
            size: size == null
                ? technical.$2
                : preview.rows[index].valueFor(size),
            model: rawModel.isNotEmpty
                ? rawModel
                : (tag.isNotEmpty
                      ? tag
                      : (_mrFallbackModelValue(preview, preview.rows[index]) ??
                            technical.$3)),
            equipmentTag: tag.isEmpty ? null : tag,
            planningModelTag: planningModelTag == null
                ? null
                : preview.rows[index].valueFor(planningModelTag),
            quantity: _mrInferredQuantity(
              rawQuantity: explicitQuantity,
              description: contextualDescription,
              model: rawModel.isNotEmpty ? rawModel : tag,
            ),
            quantityIsSuggested:
                explicitQuantity.trim().isEmpty && tag.isNotEmpty,
            unit: _mrInferredUnit(
              rawUnit: unit == null ? '' : preview.rows[index].valueFor(unit),
              description: technical.$1,
            ),
          );
        })(),
    ];
    await controller.addExcelLines(lines);
  } catch (_) {
    if (context.mounted) {
      _snack(context, YorksV1MaterialRequestStrings.importFailed.primary);
    }
  }
}

String _composeImportedMrDescription(String tag, String context) {
  if (tag.isEmpty || context.toLowerCase() == tag.toLowerCase()) return context;
  return '$tag — $context';
}

int? _mrFallbackDescriptionIndex(YorksV1BoqImportPreview preview) {
  final preferred = RegExp(
    r'description|item|equipment|serving\s*area|location|interlock\s*with|unit\s*ref',
    caseSensitive: false,
  );
  for (final column in preview.columns) {
    if (!preferred.hasMatch(column.heading)) continue;
    if (preview.rows.any(
      (row) => row.valueFor(column.sourceIndex).isNotEmpty,
    )) {
      return column.sourceIndex;
    }
  }
  for (final column in preview.columns) {
    if (column.canonicalField == YorksV1BoqCanonicalField.planningModelTag ||
        RegExp(
          r'tag|model|serial|qty|unit|make|brand',
          caseSensitive: false,
        ).hasMatch(column.heading)) {
      continue;
    }
    if (preview.rows.any(
      (row) => row.valueFor(column.sourceIndex).isNotEmpty,
    )) {
      return column.sourceIndex;
    }
  }
  return null;
}

String? _mrFallbackModelValue(
  YorksV1BoqImportPreview preview,
  YorksV1BoqImportRow row,
) {
  final pattern = RegExp(
    r'(^|\b)(tag|tag\s*no|equipment\s*tag|model|serial|reference|ref|s\s*no)(\b|#)',
    caseSensitive: false,
  );
  for (final column in preview.columns) {
    if (!pattern.hasMatch(column.heading)) continue;
    final value = row.valueFor(column.sourceIndex).trim();
    if (value.isNotEmpty) return value;
  }
  return null;
}

String? _mrFallbackBrandValue(
  YorksV1BoqImportPreview preview,
  YorksV1BoqImportRow row,
) {
  final pattern = RegExp(r'brand|make|manufacturer', caseSensitive: false);
  for (final column in preview.columns) {
    if (!pattern.hasMatch(column.heading)) continue;
    final value = row.valueFor(column.sourceIndex).trim();
    if (value.isNotEmpty) return value;
  }
  return null;
}

String _mrInferredQuantity({
  required String rawQuantity,
  required String description,
  required String? model,
}) {
  final value = rawQuantity.trim();
  if (value.isNotEmpty) return value;
  // Equipment schedules commonly encode grouped quantities in the item
  // description (for example "Supply Air Register - 4 Nos"). Preserve that
  // quantity instead of importing every grouped row as one.
  final embedded = RegExp(
    r'(\d+(?:\.\d+)?)\s*(?:nos?|each|pcs?|pieces?|sets?|pairs?)\b',
    caseSensitive: false,
  ).firstMatch(description);
  if (embedded != null) return embedded.group(1)!;
  // A tagged equipment row is an individually requestable item.  A blank
  // quantity is therefore safely initialised to one and remains editable.
  return model?.trim().isNotEmpty == true ? '1' : '';
}

String _mrInferredUnit({required String rawUnit, required String description}) {
  final value = rawUnit.trim();
  if (value.isNotEmpty) return _mrNormaliseUnit(value);
  final embedded = RegExp(
    r'\b(nos?|each|pcs?|pieces?|meter|metre|cm|length|sets?|pairs?|rolls?|boxes?|tons?|kg|lit(?:re|er)s?|packs?|lots?)\b',
    caseSensitive: false,
  ).firstMatch(description);
  return embedded == null ? 'Nos' : _mrNormaliseUnit(embedded.group(1)!);
}

String _mrNormaliseUnit(String value) {
  switch (value.trim().toLowerCase()) {
    case 'no':
    case 'nos':
    case 'number':
    case 'numbers':
    case 'pc':
    case 'pcs':
    case 'piece':
    case 'pieces':
      return 'Nos';
    case 'each':
      return 'Each';
    case 'm':
    case 'meter':
    case 'metre':
    case 'meters':
    case 'metres':
      return 'Meter';
    case 'cm':
      return 'Cm';
    case 'length':
      return 'Length';
    case 'set':
    case 'sets':
      return 'Set';
    case 'pair':
    case 'pairs':
      return 'Pairs';
    case 'roll':
    case 'rolls':
      return 'Roll';
    case 'box':
      return 'Box';
    case 'boxes':
      return 'Boxes';
    case 'ton':
    case 'tons':
      return 'Ton';
    case 'kg':
      return 'Kg';
    case 'litre':
    case 'litres':
    case 'liter':
    case 'liters':
      return 'Litre';
    case 'pack':
    case 'packs':
      return 'Pack';
    case 'lot':
    case 'lots':
      return 'Lot';
    default:
      return value;
  }
}

Future<bool> _previewMaterialRequestImport(
  BuildContext context, {
  required YorksV1BoqImportPreview preview,
  required int descriptionIndex,
  required int? brandIndex,
  required int? quantityIndex,
  required int? unitIndex,
  required int? unitCostIndex,
  required int? totalCostIndex,
}) async {
  final visibleRows = preview.rows.take(25).toList(growable: false);
  final mismatchedTotals = _mrTotalMismatchCount(
    preview.rows,
    quantityIndex,
    unitCostIndex,
    totalCostIndex,
  );
  final headings = [
    YorksV1MaterialRequestStrings.rowNumber.primary,
    YorksV1MaterialRequestStrings.itemDescription.primary,
    YorksV1MaterialRequestStrings.brandOrigin.primary,
    YorksV1MaterialRequestStrings.quantity.primary,
    YorksV1MaterialRequestStrings.unit.primary,
    YorksV1MaterialRequestStrings.unitCost.primary,
    YorksV1MaterialRequestStrings.totalCost.primary,
  ];
  return await showDialog<bool>(
        context: context,
        animationStyle: AnimationStyle.noAnimation,
        builder: (context) => Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xl,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980, maxHeight: 680),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          YorksV1MaterialRequestStrings.previewImport.primary,
                          style: AppTypography.titleLarge.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).closeButtonTooltip,
                        onPressed: () => Navigator.of(context).pop(false),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  Text(
                    '${preview.worksheetName} · ${preview.rows.length} ${YorksV1MaterialRequestStrings.rows.primary}',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                  if (mismatchedTotals > 0) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 17,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            YorksV1MaterialRequestStrings
                                .importCostMismatch
                                .primary,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.line),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            headingRowColor: WidgetStatePropertyAll(
                              AppColors.surfaceContainerLow,
                            ),
                            columns: [
                              for (final heading in headings)
                                DataColumn(
                                  label: Text(
                                    heading.toUpperCase(),
                                    style: AppTypography.labelSmall.copyWith(
                                      color: AppColors.muted,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                            ],
                            rows: [
                              for (
                                var rowIndex = 0;
                                rowIndex < visibleRows.length;
                                rowIndex++
                              )
                                DataRow(
                                  cells: [
                                    DataCell(Text('${rowIndex + 1}')),
                                    DataCell(
                                      SizedBox(
                                        width: 360,
                                        child: Text(
                                          visibleRows[rowIndex].valueFor(
                                            descriptionIndex,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        brandIndex == null
                                            ? ''
                                            : visibleRows[rowIndex].valueFor(
                                                brandIndex,
                                              ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        quantityIndex == null
                                            ? '1'
                                            : visibleRows[rowIndex].valueFor(
                                                quantityIndex,
                                              ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        unitIndex == null
                                            ? 'Nos'
                                            : visibleRows[rowIndex].valueFor(
                                                unitIndex,
                                              ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        unitCostIndex == null
                                            ? ''
                                            : visibleRows[rowIndex].valueFor(
                                                unitCostIndex,
                                              ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        totalCostIndex == null
                                            ? ''
                                            : visibleRows[rowIndex].valueFor(
                                                totalCostIndex,
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (preview.rows.length > visibleRows.length) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      YorksV1MaterialRequestStrings.importPreviewLimit.primary,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(
                          YorksV1MaterialRequestStrings.cancelImport.primary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(true),
                        icon: const Icon(Icons.add_rounded),
                        label: Text(
                          YorksV1MaterialRequestStrings.addImportedRows.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ) ??
      false;
}

int? _mrHeaderIndex(YorksV1BoqImportPreview preview, RegExp pattern) => preview
    .columns
    .where((column) => pattern.hasMatch(column.heading.trim()))
    .map((column) => column.sourceIndex)
    .firstOrNull;

int _mrTotalMismatchCount(
  List<YorksV1BoqImportRow> rows,
  int? quantityIndex,
  int? unitCostIndex,
  int? totalCostIndex,
) {
  if (quantityIndex == null ||
      unitCostIndex == null ||
      totalCostIndex == null) {
    return 0;
  }
  var count = 0;
  for (final row in rows) {
    final qty = double.tryParse(row.valueFor(quantityIndex));
    final unitCost = double.tryParse(row.valueFor(unitCostIndex));
    final total = double.tryParse(row.valueFor(totalCostIndex));
    if (qty == null || unitCost == null || total == null) continue;
    if ((qty * unitCost - total).abs() > 0.01) count++;
  }
  return count;
}

/// Material Request workbooks keep BOQ-only technical context in the
/// description cell. Parse that stable, human-readable suffix on re-import so
/// an exported MR can be edited and round-tripped without losing the context.
(String, String?, String?) _splitExportedDescription(String raw) {
  final lines = raw.split(RegExp(r'\r?\n'));
  if (lines.length == 1) return (raw.trim(), null, null);
  String? size;
  String? model;
  final description = <String>[];
  for (final line in lines) {
    final value = line.trim();
    if (value.toLowerCase().startsWith('size:')) {
      size = value.substring(5).trim();
    } else if (value.toLowerCase().startsWith('model / tag:')) {
      model = value.substring('model / tag:'.length).trim();
    } else if (value.isNotEmpty) {
      description.add(value);
    }
  }
  return (description.join('\n').trim(), size, model);
}

Future<YorksV1BoqWorkbookSheet?> _chooseWorkbookSheet(
  BuildContext context,
  YorksV1BoqParsedWorkbook workbook,
) => showDialog<YorksV1BoqWorkbookSheet>(
  context: context,
  animationStyle: AnimationStyle.noAnimation,
  builder: (context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.68;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 720, maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          YorksV1MaterialRequestStrings
                              .chooseEquipmentSchedule
                              .primary,
                          style: AppTypography.titleLarge.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${workbook.fileName} contains ${workbook.sheets.length} worksheets. ${YorksV1MaterialRequestStrings.worksheetImportDescription.primary}',
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
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const Divider(height: AppSpacing.xl),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisExtent: 78,
                    crossAxisSpacing: AppSpacing.sm,
                    mainAxisSpacing: AppSpacing.sm,
                  ),
                  itemCount: workbook.sheets.length,
                  itemBuilder: (context, index) {
                    final sheet = workbook.sheets[index];
                    final populated = sheet.nonEmptyRowIndexes.length;
                    return OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(sheet),
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        side: const BorderSide(color: AppColors.line),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusSm,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.table_chart_outlined, size: 19),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  sheet.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.labelLarge.copyWith(
                                    color: AppColors.ink,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '$populated ${YorksV1BoqStrings.rows.primary}',
                                  style: AppTypography.labelSmall.copyWith(
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, size: 19),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: AppSpacing.xl),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(YorksV1MaterialRequestStrings.cancel.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  },
);

Future<void> _exportDraft(
  BuildContext context,
  YorksV1BoqWorkbookFileService fileService,
  YorksV1MaterialRequestDocumentService documentService,
  YorksV1MaterialRequestDraft draft, {
  String? projectReference,
}) async {
  try {
    final saved = await fileService.saveWorkbook(
      bytes: documentService.buildDraftImportExcel(draft),
      suggestedName: documentService.suggestedDraftImportExcelName(
        draft,
        projectReference: projectReference,
      ),
    );
    if (saved && context.mounted) {
      _snack(context, YorksV1MaterialRequestStrings.saved.primary);
    }
  } catch (_) {
    if (context.mounted) {
      _snack(context, YorksV1MaterialRequestStrings.saveFailed.primary);
    }
  }
}

Future<String?> _cancelReason(BuildContext context, AppLanguage language) =>
    showDialog<String>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (context) => _CancelMaterialRequestDialog(language: language),
    );

class _CancelMaterialRequestDialog extends StatefulWidget {
  const _CancelMaterialRequestDialog({required this.language});

  final AppLanguage language;

  @override
  State<_CancelMaterialRequestDialog> createState() =>
      _CancelMaterialRequestDialogState();
}

class _CancelMaterialRequestDialogState
    extends State<_CancelMaterialRequestDialog> {
  final _reason = TextEditingController();
  bool _attempted = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _confirm() {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _attempted = true);
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) => Dialog(
    key: const ValueKey('material-request-cancel-dialog'),
    insetPadding: const EdgeInsets.all(AppSpacing.lg),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      side: const BorderSide(color: AppColors.line),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: AppSpacing.minTapTarget,
                  height: AppSpacing.minTapTarget,
                  decoration: BoxDecoration(
                    color: AppColors.errorContainer,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.cancel_outlined,
                    color: AppColors.error,
                    size: 24,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        YorksV1MaterialRequestStrings.cancelRequestQuestion
                            .active(widget.language),
                        style: AppTypography.headlineSmall.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        YorksV1MaterialRequestStrings.cancelRequestConfirmation
                            .active(widget.language),
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.errorContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.history_rounded,
                    color: AppColors.error,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      YorksV1MaterialRequestStrings.cancelRequestConsequence
                          .active(widget.language),
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.ink,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              key: const ValueKey('material-request-cancel-reason'),
              controller: _reason,
              minLines: 2,
              maxLines: 3,
              maxLength: 300,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _confirm(),
              onChanged: (_) {
                if (_attempted) setState(() {});
              },
              decoration: InputDecoration(
                labelText: YorksV1MaterialRequestStrings.cancelReason.active(
                  widget.language,
                ),
                hintText: YorksV1MaterialRequestStrings.cancelReasonHint.active(
                  widget.language,
                ),
                errorText: _attempted && _reason.text.trim().isEmpty
                    ? YorksV1MaterialRequestStrings.cancelReasonRequired.active(
                        widget.language,
                      )
                    : null,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  key: const ValueKey('material-request-cancel-keep'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    YorksV1MaterialRequestStrings.keepRequest.active(
                      widget.language,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.icon(
                  key: const ValueKey('material-request-cancel-confirm'),
                  onPressed: _confirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: AppColors.surface,
                  ),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: Text(
                    YorksV1MaterialRequestStrings.cancelRequest.active(
                      widget.language,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Future<String?> _arrangementReturnReason(BuildContext context) async {
  final text = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    animationStyle: AnimationStyle.noAnimation,
    builder: (context) => AlertDialog(
      title: Text(YorksV1ArrangementStrings.returnToProcurement.primary),
      content: TextField(
        controller: text,
        autofocus: true,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: YorksV1ArrangementStrings.returnReason.primary,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(YorksV1MaterialRequestStrings.cancel.primary),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(text.text),
          child: Text(YorksV1ArrangementStrings.returnToProcurement.primary),
        ),
      ],
    ),
  );
  text.dispose();
  return result;
}

void _snack(BuildContext context, String message) =>
    YorksAppToast.show(context, title: message);

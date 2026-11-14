import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/models/yorks_v1_permission_management.dart';
import '../../../../shared/models/yorks_v1_permission_strings.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/users_provider.dart';
import '../../../../shared/providers/yorks_v1_feature_flags_provider.dart';
import '../../../../shared/providers/yorks_v1_permission_provider.dart';
import '../widgets/yorks_v1_permission_widgets.dart';

const _immediateOpenEndedPermissionKeys = <String>{
  YorksV1CapabilityKeys.usersView,
  YorksV1CapabilityKeys.permissionsView,
  YorksV1CapabilityKeys.permissionsManage,
  YorksV1CapabilityKeys.permissionsDelegate,
};

@visibleForTesting
bool yorksV1PermissionRequiresImmediateOpenEnded(String capabilityKey) =>
    _immediateOpenEndedPermissionKeys.contains(capabilityKey);

/// The client-side projection of the server's delegation ceiling. The server
/// remains authoritative, but this keeps the editor from presenting scopes or
/// projects that the current actor cannot administer.
@visibleForTesting
class YorksV1DelegableScopeContext {
  const YorksV1DelegableScopeContext({
    required this.allowedScopes,
    required this.projects,
  });

  const YorksV1DelegableScopeContext.empty()
    : allowedScopes = const <YorksV1PermissionScopeKind>{},
      projects = const <YorksV1PermissionProjectAccess>[];

  final Set<YorksV1PermissionScopeKind> allowedScopes;
  final List<YorksV1PermissionProjectAccess> projects;

  bool allows(YorksV1PermissionScope scope) {
    if (!allowedScopes.contains(scope.kind)) return false;
    if (scope.kind == YorksV1PermissionScopeKind.organization) return true;
    final projectIds = projects.map((project) => project.projectId).toSet();
    return scope.projectIds.every(projectIds.contains);
  }
}

@visibleForTesting
YorksV1DelegableScopeContext yorksV1DelegableScopeContext({
  required YorksV1PermissionCapabilityAccess access,
  required Iterable<YorksV1PermissionProjectAccess> targetProjects,
  required Iterable<YorksV1PermissionProjectAccess> actorProjects,
}) {
  if (!access.canEdit) return const YorksV1DelegableScopeContext.empty();

  final allowedScopes = access.actorDelegableScopes
      .intersection(access.catalog.allowedScopes)
      .toSet();
  final actorProjectIds = actorProjects
      .where((project) => project.hasAccess)
      .map((project) => project.projectId)
      .toSet();
  final projects = allowedScopes.contains(YorksV1PermissionScopeKind.project)
      ? targetProjects
            .where(
              (project) =>
                  project.hasAccess &&
                  actorProjectIds.contains(project.projectId),
            )
            .toList(growable: false)
      : const <YorksV1PermissionProjectAccess>[];
  if (projects.isEmpty) {
    allowedScopes.remove(YorksV1PermissionScopeKind.project);
  }
  if (allowedScopes.isEmpty) {
    return const YorksV1DelegableScopeContext.empty();
  }
  return YorksV1DelegableScopeContext(
    allowedScopes: Set.unmodifiable(allowedScopes),
    projects: List.unmodifiable(projects),
  );
}

class _PermissionDependencyExpansion {
  const _PermissionDependencyExpansion({
    required this.changes,
    this.unavailableDependencyKey,
  });

  final List<_StagedPermissionChange> changes;
  final String? unavailableDependencyKey;

  bool get isComplete => unavailableDependencyKey == null;
}

/// Expands a reviewed grant with the catalogue-declared prerequisites that
/// are not already effective for the same scope. Generated rows remain
/// visible in the review dialog; the client never silently widens authority.
_PermissionDependencyExpansion _expandPermissionDependencies({
  required Iterable<_StagedPermissionChange> drafts,
  required YorksV1UserPermissionWorkspace workspace,
}) {
  final catalog = {
    for (final access in workspace.catalog) access.catalog.key: access,
  };
  final expanded = <String, _StagedPermissionChange>{
    for (final draft in drafts) draft.change.identity: draft,
  };
  String? unavailable;
  final processing = <String>{};

  bool effectiveForScope(
    YorksV1PermissionCapabilityAccess access,
    YorksV1PermissionScope scope,
  ) => switch (scope.kind) {
    YorksV1PermissionScopeKind.organization =>
      access.authoritativeEffective == true,
    YorksV1PermissionScopeKind.project => scope.projectIds.every(
      access.authoritativeEffectiveForProject,
    ),
  };

  void ensureDependencies(_StagedPermissionChange parent) {
    if (unavailable != null ||
        parent.change.operation != YorksV1PermissionChangeOperation.set ||
        parent.change.effect != YorksV1PermissionAssignmentEffect.grant) {
      return;
    }
    final scope = parent.change.scope!;
    final processKey =
        '${parent.capabilityKey}:${scope.kind.wireValue}:'
        '${scope.projectIds.join(',')}';
    if (!processing.add(processKey)) return;
    final parentAccess = catalog[parent.capabilityKey];
    if (parentAccess == null) {
      unavailable = parent.capabilityKey;
      return;
    }
    for (final dependencyKey in parentAccess.catalog.dependencies) {
      final dependencyAccess = catalog[dependencyKey];
      if (dependencyAccess == null) {
        unavailable = dependencyKey;
        return;
      }
      final dependencyCleared = expanded.values.any(
        (draft) =>
            draft.capabilityKey == dependencyKey &&
            draft.change.operation == YorksV1PermissionChangeOperation.clear,
      );
      final identity = [
        YorksV1PermissionChangeOperation.set.wireValue,
        dependencyKey,
        scope.kind.wireValue,
      ].join(':');
      final existing = expanded[identity];
      if (existing == null &&
          !dependencyCleared &&
          effectiveForScope(dependencyAccess, scope)) {
        continue;
      }
      if ((existing != null &&
              existing.change.effect !=
                  YorksV1PermissionAssignmentEffect.grant) ||
          (existing == null && dependencyCleared) ||
          !dependencyAccess.canEdit ||
          !dependencyAccess.actorDelegableScopes.contains(scope.kind)) {
        unavailable = dependencyKey;
        return;
      }

      var dependencyScope = scope;
      if (existing?.change.scope?.kind == YorksV1PermissionScopeKind.project) {
        final projectIds = <String>{
          ...existing!.change.scope!.projectIds,
          ...scope.projectIds,
        }.toList()..sort();
        dependencyScope = YorksV1PermissionScope(
          kind: YorksV1PermissionScopeKind.project,
          projectIds: projectIds,
        );
      }
      final generated = _StagedPermissionChange.set(
        access: dependencyAccess,
        effect: YorksV1PermissionAssignmentEffect.grant,
        scope: dependencyScope,
        effectiveUntil: _coveringExpiry(
          existing?.change.effectiveUntil,
          parent.change.effectiveUntil,
          hasExisting: existing != null,
        ),
        requiredByCapabilityKey:
            existing?.requiredByCapabilityKey ?? parent.capabilityKey,
      );
      expanded[identity] = generated;
      ensureDependencies(generated);
      if (unavailable != null) return;
    }
    processing.remove(processKey);
  }

  for (final draft in List<_StagedPermissionChange>.from(expanded.values)) {
    ensureDependencies(draft);
    if (unavailable != null) break;
  }
  return _PermissionDependencyExpansion(
    changes: List.unmodifiable(expanded.values),
    unavailableDependencyKey: unavailable,
  );
}

DateTime? _coveringExpiry(
  DateTime? existing,
  DateTime? required, {
  required bool hasExisting,
}) {
  if (!hasExisting) return required;
  if (existing == null || required == null) return null;
  return existing.isAfter(required) ? existing : required;
}

class YorksV1UserAccessScreen extends ConsumerStatefulWidget {
  const YorksV1UserAccessScreen({super.key, required this.targetAppUserId});

  final String targetAppUserId;

  @override
  ConsumerState<YorksV1UserAccessScreen> createState() =>
      _YorksV1UserAccessScreenState();
}

class _YorksV1UserAccessScreenState
    extends ConsumerState<YorksV1UserAccessScreen> {
  final _searchController = TextEditingController();
  final Map<String, _StagedPermissionChange> _drafts = {};
  String _query = '';
  String? _module;
  int? _baseRevision;
  int? _lastDirectorySyncedRevision;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _t(AppLanguage language, String key, {String? fallback}) =>
      YorksV1PermissionStrings.text(language, key, fallback: fallback);

  YorksV1DomainErrorCode? _errorCode(Object? error) =>
      error is YorksV1DomainException ? error.code : null;

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final provider = yorksV1UserPermissionWorkspaceControllerProvider(
      widget.targetAppUserId,
    );
    final state = ref.watch(provider);
    ref.watch(
      yorksV1TargetPermissionRevisionSyncProvider(widget.targetAppUserId),
    );
    final currentPermissions = ref.watch(
      yorksV1CurrentPermissionSnapshotProvider,
    );
    final workspace = state.workspace;
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= AppSpacing.wideBreakpoint;
    final compact = width < AppSpacing.compactBreakpoint;

    if (workspace == null) {
      return Scaffold(
        key: const Key('permission-access-screen'),
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: _initialState(
            language: language,
            state: state,
            onRetry: () => ref.read(provider.notifier).load(),
          ),
        ),
      );
    }

    final legacyConfigurationActor =
        currentPermissions.snapshot?.user.exactRole?.canConfigureUsers ?? false;
    final canView = currentPermissions.hybridAllows(
      YorksV1CapabilityKeys.permissionsView,
      legacyAllowed: legacyConfigurationActor,
      organizationSummary: true,
    );
    if (!canView) {
      return Scaffold(
        key: const Key('permission-access-screen'),
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: YorksPermissionStatePanel(
            key: Key(
              currentPermissions.isInitialLoading
                  ? 'permission-authority-loading'
                  : 'permission-forbidden',
            ),
            icon: currentPermissions.isInitialLoading
                ? Icons.admin_panel_settings_outlined
                : Icons.lock_outline_rounded,
            title: _t(
              language,
              currentPermissions.isInitialLoading
                  ? 'loading_title'
                  : 'forbidden_title',
            ),
            body: _t(
              language,
              currentPermissions.isInitialLoading
                  ? 'loading_body'
                  : 'forbidden_body',
            ),
            busy: currentPermissions.isInitialLoading,
            secondaryLabel: _t(language, 'back_to_users'),
            onSecondary: () => context.go(RoutePaths.users),
          ),
        ),
      );
    }

    final previousDirectoryRevision = _lastDirectorySyncedRevision;
    if (previousDirectoryRevision != workspace.revision) {
      _lastDirectorySyncedRevision = workspace.revision;
      if (previousDirectoryRevision != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          try {
            await ref
                .read(usersProvider.notifier)
                .refreshFromServer(permissionConfirmed: true);
          } catch (_) {
            // The workspace already holds the current target projection. The
            // directory keeps its last confirmed roster until its own retry.
          }
        });
      }
    }

    final revisionConflict =
        _drafts.isNotEmpty &&
        _baseRevision != null &&
        workspace.revision != _baseRevision;
    final serverConflict =
        _errorCode(state.error) == YorksV1DomainErrorCode.conflict;
    final conflicted = revisionConflict || serverConflict;
    final canManageDecision = currentPermissions.hybridDecision(
      YorksV1CapabilityKeys.permissionsManage,
      legacyAllowed: legacyConfigurationActor,
      organizationSummary: true,
    );
    final canManage =
        workspace.target.isActive &&
        workspace.actor.appUserId != workspace.target.appUserId &&
        canManageDecision.canWrite;
    final actorProjects =
        currentPermissions.snapshot?.projectAccess ??
        const <YorksV1PermissionProjectAccess>[];
    bool canEditAccess(YorksV1PermissionCapabilityAccess access) =>
        canManage &&
        yorksV1DelegableScopeContext(
          access: access,
          targetProjects: workspace.projects,
          actorProjects: actorProjects,
        ).allowedScopes.isNotEmpty;
    final draftsWithinCeiling =
        canManage &&
        _drafts.values.every(
          (draft) => _draftIsDelegable(
            draft: draft,
            workspace: workspace,
            actorProjects: actorProjects,
          ),
        );

    final body = desktop
        ? _desktopWorkspace(
            language: language,
            state: state,
            workspace: workspace,
            conflicted: conflicted,
            canManage: canManage,
            canEditAccess: canEditAccess,
            saveBlocked: !draftsWithinCeiling,
          )
        : _compactWorkspace(
            language: language,
            state: state,
            workspace: workspace,
            conflicted: conflicted,
            canManage: canManage,
            canEditAccess: canEditAccess,
            phone: compact,
          );

    return Scaffold(
      key: const Key('permission-access-screen'),
      backgroundColor: AppColors.surface,
      body: SafeArea(child: body),
      bottomNavigationBar: !desktop && _drafts.isNotEmpty
          ? _ReviewBottomBar(
              count: _drafts.length,
              saving: state.isSaving,
              disabled: conflicted || !draftsWithinCeiling,
              reviewLabel: _t(language, 'review_changes'),
              discardLabel: _t(language, 'discard'),
              onReview: () =>
                  _reviewAndSave(language, workspace, conflicted: conflicted),
              onDiscard: _discardDrafts,
            )
          : null,
    );
  }

  Widget _initialState({
    required AppLanguage language,
    required YorksV1UserPermissionWorkspaceState state,
    required VoidCallback onRetry,
  }) {
    if (state.isInitialLoading && state.error == null) {
      return YorksPermissionStatePanel(
        key: const Key('permission-initial-loading'),
        icon: Icons.admin_panel_settings_outlined,
        title: _t(language, 'loading_title'),
        body: _t(language, 'loading_body'),
        busy: true,
      );
    }
    final code = _errorCode(state.error);
    final forbidden =
        code == YorksV1DomainErrorCode.unauthorized ||
        code == YorksV1DomainErrorCode.unauthenticated;
    final offline = code == YorksV1DomainErrorCode.offline;
    return YorksPermissionStatePanel(
      key: Key(
        forbidden
            ? 'permission-forbidden'
            : offline
            ? 'permission-offline'
            : 'permission-error',
      ),
      icon: forbidden
          ? Icons.lock_outline_rounded
          : offline
          ? Icons.cloud_off_rounded
          : Icons.shield_outlined,
      title: _t(
        language,
        forbidden
            ? 'forbidden_title'
            : offline
            ? 'offline_title'
            : 'load_failed_title',
      ),
      body: _t(
        language,
        forbidden
            ? 'forbidden_body'
            : offline
            ? 'offline_body'
            : 'load_failed_body',
      ),
      primaryLabel: forbidden ? null : _t(language, 'retry'),
      onPrimary: forbidden ? null : onRetry,
      secondaryLabel: _t(language, 'back_to_users'),
      onSecondary: () => context.go(RoutePaths.users),
    );
  }

  Widget _pageHeader(
    AppLanguage language,
    YorksV1UserPermissionWorkspaceState state,
  ) => YorksR35PageHeader(
    eyebrow: _t(language, 'eyebrow'),
    title: _t(language, 'title'),
    description: _t(language, 'subtitle'),
    actions: [
      OutlinedButton.icon(
        onPressed: () => context.go(RoutePaths.users),
        style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
        icon: const Icon(Icons.arrow_back_rounded),
        label: Text(_t(language, 'back_to_users')),
      ),
      IconButton.outlined(
        tooltip: _t(language, 'refresh'),
        onPressed: state.isRefreshing
            ? null
            : () => ref
                  .read(
                    yorksV1UserPermissionWorkspaceControllerProvider(
                      widget.targetAppUserId,
                    ).notifier,
                  )
                  .refresh(),
        icon: state.isRefreshing
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh_rounded),
      ),
    ],
  );

  Widget _desktopWorkspace({
    required AppLanguage language,
    required YorksV1UserPermissionWorkspaceState state,
    required YorksV1UserPermissionWorkspace workspace,
    required bool conflicted,
    required bool canManage,
    required bool Function(YorksV1PermissionCapabilityAccess) canEditAccess,
    required bool saveBlocked,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.xxxl,
      AppSpacing.xxl,
      AppSpacing.xxxl,
      AppSpacing.xxl,
    ),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _pageHeader(language, state),
            const SizedBox(height: AppSpacing.xl),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 245,
                    child: ListView(
                      children: [
                        _UserAccessSummary(
                          language: language,
                          workspace: workspace,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _AccessLegend(language: language),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ..._workspaceBanners(
                          language: language,
                          state: state,
                          workspace: workspace,
                          conflicted: conflicted,
                        ),
                        Expanded(
                          child: _PermissionCatalogue(
                            language: language,
                            workspace: workspace,
                            queryController: _searchController,
                            query: _query,
                            selectedModule: _module,
                            drafts: _drafts.values.toList(growable: false),
                            compact: false,
                            canManage: canManage && !state.isSaving,
                            canEditAccess: canEditAccess,
                            onQueryChanged: (value) =>
                                setState(() => _query = value),
                            onModuleChanged: (value) =>
                                setState(() => _module = value),
                            onEdit: (access) =>
                                _openEditor(language, workspace, access),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  SizedBox(
                    width: 310,
                    child: _ReviewHistoryRail(
                      language: language,
                      workspace: workspace,
                      drafts: _drafts.values.toList(growable: false),
                      saving: state.isSaving,
                      conflicted: conflicted || saveBlocked,
                      onReview: () => _reviewAndSave(
                        language,
                        workspace,
                        conflicted: conflicted,
                      ),
                      onDiscard: _discardDrafts,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _compactWorkspace({
    required AppLanguage language,
    required YorksV1UserPermissionWorkspaceState state,
    required YorksV1UserPermissionWorkspace workspace,
    required bool conflicted,
    required bool canManage,
    required bool Function(YorksV1PermissionCapabilityAccess) canEditAccess,
    required bool phone,
  }) => ListView(
    padding: EdgeInsets.fromLTRB(
      phone ? AppSpacing.mobileScreenHorizontal : AppSpacing.xxl,
      phone ? AppSpacing.mobileScreenVertical : AppSpacing.xxl,
      phone ? AppSpacing.mobileScreenHorizontal : AppSpacing.xxl,
      AppSpacing.massive,
    ),
    children: [
      _pageHeader(language, state),
      const SizedBox(height: AppSpacing.lg),
      _UserAccessSummary(language: language, workspace: workspace),
      const SizedBox(height: AppSpacing.md),
      ..._workspaceBanners(
        language: language,
        state: state,
        workspace: workspace,
        conflicted: conflicted,
      ),
      _PermissionCatalogue(
        language: language,
        workspace: workspace,
        queryController: _searchController,
        query: _query,
        selectedModule: _module,
        drafts: _drafts.values.toList(growable: false),
        compact: true,
        canManage: canManage && !state.isSaving,
        canEditAccess: canEditAccess,
        onQueryChanged: (value) => setState(() => _query = value),
        onModuleChanged: (value) => setState(() => _module = value),
        onEdit: (access) => _openEditor(language, workspace, access),
      ),
      const SizedBox(height: AppSpacing.lg),
      _PermissionHistoryCard(
        language: language,
        history: workspace.recentHistory,
      ),
    ],
  );

  List<Widget> _workspaceBanners({
    required AppLanguage language,
    required YorksV1UserPermissionWorkspaceState state,
    required YorksV1UserPermissionWorkspace workspace,
    required bool conflicted,
  }) {
    final banners = <Widget>[];
    if (!workspace.target.isActive) {
      banners.add(
        _WorkspaceBanner(
          key: const Key('permission-deactivated-banner'),
          icon: Icons.person_off_outlined,
          title: _t(language, 'deactivated_title'),
          body: _t(language, 'deactivated_body'),
          tone: _BannerTone.danger,
        ),
      );
    }
    // The rollout mode (shadow, mixed) is not shown as a banner: each row
    // that follows the role says so itself.
    if (workspace.actor.appUserId == workspace.target.appUserId) {
      banners.add(
        _WorkspaceBanner(
          key: const Key('permission-self-protected-banner'),
          icon: Icons.lock_person_outlined,
          title: _t(language, 'protected'),
          body: _t(language, 'protected_help'),
          tone: _BannerTone.warning,
        ),
      );
    }
    // A dated organization responsibility only gates the legacy Workforce
    // screens. Attendance V2 decides access by role and project, so the
    // warning and the assignment are not offered there.
    final legacyWorkforce = !ref
        .watch(yorksV1FeatureFlagsProvider)
        .workforceAttendanceV2;
    final workforceAccess = legacyWorkforce ? workspace.workforceAccess : null;
    if (workforceAccess != null &&
        workforceAccess.hasOperationalAccess &&
        !workforceAccess.hasOrganizationResponsibility) {
      banners.add(
        _WorkspaceBanner(
          key: const Key('permission-workforce-responsibility-banner'),
          icon: Icons.badge_outlined,
          title: _t(language, 'workforce_responsibility_missing_title'),
          body: _t(language, 'workforce_responsibility_missing_body'),
          tone: _BannerTone.warning,
          actionLabel: workforceAccess.canAssignOrganizationResponsibility
              ? _t(language, 'assign_workforce_responsibility')
              : null,
          onAction:
              workforceAccess.canAssignOrganizationResponsibility &&
                  !state.isSaving
              ? () => _assignWorkforceOrganizationResponsibility(
                  language,
                  workspace,
                )
              : null,
        ),
      );
    } else if (workforceAccess != null &&
        workforceAccess.hasOperationalAccess &&
        workforceAccess.hasOrganizationResponsibility &&
        workforceAccess.isConfigurationEmpty) {
      banners.add(
        _WorkspaceBanner(
          key: const Key('permission-workforce-empty-setup-banner'),
          icon: Icons.task_alt_rounded,
          title: _t(language, 'workforce_access_ready_title'),
          body: _t(language, 'workforce_access_ready_empty_body'),
          tone: _BannerTone.info,
        ),
      );
    }
    if (conflicted) {
      banners.add(
        _WorkspaceBanner(
          key: const Key('permission-conflict-banner'),
          icon: Icons.sync_problem_rounded,
          title: _t(language, 'conflict_title'),
          body: _t(language, 'conflict_body'),
          tone: _BannerTone.warning,
          actionLabel: _t(language, 'reload_latest'),
          onAction: () => _reloadForConflict(workspace),
        ),
      );
    } else if (state.error != null) {
      final offline = _errorCode(state.error) == YorksV1DomainErrorCode.offline;
      banners.add(
        _WorkspaceBanner(
          key: const Key('permission-refresh-error-banner'),
          icon: offline ? Icons.cloud_off_rounded : Icons.error_outline,
          title: _t(language, offline ? 'offline_title' : 'load_failed_title'),
          body: _t(language, offline ? 'offline_body' : 'load_failed_body'),
          tone: _BannerTone.warning,
          actionLabel: _t(language, 'retry'),
          onAction: () => ref
              .read(
                yorksV1UserPermissionWorkspaceControllerProvider(
                  widget.targetAppUserId,
                ).notifier,
              )
              .refresh(),
        ),
      );
    }
    if (state.isRefreshing) {
      banners.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Semantics(
            liveRegion: true,
            label: _t(language, 'refreshing'),
            child: const LinearProgressIndicator(minHeight: 2),
          ),
        ),
      );
    }
    return [
      for (final banner in banners) ...[
        banner,
        const SizedBox(height: AppSpacing.md),
      ],
    ];
  }

  Future<void> _assignWorkforceOrganizationResponsibility(
    AppLanguage language,
    YorksV1UserPermissionWorkspace workspace,
  ) async {
    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _WorkforceResponsibilityDialog(language: language),
    );
    if (reason == null || !mounted) return;
    final provider = yorksV1UserPermissionWorkspaceControllerProvider(
      widget.targetAppUserId,
    );
    final succeeded = await ref
        .read(provider.notifier)
        .assignWorkforceOrganizationResponsibility(
          reason: reason,
          expectedRevision: workspace.revision,
        );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (succeeded) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _t(language, 'workforce_responsibility_assign_succeeded'),
          ),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(_saveError(language, ref.read(provider).error)),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _reloadForConflict(
    YorksV1UserPermissionWorkspace current,
  ) async {
    final provider = yorksV1UserPermissionWorkspaceControllerProvider(
      widget.targetAppUserId,
    );
    await ref.read(provider.notifier).refresh();
    if (!mounted) return;
    final fresh = ref.read(provider).workspace;
    setState(() => _baseRevision = fresh?.revision ?? current.revision);
  }

  Future<void> _openEditor(
    AppLanguage language,
    YorksV1UserPermissionWorkspace workspace,
    YorksV1PermissionCapabilityAccess access,
  ) async {
    final currentPermissions = ref.read(
      yorksV1CurrentPermissionSnapshotProvider,
    );
    final legacyConfigurationActor =
        currentPermissions.snapshot?.user.exactRole?.canConfigureUsers ?? false;
    final canManage = currentPermissions
        .hybridDecision(
          YorksV1CapabilityKeys.permissionsManage,
          legacyAllowed: legacyConfigurationActor,
          organizationSummary: true,
        )
        .canWrite;
    final scopeContext = yorksV1DelegableScopeContext(
      access: access,
      targetProjects: workspace.projects,
      actorProjects:
          currentPermissions.snapshot?.projectAccess ??
          const <YorksV1PermissionProjectAccess>[],
    );
    if (!canManage ||
        !workspace.target.isActive ||
        workspace.actor.appUserId == workspace.target.appUserId ||
        scopeContext.allowedScopes.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_t(language, 'forbidden_title'))));
      return;
    }
    final assignments = workspace.assignments
        .where(
          (item) =>
              item.capabilityKey == access.catalog.key &&
              scopeContext.allows(item.scope),
        )
        .toList(growable: false);
    final existingDrafts = _drafts.values
        .where((item) {
          final scope = _draftScope(item);
          return item.capabilityKey == access.catalog.key &&
              scope != null &&
              scopeContext.allows(scope);
        })
        .toList(growable: false);
    final editor = _PermissionEditorSheet(
      language: language,
      access: access,
      assignments: assignments,
      allowedScopes: scopeContext.allowedScopes,
      projects: scopeContext.projects,
      staged: existingDrafts,
    );
    final result = MediaQuery.sizeOf(context).width < 760
        ? await showModalBottomSheet<_PermissionEditResult>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Colors.transparent,
            builder: (_) => editor,
          )
        : await showDialog<_PermissionEditResult>(
            context: context,
            builder: (_) => Dialog(
              insetPadding: const EdgeInsets.all(AppSpacing.xxl),
              backgroundColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 680,
                  maxHeight: 760,
                ),
                child: editor,
              ),
            ),
          );
    if (result == null || !mounted) return;
    setState(() {
      _baseRevision ??= workspace.revision;
      _drafts.removeWhere(
        (_, draft) => draft.capabilityKey == access.catalog.key,
      );
      for (final change in result.changes) {
        _drafts[change.change.identity] = change;
      }
      if (_drafts.isEmpty) _baseRevision = null;
    });
  }

  void _discardDrafts() => setState(() {
    _drafts.clear();
    _baseRevision = null;
  });

  YorksV1PermissionScope? _draftScope(_StagedPermissionChange draft) =>
      draft.change.operation == YorksV1PermissionChangeOperation.clear
      ? draft.assignment?.scope
      : draft.change.scope;

  bool _draftIsDelegable({
    required _StagedPermissionChange draft,
    required YorksV1UserPermissionWorkspace workspace,
    required Iterable<YorksV1PermissionProjectAccess> actorProjects,
  }) {
    YorksV1PermissionCapabilityAccess? access;
    for (final entry in workspace.catalog) {
      if (entry.catalog.key == draft.capabilityKey) {
        access = entry;
        break;
      }
    }
    final scope = _draftScope(draft);
    if (access == null || scope == null) return false;
    return yorksV1DelegableScopeContext(
      access: access,
      targetProjects: workspace.projects,
      actorProjects: actorProjects,
    ).allows(scope);
  }

  Future<void> _reviewAndSave(
    AppLanguage language,
    YorksV1UserPermissionWorkspace workspace, {
    required bool conflicted,
  }) async {
    if (_drafts.isEmpty || conflicted) return;
    final currentPermissions = ref.read(
      yorksV1CurrentPermissionSnapshotProvider,
    );
    final legacyConfigurationActor =
        currentPermissions.snapshot?.user.exactRole?.canConfigureUsers ?? false;
    final stillCanManage = currentPermissions
        .hybridDecision(
          YorksV1CapabilityKeys.permissionsManage,
          legacyAllowed: legacyConfigurationActor,
          organizationSummary: true,
        )
        .canWrite;
    final actorProjects =
        currentPermissions.snapshot?.projectAccess ??
        const <YorksV1PermissionProjectAccess>[];
    final expansion = _expandPermissionDependencies(
      drafts: _drafts.values,
      workspace: workspace,
    );
    if (!expansion.isComplete) {
      final message = _t(
        language,
        'permission_dependency_unavailable',
      ).replaceAll('{permission}', expansion.unavailableDependencyKey ?? '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.error),
      );
      return;
    }
    final reviewedChanges = expansion.changes;
    final draftsWithinCeiling = reviewedChanges.every(
      (draft) => _draftIsDelegable(
        draft: draft,
        workspace: workspace,
        actorProjects: actorProjects,
      ),
    );
    if (!stillCanManage || !draftsWithinCeiling) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_t(language, 'forbidden_title'))));
      return;
    }
    final offersWorkforceResponsibility =
        !ref.read(yorksV1FeatureFlagsProvider).workforceAttendanceV2 &&
        workspace.workforceAccess?.canAssignOrganizationResponsibility ==
            true &&
        workspace.workforceAccess?.hasOrganizationResponsibility == false &&
        reviewedChanges.any(
          (draft) =>
              draft.change.operation == YorksV1PermissionChangeOperation.set &&
              draft.change.effect == YorksV1PermissionAssignmentEffect.grant &&
              draft.change.scope?.kind ==
                  YorksV1PermissionScopeKind.organization &&
              draft.capabilityKey.startsWith('workforce.'),
        );
    final review = await showDialog<_PermissionReviewResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReviewPermissionChangesDialog(
        language: language,
        workspace: workspace,
        changes: reviewedChanges,
        offerWorkforceResponsibility: offersWorkforceResponsibility,
      ),
    );
    if (review == null || !mounted) return;
    final expectedRevision = _baseRevision ?? workspace.revision;
    final provider = yorksV1UserPermissionWorkspaceControllerProvider(
      widget.targetAppUserId,
    );
    final succeeded = await ref
        .read(provider.notifier)
        .applyChanges(
          changes: reviewedChanges
              .map((draft) => draft.change)
              .toList(growable: false),
          reason: review.reason,
          expectedRevision: expectedRevision,
          assignOrganizationWorkforceResponsibility:
              review.assignOrganizationWorkforceResponsibility,
        );
    if (!mounted) return;
    if (succeeded) {
      setState(() {
        _drafts.clear();
        _baseRevision = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_t(language, 'save_succeeded'))));
      return;
    }
    final error = ref.read(provider).error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_saveError(language, error)),
        backgroundColor: AppColors.error,
      ),
    );
  }

  String _saveError(AppLanguage language, Object? error) {
    if (error is YorksV1DomainException &&
        error.serverMessage == 'V1_PERMISSION_DEPENDENCY_NOT_EFFECTIVE') {
      return _t(language, 'permission_dependency_rejected');
    }
    return switch (_errorCode(error)) {
      YorksV1DomainErrorCode.conflict => _t(language, 'conflict_title'),
      YorksV1DomainErrorCode.offline => _t(language, 'offline_title'),
      YorksV1DomainErrorCode.invalidInput => _t(language, 'invalid_change'),
      YorksV1DomainErrorCode.unauthorized => _t(language, 'forbidden_title'),
      YorksV1DomainErrorCode.unexpectedResponse => _t(
        language,
        'unexpected_response',
      ),
      YorksV1DomainErrorCode.serverRejected => _t(language, 'server_rejected'),
      _ => _t(language, 'save_failed'),
    };
  }
}

class _PermissionCatalogue extends StatelessWidget {
  const _PermissionCatalogue({
    required this.language,
    required this.workspace,
    required this.queryController,
    required this.query,
    required this.selectedModule,
    required this.drafts,
    required this.compact,
    required this.canManage,
    required this.canEditAccess,
    required this.onQueryChanged,
    required this.onModuleChanged,
    required this.onEdit,
  });

  final AppLanguage language;
  final YorksV1UserPermissionWorkspace workspace;
  final TextEditingController queryController;
  final String query;
  final String? selectedModule;
  final List<_StagedPermissionChange> drafts;
  final bool compact;
  final bool canManage;
  final bool Function(YorksV1PermissionCapabilityAccess) canEditAccess;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String?> onModuleChanged;
  final ValueChanged<YorksV1PermissionCapabilityAccess> onEdit;

  String _t(String key, {String? fallback}) =>
      YorksV1PermissionStrings.text(language, key, fallback: fallback);

  @override
  Widget build(BuildContext context) {
    final modules =
        workspace.catalog.map((item) => item.catalog.module).toSet().toList()
          ..sort(
            (a, b) => YorksV1PermissionStrings.module(
              language,
              a,
            ).compareTo(YorksV1PermissionStrings.module(language, b)),
          );
    final normalized = query.trim().toLowerCase();
    final filtered = workspace.catalog
        .where((entry) {
          if (selectedModule != null &&
              entry.catalog.module != selectedModule) {
            return false;
          }
          if (normalized.isEmpty) return true;
          return [
            entry.catalog.key,
            YorksV1PermissionStrings.module(language, entry.catalog.module),
            YorksV1PermissionStrings.action(language, entry.catalog.action),
          ].any((value) => value.toLowerCase().contains(normalized));
        })
        .toList(growable: false);
    final grouped = <String, List<YorksV1PermissionCapabilityAccess>>{};
    for (final entry in filtered) {
      grouped.putIfAbsent(entry.catalog.module, () => []).add(entry);
    }
    for (final entries in grouped.values) {
      entries.sort((a, b) => a.catalog.action.compareTo(b.catalog.action));
    }

    final filter = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('permission-search'),
          controller: queryController,
          onChanged: onQueryChanged,
          decoration: InputDecoration(
            labelText: _t('search_permissions'),
            hintText: _t('search_hint'),
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: _t('close'),
                    onPressed: () {
                      queryController.clear();
                      onQueryChanged('');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _FilterChip(
                label: _t('all_modules'),
                selected: selectedModule == null,
                onSelected: () => onModuleChanged(null),
              ),
              for (final module in modules) ...[
                const SizedBox(width: AppSpacing.sm),
                _FilterChip(
                  label: YorksV1PermissionStrings.module(language, module),
                  selected: selectedModule == module,
                  onSelected: () => onModuleChanged(module),
                ),
              ],
            ],
          ),
        ),
      ],
    );

    final content = filtered.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.massive),
            child: YorksPermissionStatePanel(
              key: const Key('permission-empty-state'),
              icon: Icons.filter_alt_off_outlined,
              title: _t('empty_title'),
              body: _t('empty_body'),
            ),
          )
        : Column(
            children: [
              for (final module in grouped.keys) ...[
                _PermissionModuleCard(
                  language: language,
                  module: module,
                  entries: grouped[module]!,
                  workspace: workspace,
                  compact: compact,
                  canManage: canManage,
                  canEditAccess: canEditAccess,
                  draftCountFor: (key) => drafts
                      .where((draft) => draft.capabilityKey == key)
                      .length,
                  onEdit: onEdit,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ],
          );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          filter,
          const SizedBox(height: AppSpacing.md),
          content,
        ],
      );
    }
    return ListView(
      key: const Key('permission-catalogue'),
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      children: [
        filter,
        const SizedBox(height: AppSpacing.md),
        content,
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onSelected(),
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
  );
}

class _PermissionModuleCard extends StatelessWidget {
  const _PermissionModuleCard({
    required this.language,
    required this.module,
    required this.entries,
    required this.workspace,
    required this.compact,
    required this.canManage,
    required this.canEditAccess,
    required this.draftCountFor,
    required this.onEdit,
  });

  final AppLanguage language;
  final String module;
  final List<YorksV1PermissionCapabilityAccess> entries;
  final YorksV1UserPermissionWorkspace workspace;
  final bool compact;
  final bool canManage;
  final bool Function(YorksV1PermissionCapabilityAccess) canEditAccess;
  final int Function(String capabilityKey) draftCountFor;
  final ValueChanged<YorksV1PermissionCapabilityAccess> onEdit;

  @override
  Widget build(BuildContext context) {
    final title = YorksV1PermissionStrings.module(language, module);
    final children = [
      for (var index = 0; index < entries.length; index++) ...[
        _PermissionRow(
          language: language,
          access: entries[index],
          workspace: workspace,
          compact: compact,
          canManage: canManage && canEditAccess(entries[index]),
          draftCount: draftCountFor(entries[index].catalog.key),
          onEdit: () => onEdit(entries[index]),
        ),
        if (index < entries.length - 1) const Divider(height: 1),
      ],
    ];
    if (compact) {
      return YorksPermissionSurface(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          key: Key('permission-module-$module'),
          initiallyExpanded: false,
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          title: Text(title, style: AppTypography.titleMedium),
          subtitle: Text(
            '${entries.length}',
            style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
          ),
          children: children,
        ),
      );
    }
    return YorksPermissionSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: YorksPermissionSectionTitle(
              title: title,
              trailing: YorksPermissionPill(
                label: '${entries.length}',
                tone: YorksPermissionPillTone.neutral,
              ),
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.language,
    required this.access,
    required this.workspace,
    required this.compact,
    required this.canManage,
    required this.draftCount,
    required this.onEdit,
  });

  final AppLanguage language;
  final YorksV1PermissionCapabilityAccess access;
  final YorksV1UserPermissionWorkspace workspace;
  final bool compact;
  final bool canManage;
  final int draftCount;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final catalog = access.catalog;
    final assignable = canManage && access.canEdit;
    final organizationVisible = access.organizationSummaryVisible;
    final effective = access.authoritativeEffective == true;
    final visibleProjectCount = access.projectOverrides.length;
    final allowedProjectCount = access.projectOverrides
        .where((item) => item.authoritativeEffective)
        .length;
    final candidateProjectCount = access.projectOverrides
        .where((item) => item.candidateEffective)
        .length;
    String projectCountLabel(int allowed) =>
        YorksV1PermissionStrings.text(language, 'allowed_project_count')
            .replaceAll('{allowed}', '$allowed')
            .replaceAll('{count}', '$visibleProjectCount');
    final effectiveLabel = organizationVisible
        ? YorksV1PermissionStrings.text(
            language,
            effective ? 'allowed' : 'denied',
          )
        : projectCountLabel(allowedProjectCount);
    final source = organizationVisible
        ? YorksV1PermissionStrings.source(language, access.authoritativeSource!)
        : YorksV1PermissionStrings.text(language, 'project_specific_summary');
    final parity = organizationVisible
        ? access.hasParity == true
        : access.projectOverrides.isNotEmpty &&
              access.projectOverrides.every((item) => item.hasParity);
    final action = YorksV1PermissionStrings.action(language, catalog.action);
    final scope = access.projectOverrides.isEmpty
        ? YorksV1PermissionStrings.scope(
            language,
            YorksV1PermissionScopeKind.organization,
          )
        : YorksV1PermissionStrings.text(language, 'selected_projects');
    final effectivePill = YorksPermissionPill(
      label: effectiveLabel,
      tone: organizationVisible && !effective
          ? YorksPermissionPillTone.denied
          : effective || allowedProjectCount > 0
          ? YorksPermissionPillTone.allowed
          : YorksPermissionPillTone.neutral,
      icon: organizationVisible
          ? effective
                ? Icons.check_rounded
                : Icons.block_rounded
          : Icons.account_tree_outlined,
    );
    final roleManaged =
        access.authorizationMode ==
        YorksV1PermissionCapabilityAuthorizationMode.shadow;
    final edit = SizedBox.square(
      dimension: AppSpacing.minTapTarget,
      child: IconButton(
        key: Key('permission-edit-${catalog.key}'),
        tooltip: assignable
            ? YorksV1PermissionStrings.text(language, 'edit_access')
            : YorksV1PermissionStrings.text(
                language,
                roleManaged ? 'role_managed_help' : 'protected',
              ),
        onPressed: assignable ? onEdit : null,
        icon: Icon(
          assignable ? Icons.tune_rounded : Icons.lock_outline_rounded,
          size: 20,
        ),
      ),
    );
    final badges = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        effectivePill,
        YorksPermissionPill(
          label: source,
          tone:
              organizationVisible &&
                  (access.authoritativeSource ==
                          YorksV1PermissionEffectiveSource.explicitGrant ||
                      access.authoritativeSource ==
                          YorksV1PermissionEffectiveSource.explicitDeny)
              ? YorksPermissionPillTone.info
              : YorksPermissionPillTone.neutral,
        ),
        YorksPermissionPill(
          label: scope,
          tone: YorksPermissionPillTone.neutral,
        ),
        if (catalog.runtimeStatus == YorksV1PermissionRuntimeStatus.planned)
          YorksPermissionPill(
            label: YorksV1PermissionStrings.text(language, 'planned'),
            tone: YorksPermissionPillTone.warning,
          )
        else if (!catalog.canAssignFromThisClient)
          YorksPermissionPill(
            label: YorksV1PermissionStrings.text(language, 'protected'),
            tone: YorksPermissionPillTone.warning,
          ),
        // Follows the role and cannot be customised here yet.
        if (roleManaged && catalog.canAssignFromThisClient)
          YorksPermissionPill(
            key: Key('permission-role-managed-${catalog.key}'),
            label: YorksV1PermissionStrings.text(language, 'role_managed'),
            tone: YorksPermissionPillTone.neutral,
            icon: Icons.lock_outline_rounded,
          ),
        // The rollout comparison shows only when the rules disagree.
        if (!parity) ...[
          YorksPermissionPill(
            key: Key('permission-rules-differ-${catalog.key}'),
            label: YorksV1PermissionStrings.text(language, 'rules_differ'),
            tone: YorksPermissionPillTone.warning,
            icon: Icons.difference_outlined,
          ),
          YorksPermissionPill(
            label: organizationVisible
                ? '${YorksV1PermissionStrings.text(language, 'new_rule')}: '
                      '${YorksV1PermissionStrings.text(language, access.candidateEffective == true ? 'allowed' : 'denied')}'
                : '${YorksV1PermissionStrings.text(language, 'new_rule')}: '
                      '${projectCountLabel(candidateProjectCount)}',
            tone: access.candidateEffective == true || candidateProjectCount > 0
                ? YorksPermissionPillTone.allowed
                : YorksPermissionPillTone.denied,
          ),
        ],
        if (draftCount > 0)
          YorksPermissionPill(
            label:
                '$draftCount ${YorksV1PermissionStrings.text(language, 'review_changes')}',
            tone: YorksPermissionPillTone.info,
            icon: Icons.edit_note_rounded,
          ),
      ],
    );

    return Semantics(
      key: Key('permission-row-${catalog.key}'),
      container: true,
      label:
          '$action, '
          '$effectiveLabel, '
          '$source',
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(action, style: AppTypography.titleSmall),
                            const SizedBox(height: 3),
                            Text(
                              catalog.key,
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      edit,
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  badges,
                ],
              )
            : Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(action, style: AppTypography.titleSmall),
                        const SizedBox(height: 3),
                        Text(
                          catalog.key,
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(flex: 5, child: badges),
                  edit,
                ],
              ),
      ),
    );
  }
}

class _UserAccessSummary extends StatelessWidget {
  const _UserAccessSummary({required this.language, required this.workspace});

  final AppLanguage language;
  final YorksV1UserPermissionWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    final target = workspace.target;
    final initial = target.displayName.trim().isEmpty
        ? '?'
        : target.displayName.trim()[0].toUpperCase();
    return YorksPermissionSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.blueContainer,
              foregroundColor: AppColors.blue,
              child: Text(
                initial,
                style: AppTypography.headlineSmall.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            target.displayName,
            textAlign: TextAlign.center,
            style: AppTypography.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            YorksV1PermissionStrings.role(language, target.exactRole),
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              YorksPermissionPill(
                label: YorksV1PermissionStrings.text(
                  language,
                  target.isActive ? 'active' : 'deactivated',
                ),
                tone: target.isActive
                    ? YorksPermissionPillTone.allowed
                    : YorksPermissionPillTone.denied,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          _SummaryMetric(
            icon: Icons.shield_outlined,
            label: YorksV1PermissionStrings.text(
              language,
              'custom_assignments',
            ),
            value: '${workspace.assignments.length}',
          ),
          const SizedBox(height: AppSpacing.sm),
          _SummaryMetric(
            icon: Icons.folder_shared_outlined,
            label: YorksV1PermissionStrings.text(language, 'project_scope'),
            value:
                '${workspace.projects.where((item) => item.hasAccess).length}',
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: AppColors.blue),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Text(
          label,
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        ),
      ),
      Text(value, style: AppTypography.labelLarge),
    ],
  );
}

class _AccessLegend extends StatelessWidget {
  const _AccessLegend({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) => YorksPermissionSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          YorksV1PermissionStrings.text(language, 'source'),
          style: AppTypography.titleSmall,
        ),
        const SizedBox(height: AppSpacing.md),
        for (final source in const [
          YorksV1PermissionEffectiveSource.roleDefault,
          YorksV1PermissionEffectiveSource.explicitGrant,
          YorksV1PermissionEffectiveSource.explicitDeny,
          YorksV1PermissionEffectiveSource.legacyOverride,
        ]) ...[
          Row(
            children: [
              Icon(
                source == YorksV1PermissionEffectiveSource.explicitDeny
                    ? Icons.block_rounded
                    : source == YorksV1PermissionEffectiveSource.explicitGrant
                    ? Icons.add_circle_outline_rounded
                    : Icons.account_tree_outlined,
                size: 17,
                color: AppColors.muted,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  YorksV1PermissionStrings.source(language, source),
                  style: AppTypography.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    ),
  );
}

class _ReviewHistoryRail extends StatelessWidget {
  const _ReviewHistoryRail({
    required this.language,
    required this.workspace,
    required this.drafts,
    required this.saving,
    required this.conflicted,
    required this.onReview,
    required this.onDiscard,
  });

  final AppLanguage language;
  final YorksV1UserPermissionWorkspace workspace;
  final List<_StagedPermissionChange> drafts;
  final bool saving;
  final bool conflicted;
  final VoidCallback onReview;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      YorksPermissionSurface(
        highlighted: drafts.isNotEmpty,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            YorksPermissionSectionTitle(
              title: YorksV1PermissionStrings.text(language, 'review_changes'),
              trailing: YorksPermissionPill(
                label: '${drafts.length}',
                tone: drafts.isEmpty
                    ? YorksPermissionPillTone.neutral
                    : YorksPermissionPillTone.info,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (drafts.isEmpty)
              Text(
                YorksV1PermissionStrings.text(
                  language,
                  'server_confirmed_notice',
                ),
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              )
            else ...[
              for (final draft in drafts.take(5)) ...[
                _DraftSummaryLine(language: language, draft: draft),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (drafts.length > 5)
                Text(
                  '+${drafts.length - 5}',
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.blue,
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(
                label: YorksV1PermissionStrings.text(
                  language,
                  'review_changes',
                ),
                icon: Icons.fact_check_outlined,
                isLoading: saving,
                onPressed: saving || conflicted ? null : onReview,
              ),
              const SizedBox(height: AppSpacing.sm),
              SecondaryButton(
                label: YorksV1PermissionStrings.text(language, 'discard'),
                icon: Icons.undo_rounded,
                onPressed: saving ? null : onDiscard,
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      _PermissionHistoryCard(
        language: language,
        history: workspace.recentHistory,
      ),
    ],
  );
}

class _ReviewBottomBar extends StatelessWidget {
  const _ReviewBottomBar({
    required this.count,
    required this.saving,
    required this.disabled,
    required this.reviewLabel,
    required this.discardLabel,
    required this.onReview,
    required this.onDiscard,
  });

  final int count;
  final bool saving;
  final bool disabled;
  final String reviewLabel;
  final String discardLabel;
  final VoidCallback onReview;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceContainerLowest,
    elevation: 8,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            TextButton(
              onPressed: saving ? null : onDiscard,
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              child: Text(discardLabel),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: PrimaryButton(
                key: const Key('permission-review-button'),
                label: '$reviewLabel ($count)',
                icon: Icons.fact_check_outlined,
                isLoading: saving,
                onPressed: saving || disabled ? null : onReview,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DraftSummaryLine extends StatelessWidget {
  const _DraftSummaryLine({required this.language, required this.draft});

  final AppLanguage language;
  final _StagedPermissionChange draft;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        draft.change.operation == YorksV1PermissionChangeOperation.clear
            ? Icons.remove_circle_outline_rounded
            : draft.change.effect == YorksV1PermissionAssignmentEffect.grant
            ? Icons.add_circle_outline_rounded
            : Icons.block_rounded,
        size: 17,
        color: draft.change.effect == YorksV1PermissionAssignmentEffect.deny
            ? AppColors.error
            : AppColors.blue,
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              YorksV1PermissionStrings.action(language, draft.action),
              style: AppTypography.labelMedium,
            ),
            Text(
              YorksV1PermissionStrings.module(language, draft.module),
              style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
            ),
          ],
        ),
      ),
    ],
  );
}

class _PermissionHistoryCard extends StatelessWidget {
  const _PermissionHistoryCard({required this.language, required this.history});

  final AppLanguage language;
  final List<YorksV1PermissionHistoryEvent> history;

  @override
  Widget build(BuildContext context) => YorksPermissionSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        YorksPermissionSectionTitle(
          title: YorksV1PermissionStrings.text(language, 'permission_history'),
          trailing: const Icon(Icons.history_rounded, color: AppColors.blue),
        ),
        const SizedBox(height: AppSpacing.md),
        if (history.isEmpty)
          Column(
            children: [
              const Icon(
                Icons.history_toggle_off_outlined,
                color: AppColors.muted,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                YorksV1PermissionStrings.text(language, 'no_history_title'),
                textAlign: TextAlign.center,
                style: AppTypography.labelLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                YorksV1PermissionStrings.text(language, 'no_history_body'),
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ],
          )
        else
          for (var index = 0; index < history.take(12).length; index++) ...[
            _HistoryEventTile(language: language, event: history[index]),
            if (index < history.take(12).length - 1)
              const Divider(height: AppSpacing.lg),
          ],
      ],
    ),
  );
}

class _HistoryEventTile extends StatelessWidget {
  const _HistoryEventTile({required this.language, required this.event});

  final AppLanguage language;
  final YorksV1PermissionHistoryEvent event;

  @override
  Widget build(BuildContext context) {
    final local = event.occurredAt.toLocal();
    final timestamp =
        '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: AppColors.blueContainer,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.history_rounded,
            size: 17,
            color: AppColors.blue,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                YorksV1PermissionStrings.historyKind(language, event.kind),
                style: AppTypography.labelLarge,
              ),
              const SizedBox(height: 2),
              Text(
                event.capabilityKey,
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              if (event.reason.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(event.reason, style: AppTypography.bodySmall),
              ],
              if (event.before.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  '${YorksV1PermissionStrings.text(language, 'before')}: '
                  '${_assignmentSummary(event.before)}',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
              if (event.after.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  '${YorksV1PermissionStrings.text(language, 'after')}: '
                  '${_assignmentSummary(event.after)}',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 3),
              Text(
                '${event.actor.displayName ?? YorksV1PermissionStrings.text(language, 'system_actor')} · $timestamp',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _assignmentSummary(
    List<YorksV1PermissionAssignmentValue> assignments,
  ) => assignments
      .map(
        (assignment) =>
            '${YorksV1PermissionStrings.effect(language, assignment.effect)} · '
            '${YorksV1PermissionStrings.scope(language, assignment.scope.kind)}',
      )
      .join('; ');
}

enum _BannerTone { info, warning, danger }

class _WorkspaceBanner extends StatelessWidget {
  const _WorkspaceBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.tone,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final _BannerTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = switch (tone) {
      _BannerTone.info => const (
        AppColors.blueContainer,
        AppColors.blue,
        AppColors.blueContainerStrong,
      ),
      _BannerTone.warning => const (
        AppColors.warningContainer,
        AppColors.onWarningContainer,
        Color(0xFFEACD89),
      ),
      _BannerTone.danger => const (
        AppColors.errorContainer,
        AppColors.onErrorContainer,
        Color(0xFFE8B7B7),
      ),
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.$1,
        border: Border.all(color: colors.$3),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.$2),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.labelLarge.copyWith(color: colors.$2),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  body,
                  style: AppTypography.bodySmall.copyWith(color: colors.$2),
                ),
                if (actionLabel != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: onAction,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.$2,
                        minimumSize: const Size(44, 44),
                      ),
                      child: Text(actionLabel!),
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
}

class _StagedPermissionChange {
  const _StagedPermissionChange({
    required this.change,
    required this.capabilityKey,
    required this.module,
    required this.action,
    this.assignment,
    this.requiredByCapabilityKey,
  });

  final YorksV1PermissionChange change;
  final String capabilityKey;
  final String module;
  final String action;
  final YorksV1PermissionAssignment? assignment;
  final String? requiredByCapabilityKey;

  factory _StagedPermissionChange.set({
    required YorksV1PermissionCapabilityAccess access,
    required YorksV1PermissionAssignmentEffect effect,
    required YorksV1PermissionScope scope,
    DateTime? effectiveUntil,
    String? requiredByCapabilityKey,
  }) => _StagedPermissionChange(
    change: YorksV1PermissionChange.set(
      capabilityKey: access.catalog.key,
      effect: effect,
      scope: scope,
      effectiveUntil: effectiveUntil,
    ),
    capabilityKey: access.catalog.key,
    module: access.catalog.module,
    action: access.catalog.action,
    requiredByCapabilityKey: requiredByCapabilityKey,
  );

  factory _StagedPermissionChange.clear({
    required YorksV1PermissionCapabilityAccess access,
    required YorksV1PermissionAssignment assignment,
  }) => _StagedPermissionChange(
    change: YorksV1PermissionChange.clear(assignmentId: assignment.id),
    capabilityKey: access.catalog.key,
    module: access.catalog.module,
    action: access.catalog.action,
    assignment: assignment,
  );
}

class _PermissionEditResult {
  const _PermissionEditResult(this.changes);
  final List<_StagedPermissionChange> changes;
}

class _PermissionReviewResult {
  const _PermissionReviewResult({
    required this.reason,
    required this.assignOrganizationWorkforceResponsibility,
  });

  final String reason;
  final bool assignOrganizationWorkforceResponsibility;
}

class _PermissionEditorSheet extends StatefulWidget {
  const _PermissionEditorSheet({
    required this.language,
    required this.access,
    required this.assignments,
    required this.allowedScopes,
    required this.projects,
    required this.staged,
  });

  final AppLanguage language;
  final YorksV1PermissionCapabilityAccess access;
  final List<YorksV1PermissionAssignment> assignments;
  final Set<YorksV1PermissionScopeKind> allowedScopes;
  final List<YorksV1PermissionProjectAccess> projects;
  final List<_StagedPermissionChange> staged;

  @override
  State<_PermissionEditorSheet> createState() => _PermissionEditorSheetState();
}

class _PermissionEditorSheetState extends State<_PermissionEditorSheet> {
  YorksV1PermissionAssignmentEffect _effect =
      YorksV1PermissionAssignmentEffect.grant;
  late YorksV1PermissionScopeKind _scopeKind;
  final Set<String> _projects = {};
  final Set<String> _clearAssignmentIds = {};
  bool _includeSet = false;
  bool _hasExpiry = false;
  DateTime? _expiry;
  String? _validation;

  @override
  void initState() {
    super.initState();
    final scopes = widget.allowedScopes;
    _scopeKind = scopes.contains(YorksV1PermissionScopeKind.organization)
        ? YorksV1PermissionScopeKind.organization
        : YorksV1PermissionScopeKind.project;
    for (final draft in widget.staged) {
      final change = draft.change;
      if (change.operation == YorksV1PermissionChangeOperation.clear) {
        _clearAssignmentIds.add(change.assignmentId!);
      } else {
        _includeSet = true;
        _effect = change.effect!;
        _scopeKind = change.scope!.kind;
        _projects.addAll(change.scope!.projectIds);
        _expiry =
            yorksV1PermissionRequiresImmediateOpenEnded(
              widget.access.catalog.key,
            )
            ? null
            : change.effectiveUntil;
        _hasExpiry = _expiry != null;
      }
    }
  }

  String _t(String key) => YorksV1PermissionStrings.text(widget.language, key);

  @override
  Widget build(BuildContext context) {
    final access = widget.access;
    final availableProjects = widget.projects
        .where((item) => item.hasAccess)
        .toList(growable: false);
    final bothScopes = widget.allowedScopes.length > 1;
    final requiresImmediateOpenEnded =
        yorksV1PermissionRequiresImmediateOpenEnded(access.catalog.key);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .9,
      ),
      child: Material(
        color: AppColors.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl),
          bottom: Radius.circular(AppSpacing.radiusXl),
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _t('edit_access'),
                            style: AppTypography.titleLarge,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '${YorksV1PermissionStrings.module(widget.language, access.catalog.module)} · '
                            '${YorksV1PermissionStrings.action(widget.language, access.catalog.action)}',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: _t('close'),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  children: [
                    if (widget.assignments.isNotEmpty) ...[
                      YorksPermissionSectionTitle(
                        title: _t('custom_assignments'),
                        subtitle: _t('server_confirmed_notice'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      for (final assignment in widget.assignments)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.trailing,
                          value: _clearAssignmentIds.contains(assignment.id),
                          onChanged: (value) => setState(() {
                            if (value == true) {
                              _clearAssignmentIds.add(assignment.id);
                            } else {
                              _clearAssignmentIds.remove(assignment.id);
                            }
                          }),
                          title: Text(
                            '${YorksV1PermissionStrings.effect(widget.language, assignment.effect)} · '
                            '${YorksV1PermissionStrings.scope(widget.language, assignment.scope.kind)}',
                          ),
                          subtitle: Text(
                            assignment.scope.kind ==
                                    YorksV1PermissionScopeKind.organization
                                ? _t('all_projects')
                                : assignment.scope.projectIds
                                      .map((id) => _projectLabel(id))
                                      .join(', '),
                          ),
                          secondary: const Icon(Icons.history_rounded),
                        ),
                      const Divider(height: AppSpacing.xl),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _includeSet,
                      onChanged: (value) => setState(() => _includeSet = value),
                      title: Text(_t('stage_assignment')),
                      subtitle: Text(_t('stage_assignment_help')),
                    ),
                    if (_includeSet) ...[
                      const SizedBox(height: AppSpacing.sm),
                      SegmentedButton<YorksV1PermissionAssignmentEffect>(
                        segments: [
                          ButtonSegment(
                            value: YorksV1PermissionAssignmentEffect.grant,
                            icon: const Icon(Icons.check_rounded),
                            label: Text(
                              YorksV1PermissionStrings.effect(
                                widget.language,
                                YorksV1PermissionAssignmentEffect.grant,
                              ),
                            ),
                          ),
                          ButtonSegment(
                            value: YorksV1PermissionAssignmentEffect.deny,
                            icon: const Icon(Icons.block_rounded),
                            label: Text(
                              YorksV1PermissionStrings.effect(
                                widget.language,
                                YorksV1PermissionAssignmentEffect.deny,
                              ),
                            ),
                          ),
                        ],
                        selected: {_effect},
                        onSelectionChanged: (value) =>
                            setState(() => _effect = value.first),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (bothScopes)
                        SegmentedButton<YorksV1PermissionScopeKind>(
                          segments: [
                            if (widget.allowedScopes.contains(
                              YorksV1PermissionScopeKind.organization,
                            ))
                              ButtonSegment(
                                value: YorksV1PermissionScopeKind.organization,
                                icon: const Icon(Icons.apartment_rounded),
                                label: Text(
                                  YorksV1PermissionStrings.scope(
                                    widget.language,
                                    YorksV1PermissionScopeKind.organization,
                                  ),
                                ),
                              ),
                            if (widget.allowedScopes.contains(
                              YorksV1PermissionScopeKind.project,
                            ))
                              ButtonSegment(
                                value: YorksV1PermissionScopeKind.project,
                                icon: const Icon(Icons.folder_outlined),
                                label: Text(
                                  YorksV1PermissionStrings.scope(
                                    widget.language,
                                    YorksV1PermissionScopeKind.project,
                                  ),
                                ),
                              ),
                          ],
                          selected: {_scopeKind},
                          onSelectionChanged: (value) =>
                              setState(() => _scopeKind = value.first),
                        ),
                      if (_scopeKind == YorksV1PermissionScopeKind.project) ...[
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          _t('select_projects'),
                          style: AppTypography.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        if (availableProjects.isEmpty)
                          Text(
                            _t('no_project_access'),
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.error,
                            ),
                          )
                        else
                          for (final project in availableProjects)
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _projects.contains(project.projectId),
                              onChanged: (value) => setState(() {
                                if (value == true) {
                                  _projects.add(project.projectId);
                                } else {
                                  _projects.remove(project.projectId);
                                }
                              }),
                              title: Text(project.projectRef),
                              subtitle: Text(
                                project.projectName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      if (requiresImmediateOpenEnded)
                        Semantics(
                          container: true,
                          label: _t('continuity_assignment_policy'),
                          child: Container(
                            key: const Key('permission-continuity-policy'),
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: AppColors.primaryContainer,
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusMd,
                              ),
                              border: Border.all(
                                color: AppColors.blueContainerStrong,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.shield_outlined,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    _t('continuity_assignment_policy'),
                                    style: AppTypography.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else ...[
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _hasExpiry,
                          onChanged: (value) => setState(() {
                            _hasExpiry = value;
                            if (!value) _expiry = null;
                          }),
                          title: Text(_t('set_expiry')),
                          subtitle: Text(
                            _expiry == null
                                ? _t('no_expiry')
                                : _dateLabel(_expiry!),
                          ),
                        ),
                        if (_hasExpiry)
                          OutlinedButton.icon(
                            onPressed: _selectExpiry,
                            icon: const Icon(Icons.calendar_today_outlined),
                            label: Text(_t('choose_expiry')),
                          ),
                      ],
                    ],
                    if (_validation != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        _validation!,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: LayoutBuilder(
                  builder: (context, constraints) => constraints.maxWidth < 520
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _stageButton(expanded: true),
                            const SizedBox(height: AppSpacing.sm),
                            Row(
                              children: [
                                Expanded(child: _roleDefaultButton()),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(child: _cancelButton()),
                              ],
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            _roleDefaultButton(),
                            const Spacer(),
                            _cancelButton(),
                            const SizedBox(width: AppSpacing.sm),
                            _stageButton(),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roleDefaultButton() => TextButton(
    onPressed: widget.assignments.isEmpty
        ? null
        : () {
            setState(() {
              _includeSet = false;
              _clearAssignmentIds
                ..clear()
                ..addAll(widget.assignments.map((item) => item.id));
            });
          },
    style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
    child: Text(
      _t('use_role_default'),
      maxLines: 2,
      textAlign: TextAlign.center,
    ),
  );

  Widget _cancelButton() => OutlinedButton(
    onPressed: () => Navigator.pop(context),
    style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
    child: Text(_t('cancel')),
  );

  Widget _stageButton({bool expanded = false}) => FilledButton.icon(
    key: const Key('permission-stage-change'),
    onPressed: _stage,
    style: FilledButton.styleFrom(
      minimumSize: Size(expanded ? double.infinity : 44, 44),
    ),
    icon: const Icon(Icons.playlist_add_check_rounded),
    label: Text(_t('stage_change')),
  );

  String _projectLabel(String id) {
    for (final project in widget.projects) {
      if (project.projectId == id) return project.projectRef;
    }
    return id;
  }

  String _dateLabel(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  Future<void> _selectExpiry() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _expiry?.toLocal() ?? now.add(const Duration(days: 30)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _expiry = DateTime.utc(
        selected.year,
        selected.month,
        selected.day,
        23,
        59,
        59,
      );
    });
  }

  void _stage() {
    if (!_includeSet && _clearAssignmentIds.isEmpty) {
      setState(() => _validation = _t('no_change_selected'));
      return;
    }
    if (_includeSet &&
        _scopeKind == YorksV1PermissionScopeKind.project &&
        _projects.isEmpty) {
      setState(() => _validation = _t('select_at_least_one_project'));
      return;
    }
    final requiresImmediateOpenEnded =
        yorksV1PermissionRequiresImmediateOpenEnded(widget.access.catalog.key);
    if (_includeSet &&
        !requiresImmediateOpenEnded &&
        _hasExpiry &&
        _expiry == null) {
      setState(() => _validation = _t('choose_expiry'));
      return;
    }
    final changes = <_StagedPermissionChange>[
      for (final assignment in widget.assignments)
        if (_clearAssignmentIds.contains(assignment.id))
          _StagedPermissionChange.clear(
            access: widget.access,
            assignment: assignment,
          ),
      if (_includeSet)
        _StagedPermissionChange.set(
          access: widget.access,
          effect: _effect,
          scope: YorksV1PermissionScope(
            kind: _scopeKind,
            projectIds: _scopeKind == YorksV1PermissionScopeKind.project
                ? (_projects.toList()..sort())
                : const [],
          ),
          effectiveUntil: requiresImmediateOpenEnded
              ? null
              : (_hasExpiry ? _expiry : null),
        ),
    ];
    Navigator.pop(context, _PermissionEditResult(changes));
  }
}

class _WorkforceResponsibilityDialog extends StatefulWidget {
  const _WorkforceResponsibilityDialog({required this.language});

  final AppLanguage language;

  @override
  State<_WorkforceResponsibilityDialog> createState() =>
      _WorkforceResponsibilityDialogState();
}

class _WorkforceResponsibilityDialogState
    extends State<_WorkforceResponsibilityDialog> {
  final _reasonController = TextEditingController();
  String? _validation;

  String _t(String key) => YorksV1PermissionStrings.text(widget.language, key);

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('permission-workforce-responsibility-dialog'),
    title: Text(_t('assign_workforce_responsibility_title')),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_t('assign_workforce_responsibility_body')),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('workforce-responsibility-reason'),
              controller: _reasonController,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: _t('reason'),
                hintText: _t('reason_hint'),
                errorText: _validation,
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(_t('cancel')),
      ),
      FilledButton(
        key: const Key('confirm-workforce-responsibility'),
        onPressed: _confirm,
        child: Text(_t('assign_workforce_responsibility')),
      ),
    ],
  );

  void _confirm() {
    final reason = _reasonController.text.trim();
    if (reason.length < 8) {
      setState(() => _validation = _t('reason_required'));
      return;
    }
    Navigator.pop(context, reason);
  }
}

class _ReviewPermissionChangesDialog extends StatefulWidget {
  const _ReviewPermissionChangesDialog({
    required this.language,
    required this.workspace,
    required this.changes,
    required this.offerWorkforceResponsibility,
  });

  final AppLanguage language;
  final YorksV1UserPermissionWorkspace workspace;
  final List<_StagedPermissionChange> changes;
  final bool offerWorkforceResponsibility;

  @override
  State<_ReviewPermissionChangesDialog> createState() =>
      _ReviewPermissionChangesDialogState();
}

class _ReviewPermissionChangesDialogState
    extends State<_ReviewPermissionChangesDialog> {
  final _reasonController = TextEditingController();
  String? _reasonError;
  late bool _assignWorkforceResponsibility;

  @override
  void initState() {
    super.initState();
    _assignWorkforceResponsibility = widget.offerWorkforceResponsibility;
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  String _t(String key) => YorksV1PermissionStrings.text(widget.language, key);

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('permission-review-dialog'),
    insetPadding: const EdgeInsets.all(AppSpacing.md),
    backgroundColor: AppColors.surfaceContainerLowest,
    title: Row(
      children: [
        const Icon(Icons.fact_check_outlined, color: AppColors.blue),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(_t('review_change'))),
      ],
    ),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680, maxHeight: 620),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WorkspaceBanner(
              icon: Icons.verified_user_outlined,
              title: _t(
                'revision',
              ).replaceAll('{revision}', '${widget.workspace.revision}'),
              body: _t('server_confirmed_notice'),
              tone: _BannerTone.info,
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final draft in widget.changes) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${YorksV1PermissionStrings.module(widget.language, draft.module)} · '
                      '${YorksV1PermissionStrings.action(widget.language, draft.action)}',
                      style: AppTypography.labelLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      draft.change.operation ==
                              YorksV1PermissionChangeOperation.clear
                          ? _t('use_role_default')
                          : '${YorksV1PermissionStrings.effect(widget.language, draft.change.effect!)} · '
                                '${YorksV1PermissionStrings.scope(widget.language, draft.change.scope!.kind)}',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    if (draft.change.scope?.projectIds.isNotEmpty == true) ...[
                      const SizedBox(height: 3),
                      Text(
                        draft.change.scope!.projectIds
                            .map((id) => _projectLabel(id))
                            .join(', '),
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                    if (draft.requiredByCapabilityKey != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _t('permission_dependency_added').replaceAll(
                          '{permission}',
                          _capabilityLabel(draft.requiredByCapabilityKey!),
                        ),
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.blue,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (widget.offerWorkforceResponsibility) ...[
              const SizedBox(height: AppSpacing.sm),
              CheckboxListTile(
                key: const Key('permission-include-workforce-responsibility'),
                value: _assignWorkforceResponsibility,
                onChanged: (value) => setState(
                  () => _assignWorkforceResponsibility = value ?? false,
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text(_t('include_workforce_responsibility')),
                subtitle: Text(_t('include_workforce_responsibility_help')),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('permission-change-reason'),
              controller: _reasonController,
              autofocus: true,
              minLines: 3,
              maxLines: 5,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: _t('reason'),
                hintText: _t('reason_hint'),
                errorText: _reasonError,
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
        child: Text(_t('cancel')),
      ),
      FilledButton.icon(
        key: const Key('permission-confirm-save'),
        onPressed: _confirm,
        style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
        icon: const Icon(Icons.shield_outlined),
        label: Text(_t('save_change')),
      ),
    ],
  );

  String _projectLabel(String id) {
    for (final project in widget.workspace.projects) {
      if (project.projectId == id) return project.projectRef;
    }
    return id;
  }

  String _capabilityLabel(String key) {
    for (final access in widget.workspace.catalog) {
      if (access.catalog.key == key) {
        return '${YorksV1PermissionStrings.module(widget.language, access.catalog.module)} · '
            '${YorksV1PermissionStrings.action(widget.language, access.catalog.action)}';
      }
    }
    return key;
  }

  void _confirm() {
    final reason = _reasonController.text.trim();
    if (reason.length < 8) {
      setState(() => _reasonError = _t('reason_required'));
      return;
    }
    Navigator.pop(
      context,
      _PermissionReviewResult(
        reason: reason,
        assignOrganizationWorkforceResponsibility:
            _assignWorkforceResponsibility,
      ),
    );
  }
}

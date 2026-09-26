import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/controllers/yorks_v1_boq_controller.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_boq.dart';
import '../../../../shared/models/yorks_v1_boq_strings.dart';
import '../../../../shared/models/yorks_v1_boq_workbook.dart';
import '../../../../shared/models/yorks_v1_document_strings.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/models/yorks_v1_material_request.dart';
import '../../../../shared/models/yorks_v1_material_request_strings.dart';
import '../../../../shared/models/yorks_v1_permission_management.dart';
import '../../../../shared/models/yorks_v1_project_strings.dart';
import '../../../../shared/models/yorks_v1_role.dart';
import '../../../../shared/models/yorks_v1_shell_strings.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/permissions_provider.dart';
import '../../../../shared/providers/yorks_v1_boq_provider.dart';
import '../../../../shared/providers/yorks_v1_boq_repository_provider.dart';
import '../../../../shared/providers/yorks_v1_boq_workbook_provider.dart';
import '../../../../shared/providers/yorks_v1_feature_flags_provider.dart';
import '../../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../../../shared/providers/yorks_v1_material_request_provider.dart';
import '../../../../shared/providers/yorks_v1_permission_provider.dart';
import '../../../../shared/services/yorks_v1_boq_workbook_service.dart';
import '../../../../shared/services/yorks_v1_boq_document_service.dart';
import '../../../../shared/services/analytics_service.dart';
import '../../../materials/presentation/yorks_v1_feature_action_access.dart';

/// Ordered BOQ folder view for the normalized R35 project workspace.
///
/// [embedded] lets the project workspace keep its own project header, tabs and
/// persistent office shell while showing the same connected BOQ folders. It is
/// not a second data path: create, export and worksheet navigation still use
/// the same protected repositories and routes.
class YorksV1BoqGroupsScreen extends ConsumerWidget {
  const YorksV1BoqGroupsScreen({
    super.key,
    required this.projectId,
    this.embedded = false,
  });

  final String projectId;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final role = ref.watch(yorksV1CurrentRoleProvider);
    final permissionState = ref.watch(yorksV1CurrentPermissionSnapshotProvider);
    final canRead = yorksV1CanReadProjectRecord(
      permissionState,
      YorksV1CapabilityKeys.boqView,
      legacyAllowed: role != null,
      projectId: projectId,
    );
    if (!canRead) {
      final denied = YorksV1ProjectReadBoundary(
        allowed: false,
        language: language,
        child: const SizedBox.shrink(),
      );
      if (embedded) return denied;
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(top: false, child: denied),
      );
    }
    final scopeOptions = ref.watch(
      yorksV1MaterialRequestScopesProvider(projectId),
    );
    final selectedScopeId = ref.watch(
      yorksV1BoqScopeSelectionProvider(projectId),
    );
    final groupQuery = YorksV1BoqScopeQuery(
      projectId: projectId,
      scopeId: selectedScopeId,
    );
    final groups = ref.watch(yorksV1ScopedBoqGroupsProvider(groupQuery));
    final legacyEditable = role != null && role != YorksV1Role.procurement;
    final editAccess = yorksV1FeatureActionAccess(
      permissionState,
      YorksV1CapabilityKeys.boqEdit,
      legacyAllowed: legacyEditable,
      projectId: projectId,
    );
    final folderAccess = yorksV1FeatureActionAccess(
      permissionState,
      YorksV1CapabilityKeys.boqManageFolders,
      legacyAllowed: role?.isEngineering == true || role == YorksV1Role.admin,
      projectId: projectId,
    );
    final requestCreateAccess = yorksV1FeatureActionAccess(
      permissionState,
      YorksV1CapabilityKeys.materialRequestsCreate,
      legacyAllowed: role?.canCreateMaterialRequest == true,
      projectId: projectId,
    );
    final editable = editAccess.canWrite;
    final showEditActions = editAccess.isVisible;
    final isAllAggregate = selectedScopeId == null;
    final canManageSelectedScope = folderAccess.canWrite && !isAllAggregate;
    final showManageSelectedScope = folderAccess.isVisible && !isAllAggregate;
    final selectedRealScopeId = selectedScopeId;
    final requestsEnabled = ref.watch(yorksV1FeatureFlagsProvider).requests;
    final documentsEnabled = ref.watch(yorksV1FeatureFlagsProvider).documents;
    final excelEnabled = ref.watch(yorksV1FeatureFlagsProvider).excel;
    final canViewCommercials = ref.watch(canViewCommercialsProvider);
    final compactRoute =
        MediaQuery.sizeOf(context).width < AppSpacing.yorksV1DesktopBreakpoint;
    final scopeSelector = _BoqScopeSelector(
      scopes: scopeOptions.valueOrNull ?? const [],
      selectedScopeId: selectedScopeId,
      onChanged: (scopeId) =>
          ref.read(yorksV1BoqScopeSelectionProvider(projectId).notifier).state =
              scopeId,
    );
    final realScopes = scopeOptions.valueOrNull ?? const [];
    void selectScope(String scopeId) {
      ref.read(yorksV1BoqScopeSelectionProvider(projectId).notifier).state =
          scopeId;
    }

    Future<void> assignLegacyScope(YorksV1BoqGroup group) =>
        _assignLegacyScope(context, ref, group, realScopes);

    final onAssignLegacyScope = editable ? assignLegacyScope : null;

    if (embedded) {
      return _EmbeddedBoqGroupsWorkspace(
        projectId: projectId,
        language: language,
        groups: groups,
        scopes: realScopes,
        scopeSelector: scopeSelector,
        isAllAggregate: isAllAggregate,
        editable: editable && !isAllAggregate,
        showEditActions: showEditActions && !isAllAggregate,
        canManageFolders: canManageSelectedScope,
        showManageFolders: showManageSelectedScope,
        excelEnabled: excelEnabled,
        onSelectScope: selectScope,
        onAssignLegacyScope: onAssignLegacyScope,
        onCreateGroup: () => _createGroup(context, ref, selectedRealScopeId),
        onManageFolders: () => _showFolderManager(
          context,
          ref,
          selectedRealScopeId,
          canWrite: canManageSelectedScope,
        ),
        onRenameGroup: (group) => _renameGroup(context, ref, group),
        onArchiveGroup: (group) => _archiveGroup(context, ref, group),
        onExport: () => _exportProjectWorkbook(context, ref, selectedScopeId),
        onPrint: () => _printProjectBoq(
          context,
          ref,
          selectedScopeId,
          canViewCommercials: canViewCommercials,
        ),
        onRetry: () =>
            ref.invalidate(yorksV1ScopedBoqGroupsProvider(groupQuery)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: compactRoute
          ? AppBar(
              backgroundColor: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              title: _CopyText(
                copy: YorksV1BoqStrings.worksheets,
                language: language,
                style: AppTypography.titleLarge.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              actions: [
                if (excelEnabled)
                  IconButton(
                    tooltip: YorksV1BoqStrings.exportWorkbook.primary,
                    onPressed: isAllAggregate
                        ? null
                        : () => _exportProjectWorkbook(
                            context,
                            ref,
                            selectedScopeId,
                          ),
                    icon: const Icon(YorksDataTransferIcons.exportData),
                  ),
                IconButton(
                  tooltip: YorksV1BoqStrings.printBoq.active(language),
                  onPressed: isAllAggregate
                      ? null
                      : () => _printProjectBoq(
                          context,
                          ref,
                          selectedScopeId,
                          canViewCommercials: canViewCommercials,
                        ),
                  icon: const Icon(Icons.print_outlined),
                ),
                if (documentsEnabled)
                  IconButton(
                    tooltip: YorksV1DocumentStrings.documents.primary,
                    onPressed: () => context.push(
                      RoutePaths.yorksV1ProjectDocumentsPath(projectId),
                    ),
                    icon: const Icon(Icons.folder_open_outlined),
                  ),
                if (requestsEnabled)
                  IconButton(
                    tooltip: YorksV1MaterialRequestStrings.requests.primary,
                    onPressed: () => context.push(
                      RoutePaths.yorksV1MaterialRequestsPath(
                        projectId: projectId,
                      ),
                    ),
                    icon: const Icon(Icons.assignment_outlined),
                  ),
                if (requestsEnabled && requestCreateAccess.isVisible)
                  IconButton(
                    tooltip: YorksV1MaterialRequestStrings.newRequest.primary,
                    onPressed: requestCreateAccess.canWrite
                        ? () => context.push(
                            RoutePaths.yorksV1MaterialRequestDraftPath(
                              const Uuid().v4(),
                              projectId: projectId,
                              entryMode:
                                  YorksV1MaterialRequestDraftEntryMode.newDraft,
                            ),
                          )
                        : null,
                    icon: const Icon(Icons.add_task_outlined),
                  ),
              ],
            )
          : null,
      floatingActionButton: compactRoute && showManageSelectedScope
          ? FloatingActionButton.extended(
              key: const ValueKey('boq-manage-folders-mobile'),
              onPressed: canManageSelectedScope
                  ? () => _showFolderManager(
                      context,
                      ref,
                      selectedRealScopeId,
                      canWrite: true,
                    )
                  : null,
              icon: const Icon(Icons.folder_copy_outlined),
              label: Text(YorksV1BoqStrings.manageFolders.active(language)),
            )
          : null,
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!compactRoute) ...[
                YorksR35PageHeader(
                  eyebrow: YorksV1ShellStrings.operationalWorkspace.primary,
                  title: YorksV1BoqStrings.worksheets.primary,
                  description: YorksV1BoqStrings.boqDescription.primary,
                  actions: [
                    if (excelEnabled)
                      SizedBox(
                        height: AppSpacing.controlHeight,
                        child: OutlinedButton.icon(
                          onPressed: isAllAggregate
                              ? null
                              : () => _exportProjectWorkbook(
                                  context,
                                  ref,
                                  selectedScopeId,
                                ),
                          icon: const Icon(
                            YorksDataTransferIcons.exportData,
                            size: 18,
                          ),
                          label: Text(YorksV1BoqStrings.exportWorkbook.primary),
                        ),
                      ),
                    SizedBox(
                      height: AppSpacing.controlHeight,
                      child: OutlinedButton.icon(
                        onPressed: isAllAggregate
                            ? null
                            : () => _printProjectBoq(
                                context,
                                ref,
                                selectedScopeId,
                                canViewCommercials: canViewCommercials,
                              ),
                        icon: const Icon(Icons.print_outlined, size: 18),
                        label: Text(
                          YorksV1BoqStrings.printBoq.active(language),
                        ),
                      ),
                    ),
                    if (requestsEnabled)
                      SizedBox(
                        height: AppSpacing.controlHeight,
                        child: OutlinedButton.icon(
                          onPressed: () => context.push(
                            RoutePaths.yorksV1MaterialRequestsPath(
                              projectId: projectId,
                            ),
                          ),
                          icon: const Icon(Icons.assignment_outlined, size: 18),
                          label: Text(
                            YorksV1MaterialRequestStrings.requests.primary,
                          ),
                        ),
                      ),
                    if (showManageSelectedScope)
                      SizedBox(
                        height: AppSpacing.minTapTarget,
                        child: OutlinedButton.icon(
                          onPressed: canManageSelectedScope
                              ? () => _showFolderManager(
                                  context,
                                  ref,
                                  selectedRealScopeId,
                                  canWrite: true,
                                )
                              : null,
                          icon: const Icon(Icons.folder_copy_outlined),
                          label: Text(
                            YorksV1BoqStrings.manageFolders.active(language),
                          ),
                        ),
                      ),
                    if (showManageSelectedScope)
                      SizedBox(
                        height: AppSpacing.minTapTarget,
                        child: FilledButton.icon(
                          onPressed: canManageSelectedScope
                              ? () => _createGroup(
                                  context,
                                  ref,
                                  selectedRealScopeId,
                                )
                              : null,
                          icon: const Icon(Icons.create_new_folder_outlined),
                          label: Text(YorksV1BoqStrings.newGroup.primary),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
              scopeSelector,
              const SizedBox(height: AppSpacing.md),
              if (isAllAggregate) ...[
                _ReadOnlyAggregateBanner(language: language),
                const SizedBox(height: AppSpacing.md),
              ],
              Expanded(
                child: groups.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => _ErrorState(
                    language: language,
                    onRetry: () => ref.invalidate(
                      yorksV1ScopedBoqGroupsProvider(groupQuery),
                    ),
                  ),
                  data: (items) => _GroupsBody(
                    groups: items,
                    scopes: realScopes,
                    language: language,
                    projectId: projectId,
                    editable: editable && !isAllAggregate,
                    showEditActions: showEditActions && !isAllAggregate,
                    canManageFolders: canManageSelectedScope,
                    showManageFolders: showManageSelectedScope,
                    aggregateReadOnly: isAllAggregate,
                    onSelectScope: selectScope,
                    onAssignLegacyScope: onAssignLegacyScope,
                    onAddGroup: () =>
                        _createGroup(context, ref, selectedRealScopeId),
                    onRenameGroup: (group) => _renameGroup(context, ref, group),
                    onArchiveGroup: (group) =>
                        _archiveGroup(context, ref, group),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createGroup(
    BuildContext context,
    WidgetRef ref,
    String? scopeId,
  ) async {
    if (scopeId == null || scopeId.trim().isEmpty) return;
    final name = await _promptForText(
      context: context,
      title: YorksV1BoqStrings.addGroup,
      label: YorksV1BoqStrings.customGroupName,
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await ref
          .read(yorksV1BoqRepositoryProvider)
          .createCustomGroup(
            YorksV1CreateBoqGroupInput(
              projectId: projectId,
              scopeId: scopeId,
              name: name,
              idempotencyKey: const Uuid().v4(),
            ),
          );
      // Folder creation is scope-local. Refresh the selected scope and the All
      // aggregate, which summarizes every independent Common/building scope.
      _invalidateFolderManagement(ref, projectId, scopeId);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(YorksV1BoqStrings.saveFailed.primary)),
      );
    }
  }

  Future<void> _showFolderManager(
    BuildContext context,
    WidgetRef ref,
    String? scopeId, {
    required bool canWrite,
  }) async {
    if (scopeId == null || scopeId.trim().isEmpty) return;
    final content = _BoqFolderManager(
      projectId: projectId,
      scopeId: scopeId,
      canWrite: canWrite,
      onCreate: () => _createGroup(context, ref, scopeId),
      onRename: (group) => _renameGroup(context, ref, group),
      onArchive: (group) => _archiveGroup(context, ref, group),
      onRestore: (group) => _restoreGroup(context, ref, group),
    );
    if (YorksMobileUi.isActive(context)) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => FractionallySizedBox(heightFactor: 0.9, child: content),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
          child: content,
        ),
      ),
    );
  }

  Future<void> _renameGroup(
    BuildContext context,
    WidgetRef ref,
    YorksV1BoqGroup group,
  ) async {
    final change = await _promptForFolderRename(
      context,
      group,
      ref.read(languageProvider),
    );
    if (change == null || !context.mounted) return;
    try {
      await ref
          .read(yorksV1BoqRepositoryProvider)
          .renameGroup(
            YorksV1RenameBoqGroupInput(
              groupId: group.id,
              expectedVersion: group.version,
              name: change.name,
              reason: change.reason,
              idempotencyKey: const Uuid().v4(),
            ),
          );
      _invalidateFolderManagement(ref, projectId, group.scopeId);
      ref.invalidate(yorksV1BoqWorksheetControllerProvider(group.id));
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(YorksV1BoqStrings.saved.primary)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(YorksV1BoqStrings.saveFailed.primary)),
      );
    }
  }

  Future<void> _archiveGroup(
    BuildContext context,
    WidgetRef ref,
    YorksV1BoqGroup group,
  ) async {
    final reason = await _promptForFolderReason(
      context,
      title: YorksV1BoqStrings.archiveGroup,
      description: YorksV1BoqStrings.archiveGroupConfirmation,
      language: ref.read(languageProvider),
    );
    if (reason == null || !context.mounted) return;
    try {
      await ref
          .read(yorksV1BoqRepositoryProvider)
          .archiveGroup(
            YorksV1ArchiveBoqGroupInput(
              groupId: group.id,
              expectedVersion: group.version,
              reason: reason,
              idempotencyKey: const Uuid().v4(),
            ),
          );
      _invalidateFolderManagement(ref, projectId, group.scopeId);
      ref.invalidate(yorksV1BoqWorksheetControllerProvider(group.id));
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(YorksV1BoqStrings.saved.primary)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(YorksV1BoqStrings.saveFailed.primary)),
      );
    }
  }

  Future<void> _restoreGroup(
    BuildContext context,
    WidgetRef ref,
    YorksV1BoqGroup group,
  ) async {
    final reason = await _promptForFolderReason(
      context,
      title: YorksV1BoqStrings.restoreFolder,
      description: YorksV1BoqStrings.restoreFolderDescription,
      language: ref.read(languageProvider),
    );
    if (reason == null || !context.mounted) return;
    try {
      await ref
          .read(yorksV1BoqRepositoryProvider)
          .restoreGroup(
            YorksV1RestoreBoqGroupInput(
              groupId: group.id,
              expectedVersion: group.version,
              reason: reason,
              idempotencyKey: const Uuid().v4(),
            ),
          );
      _invalidateFolderManagement(ref, projectId, group.scopeId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(YorksV1BoqStrings.saved.primary)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(YorksV1BoqStrings.saveFailed.primary)),
      );
    }
  }

  Future<void> _exportProjectWorkbook(
    BuildContext context,
    WidgetRef ref,
    String? scopeId,
  ) async {
    if (scopeId == null) return;
    try {
      final repository = ref.read(yorksV1BoqRepositoryProvider);
      final groups = (await repository.listGroupsForScope(
        projectId,
        scopeId: scopeId,
      )).where((group) => !group.isArchived).toList(growable: false);
      if (groups.isEmpty) return;
      final worksheets = await Future.wait([
        for (final group in groups) repository.getWorksheet(group.id),
      ]);
      final codec = ref.read(yorksV1BoqWorkbookCodecProvider);
      final saved = await ref
          .read(yorksV1BoqWorkbookFileServiceProvider)
          .saveWorkbook(
            bytes: codec.encodeWorksheets(worksheets),
            suggestedName: 'Yorks_BOQ_${_safeWorkbookName(projectId)}.xlsx',
          );
      if (!context.mounted || !saved) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(YorksV1BoqStrings.exported.primary)),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(YorksV1BoqStrings.exportFailed.primary)),
      );
    }
  }

  Future<void> _printProjectBoq(
    BuildContext context,
    WidgetRef ref,
    String? scopeId, {
    required bool canViewCommercials,
  }) async {
    if (scopeId == null) return;
    try {
      final repository = ref.read(yorksV1BoqRepositoryProvider);
      final groups = (await repository.listGroupsForScope(
        projectId,
        scopeId: scopeId,
      )).where((group) => !group.isArchived).toList(growable: false);
      final worksheets = await Future.wait([
        for (final group in groups) repository.getWorksheet(group.id),
      ]);
      if (worksheets.isEmpty) return;
      await const YorksV1BoqDocumentService().printScope(
        worksheets,
        canViewCommercials: canViewCommercials,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(YorksV1BoqStrings.printFailed.primary)),
      );
    }
  }

  static String _safeWorkbookName(String source) {
    final safe = source
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return safe.isEmpty ? 'project' : safe;
  }

  Future<void> _assignLegacyScope(
    BuildContext context,
    WidgetRef ref,
    YorksV1BoqGroup group,
    List<YorksV1MaterialRequestScopeOption> scopes,
  ) async {
    if (scopes.isEmpty) return;
    final scopeId = await showDialog<String>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (dialogContext) => AlertDialog(
        title: Text(YorksV1BoqStrings.assignLegacyScope.primary),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(YorksV1BoqStrings.assignLegacyScopeDescription.primary),
              const SizedBox(height: AppSpacing.md),
              for (final scope in scopes)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(scope.name),
                  subtitle: Text(scope.kind),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(dialogContext).pop(scope.id),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(YorksV1MaterialRequestStrings.cancel.primary),
          ),
        ],
      ),
    );
    if (scopeId == null || !context.mounted) return;
    try {
      await ref
          .read(yorksV1BoqRepositoryProvider)
          .assignLegacyGroupScope(
            YorksV1AssignLegacyBoqGroupScopeInput(
              groupId: group.id,
              scopeId: scopeId,
              expectedVersion: group.version,
              idempotencyKey: const Uuid().v4(),
            ),
          );
      _invalidateGroupLists(ref, projectId, scopeId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(YorksV1BoqStrings.saved.primary)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(YorksV1BoqStrings.saveFailed.primary)),
      );
    }
  }
}

class _BoqScopeSelector extends StatelessWidget {
  const _BoqScopeSelector({
    required this.scopes,
    required this.selectedScopeId,
    required this.onChanged,
  });

  static const _allValue = '__all_boq_scopes__';

  final List<YorksV1MaterialRequestScopeOption> scopes;
  final String? selectedScopeId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final activeScopes = scopes
        .where((scope) => scope.id.trim().isNotEmpty)
        .toList(growable: false);
    final selectedValue =
        activeScopes.any((scope) => scope.id == selectedScopeId)
        ? selectedScopeId!
        : _allValue;
    if (YorksMobileUi.isActive(context)) {
      return Semantics(
        label: YorksV1BoqStrings.scope.primary,
        child: SizedBox(
          height: 58,
          child: ListView.separated(
            key: const ValueKey('boq-scope-selector-mobile'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            itemCount: activeScopes.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, index) {
              final isOverview = index == 0;
              final scope = isOverview ? null : activeScopes[index - 1];
              final value = scope?.id ?? _allValue;
              final selected = value == selectedValue;
              final label = isOverview
                  ? YorksV1BoqStrings.allScopes.primary
                  : scope!.name;
              return Semantics(
                button: true,
                selected: selected,
                child: OutlinedButton(
                  key: ValueKey('boq-mobile-scope-$value'),
                  onPressed: () => onChanged(isOverview ? null : scope!.id),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(112, AppSpacing.minTapTarget),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm,
                    ),
                    foregroundColor: selected
                        ? AppColors.blue
                        : AppColors.inkSecondary,
                    backgroundColor: selected
                        ? AppColors.surfaceContainerLowest
                        : AppColors.mobileSurface,
                    side: BorderSide(
                      color: selected ? AppColors.blue : AppColors.line,
                      width: selected ? 1.5 : 1,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    ),
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }
    return Semantics(
      label: YorksV1BoqStrings.scope.primary,
      child: Container(
        key: const ValueKey('boq-scope-command'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          children: [
            Text(
              YorksV1BoqStrings.scope.primary,
              style: AppTypography.labelLarge.copyWith(
                color: AppColors.inkSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            SizedBox(
              width: 350,
              child: DropdownButtonFormField<String>(
                key: ValueKey('boq-scope-selector:$selectedValue'),
                initialValue: selectedValue,
                isExpanded: true,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(
                    Icons.apartment_outlined,
                    size: 19,
                    color: AppColors.blue,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                ),
                items: [
                  DropdownMenuItem(
                    value: _allValue,
                    child: Text(YorksV1BoqStrings.allScopes.primary),
                  ),
                  for (final scope in activeScopes)
                    DropdownMenuItem(value: scope.id, child: Text(scope.name)),
                ],
                onChanged: (value) =>
                    onChanged(value == _allValue ? null : value),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyAggregateBanner extends StatelessWidget {
  const _ReadOnlyAggregateBanner({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    if (YorksMobileUi.isActive(context)) {
      return YorksMobileCard(
        color: AppColors.mobileSurface,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: AppSpacing.massive,
              height: AppSpacing.massive,
              decoration: BoxDecoration(
                color: AppColors.blueContainer,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: const Icon(
                Icons.info_outline_rounded,
                color: AppColors.blue,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CopyText(
                    copy: YorksV1BoqStrings.independentBoqTitle,
                    language: language,
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _CopyText(
                    copy: YorksV1BoqStrings.independentBoqDescription,
                    language: language,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.muted,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return NexusSectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.visibility_outlined, color: AppColors.blue),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _CopyText(
              copy: YorksV1BoqStrings.allScopesDescription,
              language: language,
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupsBody extends StatelessWidget {
  const _GroupsBody({
    required this.groups,
    this.scopes = const [],
    required this.language,
    required this.projectId,
    required this.editable,
    required this.showEditActions,
    required this.canManageFolders,
    required this.showManageFolders,
    required this.onAddGroup,
    required this.onRenameGroup,
    required this.onArchiveGroup,
    this.aggregateReadOnly = false,
    this.embedded = false,
    this.onSelectScope,
    this.onAssignLegacyScope,
  });

  final List<YorksV1BoqGroup> groups;
  final List<YorksV1MaterialRequestScopeOption> scopes;
  final AppLanguage language;
  final String projectId;
  final bool editable;
  final bool showEditActions;
  final bool canManageFolders;
  final bool showManageFolders;
  final VoidCallback? onAddGroup;
  final ValueChanged<YorksV1BoqGroup> onRenameGroup;
  final ValueChanged<YorksV1BoqGroup> onArchiveGroup;
  final bool aggregateReadOnly;
  final bool embedded;
  final ValueChanged<String>? onSelectScope;
  final ValueChanged<YorksV1BoqGroup>? onAssignLegacyScope;

  @override
  Widget build(BuildContext context) {
    if (aggregateReadOnly) {
      return _BoqScopeOverview(
        groups: groups,
        scopes: scopes,
        language: language,
        embedded: embedded,
        onSelectScope: onSelectScope,
        onAssignLegacyScope: onAssignLegacyScope,
      );
    }
    if (groups.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: NexusSectionCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.folder_off_outlined,
                  size: 42,
                  color: AppColors.muted,
                ),
                const SizedBox(height: AppSpacing.lg),
                _CopyText(
                  copy: YorksV1BoqStrings.noGroups,
                  language: language,
                  center: true,
                ),
                if (showEditActions) ...[
                  const SizedBox(height: AppSpacing.lg),
                  PrimaryButton(
                    label: YorksV1BoqStrings.addGroup.primary,
                    icon: Icons.add_rounded,
                    onPressed: onAddGroup,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    if (YorksMobileUi.isActive(context)) {
      return _MobileBoqFolderList(
        groups: groups,
        language: language,
        embedded: embedded,
        onOpen: (group) => context.push(
          RoutePaths.yorksV1BoqWorksheetPath(projectId, group.id),
        ),
        canManageFolders: canManageFolders,
        showManageFolders: showManageFolders,
        onRename: onRenameGroup,
        onArchive: onArchiveGroup,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final count = constraints.maxWidth >= 1120
            ? 3
            : constraints.maxWidth >= 700
            ? 2
            : 1;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CopyText(
              copy: YorksV1BoqStrings.boqDescription,
              language: language,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (embedded)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: count,
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisSpacing: AppSpacing.md,
                  mainAxisExtent: 270,
                ),
                itemCount: groups.length,
                itemBuilder: (context, index) {
                  final group = groups[index];
                  return _BoqGroupCard(
                    group: group,
                    language: language,
                    aggregateReadOnly: aggregateReadOnly,
                    onOpen: aggregateReadOnly
                        ? null
                        : () => context.push(
                            RoutePaths.yorksV1BoqWorksheetPath(
                              projectId,
                              group.id,
                            ),
                          ),
                    canManageFolders: canManageFolders,
                    showManageFolders: showManageFolders,
                    onRename: () => onRenameGroup(group),
                    onArchive: group.isCustom
                        ? () => onArchiveGroup(group)
                        : null,
                  );
                },
              )
            else
              Expanded(
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: count,
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisSpacing: AppSpacing.md,
                    mainAxisExtent: 270,
                  ),
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    return _BoqGroupCard(
                      group: group,
                      language: language,
                      aggregateReadOnly: aggregateReadOnly,
                      onOpen: aggregateReadOnly
                          ? null
                          : () => context.push(
                              RoutePaths.yorksV1BoqWorksheetPath(
                                projectId,
                                group.id,
                              ),
                            ),
                      canManageFolders: canManageFolders,
                      showManageFolders: showManageFolders,
                      onRename: () => onRenameGroup(group),
                      onArchive: group.isCustom
                          ? () => onArchiveGroup(group)
                          : null,
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

enum _MobileFolderFilter { all, started, empty }

class _MobileBoqFolderList extends StatefulWidget {
  const _MobileBoqFolderList({
    required this.groups,
    required this.language,
    required this.embedded,
    required this.onOpen,
    required this.canManageFolders,
    required this.showManageFolders,
    required this.onRename,
    required this.onArchive,
  });

  final List<YorksV1BoqGroup> groups;
  final AppLanguage language;
  final bool embedded;
  final ValueChanged<YorksV1BoqGroup> onOpen;
  final bool canManageFolders;
  final bool showManageFolders;
  final ValueChanged<YorksV1BoqGroup> onRename;
  final ValueChanged<YorksV1BoqGroup> onArchive;

  @override
  State<_MobileBoqFolderList> createState() => _MobileBoqFolderListState();
}

class _MobileBoqFolderListState extends State<_MobileBoqFolderList> {
  _MobileFolderFilter _filter = _MobileFolderFilter.all;

  @override
  Widget build(BuildContext context) {
    final started = widget.groups.where((group) => group.rowCount > 0).length;
    final empty = widget.groups.length - started;
    final filtered = switch (_filter) {
      _MobileFolderFilter.all => widget.groups,
      _MobileFolderFilter.started =>
        widget.groups
            .where((group) => group.rowCount > 0)
            .toList(growable: false),
      _MobileFolderFilter.empty =>
        widget.groups
            .where((group) => group.rowCount == 0)
            .toList(growable: false),
    };
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CopyText(
          copy: YorksV1BoqStrings.materialFolders,
          language: widget.language,
          style: AppTypography.headlineMedium.copyWith(
            fontSize: 26,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _CopyText(
          copy: YorksV1BoqStrings.materialFoldersDescription,
          language: widget.language,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.muted,
            height: 1.45,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _MobileFolderFilterButton(
                label:
                    '${YorksV1BoqStrings.allFolders.primary} ${widget.groups.length}',
                selected: _filter == _MobileFolderFilter.all,
                onPressed: () =>
                    setState(() => _filter = _MobileFolderFilter.all),
              ),
              const SizedBox(width: AppSpacing.sm),
              _MobileFolderFilterButton(
                label: '${YorksV1BoqStrings.startedFolders.primary} $started',
                selected: _filter == _MobileFolderFilter.started,
                onPressed: () =>
                    setState(() => _filter = _MobileFolderFilter.started),
              ),
              const SizedBox(width: AppSpacing.sm),
              _MobileFolderFilterButton(
                label: '${YorksV1BoqStrings.emptyFolders.primary} $empty',
                selected: _filter == _MobileFolderFilter.empty,
                onPressed: () =>
                    setState(() => _filter = _MobileFolderFilter.empty),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );

    Widget row(YorksV1BoqGroup group) => _MobileBoqFolderRow(
      group: group,
      onTap: () => widget.onOpen(group),
      canManageFolders: widget.canManageFolders,
      showManageFolders: widget.showManageFolders,
      onRename: () => widget.onRename(group),
      onArchive: group.isCustom ? () => widget.onArchive(group) : null,
    );

    if (widget.embedded) {
      return Column(
        key: const ValueKey('boq-mobile-folder-list'),
        children: [
          header,
          for (var index = 0; index < filtered.length; index++) ...[
            row(filtered[index]),
            if (index != filtered.length - 1)
              const SizedBox(height: AppSpacing.sm),
          ],
        ],
      );
    }
    return ListView.builder(
      key: const ValueKey('boq-mobile-folder-list'),
      padding: const EdgeInsets.only(bottom: AppSpacing.colossal),
      itemCount: filtered.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return header;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: row(filtered[index - 1]),
        );
      },
    );
  }
}

class _MobileFolderFilterButton extends StatelessWidget {
  const _MobileFolderFilterButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, AppSpacing.minTapTarget),
      foregroundColor: selected ? AppColors.blue : AppColors.muted,
      backgroundColor: selected
          ? AppColors.blueContainer
          : AppColors.surfaceContainerLowest,
      side: BorderSide(color: selected ? AppColors.blue : AppColors.line),
      shape: const StadiumBorder(),
    ),
    child: Text(label),
  );
}

class _MobileBoqFolderRow extends StatelessWidget {
  const _MobileBoqFolderRow({
    required this.group,
    required this.onTap,
    required this.canManageFolders,
    required this.showManageFolders,
    required this.onRename,
    this.onArchive,
  });

  final YorksV1BoqGroup group;
  final VoidCallback onTap;
  final bool canManageFolders;
  final bool showManageFolders;
  final VoidCallback onRename;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) => YorksMobileCard(
    padding: EdgeInsets.zero,
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 88),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Container(
              width: AppSpacing.massive,
              height: AppSpacing.massive,
              decoration: BoxDecoration(
                color: group.isCustom
                    ? AppColors.purpleContainer
                    : AppColors.blueContainer,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Icon(
                group.isCustom
                    ? Icons.folder_special_outlined
                    : Icons.folder_outlined,
                color: group.isCustom ? AppColors.purple : AppColors.blue,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${group.displayOrder.toString().padLeft(2, '0')} · ${group.name}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    group.worksheetTitle.trim().isNotEmpty &&
                            group.worksheetTitle.trim() != group.name.trim()
                        ? group.worksheetTitle.trim()
                        : '${group.rowCount} ${YorksV1BoqStrings.materials.primary.toLowerCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                  if (group.worksheetTitle.trim().isNotEmpty &&
                      group.worksheetTitle.trim() != group.name.trim()) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${group.rowCount} ${YorksV1BoqStrings.materials.primary.toLowerCase()} · '
                      '${group.linkedRequestCount} ${YorksV1BoqStrings.linkedRequests.primary.toLowerCase()} · '
                      '${group.documentCount} ${YorksV1DocumentStrings.documents.primary.toLowerCase()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            if (showManageFolders)
              _BoqFolderActionsMenu(
                canWrite: canManageFolders,
                onOpen: onTap,
                onRename: onRename,
                onArchive: onArchive,
              )
            else
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    ),
  );
}

/// The Overview selector is deliberately a summary rather than a flattened
/// worksheet. It lets an engineer assess every independent scope at once
/// without creating an ambiguous cross-building edit or MR source.
class _BoqScopeOverview extends StatelessWidget {
  const _BoqScopeOverview({
    required this.groups,
    this.scopes = const [],
    required this.language,
    required this.embedded,
    this.onSelectScope,
    this.onAssignLegacyScope,
  });

  final List<YorksV1BoqGroup> groups;
  final List<YorksV1MaterialRequestScopeOption> scopes;
  final AppLanguage language;
  final bool embedded;
  final ValueChanged<String>? onSelectScope;
  final ValueChanged<YorksV1BoqGroup>? onAssignLegacyScope;

  @override
  Widget build(BuildContext context) {
    final summaries = <String, _BoqScopeSummary>{};
    final legacyGroups = <YorksV1BoqGroup>[];
    final orderedScopes = [...scopes]
      ..sort((left, right) {
        if (left.isCommon != right.isCommon) return left.isCommon ? -1 : 1;
        return left.name.toLowerCase().compareTo(right.name.toLowerCase());
      });
    for (final scope in orderedScopes) {
      if (scope.id.trim().isEmpty) continue;
      summaries.putIfAbsent(
        scope.id,
        () => _BoqScopeSummary(scopeId: scope.id, scopeName: scope.name),
      );
    }
    for (final group in groups) {
      final scopeId = group.scopeId;
      if (!group.isScopeAssigned || scopeId == null) {
        legacyGroups.add(group);
        continue;
      }
      final summary = summaries.putIfAbsent(
        scopeId,
        () => _BoqScopeSummary(
          scopeId: scopeId,
          scopeName: group.scopeName ?? group.scopeCode ?? scopeId,
        ),
      );
      summary.add(group);
    }
    if (YorksMobileUi.isActive(context)) {
      return _MobileBoqScopeOverview(
        summaries: summaries.values.toList(growable: false),
        legacyGroups: legacyGroups,
        language: language,
        embedded: embedded,
        onSelectScope: onSelectScope,
        onAssignLegacyScope: onAssignLegacyScope,
      );
    }
    final recentGroups = [...groups]
      ..sort((left, right) {
        final leftTime = left.lastEditedAt ?? left.updatedAt;
        final rightTime = right.lastEditedAt ?? right.updatedAt;
        return rightTime.compareTo(leftTime);
      });
    final children = <Widget>[
      _BoqOverviewMetricStrip(
        groups: groups,
        scopeCount: summaries.length,
        language: language,
      ),
      const SizedBox(height: AppSpacing.xl),
      _BoqSectionHeading(
        title: YorksV1BoqStrings.buildingsAndScopes,
        description: YorksV1BoqStrings.independentBoqDescription,
        language: language,
      ),
      const SizedBox(height: AppSpacing.md),
      LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = constraints.maxWidth >= 980
              ? (constraints.maxWidth - (AppSpacing.md * 2)) / 3
              : constraints.maxWidth >= 640
              ? (constraints.maxWidth - AppSpacing.md) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              for (final summary in summaries.values)
                SizedBox(
                  width: cardWidth,
                  child: _BoqScopeSummaryCard(
                    summary: summary,
                    language: language,
                    onOpen: onSelectScope == null
                        ? null
                        : () => onSelectScope!(summary.scopeId),
                  ),
                ),
            ],
          );
        },
      ),
      if (recentGroups.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.xl),
        _BoqSectionHeading(
          title: YorksV1BoqStrings.recentGroups,
          description: YorksV1BoqStrings.boqDescription,
          language: language,
        ),
        const SizedBox(height: AppSpacing.md),
        _BoqRecentGroupsTable(
          groups: recentGroups.take(5).toList(growable: false),
          language: language,
          onSelectScope: onSelectScope,
        ),
      ],
    ];
    if (legacyGroups.isNotEmpty) {
      children.addAll([
        const SizedBox(height: AppSpacing.xl),
        _CopyText(
          copy: YorksV1BoqStrings.legacyBoqs,
          language: language,
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final group in legacyGroups) ...[
          _LegacyBoqScopeCard(
            group: group,
            language: language,
            onAssign: onAssignLegacyScope == null
                ? null
                : () => onAssignLegacyScope!(group),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ]);
    }
    if (summaries.isEmpty && legacyGroups.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xl),
          child: _CopyText(
            copy: YorksV1BoqStrings.noGroups,
            language: language,
          ),
        ),
      );
    }
    return embedded
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          )
        : ListView(children: children);
  }
}

class _BoqOverviewMetricStrip extends StatelessWidget {
  const _BoqOverviewMetricStrip({
    required this.groups,
    required this.scopeCount,
    required this.language,
  });

  final List<YorksV1BoqGroup> groups;
  final int scopeCount;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final metrics = <({IconData icon, Color color, int value, String label})>[
      (
        icon: Icons.apartment_outlined,
        color: AppColors.blue,
        value: scopeCount,
        label: YorksV1MaterialRequestStrings.scopes.active(language),
      ),
      (
        icon: Icons.folder_outlined,
        color: AppColors.purple,
        value: groups.length,
        label: YorksV1BoqStrings.groupsMetric.active(language),
      ),
      (
        icon: Icons.table_rows_outlined,
        color: AppColors.success,
        value: groups.fold(0, (total, group) => total + group.rowCount),
        label: YorksV1BoqStrings.materialRowsMetric.active(language),
      ),
      (
        icon: Icons.link_rounded,
        color: AppColors.warning,
        value: groups.fold(
          0,
          (total, group) => total + group.linkedRequestCount,
        ),
        label: YorksV1BoqStrings.linkedRequests.active(language),
      ),
      (
        icon: Icons.description_outlined,
        color: AppColors.inkSecondary,
        value: groups.fold(0, (total, group) => total + group.documentCount),
        label: YorksV1BoqStrings.linkedDocuments.active(language),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1040
            ? 5
            : constraints.maxWidth >= 680
            ? 3
            : 2;
        final width =
            (constraints.maxWidth - ((columns - 1) * AppSpacing.sm)) / columns;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: _BoqOverviewMetricCard(
                  icon: metric.icon,
                  color: metric.color,
                  value: metric.value,
                  label: metric.label,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BoqOverviewMetricCard extends StatelessWidget {
  const _BoqOverviewMetricCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 88),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Row(
      children: [
        Container(
          width: AppSpacing.massive,
          height: AppSpacing.massive,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: AppTypography.titleLarge.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _BoqSectionHeading extends StatelessWidget {
  const _BoqSectionHeading({
    required this.title,
    required this.description,
    required this.language,
  });

  final TranslatableString title;
  final TranslatableString description;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title.active(language),
        style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        description.active(language),
        style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
      ),
    ],
  );
}

class _BoqRecentGroupsTable extends StatelessWidget {
  const _BoqRecentGroupsTable({
    required this.groups,
    required this.language,
    this.onSelectScope,
  });

  final List<YorksV1BoqGroup> groups;
  final AppLanguage language;
  final ValueChanged<String>? onSelectScope;

  @override
  Widget build(BuildContext context) {
    final headers = [
      YorksV1BoqStrings.groupName.active(language),
      YorksV1BoqStrings.scope.active(language),
      YorksV1BoqStrings.rows.active(language),
      YorksV1BoqStrings.linkedRequests.active(language),
      YorksV1BoqStrings.lastEdited.active(language),
      YorksV1BoqStrings.editedBy.active(language),
    ];
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            color: AppColors.surfaceContainerLow,
            child: Row(
              children: [
                for (var index = 0; index < headers.length; index++)
                  Expanded(
                    flex: index == 0 ? 2 : 1,
                    child: Text(
                      headers[index],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.inkSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          for (var index = 0; index < groups.length; index++)
            _BoqRecentGroupRow(
              group: groups[index],
              language: language,
              showDivider: index != groups.length - 1,
              onTap: groups[index].scopeId == null || onSelectScope == null
                  ? null
                  : () => onSelectScope!(groups[index].scopeId!),
            ),
        ],
      ),
    );
  }
}

class _BoqRecentGroupRow extends StatelessWidget {
  const _BoqRecentGroupRow({
    required this.group,
    required this.language,
    required this.showDivider,
    this.onTap,
  });

  final YorksV1BoqGroup group;
  final AppLanguage language;
  final bool showDivider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final editedAt = (group.lastEditedAt ?? group.updatedAt).toLocal();
    final date = MaterialLocalizations.of(context).formatShortDate(editedAt);
    final cells = <Widget>[
      Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.blueContainer,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: const Icon(
              Icons.folder_outlined,
              size: 18,
              color: AppColors.blue,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (group.effectiveTitle != group.name)
                  Text(
                    group.effectiveTitle,
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
      Text(group.scopeName ?? group.scopeCode ?? '—'),
      Text('${group.rowCount}'),
      Text('${group.linkedRequestCount}'),
      Text(date),
      Text(group.lastEditedBy ?? group.lastEditedRole ?? '—'),
    ];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            border: showDivider
                ? const Border(bottom: BorderSide(color: AppColors.line))
                : null,
          ),
          child: Row(
            children: [
              for (var index = 0; index < cells.length; index++)
                Expanded(
                  flex: index == 0 ? 2 : 1,
                  child: DefaultTextStyle(
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.inkSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: cells[index],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileBoqScopeOverview extends StatelessWidget {
  const _MobileBoqScopeOverview({
    required this.summaries,
    required this.legacyGroups,
    required this.language,
    required this.embedded,
    this.onSelectScope,
    this.onAssignLegacyScope,
  });

  final List<_BoqScopeSummary> summaries;
  final List<YorksV1BoqGroup> legacyGroups;
  final AppLanguage language;
  final bool embedded;
  final ValueChanged<String>? onSelectScope;
  final ValueChanged<YorksV1BoqGroup>? onAssignLegacyScope;

  @override
  Widget build(BuildContext context) {
    final content = <Widget>[
      for (final summary in summaries) ...[
        _MobileBoqScopeCard(
          summary: summary,
          onTap: onSelectScope == null
              ? null
              : () => onSelectScope!(summary.scopeId),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      if (legacyGroups.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.sm),
        _CopyText(
          copy: YorksV1BoqStrings.legacyBoqs,
          language: language,
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final group in legacyGroups) ...[
          _LegacyBoqScopeCard(
            group: group,
            language: language,
            onAssign: onAssignLegacyScope == null
                ? null
                : () => onAssignLegacyScope!(group),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
      if (summaries.isEmpty && legacyGroups.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
          child: _CopyText(
            copy: YorksV1BoqStrings.noGroups,
            language: language,
            center: true,
          ),
        ),
    ];
    return embedded
        ? Column(
            key: const ValueKey('boq-mobile-scope-overview'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: content,
          )
        : ListView(
            key: const ValueKey('boq-mobile-scope-overview'),
            padding: const EdgeInsets.only(bottom: AppSpacing.colossal),
            children: content,
          );
  }
}

class _MobileBoqScopeCard extends StatelessWidget {
  const _MobileBoqScopeCard({required this.summary, this.onTap});

  final _BoqScopeSummary summary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => YorksMobileCard(
    onTap: onTap,
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                summary.scopeName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: _MobileBoqMetric(
                label: YorksV1BoqStrings.folders.primary,
                value: summary.folderCount,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _MobileBoqMetric(
                label: YorksV1BoqStrings.materials.primary,
                value: summary.materialCount,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _MobileBoqMetric(
                label: YorksV1BoqStrings.startedFolders.primary,
                value: summary.startedFolderCount,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _MobileBoqMetric extends StatelessWidget {
  const _MobileBoqMetric({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: AppColors.mobileSurface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '$value',
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _BoqScopeSummary {
  _BoqScopeSummary({required this.scopeId, required this.scopeName});

  final String scopeId;
  final String scopeName;
  int folderCount = 0;
  int startedFolderCount = 0;
  int materialCount = 0;
  int linkedRequestCount = 0;
  int documentCount = 0;

  void add(YorksV1BoqGroup group) {
    folderCount += 1;
    if (group.rowCount > 0) startedFolderCount += 1;
    materialCount += group.rowCount;
    linkedRequestCount += group.linkedRequestCount;
    documentCount += group.documentCount;
  }
}

class _BoqScopeSummaryCard extends StatelessWidget {
  const _BoqScopeSummaryCard({
    required this.summary,
    required this.language,
    this.onOpen,
  });

  final _BoqScopeSummary summary;
  final AppLanguage language;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 160),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: AppSpacing.massive,
              height: AppSpacing.massive,
              decoration: BoxDecoration(
                color: AppColors.blueContainer,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: const Icon(
                Icons.apartment_outlined,
                color: AppColors.blue,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                summary.scopeName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _BoqStatusPill(
              active: summary.materialCount > 0,
              language: language,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: _BoqOverviewMetric(
                value: summary.folderCount,
                label: YorksV1BoqStrings.folders,
                language: language,
              ),
            ),
            Expanded(
              child: _BoqOverviewMetric(
                value: summary.materialCount,
                label: YorksV1BoqStrings.rows,
                language: language,
              ),
            ),
            Expanded(
              child: _BoqOverviewMetric(
                value: summary.linkedRequestCount,
                label: YorksV1ProjectStrings.requests,
                language: language,
              ),
            ),
            Expanded(
              child: _BoqOverviewMetric(
                value: summary.documentCount,
                label: YorksV1ProjectStrings.documents,
                language: language,
              ),
            ),
          ],
        ),
        if (onOpen != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: OutlinedButton.icon(
              onPressed: onOpen,
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(YorksV1BoqStrings.openScope.active(language)),
            ),
          ),
        ],
      ],
    ),
  );
}

class _BoqStatusPill extends StatelessWidget {
  const _BoqStatusPill({required this.active, required this.language});

  final bool active;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xxs,
    ),
    decoration: BoxDecoration(
      color: active ? AppColors.successContainer : AppColors.surfaceContainer,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      (active
              ? YorksV1ProjectStrings.active
              : YorksV1BoqStrings.notStartedStatus)
          .active(language),
      style: AppTypography.labelSmall.copyWith(
        color: active ? AppColors.success : AppColors.inkSecondary,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _BoqOverviewMetric extends StatelessWidget {
  const _BoqOverviewMetric({
    required this.value,
    required this.label,
    required this.language,
  });

  final int value;
  final TranslatableString label;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label.active(language),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        ),
      ],
    ),
  );
}

class _LegacyBoqScopeCard extends StatelessWidget {
  const _LegacyBoqScopeCard({
    required this.group,
    required this.language,
    this.onAssign,
  });

  final YorksV1BoqGroup group;
  final AppLanguage language;
  final VoidCallback? onAssign;

  @override
  Widget build(BuildContext context) => NexusSectionCard(
    child: Row(
      children: [
        const Icon(Icons.warning_amber_outlined, color: AppColors.warning),
        const SizedBox(width: AppSpacing.sm),
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
              const SizedBox(height: AppSpacing.xxs),
              _CopyText(
                copy: YorksV1BoqStrings.legacyUnassigned,
                language: language,
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
        if (onAssign != null) ...[
          const SizedBox(width: AppSpacing.sm),
          OutlinedButton(
            onPressed: onAssign,
            child: Text(YorksV1BoqStrings.assignLegacyScope.primary),
          ),
        ],
      ],
    ),
  );
}

class _EmbeddedBoqGroupsWorkspace extends StatelessWidget {
  const _EmbeddedBoqGroupsWorkspace({
    required this.projectId,
    required this.language,
    required this.groups,
    required this.scopes,
    required this.scopeSelector,
    required this.isAllAggregate,
    required this.editable,
    required this.showEditActions,
    required this.canManageFolders,
    required this.showManageFolders,
    required this.excelEnabled,
    required this.onSelectScope,
    this.onAssignLegacyScope,
    required this.onCreateGroup,
    required this.onManageFolders,
    required this.onRenameGroup,
    required this.onArchiveGroup,
    required this.onExport,
    required this.onPrint,
    required this.onRetry,
  });

  final String projectId;
  final AppLanguage language;
  final AsyncValue<List<YorksV1BoqGroup>> groups;
  final List<YorksV1MaterialRequestScopeOption> scopes;
  final Widget scopeSelector;
  final bool isAllAggregate;
  final bool editable;
  final bool showEditActions;
  final bool canManageFolders;
  final bool showManageFolders;
  final bool excelEnabled;
  final ValueChanged<String> onSelectScope;
  final ValueChanged<YorksV1BoqGroup>? onAssignLegacyScope;
  final VoidCallback onCreateGroup;
  final VoidCallback onManageFolders;
  final ValueChanged<YorksV1BoqGroup> onRenameGroup;
  final ValueChanged<YorksV1BoqGroup> onArchiveGroup;
  final VoidCallback onExport;
  final VoidCallback onPrint;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (YorksMobileUi.isActive(context)) {
      return ListView(
        key: const ValueKey('boq-mobile-embedded-workspace'),
        padding: const EdgeInsets.fromLTRB(
          YorksMobileUi.horizontalPadding,
          AppSpacing.sm,
          YorksMobileUi.horizontalPadding,
          128,
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          _BoqMobileWorkspaceIntro(
            language: language,
            aggregate: isAllAggregate,
          ),
          const SizedBox(height: AppSpacing.md),
          scopeSelector,
          const SizedBox(height: AppSpacing.md),
          if (isAllAggregate) ...[
            _ReadOnlyAggregateBanner(language: language),
            const SizedBox(height: AppSpacing.md),
          ] else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final textScale = MediaQuery.textScalerOf(context).scale(1);
                final buttonHeight =
                    AppSpacing.minTapTarget +
                    ((textScale - 1).clamp(0, 1.5) * 28);
                final buttons = <Widget>[
                  if (excelEnabled)
                    OutlinedButton.icon(
                      onPressed: onExport,
                      icon: const Icon(
                        YorksDataTransferIcons.exportData,
                        size: 18,
                      ),
                      label: Text(YorksV1BoqStrings.exportWorkbook.primary),
                    ),
                  OutlinedButton.icon(
                    onPressed: onPrint,
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: Text(YorksV1BoqStrings.printBoq.primary),
                  ),
                  if (showManageFolders)
                    OutlinedButton.icon(
                      onPressed: canManageFolders ? onManageFolders : null,
                      icon: const Icon(Icons.folder_copy_outlined, size: 18),
                      label: Text(YorksV1BoqStrings.manageFolders.primary),
                    ),
                  if (showManageFolders)
                    FilledButton.icon(
                      onPressed: canManageFolders ? onCreateGroup : null,
                      icon: const Icon(
                        Icons.create_new_folder_outlined,
                        size: 18,
                      ),
                      label: Text(YorksV1BoqStrings.newGroup.primary),
                    ),
                ];
                final twoColumns = constraints.maxWidth >= 330;
                final buttonWidth = twoColumns
                    ? (constraints.maxWidth - AppSpacing.sm) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final button in buttons)
                      SizedBox(
                        width: buttonWidth,
                        height: buttonHeight,
                        child: button,
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          groups.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.xxxl),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => _ErrorState(language: language, onRetry: onRetry),
            data: (items) => _GroupsBody(
              groups: items,
              scopes: scopes,
              language: language,
              projectId: projectId,
              editable: editable,
              showEditActions: showEditActions,
              canManageFolders: canManageFolders,
              showManageFolders: showManageFolders,
              aggregateReadOnly: isAllAggregate,
              onSelectScope: onSelectScope,
              onAssignLegacyScope: onAssignLegacyScope,
              onAddGroup: onCreateGroup,
              onRenameGroup: onRenameGroup,
              onArchiveGroup: onArchiveGroup,
              embedded: true,
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BoqWorkspaceIntro(language: language, aggregate: isAllAggregate),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final actions = _BoqWorkspaceActions(
              language: language,
              excelEnabled: excelEnabled,
              showManageFolders: showManageFolders,
              canManageFolders: canManageFolders,
              onExport: onExport,
              onPrint: onPrint,
              onManageFolders: onManageFolders,
              onCreateGroup: onCreateGroup,
            );
            if (isAllAggregate) return scopeSelector;
            if (constraints.maxWidth < 1180) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  scopeSelector,
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: actions,
                  ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: scopeSelector),
                const SizedBox(width: AppSpacing.sm),
                actions,
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        if (isAllAggregate) ...[
          _ReadOnlyAggregateBanner(language: language),
          const SizedBox(height: AppSpacing.md),
        ],
        groups.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.xxxl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => _ErrorState(language: language, onRetry: onRetry),
          data: (items) => isAllAggregate
              ? _GroupsBody(
                  groups: items,
                  scopes: scopes,
                  language: language,
                  projectId: projectId,
                  editable: false,
                  showEditActions: false,
                  canManageFolders: false,
                  showManageFolders: false,
                  aggregateReadOnly: true,
                  onSelectScope: onSelectScope,
                  onAssignLegacyScope: onAssignLegacyScope,
                  onAddGroup: null,
                  onRenameGroup: onRenameGroup,
                  onArchiveGroup: onArchiveGroup,
                  embedded: true,
                )
              : _DesktopBoqGroupBrowser(
                  groups: items,
                  language: language,
                  projectId: projectId,
                  canManageFolders: canManageFolders,
                  showManageFolders: showManageFolders,
                  onRenameGroup: onRenameGroup,
                  onArchiveGroup: onArchiveGroup,
                ),
        ),
      ],
    );
  }
}

class _BoqMobileWorkspaceIntro extends StatelessWidget {
  const _BoqMobileWorkspaceIntro({
    required this.language,
    required this.aggregate,
  });

  final AppLanguage language;
  final bool aggregate;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: AppSpacing.massive,
        height: AppSpacing.massive,
        decoration: BoxDecoration(
          color: AppColors.blueContainer,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: const Icon(Icons.description_outlined, color: AppColors.blue),
      ),
      const SizedBox(width: AppSpacing.md),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (aggregate
                      ? YorksV1BoqStrings.workspaceTitle
                      : YorksV1BoqStrings.groupsAndWorksheets)
                  .active(language),
              style: AppTypography.titleLarge.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              (aggregate
                      ? YorksV1BoqStrings.boqDescription
                      : YorksV1BoqStrings.materialFoldersDescription)
                  .active(language),
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.muted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _BoqWorkspaceIntro extends StatelessWidget {
  const _BoqWorkspaceIntro({required this.language, required this.aggregate});

  final AppLanguage language;
  final bool aggregate;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final title = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: AppSpacing.massive,
            height: AppSpacing.massive,
            decoration: BoxDecoration(
              color: AppColors.blueContainer,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: const Icon(
              Icons.description_outlined,
              color: AppColors.blue,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (aggregate
                          ? YorksV1BoqStrings.workspaceTitle
                          : YorksV1BoqStrings.groupsAndWorksheets)
                      .active(language),
                  style: AppTypography.headlineSmall.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  (aggregate
                          ? YorksV1BoqStrings.boqDescription
                          : YorksV1BoqStrings.materialFoldersDescription)
                      .active(language),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
      final guidance = Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.blueContainer.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, color: AppColors.blue),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                YorksV1BoqStrings.overviewDescription.active(language),
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.inkSecondary,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
      if (constraints.maxWidth < 900) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            const SizedBox(height: AppSpacing.sm),
            guidance,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: title),
          const SizedBox(width: AppSpacing.xl),
          Expanded(flex: 4, child: guidance),
        ],
      );
    },
  );
}

class _BoqWorkspaceActions extends StatelessWidget {
  const _BoqWorkspaceActions({
    required this.language,
    required this.excelEnabled,
    required this.showManageFolders,
    required this.canManageFolders,
    required this.onExport,
    required this.onPrint,
    required this.onManageFolders,
    required this.onCreateGroup,
  });

  final AppLanguage language;
  final bool excelEnabled;
  final bool showManageFolders;
  final bool canManageFolders;
  final VoidCallback onExport;
  final VoidCallback onPrint;
  final VoidCallback onManageFolders;
  final VoidCallback onCreateGroup;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.end,
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    children: [
      if (excelEnabled)
        OutlinedButton.icon(
          onPressed: onExport,
          icon: const Icon(YorksDataTransferIcons.exportData, size: 18),
          label: Text(YorksV1BoqStrings.exportWorkbook.active(language)),
        ),
      OutlinedButton.icon(
        onPressed: onPrint,
        icon: const Icon(Icons.print_outlined, size: 18),
        label: Text(YorksV1BoqStrings.printBoq.active(language)),
      ),
      if (showManageFolders)
        OutlinedButton.icon(
          onPressed: canManageFolders ? onManageFolders : null,
          icon: const Icon(Icons.folder_copy_outlined, size: 18),
          label: Text(YorksV1BoqStrings.manageFolders.active(language)),
        ),
      if (showManageFolders)
        FilledButton.icon(
          onPressed: canManageFolders ? onCreateGroup : null,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(YorksV1BoqStrings.newGroup.active(language)),
        ),
    ],
  );
}

enum _BoqGroupStatusFilter { all, active, notStarted }

class _DesktopBoqGroupBrowser extends StatefulWidget {
  const _DesktopBoqGroupBrowser({
    required this.groups,
    required this.language,
    required this.projectId,
    required this.canManageFolders,
    required this.showManageFolders,
    required this.onRenameGroup,
    required this.onArchiveGroup,
  });

  final List<YorksV1BoqGroup> groups;
  final AppLanguage language;
  final String projectId;
  final bool canManageFolders;
  final bool showManageFolders;
  final ValueChanged<YorksV1BoqGroup> onRenameGroup;
  final ValueChanged<YorksV1BoqGroup> onArchiveGroup;

  @override
  State<_DesktopBoqGroupBrowser> createState() =>
      _DesktopBoqGroupBrowserState();
}

class _DesktopBoqGroupBrowserState extends State<_DesktopBoqGroupBrowser> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  _BoqGroupStatusFilter _status = _BoqGroupStatusFilter.all;
  bool _cardView = true;
  bool _descending = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        widget.groups
            .where((group) {
              final query = _query.toLowerCase();
              final matchesQuery =
                  query.isEmpty ||
                  group.name.toLowerCase().contains(query) ||
                  group.worksheetTitle.toLowerCase().contains(query);
              final matchesStatus = switch (_status) {
                _BoqGroupStatusFilter.all => true,
                _BoqGroupStatusFilter.active => group.rowCount > 0,
                _BoqGroupStatusFilter.notStarted => group.rowCount == 0,
              };
              return matchesQuery && matchesStatus;
            })
            .toList(growable: false)
          ..sort((left, right) {
            final leftTime = left.lastEditedAt ?? left.updatedAt;
            final rightTime = right.lastEditedAt ?? right.updatedAt;
            final comparison = rightTime.compareTo(leftTime);
            return _descending ? comparison : -comparison;
          });

    return Column(
      key: const ValueKey('boq-desktop-group-browser'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final search = TextField(
                key: const ValueKey('boq-group-search'),
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value.trim()),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 19),
                  hintText: YorksV1BoqStrings.searchGroups.active(
                    widget.language,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                ),
              );
              final controls = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 170,
                    child: DropdownButtonFormField<_BoqGroupStatusFilter>(
                      key: const ValueKey('boq-group-status-filter'),
                      initialValue: _status,
                      isExpanded: true,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(
                          Icons.filter_alt_outlined,
                          size: 18,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMd,
                          ),
                        ),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: _BoqGroupStatusFilter.all,
                          child: Text(
                            YorksV1MaterialRequestStrings.allStatuses.active(
                              widget.language,
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: _BoqGroupStatusFilter.active,
                          child: Text(
                            YorksV1ProjectStrings.active.active(
                              widget.language,
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: _BoqGroupStatusFilter.notStarted,
                          child: Text(
                            YorksV1BoqStrings.notStartedStatus.active(
                              widget.language,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _status = value);
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    height: AppSpacing.minTapTarget,
                    child: OutlinedButton.icon(
                      key: const ValueKey('boq-group-sort'),
                      onPressed: () =>
                          setState(() => _descending = !_descending),
                      icon: Icon(
                        _descending
                            ? Icons.arrow_downward_rounded
                            : Icons.arrow_upward_rounded,
                        size: 17,
                      ),
                      label: Text(
                        YorksV1BoqStrings.sortLastEdited.active(
                          widget.language,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _BoqViewToggle(
                    cardView: _cardView,
                    language: widget.language,
                    onChanged: (value) => setState(() => _cardView = value),
                  ),
                ],
              );
              if (constraints.maxWidth < 760) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    search,
                    const SizedBox(height: AppSpacing.sm),
                    controls,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: AppSpacing.sm),
                  controls,
                ],
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (visible.isEmpty)
          _BoqFilteredEmptyState(language: widget.language)
        else if (_cardView)
          LayoutBuilder(
            builder: (context, constraints) {
              final count = constraints.maxWidth >= 1080 ? 3 : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: count,
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisSpacing: AppSpacing.md,
                  mainAxisExtent: 270,
                ),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final group = visible[index];
                  return _BoqGroupCard(
                    group: group,
                    language: widget.language,
                    aggregateReadOnly: false,
                    onOpen: () => context.push(
                      RoutePaths.yorksV1BoqWorksheetPath(
                        widget.projectId,
                        group.id,
                      ),
                    ),
                    canManageFolders: widget.canManageFolders,
                    showManageFolders: widget.showManageFolders,
                    onRename: () => widget.onRenameGroup(group),
                    onArchive: group.isCustom
                        ? () => widget.onArchiveGroup(group)
                        : null,
                  );
                },
              );
            },
          )
        else
          Column(
            key: const ValueKey('boq-group-list'),
            children: [
              for (var index = 0; index < visible.length; index++) ...[
                SizedBox(
                  height: 270,
                  child: _BoqGroupCard(
                    group: visible[index],
                    language: widget.language,
                    aggregateReadOnly: false,
                    onOpen: () => context.push(
                      RoutePaths.yorksV1BoqWorksheetPath(
                        widget.projectId,
                        visible[index].id,
                      ),
                    ),
                    canManageFolders: widget.canManageFolders,
                    showManageFolders: widget.showManageFolders,
                    onRename: () => widget.onRenameGroup(visible[index]),
                    onArchive: visible[index].isCustom
                        ? () => widget.onArchiveGroup(visible[index])
                        : null,
                  ),
                ),
                if (index != visible.length - 1)
                  const SizedBox(height: AppSpacing.sm),
              ],
            ],
          ),
      ],
    );
  }
}

class _BoqViewToggle extends StatelessWidget {
  const _BoqViewToggle({
    required this.cardView,
    required this.language,
    required this.onChanged,
  });

  final bool cardView;
  final AppLanguage language;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: AppSpacing.minTapTarget,
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BoqViewToggleButton(
          icon: Icons.grid_view_rounded,
          label: YorksV1MaterialRequestStrings.gridView.active(language),
          selected: cardView,
          onPressed: () => onChanged(true),
        ),
        _BoqViewToggleButton(
          icon: Icons.view_list_outlined,
          label: YorksV1MaterialRequestStrings.listView.active(language),
          selected: !cardView,
          onPressed: () => onChanged(false),
        ),
      ],
    ),
  );
}

class _BoqViewToggleButton extends StatelessWidget {
  const _BoqViewToggleButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onPressed,
    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
    child: Container(
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: selected ? AppColors.blueContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: selected ? AppColors.blue : AppColors.muted,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: selected ? AppColors.blue : AppColors.inkSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );
}

class _BoqFilteredEmptyState extends StatelessWidget {
  const _BoqFilteredEmptyState({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.xxl),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Text(
      YorksV1BoqStrings.noGroups.active(language),
      style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
    ),
  );
}

enum _BoqFolderAction { open, rename, archive }

class _BoqFolderActionsMenu extends StatelessWidget {
  const _BoqFolderActionsMenu({
    required this.canWrite,
    required this.onOpen,
    required this.onRename,
    this.onArchive,
  });

  final bool canWrite;
  final VoidCallback? onOpen;
  final VoidCallback onRename;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: AppSpacing.minTapTarget,
    child: PopupMenuButton<_BoqFolderAction>(
      tooltip: YorksV1BoqStrings.manageFolders.primary,
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (action) {
        switch (action) {
          case _BoqFolderAction.open:
            onOpen?.call();
            break;
          case _BoqFolderAction.rename:
            onRename();
            break;
          case _BoqFolderAction.archive:
            onArchive?.call();
            break;
        }
      },
      itemBuilder: (context) => [
        if (onOpen != null)
          PopupMenuItem(
            value: _BoqFolderAction.open,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_note_outlined),
              title: Text(YorksV1BoqStrings.editWorksheet.primary),
            ),
          ),
        PopupMenuItem(
          value: _BoqFolderAction.rename,
          enabled: canWrite,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.drive_file_rename_outline),
            title: Text(YorksV1BoqStrings.renameFolder.primary),
          ),
        ),
        if (onArchive != null)
          PopupMenuItem(
            value: _BoqFolderAction.archive,
            enabled: canWrite,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.archive_outlined),
              title: Text(YorksV1BoqStrings.archiveGroup.primary),
            ),
          ),
      ],
    ),
  );
}

class _BoqFolderManager extends ConsumerWidget {
  const _BoqFolderManager({
    required this.projectId,
    required this.scopeId,
    required this.canWrite,
    required this.onCreate,
    required this.onRename,
    required this.onArchive,
    required this.onRestore,
  });

  final String projectId;
  final String scopeId;
  final bool canWrite;
  final VoidCallback onCreate;
  final ValueChanged<YorksV1BoqGroup> onRename;
  final ValueChanged<YorksV1BoqGroup> onArchive;
  final ValueChanged<YorksV1BoqGroup> onRestore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final query = YorksV1BoqScopeQuery(projectId: projectId, scopeId: scopeId);
    final state = ref.watch(yorksV1BoqFolderManagementProvider(query));
    return Padding(
      key: const ValueKey('boq-folder-manager'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CopyText(
                      copy: YorksV1BoqStrings.manageFolders,
                      language: language,
                      style: AppTypography.titleLarge.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    _CopyText(
                      copy: YorksV1BoqStrings.manageFoldersDescription,
                      language: language,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: YorksV1BoqStrings.refresh.active(language),
                onPressed: () =>
                    ref.invalidate(yorksV1BoqFolderManagementProvider(query)),
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                tooltip: YorksV1BoqStrings.cancel.active(language),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SizedBox(
              height: AppSpacing.minTapTarget,
              child: FilledButton.icon(
                key: const ValueKey('boq-folder-manager-create'),
                onPressed: canWrite ? onCreate : null,
                icon: const Icon(Icons.create_new_folder_outlined),
                label: Text(YorksV1BoqStrings.newGroup.active(language)),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: state.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => _ErrorState(
                language: language,
                onRetry: () =>
                    ref.invalidate(yorksV1BoqFolderManagementProvider(query)),
              ),
              data: (items) {
                final active = items
                    .where((item) => !item.group.isArchived)
                    .toList(growable: false);
                final archived = items
                    .where((item) => item.group.isArchived)
                    .toList(growable: false);
                return ListView(
                  children: [
                    _BoqFolderManagerSection(
                      title: YorksV1BoqStrings.activeFolders,
                      language: language,
                      items: active,
                      canWrite: canWrite,
                      onRename: onRename,
                      onArchive: onArchive,
                      onRestore: onRestore,
                    ),
                    if (archived.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xl),
                      _BoqFolderManagerSection(
                        title: YorksV1BoqStrings.archivedFolders,
                        language: language,
                        items: archived,
                        canWrite: canWrite,
                        onRename: onRename,
                        onArchive: onArchive,
                        onRestore: onRestore,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.blueContainer,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: AppColors.blue,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: _CopyText(
                              copy: YorksV1BoqStrings.lifecycleGuidance,
                              language: language,
                              style: AppTypography.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BoqFolderManagerSection extends StatelessWidget {
  const _BoqFolderManagerSection({
    required this.title,
    required this.language,
    required this.items,
    required this.canWrite,
    required this.onRename,
    required this.onArchive,
    required this.onRestore,
  });

  final TranslatableString title;
  final AppLanguage language;
  final List<YorksV1BoqFolderManagementItem> items;
  final bool canWrite;
  final ValueChanged<YorksV1BoqGroup> onRename;
  final ValueChanged<YorksV1BoqGroup> onArchive;
  final ValueChanged<YorksV1BoqGroup> onRestore;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: _CopyText(
              copy: title,
              language: language,
              style: AppTypography.titleSmall.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text('${items.length}', style: AppTypography.labelLarge),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      for (var index = 0; index < items.length; index++) ...[
        _BoqFolderManagerRow(
          item: items[index],
          language: language,
          canWrite: canWrite,
          onRename: () => onRename(items[index].group),
          onArchive: () => onArchive(items[index].group),
          onRestore: () => onRestore(items[index].group),
        ),
        if (index != items.length - 1) const SizedBox(height: AppSpacing.sm),
      ],
    ],
  );
}

class _BoqFolderManagerRow extends StatelessWidget {
  const _BoqFolderManagerRow({
    required this.item,
    required this.language,
    required this.canWrite,
    required this.onRename,
    required this.onArchive,
    required this.onRestore,
  });

  final YorksV1BoqFolderManagementItem item;
  final AppLanguage language;
  final bool canWrite;
  final VoidCallback onRename;
  final VoidCallback onArchive;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final group = item.group;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: AppSpacing.minTapTarget,
            height: AppSpacing.minTapTarget,
            decoration: BoxDecoration(
              color: group.isArchived
                  ? AppColors.surfaceContainer
                  : item.isSystemDefault
                  ? AppColors.blueContainer
                  : AppColors.purpleContainer,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(
              group.isArchived
                  ? Icons.inventory_2_outlined
                  : Icons.folder_outlined,
              color: group.isArchived
                  ? AppColors.muted
                  : item.isSystemDefault
                  ? AppColors.blue
                  : AppColors.purple,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '${group.rowCount} ${YorksV1BoqStrings.rows.active(language)} · '
                  '${group.linkedRequestCount} ${YorksV1BoqStrings.linkedRequests.active(language)} · '
                  '${group.documentCount} ${YorksV1BoqStrings.linkedDocuments.active(language)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
                if (item.isSystemDefault) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  _CopyText(
                    copy: YorksV1BoqStrings.systemFolder,
                    language: language,
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.blue,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (group.isArchived)
            IconButton(
              key: ValueKey('boq-folder-restore-${group.id}'),
              tooltip: item.restoreBlocker == 'active_name_exists'
                  ? YorksV1BoqStrings.folderNameUnchanged.active(language)
                  : YorksV1BoqStrings.restoreFolder.active(language),
              onPressed: canWrite && item.canRestore ? onRestore : null,
              icon: const Icon(Icons.restore_rounded),
            )
          else ...[
            IconButton(
              key: ValueKey('boq-folder-rename-${group.id}'),
              tooltip: YorksV1BoqStrings.renameFolder.active(language),
              onPressed: canWrite && item.canRename ? onRename : null,
              icon: const Icon(Icons.drive_file_rename_outline),
            ),
            IconButton(
              key: ValueKey('boq-folder-archive-${group.id}'),
              tooltip: item.archiveBlocker == 'system_default'
                  ? YorksV1BoqStrings.systemFolderCannotArchive.active(language)
                  : YorksV1BoqStrings.archiveGroup.active(language),
              onPressed: canWrite && item.canArchive ? onArchive : null,
              icon: const Icon(Icons.archive_outlined),
            ),
          ],
        ],
      ),
    );
  }
}

class _BoqGroupCard extends StatelessWidget {
  const _BoqGroupCard({
    required this.group,
    required this.language,
    required this.onOpen,
    required this.aggregateReadOnly,
    required this.canManageFolders,
    required this.showManageFolders,
    required this.onRename,
    this.onArchive,
  });

  final YorksV1BoqGroup group;
  final AppLanguage language;
  final VoidCallback? onOpen;
  final bool aggregateReadOnly;
  final bool canManageFolders;
  final bool showManageFolders;
  final VoidCallback onRename;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    final editedAt = (group.lastEditedAt ?? group.updatedAt).toLocal();
    final editedLabel =
        '${MaterialLocalizations.of(context).formatShortDate(editedAt)} · '
        '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(editedAt))}';
    return Semantics(
      button: onOpen != null,
      label: aggregateReadOnly
          ? '${group.name} ${YorksV1BoqStrings.allScopes.primary}'
          : group.name,
      child: Material(
        color: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          side: const BorderSide(color: AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: AppSpacing.massive,
                      height: AppSpacing.massive,
                      decoration: BoxDecoration(
                        color: group.isCustom
                            ? AppColors.purpleContainer
                            : AppColors.blueContainer,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                      ),
                      child: Icon(
                        group.isCustom
                            ? Icons.folder_special_outlined
                            : Icons.folder_outlined,
                        color: group.isCustom
                            ? AppColors.purple
                            : AppColors.blue,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.titleMedium.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            group.worksheetTitle.trim().isNotEmpty &&
                                    group.worksheetTitle.trim() !=
                                        group.name.trim()
                                ? group.worksheetTitle.trim()
                                : (group.isCustom
                                      ? YorksV1BoqStrings.customGroup.active(
                                          language,
                                        )
                                      : YorksV1BoqStrings.defaultGroup.active(
                                          language,
                                        )),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _BoqStatusPill(
                      active: group.rowCount > 0,
                      language: language,
                    ),
                    if (showManageFolders) ...[
                      const SizedBox(width: AppSpacing.xxs),
                      _BoqFolderActionsMenu(
                        canWrite: canManageFolders,
                        onOpen: onOpen,
                        onRename: onRename,
                        onArchive: onArchive,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.sm),
                if (group.scopeName != null) ...[
                  Row(
                    children: [
                      const Icon(
                        Icons.layers_outlined,
                        size: 17,
                        color: AppColors.inkSecondary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          group.scopeName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.inkSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                Row(
                  children: [
                    Expanded(
                      child: _BoqOverviewMetric(
                        value: group.rowCount,
                        label: YorksV1BoqStrings.rows,
                        language: language,
                      ),
                    ),
                    Expanded(
                      child: _BoqOverviewMetric(
                        value: group.linkedRequestCount,
                        label: YorksV1ProjectStrings.requests,
                        language: language,
                      ),
                    ),
                    Expanded(
                      child: _BoqOverviewMetric(
                        value: group.documentCount,
                        label: YorksV1ProjectStrings.documents,
                        language: language,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.blueContainer,
                      child: Text(
                        _initials(group.lastEditedBy ?? group.lastEditedRole),
                        style: AppTypography.labelSmall.copyWith(
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
                          Text(
                            group.lastEditedBy ??
                                group.lastEditedRole ??
                                YorksV1BoqStrings.lastEdited.active(language),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelSmall.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            editedLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onOpen != null)
                      OutlinedButton.icon(
                        onPressed: onOpen,
                        iconAlignment: IconAlignment.end,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                        label: Text(
                          YorksV1BoqStrings.editWorksheet.active(language),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _initials(String? name) {
  final words = (name ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(2)
      .toList(growable: false);
  if (words.isEmpty) return '—';
  return words.map((word) => word.characters.first.toUpperCase()).join();
}

class YorksV1BoqWorksheetScreen extends ConsumerWidget {
  const YorksV1BoqWorksheetScreen({
    super.key,
    required this.projectId,
    required this.groupId,
  });

  final String projectId;
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final role = ref.watch(yorksV1CurrentRoleProvider);
    final permissionState = ref.watch(yorksV1CurrentPermissionSnapshotProvider);
    final canRead = yorksV1CanReadProjectRecord(
      permissionState,
      YorksV1CapabilityKeys.boqView,
      legacyAllowed: role != null,
      projectId: projectId,
    );
    if (!canRead) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          top: false,
          child: YorksV1ProjectReadBoundary(
            allowed: false,
            language: language,
            child: const SizedBox.shrink(),
          ),
        ),
      );
    }
    final state = ref.watch(yorksV1BoqWorksheetControllerProvider(groupId));
    final controller = ref.read(
      yorksV1BoqWorksheetControllerProvider(groupId).notifier,
    );
    final excelEnabled = ref.watch(yorksV1FeatureFlagsProvider).excel;
    final requestsEnabled = ref.watch(yorksV1FeatureFlagsProvider).requests;
    final documentsEnabled = ref.watch(yorksV1FeatureFlagsProvider).documents;
    final canViewCommercials = ref.watch(canViewCommercialsProvider);
    final canManageCommercials = ref.watch(canManageCommercialsProvider);
    final legacyEditable =
        role != null &&
        role != YorksV1Role.procurement &&
        !state.isReadOnly &&
        !(state.worksheet?.group.isLegacyUnassigned ?? false);
    final editAccess = yorksV1FeatureActionAccess(
      permissionState,
      YorksV1CapabilityKeys.boqEdit,
      legacyAllowed: legacyEditable,
      projectId: projectId,
    );
    final requestCreateAccess = yorksV1FeatureActionAccess(
      permissionState,
      YorksV1CapabilityKeys.materialRequestsCreate,
      legacyAllowed: role?.canCreateMaterialRequest == true,
      projectId: projectId,
    );
    final editable = editAccess.canWrite;
    final showEditActions = editAccess.isVisible;
    final compactRoute =
        MediaQuery.sizeOf(context).width < AppSpacing.yorksV1DesktopBreakpoint;

    final scaffold = Scaffold(
      backgroundColor: compactRoute
          ? AppColors.surface
          : AppColors.surfaceContainerLowest,
      appBar: compactRoute
          ? AppBar(
              backgroundColor: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              leading: IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () =>
                    _leaveWorksheet(context, ref, controller, state),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              title: YorksMobileUi.isActive(context)
                  ? Text(
                      _mobileWorksheetTitle(state.worksheet),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  : _CopyText(
                      copy: YorksV1BoqStrings.worksheet,
                      language: language,
                      style: AppTypography.titleLarge.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
              actions: [
                if (documentsEnabled)
                  IconButton(
                    tooltip: YorksV1DocumentStrings.documents.primary,
                    onPressed: () => context.push(
                      RoutePaths.yorksV1ProjectDocumentsPath(
                        projectId,
                        entityType: 'boq_group',
                        entityId: groupId,
                      ),
                    ),
                    icon: const Icon(Icons.folder_open_outlined),
                  ),
                if (showEditActions && state.worksheet?.group.isCustom == true)
                  IconButton(
                    tooltip: YorksV1BoqStrings.archiveGroup.primary,
                    icon: const Icon(Icons.archive_outlined),
                    onPressed: editable
                        ? () => _archive(context, ref, state.worksheet!.group)
                        : null,
                  ),
                IconButton(
                  tooltip: YorksV1BoqStrings.refresh.primary,
                  onPressed: () =>
                      _refreshWorksheet(context, ref, controller, state),
                  icon: const Icon(Icons.refresh_rounded),
                ),
                if (requestsEnabled && requestCreateAccess.isVisible)
                  IconButton(
                    tooltip: YorksV1MaterialRequestStrings.newRequest.primary,
                    onPressed: requestCreateAccess.canWrite
                        ? () => context.push(
                            RoutePaths.yorksV1MaterialRequestDraftPath(
                              const Uuid().v4(),
                              projectId: projectId,
                              entryMode:
                                  YorksV1MaterialRequestDraftEntryMode.newDraft,
                            ),
                          )
                        : null,
                    icon: const Icon(Icons.add_task_outlined),
                  ),
              ],
            )
          : null,
      body: SafeArea(
        top: false,
        child: switch (state.status) {
          YorksV1BoqSyncStatus.loading => const Center(
            child: CircularProgressIndicator(),
          ),
          YorksV1BoqSyncStatus.failed when state.worksheet == null =>
            _ErrorState(language: language, onRetry: controller.load),
          _ => _WorksheetBody(
            state: state,
            controller: controller,
            language: language,
            editable: editable,
            showEditActions: showEditActions,
            excelEnabled: excelEnabled,
            canViewCommercials: canViewCommercials,
            canManageCommercials: canManageCommercials,
            onSaved: () => _invalidateGroupLists(
              ref,
              projectId,
              state.worksheet?.group.scopeId,
            ),
            showPageHeader: !compactRoute,
            onCreateRequestFromFolder:
                requestsEnabled &&
                    requestCreateAccess.canWrite &&
                    state.worksheet?.group.isScopeAssigned == true
                ? () => _createRequestDraft(context, ref, controller, state)
                : null,
            showCreateRequestFromFolder:
                requestsEnabled &&
                requestCreateAccess.isVisible &&
                state.worksheet?.group.isScopeAssigned == true,
            onImport: editable && excelEnabled && state.worksheet != null
                ? () => _importWorkbook(
                    context,
                    ref,
                    controller,
                    state.worksheet!,
                    language,
                  )
                : null,
            onExport: excelEnabled && state.worksheet != null
                ? () => _exportWorksheet(context, ref, controller, state)
                : null,
            onPrint: state.worksheet == null
                ? null
                : () => _printWorksheetWithChoice(
                    context,
                    ref,
                    controller,
                    state,
                    canViewCommercials: canViewCommercials,
                  ),
            onOpenDocuments: documentsEnabled && state.worksheet != null
                ? () => context.push(
                    RoutePaths.yorksV1ProjectDocumentsPath(
                      projectId,
                      entityType: 'boq_group',
                      entityId: groupId,
                    ),
                  )
                : null,
            onOpenRequests: requestsEnabled
                ? () => context.push(
                    RoutePaths.yorksV1MaterialRequestsPath(
                      projectId: projectId,
                    ),
                  )
                : null,
          ),
        },
      ),
    );
    return PopScope(
      canPop: !state.hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _leaveWorksheet(context, ref, controller, state);
        }
      },
      child: scaffold,
    );
  }

  static String _mobileWorksheetTitle(YorksV1BoqWorksheet? worksheet) {
    if (worksheet == null) return YorksV1BoqStrings.worksheet.primary;
    final scope = worksheet.group.scopeCode?.trim().isNotEmpty == true
        ? worksheet.group.scopeCode!.trim()
        : worksheet.group.scopeName?.trim();
    return scope == null || scope.isEmpty
        ? worksheet.group.name
        : '$scope · ${worksheet.group.name}';
  }

  Future<void> _leaveWorksheet(
    BuildContext context,
    WidgetRef ref,
    YorksV1BoqWorksheetController controller,
    YorksV1BoqWorksheetState state,
  ) async {
    if (!state.hasUnsavedChanges) {
      if (context.mounted) context.pop();
      return;
    }
    final decision = await _showUnsavedWorksheetDialog(context);
    if (decision == _UnsavedWorksheetDecision.keepEditing || !context.mounted) {
      return;
    }
    if (decision == _UnsavedWorksheetDecision.save) {
      final saved = await controller.save();
      if (!context.mounted) return;
      if (!saved) {
        _showBoqFailure(
          context,
          ref.read(yorksV1BoqWorksheetControllerProvider(groupId)).errorCode,
        );
        return;
      }
      _invalidateGroupLists(ref, projectId, state.worksheet?.group.scopeId);
    } else {
      await controller.discardLocalChanges();
      if (!context.mounted) return;
    }
    context.pop();
  }

  Future<void> _refreshWorksheet(
    BuildContext context,
    WidgetRef ref,
    YorksV1BoqWorksheetController controller,
    YorksV1BoqWorksheetState state,
  ) async {
    if (!state.hasUnsavedChanges) {
      await controller.load();
      return;
    }
    final decision = await _showUnsavedWorksheetDialog(context);
    if (decision == _UnsavedWorksheetDecision.keepEditing) return;
    if (decision == _UnsavedWorksheetDecision.save) {
      final saved = await controller.save();
      if (!saved || !context.mounted) {
        if (context.mounted) {
          _showBoqFailure(
            context,
            ref.read(yorksV1BoqWorksheetControllerProvider(groupId)).errorCode,
          );
        }
        return;
      }
    }
    await controller.load(discardLocalChanges: true);
  }

  Future<void> _createRequestDraft(
    BuildContext context,
    WidgetRef ref,
    YorksV1BoqWorksheetController controller,
    YorksV1BoqWorksheetState state,
  ) async {
    final worksheet = state.worksheet;
    if (worksheet == null || !_hasRequestReadyBoqRow(worksheet)) {
      _showBoqFailure(context, YorksV1DomainErrorCode.invalidInput);
      return;
    }
    if (state.hasUnsavedChanges) {
      final saved = await controller.save();
      if (!saved || !context.mounted) {
        if (context.mounted) {
          _showBoqFailure(
            context,
            ref.read(yorksV1BoqWorksheetControllerProvider(groupId)).errorCode,
          );
        }
        return;
      }
      _invalidateGroupLists(ref, projectId, worksheet.group.scopeId);
    }
    final current = ref
        .read(yorksV1BoqWorksheetControllerProvider(groupId))
        .worksheet;
    if (current == null || !context.mounted) return;
    context.push(
      RoutePaths.yorksV1MaterialRequestDraftPath(
        const Uuid().v4(),
        boqGroupId: groupId,
        projectId: projectId,
        boqVersion: current.group.version,
        entryMode: YorksV1MaterialRequestDraftEntryMode.newDraft,
      ),
    );
  }

  Future<void> _exportWorksheet(
    BuildContext context,
    WidgetRef ref,
    YorksV1BoqWorksheetController controller,
    YorksV1BoqWorksheetState state,
  ) async {
    final selected = await _resolveWorksheetOutput(
      context,
      ref,
      controller,
      state,
    );
    if (selected == null || !context.mounted) return;
    await _exportWorkbook(
      context,
      ref,
      selected.worksheet,
      draftCopy: selected.draftCopy,
    );
  }

  Future<void> _printWorksheetWithChoice(
    BuildContext context,
    WidgetRef ref,
    YorksV1BoqWorksheetController controller,
    YorksV1BoqWorksheetState state, {
    required bool canViewCommercials,
  }) async {
    final selected = await _resolveWorksheetOutput(
      context,
      ref,
      controller,
      state,
    );
    if (selected == null || !context.mounted) return;
    await _printWorksheet(
      context,
      selected.worksheet,
      canViewCommercials: canViewCommercials,
      draftCopy: selected.draftCopy,
    );
  }

  Future<_ResolvedWorksheetOutput?> _resolveWorksheetOutput(
    BuildContext context,
    WidgetRef ref,
    YorksV1BoqWorksheetController controller,
    YorksV1BoqWorksheetState state,
  ) async {
    final worksheet = state.worksheet;
    if (worksheet == null) return null;
    if (!state.hasUnsavedChanges) {
      return _ResolvedWorksheetOutput(worksheet: worksheet);
    }
    final choice = await _showOutputChoice(context);
    if (choice == _WorksheetOutputChoice.cancel) return null;
    if (choice == _WorksheetOutputChoice.draftCopy) {
      return _ResolvedWorksheetOutput(worksheet: worksheet, draftCopy: true);
    }
    final saved = await controller.save();
    if (!saved || !context.mounted) {
      if (context.mounted) {
        _showBoqFailure(
          context,
          ref.read(yorksV1BoqWorksheetControllerProvider(groupId)).errorCode,
        );
      }
      return null;
    }
    _invalidateGroupLists(ref, projectId, worksheet.group.scopeId);
    final current = ref
        .read(yorksV1BoqWorksheetControllerProvider(groupId))
        .worksheet;
    return current == null
        ? null
        : _ResolvedWorksheetOutput(worksheet: current);
  }

  Future<void> _archive(
    BuildContext context,
    WidgetRef ref,
    YorksV1BoqGroup group,
  ) async {
    final reason = await _promptForFolderReason(
      context,
      title: YorksV1BoqStrings.archiveGroup,
      description: YorksV1BoqStrings.archiveGroupConfirmation,
      language: ref.read(languageProvider),
    );
    if (reason == null) return;
    try {
      await ref
          .read(yorksV1BoqRepositoryProvider)
          .archiveGroup(
            YorksV1ArchiveBoqGroupInput(
              groupId: group.id,
              expectedVersion: group.version,
              reason: reason,
              idempotencyKey: const Uuid().v4(),
            ),
          );
      _invalidateGroupLists(ref, projectId, group.scopeId);
      if (context.mounted) context.pop();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(YorksV1BoqStrings.saveFailed.primary)),
      );
    }
  }

  Future<void> _importWorkbook(
    BuildContext context,
    WidgetRef ref,
    YorksV1BoqWorksheetController controller,
    YorksV1BoqWorksheet worksheet,
    AppLanguage language,
  ) async {
    try {
      final fileService = ref.read(yorksV1BoqWorkbookFileServiceProvider);
      final codec = ref.read(yorksV1BoqWorkbookCodecProvider);
      final canManageCommercials = ref.read(canManageCommercialsProvider);
      if (YorksMobileUi.isActive(context)) {
        final imported = await Navigator.of(context, rootNavigator: true)
            .push<bool>(
              MaterialPageRoute<bool>(
                fullscreenDialog: true,
                builder: (_) => _MobileBoqWorkbookImportFlow(
                  fileService: fileService,
                  codec: codec,
                  worksheet: worksheet,
                  language: language,
                  canManageCommercials: canManageCommercials,
                  onCommit: controller.importWorkbook,
                  readSyncStatus: () => ref
                      .read(yorksV1BoqWorksheetControllerProvider(groupId))
                      .status,
                  onRefresh: controller.load,
                ),
              ),
            );
        if (!context.mounted || imported != true) return;
        _invalidateGroupLists(ref, projectId, worksheet.group.scopeId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(YorksV1BoqStrings.imported.primary)),
        );
        return;
      }
      final selected = await fileService.selectWorkbook();
      if (selected == null || !context.mounted) return;
      final workbook = codec.decode(
        bytes: selected.bytes,
        fileName: selected.fileName,
      );
      final preview = await showDialog<YorksV1BoqImportPreview>(
        context: context,
        animationStyle: AnimationStyle.noAnimation,
        builder: (_) => _BoqWorkbookImportDialog(
          workbook: workbook,
          codec: codec,
          fallbackTitle: worksheet.group.effectiveTitle,
          language: language,
          canManageCommercials: canManageCommercials,
        ),
      );
      if (preview == null) return;
      final imported = await controller.importWorkbook(preview);
      if (!context.mounted) return;
      if (imported) {
        _invalidateGroupLists(ref, projectId, worksheet.group.scopeId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(YorksV1BoqStrings.imported.primary)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(YorksV1BoqStrings.importFailed.primary)),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(YorksV1BoqStrings.importFailed.primary)),
      );
    }
  }

  Future<void> _exportWorkbook(
    BuildContext context,
    WidgetRef ref,
    YorksV1BoqWorksheet worksheet, {
    bool draftCopy = false,
  }) async {
    try {
      final codec = ref.read(yorksV1BoqWorkbookCodecProvider);
      final saved = await ref
          .read(yorksV1BoqWorkbookFileServiceProvider)
          .saveWorkbook(
            bytes: codec.encodeWorksheet(worksheet),
            suggestedName: _workbookFileName(
              worksheet.group.effectiveTitle,
              worksheet.group.version,
              draftCopy: draftCopy,
            ),
          );
      if (!context.mounted || !saved) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(YorksV1BoqStrings.exported.primary)),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(YorksV1BoqStrings.exportFailed.primary)),
      );
    }
  }

  Future<void> _printWorksheet(
    BuildContext context,
    YorksV1BoqWorksheet worksheet, {
    required bool canViewCommercials,
    bool draftCopy = false,
  }) async {
    try {
      await const YorksV1BoqDocumentService().printWorksheet(
        worksheet,
        canViewCommercials: canViewCommercials,
        draftCopy: draftCopy,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(YorksV1BoqStrings.printFailed.primary)),
      );
    }
  }

  static String _workbookFileName(
    String title,
    int version, {
    required bool draftCopy,
  }) {
    final safe = title
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final state = draftCopy ? 'DRAFT' : 'v$version';
    return '${safe.isEmpty ? 'Yorks_BOQ' : safe}_$state.xlsx';
  }
}

enum _UnsavedWorksheetDecision { save, discard, keepEditing }

enum _WorksheetOutputChoice { saveAndGenerate, draftCopy, cancel }

class _ResolvedWorksheetOutput {
  const _ResolvedWorksheetOutput({
    required this.worksheet,
    this.draftCopy = false,
  });

  final YorksV1BoqWorksheet worksheet;
  final bool draftCopy;
}

Future<_UnsavedWorksheetDecision> _showUnsavedWorksheetDialog(
  BuildContext context,
) async =>
    await showDialog<_UnsavedWorksheetDecision>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(YorksV1BoqStrings.unsavedWorksheetTitle.primary),
        content: Text(YorksV1BoqStrings.unsavedWorksheetBody.primary),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              _UnsavedWorksheetDecision.keepEditing,
            ),
            child: Text(AppStrings.keepEditing.primary),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _UnsavedWorksheetDecision.discard),
            child: Text(AppStrings.discard.primary),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _UnsavedWorksheetDecision.save),
            child: Text(YorksV1BoqStrings.saveAndContinue.primary),
          ),
        ],
      ),
    ) ??
    _UnsavedWorksheetDecision.keepEditing;

Future<_WorksheetOutputChoice> _showOutputChoice(BuildContext context) async =>
    await showDialog<_WorksheetOutputChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(YorksV1BoqStrings.outputUnsavedTitle.primary),
        content: Text(YorksV1BoqStrings.outputUnsavedBody.primary),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _WorksheetOutputChoice.cancel),
            child: Text(YorksV1BoqStrings.cancel.primary),
          ),
          OutlinedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _WorksheetOutputChoice.draftCopy),
            child: Text(YorksV1BoqStrings.draftCopy.primary),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              _WorksheetOutputChoice.saveAndGenerate,
            ),
            child: Text(YorksV1BoqStrings.saveAndContinue.primary),
          ),
        ],
      ),
    ) ??
    _WorksheetOutputChoice.cancel;

bool _hasRequestReadyBoqRow(YorksV1BoqWorksheet worksheet) {
  for (final row in worksheet.rows) {
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
  }
  return false;
}

void _showBoqFailure(BuildContext context, YorksV1DomainErrorCode? errorCode) {
  final copy = switch (errorCode) {
    YorksV1DomainErrorCode.conflict => YorksV1BoqStrings.syncConflict,
    YorksV1DomainErrorCode.invalidInput => YorksV1BoqStrings.noRequestReadyRows,
    YorksV1DomainErrorCode.offline => YorksV1BoqStrings.offlineSave,
    YorksV1DomainErrorCode.unauthorized => YorksV1BoqStrings.permissionDenied,
    YorksV1DomainErrorCode.backendUnavailable ||
    YorksV1DomainErrorCode.unexpectedResponse =>
      YorksV1BoqStrings.serviceUnavailable,
    _ => YorksV1BoqStrings.saveFailed,
  };
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(copy.primary)));
}

void _invalidateGroupLists(WidgetRef ref, String projectId, String? scopeId) {
  ref.invalidate(yorksV1BoqGroupsProvider(projectId));
  ref.invalidate(
    yorksV1ScopedBoqGroupsProvider(YorksV1BoqScopeQuery(projectId: projectId)),
  );
  if (scopeId == null) return;
  ref.invalidate(
    yorksV1ScopedBoqGroupsProvider(
      YorksV1BoqScopeQuery(projectId: projectId, scopeId: scopeId),
    ),
  );
}

void _invalidateFolderManagement(
  WidgetRef ref,
  String projectId,
  String? scopeId,
) {
  _invalidateGroupLists(ref, projectId, scopeId);
  if (scopeId == null || scopeId.trim().isEmpty) return;
  ref.invalidate(
    yorksV1BoqFolderManagementProvider(
      YorksV1BoqScopeQuery(projectId: projectId, scopeId: scopeId),
    ),
  );
}

class _WorksheetBody extends ConsumerWidget {
  const _WorksheetBody({
    required this.state,
    required this.controller,
    required this.language,
    required this.editable,
    required this.showEditActions,
    required this.excelEnabled,
    required this.canViewCommercials,
    required this.canManageCommercials,
    required this.onSaved,
    required this.showPageHeader,
    required this.showCreateRequestFromFolder,
    this.onCreateRequestFromFolder,
    this.onImport,
    this.onExport,
    this.onPrint,
    this.onOpenDocuments,
    this.onOpenRequests,
  });

  final YorksV1BoqWorksheetState state;
  final YorksV1BoqWorksheetController controller;
  final AppLanguage language;
  final bool editable;
  final bool showEditActions;
  final bool excelEnabled;
  final bool canViewCommercials;
  final bool canManageCommercials;
  final VoidCallback onSaved;
  final bool showPageHeader;
  final bool showCreateRequestFromFolder;
  final VoidCallback? onCreateRequestFromFolder;
  final Future<void> Function()? onImport;
  final Future<void> Function()? onExport;
  final Future<void> Function()? onPrint;
  final VoidCallback? onOpenDocuments;
  final VoidCallback? onOpenRequests;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final worksheet = state.worksheet!;
    final scopeId = worksheet.group.scopeId;
    final preferences = ref.watch(sharedPreferencesProvider);
    final ownerAuthUserId =
        ref.watch(yorksV1AuthUserIdProvider) ?? 'signed-out';
    String columnWidthKey(String columnId) =>
        'yorks_v1_boq_column_width_v1:$ownerAuthUserId:${worksheet.group.id}:$columnId';
    final compact = YorksMobileUi.isActive(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        compact ? AppSpacing.sm : AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showPageHeader) ...[
            _WorksheetContextBar(
              group: worksheet.group,
              status: _worksheetStatusCopy(state.status),
              statusColor: _worksheetStatusColor(state.status),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          _WorksheetHeader(
            worksheet: worksheet,
            language: language,
            editable: editable,
            showEditActions: showEditActions,
            excelEnabled: excelEnabled,
            state: state,
            onTitleChanged: controller.updateTitle,
            onImport: onImport,
            onExport: onExport,
            onPrint: onPrint,
            onOpenDocuments: onOpenDocuments,
            onAddMaterial: editable && worksheet.columns.isNotEmpty
                ? () => controller.addBlankRow(
                    afterRowId: worksheet.rows.lastOrNull?.id,
                  )
                : null,
            onSave: () async {
              final saved = await controller.save();
              if (!context.mounted) return;
              if (saved) {
                onSaved();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(YorksV1BoqStrings.saved.primary)),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(YorksV1BoqStrings.saveFailed.primary)),
                );
              }
            },
            onRefresh: controller.load,
            onCreateRequestFromFolder: onCreateRequestFromFolder,
            showCreateRequestFromFolder: showCreateRequestFromFolder,
          ),
          const SizedBox(height: AppSpacing.sm),
          _LinkedWorkStrip(
            group: worksheet.group,
            compact: compact,
            onOpenDocuments: onOpenDocuments,
            onOpenRequests: onOpenRequests,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (!editable && !showEditActions)
            _ReadOnlyBanner(language: language),
          if (!editable && !showEditActions)
            const SizedBox(height: AppSpacing.md),
          if (state.status == YorksV1BoqSyncStatus.conflict)
            _ConflictBanner(language: language, onRefresh: controller.load),
          if (state.status == YorksV1BoqSyncStatus.conflict)
            const SizedBox(height: AppSpacing.md),
          Expanded(
            child: YorksV1BoqSpreadsheet(
              worksheet: worksheet,
              editable: editable,
              showEditActions: showEditActions,
              canViewCommercials: canViewCommercials,
              canManageCommercials: canManageCommercials,
              canUndo: controller.canUndo,
              canRedo: controller.canRedo,
              initialColumnWidths: {
                for (final column in worksheet.columns)
                  if (!column.isCommercial &&
                      preferences.getDouble(columnWidthKey(column.id)) != null)
                    column.id: preferences.getDouble(
                      columnWidthKey(column.id),
                    )!,
              },
              onColumnWidthChanged: (columnId, width) {
                final column = worksheet.columns
                    .where((item) => item.id == columnId)
                    .firstOrNull;
                if (column == null || column.isCommercial) return;
                preferences.setDouble(columnWidthKey(columnId), width);
              },
              onUndo: controller.undo,
              onRedo: controller.redo,
              mobileConflict: state.status == YorksV1BoqSyncStatus.conflict,
              mobileLanguage: language,
              onMobileRefresh: controller.load,
              onSearchMaterials: scopeId == null
                  ? null
                  : (query, excludedRowId) async {
                      final suggestions = await ref.read(
                        yorksV1MaterialRequestInventorySearchProvider(
                          YorksV1MaterialRequestInventorySearchKey(
                            projectId: worksheet.group.projectId,
                            scopeId: scopeId,
                            query: query,
                          ),
                        ).future,
                      );
                      return suggestions
                          .where(
                            (suggestion) =>
                                suggestion.sourceBoqRowId != excludedRowId,
                          )
                          .toList(growable: false);
                    },
              onApplyMaterialSuggestion: (rowId, suggestion) =>
                  controller.updateMaterialCells(
                    rowId: rowId,
                    values: _boqMaterialValues(suggestion),
                  ),
              onMaterialSuggestionSelected: (suggestion) {
                ref
                    .read(analyticsServiceProvider)
                    .recordMaterialSearchSelection();
              },
              onUpdateCell: controller.updateCell,
              onPasteCells: controller.pasteCells,
              onAddBlankRow: controller.addBlankRow,
              onAddSimilarRow: controller.addSimilarRow,
              onRemoveRow: controller.removeRow,
              onAddColumn: controller.addColumn,
              onRenameColumn: controller.renameColumn,
              onRemoveColumn: controller.removeColumn,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorksheetContextBar extends StatelessWidget {
  const _WorksheetContextBar({
    required this.group,
    required this.status,
    required this.statusColor,
  });

  final YorksV1BoqGroup group;
  final TranslatableString status;
  final Color statusColor;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('boq-worksheet-context-bar'),
    height: 60,
    child: Row(
      children: [
        Container(
          width: AppSpacing.massive,
          height: AppSpacing.massive,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: const Icon(Icons.folder_outlined, color: AppColors.blue),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.titleLarge.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (group.scopeName?.trim().isNotEmpty == true)
                Text(
                  group.scopeName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _SyncChip(copy: status, color: statusColor),
      ],
    ),
  );
}

class _LinkedWorkStrip extends StatelessWidget {
  const _LinkedWorkStrip({
    required this.group,
    required this.compact,
    this.onOpenDocuments,
    this.onOpenRequests,
  });

  final YorksV1BoqGroup group;
  final bool compact;
  final VoidCallback? onOpenDocuments;
  final VoidCallback? onOpenRequests;

  @override
  Widget build(BuildContext context) {
    final lastEditedAt = group.lastEditedAt?.toLocal();
    final lastEditedLabel = lastEditedAt == null
        ? null
        : '${YorksV1BoqStrings.lastEdited.primary}: '
              '${group.lastEditedBy ?? group.lastEditedRole ?? ''} · '
              '${MaterialLocalizations.of(context).formatMediumDate(lastEditedAt)} · '
              '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(lastEditedAt))}';
    if (compact) {
      final metadata = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CountPill(
            label: '${YorksV1BoqStrings.revision.primary} ${group.version}',
          ),
          const SizedBox(width: AppSpacing.sm),
          ActionChip(
            avatar: const Icon(Icons.assignment_outlined, size: 17),
            label: Text(
              '${group.linkedRequestCount} '
              '${YorksV1BoqStrings.linkedRequests.primary}',
            ),
            onPressed: onOpenRequests,
          ),
          const SizedBox(width: AppSpacing.sm),
          ActionChip(
            avatar: const Icon(Icons.description_outlined, size: 17),
            label: Text(
              '${group.documentCount} '
              '${YorksV1BoqStrings.linkedDocuments.primary}',
            ),
            onPressed: onOpenDocuments,
          ),
        ],
      );
      return Container(
        key: const ValueKey('boq-linked-work-strip'),
        constraints: const BoxConstraints(
          minHeight: AppSpacing.gigantic,
          maxHeight: AppSpacing.colossal,
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          children: [
            const Icon(Icons.link_rounded, size: 19, color: AppColors.blue),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: lastEditedLabel == null
                    ? metadata
                    : Tooltip(message: lastEditedLabel, child: metadata),
              ),
            ),
          ],
        ),
      );
    }
    final metadata = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WorksheetMetadataChip(
          icon: Icons.description_outlined,
          label: '${YorksV1BoqStrings.revision.primary} ${group.version}',
        ),
        if (!compact && lastEditedLabel != null) ...[
          const SizedBox(width: AppSpacing.sm),
          _WorksheetMetadataChip(
            icon: Icons.schedule_outlined,
            label: lastEditedLabel,
          ),
        ],
        const SizedBox(width: AppSpacing.sm),
        _WorksheetMetadataChip(
          icon: Icons.link_rounded,
          label:
              '${group.linkedRequestCount} '
              '${YorksV1BoqStrings.linkedRequests.primary}',
          onTap: onOpenRequests,
        ),
        const SizedBox(width: AppSpacing.sm),
        _WorksheetMetadataChip(
          icon: Icons.description_outlined,
          label:
              '${group.documentCount} '
              '${YorksV1BoqStrings.linkedDocuments.primary}',
          onTap: onOpenDocuments,
        ),
      ],
    );
    final scrollableMetadata = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: lastEditedLabel == null || !compact
          ? metadata
          : Tooltip(message: lastEditedLabel, child: metadata),
    );
    return SizedBox(
      key: const ValueKey('boq-linked-work-strip'),
      height: compact ? AppSpacing.minTapTarget : 36,
      child: Row(
        children: [
          if (!compact) ...[
            _WorksheetMetadataChip(
              icon: Icons.link_rounded,
              label: YorksV1BoqStrings.linkedWork.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(child: scrollableMetadata),
        ],
      ),
    );
  }
}

class _WorksheetMetadataChip extends StatelessWidget {
  const _WorksheetMetadataChip({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceContainerLow,
    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: AppColors.blue),
            const SizedBox(width: AppSpacing.sm),
            Text(label, style: AppTypography.bodySmall),
          ],
        ),
      ),
    ),
  );
}

TranslatableString _worksheetStatusCopy(YorksV1BoqSyncStatus status) =>
    switch (status) {
      YorksV1BoqSyncStatus.saving => YorksV1BoqStrings.saving,
      YorksV1BoqSyncStatus.saved ||
      YorksV1BoqSyncStatus.ready => YorksV1BoqStrings.saved,
      _ => YorksV1BoqStrings.unsavedChanges,
    };

Color _worksheetStatusColor(YorksV1BoqSyncStatus status) =>
    status == YorksV1BoqSyncStatus.saving
    ? AppColors.blue
    : status == YorksV1BoqSyncStatus.saved ||
          status == YorksV1BoqSyncStatus.ready
    ? AppColors.success
    : AppColors.warning;

class _WorksheetHeader extends StatelessWidget {
  const _WorksheetHeader({
    required this.worksheet,
    required this.language,
    required this.editable,
    required this.showEditActions,
    required this.excelEnabled,
    required this.state,
    required this.onTitleChanged,
    required this.onSave,
    this.onImport,
    this.onExport,
    this.onPrint,
    this.onOpenDocuments,
    this.onAddMaterial,
    required this.onRefresh,
    this.onCreateRequestFromFolder,
    required this.showCreateRequestFromFolder,
  });

  final YorksV1BoqWorksheet worksheet;
  final AppLanguage language;
  final bool editable;
  final bool showEditActions;
  final bool excelEnabled;
  final YorksV1BoqWorksheetState state;
  final ValueChanged<String> onTitleChanged;
  final Future<void> Function() onSave;
  final Future<void> Function()? onImport;
  final Future<void> Function()? onExport;
  final Future<void> Function()? onPrint;
  final VoidCallback? onOpenDocuments;
  final VoidCallback? onAddMaterial;
  final Future<void> Function() onRefresh;
  final VoidCallback? onCreateRequestFromFolder;
  final bool showCreateRequestFromFolder;

  @override
  Widget build(BuildContext context) {
    final status = _worksheetStatusCopy(state.status);
    final statusColor = _worksheetStatusColor(state.status);
    if (YorksMobileUi.isActive(context)) {
      return _MobileWorksheetHeader(
        worksheet: worksheet,
        status: status,
        statusColor: statusColor,
        editable: editable,
        showEditActions: showEditActions,
        saving: state.status == YorksV1BoqSyncStatus.saving,
        onTitleChanged: onTitleChanged,
        onAddMaterial: onAddMaterial,
        onImport: excelEnabled ? onImport : null,
        onExport: excelEnabled ? onExport : null,
        onPrint: onPrint,
        onOpenDocuments: onOpenDocuments,
        onSave: onSave,
        onCreateRequestFromFolder: onCreateRequestFromFolder,
        showCreateRequestFromFolder: showCreateRequestFromFolder,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow =
            constraints.maxWidth < AppSpacing.yorksV1DesktopBreakpoint;
        final title = TextFormField(
          key: ValueKey('boq-title-${worksheet.group.id}'),
          initialValue: worksheet.group.worksheetTitle,
          enabled: editable,
          onChanged: onTitleChanged,
          decoration: InputDecoration(
            labelText: YorksV1BoqStrings.worksheetTitle.primary,
            border: const OutlineInputBorder(),
          ),
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w800,
          ),
        );
        final actions = Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            if (excelEnabled && onExport != null)
              OutlinedButton.icon(
                key: const ValueKey('boq-export-workbook'),
                onPressed: onExport,
                icon: const Icon(YorksDataTransferIcons.exportData),
                label: Text(YorksV1BoqStrings.exportWorkbook.primary),
              ),
            if (excelEnabled && onImport != null)
              OutlinedButton.icon(
                key: const ValueKey('boq-import-workbook'),
                onPressed: state.status == YorksV1BoqSyncStatus.saving
                    ? null
                    : onImport,
                icon: const Icon(YorksDataTransferIcons.importData),
                label: Text(YorksV1BoqStrings.importWorkbook.primary),
              ),
            if (onPrint != null)
              OutlinedButton.icon(
                key: const ValueKey('boq-print-workbook'),
                onPressed: onPrint,
                icon: const Icon(Icons.print_outlined),
                label: Text(YorksV1BoqStrings.printBoq.primary),
              ),
            if (showEditActions)
              FilledButton.icon(
                onPressed:
                    state.status == YorksV1BoqSyncStatus.saving || !editable
                    ? null
                    : onSave,
                icon: const Icon(Icons.save_outlined),
                label: Text(YorksV1BoqStrings.save.primary),
              ),
            if (showCreateRequestFromFolder)
              OutlinedButton.icon(
                key: const ValueKey('boq-create-request-from-folder'),
                onPressed: onCreateRequestFromFolder,
                icon: const Icon(Icons.assignment_outlined),
                label: Text(YorksV1BoqStrings.sendWholeGroup.primary),
              ),
          ],
        );
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: AppSpacing.sm),
              actions,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: title),
            const SizedBox(width: AppSpacing.md),
            actions,
          ],
        );
      },
    );
  }
}

class _MobileWorksheetHeader extends StatelessWidget {
  const _MobileWorksheetHeader({
    required this.worksheet,
    required this.status,
    required this.statusColor,
    required this.editable,
    required this.showEditActions,
    required this.saving,
    required this.onTitleChanged,
    required this.onSave,
    this.onAddMaterial,
    this.onImport,
    this.onExport,
    this.onPrint,
    this.onOpenDocuments,
    this.onCreateRequestFromFolder,
    required this.showCreateRequestFromFolder,
  });

  final YorksV1BoqWorksheet worksheet;
  final TranslatableString status;
  final Color statusColor;
  final bool editable;
  final bool showEditActions;
  final bool saving;
  final ValueChanged<String> onTitleChanged;
  final Future<void> Function() onSave;
  final VoidCallback? onAddMaterial;
  final Future<void> Function()? onImport;
  final Future<void> Function()? onExport;
  final Future<void> Function()? onPrint;
  final VoidCallback? onOpenDocuments;
  final VoidCallback? onCreateRequestFromFolder;
  final bool showCreateRequestFromFolder;

  @override
  Widget build(BuildContext context) => YorksMobileCard(
    padding: const EdgeInsets.all(AppSpacing.sm),
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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          worksheet.group.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.titleMedium.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (showEditActions)
                        IconButton(
                          tooltip: YorksV1BoqStrings.worksheetTitle.primary,
                          constraints: const BoxConstraints(
                            minWidth: AppSpacing.minTapTarget,
                            minHeight: AppSpacing.minTapTarget,
                          ),
                          onPressed: editable
                              ? () => _editMobileWorksheetTitle(
                                  context,
                                  worksheet.group.worksheetTitle,
                                  onTitleChanged,
                                )
                              : null,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                        ),
                    ],
                  ),
                  if (worksheet.group.scopeName?.trim().isNotEmpty == true)
                    Text(
                      worksheet.group.scopeName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  if (worksheet.group.worksheetTitle.trim().isNotEmpty &&
                      worksheet.group.worksheetTitle.trim() !=
                          worksheet.group.name.trim())
                    Text(
                      worksheet.group.worksheetTitle.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _SyncChip(copy: status, color: statusColor),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _MobileWorksheetAction(
                key: const ValueKey('boq-mobile-add-material'),
                label: YorksV1BoqStrings.addMaterial.primary,
                icon: Icons.add_rounded,
                primary: true,
                onPressed: onAddMaterial,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            PopupMenuButton<_MobileWorksheetMenuAction>(
              key: const ValueKey('boq-mobile-more-actions'),
              tooltip: AppStrings.more.primary,
              onSelected: (action) async {
                switch (action) {
                  case _MobileWorksheetMenuAction.importWorkbook:
                    await onImport?.call();
                  case _MobileWorksheetMenuAction.exportWorkbook:
                    await onExport?.call();
                  case _MobileWorksheetMenuAction.print:
                    await onPrint?.call();
                  case _MobileWorksheetMenuAction.documents:
                    onOpenDocuments?.call();
                }
              },
              itemBuilder: (_) => [
                if (onImport != null)
                  PopupMenuItem(
                    key: const ValueKey('boq-import-workbook'),
                    value: _MobileWorksheetMenuAction.importWorkbook,
                    enabled: !saving,
                    child: ListTile(
                      leading: const Icon(YorksDataTransferIcons.importData),
                      title: Text(YorksV1BoqStrings.importWorkbook.primary),
                    ),
                  ),
                if (onExport != null)
                  PopupMenuItem(
                    key: const ValueKey('boq-export-workbook'),
                    value: _MobileWorksheetMenuAction.exportWorkbook,
                    child: ListTile(
                      leading: const Icon(YorksDataTransferIcons.exportData),
                      title: Text(YorksV1BoqStrings.exportWorkbook.primary),
                    ),
                  ),
                if (onPrint != null)
                  PopupMenuItem(
                    key: const ValueKey('boq-print-workbook'),
                    value: _MobileWorksheetMenuAction.print,
                    child: ListTile(
                      leading: const Icon(Icons.print_outlined),
                      title: Text(YorksV1BoqStrings.printBoq.primary),
                    ),
                  ),
                if (onOpenDocuments != null)
                  PopupMenuItem(
                    value: _MobileWorksheetMenuAction.documents,
                    child: ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(YorksV1DocumentStrings.documents.primary),
                    ),
                  ),
              ],
              child: Container(
                width: AppSpacing.massive,
                height: AppSpacing.massive,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.line),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: const Icon(Icons.more_horiz_rounded),
              ),
            ),
          ],
        ),
        if (showEditActions || showCreateRequestFromFolder) ...[
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: AppSpacing.massive,
            child: Row(
              children: [
                if (showEditActions)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: saving || !editable ? null : onSave,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: Text(YorksV1BoqStrings.saveWorksheet.primary),
                    ),
                  ),
                if (showEditActions && showCreateRequestFromFolder)
                  const SizedBox(width: AppSpacing.sm),
                if (showCreateRequestFromFolder)
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('boq-create-request-from-folder'),
                      onPressed: onCreateRequestFromFolder,
                      icon: const Icon(Icons.assignment_outlined, size: 18),
                      label: Text(YorksV1BoqStrings.sendWholeGroup.primary),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    ),
  );

  static Future<void> _editMobileWorksheetTitle(
    BuildContext context,
    String current,
    ValueChanged<String> onChanged,
  ) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(YorksV1BoqStrings.worksheetTitle.primary),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(YorksV1BoqStrings.cancel.primary),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(YorksV1BoqStrings.save.primary),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null && result.trim().isNotEmpty) onChanged(result.trim());
  }
}

enum _MobileWorksheetMenuAction {
  importWorkbook,
  exportWorkbook,
  print,
  documents,
}

class _MobileWorksheetAction extends StatelessWidget {
  const _MobileWorksheetAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 21),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelLarge.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
    return SizedBox(
      height: AppSpacing.massive,
      child: primary
          ? FilledButton(onPressed: onPressed, child: child)
          : OutlinedButton(onPressed: onPressed, child: child),
    );
  }
}

class _MobileBoqWorkbookImportFlow extends StatefulWidget {
  const _MobileBoqWorkbookImportFlow({
    required this.fileService,
    required this.codec,
    required this.worksheet,
    required this.language,
    required this.canManageCommercials,
    required this.onCommit,
    required this.readSyncStatus,
    required this.onRefresh,
  });

  final YorksV1BoqWorkbookFileService fileService;
  final YorksV1BoqWorkbookCodec codec;
  final YorksV1BoqWorksheet worksheet;
  final AppLanguage language;
  final bool canManageCommercials;
  final Future<bool> Function(YorksV1BoqImportPreview preview) onCommit;
  final YorksV1BoqSyncStatus Function() readSyncStatus;
  final Future<void> Function() onRefresh;

  @override
  State<_MobileBoqWorkbookImportFlow> createState() =>
      _MobileBoqWorkbookImportFlowState();
}

class _MobileBoqWorkbookImportFlowState
    extends State<_MobileBoqWorkbookImportFlow> {
  int _step = 0;
  bool _busy = false;
  bool _commitFailed = false;
  bool _commitConflict = false;
  bool _selectionFailed = false;
  YorksV1BoqParsedWorkbook? _workbook;
  YorksV1BoqWorkbookSheet? _sheet;
  int _headerRowIndex = 0;
  bool _hasSelectedHeader = false;
  String _title = '';
  List<int> _headerRowIndexes = const [];
  List<YorksV1BoqHeaderPath> _headerHierarchy = const [];
  List<YorksV1BoqImportColumn> _columns = const [];
  List<YorksV1BoqImportRow> _rows = const [];

  YorksV1BoqImportPreview? get _preview {
    final workbook = _workbook;
    final sheet = _sheet;
    if (workbook == null || sheet == null) return null;
    return YorksV1BoqImportPreview(
      fileName: workbook.fileName,
      worksheetName: sheet.name,
      title: _title,
      headerRowIndex: _headerRowIndex,
      headerRowIndexes: _headerRowIndexes,
      headerHierarchy: _headerHierarchy,
      columns: _columns,
      rows: _rows,
      validationIssues: _importValidationIssues(
        widget.codec,
        _columns,
        canManageCommercials: widget.canManageCommercials,
      ),
    );
  }

  void _resetPreview() {
    final workbook = _workbook;
    final sheet = _sheet;
    if (workbook == null || sheet == null) return;
    final detected = widget.codec.preview(
      workbook: workbook,
      sheet: sheet,
      fallbackTitle: widget.worksheet.group.effectiveTitle,
      headerRowIndex: _hasSelectedHeader ? _headerRowIndex : null,
    );
    _headerRowIndex = detected.headerRowIndex;
    _headerRowIndexes = detected.headerRowIndexes;
    _headerHierarchy = detected.headerHierarchy;
    _title = detected.title;
    _columns = detected.columns;
    _rows = detected.rows;
  }

  Future<void> _pickWorkbook() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _commitFailed = false;
      _commitConflict = false;
      _selectionFailed = false;
    });
    try {
      final selected = await widget.fileService.selectWorkbook();
      if (selected == null || !mounted) return;
      final workbook = widget.codec.decode(
        bytes: selected.bytes,
        fileName: selected.fileName,
      );
      setState(() {
        _workbook = workbook;
        _sheet = workbook.sheets.first;
        _headerRowIndex = 0;
        _hasSelectedHeader = false;
        _selectionFailed = false;
        _resetPreview();
      });
    } catch (_) {
      if (mounted) setState(() => _selectionFailed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _selectSheet(YorksV1BoqWorkbookSheet sheet) {
    setState(() {
      _sheet = sheet;
      _headerRowIndex = 0;
      _hasSelectedHeader = false;
      _commitFailed = false;
      _commitConflict = false;
      _resetPreview();
    });
  }

  void _selectHeader(int index) {
    setState(() {
      _headerRowIndex = index;
      _hasSelectedHeader = true;
      _commitFailed = false;
      _commitConflict = false;
      _resetPreview();
    });
  }

  void _updateColumn(
    int index,
    YorksV1BoqImportColumn Function(YorksV1BoqImportColumn current) update,
  ) {
    setState(() {
      _columns = [
        for (var item = 0; item < _columns.length; item++)
          item == index ? update(_columns[item]) : _columns[item],
      ];
      _commitFailed = false;
      _commitConflict = false;
    });
  }

  Future<void> _continue() async {
    if (_step < 3) {
      setState(() => _step += 1);
      return;
    }
    final preview = _preview;
    if (preview == null || !preview.isValid || preview.title.trim().isEmpty) {
      return;
    }
    setState(() {
      _busy = true;
      _commitFailed = false;
      _commitConflict = false;
    });
    bool imported;
    try {
      imported = await widget.onCommit(preview);
    } catch (_) {
      imported = false;
    }
    if (!mounted) return;
    if (imported) {
      setState(() => _busy = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, true);
      });
      return;
    }
    setState(() {
      _busy = false;
      _commitConflict =
          widget.readSyncStatus() == YorksV1BoqSyncStatus.conflict;
      _commitFailed = !_commitConflict;
    });
  }

  Future<void> _refreshAfterConflict() async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.onRefresh();
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final steps = [
      YorksV1BoqStrings.importFileStep,
      YorksV1BoqStrings.importSheetStep,
      YorksV1BoqStrings.importMapStep,
      YorksV1BoqStrings.importReviewStep,
    ];
    final canContinue =
        !_busy &&
        switch (_step) {
          0 => _workbook != null,
          1 => preview != null && _title.trim().isNotEmpty,
          2 => preview?.isValid == true && _title.trim().isNotEmpty,
          _ =>
            !_commitConflict &&
                preview?.isValid == true &&
                _title.trim().isNotEmpty,
        };
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: AppColors.mobileSurface,
        appBar: AppBar(
          backgroundColor: AppColors.surfaceContainerLowest,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: _busy ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(
            steps[_step].primary,
            style: AppTypography.titleMedium.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              _MobileImportProgress(currentStep: _step, steps: steps),
              Expanded(
                child: SingleChildScrollView(
                  key: ValueKey('boq-mobile-import-step-$_step'),
                  padding: const EdgeInsets.all(
                    AppSpacing.mobileScreenHorizontal,
                  ),
                  child: switch (_step) {
                    0 => _buildFileStep(),
                    1 => _buildSheetStep(),
                    2 => _buildMapStep(),
                    _ => _buildReviewStep(),
                  },
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.mobileScreenHorizontal),
            decoration: const BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              border: Border(top: BorderSide(color: AppColors.line)),
            ),
            child: Row(
              children: [
                if (_step > 0) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _step -= 1),
                      child: Text(YorksV1BoqStrings.previous.primary),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  flex: _step > 0 ? 1 : 2,
                  child: FilledButton(
                    key: const ValueKey('boq-mobile-import-continue'),
                    onPressed: canContinue ? _continue : null,
                    child: Text(
                      _step == 3
                          ? YorksV1BoqStrings.importMaterials.primary
                                .replaceFirst(
                                  '{count}',
                                  '${preview?.rows.length ?? 0}',
                                )
                          : YorksV1BoqStrings.continueAction.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _MobileImportHeading(
        eyebrow: YorksV1BoqStrings.excelImport.primary,
        title: YorksV1BoqStrings.chooseWorkbookTitle.primary,
        description: YorksV1BoqStrings.chooseWorkbookDescription.primary,
      ),
      const SizedBox(height: AppSpacing.xl),
      YorksMobileCard(
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: AppColors.blueContainer,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
              child: const Icon(
                YorksDataTransferIcons.importData,
                color: AppColors.blue,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              _workbook?.fileName ??
                  YorksV1BoqStrings.uploadEquipmentSchedule.primary,
              textAlign: TextAlign.center,
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              YorksV1BoqStrings.xlsxConfiguredLimit.primary,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey('boq-mobile-import-choose-file'),
                onPressed: _busy ? null : _pickWorkbook,
                icon: const Icon(Icons.note_add_outlined),
                label: Text(YorksV1BoqStrings.chooseFile.primary),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      _MobileImportInfo(
        title: YorksV1BoqStrings.importDestination.primary,
        body: YorksV1BoqStrings.importDestinationDescription.primary
            .replaceFirst(
              '{scope}',
              widget.worksheet.group.scopeName ??
                  widget.worksheet.group.scopeCode ??
                  YorksV1BoqStrings.scope.primary,
            )
            .replaceFirst('{folder}', widget.worksheet.group.effectiveTitle),
      ),
      if (_selectionFailed) ...[
        const SizedBox(height: AppSpacing.md),
        _MobileImportInfo(
          title: YorksV1BoqStrings.importFailed.primary,
          body: YorksV1BoqStrings.workbookReadFailed.primary,
          error: true,
        ),
      ],
    ],
  );

  Widget _buildSheetStep() {
    final workbook = _workbook!;
    final sheet = _sheet!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MobileImportHeading(
          eyebrow: workbook.fileName,
          title: YorksV1BoqStrings.chooseSheetTitle.primary,
          description: YorksV1BoqStrings.chooseSheetDescription.primary,
        ),
        const SizedBox(height: AppSpacing.lg),
        _ImportSheetChoices(
          sheets: workbook.sheets,
          selected: sheet,
          onSelected: _selectSheet,
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<int>(
          key: ValueKey('boq-mobile-import-header-$_headerRowIndex'),
          initialValue: sheet.nonEmptyRowIndexes.contains(_headerRowIndex)
              ? _headerRowIndex
              : null,
          decoration: InputDecoration(
            labelText: YorksV1BoqStrings.headerRow.primary,
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final index in sheet.nonEmptyRowIndexes)
              DropdownMenuItem(value: index, child: Text('#${index + 1}')),
          ],
          onChanged: (index) {
            if (index != null) _selectHeader(index);
          },
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          key: ValueKey('boq-mobile-import-title-${sheet.name}'),
          initialValue: _title,
          onChanged: (value) => setState(() => _title = value),
          decoration: InputDecoration(
            labelText: YorksV1BoqStrings.detectedTitle.primary,
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildMapStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _MobileImportHeading(
        eyebrow: _workbook!.fileName,
        title: YorksV1BoqStrings.mapColumnsTitle.primary,
        description: YorksV1BoqStrings.mapColumnsDescription.primary,
      ),
      const SizedBox(height: AppSpacing.lg),
      for (var index = 0; index < _columns.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _ImportColumnEditor(
            key: ValueKey(
              'boq-mobile-import-column-${_columns[index].sourceIndex}',
            ),
            column: _columns[index],
            canManageCommercials: widget.canManageCommercials,
            onHeadingChanged: (value) => _updateColumn(
              index,
              (current) => current.copyWith(heading: value),
            ),
            onCanonicalChanged: (field) => _updateColumn(
              index,
              (current) => current.copyWith(
                canonicalField: field,
                clearCanonicalField: field == null,
              ),
            ),
          ),
        ),
      for (final issue
          in _preview?.validationIssues ??
              const <YorksV1BoqImportValidationIssue>[]) ...[
        _ImportIssueBanner(
          copy: _importIssueCopy(issue.code),
          language: widget.language,
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      _MobileImportInfo(
        title: YorksV1BoqStrings.otherColumnsStayAvailable.primary,
        body: YorksV1BoqStrings.otherColumnsStayAvailableDescription.primary,
      ),
    ],
  );

  Widget _buildReviewStep() {
    final preview = _preview!;
    final mapped = preview.columns
        .where((column) => column.canonicalField != null)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MobileImportHeading(
          eyebrow: YorksV1BoqStrings.readyToImport.primary,
          title: YorksV1BoqStrings.reviewWorkbook.primary,
          description: YorksV1BoqStrings.importDescription.primary,
        ),
        const SizedBox(height: AppSpacing.lg),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: 1.55,
          children: [
            _MobileImportMetric(
              label: YorksV1BoqStrings.rowsFound.primary,
              value: preview.rows.length,
            ),
            _MobileImportMetric(
              label: YorksV1BoqStrings.columns.primary,
              value: preview.columns.length,
            ),
            _MobileImportMetric(
              label: YorksV1BoqStrings.mapped.primary,
              value: mapped,
            ),
            _MobileImportMetric(
              label: YorksV1BoqStrings.fatalErrors.primary,
              value: preview.validationIssues.length,
              warning: preview.validationIssues.isNotEmpty,
            ),
          ],
        ),
        if (preview.validationIssues.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          for (final issue in preview.validationIssues)
            _ImportIssueBanner(
              copy: _importIssueCopy(issue.code),
              language: widget.language,
            ),
        ],
        const SizedBox(height: AppSpacing.md),
        YorksMobileCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                preview.title,
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${preview.rows.length} ${YorksV1BoqStrings.rows.primary} · '
                '${preview.headerRowNumbers.map((number) => '#$number').join(', ')}',
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
              const Divider(height: AppSpacing.xl),
              Text(
                YorksV1BoqStrings.columnMapping.primary,
                style: AppTypography.labelLarge.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                YorksV1BoqStrings.mappingReadyDescription.primary
                    .replaceFirst('{mapped}', '$mapped')
                    .replaceFirst('{total}', '${preview.columns.length}'),
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
        if (_commitConflict) ...[
          const SizedBox(height: AppSpacing.md),
          _MobileImportInfo(
            title: YorksV1BoqStrings.importConflictTitle.primary,
            body: YorksV1BoqStrings.importConflictBody.primary,
            error: true,
            actionLabel: YorksV1BoqStrings.refresh.primary,
            onAction: _refreshAfterConflict,
          ),
        ] else if (_commitFailed) ...[
          const SizedBox(height: AppSpacing.md),
          _MobileImportInfo(
            title: YorksV1BoqStrings.importFailed.primary,
            body: YorksV1BoqStrings.previewRetainedAfterFailure.primary,
            error: true,
          ),
        ],
      ],
    );
  }
}

class _MobileImportProgress extends StatelessWidget {
  const _MobileImportProgress({required this.currentStep, required this.steps});

  final int currentStep;
  final List<TranslatableString> steps;

  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.surfaceContainerLowest,
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.mobileScreenHorizontal,
      AppSpacing.md,
      AppSpacing.mobileScreenHorizontal,
      AppSpacing.sm,
    ),
    child: Row(
      children: [
        for (var index = 0; index < steps.length; index++) ...[
          Expanded(
            child: Column(
              children: [
                Container(
                  width: AppSpacing.huge,
                  height: AppSpacing.huge,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: index <= currentStep
                        ? AppColors.blue
                        : AppColors.surfaceContainerHigh,
                    shape: BoxShape.circle,
                  ),
                  child: index < currentStep
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 20,
                        )
                      : Text(
                          '${index + 1}',
                          style: AppTypography.labelLarge.copyWith(
                            color: index <= currentStep
                                ? Colors.white
                                : AppColors.muted,
                          ),
                        ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  steps[index].primary,
                  style: AppTypography.labelMedium.copyWith(
                    color: index <= currentStep
                        ? AppColors.blue
                        : AppColors.mutedLight,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

class _MobileImportHeading extends StatelessWidget {
  const _MobileImportHeading({
    required this.eyebrow,
    required this.title,
    required this.description,
  });

  final String eyebrow;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        eyebrow.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelLarge.copyWith(
          color: AppColors.blue,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        title,
        style: AppTypography.headlineLarge.copyWith(
          fontSize: 30,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        description,
        style: AppTypography.bodyMedium.copyWith(
          color: AppColors.muted,
          height: 1.45,
        ),
      ),
    ],
  );
}

class _MobileImportInfo extends StatelessWidget {
  const _MobileImportInfo({
    required this.title,
    required this.body,
    this.error = false,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String body;
  final bool error;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => YorksMobileCard(
    color: error ? AppColors.errorContainer : AppColors.blueContainer,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          error ? Icons.error_outline_rounded : Icons.info_outline_rounded,
          color: error ? AppColors.error : AppColors.blue,
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
              const SizedBox(height: AppSpacing.xs),
              Text(
                body,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.muted,
                  height: 1.45,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  height: AppSpacing.minTapTarget,
                  child: TextButton(
                    onPressed: onAction,
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

class _MobileImportMetric extends StatelessWidget {
  const _MobileImportMetric({
    required this.label,
    required this.value,
    this.warning = false,
  });

  final String label;
  final int value;
  final bool warning;

  @override
  Widget build(BuildContext context) => YorksMobileCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTypography.labelMedium.copyWith(color: AppColors.muted),
        ),
        const Spacer(),
        Text(
          '$value',
          style: AppTypography.headlineMedium.copyWith(
            color: warning ? AppColors.error : AppColors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _BoqWorkbookImportDialog extends StatefulWidget {
  const _BoqWorkbookImportDialog({
    required this.workbook,
    required this.codec,
    required this.fallbackTitle,
    required this.language,
    required this.canManageCommercials,
  });

  final YorksV1BoqParsedWorkbook workbook;
  final YorksV1BoqWorkbookCodec codec;
  final String fallbackTitle;
  final AppLanguage language;
  final bool canManageCommercials;

  @override
  State<_BoqWorkbookImportDialog> createState() =>
      _BoqWorkbookImportDialogState();
}

class _BoqWorkbookImportDialogState extends State<_BoqWorkbookImportDialog> {
  late YorksV1BoqWorkbookSheet _sheet;
  late int _headerRowIndex;
  late bool _hasSelectedHeader;
  late String _title;
  late List<int> _headerRowIndexes;
  late List<YorksV1BoqHeaderPath> _headerHierarchy;
  late List<YorksV1BoqImportColumn> _columns;
  late List<YorksV1BoqImportRow> _rows;

  @override
  void initState() {
    super.initState();
    _sheet = widget.workbook.sheets.first;
    _headerRowIndex = 0;
    _hasSelectedHeader = false;
    _resetPreview();
  }

  YorksV1BoqImportPreview get _preview => YorksV1BoqImportPreview(
    fileName: widget.workbook.fileName,
    worksheetName: _sheet.name,
    title: _title,
    headerRowIndex: _headerRowIndex,
    headerRowIndexes: _headerRowIndexes,
    headerHierarchy: _headerHierarchy,
    columns: _columns,
    rows: _rows,
    validationIssues: _importValidationIssues(
      widget.codec,
      _columns,
      canManageCommercials: widget.canManageCommercials,
    ),
  );

  void _resetPreview() {
    final detected = widget.codec.preview(
      workbook: widget.workbook,
      sheet: _sheet,
      fallbackTitle: widget.fallbackTitle,
      headerRowIndex: _hasSelectedHeader ? _headerRowIndex : null,
    );
    _headerRowIndex = detected.headerRowIndex;
    _headerRowIndexes = detected.headerRowIndexes;
    _headerHierarchy = detected.headerHierarchy;
    _title = detected.title;
    _columns = detected.columns;
    _rows = detected.rows;
  }

  void _selectSheet(YorksV1BoqWorkbookSheet sheet) {
    setState(() {
      _sheet = sheet;
      _headerRowIndex = 0;
      _hasSelectedHeader = false;
      _resetPreview();
    });
  }

  void _selectHeader(int index) {
    setState(() {
      _headerRowIndex = index;
      _hasSelectedHeader = true;
      _resetPreview();
    });
  }

  void _updateColumn(
    int index,
    YorksV1BoqImportColumn Function(YorksV1BoqImportColumn current) update,
  ) {
    setState(() {
      _columns = [
        for (var item = 0; item < _columns.length; item++)
          item == index ? update(_columns[item]) : _columns[item],
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final headerCandidates = _sheet.nonEmptyRowIndexes;
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CopyText(
                copy: YorksV1BoqStrings.importPreview,
                language: widget.language,
                style: AppTypography.titleLarge.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                widget.workbook.fileName,
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.sm),
              _CopyText(
                copy: YorksV1BoqStrings.importDescription,
                language: widget.language,
                style: AppTypography.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.workbook.sheets.length > 1) ...[
                        _ImportSheetChoices(
                          sheets: widget.workbook.sheets,
                          selected: _sheet,
                          onSelected: _selectSheet,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final narrow = constraints.maxWidth < 600;
                          final selectors = [
                            Expanded(
                              child:
                                  DropdownButtonFormField<
                                    YorksV1BoqWorkbookSheet
                                  >(
                                    key: ValueKey(
                                      'boq-import-sheet-${_sheet.name}',
                                    ),
                                    initialValue: _sheet,
                                    decoration: InputDecoration(
                                      labelText: YorksV1BoqStrings
                                          .worksheetSelection
                                          .primary,
                                      border: const OutlineInputBorder(),
                                    ),
                                    items: [
                                      for (final sheet
                                          in widget.workbook.sheets)
                                        DropdownMenuItem(
                                          value: sheet,
                                          child: Text(sheet.name),
                                        ),
                                    ],
                                    onChanged: (sheet) {
                                      if (sheet != null) _selectSheet(sheet);
                                    },
                                  ),
                            ),
                            const SizedBox(
                              width: AppSpacing.sm,
                              height: AppSpacing.sm,
                            ),
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                key: ValueKey(
                                  'boq-import-header-$_headerRowIndex',
                                ),
                                initialValue:
                                    headerCandidates.contains(_headerRowIndex)
                                    ? _headerRowIndex
                                    : null,
                                decoration: InputDecoration(
                                  labelText:
                                      YorksV1BoqStrings.headerRow.primary,
                                  border: const OutlineInputBorder(),
                                ),
                                items: [
                                  for (final index in headerCandidates)
                                    DropdownMenuItem(
                                      value: index,
                                      child: Text('#${index + 1}'),
                                    ),
                                ],
                                onChanged: (index) {
                                  if (index != null) _selectHeader(index);
                                },
                              ),
                            ),
                          ];
                          return narrow
                              ? Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: selectors,
                                )
                              : Row(children: selectors);
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        key: ValueKey(
                          'boq-import-title-${_sheet.name}-$_headerRowIndex',
                        ),
                        initialValue: _title,
                        onChanged: (value) => setState(() => _title = value),
                        decoration: InputDecoration(
                          labelText: YorksV1BoqStrings.detectedTitle.primary,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      if (preview.validationIssues.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        for (final issue in preview.validationIssues)
                          _ImportIssueBanner(
                            copy: _importIssueCopy(issue.code),
                            language: widget.language,
                          ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      _CopyText(
                        copy: YorksV1BoqStrings.columnMapping,
                        language: widget.language,
                        style: AppTypography.titleSmall.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      for (var index = 0; index < _columns.length; index++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _ImportColumnEditor(
                            key: ValueKey(
                              'boq-import-column-${_columns[index].sourceIndex}',
                            ),
                            column: _columns[index],
                            canManageCommercials: widget.canManageCommercials,
                            onHeadingChanged: (value) => _updateColumn(
                              index,
                              (current) => current.copyWith(heading: value),
                            ),
                            onCanonicalChanged: (field) => _updateColumn(
                              index,
                              (current) => current.copyWith(
                                canonicalField: field,
                                clearCanonicalField: field == null,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.md),
                      _CopyText(
                        copy: YorksV1BoqStrings.previewRows,
                        language: widget.language,
                        style: AppTypography.titleSmall.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _ImportSampleTable(preview: preview),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(YorksV1BoqStrings.cancel.primary),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('boq-confirm-import'),
                    onPressed: !preview.isValid || preview.title.trim().isEmpty
                        ? null
                        : () => Navigator.pop(context, preview),
                    icon: const Icon(YorksDataTransferIcons.importData),
                    label: Text(YorksV1BoqStrings.commitImport.primary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportSheetChoices extends StatelessWidget {
  const _ImportSheetChoices({
    required this.sheets,
    required this.selected,
    required this.onSelected,
  });

  final List<YorksV1BoqWorkbookSheet> sheets;
  final YorksV1BoqWorkbookSheet selected;
  final ValueChanged<YorksV1BoqWorkbookSheet> onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth >= 700
          ? 210.0
          : constraints.maxWidth >= 460
          ? 190.0
          : constraints.maxWidth;
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final sheet in sheets)
            SizedBox(
              width: width,
              child: OutlinedButton(
                key: ValueKey('boq-import-sheet-choice-${sheet.name}'),
                onPressed: () => onSelected(sheet),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  backgroundColor: identical(sheet, selected)
                      ? AppColors.blueContainer
                      : AppColors.surfaceContainerLowest,
                  side: BorderSide(
                    color: identical(sheet, selected)
                        ? AppColors.primary
                        : AppColors.line,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.table_chart_outlined, size: 18),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      sheet.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${sheet.nonEmptyRowIndexes.length} ${YorksV1BoqStrings.rows.primary}',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _ImportColumnEditor extends StatelessWidget {
  const _ImportColumnEditor({
    super.key,
    required this.column,
    required this.canManageCommercials,
    required this.onHeadingChanged,
    required this.onCanonicalChanged,
  });

  final YorksV1BoqImportColumn column;
  final bool canManageCommercials;
  final ValueChanged<String> onHeadingChanged;
  final ValueChanged<YorksV1BoqCanonicalField?> onCanonicalChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final lockedCommercial =
          column.canonicalField?.isCommercial == true && !canManageCommercials;
      final heading = TextFormField(
        initialValue: column.heading,
        enabled: !lockedCommercial,
        onChanged: lockedCommercial ? null : onHeadingChanged,
        decoration: InputDecoration(
          labelText: YorksV1BoqStrings.columnHeading.primary,
          border: const OutlineInputBorder(),
        ),
      );
      final mapping = DropdownButtonFormField<YorksV1BoqCanonicalField?>(
        initialValue: column.canonicalField,
        decoration: InputDecoration(
          labelText: YorksV1BoqStrings.columnMapping.primary,
          border: const OutlineInputBorder(),
        ),
        items: [
          DropdownMenuItem<YorksV1BoqCanonicalField?>(
            value: null,
            child: Text(YorksV1BoqStrings.noCanonicalMapping.primary),
          ),
          for (final field in YorksV1BoqCanonicalField.values)
            if (canManageCommercials || !field.isCommercial)
              DropdownMenuItem<YorksV1BoqCanonicalField?>(
                value: field,
                child: Text(_canonicalCopy(field).primary),
              ),
          if (lockedCommercial)
            DropdownMenuItem<YorksV1BoqCanonicalField?>(
              value: column.canonicalField,
              enabled: false,
              child: Text(_canonicalCopy(column.canonicalField!).primary),
            ),
        ],
        onChanged: lockedCommercial ? null : onCanonicalChanged,
      );
      return constraints.maxWidth < 600
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                const SizedBox(height: AppSpacing.sm),
                mapping,
              ],
            )
          : Row(
              children: [
                Expanded(flex: 3, child: heading),
                const SizedBox(width: AppSpacing.sm),
                Expanded(flex: 2, child: mapping),
              ],
            );
    },
  );
}

class _ImportSampleTable extends StatelessWidget {
  const _ImportSampleTable({required this.preview});

  final YorksV1BoqImportPreview preview;

  @override
  Widget build(BuildContext context) {
    final columns = preview.columns.take(6).toList(growable: false);
    final rows = preview.rows.take(4).toList(growable: false);
    if (columns.isEmpty) {
      return _EmptyWorksheet(copy: YorksV1BoqStrings.importNoColumns);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          for (final column in columns)
            DataColumn(label: Text(column.heading.trim())),
        ],
        rows: [
          for (final row in rows)
            DataRow(
              cells: [
                for (final column in columns)
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        row.valueFor(column.sourceIndex),
                        overflow: TextOverflow.ellipsis,
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

class _ImportIssueBanner extends StatelessWidget {
  const _ImportIssueBanner({required this.copy, required this.language});

  final TranslatableString copy;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: _InfoBanner(
      icon: Icons.error_outline,
      color: AppColors.error,
      title: YorksV1BoqStrings.importFailed,
      body: copy,
      language: language,
    ),
  );
}

List<YorksV1BoqImportValidationIssue> _importValidationIssues(
  YorksV1BoqWorkbookCodec codec,
  List<YorksV1BoqImportColumn> columns, {
  required bool canManageCommercials,
}) => [
  ...codec.validatePreviewColumns(columns),
  if (!canManageCommercials &&
      columns.any((column) => column.canonicalField?.isCommercial == true))
    const YorksV1BoqImportValidationIssue(
      code: YorksV1BoqImportValidationCode.commercialPermissionRequired,
    ),
];

Map<YorksV1BoqCanonicalField, String> _boqMaterialValues(
  YorksV1MaterialRequestInventorySuggestion suggestion,
) => {
  YorksV1BoqCanonicalField.description: suggestion.description,
  YorksV1BoqCanonicalField.unit: suggestion.unit,
  if (suggestion.brandOrigin?.trim().isNotEmpty == true)
    YorksV1BoqCanonicalField.brandOrigin: suggestion.brandOrigin!.trim(),
  if (suggestion.size?.trim().isNotEmpty == true)
    YorksV1BoqCanonicalField.size: suggestion.size!.trim(),
  if (suggestion.model?.trim().isNotEmpty == true) ...{
    YorksV1BoqCanonicalField.model: suggestion.model!.trim(),
    YorksV1BoqCanonicalField.planningModelTag: suggestion.model!.trim(),
  },
  if (suggestion.equipmentTag?.trim().isNotEmpty == true)
    YorksV1BoqCanonicalField.equipmentTag: suggestion.equipmentTag!.trim(),
};

String _boqMaterialSuggestionDetails(
  YorksV1MaterialRequestInventorySuggestion suggestion,
) => <String>[
  switch (suggestion.source) {
    YorksV1MaterialRequestSuggestionSource.selectedScopeBoq =>
      YorksV1MaterialRequestStrings.selectedScopeBoq.primary,
    YorksV1MaterialRequestSuggestionSource.projectBoq =>
      YorksV1MaterialRequestStrings.projectBoq.primary,
    YorksV1MaterialRequestSuggestionSource.inventory =>
      YorksV1MaterialRequestStrings.inventoryCatalogue.primary,
  },
  ?suggestion.sourceScopeName,
  ?suggestion.sourceGroupName,
  ?suggestion.itemCode,
  ?suggestion.size,
  ?suggestion.model,
  suggestion.unit,
].where((value) => value.trim().isNotEmpty).toSet().join(' · ');

IconData _boqMaterialSuggestionIcon(
  YorksV1MaterialRequestSuggestionSource source,
) => switch (source) {
  YorksV1MaterialRequestSuggestionSource.selectedScopeBoq =>
    Icons.folder_special_outlined,
  YorksV1MaterialRequestSuggestionSource.projectBoq => Icons.folder_outlined,
  YorksV1MaterialRequestSuggestionSource.inventory =>
    Icons.inventory_2_outlined,
};

TranslatableString _importIssueCopy(YorksV1BoqImportValidationCode code) =>
    switch (code) {
      YorksV1BoqImportValidationCode.noColumns =>
        YorksV1BoqStrings.importNoColumns,
      YorksV1BoqImportValidationCode.blankHeading =>
        YorksV1BoqStrings.importBlankHeading,
      YorksV1BoqImportValidationCode.duplicateHeading =>
        YorksV1BoqStrings.importDuplicateHeading,
      YorksV1BoqImportValidationCode.duplicateCanonicalMapping =>
        YorksV1BoqStrings.importDuplicateCanonical,
      YorksV1BoqImportValidationCode.commercialPermissionRequired =>
        YorksV1BoqStrings.commercialImportPermissionRequired,
    };

class YorksV1BoqSpreadsheet extends StatefulWidget {
  const YorksV1BoqSpreadsheet({
    super.key,
    required this.worksheet,
    required this.editable,
    required this.showEditActions,
    this.canViewCommercials = false,
    this.canManageCommercials = false,
    this.canUndo = false,
    this.canRedo = false,
    this.initialColumnWidths = const {},
    this.onColumnWidthChanged,
    this.onUndo,
    this.onRedo,
    this.mobileConflict = false,
    this.mobileLanguage,
    this.onMobileRefresh,
    this.onSearchMaterials,
    this.onApplyMaterialSuggestion,
    this.onMaterialSuggestionSelected,
    required this.onUpdateCell,
    this.onPasteCells,
    required this.onAddBlankRow,
    required this.onAddSimilarRow,
    required this.onRemoveRow,
    required this.onAddColumn,
    required this.onRenameColumn,
    required this.onRemoveColumn,
  });

  final YorksV1BoqWorksheet worksheet;
  final bool editable;
  final bool showEditActions;
  final bool canViewCommercials;
  final bool canManageCommercials;
  final bool canUndo;
  final bool canRedo;
  final Map<String, double> initialColumnWidths;
  final void Function(String columnId, double width)? onColumnWidthChanged;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final bool mobileConflict;
  final AppLanguage? mobileLanguage;
  final Future<void> Function()? onMobileRefresh;
  final Future<List<YorksV1MaterialRequestInventorySuggestion>> Function(
    String query,
    String? excludedRowId,
  )?
  onSearchMaterials;
  final void Function(
    String rowId,
    YorksV1MaterialRequestInventorySuggestion suggestion,
  )?
  onApplyMaterialSuggestion;
  final ValueChanged<YorksV1MaterialRequestInventorySuggestion>?
  onMaterialSuggestionSelected;
  final void Function({
    required String rowId,
    required String columnId,
    required String value,
  })
  onUpdateCell;
  final void Function({
    required String? startRowId,
    required List<String> columnIds,
    required List<List<String>> values,
  })?
  onPasteCells;
  final YorksV1BoqRow Function({String? afterRowId}) onAddBlankRow;
  final YorksV1BoqRow Function({required String sourceRowId}) onAddSimilarRow;
  final ValueChanged<String> onRemoveRow;
  final void Function({
    required String heading,
    YorksV1BoqCanonicalField? canonicalField,
  })
  onAddColumn;
  final void Function(String columnId, String heading) onRenameColumn;
  final ValueChanged<String> onRemoveColumn;

  @override
  State<YorksV1BoqSpreadsheet> createState() => _YorksV1BoqSpreadsheetState();
}

class _YorksV1BoqSpreadsheetState extends State<YorksV1BoqSpreadsheet> {
  static const _rowHeight = 50.0;
  static const _serialWidth = 64.0;
  static const _columnWidth = 184.0;
  static const _actionWidth = 56.0;
  final _serialScroll = ScrollController();
  final _bodyScroll = ScrollController();
  final _horizontalScroll = ScrollController();
  final Map<String, FocusNode> _focusNodes = {};
  final Map<String, double> _columnWidths = {};
  final TextEditingController _findController = TextEditingController();
  bool _syncingVertical = false;
  String? _selectedRowId;
  String? _selectedColumnId;
  String _findQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedRowId = widget.worksheet.rows.firstOrNull?.id;
    _columnWidths.addAll(widget.initialColumnWidths);
    _serialScroll.addListener(() => _sync(_serialScroll, _bodyScroll));
    _bodyScroll.addListener(() => _sync(_bodyScroll, _serialScroll));
  }

  @override
  void didUpdateWidget(covariant YorksV1BoqSpreadsheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.worksheet.rows.any((row) => row.id == _selectedRowId)) {
      _selectedRowId = widget.worksheet.rows.firstOrNull?.id;
    }
    for (final entry in widget.initialColumnWidths.entries) {
      _columnWidths.putIfAbsent(entry.key, () => entry.value);
    }
  }

  @override
  void dispose() {
    _serialScroll.dispose();
    _bodyScroll.dispose();
    _horizontalScroll.dispose();
    _findController.dispose();
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _sync(ScrollController source, ScrollController target) {
    if (_syncingVertical || !source.hasClients || !target.hasClients) return;
    _syncingVertical = true;
    target.jumpTo(
      source.offset.clamp(
        target.position.minScrollExtent,
        target.position.maxScrollExtent,
      ),
    );
    _syncingVertical = false;
  }

  bool _cellMatches(YorksV1BoqRow row, YorksV1BoqColumn column) {
    final query = _findQuery.toLowerCase();
    if (query.isEmpty) return false;
    return '${row.valueFor(column.id) ?? ''}'.toLowerCase().contains(query);
  }

  double _widthFor(YorksV1BoqColumn column) => _columnWidths.putIfAbsent(
    column.id,
    () => switch (column.canonicalField) {
      YorksV1BoqCanonicalField.description => 300,
      YorksV1BoqCanonicalField.size ||
      YorksV1BoqCanonicalField.model ||
      YorksV1BoqCanonicalField.planningModelTag ||
      YorksV1BoqCanonicalField.equipmentTag ||
      YorksV1BoqCanonicalField.brandOrigin => 210,
      YorksV1BoqCanonicalField.quantity || YorksV1BoqCanonicalField.unit => 120,
      YorksV1BoqCanonicalField.unitCost ||
      YorksV1BoqCanonicalField.totalCost => 150,
      _ => _columnWidth,
    },
  );

  bool _rowMatches(YorksV1BoqRow row, List<YorksV1BoqColumn> columns) =>
      _findQuery.isNotEmpty &&
      columns.any((column) => _cellMatches(row, column));

  Set<String> _duplicateRowIds(List<YorksV1BoqColumn> columns) {
    final rowsBySignature = <String, List<String>>{};
    for (final row in widget.worksheet.rows) {
      String canonical(YorksV1BoqCanonicalField field) {
        final column = columns
            .where((item) => item.canonicalField == field)
            .firstOrNull;
        return column == null
            ? ''
            : '${row.valueFor(column.id) ?? ''}'.trim().toLowerCase();
      }

      final description = canonical(YorksV1BoqCanonicalField.description);
      final tag = canonical(YorksV1BoqCanonicalField.equipmentTag);
      if (description.isEmpty && tag.isEmpty) continue;
      final signature = [
        description,
        canonical(YorksV1BoqCanonicalField.size),
        canonical(YorksV1BoqCanonicalField.model),
        tag,
        canonical(YorksV1BoqCanonicalField.unit),
      ].join('|');
      rowsBySignature.putIfAbsent(signature, () => []).add(row.id);
    }
    return {
      for (final ids in rowsBySignature.values)
        if (ids.length > 1) ...ids,
    };
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        if (widget.editable && widget.canUndo && widget.onUndo != null)
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
              widget.onUndo!,
        if (widget.editable && widget.canUndo && widget.onUndo != null)
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
              widget.onUndo!,
        if (widget.editable && widget.canRedo && widget.onRedo != null)
          const SingleActivator(
            LogicalKeyboardKey.keyZ,
            control: true,
            shift: true,
          ): widget.onRedo!,
        if (widget.editable && widget.onPasteCells != null)
          const SingleActivator(LogicalKeyboardKey.keyV, control: true):
              _pasteFromClipboard,
        if (widget.editable && widget.onPasteCells != null)
          const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
              _pasteFromClipboard,
        if (widget.editable && widget.canRedo && widget.onRedo != null)
          const SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: true,
            shift: true,
          ): widget.onRedo!,
      },
      child: LayoutBuilder(
        builder: (context, constraints) =>
            constraints.maxWidth <= AppSpacing.compactBreakpoint
            ? _buildMobile(context)
            : _buildDesktop(context),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final hasSelection = _selectedRowId != null;
    final addFirstRow = widget.worksheet.rows.isEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final controls = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showEditActions) ...[
                IconButton(
                  tooltip: YorksV1BoqStrings.undo.primary,
                  onPressed: widget.editable && widget.canUndo
                      ? widget.onUndo
                      : null,
                  icon: const Icon(Icons.undo_rounded),
                ),
                IconButton(
                  tooltip: YorksV1BoqStrings.redo.primary,
                  onPressed: widget.editable && widget.canRedo
                      ? widget.onRedo
                      : null,
                  icon: const Icon(Icons.redo_rounded),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(width: 1, height: 30, color: AppColors.line),
                const SizedBox(width: AppSpacing.md),
                OutlinedButton.icon(
                  key: const ValueKey('boq-add-column'),
                  onPressed: widget.editable ? _addColumn : null,
                  icon: const Icon(Icons.view_column_outlined, size: 18),
                  label: Text(YorksV1BoqStrings.addColumn.primary),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (addFirstRow)
                  FilledButton.icon(
                    key: const ValueKey('boq-add-blank-row'),
                    onPressed:
                        !widget.editable || widget.worksheet.columns.isEmpty
                        ? null
                        : () {
                            final row = widget.onAddBlankRow(
                              afterRowId: _selectedRowId,
                            );
                            setState(() => _selectedRowId = row.id);
                          },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(YorksV1BoqStrings.addFirstRow.primary),
                  )
                else
                  OutlinedButton.icon(
                    key: const ValueKey('boq-add-blank-row'),
                    onPressed:
                        !widget.editable || widget.worksheet.columns.isEmpty
                        ? null
                        : () {
                            final row = widget.onAddBlankRow(
                              afterRowId: _selectedRowId,
                            );
                            setState(() => _selectedRowId = row.id);
                          },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(YorksV1BoqStrings.blankRow.primary),
                  ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton.icon(
                  key: const ValueKey('boq-add-similar-row'),
                  onPressed: !widget.editable || !hasSelection
                      ? null
                      : () {
                          final row = widget.onAddSimilarRow(
                            sourceRowId: _selectedRowId!,
                          );
                          setState(() => _selectedRowId = row.id);
                        },
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: Text(YorksV1BoqStrings.similarRow.primary),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  tooltip: YorksV1BoqStrings.pasteCells.primary,
                  onPressed: widget.editable && widget.onPasteCells != null
                      ? _pasteFromClipboard
                      : null,
                  icon: const Icon(Icons.content_paste_outlined, size: 19),
                ),
              ],
            ],
          );
          final search = TextField(
            key: const ValueKey('boq-find-worksheet'),
            controller: _findController,
            onChanged: (value) => setState(() => _findQuery = value.trim()),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: _findQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: YorksV1BoqStrings.clearFind.primary,
                      onPressed: () {
                        _findController.clear();
                        setState(() => _findQuery = '');
                      },
                      icon: const Icon(Icons.close_rounded, size: 17),
                    ),
              hintText: YorksV1BoqStrings.findInWorksheet.primary,
              border: const OutlineInputBorder(),
            ),
          );
          final count = _CountPill(
            label:
                '${widget.worksheet.rows.length} ${YorksV1BoqStrings.rows.primary} · '
                '${widget.worksheet.columns.length} ${YorksV1BoqStrings.columns.primary}',
          );
          final actionRow = Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: controls,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              count,
            ],
          );
          if (constraints.maxWidth < 960) {
            return Column(
              children: [
                actionRow,
                const SizedBox(height: AppSpacing.sm),
                search,
              ],
            );
          }
          return Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      controls,
                      const SizedBox(width: AppSpacing.md),
                      SizedBox(width: 280, child: search),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              count,
            ],
          );
        },
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final rows = widget.worksheet.rows;
    final columns = widget.worksheet.columns
        .where((column) => !column.isCommercial || widget.canViewCommercials)
        .toList(growable: false);
    final duplicateRowIds = _duplicateRowIds(columns);
    return Container(
      key: const ValueKey('yorks-v1-boq-desktop-grid'),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildToolbar(context),
          if (columns.isEmpty)
            Expanded(child: _EmptyWorksheet(copy: YorksV1BoqStrings.noColumns))
          else
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: _serialWidth,
                    child: Column(
                      children: [
                        _HeaderCell(
                          label: YorksV1BoqStrings.serialNumber.primary,
                        ),
                        Expanded(
                          child: ListView.builder(
                            key: const ValueKey('boq-serial-list'),
                            controller: _serialScroll,
                            itemExtent: _rowHeight,
                            itemCount: rows.length,
                            itemBuilder: (context, index) => _SerialCell(
                              number: index + 1,
                              selected: rows[index].id == _selectedRowId,
                              onTap: () => setState(
                                () => _selectedRowId = rows[index].id,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1, color: AppColors.line),
                  Expanded(
                    child: Scrollbar(
                      controller: _horizontalScroll,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _horizontalScroll,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width:
                              columns.fold<double>(
                                0,
                                (total, column) => total + _widthFor(column),
                              ) +
                              (widget.showEditActions ? _actionWidth : 0),
                          child: Column(
                            children: [
                              SizedBox(
                                height: _rowHeight,
                                child: Row(
                                  children: [
                                    for (final column in columns)
                                      _ColumnHeader(
                                        key: ValueKey(
                                          'boq-column-header-${column.id}',
                                        ),
                                        column: column,
                                        width: _widthFor(column),
                                        editable:
                                            widget.editable &&
                                            (!column.isCommercial ||
                                                widget.canManageCommercials),
                                        showEditAction: widget.showEditActions,
                                        onRename: widget.onRenameColumn,
                                        onDelete: () => _deleteColumn(column),
                                        onWidthChanged: (width) {
                                          final next = width.clamp(96.0, 520.0);
                                          setState(
                                            () =>
                                                _columnWidths[column.id] = next,
                                          );
                                          widget.onColumnWidthChanged?.call(
                                            column.id,
                                            next,
                                          );
                                        },
                                      ),
                                    if (widget.showEditActions)
                                      const _GridActionHeader(),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: rows.isEmpty
                                    ? _EmptyWorksheet(
                                        copy: YorksV1BoqStrings.noRows,
                                      )
                                    : ListView.builder(
                                        key: const ValueKey('boq-body-list'),
                                        controller: _bodyScroll,
                                        itemExtent: _rowHeight,
                                        itemCount: rows.length,
                                        itemBuilder: (context, rowIndex) {
                                          final row = rows[rowIndex];
                                          return Row(
                                            key: ValueKey(
                                              'boq-grid-row-${row.id}',
                                            ),
                                            children: [
                                              for (
                                                var colIndex = 0;
                                                colIndex < columns.length;
                                                colIndex++
                                              )
                                                _GridCell(
                                                  key: ValueKey(
                                                    'boq-grid-cell-${row.id}-${columns[colIndex].id}',
                                                  ),
                                                  width: _widthFor(
                                                    columns[colIndex],
                                                  ),
                                                  row: row,
                                                  column: columns[colIndex],
                                                  editable:
                                                      widget.editable &&
                                                      (!columns[colIndex]
                                                              .isCommercial ||
                                                          widget
                                                              .canManageCommercials),
                                                  highlighted: _cellMatches(
                                                    row,
                                                    columns[colIndex],
                                                  ),
                                                  possibleDuplicate:
                                                      duplicateRowIds.contains(
                                                        row.id,
                                                      ),
                                                  focusNode: _focusNode(
                                                    row.id,
                                                    columns[colIndex].id,
                                                  ),
                                                  onSelected: () => setState(
                                                    () {
                                                      _selectedRowId = row.id;
                                                      _selectedColumnId =
                                                          columns[colIndex].id;
                                                    },
                                                  ),
                                                  onSearchMaterials:
                                                      columns[colIndex]
                                                              .canonicalField ==
                                                          YorksV1BoqCanonicalField
                                                              .description
                                                      ? widget.onSearchMaterials
                                                      : null,
                                                  onMaterialSelected:
                                                      columns[colIndex]
                                                                  .canonicalField ==
                                                              YorksV1BoqCanonicalField
                                                                  .description &&
                                                          widget.onApplyMaterialSuggestion !=
                                                              null
                                                      ? (suggestion) {
                                                          widget
                                                              .onMaterialSuggestionSelected
                                                              ?.call(
                                                                suggestion,
                                                              );
                                                          widget
                                                              .onApplyMaterialSuggestion!(
                                                            row.id,
                                                            suggestion,
                                                          );
                                                        }
                                                      : null,
                                                  onValueChanged: (value) =>
                                                      widget.onUpdateCell(
                                                        rowId: row.id,
                                                        columnId:
                                                            columns[colIndex]
                                                                .id,
                                                        value: value,
                                                      ),
                                                ),
                                              if (widget.showEditActions)
                                                _GridRowDeleteAction(
                                                  onPressed: widget.editable
                                                      ? () => _deleteRow(row)
                                                      : null,
                                                ),
                                            ],
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (columns.isNotEmpty && widget.showEditActions)
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              alignment: Alignment.centerLeft,
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: OutlinedButton.icon(
                key: const ValueKey('boq-add-row-footer'),
                onPressed: widget.editable
                    ? () {
                        final row = widget.onAddBlankRow(
                          afterRowId: _selectedRowId,
                        );
                        setState(() => _selectedRowId = row.id);
                      }
                    : null,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(YorksV1BoqStrings.addRow.primary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMobileToolbar(BuildContext context) => Container(
    height: 58,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      children: [
        if (widget.showEditActions) ...[
          IconButton(
            tooltip: YorksV1BoqStrings.undo.primary,
            onPressed: widget.editable && widget.canUndo ? widget.onUndo : null,
            icon: const Icon(Icons.undo_rounded),
          ),
          IconButton(
            tooltip: YorksV1BoqStrings.redo.primary,
            onPressed: widget.editable && widget.canRedo ? widget.onRedo : null,
            icon: const Icon(Icons.redo_rounded),
          ),
          IconButton(
            key: const ValueKey('boq-add-column'),
            tooltip: YorksV1BoqStrings.addColumn.primary,
            onPressed: widget.editable ? _addColumn : null,
            icon: const Icon(Icons.view_column_outlined),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
        Expanded(
          child: TextField(
            key: const ValueKey('boq-find-worksheet'),
            controller: _findController,
            onChanged: (value) => setState(() => _findQuery = value.trim()),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: _findQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: YorksV1BoqStrings.clearFind.primary,
                      onPressed: () {
                        _findController.clear();
                        setState(() => _findQuery = '');
                      },
                      icon: const Icon(Icons.close_rounded, size: 17),
                    ),
              hintText: YorksV1BoqStrings.findInWorksheet.primary,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildMobile(BuildContext context) {
    final rows = widget.worksheet.rows;
    final columns = widget.worksheet.columns
        .where((column) => !column.isCommercial || widget.canViewCommercials)
        .toList(growable: false);
    final duplicateRowIds = _duplicateRowIds(columns);
    return Container(
      key: const ValueKey('yorks-v1-boq-mobile-list'),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildMobileToolbar(context),
          Expanded(
            child: columns.isEmpty
                ? _EmptyWorksheet(copy: YorksV1BoqStrings.noColumns)
                : rows.isEmpty
                ? _EmptyWorksheet(copy: YorksV1BoqStrings.noRows)
                : ListView.separated(
                    itemCount: rows.length,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.sm,
                      AppSpacing.sm,
                      AppSpacing.sm,
                      AppSpacing.xxl,
                    ),
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) => _MobileRowCard(
                      key: ValueKey('mobile-boq-row-${rows[index].id}'),
                      row: rows[index],
                      number: index + 1,
                      columns: columns,
                      editable: widget.showEditActions,
                      highlighted: _rowMatches(rows[index], columns),
                      possibleDuplicate: duplicateRowIds.contains(
                        rows[index].id,
                      ),
                      onTap: () {
                        setState(() => _selectedRowId = rows[index].id);
                        _openMobileEditor(index);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  FocusNode _focusNode(String rowId, String columnId) {
    final key = '$rowId:$columnId';
    return _focusNodes.putIfAbsent(key, () {
      final node = FocusNode(debugLabel: key);
      node.onKeyEvent = (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.tab) {
          return _moveHorizontal(
                rowId,
                columnId,
                HardwareKeyboard.instance.isShiftPressed ? -1 : 1,
              )
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        final delta = switch (event.logicalKey) {
          LogicalKeyboardKey.enter =>
            HardwareKeyboard.instance.isShiftPressed ? -1 : 1,
          LogicalKeyboardKey.arrowDown => 1,
          LogicalKeyboardKey.arrowUp => -1,
          _ => 0,
        };
        if (delta == 0) return KeyEventResult.ignored;
        _moveVertical(rowId, columnId, delta);
        return KeyEventResult.handled;
      };
      node.addListener(() {
        if (node.hasFocus && mounted) {
          setState(() {
            _selectedRowId = rowId;
            _selectedColumnId = columnId;
          });
        }
      });
      return node;
    });
  }

  void _moveVertical(String rowId, String columnId, int delta) {
    final rows = widget.worksheet.rows;
    final current = rows.indexWhere((row) => row.id == rowId);
    if (current < 0) return;
    final target = (current + delta).clamp(0, rows.length - 1);
    if (target == current || !_bodyScroll.hasClients) return;
    _scrollRowIntoView(target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode(rows[target].id, columnId).requestFocus();
    });
  }

  bool _moveHorizontal(String rowId, String columnId, int delta) {
    final columns = widget.worksheet.columns
        .where(
          (column) =>
              (!column.isCommercial || widget.canViewCommercials) &&
              widget.editable &&
              (!column.isCommercial || widget.canManageCommercials),
        )
        .toList(growable: false);
    final rows = widget.worksheet.rows;
    final rowIndex = rows.indexWhere((row) => row.id == rowId);
    final columnIndex = columns.indexWhere((column) => column.id == columnId);
    if (rowIndex < 0 || columnIndex < 0 || columns.isEmpty) return false;
    final nextIndex = rowIndex * columns.length + columnIndex + delta;
    if (nextIndex < 0 || nextIndex >= rows.length * columns.length) {
      return false;
    }
    final nextRow = nextIndex ~/ columns.length;
    final nextColumnIndex = nextIndex % columns.length;
    final nextColumn = columns[nextColumnIndex];
    _scrollRowIntoView(nextRow);
    final columnOffset = columns
        .take(nextColumnIndex)
        .fold<double>(0, (sum, column) => sum + _widthFor(column));
    if (_horizontalScroll.hasClients) {
      final viewport = _horizontalScroll.position.viewportDimension;
      final start = _horizontalScroll.offset;
      final end = columnOffset + _widthFor(nextColumn);
      if (columnOffset < start || end > start + viewport) {
        _horizontalScroll.jumpTo(
          (columnOffset < start ? columnOffset : end - viewport).clamp(
            _horizontalScroll.position.minScrollExtent,
            _horizontalScroll.position.maxScrollExtent,
          ),
        );
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode(rows[nextRow].id, nextColumn.id).requestFocus();
    });
    return true;
  }

  void _scrollRowIntoView(int index) {
    if (!_bodyScroll.hasClients) return;
    final start = _bodyScroll.offset;
    final end = start + _bodyScroll.position.viewportDimension;
    final rowStart = index * _rowHeight;
    final rowEnd = rowStart + _rowHeight;
    if (rowStart < start || rowEnd > end) {
      _bodyScroll.jumpTo(
        (rowStart < start
                ? rowStart
                : rowEnd - _bodyScroll.position.viewportDimension)
            .clamp(
              _bodyScroll.position.minScrollExtent,
              _bodyScroll.position.maxScrollExtent,
            ),
      );
    }
  }

  Future<void> _pasteFromClipboard() async {
    final paste = widget.onPasteCells;
    if (!widget.editable || paste == null) return;
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (!mounted || text == null || text.isEmpty) return;
    final columns = widget.worksheet.columns
        .where(
          (column) =>
              (!column.isCommercial || widget.canViewCommercials) &&
              (!column.isCommercial || widget.canManageCommercials),
        )
        .toList(growable: false);
    if (columns.isEmpty) return;
    final selectedIndex = columns.indexWhere(
      (column) => column.id == _selectedColumnId,
    );
    final startColumn = selectedIndex < 0 ? 0 : selectedIndex;
    final lines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    if (lines.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    paste(
      startRowId: _selectedRowId,
      columnIds: [for (final column in columns.skip(startColumn)) column.id],
      values: [for (final line in lines) line.split('\t')],
    );
  }

  Future<void> _addColumn() async {
    final result = await _showAddColumnDialog(
      context,
      columns: widget.worksheet.columns,
      canManageCommercials: widget.canManageCommercials,
    );
    if (result == null) return;
    widget.onAddColumn(heading: result.heading, canonicalField: result.mapping);
  }

  Future<void> _deleteColumn(YorksV1BoqColumn column) async {
    final hasValues = widget.worksheet.rows.any(
      (row) =>
          row.valueFor(column.id) != null &&
          '${row.valueFor(column.id)}'.isNotEmpty,
    );
    if (hasValues) {
      final confirmed = await _confirm(
        context: context,
        title: YorksV1BoqStrings.deleteColumn,
        body: YorksV1BoqStrings.deleteColumnConfirmation,
      );
      if (confirmed != true) return;
    }
    widget.onRemoveColumn(column.id);
  }

  Future<void> _deleteRow(YorksV1BoqRow row) async {
    final populated = row.values.values.any(
      (value) => value != null && '$value'.trim().isNotEmpty,
    );
    if (populated) {
      final confirmed = await _confirm(
        context: context,
        title: YorksV1BoqStrings.deleteRow,
        body: YorksV1BoqStrings.deleteRowConfirmation,
      );
      if (confirmed != true) return;
    }
    widget.onRemoveRow(row.id);
  }

  Future<void> _openMobileEditor(int rowIndex) async {
    final columns = widget.worksheet.columns
        .where((column) => !column.isCommercial || widget.canViewCommercials)
        .toList(growable: false);
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => _MobileBoqRowEditor(
          initialIndex: rowIndex,
          rows: widget.worksheet.rows,
          columns: columns,
          editable: widget.editable && !widget.mobileConflict,
          showEditActions: widget.showEditActions,
          canManageCommercials: widget.canManageCommercials,
          conflict: widget.mobileConflict,
          language: widget.mobileLanguage,
          onRefresh: widget.onMobileRefresh,
          onSearchMaterials: widget.onSearchMaterials,
          onMaterialSuggestionSelected: widget.onMaterialSuggestionSelected,
          onUpdateCell: widget.onUpdateCell,
          onAddSimilarRow: widget.onAddSimilarRow,
          onRemoveRow: widget.onRemoveRow,
        ),
      ),
    );
  }
}

/// Holds a BOQ heading locally until the engineer commits it.  This prevents
/// a complete worksheet state replacement for every typed character.
class _ColumnHeader extends StatefulWidget {
  const _ColumnHeader({
    super.key,
    required this.column,
    required this.width,
    required this.editable,
    required this.showEditAction,
    required this.onRename,
    required this.onDelete,
    required this.onWidthChanged,
  });

  final YorksV1BoqColumn column;
  final double width;
  final bool editable;
  final bool showEditAction;
  final void Function(String, String) onRename;
  final VoidCallback onDelete;
  final ValueChanged<double> onWidthChanged;

  @override
  State<_ColumnHeader> createState() => _ColumnHeaderState();
}

class _ColumnHeaderState extends State<_ColumnHeader> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  late String _lastCommitted;

  @override
  void initState() {
    super.initState();
    _lastCommitted = widget.column.heading;
    _textController = TextEditingController(text: widget.column.heading);
    _focusNode = FocusNode();
    _focusNode.addListener(_commitOnBlur);
  }

  @override
  void didUpdateWidget(covariant _ColumnHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.column.heading != _textController.text) {
      _lastCommitted = widget.column.heading;
      _textController.value = TextEditingValue(
        text: widget.column.heading,
        selection: TextSelection.collapsed(
          offset: widget.column.heading.length,
        ),
      );
    }
  }

  void _commitOnBlur() {
    if (!_focusNode.hasFocus) _commit();
  }

  void _commit() {
    final value = _textController.text.trim();
    if (value.isEmpty || value == _lastCommitted) return;
    _lastCommitted = value;
    widget.onRename(widget.column.id, value);
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
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xs,
                AppSpacing.xs,
                AppSpacing.xs,
                0,
              ),
              decoration: const BoxDecoration(
                color: AppColors.surfaceContainerLow,
                border: Border(right: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('boq-column-${widget.column.id}'),
                      controller: _textController,
                      focusNode: _focusNode,
                      enabled: widget.editable,
                      onFieldSubmitted: (_) => _commit(),
                      style: AppTypography.labelLarge,
                      decoration: const InputDecoration(
                        isDense: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.blue),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                        ),
                      ),
                    ),
                  ),
                  if (widget.showEditAction)
                    IconButton(
                      tooltip: YorksV1BoqStrings.deleteColumn.primary,
                      constraints: const BoxConstraints(
                        minHeight: AppSpacing.minTapTarget,
                        minWidth: AppSpacing.minTapTarget,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: widget.editable ? widget.onDelete : null,
                      icon: const Icon(Icons.close_rounded, size: 17),
                    ),
                ],
              ),
            ),
          ),
          PositionedDirectional(
            end: 0,
            top: 0,
            bottom: 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) =>
                    widget.onWidthChanged(widget.width + details.delta.dx),
                child: const SizedBox(width: 9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    height: _YorksV1BoqSpreadsheetState._rowHeight,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: AppColors.surfaceContainerLow,
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Text(label, style: AppTypography.labelLarge),
  );
}

class _GridActionHeader extends StatelessWidget {
  const _GridActionHeader();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: _YorksV1BoqSpreadsheetState._actionWidth,
    height: _YorksV1BoqSpreadsheetState._rowHeight,
    child: Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLow,
        border: Border(
          left: BorderSide(color: AppColors.line),
          bottom: BorderSide(color: AppColors.line),
        ),
      ),
      child: const Icon(Icons.more_horiz_rounded, size: 18),
    ),
  );
}

class _GridRowDeleteAction extends StatelessWidget {
  const _GridRowDeleteAction({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: _YorksV1BoqSpreadsheetState._actionWidth,
    height: _YorksV1BoqSpreadsheetState._rowHeight,
    child: Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: AppColors.line),
          bottom: BorderSide(color: AppColors.line),
        ),
      ),
      child: IconButton(
        tooltip: YorksV1BoqStrings.deleteRow.primary,
        constraints: const BoxConstraints(
          minWidth: AppSpacing.minTapTarget,
          minHeight: AppSpacing.minTapTarget,
        ),
        onPressed: onPressed,
        icon: const Icon(Icons.delete_outline_rounded, size: 18),
      ),
    ),
  );
}

class _SerialCell extends StatelessWidget {
  const _SerialCell({
    required this.number,
    required this.selected,
    required this.onTap,
  });

  final int number;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? AppColors.blueContainer
            : AppColors.surfaceContainerLowest,
        border: const Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Text('$number', style: AppTypography.labelLarge),
    ),
  );
}

/// The text controller belongs to the active cell, not the complete BOQ
/// worksheet.  A commit happens on blur or Enter, which keeps browser typing
/// smooth even for imported sheets with hundreds of rows.
class _GridCell extends StatefulWidget {
  const _GridCell({
    super.key,
    required this.width,
    required this.row,
    required this.column,
    required this.editable,
    this.highlighted = false,
    this.possibleDuplicate = false,
    required this.focusNode,
    required this.onSelected,
    required this.onValueChanged,
    this.onSearchMaterials,
    this.onMaterialSelected,
  });

  final double width;
  final YorksV1BoqRow row;
  final YorksV1BoqColumn column;
  final bool editable;
  final bool highlighted;
  final bool possibleDuplicate;
  final FocusNode focusNode;
  final VoidCallback onSelected;
  final ValueChanged<String> onValueChanged;
  final Future<List<YorksV1MaterialRequestInventorySuggestion>> Function(
    String query,
    String? excludedRowId,
  )?
  onSearchMaterials;
  final ValueChanged<YorksV1MaterialRequestInventorySuggestion>?
  onMaterialSelected;

  @override
  State<_GridCell> createState() => _GridCellState();
}

class _GridCellState extends State<_GridCell> {
  late final TextEditingController _textController;
  late String _lastCommitted;
  int _searchEpoch = 0;

  @override
  void initState() {
    super.initState();
    _lastCommitted = _valueFor(widget);
    _textController = TextEditingController(text: _lastCommitted);
    widget.focusNode.addListener(_commitOnBlur);
  }

  @override
  void didUpdateWidget(covariant _GridCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_commitOnBlur);
      widget.focusNode.addListener(_commitOnBlur);
    }
    final value = _valueFor(widget);
    if (!widget.focusNode.hasFocus && value != _textController.text) {
      _lastCommitted = value;
      _textController.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
  }

  String _valueFor(_GridCell cell) =>
      '${cell.row.valueFor(cell.column.id) ?? ''}';

  void _commitOnBlur() {
    if (!widget.focusNode.hasFocus) _commit();
  }

  void _commit() {
    final value = _textController.text;
    if (value == _lastCommitted) return;
    _lastCommitted = value;
    widget.onValueChanged(value);
  }

  Future<Iterable<YorksV1MaterialRequestInventorySuggestion>> _options(
    TextEditingValue value,
  ) async {
    final epoch = ++_searchEpoch;
    final query = value.text.trim();
    final search = widget.onSearchMaterials;
    if (!widget.editable || search == null || query.length < 2) {
      return const <YorksV1MaterialRequestInventorySuggestion>[];
    }
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted || epoch != _searchEpoch) {
      return const <YorksV1MaterialRequestInventorySuggestion>[];
    }
    try {
      final results = await search(query, widget.row.id);
      if (!mounted || epoch != _searchEpoch) {
        return const <YorksV1MaterialRequestInventorySuggestion>[];
      }
      return results;
    } catch (_) {
      return const <YorksV1MaterialRequestInventorySuggestion>[];
    }
  }

  void _selectMaterial(YorksV1MaterialRequestInventorySuggestion suggestion) {
    _lastCommitted = suggestion.description;
    widget.onMaterialSelected?.call(suggestion);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_commitOnBlur);
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: widget.highlighted
            ? AppColors.blueContainer
            : widget.possibleDuplicate
            ? AppColors.warningContainer
            : null,
        border: Border(
          right: const BorderSide(color: AppColors.line),
          bottom: const BorderSide(color: AppColors.line),
        ),
      ),
      child:
          widget.onSearchMaterials == null || widget.onMaterialSelected == null
          ? _textField()
          : RawAutocomplete<YorksV1MaterialRequestInventorySuggestion>(
              textEditingController: _textController,
              focusNode: widget.focusNode,
              displayStringForOption: (option) => option.description,
              optionsBuilder: _options,
              onSelected: _selectMaterial,
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) =>
                      _textField(onAutocompleteSubmitted: onFieldSubmitted),
              optionsViewBuilder: (context, select, options) {
                final values = options.toList(growable: false);
                return Align(
                  alignment: AlignmentDirectional.topStart,
                  child: Material(
                    elevation: 8,
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 440,
                        maxHeight: 280,
                      ),
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: values.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final suggestion = values[index];
                          return ListTile(
                            dense: true,
                            minTileHeight: AppSpacing.minTapTarget,
                            leading: Icon(
                              _boqMaterialSuggestionIcon(suggestion.source),
                              size: 19,
                              color: AppColors.blue,
                            ),
                            title: Text(
                              suggestion.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              _boqMaterialSuggestionDetails(suggestion),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => select(suggestion),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
    ),
  );

  Widget _textField({VoidCallback? onAutocompleteSubmitted}) => TextFormField(
    key: ValueKey('boq-cell-${widget.row.id}-${widget.column.id}'),
    controller: _textController,
    focusNode: widget.focusNode,
    enabled: widget.editable,
    onTap: widget.onSelected,
    onFieldSubmitted: (_) {
      _commit();
      onAutocompleteSubmitted?.call();
    },
    style: AppTypography.bodySmall,
    decoration: InputDecoration(
      isDense: true,
      border: InputBorder.none,
      suffixIcon: widget.onSearchMaterials == null
          ? null
          : const Icon(Icons.search_rounded, size: 16, color: AppColors.muted),
      suffixIconConstraints: const BoxConstraints(minWidth: 26),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 8,
      ),
    ),
  );
}

class _MobileRowCard extends StatelessWidget {
  const _MobileRowCard({
    super.key,
    required this.row,
    required this.number,
    required this.columns,
    required this.editable,
    this.highlighted = false,
    this.possibleDuplicate = false,
    required this.onTap,
  });

  final YorksV1BoqRow row;
  final int number;
  final List<YorksV1BoqColumn> columns;
  final bool editable;
  final bool highlighted;
  final bool possibleDuplicate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    String valueFor(YorksV1BoqCanonicalField field) {
      for (final column in columns) {
        if (column.canonicalField != field) continue;
        final value = '${row.valueFor(column.id) ?? ''}'.trim();
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    final populatedValues = <String>[
      for (final column in columns)
        if ('${row.valueFor(column.id) ?? ''}'.trim().isNotEmpty)
          '${row.valueFor(column.id)}'.trim(),
    ];
    final description = valueFor(YorksV1BoqCanonicalField.description);
    final title = description.isNotEmpty
        ? description
        : populatedValues.firstOrNull ??
              '${YorksV1BoqStrings.mobileEditor.primary} $number';
    final details = [
      valueFor(YorksV1BoqCanonicalField.size),
      valueFor(YorksV1BoqCanonicalField.brandOrigin),
      valueFor(YorksV1BoqCanonicalField.model),
      valueFor(YorksV1BoqCanonicalField.equipmentTag),
    ].where((value) => value.isNotEmpty).toList(growable: false);
    final quantity = valueFor(YorksV1BoqCanonicalField.quantity);
    final unit = valueFor(YorksV1BoqCanonicalField.unit);
    return Semantics(
      label: possibleDuplicate
          ? YorksV1BoqStrings.possibleDuplicate.primary
          : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: highlighted
              ? AppColors.blueContainer
              : possibleDuplicate
              ? AppColors.warningContainer
              : null,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: YorksMobileCard(
          padding: EdgeInsets.zero,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 102),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Text(
                      '$number',
                      style: AppTypography.labelLarge.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.titleSmall.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (possibleDuplicate)
                              Tooltip(
                                message:
                                    YorksV1BoqStrings.possibleDuplicate.primary,
                                child: const Icon(
                                  Icons.content_copy_rounded,
                                  size: 17,
                                  color: AppColors.warning,
                                ),
                              ),
                          ],
                        ),
                        if (details.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            details.join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                        if (quantity.isNotEmpty || unit.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            [
                              quantity,
                              unit,
                            ].where((value) => value.isNotEmpty).join(' '),
                            style: AppTypography.labelLarge.copyWith(
                              color: AppColors.inkSecondary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    editable
                        ? Icons.chevron_right_rounded
                        : Icons.visibility_outlined,
                    color: AppColors.inkSecondary,
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

class _MobileBoqMaterialDescriptionField extends StatefulWidget {
  const _MobileBoqMaterialDescriptionField({
    super.key,
    required this.controller,
    required this.rowId,
    required this.enabled,
    required this.onSearchMaterials,
    required this.onSelected,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String rowId;
  final bool enabled;
  final Future<List<YorksV1MaterialRequestInventorySuggestion>> Function(
    String query,
    String? excludedRowId,
  )
  onSearchMaterials;
  final ValueChanged<YorksV1MaterialRequestInventorySuggestion> onSelected;
  final ValueChanged<String> onChanged;

  @override
  State<_MobileBoqMaterialDescriptionField> createState() =>
      _MobileBoqMaterialDescriptionFieldState();
}

class _MobileBoqMaterialDescriptionFieldState
    extends State<_MobileBoqMaterialDescriptionField> {
  final FocusNode _focusNode = FocusNode();
  int _searchEpoch = 0;

  Future<Iterable<YorksV1MaterialRequestInventorySuggestion>> _options(
    TextEditingValue value,
  ) async {
    final epoch = ++_searchEpoch;
    final query = value.text.trim();
    if (!widget.enabled || query.length < 2) {
      return const <YorksV1MaterialRequestInventorySuggestion>[];
    }
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted || epoch != _searchEpoch) {
      return const <YorksV1MaterialRequestInventorySuggestion>[];
    }
    try {
      final results = await widget.onSearchMaterials(query, widget.rowId);
      if (!mounted || epoch != _searchEpoch) {
        return const <YorksV1MaterialRequestInventorySuggestion>[];
      }
      return results;
    } catch (_) {
      return const <YorksV1MaterialRequestInventorySuggestion>[];
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RawAutocomplete<YorksV1MaterialRequestInventorySuggestion>(
        textEditingController: widget.controller,
        focusNode: _focusNode,
        displayStringForOption: (option) => option.description,
        optionsBuilder: _options,
        onSelected: widget.onSelected,
        fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
            TextFormField(
              controller: controller,
              focusNode: focusNode,
              enabled: widget.enabled,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              minLines: 1,
              maxLines: 3,
              onChanged: widget.onChanged,
              onFieldSubmitted: (_) => onSubmitted(),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.search_rounded, size: 19),
              ),
            ),
        optionsViewBuilder: (context, select, options) {
          final values = options.toList(growable: false);
          return Align(
            alignment: AlignmentDirectional.topStart,
            child: Material(
              elevation: 8,
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 340,
                  maxHeight: 280,
                ),
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: values.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final suggestion = values[index];
                    return ListTile(
                      minTileHeight: AppSpacing.minTapTarget,
                      leading: Icon(
                        _boqMaterialSuggestionIcon(suggestion.source),
                        color: AppColors.blue,
                      ),
                      title: Text(
                        suggestion.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        _boqMaterialSuggestionDetails(suggestion),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => select(suggestion),
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
}

class _MobileBoqRowEditor extends StatefulWidget {
  const _MobileBoqRowEditor({
    required this.initialIndex,
    required this.rows,
    required this.columns,
    required this.editable,
    required this.showEditActions,
    required this.canManageCommercials,
    required this.conflict,
    this.language,
    this.onRefresh,
    this.onSearchMaterials,
    this.onMaterialSuggestionSelected,
    required this.onUpdateCell,
    required this.onAddSimilarRow,
    required this.onRemoveRow,
  });

  final int initialIndex;
  final List<YorksV1BoqRow> rows;
  final List<YorksV1BoqColumn> columns;
  final bool editable;
  final bool showEditActions;
  final bool canManageCommercials;
  final bool conflict;
  final AppLanguage? language;
  final Future<void> Function()? onRefresh;
  final Future<List<YorksV1MaterialRequestInventorySuggestion>> Function(
    String query,
    String? excludedRowId,
  )?
  onSearchMaterials;
  final ValueChanged<YorksV1MaterialRequestInventorySuggestion>?
  onMaterialSuggestionSelected;
  final void Function({
    required String rowId,
    required String columnId,
    required String value,
  })
  onUpdateCell;
  final YorksV1BoqRow Function({required String sourceRowId}) onAddSimilarRow;
  final ValueChanged<String> onRemoveRow;

  @override
  State<_MobileBoqRowEditor> createState() => _MobileBoqRowEditorState();
}

class _MobileBoqRowEditorState extends State<_MobileBoqRowEditor> {
  late int _index;
  final Map<String, TextEditingController> _controllers = {};
  bool _allowPop = false;

  YorksV1BoqRow get _row => widget.rows[_index];
  bool get _hasUnsavedChanges =>
      widget.editable &&
      widget.columns.any(
        (column) =>
            _controllers[column.id]?.text !=
            '${_row.valueFor(column.id) ?? ''}',
      );

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _loadControllers();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _loadControllers() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    for (final column in widget.columns) {
      _controllers[column.id] = TextEditingController(
        text: '${_row.valueFor(column.id) ?? ''}',
      );
    }
  }

  void _saveCurrent() {
    if (!widget.editable) return;
    for (final column in widget.columns) {
      widget.onUpdateCell(
        rowId: _row.id,
        columnId: column.id,
        value: _controllers[column.id]!.text,
      );
    }
  }

  void _applyMaterialSuggestion(
    YorksV1MaterialRequestInventorySuggestion suggestion,
  ) {
    widget.onMaterialSuggestionSelected?.call(suggestion);
    final values = _boqMaterialValues(suggestion);
    for (final column in widget.columns) {
      final value = values[column.canonicalField];
      if (value == null || value.isEmpty) continue;
      _controllers[column.id]?.text = value;
    }
    setState(() {});
  }

  void _move(int delta) {
    _saveCurrent();
    final next = (_index + delta).clamp(0, widget.rows.length - 1);
    if (next == _index) return;
    setState(() {
      _index = next;
      _loadControllers();
    });
  }

  Future<void> _requestExit() async {
    if (!_hasUnsavedChanges) {
      Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(YorksV1BoqStrings.discardRowChanges.primary),
        content: Text(YorksV1BoqStrings.discardRowChangesBody.primary),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppStrings.keepEditing.primary),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(AppStrings.discard.primary),
          ),
        ],
      ),
    );
    if (discard == true && mounted) _finishAndPop();
  }

  void _finishAndPop() {
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop || !_hasUnsavedChanges,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _requestExit();
    },
    child: Scaffold(
      backgroundColor: AppColors.mobileSurface,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: _requestExit,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          YorksV1BoqStrings.editMaterial.primary,
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.mobileScreenHorizontal,
            AppSpacing.lg,
            AppSpacing.mobileScreenHorizontal,
            AppSpacing.colossal + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: [
            Text(
              '${YorksV1BoqStrings.mobileEditor.primary} ${_index + 1}',
              style: AppTypography.labelLarge.copyWith(
                color: AppColors.blue,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              YorksV1BoqStrings.editMaterial.primary,
              style: AppTypography.headlineLarge.copyWith(
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              YorksV1BoqStrings.editorDescription.primary,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.muted,
                height: 1.45,
              ),
            ),
            if (widget.conflict && widget.language != null) ...[
              const SizedBox(height: AppSpacing.md),
              _ConflictBanner(
                language: widget.language!,
                onRefresh: widget.onRefresh ?? () async {},
              ),
            ] else if (!widget.editable &&
                !widget.showEditActions &&
                widget.language != null) ...[
              const SizedBox(height: AppSpacing.md),
              _ReadOnlyBanner(language: widget.language!),
            ],
            const SizedBox(height: AppSpacing.lg),
            for (final column in widget.columns) ...[
              Text(
                column.heading,
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.inkSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              if (column.canonicalField ==
                      YorksV1BoqCanonicalField.description &&
                  widget.onSearchMaterials != null)
                _MobileBoqMaterialDescriptionField(
                  key: ValueKey('mobile-boq-description-${_row.id}'),
                  controller: _controllers[column.id]!,
                  rowId: _row.id,
                  enabled:
                      widget.editable &&
                      (!column.isCommercial || widget.canManageCommercials),
                  onSearchMaterials: widget.onSearchMaterials!,
                  onSelected: _applyMaterialSuggestion,
                  onChanged: (_) => setState(() {}),
                )
              else
                TextFormField(
                  controller: _controllers[column.id],
                  enabled:
                      widget.editable &&
                      (!column.isCommercial || widget.canManageCommercials),
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.next,
                  minLines: 1,
                  maxLines:
                      column.canonicalField ==
                          YorksV1BoqCanonicalField.description
                      ? 3
                      : 1,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (widget.showEditActions)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('boq-mobile-similar-row'),
                      onPressed: widget.editable
                          ? () {
                              _saveCurrent();
                              widget.onAddSimilarRow(sourceRowId: _row.id);
                              _finishAndPop();
                            }
                          : null,
                      icon: const Icon(Icons.copy_outlined),
                      label: Text(YorksV1BoqStrings.similarRow.primary),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.editable
                          ? () async {
                              final confirmed = await _confirm(
                                context: context,
                                title: YorksV1BoqStrings.deleteRow,
                                body: YorksV1BoqStrings.deleteRowConfirmation,
                              );
                              if (confirmed != true || !context.mounted) return;
                              widget.onRemoveRow(_row.id);
                              _finishAndPop();
                            }
                          : null,
                      icon: const Icon(Icons.delete_outline),
                      label: Text(YorksV1BoqStrings.deleteRow.primary),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.mobileScreenHorizontal),
          decoration: const BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _index == 0 ? null : () => _move(-1),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, AppSpacing.minTapTarget),
                  ),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: Text(
                    YorksV1BoqStrings.previous.primary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _index == widget.rows.length - 1
                      ? null
                      : () => _move(1),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, AppSpacing.minTapTarget),
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: Text(
                    YorksV1BoqStrings.next.primary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed: !widget.editable
                      ? null
                      : () {
                          _saveCurrent();
                          _finishAndPop();
                        },
                  child: Text(YorksV1BoqStrings.save.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SyncChip extends StatelessWidget {
  const _SyncChip({required this.copy, required this.color});
  final TranslatableString copy;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    height: 32,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
    ),
    alignment: Alignment.center,
    child: Text(
      copy.primary,
      style: AppTypography.labelLarge.copyWith(color: color),
    ),
  );
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => IntrinsicWidth(
    child: Container(
      constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(label, style: AppTypography.labelLarge),
    ),
  );
}

class _EmptyWorksheet extends StatelessWidget {
  const _EmptyWorksheet({required this.copy});
  final TranslatableString copy;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Text(
        copy.primary,
        textAlign: TextAlign.center,
        style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
      ),
    ),
  );
}

class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner({required this.language});
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => _InfoBanner(
    icon: Icons.lock_outline,
    color: AppColors.navy,
    title: YorksV1BoqStrings.readOnly,
    body: YorksV1BoqStrings.readOnlyDescription,
    language: language,
  );
}

class _ConflictBanner extends StatelessWidget {
  const _ConflictBanner({required this.language, required this.onRefresh});
  final AppLanguage language;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => _InfoBanner(
    icon: Icons.sync_problem_outlined,
    color: AppColors.warning,
    title: YorksV1BoqStrings.unsavedChanges,
    body: YorksV1BoqStrings.syncConflict,
    language: language,
    action: TextButton(
      onPressed: onRefresh,
      child: Text(YorksV1BoqStrings.refresh.primary),
    ),
  );
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.language,
    this.action,
  });
  final IconData icon;
  final Color color;
  final TranslatableString title;
  final TranslatableString body;
  final AppLanguage language;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CopyText(
                copy: title,
                language: language,
                style: AppTypography.labelLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              _CopyText(
                copy: body,
                language: language,
                style: AppTypography.bodySmall,
              ),
            ],
          ),
        ),
        ?action,
      ],
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.language, required this.onRetry});
  final AppLanguage language;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 42,
            color: AppColors.muted,
          ),
          const SizedBox(height: AppSpacing.md),
          _CopyText(
            copy: YorksV1BoqStrings.saveFailed,
            language: language,
            center: true,
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(YorksV1BoqStrings.refresh.primary),
          ),
        ],
      ),
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

class _AddColumnResult {
  const _AddColumnResult({required this.heading, required this.mapping});
  final String heading;
  final YorksV1BoqCanonicalField? mapping;
}

Future<_AddColumnResult?> _showAddColumnDialog(
  BuildContext context, {
  required List<YorksV1BoqColumn> columns,
  required bool canManageCommercials,
}) async {
  final controller = TextEditingController();
  YorksV1BoqCanonicalField? mapping;
  return showDialog<_AddColumnResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final heading = controller.text.trim();
        final normalizedHeading = heading.toLowerCase();
        final duplicateHeading =
            heading.isNotEmpty &&
            columns.any(
              (column) =>
                  column.heading.trim().toLowerCase() == normalizedHeading,
            );
        final duplicateMapping =
            mapping != null &&
            columns.any((column) => column.canonicalField == mapping);
        final valid =
            heading.isNotEmpty &&
            !duplicateHeading &&
            !duplicateMapping &&
            (canManageCommercials || mapping?.isCommercial != true);
        return AlertDialog(
          title: Text(YorksV1BoqStrings.addColumn.primary),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: YorksV1BoqStrings.columnHeading.primary,
                  errorText: duplicateHeading
                      ? YorksV1BoqStrings.duplicateColumnHeading.primary
                      : null,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<YorksV1BoqCanonicalField?>(
                initialValue: mapping,
                decoration: InputDecoration(
                  labelText: YorksV1BoqStrings.mappingOptional.primary,
                  errorText: duplicateMapping
                      ? YorksV1BoqStrings.mappingAlreadyUsed.primary
                      : null,
                  helperText: YorksV1BoqStrings.noCanonicalMapping.primary,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(YorksV1BoqStrings.noCanonicalMapping.primary),
                  ),
                  for (final item in YorksV1BoqCanonicalField.values)
                    if ((canManageCommercials || !item.isCommercial) &&
                        !columns.any((column) => column.canonicalField == item))
                      DropdownMenuItem(
                        value: item,
                        child: Text(_canonicalCopy(item).primary),
                      ),
                ],
                onChanged: (value) => setState(() => mapping = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(YorksV1BoqStrings.cancel.primary),
            ),
            FilledButton(
              onPressed: valid
                  ? () => Navigator.pop(
                      context,
                      _AddColumnResult(heading: heading, mapping: mapping),
                    )
                  : null,
              child: Text(YorksV1BoqStrings.add.primary),
            ),
          ],
        );
      },
    ),
  ).whenComplete(controller.dispose);
}

Future<String?> _promptForText({
  required BuildContext context,
  required TranslatableString title,
  required TranslatableString label,
}) async {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title.primary),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: label.primary,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(YorksV1BoqStrings.cancel.primary),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(YorksV1BoqStrings.add.primary),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

class _BoqFolderRenameChange {
  const _BoqFolderRenameChange({required this.name, required this.reason});

  final String name;
  final String reason;
}

Future<_BoqFolderRenameChange?> _promptForFolderRename(
  BuildContext context,
  YorksV1BoqGroup group,
  AppLanguage language,
) => showDialog<_BoqFolderRenameChange>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _BoqFolderRenameDialog(group: group, language: language),
);

Future<String?> _promptForFolderReason(
  BuildContext context, {
  required TranslatableString title,
  required TranslatableString description,
  required AppLanguage language,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _BoqFolderReasonDialog(
    title: title,
    description: description,
    language: language,
  ),
);

class _BoqFolderRenameDialog extends StatefulWidget {
  const _BoqFolderRenameDialog({required this.group, required this.language});

  final YorksV1BoqGroup group;
  final AppLanguage language;

  @override
  State<_BoqFolderRenameDialog> createState() => _BoqFolderRenameDialogState();
}

class _BoqFolderRenameDialogState extends State<_BoqFolderRenameDialog> {
  late final TextEditingController _nameController;
  final TextEditingController _reasonController = TextEditingController();
  String? _nameError;
  String? _reasonError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.group.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final reason = _reasonController.text.trim();
    setState(() {
      _nameError = name.isEmpty
          ? YorksV1BoqStrings.folderNameRequired.active(widget.language)
          : name.toLowerCase() == widget.group.name.trim().toLowerCase()
          ? YorksV1BoqStrings.folderNameUnchanged.active(widget.language)
          : null;
      _reasonError = reason.isEmpty
          ? YorksV1BoqStrings.reasonRequired.active(widget.language)
          : null;
    });
    if (_nameError != null || _reasonError != null) return;
    Navigator.pop(context, _BoqFolderRenameChange(name: name, reason: reason));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(YorksV1BoqStrings.renameFolder.active(widget.language)),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              YorksV1BoqStrings.renameFolderDescription.active(widget.language),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _nameController,
              autofocus: true,
              maxLength: 120,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: YorksV1BoqStrings.customGroupName.active(
                  widget.language,
                ),
                errorText: _nameError,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _reasonController,
              maxLength: 2000,
              minLines: 2,
              maxLines: 4,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: YorksV1BoqStrings.changeReason.active(
                  widget.language,
                ),
                errorText: _reasonError,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(YorksV1BoqStrings.cancel.active(widget.language)),
      ),
      FilledButton(
        onPressed: _submit,
        child: Text(YorksV1BoqStrings.save.active(widget.language)),
      ),
    ],
  );
}

class _BoqFolderReasonDialog extends StatefulWidget {
  const _BoqFolderReasonDialog({
    required this.title,
    required this.description,
    required this.language,
  });

  final TranslatableString title;
  final TranslatableString description;
  final AppLanguage language;

  @override
  State<_BoqFolderReasonDialog> createState() => _BoqFolderReasonDialogState();
}

class _BoqFolderReasonDialogState extends State<_BoqFolderReasonDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _reasonError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _controller.text.trim();
    setState(() {
      _reasonError = reason.isEmpty
          ? YorksV1BoqStrings.reasonRequired.active(widget.language)
          : null;
    });
    if (_reasonError != null) return;
    Navigator.pop(context, reason);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title.active(widget.language)),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.description.active(widget.language)),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 2000,
            minLines: 2,
            maxLines: 4,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: YorksV1BoqStrings.changeReason.active(widget.language),
              errorText: _reasonError,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(YorksV1BoqStrings.cancel.active(widget.language)),
      ),
      FilledButton(
        onPressed: _submit,
        child: Text(widget.title.active(widget.language)),
      ),
    ],
  );
}

Future<bool?> _confirm({
  required BuildContext context,
  required TranslatableString title,
  required TranslatableString body,
}) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title.primary),
    content: Text(body.primary),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: Text(YorksV1BoqStrings.cancel.primary),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: Text(title.primary),
      ),
    ],
  ),
);

TranslatableString _canonicalCopy(
  YorksV1BoqCanonicalField field,
) => switch (field) {
  YorksV1BoqCanonicalField.description => YorksV1BoqStrings.description,
  YorksV1BoqCanonicalField.size => YorksV1BoqStrings.size,
  YorksV1BoqCanonicalField.model => YorksV1BoqStrings.model,
  YorksV1BoqCanonicalField.equipmentTag => YorksV1BoqStrings.equipmentTag,
  YorksV1BoqCanonicalField.brandOrigin => YorksV1BoqStrings.brandOrigin,
  YorksV1BoqCanonicalField.quantity => YorksV1BoqStrings.quantity,
  YorksV1BoqCanonicalField.unit => YorksV1BoqStrings.unit,
  YorksV1BoqCanonicalField.unitCost => YorksV1MaterialRequestStrings.unitCost,
  YorksV1BoqCanonicalField.totalCost => YorksV1MaterialRequestStrings.totalCost,
  YorksV1BoqCanonicalField.planningModelTag =>
    YorksV1BoqStrings.planningModelTag,
};

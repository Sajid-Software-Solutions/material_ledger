import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_material_return_candidates.dart';
import '../../../../shared/models/yorks_v1_material_return_composer_strings.dart';
import '../../../../shared/models/yorks_v1_material_return_strings.dart';
import '../../../../shared/models/yorks_v1_material_return_workflow.dart';
import '../../../../shared/models/yorks_v1_permission_management.dart';
import '../../../../shared/models/yorks_v1_quantity.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/yorks_v1_boq_workbook_provider.dart';
import '../../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../../../shared/providers/yorks_v1_logistics_provider.dart';
import '../../../../shared/providers/yorks_v1_logistics_repository_provider.dart';
import '../../../../shared/providers/yorks_v1_permission_provider.dart';
import '../../../../shared/repositories/yorks_v1_logistics_repository.dart';
import '../../../../shared/services/yorks_v1_logistics_document_service.dart';
import '../widgets/yorks_v1_material_return_composer.dart';
import 'yorks_v1_material_request_screens.dart'
    show
        YorksV1MaterialFormAction,
        YorksV1MaterialFormCard,
        YorksV1MaterialFormField,
        YorksV1MaterialFormMeta;
import '../yorks_v1_feature_action_access.dart';

class YorksV1MaterialReturnsScreen extends ConsumerStatefulWidget {
  const YorksV1MaterialReturnsScreen({super.key});

  @override
  ConsumerState<YorksV1MaterialReturnsScreen> createState() =>
      _YorksV1MaterialReturnsScreenState();
}

class _YorksV1MaterialReturnsScreenState
    extends ConsumerState<YorksV1MaterialReturnsScreen> {
  final _searchController = TextEditingController();
  String? _state;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final role = ref.watch(yorksV1CurrentRoleProvider);
    final permissionState = ref.watch(yorksV1CurrentPermissionSnapshotProvider);
    final createAccess = yorksV1FeatureActionAccess(
      permissionState,
      YorksV1CapabilityKeys.returnsCreate,
      legacyAllowed: role?.canCreateMaterialReturn == true,
      anyProject: true,
    );
    final query = YorksV1MaterialReturnRegisterQuery(
      state: _state,
      search: _searchController.text.trim(),
    );
    final returns = ref.watch(yorksV1MaterialReturnRegisterProvider(query));
    final compact = MediaQuery.sizeOf(context).width < 760;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(yorksV1MaterialReturnRegisterProvider);
            await ref.read(yorksV1MaterialReturnRegisterProvider(query).future);
          },
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: compact
                  ? AppSpacing.mobileScreenHorizontal
                  : AppSpacing.screenHorizontal,
              vertical: compact
                  ? AppSpacing.mobileScreenVertical
                  : AppSpacing.screenVertical,
            ),
            children: [
              YorksR35PageHeader(
                eyebrow: YorksV1MaterialReturnStrings.workspace.active(
                  language,
                ),
                title: YorksV1MaterialReturnStrings.centre.active(language),
                description: YorksV1MaterialReturnStrings.centreDescription
                    .active(language),
                actions: [
                  if (createAccess.isVisible)
                    PrimaryButton(
                      label: YorksV1MaterialReturnStrings.newReturn.active(
                        language,
                      ),
                      icon: Icons.add_rounded,
                      isExpanded: false,
                      onPressed: createAccess.canWrite
                          ? () =>
                                context.go(RoutePaths.yorksV1MaterialReturnNew)
                          : null,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              _FlowBanner(language: language),
              const SizedBox(height: AppSpacing.lg),
              _ReturnFilters(
                language: language,
                searchController: _searchController,
                state: _state,
                onSearch: () => setState(() {}),
                onStateChanged: (value) => setState(() => _state = value),
              ),
              const SizedBox(height: AppSpacing.md),
              returns.when(
                loading: () => const _ReturnLoading(),
                error: (_, _) => _ReturnError(
                  language: language,
                  onRetry: () => ref.invalidate(
                    yorksV1MaterialReturnRegisterProvider(query),
                  ),
                ),
                data: (items) {
                  final visibleItems = items
                      .where(
                        (item) => yorksV1CanReadProjectRecord(
                          permissionState,
                          YorksV1CapabilityKeys.returnsView,
                          legacyAllowed: true,
                          projectId: item.projectId,
                        ),
                      )
                      .toList(growable: false);
                  return visibleItems.isEmpty
                      ? _ReturnEmpty(language: language)
                      : _ReturnRegister(
                          items: visibleItems,
                          language: language,
                          compact: compact,
                        );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlowBanner extends StatelessWidget {
  const _FlowBanner({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: AppColors.blueContainer,
      border: Border.all(color: AppColors.blueContainerStrong),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
    ),
    child: Row(
      children: [
        const Icon(Icons.sync_alt_rounded, color: AppColors.blue),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            YorksV1MaterialReturnStrings.controlledFlow.active(language),
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.inkSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ReturnFilters extends StatelessWidget {
  const _ReturnFilters({
    required this.language,
    required this.searchController,
    required this.state,
    required this.onSearch,
    required this.onStateChanged,
  });

  final AppLanguage language;
  final TextEditingController searchController;
  final String? state;
  final VoidCallback onSearch;
  final ValueChanged<String?> onStateChanged;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    final search = TextField(
      controller: searchController,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => onSearch(),
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded),
        hintText: YorksV1MaterialReturnStrings.searchHint.active(language),
        suffixIcon: IconButton(
          tooltip: YorksV1MaterialReturnStrings.searchHint.active(language),
          onPressed: onSearch,
          icon: const Icon(Icons.arrow_forward_rounded),
        ),
      ),
    );
    final status = DropdownButtonFormField<String?>(
      isExpanded: true,
      initialValue: state,
      decoration: InputDecoration(
        labelText: YorksV1MaterialReturnStrings.status.active(language),
        prefixIcon: const Icon(Icons.filter_alt_outlined),
      ),
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(
            YorksV1MaterialReturnStrings.allReturns.active(language),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        for (final value in YorksV1ProjectMaterialReturnState.values)
          DropdownMenuItem<String?>(
            value: value.wireValue,
            child: Text(
              yorksV1ProjectMaterialReturnStateCopy(value).active(language),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onStateChanged,
    );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: _panelDecoration,
      child: compact
          ? Column(
              children: [
                search,
                const SizedBox(height: AppSpacing.md),
                status,
              ],
            )
          : Row(
              children: [
                Expanded(child: search),
                const SizedBox(width: AppSpacing.md),
                SizedBox(width: 260, child: status),
              ],
            ),
    );
  }
}

class _ReturnRegister extends StatelessWidget {
  const _ReturnRegister({
    required this.items,
    required this.language,
    required this.compact,
  });

  final List<YorksV1MaterialReturnRegisterItem> items;
  final AppLanguage language;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.lg),
    decoration: _panelDecoration,
    child: Column(
      children: [
        for (var index = 0; index < items.length; index++) ...[
          _ReturnRegisterTile(
            item: items[index],
            language: language,
            compact: compact,
          ),
          if (index != items.length - 1) const SizedBox(height: AppSpacing.sm),
        ],
      ],
    ),
  );
}

class _ReturnRegisterTile extends StatelessWidget {
  const _ReturnRegisterTile({
    required this.item,
    required this.language,
    required this.compact,
  });

  final YorksV1MaterialReturnRegisterItem item;
  final AppLanguage language;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final title =
        item.number ??
        yorksV1ProjectMaterialReturnStateCopy(item.state).active(language);
    final state = _ReturnStatePill(state: item.state, language: language);
    return Semantics(
      button: true,
      label: '$title ${item.projectReference} ${item.projectName}',
      child: Material(
        color: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: const BorderSide(color: AppColors.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          onTap: () =>
              context.go(RoutePaths.yorksV1MaterialReturnPath(item.id)),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const _ReturnIcon(),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Text(
                              title,
                              style: AppTypography.titleMedium,
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        '${item.projectReference} · ${item.projectName}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${item.scopeName} · ${item.lineCount} · ${yorksV1DisplayQuantity(item.totalQuantity)}',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      state,
                    ],
                  )
                : Row(
                    children: [
                      const _ReturnIcon(),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: AppTypography.titleMedium),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              '${item.projectReference} · ${item.projectName}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodyMedium,
                            ),
                            Text(
                              item.scopeName,
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${item.lineCount}',
                          textAlign: TextAlign.center,
                          style: AppTypography.titleMedium,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          yorksV1DisplayQuantity(item.totalQuantity),
                          textAlign: TextAlign.center,
                          style: AppTypography.titleMedium,
                        ),
                      ),
                      SizedBox(width: 190, child: state),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _ReturnIcon extends StatelessWidget {
  const _ReturnIcon();

  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      color: AppColors.blueContainer,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: const Icon(Icons.assignment_return_outlined, color: AppColors.blue),
  );
}

class _ReturnStatePill extends StatelessWidget {
  const _ReturnStatePill({required this.state, required this.language});

  final YorksV1ProjectMaterialReturnState state;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (state) {
      YorksV1ProjectMaterialReturnState.confirmed => (
        AppColors.successContainer,
        AppColors.success,
      ),
      YorksV1ProjectMaterialReturnState.rejected ||
      YorksV1ProjectMaterialReturnState.cancelled => (
        AppColors.errorContainer,
        AppColors.error,
      ),
      YorksV1ProjectMaterialReturnState.returnedForChanges => (
        AppColors.warningContainer,
        AppColors.warning,
      ),
      _ => (AppColors.blueContainer, AppColors.blue),
    };
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        ),
        child: Text(
          yorksV1ProjectMaterialReturnStateCopy(state).active(language),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelMedium.copyWith(color: foreground),
        ),
      ),
    );
  }
}

class YorksV1MaterialReturnEditorScreen extends ConsumerStatefulWidget {
  const YorksV1MaterialReturnEditorScreen({
    super.key,
    this.initialProjectId,
    this.returnId,
  });

  final String? initialProjectId;
  final String? returnId;

  @override
  ConsumerState<YorksV1MaterialReturnEditorScreen> createState() =>
      _YorksV1MaterialReturnEditorScreenState();
}

class _YorksV1MaterialReturnEditorScreenState
    extends ConsumerState<YorksV1MaterialReturnEditorScreen> {
  final _purposeController = TextEditingController();
  final _noteController = TextEditingController();
  final _composer = YorksV1ReturnComposerController();
  String? _projectId;
  String? _scopeId;
  DateTime? _requestedDate;
  String? _hydratedDraftId;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _projectId = widget.initialProjectId;
  }

  @override
  void dispose() {
    _purposeController.dispose();
    _noteController.dispose();
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final role = ref.watch(yorksV1CurrentRoleProvider);
    final createAccess = yorksV1FeatureActionAccess(
      ref.watch(yorksV1CurrentPermissionSnapshotProvider),
      YorksV1CapabilityKeys.returnsCreate,
      legacyAllowed: role?.canCreateMaterialReturn == true,
      projectId: _projectId,
      anyProject: _projectId == null,
    );
    final projects = ref.watch(yorksV1MaterialReturnProjectsProvider);
    final workspace = _projectId == null
        ? null
        : ref.watch(
            yorksV1MaterialReturnCreationWorkspaceProvider((
              projectId: _projectId!,
              returnId: widget.returnId,
            )),
          );
    if (workspace case AsyncData(:final value)) {
      _hydrate(value);
    }
    final ready = workspace?.valueOrNull;
    final scopeId = ready == null
        ? null
        : ready.scopes.any((scope) => scope.id == _scopeId)
        ? _scopeId
        : ready.scopes.firstOrNull?.id;
    if (_scopeId == null && scopeId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scopeId == null) setState(() => _scopeId = scopeId);
      });
    }
    final scopeName = ready?.scopes
        .where((scope) => scope.id == scopeId)
        .firstOrNull
        ?.name;
    final project = projects.valueOrNull
        ?.where((item) => item.id == _projectId)
        .firstOrNull;
    final canEdit = createAccess.canWrite && !_working;
    final onSave = ready == null || !canEdit
        ? null
        : () => _save(ready, submit: false);
    final onSubmit = ready == null || !canEdit
        ? null
        : () => _save(ready, submit: true);
    void onCancel() => context.canPop()
        ? context.pop()
        : context.go(RoutePaths.yorksV1Returns);
    final editing = widget.returnId != null;
    final title =
        (editing
                ? YorksV1MaterialReturnComposerStrings.editReturn
                : YorksV1MaterialReturnStrings.newReturn)
            .active(language);
    final compact = MediaQuery.sizeOf(context).width < 680;

    final information = YorksV1MaterialFormCard(
      key: const ValueKey('material-return-information-card'),
      title: YorksV1MaterialReturnComposerStrings.returnInformation.active(
        language,
      ),
      description: YorksV1MaterialReturnComposerStrings
          .returnInformationDescription
          .active(language),
      child: _ReturnInformationFields(
        language: language,
        enabled: canEdit,
        purpose: _purposeController,
        note: _noteController,
        projectField: projects.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => _ReturnError(
            language: language,
            onRetry: () =>
                ref.invalidate(yorksV1MaterialReturnProjectsProvider),
          ),
          data: (values) => DropdownButtonFormField<String>(
            key: const ValueKey('material-return-project'),
            initialValue: values.any((item) => item.id == _projectId)
                ? _projectId
                : null,
            isExpanded: true,
            style: AppTypography.bodyMedium.copyWith(color: AppColors.ink),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.apartment_outlined, size: 20),
            ),
            hint: Text(
              YorksV1MaterialReturnStrings.chooseProject.active(language),
              overflow: TextOverflow.ellipsis,
            ),
            items: [
              for (final project in values)
                DropdownMenuItem(
                  value: project.id,
                  child: Text(
                    '${project.reference} · ${project.name}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: !canEdit || editing
                ? null
                : (value) => setState(() {
                    _projectId = value;
                    _scopeId = null;
                    _hydratedDraftId = null;
                    _composer.clear();
                  }),
          ),
        ),
        scopeField: DropdownButtonFormField<String>(
          key: ValueKey('material-return-scope-$scopeId'),
          initialValue: scopeId,
          isExpanded: true,
          style: AppTypography.bodyMedium.copyWith(color: AppColors.ink),
          items: [
            for (final scope
                in ready?.scopes ?? const <YorksV1MaterialReturnScope>[])
              DropdownMenuItem(
                value: scope.id,
                child: Text(scope.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: !canEdit || ready == null
              ? null
              : (value) => setState(() => _scopeId = value),
        ),
        dateField: OutlinedButton.icon(
          key: const ValueKey('material-return-date'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            alignment: AlignmentDirectional.centerStart,
            foregroundColor: AppColors.ink,
            side: const BorderSide(color: AppColors.line),
          ),
          onPressed: canEdit ? () => _pickDate(context) : null,
          icon: const Icon(Icons.event_outlined, size: 18),
          label: Text(
            _requestedDate == null
                ? YorksV1MaterialReturnStrings.requestedDate.active(language)
                : DateFormat.yMMMd().format(_requestedDate!),
          ),
        ),
      ),
    );

    final items = YorksV1MaterialFormCard(
      key: const ValueKey('material-return-items-card'),
      sectionNumber: 2,
      title: YorksV1MaterialReturnComposerStrings.materialItems.active(
        language,
      ),
      description: YorksV1MaterialReturnComposerStrings.materialItemsDescription
          .active(language),
      actions: [
        YorksV1MaterialFormAction(
          key: const ValueKey('material-return-add-deliveries'),
          label: YorksV1MaterialReturnComposerStrings.addFromDeliveries.active(
            language,
          ),
          icon: Icons.local_shipping_outlined,
          primary: true,
          onPressed: ready == null || !canEdit
              ? null
              : () => showYorksV1DeliveredMaterialPicker(
                  context,
                  projectId: ready.projectId,
                  returnId: ready.draft?.id ?? widget.returnId,
                  scopeId: scopeId,
                  scopeName: scopeName,
                  projectReference: ready.projectReference,
                  controller: _composer,
                  language: language,
                ),
        ),
        YorksV1MaterialFormAction(
          key: const ValueKey('material-return-add-custom'),
          label: YorksV1MaterialReturnComposerStrings.addCustomItem.active(
            language,
          ),
          icon: Icons.add_rounded,
          onPressed: ready == null || !canEdit
              ? null
              : () => _composer.addCustomLine(),
        ),
      ],
      child: workspace == null
          ? _EditorNotice(
              icon: Icons.folder_open_outlined,
              copy: YorksV1MaterialReturnStrings.chooseProject.active(language),
            )
          : workspace.when(
              skipLoadingOnRefresh: true,
              loading: () => const _ReturnLoading(),
              error: (_, _) => _ReturnError(
                language: language,
                onRetry: () => ref.invalidate(
                  yorksV1MaterialReturnCreationWorkspaceProvider((
                    projectId: _projectId!,
                    returnId: widget.returnId,
                  )),
                ),
              ),
              data: (value) => YorksV1MaterialReturnItems(
                projectId: value.projectId,
                returnId: value.draft?.id ?? widget.returnId,
                scopeId: scopeId,
                controller: _composer,
                language: language,
                enabled: canEdit,
              ),
            ),
    );

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: compact
          ? AppBar(backgroundColor: AppColors.surface, title: Text(title))
          : null,
      bottomNavigationBar: compact
          ? _ReturnBottomActions(
              language: language,
              working: _working,
              onCancel: onCancel,
              onSave: onSave,
              onSubmit: onSubmit,
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
            return ListView(
              key: const ValueKey('material-return-editor'),
              padding: EdgeInsets.fromLTRB(
                horizontal,
                AppSpacing.xl,
                horizontal,
                AppSpacing.xxxl,
              ),
              children: [
                ListenableBuilder(
                  listenable: _composer,
                  builder: (context, _) => _ReturnHero(
                    language: language,
                    title: title,
                    reference:
                        ready?.draft?.number ??
                        YorksV1MaterialReturnComposerStrings.assignedOnSubmit
                            .active(language),
                    scopeName: scopeName,
                    projectName: project == null
                        ? null
                        : '${project.reference} · ${project.name}',
                    lineCount: _composer.lines.length,
                    showActions: !compact,
                    working: _working,
                    onCancel: onCancel,
                    onSave: onSave,
                    onSubmit: onSubmit,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                information,
                const SizedBox(height: AppSpacing.lg),
                items,
              ],
            );
          },
        ),
      ),
    );
  }

  void _hydrate(YorksV1MaterialReturnCreationWorkspace workspace) {
    final draft = workspace.draft;
    if (draft == null || _hydratedDraftId == draft.id) return;
    _hydratedDraftId = draft.id;
    _scopeId = draft.scopeId;
    _purposeController.text = draft.purpose ?? '';
    _noteController.text = draft.note ?? '';
    _requestedDate = draft.requestedReturnDate;
    // The composer notifies listeners; never do that while this tree builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _hydratedDraftId == draft.id) {
        _composer.hydrate(draft.lines);
      }
    });
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _requestedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null && mounted) setState(() => _requestedDate = picked);
  }

  Future<void> _save(
    YorksV1MaterialReturnCreationWorkspace workspace, {
    required bool submit,
  }) async {
    final role = ref.read(yorksV1CurrentRoleProvider);
    final access = yorksV1FeatureActionAccess(
      ref.read(yorksV1CurrentPermissionSnapshotProvider),
      YorksV1CapabilityKeys.returnsCreate,
      legacyAllowed: role?.canCreateMaterialReturn == true,
      projectId: workspace.projectId,
    );
    if (!access.canWrite) return;
    final language = ref.read(languageProvider);
    if (_purposeController.text.trim().isEmpty) {
      _toast(
        context,
        YorksV1MaterialReturnStrings.purposeRequired.active(language),
        error: true,
      );
      return;
    }
    if (_composer.hasDelivered && !_composer.isResolved) return;
    final built = _composer.buildLines();
    if (built.hasIssues) {
      _toast(
        context,
        YorksV1MaterialReturnComposerStrings.fixHighlighted.active(language),
        error: true,
      );
      return;
    }
    if (built.customIncomplete) {
      _toast(
        context,
        YorksV1MaterialReturnStrings.customLineRequired.active(language),
        error: true,
      );
      return;
    }
    final lines = built.lines;
    if (lines.isEmpty || _scopeId == null) {
      _toast(
        context,
        YorksV1MaterialReturnStrings.atLeastOneLine.active(language),
        error: true,
      );
      return;
    }
    setState(() => _working = true);
    YorksV1ProjectMaterialReturn? savedDraft;
    try {
      final repository = _returnRepository(ref);
      var saved = savedDraft = await repository.saveProjectMaterialReturnDraft(
        YorksV1SaveMaterialReturnDraftInput(
          returnId: workspace.draft?.id,
          projectId: workspace.projectId,
          scopeId: _scopeId!,
          expectedVersion: workspace.draft?.recordVersion ?? 0,
          purpose: _purposeController.text,
          note: _noteController.text,
          requestedReturnDate: _requestedDate,
          lines: lines,
          idempotencyKey: const Uuid().v4(),
        ),
      );
      if (submit) {
        saved = await repository.submitProjectMaterialReturn(
          YorksV1MaterialReturnCommandInput(
            returnId: saved.id,
            expectedVersion: saved.recordVersion,
            idempotencyKey: const Uuid().v4(),
          ),
        );
      }
      if (!mounted) return;
      ref.invalidate(yorksV1MaterialReturnRegisterProvider);
      ref.invalidate(yorksV1MaterialReturnItemCandidatesProvider);
      context.go(RoutePaths.yorksV1MaterialReturnPath(saved.id));
      _toast(
        context,
        YorksV1MaterialReturnStrings.commandConfirmed(
          reference:
              saved.number ??
              YorksV1MaterialReturnStrings.newReturn.active(language),
          state: saved.state,
          lines: saved.lines.length,
        ).active(language),
      );
    } catch (error) {
      if (mounted) {
        final specific = yorksV1MaterialReturnComposerFailure(error);
        if (specific != null) {
          ref.invalidate(yorksV1MaterialReturnItemCandidatesProvider);
        }
        if (savedDraft != null) {
          // The draft was saved but submission failed: continue from the
          // saved version so the next attempt cannot hit a version conflict.
          ref.invalidate(yorksV1MaterialReturnRegisterProvider);
          context.go(RoutePaths.yorksV1MaterialReturnPath(savedDraft.id));
        }
        _toast(
          context,
          (specific ?? YorksV1MaterialReturnStrings.failed).active(language),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

/// Mirrors the Material Request draft hero: eyebrow, title with stage, one
/// line of guidance, metadata and the header commands.
class _ReturnHero extends StatelessWidget {
  const _ReturnHero({
    required this.language,
    required this.title,
    required this.reference,
    required this.scopeName,
    required this.projectName,
    required this.lineCount,
    required this.showActions,
    required this.working,
    required this.onCancel,
    required this.onSave,
    required this.onSubmit,
  });

  final AppLanguage language;
  final String title;
  final String reference;
  final String? scopeName;
  final String? projectName;
  final int lineCount;
  final bool showActions;
  final bool working;
  final VoidCallback onCancel;
  final VoidCallback? onSave;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked = constraints.maxWidth < 920;
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            YorksV1MaterialReturnComposerStrings.eyebrow
                .active(language)
                .toUpperCase(),
            style: AppTypography.eyebrow,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                title,
                style: AppTypography.headlineMedium.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              _ReturnStageChip(language: language),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            YorksV1MaterialReturnComposerStrings.pageDescription.active(
              language,
            ),
            style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            YorksV1MaterialReturnStrings.controlledFlow.active(language),
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.xs,
            children: [
              YorksV1MaterialFormMeta(
                icon: Icons.tag_rounded,
                value: reference,
              ),
              if (scopeName != null)
                YorksV1MaterialFormMeta(
                  icon: Icons.logout_rounded,
                  value:
                      '${YorksV1MaterialReturnComposerStrings.returnFrom.active(language)}: $scopeName',
                ),
              if (projectName != null)
                YorksV1MaterialFormMeta(
                  icon: Icons.business_outlined,
                  value: projectName!,
                ),
              YorksV1MaterialFormMeta(
                icon: Icons.inventory_2_outlined,
                value: YorksV1MaterialReturnComposerStrings.itemCount(
                  lineCount,
                ).active(language),
              ),
            ],
          ),
        ],
      );
      if (!showActions) return heading;
      final actions = Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        alignment: stacked ? WrapAlignment.start : WrapAlignment.end,
        children: [
          YorksV1MaterialFormAction(
            key: const ValueKey('material-return-save'),
            label: YorksV1MaterialReturnStrings.saveDraft.active(language),
            icon: Icons.save_outlined,
            onPressed: onSave,
          ),
          YorksV1MaterialFormAction(
            key: const ValueKey('material-return-cancel'),
            label: YorksV1MaterialReturnComposerStrings.cancel.active(language),
            onPressed: working ? null : onCancel,
          ),
          YorksV1MaterialFormAction(
            key: const ValueKey('material-return-submit'),
            label: YorksV1MaterialReturnStrings.submitForApproval.active(
              language,
            ),
            icon: Icons.send_rounded,
            primary: true,
            onPressed: onSubmit,
          ),
        ],
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

class _ReturnStageChip extends StatelessWidget {
  const _ReturnStageChip({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Container(
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
      YorksV1MaterialReturnComposerStrings.stageOfFour(1).active(language),
      style: AppTypography.labelSmall.copyWith(
        color: AppColors.onSuccessContainer,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

/// The Material Request "Request Information" field grid, for returns.
class _ReturnInformationFields extends StatelessWidget {
  const _ReturnInformationFields({
    required this.language,
    required this.enabled,
    required this.purpose,
    required this.note,
    required this.projectField,
    required this.scopeField,
    required this.dateField,
  });

  final AppLanguage language;
  final bool enabled;
  final TextEditingController purpose;
  final TextEditingController note;
  final Widget projectField;
  final Widget scopeField;
  final Widget dateField;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final purposeField = YorksV1MaterialFormField(
        label: YorksV1MaterialReturnStrings.purpose.active(language),
        child: TextField(
          key: const ValueKey('material-return-purpose'),
          controller: purpose,
          enabled: enabled,
          decoration: InputDecoration(
            hintText: YorksV1MaterialReturnStrings.purposeHint.active(language),
          ),
        ),
      );
      final project = YorksV1MaterialFormField(
        label: YorksV1MaterialReturnStrings.project.active(language),
        child: projectField,
      );
      final scope = YorksV1MaterialFormField(
        label: YorksV1MaterialReturnComposerStrings.returnFrom.active(language),
        child: scopeField,
      );
      final date = YorksV1MaterialFormField(
        label: YorksV1MaterialReturnStrings.requestedDate.active(language),
        child: dateField,
      );
      final notes = YorksV1MaterialFormField(
        label: YorksV1MaterialReturnStrings.notes.active(language),
        child: TextField(
          key: const ValueKey('material-return-notes'),
          controller: note,
          enabled: enabled,
          minLines: 1,
          maxLines: 4,
        ),
      );
      final width = constraints.maxWidth;
      if (width >= 1160) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: purposeField),
                const SizedBox(width: AppSpacing.lg),
                Expanded(flex: 4, child: project),
                const SizedBox(width: AppSpacing.lg),
                Expanded(flex: 3, child: scope),
                const SizedBox(width: AppSpacing.lg),
                Expanded(flex: 2, child: date),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            notes,
          ],
        );
      }
      if (width >= 620) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: purposeField),
                const SizedBox(width: AppSpacing.lg),
                Expanded(flex: 7, child: project),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: scope),
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: date),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            notes,
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          purposeField,
          const SizedBox(height: AppSpacing.lg),
          project,
          const SizedBox(height: AppSpacing.lg),
          scope,
          const SizedBox(height: AppSpacing.lg),
          date,
          const SizedBox(height: AppSpacing.lg),
          notes,
        ],
      );
    },
  );
}

/// Phone command bar, the same shape as the Material Request draft's.
class _ReturnBottomActions extends StatelessWidget {
  const _ReturnBottomActions({
    required this.language,
    required this.working,
    required this.onCancel,
    required this.onSave,
    required this.onSubmit,
  });

  final AppLanguage language;
  final bool working;
  final VoidCallback onCancel;
  final VoidCallback? onSave;
  final VoidCallback? onSubmit;

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
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          TextButton(
            onPressed: working ? null : onCancel,
            child: Text(
              YorksV1MaterialReturnComposerStrings.cancel.active(language),
            ),
          ),
          OutlinedButton.icon(
            key: const ValueKey('material-return-save-mobile'),
            onPressed: onSave,
            icon: const Icon(Icons.save_outlined),
            label: Text(
              YorksV1MaterialReturnStrings.saveDraft.active(language),
            ),
          ),
          FilledButton.icon(
            key: const ValueKey('material-return-submit-mobile'),
            onPressed: onSubmit,
            icon: working
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(
              YorksV1MaterialReturnStrings.submitForApproval.active(language),
            ),
          ),
        ],
      ),
    ),
  );
}

class YorksV1MaterialReturnDetailScreen extends ConsumerStatefulWidget {
  const YorksV1MaterialReturnDetailScreen({super.key, required this.returnId});

  final String returnId;

  @override
  ConsumerState<YorksV1MaterialReturnDetailScreen> createState() =>
      _YorksV1MaterialReturnDetailScreenState();
}

class _YorksV1MaterialReturnDetailScreenState
    extends ConsumerState<YorksV1MaterialReturnDetailScreen> {
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final detail = ref.watch(
      yorksV1ProjectMaterialReturnProvider(widget.returnId),
    );
    final permissionState = ref.watch(yorksV1CurrentPermissionSnapshotProvider);
    final compact = MediaQuery.sizeOf(context).width < 820;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: compact
          ? AppBar(
              backgroundColor: AppColors.surface,
              title: Text(YorksV1MaterialReturnStrings.centre.active(language)),
            )
          : null,
      body: SafeArea(
        child: detail.when(
          loading: () => const _ReturnLoading(),
          error: (_, _) => _ReturnError(
            language: language,
            onRetry: () => ref.invalidate(
              yorksV1ProjectMaterialReturnProvider(widget.returnId),
            ),
          ),
          data: (value) => YorksV1ProjectReadBoundary(
            allowed: yorksV1CanReadProjectRecord(
              permissionState,
              YorksV1CapabilityKeys.returnsView,
              legacyAllowed: true,
              projectId: value.projectId,
            ),
            language: language,
            child: _detailBody(value, language, compact),
          ),
        ),
      ),
    );
  }

  Widget _detailBody(
    YorksV1ProjectMaterialReturn value,
    AppLanguage language,
    bool compact,
  ) => ListView(
    padding: EdgeInsets.symmetric(
      horizontal: compact
          ? AppSpacing.mobileScreenHorizontal
          : AppSpacing.screenHorizontal,
      vertical: AppSpacing.screenVertical,
    ),
    children: [
      YorksR35PageHeader(
        eyebrow: YorksV1MaterialReturnStrings.workspace.active(language),
        title:
            value.number ??
            yorksV1ProjectMaterialReturnStateCopy(value.state).active(language),
        description: '${value.projectReference} · ${value.projectName}',
        actions: [_ReturnStatePill(state: value.state, language: language)],
      ),
      const SizedBox(height: AppSpacing.lg),
      _ReturnSummary(detail: value, language: language, compact: compact),
      const SizedBox(height: AppSpacing.md),
      _ReturnDetailLines(detail: value, language: language, compact: compact),
      const SizedBox(height: AppSpacing.lg),
      _actionBar(value, language, compact),
    ],
  );

  Widget _actionBar(
    YorksV1ProjectMaterialReturn detail,
    AppLanguage language,
    bool compact,
  ) {
    final permissionState = ref.watch(yorksV1CurrentPermissionSnapshotProvider);
    final createAccess = yorksV1FeatureActionAccess(
      permissionState,
      YorksV1CapabilityKeys.returnsCreate,
      legacyAllowed: detail.canEdit || detail.canSubmit,
      projectId: detail.projectId,
    );
    final approveAccess = yorksV1FeatureActionAccess(
      permissionState,
      YorksV1CapabilityKeys.returnsApprove,
      legacyAllowed: detail.canApprove || detail.canReturnForChanges,
      projectId: detail.projectId,
    );
    final dispatchAccess = yorksV1FeatureActionAccess(
      permissionState,
      YorksV1CapabilityKeys.returnsDispatch,
      legacyAllowed: detail.canDispatch,
      projectId: detail.projectId,
    );
    final actions = <Widget>[
      if (detail.canEdit && createAccess.isVisible)
        SecondaryButton(
          label: YorksV1MaterialReturnStrings.saveDraft.active(language),
          icon: Icons.edit_outlined,
          isExpanded: compact,
          onPressed: _working || !createAccess.canWrite
              ? null
              : () => context.go(
                  RoutePaths.yorksV1MaterialReturnEditPath(
                    detail.projectId,
                    detail.id,
                  ),
                ),
        ),
      if (detail.canSubmit && createAccess.isVisible)
        PrimaryButton(
          label: YorksV1MaterialReturnStrings.submitForApproval.active(
            language,
          ),
          icon: Icons.send_rounded,
          isExpanded: compact,
          onPressed: _working || !createAccess.canWrite
              ? null
              : () => _submit(detail),
        ),
      if (detail.canApprove && approveAccess.isVisible)
        PrimaryButton(
          label: YorksV1MaterialReturnStrings.approve.active(language),
          icon: Icons.verified_outlined,
          isExpanded: compact,
          onPressed: _working || !approveAccess.canWrite
              ? null
              : () =>
                    _decide(detail, YorksV1ProjectMaterialReturnState.approved),
        ),
      if (detail.canReturnForChanges && approveAccess.isVisible)
        SecondaryButton(
          label: YorksV1MaterialReturnStrings.returnForChanges.active(language),
          icon: Icons.undo_rounded,
          isExpanded: compact,
          onPressed: _working || !approveAccess.canWrite
              ? null
              : () => _decisionWithReason(
                  detail,
                  YorksV1ProjectMaterialReturnState.returnedForChanges,
                ),
        ),
      if (detail.canApprove && approveAccess.isVisible)
        SecondaryButton(
          label: YorksV1MaterialReturnStrings.reject.active(language),
          icon: Icons.close_rounded,
          isExpanded: compact,
          onPressed: _working || !approveAccess.canWrite
              ? null
              : () => _decisionWithReason(
                  detail,
                  YorksV1ProjectMaterialReturnState.rejected,
                ),
        ),
      if (detail.canDispatch && dispatchAccess.isVisible)
        PrimaryButton(
          label: YorksV1MaterialReturnStrings.dispatchToWarehouse.active(
            language,
          ),
          icon: Icons.local_shipping_outlined,
          isExpanded: compact,
          onPressed: _working || !dispatchAccess.canWrite
              ? null
              : () => _dispatch(detail),
        ),
      if (detail.canConfirm)
        PrimaryButton(
          label: YorksV1MaterialReturnStrings.confirmReceipt.active(language),
          icon: Icons.inventory_outlined,
          isExpanded: compact,
          onPressed: _working ? null : () => _confirm(detail),
        ),
      if (detail.canCancel)
        SecondaryButton(
          label: YorksV1MaterialReturnStrings.cancelReturn.active(language),
          icon: Icons.block_outlined,
          isExpanded: compact,
          onPressed: _working ? null : () => _cancel(detail),
        ),
      SecondaryButton(
        label: YorksV1MaterialReturnStrings.print.active(language),
        icon: Icons.print_outlined,
        isExpanded: compact,
        onPressed: _working
            ? null
            : () => const YorksV1LogisticsDocumentService()
                  .printProjectMaterialReturn(detail),
      ),
      SecondaryButton(
        label: YorksV1MaterialReturnStrings.downloadPdf.active(language),
        icon: Icons.picture_as_pdf_outlined,
        isExpanded: compact,
        onPressed: _working
            ? null
            : () => const YorksV1LogisticsDocumentService()
                  .shareProjectMaterialReturnPdf(detail),
      ),
      SecondaryButton(
        label: YorksV1MaterialReturnStrings.exportExcel.active(language),
        icon: Icons.file_download_outlined,
        isExpanded: compact,
        onPressed: _working ? null : () => _export(detail),
      ),
    ];
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      alignment: WrapAlignment.end,
      children: [
        for (final action in actions)
          SizedBox(width: compact ? double.infinity : 220, child: action),
      ],
    );
  }

  Future<void> _run(
    Future<YorksV1ProjectMaterialReturn> Function() command,
  ) async {
    final language = ref.read(languageProvider);
    setState(() => _working = true);
    try {
      final confirmed = await command();
      ref.invalidate(yorksV1ProjectMaterialReturnProvider(widget.returnId));
      ref.invalidate(yorksV1MaterialReturnRegisterProvider);
      if (mounted) {
        _toast(
          context,
          YorksV1MaterialReturnStrings.commandConfirmed(
            reference:
                confirmed.number ??
                YorksV1MaterialReturnStrings.newReturn.active(language),
            state: confirmed.state,
            lines: confirmed.lines.length,
          ).active(language),
        );
      }
    } catch (_) {
      if (mounted) {
        _toast(
          context,
          YorksV1MaterialReturnStrings.failed.active(language),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _submit(YorksV1ProjectMaterialReturn detail) => _run(
    () => _returnRepository(ref).submitProjectMaterialReturn(
      YorksV1MaterialReturnCommandInput(
        returnId: detail.id,
        expectedVersion: detail.recordVersion,
        idempotencyKey: const Uuid().v4(),
      ),
    ),
  );

  Future<void> _decide(
    YorksV1ProjectMaterialReturn detail,
    YorksV1ProjectMaterialReturnState decision, {
    String? reason,
  }) => _run(
    () => _returnRepository(ref).decideProjectMaterialReturn(
      YorksV1MaterialReturnDecisionInput(
        returnId: detail.id,
        expectedVersion: detail.recordVersion,
        idempotencyKey: const Uuid().v4(),
        decision: decision,
        reason: reason,
      ),
    ),
  );

  Future<void> _decisionWithReason(
    YorksV1ProjectMaterialReturn detail,
    YorksV1ProjectMaterialReturnState decision,
  ) async {
    final reason = await _textDialog(
      context,
      title: decision == YorksV1ProjectMaterialReturnState.rejected
          ? YorksV1MaterialReturnStrings.reject.active(
              ref.read(languageProvider),
            )
          : YorksV1MaterialReturnStrings.returnForChanges.active(
              ref.read(languageProvider),
            ),
      label: YorksV1MaterialReturnStrings.reason.active(
        ref.read(languageProvider),
      ),
    );
    if (reason != null && reason.trim().isNotEmpty) {
      await _decide(detail, decision, reason: reason);
    }
  }

  Future<void> _dispatch(YorksV1ProjectMaterialReturn detail) async {
    final result = await showDialog<_DispatchValues>(
      context: context,
      builder: (_) => _DispatchDialog(language: ref.read(languageProvider)),
    );
    if (result == null) return;
    await _run(
      () => _returnRepository(ref).dispatchProjectMaterialReturn(
        YorksV1MaterialReturnDispatchInput(
          returnId: detail.id,
          expectedVersion: detail.recordVersion,
          idempotencyKey: const Uuid().v4(),
          driverName: result.driver,
          vehicleReference: result.vehicle,
          deliveryNoteReference: result.deliveryNote,
        ),
      ),
    );
  }

  Future<void> _confirm(YorksV1ProjectMaterialReturn detail) async {
    final result = await showModalBottomSheet<_ReceiptValues>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      builder: (_) =>
          _ReceiptSheet(detail: detail, language: ref.read(languageProvider)),
    );
    if (result == null) return;
    await _run(
      () => _returnRepository(ref).confirmProjectMaterialReturn(
        YorksV1MaterialReturnReceiptInput(
          returnId: detail.id,
          expectedVersion: detail.recordVersion,
          idempotencyKey: const Uuid().v4(),
          receiptNote: result.note,
          lineReceipts: result.lines,
        ),
      ),
    );
  }

  Future<void> _cancel(YorksV1ProjectMaterialReturn detail) async {
    final language = ref.read(languageProvider);
    final reason = await _textDialog(
      context,
      title: YorksV1MaterialReturnStrings.cancelReturn.active(language),
      label: YorksV1MaterialReturnStrings.reason.active(language),
    );
    if (reason == null || reason.trim().isEmpty) return;
    await _run(
      () => _returnRepository(ref).cancelProjectMaterialReturn(
        YorksV1MaterialReturnCancellationInput(
          returnId: detail.id,
          expectedVersion: detail.recordVersion,
          idempotencyKey: const Uuid().v4(),
          reason: reason,
        ),
      ),
    );
  }

  Future<void> _export(YorksV1ProjectMaterialReturn detail) async {
    final documents = const YorksV1LogisticsDocumentService();
    await ref
        .read(yorksV1BoqWorkbookFileServiceProvider)
        .saveWorkbook(
          bytes: documents.buildProjectMaterialReturnExcel(detail),
          suggestedName: documents.suggestedProjectMaterialReturnExcelName(
            detail,
          ),
        );
  }
}

class _ReturnSummary extends StatelessWidget {
  const _ReturnSummary({
    required this.detail,
    required this.language,
    required this.compact,
  });

  final YorksV1ProjectMaterialReturn detail;
  final AppLanguage language;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final values = <(String, String)>[
      (
        YorksV1MaterialReturnStrings.project.active(language),
        detail.projectReference,
      ),
      (YorksV1MaterialReturnStrings.scope.active(language), detail.scopeName),
      (
        YorksV1MaterialReturnStrings.purpose.active(language),
        detail.purpose ?? '—',
      ),
      if (detail.driverName != null)
        (
          YorksV1MaterialReturnStrings.driverName.active(language),
          detail.driverName!,
        ),
      if (detail.vehicleReference != null)
        (
          YorksV1MaterialReturnStrings.vehicleReference.active(language),
          detail.vehicleReference!,
        ),
      if (detail.deliveryNoteReference != null)
        (
          YorksV1MaterialReturnStrings.deliveryNote.active(language),
          detail.deliveryNoteReference!,
        ),
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: _panelDecoration,
      child: Wrap(
        spacing: AppSpacing.xxl,
        runSpacing: AppSpacing.lg,
        children: [
          for (final value in values)
            SizedBox(
              width: compact ? double.infinity : 300,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value.$1,
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(value.$2, style: AppTypography.bodyLarge),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ReturnDetailLines extends StatefulWidget {
  const _ReturnDetailLines({
    required this.detail,
    required this.language,
    required this.compact,
  });

  final YorksV1ProjectMaterialReturn detail;
  final AppLanguage language;
  final bool compact;

  @override
  State<_ReturnDetailLines> createState() => _ReturnDetailLinesState();
}

class _ReturnDetailLinesState extends State<_ReturnDetailLines> {
  final _horizontalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: _panelDecoration,
    child: widget.compact
        ? Column(
            children: [
              for (final line in widget.detail.lines)
                _DetailLineCard(line: line, language: widget.language),
            ],
          )
        : Scrollbar(
            controller: _horizontalController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  const DataColumn(label: Text('#')),
                  DataColumn(
                    label: Text(
                      YorksV1MaterialReturnStrings.description.active(
                        widget.language,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      YorksV1MaterialReturnStrings.sourceReference.active(
                        widget.language,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      YorksV1MaterialReturnStrings.quantity.active(
                        widget.language,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      YorksV1MaterialReturnStrings.unit.active(widget.language),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      YorksV1MaterialReturnStrings.notes.active(
                        widget.language,
                      ),
                    ),
                  ),
                ],
                rows: [
                  for (final line in widget.detail.lines)
                    DataRow(
                      cells: [
                        DataCell(Text('${line.displayOrder}')),
                        DataCell(
                          SizedBox(
                            width: 320,
                            child: _LineDescription(
                              line: line,
                              language: widget.language,
                            ),
                          ),
                        ),
                        DataCell(Text(_lineSource(line, widget.language))),
                        DataCell(
                          Text(yorksV1DisplayQuantity(line.returnQuantity)),
                        ),
                        DataCell(Text(line.unit)),
                        DataCell(Text(line.lineNote ?? '—')),
                      ],
                    ),
                ],
              ),
            ),
          ),
  );
}

class _DetailLineCard extends StatelessWidget {
  const _DetailLineCard({required this.line, required this.language});
  final YorksV1MaterialReturnLineRecord line;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LineDescription(line: line, language: language, emphasise: true),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _lineSource(line, language),
          style: AppTypography.bodySmall.copyWith(color: AppColors.blue),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${yorksV1DisplayQuantity(line.returnQuantity)} ${line.unit}',
          style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

/// Description with the Material Request technical fields beneath it.
class _LineDescription extends StatelessWidget {
  const _LineDescription({
    required this.line,
    required this.language,
    this.emphasise = false,
  });

  final YorksV1MaterialReturnLineRecord line;
  final AppLanguage language;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final spec = [
      if (line.size != null)
        '${YorksV1MaterialReturnComposerStrings.size.active(language)} ${line.size}',
      if (line.model != null)
        '${YorksV1MaterialReturnComposerStrings.model.active(language)} ${line.model}',
      if (line.equipmentTag != null)
        '${YorksV1MaterialReturnComposerStrings.equipmentTag.active(language)} ${line.equipmentTag}',
      ?line.itemCode,
    ].join(' · ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          line.description,
          style: emphasise ? AppTypography.titleMedium : null,
        ),
        if (spec.isNotEmpty)
          Text(
            spec,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
      ],
    );
  }
}

String _lineSource(YorksV1MaterialReturnLineRecord line, AppLanguage language) {
  if (line.origin == YorksV1ReturnLineOrigin.custom) {
    return YorksV1MaterialReturnStrings.customMaterials.active(language);
  }
  return [
    line.sourceRequestNumber,
    line.sourceDispatchNumber,
    if (line.basisKind == YorksV1ReturnBasisKind.dispatchedUnconfirmed)
      YorksV1MaterialReturnComposerStrings.unconfirmedDelivery.active(language),
  ].whereType<String>().join(' · ');
}

class _DispatchDialog extends StatefulWidget {
  const _DispatchDialog({required this.language});
  final AppLanguage language;

  @override
  State<_DispatchDialog> createState() => _DispatchDialogState();
}

class _DispatchDialogState extends State<_DispatchDialog> {
  final driver = TextEditingController();
  final vehicle = TextEditingController();
  final deliveryNote = TextEditingController();

  @override
  void dispose() {
    driver.dispose();
    vehicle.dispose();
    deliveryNote.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      YorksV1MaterialReturnStrings.dispatchToWarehouse.active(widget.language),
    ),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: driver,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: YorksV1MaterialReturnStrings.driverName.active(
                widget.language,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: vehicle,
            decoration: InputDecoration(
              labelText: YorksV1MaterialReturnStrings.vehicleReference.active(
                widget.language,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: deliveryNote,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: YorksV1MaterialReturnStrings.deliveryNote.active(
                widget.language,
              ),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(
          YorksV1MaterialReturnStrings.cancel.active(widget.language),
        ),
      ),
      FilledButton(
        onPressed:
            driver.text.trim().isEmpty || deliveryNote.text.trim().isEmpty
            ? null
            : () => Navigator.pop(
                context,
                _DispatchValues(
                  driver.text.trim(),
                  vehicle.text.trim(),
                  deliveryNote.text.trim(),
                ),
              ),
        child: Text(
          YorksV1MaterialReturnStrings.continueAction.active(widget.language),
        ),
      ),
    ],
  );
}

class _DispatchValues {
  const _DispatchValues(this.driver, this.vehicle, this.deliveryNote);

  final String driver;
  final String vehicle;
  final String deliveryNote;
}

class _ReceiptSheet extends StatefulWidget {
  const _ReceiptSheet({required this.detail, required this.language});
  final YorksV1ProjectMaterialReturn detail;
  final AppLanguage language;

  @override
  State<_ReceiptSheet> createState() => _ReceiptSheetState();
}

class _ReceiptSheetState extends State<_ReceiptSheet> {
  late final Map<String, _ReceiptRow> rows;
  final note = TextEditingController();

  @override
  void initState() {
    super.initState();
    rows = {
      for (final line in widget.detail.lines)
        line.id: _ReceiptRow(
          good: yorksV1DisplayQuantity(line.returnQuantity),
          inventoryItemId: line.sourceInventoryItemId,
        ),
    };
  }

  @override
  void dispose() {
    note.dispose();
    for (final row in rows.values) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 760),
        child: Column(
          children: [
            Text(
              YorksV1MaterialReturnStrings.confirmReceipt.active(
                widget.language,
              ),
              style: AppTypography.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: ListView(
                children: [
                  for (final line in widget.detail.lines)
                    _ReceiptLineEditor(
                      line: line,
                      row: rows[line.id]!,
                      inventory: widget.detail.inventoryItems,
                      language: widget.language,
                      onChanged: () => setState(() {}),
                    ),
                  TextField(
                    controller: note,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: YorksV1MaterialReturnStrings
                          .warehouseReceiptNote
                          .active(widget.language),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: YorksV1MaterialReturnStrings.cancel.active(
                      widget.language,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: PrimaryButton(
                    label: YorksV1MaterialReturnStrings.confirmReceipt.active(
                      widget.language,
                    ),
                    onPressed: _valid
                        ? () => Navigator.pop(
                            context,
                            _ReceiptValues(note.text.trim(), [
                              for (final line in widget.detail.lines)
                                rows[line.id]!.toInput(line),
                            ]),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  bool get _valid {
    for (final line in widget.detail.lines) {
      final row = rows[line.id]!;
      final good = double.tryParse(row.good.text) ?? -1;
      final damaged = double.tryParse(row.damaged.text) ?? -1;
      final missing = double.tryParse(row.missing.text) ?? -1;
      final expected = double.tryParse(line.returnQuantity) ?? 0;
      if (good < 0 || damaged < 0 || missing < 0) return false;
      if ((good + damaged + missing - expected).abs() > 0.0001) return false;
      if (good > 0 && row.inventoryItemId == null && !row.createNewItem) {
        return false;
      }
    }
    return true;
  }
}

class _ReceiptLineEditor extends StatelessWidget {
  const _ReceiptLineEditor({
    required this.line,
    required this.row,
    required this.inventory,
    required this.language,
    required this.onChanged,
  });

  final YorksV1MaterialReturnLineRecord line;
  final _ReceiptRow row;
  final List<YorksV1MaterialReturnInventoryOption> inventory;
  final AppLanguage language;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: AppSpacing.md),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLow,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(line.description, style: AppTypography.titleMedium),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _quantityField(
              row.good,
              YorksV1MaterialReturnStrings.goodQuantity.active(language),
            ),
            _quantityField(
              row.damaged,
              YorksV1MaterialReturnStrings.damagedQuantity.active(language),
            ),
            _quantityField(
              row.missing,
              YorksV1MaterialReturnStrings.notReceivedQuantity.active(language),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String?>(
          initialValue: inventory.any((item) => item.id == row.inventoryItemId)
              ? row.inventoryItemId
              : null,
          decoration: InputDecoration(
            labelText: YorksV1MaterialReturnStrings.inventoryMapping.active(
              language,
            ),
          ),
          items: [
            for (final item in inventory)
              DropdownMenuItem(
                value: item.id,
                child: Text(item.description, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) {
            row.inventoryItemId = value;
            row.createNewItem = false;
            onChanged();
          },
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: row.createNewItem,
          title: Text(
            YorksV1MaterialReturnStrings.createWarehouseItem.active(language),
          ),
          onChanged: (value) {
            row.createNewItem = value == true;
            if (row.createNewItem) row.inventoryItemId = null;
            onChanged();
          },
        ),
      ],
    ),
  );

  Widget _quantityField(TextEditingController controller, String label) =>
      SizedBox(
        width: 190,
        child: TextField(
          controller: controller,
          onChanged: (_) => onChanged(),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label),
        ),
      );
}

class _ReceiptRow {
  _ReceiptRow({required String good, this.inventoryItemId})
    : good = TextEditingController(text: good),
      damaged = TextEditingController(text: '0'),
      missing = TextEditingController(text: '0');

  final TextEditingController good;
  final TextEditingController damaged;
  final TextEditingController missing;
  String? inventoryItemId;
  bool createNewItem = false;

  YorksV1MaterialReturnReceiptLineInput toInput(
    YorksV1MaterialReturnLineRecord line,
  ) => YorksV1MaterialReturnReceiptLineInput(
    returnLineId: line.id,
    receivedGoodQuantity: good.text,
    damagedQuantity: damaged.text,
    notReceivedQuantity: missing.text,
    inventoryItemId: inventoryItemId,
    newItemDescription: createNewItem ? line.description : null,
    newItemBrandOrigin: createNewItem ? line.brandOrigin : null,
    unit: createNewItem ? line.unit : null,
  );

  void dispose() {
    good.dispose();
    damaged.dispose();
    missing.dispose();
  }
}

class _ReceiptValues {
  const _ReceiptValues(this.note, this.lines);

  final String note;
  final List<YorksV1MaterialReturnReceiptLineInput> lines;
}

class _ReturnLoading extends StatelessWidget {
  const _ReturnLoading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(AppSpacing.massive),
    child: Center(child: CircularProgressIndicator()),
  );
}

class _ReturnEmpty extends StatelessWidget {
  const _ReturnEmpty({required this.language});
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => _EditorNotice(
    icon: Icons.assignment_return_outlined,
    copy: YorksV1MaterialReturnStrings.noReturns.active(language),
  );
}

class _ReturnError extends StatelessWidget {
  const _ReturnError({required this.language, required this.onRetry});
  final AppLanguage language;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.xxl),
    decoration: _panelDecoration,
    child: Column(
      children: [
        const Icon(Icons.cloud_off_outlined, color: AppColors.muted, size: 42),
        const SizedBox(height: AppSpacing.md),
        Text(
          YorksV1MaterialReturnStrings.failed.active(language),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(
            YorksV1MaterialReturnStrings.continueAction.active(language),
          ),
        ),
      ],
    ),
  );
}

class _EditorNotice extends StatelessWidget {
  const _EditorNotice({required this.icon, required this.copy});
  final IconData icon;
  final String copy;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.massive),
    decoration: _panelDecoration,
    child: Column(
      children: [
        Icon(icon, size: 42, color: AppColors.blue),
        const SizedBox(height: AppSpacing.md),
        Text(copy, textAlign: TextAlign.center, style: AppTypography.bodyLarge),
      ],
    ),
  );
}

YorksV1ProjectMaterialReturnRepository _returnRepository(WidgetRef ref) {
  final repository = ref.read(yorksV1LogisticsRepositoryProvider);
  if (repository is! YorksV1ProjectMaterialReturnRepository) {
    throw StateError('Material return workflow is unavailable.');
  }
  return repository as YorksV1ProjectMaterialReturnRepository;
}

Future<String?> _textDialog(
  BuildContext context, {
  required String title,
  required String label,
}) async {
  final controller = TextEditingController();
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        minLines: 2,
        maxLines: 5,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(YorksV1MaterialReturnStrings.cancel.primary),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(YorksV1MaterialReturnStrings.continueAction.primary),
        ),
      ],
    ),
  );
  controller.dispose();
  return value;
}

void _toast(BuildContext context, String message, {bool error = false}) {
  YorksAppToast.show(
    context,
    title: message,
    tone: error ? YorksAppToastTone.error : YorksAppToastTone.success,
    dismissible: true,
    duration: const Duration(seconds: 4),
  );
}

const _panelDecoration = BoxDecoration(
  color: AppColors.surfaceContainerLowest,
  borderRadius: BorderRadius.all(Radius.circular(AppSpacing.radiusLg)),
  border: Border.fromBorderSide(BorderSide(color: AppColors.line)),
  boxShadow: [
    BoxShadow(color: AppColors.shadow, blurRadius: 14, offset: Offset(0, 5)),
  ],
);

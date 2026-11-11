import '../../../../shared/providers/yorks_v1_inventory_import_recovery_provider.dart';
import 'yorks_v1_inventory_recovery_panel.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';

import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/yorks_app_toast.dart';
import '../../../../shared/controllers/yorks_v1_inventory_import_controller.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_boq_strings.dart';
import '../../../../shared/models/yorks_v1_document_strings.dart';
import '../../../../shared/models/yorks_v1_inventory_strings.dart';
import '../../../../shared/models/yorks_v1_inventory_supplier.dart';
import '../../../../shared/models/yorks_v1_inventory_supplier_strings.dart';
import '../../../../shared/models/yorks_v1_inventory_workbook.dart';
import '../../../../shared/models/yorks_v1_logistics.dart';
import '../../../../shared/models/yorks_v1_logistics_strings.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/yorks_v1_configuration_provider.dart';
import '../../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../../../shared/providers/yorks_v1_inventory_supplier_provider.dart';
import '../../../../shared/providers/yorks_v1_inventory_workbook_provider.dart';
import '../../../../shared/providers/yorks_v1_logistics_provider.dart';
import '../../../../shared/services/yorks_v1_inventory_workbook_service.dart';

import 'yorks_v1_controlled_unit_field.dart';

/// Import matching must see the complete protected supplier master. An exact
/// supplier on page two must never be offered as a new supplier, so this
/// projection reads all pages with a bounded 10,000-record safety ceiling.
final _inventoryImportSupplierMastersProvider =
    FutureProvider.autoDispose<List<YorksV1InventorySupplierMaster>>((
      ref,
    ) async {
      const pageSize = 100;
      const maximum = 10000;
      final repository = ref.watch(yorksV1InventorySupplierRepositoryProvider);
      final result = <YorksV1InventorySupplierMaster>[];
      var offset = 0;
      while (offset < maximum) {
        final page = await repository.getDirectory(
          limit: pageSize,
          offset: offset,
        );
        for (final supplier in page.suppliers) {
          result.add(
            YorksV1InventorySupplierMaster(
              id: supplier.id,
              name: supplier.name,
              aliases: supplier.aliases,
              isActive:
                  supplier.status == YorksV1InventorySupplierStatus.active ||
                  supplier.isSystemUnknown,
              isUnknownSupplier: supplier.isSystemUnknown,
            ),
          );
        }
        offset += page.suppliers.length;
        if (!page.hasMore || page.suppliers.isEmpty) break;
        if (offset >= maximum) {
          throw StateError('Supplier master exceeds the safe import limit.');
        }
      }
      return List.unmodifiable(result);
    });

/// Procurement/Admin-only R38.9 controlled inventory import workflow.
///
/// The widget accepts already-authorized projections for focused tests and
/// embedded flows. Production callers normally omit them so Riverpod loads the
/// role-safe Warehouse and supplier projections. Every data-changing action is
/// still delegated to [YorksV1InventoryImportController].
class YorksV1InventoryImportScreen extends ConsumerStatefulWidget {
  const YorksV1InventoryImportScreen({
    super.key,
    this.workspace,
    this.suppliers,
    this.preselectedSupplierId,
    this.onCancel,
    this.onReturnToSuppliers,
    this.onOpenSupplier,
  });

  final YorksV1InventoryWorkspace? workspace;
  final List<YorksV1InventorySupplierMaster>? suppliers;
  final String? preselectedSupplierId;
  final VoidCallback? onCancel;
  final VoidCallback? onReturnToSuppliers;
  final ValueChanged<String>? onOpenSupplier;

  @override
  ConsumerState<YorksV1InventoryImportScreen> createState() =>
      _YorksV1InventoryImportScreenState();
}

class _YorksV1InventoryImportScreenState
    extends ConsumerState<YorksV1InventoryImportScreen> {
  final _reviewSearchController = TextEditingController();
  Timer? _searchDebounce;
  String _reviewSearch = '';
  _ReviewFilter _reviewFilter = _ReviewFilter.all;
  bool _selectingFile = false;
  bool _downloadingTemplate = false;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _reviewSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final canManage =
        ref.watch(yorksV1CurrentRoleProvider)?.canManageInventory ?? false;
    if (!canManage) {
      return _RestrictedImportSurface(language: language);
    }

    final importState = ref.watch(yorksV1InventoryImportControllerProvider);
    final pending = ref.watch(yorksV1InventoryImportRecoveryProvider);
    if (pending?.exists == true &&
        importState.status == YorksV1InventoryImportStatus.idle) {
      return Scaffold(
        body: SafeArea(
          child: YorksV1InventoryImportRecoveryPanel(
            onResolved: () {
              if (mounted) setState(() {});
            },
          ),
        ),
      );
    }
    final unitsAsync = ref.watch(yorksV1ConfigurationUnitCodesProvider);
    if (unitsAsync.isLoading && !unitsAsync.hasError) {
      return const _ImportLoadingSurface();
    }
    final controlledUnits = yorksV1LoadedControlledUnits(unitsAsync);
    if (controlledUnits.isEmpty) {
      return _ImportDependencyError(
        language: language,
        message: YorksV1ControlledUnitStrings.unavailable.active(language),
        retryKey: const ValueKey('inventory-import-controlled-units-retry'),
        onRetry: () => ref.invalidate(yorksV1ConfigurationUnitCodesProvider),
      );
    }

    final workspaceAsync = widget.workspace == null
        ? ref.watch(yorksV1InventoryWorkspaceProvider(null))
        : AsyncValue.data(widget.workspace!);
    return workspaceAsync.when(
      loading: () => const _ImportLoadingSurface(),
      error: (_, _) => _ImportDependencyError(
        language: language,
        onRetry: () => ref.invalidate(yorksV1InventoryWorkspaceProvider(null)),
      ),
      data: (workspace) =>
          _buildWithWorkspace(context, language, workspace, controlledUnits),
    );
  }

  Widget _buildWithWorkspace(
    BuildContext context,
    AppLanguage language,
    YorksV1InventoryWorkspace workspace,
    List<String> controlledUnits,
  ) {
    if (widget.suppliers != null) {
      return _buildBody(
        context,
        language,
        workspace,
        widget.suppliers!,
        controlledUnits,
      );
    }
    final suppliersAsync = ref.watch(_inventoryImportSupplierMastersProvider);
    return suppliersAsync.when(
      loading: () => const _ImportLoadingSurface(),
      error: (_, _) => _ImportDependencyError(
        language: language,
        onRetry: () => ref.invalidate(_inventoryImportSupplierMastersProvider),
      ),
      data: (suppliers) =>
          _buildBody(context, language, workspace, suppliers, controlledUnits),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLanguage language,
    YorksV1InventoryWorkspace workspace,
    List<YorksV1InventorySupplierMaster> suppliers,
    List<String> controlledUnits,
  ) {
    final state = ref.watch(yorksV1InventoryImportControllerProvider);
    final controller = ref.read(
      yorksV1InventoryImportControllerProvider.notifier,
    );
    final compact = MediaQuery.sizeOf(context).width < 720;
    final horizontal = compact
        ? AppSpacing.mobileScreenHorizontal
        : AppSpacing.screenHorizontal;

    return PopScope(
      canPop:
          state.status != YorksV1InventoryImportStatus.committing &&
          !state.hasUnconfirmedCommit,
      child: Scaffold(
        backgroundColor: compact ? AppColors.mobileSurface : AppColors.surface,
        body: SafeArea(
          top: false,
          child: CustomScrollView(
            key: const ValueKey('inventory-import-scroll-view'),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontal,
                  compact ? AppSpacing.lg : AppSpacing.xxl,
                  horizontal,
                  AppSpacing.xxl,
                ),
                sliver: SliverList.list(
                  children: [
                    _ImportHeader(
                      language: language,
                      onCancel:
                          (state.status ==
                                  YorksV1InventoryImportStatus.committing ||
                              state.hasUnconfirmedCommit)
                          ? null
                          : widget.onCancel,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _ImportStageRail(language: language, stage: state.stage),
                    const SizedBox(height: AppSpacing.lg),
                    if (state.status == YorksV1InventoryImportStatus.failed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: _ImportFailureBanner(
                          language: language,
                          uncertain: state.hasUnconfirmedCommit,
                          onRetry:
                              state.stage ==
                                  YorksV1InventoryImportStage.uploadFile
                              ? () => _chooseFile(
                                  controller,
                                  workspace,
                                  suppliers,
                                )
                              : null,
                        ),
                      ),
                    _stageBody(
                      language: language,
                      state: state,
                      controller: controller,
                      workspace: workspace,
                      suppliers: suppliers,
                      controlledUnits: controlledUnits,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stageBody({
    required AppLanguage language,
    required YorksV1InventoryImportState state,
    required YorksV1InventoryImportController controller,
    required YorksV1InventoryWorkspace workspace,
    required List<YorksV1InventorySupplierMaster> suppliers,
    required List<String> controlledUnits,
  }) => switch (state.stage) {
    YorksV1InventoryImportStage.uploadFile => _UploadStage(
      language: language,
      busy: state.isBusy || _selectingFile || _downloadingTemplate,
      onChooseFile: () => _chooseFile(controller, workspace, suppliers),
      onDropped: (selected) => unawaited(
        _prepareDroppedWorkbook(selected, controller, workspace, suppliers),
      ),
      onDropError: _showInvalidDrop,
      onDownloadTemplate: _downloadTemplate,
    ),
    YorksV1InventoryImportStage.mapColumns => _MappingStage(
      language: language,
      state: state,
      onReplaceFile: () => _chooseFile(controller, workspace, suppliers),
      onChangeMapping: ({required field, required sourceColumnIndex}) =>
          controller.updateMapping(
            field: field,
            sourceColumnIndex: sourceColumnIndex,
          ),
      canTreatAsOpeningBalance: state.canTreatWorkbookAsOpeningBalance,
      treatsAsOpeningBalance: state.treatsWorkbookAsOpeningBalance,
      onTreatAsOpeningBalanceChanged:
          controller.setTreatWorkbookAsOpeningBalance,
      onBack: controller.previousStage,
      onContinue:
          state.canContinueMapping &&
              (!state.canTreatWorkbookAsOpeningBalance ||
                  state.treatsWorkbookAsOpeningBalance)
          ? () => _confirmMapping(controller, suppliers)
          : null,
    ),
    YorksV1InventoryImportStage.reviewValidate => _ReviewStage(
      language: language,
      state: state,
      workspace: workspace,
      controlledUnits: controlledUnits,
      searchController: _reviewSearchController,
      query: _reviewSearch,
      filter: _reviewFilter,
      onSearchChanged: _onSearchChanged,
      onFilterChanged: (value) => setState(() => _reviewFilter = value),
      onSelectCategory: ({required sourceCategory, required categoryId}) =>
          controller.selectExistingCategory(
            sourceCategory: sourceCategory,
            categoryId: categoryId,
          ),
      onCreateCategory: controller.createNewCategory,
      onResolveSupplier:
          ({
            required sourceSupplierText,
            supplierId,
            canonicalSupplierName,
            createNew = false,
            useUnknownSupplier = false,
          }) => controller.resolveSupplier(
            sourceSupplierText: sourceSupplierText,
            supplierId: supplierId,
            canonicalSupplierName: canonicalSupplierName,
            createNew: createNew,
            useUnknownSupplier: useUnknownSupplier,
          ),
      onResolveUnit: ({required sourceUnitText, required controlledUnit}) =>
          controller.resolveUnit(
            sourceUnitText: sourceUnitText,
            controlledUnit: controlledUnit,
          ),
      onClearUnit: controller.clearUnitResolution,
      onOpeningBalanceDateChanged: controller.setOpeningBalanceAsOfDate,
      onEditRow: (row) => _showReviewCellEditor(controller, row),
      onSearchAndReplace: () => _showSearchAndReplace(controller),
      onApplySafeFixes: controller.applySafeFixes,
      onUndoSafeFixes: controller.canUndoSafeFixes
          ? controller.undoSafeFixes
          : null,
      onExportIssues: () => _runEvidenceExport(controller.exportIssuesWorkbook),
      onExportCleanedPreview: () =>
          _runEvidenceExport(controller.exportCleanedPreviewWorkbook),
      onReplaceFile: () => _chooseFile(controller, workspace, suppliers),
      onBack: controller.previousStage,
      onContinue: state.canContinueReview
          ? controller.continueToSupplierReceipt
          : null,
    ),
    YorksV1InventoryImportStage.supplierReceipt => _SupplierReceiptStage(
      language: language,
      state: state,
      suppliers: suppliers,
      onResolveSupplier:
          ({
            required sourceSupplierText,
            supplierId,
            canonicalSupplierName,
            createNew = false,
            useUnknownSupplier = false,
          }) => controller.resolveSupplier(
            sourceSupplierText: sourceSupplierText,
            supplierId: supplierId,
            canonicalSupplierName: canonicalSupplierName,
            createNew: createNew,
            useUnknownSupplier: useUnknownSupplier,
          ),
      onSetQuantities:
          ({
            required sourceRowNumber,
            required accepted,
            required damaged,
            required rejected,
          }) => controller.setReceiptQuantities(
            sourceRowNumber: sourceRowNumber,
            accepted: accepted,
            damaged: damaged,
            rejected: rejected,
          ),
      onConfirmationChanged: (value) =>
          controller.confirmSupplierAndReceipt(confirmed: value),
      onBack: controller.previousStage,
      onCommit: state.canCommit ? controller.commit : null,
    ),
    YorksV1InventoryImportStage.importSummary => _SummaryStage(
      language: language,
      result: state.result,
      preview: state.preview,
      onReturn: widget.onReturnToSuppliers ?? widget.onCancel,
      onOpenSupplier: widget.onOpenSupplier,
      onExportResult: () => _runEvidenceExport(controller.exportResultWorkbook),
      onReset: controller.reset,
    ),
  };

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      setState(() => _reviewSearch = value.trim().toLowerCase());
    });
  }

  Future<void> _downloadTemplate() async {
    if (_downloadingTemplate) return;
    final language = ref.read(languageProvider);
    setState(() => _downloadingTemplate = true);
    try {
      final saved = await ref
          .read(yorksV1InventoryWorkbookFileServiceProvider)
          .saveImportTemplate();
      if (mounted && saved) {
        YorksAppToast.show(
          context,
          title: YorksV1InventoryStrings.downloadFormatComplete.active(
            language,
          ),
          tone: YorksAppToastTone.success,
        );
      }
    } catch (_) {
      if (mounted) {
        YorksAppToast.show(
          context,
          title: YorksV1InventoryStrings.downloadFormatFailed.active(language),
          tone: YorksAppToastTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingTemplate = false);
    }
  }

  Future<void> _chooseFile(
    YorksV1InventoryImportController controller,
    YorksV1InventoryWorkspace workspace,
    List<YorksV1InventorySupplierMaster> suppliers,
  ) async {
    if (_selectingFile) return;
    setState(() => _selectingFile = true);
    try {
      final selected = await ref
          .read(yorksV1InventoryWorkbookFileServiceProvider)
          .selectWorkbook();
      if (!mounted || selected == null) return;
      final prepared = await _prepareSelectedWorkbook(
        selected,
        controller,
        workspace,
        suppliers,
      );
      if (prepared == true) _applyPreselectedSupplier(controller, suppliers);
    } catch (_) {
      _showInvalidDrop();
    } finally {
      if (mounted) setState(() => _selectingFile = false);
    }
  }

  Future<void> _prepareDroppedWorkbook(
    YorksV1InventorySelectedWorkbook selected,
    YorksV1InventoryImportController controller,
    YorksV1InventoryWorkspace workspace,
    List<YorksV1InventorySupplierMaster> suppliers,
  ) async {
    try {
      final prepared = await _prepareSelectedWorkbook(
        selected,
        controller,
        workspace,
        suppliers,
      );
      if (prepared == null) return;
      if (!prepared) {
        _showInvalidDrop();
        return;
      }
      _applyPreselectedSupplier(controller, suppliers);
    } catch (_) {
      _showInvalidDrop();
    }
  }

  Future<bool?> _prepareSelectedWorkbook(
    YorksV1InventorySelectedWorkbook selected,
    YorksV1InventoryImportController controller,
    YorksV1InventoryWorkspace workspace,
    List<YorksV1InventorySupplierMaster> suppliers,
  ) async {
    final resolved = await _resolveWorksheetChoice(controller, selected);
    if (resolved == null) return null;
    return controller.prepareSelectedAsync(
      resolved,
      workspace,
      suppliers: suppliers,
    );
  }

  Future<YorksV1InventorySelectedWorkbook?> _resolveWorksheetChoice(
    YorksV1InventoryImportController controller,
    YorksV1InventorySelectedWorkbook selected,
  ) async {
    if ((selected.worksheetName ?? '').trim().isNotEmpty) return selected;
    final options = await controller.availableWorksheets(selected);
    if (options.isEmpty) return selected;
    for (final option in options) {
      if (yorksV1InventorySearchKey(option.name) == 'inventoryimport') {
        return selected.selectWorksheet(option.name);
      }
    }
    if (options.length == 1) {
      return selected.selectWorksheet(options.single.name);
    }
    if (!mounted) return null;
    final option = await showDialog<YorksV1InventoryWorksheetOption>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _WorksheetChoiceDialog(
        language: ref.read(languageProvider),
        options: options,
      ),
    );
    return option == null ? null : selected.selectWorksheet(option.name);
  }

  void _showInvalidDrop() {
    if (!mounted) return;
    final language = ref.read(languageProvider);
    YorksAppToast.show(
      context,
      title: YorksV1BoqStrings.importFailed.active(language),
      tone: YorksAppToastTone.error,
    );
  }

  Future<void> _runEvidenceExport(Future<bool> Function() export) async {
    final succeeded = await export();
    if (!mounted) return;
    final language = ref.read(languageProvider);
    YorksAppToast.show(
      context,
      title:
          (succeeded
                  ? YorksV1BoqStrings.exported
                  : YorksV1BoqStrings.exportFailed)
              .active(language),
      tone: succeeded ? YorksAppToastTone.success : YorksAppToastTone.error,
    );
  }

  Future<void> _showReviewCellEditor(
    YorksV1InventoryImportController controller,
    YorksV1InventoryImportRow row,
  ) async {
    final request = await showDialog<_ReviewCellEditRequest>(
      context: context,
      builder: (_) =>
          _ReviewCellEditDialog(language: ref.read(languageProvider), row: row),
    );
    if (request == null) return;
    controller.editReviewCell(
      sourceRowNumber: row.sourceRowNumber,
      field: request.field,
      value: request.value,
    );
  }

  Future<void> _showSearchAndReplace(
    YorksV1InventoryImportController controller,
  ) async {
    final request = await showDialog<_ReviewSearchReplaceRequest>(
      context: context,
      builder: (_) =>
          _ReviewSearchReplaceDialog(language: ref.read(languageProvider)),
    );
    if (request == null) return;
    controller.searchAndReplaceReviewCells(
      field: request.field,
      sourceText: request.sourceText,
      replacementText: request.replacementText,
    );
  }

  void _confirmMapping(
    YorksV1InventoryImportController controller,
    List<YorksV1InventorySupplierMaster> suppliers,
  ) {
    if (controller.confirmMapping()) {
      _applyPreselectedSupplier(controller, suppliers);
    }
  }

  void _applyPreselectedSupplier(
    YorksV1InventoryImportController controller,
    List<YorksV1InventorySupplierMaster> suppliers,
  ) {
    final supplierId = widget.preselectedSupplierId?.trim();
    if (supplierId == null || supplierId.isEmpty) return;
    final supplier = suppliers
        .where((candidate) => candidate.id == supplierId)
        .firstOrNull;
    if (supplier == null || !supplier.isActive) return;
    final unresolved =
        ref
            .read(yorksV1InventoryImportControllerProvider)
            .preview
            ?.rows
            .where(
              (row) =>
                  row.sourceType ==
                      YorksV1InventorySourceType.externalSupplier &&
                  row.requiresSupplierDecision,
            )
            .toList(growable: false) ??
        const <YorksV1InventoryImportRow>[];
    final distinctSourceKeys = unresolved
        .map((row) => row.supplierSourceKey)
        .toSet();
    if (unresolved.isEmpty || distinctSourceKeys.length != 1) return;
    controller.resolveSupplier(
      sourceSupplierText: unresolved.first.rawSupplierName,
      supplierId: supplier.id,
      canonicalSupplierName: supplier.name,
    );
  }
}

typedef _MappingChanged =
    void Function({
      required YorksV1InventoryControlledField field,
      required int? sourceColumnIndex,
    });

typedef _CategorySelected =
    void Function({required String sourceCategory, required String categoryId});

typedef _SupplierResolved =
    void Function({
      required String sourceSupplierText,
      String? supplierId,
      String? canonicalSupplierName,
      bool createNew,
      bool useUnknownSupplier,
    });

typedef _QuantitiesChanged =
    void Function({
      required int sourceRowNumber,
      required String accepted,
      required String damaged,
      required String rejected,
    });

typedef _UnitResolved =
    void Function({
      required String sourceUnitText,
      required String controlledUnit,
    });

enum _ReviewFilter { all, valid, warnings, errors, existing }

class _ImportHeader extends StatelessWidget {
  const _ImportHeader({required this.language, required this.onCancel});

  final AppLanguage language;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          YorksV1InventoryStrings.warehouseInventory.active(language),
          style: AppTypography.eyebrow,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          YorksV1InventorySupplierStrings.importTitle.active(language),
          style: compact
              ? AppTypography.headlineMedium
              : AppTypography.displaySmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Text(
            YorksV1InventorySupplierStrings.importSubtitle.active(language),
            style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
          ),
        ),
      ],
    );
    final cancel = OutlinedButton(
      onPressed: onCancel,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, AppSpacing.minTapTarget),
        foregroundColor: AppColors.ink,
        backgroundColor: AppColors.surfaceContainerLowest,
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
      ),
      child: Text(
        YorksV1InventorySupplierStrings.cancelImport.active(language),
      ),
    );
    if (compact) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: title),
          const SizedBox(width: AppSpacing.md),
          cancel,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: title),
        const SizedBox(width: AppSpacing.xl),
        cancel,
      ],
    );
  }
}

class _ImportStageRail extends StatefulWidget {
  const _ImportStageRail({required this.language, required this.stage});

  final AppLanguage language;
  final YorksV1InventoryImportStage stage;

  @override
  State<_ImportStageRail> createState() => _ImportStageRailState();
}

class _ImportStageRailState extends State<_ImportStageRail> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _scheduleActiveStageAlignment();
  }

  @override
  void didUpdateWidget(covariant _ImportStageRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stage != widget.stage) _scheduleActiveStageAlignment();
  }

  void _scheduleActiveStageAlignment() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      const tileWidth = 152.0;
      final viewport = _controller.position.viewportDimension;
      final requested =
          (widget.stage.index * tileWidth) - ((viewport - tileWidth) / 2);
      final target = requested.clamp(
        _controller.position.minScrollExtent,
        _controller.position.maxScrollExtent,
      );
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.jumpTo(target);
      } else {
        _controller.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    final items = YorksV1InventoryImportStage.values;
    final content = Row(
      children: [
        for (var index = 0; index < items.length; index++)
          SizedBox(
            width: compact ? 152 : null,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: compact ? 152 : 0,
                minHeight: 94,
              ),
              child: _ImportStageTile(
                language: widget.language,
                stage: items[index],
                number: index + 1,
                active: widget.stage == items[index],
                complete: items.indexOf(widget.stage) > index,
              ),
            ),
          ),
      ],
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: compact
            ? SingleChildScrollView(
                key: const ValueKey('import-stage-horizontal-scroll'),
                controller: _controller,
                scrollDirection: Axis.horizontal,
                child: content,
              )
            : Row(
                children: [
                  for (var index = 0; index < items.length; index++)
                    Expanded(
                      child: _ImportStageTile(
                        language: widget.language,
                        stage: items[index],
                        number: index + 1,
                        active: widget.stage == items[index],
                        complete: items.indexOf(widget.stage) > index,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _ImportStageTile extends StatelessWidget {
  const _ImportStageTile({
    required this.language,
    required this.stage,
    required this.number,
    required this.active,
    required this.complete,
  });

  final AppLanguage language;
  final YorksV1InventoryImportStage stage;
  final int number;
  final bool active;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final tone = active ? AppColors.blue : AppColors.muted;
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 160),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: active ? AppColors.blueContainer : Colors.transparent,
        border: const Border(right: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: AppSpacing.minTapTarget,
            height: AppSpacing.minTapTarget,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: complete
                  ? AppColors.successContainer
                  : AppColors.surfaceContainerLowest,
              border: Border.all(
                color: complete ? AppColors.success : AppColors.lineStrong,
              ),
              shape: BoxShape.circle,
            ),
            child: complete
                ? const Icon(
                    Icons.check_rounded,
                    size: 19,
                    color: AppColors.success,
                  )
                : Text(
                    '$number',
                    style: AppTypography.labelLarge.copyWith(color: tone),
                  ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                _stageLabel(stage, language),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.titleSmall.copyWith(color: tone),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorksheetChoiceDialog extends StatelessWidget {
  const _WorksheetChoiceDialog({required this.language, required this.options});

  final AppLanguage language;
  final List<YorksV1InventoryWorksheetOption> options;

  @override
  Widget build(BuildContext context) {
    final listHeight = (options.length * 64.0).clamp(64.0, 320.0);
    return AlertDialog(
      title: Text(
        YorksV1InventorySupplierStrings.chooseWorksheet.active(language),
      ),
      content: SizedBox(
        width: 520,
        height: listHeight + 68,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              YorksV1InventorySupplierStrings.chooseWorksheetDescription.active(
                language,
              ),
              style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: ListView.separated(
                key: const ValueKey('inventory-import-worksheet-list'),
                itemCount: options.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.xs),
                itemBuilder: (context, index) {
                  final option = options[index];
                  return Material(
                    color: AppColors.surfaceContainerLowest,
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(color: AppColors.line),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: ListTile(
                      key: ValueKey(
                        'inventory-import-worksheet-${option.name}',
                      ),
                      minTileHeight: AppSpacing.minTapTarget,
                      title: Text(
                        option.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: option.isHidden
                          ? Text(
                              YorksV1InventorySupplierStrings.hiddenWorksheet
                                  .active(language),
                            )
                          : null,
                      trailing: option.isHidden
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xs,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.warningContainer,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                YorksV1InventorySupplierStrings.hiddenWorksheet
                                    .active(language),
                                style: AppTypography.labelSmall.copyWith(
                                  color: AppColors.warning,
                                ),
                              ),
                            )
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.pop(context, option),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('inventory-import-worksheet-cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(AppStrings.cancel.active(language)),
        ),
      ],
    );
  }
}

class _UploadStage extends StatelessWidget {
  const _UploadStage({
    required this.language,
    required this.busy,
    required this.onChooseFile,
    required this.onDropped,
    required this.onDropError,
    required this.onDownloadTemplate,
  });

  final AppLanguage language;
  final bool busy;
  final VoidCallback onChooseFile;
  final ValueChanged<YorksV1InventorySelectedWorkbook> onDropped;
  final VoidCallback onDropError;
  final VoidCallback onDownloadTemplate;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final upload = _Panel(
      child: Padding(
        padding: EdgeInsets.all(wide ? AppSpacing.xxxl : AppSpacing.xl),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final row = constraints.maxWidth >= 700;
            final introduction = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SquareIcon(
                  icon: YorksDataTransferIcons.importData,
                  color: AppColors.success,
                  background: AppColors.successContainer,
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        YorksV1InventoryStrings.controlledExcelStructure.active(
                          language,
                        ),
                        style: AppTypography.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        YorksV1InventorySupplierStrings
                            .noStockBeforeConfirmation
                            .active(language),
                        style: AppTypography.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            );
            final actions = _InventoryWorkbookDropzone(
              language: language,
              busy: busy,
              onChooseFile: onChooseFile,
              onDropped: onDropped,
              onDropError: onDropError,
              onDownloadTemplate: onDownloadTemplate,
            );
            return row
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(flex: 3, child: introduction),
                      const SizedBox(width: AppSpacing.xxl),
                      Expanded(flex: 2, child: actions),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      introduction,
                      const SizedBox(height: AppSpacing.xxl),
                      actions,
                    ],
                  );
          },
        ),
      ),
    );
    final assurance = _Panel(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              YorksV1InventorySupplierStrings.strictByDefault.active(language),
              style: AppTypography.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              YorksV1InventoryStrings.serverRevalidatesBeforeCommit.active(
                language,
              ),
              style: AppTypography.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            _AssuranceLine(
              icon: Icons.verified_user_outlined,
              label: YorksV1InventoryStrings.previewBeforeCommit.active(
                language,
              ),
            ),
            _AssuranceLine(
              icon: Icons.swap_vert_circle_outlined,
              label: YorksV1InventoryStrings.movementNotBalanceOverwrite.active(
                language,
              ),
            ),
            _AssuranceLine(
              icon: Icons.fact_check_outlined,
              label: YorksV1InventorySupplierStrings.reviewRowsHelp.active(
                language,
              ),
            ),
          ],
        ),
      ),
    );
    final primary = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: upload),
              const SizedBox(width: AppSpacing.lg),
              SizedBox(width: 310, child: assurance),
            ],
          )
        : Column(
            children: [
              upload,
              const SizedBox(height: AppSpacing.lg),
              assurance,
            ],
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        primary,
        const SizedBox(height: AppSpacing.lg),
        _UploadResourceCards(
          language: language,
          busy: busy,
          onDownloadTemplate: onDownloadTemplate,
        ),
      ],
    );
  }
}

class _UploadResourceCards extends StatelessWidget {
  const _UploadResourceCards({
    required this.language,
    required this.busy,
    required this.onDownloadTemplate,
  });

  final AppLanguage language;
  final bool busy;
  final VoidCallback onDownloadTemplate;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _UploadResourceCard(
        icon: Icons.table_view_outlined,
        title: YorksV1InventorySupplierStrings.downloadFormat.active(language),
        description: YorksV1InventoryStrings.controlledExcelStructure.active(
          language,
        ),
        action: OutlinedButton.icon(
          key: const ValueKey('inventory-import-resource-template'),
          onPressed: busy ? null : onDownloadTemplate,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(44, AppSpacing.minTapTarget),
          ),
          icon: const Icon(YorksDataTransferIcons.downloadTemplate, size: 18),
          label: Text(
            YorksV1InventorySupplierStrings.downloadFormat.active(language),
          ),
        ),
      ),
      _UploadResourceCard(
        icon: Icons.cleaning_services_outlined,
        title: YorksV1InventoryStrings.previewBeforeCommit.active(language),
        description: YorksV1InventorySupplierStrings.reviewRowsHelp.active(
          language,
        ),
      ),
      _UploadResourceCard(
        icon: Icons.rule_folder_outlined,
        title: YorksV1InventoryStrings.validation.active(language),
        description: YorksV1InventoryStrings.serverRevalidatesBeforeCommit
            .active(language),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980
            ? 3
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        final width =
            (constraints.maxWidth - (columns - 1) * AppSpacing.md) / columns;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

class _UploadResourceCard extends StatelessWidget {
  const _UploadResourceCard({
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
  Widget build(BuildContext context) => _Panel(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SquareIcon(
            icon: icon,
            color: AppColors.blue,
            background: AppColors.blueContainer,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            description,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(width: double.infinity, child: action),
          ],
        ],
      ),
    ),
  );
}

class _InventoryWorkbookDropzone extends StatefulWidget {
  const _InventoryWorkbookDropzone({
    required this.language,
    required this.busy,
    required this.onChooseFile,
    required this.onDropped,
    required this.onDropError,
    required this.onDownloadTemplate,
  });

  final AppLanguage language;
  final bool busy;
  final VoidCallback onChooseFile;
  final ValueChanged<YorksV1InventorySelectedWorkbook> onDropped;
  final VoidCallback onDropError;
  final VoidCallback onDownloadTemplate;

  @override
  State<_InventoryWorkbookDropzone> createState() =>
      _InventoryWorkbookDropzoneState();
}

class _InventoryWorkbookDropzoneState
    extends State<_InventoryWorkbookDropzone> {
  static const _maximumBytes = 25 * 1024 * 1024;
  static const _acceptedMimeTypes = <String>[
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-excel',
    'application/zip',
    'application/octet-stream',
    'text/csv',
    'text/plain',
    'application/csv',
  ];

  DropzoneViewController? _controller;
  bool _dragging = false;

  Future<void> _handleDrop(List<DropzoneFileInterface>? files) async {
    final controller = _controller;
    if (widget.busy || controller == null || files == null) return;
    if (mounted) setState(() => _dragging = false);
    if (files.length != 1) {
      widget.onDropError();
      return;
    }
    try {
      final file = files.single;
      final fileName = await controller.getFilename(file);
      final extension = fileName.trim().toLowerCase().split('.').last;
      if (extension != 'xlsx' && extension != 'csv') {
        widget.onDropError();
        return;
      }
      final bytes = await controller.getFileData(file);
      if (bytes.isEmpty || bytes.lengthInBytes > _maximumBytes) {
        widget.onDropError();
        return;
      }
      widget.onDropped(
        YorksV1InventorySelectedWorkbook(fileName: fileName, bytes: bytes),
      );
    } catch (_) {
      widget.onDropError();
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Material(
      color: _dragging
          ? AppColors.blueContainer.withValues(alpha: .74)
          : AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InkWell(
        key: const ValueKey('inventory-import-dropzone'),
        onTap: widget.busy ? null : widget.onChooseFile,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: CustomPaint(
          painter: _ImportDropBorderPainter(
            color: _dragging ? AppColors.primary : AppColors.lineStrong,
            radius: AppSpacing.radiusMd,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.cloud_upload_outlined,
                      color: AppColors.primary,
                      size: 28,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _dragging
                            ? YorksV1DocumentStrings.dropDocumentsActive.active(
                                widget.language,
                              )
                            : YorksV1InventoryStrings.selectFile.active(
                                widget.language,
                              ),
                        style: AppTypography.titleSmall.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                if (kIsWeb) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    YorksV1DocumentStrings.dropDocumentsPrompt.active(
                      widget.language,
                    ),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                _UploadActions(
                  language: widget.language,
                  busy: widget.busy,
                  onChooseFile: widget.onChooseFile,
                  onDownloadTemplate: widget.onDownloadTemplate,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!kIsWeb) return content;
    return Stack(
      children: [
        Positioned.fill(
          child: DropzoneView(
            mime: _acceptedMimeTypes,
            operation: DragOperation.copy,
            cursor: CursorType.grab,
            onCreated: (controller) => _controller = controller,
            onHover: () {
              if (mounted && !widget.busy) setState(() => _dragging = true);
            },
            onLeave: () {
              if (mounted) setState(() => _dragging = false);
            },
            onDropInvalid: (_) => widget.onDropError(),
            onDropFiles: (files) => unawaited(_handleDrop(files)),
          ),
        ),
        content,
      ],
    );
  }
}

class _ImportDropBorderPainter extends CustomPainter {
  const _ImportDropBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    const dash = 7.0;
    const gap = 5.0;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(
            distance,
            (distance + dash).clamp(0, metric.length),
          ),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ImportDropBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _UploadActions extends StatelessWidget {
  const _UploadActions({
    required this.language,
    required this.busy,
    required this.onChooseFile,
    required this.onDownloadTemplate,
  });

  final AppLanguage language;
  final bool busy;
  final VoidCallback onChooseFile;
  final VoidCallback onDownloadTemplate;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton.icon(
        key: const ValueKey('inventory-import-choose-file'),
        onPressed: busy ? null : onChooseFile,
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, AppSpacing.minTapTarget),
          backgroundColor: AppColors.navy,
          foregroundColor: AppColors.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
        ),
        icon: busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.onPrimary,
                ),
              )
            : const Icon(YorksDataTransferIcons.importData, size: 18),
        label: Text(
          YorksV1InventorySupplierStrings.chooseFile.active(language),
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      OutlinedButton.icon(
        key: const ValueKey('inventory-import-download-template'),
        onPressed: busy ? null : onDownloadTemplate,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, AppSpacing.minTapTarget),
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.lineStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
        ),
        icon: const Icon(YorksDataTransferIcons.downloadTemplate, size: 18),
        label: Text(
          YorksV1InventorySupplierStrings.downloadFormat.active(language),
        ),
      ),
    ],
  );
}

class _AssuranceLine extends StatelessWidget {
  const _AssuranceLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.blue, size: 19),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(label, style: AppTypography.bodySmall)),
      ],
    ),
  );
}

class _MappingStage extends StatelessWidget {
  const _MappingStage({
    required this.language,
    required this.state,
    required this.onReplaceFile,
    required this.onChangeMapping,
    required this.canTreatAsOpeningBalance,
    required this.treatsAsOpeningBalance,
    required this.onTreatAsOpeningBalanceChanged,
    required this.onBack,
    required this.onContinue,
  });

  final AppLanguage language;
  final YorksV1InventoryImportState state;
  final VoidCallback onReplaceFile;
  final _MappingChanged onChangeMapping;
  final bool canTreatAsOpeningBalance;
  final bool treatsAsOpeningBalance;
  final ValueChanged<bool> onTreatAsOpeningBalanceChanged;
  final VoidCallback onBack;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final source = state.source;
    final mapping = state.mapping;
    if (source == null || mapping == null) {
      return _ImportFailureBanner(language: language, onRetry: onBack);
    }
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final main = Column(
      children: [
        _SelectedFileBar(
          language: language,
          source: source,
          busy: state.isBusy,
          onReplace: onReplaceFile,
        ),
        if (canTreatAsOpeningBalance) ...[
          const SizedBox(height: AppSpacing.md),
          _LegacyOpeningBalanceChoice(
            language: language,
            selected: treatsAsOpeningBalance,
            onChanged: onTreatAsOpeningBalanceChanged,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        _Panel(
          child: Column(
            children: [
              _StageSectionHeader(
                language: language,
                step: YorksV1InventorySupplierStrings.mapColumns,
                title: YorksV1InventorySupplierStrings.confirmColumnMapping,
                subtitle: YorksV1InventoryStrings.importHelp,
                badge: mapping.canContinue
                    ? YorksV1InventorySupplierStrings.mappingReady
                    : YorksV1InventorySupplierStrings.review,
                badgeTone: mapping.canContinue
                    ? AppColors.success
                    : AppColors.warning,
              ),
              SizedBox(
                height: wide ? 560 : 500,
                child: Scrollbar(
                  child: ListView.separated(
                    key: const ValueKey('inventory-import-mapping-list'),
                    padding: EdgeInsets.zero,
                    itemCount: YorksV1InventoryControlledField.values.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: AppColors.line),
                    itemBuilder: (context, index) {
                      final field =
                          YorksV1InventoryControlledField.values[index];
                      return _MappingRow(
                        language: language,
                        field: field,
                        mapping: mapping,
                        wide: wide,
                        onChanged: (value) => onChangeMapping(
                          field: field,
                          sourceColumnIndex: value,
                        ),
                      );
                    },
                  ),
                ),
              ),
              _StageFooter(
                language: language,
                onBack: onBack,
                onContinue: onContinue,
                continueLabel: YorksV1InventorySupplierStrings.reviewValidate,
                busy: state.isBusy,
              ),
            ],
          ),
        ),
      ],
    );
    final summary = _SchemaSummary(
      language: language,
      source: source,
      mapping: mapping,
    );
    if (!wide) {
      return Column(
        children: [
          main,
          const SizedBox(height: AppSpacing.lg),
          summary,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: main),
        const SizedBox(width: AppSpacing.lg),
        SizedBox(width: 310, child: summary),
      ],
    );
  }
}

class _SelectedFileBar extends StatelessWidget {
  const _SelectedFileBar({
    required this.language,
    required this.source,
    required this.busy,
    required this.onReplace,
  });

  final AppLanguage language;
  final YorksV1InventoryWorkbookSource source;
  final bool busy;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 560;
    final file = Row(
      children: [
        const _SquareIcon(
          icon: Icons.description_outlined,
          color: AppColors.success,
          background: AppColors.successContainer,
          size: 42,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                YorksV1InventorySupplierStrings.fileReady.active(language),
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.success,
                ),
              ),
              Text(
                source.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.titleSmall,
              ),
              Text(
                '${source.rowCount} ${YorksV1InventoryStrings.rows.active(language)}',
                style: AppTypography.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
    final replace = OutlinedButton(
      key: const ValueKey('inventory-import-replace-file'),
      onPressed: busy ? null : onReplace,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, AppSpacing.minTapTarget),
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.lineStrong),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
      ),
      child: Text(YorksV1InventorySupplierStrings.replaceFile.active(language)),
    );
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  file,
                  const SizedBox(height: AppSpacing.md),
                  replace,
                ],
              )
            : Row(
                children: [
                  Expanded(child: file),
                  const SizedBox(width: AppSpacing.md),
                  replace,
                ],
              ),
      ),
    );
  }
}

class _LegacyOpeningBalanceChoice extends StatelessWidget {
  const _LegacyOpeningBalanceChoice({
    required this.language,
    required this.selected,
    required this.onChanged,
  });

  final AppLanguage language;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => _Panel(
    child: SwitchListTile.adaptive(
      key: const ValueKey('inventory-import-opening-balance-default'),
      value: selected,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      secondary: const _SquareIcon(
        icon: Icons.event_note_outlined,
        color: AppColors.warning,
        background: AppColors.warningContainer,
        size: 44,
      ),
      title: Text(
        '${YorksV1InventorySourceType.openingBalance.displayName} · '
        '${YorksV1LogisticsStrings.date.active(language)} · '
        '${YorksV1InventorySupplierStrings.required.active(language)}',
        style: AppTypography.titleSmall,
      ),
      subtitle: Text(
        '${YorksV1InventoryStrings.reviewWarningsBeforeImport.active(language)} '
        '${YorksV1InventoryStrings.serverRevalidatesBeforeCommit.active(language)}',
        style: AppTypography.bodySmall,
      ),
    ),
  );
}

class _MappingRow extends StatelessWidget {
  const _MappingRow({
    required this.language,
    required this.field,
    required this.mapping,
    required this.wide,
    required this.onChanged,
  });

  final AppLanguage language;
  final YorksV1InventoryControlledField field;
  final YorksV1InventoryColumnMapping mapping;
  final bool wide;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = mapping.sourceIndex(field) ?? -1;
    final samples = mapping.samplesFor(field);
    final hasIssue = mapping.issues.any((issue) => issue.field == field);
    final fieldLabel = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(field.displayName, style: AppTypography.titleSmall),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          (field.isRequired
                  ? YorksV1InventorySupplierStrings.required
                  : YorksV1InventorySupplierStrings.optional)
              .active(language),
          style: AppTypography.labelSmall.copyWith(
            color: field.isRequired ? AppColors.warning : AppColors.muted,
          ),
        ),
      ],
    );
    final dropdown = DropdownButtonFormField<int>(
      key: ValueKey('mapping-${field.name}'),
      initialValue: selected,
      isExpanded: true,
      decoration: _fieldDecoration(),
      items: [
        DropdownMenuItem(
          value: -1,
          child: Text(
            YorksV1InventorySupplierStrings.notMapped.active(language),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        for (final column in mapping.source.columns)
          DropdownMenuItem(
            value: column.index,
            child: Text(column.header, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (value) => onChanged(value == -1 ? null : value),
    );
    final sample = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          YorksV1InventorySupplierStrings.sampleValue.active(language),
          style: AppTypography.labelSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          samples.where((value) => value.trim().isNotEmpty).take(2).join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySmall,
        ),
      ],
    );
    final status = _StatusPill(
      label:
          (hasIssue
                  ? YorksV1InventorySupplierStrings.review
                  : selected >= 0
                  ? YorksV1InventorySupplierStrings.mappingReady
                  : YorksV1InventorySupplierStrings.notMapped)
              .active(language),
      tone: hasIssue
          ? AppColors.error
          : selected >= 0
          ? AppColors.success
          : AppColors.muted,
    );

    if (!wide) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: fieldLabel),
                const SizedBox(width: AppSpacing.sm),
                status,
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            dropdown,
            if (samples.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              sample,
            ],
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: fieldLabel),
          const SizedBox(width: AppSpacing.md),
          Expanded(flex: 4, child: dropdown),
          const SizedBox(width: AppSpacing.md),
          Expanded(flex: 3, child: sample),
          const SizedBox(width: AppSpacing.md),
          status,
        ],
      ),
    );
  }
}

class _SchemaSummary extends StatelessWidget {
  const _SchemaSummary({
    required this.language,
    required this.source,
    required this.mapping,
  });

  final AppLanguage language;
  final YorksV1InventoryWorkbookSource source;
  final YorksV1InventoryColumnMapping mapping;

  @override
  Widget build(BuildContext context) {
    final mapped = mapping.indexes.length;
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              YorksV1InventorySupplierStrings.mapColumns.active(language),
              style: AppTypography.eyebrow,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '$mapped ${YorksV1InventorySupplierStrings.mappingReady.active(language)}',
              style: AppTypography.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            _MetricPair(
              label: YorksV1InventorySupplierStrings.totalRows.active(language),
              value: '${source.rowCount}',
            ),
            _MetricPair(
              label: YorksV1InventorySupplierStrings.mapColumns.active(
                language,
              ),
              value: '$mapped',
            ),
            _MetricPair(
              label: YorksV1InventorySupplierStrings.errors.active(language),
              value: '${mapping.issues.length}',
              valueColor: mapping.issues.isEmpty
                  ? AppColors.success
                  : AppColors.error,
            ),
            const SizedBox(height: AppSpacing.md),
            _TrustCallout(
              language: language,
              text: YorksV1InventorySupplierStrings.noStockBeforeConfirmation,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewStage extends StatelessWidget {
  const _ReviewStage({
    required this.language,
    required this.state,
    required this.workspace,
    required this.controlledUnits,
    required this.searchController,
    required this.query,
    required this.filter,
    required this.onSearchChanged,
    required this.onFilterChanged,
    required this.onSelectCategory,
    required this.onCreateCategory,
    required this.onResolveSupplier,
    required this.onResolveUnit,
    required this.onClearUnit,
    required this.onOpeningBalanceDateChanged,
    required this.onEditRow,
    required this.onSearchAndReplace,
    required this.onApplySafeFixes,
    required this.onUndoSafeFixes,
    required this.onExportIssues,
    required this.onExportCleanedPreview,
    required this.onReplaceFile,
    required this.onBack,
    required this.onContinue,
  });

  final AppLanguage language;
  final YorksV1InventoryImportState state;
  final YorksV1InventoryWorkspace workspace;
  final List<String> controlledUnits;
  final TextEditingController searchController;
  final String query;
  final _ReviewFilter filter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_ReviewFilter> onFilterChanged;
  final _CategorySelected onSelectCategory;
  final ValueChanged<String> onCreateCategory;
  final _SupplierResolved onResolveSupplier;
  final _UnitResolved onResolveUnit;
  final ValueChanged<String> onClearUnit;
  final ValueChanged<String?> onOpeningBalanceDateChanged;
  final ValueChanged<YorksV1InventoryImportRow> onEditRow;
  final VoidCallback onSearchAndReplace;
  final VoidCallback onApplySafeFixes;
  final VoidCallback? onUndoSafeFixes;
  final VoidCallback onExportIssues;
  final VoidCallback onExportCleanedPreview;
  final VoidCallback onReplaceFile;
  final VoidCallback onBack;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final preview = state.preview;
    final source = state.source;
    if (preview == null || source == null) {
      return _ImportFailureBanner(language: language, onRetry: onBack);
    }
    final rows = preview.rows.where(_matches).toList(growable: false);
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final main = Column(
      children: [
        _SelectedFileBar(
          language: language,
          source: source,
          busy: state.isBusy,
          onReplace: onReplaceFile,
        ),
        const SizedBox(height: AppSpacing.md),
        _ReviewMetrics(language: language, preview: preview),
        if (state.requiresOpeningBalanceAsOfDate) ...[
          const SizedBox(height: AppSpacing.md),
          _OpeningBalanceAsOfField(
            language: language,
            value: state.openingBalanceAsOfDate,
            isValid: state.hasValidOpeningBalanceAsOfDate,
            onChanged: onOpeningBalanceDateChanged,
          ),
        ],
        if (state.unresolvedUnitGroups.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _UnitResolutionPanel(
            language: language,
            groups: state.unresolvedUnitGroups,
            mapping: state.mapping,
            controlledUnits: controlledUnits,
            onResolve: onResolveUnit,
            onClear: onClearUnit,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        _Panel(
          child: Column(
            children: [
              _StageSectionHeader(
                language: language,
                step: YorksV1InventorySupplierStrings.reviewValidate,
                title: YorksV1InventoryStrings.previewInventoryImport,
                subtitle: YorksV1InventorySupplierStrings.reviewRowsHelp,
                badge: preview.canCommit
                    ? YorksV1InventoryStrings.ready
                    : YorksV1InventoryStrings.needReview,
                badgeTone: preview.canCommit
                    ? AppColors.success
                    : AppColors.warning,
              ),
              _ReviewActionBar(
                language: language,
                busy: state.isBusy,
                onSearchAndReplace: onSearchAndReplace,
                onApplySafeFixes: onApplySafeFixes,
                onUndoSafeFixes: onUndoSafeFixes,
                onExportIssues: onExportIssues,
                onExportCleanedPreview: onExportCleanedPreview,
              ),
              _ReviewFilters(
                language: language,
                controller: searchController,
                selected: filter,
                onSearchChanged: onSearchChanged,
                onFilterChanged: onFilterChanged,
              ),
              const Divider(height: 1, color: AppColors.line),
              SizedBox(
                height: wide ? 570 : 540,
                child: rows.isEmpty
                    ? Center(
                        child: Text(
                          YorksV1InventoryStrings.noItems.active(language),
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyMedium,
                        ),
                      )
                    : Scrollbar(
                        child: ListView.builder(
                          key: const ValueKey('inventory-import-review-list'),
                          padding: const EdgeInsets.all(AppSpacing.md),
                          itemCount: rows.length,
                          itemBuilder: (context, index) => Padding(
                            padding: EdgeInsets.only(
                              bottom: index == rows.length - 1
                                  ? 0
                                  : AppSpacing.sm,
                            ),
                            child: _ReviewRowCard(
                              language: language,
                              row: rows[index],
                              categories: workspace.categories,
                              onSelectCategory: onSelectCategory,
                              onCreateCategory: onCreateCategory,
                              onResolveSupplier: onResolveSupplier,
                              onEdit: () => onEditRow(rows[index]),
                            ),
                          ),
                        ),
                      ),
              ),
              if (!wide)
                _StageFooter(
                  language: language,
                  onBack: onBack,
                  onContinue: onContinue,
                  continueLabel:
                      YorksV1InventorySupplierStrings.supplierReceipt,
                  busy: state.isBusy,
                ),
            ],
          ),
        ),
      ],
    );
    final summary = _ReviewSummary(
      language: language,
      preview: preview,
      busy: state.isBusy,
      onBack: onBack,
      onContinue: onContinue,
    );
    if (!wide) return main;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: main),
        const SizedBox(width: AppSpacing.lg),
        SizedBox(width: 315, child: summary),
      ],
    );
  }

  bool _matches(YorksV1InventoryImportRow row) {
    final matchesSearch =
        query.isEmpty ||
        row.itemCode.toLowerCase().contains(query) ||
        row.description.toLowerCase().contains(query) ||
        row.sourceCategory.toLowerCase().contains(query) ||
        row.rawSupplierName.toLowerCase().contains(query) ||
        row.rawSupplierReference.toLowerCase().contains(query);
    if (!matchesSearch) return false;
    return switch (filter) {
      _ReviewFilter.all => true,
      _ReviewFilter.valid => !row.hasErrors && !row.hasWarnings,
      _ReviewFilter.warnings => row.hasWarnings,
      _ReviewFilter.errors => row.hasErrors,
      _ReviewFilter.existing => !row.isNewItem,
    };
  }
}

class _ReviewMetrics extends StatelessWidget {
  const _ReviewMetrics({required this.language, required this.preview});

  final AppLanguage language;
  final YorksV1InventoryImportPreview preview;

  @override
  Widget build(BuildContext context) {
    final valid = preview.rows
        .where((row) => !row.hasErrors && !row.hasWarnings)
        .length;
    final values = [
      (
        YorksV1InventorySupplierStrings.totalRows.active(language),
        preview.rowCount,
        AppColors.ink,
      ),
      (
        YorksV1InventorySupplierStrings.validRows.active(language),
        valid,
        AppColors.success,
      ),
      (
        YorksV1InventorySupplierStrings.warnings.active(language),
        preview.warningCount,
        AppColors.warning,
      ),
      (
        YorksV1InventorySupplierStrings.errors.active(language),
        preview.errorCount,
        AppColors.error,
      ),
      (
        YorksV1InventorySupplierStrings.existingItems.active(language),
        preview.existingItemCount,
        AppColors.purple,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 5
            : constraints.maxWidth >= 520
            ? 3
            : 2;
        final width =
            (constraints.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final value in values)
              SizedBox(
                width: width,
                child: _MetricCard(
                  label: value.$1,
                  value: '${value.$2}',
                  valueColor: value.$3,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _OpeningBalanceAsOfField extends StatefulWidget {
  const _OpeningBalanceAsOfField({
    required this.language,
    required this.value,
    required this.isValid,
    required this.onChanged,
  });

  final AppLanguage language;
  final String? value;
  final bool isValid;
  final ValueChanged<String?> onChanged;

  @override
  State<_OpeningBalanceAsOfField> createState() =>
      _OpeningBalanceAsOfFieldState();
}

class _OpeningBalanceAsOfFieldState extends State<_OpeningBalanceAsOfField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value ?? '');
  }

  @override
  void didUpdateWidget(covariant _OpeningBalanceAsOfField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.value ?? '';
    if (_controller.text != next) _controller.text = next;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Panel(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                YorksV1InventorySourceType.openingBalance.displayName,
                style: AppTypography.titleSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                YorksV1InventorySupplierStrings.noStockBeforeConfirmation
                    .active(widget.language),
                style: AppTypography.bodySmall,
              ),
            ],
          );
          final field = TextField(
            key: const ValueKey('inventory-import-opening-balance-date'),
            controller: _controller,
            keyboardType: TextInputType.datetime,
            onChanged: widget.onChanged,
            decoration:
                _fieldDecoration(
                  labelText:
                      '${YorksV1InventorySourceType.openingBalance.displayName} · ${YorksV1LogisticsStrings.date.active(widget.language)}',
                ).copyWith(
                  errorText: widget.isValid
                      ? null
                      : YorksV1InventorySupplierStrings.required.active(
                          widget.language,
                        ),
                  suffixIcon: IconButton(
                    onPressed: _selectDate,
                    constraints: const BoxConstraints.tightFor(
                      width: AppSpacing.minTapTarget,
                      height: AppSpacing.minTapTarget,
                    ),
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  ),
                ),
          );
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                copy,
                const SizedBox(height: AppSpacing.md),
                field,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: copy),
              const SizedBox(width: AppSpacing.xl),
              SizedBox(width: 260, child: field),
            ],
          );
        },
      ),
    ),
  );

  Future<void> _selectDate() async {
    final parsed = DateTime.tryParse(_controller.text.trim());
    final value = await showDatePicker(
      context: context,
      initialDate: parsed ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (value == null) return;
    final formatted =
        '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
    _controller.text = formatted;
    widget.onChanged(formatted);
  }
}

class _UnitResolutionPanel extends StatelessWidget {
  const _UnitResolutionPanel({
    required this.language,
    required this.groups,
    required this.mapping,
    required this.controlledUnits,
    required this.onResolve,
    required this.onClear,
  });

  final AppLanguage language;
  final List<YorksV1InventoryUnitReviewGroup> groups;
  final YorksV1InventoryColumnMapping? mapping;
  final List<String> controlledUnits;
  final _UnitResolved onResolve;
  final ValueChanged<String> onClear;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StageSectionHeader(
          language: language,
          step: YorksV1InventoryStrings.validation,
          title: YorksV1InventoryStrings.reviewWarningsBeforeImport,
          subtitle: YorksV1InventoryStrings.serverRevalidatesBeforeCommit,
          badge: YorksV1InventoryStrings.needReview,
          badgeTone: AppColors.warning,
        ),
        const Divider(height: 1, color: AppColors.line),
        SizedBox(
          height: (groups.length * 84.0).clamp(84, 280),
          child: ListView.separated(
            key: const ValueKey('inventory-import-unit-resolution-list'),
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: groups.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final group = groups[index];
              final selected = mapping?.controlledUnitFor(group.sourceUnitText);
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.warningContainer.withValues(alpha: 0.5),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.22),
                  ),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final copy = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.sourceUnitText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.titleSmall,
                          ),
                          Text(
                            '${group.rowCount} ${YorksV1InventoryStrings.rows.active(language)}',
                            style: AppTypography.bodySmall,
                          ),
                        ],
                      );
                      final dropdown = DropdownButtonFormField<String>(
                        key: ValueKey('unit-resolution-${group.sourceKey}'),
                        initialValue: selected,
                        isExpanded: true,
                        decoration: _fieldDecoration(
                          labelText: AppStrings.unit.active(language),
                        ),
                        hint: Text(
                          YorksV1InventorySupplierStrings.notMapped.active(
                            language,
                          ),
                        ),
                        items: [
                          for (final unit in controlledUnits)
                            DropdownMenuItem(value: unit, child: Text(unit)),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            onClear(group.sourceUnitText);
                          } else {
                            onResolve(
                              sourceUnitText: group.sourceUnitText,
                              controlledUnit: value,
                            );
                          }
                        },
                      );
                      if (constraints.maxWidth < 560) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            copy,
                            const SizedBox(height: AppSpacing.sm),
                            dropdown,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: copy),
                          const SizedBox(width: AppSpacing.md),
                          SizedBox(width: 250, child: dropdown),
                        ],
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _ReviewFilters extends StatelessWidget {
  const _ReviewFilters({
    required this.language,
    required this.controller,
    required this.selected,
    required this.onSearchChanged,
    required this.onFilterChanged,
  });

  final AppLanguage language;
  final TextEditingController controller;
  final _ReviewFilter selected;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_ReviewFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final search = TextField(
          key: const ValueKey('inventory-import-review-search'),
          controller: controller,
          onChanged: onSearchChanged,
          decoration: _fieldDecoration(
            hintText: YorksV1InventoryStrings.itemSearchHint.active(language),
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
          ),
        );
        final filter = DropdownButtonFormField<_ReviewFilter>(
          key: const ValueKey('inventory-import-review-filter'),
          initialValue: selected,
          isExpanded: true,
          decoration: _fieldDecoration(),
          items: [
            for (final value in _ReviewFilter.values)
              DropdownMenuItem(
                value: value,
                child: Text(
                  _reviewFilterLabel(value, language),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) onFilterChanged(value);
          },
        );
        if (constraints.maxWidth < 560) {
          return Column(
            children: [
              search,
              const SizedBox(height: AppSpacing.sm),
              filter,
            ],
          );
        }
        return Row(
          children: [
            Expanded(flex: 3, child: search),
            const SizedBox(width: AppSpacing.sm),
            Expanded(flex: 2, child: filter),
          ],
        );
      },
    ),
  );
}

class _ReviewActionBar extends StatelessWidget {
  const _ReviewActionBar({
    required this.language,
    required this.busy,
    required this.onSearchAndReplace,
    required this.onApplySafeFixes,
    required this.onUndoSafeFixes,
    required this.onExportIssues,
    required this.onExportCleanedPreview,
  });

  final AppLanguage language;
  final bool busy;
  final VoidCallback onSearchAndReplace;
  final VoidCallback onApplySafeFixes;
  final VoidCallback? onUndoSafeFixes;
  final VoidCallback onExportIssues;
  final VoidCallback onExportCleanedPreview;

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      OutlinedButton.icon(
        key: const ValueKey('inventory-import-search-replace'),
        onPressed: busy ? null : onSearchAndReplace,
        icon: const Icon(Icons.find_replace_rounded, size: 18),
        label: Text(YorksV1InventoryStrings.search.active(language)),
      ),
      OutlinedButton.icon(
        key: const ValueKey('inventory-import-safe-fixes'),
        onPressed: busy ? null : onApplySafeFixes,
        icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
        label: Text(YorksV1InventoryStrings.reviewImport.active(language)),
      ),
      OutlinedButton.icon(
        key: const ValueKey('inventory-import-undo-safe-fixes'),
        onPressed: busy ? null : onUndoSafeFixes,
        icon: const Icon(Icons.undo_rounded, size: 18),
        label: Text(AppStrings.undo.active(language)),
      ),
      OutlinedButton.icon(
        key: const ValueKey('inventory-import-export-issues'),
        onPressed: busy ? null : onExportIssues,
        icon: const Icon(Icons.rule_folder_outlined, size: 18),
        label: Text(YorksV1InventorySupplierStrings.errors.active(language)),
      ),
      OutlinedButton.icon(
        key: const ValueKey('inventory-import-export-cleaned'),
        onPressed: busy ? null : onExportCleanedPreview,
        icon: const Icon(Icons.download_done_outlined, size: 18),
        label: Text(
          YorksV1InventoryStrings.previewBeforeCommit.active(language),
        ),
      ),
    ];
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: buttons,
        ),
      ),
    );
  }
}

class _ReviewCellEditRequest {
  const _ReviewCellEditRequest({required this.field, required this.value});

  final YorksV1InventoryControlledField field;
  final String value;
}

class _ReviewCellEditDialog extends StatefulWidget {
  const _ReviewCellEditDialog({required this.language, required this.row});

  final AppLanguage language;
  final YorksV1InventoryImportRow row;

  @override
  State<_ReviewCellEditDialog> createState() => _ReviewCellEditDialogState();
}

class _ReviewCellEditDialogState extends State<_ReviewCellEditDialog> {
  late YorksV1InventoryControlledField _field;
  late final TextEditingController _valueController;

  @override
  void initState() {
    super.initState();
    _field = YorksV1InventoryControlledField.description;
    _valueController = TextEditingController(
      text: _reviewFieldValue(widget.row, _field),
    );
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(YorksV1InventoryStrings.editDetails.active(widget.language)),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<YorksV1InventoryControlledField>(
            key: const ValueKey('inventory-import-edit-field'),
            initialValue: _field,
            isExpanded: true,
            decoration: _fieldDecoration(
              labelText: YorksV1InventorySupplierStrings.mapColumns.active(
                widget.language,
              ),
            ),
            items: [
              for (final field in yorksV1InventorySafeEditableFields)
                DropdownMenuItem(
                  value: field,
                  child: Text(
                    field.displayName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _field = value;
                _valueController.text = _reviewFieldValue(widget.row, value);
              });
            },
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const ValueKey('inventory-import-edit-value'),
            controller: _valueController,
            minLines: 1,
            maxLines: 4,
            decoration: _fieldDecoration(labelText: _field.displayName),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(AppStrings.cancel.active(widget.language)),
      ),
      FilledButton(
        key: const ValueKey('inventory-import-save-cell-edit'),
        onPressed: () => Navigator.of(context).pop(
          _ReviewCellEditRequest(field: _field, value: _valueController.text),
        ),
        child: Text(AppStrings.saveChanges.active(widget.language)),
      ),
    ],
  );
}

class _ReviewSearchReplaceRequest {
  const _ReviewSearchReplaceRequest({
    required this.field,
    required this.sourceText,
    required this.replacementText,
  });

  final YorksV1InventoryControlledField field;
  final String sourceText;
  final String replacementText;
}

class _ReviewSearchReplaceDialog extends StatefulWidget {
  const _ReviewSearchReplaceDialog({required this.language});

  final AppLanguage language;

  @override
  State<_ReviewSearchReplaceDialog> createState() =>
      _ReviewSearchReplaceDialogState();
}

class _ReviewSearchReplaceDialogState
    extends State<_ReviewSearchReplaceDialog> {
  YorksV1InventoryControlledField _field =
      YorksV1InventoryControlledField.description;
  final _sourceController = TextEditingController();
  final _replacementController = TextEditingController();

  @override
  void dispose() {
    _sourceController.dispose();
    _replacementController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(YorksV1InventoryStrings.search.active(widget.language)),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<YorksV1InventoryControlledField>(
            key: const ValueKey('inventory-import-replace-field'),
            initialValue: _field,
            isExpanded: true,
            decoration: _fieldDecoration(
              labelText: YorksV1InventorySupplierStrings.mapColumns.active(
                widget.language,
              ),
            ),
            items: [
              for (final field in yorksV1InventorySafeEditableFields)
                DropdownMenuItem(
                  value: field,
                  child: Text(
                    field.displayName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _field = value);
            },
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const ValueKey('inventory-import-replace-source'),
            controller: _sourceController,
            onChanged: (_) => setState(() {}),
            decoration: _fieldDecoration(
              labelText: YorksV1InventoryStrings.search.active(widget.language),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const ValueKey('inventory-import-replace-value'),
            controller: _replacementController,
            decoration: _fieldDecoration(
              labelText: YorksV1InventoryStrings.editDetails.active(
                widget.language,
              ),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(AppStrings.cancel.active(widget.language)),
      ),
      FilledButton(
        key: const ValueKey('inventory-import-apply-replace'),
        onPressed: _sourceController.text.isEmpty
            ? null
            : () => Navigator.of(context).pop(
                _ReviewSearchReplaceRequest(
                  field: _field,
                  sourceText: _sourceController.text,
                  replacementText: _replacementController.text,
                ),
              ),
        child: Text(AppStrings.saveChanges.active(widget.language)),
      ),
    ],
  );
}

String _reviewFieldValue(
  YorksV1InventoryImportRow row,
  YorksV1InventoryControlledField field,
) => switch (field) {
  YorksV1InventoryControlledField.itemCode => row.itemCode,
  YorksV1InventoryControlledField.category => row.sourceCategory,
  YorksV1InventoryControlledField.description => row.description,
  YorksV1InventoryControlledField.sizeText => row.sizeText,
  YorksV1InventoryControlledField.modelTag => row.modelTag,
  YorksV1InventoryControlledField.serialNumber => row.serialNumber,
  YorksV1InventoryControlledField.brandOrigin => row.brandOrigin,
  YorksV1InventoryControlledField.ralColour => row.ralColour,
  YorksV1InventoryControlledField.reason => row.reason,
  YorksV1InventoryControlledField.minimumStock => row.minimumStock,
  YorksV1InventoryControlledField.locationShelf => row.locationBin,
  YorksV1InventoryControlledField.externalSupplierName =>
    row.supplierSourceText,
  YorksV1InventoryControlledField.supplierReference => row.supplierReference,
  YorksV1InventoryControlledField.receivedDate => row.receivedDate,
  YorksV1InventoryControlledField.notes => row.notes,
  _ => '',
};

class _ReviewRowCard extends StatelessWidget {
  const _ReviewRowCard({
    required this.language,
    required this.row,
    required this.categories,
    required this.onSelectCategory,
    required this.onCreateCategory,
    required this.onResolveSupplier,
    required this.onEdit,
  });

  final AppLanguage language;
  final YorksV1InventoryImportRow row;
  final List<YorksV1InventoryCategory> categories;
  final _CategorySelected onSelectCategory;
  final ValueChanged<String> onCreateCategory;
  final _SupplierResolved onResolveSupplier;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final tone = row.hasErrors
        ? AppColors.error
        : row.hasWarnings
        ? AppColors.warning
        : AppColors.success;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: row.hasErrors
            ? AppColors.errorContainer.withValues(alpha: 0.45)
            : row.hasWarnings
            ? AppColors.warningContainer.withValues(alpha: 0.48)
            : AppColors.surfaceContainerLowest,
        border: Border.all(color: tone.withValues(alpha: 0.26)),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final identity = _ReviewIdentity(
              language: language,
              row: row,
              onEdit: onEdit,
            );
            final facts = _ReviewFacts(language: language, row: row);
            final decisions = _ReviewDecisions(
              language: language,
              row: row,
              categories: categories,
              onSelectCategory: onSelectCategory,
              onCreateCategory: onCreateCategory,
              onResolveSupplier: onResolveSupplier,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: identity),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(flex: 3, child: facts),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(flex: 4, child: decisions),
                    ],
                  )
                else ...[
                  identity,
                  const SizedBox(height: AppSpacing.md),
                  facts,
                  if (row.requiresCategoryDecision ||
                      row.requiresSupplierDecision) ...[
                    const SizedBox(height: AppSpacing.md),
                    decisions,
                  ],
                ],
                if (row.issues.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final issue in row.issues) _IssueChip(issue: issue),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ReviewIdentity extends StatelessWidget {
  const _ReviewIdentity({
    required this.language,
    required this.row,
    required this.onEdit,
  });

  final AppLanguage language;
  final YorksV1InventoryImportRow row;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          _StatusPill(
            label:
                '${YorksV1InventoryStrings.row.active(language)} ${row.sourceRowNumber}',
            tone: row.hasErrors
                ? AppColors.error
                : row.hasWarnings
                ? AppColors.warning
                : AppColors.success,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              row.itemCode.isEmpty ? row.description : row.itemCode,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.titleSmall,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          IconButton.outlined(
            key: ValueKey('inventory-import-edit-row-${row.sourceRowNumber}'),
            tooltip: YorksV1InventoryStrings.editDetails.active(language),
            onPressed: onEdit,
            constraints: const BoxConstraints.tightFor(
              width: AppSpacing.minTapTarget,
              height: AppSpacing.minTapTarget,
            ),
            icon: const Icon(Icons.edit_outlined, size: 18),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        row.description,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.bodyMedium.copyWith(color: AppColors.ink),
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        row.sourceCategory,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.bodySmall,
      ),
    ],
  );
}

class _ReviewFacts extends StatelessWidget {
  const _ReviewFacts({required this.language, required this.row});

  final AppLanguage language;
  final YorksV1InventoryImportRow row;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _FactLine(
        icon: Icons.inventory_2_outlined,
        label:
            row.stockAction?.displayName ??
            YorksV1InventorySupplierStrings.review.active(language),
      ),
      _FactLine(
        icon: Icons.numbers_rounded,
        label:
            '${row.quantity} ${row.unit} · ${row.rawSourceType.isEmpty ? row.sourceType?.displayName ?? '' : row.rawSourceType}',
      ),
      if (row.rawSupplierName.isNotEmpty)
        _FactLine(
          icon: Icons.local_shipping_outlined,
          label:
              row.canonicalSupplierName ??
              row.newSupplierName ??
              row.rawSupplierName,
        ),
    ],
  );
}

class _ReviewDecisions extends StatelessWidget {
  const _ReviewDecisions({
    required this.language,
    required this.row,
    required this.categories,
    required this.onSelectCategory,
    required this.onCreateCategory,
    required this.onResolveSupplier,
  });

  final AppLanguage language;
  final YorksV1InventoryImportRow row;
  final List<YorksV1InventoryCategory> categories;
  final _CategorySelected onSelectCategory;
  final ValueChanged<String> onCreateCategory;
  final _SupplierResolved onResolveSupplier;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (row.requiresCategoryDecision)
        _CategoryDecisionField(
          language: language,
          row: row,
          categories: categories,
          onSelectCategory: onSelectCategory,
          onCreateCategory: onCreateCategory,
        ),
      if (row.requiresCategoryDecision && row.requiresSupplierDecision)
        const SizedBox(height: AppSpacing.sm),
      if (row.requiresSupplierDecision)
        _SupplierDecisionField(
          language: language,
          row: row,
          onResolve: onResolveSupplier,
        ),
      if (!row.requiresCategoryDecision && !row.requiresSupplierDecision)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: _StatusPill(
            label: row.hasErrors
                ? YorksV1InventoryStrings.needReview.active(language)
                : row.hasWarnings
                ? YorksV1InventoryStrings.readyWithWarnings.active(language)
                : YorksV1InventoryStrings.ready.active(language),
            tone: row.hasErrors
                ? AppColors.error
                : row.hasWarnings
                ? AppColors.warning
                : AppColors.success,
          ),
        ),
    ],
  );
}

class _CategoryDecisionField extends StatelessWidget {
  const _CategoryDecisionField({
    required this.language,
    required this.row,
    required this.categories,
    required this.onSelectCategory,
    required this.onCreateCategory,
  });

  static const _create = '__create_category__';
  final AppLanguage language;
  final YorksV1InventoryImportRow row;
  final List<YorksV1InventoryCategory> categories;
  final _CategorySelected onSelectCategory;
  final ValueChanged<String> onCreateCategory;

  @override
  Widget build(BuildContext context) {
    final active = categories.where((value) => value.isActive).toList();
    final selected = row.newCategoryName != null
        ? _create
        : active.any((category) => category.id == row.categoryId)
        ? row.categoryId
        : null;
    return DropdownButtonFormField<String>(
      key: ValueKey('category-decision-${row.sourceRowNumber}'),
      initialValue: selected,
      isExpanded: true,
      decoration: _fieldDecoration(
        labelText: YorksV1InventoryStrings.category.active(language),
      ),
      hint: Text(
        YorksV1InventoryStrings.chooseOrCreateCategory.active(language),
        overflow: TextOverflow.ellipsis,
      ),
      items: [
        for (final category in active)
          DropdownMenuItem(
            value: category.id,
            child: Text(category.displayPath, overflow: TextOverflow.ellipsis),
          ),
        DropdownMenuItem(
          value: _create,
          child: Text(
            YorksV1InventoryStrings.newCategory.active(language),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
      onChanged: (value) {
        if (value == null) return;
        if (value == _create) {
          onCreateCategory(row.sourceCategory);
          return;
        }
        onSelectCategory(sourceCategory: row.sourceCategory, categoryId: value);
      },
    );
  }
}

class _SupplierDecisionField extends StatelessWidget {
  const _SupplierDecisionField({
    required this.language,
    required this.row,
    required this.onResolve,
  });

  static const _create = '__create_supplier__';
  static const _unknown = '__unknown_supplier__';
  final AppLanguage language;
  final YorksV1InventoryImportRow row;
  final _SupplierResolved onResolve;

  @override
  Widget build(BuildContext context) {
    final suggestions = <String, YorksV1InventorySupplierMaster>{
      for (final suggestion in row.supplierSuggestions)
        suggestion.supplier.id: suggestion.supplier,
    };
    final selected = suggestions.containsKey(row.supplierId)
        ? row.supplierId
        : row.supplierResolution == YorksV1InventorySupplierResolution.createNew
        ? _create
        : row.usesUnknownSupplier
        ? _unknown
        : null;
    return DropdownButtonFormField<String>(
      key: ValueKey('supplier-decision-${row.sourceRowNumber}'),
      initialValue: selected,
      isExpanded: true,
      decoration: _fieldDecoration(
        labelText: YorksV1InventorySupplierStrings.supplierResolution.active(
          language,
        ),
      ),
      hint: Text(
        YorksV1InventorySupplierStrings.supplierResolution.active(language),
        overflow: TextOverflow.ellipsis,
      ),
      items: [
        for (final supplier in suggestions.values)
          DropdownMenuItem(
            value: supplier.id,
            child: Text(supplier.name, overflow: TextOverflow.ellipsis),
          ),
        DropdownMenuItem(
          value: _create,
          child: Text(
            YorksV1InventorySupplierStrings.addSupplier.active(language),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        DropdownMenuItem(
          value: _unknown,
          child: Text(
            YorksV1InventorySupplierStrings.unknownSupplier.active(language),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
      onChanged: (value) {
        if (value == null) return;
        if (value == _create) {
          onResolve(sourceSupplierText: row.rawSupplierName, createNew: true);
          return;
        }
        if (value == _unknown) {
          onResolve(
            sourceSupplierText: row.rawSupplierName,
            useUnknownSupplier: true,
          );
          return;
        }
        final supplier = suggestions[value];
        if (supplier != null) {
          onResolve(
            sourceSupplierText: row.rawSupplierName,
            supplierId: supplier.id,
            canonicalSupplierName: supplier.name,
          );
        }
      },
    );
  }
}

class _ReviewSummary extends StatelessWidget {
  const _ReviewSummary({
    required this.language,
    required this.preview,
    required this.busy,
    required this.onBack,
    required this.onContinue,
  });

  final AppLanguage language;
  final YorksV1InventoryImportPreview preview;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            YorksV1InventorySupplierStrings.importSummary.active(language),
            style: AppTypography.eyebrow,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('${preview.rowCount}', style: AppTypography.displaySmall),
          Text(
            YorksV1InventorySupplierStrings.totalRows.active(language),
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          _MetricPair(
            label: YorksV1InventorySupplierStrings.validRows.active(language),
            value:
                '${preview.rows.where((row) => !row.hasErrors && !row.hasWarnings).length}',
            valueColor: AppColors.success,
          ),
          _MetricPair(
            label: YorksV1InventorySupplierStrings.warnings.active(language),
            value: '${preview.warningCount}',
            valueColor: AppColors.warning,
          ),
          _MetricPair(
            label: YorksV1InventorySupplierStrings.errors.active(language),
            value: '${preview.errorCount}',
            valueColor: AppColors.error,
          ),
          const Divider(height: AppSpacing.xxl, color: AppColors.line),
          OutlinedButton.icon(
            onPressed: busy ? null : onBack,
            style: _secondaryButtonStyle(),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: Text(
              YorksV1InventorySupplierStrings.mapColumns.active(language),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            key: const ValueKey('inventory-import-review-continue'),
            onPressed: busy ? null : onContinue,
            style: _primaryButtonStyle(),
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text(
              YorksV1InventorySupplierStrings.supplierReceipt.active(language),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _TrustCallout(
            language: language,
            text: YorksV1InventorySupplierStrings.noStockBeforeConfirmation,
          ),
        ],
      ),
    ),
  );
}

class _SupplierReceiptStage extends StatelessWidget {
  const _SupplierReceiptStage({
    required this.language,
    required this.state,
    required this.suppliers,
    required this.onResolveSupplier,
    required this.onSetQuantities,
    required this.onConfirmationChanged,
    required this.onBack,
    required this.onCommit,
  });

  final AppLanguage language;
  final YorksV1InventoryImportState state;
  final List<YorksV1InventorySupplierMaster> suppliers;
  final _SupplierResolved onResolveSupplier;
  final _QuantitiesChanged onSetQuantities;
  final ValueChanged<bool> onConfirmationChanged;
  final VoidCallback onBack;
  final FutureOr<Object?> Function()? onCommit;

  @override
  Widget build(BuildContext context) {
    final preview = state.preview;
    if (preview == null) {
      return _ImportFailureBanner(language: language, onRetry: onBack);
    }
    final groups = _receiptGroups(preview.rows);
    final openingBalanceRows = preview.rows
        .where(
          (row) => row.sourceType == YorksV1InventorySourceType.openingBalance,
        )
        .length;
    final wide = MediaQuery.sizeOf(context).width >= 1060;
    final main = _Panel(
      child: Column(
        children: [
          _StageSectionHeader(
            language: language,
            step: YorksV1InventorySupplierStrings.supplierReceipt,
            title: YorksV1InventorySupplierStrings.supplierResolution,
            subtitle: YorksV1InventorySupplierStrings.receiptEvidence,
            badge: preview.errorCount == 0
                ? YorksV1InventoryStrings.ready
                : YorksV1InventoryStrings.needReview,
            badgeTone: preview.errorCount == 0
                ? AppColors.success
                : AppColors.warning,
          ),
          if (preview.rows.any((row) => row.usesUnknownSupplier))
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                0,
              ),
              child: _InlineCallout(
                icon: Icons.info_outline_rounded,
                color: AppColors.warning,
                title: YorksV1InventorySupplierStrings.unknownSupplier.active(
                  language,
                ),
                body: YorksV1InventorySupplierStrings.unknownSupplierExplanation
                    .active(language),
              ),
            ),
          if (openingBalanceRows > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                0,
              ),
              child: _OpeningBalanceNotice(
                language: language,
                rowCount: openingBalanceRows,
                asOfDate: state.openingBalanceAsOfDate,
              ),
            ),
          SizedBox(
            height: wide ? 610 : 590,
            child: groups.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Text(
                        YorksV1InventorySupplierStrings.noRecords.active(
                          language,
                        ),
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMedium,
                      ),
                    ),
                  )
                : Scrollbar(
                    child: ListView.builder(
                      key: const ValueKey('inventory-import-receipt-list'),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      itemCount: groups.length,
                      itemBuilder: (context, index) => Padding(
                        padding: EdgeInsets.only(
                          bottom: index == groups.length - 1
                              ? 0
                              : AppSpacing.sm,
                        ),
                        child: _SupplierReceiptGroupCard(
                          language: language,
                          group: groups[index],
                          suppliers: suppliers,
                          onResolveSupplier: onResolveSupplier,
                          onSetQuantities: onSetQuantities,
                        ),
                      ),
                    ),
                  ),
          ),
          if (!wide)
            _SupplierReceiptFooter(
              language: language,
              state: state,
              onConfirmationChanged: onConfirmationChanged,
              onBack: onBack,
              onCommit: onCommit,
            ),
        ],
      ),
    );
    if (!wide) return main;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: main),
        const SizedBox(width: AppSpacing.lg),
        SizedBox(
          width: 330,
          child: _SupplierReceiptSummary(
            language: language,
            state: state,
            onConfirmationChanged: onConfirmationChanged,
            onBack: onBack,
            onCommit: onCommit,
          ),
        ),
      ],
    );
  }
}

class _OpeningBalanceNotice extends StatelessWidget {
  const _OpeningBalanceNotice({
    required this.language,
    required this.rowCount,
    required this.asOfDate,
  });

  final AppLanguage language;
  final int rowCount;
  final String? asOfDate;

  @override
  Widget build(BuildContext context) => _InlineCallout(
    icon: Icons.event_available_outlined,
    color: AppColors.blue,
    title: YorksV1InventorySourceType.openingBalance.displayName,
    body:
        '$rowCount ${YorksV1InventoryStrings.rows.active(language)} · ${asOfDate ?? YorksV1InventorySupplierStrings.required.active(language)}',
  );
}

class _SupplierReceiptGroup {
  const _SupplierReceiptGroup({required this.sourceText, required this.rows});

  final String sourceText;
  final List<YorksV1InventoryImportRow> rows;

  YorksV1InventoryImportRow get lead => rows.first;
}

List<_SupplierReceiptGroup> _receiptGroups(
  List<YorksV1InventoryImportRow> rows,
) {
  final grouped = <String, List<YorksV1InventoryImportRow>>{};
  for (final row in rows) {
    if (row.sourceType != YorksV1InventorySourceType.externalSupplier) {
      continue;
    }
    final key = row.supplierSourceKey.isEmpty
        ? yorksV1UnknownSupplierId
        : row.supplierSourceKey;
    grouped.putIfAbsent(key, () => []).add(row);
  }
  return [
    for (final rows in grouped.values)
      _SupplierReceiptGroup(
        sourceText: rows.first.rawSupplierName,
        rows: List.unmodifiable(rows),
      ),
  ];
}

class _SupplierReceiptGroupCard extends StatelessWidget {
  const _SupplierReceiptGroupCard({
    required this.language,
    required this.group,
    required this.suppliers,
    required this.onResolveSupplier,
    required this.onSetQuantities,
  });

  static const _create = '__create_supplier__';
  static const _unknown = '__unknown_supplier__';
  final AppLanguage language;
  final _SupplierReceiptGroup group;
  final List<YorksV1InventorySupplierMaster> suppliers;
  final _SupplierResolved onResolveSupplier;
  final _QuantitiesChanged onSetQuantities;

  @override
  Widget build(BuildContext context) {
    final lead = group.lead;
    final available = <String, YorksV1InventorySupplierMaster>{
      for (final supplier in suppliers)
        if (supplier.isActive || supplier.isUnknownSupplier)
          supplier.id: supplier,
      for (final suggestion in lead.supplierSuggestions)
        suggestion.supplier.id: suggestion.supplier,
    };
    final selected = available.containsKey(lead.supplierId)
        ? lead.supplierId
        : lead.supplierResolution ==
              YorksV1InventorySupplierResolution.createNew
        ? _create
        : lead.usesUnknownSupplier
        ? _unknown
        : null;
    final supplierField = DropdownButtonFormField<String>(
      key: ValueKey('receipt-supplier-${lead.supplierSourceKey}'),
      initialValue: selected,
      isExpanded: true,
      decoration: _fieldDecoration(
        labelText: YorksV1InventorySupplierStrings.canonicalSupplier.active(
          language,
        ),
      ),
      items: [
        for (final supplier in available.values)
          DropdownMenuItem(
            value: supplier.id,
            child: Text(supplier.name, overflow: TextOverflow.ellipsis),
          ),
        DropdownMenuItem(
          value: _create,
          child: Text(
            YorksV1InventorySupplierStrings.addSupplier.active(language),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        DropdownMenuItem(
          value: _unknown,
          child: Text(
            YorksV1InventorySupplierStrings.unknownSupplier.active(language),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
      onChanged: (value) {
        if (value == null) return;
        if (value == _create) {
          onResolveSupplier(
            sourceSupplierText: group.sourceText,
            createNew: true,
          );
          return;
        }
        if (value == _unknown) {
          onResolveSupplier(
            sourceSupplierText: group.sourceText,
            useUnknownSupplier: true,
          );
          return;
        }
        final supplier = available[value];
        if (supplier != null) {
          onResolveSupplier(
            sourceSupplierText: group.sourceText,
            supplierId: supplier.id,
            canonicalSupplierName: supplier.name,
          );
        }
      },
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.sourceText.isEmpty
                            ? YorksV1InventorySupplierStrings.unknownSupplier
                                  .active(language)
                            : group.sourceText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.titleSmall,
                      ),
                      Text(
                        '${group.rows.length} ${YorksV1InventoryStrings.rows.active(language)}',
                        style: AppTypography.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _StatusPill(
                  label: lead.requiresSupplierDecision
                      ? YorksV1InventoryStrings.needReview.active(language)
                      : YorksV1InventoryStrings.ready.active(language),
                  tone: lead.requiresSupplierDecision
                      ? AppColors.warning
                      : AppColors.success,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            supplierField,
            const SizedBox(height: AppSpacing.md),
            for (var index = 0; index < group.rows.length; index++) ...[
              _ReceiptEvidenceRow(
                language: language,
                row: group.rows[index],
                onSetQuantities: onSetQuantities,
              ),
              if (index != group.rows.length - 1)
                const Divider(height: AppSpacing.xl, color: AppColors.line),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReceiptEvidenceRow extends StatelessWidget {
  const _ReceiptEvidenceRow({
    required this.language,
    required this.row,
    required this.onSetQuantities,
  });

  final AppLanguage language;
  final YorksV1InventoryImportRow row;
  final _QuantitiesChanged onSetQuantities;

  @override
  Widget build(BuildContext context) {
    final quantities = row.receiptQuantities;
    final compact = MediaQuery.sizeOf(context).width < 620;
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          row.itemCode.isEmpty ? row.description : row.itemCode,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelLarge,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          row.rawSupplierReference,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySmall,
        ),
        Text(row.rawReceivedDate, style: AppTypography.bodySmall),
      ],
    );
    final condition = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        _QuantityChip(
          label: YorksV1LogisticsStrings.goodQuantity.active(language),
          value: quantities.accepted,
          tone: AppColors.success,
        ),
        _QuantityChip(
          label: yorksV1ReceiptOutcomeCopy(
            YorksV1ReceiptOutcome.damaged,
          ).active(language),
          value: quantities.damaged,
          tone: AppColors.warning,
        ),
        _QuantityChip(
          label: yorksV1MaterialReturnStateCopy(
            YorksV1MaterialReturnState.rejected,
          ).active(language),
          value: quantities.rejected,
          tone: AppColors.error,
        ),
      ],
    );
    final edit = IconButton.outlined(
      key: ValueKey('receipt-quantities-${row.sourceRowNumber}'),
      onPressed: () => _editReceiptQuantities(
        context,
        language: language,
        row: row,
        onSetQuantities: onSetQuantities,
      ),
      constraints: const BoxConstraints.tightFor(
        width: AppSpacing.minTapTarget,
        height: AppSpacing.minTapTarget,
      ),
      tooltip: AppStrings.editQuantity.active(language),
      icon: const Icon(Icons.edit_outlined, size: 18),
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: identity),
              edit,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          condition,
        ],
      );
    }
    return Row(
      children: [
        Expanded(flex: 3, child: identity),
        const SizedBox(width: AppSpacing.md),
        Expanded(flex: 4, child: condition),
        const SizedBox(width: AppSpacing.md),
        edit,
      ],
    );
  }
}

class _QuantityChip extends StatelessWidget {
  const _QuantityChip({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: tone.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Text(
        '$label · $value',
        style: AppTypography.labelSmall.copyWith(color: tone),
      ),
    ),
  );
}

Future<void> _editReceiptQuantities(
  BuildContext context, {
  required AppLanguage language,
  required YorksV1InventoryImportRow row,
  required _QuantitiesChanged onSetQuantities,
}) async {
  final quantities = row.receiptQuantities;
  final accepted = TextEditingController(text: quantities.accepted);
  final damaged = TextEditingController(text: quantities.damaged);
  final rejected = TextEditingController(text: quantities.rejected);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        YorksV1InventorySupplierStrings.receiptEvidence.active(language),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DecimalField(
              controller: accepted,
              label: YorksV1LogisticsStrings.goodQuantity.active(language),
            ),
            const SizedBox(height: AppSpacing.sm),
            _DecimalField(
              controller: damaged,
              label: yorksV1ReceiptOutcomeCopy(
                YorksV1ReceiptOutcome.damaged,
              ).active(language),
            ),
            const SizedBox(height: AppSpacing.sm),
            _DecimalField(
              controller: rejected,
              label: yorksV1MaterialReturnStateCopy(
                YorksV1MaterialReturnState.rejected,
              ).active(language),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            YorksV1InventorySupplierStrings.cancelImport.active(language),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(AppStrings.saveChanges.active(language)),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    onSetQuantities(
      sourceRowNumber: row.sourceRowNumber,
      accepted: accepted.text.trim(),
      damaged: damaged.text.trim(),
      rejected: rejected.text.trim(),
    );
  }
  accepted.dispose();
  damaged.dispose();
  rejected.dispose();
}

class _DecimalField extends StatelessWidget {
  const _DecimalField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: _fieldDecoration(labelText: label),
  );
}

class _SupplierReceiptSummary extends StatelessWidget {
  const _SupplierReceiptSummary({
    required this.language,
    required this.state,
    required this.onConfirmationChanged,
    required this.onBack,
    required this.onCommit,
  });

  final AppLanguage language;
  final YorksV1InventoryImportState state;
  final ValueChanged<bool> onConfirmationChanged;
  final VoidCallback onBack;
  final FutureOr<Object?> Function()? onCommit;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: _SupplierReceiptActions(
        language: language,
        state: state,
        onConfirmationChanged: onConfirmationChanged,
        onBack: onBack,
        onCommit: onCommit,
      ),
    ),
  );
}

class _SupplierReceiptFooter extends StatelessWidget {
  const _SupplierReceiptFooter({
    required this.language,
    required this.state,
    required this.onConfirmationChanged,
    required this.onBack,
    required this.onCommit,
  });

  final AppLanguage language;
  final YorksV1InventoryImportState state;
  final ValueChanged<bool> onConfirmationChanged;
  final VoidCallback onBack;
  final FutureOr<Object?> Function()? onCommit;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.line)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: _SupplierReceiptActions(
        language: language,
        state: state,
        onConfirmationChanged: onConfirmationChanged,
        onBack: onBack,
        onCommit: onCommit,
      ),
    ),
  );
}

class _SupplierReceiptActions extends StatelessWidget {
  const _SupplierReceiptActions({
    required this.language,
    required this.state,
    required this.onConfirmationChanged,
    required this.onBack,
    required this.onCommit,
  });

  final AppLanguage language;
  final YorksV1InventoryImportState state;
  final ValueChanged<bool> onConfirmationChanged;
  final VoidCallback onBack;
  final FutureOr<Object?> Function()? onCommit;

  @override
  Widget build(BuildContext context) {
    final preview = state.preview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          YorksV1InventorySupplierStrings.importSummary.active(language),
          style: AppTypography.eyebrow,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text('${preview?.rowCount ?? 0}', style: AppTypography.displaySmall),
        Text(
          YorksV1InventorySupplierStrings.totalRows.active(language),
          style: AppTypography.bodySmall,
        ),
        const SizedBox(height: AppSpacing.lg),
        CheckboxListTile(
          key: const ValueKey('inventory-import-confirm-evidence'),
          value: state.supplierReceiptConfirmed,
          onChanged: state.isBusy
              ? null
              : (value) => onConfirmationChanged(value ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          visualDensity: VisualDensity.standard,
          title: Text(
            YorksV1InventorySupplierStrings.reviewedWarnings.active(language),
            style: AppTypography.bodySmall.copyWith(color: AppColors.ink),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: state.isBusy ? null : onBack,
          style: _secondaryButtonStyle(),
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: Text(
            YorksV1InventorySupplierStrings.reviewValidate.active(language),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton.icon(
          key: const ValueKey('inventory-import-commit'),
          onPressed:
              state.status == YorksV1InventoryImportStatus.committing ||
                  onCommit == null
              ? null
              : () async => onCommit!(),
          style: _primaryButtonStyle(),
          icon: state.status == YorksV1InventoryImportStatus.committing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.onPrimary,
                  ),
                )
              : const Icon(Icons.verified_outlined, size: 18),
          label: Text(
            YorksV1InventorySupplierStrings.confirmInventoryImport.active(
              language,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _TrustCallout(
          language: language,
          text: YorksV1InventorySupplierStrings.noStockBeforeConfirmation,
        ),
      ],
    );
  }
}

class _SummaryStage extends StatelessWidget {
  const _SummaryStage({
    required this.language,
    required this.result,
    required this.preview,
    required this.onReturn,
    required this.onOpenSupplier,
    required this.onExportResult,
    required this.onReset,
  });

  final AppLanguage language;
  final YorksV1InventoryImportResult? result;
  final YorksV1InventoryImportPreview? preview;
  final VoidCallback? onReturn;
  final ValueChanged<String>? onOpenSupplier;
  final VoidCallback onExportResult;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final authoritative = result;
    if (authoritative == null) {
      return _ImportFailureBanner(language: language, onRetry: onReset);
    }
    final supplierIds = <String>{
      for (final row in preview?.rows ?? const <YorksV1InventoryImportRow>[])
        if (row.supplierId != null &&
            row.supplierId != yorksV1UnknownSupplierId)
          row.supplierId!,
    };
    final metrics = [
      (
        YorksV1InventorySupplierStrings.totalRows.active(language),
        authoritative.rowCount,
        AppColors.blue,
      ),
      (
        YorksV1InventorySupplierStrings.createdItems.active(language),
        authoritative.createdItems,
        AppColors.success,
      ),
      (
        YorksV1InventorySupplierStrings.updatedItems.active(language),
        authoritative.updatedItems,
        AppColors.purple,
      ),
      (
        YorksV1InventorySupplierStrings.createdCategories.active(language),
        authoritative.createdCategories,
        AppColors.warning,
      ),
      (
        YorksV1InventorySupplierStrings.activeSuppliers.active(language),
        authoritative.createdSuppliers,
        AppColors.success,
      ),
      (
        YorksV1InventorySupplierStrings.receiptBatches.active(language),
        authoritative.receiptBatches,
        AppColors.blue,
      ),
      (
        YorksV1InventoryStrings.movements.active(language),
        authoritative.movements,
        AppColors.purple,
      ),
      (
        YorksV1InventorySupplierStrings.warnings.active(language),
        authoritative.warningCount,
        AppColors.warning,
      ),
      if (authoritative.excludedCount > 0)
        (
          YorksV1InventoryStrings.needReview.active(language),
          authoritative.excludedCount,
          AppColors.error,
        ),
      if (authoritative.unknownSupplierRows > 0)
        (
          YorksV1InventorySupplierStrings.unknownSupplier.active(language),
          authoritative.unknownSupplierRows,
          AppColors.warning,
        ),
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: _Panel(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: AppColors.successContainer,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 38,
                      color: AppColors.success,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  YorksV1InventorySupplierStrings.importCommitted.active(
                    language,
                  ),
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  YorksV1InventorySupplierStrings.authoritativeSummary.active(
                    language,
                  ),
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.xxl),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 620 ? 4 : 2;
                    final width =
                        (constraints.maxWidth - AppSpacing.sm * (columns - 1)) /
                        columns;
                    return Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final metric in metrics)
                          SizedBox(
                            width: width,
                            child: _MetricCard(
                              label: metric.$1,
                              value: '${metric.$2}',
                              valueColor: metric.$3,
                            ),
                          ),
                      ],
                    );
                  },
                ),
                if (authoritative.unitTotals.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    YorksV1InventorySupplierStrings.quantityReceived.active(
                      language,
                    ),
                    style: AppTypography.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _ImportUnitTotals(
                    language: language,
                    totals: authoritative.unitTotals,
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                _TrustCallout(
                  language: language,
                  text: YorksV1InventorySupplierStrings.authoritativeSummary,
                ),
                const SizedBox(height: AppSpacing.xl),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final buttons = <Widget>[
                      OutlinedButton.icon(
                        key: const ValueKey('inventory-import-export-result'),
                        onPressed: onExportResult,
                        style: _secondaryButtonStyle(),
                        icon: const Icon(
                          Icons.download_done_outlined,
                          size: 18,
                        ),
                        label: Text(
                          YorksV1InventorySupplierStrings.authoritativeSummary
                              .active(language),
                        ),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('inventory-import-new-import'),
                        onPressed: onReset,
                        style: _secondaryButtonStyle(),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(
                          YorksV1InventorySupplierStrings.importReceipt.active(
                            language,
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        key: const ValueKey('inventory-import-return'),
                        onPressed: onReturn,
                        style: _primaryButtonStyle(),
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: Text(
                          YorksV1InventorySupplierStrings.returnToSuppliers
                              .active(language),
                        ),
                      ),
                      if (supplierIds.length == 1 && onOpenSupplier != null)
                        OutlinedButton.icon(
                          onPressed: () => onOpenSupplier!(supplierIds.single),
                          style: _secondaryButtonStyle(),
                          icon: const Icon(
                            Icons.folder_open_outlined,
                            size: 18,
                          ),
                          label: Text(
                            YorksV1InventorySupplierStrings.openFolder.active(
                              language,
                            ),
                          ),
                        ),
                    ];
                    if (constraints.maxWidth < 580) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (
                            var index = 0;
                            index < buttons.length;
                            index++
                          ) ...[
                            buttons[index],
                            if (index != buttons.length - 1)
                              const SizedBox(height: AppSpacing.sm),
                          ],
                        ],
                      );
                    }
                    return Wrap(
                      alignment: WrapAlignment.center,
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: buttons,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImportUnitTotals extends StatelessWidget {
  const _ImportUnitTotals({required this.language, required this.totals});

  final AppLanguage language;
  final List<YorksV1InventoryImportUnitTotal> totals;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 620 ? 2 : 1;
      final width =
          (constraints.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final total in totals)
            SizedBox(
              width: width,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  border: Border.all(color: AppColors.line),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(total.unit, style: AppTypography.titleSmall),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [
                          _QuantityChip(
                            label: YorksV1LogisticsStrings.goodQuantity.active(
                              language,
                            ),
                            value: total.acceptedQuantity,
                            tone: AppColors.success,
                          ),
                          _QuantityChip(
                            label: yorksV1ReceiptOutcomeCopy(
                              YorksV1ReceiptOutcome.damaged,
                            ).active(language),
                            value: total.damagedQuantity,
                            tone: AppColors.warning,
                          ),
                          _QuantityChip(
                            label: yorksV1MaterialReturnStateCopy(
                              YorksV1MaterialReturnState.rejected,
                            ).active(language),
                            value: total.rejectedQuantity,
                            tone: AppColors.error,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceContainerLowest,
    elevation: 1,
    shadowColor: AppColors.shadow,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
    ),
    child: child,
  );
}

class _SquareIcon extends StatelessWidget {
  const _SquareIcon({
    required this.icon,
    required this.color,
    required this.background,
    this.size = 52,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Icon(icon, color: color, size: size * 0.46),
  );
}

class _StageSectionHeader extends StatelessWidget {
  const _StageSectionHeader({
    required this.language,
    required this.step,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeTone,
  });

  final AppLanguage language;
  final TranslatableString step;
  final TranslatableString title;
  final TranslatableString subtitle;
  final TranslatableString badge;
  final Color badgeTone;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(step.active(language), style: AppTypography.eyebrow),
              const SizedBox(height: AppSpacing.xs),
              Text(title.active(language), style: AppTypography.headlineSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(subtitle.active(language), style: AppTypography.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _StatusPill(label: badge.active(language), tone: badgeTone),
      ],
    ),
  );
}

class _StageFooter extends StatelessWidget {
  const _StageFooter({
    required this.language,
    required this.onBack,
    required this.onContinue,
    required this.continueLabel,
    required this.busy,
  });

  final AppLanguage language;
  final VoidCallback onBack;
  final VoidCallback? onContinue;
  final TranslatableString continueLabel;
  final bool busy;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.line)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final back = OutlinedButton.icon(
            onPressed: busy ? null : onBack,
            style: _secondaryButtonStyle(),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: Text(YorksV1InventorySupplierStrings.back.active(language)),
          );
          final next = FilledButton.icon(
            key: const ValueKey('inventory-import-stage-continue'),
            onPressed: busy ? null : onContinue,
            style: _primaryButtonStyle(),
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text(continueLabel.active(language)),
          );
          if (constraints.maxWidth < 480) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                next,
                const SizedBox(height: AppSpacing.sm),
                back,
              ],
            );
          }
          return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              back,
              const SizedBox(width: AppSpacing.sm),
              next,
            ],
          );
        },
      ),
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: tone.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelSmall.copyWith(color: tone),
      ),
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: AppTypography.headlineSmall.copyWith(color: valueColor),
          ),
        ],
      ),
    ),
  );
}

class _MetricPair extends StatelessWidget {
  const _MetricPair({
    required this.label,
    required this.value,
    this.valueColor = AppColors.ink,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Row(
      children: [
        Expanded(child: Text(label, style: AppTypography.bodySmall)),
        const SizedBox(width: AppSpacing.sm),
        Text(
          value,
          style: AppTypography.titleSmall.copyWith(color: valueColor),
        ),
      ],
    ),
  );
}

class _TrustCallout extends StatelessWidget {
  const _TrustCallout({required this.language, required this.text});

  final AppLanguage language;
  final TranslatableString text;

  @override
  Widget build(BuildContext context) => _InlineCallout(
    icon: Icons.verified_user_outlined,
    color: AppColors.blue,
    title: YorksV1InventorySupplierStrings.strictByDefault.active(language),
    body: text.active(language),
  );
}

class _InlineCallout extends StatelessWidget {
  const _InlineCallout({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07),
      border: Border.all(color: color.withValues(alpha: 0.22)),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.labelLarge.copyWith(color: color),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(body, style: AppTypography.bodySmall),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _FactLine extends StatelessWidget {
  const _FactLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: AppColors.muted),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall,
          ),
        ),
      ],
    ),
  );
}

class _IssueChip extends StatelessWidget {
  const _IssueChip({required this.issue});

  final YorksV1InventoryImportIssue issue;

  @override
  Widget build(BuildContext context) {
    final tone = issue.isWarning ? AppColors.warning : AppColors.error;
    final detail = issue.detail?.trim();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          detail == null || detail.isEmpty
              ? _humanize(issue.code.name)
              : detail,
          style: AppTypography.labelSmall.copyWith(color: tone),
        ),
      ),
    );
  }
}

class _ImportFailureBanner extends StatelessWidget {
  const _ImportFailureBanner({
    required this.language,
    required this.onRetry,
    this.uncertain = false,
  });
  final bool uncertain;

  final AppLanguage language;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _InlineCallout(
        icon: Icons.error_outline_rounded,
        color: AppColors.error,
        title: YorksV1InventorySupplierStrings.importFailed.active(language),
        body:
            (uncertain
                    ? YorksV1InventoryStrings.uncertainSave
                    : YorksV1InventoryStrings.savingFailed)
                .active(language),
      ),
      if (onRetry != null) ...[
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: OutlinedButton.icon(
            onPressed: onRetry,
            style: _secondaryButtonStyle(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(
              YorksV1InventorySupplierStrings.tryAgain.active(language),
            ),
          ),
        ),
      ],
    ],
  );
}

class _ImportDependencyError extends StatelessWidget {
  const _ImportDependencyError({
    required this.language,
    required this.onRetry,
    this.message,
    this.retryKey,
  });

  final AppLanguage language;
  final VoidCallback onRetry;
  final String? message;
  final Key? retryKey;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.surface,
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              color: AppColors.muted,
              size: 44,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              message ??
                  YorksV1InventorySupplierStrings.loadFailed.active(language),
              textAlign: TextAlign.center,
              style: AppTypography.titleMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              key: retryKey,
              onPressed: onRetry,
              style: _primaryButtonStyle(),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                YorksV1InventorySupplierStrings.tryAgain.active(language),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ImportLoadingSurface extends StatelessWidget {
  const _ImportLoadingSurface();

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: AppColors.surface,
    body: Center(
      child: SizedBox.square(
        dimension: 32,
        child: CircularProgressIndicator(strokeWidth: 3),
      ),
    ),
  );
}

class _RestrictedImportSurface extends StatelessWidget {
  const _RestrictedImportSurface({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.surface,
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.shield_outlined, size: 44, color: AppColors.muted),
          const SizedBox(height: AppSpacing.md),
          Text(
            AppStrings.restrictedLabel.active(language),
            style: AppTypography.titleMedium,
          ),
        ],
      ),
    ),
  );
}

InputDecoration _fieldDecoration({
  String? labelText,
  String? hintText,
  Widget? prefixIcon,
}) => InputDecoration(
  labelText: labelText,
  hintText: hintText,
  prefixIcon: prefixIcon,
  isDense: true,
  constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
  filled: true,
  fillColor: AppColors.surfaceContainerLowest,
  contentPadding: const EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: AppSpacing.md,
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    borderSide: const BorderSide(color: AppColors.lineStrong),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    borderSide: const BorderSide(color: AppColors.blue, width: 1.5),
  ),
  errorBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    borderSide: const BorderSide(color: AppColors.error),
  ),
);

ButtonStyle _primaryButtonStyle() => FilledButton.styleFrom(
  minimumSize: const Size(44, AppSpacing.minTapTarget),
  backgroundColor: AppColors.navy,
  foregroundColor: AppColors.onPrimary,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
  ),
);

ButtonStyle _secondaryButtonStyle() => OutlinedButton.styleFrom(
  minimumSize: const Size(44, AppSpacing.minTapTarget),
  foregroundColor: AppColors.ink,
  side: const BorderSide(color: AppColors.lineStrong),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
  ),
);

String _stageLabel(YorksV1InventoryImportStage stage, AppLanguage language) =>
    switch (stage) {
      YorksV1InventoryImportStage.uploadFile =>
        YorksV1InventorySupplierStrings.uploadFile.active(language),
      YorksV1InventoryImportStage.mapColumns =>
        YorksV1InventorySupplierStrings.mapColumns.active(language),
      YorksV1InventoryImportStage.reviewValidate =>
        YorksV1InventorySupplierStrings.reviewValidate.active(language),
      YorksV1InventoryImportStage.supplierReceipt =>
        YorksV1InventorySupplierStrings.supplierReceipt.active(language),
      YorksV1InventoryImportStage.importSummary =>
        YorksV1InventorySupplierStrings.importSummary.active(language),
    };

String _reviewFilterLabel(_ReviewFilter filter, AppLanguage language) =>
    switch (filter) {
      _ReviewFilter.all => AppStrings.allItems.active(language),
      _ReviewFilter.valid => YorksV1InventorySupplierStrings.validRows.active(
        language,
      ),
      _ReviewFilter.warnings => YorksV1InventorySupplierStrings.warnings.active(
        language,
      ),
      _ReviewFilter.errors => YorksV1InventorySupplierStrings.errors.active(
        language,
      ),
      _ReviewFilter.existing =>
        YorksV1InventorySupplierStrings.existingItems.active(language),
    };

String _humanize(String value) {
  final spaced = value.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  if (spaced.isEmpty) return spaced;
  return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}

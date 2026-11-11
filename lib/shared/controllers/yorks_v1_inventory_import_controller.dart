import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/yorks_v1_domain_error.dart';
import '../models/yorks_v1_inventory_workbook.dart';
import '../models/yorks_v1_logistics.dart';
import '../repositories/yorks_v1_logistics_repository.dart';
import '../services/yorks_v1_inventory_workbook_service.dart';

/// Retained for the R38.3 screen while [YorksV1InventoryImportStage] is the
/// authoritative five-stage workflow state.
enum YorksV1InventoryImportStatus {
  idle,
  selecting,
  preview,
  committing,
  succeeded,
  failed,
}

typedef YorksV1R389InventoryCommit =
    Future<YorksV1InventoryImportResult> Function({
      required Map<String, Object?> payload,
      required String idempotencyKey,
    });

class YorksV1InventoryImportState {
  const YorksV1InventoryImportState({
    this.status = YorksV1InventoryImportStatus.idle,
    this.stage = YorksV1InventoryImportStage.uploadFile,
    this.source,
    this.mapping,
    this.preview,
    this.result,
    this.errorCode,
    this.supplierReceiptConfirmed = false,
    this.openingBalanceAsOfDate,
  });

  final YorksV1InventoryImportStatus status;
  final YorksV1InventoryImportStage stage;
  final YorksV1InventoryWorkbookSource? source;
  final YorksV1InventoryColumnMapping? mapping;
  final YorksV1InventoryImportPreview? preview;
  final YorksV1InventoryImportResult? result;
  final YorksV1DomainErrorCode? errorCode;
  final bool supplierReceiptConfirmed;
  final String? openingBalanceAsOfDate;

  bool get hasUnconfirmedCommit =>
      stage == YorksV1InventoryImportStage.supplierReceipt &&
      supplierReceiptConfirmed &&
      status == YorksV1InventoryImportStatus.failed &&
      {
        YorksV1DomainErrorCode.backendUnavailable,
        YorksV1DomainErrorCode.unexpectedResponse,
        YorksV1DomainErrorCode.offline,
      }.contains(errorCode);

  bool get isBusy =>
      hasUnconfirmedCommit ||
      status == YorksV1InventoryImportStatus.selecting ||
      status == YorksV1InventoryImportStatus.committing;

  bool get requiresOpeningBalanceAsOfDate =>
      preview?.requiresOpeningBalanceAsOfDate == true;
  bool get treatsWorkbookAsOpeningBalance =>
      mapping?.treatWorkbookAsOpeningBalance == true;
  bool get canTreatWorkbookAsOpeningBalance =>
      mapping != null &&
      !mapping!.indexes.containsKey(
        YorksV1InventoryControlledField.sourceType,
      ) &&
      !(preview?.hasOpeningBalanceRows ?? false);
  List<YorksV1InventoryUnitReviewGroup> get unresolvedUnitGroups =>
      preview?.unresolvedUnitGroups ?? const [];
  bool get hasValidOpeningBalanceAsOfDate =>
      !requiresOpeningBalanceAsOfDate ||
      yorksV1InventoryIsIsoDate(openingBalanceAsOfDate);
  bool get canContinueMapping => mapping?.canContinue == true && !isBusy;
  bool get canContinueReview =>
      preview?.canCommit == true && hasValidOpeningBalanceAsOfDate && !isBusy;
  bool get canCommit =>
      stage == YorksV1InventoryImportStage.supplierReceipt &&
      supplierReceiptConfirmed &&
      preview?.canCommit == true &&
      hasValidOpeningBalanceAsOfDate &&
      (!isBusy || hasUnconfirmedCommit);
}

class YorksV1InventoryImportController
    extends StateNotifier<YorksV1InventoryImportState> {
  YorksV1InventoryImportController({
    required YorksV1LogisticsRepository repository,
    required YorksV1InventoryWorkbookFileService fileService,
    YorksV1InventoryWorkbookCodec? codec,
    YorksV1R389InventoryCommit? r38_9Commit,
    String Function()? uuidFactory,
    this.persistPending,
    this.canExecute,
  }) : _repository = repository,
       _fileService = fileService,
       _codec = codec ?? const YorksV1InventoryWorkbookCodec(),
       _canOffloadPreparation = codec == null,
       _r38_9Commit = r38_9Commit,
       _uuidFactory = uuidFactory ?? const Uuid().v4,
       super(const YorksV1InventoryImportState());

  final YorksV1LogisticsRepository _repository;
  final YorksV1InventoryWorkbookFileService _fileService;
  final YorksV1InventoryWorkbookCodec _codec;
  final bool _canOffloadPreparation;
  final YorksV1R389InventoryCommit? _r38_9Commit;
  final String Function() _uuidFactory;
  final Future<void> Function(Map<String, Object?>?)? persistPending;
  final bool Function()? canExecute;
  String? _idempotencyKey;
  YorksV1InventoryWorkspace? _workspace;
  List<YorksV1InventorySupplierMaster> _suppliers = const [];
  YorksV1InventoryColumnMapping? _mappingBeforeSafeFixes;

  bool get canUndoSafeFixes =>
      _mappingBeforeSafeFixes != null &&
      state.stage == YorksV1InventoryImportStage.reviewValidate &&
      !state.isBusy;

  Future<void> chooseFile(
    YorksV1InventoryWorkspace workspace, {
    List<YorksV1InventorySupplierMaster> suppliers = const [],
  }) async {
    if (state.isBusy) return;
    final previous = state;
    state = YorksV1InventoryImportState(
      status: YorksV1InventoryImportStatus.selecting,
      stage: previous.stage,
      source: previous.source,
      mapping: previous.mapping,
      preview: previous.preview,
      result: previous.result,
      supplierReceiptConfirmed: previous.supplierReceiptConfirmed,
      openingBalanceAsOfDate: previous.openingBalanceAsOfDate,
    );
    try {
      final selected = await _fileService.selectWorkbook();
      if (selected == null) {
        state = previous;
        return;
      }
      await prepareSelectedAsync(selected, workspace, suppliers: suppliers);
    } on YorksV1DomainException catch (error) {
      _setFailure(error.code);
    } catch (_) {
      _setFailure(YorksV1DomainErrorCode.invalidInput);
    }
  }

  void prepareSelected(
    YorksV1InventorySelectedWorkbook selected,
    YorksV1InventoryWorkspace workspace, {
    List<YorksV1InventorySupplierMaster> suppliers = const [],
  }) {
    final source = _codec.read(selected);
    final mapping = _codec.proposeMapping(
      source,
      requireR38_9Fields: _requiresR38_9Fields(source),
    );
    _workspace = workspace;
    _suppliers = List.unmodifiable(suppliers);
    _idempotencyKey = _uuidFactory();
    state = YorksV1InventoryImportState(
      status: YorksV1InventoryImportStatus.preview,
      stage: YorksV1InventoryImportStage.mapColumns,
      source: source,
      mapping: mapping,
      preview: mapping.canContinue ? _buildPreview(mapping) : null,
    );
  }

  /// Parses and validates a selected workbook outside the native UI isolate.
  /// Flutter web uses the platform compute implementation; the indexed codec
  /// keeps repeated category/supplier/item resolution linear and deterministic.
  Future<bool> prepareSelectedAsync(
    YorksV1InventorySelectedWorkbook selected,
    YorksV1InventoryWorkspace workspace, {
    List<YorksV1InventorySupplierMaster> suppliers = const [],
  }) async {
    state = const YorksV1InventoryImportState(
      status: YorksV1InventoryImportStatus.selecting,
      stage: YorksV1InventoryImportStage.uploadFile,
    );
    try {
      final preparation = _canOffloadPreparation
          ? await compute(
              _prepareInventoryImport,
              _InventoryPreparationRequest(
                selected: selected,
                workspace: workspace,
                suppliers: suppliers,
                forceR38_9: _r38_9Commit != null,
              ),
            )
          : _prepareInventoryImportWithCodec(
              codec: _codec,
              selected: selected,
              workspace: workspace,
              suppliers: suppliers,
              forceR38_9: _r38_9Commit != null,
            );
      if (!mounted) return false;
      _workspace = workspace;
      _suppliers = List.unmodifiable(suppliers);
      _idempotencyKey = _uuidFactory();
      state = YorksV1InventoryImportState(
        status: YorksV1InventoryImportStatus.preview,
        stage: YorksV1InventoryImportStage.mapColumns,
        source: preparation.source,
        mapping: preparation.mapping,
        preview: preparation.preview,
      );
      return true;
    } on YorksV1DomainException catch (error) {
      if (mounted) _setFailure(error.code);
    } catch (_) {
      if (mounted) _setFailure(YorksV1DomainErrorCode.invalidInput);
    }
    return false;
  }

  /// Inspects an Excel workbook before parsing so an ambiguous multi-sheet
  /// file can require an explicit operator choice. The official controlled
  /// worksheet remains auto-selected by the codec during preparation.
  Future<List<String>> availableWorksheetNames(
    YorksV1InventorySelectedWorkbook selected,
  ) async => [
    for (final option in await availableWorksheets(selected)) option.name,
  ];

  Future<List<YorksV1InventoryWorksheetOption>> availableWorksheets(
    YorksV1InventorySelectedWorkbook selected,
  ) async {
    if (_canOffloadPreparation) {
      return compute(_inspectInventoryWorksheets, selected);
    }
    return _codec.availableWorksheets(selected);
  }

  void updateMapping({
    required YorksV1InventoryControlledField field,
    required int? sourceColumnIndex,
  }) {
    final mapping = state.mapping;
    if (mapping == null || state.isBusy) return;
    final next = _codec.updateMapping(
      mapping: mapping,
      field: field,
      sourceColumnIndex: sourceColumnIndex,
      requireR38_9Fields: _requiresR38_9Fields(mapping.source),
    );
    state = YorksV1InventoryImportState(
      status: YorksV1InventoryImportStatus.preview,
      stage: YorksV1InventoryImportStage.mapColumns,
      source: state.source,
      mapping: next,
      preview: next.canContinue ? _buildPreview(next) : null,
      openingBalanceAsOfDate: state.openingBalanceAsOfDate,
    );
  }

  /// Explicitly treats a source-type-less workbook as an Opening Balance run.
  /// This is a reviewed Stage 2 decision and is never inferred from its name.
  void setTreatWorkbookAsOpeningBalance(bool enabled) {
    final mapping = state.mapping;
    if (mapping == null ||
        state.stage != YorksV1InventoryImportStage.mapColumns ||
        state.isBusy) {
      return;
    }
    final next = _codec.applyOpeningBalanceDefault(
      mapping: mapping,
      enabled: enabled,
      requireR38_9Fields: _requiresR38_9Fields(mapping.source),
    );
    state = YorksV1InventoryImportState(
      status: YorksV1InventoryImportStatus.preview,
      stage: YorksV1InventoryImportStage.mapColumns,
      source: state.source,
      mapping: next,
      preview: next.canContinue ? _buildPreview(next) : null,
    );
  }

  bool confirmMapping() {
    final mapping = state.mapping;
    if (mapping == null || !mapping.canContinue || state.isBusy) return false;
    final preview = _buildPreview(mapping);
    state = YorksV1InventoryImportState(
      status: YorksV1InventoryImportStatus.preview,
      stage: YorksV1InventoryImportStage.reviewValidate,
      source: state.source,
      mapping: mapping,
      preview: preview,
      openingBalanceAsOfDate: state.openingBalanceAsOfDate,
    );
    return true;
  }

  void selectExistingCategory({
    required String sourceCategory,
    required String categoryId,
  }) {
    final preview = state.preview;
    if (preview == null || state.isBusy) return;
    _replacePreview(
      _codec.applyCategoryDecision(
        preview: preview,
        sourceCategory: sourceCategory,
        categoryId: categoryId,
      ),
    );
  }

  void createNewCategory(String sourceCategory) {
    final preview = state.preview;
    if (preview == null || state.isBusy) return;
    _replacePreview(
      _codec.applyCategoryDecision(
        preview: preview,
        sourceCategory: sourceCategory,
        createNew: true,
      ),
    );
  }

  void resolveSupplier({
    required String sourceSupplierText,
    String? supplierId,
    String? canonicalSupplierName,
    bool createNew = false,
    bool useUnknownSupplier = false,
  }) {
    final preview = state.preview;
    if (preview == null || state.isBusy) return;
    _replacePreview(
      _codec.applySupplierDecision(
        preview: preview,
        sourceSupplierText: sourceSupplierText,
        supplierId: supplierId,
        canonicalSupplierName: canonicalSupplierName,
        createNew: createNew,
        useUnknownSupplier: useUnknownSupplier,
      ),
    );
  }

  void setReceiptQuantities({
    required int sourceRowNumber,
    required String accepted,
    required String damaged,
    required String rejected,
  }) {
    final preview = state.preview;
    if (preview == null || state.isBusy) return;
    _replacePreview(
      _codec.applyReceiptQuantities(
        preview: preview,
        sourceRowNumber: sourceRowNumber,
        accepted: accepted,
        damaged: damaged,
        rejected: rejected,
      ),
    );
  }

  /// Maps every equivalent source unit to one reviewed controlled unit.
  void resolveUnit({
    required String sourceUnitText,
    required String controlledUnit,
  }) {
    final mapping = state.mapping;
    if (mapping == null || state.preview == null || state.isBusy) return;
    final next = _codec.applyUnitMapping(
      mapping: mapping,
      sourceUnitText: sourceUnitText,
      controlledUnit: controlledUnit,
    );
    _replaceMappingAndPreview(next);
  }

  void clearUnitResolution(String sourceUnitText) {
    final mapping = state.mapping;
    if (mapping == null || state.preview == null || state.isBusy) return;
    final next = _codec.clearUnitMapping(
      mapping: mapping,
      sourceUnitText: sourceUnitText,
    );
    _replaceMappingAndPreview(next);
  }

  /// Corrects one quantity-neutral review cell and immediately revalidates the
  /// entire preview. Quantity, action, source type, unit and price fields are
  /// deliberately rejected by the codec.
  bool editReviewCell({
    required int sourceRowNumber,
    required YorksV1InventoryControlledField field,
    required String value,
  }) {
    final mapping = state.mapping;
    if (mapping == null ||
        state.stage != YorksV1InventoryImportStage.reviewValidate ||
        state.isBusy) {
      return false;
    }
    final next = _codec.applyCellEdit(
      mapping: mapping,
      sourceRowNumber: sourceRowNumber,
      field: field,
      value: value,
    );
    _mappingBeforeSafeFixes = null;
    _replaceMappingAndPreview(next);
    return true;
  }

  /// Replaces exact whole-cell values in one reviewed quantity-neutral field.
  /// Returns the number of source rows affected.
  int searchAndReplaceReviewCells({
    required YorksV1InventoryControlledField field,
    required String sourceText,
    required String replacementText,
  }) {
    final mapping = state.mapping;
    if (mapping == null ||
        state.stage != YorksV1InventoryImportStage.reviewValidate ||
        state.isBusy) {
      return 0;
    }
    final result = _codec.applyExactSearchAndReplace(
      mapping: mapping,
      field: field,
      sourceText: sourceText,
      replacementText: replacementText,
    );
    if (result.affectedRows == 0) return 0;
    _mappingBeforeSafeFixes = null;
    _replaceMappingAndPreview(result.mapping);
    return result.affectedRows;
  }

  /// Applies the idempotent whitespace/control-character cleanup. The prior
  /// mapping remains available for one explicit undo operation.
  int applySafeFixes() {
    final mapping = state.mapping;
    if (mapping == null ||
        state.stage != YorksV1InventoryImportStage.reviewValidate ||
        state.isBusy) {
      return 0;
    }
    final result = _codec.applySafeFixes(mapping);
    if (result.affectedRows == 0) return 0;
    _mappingBeforeSafeFixes = mapping;
    _replaceMappingAndPreview(result.mapping);
    return result.affectedRows;
  }

  bool undoSafeFixes() {
    final mapping = _mappingBeforeSafeFixes;
    if (mapping == null ||
        state.stage != YorksV1InventoryImportStage.reviewValidate ||
        state.isBusy) {
      return false;
    }
    _mappingBeforeSafeFixes = null;
    _replaceMappingAndPreview(mapping);
    return true;
  }

  Future<bool> exportIssuesWorkbook() async {
    final preview = state.preview;
    final exporter = _fileService;
    if (preview == null ||
        exporter is! YorksV1InventoryImportEvidenceFileService ||
        state.isBusy) {
      return false;
    }
    return (exporter as YorksV1InventoryImportEvidenceFileService)
        .saveImportIssues(preview: preview);
  }

  Future<bool> exportCleanedPreviewWorkbook() async {
    final preview = state.preview;
    final exporter = _fileService;
    if (preview == null ||
        exporter is! YorksV1InventoryImportEvidenceFileService ||
        state.isBusy) {
      return false;
    }
    return (exporter as YorksV1InventoryImportEvidenceFileService)
        .saveCleanedImportPreview(preview: preview);
  }

  Future<bool> exportResultWorkbook() async {
    final preview = state.preview;
    final result = state.result;
    final exporter = _fileService;
    if (preview == null ||
        result == null ||
        state.stage != YorksV1InventoryImportStage.importSummary ||
        exporter is! YorksV1InventoryImportEvidenceFileService ||
        state.isBusy) {
      return false;
    }
    return (exporter as YorksV1InventoryImportEvidenceFileService)
        .saveImportResult(preview: preview, result: result);
  }

  /// Sets the explicit stock-position date for Opening Balance rows. The date
  /// is never inferred from the device clock and must be an ISO date
  /// (`YYYY-MM-DD`) before the workflow can enter Supplier & Receipt.
  void setOpeningBalanceAsOfDate(String? value) {
    if (state.isBusy || state.preview == null) return;
    final normalized = value?.trim();
    state = YorksV1InventoryImportState(
      status: YorksV1InventoryImportStatus.preview,
      stage: state.stage,
      source: state.source,
      mapping: state.mapping,
      preview: state.preview,
      result: state.result,
      openingBalanceAsOfDate: normalized == null || normalized.isEmpty
          ? null
          : normalized,
    );
  }

  bool continueToSupplierReceipt() {
    final preview = state.preview;
    if (state.stage != YorksV1InventoryImportStage.reviewValidate ||
        preview == null ||
        !state.canContinueReview ||
        state.isBusy) {
      return false;
    }
    state = YorksV1InventoryImportState(
      status: YorksV1InventoryImportStatus.preview,
      stage: YorksV1InventoryImportStage.supplierReceipt,
      source: state.source,
      mapping: state.mapping,
      preview: preview,
      openingBalanceAsOfDate: state.openingBalanceAsOfDate,
    );
    return true;
  }

  void confirmSupplierAndReceipt({bool confirmed = true}) {
    if (state.stage != YorksV1InventoryImportStage.supplierReceipt ||
        state.isBusy ||
        !state.hasValidOpeningBalanceAsOfDate) {
      return;
    }
    state = YorksV1InventoryImportState(
      status: YorksV1InventoryImportStatus.preview,
      stage: state.stage,
      source: state.source,
      mapping: state.mapping,
      preview: state.preview,
      supplierReceiptConfirmed: confirmed,
      openingBalanceAsOfDate: state.openingBalanceAsOfDate,
    );
  }

  void previousStage() {
    if (state.isBusy) return;
    switch (state.stage) {
      case YorksV1InventoryImportStage.uploadFile:
        return;
      case YorksV1InventoryImportStage.mapColumns:
        reset();
        return;
      case YorksV1InventoryImportStage.reviewValidate:
        _moveTo(YorksV1InventoryImportStage.mapColumns);
        return;
      case YorksV1InventoryImportStage.supplierReceipt:
        _moveTo(YorksV1InventoryImportStage.reviewValidate);
        return;
      case YorksV1InventoryImportStage.importSummary:
        return;
    }
  }

  Future<YorksV1InventoryImportResult?> commit() async {
    final preview = state.preview;
    final idempotencyKey = _idempotencyKey;
    if (!state.canCommit || preview == null || idempotencyKey == null) {
      return null;
    }
    state = YorksV1InventoryImportState(
      status: YorksV1InventoryImportStatus.committing,
      stage: YorksV1InventoryImportStage.supplierReceipt,
      source: state.source,
      mapping: state.mapping,
      preview: preview,
      supplierReceiptConfirmed: true,
      openingBalanceAsOfDate: state.openingBalanceAsOfDate,
    );
    try {
      final supplierImport =
          _r38_9Commit != null &&
          preview.rows.every((row) => row.isReceiptAction);
      if (persistPending != null) {
        await persistPending!({
          'key': idempotencyKey,
          'supplier': supplierImport,
          'payload': supplierImport
              ? preview.toR38_9RpcPayload(
                  openingBalanceAsOfDate: state.openingBalanceAsOfDate,
                )
              : YorksV1InventoryImportInput(
                  fileName: preview.fileName,
                  rows: [for (final row in preview.rows) row.toRpcInput()],
                  idempotencyKey: idempotencyKey,
                ).toRpcPayload(),
        });
      }
      if (canExecute != null && !canExecute!()) {
        throw StateError('Authority changed');
      }
      // Supplier receipts use the provenance-aware command. Controlled stock
      // corrections, removals and metadata-only imports deliberately use the
      // established adjustment import command instead: they do not fabricate
      // a supplier receipt or receipt condition record.
      final result =
          _r38_9Commit != null &&
              preview.rows.every((row) => row.isReceiptAction)
          ? await _r38_9Commit(
              payload: preview.toR38_9RpcPayload(
                openingBalanceAsOfDate: state.openingBalanceAsOfDate,
              ),
              idempotencyKey: idempotencyKey,
            )
          : await _repository.importInventory(
              YorksV1InventoryImportInput(
                fileName: preview.fileName,
                rows: [for (final row in preview.rows) row.toRpcInput()],
                idempotencyKey: idempotencyKey,
              ),
            );
      if (persistPending != null) await persistPending!(null);
      if (!mounted) return result;
      state = YorksV1InventoryImportState(
        status: YorksV1InventoryImportStatus.succeeded,
        stage: YorksV1InventoryImportStage.importSummary,
        source: state.source,
        mapping: state.mapping,
        preview: preview,
        result: result,
        supplierReceiptConfirmed: true,
        openingBalanceAsOfDate: state.openingBalanceAsOfDate,
      );
      return result;
    } on YorksV1DomainException catch (error) {
      if (persistPending != null &&
          !{
            YorksV1DomainErrorCode.offline,
            YorksV1DomainErrorCode.backendUnavailable,
            YorksV1DomainErrorCode.unexpectedResponse,
          }.contains(error.code)) {
        try {
          await persistPending!(null);
        } catch (_) {
          _setFailure(
            YorksV1DomainErrorCode.backendUnavailable,
            preserveConfirmation: true,
          );
          return null;
        }
      }
      _setFailure(error.code, preserveConfirmation: true);
    } catch (_) {
      _setFailure(
        YorksV1DomainErrorCode.backendUnavailable,
        preserveConfirmation: true,
      );
    }
    return null;
  }

  YorksV1InventoryImportPreview _buildPreview(
    YorksV1InventoryColumnMapping mapping,
  ) {
    final workspace = _workspace;
    if (workspace == null) {
      throw StateError('An inventory workspace is required for validation.');
    }
    return _codec.previewFromSource(
      mapping: mapping,
      categories: workspace.categories,
      inventoryItems: workspace.items,
      suppliers: _suppliers,
    );
  }

  static bool _isR38_9Source(YorksV1InventoryWorkbookSource source) {
    return _isR38_9InventorySource(source);
  }

  bool _requiresR38_9Fields(YorksV1InventoryWorkbookSource source) =>
      _r38_9Commit != null || _isR38_9Source(source);

  void _replaceMappingAndPreview(YorksV1InventoryColumnMapping mapping) {
    final preview = _rebuildPreviewPreservingDecisions(mapping);
    state = YorksV1InventoryImportState(
      status: YorksV1InventoryImportStatus.preview,
      stage: state.stage,
      source: state.source,
      mapping: mapping,
      preview: preview,
      openingBalanceAsOfDate: state.openingBalanceAsOfDate,
    );
  }

  YorksV1InventoryImportPreview _rebuildPreviewPreservingDecisions(
    YorksV1InventoryColumnMapping mapping,
  ) {
    final prior = state.preview;
    var next = _buildPreview(mapping);
    if (prior == null) return next;

    final categoryKeys = <String>{};
    for (final row in prior.rows) {
      if (!row.requiresCategoryDecision ||
          !categoryKeys.add(row.categorySourceKey)) {
        continue;
      }
      if (row.newCategoryName != null) {
        next = _codec.applyCategoryDecision(
          preview: next,
          sourceCategory: row.sourceCategory,
          createNew: true,
        );
      } else if (row.categoryId != null) {
        next = _codec.applyCategoryDecision(
          preview: next,
          sourceCategory: row.sourceCategory,
          categoryId: row.categoryId,
        );
      }
    }

    final supplierKeys = <String>{};
    for (final row in prior.rows) {
      if (!supplierKeys.add(row.supplierSourceKey)) continue;
      final matchingNext = next.rows.where(
        (candidate) => candidate.supplierSourceKey == row.supplierSourceKey,
      );
      if (!matchingNext.any(
        (candidate) => candidate.requiresSupplierDecision,
      )) {
        continue;
      }
      switch (row.supplierResolution) {
        case YorksV1InventorySupplierResolution.createNew:
          next = _codec.applySupplierDecision(
            preview: next,
            sourceSupplierText: row.supplierSourceText,
            createNew: true,
          );
        case YorksV1InventorySupplierResolution.existing:
          if (row.supplierId != null && row.canonicalSupplierName != null) {
            next = _codec.applySupplierDecision(
              preview: next,
              sourceSupplierText: row.supplierSourceText,
              supplierId: row.supplierId,
              canonicalSupplierName: row.canonicalSupplierName,
            );
          }
        case YorksV1InventorySupplierResolution.unknownSupplier:
          next = _codec.applySupplierDecision(
            preview: next,
            sourceSupplierText: row.supplierSourceText,
            useUnknownSupplier: true,
          );
        case null:
          break;
      }
    }

    for (final row in prior.rows) {
      next = _codec.applyReceiptQuantities(
        preview: next,
        sourceRowNumber: row.sourceRowNumber,
        accepted: row.acceptedQuantity ?? row.quantity,
        damaged: row.damagedQuantity,
        rejected: row.rejectedQuantity,
      );
    }
    return next;
  }

  void _replacePreview(YorksV1InventoryImportPreview preview) {
    state = YorksV1InventoryImportState(
      status: YorksV1InventoryImportStatus.preview,
      stage: state.stage,
      source: state.source,
      mapping: state.mapping,
      preview: preview,
      supplierReceiptConfirmed: false,
      openingBalanceAsOfDate: state.openingBalanceAsOfDate,
    );
  }

  void _moveTo(YorksV1InventoryImportStage stage) {
    state = YorksV1InventoryImportState(
      status: YorksV1InventoryImportStatus.preview,
      stage: stage,
      source: state.source,
      mapping: state.mapping,
      preview: state.preview,
      openingBalanceAsOfDate: state.openingBalanceAsOfDate,
    );
  }

  void _setFailure(
    YorksV1DomainErrorCode code, {
    bool preserveConfirmation = false,
  }) {
    if (!mounted) return;
    state = YorksV1InventoryImportState(
      status: YorksV1InventoryImportStatus.failed,
      stage: state.stage,
      source: state.source,
      mapping: state.mapping,
      preview: state.preview,
      result: state.result,
      errorCode: code,
      supplierReceiptConfirmed:
          preserveConfirmation && state.supplierReceiptConfirmed,
      openingBalanceAsOfDate: state.openingBalanceAsOfDate,
    );
  }

  void reset() {
    if (state.isBusy) return;
    _idempotencyKey = null;
    _workspace = null;
    _suppliers = const [];
    _mappingBeforeSafeFixes = null;
    state = const YorksV1InventoryImportState();
  }
}

class _InventoryPreparationRequest {
  const _InventoryPreparationRequest({
    required this.selected,
    required this.workspace,
    required this.suppliers,
    required this.forceR38_9,
  });

  final YorksV1InventorySelectedWorkbook selected;
  final YorksV1InventoryWorkspace workspace;
  final List<YorksV1InventorySupplierMaster> suppliers;
  final bool forceR38_9;
}

class _InventoryPreparationResult {
  const _InventoryPreparationResult({
    required this.source,
    required this.mapping,
    required this.preview,
  });

  final YorksV1InventoryWorkbookSource source;
  final YorksV1InventoryColumnMapping mapping;
  final YorksV1InventoryImportPreview? preview;
}

_InventoryPreparationResult _prepareInventoryImport(
  _InventoryPreparationRequest request,
) => _prepareInventoryImportWithCodec(
  codec: const YorksV1InventoryWorkbookCodec(),
  selected: request.selected,
  workspace: request.workspace,
  suppliers: request.suppliers,
  forceR38_9: request.forceR38_9,
);

_InventoryPreparationResult _prepareInventoryImportWithCodec({
  required YorksV1InventoryWorkbookCodec codec,
  required YorksV1InventorySelectedWorkbook selected,
  required YorksV1InventoryWorkspace workspace,
  required List<YorksV1InventorySupplierMaster> suppliers,
  required bool forceR38_9,
}) {
  final source = codec.read(selected);
  final mapping = codec.proposeMapping(
    source,
    requireR38_9Fields: forceR38_9 || _isR38_9InventorySource(source),
  );
  return _InventoryPreparationResult(
    source: source,
    mapping: mapping,
    preview: mapping.canContinue
        ? codec.previewFromSource(
            mapping: mapping,
            categories: workspace.categories,
            inventoryItems: workspace.items,
            suppliers: suppliers,
          )
        : null,
  );
}

List<YorksV1InventoryWorksheetOption> _inspectInventoryWorksheets(
  YorksV1InventorySelectedWorkbook selected,
) => const YorksV1InventoryWorkbookCodec().availableWorksheets(selected);

bool _isR38_9InventorySource(YorksV1InventoryWorkbookSource source) {
  const indicators = {
    YorksV1InventoryControlledField.sourceType,
    YorksV1InventoryControlledField.externalSupplierName,
    YorksV1InventoryControlledField.supplierReference,
    YorksV1InventoryControlledField.receivedDate,
  };
  return source.columns.any(
    (column) =>
        indicators.any((field) => field.recognizesHeader(column.header)),
  );
}

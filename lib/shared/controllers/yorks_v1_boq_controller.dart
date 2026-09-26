import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/yorks_v1_boq.dart';
import '../models/yorks_v1_boq_workbook.dart';
import '../models/yorks_v1_domain_error.dart';
import '../repositories/yorks_v1_boq_repository.dart';
import '../services/yorks_v1_boq_recovery_store.dart';

enum YorksV1BoqSyncStatus {
  loading,
  ready,
  dirty,
  saving,
  saved,
  conflict,
  failed,
}

class YorksV1BoqWorksheetState {
  const YorksV1BoqWorksheetState({
    this.status = YorksV1BoqSyncStatus.loading,
    this.worksheet,
    this.errorCode,
    this.recoveredLocally = false,
    this.remoteVersion,
  });

  final YorksV1BoqSyncStatus status;
  final YorksV1BoqWorksheet? worksheet;
  final YorksV1DomainErrorCode? errorCode;
  final bool recoveredLocally;
  final int? remoteVersion;

  bool get hasUnsavedChanges =>
      worksheet != null &&
      (status == YorksV1BoqSyncStatus.dirty ||
          status == YorksV1BoqSyncStatus.conflict ||
          status == YorksV1BoqSyncStatus.failed);
  bool get isReadOnly => worksheet?.group.isArchived ?? false;
}

/// Client-side BOQ editor state.  The server remains the authority: this
/// controller only stages a worksheet snapshot and commits it via a
/// version-checked, idempotent RPC when the user saves.
class YorksV1BoqWorksheetController
    extends StateNotifier<YorksV1BoqWorksheetState> {
  YorksV1BoqWorksheetController({
    required String groupId,
    required YorksV1BoqRepository repository,
    String Function()? uuidFactory,
    YorksV1BoqRecoveryStore? recoveryStore,
    bool canManageCommercials = false,
  }) : _groupId = groupId,
       _repository = repository,
       _uuidFactory = uuidFactory ?? const Uuid().v4,
       _recoveryStore = recoveryStore,
       _canManageCommercials = canManageCommercials,
       super(const YorksV1BoqWorksheetState());

  final String _groupId;
  final YorksV1BoqRepository _repository;
  final String Function() _uuidFactory;
  final YorksV1BoqRecoveryStore? _recoveryStore;
  final bool _canManageCommercials;
  _PendingBoqImport? _pendingImport;
  YorksV1BoqWorksheet? _acceptedWorksheet;
  final List<YorksV1BoqWorksheet> _undoStack = [];
  final List<YorksV1BoqWorksheet> _redoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  Future<bool> load({bool discardLocalChanges = false}) async {
    if (state.hasUnsavedChanges && !discardLocalChanges) return false;
    _pendingImport = null;
    if (discardLocalChanges) await _recoveryStore?.clear(_groupId);
    state = const YorksV1BoqWorksheetState(
      status: YorksV1BoqSyncStatus.loading,
    );
    try {
      final worksheet = await _repository.getWorksheet(_groupId);
      _acceptedWorksheet = worksheet;
      _undoStack.clear();
      _redoStack.clear();
      final recovered = discardLocalChanges
          ? null
          : await _recoveryStore?.load(_groupId);
      if (recovered != null) {
        final matchesServer =
            recovered.group.version == worksheet.group.version;
        final mergedRecovery = _mergeRecoveryWithServer(
          recovered: recovered,
          server: worksheet,
        );
        state = YorksV1BoqWorksheetState(
          status: matchesServer
              ? YorksV1BoqSyncStatus.dirty
              : YorksV1BoqSyncStatus.conflict,
          worksheet: mergedRecovery,
          recoveredLocally: true,
          remoteVersion: worksheet.group.version,
          errorCode: matchesServer ? null : YorksV1DomainErrorCode.conflict,
        );
      } else {
        state = YorksV1BoqWorksheetState(
          status: YorksV1BoqSyncStatus.ready,
          worksheet: worksheet,
        );
      }
      return true;
    } on YorksV1DomainException catch (error) {
      final recovered = await _recoveryStore?.load(_groupId);
      state = YorksV1BoqWorksheetState(
        status: recovered == null
            ? YorksV1BoqSyncStatus.failed
            : YorksV1BoqSyncStatus.dirty,
        worksheet: recovered,
        recoveredLocally: recovered != null,
        errorCode: error.code,
      );
      return recovered != null;
    } catch (_) {
      final recovered = await _recoveryStore?.load(_groupId);
      state = YorksV1BoqWorksheetState(
        status: recovered == null
            ? YorksV1BoqSyncStatus.failed
            : YorksV1BoqSyncStatus.dirty,
        worksheet: recovered,
        recoveredLocally: recovered != null,
        errorCode: YorksV1DomainErrorCode.backendUnavailable,
      );
      return recovered != null;
    }
  }

  Future<void> discardLocalChanges() async {
    _pendingImport = null;
    _undoStack.clear();
    _redoStack.clear();
    await _recoveryStore?.clear(_groupId);
    final accepted = _acceptedWorksheet;
    if (accepted == null) {
      await load(discardLocalChanges: true);
      return;
    }
    state = YorksV1BoqWorksheetState(
      status: YorksV1BoqSyncStatus.ready,
      worksheet: accepted,
    );
  }

  void undo() {
    final current = state.worksheet;
    if (current == null || _undoStack.isEmpty) return;
    _redoStack.add(current);
    _setEdited(_undoStack.removeLast());
  }

  void redo() {
    final current = state.worksheet;
    if (current == null || _redoStack.isEmpty) return;
    _undoStack.add(current);
    _setEdited(_redoStack.removeLast());
  }

  void updateTitle(String value) {
    final worksheet = _editableWorksheet();
    _replace(
      worksheet.copyWith(
        group: YorksV1BoqGroup(
          id: worksheet.group.id,
          projectId: worksheet.group.projectId,
          name: worksheet.group.name,
          worksheetTitle: value,
          displayOrder: worksheet.group.displayOrder,
          isCustom: worksheet.group.isCustom,
          isArchived: worksheet.group.isArchived,
          version: worksheet.group.version,
          rowCount: worksheet.group.rowCount,
          columnCount: worksheet.group.columnCount,
          documentCount: worksheet.group.documentCount,
          linkedRequestCount: worksheet.group.linkedRequestCount,
          lastEditedBy: worksheet.group.lastEditedBy,
          lastEditedRole: worksheet.group.lastEditedRole,
          lastEditedAt: worksheet.group.lastEditedAt,
          updatedAt: worksheet.group.updatedAt,
          scopeId: worksheet.group.scopeId,
          scopeKind: worksheet.group.scopeKind,
          scopeCode: worksheet.group.scopeCode,
          scopeName: worksheet.group.scopeName,
          isLegacyUnassigned: worksheet.group.isLegacyUnassigned,
        ),
      ),
    );
  }

  void addColumn({
    required String heading,
    YorksV1BoqCanonicalField? canonicalField,
  }) {
    final worksheet = _editableWorksheet();
    final cleanHeading = heading.trim();
    if (cleanHeading.isEmpty) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    if (canonicalField?.isCommercial == true && !_canManageCommercials) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.unauthorized);
    }
    final normalizedHeading = cleanHeading.toLowerCase();
    if (worksheet.columns.any(
          (column) => column.heading.trim().toLowerCase() == normalizedHeading,
        ) ||
        (canonicalField != null &&
            worksheet.columns.any(
              (column) => column.canonicalField == canonicalField,
            ))) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    _replace(
      worksheet.copyWith(
        columns: [
          ...worksheet.columns,
          YorksV1BoqColumn(
            id: _uuidFactory(),
            heading: cleanHeading,
            displayOrder: worksheet.columns.length + 1,
            canonicalField: canonicalField,
            isCommercial: canonicalField?.isCommercial ?? false,
          ),
        ],
      ),
    );
  }

  void renameColumn(String columnId, String heading) {
    final worksheet = _editableWorksheet();
    final cleanHeading = heading.trim();
    if (cleanHeading.isEmpty) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    final target = worksheet.columns
        .where((item) => item.id == columnId)
        .firstOrNull;
    if (target == null) return;
    if (target.isCommercial && !_canManageCommercials) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.unauthorized);
    }
    if (worksheet.columns.any(
      (column) =>
          column.id != columnId &&
          column.heading.trim().toLowerCase() == cleanHeading.toLowerCase(),
    )) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    _replace(
      worksheet.copyWith(
        columns: [
          for (final column in worksheet.columns)
            if (column.id == columnId)
              column.copyWith(heading: cleanHeading)
            else
              column,
        ],
      ),
    );
  }

  void removeColumn(String columnId) {
    final worksheet = _editableWorksheet();
    final target = worksheet.columns
        .where((item) => item.id == columnId)
        .firstOrNull;
    if (target?.isCommercial == true && !_canManageCommercials) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.unauthorized);
    }
    final next = worksheet.columns
        .where((column) => column.id != columnId)
        .toList(growable: false);
    if (next.length == worksheet.columns.length) return;
    _replace(
      worksheet.copyWith(
        columns: [
          for (var index = 0; index < next.length; index++)
            next[index].copyWith(displayOrder: index + 1),
        ],
      ),
    );
  }

  YorksV1BoqRow addBlankRow({String? afterRowId}) {
    final worksheet = _editableWorksheet();
    final index = _insertIndex(worksheet.rows, afterRowId);
    final row = YorksV1BoqRow(
      id: _uuidFactory(),
      displayOrder: index + 1,
      values: const {},
      canonicalValues: const {},
    );
    _replace(
      worksheet.copyWith(rows: _insertAndOrder(worksheet.rows, row, index)),
    );
    return row;
  }

  YorksV1BoqRow addSimilarRow({required String sourceRowId}) {
    final worksheet = _editableWorksheet();
    final sourceIndex = worksheet.rows.indexWhere(
      (row) => row.id == sourceRowId,
    );
    if (sourceIndex < 0) return addBlankRow(afterRowId: sourceRowId);
    final source = worksheet.rows[sourceIndex];
    final carriedValues = <String, Object?>{};
    final carriedCanonicalValues = <String, Object?>{};
    for (final column in worksheet.columns) {
      if (!_copiesToSimilarRow(column)) continue;
      final value = source.valueFor(column.id);
      if (value == null || value.toString().trim().isEmpty) continue;
      carriedValues[column.id] = value;
      final canonical = column.canonicalField;
      if (canonical != null) {
        carriedCanonicalValues[canonical.wireValue] = value;
      }
    }
    final row = YorksV1BoqRow(
      id: _uuidFactory(),
      displayOrder: sourceIndex + 2,
      values: carriedValues,
      canonicalValues: carriedCanonicalValues,
    );
    _replace(
      worksheet.copyWith(
        rows: _insertAndOrder(worksheet.rows, row, sourceIndex + 1),
      ),
    );
    return row;
  }

  /// R35 Similar Row deliberately carries only reusable material context.
  /// Tag/model, quantities, commercial values and arbitrary technical/status
  /// data are unique to the original equipment and must be reviewed again.
  static bool _copiesToSimilarRow(YorksV1BoqColumn column) {
    switch (column.canonicalField) {
      case YorksV1BoqCanonicalField.description:
      case YorksV1BoqCanonicalField.size:
      case YorksV1BoqCanonicalField.brandOrigin:
      case YorksV1BoqCanonicalField.unit:
        return true;
      case YorksV1BoqCanonicalField.model:
      case YorksV1BoqCanonicalField.equipmentTag:
      case YorksV1BoqCanonicalField.quantity:
      case YorksV1BoqCanonicalField.unitCost:
      case YorksV1BoqCanonicalField.totalCost:
      case YorksV1BoqCanonicalField.planningModelTag:
      case null:
        break;
    }
    final heading = column.heading.toLowerCase();
    return RegExp(
          r'(^|[^a-z])(description|item|size|dimension|make|brand|origin|unit)([^a-z]|$)',
        ).hasMatch(heading) &&
        !RegExp(
          r'tag|model|serial|qty|quantity|cost|price|mass|status|approval|amount',
        ).hasMatch(heading);
  }

  void updateCell({
    required String rowId,
    required String columnId,
    required String value,
  }) {
    final worksheet = _editableWorksheet();
    final column = worksheet.columns
        .where((item) => item.id == columnId)
        .firstOrNull;
    if (column == null) return;
    if (column.isCommercial && !_canManageCommercials) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.unauthorized);
    }
    final canonicalValues = <String, Object?>{};
    for (final entry in worksheet.rows) {
      if (entry.id != rowId) {
        continue;
      }
      canonicalValues.addAll(entry.canonicalValues);
      final canonical = column.canonicalField;
      if (canonical != null && !canonical.isCommercial) {
        final clean = value.trim();
        if (clean.isEmpty) {
          canonicalValues.remove(canonical.wireValue);
        } else {
          canonicalValues[canonical.wireValue] = clean;
        }
      }
    }
    _replace(
      worksheet.copyWith(
        rows: [
          for (final row in worksheet.rows)
            if (row.id == rowId)
              row.copyWith(
                values: {...row.values, columnId: value},
                canonicalValues: canonicalValues,
              )
            else
              row,
        ],
      ),
    );
  }

  /// Applies a spreadsheet paste as one recoverable local revision. The
  /// visible column order comes from the UI, but authority is rechecked here.
  void pasteCells({
    required String? startRowId,
    required List<String> columnIds,
    required List<List<String>> values,
  }) {
    final worksheet = _editableWorksheet();
    if (values.isEmpty || columnIds.isEmpty) return;
    final columns = {for (final column in worksheet.columns) column.id: column};
    for (final id in columnIds) {
      final column = columns[id];
      if (column == null || (column.isCommercial && !_canManageCommercials)) {
        throw const YorksV1DomainException(YorksV1DomainErrorCode.unauthorized);
      }
    }
    final rows = [...worksheet.rows];
    final selected = rows.indexWhere((row) => row.id == startRowId);
    final start = selected < 0 ? rows.length : selected;
    var changed = false;
    for (var rowOffset = 0; rowOffset < values.length; rowOffset++) {
      final cells = values[rowOffset];
      if (cells.isEmpty) continue;
      final rowIndex = start + rowOffset;
      while (rows.length <= rowIndex) {
        rows.add(
          YorksV1BoqRow(
            id: _uuidFactory(),
            displayOrder: rows.length + 1,
            values: const {},
            canonicalValues: const {},
          ),
        );
        changed = true;
      }
      final row = rows[rowIndex];
      final nextValues = <String, Object?>{...row.values};
      final canonicalValues = <String, Object?>{...row.canonicalValues};
      for (
        var columnOffset = 0;
        columnOffset < cells.length && columnOffset < columnIds.length;
        columnOffset++
      ) {
        final column = columns[columnIds[columnOffset]]!;
        final value = cells[columnOffset];
        if (nextValues[column.id] != value) changed = true;
        nextValues[column.id] = value;
        final canonical = column.canonicalField;
        if (canonical != null && !canonical.isCommercial) {
          if (value.trim().isEmpty) {
            canonicalValues.remove(canonical.wireValue);
          } else {
            canonicalValues[canonical.wireValue] = value.trim();
          }
        }
      }
      rows[rowIndex] = row.copyWith(
        values: nextValues,
        canonicalValues: canonicalValues,
      );
    }
    if (changed) _replace(worksheet.copyWith(rows: rows));
  }

  /// Applies one reviewed material suggestion to the mapped operational
  /// columns in a single local revision. Quantity and commercial fields are
  /// intentionally absent: engineers must still enter and review them.
  void updateMaterialCells({
    required String rowId,
    required Map<YorksV1BoqCanonicalField, String> values,
  }) {
    final worksheet = _editableWorksheet();
    final source = worksheet.rows.where((row) => row.id == rowId).firstOrNull;
    if (source == null) return;

    final nextValues = <String, Object?>{...source.values};
    final nextCanonicalValues = <String, Object?>{...source.canonicalValues};
    var changed = false;
    for (final column in worksheet.columns) {
      final canonical = column.canonicalField;
      if (canonical == null || canonical.isCommercial) continue;
      final value = values[canonical]?.trim();
      if (value == null || value.isEmpty) continue;
      if (nextValues[column.id] == value &&
          nextCanonicalValues[canonical.wireValue] == value) {
        continue;
      }
      nextValues[column.id] = value;
      nextCanonicalValues[canonical.wireValue] = value;
      changed = true;
    }
    if (!changed) return;

    _replace(
      worksheet.copyWith(
        rows: [
          for (final row in worksheet.rows)
            if (row.id == rowId)
              row.copyWith(
                values: nextValues,
                canonicalValues: nextCanonicalValues,
              )
            else
              row,
        ],
      ),
    );
  }

  void removeRow(String rowId) {
    final worksheet = _editableWorksheet();
    final remaining = worksheet.rows
        .where((row) => row.id != rowId)
        .toList(growable: false);
    if (remaining.length == worksheet.rows.length) return;
    _replace(
      worksheet.copyWith(
        rows: [
          for (var index = 0; index < remaining.length; index++)
            remaining[index].copyWith(displayOrder: index + 1),
        ],
      ),
    );
  }

  Future<bool> save() async {
    final worksheet = state.worksheet;
    if (worksheet == null || worksheet.group.isArchived) return false;
    if (worksheet.group.worksheetTitle.trim().isEmpty) {
      state = YorksV1BoqWorksheetState(
        status: YorksV1BoqSyncStatus.failed,
        worksheet: worksheet,
        errorCode: YorksV1DomainErrorCode.invalidInput,
      );
      return false;
    }
    state = YorksV1BoqWorksheetState(
      status: YorksV1BoqSyncStatus.saving,
      worksheet: worksheet,
    );
    try {
      final saved = await _repository.saveWorksheet(
        YorksV1SaveBoqWorksheetInput(
          worksheet: worksheet,
          worksheetTitle: worksheet.group.worksheetTitle,
          expectedVersion: worksheet.group.version,
          idempotencyKey: _uuidFactory(),
        ),
      );
      _acceptedWorksheet = saved;
      await _recoveryStore?.clear(_groupId);
      state = YorksV1BoqWorksheetState(
        status: YorksV1BoqSyncStatus.saved,
        worksheet: saved,
      );
      return true;
    } on YorksV1DomainException catch (error) {
      state = YorksV1BoqWorksheetState(
        status: error.code == YorksV1DomainErrorCode.conflict
            ? YorksV1BoqSyncStatus.conflict
            : YorksV1BoqSyncStatus.failed,
        worksheet: worksheet,
        errorCode: error.code,
      );
      return false;
    } catch (_) {
      state = YorksV1BoqWorksheetState(
        status: YorksV1BoqSyncStatus.failed,
        worksheet: worksheet,
        errorCode: YorksV1DomainErrorCode.backendUnavailable,
      );
      return false;
    }
  }

  /// Commits a reviewed local XLSX preview as one server-side worksheet
  /// replacement. Parsing or previewing a file never reaches Supabase; this
  /// is the only import mutation boundary.
  Future<bool> importWorkbook(YorksV1BoqImportPreview preview) async {
    final current = state.worksheet;
    if (current == null || current.group.isArchived || !preview.isValid) {
      if (current != null) {
        state = YorksV1BoqWorksheetState(
          status: YorksV1BoqSyncStatus.failed,
          worksheet: current,
          errorCode: YorksV1DomainErrorCode.invalidInput,
        );
      }
      return false;
    }
    if (!_canManageCommercials &&
        preview.columns.any(
          (column) => column.canonicalField?.isCommercial == true,
        )) {
      state = YorksV1BoqWorksheetState(
        status: YorksV1BoqSyncStatus.failed,
        worksheet: current,
        errorCode: YorksV1DomainErrorCode.unauthorized,
      );
      return false;
    }
    final title = preview.title.trim();
    if (title.isEmpty) {
      state = YorksV1BoqWorksheetState(
        status: YorksV1BoqSyncStatus.failed,
        worksheet: current,
        errorCode: YorksV1DomainErrorCode.invalidInput,
      );
      return false;
    }

    final fingerprint = _importFingerprint(preview, current.group);
    final existingCommand = _pendingImport;
    final input = existingCommand?.fingerprint == fingerprint
        ? existingCommand!.input
        : _buildImportInput(preview, current, title);
    _pendingImport = _PendingBoqImport(fingerprint: fingerprint, input: input);
    state = YorksV1BoqWorksheetState(
      status: YorksV1BoqSyncStatus.saving,
      worksheet: current,
    );
    try {
      final saved = await _repository.importWorksheet(input);
      _pendingImport = null;
      _acceptedWorksheet = saved;
      await _recoveryStore?.clear(_groupId);
      state = YorksV1BoqWorksheetState(
        status: YorksV1BoqSyncStatus.saved,
        worksheet: saved,
      );
      return true;
    } on YorksV1DomainException catch (error) {
      state = YorksV1BoqWorksheetState(
        status: error.code == YorksV1DomainErrorCode.conflict
            ? YorksV1BoqSyncStatus.conflict
            : YorksV1BoqSyncStatus.failed,
        worksheet: current,
        errorCode: error.code,
      );
      return false;
    } catch (_) {
      state = YorksV1BoqWorksheetState(
        status: YorksV1BoqSyncStatus.failed,
        worksheet: current,
        errorCode: YorksV1DomainErrorCode.backendUnavailable,
      );
      return false;
    }
  }

  YorksV1BoqWorksheet _editableWorksheet() {
    final worksheet = state.worksheet;
    if (worksheet == null ||
        worksheet.group.isArchived ||
        worksheet.group.isLegacyUnassigned) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    return worksheet;
  }

  void _replace(YorksV1BoqWorksheet worksheet) {
    final current = state.worksheet;
    if (current != null) {
      _undoStack.add(current);
      if (_undoStack.length > 50) _undoStack.removeAt(0);
    }
    _redoStack.clear();
    _setEdited(worksheet);
  }

  void _setEdited(YorksV1BoqWorksheet worksheet) {
    _pendingImport = null;
    state = YorksV1BoqWorksheetState(
      status: YorksV1BoqSyncStatus.dirty,
      worksheet: worksheet,
    );
    unawaited(_recoveryStore?.save(worksheet));
  }

  YorksV1ImportBoqWorksheetInput _buildImportInput(
    YorksV1BoqImportPreview preview,
    YorksV1BoqWorksheet current,
    String title,
  ) {
    final columns = [
      for (var index = 0; index < preview.columns.length; index++)
        YorksV1BoqColumn(
          id: _uuidFactory(),
          heading: preview.columns[index].heading.trim(),
          displayOrder: index + 1,
          canonicalField: preview.columns[index].canonicalField,
          isCommercial:
              preview.columns[index].canonicalField?.isCommercial ?? false,
        ),
    ];
    final rows = [
      for (var rowIndex = 0; rowIndex < preview.rows.length; rowIndex++)
        YorksV1BoqRow(
          id: _uuidFactory(),
          displayOrder: rowIndex + 1,
          values: {
            for (
              var columnIndex = 0;
              columnIndex < columns.length;
              columnIndex++
            )
              if (preview.rows[rowIndex]
                  .valueFor(preview.columns[columnIndex].sourceIndex)
                  .isNotEmpty)
                columns[columnIndex].id: preview.rows[rowIndex].valueFor(
                  preview.columns[columnIndex].sourceIndex,
                ),
          },
          canonicalValues: {
            for (
              var columnIndex = 0;
              columnIndex < columns.length;
              columnIndex++
            )
              if (preview.rows[rowIndex]
                      .valueFor(preview.columns[columnIndex].sourceIndex)
                      .trim()
                      .isNotEmpty &&
                  preview.columns[columnIndex].canonicalField != null &&
                  !preview.columns[columnIndex].canonicalField!.isCommercial)
                preview.columns[columnIndex].canonicalField!.wireValue: preview
                    .rows[rowIndex]
                    .valueFor(preview.columns[columnIndex].sourceIndex),
          },
        ),
    ];
    return YorksV1ImportBoqWorksheetInput(
      worksheet: YorksV1BoqWorksheet(
        group: _groupWithTitle(current.group, title),
        columns: columns,
        rows: rows,
      ),
      worksheetTitle: title,
      expectedVersion: current.group.version,
      idempotencyKey: _uuidFactory(),
      sourceFileName: preview.fileName,
      sourceWorksheetName: preview.worksheetName,
      sourceHeaderRowNumber: preview.headerRowNumber,
      sourceHeaderRowNumbers: preview.headerRowNumbers,
      sourceHeaderHierarchy: preview.headerHierarchy,
    );
  }

  static String _importFingerprint(
    YorksV1BoqImportPreview preview,
    YorksV1BoqGroup group,
  ) => jsonEncode({
    'group_id': group.id,
    'expected_version': group.version,
    'file_name': preview.fileName.trim(),
    'worksheet_name': preview.worksheetName.trim(),
    'title': preview.title.trim(),
    'header_rows': preview.headerRowNumbers,
    'header_hierarchy': [
      for (final path in preview.headerHierarchy) path.toJson(),
    ],
    'columns': [
      for (final column in preview.columns)
        [
          column.sourceIndex,
          column.heading.trim(),
          column.canonicalField?.wireValue,
        ],
    ],
    'rows': [
      for (final row in preview.rows)
        [row.sourceRowNumber, _sortedImportValues(row)],
    ],
  });

  static List<List<Object>> _sortedImportValues(YorksV1BoqImportRow row) {
    final entries = row.values.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    return [
      for (final entry in entries) [entry.key, entry.value],
    ];
  }

  static YorksV1BoqGroup _groupWithTitle(YorksV1BoqGroup group, String title) =>
      YorksV1BoqGroup(
        id: group.id,
        projectId: group.projectId,
        name: group.name,
        worksheetTitle: title,
        displayOrder: group.displayOrder,
        isCustom: group.isCustom,
        isArchived: group.isArchived,
        version: group.version,
        rowCount: group.rowCount,
        columnCount: group.columnCount,
        documentCount: group.documentCount,
        linkedRequestCount: group.linkedRequestCount,
        lastEditedBy: group.lastEditedBy,
        lastEditedRole: group.lastEditedRole,
        lastEditedAt: group.lastEditedAt,
        updatedAt: group.updatedAt,
        scopeId: group.scopeId,
        scopeKind: group.scopeKind,
        scopeCode: group.scopeCode,
        scopeName: group.scopeName,
        isLegacyUnassigned: group.isLegacyUnassigned,
      );

  /// Recovery intentionally stores operational fields only. Rejoin any
  /// currently authorized protected columns and values from the fresh server
  /// projection before a recovered worksheet can be saved.
  static YorksV1BoqWorksheet _mergeRecoveryWithServer({
    required YorksV1BoqWorksheet recovered,
    required YorksV1BoqWorksheet server,
  }) {
    final recoveredColumnIds = recovered.columns
        .map((column) => column.id)
        .toSet();
    final protectedColumns = server.columns
        .where(
          (column) =>
              column.isCommercial && !recoveredColumnIds.contains(column.id),
        )
        .toList(growable: false);
    if (protectedColumns.isEmpty) return recovered;

    final serverRows = {for (final row in server.rows) row.id: row};
    final protectedColumnIds = protectedColumns
        .map((column) => column.id)
        .toSet();
    return recovered.copyWith(
      columns: [
        ...recovered.columns,
        ...protectedColumns,
      ]..sort((left, right) => left.displayOrder.compareTo(right.displayOrder)),
      rows: [
        for (final row in recovered.rows)
          row.copyWith(
            values: {
              ...row.values,
              for (final entry
                  in serverRows[row.id]?.values.entries ??
                      const <MapEntry<String, Object?>>[])
                if (protectedColumnIds.contains(entry.key))
                  entry.key: entry.value,
            },
            canonicalValues: {
              ...row.canonicalValues,
              for (final entry
                  in serverRows[row.id]?.canonicalValues.entries ??
                      const <MapEntry<String, Object?>>[])
                if (YorksV1BoqCanonicalField.fromWireValue(
                      entry.key,
                    )?.isCommercial ==
                    true)
                  entry.key: entry.value,
            },
          ),
      ],
    );
  }

  static int _insertIndex(List<YorksV1BoqRow> rows, String? afterRowId) {
    if (afterRowId == null) return rows.length;
    final index = rows.indexWhere((row) => row.id == afterRowId);
    return index < 0 ? rows.length : index + 1;
  }

  static List<YorksV1BoqRow> _insertAndOrder(
    List<YorksV1BoqRow> rows,
    YorksV1BoqRow row,
    int index,
  ) {
    final next = List<YorksV1BoqRow>.of(rows)..insert(index, row);
    return [
      for (var item = 0; item < next.length; item++)
        next[item].copyWith(displayOrder: item + 1),
    ];
  }
}

class _PendingBoqImport {
  const _PendingBoqImport({required this.fingerprint, required this.input});

  final String fingerprint;
  final YorksV1ImportBoqWorksheetInput input;
}

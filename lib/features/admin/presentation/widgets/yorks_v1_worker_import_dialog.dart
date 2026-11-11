import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_boq_workbook.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/models/yorks_v1_worker_record.dart';
import '../../../../shared/models/yorks_v1_worker_record_strings.dart';
import '../../../../shared/providers/yorks_v1_worker_record_provider.dart';
import '../../../../shared/services/yorks_v1_worker_workbook_service.dart';

typedef _S = YorksV1WorkerRecordStrings;

/// Choose an Excel sheet, see what the server would do with every row, then
/// import all rows or none. Pops the [YorksV1WorkerImportResult] on success.
class YorksV1WorkerImportDialog extends ConsumerStatefulWidget {
  const YorksV1WorkerImportDialog({super.key, required this.language});

  final AppLanguage language;

  static Future<YorksV1WorkerImportResult?> show(
    BuildContext context, {
    required AppLanguage language,
  }) => showDialog<YorksV1WorkerImportResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => YorksV1WorkerImportDialog(language: language),
  );

  @override
  ConsumerState<YorksV1WorkerImportDialog> createState() =>
      _YorksV1WorkerImportDialogState();
}

class _YorksV1WorkerImportDialogState
    extends ConsumerState<YorksV1WorkerImportDialog> {
  final _designation = TextEditingController();
  final _joiningDate = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  YorksV1PickedWorkerWorkbook? _workbook;
  YorksV1BoqWorkbookSheet? _sheet;
  YorksV1WorkerSheet? _parsed;
  YorksV1WorkerImportPreview? _preview;
  bool _busy = false;
  bool _stale = false;
  TranslatableString? _error;

  /// One key per previewed file. A retry after a lost response reuses it, so
  /// the import can never run twice; a new preview gets a new key.
  String _importKey = const Uuid().v4();

  @override
  void dispose() {
    _designation.dispose();
    _joiningDate.dispose();
    super.dispose();
  }

  String t(TranslatableString copy) => copy.active(widget.language);

  Future<void> _pickFile() async {
    setState(() => _error = null);
    final YorksV1PickedWorkerWorkbook? workbook;
    try {
      workbook = await ref
          .read(yorksV1WorkerWorkbookFilesProvider)
          .pickWorkbook();
    } on YorksV1DomainException {
      if (mounted) setState(() => _error = _S.fileUnreadable);
      return;
    }
    if (!mounted || workbook == null) return;
    if (workbook.sheets.isEmpty) {
      setState(() => _error = _S.noRows);
      return;
    }
    _workbook = workbook;
    // Prefer the first worksheet that has the expected headings.
    final sheet = workbook.sheets.firstWhere(
      (candidate) => yorksV1ReadWorkerSheet(candidate).missingColumns.isEmpty,
      orElse: () => workbook!.sheets.first,
    );
    await _useSheet(sheet);
  }

  Future<void> _useSheet(YorksV1BoqWorkbookSheet sheet) async {
    final parsed = yorksV1ReadWorkerSheet(sheet);
    setState(() {
      _sheet = sheet;
      _parsed = parsed;
      _preview = null;
      _stale = false;
      _error = parsed.missingColumns.isNotEmpty
          ? _S.columnsMissing
          : parsed.tooManyRows
          ? _S.tooManyRows
          : parsed.rows.isEmpty
          ? _S.noRows
          : null;
    });
    if (parsed.readable) await _check();
  }

  Future<void> _check() async {
    final parsed = _parsed;
    if (parsed == null || !parsed.readable) return;
    setState(() {
      _busy = true;
      _error = null;
      _stale = false;
    });
    try {
      final preview = await ref
          .read(yorksV1WorkerRecordRepositoryProvider)
          .previewImport([for (final row in parsed.rows) row.toRpcJson()]);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _importKey = const Uuid().v4();
        _busy = false;
      });
    } on YorksV1DomainException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _failure(error);
      });
    }
  }

  Future<void> _import() async {
    final parsed = _parsed;
    final preview = _preview;
    if (_busy || parsed == null || preview == null) return;
    if (preview.createCount > 0 &&
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(yorksV1WorkerRecordRepositoryProvider)
          .importRecords(
            rows: [for (final row in parsed.rows) row.toRpcJson()],
            expected: [for (final row in preview.rows) row.raw],
            newWorkerDesignation: preview.createCount > 0
                ? _designation.text.trim()
                : null,
            newWorkerJoiningDate: preview.createCount > 0
                ? _joiningDate.text.trim()
                : null,
            idempotencyKey: _importKey,
          );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on YorksV1DomainException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (error.code == YorksV1DomainErrorCode.conflict) {
          _stale = true;
          _error = _S.importStale;
        } else {
          _error = _failure(error);
        }
      });
    }
  }

  TranslatableString _failure(YorksV1DomainException error) =>
      switch (error.code) {
        YorksV1DomainErrorCode.offline => _S.saveOffline,
        YorksV1DomainErrorCode.unauthorized ||
        YorksV1DomainErrorCode.unauthenticated => _S.saveNotAllowed,
        _ => _S.importFailed,
      };

  Future<void> _saveTemplate() async {
    try {
      await ref.read(yorksV1WorkerWorkbookFilesProvider).saveTemplate();
    } catch (_) {
      if (mounted) setState(() => _error = _S.importFailed);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_joiningDate.text) ?? now,
      firstDate: DateTime(1990),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    _joiningDate.text =
        '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final compact =
        MediaQuery.sizeOf(context).width < AppSpacing.compactBreakpoint;
    final parsed = _parsed;
    final preview = _preview;
    final workbook = _workbook;

    // A sheet problem the server never sees (bad number, wrong total) blocks
    // the import exactly like a server row error.
    final sheetProblems =
        parsed?.rows.where((row) => row.issues.isNotEmpty).length ?? 0;
    final problems = (preview?.errorCount ?? 0) + sheetProblems;
    final toImport = (preview?.createCount ?? 0) + (preview?.updateCount ?? 0);
    final canImport =
        preview != null && !_busy && !_stale && problems == 0 && toImport > 0;

    return Directionality(
      textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: AlertDialog(
        key: const ValueKey('worker-import-dialog'),
        insetPadding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.xl),
        title: Text(t(_S.importWorkers)),
        content: SizedBox(
          width: 860,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t(_S.importIntro),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      height: AppSpacing.minTapTarget,
                      child: FilledButton.tonalIcon(
                        key: const ValueKey('worker-import-choose'),
                        onPressed: _busy ? null : _pickFile,
                        icon: const Icon(Icons.upload_file_rounded),
                        label: Text(t(_S.chooseFile)),
                      ),
                    ),
                    SizedBox(
                      height: AppSpacing.minTapTarget,
                      child: TextButton.icon(
                        key: const ValueKey('worker-import-template'),
                        onPressed: _busy ? null : _saveTemplate,
                        icon: const Icon(Icons.download_rounded),
                        label: Text(t(_S.downloadTemplate)),
                      ),
                    ),
                    if (workbook != null)
                      Text(
                        workbook.fileName,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.ink,
                        ),
                      ),
                  ],
                ),
                if (workbook != null && workbook.sheets.length > 1) ...[
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<YorksV1BoqWorkbookSheet>(
                    key: const ValueKey('worker-import-sheet'),
                    initialValue: _sheet,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: t(_S.worksheet)),
                    items: [
                      for (final sheet in workbook.sheets)
                        DropdownMenuItem(value: sheet, child: Text(sheet.name)),
                    ],
                    onChanged: _busy || _sheet == null
                        ? null
                        : (sheet) {
                            if (sheet != null) _useSheet(sheet);
                          },
                  ),
                ],
                if (_busy) ...[
                  const SizedBox(height: AppSpacing.md),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                if (preview != null && parsed != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _Summary(
                    language: language,
                    preview: preview,
                    problems: problems,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _RowsTable(
                    language: language,
                    rows: parsed.rows,
                    results: preview.rows,
                    compact: compact,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    t(_S.blankKeeps),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                  if (problems > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        t(_S.fixProblems),
                        key: const ValueKey('worker-import-fix'),
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    )
                  else if (toImport == 0)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        t(_S.nothingToImport),
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  if (preview.createCount > 0 && problems == 0)
                    Form(
                      key: _formKey,
                      child: Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        child: _NewWorkerDefaults(
                          language: language,
                          compact: compact,
                          enabled: !_busy,
                          designation: _designation,
                          joiningDate: _joiningDate,
                          onPickDate: _pickDate,
                        ),
                      ),
                    ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    key: const ValueKey('worker-import-error'),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.errorContainer,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            t(_error!),
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.onErrorContainer,
                            ),
                          ),
                        ),
                        if (_stale)
                          TextButton(
                            key: const ValueKey('worker-import-recheck'),
                            onPressed: _busy ? null : _check,
                            child: Text(t(_S.checkAgain)),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(t(_S.cancel)),
          ),
          FilledButton(
            key: const ValueKey('worker-import-confirm'),
            onPressed: canImport ? _import : null,
            child: Text(
              _busy && preview != null
                  ? t(_S.importing)
                  : t(_S.importN).replaceAll('{n}', '$toImport'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.language,
    required this.preview,
    required this.problems,
  });

  final AppLanguage language;
  final YorksV1WorkerImportPreview preview;
  final int problems;

  @override
  Widget build(BuildContext context) {
    Widget chip(
      TranslatableString copy,
      int count,
      Color foreground,
      Color background,
      String key,
    ) => Container(
      key: ValueKey('worker-import-$key'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Text(
        copy.active(language).replaceAll('{n}', '$count'),
        style: AppTypography.labelSmall.copyWith(color: foreground),
      ),
    );
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        chip(
          _S.summaryNew,
          preview.createCount,
          AppColors.blue,
          AppColors.blueContainer,
          'new',
        ),
        chip(
          _S.summaryUpdate,
          preview.updateCount,
          AppColors.success,
          AppColors.successContainer,
          'update',
        ),
        chip(
          _S.summaryUnchanged,
          preview.unchangedCount,
          AppColors.neutralText,
          AppColors.neutralContainer,
          'unchanged',
        ),
        chip(
          _S.summaryProblems,
          problems,
          problems > 0 ? AppColors.error : AppColors.neutralText,
          problems > 0 ? AppColors.errorContainer : AppColors.neutralContainer,
          'problems',
        ),
      ],
    );
  }
}

const _fieldLabels = <String, TranslatableString>{
  'trade_license_no': YorksV1WorkerRecordStrings.tradeLicense,
  'passport_no': YorksV1WorkerRecordStrings.passport,
  'basic_salary': YorksV1WorkerRecordStrings.basicSalary,
  'housing_allowance': YorksV1WorkerRecordStrings.housing,
  'other_allowance': YorksV1WorkerRecordStrings.others,
};

const _errorLabels = <String, TranslatableString>{
  'name_required': YorksV1WorkerRecordStrings.errName,
  'company_required': YorksV1WorkerRecordStrings.errCompany,
  'field_too_long': YorksV1WorkerRecordStrings.errTooLong,
  'amount_invalid': YorksV1WorkerRecordStrings.errAmount,
  'duplicate_in_file': YorksV1WorkerRecordStrings.errDuplicate,
  'ambiguous_match': YorksV1WorkerRecordStrings.errAmbiguous,
  'passport_other_worker': YorksV1WorkerRecordStrings.errPassportOther,
  'passport_differs': YorksV1WorkerRecordStrings.errPassportDiffers,
};

class _RowsTable extends StatelessWidget {
  const _RowsTable({
    required this.language,
    required this.rows,
    required this.results,
    required this.compact,
  });

  final AppLanguage language;
  final List<YorksV1WorkerSheetRow> rows;
  final List<YorksV1WorkerImportRowResult> results;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    String t(TranslatableString copy) => copy.active(language);
    final header = AppTypography.labelSmall.copyWith(color: AppColors.muted);
    final cell = AppTypography.bodySmall.copyWith(color: AppColors.ink);
    return Container(
      constraints: const BoxConstraints(maxHeight: 360),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: ListView.separated(
        key: const ValueKey('worker-import-rows'),
        shrinkWrap: true,
        itemCount: rows.length + 1,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: AppColors.line),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Container(
              color: AppColors.surfaceContainerLow,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  SizedBox(width: 44, child: Text(t(_S.row), style: header)),
                  Expanded(flex: 5, child: Text(t(_S.name), style: header)),
                  if (!compact)
                    Expanded(
                      flex: 4,
                      child: Text(t(_S.company), style: header),
                    ),
                  Expanded(flex: 5, child: Text(t(_S.result), style: header)),
                ],
              ),
            );
          }
          final row = rows[index - 1];
          final result = index - 1 < results.length ? results[index - 1] : null;
          final sheetErrors = [
            for (final issue in row.issues)
              switch (issue) {
                YorksV1WorkerSheetIssue.amountInvalid => t(_S.errAmount),
                YorksV1WorkerSheetIssue.totalMismatch => t(_S.errTotal),
              },
          ];
          final serverErrors = [
            for (final code in result?.errors ?? const <String>[])
              t(_errorLabels[code] ?? _S.actionError),
          ];
          final errors = {...sheetErrors, ...serverErrors}.toList();
          final action = errors.isNotEmpty
              ? YorksV1WorkerImportAction.error
              : result?.action ?? YorksV1WorkerImportAction.error;
          final (label, color) = switch (action) {
            YorksV1WorkerImportAction.create => (
              t(_S.actionCreate),
              AppColors.blue,
            ),
            YorksV1WorkerImportAction.update => (
              '${t(_S.actionUpdate)}: ${[for (final field in result!.changedFields) t(_fieldLabels[field] ?? _S.others)].join(', ')}',
              AppColors.success,
            ),
            YorksV1WorkerImportAction.unchanged => (
              t(_S.actionUnchanged),
              AppColors.muted,
            ),
            YorksV1WorkerImportAction.error => (
              errors.join(' · '),
              AppColors.error,
            ),
          };
          return Padding(
            key: ValueKey('worker-import-row-${row.rowNumber}'),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 44,
                  child: Text('${row.rowNumber}', style: cell),
                ),
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.fullName.isEmpty ? '—' : row.fullName,
                        style: cell,
                      ),
                      if (compact)
                        Text(
                          row.company,
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                    ],
                  ),
                ),
                if (!compact)
                  Expanded(
                    flex: 4,
                    child: Text(
                      row.company.isEmpty ? '—' : row.company,
                      style: cell,
                    ),
                  ),
                Expanded(
                  flex: 5,
                  child: Text(label, style: cell.copyWith(color: color)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NewWorkerDefaults extends StatelessWidget {
  const _NewWorkerDefaults({
    required this.language,
    required this.compact,
    required this.enabled,
    required this.designation,
    required this.joiningDate,
    required this.onPickDate,
  });

  final AppLanguage language;
  final bool compact;
  final bool enabled;
  final TextEditingController designation;
  final TextEditingController joiningDate;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    String t(TranslatableString copy) => copy.active(language);
    final designationField = TextFormField(
      key: const ValueKey('worker-import-designation'),
      controller: designation,
      enabled: enabled,
      textCapitalization: TextCapitalization.words,
      inputFormatters: [LengthLimitingTextInputFormatter(120)],
      validator: (value) =>
          (value ?? '').trim().isEmpty ? t(_S.fieldRequired) : null,
      decoration: InputDecoration(labelText: t(_S.designation)),
    );
    final dateField = TextFormField(
      key: const ValueKey('worker-import-joining-date'),
      controller: joiningDate,
      enabled: enabled,
      validator: (value) {
        final text = (value ?? '').trim();
        if (text.isEmpty) return t(_S.fieldRequired);
        return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) &&
                DateTime.tryParse(text) != null
            ? null
            : t(_S.invalidDate);
      },
      decoration: InputDecoration(
        labelText: t(_S.joiningDate),
        hintText: t(_S.joiningDateHint),
        suffixIcon: IconButton(
          onPressed: enabled ? onPickDate : null,
          icon: const Icon(Icons.event_outlined),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t(_S.newWorkerDefaults),
          style: AppTypography.titleSmall.copyWith(color: AppColors.ink),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          t(_S.newWorkerDefaultsHint),
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (compact) ...[
          designationField,
          const SizedBox(height: AppSpacing.md),
          dateField,
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: designationField),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: dateField),
            ],
          ),
      ],
    );
  }
}

/// R39 Accounts Workspace V2 — Progress & claims tab (P6, read view).
///
/// Shows the claim workbench (`v1_get_claim_workbench`): the current open claim
/// (reference, pipeline status, period, gross) and the confirmed progress by
/// building × stage, with the per-item breakdown for items-mode cells. Monetary
/// columns are drawn only with view_project_commercial_values. Confirming
/// progress, editing claim lines and issuing the invoice are a later P6
/// increment; this slice presents the current position read-only.
library;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../shared/models/app_language.dart';
import '../../domain/accounts_decimal.dart';
import '../../domain/v2/claim_workbench_models.dart';
import 'accounts_v2_common.dart';

/// Reopens a checked claim to draft; returns null on success or an error.
typedef YorksReopenClaimAction =
    Future<String?> Function({
      required String claimId,
      required int expectedVersion,
      required String reason,
    });

/// Issues the invoice for a checked claim; returns null on success or an error.
typedef YorksIssueInvoiceAction =
    Future<String?> Function({
      required String claimId,
      required int expectedClaimVersion,
      required String invoiceDate,
      required String submissionDate,
      String? invoiceReference,
    });

/// A selectable evidence document (id + display name) for the progress editor.
typedef YorksAccountsEvidenceDoc = ({String id, String name});

/// Confirms edited progress and rebuilds the draft claim; returns null on
/// success or an error message.
typedef YorksSaveWorkbenchAction =
    Future<String?> Function({
      String? claimReference,
      required String periodStart,
      required String periodEnd,
      required List<Map<String, Object?>> entries,
      required List<String> evidenceDocumentIds,
      String? reason,
    });

class AccountsV2ClaimsTab extends StatefulWidget {
  const AccountsV2ClaimsTab({
    super.key,
    required this.workbench,
    required this.language,
    this.onReopen,
    this.onIssue,
    this.onMarkChecked,
    this.onSaveWorkbench,
    this.canRecordProgress = false,
    this.evidenceDocuments = const [],
  });

  final YorksAccountsWorkbench workbench;
  final AppLanguage language;
  final YorksReopenClaimAction? onReopen;
  final YorksIssueInvoiceAction? onIssue;
  final YorksReopenClaimAction? onMarkChecked;
  final YorksSaveWorkbenchAction? onSaveWorkbench;
  final bool canRecordProgress;
  final List<YorksAccountsEvidenceDoc> evidenceDocuments;

  @override
  State<AccountsV2ClaimsTab> createState() => _AccountsV2ClaimsTabState();
}

class _AccountsV2ClaimsTabState extends State<AccountsV2ClaimsTab> {
  bool _editing = false;

  bool get _canValues =>
      widget.workbench.capabilities['view_project_commercial_values'] == true;

  String _t(String key) => accountsV2Text(widget.language, key);

  List<YorksAccountsWorkbenchCell> get _percentCells => widget.workbench.cells
      .where((c) => !c.isItemsMode)
      .toList(growable: false);

  bool get _showRecordProgress =>
      widget.canRecordProgress &&
      widget.onSaveWorkbench != null &&
      _percentCells.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return _ProgressEditor(
        cells: _percentCells,
        language: widget.language,
        evidenceDocuments: widget.evidenceDocuments,
        onCancel: () => setState(() => _editing = false),
        onSave:
            ({
              String? claimReference,
              required String periodStart,
              required String periodEnd,
              required List<Map<String, Object?>> entries,
              required List<String> evidenceDocumentIds,
              String? reason,
            }) async {
              final error = await widget.onSaveWorkbench!(
                claimReference: claimReference,
                periodStart: periodStart,
                periodEnd: periodEnd,
                entries: entries,
                evidenceDocumentIds: evidenceDocumentIds,
                reason: reason,
              );
              if (mounted && error == null) setState(() => _editing = false);
              return error;
            },
      );
    }

    final workbench = widget.workbench;
    final language = widget.language;
    final onReopen = widget.onReopen;
    final onIssue = widget.onIssue;
    final format = const AccountsV2Format();

    if (workbench.baselineRevisionId == null) {
      return _Empty(message: _t('v2_claims_need_baseline'));
    }

    // Order unique stages by position, keep each stage's cells by building.
    final stageOrder = <String>[];
    final stageLabels = <String, String>{};
    final cellsByStage = <String, List<YorksAccountsWorkbenchCell>>{};
    final sorted = [...workbench.cells]
      ..sort((a, b) {
        final byStage = a.stagePosition.compareTo(b.stagePosition);
        return byStage != 0
            ? byStage
            : a.buildingName.compareTo(b.buildingName);
      });
    for (final c in sorted) {
      if (!stageOrder.contains(c.stageKey)) {
        stageOrder.add(c.stageKey);
        stageLabels[c.stageKey] = c.stageLabel ?? c.stageKey;
      }
      cellsByStage.putIfAbsent(c.stageKey, () => []).add(c);
    }

    final grid = <Widget>[
      for (final stageKey in stageOrder) ...[
        _StageSection(
          title: stageLabels[stageKey] ?? stageKey,
          cells: cellsByStage[stageKey]!,
          canValues: _canValues,
          language: language,
          format: format,
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    ];
    if (grid.isNotEmpty) grid.removeLast();

    if (_showRecordProgress) {
      grid
        ..insert(
          0,
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: () => setState(() => _editing = true),
              icon: const Icon(Icons.edit_note_outlined, size: 16),
              label: Text(_t('v2_record_progress')),
            ),
          ),
        )
        ..insert(1, const SizedBox(height: AppSpacing.lg));
    }

    final aside = _ClaimSidePanel(
      workbench: workbench,
      canValues: _canValues,
      language: language,
      format: format,
      onReopen: onReopen,
      onIssue: onIssue,
      onMarkChecked: widget.onMarkChecked,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= AppSpacing.stackedBreakpoint;
        if (!wide) {
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              aside,
              const SizedBox(height: AppSpacing.lg),
              ...grid,
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: grid,
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                SizedBox(width: AppSpacing.inspectorWidth, child: aside),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ─── Claim side panel ────────────────────────────────────────────────────────

class _ClaimSidePanel extends StatelessWidget {
  const _ClaimSidePanel({
    required this.workbench,
    required this.canValues,
    required this.language,
    required this.format,
    this.onReopen,
    this.onIssue,
    this.onMarkChecked,
  });

  final YorksAccountsWorkbench workbench;
  final bool canValues;
  final AppLanguage language;
  final AccountsV2Format format;
  final YorksReopenClaimAction? onReopen;
  final YorksIssueInvoiceAction? onIssue;
  final YorksReopenClaimAction? onMarkChecked;

  String _t(String key) => accountsV2Text(language, key);

  Future<void> _report(
    BuildContext context,
    String? error,
    String okKey,
  ) async {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(error == null ? _t(okKey) : _t('v2_action_failed')),
      ),
    );
  }

  Future<void> _reopen(
    BuildContext context,
    String claimId,
    int version,
  ) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(
        title: _t('v2_claim_back_to_draft'),
        label: _t('v2_claim_reopen_reason'),
        language: language,
      ),
    );
    if (reason == null) return;
    final error = await onReopen!(
      claimId: claimId,
      expectedVersion: version,
      reason: reason,
    );
    if (context.mounted) await _report(context, error, 'v2_claim_reopened');
  }

  Future<void> _markChecked(
    BuildContext context,
    String claimId,
    int version,
  ) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(
        title: _t('v2_claim_mark_checked'),
        label: _t('v2_claim_mark_reason'),
        language: language,
      ),
    );
    if (reason == null) return;
    final error = await onMarkChecked!(
      claimId: claimId,
      expectedVersion: version,
      reason: reason,
    );
    if (context.mounted) await _report(context, error, 'v2_claim_checked_done');
  }

  Future<void> _issue(BuildContext context, String claimId, int version) async {
    final result = await showDialog<_IssueResult>(
      context: context,
      builder: (_) => _IssueDialog(language: language),
    );
    if (result == null) return;
    final error = await onIssue!(
      claimId: claimId,
      expectedClaimVersion: version,
      invoiceDate: result.invoiceDate,
      submissionDate: result.submissionDate,
      invoiceReference: result.reference,
    );
    if (context.mounted) await _report(context, error, 'v2_claim_issued');
  }

  @override
  Widget build(BuildContext context) {
    final claim = workbench.claim;
    if (claim == null) {
      return AccountsV2Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AccountsV2SectionTitle(_t('v2_claim_title')),
            const SizedBox(height: AppSpacing.sm),
            Text(_t('v2_claims_no_claim'), style: AppTypography.bodyMedium),
          ],
        ),
      );
    }
    final status = claim['status'] as String? ?? 'draft';
    final reference = claim['claim_reference'] as String? ?? '—';
    final periodStart = claim['claim_period_start'] as String?;
    final periodEnd = claim['claim_period_end'] as String?;
    final period = (periodStart != null && periodEnd != null)
        ? '$periodStart → $periodEnd'
        : '—';
    final gross = YorksAccountsDecimal.tryParse(
      claim['claimed_ex_vat'] as String? ?? '',
    );
    final lineCount = (claim['lines'] as List?)?.length ?? 0;
    final claimId = claim['claim_id'] as String?;
    final version = (claim['record_version'] as num?)?.toInt() ?? 1;
    final isChecked = status == 'ready_for_accounts';
    final showIssue = isChecked && onIssue != null && claimId != null;
    final showReopen = isChecked && onReopen != null && claimId != null;
    final showMark =
        status == 'draft' &&
        onMarkChecked != null &&
        claimId != null &&
        lineCount > 0;

    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  reference,
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.ink,
                  ),
                ),
              ),
              _ClaimStatusChip(status: status, language: language),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _ClaimPipeline(status: status, language: language),
          const SizedBox(height: AppSpacing.md),
          _PanelRow(label: _t('v2_claim_period'), value: period),
          _PanelRow(label: _t('v2_claim_lines'), value: '$lineCount'),
          if (canValues)
            _PanelRow(
              label: _t('v2_claim_gross'),
              value: format.money(gross),
              emphasize: true,
            ),
          if (showIssue || showReopen || showMark) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1, color: AppColors.line),
            const SizedBox(height: AppSpacing.md),
            if (showMark)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _markChecked(context, claimId, version),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: Text(_t('v2_claim_mark_checked')),
                ),
              ),
            if (showIssue)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _issue(context, claimId, version),
                  icon: const Icon(Icons.receipt_long_outlined, size: 16),
                  label: Text(_t('v2_claim_issue')),
                ),
              ),
            if (showIssue && showReopen) const SizedBox(height: AppSpacing.sm),
            if (showReopen)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _reopen(context, claimId, version),
                  icon: const Icon(Icons.undo_outlined, size: 16),
                  label: Text(_t('v2_claim_back_to_draft')),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ClaimPipeline extends StatelessWidget {
  const _ClaimPipeline({required this.status, required this.language});

  final String status;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final steps = <(String, int)>[
      (accountsV2Text(language, 'v2_claim_status_draft'), 0),
      (accountsV2Text(language, 'v2_claim_status_checked'), 1),
      (accountsV2Text(language, 'v2_claim_status_invoiced'), 2),
    ];
    final current = switch (status) {
      'ready_for_accounts' => 1,
      'invoiced' => 2,
      _ => 0,
    };
    return Row(
      children: [
        for (final step in steps) ...[
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: step.$2 <= current
                        ? AppColors.primary
                        : AppColors.line,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  step.$1,
                  style: AppTypography.labelSmall.copyWith(
                    color: step.$2 == current
                        ? AppColors.primary
                        : AppColors.muted,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                ),
              ],
            ),
          ),
          if (step.$2 < 2) const SizedBox(width: AppSpacing.xs),
        ],
      ],
    );
  }
}

class _ClaimStatusChip extends StatelessWidget {
  const _ClaimStatusChip({required this.status, required this.language});

  final String status;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final (key, tone) = switch (status) {
      'invoiced' => ('v2_claim_status_invoiced', NexusStatusTone.success),
      'ready_for_accounts' => ('v2_claim_status_checked', NexusStatusTone.info),
      _ => ('v2_claim_status_draft', NexusStatusTone.neutral),
    };
    return StatusChip(label: accountsV2Text(language, key), tone: tone);
  }
}

class _PanelRow extends StatelessWidget {
  const _PanelRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style:
                  (emphasize
                          ? AppTypography.titleSmall
                          : AppTypography.bodyMedium)
                      .copyWith(
                        color: AppColors.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Stage section (progress grid) ───────────────────────────────────────────

class _StageSection extends StatelessWidget {
  const _StageSection({
    required this.title,
    required this.cells,
    required this.canValues,
    required this.language,
    required this.format,
  });

  final String title;
  final List<YorksAccountsWorkbenchCell> cells;
  final bool canValues;
  final AppLanguage language;
  final AccountsV2Format format;

  @override
  Widget build(BuildContext context) {
    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(title),
          const SizedBox(height: AppSpacing.sm),
          for (final cell in cells) ...[
            _CellRow(
              cell: cell,
              canValues: canValues,
              language: language,
              format: format,
            ),
            if (cell.isItemsMode && cell.items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.md,
                  bottom: AppSpacing.xs,
                ),
                child: Column(
                  children: [
                    for (final item in cell.items)
                      _ItemRow(
                        item: item,
                        canValues: canValues,
                        language: language,
                        format: format,
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CellRow extends StatelessWidget {
  const _CellRow({
    required this.cell,
    required this.canValues,
    required this.language,
    required this.format,
  });

  final YorksAccountsWorkbenchCell cell;
  final bool canValues;
  final AppLanguage language;
  final AccountsV2Format format;

  @override
  Widget build(BuildContext context) {
    final nameAndPercent = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cell.buildingName,
                style: AppTypography.bodyMedium.copyWith(color: AppColors.ink),
              ),
              if (cell.isItemsMode)
                Text(
                  accountsV2Text(language, 'v2_mode_items'),
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          width: 68,
          child: Text(
            format.percent(cell.confirmedPercent),
            textAlign: TextAlign.end,
            style: AppTypography.bodyMedium.copyWith(color: AppColors.ink),
          ),
        ),
      ],
    );
    final moneyCols = <Widget>[
      if (canValues) ...[
        _MoneyCol(
          label: accountsV2Text(language, 'v2_col_eligible'),
          value: format.money(cell.eligible),
        ),
        _MoneyCol(
          label: accountsV2Text(language, 'v2_col_claimed'),
          value: format.money(cell.claimed),
        ),
        _MoneyCol(
          label: accountsV2Text(language, 'v2_col_available'),
          value: format.money(cell.available),
          danger: cell.overClaimed,
        ),
      ],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Fixed money columns need ~430px; stack them below on a narrow tab.
          final narrow = constraints.maxWidth < 440;
          if (!narrow) {
            return Row(
              children: [
                Expanded(child: nameAndPercent),
                ...moneyCols,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              nameAndPercent,
              if (moneyCols.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xxs),
                  child: Wrap(
                    spacing: AppSpacing.lg,
                    runSpacing: AppSpacing.xs,
                    children: moneyCols,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MoneyCol extends StatelessWidget {
  const _MoneyCol({
    required this.label,
    required this.value,
    this.danger = false,
  });

  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
          ),
          Text(
            value,
            style: AppTypography.bodyMedium.copyWith(
              color: danger ? AppColors.error : AppColors.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.canValues,
    required this.language,
    required this.format,
  });

  final YorksAccountsWorkbenchItem item;
  final bool canValues;
  final AppLanguage language;
  final AccountsV2Format format;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    item.itemLabel,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.inkSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (item.needsReview) ...[
                  const SizedBox(width: AppSpacing.xs),
                  StatusChip.warning(
                    accountsV2Text(language, 'v2_needs_review'),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              '${item.confirmedQty.displayText(maximumFractionDigits: 2)} / ${item.quantity.displayText(maximumFractionDigits: 2)} ${item.unitCode}',
              textAlign: TextAlign.end,
              style: AppTypography.bodySmall,
            ),
          ),
          if (canValues)
            SizedBox(
              width: 120,
              child: Text(
                format.money(item.itemValue),
                textAlign: TextAlign.end,
                style: AppTypography.bodySmall.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Empty state ─────────────────────────────────────────────────────────────

class _Empty extends StatelessWidget {
  const _Empty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.timeline_outlined,
              size: 32,
              color: AppColors.muted,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: AppTypography.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Command dialogs ─────────────────────────────────────────────────────────

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.label,
    required this.language,
  });

  final String title;
  final String label;
  final AppLanguage language;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  String _t(String key) => accountsV2Text(widget.language, key);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _controller.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 1,
        maxLines: 3,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_t('v2_cancel')),
        ),
        FilledButton(
          onPressed: valid
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
          child: Text(_t('v2_confirm')),
        ),
      ],
    );
  }
}

class _IssueResult {
  const _IssueResult({
    required this.invoiceDate,
    required this.submissionDate,
    this.reference,
  });

  final String invoiceDate;
  final String submissionDate;
  final String? reference;
}

class _IssueDialog extends StatefulWidget {
  const _IssueDialog({required this.language});

  final AppLanguage language;

  @override
  State<_IssueDialog> createState() => _IssueDialogState();
}

class _IssueDialogState extends State<_IssueDialog> {
  late final TextEditingController _invoiceDate;
  late final TextEditingController _submissionDate;
  final _reference = TextEditingController();

  String _t(String key) => accountsV2Text(widget.language, key);

  static String _today() {
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  static final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  @override
  void initState() {
    super.initState();
    final today = _today();
    _invoiceDate = TextEditingController(text: today);
    _submissionDate = TextEditingController(text: today);
  }

  @override
  void dispose() {
    _invoiceDate.dispose();
    _submissionDate.dispose();
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid =
        _datePattern.hasMatch(_invoiceDate.text.trim()) &&
        _datePattern.hasMatch(_submissionDate.text.trim());
    InputDecoration deco(String label) => InputDecoration(
      labelText: label,
      hintText: 'YYYY-MM-DD',
      border: const OutlineInputBorder(),
    );
    return AlertDialog(
      title: Text(_t('v2_claim_issue')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _invoiceDate,
            onChanged: (_) => setState(() {}),
            decoration: deco(_t('v2_claim_invoice_date')),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _submissionDate,
            onChanged: (_) => setState(() {}),
            decoration: deco(_t('v2_claim_submission_date')),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _reference,
            decoration: deco(_t('v2_claim_reference_opt')),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_t('v2_cancel')),
        ),
        FilledButton(
          onPressed: valid
              ? () {
                  final ref = _reference.text.trim();
                  Navigator.of(context).pop(
                    _IssueResult(
                      invoiceDate: _invoiceDate.text.trim(),
                      submissionDate: _submissionDate.text.trim(),
                      reference: ref.isEmpty ? null : ref,
                    ),
                  );
                }
              : null,
          child: Text(_t('v2_confirm')),
        ),
      ],
    );
  }
}

// ─── Progress editor (percent-mode confirm) ──────────────────────────────────

class _ProgressEditor extends StatefulWidget {
  const _ProgressEditor({
    required this.cells,
    required this.language,
    required this.evidenceDocuments,
    required this.onCancel,
    required this.onSave,
  });

  final List<YorksAccountsWorkbenchCell> cells;
  final AppLanguage language;
  final List<YorksAccountsEvidenceDoc> evidenceDocuments;
  final VoidCallback onCancel;
  final YorksSaveWorkbenchAction onSave;

  @override
  State<_ProgressEditor> createState() => _ProgressEditorState();
}

class _ProgressEditorState extends State<_ProgressEditor> {
  final Map<String, TextEditingController> _pct = {};
  late final TextEditingController _start;
  late final TextEditingController _end;
  final _reason = TextEditingController();
  final Set<String> _evidence = {};
  bool _saving = false;

  static final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  String _t(String key) => accountsV2Text(widget.language, key);

  @override
  void initState() {
    super.initState();
    final today = accountsV2TodayIso();
    _start = TextEditingController(text: today);
    _end = TextEditingController(text: today);
    for (final c in widget.cells) {
      _pct[c.progressEntryId] = TextEditingController(
        text: c.confirmedPercent.canonicalText,
      );
    }
    for (final c in _pct.values) {
      c.addListener(_onChanged);
    }
    _start.addListener(_onChanged);
    _end.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_start, _end, _reason, ..._pct.values]) {
      c.dispose();
    }
    super.dispose();
  }

  List<Map<String, Object?>> _entries() {
    final out = <Map<String, Object?>>[];
    for (final c in widget.cells) {
      final text = _pct[c.progressEntryId]!.text.trim();
      final parsed = YorksAccountsDecimal.tryParse(text);
      if (parsed == null) continue;
      if (parsed.compareTo(c.confirmedPercent) != 0) {
        out.add({
          'progress_entry_id': c.progressEntryId,
          'confirmed_percent_to_date': text,
        });
      }
    }
    return out;
  }

  bool get _hasIncrease {
    for (final c in widget.cells) {
      final parsed = YorksAccountsDecimal.tryParse(
        _pct[c.progressEntryId]!.text.trim(),
      );
      if (parsed != null && parsed.compareTo(c.confirmedPercent) > 0) {
        return true;
      }
    }
    return false;
  }

  bool get _datesValid =>
      _datePattern.hasMatch(_start.text.trim()) &&
      _datePattern.hasMatch(_end.text.trim());

  Future<void> _save() async {
    final entries = _entries();
    // Capture the messenger before the await: on success the parent leaves edit
    // mode and disposes this editor, so a post-await `mounted` guard would
    // swallow the confirmation toast.
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _saving = true);
    final error = await widget.onSave(
      periodStart: _start.text.trim(),
      periodEnd: _end.text.trim(),
      entries: entries,
      evidenceDocumentIds: _evidence.toList(growable: false),
      reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
    );
    if (mounted) setState(() => _saving = false);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          error == null ? _t('v2_progress_saved') : _t('v2_action_failed'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries();
    final needsEvidence = _hasIncrease && _evidence.isEmpty;
    final canSave =
        !_saving && _datesValid && entries.isNotEmpty && !needsEvidence;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AccountsV2Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AccountsV2SectionTitle(_t('v2_record_progress')),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: _ProgressField(
                      label: _t('v2_progress_period_start'),
                      controller: _start,
                      hint: 'YYYY-MM-DD',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _ProgressField(
                      label: _t('v2_progress_period_end'),
                      controller: _end,
                      hint: 'YYYY-MM-DD',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AccountsV2Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AccountsV2SectionTitle(_t('v2_progress_this_claim')),
              const SizedBox(height: AppSpacing.sm),
              if (widget.cells.isEmpty)
                Text(
                  _t('v2_progress_no_percent_cells'),
                  style: AppTypography.bodyMedium,
                )
              else
                for (final c in widget.cells)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${c.buildingName} · ${c.stageLabel ?? c.stageKey}',
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: _pct[c.progressEntryId],
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textAlign: TextAlign.end,
                            decoration: const InputDecoration(
                              isDense: true,
                              suffixText: '%',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _EvidencePicker(
          documents: widget.evidenceDocuments,
          selected: _evidence,
          language: widget.language,
          required: needsEvidence,
          onToggle: (id, on) => setState(() {
            if (on) {
              _evidence.add(id);
            } else {
              _evidence.remove(id);
            }
          }),
        ),
        const SizedBox(height: AppSpacing.lg),
        AccountsV2Card(
          child: _ProgressField(
            label: _t('v2_progress_reason_opt'),
            controller: _reason,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            FilledButton(
              onPressed: canSave ? _save : null,
              child: Text(_saving ? _t('v2_saving') : _t('v2_save')),
            ),
            const SizedBox(width: AppSpacing.sm),
            OutlinedButton(
              onPressed: _saving ? null : widget.onCancel,
              child: Text(_t('v2_cancel')),
            ),
            if (_saving) ...[
              const SizedBox(width: AppSpacing.md),
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _EvidencePicker extends StatelessWidget {
  const _EvidencePicker({
    required this.documents,
    required this.selected,
    required this.language,
    required this.required,
    required this.onToggle,
  });

  final List<YorksAccountsEvidenceDoc> documents;
  final Set<String> selected;
  final AppLanguage language;
  final bool required;
  final void Function(String id, bool on) onToggle;

  @override
  Widget build(BuildContext context) {
    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(
            '${accountsV2Text(language, 'v2_progress_evidence')}'
            '${selected.isEmpty ? '' : ' · ${selected.length} '
                      '${accountsV2Text(language, 'v2_evidence_selected')}'}',
          ),
          const SizedBox(height: AppSpacing.sm),
          if (documents.isEmpty)
            Text(
              accountsV2Text(language, 'v2_evidence_none_available'),
              style: AppTypography.bodyMedium,
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final doc in documents)
                  FilterChip(
                    label: Text(doc.name),
                    selected: selected.contains(doc.id),
                    onSelected: (on) => onToggle(doc.id, on),
                  ),
              ],
            ),
          if (required) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              accountsV2Text(language, 'v2_progress_evidence_required'),
              style: AppTypography.bodySmall.copyWith(color: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgressField extends StatelessWidget {
  const _ProgressField({
    required this.label,
    required this.controller,
    this.hint,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

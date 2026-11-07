/// R39 Accounts Workspace V2 — project cheque (PDC) register card (P8).
///
/// A standalone card on the Invoices & payments tab that lists every client
/// post-dated cheque for the project (from v1_list_project_client_pdcs) with its
/// lifecycle status, and drives the In hand → Deposited → Cleared / Bounced /
/// Returned transitions through the existing receivables transition command.
/// Every step can be walked back and a cheque's details edited. A cheque reduces
/// the amount due only once it clears. The whole card is drawn
/// only for an actor with view_project_commercial_values (cheques are
/// commercial), and the Update action only with manage_pdc.
library;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../shared/models/app_language.dart';
import '../../domain/accounts_decimal.dart';
import '../../domain/accounts_receivables_inputs.dart';
import '../../domain/v2/pdc_register_models.dart';
import 'accounts_v2_common.dart';

/// Runs a cheque lifecycle transition; returns null on success or an error
/// message (a version conflict resolves on reload).
typedef YorksPdcTransitionAction =
    Future<String?> Function(YorksAccountsPdcTransitionInput input);

/// Replaces a returned/bounced cheque with a re-presented one; returns null on
/// success or an error message.
typedef YorksPdcReplaceAction =
    Future<String?> Function(YorksAccountsPdcReplacementInput input);

/// Edits a cheque's details; returns null on success or an error message.
typedef YorksPdcEditAction =
    Future<String?> Function(YorksAccountsPdcEditInput input);

class AccountsV2PdcRegisterCard extends StatelessWidget {
  const AccountsV2PdcRegisterCard({
    super.key,
    required this.projectId,
    required this.register,
    required this.language,
    required this.canManage,
    this.onTransition,
    this.onReplace,
    this.onEdit,
  });

  final String projectId;
  final YorksAccountsProjectPdcRegister register;
  final AppLanguage language;

  /// Whether the actor holds manage_pdc. The Update control is hidden without
  /// it; the server re-checks regardless.
  final bool canManage;
  final YorksPdcTransitionAction? onTransition;
  final YorksPdcReplaceAction? onReplace;
  final YorksPdcEditAction? onEdit;

  String _t(String key) => accountsV2Text(language, key);

  bool get _showAction =>
      canManage &&
      (onTransition != null || onReplace != null || onEdit != null);

  bool _hasMenu(YorksAccountsProjectPdc pdc) =>
      (onEdit != null && pdc.canEditDetails) ||
      (onTransition != null && pdc.nextStatuses.isNotEmpty);

  bool _canReplace(YorksAccountsProjectPdc pdc) =>
      onReplace != null &&
      (pdc.status == YorksAccountsPdcStatus.returned ||
          pdc.status == YorksAccountsPdcStatus.bounced);

  Future<void> _transition(
    BuildContext context,
    YorksAccountsProjectPdc pdc,
    YorksAccountsPdcStatus target,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final input = await showDialog<YorksAccountsPdcTransitionInput>(
      context: context,
      builder: (_) => _PdcTransitionDialog(
        projectId: projectId,
        pdc: pdc,
        target: target,
        language: language,
      ),
    );
    if (input == null) return;
    final error = await onTransition!(input);
    if (!context.mounted) return;
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          error == null
              ? _t('v2_pdc_saved')
              : accountsV2ErrorText(language, error),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, YorksAccountsProjectPdc pdc) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final input = await showDialog<YorksAccountsPdcEditInput>(
      context: context,
      builder: (_) =>
          _PdcEditDialog(projectId: projectId, pdc: pdc, language: language),
    );
    if (input == null) return;
    final error = await onEdit!(input);
    if (!context.mounted) return;
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          error == null
              ? _t('v2_pdc_saved')
              : accountsV2ErrorText(language, error),
        ),
      ),
    );
  }

  Future<void> _replace(
    BuildContext context,
    YorksAccountsProjectPdc pdc,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final input = await showDialog<YorksAccountsPdcReplacementInput>(
      context: context,
      builder: (_) => _PdcReplacementDialog(
        projectId: projectId,
        pdc: pdc,
        language: language,
      ),
    );
    if (input == null) return;
    final error = await onReplace!(input);
    if (!context.mounted) return;
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          error == null
              ? _t('v2_pdc_saved')
              : accountsV2ErrorText(language, error),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final format = const AccountsV2Format();
    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(_t('v2_pdc_register_title')),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            _t('v2_pdc_register_hint'),
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (register.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(_t('v2_pdc_empty'), style: AppTypography.bodyMedium),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < AppSpacing.compactBreakpoint) {
                  return Column(
                    children: [
                      for (final pdc in register.pdcs)
                        _chequeCard(context, pdc, format),
                    ],
                  );
                }
                return _table(context, format);
              },
            ),
        ],
      ),
    );
  }

  Widget _chequeCard(
    BuildContext context,
    YorksAccountsProjectPdc pdc,
    AccountsV2Format format,
  ) {
    Widget plain(String text) => Text(
      text,
      style: AppTypography.bodyMedium.copyWith(color: AppColors.ink),
    );
    return AccountsV2RecordCard(
      title: Text(
        pdc.chequeNumber,
        style: AppTypography.bodyMedium.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
        ),
      ),
      status: PdcStatusChip(status: pdc.status, language: language),
      facts: [
        (_t('v2_pdc_col_invoice'), plain(pdc.invoiceReference)),
        (_t('v2_pdc_col_bank'), plain(pdc.bankName ?? '—')),
        (_t('v2_pdc_col_cheque_date'), plain(pdc.chequeDate.postgresText)),
        (_t('v2_pdc_col_amount'), plain(format.money(pdc.amount))),
        if (pdc.actionRequired)
          (
            _t('v2_pdc_col_status'),
            StatusChip.warning(_t('v2_pdc_needs_action')),
          ),
      ],
      actions: [
        if (_showAction && (_canReplace(pdc) || _hasMenu(pdc)))
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTapTarget,
            ),
            child: Center(widthFactor: 1, child: _actionCell(context, pdc)),
          ),
      ],
    );
  }

  Widget _table(BuildContext context, AccountsV2Format format) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: AppSpacing.xl,
        headingRowHeight: 36,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 56,
        columns: [
          DataColumn(label: Text(_t('v2_pdc_col_cheque'))),
          DataColumn(label: Text(_t('v2_pdc_col_invoice'))),
          DataColumn(label: Text(_t('v2_pdc_col_bank'))),
          DataColumn(label: Text(_t('v2_pdc_col_cheque_date'))),
          DataColumn(label: Text(_t('v2_pdc_col_amount')), numeric: true),
          DataColumn(label: Text(_t('v2_pdc_col_status'))),
          if (_showAction) DataColumn(label: Text(_t('v2_pdc_col_action'))),
        ],
        rows: [
          for (final pdc in register.pdcs)
            DataRow(
              cells: [
                DataCell(
                  Text(
                    pdc.chequeNumber,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                DataCell(Text(pdc.invoiceReference)),
                DataCell(Text(pdc.bankName ?? '—')),
                DataCell(Text(pdc.chequeDate.postgresText)),
                DataCell(Text(format.money(pdc.amount, withCurrency: false))),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PdcStatusChip(status: pdc.status, language: language),
                      if (pdc.actionRequired) ...[
                        const SizedBox(width: AppSpacing.xs),
                        StatusChip.warning(_t('v2_pdc_needs_action')),
                      ],
                    ],
                  ),
                ),
                if (_showAction) DataCell(_actionCell(context, pdc)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _actionCell(BuildContext context, YorksAccountsProjectPdc pdc) {
    if (!_canReplace(pdc) && !_hasMenu(pdc)) return const Text('—');
    return _menu(context, pdc);
  }

  /// Written for what the step means, so walking back never reads like moving on.
  String _moveLabel(YorksAccountsProjectPdc pdc, YorksAccountsPdcStatus to) {
    final key = switch ((pdc.status, to)) {
      (YorksAccountsPdcStatus.cleared, YorksAccountsPdcStatus.deposited) =>
        'v2_pdc_undo_clearing',
      (YorksAccountsPdcStatus.cleared, YorksAccountsPdcStatus.bounced) =>
        'v2_pdc_bounced_after',
      (YorksAccountsPdcStatus.cleared, YorksAccountsPdcStatus.returned) =>
        'v2_pdc_returned_after',
      (YorksAccountsPdcStatus.received, YorksAccountsPdcStatus.expected) =>
        'v2_pdc_undo_received',
      (YorksAccountsPdcStatus.deposited, YorksAccountsPdcStatus.received) =>
        'v2_pdc_undo_deposited',
      (YorksAccountsPdcStatus.bounced, YorksAccountsPdcStatus.received) ||
      (
        YorksAccountsPdcStatus.returned,
        YorksAccountsPdcStatus.received,
      ) => 'v2_pdc_represent',
      (YorksAccountsPdcStatus.cancelled, YorksAccountsPdcStatus.expected) =>
        'v2_pdc_restore',
      _ => _statusKey(to),
    };
    return _t(key);
  }

  Widget _menu(BuildContext context, YorksAccountsProjectPdc pdc) {
    final next = onTransition == null
        ? const <YorksAccountsPdcStatus>[]
        : pdc.nextStatuses;
    const edit = 'edit';
    const replace = 'replace';
    return PopupMenuButton<String>(
      onSelected: (choice) {
        if (choice == edit) {
          _edit(context, pdc);
        } else if (choice == replace) {
          _replace(context, pdc);
        } else {
          _transition(
            context,
            pdc,
            next.firstWhere((target) => target.name == choice),
          );
        }
      },
      itemBuilder: (_) => [
        for (final target in next)
          PopupMenuItem<String>(
            value: target.name,
            child: Text(_moveLabel(pdc, target)),
          ),
        if (_canReplace(pdc))
          PopupMenuItem<String>(
            value: replace,
            child: Text(_t('v2_pdc_replace')),
          ),
        if (onEdit != null && pdc.canEditDetails)
          PopupMenuItem<String>(value: edit, child: Text(_t('v2_pdc_edit'))),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _t('v2_pdc_update'),
            style: AppTypography.bodyMedium.copyWith(color: AppColors.primary),
          ),
          const Icon(Icons.arrow_drop_down, size: 20, color: AppColors.primary),
        ],
      ),
    );
  }
}

String _statusKey(YorksAccountsPdcStatus status) => switch (status) {
  YorksAccountsPdcStatus.expected => 'v2_pdc_expected',
  YorksAccountsPdcStatus.received => 'v2_pdc_received',
  YorksAccountsPdcStatus.deposited => 'v2_pdc_deposited',
  YorksAccountsPdcStatus.cleared => 'v2_pdc_cleared',
  YorksAccountsPdcStatus.replaced => 'v2_pdc_replaced',
  YorksAccountsPdcStatus.returned => 'v2_pdc_returned',
  YorksAccountsPdcStatus.bounced => 'v2_pdc_bounced',
  YorksAccountsPdcStatus.cancelled => 'v2_pdc_cancelled',
};

/// Shared status chip for a cheque, reused by the register and the invoice
/// drawer.
class PdcStatusChip extends StatelessWidget {
  const PdcStatusChip({
    super.key,
    required this.status,
    required this.language,
  });

  final YorksAccountsPdcStatus status;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final tone = switch (status) {
      YorksAccountsPdcStatus.expected => NexusStatusTone.neutral,
      YorksAccountsPdcStatus.received => NexusStatusTone.info,
      YorksAccountsPdcStatus.deposited => NexusStatusTone.info,
      YorksAccountsPdcStatus.cleared => NexusStatusTone.success,
      YorksAccountsPdcStatus.replaced => NexusStatusTone.neutral,
      YorksAccountsPdcStatus.returned => NexusStatusTone.warning,
      YorksAccountsPdcStatus.bounced => NexusStatusTone.danger,
      YorksAccountsPdcStatus.cancelled => NexusStatusTone.neutral,
    };
    return StatusChip(
      label: accountsV2Text(language, _statusKey(status)),
      tone: tone,
    );
  }
}

// ─── Transition dialog ───────────────────────────────────────────────────────

class _PdcTransitionDialog extends StatefulWidget {
  const _PdcTransitionDialog({
    required this.projectId,
    required this.pdc,
    required this.target,
    required this.language,
  });

  final String projectId;
  final YorksAccountsProjectPdc pdc;
  final YorksAccountsPdcStatus target;
  final AppLanguage language;

  @override
  State<_PdcTransitionDialog> createState() => _PdcTransitionDialogState();
}

class _PdcTransitionDialogState extends State<_PdcTransitionDialog> {
  late final TextEditingController _date;
  final _clearance = TextEditingController();
  final _reason = TextEditingController();

  String _t(String key) => accountsV2Text(widget.language, key);

  bool get _needsClearance => widget.target == YorksAccountsPdcStatus.cleared;

  bool get _needsReason =>
      widget.target == YorksAccountsPdcStatus.returned ||
      widget.target == YorksAccountsPdcStatus.bounced ||
      widget.target == YorksAccountsPdcStatus.cancelled ||
      widget.pdc.isBackwardMove(widget.target);

  bool get _takesMoneyBack =>
      widget.pdc.status == YorksAccountsPdcStatus.cleared;

  @override
  void initState() {
    super.initState();
    _date = TextEditingController(text: accountsV2TodayIso());
  }

  @override
  void dispose() {
    _date.dispose();
    _clearance.dispose();
    _reason.dispose();
    super.dispose();
  }

  YorksAccountsPdcTransitionInput? _build() {
    final date = YorksAccountsDate.tryParse(_date.text.trim());
    if (date == null) return null;
    final clearance = _clearance.text.trim();
    final reason = _reason.text.trim();
    return YorksAccountsPdcTransitionInput(
      projectId: widget.projectId,
      pdcId: widget.pdc.pdcId,
      expectedVersion: widget.pdc.recordVersion,
      targetStatus: widget.target,
      actionDate: date,
      clearanceReference: clearance.isEmpty ? null : clearance,
      reason: reason.isEmpty ? null : reason,
    );
  }

  @override
  Widget build(BuildContext context) {
    final input = _build();
    final valid =
        input != null &&
        input.isValid &&
        (!_needsReason || _reason.text.trim().isNotEmpty);
    return AlertDialog(
      title: Text(_t('v2_pdc_transition_title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.pdc.chequeNumber} → '
            '${accountsV2Text(widget.language, _statusKey(widget.target))}',
            style: AppTypography.bodyMedium.copyWith(color: AppColors.ink),
          ),
          if (_takesMoneyBack) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _t('v2_pdc_undo_money_hint'),
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          AccountsV2DateField(
            label: _t('v2_pdc_action_date'),
            controller: _date,
            language: widget.language,
            onChanged: () => setState(() {}),
          ),
          if (_needsClearance) ...[
            const SizedBox(height: AppSpacing.sm),
            _Field(
              label: _t('v2_pdc_clearance_ref'),
              controller: _clearance,
              onChanged: () => setState(() {}),
            ),
          ],
          if (_needsReason) ...[
            const SizedBox(height: AppSpacing.sm),
            _Field(
              label: _t('v2_pdc_reason'),
              controller: _reason,
              onChanged: () => setState(() {}),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_t('v2_cancel')),
        ),
        FilledButton(
          onPressed: valid ? () => Navigator.of(context).pop(input) : null,
          child: Text(_t('v2_confirm')),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.numeric = false,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final bool numeric;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      onChanged: onChanged == null ? null : (_) => onChanged!(),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

// ─── Cheque edit dialog ──────────────────────────────────────────────────────

class _PdcEditDialog extends StatefulWidget {
  const _PdcEditDialog({
    required this.projectId,
    required this.pdc,
    required this.language,
  });

  final String projectId;
  final YorksAccountsProjectPdc pdc;
  final AppLanguage language;

  @override
  State<_PdcEditDialog> createState() => _PdcEditDialogState();
}

class _PdcEditDialogState extends State<_PdcEditDialog> {
  late final TextEditingController _cheque;
  late final TextEditingController _date;
  late final TextEditingController _amount;
  late final TextEditingController _bank;
  final _reason = TextEditingController();

  String _t(String key) => accountsV2Text(widget.language, key);

  @override
  void initState() {
    super.initState();
    _cheque = TextEditingController(text: widget.pdc.chequeNumber);
    _date = TextEditingController(text: widget.pdc.chequeDate.postgresText);
    _amount = TextEditingController(text: widget.pdc.amount.canonicalText);
    _bank = TextEditingController(text: widget.pdc.bankName ?? '');
  }

  @override
  void dispose() {
    _cheque.dispose();
    _date.dispose();
    _amount.dispose();
    _bank.dispose();
    _reason.dispose();
    super.dispose();
  }

  YorksAccountsPdcEditInput? _build() {
    final date = YorksAccountsDate.tryParse(_date.text.trim());
    final amount = YorksAccountsDecimal.tryParse(_amount.text.trim());
    if (date == null || amount == null) return null;
    final bank = _bank.text.trim();
    return YorksAccountsPdcEditInput(
      projectId: widget.projectId,
      pdcId: widget.pdc.pdcId,
      expectedVersion: widget.pdc.recordVersion,
      chequeNumber: _cheque.text.trim(),
      chequeDate: date,
      amount: amount,
      bankName: bank.isEmpty ? null : bank,
      reason: _reason.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final input = _build();
    final valid = input != null && input.isValid;
    return AlertDialog(
      title: Text(_t('v2_pdc_edit_title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Field(
              label: _t('v2_pdc_col_cheque'),
              controller: _cheque,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            AccountsV2DateField(
              label: _t('v2_pdc_col_cheque_date'),
              controller: _date,
              language: widget.language,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            _Field(
              label: _t('v2_pdc_col_amount'),
              controller: _amount,
              numeric: true,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            _Field(
              label: _t('v2_pdc_col_bank'),
              controller: _bank,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            _Field(
              label: _t('v2_pdc_reason'),
              controller: _reason,
              onChanged: () => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_t('v2_cancel')),
        ),
        FilledButton(
          onPressed: valid ? () => Navigator.of(context).pop(input) : null,
          child: Text(_t('v2_confirm')),
        ),
      ],
    );
  }
}

// ─── Cheque replacement dialog ───────────────────────────────────────────────

class _PdcReplacementDialog extends StatefulWidget {
  const _PdcReplacementDialog({
    required this.projectId,
    required this.pdc,
    required this.language,
  });

  final String projectId;
  final YorksAccountsProjectPdc pdc;
  final AppLanguage language;

  @override
  State<_PdcReplacementDialog> createState() => _PdcReplacementDialogState();
}

class _PdcReplacementDialogState extends State<_PdcReplacementDialog> {
  late final TextEditingController _cheque;
  late final TextEditingController _date;
  late final TextEditingController _amount;
  late final TextEditingController _bank;
  final _reason = TextEditingController();

  String _t(String key) => accountsV2Text(widget.language, key);

  @override
  void initState() {
    super.initState();
    _cheque = TextEditingController();
    _date = TextEditingController(text: accountsV2TodayIso());
    _amount = TextEditingController(text: widget.pdc.amount.canonicalText);
    _bank = TextEditingController(text: widget.pdc.bankName ?? '');
  }

  @override
  void dispose() {
    _cheque.dispose();
    _date.dispose();
    _amount.dispose();
    _bank.dispose();
    _reason.dispose();
    super.dispose();
  }

  YorksAccountsPdcReplacementInput? _build() {
    final date = YorksAccountsDate.tryParse(_date.text.trim());
    final amount = YorksAccountsDecimal.tryParse(_amount.text.trim());
    if (date == null || amount == null) return null;
    final bank = _bank.text.trim();
    return YorksAccountsPdcReplacementInput(
      projectId: widget.projectId,
      originalPdcId: widget.pdc.pdcId,
      expectedVersion: widget.pdc.recordVersion,
      chequeNumber: _cheque.text.trim(),
      chequeDate: date,
      amount: amount,
      bankName: bank.isEmpty ? null : bank,
      reason: _reason.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final input = _build();
    final valid = input != null && input.isValid;
    return AlertDialog(
      title: Text(_t('v2_pdc_replace_title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.pdc.chequeNumber,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.ink),
            ),
            const SizedBox(height: AppSpacing.sm),
            _Field(
              label: _t('v2_pdc_replace_cheque'),
              controller: _cheque,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            AccountsV2DateField(
              label: _t('v2_pdc_replace_date'),
              controller: _date,
              language: widget.language,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            _Field(
              label: _t('v2_pdc_replace_amount'),
              controller: _amount,
              numeric: true,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            _Field(
              label: _t('v2_pdc_replace_bank'),
              controller: _bank,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            _Field(
              label: _t('v2_pdc_reason'),
              controller: _reason,
              onChanged: () => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_t('v2_cancel')),
        ),
        FilledButton(
          onPressed: valid ? () => Navigator.of(context).pop(input) : null,
          child: Text(_t('v2_confirm')),
        ),
      ],
    );
  }
}

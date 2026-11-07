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
import '../../../../shared/models/app_language.dart';
import '../../domain/accounts_decimal.dart';
import '../../domain/accounts_receivables_inputs.dart';
import '../../domain/v2/pdc_register_models.dart';
import 'accounts_v2_common.dart';
import 'kit/accounts_v2_kit.dart';

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
    int count(YorksAccountsPdcStatus s) =>
        register.pdcs.where((p) => p.status == s).length;
    final inHand = count(YorksAccountsPdcStatus.received);
    final deposited = count(YorksAccountsPdcStatus.deposited);
    final cleared = count(YorksAccountsPdcStatus.cleared);
    final bounced =
        count(YorksAccountsPdcStatus.bounced) +
        count(YorksAccountsPdcStatus.returned);
    return AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2TileHead(
            icon: 'cheque',
            tone: AccountsV2Tone.vio,
            title: _t('v2i_pdc_title'),
            subtitle:
                '${_t('v2i_pdc_sub_a')} ${_t('v2i_pdc_sub_b')}${_t('v2i_pdc_sub_c')}',
            actions: [
              if (inHand > 0)
                AccountsV2Chip(
                  '$inHand ${_t('v2i_ps_inhand').toLowerCase()}',
                  tone: AccountsV2ChipTone.vio,
                ),
              if (deposited > 0)
                AccountsV2Chip(
                  '$deposited ${_t('v2i_ps_deposited').toLowerCase()}',
                  tone: AccountsV2ChipTone.pri,
                ),
              if (cleared > 0)
                AccountsV2Chip(
                  '$cleared ${_t('v2i_ps_cleared').toLowerCase()}',
                  tone: AccountsV2ChipTone.ok,
                ),
              if (bounced > 0)
                AccountsV2Chip(
                  '$bounced ${_t('v2i_ps_bounced').toLowerCase()}',
                  tone: AccountsV2ChipTone.bad,
                ),
            ],
          ),
          if (register.isEmpty)
            AccountsV2Empty(
              icon: 'cheque',
              title: _t('v2i_no_records'),
              body: _t('v2i_pdc_empty_body'),
            )
          else
            AccountsV2Table(
              minWidth: 960,
              columns: [
                AccountsV2Column(_t('v2i_p_no'), width: 120),
                AccountsV2Column(_t('v2i_c_invoice'), width: 140),
                AccountsV2Column(_t('v2i_p_bank')),
                AccountsV2Column(_t('v2i_p_received'), width: 120),
                AccountsV2Column(_t('v2i_p_date'), width: 130),
                AccountsV2Column(_t('v2i_p_amount'), width: 130, numeric: true),
                AccountsV2Column(_t('v2i_c_status'), width: 120, center: true),
                if (_showAction)
                  AccountsV2Column(
                    _t('v2i_p_action'),
                    width: 200,
                    numeric: true,
                  ),
              ],
              rows: [for (final pdc in register.pdcs) _row(context, pdc)],
            ),
        ],
      ),
    );
  }

  AccountsV2Row _row(BuildContext context, YorksAccountsProjectPdc pdc) {
    final today = DateTime.now();
    final date = DateTime.tryParse(pdc.chequeDate.postgresText);
    final days = date == null
        ? 0
        : DateTime(
            date.year,
            date.month,
            date.day,
          ).difference(DateTime(today.year, today.month, today.day)).inDays;
    final inHand = pdc.status == YorksAccountsPdcStatus.received;
    return AccountsV2Row([
      Text(pdc.chequeNumber, style: v2Style(12.5, weight: FontWeight.w700)),
      Text(pdc.invoiceReference),
      Text(pdc.bankName ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis),
      Text(v2Date(pdc.receivedDate?.postgresText)),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(v2Date(pdc.chequeDate.postgresText)),
          if (inHand)
            Text(
              days <= 0
                  ? _t('v2i_ready_deposit')
                  : '${_t('v2i_in')} $days ${_t('v2i_days')}',
              style: days <= 0
                  ? v2Style(
                      12,
                      weight: FontWeight.w700,
                      color: AccountsV2Colors.bad,
                    )
                  : v2Style(12, color: AccountsV2Colors.mut),
            ),
        ],
      ),
      Text(v2Fmt(v2Number(pdc.amount.canonicalText))),
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PdcStatusChip(status: pdc.status, language: language),
          if (pdc.actionRequired) ...[
            const SizedBox(height: 3),
            Text(
              _t('v2_pdc_needs_action'),
              style: v2Style(11.5, color: AccountsV2Colors.warn),
            ),
          ],
        ],
      ),
      if (_showAction) _actions(context, pdc),
    ]);
  }

  /// The next step as buttons, as the prototype offers them, and every other
  /// move (walking back, edit, replace) in a menu.
  Widget _actions(BuildContext context, YorksAccountsProjectPdc pdc) {
    final next = onTransition == null
        ? const <YorksAccountsPdcStatus>[]
        : pdc.nextStatuses;
    final primary = <(String, YorksAccountsPdcStatus, AccountsV2ButtonKind)>[
      if (pdc.status == YorksAccountsPdcStatus.expected &&
          next.contains(YorksAccountsPdcStatus.received))
        (
          _t('v2i_mark_received'),
          YorksAccountsPdcStatus.received,
          AccountsV2ButtonKind.normal,
        ),
      if (pdc.status == YorksAccountsPdcStatus.received &&
          next.contains(YorksAccountsPdcStatus.deposited))
        (
          _t('v2i_mark_deposited'),
          YorksAccountsPdcStatus.deposited,
          AccountsV2ButtonKind.normal,
        ),
      if (pdc.status == YorksAccountsPdcStatus.deposited) ...[
        if (next.contains(YorksAccountsPdcStatus.cleared))
          (
            _t('v2i_cleared_btn'),
            YorksAccountsPdcStatus.cleared,
            AccountsV2ButtonKind.ok,
          ),
        if (next.contains(YorksAccountsPdcStatus.bounced))
          (
            _t('v2i_bounced_btn'),
            YorksAccountsPdcStatus.bounced,
            AccountsV2ButtonKind.danger,
          ),
      ],
      if ((pdc.status == YorksAccountsPdcStatus.bounced ||
              pdc.status == YorksAccountsPdcStatus.returned) &&
          next.contains(YorksAccountsPdcStatus.received))
        (
          _t('v2i_represented'),
          YorksAccountsPdcStatus.received,
          AccountsV2ButtonKind.normal,
        ),
    ];
    final shown = {for (final p in primary) p.$2};
    final rest = [
      for (final t in next)
        if (!shown.contains(t)) t,
    ];
    final hasMenu =
        rest.isNotEmpty ||
        _canReplace(pdc) ||
        (onEdit != null && pdc.canEditDetails);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (label, target, kind) in primary)
          AccountsV2Button(
            label: label,
            kind: kind,
            size: AccountsV2ButtonSize.small,
            onPressed: () => _transition(context, pdc, target),
          ),
        if (primary.isEmpty && !hasMenu)
          Text(_t('v2i_done'), style: v2Style(12, color: AccountsV2Colors.mut)),
        if (primary.isEmpty &&
            hasMenu &&
            pdc.status == YorksAccountsPdcStatus.cleared)
          Text(_t('v2i_done'), style: v2Style(12, color: AccountsV2Colors.mut)),
        if (hasMenu) _menu(context, pdc, rest),
      ],
    );
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

  Widget _menu(
    BuildContext context,
    YorksAccountsProjectPdc pdc,
    List<YorksAccountsPdcStatus> moves,
  ) {
    const edit = 'edit';
    const replace = 'replace';
    return Builder(
      builder: (buttonContext) => Tooltip(
        message: _t('v2i_more'),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () async {
            final box = buttonContext.findRenderObject() as RenderBox?;
            final overlay =
                Overlay.of(buttonContext).context.findRenderObject()
                    as RenderBox?;
            if (box == null || overlay == null) return;
            final at = box.localToGlobal(
              Offset(0, box.size.height),
              ancestor: overlay,
            );
            final choice = await showMenu<String>(
              context: buttonContext,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              position: RelativeRect.fromRect(
                at & const Size(1, 1),
                Offset.zero & overlay.size,
              ),
              items: [
                for (final target in moves)
                  PopupMenuItem<String>(
                    value: target.name,
                    child: Text(_moveLabel(pdc, target), style: v2Style(13)),
                  ),
                if (_canReplace(pdc))
                  PopupMenuItem<String>(
                    value: replace,
                    child: Text(_t('v2_pdc_replace'), style: v2Style(13)),
                  ),
                if (onEdit != null && pdc.canEditDetails)
                  PopupMenuItem<String>(
                    value: edit,
                    child: Text(_t('v2_pdc_edit'), style: v2Style(13)),
                  ),
              ],
            );
            if (choice == null || !context.mounted) return;
            if (choice == edit) {
              await _edit(context, pdc);
            } else if (choice == replace) {
              await _replace(context, pdc);
            } else {
              await _transition(
                context,
                pdc,
                moves.firstWhere((target) => target.name == choice),
              );
            }
          },
          child: const SizedBox(
            width: 32,
            height: 30,
            child: Center(
              child: AccountsV2Icon(
                'dots',
                size: 18,
                color: AccountsV2Colors.ink2,
              ),
            ),
          ),
        ),
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
    final (key, tone) = switch (status) {
      YorksAccountsPdcStatus.expected => (
        'v2i_ps_expected',
        AccountsV2ChipTone.neutral,
      ),
      YorksAccountsPdcStatus.received => (
        'v2i_ps_inhand',
        AccountsV2ChipTone.vio,
      ),
      YorksAccountsPdcStatus.deposited => (
        'v2i_ps_deposited',
        AccountsV2ChipTone.pri,
      ),
      YorksAccountsPdcStatus.cleared => (
        'v2i_ps_cleared',
        AccountsV2ChipTone.ok,
      ),
      YorksAccountsPdcStatus.replaced => (
        'v2i_ps_replaced',
        AccountsV2ChipTone.neutral,
      ),
      YorksAccountsPdcStatus.returned => (
        'v2i_ps_returned',
        AccountsV2ChipTone.bad,
      ),
      YorksAccountsPdcStatus.bounced => (
        'v2i_ps_bounced',
        AccountsV2ChipTone.bad,
      ),
      YorksAccountsPdcStatus.cancelled => (
        'v2i_ps_cancelled',
        AccountsV2ChipTone.neutral,
      ),
    };
    return AccountsV2Chip(accountsV2Text(language, key), tone: tone);
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

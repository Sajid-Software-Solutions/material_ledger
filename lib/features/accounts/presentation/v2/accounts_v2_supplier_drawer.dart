/// R39 Accounts Workspace V2 — a supplier bill in the side drawer.
///
/// The same pattern as a client invoice: the figures at the top, one button
/// per thing that can be done now, the papers matched to the bill in plain
/// words, and the payments with their own Edit and Reverse. Every command
/// runs in a dialog that stays open until the server answers, through the
/// existing supplier controller (no change to what is sent or checked).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/models/app_language.dart';
import '../../application/accounts_controller.dart'
    show YorksAccountsViewStatus;
import '../../application/accounts_supplier_controller.dart';
import '../../application/accounts_supplier_providers.dart';
import '../../domain/accounts_decimal.dart';
import '../../domain/accounts_receivables_inputs.dart' show YorksAccountsDate;
import '../../domain/accounts_supplier_inputs.dart';
import '../../domain/accounts_supplier_models.dart';
import '../widgets/yorks_accounts_supplier_action_sheets.dart'
    show showAccountsV2SupplierBillForm;
import 'accounts_v2_common.dart';
import 'accounts_v2_safety.dart';
import 'kit/accounts_v2_kit.dart';

/// Opens [bill] in the side drawer.
Future<void> showAccountsV2SupplierBillDrawer(
  BuildContext context, {
  required String projectId,
  required YorksAccountsSupplierBill bill,
  required AppLanguage language,
}) => showAccountsV2Drawer<void>(
  context,
  closeLabel: accountsV2Text(language, 'v2i_close'),
  title: Wrap(
    spacing: 8,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(bill.supplierInvoiceReference),
      AccountsV2Chip(
        accountsV2Text(language, accountsV2SupplierStatusKey(bill)),
        tone: accountsV2SupplierStatusTone(bill),
      ),
    ],
  ),
  builder: (_) => AccountsV2SupplierBillDrawer(
    projectId: projectId,
    supplierBillId: bill.supplierBillId,
    language: language,
  ),
);

/// The bill's state in one word, as the bills table shows it.
String accountsV2SupplierStatus(
  YorksAccountsSupplierBill bill, [
  DateTime? today,
]) {
  if (bill.status == YorksAccountsSupplierBillStatus.cancelled) {
    return 'cancelled';
  }
  if (bill.status == YorksAccountsSupplierBillStatus.draft) return 'draft';
  if (bill.matchStatus == YorksAccountsSupplierMatchStatus.blocked) {
    return 'blocked';
  }
  if (!bill.outstandingAmount.isPositive) return 'paid';
  final now = today ?? DateTime.now();
  final due = DateTime.tryParse(bill.dueDate.postgresText);
  if (due != null && due.isBefore(DateTime(now.year, now.month, now.day))) {
    return 'overdue';
  }
  return bill.paidAmount.isPositive ? 'part' : 'unpaid';
}

String accountsV2SupplierStatusKey(YorksAccountsSupplierBill bill) =>
    switch (accountsV2SupplierStatus(bill)) {
      'paid' => 'v2s_st_paid',
      'overdue' => 'v2s_st_overdue',
      'part' => 'v2s_st_part',
      'draft' => 'v2s_st_draft',
      'cancelled' => 'v2s_st_cancelled',
      'blocked' => 'v2s_st_blocked',
      _ => 'v2s_st_unpaid',
    };

AccountsV2ChipTone accountsV2SupplierStatusTone(
  YorksAccountsSupplierBill bill,
) => switch (accountsV2SupplierStatus(bill)) {
  'paid' => AccountsV2ChipTone.ok,
  'overdue' || 'blocked' => AccountsV2ChipTone.bad,
  'part' => AccountsV2ChipTone.warn,
  _ => AccountsV2ChipTone.neutral,
};

/// A payment method's words; an older free-text value shows as it was typed.
String accountsV2PaymentMethodLabel(AppLanguage language, String method) =>
    switch (method) {
      'bank_transfer' => accountsV2Text(language, 'v2i_type_bank'),
      'cash' => accountsV2Text(language, 'v2i_type_cash'),
      'cheque' => accountsV2Text(language, 'v2i_type_cheque'),
      _ => method,
    };

double _n(YorksAccountsDecimal? value) =>
    value == null ? 0 : v2Number(value.canonicalText);

class AccountsV2SupplierBillDrawer extends ConsumerStatefulWidget {
  const AccountsV2SupplierBillDrawer({
    super.key,
    required this.projectId,
    required this.supplierBillId,
    required this.language,
  });

  final String projectId;
  final String supplierBillId;
  final AppLanguage language;

  @override
  ConsumerState<AccountsV2SupplierBillDrawer> createState() =>
      _AccountsV2SupplierBillDrawerState();
}

class _AccountsV2SupplierBillDrawerState
    extends ConsumerState<AccountsV2SupplierBillDrawer> {
  String _t(String key) => accountsV2Text(widget.language, key);

  YorksAccountsSupplierController get _controller => ref.read(
    yorksAccountsSupplierControllerProvider(widget.projectId).notifier,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.loadBill(widget.supplierBillId);
    });
  }

  /// The controller's last refusal as a failure code the shared messages
  /// understand; null when the command went through.
  String? _failure(YorksAccountsSupplierCommandResult? result) {
    if (result != null) return null;
    final state = ref.read(
      yorksAccountsSupplierControllerProvider(widget.projectId),
    );
    return switch (state.status) {
      YorksAccountsViewStatus.conflict => 'VERSION_CONFLICT',
      YorksAccountsViewStatus.offline ||
      YorksAccountsViewStatus.uncertain => 'backendUnavailable',
      YorksAccountsViewStatus.forbidden => 'ACCESS_DENIED',
      _ =>
        state.error?.serverMessage ?? state.error?.code.name ?? 'action_failed',
    };
  }

  /// After a dialog's command succeeded: closes the drawer with a message.
  void _done(Object? result, String messageKey) {
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop();
    messenger?.showSnackBar(SnackBar(content: Text(_t(messageKey))));
  }

  List<YorksAccountsSupplierPayment> _active(
    YorksAccountsSupplierBillDetailProjection d,
  ) {
    final reversed = {
      for (final p in d.payments)
        if (p.entryKind == YorksAccountsSupplierPaymentEntryKind.reversal)
          p.originalPaymentId,
    };
    return [
      for (final p in d.payments)
        if (p.entryKind == YorksAccountsSupplierPaymentEntryKind.payment &&
            !reversed.contains(p.paymentId))
          p,
    ];
  }

  // ─── Commands ─────────────────────────────────────────────────────────────

  Future<void> _approve(YorksAccountsSupplierBill bill) async {
    final result = await showDialog<Object>(
      context: context,
      builder: (_) => _ApproveDialog(
        language: widget.language,
        bill: bill,
        onSubmit: (exception) async => _failure(
          await _controller.approveBill(
            YorksAccountsSupplierBillApprovalInput(
              projectId: widget.projectId,
              supplierBillId: bill.supplierBillId,
              expectedVersion: bill.recordVersion,
              adminExceptionReason: exception,
            ),
          ),
        ),
      ),
    );
    _done(result, 'v2sd_approved');
  }

  Future<void> _pay(YorksAccountsSupplierBill bill) async {
    final result = await showDialog<_PaymentForm>(
      context: context,
      builder: (_) => _PaymentDialog(
        language: widget.language,
        title: _t('v2sd_pay'),
        summary: _t('v2sd_sum_due')
            .replaceAll('{ref}', bill.supplierInvoiceReference)
            .replaceAll('{supplier}', bill.supplierName)
            .replaceAll('{amount}', v2Money(_n(bill.outstandingAmount))),
        initialAmount: bill.outstandingAmount.canonicalText,
        reasonRequired: false,
        onSubmit: (f) async => _failure(
          await _controller.recordPayment(
            YorksAccountsSupplierPaymentInput(
              projectId: widget.projectId,
              supplierBillId: bill.supplierBillId,
              expectedVersion: bill.recordVersion,
              paymentDate: f.date,
              paymentMethod: f.method,
              paymentReference: f.reference,
              amount: f.amount,
              reason: f.reason,
            ),
          ),
        ),
      ),
    );
    _done(result, 'v2sd_paid_done');
  }

  Future<void> _editPayment(
    YorksAccountsSupplierBill bill,
    YorksAccountsSupplierPayment p,
  ) async {
    final result = await showDialog<_PaymentForm>(
      context: context,
      builder: (_) => _PaymentDialog(
        language: widget.language,
        title: _t('v2sd_edit_payment'),
        confirmKey: 'v2c_save_changes',
        initialAmount: p.amount.canonicalText,
        initialDate: p.paymentDate.postgresText,
        initialMethod: p.paymentMethod,
        initialReference: p.paymentReference,
        reasonRequired: true,
        onSubmit: (f) async => _failure(
          await _controller.correctPayment(
            YorksAccountsSupplierPaymentCorrectionInput(
              projectId: widget.projectId,
              supplierBillId: bill.supplierBillId,
              expectedVersion: bill.recordVersion,
              originalPaymentId: p.paymentId,
              paymentDate: f.date,
              paymentMethod: f.method,
              paymentReference: f.reference,
              amount: f.amount,
              reason: f.reason ?? '',
            ),
          ),
        ),
      ),
    );
    _done(result, 'v2sd_edited');
  }

  Future<void> _reverse(
    YorksAccountsSupplierBill bill,
    YorksAccountsSupplierPayment p,
  ) async {
    final result = await showDialog<Object>(
      context: context,
      builder: (_) => _ReverseDialog(
        language: widget.language,
        summary: _t('v2b_sum_payment')
            .replaceAll('{amount}', v2Money(_n(p.amount)))
            .replaceAll('{date}', v2Date(p.paymentDate.postgresText)),
        onSubmit: (r) async => _failure(
          await _controller.reversePayment(
            YorksAccountsSupplierPaymentReversalInput(
              projectId: widget.projectId,
              supplierBillId: bill.supplierBillId,
              expectedVersion: bill.recordVersion,
              originalPaymentId: p.paymentId,
              reversalDate: r.date,
              reversalReference: r.reference,
              reason: r.reason,
            ),
          ),
        ),
      ),
    );
    _done(result, 'v2sd_reversed');
  }

  Future<void> _reasonCommand(
    YorksAccountsSupplierBill bill, {
    required bool cancel,
  }) async {
    YorksAccountsSupplierBillCancelInput input(String reason) =>
        YorksAccountsSupplierBillCancelInput(
          projectId: widget.projectId,
          supplierBillId: bill.supplierBillId,
          expectedVersion: bill.recordVersion,
          reason: reason,
        );
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _BillReasonDialog(
        language: widget.language,
        titleKey: cancel ? 'v2sd_cancel' : 'v2sd_reopen',
        hintKey: cancel ? 'v2sd_cancel_hint' : 'v2sd_reopen_hint',
        destructive: cancel,
        onSubmit: (reason) async => _failure(
          cancel
              ? await _controller.cancelBill(input(reason))
              : await _controller.reopenBill(input(reason)),
        ),
      ),
    );
    _done(result, cancel ? 'v2sd_cancelled' : 'v2sd_reopened');
  }

  Future<void> _edit(YorksAccountsSupplierBill bill) async {
    final saved = await showAccountsV2SupplierBillForm(
      context,
      projectId: widget.projectId,
      language: widget.language,
      existing: bill,
    );
    if (saved && mounted) await _controller.loadBill(widget.supplierBillId);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      yorksAccountsSupplierControllerProvider(widget.projectId),
    );
    final d = state.selectedBill;
    if (d == null || d.supplierBill.supplierBillId != widget.supplierBillId) {
      final failed =
          state.status != YorksAccountsViewStatus.loading &&
          state.status != YorksAccountsViewStatus.idle &&
          state.status != YorksAccountsViewStatus.success;
      return Center(
        child: failed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_t('v2_action_failed'), textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  AccountsV2Button(
                    label: _t('v2_retry'),
                    onPressed: () =>
                        _controller.loadBill(widget.supplierBillId),
                  ),
                ],
              )
            : const CircularProgressIndicator(),
      );
    }
    final bill = d.supplierBill;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            [
              bill.supplierName,
              if ((bill.notes ?? '').trim().isNotEmpty) bill.notes!.trim(),
            ].join(' · '),
            style: v2Style(13, color: AccountsV2Colors.mut),
          ),
          const SizedBox(height: 12),
          _stats(bill),
          const SizedBox(height: 14),
          _actions(d),
          AccountsV2Section(_t('v2sd_docs')),
          _papers(bill),
          AccountsV2Section(_t('v2sd_payments')),
          _payments(d),
          if (_canCancel(d)) ...[
            const SizedBox(height: 20),
            AccountsV2Button(
              key: const ValueKey('accounts-v2-supplier-cancel'),
              label: _t('v2sd_cancel'),
              icon: 'x',
              kind: AccountsV2ButtonKind.ghostDanger,
              size: AccountsV2ButtonSize.small,
              onPressed: () => _reasonCommand(bill, cancel: true),
            ),
            Text(
              _t('v2sd_cancel_hint'),
              style: v2Style(12, color: AccountsV2Colors.mut),
            ),
          ],
        ],
      ),
    );
  }

  // As the invoice drawer: three across, stacked on a phone.
  Widget _stats(YorksAccountsSupplierBill bill) => AccountsV2Grid(
    columns: AccountsV2Breakpoints.isPhone(context) ? 1 : 3,
    gap: 10,
    children: [
      AccountsV2MiniStat(
        label: _t('v2sd_total'),
        value: v2Fmt(_n(bill.totalInclVat)),
        caption: _t('v2sd_total_caption')
            .replaceAll('{ex}', v2Fmt(_n(bill.exVatAmount)))
            .replaceAll('{vat}', v2Fmt(_n(bill.vatAmount))),
      ),
      AccountsV2MiniStat(
        label: _t('v2sd_paid'),
        value: v2Fmt(_n(bill.paidAmount)),
        caption: '',
      ),
      AccountsV2MiniStat(
        label: _t('v2sd_due'),
        value: v2Fmt(_n(bill.outstandingAmount)),
        caption: _t(
          'v2sd_due_caption',
        ).replaceAll('{date}', v2Date(bill.dueDate.postgresText)),
      ),
    ],
  );

  bool _canCancel(YorksAccountsSupplierBillDetailProjection d) =>
      d.commands.cancelBill &&
      d.supplierBill.status != YorksAccountsSupplierBillStatus.cancelled;

  /// Why Record payment is unavailable, when the person could otherwise pay.
  String? _payBlocked(YorksAccountsSupplierBill bill) => switch (bill.status) {
    YorksAccountsSupplierBillStatus.draft => _t('v2sd_pay_blocked_draft'),
    YorksAccountsSupplierBillStatus.cancelled => _t(
      'v2b_pay_blocked_cancelled',
    ),
    _ when !bill.outstandingAmount.isPositive => _t('v2sd_pay_blocked_paid'),
    _ => null,
  };

  Widget _actions(YorksAccountsSupplierBillDetailProjection d) {
    final bill = d.supplierBill;
    final c = d.commands;
    final draft = bill.status == YorksAccountsSupplierBillStatus.draft;
    final payBlocked = _payBlocked(bill);
    final buttons = <Widget>[
      if (c.approveBill && draft)
        AccountsV2Button(
          key: const ValueKey('accounts-v2-supplier-approve'),
          label: _t('v2sd_approve'),
          icon: 'check',
          kind: AccountsV2ButtonKind.primary,
          size: AccountsV2ButtonSize.small,
          block: true,
          onPressed: () => _approve(bill),
        ),
      if (c.recordPayment)
        AccountsV2Button(
          key: const ValueKey('accounts-v2-supplier-pay'),
          label: _t('v2sd_pay'),
          icon: 'wallet',
          kind: draft
              ? AccountsV2ButtonKind.normal
              : AccountsV2ButtonKind.primary,
          size: AccountsV2ButtonSize.small,
          block: true,
          onPressed: payBlocked == null ? () => _pay(bill) : null,
        ),
      if (c.editBill && draft)
        AccountsV2Button(
          label: _t('v2sd_edit'),
          icon: 'edit',
          size: AccountsV2ButtonSize.small,
          block: true,
          onPressed: () => _edit(bill),
        ),
      if (c.reopenBill &&
          !draft &&
          _active(d).isEmpty &&
          bill.status != YorksAccountsSupplierBillStatus.cancelled)
        AccountsV2Button(
          label: _t('v2sd_reopen'),
          icon: 'undo',
          size: AccountsV2ButtonSize.small,
          block: true,
          onPressed: () => _reasonCommand(bill, cancel: false),
        ),
    ];
    if (buttons.isEmpty) {
      return Text(
        _t('v2sd_nothing_to_do'),
        style: v2Style(12.5, color: AccountsV2Colors.mut),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountsV2Grid(columns: 2, gap: 8, children: buttons),
        if (c.recordPayment && payBlocked != null) ...[
          const SizedBox(height: 6),
          Text(
            payBlocked,
            key: const ValueKey('accounts-v2-supplier-pay-blocked'),
            style: v2Style(12, color: AccountsV2Colors.mut),
          ),
        ],
      ],
    );
  }

  Widget _papers(YorksAccountsSupplierBill bill) {
    Widget line(String title, bool onFile, String detail) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2Icon(
            onFile ? 'check' : 'alert',
            size: 16,
            color: onFile ? AccountsV2Colors.ok : AccountsV2Colors.warn,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: v2Style(13, weight: FontWeight.w600)),
                Text(detail, style: v2Style(12, color: AccountsV2Colors.mut)),
              ],
            ),
          ),
        ],
      ),
    );
    final missing = _t('v2sd_doc_missing');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _t('v2sd_docs_sub'),
          style: v2Style(12, color: AccountsV2Colors.mut),
        ),
        const SizedBox(height: 4),
        line(
          _t('v2sd_doc_po'),
          bill.poLpoReference != null && bill.poLpoDocumentId != null,
          switch ((bill.poLpoReference, bill.poLpoDocumentId)) {
            (null, null) => missing,
            (null, _) => _t('v2_sup_po_needs_reference'),
            (final reference?, null) =>
              '$reference · ${_t('v2_sup_po_needs_file')}',
            (final reference?, _) => reference,
          },
        ),
        line(
          _t('v2sd_doc_delivery'),
          bill.acceptedDelivery != null,
          bill.acceptedDeliveryReference ?? missing,
        ),
        line(
          _t('v2sd_doc_invoice'),
          bill.supplierInvoiceDocumentId != null,
          bill.supplierInvoiceDocumentId == null
              ? missing
              : _t('v2sd_doc_on_file'),
        ),
        if ((bill.explicitMismatchReason ?? '').trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: AccountsV2Note(
              tone: AccountsV2NoteTone.warn,
              child: Text(
                _t(
                  'v2sd_mismatch',
                ).replaceAll('{reason}', bill.explicitMismatchReason!.trim()),
              ),
            ),
          ),
        if ((bill.approvalAdminExceptionReason ?? '').trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: AccountsV2Note(
              tone: AccountsV2NoteTone.warn,
              child: Text(
                _t('v2sd_approved_without').replaceAll(
                  '{reason}',
                  bill.approvalAdminExceptionReason!.trim(),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _payments(YorksAccountsSupplierBillDetailProjection d) {
    final bill = d.supplierBill;
    final active = {for (final p in _active(d)) p.paymentId};
    final rows = <AccountsV2Row>[
      for (final p in d.payments)
        () {
          final isReversal =
              p.entryKind == YorksAccountsSupplierPaymentEntryKind.reversal;
          final open = active.contains(p.paymentId);
          final canEdit =
              open &&
              d.commands.correctPayment &&
              bill.status == YorksAccountsSupplierBillStatus.approved;
          final canReverse = open && d.commands.reversePayment;
          return AccountsV2Row([
            Text(
              isReversal
                  ? _t('v2i_type_reversal')
                  : accountsV2PaymentMethodLabel(
                      widget.language,
                      p.paymentMethod,
                    ),
            ),
            Text(p.paymentReference),
            Text(v2Date(p.paymentDate.postgresText)),
            Text(v2Fmt(_n(p.amount))),
            Wrap(
              spacing: 2,
              children: [
                if (canEdit)
                  IconButton(
                    tooltip: _t('v2sd_edit_payment'),
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    onPressed: () => _editPayment(bill, p),
                    icon: const AccountsV2Icon('edit', size: 16),
                  ),
                if (canReverse)
                  IconButton(
                    tooltip: _t('v2sd_reverse'),
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    onPressed: () => _reverse(bill, p),
                    icon: const AccountsV2Icon('undo', size: 16),
                  ),
                if (!isReversal && !open)
                  AccountsV2Chip(
                    _t('v2i_reversed_chip'),
                    tone: AccountsV2ChipTone.neutral,
                  ),
              ],
            ),
          ]);
        }(),
    ];
    if (rows.isEmpty) {
      return Text(
        _t('v2sd_no_payments'),
        style: v2Style(12, color: AccountsV2Colors.mut),
      );
    }
    return AccountsV2Table(
      boxed: true,
      minWidth: 520,
      phoneCards: true,
      columns: [
        AccountsV2Column(_t('v2i_t_type'), width: 112),
        AccountsV2Column(_t('v2i_t_ref')),
        AccountsV2Column(_t('v2i_t_date'), width: 104),
        AccountsV2Column(_t('v2i_p_amount'), width: 112, numeric: true),
        const AccountsV2Column('', width: 100, center: true),
      ],
      rows: rows,
    );
  }
}

// ─── Dialogs ─────────────────────────────────────────────────────────────────

class _ApproveDialog extends StatefulWidget {
  const _ApproveDialog({
    required this.language,
    required this.bill,
    required this.onSubmit,
  });

  final AppLanguage language;
  final YorksAccountsSupplierBill bill;

  /// Runs with the reason for approving without all papers (null when not
  /// needed).
  final AccountsV2DialogCommand<String?> onSubmit;

  @override
  State<_ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends State<_ApproveDialog>
    with AccountsV2SubmitDialog {
  @override
  AppLanguage get submitLanguage => widget.language;
  final _reason = TextEditingController();
  String _t(String key) => accountsV2Text(widget.language, key);

  bool get _papersMissing =>
      widget.bill.matchStatus != YorksAccountsSupplierMatchStatus.matched;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bill = widget.bill;
    final reason = _reason.text.trim();
    return submitDialog(
      title: Text(_t('v2sd_approve')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          submitSummary(
            '${bill.supplierInvoiceReference} · ${bill.supplierName} · '
            '${v2Money(_n(bill.totalInclVat))}',
          ),
          Text(
            _t(_papersMissing ? 'v2sd_approve_missing' : 'v2sd_approve_hint'),
            style: v2Style(12.5, color: AccountsV2Colors.mut),
          ),
          if (_papersMissing) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _reason,
              minLines: 1,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _t('v2sd_approve_reason'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ],
      ),
      actions: submitActions(
        confirmLabel: _t('v2sd_approve'),
        onConfirm: () =>
            submit<String?>(reason.isEmpty ? null : reason, widget.onSubmit),
      ),
    );
  }
}

/// What the payment dialog collects.
typedef _PaymentForm = ({
  YorksAccountsDecimal amount,
  YorksAccountsDate date,
  String method,
  String reference,
  String? reason,
});

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({
    required this.language,
    required this.title,
    required this.initialAmount,
    required this.reasonRequired,
    required this.onSubmit,
    this.summary,
    this.confirmKey,
    this.initialDate,
    this.initialMethod,
    this.initialReference,
  });

  final AppLanguage language;
  final String title;
  final String? summary;
  final String? confirmKey;
  final String initialAmount;
  final String? initialDate;
  final String? initialMethod;
  final String? initialReference;
  final bool reasonRequired;
  final AccountsV2DialogCommand<_PaymentForm> onSubmit;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog>
    with AccountsV2SubmitDialog {
  @override
  AppLanguage get submitLanguage => widget.language;
  late final _amount = TextEditingController(text: widget.initialAmount);
  late final _date = TextEditingController(
    text: widget.initialDate ?? accountsV2TodayIso(),
  );
  late final _reference = TextEditingController(
    text: widget.initialReference ?? '',
  );
  final _reason = TextEditingController();
  late String _method = widget.initialMethod ?? 'bank_transfer';
  String _t(String key) => accountsV2Text(widget.language, key);

  @override
  void dispose() {
    for (final c in [_amount, _date, _reference, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.language;
    final blocker = accountsV2FirstBlocker([
      accountsV2NeedAmount(l, _amount, _t('v2sd_amount')),
      accountsV2NeedDate(l, _date, _t('v2sd_date')),
      accountsV2NeedText(l, _reference, _t('v2sd_reference')),
      if (widget.reasonRequired)
        accountsV2NeedText(l, _reason, _t('v2_pay_reverse_reason')),
    ]);
    final methods = {
      'bank_transfer',
      'cash',
      'cheque',
      if (widget.initialMethod != null) widget.initialMethod!,
    };
    void changed() => setState(clearSubmitError);
    return submitDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.summary != null) submitSummary(widget.summary!),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => changed(),
              decoration: InputDecoration(
                labelText: _t('v2sd_amount'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            AccountsV2DateField(
              label: _t('v2sd_date'),
              controller: _date,
              language: l,
              onChanged: changed,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: InputDecoration(
                labelText: _t('v2_pay_method'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final m in methods)
                  DropdownMenuItem(
                    value: m,
                    child: Text(accountsV2PaymentMethodLabel(l, m)),
                  ),
              ],
              onChanged: (v) => setState(() => _method = v ?? _method),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reference,
              onChanged: (_) => changed(),
              decoration: InputDecoration(
                labelText: _t('v2sd_reference'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reason,
              onChanged: (_) => changed(),
              decoration: InputDecoration(
                labelText: widget.reasonRequired
                    ? _t('v2_pay_reverse_reason')
                    : _t('v2b_note_optional'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: submitActions(
        confirmLabel: _t(widget.confirmKey ?? 'v2sd_pay'),
        blockedReason: blocker,
        onConfirm: blocker != null
            ? null
            : () {
                final reason = _reason.text.trim();
                submit<_PaymentForm>((
                  amount: YorksAccountsDecimal.parse(_amount.text.trim()),
                  date: YorksAccountsDate.parse(_date.text.trim()),
                  method: _method,
                  reference: _reference.text.trim(),
                  reason: reason.isEmpty ? null : reason,
                ), widget.onSubmit);
              },
      ),
    );
  }
}

typedef _ReversalForm = ({
  YorksAccountsDate date,
  String reference,
  String reason,
});

class _ReverseDialog extends StatefulWidget {
  const _ReverseDialog({
    required this.language,
    required this.summary,
    required this.onSubmit,
  });

  final AppLanguage language;
  final String summary;
  final AccountsV2DialogCommand<_ReversalForm> onSubmit;

  @override
  State<_ReverseDialog> createState() => _ReverseDialogState();
}

class _ReverseDialogState extends State<_ReverseDialog>
    with AccountsV2SubmitDialog {
  @override
  AppLanguage get submitLanguage => widget.language;
  final _date = TextEditingController(text: accountsV2TodayIso());
  final _reference = TextEditingController();
  final _reason = TextEditingController();
  String _t(String key) => accountsV2Text(widget.language, key);

  @override
  void dispose() {
    for (final c in [_date, _reference, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.language;
    final blocker = accountsV2FirstBlocker([
      accountsV2NeedDate(l, _date, _t('v2_pay_reverse_date')),
      accountsV2NeedText(l, _reason, _t('v2_pay_reverse_reason')),
    ]);
    void changed() => setState(clearSubmitError);
    return submitDialog(
      title: Text(_t('v2sd_reverse')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          submitSummary(widget.summary),
          AccountsV2DateField(
            label: _t('v2_pay_reverse_date'),
            controller: _date,
            language: l,
            onChanged: changed,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _reason,
            onChanged: (_) => changed(),
            decoration: InputDecoration(
              labelText: _t('v2_pay_reverse_reason'),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _reference,
            decoration: InputDecoration(
              labelText: _t('v2_sup_reversal_reference_opt'),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
      actions: submitActions(
        confirmLabel: _t('v2sd_reverse'),
        destructive: true,
        blockedReason: blocker,
        onConfirm: blocker != null
            ? null
            : () => submit<_ReversalForm>((
                date: YorksAccountsDate.parse(_date.text.trim()),
                reference: _reference.text.trim(),
                reason: _reason.text.trim(),
              ), widget.onSubmit),
      ),
    );
  }
}

class _BillReasonDialog extends StatefulWidget {
  const _BillReasonDialog({
    required this.language,
    required this.titleKey,
    required this.hintKey,
    required this.destructive,
    required this.onSubmit,
  });

  final AppLanguage language;
  final String titleKey;
  final String hintKey;
  final bool destructive;
  final AccountsV2DialogCommand<String> onSubmit;

  @override
  State<_BillReasonDialog> createState() => _BillReasonDialogState();
}

class _BillReasonDialogState extends State<_BillReasonDialog>
    with AccountsV2SubmitDialog {
  @override
  AppLanguage get submitLanguage => widget.language;
  final _reason = TextEditingController();
  String _t(String key) => accountsV2Text(widget.language, key);

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reason = _reason.text.trim();
    return submitDialog(
      title: Text(_t(widget.titleKey)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _t(widget.hintKey),
            style: v2Style(12.5, color: AccountsV2Colors.mut),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _reason,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            onChanged: (_) => setState(clearSubmitError),
            decoration: InputDecoration(
              labelText: _t('v2_pay_reverse_reason'),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: submitActions(
        confirmLabel: _t(widget.titleKey),
        cancelLabel: widget.destructive ? _t('v2sd_keep') : null,
        destructive: widget.destructive,
        blockedReason: accountsV2FirstBlocker([
          accountsV2NeedText(
            widget.language,
            _reason,
            _t('v2_pay_reverse_reason'),
          ),
        ]),
        onConfirm: reason.isEmpty
            ? null
            : () => submit(reason, widget.onSubmit),
      ),
    );
  }
}

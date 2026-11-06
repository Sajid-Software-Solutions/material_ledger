/// R39 Accounts Workspace V2 — Supplier bills tab (P6, read view).
///
/// Shows the supplier bills from the existing v1_list_supplier_bills
/// projection: the KPIs (billed incl VAT, paid, unpaid with an overdue count)
/// and a per-bill table (supplier, linked delivery or a no-delivery warning,
/// bill date, incl VAT, paid, due, payment status). The whole surface requires
/// view_supplier_costs. The bill modal and payment actions are a later
/// increment; this slice is read-only.
library;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../shared/models/app_language.dart';
import '../../domain/accounts_decimal.dart';
import '../../domain/accounts_receivables_inputs.dart' show YorksAccountsDate;
import '../../domain/accounts_supplier_inputs.dart';
import '../../domain/accounts_supplier_models.dart';
import 'accounts_v2_common.dart';

/// Records a supplier-bill payment; returns null on success or an error.
typedef YorksSupplierPayAction =
    Future<String?> Function(YorksAccountsSupplierPaymentInput input);

/// Approves a draft supplier bill; returns null on success or an error.
typedef YorksSupplierApproveAction =
    Future<String?> Function({
      required String supplierBillId,
      required int expectedVersion,
    });

class AccountsV2SupplierTab extends StatelessWidget {
  const AccountsV2SupplierTab({
    super.key,
    required this.projection,
    required this.language,
    this.onPay,
    this.onApprove,
  });

  final YorksAccountsSupplierBillsProjection projection;
  final AppLanguage language;
  final YorksSupplierPayAction? onPay;
  final YorksSupplierApproveAction? onApprove;

  String _t(String key) => accountsV2Text(language, key);

  bool _isOverdue(YorksAccountsSupplierBill bill) {
    if (!bill.outstandingAmount.isPositive) return false;
    if (bill.status != YorksAccountsSupplierBillStatus.approved) return false;
    final d = bill.dueDate;
    final due = DateTime.utc(d.year, d.month, d.day);
    final today = DateTime.now().toUtc();
    return due.isBefore(DateTime.utc(today.year, today.month, today.day));
  }

  @override
  Widget build(BuildContext context) {
    if (!projection.capabilities.viewSupplierCosts) {
      return _Notice(icon: Icons.lock_outline, message: _t('v2_sup_no_access'));
    }
    if (projection.items.isEmpty) {
      return _Notice(
        icon: Icons.local_shipping_outlined,
        message: _t('v2_sup_empty'),
      );
    }

    final format = const AccountsV2Format();
    final live = projection.items
        .where((b) => b.status != YorksAccountsSupplierBillStatus.cancelled)
        .toList(growable: false);
    YorksAccountsDecimal sum(
      YorksAccountsDecimal Function(YorksAccountsSupplierBill) pick,
    ) => live.fold(YorksAccountsDecimal.zero, (a, b) => a + pick(b));
    final overdue = live.where(_isOverdue).length;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _KpiRow(
          language: language,
          format: format,
          billed: sum((b) => b.totalInclVat),
          paid: sum((b) => b.paidAmount),
          unpaid: sum((b) => b.outstandingAmount),
          overdueCount: overdue,
        ),
        const SizedBox(height: AppSpacing.lg),
        _BillsCard(
          projectId: projection.projectId,
          bills: projection.items,
          canPay:
              projection.capabilities.approveSupplierBillPayment &&
              onPay != null,
          canApprove:
              projection.capabilities.manageSupplierBills && onApprove != null,
          language: language,
          format: format,
          isOverdue: _isOverdue,
          onPay: onPay,
          onApprove: onApprove,
        ),
      ],
    );
  }
}

// ─── KPIs ────────────────────────────────────────────────────────────────────

class _KpiRow extends StatelessWidget {
  const _KpiRow({
    required this.language,
    required this.format,
    required this.billed,
    required this.paid,
    required this.unpaid,
    required this.overdueCount,
  });

  final AppLanguage language;
  final AccountsV2Format format;
  final YorksAccountsDecimal billed;
  final YorksAccountsDecimal paid;
  final YorksAccountsDecimal unpaid;
  final int overdueCount;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _Kpi(
        icon: Icons.receipt_long_outlined,
        label: accountsV2Text(language, 'v2_sup_kpi_billed'),
        value: format.money(billed),
      ),
      _Kpi(
        icon: Icons.payments_outlined,
        label: accountsV2Text(language, 'v2_sup_kpi_paid'),
        value: format.money(paid),
        accent: AppColors.success,
      ),
      _Kpi(
        icon: Icons.account_balance_wallet_outlined,
        label: accountsV2Text(language, 'v2_sup_kpi_unpaid'),
        value: format.money(unpaid),
        caption: overdueCount > 0
            ? '$overdueCount ${accountsV2Text(language, 'v2_overdue_count_suffix')}'
            : '',
        accent: unpaid.isPositive ? AppColors.warning : null,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = (constraints.maxWidth / 220).floor().clamp(1, 3);
        const spacing = AppSpacing.md;
        final tileWidth =
            (constraints.maxWidth - spacing * (perRow - 1)) / perRow;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final tile in tiles) SizedBox(width: tileWidth, child: tile),
          ],
        );
      },
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.icon,
    required this.label,
    required this.value,
    this.caption = '',
    this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final String caption;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? AppColors.primary;
    return AccountsV2Card(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 16, color: tint),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.muted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: AppTypography.titleMedium.copyWith(
              color: accent ?? AppColors.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (caption.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(caption, style: AppTypography.bodySmall),
          ],
        ],
      ),
    );
  }
}

// ─── Bills table ─────────────────────────────────────────────────────────────

class _BillsCard extends StatelessWidget {
  const _BillsCard({
    required this.projectId,
    required this.bills,
    required this.canPay,
    required this.canApprove,
    required this.language,
    required this.format,
    required this.isOverdue,
    this.onPay,
    this.onApprove,
  });

  final String projectId;
  final List<YorksAccountsSupplierBill> bills;
  final bool canPay;
  final bool canApprove;
  final AppLanguage language;
  final AccountsV2Format format;
  final bool Function(YorksAccountsSupplierBill) isOverdue;
  final YorksSupplierPayAction? onPay;
  final YorksSupplierApproveAction? onApprove;

  bool get _showActions => canPay || canApprove;

  String _t(String key) => accountsV2Text(language, key);

  bool _canPay(YorksAccountsSupplierBill bill) =>
      canPay &&
      bill.status == YorksAccountsSupplierBillStatus.approved &&
      bill.outstandingAmount.isPositive;

  bool _canApprove(YorksAccountsSupplierBill bill) =>
      canApprove && bill.status == YorksAccountsSupplierBillStatus.draft;

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

  Future<void> _pay(
    BuildContext context,
    YorksAccountsSupplierBill bill,
  ) async {
    final input = await showDialog<YorksAccountsSupplierPaymentInput>(
      context: context,
      builder: (_) => _SupplierPayDialog(
        projectId: projectId,
        bill: bill,
        language: language,
      ),
    );
    if (input == null) return;
    final error = await onPay!(input);
    if (context.mounted) await _report(context, error, 'v2_pay_saved');
  }

  Future<void> _approve(
    BuildContext context,
    YorksAccountsSupplierBill bill,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(_t('v2_sup_approve_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_t('v2_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_t('v2_confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final error = await onApprove!(
      supplierBillId: bill.supplierBillId,
      expectedVersion: bill.recordVersion,
    );
    if (context.mounted) await _report(context, error, 'v2_sup_approved_done');
  }

  @override
  Widget build(BuildContext context) {
    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(_t('v2_tab_supplier_bills')),
          const SizedBox(height: AppSpacing.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: AppSpacing.xl,
              headingRowHeight: 36,
              dataRowMinHeight: 42,
              dataRowMaxHeight: 56,
              columns: [
                DataColumn(label: Text(_t('v2_sup_col_bill'))),
                DataColumn(label: Text(_t('v2_sup_col_supplier'))),
                DataColumn(label: Text(_t('v2_sup_col_linked'))),
                DataColumn(label: Text(_t('v2_sup_col_date'))),
                DataColumn(label: Text(_t('v2_inv_col_incl')), numeric: true),
                DataColumn(label: Text(_t('v2_sup_kpi_paid')), numeric: true),
                DataColumn(
                  label: Text(_t('v2_inv_col_balance')),
                  numeric: true,
                ),
                DataColumn(label: Text(_t('v2_inv_col_status'))),
                if (_showActions) DataColumn(label: Text(_t('v2_inv_actions'))),
              ],
              rows: [
                for (final bill in bills)
                  DataRow(
                    cells: [
                      DataCell(
                        Text(
                          bill.supplierInvoiceReference,
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      DataCell(Text(bill.supplierName)),
                      DataCell(_LinkedCell(bill: bill, language: language)),
                      DataCell(Text(bill.invoiceDate.toString())),
                      DataCell(
                        Text(
                          format.money(bill.totalInclVat, withCurrency: false),
                        ),
                      ),
                      DataCell(
                        Text(
                          format.money(bill.paidAmount, withCurrency: false),
                        ),
                      ),
                      DataCell(
                        Text(
                          format.money(
                            bill.outstandingAmount,
                            withCurrency: false,
                          ),
                          style: AppTypography.bodyMedium.copyWith(
                            color: isOverdue(bill)
                                ? AppColors.error
                                : AppColors.ink,
                          ),
                        ),
                      ),
                      DataCell(
                        _PaymentStatusChip(
                          status: bill.paymentStatus,
                          language: language,
                        ),
                      ),
                      if (_showActions)
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_canApprove(bill))
                                TextButton(
                                  onPressed: () => _approve(context, bill),
                                  child: Text(_t('v2_sup_approve')),
                                ),
                              if (_canPay(bill))
                                TextButton(
                                  onPressed: () => _pay(context, bill),
                                  child: Text(_t('v2_inv_record_payment')),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkedCell extends StatelessWidget {
  const _LinkedCell({required this.bill, required this.language});

  final YorksAccountsSupplierBill bill;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final ref = bill.acceptedDeliveryReference;
    if (ref != null && ref.isNotEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.link, size: 14, color: AppColors.success),
          const SizedBox(width: AppSpacing.xxs),
          Text(ref, style: AppTypography.bodySmall),
        ],
      );
    }
    return StatusChip.warning(accountsV2Text(language, 'v2_sup_no_delivery'));
  }
}

class _PaymentStatusChip extends StatelessWidget {
  const _PaymentStatusChip({required this.status, required this.language});

  final YorksAccountsSupplierPaymentStatus status;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final (key, tone) = switch (status) {
      YorksAccountsSupplierPaymentStatus.pending => (
        'v2_sup_pay_pending',
        NexusStatusTone.neutral,
      ),
      YorksAccountsSupplierPaymentStatus.approved => (
        'v2_sup_pay_approved',
        NexusStatusTone.info,
      ),
      YorksAccountsSupplierPaymentStatus.partiallyPaid => (
        'v2_sup_pay_partially_paid',
        NexusStatusTone.warning,
      ),
      YorksAccountsSupplierPaymentStatus.paid => (
        'v2_sup_pay_paid',
        NexusStatusTone.success,
      ),
      YorksAccountsSupplierPaymentStatus.blocked => (
        'v2_sup_pay_blocked',
        NexusStatusTone.danger,
      ),
      YorksAccountsSupplierPaymentStatus.cancelled => (
        'v2_sup_pay_cancelled',
        NexusStatusTone.neutral,
      ),
    };
    return StatusChip(label: accountsV2Text(language, key), tone: tone);
  }
}

// ─── Notice (no access / empty) ──────────────────────────────────────────────

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: AppColors.muted),
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

// ─── Supplier payment dialog ─────────────────────────────────────────────────

class _SupplierPayDialog extends StatefulWidget {
  const _SupplierPayDialog({
    required this.projectId,
    required this.bill,
    required this.language,
  });

  final String projectId;
  final YorksAccountsSupplierBill bill;
  final AppLanguage language;

  @override
  State<_SupplierPayDialog> createState() => _SupplierPayDialogState();
}

class _SupplierPayDialogState extends State<_SupplierPayDialog> {
  late final TextEditingController _amount;
  late final TextEditingController _date;
  final _reference = TextEditingController();
  final _reason = TextEditingController();
  String _method = 'bank_transfer';

  String _t(String key) => accountsV2Text(widget.language, key);

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.bill.outstandingAmount.canonicalText,
    );
    _date = TextEditingController(text: accountsV2TodayIso());
  }

  @override
  void dispose() {
    _amount.dispose();
    _date.dispose();
    _reference.dispose();
    _reason.dispose();
    super.dispose();
  }

  YorksAccountsSupplierPaymentInput? _build() {
    final amount = YorksAccountsDecimal.tryParse(_amount.text.trim());
    final date = YorksAccountsDate.tryParse(_date.text.trim());
    if (amount == null || date == null) return null;
    final reason = _reason.text.trim();
    return YorksAccountsSupplierPaymentInput(
      projectId: widget.projectId,
      supplierBillId: widget.bill.supplierBillId,
      expectedVersion: widget.bill.recordVersion,
      paymentDate: date,
      paymentMethod: _method,
      paymentReference: _reference.text.trim(),
      amount: amount,
      reason: reason.isEmpty ? null : reason,
    );
  }

  @override
  Widget build(BuildContext context) {
    final input = _build();
    final valid = input != null && input.isValid;
    InputDecoration deco(String label, {String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      border: const OutlineInputBorder(),
    );
    return AlertDialog(
      title: Text(_t('v2_pay_title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: deco(_t('v2_pay_amount')),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _date,
            onChanged: (_) => setState(() {}),
            decoration: deco(_t('v2_pay_date'), hint: 'YYYY-MM-DD'),
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration: deco(_t('v2_pay_method')),
            items: [
              DropdownMenuItem(
                value: 'bank_transfer',
                child: Text(_t('v2_pay_method_bank')),
              ),
              DropdownMenuItem(
                value: 'cash',
                child: Text(_t('v2_pay_method_cash')),
              ),
            ],
            onChanged: (v) => setState(() => _method = v ?? 'bank_transfer'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _reference,
            onChanged: (_) => setState(() {}),
            decoration: deco(_t('v2_pay_reference')),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _reason,
            onChanged: (_) => setState(() {}),
            decoration: deco(_t('v2_pay_reason_opt')),
          ),
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

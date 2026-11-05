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
import '../../domain/accounts_supplier_models.dart';
import 'accounts_v2_common.dart';

class AccountsV2SupplierTab extends StatelessWidget {
  const AccountsV2SupplierTab({
    super.key,
    required this.projection,
    required this.language,
  });

  final YorksAccountsSupplierBillsProjection projection;
  final AppLanguage language;

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
          bills: projection.items,
          language: language,
          format: format,
          isOverdue: _isOverdue,
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
        label: accountsV2Text(language, 'v2_sup_kpi_billed'),
        value: format.money(billed),
      ),
      _Kpi(
        label: accountsV2Text(language, 'v2_sup_kpi_paid'),
        value: format.money(paid),
        accent: AppColors.success,
      ),
      _Kpi(
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
    required this.label,
    required this.value,
    this.caption = '',
    this.accent,
  });

  final String label;
  final String value;
  final String caption;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return AccountsV2Card(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTypography.labelMedium.copyWith(color: AppColors.muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xs),
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
    required this.bills,
    required this.language,
    required this.format,
    required this.isOverdue,
  });

  final List<YorksAccountsSupplierBill> bills;
  final AppLanguage language;
  final AccountsV2Format format;
  final bool Function(YorksAccountsSupplierBill) isOverdue;

  String _t(String key) => accountsV2Text(language, key);

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

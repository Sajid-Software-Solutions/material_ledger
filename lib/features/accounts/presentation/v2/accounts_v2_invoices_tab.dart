/// R39 Accounts Workspace V2 — Invoices & payments tab (P6, read view).
///
/// Shows the client invoice tracker from the existing v1_list_client_invoices
/// projection: the five KPIs (invoiced incl VAT, certified, received, cheques
/// in hand, still due) and a per-invoice table (ex/incl VAT, certified, due,
/// received, balance, status). Monetary content is drawn only with
/// view_project_commercial_values. The cheque (PDC) register, the invoice
/// drawer and the certification/payment actions are a later P6 increment.
library;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../shared/models/app_language.dart';
import '../../domain/accounts_decimal.dart';
import '../../domain/accounts_receivables_models.dart';
import 'accounts_v2_common.dart';

class AccountsV2InvoicesTab extends StatelessWidget {
  const AccountsV2InvoicesTab({
    super.key,
    required this.projection,
    required this.language,
  });

  final YorksAccountsInvoicesProjection projection;
  final AppLanguage language;

  bool get _canValues => projection.capabilities.canViewValues;

  String _t(String key) => accountsV2Text(language, key);

  List<YorksAccountsClientInvoiceSummary> get _live => projection.invoices
      .where((i) => i.status != YorksAccountsInvoiceStatus.cancelled)
      .toList(growable: false);

  YorksAccountsDecimal _sum(
    YorksAccountsDecimal Function(YorksAccountsClientInvoiceSummary) pick,
  ) => _live.fold(YorksAccountsDecimal.zero, (a, i) => a + pick(i));

  @override
  Widget build(BuildContext context) {
    final format = const AccountsV2Format();

    if (projection.invoices.isEmpty) {
      return _Empty(message: _t('v2_inv_empty'));
    }

    final children = <Widget>[];
    if (_canValues) {
      children
        ..add(
          _KpiRow(
            language: language,
            format: format,
            invoiced: _sum((i) => i.totalInclVat),
            certified: _sum((i) => i.certifiedExVat),
            received: _sum((i) => i.amountPaidTillDate),
            cheques: _sum((i) => i.pdcExposure),
            due: _sum((i) => i.stillDue),
          ),
        )
        ..add(const SizedBox(height: AppSpacing.lg));
    }
    children.add(
      _TrackerCard(
        invoices: projection.invoices,
        canValues: _canValues,
        language: language,
        format: format,
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: children,
    );
  }
}

// ─── KPIs ────────────────────────────────────────────────────────────────────

class _KpiRow extends StatelessWidget {
  const _KpiRow({
    required this.language,
    required this.format,
    required this.invoiced,
    required this.certified,
    required this.received,
    required this.cheques,
    required this.due,
  });

  final AppLanguage language;
  final AccountsV2Format format;
  final YorksAccountsDecimal invoiced;
  final YorksAccountsDecimal certified;
  final YorksAccountsDecimal received;
  final YorksAccountsDecimal cheques;
  final YorksAccountsDecimal due;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _Kpi(
        label: accountsV2Text(language, 'v2_inv_kpi_invoiced'),
        value: format.money(invoiced),
      ),
      _Kpi(
        label: accountsV2Text(language, 'v2_inv_kpi_certified'),
        value: format.money(certified),
      ),
      _Kpi(
        label: accountsV2Text(language, 'v2_kpi_received'),
        value: format.money(received),
        accent: AppColors.success,
      ),
      _Kpi(
        label: accountsV2Text(language, 'v2_inv_kpi_cheques'),
        value: format.money(cheques),
        accent: AppColors.purple,
      ),
      _Kpi(
        label: accountsV2Text(language, 'v2_inv_kpi_due'),
        value: format.money(due),
        accent: due.isPositive ? AppColors.warning : null,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = (constraints.maxWidth / 200).floor().clamp(1, 5);
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
  const _Kpi({required this.label, required this.value, this.accent});

  final String label;
  final String value;
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
        ],
      ),
    );
  }
}

// ─── Tracker ───────────────────────────────────────────────────────────────

class _TrackerCard extends StatelessWidget {
  const _TrackerCard({
    required this.invoices,
    required this.canValues,
    required this.language,
    required this.format,
  });

  final List<YorksAccountsClientInvoiceSummary> invoices;
  final bool canValues;
  final AppLanguage language;
  final AccountsV2Format format;

  String _t(String key) => accountsV2Text(language, key);

  @override
  Widget build(BuildContext context) {
    final columns = <DataColumn>[
      DataColumn(label: Text(_t('v2_inv_col_invoice'))),
      DataColumn(label: Text(_t('v2_inv_col_submitted'))),
      if (canValues) ...[
        DataColumn(label: Text(_t('v2_inv_col_excl')), numeric: true),
        DataColumn(label: Text(_t('v2_inv_col_incl')), numeric: true),
        DataColumn(label: Text(_t('v2_inv_kpi_certified')), numeric: true),
      ],
      DataColumn(label: Text(_t('v2_inv_col_due'))),
      if (canValues) ...[
        DataColumn(label: Text(_t('v2_kpi_received')), numeric: true),
        DataColumn(label: Text(_t('v2_inv_col_balance')), numeric: true),
      ],
      DataColumn(label: Text(_t('v2_inv_col_status'))),
    ];

    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(_t('v2_tab_invoices')),
          const SizedBox(height: AppSpacing.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: AppSpacing.xl,
              headingRowHeight: 36,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 52,
              columns: columns,
              rows: [
                for (final inv in invoices)
                  DataRow(
                    cells: [
                      DataCell(
                        Text(
                          inv.invoiceReference,
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      DataCell(Text(inv.submissionDate?.toString() ?? '—')),
                      if (canValues) ...[
                        DataCell(
                          Text(
                            format.money(inv.claimedExVat, withCurrency: false),
                          ),
                        ),
                        DataCell(
                          Text(
                            format.money(inv.totalInclVat, withCurrency: false),
                          ),
                        ),
                        DataCell(
                          Text(
                            format.money(
                              inv.certifiedExVat,
                              withCurrency: false,
                            ),
                          ),
                        ),
                      ],
                      DataCell(_DueCell(inv: inv, language: language)),
                      if (canValues) ...[
                        DataCell(
                          Text(
                            format.money(
                              inv.amountPaidTillDate,
                              withCurrency: false,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(format.money(inv.stillDue, withCurrency: false)),
                        ),
                      ],
                      DataCell(
                        _StatusChip(status: inv.status, language: language),
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

class _DueCell extends StatelessWidget {
  const _DueCell({required this.inv, required this.language});

  final YorksAccountsClientInvoiceSummary inv;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final overdue = inv.dueState == YorksAccountsDueState.overdue;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          inv.dueDate?.toString() ?? '—',
          style: AppTypography.bodyMedium.copyWith(
            color: overdue ? AppColors.error : AppColors.inkSecondary,
          ),
        ),
        if (overdue) ...[
          const SizedBox(width: AppSpacing.xs),
          StatusChip.error(accountsV2Text(language, 'v2_inv_overdue')),
        ],
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.language});

  final YorksAccountsInvoiceStatus status;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final (key, tone) = switch (status) {
      YorksAccountsInvoiceStatus.draft => (
        'v2_inv_status_draft',
        NexusStatusTone.neutral,
      ),
      YorksAccountsInvoiceStatus.submitted => (
        'v2_inv_status_submitted',
        NexusStatusTone.info,
      ),
      YorksAccountsInvoiceStatus.underCertification => (
        'v2_inv_status_under_certification',
        NexusStatusTone.info,
      ),
      YorksAccountsInvoiceStatus.partiallyCertified => (
        'v2_inv_status_partially_certified',
        NexusStatusTone.info,
      ),
      YorksAccountsInvoiceStatus.certified => (
        'v2_inv_status_certified',
        NexusStatusTone.success,
      ),
      YorksAccountsInvoiceStatus.partiallyPaid => (
        'v2_inv_status_partially_paid',
        NexusStatusTone.warning,
      ),
      YorksAccountsInvoiceStatus.paid => (
        'v2_inv_status_paid',
        NexusStatusTone.success,
      ),
      YorksAccountsInvoiceStatus.returned => (
        'v2_inv_status_returned',
        NexusStatusTone.warning,
      ),
      YorksAccountsInvoiceStatus.cancelled => (
        'v2_inv_status_cancelled',
        NexusStatusTone.neutral,
      ),
    };
    return StatusChip(label: accountsV2Text(language, key), tone: tone);
  }
}

// ─── Empty ─────────────────────────────────────────────────────────────────

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
              Icons.receipt_long_outlined,
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

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
import '../../domain/accounts_receivables_inputs.dart';
import '../../domain/accounts_receivables_models.dart';
import 'accounts_v2_common.dart';

/// Records client certification; returns null on success or an error message.
typedef YorksCertifyAction =
    Future<String?> Function(YorksAccountsCertificationInput input);

/// Records a client payment; returns null on success or an error message.
typedef YorksPayAction =
    Future<String?> Function(YorksAccountsPaymentInput input);

class AccountsV2InvoicesTab extends StatelessWidget {
  const AccountsV2InvoicesTab({
    super.key,
    required this.projection,
    required this.language,
    this.onCertify,
    this.onPay,
    this.onPrintInvoice,
    this.onOpenDetail,
    this.trailing,
  });

  final YorksAccountsInvoicesProjection projection;
  final AppLanguage language;

  /// Optional card rendered below the tracker (the cheque register), scrolling
  /// with it rather than in a separate viewport.
  final Widget? trailing;
  final YorksCertifyAction? onCertify;
  final YorksPayAction? onPay;

  /// Fetches + renders the invoice PDF and opens the print/preview; returns
  /// null on success or an error message.
  final Future<String?> Function(String invoiceId)? onPrintInvoice;

  /// Fetches the full invoice detail for the drawer; null on failure.
  final Future<YorksAccountsInvoiceDetailProjection?> Function(
    String invoiceId,
  )?
  onOpenDetail;

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
        projectId: projection.projectId,
        invoices: projection.invoices,
        canValues: _canValues,
        canCertify:
            projection.capabilities.recordClientCertification &&
            onCertify != null,
        canPay: projection.capabilities.recordClientPayment && onPay != null,
        language: language,
        format: format,
        onCertify: onCertify,
        onPay: onPay,
        onPrintInvoice: onPrintInvoice,
        onOpenDetail: onOpenDetail,
      ),
    );
    if (trailing != null) {
      children
        ..add(const SizedBox(height: AppSpacing.lg))
        ..add(trailing!);
    }

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
    required this.projectId,
    required this.invoices,
    required this.canValues,
    required this.canCertify,
    required this.canPay,
    required this.language,
    required this.format,
    this.onCertify,
    this.onPay,
    this.onPrintInvoice,
    this.onOpenDetail,
  });

  final String projectId;
  final List<YorksAccountsClientInvoiceSummary> invoices;
  final bool canValues;
  final bool canCertify;
  final bool canPay;
  final AppLanguage language;
  final AccountsV2Format format;
  final YorksCertifyAction? onCertify;
  final YorksPayAction? onPay;
  final Future<String?> Function(String invoiceId)? onPrintInvoice;
  final Future<YorksAccountsInvoiceDetailProjection?> Function(
    String invoiceId,
  )?
  onOpenDetail;

  bool get _showActions => canCertify || canPay || onPrintInvoice != null;

  Future<void> _openDetail(
    BuildContext context,
    YorksAccountsClientInvoiceSummary inv,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final detail = await onOpenDetail!(inv.invoiceId);
    if (!context.mounted) return;
    if (detail == null) {
      messenger?.showSnackBar(
        SnackBar(content: Text(_t('v2_inv_detail_failed'))),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _InvoiceDetailSheet(
        detail: detail,
        language: language,
        format: format,
      ),
    );
  }

  bool _canPrint(YorksAccountsClientInvoiceSummary inv) =>
      onPrintInvoice != null &&
      inv.status != YorksAccountsInvoiceStatus.draft &&
      inv.status != YorksAccountsInvoiceStatus.cancelled;

  Future<void> _print(
    BuildContext context,
    YorksAccountsClientInvoiceSummary inv,
  ) async {
    final error = await onPrintInvoice!(inv.invoiceId);
    if (!context.mounted || error == null) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(_t('v2_inv_pdf_failed'))));
  }

  String _t(String key) => accountsV2Text(language, key);

  bool _canCertify(YorksAccountsClientInvoiceSummary inv) =>
      canCertify &&
      const {
        YorksAccountsInvoiceStatus.submitted,
        YorksAccountsInvoiceStatus.underCertification,
        YorksAccountsInvoiceStatus.partiallyCertified,
        YorksAccountsInvoiceStatus.certified,
      }.contains(inv.status);

  bool _canPay(YorksAccountsClientInvoiceSummary inv) =>
      canPay &&
      const {
        YorksAccountsInvoiceStatus.certified,
        YorksAccountsInvoiceStatus.partiallyCertified,
        YorksAccountsInvoiceStatus.partiallyPaid,
      }.contains(inv.status);

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

  Future<void> _certify(
    BuildContext context,
    YorksAccountsClientInvoiceSummary inv,
  ) async {
    final input = await showDialog<YorksAccountsCertificationInput>(
      context: context,
      builder: (_) => _CertifyDialog(
        projectId: projectId,
        invoice: inv,
        language: language,
      ),
    );
    if (input == null) return;
    final error = await onCertify!(input);
    if (context.mounted) await _report(context, error, 'v2_cert_saved');
  }

  Future<void> _pay(
    BuildContext context,
    YorksAccountsClientInvoiceSummary inv,
  ) async {
    final input = await showDialog<YorksAccountsPaymentInput>(
      context: context,
      builder: (_) =>
          _PayDialog(projectId: projectId, invoice: inv, language: language),
    );
    if (input == null) return;
    final error = await onPay!(input);
    if (context.mounted) await _report(context, error, 'v2_pay_saved');
  }

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
      if (_showActions) DataColumn(label: Text(_t('v2_inv_actions'))),
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
                        onOpenDetail == null
                            ? Text(
                                inv.invoiceReference,
                                style: AppTypography.bodyMedium.copyWith(
                                  color: AppColors.ink,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            : InkWell(
                                onTap: () => _openDetail(context, inv),
                                child: Text(
                                  inv.invoiceReference,
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                    decoration: TextDecoration.underline,
                                    decorationColor: AppColors.primary,
                                  ),
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
                      if (_showActions)
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_canCertify(inv))
                                TextButton(
                                  onPressed: () => _certify(context, inv),
                                  child: Text(_t('v2_inv_certify')),
                                ),
                              if (_canPay(inv))
                                TextButton(
                                  onPressed: () => _pay(context, inv),
                                  child: Text(_t('v2_inv_record_payment')),
                                ),
                              if (_canPrint(inv))
                                TextButton(
                                  onPressed: () => _print(context, inv),
                                  child: Text(_t('v2_inv_view_print')),
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

// ─── Certify / pay dialogs ───────────────────────────────────────────────────

class _CertifyDialog extends StatefulWidget {
  const _CertifyDialog({
    required this.projectId,
    required this.invoice,
    required this.language,
  });

  final String projectId;
  final YorksAccountsClientInvoiceSummary invoice;
  final AppLanguage language;

  @override
  State<_CertifyDialog> createState() => _CertifyDialogState();
}

class _CertifyDialogState extends State<_CertifyDialog> {
  late final TextEditingController _amount;
  late final TextEditingController _date;
  final _reference = TextEditingController();
  final _reason = TextEditingController();

  String _t(String key) => accountsV2Text(widget.language, key);

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.invoice.claimedExVat.canonicalText,
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

  YorksAccountsCertificationInput? _build() {
    final amount = YorksAccountsDecimal.tryParse(_amount.text.trim());
    final date = YorksAccountsDate.tryParse(_date.text.trim());
    if (amount == null || date == null) return null;
    final reason = _reason.text.trim();
    return YorksAccountsCertificationInput(
      projectId: widget.projectId,
      invoiceId: widget.invoice.invoiceId,
      expectedVersion: widget.invoice.recordVersion,
      certifiedExVat: amount,
      certificationDate: date,
      certificationReference: _reference.text.trim(),
      differenceReason: reason.isEmpty ? null : reason,
    );
  }

  @override
  Widget build(BuildContext context) {
    final input = _build();
    final valid =
        input != null &&
        input.isValidAgainstClaimed(widget.invoice.claimedExVat);
    return AlertDialog(
      title: Text(_t('v2_cert_title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DialogField(
            label: _t('v2_cert_amount'),
            controller: _amount,
            numeric: true,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          _DialogField(
            label: _t('v2_cert_date'),
            controller: _date,
            hint: 'YYYY-MM-DD',
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          _DialogField(
            label: _t('v2_cert_reference'),
            controller: _reference,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          _DialogField(
            label: _t('v2_cert_difference_reason'),
            controller: _reason,
            onChanged: () => setState(() {}),
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

class _PayDialog extends StatefulWidget {
  const _PayDialog({
    required this.projectId,
    required this.invoice,
    required this.language,
  });

  final String projectId;
  final YorksAccountsClientInvoiceSummary invoice;
  final AppLanguage language;

  @override
  State<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends State<_PayDialog> {
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
      text: widget.invoice.stillDue.canonicalText,
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

  YorksAccountsPaymentInput? _build() {
    final amount = YorksAccountsDecimal.tryParse(_amount.text.trim());
    final date = YorksAccountsDate.tryParse(_date.text.trim());
    if (amount == null || date == null) return null;
    final reason = _reason.text.trim();
    return YorksAccountsPaymentInput(
      projectId: widget.projectId,
      invoiceId: widget.invoice.invoiceId,
      expectedVersion: widget.invoice.recordVersion,
      paymentDate: date,
      amount: amount,
      paymentMethod: _method,
      paymentReference: _reference.text.trim(),
      reason: reason.isEmpty ? null : reason,
    );
  }

  @override
  Widget build(BuildContext context) {
    final input = _build();
    final valid = input != null && input.isValid;
    return AlertDialog(
      title: Text(_t('v2_pay_title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DialogField(
            label: _t('v2_pay_amount'),
            controller: _amount,
            numeric: true,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          _DialogField(
            label: _t('v2_pay_date'),
            controller: _date,
            hint: 'YYYY-MM-DD',
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration: InputDecoration(
              labelText: _t('v2_pay_method'),
              border: const OutlineInputBorder(),
            ),
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
          _DialogField(
            label: _t('v2_pay_reference'),
            controller: _reference,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          _DialogField(
            label: _t('v2_pay_reason_opt'),
            controller: _reason,
            onChanged: () => setState(() {}),
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

class _DialogField extends StatelessWidget {
  const _DialogField({
    required this.label,
    required this.controller,
    this.numeric = false,
    this.hint,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final bool numeric;
  final String? hint;
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
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

// ─── Invoice detail drawer ───────────────────────────────────────────────────

class _InvoiceDetailSheet extends StatelessWidget {
  const _InvoiceDetailSheet({
    required this.detail,
    required this.language,
    required this.format,
  });

  final YorksAccountsInvoiceDetailProjection detail;
  final AppLanguage language;
  final AccountsV2Format format;

  String _t(String key) => accountsV2Text(language, key);

  @override
  Widget build(BuildContext context) {
    final invoice = detail.invoice;
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    invoice.invoiceReference,
                    style: AppTypography.titleMedium.copyWith(
                      color: AppColors.ink,
                    ),
                  ),
                ),
                _StatusChip(status: invoice.status, language: language),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _MiniKpi(
                    label: _t('v2_inv_detail_total'),
                    value: format.money(invoice.totalInclVatSnapshot),
                  ),
                ),
                Expanded(
                  child: _MiniKpi(
                    label: _t('v2_inv_detail_received'),
                    value: format.money(invoice.paidAmount),
                    accent: AppColors.success,
                  ),
                ),
                Expanded(
                  child: _MiniKpi(
                    label: _t('v2_inv_detail_balance'),
                    value: format.money(invoice.stillDue),
                    accent: AppColors.warning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _DetailSection(
              title: _t('v2_inv_certifications'),
              emptyLabel: _t('v2_inv_none'),
              rows: [
                for (final c in detail.certifications)
                  _DetailRow(
                    leading: c.certificationReference,
                    trailing: format.money(c.certifiedExVat),
                    sub: c.certificationDate.toString(),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _DetailSection(
              title: _t('v2_inv_payments'),
              emptyLabel: _t('v2_inv_none'),
              rows: [
                for (final p in detail.payments)
                  _DetailRow(
                    leading: p.paymentReference,
                    trailing: format.money(p.amount),
                    sub: '${p.paymentDate} · ${p.paymentMethod}',
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _DetailSection(
              title: _t('v2_inv_cheques'),
              emptyLabel: _t('v2_inv_none'),
              rows: [
                for (final pdc in detail.pdcs)
                  _DetailRow(
                    leading: pdc.chequeNumber,
                    trailing: format.money(pdc.amount),
                    sub: [
                      if (pdc.bankName != null) pdc.bankName!,
                      pdc.chequeDate.toString(),
                    ].join(' · '),
                    chip: _pdcChip(pdc.status),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pdcChip(YorksAccountsPdcStatus status) {
    final (key, tone) = switch (status) {
      YorksAccountsPdcStatus.expected => (
        'v2_pdc_expected',
        NexusStatusTone.neutral,
      ),
      YorksAccountsPdcStatus.received => (
        'v2_pdc_received',
        NexusStatusTone.info,
      ),
      YorksAccountsPdcStatus.deposited => (
        'v2_pdc_deposited',
        NexusStatusTone.info,
      ),
      YorksAccountsPdcStatus.cleared => (
        'v2_pdc_cleared',
        NexusStatusTone.success,
      ),
      YorksAccountsPdcStatus.replaced => (
        'v2_pdc_replaced',
        NexusStatusTone.neutral,
      ),
      YorksAccountsPdcStatus.returned => (
        'v2_pdc_returned',
        NexusStatusTone.warning,
      ),
      YorksAccountsPdcStatus.bounced => (
        'v2_pdc_bounced',
        NexusStatusTone.danger,
      ),
      YorksAccountsPdcStatus.cancelled => (
        'v2_pdc_cancelled',
        NexusStatusTone.neutral,
      ),
    };
    return StatusChip(label: accountsV2Text(language, key), tone: tone);
  }
}

class _MiniKpi extends StatelessWidget {
  const _MiniKpi({required this.label, required this.value, this.accent});

  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.labelMedium.copyWith(color: AppColors.muted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          value,
          style: AppTypography.titleSmall.copyWith(
            color: accent ?? AppColors.ink,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.emptyLabel,
    required this.rows,
  });

  final String title;
  final String emptyLabel;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(title),
          const SizedBox(height: AppSpacing.xs),
          if (rows.isEmpty)
            Text(emptyLabel, style: AppTypography.bodySmall)
          else
            ...rows,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.leading,
    required this.trailing,
    required this.sub,
    this.chip,
  });

  final String leading;
  final String trailing;
  final String sub;
  final Widget? chip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  leading,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.ink,
                  ),
                ),
                Text(sub, style: AppTypography.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                trailing,
                style: AppTypography.titleSmall.copyWith(
                  color: AppColors.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (chip != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                chip!,
              ],
            ],
          ),
        ],
      ),
    );
  }
}

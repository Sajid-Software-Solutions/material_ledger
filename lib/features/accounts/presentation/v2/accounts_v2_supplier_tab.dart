/// R39 Accounts Workspace V2 — Supplier Bills tab, laid out as the approved
/// prototype: Report actions, five KPIs, a search with delivery-link and
/// payment filters, and the bills table. A row opens the bill, where it is
/// approved, paid, edited, reversed or cancelled on the server.
///
/// Drawn only with view_supplier_costs; the server returns nothing otherwise.
library;

import 'package:flutter/material.dart';

import '../../../../shared/models/app_language.dart';
import '../../domain/accounts_decimal.dart';
import '../../domain/accounts_records_models.dart';
import '../../domain/accounts_supplier_models.dart';
import 'accounts_v2_common.dart';
import 'kit/accounts_v2_kit.dart';
import 'kit/accounts_v2_report_buttons.dart';

const double _eps = 0.005;

class AccountsV2SupplierTab extends StatefulWidget {
  const AccountsV2SupplierTab({
    super.key,
    required this.projection,
    required this.language,
    this.invoicedTotal,
    this.onAddBill,
    this.onOpenBill,
    this.focusBillId,
    this.onFocusHandled,
    this.today,
  });

  final YorksAccountsSupplierBillsProjection projection;
  final AppLanguage language;

  /// Client-invoiced total excluding VAT, for Cost vs. invoiced.
  final YorksAccountsDecimal? invoicedTotal;

  /// Adds a supplier bill; null hides the button.
  final VoidCallback? onAddBill;

  /// Opens a bill, where everything about it is done.
  final ValueChanged<YorksAccountsSupplierBill>? onOpenBill;

  /// A bill to open once, from the Overview.
  final String? focusBillId;
  final VoidCallback? onFocusHandled;
  final DateTime? today;

  @override
  State<AccountsV2SupplierTab> createState() => _AccountsV2SupplierTabState();
}

/// What a bill shows (`billCalc` in the prototype).
final class _BillView {
  _BillView(this.bill, DateTime today)
    : total = _d(bill.totalInclVat),
      paid = _d(bill.paidAmount),
      balance = _d(bill.outstandingAmount),
      exVat = _d(bill.exVatAmount) {
    final due = DateTime(
      bill.dueDate.year,
      bill.dueDate.month,
      bill.dueDate.day,
    );
    final now = DateTime(today.year, today.month, today.day);
    done =
        balance <= _eps && bill.status != YorksAccountsSupplierBillStatus.draft;
    overdue =
        !done &&
        bill.status == YorksAccountsSupplierBillStatus.approved &&
        now.isAfter(due);
    linked = bill.acceptedReceiptReviewId != null;
    status = switch (bill.status) {
      YorksAccountsSupplierBillStatus.cancelled => 'cancelled',
      YorksAccountsSupplierBillStatus.draft => 'draft',
      _ when bill.paymentStatus == YorksAccountsSupplierPaymentStatus.blocked =>
        'blocked',
      _ when done => 'paid',
      _ when overdue => 'overdue',
      _ when paid > _eps => 'part',
      _ => 'unpaid',
    };
  }

  final YorksAccountsSupplierBill bill;
  final double total;
  final double paid;
  final double balance;
  final double exVat;
  late final bool done;
  late final bool overdue;
  late final bool linked;
  late final String status;

  String get linkLabel => [
    if ((bill.poLpoReference ?? '').isNotEmpty) bill.poLpoReference!,
    if ((bill.acceptedDeliveryReference ?? '').isNotEmpty)
      bill.acceptedDeliveryReference!,
  ].join(' · ');

  static double _d(YorksAccountsDecimal v) => v2Number(v.canonicalText);
}

String _statusKey(String s) => switch (s) {
  'paid' => 'v2s_st_paid',
  'overdue' => 'v2s_st_overdue',
  'part' => 'v2s_st_part',
  'draft' => 'v2s_st_draft',
  'cancelled' => 'v2s_st_cancelled',
  'blocked' => 'v2s_st_blocked',
  _ => 'v2s_st_unpaid',
};

AccountsV2ChipTone _statusTone(String s) => switch (s) {
  'paid' => AccountsV2ChipTone.ok,
  'overdue' || 'blocked' => AccountsV2ChipTone.bad,
  'part' => AccountsV2ChipTone.warn,
  _ => AccountsV2ChipTone.neutral,
};

class _AccountsV2SupplierTabState extends State<AccountsV2SupplierTab> {
  final _search = TextEditingController();
  String _fLink = 'all';
  String _fPay = 'all';
  String? _focused;

  String _t(String key) => accountsV2Text(widget.language, key);

  /// Oldest bill first, as the prototype lists them.
  List<_BillView> get _views {
    final views = [
      for (final b in widget.projection.items)
        _BillView(b, widget.today ?? DateTime.now()),
    ];
    views.sort((a, b) {
      final byDate = a.bill.invoiceDate.postgresText.compareTo(
        b.bill.invoiceDate.postgresText,
      );
      return byDate != 0
          ? byDate
          : a.bill.supplierInvoiceReference.compareTo(
              b.bill.supplierInvoiceReference,
            );
    });
    return views;
  }

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _openFocus();
  }

  @override
  void didUpdateWidget(AccountsV2SupplierTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusBillId != oldWidget.focusBillId) _openFocus();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openFocus() {
    final id = widget.focusBillId;
    if (id == null || id == _focused) return;
    _focused = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onFocusHandled?.call();
      final match = widget.projection.items.where(
        (b) => b.supplierBillId == id,
      );
      if (match.isNotEmpty) widget.onOpenBill?.call(match.first);
    });
  }

  bool _matches(_BillView v) {
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      final hay = [
        v.bill.supplierName,
        v.bill.supplierInvoiceReference,
        v.bill.notes ?? '',
        v.linkLabel,
      ].join(' ').toLowerCase();
      if (!hay.contains(q)) return false;
    }
    if (_fLink == 'linked' && !v.linked) return false;
    if (_fLink == 'unlinked' && v.linked) return false;
    if (_fPay != 'all' && v.status != _fPay) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.projection.capabilities.viewSupplierCosts) {
      return AccountsV2Panel(
        child: AccountsV2Empty(icon: 'archive', title: _t('v2_sup_no_access')),
      );
    }
    final all = _views;
    final live = all.where((v) => v.status != 'cancelled').toList();
    final addBill = widget.onAddBill == null
        ? null
        : AccountsV2Button(
            label: _t('v2s_new_bill'),
            icon: 'plus',
            kind: AccountsV2ButtonKind.primary,
            onPressed: widget.onAddBill,
          );
    return AccountsV2Stack(
      children: [
        AccountsV2ReportActions(
          title: _t('v2i_report_actions'),
          actions: [
            for (final output in AccountsV2ReportOutput.values)
              AccountsV2ReportButton(
                projectId: widget.projection.projectId,
                kind: YorksAccountsReportKind.supplierBills,
                output: output,
                language: widget.language,
              ),
          ],
          primary: addBill,
        ),
        _kpis(live),
        _filters(context),
        _bills(all),
      ],
    );
  }

  Widget _kpis(List<_BillView> live) {
    final total = live.fold<double>(0, (a, v) => a + v.total);
    final paid = live.fold<double>(0, (a, v) => a + v.paid);
    final unpaid = live.fold<double>(0, (a, v) => a + v.balance);
    final overdue = live.where((v) => v.overdue).length;
    final unlinked = live.where((v) => !v.linked && !v.done).toList();
    final waiting = unlinked.fold<double>(0, (a, v) => a + v.balance);
    final exVat = live.fold<double>(0, (a, v) => a + v.exVat);
    final invoiced = widget.invoicedTotal == null
        ? 0.0
        : v2Number(widget.invoicedTotal!.canonicalText);
    final count = live.length;
    return AccountsV2KpiRow(
      children: [
        AccountsV2KpiCard(
          icon: 'archive',
          label: _t('v2s_kpi_bills'),
          value: v2Money(total),
          caption:
              '$count ${count == 1 ? _t('v2s_bill_word') : _t('v2s_bills_word')} · '
              '${_t('v2s_incl_vat')}',
        ),
        AccountsV2KpiCard(
          icon: 'coins',
          tone: AccountsV2Tone.green,
          label: _t('v2s_kpi_paid'),
          value: v2Money(paid),
          caption: _t('v2s_paid_sub'),
        ),
        AccountsV2KpiCard(
          icon: 'clock',
          tone: overdue > 0 ? AccountsV2Tone.org : AccountsV2Tone.blue,
          label: _t('v2s_kpi_unpaid'),
          value: v2Money(unpaid),
          caption: '$overdue ${_t('v2s_overdue')}',
          valueTone: overdue > 0
              ? AccountsV2ValueTone.warn
              : AccountsV2ValueTone.plain,
        ),
        AccountsV2KpiCard(
          icon: 'truck',
          tone: unlinked.isNotEmpty ? AccountsV2Tone.red : AccountsV2Tone.green,
          label: _t('v2s_kpi_unlinked'),
          value: '${unlinked.length}',
          caption: unlinked.isNotEmpty
              ? '${v2Money(waiting)} ${_t('v2s_waiting_proof')}'
              : _t('v2s_all_matched'),
          valueTone: unlinked.isNotEmpty
              ? AccountsV2ValueTone.bad
              : AccountsV2ValueTone.plain,
        ),
        AccountsV2KpiCard(
          icon: 'spark',
          tone: AccountsV2Tone.vio,
          label: _t('v2s_kpi_cost'),
          value: invoiced > 0 ? v2Pct(exVat / invoiced * 100, 0) : '—',
          caption: _t('v2s_cost_sub'),
        ),
      ],
    );
  }

  Widget _filters(BuildContext context) {
    final narrow = AccountsV2Breakpoints.isNarrow(context);
    final fields = <Widget>[
      AccountsV2TextField(
        label: _t('v2s_search'),
        controller: _search,
        hint: _t('v2s_search_hint'),
        search: true,
        width: narrow ? null : 300,
      ),
      AccountsV2Select<String>(
        label: _t('v2s_f_link'),
        value: _fLink,
        width: narrow ? null : 228,
        options: [
          ('all', _t('v2i_all')),
          ('linked', _t('v2s_linked')),
          ('unlinked', _t('v2s_not_linked')),
        ],
        onChanged: (v) => setState(() => _fLink = v),
      ),
      AccountsV2Select<String>(
        label: _t('v2s_f_pay'),
        value: _fPay,
        width: narrow ? null : 228,
        options: [
          ('all', _t('v2i_all')),
          for (final s in const ['unpaid', 'part', 'paid', 'overdue', 'draft'])
            (s, _t(_statusKey(s))),
        ],
        onChanged: (v) => setState(() => _fPay = v),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: AccountsV2Breakpoints.isPhone(context)
          ? AccountsV2PhoneFilters(
              search: fields.first,
              selects: fields.sublist(1),
            )
          : narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, f) in fields.indexed) ...[
                  if (i > 0) const SizedBox(height: 10),
                  f,
                ],
              ],
            )
          : Row(
              children: [
                for (final (i, f) in fields.indexed) ...[
                  if (i > 0) const SizedBox(width: 10),
                  f,
                ],
              ],
            ),
    );
  }

  Widget _bills(List<_BillView> all) {
    final rows = all
        .where((v) => (_fPay == 'all' ? v.status != 'cancelled' : true))
        .where(_matches)
        .toList();
    final count = all.where((v) => v.status != 'cancelled').length;
    final small = v2Style(12.5, color: AccountsV2Colors.mut);
    return AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2TileHead(
            icon: 'archive',
            tone: AccountsV2Tone.org,
            title: _t('v2s_card'),
            subtitle: _t('v2s_card_sub'),
            actions: [
              AccountsV2Chip(
                '$count ${count == 1 ? _t('v2s_bill_word') : _t('v2s_bills_word')}',
                tone: AccountsV2ChipTone.pri,
              ),
            ],
          ),
          if (all.isEmpty)
            AccountsV2Empty(
              icon: 'archive',
              title: _t('v2s_empty_title'),
              body: _t('v2s_empty_body'),
              action: widget.onAddBill == null
                  ? null
                  : AccountsV2Button(
                      label: _t('v2s_new_bill'),
                      icon: 'plus',
                      size: AccountsV2ButtonSize.small,
                      onPressed: widget.onAddBill,
                    ),
            )
          else
            AccountsV2Table(
              minWidth: 1000,
              phoneCards: true,
              columns: [
                AccountsV2Column(_t('v2s_c_bill'), width: 112),
                AccountsV2Column(_t('v2s_c_supplier'), flex: 3),
                AccountsV2Column(_t('v2s_c_for'), flex: 4),
                AccountsV2Column(_t('v2s_c_linked'), width: 176),
                AccountsV2Column(_t('v2s_c_date'), width: 108),
                AccountsV2Column(_t('v2s_c_incl'), width: 120, numeric: true),
                AccountsV2Column(_t('v2s_c_paid'), width: 116, numeric: true),
                AccountsV2Column(_t('v2s_c_due'), width: 108),
                AccountsV2Column(
                  _t('v2s_c_status'),
                  width: 100,
                  center: true,
                  cardBadge: true,
                ),
              ],
              emptyRow: SizedBox(
                height: 84,
                child: Center(child: Text(_t('v2s_no_match'), style: small)),
              ),
              rows: [
                for (final v in rows)
                  AccountsV2Row(
                    [
                      Text(
                        v.bill.supplierInvoiceReference,
                        style: v2Style(12.5, weight: FontWeight.w700),
                      ),
                      Text(v.bill.supplierName, maxLines: 2),
                      Text(
                        (v.bill.notes ?? '').isEmpty ? '—' : v.bill.notes!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      v.linked
                          ? AccountsV2Chip(
                              v.linkLabel.isEmpty
                                  ? _t('v2_sup_linked')
                                  : v.linkLabel,
                              tone: AccountsV2ChipTone.ok,
                              icon: 'check',
                            )
                          : AccountsV2Chip(
                              _t('v2s_no_delivery'),
                              tone: AccountsV2ChipTone.warn,
                              icon: 'alert',
                            ),
                      Text(v2Date(v.bill.invoiceDate.postgresText)),
                      Text(v2Fmt(v.total)),
                      Text(v2Fmt(v.paid)),
                      Text(v2Date(v.bill.dueDate.postgresText)),
                      AccountsV2Chip(
                        _t(_statusKey(v.status)),
                        tone: _statusTone(v.status),
                      ),
                    ],
                    key: ValueKey(v.bill.supplierBillId),
                    onTap: widget.onOpenBill == null
                        ? null
                        : () => widget.onOpenBill!(v.bill),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

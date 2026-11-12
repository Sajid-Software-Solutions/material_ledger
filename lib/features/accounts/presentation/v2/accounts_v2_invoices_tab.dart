/// R39 Accounts Workspace V2 — Invoices & Payments tab, laid out as the
/// approved prototype: Report actions, five KPIs, status and due filters, the
/// invoice tracker, the cheque register and a right-hand invoice drawer.
///
/// Figures come from v1_list_client_invoices and the invoice detail read; every
/// command (certify, pay, edit, reverse, cheque, revise, cancel) runs on the
/// server and the tab shows the result only after it confirms. Money appears
/// only with view_project_commercial_values.
library;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/models/app_language.dart';
import '../../domain/accounts_decimal.dart';
import '../../domain/accounts_receivables_inputs.dart';
import '../../domain/accounts_receivables_models.dart';
import '../../domain/accounts_records_models.dart';
import 'accounts_v2_common.dart';
import 'accounts_v2_safety.dart';
import 'kit/accounts_v2_kit.dart';
import 'kit/accounts_v2_report_buttons.dart';

/// Records client certification; returns null on success or an error message.
typedef YorksCertifyAction =
    Future<String?> Function(YorksAccountsCertificationInput input);

/// Records a client payment; returns null on success or an error message.
typedef YorksPayAction =
    Future<String?> Function(YorksAccountsPaymentInput input);

/// Reverses a recorded receipt; returns null on success or an error message.
typedef YorksReversePaymentAction =
    Future<String?> Function(YorksAccountsPaymentReversalInput input);

/// Edits a payment in one step; returns null on success or an error message.
typedef YorksCorrectPaymentAction =
    Future<String?> Function(YorksAccountsPaymentCorrectionInput input);

/// Edits the latest certification; returns null on success or an error message.
typedef YorksCorrectCertificationAction =
    Future<String?> Function(YorksAccountsCertificationCorrectionInput input);

/// Cancels an invoice; returns null on success or an error message.
typedef YorksCancelInvoiceAction =
    Future<String?> Function(YorksAccountsEntityActionInput input);

/// Records a cheque against an invoice; returns null on success or a failure code.
typedef YorksCreatePdcAction =
    Future<String?> Function(YorksAccountsPdcCreateInput input);

/// Revises an issued invoice (R.n); returns null on success or an error message.
typedef YorksReviseInvoiceAction =
    Future<String?> Function({
      required String invoiceId,
      required int expectedVersion,
      required String reason,
    });

/// A file attached to an invoice, for the drawer's Files row.
typedef AccountsV2InvoiceFile = ({String name, VoidCallback? onOpen});

const double _eps = 0.005;

/// What the tracker says about an invoice (`invCalc` in the prototype).
final class _InvoiceView {
  _InvoiceView(this.inv, DateTime today)
    : gross = _d(inv.claimedExVat),
      total = _d(inv.totalInclVat),
      received = _d(inv.amountPaidTillDate),
      inHand = _d(inv.pdcExposure),
      certified = _d(inv.certifiedExVat),
      stillDue = _d(inv.stillDue) {
    balance = certified > _eps
        ? stillDue
        : (total - received).clamp(0, double.infinity).toDouble();
    paid =
        inv.status == YorksAccountsInvoiceStatus.paid ||
        (certified > _eps && balance <= _eps);
    final due = _date(inv.dueDate);
    final last = _date(inv.lastReceiptDate);
    final now = DateTime(today.year, today.month, today.day);
    if (paid) {
      delay = due != null && last != null ? last.difference(due).inDays : 0;
    } else {
      delay = due != null && now.isAfter(due) ? now.difference(due).inDays : 0;
    }
    daysToDue = due == null ? 0 : due.difference(now).inDays;
    overdue =
        !paid &&
        !inv.revisionInProgress &&
        (inv.dueState == YorksAccountsDueState.overdue || delay > 0);
    status = switch (inv.status) {
      YorksAccountsInvoiceStatus.cancelled => 'cancelled',
      YorksAccountsInvoiceStatus.returned => 'returned',
      YorksAccountsInvoiceStatus.draft => 'draft',
      _ when inv.revisionInProgress => 'revising',
      _ when paid => 'paid',
      _ when overdue => 'overdue',
      _ when received > _eps => 'part_paid',
      _ when certified > _eps => 'certified',
      _ => 'submitted',
    };
  }

  final YorksAccountsClientInvoiceSummary inv;
  final double gross;
  final double total;
  final double received;
  final double inHand;
  final double certified;
  final double stillDue;
  late final double balance;
  late final bool paid;
  late final int delay;
  late final int daysToDue;
  late final bool overdue;
  late final String status;

  /// Certified amount including VAT, at the invoice's own rate.
  double get certifiedInclVat => gross > 0 ? certified * total / gross : 0;

  String get dueState => paid
      ? 'paid'
      : overdue
      ? 'overdue'
      : daysToDue <= 14
      ? 'soon'
      : 'notdue';

  static double _d(YorksAccountsDecimal? v) =>
      v == null ? 0 : v2Number(v.canonicalText);

  static DateTime? _date(YorksAccountsDate? d) =>
      d == null ? null : DateTime.tryParse(d.postgresText);
}

AccountsV2ChipTone _statusTone(String status) => switch (status) {
  'paid' => AccountsV2ChipTone.ok,
  'overdue' || 'returned' => AccountsV2ChipTone.bad,
  'part_paid' => AccountsV2ChipTone.warn,
  'certified' => AccountsV2ChipTone.pri,
  'revising' => AccountsV2ChipTone.vio,
  _ => AccountsV2ChipTone.neutral,
};

String _statusKey(String status) => switch (status) {
  'paid' => 'v2i_st_paid',
  'overdue' => 'v2i_st_overdue',
  'part_paid' => 'v2i_st_part_paid',
  'certified' => 'v2i_st_certified',
  'revising' => 'v2i_st_revising',
  'returned' => 'v2i_st_returned',
  'cancelled' => 'v2i_st_cancelled',
  'draft' => 'v2i_st_draft',
  _ => 'v2i_st_submitted',
};

class AccountsV2InvoicesTab extends StatefulWidget {
  const AccountsV2InvoicesTab({
    super.key,
    required this.projection,
    required this.language,
    this.onCertify,
    this.onPay,
    this.onReversePayment,
    this.onCorrectPayment,
    this.onCorrectCertification,
    this.onCancelInvoice,
    this.onRestoreInvoice,
    this.onRevise,
    this.onCreatePdc,
    this.onPrintInvoice,
    this.onOpenDetail,
    this.trailing,
    this.claimNumbers = const {},
    this.filesFor,
    this.onAttach,
    this.onOpenClaims,
    this.focusInvoiceId,
    this.focusRevise = false,
    this.onFocusHandled,
    this.today,
  });

  final YorksAccountsInvoicesProjection projection;
  final AppLanguage language;

  /// The cheque register card, drawn below the tracker.
  final Widget? trailing;
  final YorksCertifyAction? onCertify;
  final YorksPayAction? onPay;
  final YorksReversePaymentAction? onReversePayment;
  final YorksCorrectPaymentAction? onCorrectPayment;
  final YorksCorrectCertificationAction? onCorrectCertification;
  final YorksCancelInvoiceAction? onCancelInvoice;

  /// Restores a cancelled invoice (and its claim); null hides Restore.
  final YorksCancelInvoiceAction? onRestoreInvoice;

  /// Revises an issued invoice (R.n) from the drawer; null hides it.
  final YorksReviseInvoiceAction? onRevise;

  /// Records a cheque; shown only with manage_pdc.
  final YorksCreatePdcAction? onCreatePdc;

  /// Fetches + renders the invoice PDF and opens the print/preview; returns
  /// null on success or an error message.
  final Future<String?> Function(String invoiceId)? onPrintInvoice;

  /// Fetches the full invoice detail for the drawer; null on failure.
  final Future<YorksAccountsInvoiceDetailProjection?> Function(
    String invoiceId,
  )?
  onOpenDetail;

  /// Claim number (#01, #02 …) by claim id.
  final Map<String, int> claimNumbers;

  /// Files attached to an invoice.
  final List<AccountsV2InvoiceFile> Function(String invoiceId)? filesFor;

  /// Attaches a signed copy to an invoice.
  final Future<void> Function(String invoiceId)? onAttach;

  /// Opens Progress & Claims (New invoice from claim).
  final VoidCallback? onOpenClaims;

  /// An invoice to open once, from the Overview or a claim.
  final String? focusInvoiceId;
  final bool focusRevise;
  final VoidCallback? onFocusHandled;
  final DateTime? today;

  @override
  State<AccountsV2InvoicesTab> createState() => _AccountsV2InvoicesTabState();
}

class _AccountsV2InvoicesTabState extends State<AccountsV2InvoicesTab> {
  String _fStatus = 'all';
  String _fDue = 'all';
  String? _focused;

  String _t(String key) => accountsV2Text(widget.language, key);
  bool get _values => widget.projection.capabilities.canViewValues;
  DateTime get _today => widget.today ?? DateTime.now();

  /// Oldest invoice first, as the tracker in the Project Master File lists them.
  List<_InvoiceView> get _views {
    final views = [
      for (final inv in widget.projection.invoices) _InvoiceView(inv, _today),
    ];
    String key(_InvoiceView v) =>
        '${v.inv.submissionDate?.postgresText ?? '9999'}|${v.inv.invoiceReference}';
    views.sort((a, b) => key(a).compareTo(key(b)));
    return views;
  }

  @override
  void initState() {
    super.initState();
    _openFocus();
  }

  @override
  void didUpdateWidget(AccountsV2InvoicesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusInvoiceId != oldWidget.focusInvoiceId) _openFocus();
  }

  void _openFocus() {
    final id = widget.focusInvoiceId;
    if (id == null || id == _focused) return;
    _focused = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onFocusHandled?.call();
      final match = _views.where((v) => v.inv.invoiceId == id);
      if (match.isNotEmpty) _openDrawer(match.first);
    });
  }

  String _claimLabel(String claimId) {
    final n = widget.claimNumbers[claimId];
    return n == null
        ? _t('v2i_claim')
        : '${_t('v2i_claim')} #${n.toString().padLeft(2, '0')}';
  }

  String _money(double v, [int digits = 2]) => v2Money(v, digits: digits);

  @override
  Widget build(BuildContext context) {
    final all = _views;
    final live = all.where((v) => v.status != 'cancelled').toList();
    final rows = all.where((v) {
      final status = _fStatus == 'all'
          ? v.status != 'cancelled'
          : v.status == _fStatus;
      final due = _fDue == 'all' || v.dueState == _fDue;
      return status && due;
    }).toList();
    final projectId = widget.projection.projectId;
    return AccountsV2Stack(
      children: [
        AccountsV2ReportActions(
          title: _t('v2i_report_actions'),
          actions: [
            for (final output in AccountsV2ReportOutput.values)
              AccountsV2ReportButton(
                projectId: projectId,
                kind: YorksAccountsReportKind.clientInvoices,
                companions: const [YorksAccountsReportKind.pdcRegister],
                output: output,
                language: widget.language,
              ),
          ],
          primary: widget.onOpenClaims == null
              ? null
              : AccountsV2Button(
                  label: _t('v2i_new_from_claim'),
                  icon: 'plus',
                  kind: AccountsV2ButtonKind.primary,
                  onPressed: widget.onOpenClaims,
                ),
        ),
        if (_values) _kpis(live),
        _filters(context),
        _tracker(context, all, rows),
        ?widget.trailing,
      ],
    );
  }

  Widget _kpis(List<_InvoiceView> live) {
    final invoiced = live.fold<double>(0, (a, v) => a + v.total);
    final certified = live.fold<double>(0, (a, v) => a + v.certifiedInclVat);
    final received = live.fold<double>(0, (a, v) => a + v.received);
    final inHand = live.fold<double>(0, (a, v) => a + v.inHand);
    final due = live.fold<double>(0, (a, v) => a + v.stillDue);
    final overdue = live.where((v) => v.overdue).toList();
    final overdueAmount = overdue.fold<double>(0, (a, v) => a + v.balance);
    final count = live.length;
    return AccountsV2KpiRow(
      children: [
        AccountsV2KpiCard(
          icon: 'receipt',
          label: _t('v2i_kpi_invoiced'),
          value: _money(invoiced),
          caption:
              '$count ${count == 1 ? _t('v2i_invoice_one') : _t('v2i_invoice_many')}',
        ),
        AccountsV2KpiCard(
          icon: 'shield',
          tone: AccountsV2Tone.vio,
          label: _t('v2i_kpi_certified'),
          value: _money(certified),
          caption: _t('v2i_incl_vat'),
        ),
        AccountsV2KpiCard(
          icon: 'coins',
          tone: AccountsV2Tone.green,
          label: _t('v2i_kpi_received'),
          value: _money(received),
          caption: _t('v2i_cleared_only'),
          valueTone: AccountsV2ValueTone.ok,
        ),
        AccountsV2KpiCard(
          icon: 'cheque',
          tone: AccountsV2Tone.vio,
          label: _t('v2i_kpi_cheques'),
          value: _money(inHand),
          caption: _t('v2i_not_cleared'),
        ),
        AccountsV2KpiCard(
          icon: 'alert',
          tone: overdue.isNotEmpty ? AccountsV2Tone.red : AccountsV2Tone.org,
          label: _t('v2i_kpi_due'),
          value: _money(due),
          caption: overdue.isNotEmpty
              ? '${_money(overdueAmount)} ${_t('v2i_overdue_word')}'
              : '0 ${_t('v2i_overdue_word')}',
          valueTone: overdue.isNotEmpty
              ? AccountsV2ValueTone.bad
              : AccountsV2ValueTone.plain,
        ),
      ],
    );
  }

  Widget _filters(BuildContext context) {
    final narrow = AccountsV2Breakpoints.isNarrow(context);
    final width = narrow ? null : 228.0;
    final selects = [
      AccountsV2Select<String>(
        label: _t('v2i_f_status'),
        value: _fStatus,
        width: width,
        options: [
          ('all', _t('v2i_all')),
          for (final s in const [
            'submitted',
            'certified',
            'part_paid',
            'paid',
            'overdue',
            'revising',
            'cancelled',
          ])
            (s, _t(_statusKey(s))),
        ],
        onChanged: (v) => setState(() => _fStatus = v),
      ),
      AccountsV2Select<String>(
        label: _t('v2i_f_due'),
        value: _fDue,
        width: width,
        options: [
          ('all', _t('v2i_all')),
          ('overdue', _t('v2i_st_overdue')),
          ('soon', _t('v2i_due_soon')),
          ('notdue', _t('v2i_due_notdue')),
          ('paid', _t('v2i_st_paid')),
        ],
        onChanged: (v) => setState(() => _fDue = v),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, s) in selects.indexed) ...[
                  if (i > 0) const SizedBox(height: 10),
                  s,
                ],
              ],
            )
          : Row(
              children: [
                for (final (i, s) in selects.indexed) ...[
                  if (i > 0) const SizedBox(width: 10),
                  s,
                ],
              ],
            ),
    );
  }

  Widget _tracker(
    BuildContext context,
    List<_InvoiceView> all,
    List<_InvoiceView> rows,
  ) {
    final liveCount = all.where((v) => v.status != 'cancelled').length;
    final chip = rows.length == liveCount
        ? '$liveCount ${liveCount == 1 ? _t('v2i_invoice_one') : _t('v2i_invoice_many')}'
        : '${rows.length} ${_t('v2i_of')} $liveCount';
    final Widget body;
    if (all.isEmpty) {
      body = AccountsV2Empty(
        icon: 'receipt',
        title: _t('v2i_no_records'),
        body: _t('v2i_no_records_body'),
        action: widget.onOpenClaims == null
            ? null
            : AccountsV2Button(
                label: _t('v2i_prepare_claim'),
                onPressed: widget.onOpenClaims,
              ),
      );
    } else if (rows.isEmpty) {
      body = AccountsV2Empty(
        icon: 'receipt',
        title: _t('v2i_no_match'),
        action: AccountsV2Button(
          label: _t('v2i_clear_filters'),
          onPressed: () => setState(() {
            _fStatus = 'all';
            _fDue = 'all';
          }),
        ),
      );
    } else {
      body = AccountsV2Table(
        minWidth: 980,
        columns: [
          AccountsV2Column(_t('v2i_c_invoice'), flex: 2),
          AccountsV2Column(_t('v2i_c_submitted'), width: 112),
          if (_values) ...[
            AccountsV2Column(_t('v2i_c_excl'), width: 120, numeric: true),
            AccountsV2Column(_t('v2i_c_incl'), width: 120, numeric: true),
          ],
          AccountsV2Column(_t('v2i_c_certified'), width: 116),
          AccountsV2Column(_t('v2i_c_due'), width: 112),
          if (_values) ...[
            AccountsV2Column(_t('v2i_c_received'), width: 168, numeric: true),
            AccountsV2Column(_t('v2i_c_balance'), width: 120, numeric: true),
          ],
          AccountsV2Column(_t('v2i_c_status'), width: 130, center: true),
        ],
        rows: [for (final v in rows) _row(v)],
      );
    }
    return AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2TileHead(
            icon: 'receipt',
            title: _t('v2i_tracker'),
            subtitle: _t('v2i_tracker_sub'),
            actions: [AccountsV2Chip(chip, tone: AccountsV2ChipTone.pri)],
          ),
          body,
        ],
      ),
    );
  }

  AccountsV2Row _row(_InvoiceView v) {
    final inv = v.inv;
    final small = v2Style(12, color: AccountsV2Colors.mut);
    final certDiffers =
        v.certified > _eps && (v.certified - v.gross).abs() > _eps;
    final statusLine = v.delay > 0
        ? '${v.delay} ${v.paid ? _t('v2i_days_late') : _t('v2i_days_overdue')}'
        : v.paid
        ? _t('v2i_on_time')
        : '${_t('v2i_due_in')} ${v.daysToDue} ${_t('v2i_d')}';
    return AccountsV2Row(
      [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // An invoice number never breaks ("YRA32202R" / ".1"): on a narrow
            // column it shrinks to fit instead.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                inv.invoiceReference,
                maxLines: 1,
                softWrap: false,
                style: v2Style(12.5, weight: FontWeight.w700),
              ),
            ),
            Text(
              [
                _claimLabel(inv.claimId),
                if (inv.replacesReference != null)
                  '${_t('v2i_replaces')} ${inv.replacesReference}',
              ].join(' · '),
              style: small,
            ),
          ],
        ),
        Text(v2Date(inv.submissionDate?.postgresText)),
        if (_values) ...[Text(v2Fmt(v.gross)), Text(v2Fmt(v.total))],
        inv.certificationDate == null && v.certified <= _eps
            ? Text(
                _t('v2i_waiting'),
                style: v2Style(12.5, color: AccountsV2Colors.mut),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(v2Date(inv.certificationDate?.postgresText)),
                  if (certDiffers && _values)
                    Text(
                      v2Fmt(v.certified),
                      style: v2Style(12, color: AccountsV2Colors.warn),
                    ),
                ],
              ),
        Text(v2Date(inv.dueDate?.postgresText)),
        if (_values) ...[
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(v2Fmt(v.received)),
              if (v.inHand > _eps)
                Text(
                  '+ ${v2Fmt(v.inHand)} ${_t('v2i_cheque_word')}',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: v2Style(12, color: AccountsV2Colors.vio),
                ),
            ],
          ),
          Text(
            v2Fmt(v.balance),
            style: v2Style(12.5, weight: FontWeight.w700, tabular: true),
          ),
        ],
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AccountsV2Chip(
              _t(_statusKey(v.status)),
              tone: _statusTone(v.status),
            ),
            const SizedBox(height: 3),
            Text(
              statusLine,
              textAlign: TextAlign.center,
              style: v2Style(
                12,
                color: v.delay > 0
                    ? AccountsV2Colors.bad
                    : AccountsV2Colors.mut,
              ),
            ),
          ],
        ),
      ],
      key: ValueKey(inv.invoiceId),
      onTap: widget.onOpenDetail == null ? null : () => _openDrawer(v),
    );
  }

  // ─── Drawer ───────────────────────────────────────────────────────────────

  Future<void> _openDrawer(_InvoiceView v) async {
    final fetch = widget.onOpenDetail;
    if (fetch == null) return;
    await showAccountsV2Drawer<void>(
      context,
      closeLabel: _t('v2i_close'),
      title: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(v.inv.invoiceReference),
          AccountsV2Chip(_t(_statusKey(v.status)), tone: _statusTone(v.status)),
        ],
      ),
      builder: (_) => _InvoiceDrawer(
        view: v,
        all: _views,
        language: widget.language,
        fetch: () => fetch(v.inv.invoiceId),
        capabilities: widget.projection.capabilities,
        claimLabel: _claimLabel(v.inv.claimId),
        files: widget.filesFor?.call(v.inv.invoiceId) ?? const [],
        onAttach: widget.onAttach == null
            ? null
            : () => widget.onAttach!(v.inv.invoiceId),
        onCertify: widget.onCertify,
        onPay: widget.onPay,
        onReversePayment: widget.onReversePayment,
        onCorrectPayment: widget.onCorrectPayment,
        onCorrectCertification: widget.onCorrectCertification,
        onCancelInvoice: widget.onCancelInvoice,
        onRestoreInvoice: widget.onRestoreInvoice,
        onRevise: widget.onRevise,
        onCreatePdc: widget.projection.capabilities.managePdc
            ? widget.onCreatePdc
            : null,
        onPrintInvoice: widget.onPrintInvoice,
        onOpenClaims: widget.onOpenClaims,
        openRevise:
            widget.focusRevise && v.inv.invoiceId == widget.focusInvoiceId,
      ),
    );
  }
}

/// The invoice drawer body: figures, actions, progress, payments, files.
class _InvoiceDrawer extends StatefulWidget {
  const _InvoiceDrawer({
    required this.view,
    required this.all,
    required this.language,
    required this.fetch,
    required this.capabilities,
    required this.claimLabel,
    required this.files,
    this.onAttach,
    this.onCertify,
    this.onPay,
    this.onReversePayment,
    this.onCorrectPayment,
    this.onCorrectCertification,
    this.onCancelInvoice,
    this.onRestoreInvoice,
    this.onRevise,
    this.onCreatePdc,
    this.onPrintInvoice,
    this.onOpenClaims,
    this.openRevise = false,
  });

  final _InvoiceView view;
  final List<_InvoiceView> all;
  final AppLanguage language;
  final Future<YorksAccountsInvoiceDetailProjection?> Function() fetch;
  final YorksAccountsReceivablesCapabilities capabilities;
  final String claimLabel;
  final List<AccountsV2InvoiceFile> files;
  final VoidCallback? onAttach;
  final YorksCertifyAction? onCertify;
  final YorksPayAction? onPay;
  final YorksReversePaymentAction? onReversePayment;
  final YorksCorrectPaymentAction? onCorrectPayment;
  final YorksCorrectCertificationAction? onCorrectCertification;
  final YorksCancelInvoiceAction? onCancelInvoice;

  /// Restores a cancelled invoice (and its claim); null hides Restore.
  final YorksCancelInvoiceAction? onRestoreInvoice;
  final YorksReviseInvoiceAction? onRevise;
  final YorksCreatePdcAction? onCreatePdc;
  final Future<String?> Function(String invoiceId)? onPrintInvoice;
  final VoidCallback? onOpenClaims;
  final bool openRevise;

  @override
  State<_InvoiceDrawer> createState() => _InvoiceDrawerState();
}

class _InvoiceDrawerState extends State<_InvoiceDrawer> {
  late Future<YorksAccountsInvoiceDetailProjection?> _detail = widget.fetch();
  bool _reviseOpened = false;

  String _t(String key) => accountsV2Text(widget.language, key);
  _InvoiceView get v => widget.view;
  YorksAccountsClientInvoiceSummary get inv => widget.view.inv;
  String? _detailProjectId;

  /// After a dialog's command succeeded (the dialog showed any refusal itself
  /// and stayed open): closes the drawer, so the refreshed tracker is shown.
  void _done(Object? result, String doneKey) {
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop();
    messenger?.showSnackBar(SnackBar(content: Text(_t(doneKey))));
  }

  /// Closes the drawer on success, so the refreshed tracker is what's shown. A
  /// refusal stays over the drawer.
  Future<void> _finish(String? error, String doneKey) async {
    if (!mounted) return;
    if (error == null) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      messenger?.showSnackBar(SnackBar(content: Text(_t(doneKey))));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AccountsV2AlertDialog(
        content: Text(accountsV2ErrorText(widget.language, error)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(MaterialLocalizations.of(dialogContext).okButtonLabel),
          ),
        ],
      ),
    );
  }

  bool get _canCertify =>
      widget.onCertify != null &&
      widget.capabilities.recordClientCertification &&
      const {
        YorksAccountsInvoiceStatus.submitted,
        YorksAccountsInvoiceStatus.underCertification,
        YorksAccountsInvoiceStatus.partiallyCertified,
        YorksAccountsInvoiceStatus.certified,
      }.contains(inv.status);

  bool get _canPay =>
      widget.onPay != null &&
      widget.capabilities.recordClientPayment &&
      !v.paid &&
      const {
        YorksAccountsInvoiceStatus.certified,
        YorksAccountsInvoiceStatus.partiallyCertified,
        YorksAccountsInvoiceStatus.partiallyPaid,
      }.contains(inv.status);

  bool get _canCheque =>
      widget.onCreatePdc != null &&
      inv.certifiedExVat.isPositive &&
      !const {
        YorksAccountsInvoiceStatus.draft,
        YorksAccountsInvoiceStatus.returned,
        YorksAccountsInvoiceStatus.cancelled,
        YorksAccountsInvoiceStatus.paid,
      }.contains(inv.status);

  bool get _canPrint =>
      widget.onPrintInvoice != null &&
      inv.status != YorksAccountsInvoiceStatus.draft &&
      inv.status != YorksAccountsInvoiceStatus.cancelled;

  /// D7: revisable before any certification, net payment or active cheque. The
  /// server re-checks.
  bool _canRevise(YorksAccountsInvoiceDetailProjection d) {
    if (widget.onRevise == null || inv.revisionInProgress) return false;
    final status = d.invoice.status;
    if (status != YorksAccountsInvoiceStatus.submitted &&
        status != YorksAccountsInvoiceStatus.underCertification) {
      return false;
    }
    if (d.certifications.isNotEmpty) return false;
    if (d.invoice.paidAmount?.isPositive ?? false) return false;
    return !d.pdcs.any(
      (p) => const {
        YorksAccountsPdcStatus.expected,
        YorksAccountsPdcStatus.received,
        YorksAccountsPdcStatus.deposited,
      }.contains(p.status),
    );
  }

  int get _nextRevision {
    final m = RegExp(r'R\.(\d+)$').firstMatch(inv.invoiceReference);
    return m == null ? 1 : int.parse(m.group(1)!) + 1;
  }

  Set<String> _reversedIds(YorksAccountsInvoiceDetailProjection d) => {
    for (final p in d.payments)
      if (p.entryKind == YorksAccountsPaymentEntryKind.reversal &&
          p.originalPaymentId != null)
        p.originalPaymentId!,
  };

  Future<void> _certify() async {
    final input = await showDialog<YorksAccountsCertificationInput>(
      context: context,
      builder: (_) => _CertifyDialog(
        projectId: _detailProjectId ?? '',
        invoice: inv,
        language: widget.language,
        onSubmit: widget.onCertify,
      ),
    );
    _done(input, 'v2_cert_saved');
  }

  Future<void> _editCertification(
    YorksAccountsInvoiceDetailProjection d,
    YorksAccountsClientCertification c,
  ) async {
    final input = await showDialog<YorksAccountsCertificationCorrectionInput>(
      context: context,
      builder: (_) => _EditCertificationDialog(
        projectId: d.projectId,
        invoiceId: inv.invoiceId,
        expectedVersion: d.invoice.recordVersion,
        certification: c,
        language: widget.language,
        onSubmit: widget.onCorrectCertification,
      ),
    );
    _done(input, 'v2_cert_edit_done');
  }

  Future<void> _pay() async {
    final input = await showDialog<YorksAccountsPaymentInput>(
      context: context,
      builder: (_) => _PayDialog(
        projectId: _detailProjectId ?? '',
        invoice: inv,
        language: widget.language,
        onSubmit: widget.onPay,
      ),
    );
    _done(input, 'v2_pay_saved');
  }

  Future<void> _cheque() async {
    final input = await showDialog<YorksAccountsPdcCreateInput>(
      context: context,
      builder: (_) => _ChequeDialog(
        projectId: _detailProjectId ?? '',
        invoice: inv,
        language: widget.language,
        onSubmit: widget.onCreatePdc,
      ),
    );
    _done(input, 'v2_pdc_saved');
  }

  Future<void> _print() async {
    final error = await widget.onPrintInvoice!(inv.invoiceId);
    if (!mounted || error == null) return;
    await _finish(error, 'v2_inv_pdf_failed');
  }

  Future<void> _revise(YorksAccountsInvoiceDetailProjection d) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReviseDialog(
        language: widget.language,
        onSubmit: (reason) => widget.onRevise!(
          invoiceId: inv.invoiceId,
          expectedVersion: d.invoice.recordVersion,
          reason: reason,
        ),
      ),
    );
    _done(reason, 'v2_inv_revised');
  }

  Future<void> _cancel(YorksAccountsInvoiceDetailProjection d) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _CancelInvoiceDialog(
        language: widget.language,
        onSubmit: (reason) => widget.onCancelInvoice!(
          YorksAccountsEntityActionInput(
            projectId: d.projectId,
            entityId: inv.invoiceId,
            expectedVersion: d.invoice.recordVersion,
            reason: reason,
          ),
        ),
      ),
    );
    _done(reason, 'v2_inv_cancel_done');
  }

  Future<void> _restore(YorksAccountsInvoiceDetailProjection d) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReviseDialog(
        language: widget.language,
        titleKey: 'v2r_restore_invoice',
        hintKey: 'v2r_restore_invoice_detail',
        reasonKey: 'v2r_restore_reason',
        confirmKey: 'v2r_restore_invoice',
        onSubmit: (reason) async => accountsV2RestoreFailure(
          await widget.onRestoreInvoice!(
            YorksAccountsEntityActionInput(
              projectId: d.projectId,
              entityId: inv.invoiceId,
              expectedVersion: d.invoice.recordVersion,
              reason: reason,
            ),
          ),
        ),
      ),
    );
    _done(reason, 'v2r_invoice_restored');
  }

  Future<void> _editPayment(
    YorksAccountsInvoiceDetailProjection d,
    YorksAccountsClientPayment p,
  ) async {
    final input = await showDialog<YorksAccountsPaymentCorrectionInput>(
      context: context,
      builder: (_) => _EditPaymentDialog(
        projectId: d.projectId,
        invoiceId: inv.invoiceId,
        expectedVersion: d.invoice.recordVersion,
        payment: p,
        language: widget.language,
        onSubmit: widget.onCorrectPayment,
      ),
    );
    _done(input, 'v2_pay_edit_done');
  }

  Future<void> _reverse(
    YorksAccountsInvoiceDetailProjection d,
    YorksAccountsClientPayment p,
  ) async {
    final input = await showDialog<YorksAccountsPaymentReversalInput>(
      context: context,
      builder: (_) => _ReversalDialog(
        projectId: d.projectId,
        invoiceId: inv.invoiceId,
        expectedVersion: d.invoice.recordVersion,
        payment: p,
        language: widget.language,
        onSubmit: widget.onReversePayment,
      ),
    );
    _done(input, 'v2_pay_reversed');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<YorksAccountsInvoiceDetailProjection?>(
      future: _detail,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final d = snap.data;
        if (d == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _t('v2_inv_detail_failed'),
                    textAlign: TextAlign.center,
                    style: v2Style(13, color: AccountsV2Colors.ink2),
                  ),
                  const SizedBox(height: 12),
                  AccountsV2Button(
                    label: _t('v2_retry'),
                    onPressed: () => setState(() => _detail = widget.fetch()),
                  ),
                ],
              ),
            ),
          );
        }
        _detailProjectId = d.projectId;
        if (widget.openRevise && !_reviseOpened && _canRevise(d)) {
          _reviseOpened = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _revise(d);
          });
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _stats(d),
              if (_d(d.invoice.retentionSnapshot) > _eps) ...[
                const SizedBox(height: 8),
                AccountsV2KeyValue(
                  label: _t('v2i_retention_held'),
                  value: v2Money(_d(d.invoice.retentionSnapshot)),
                ),
              ],
              const SizedBox(height: 14),
              _actions(d),
              AccountsV2Section(_t('v2i_progress')),
              AccountsV2Timeline(steps: _timeline(d)),
              AccountsV2Section(_t('v2i_payments')),
              _payments(d),
              AccountsV2Section(_t('v2i_files')),
              _files(),
              if (inv.replacesReference != null) ...[
                AccountsV2Section(_t('v2i_earlier')),
                _earlier(),
              ],
              if (_canCancel(d)) ...[
                const SizedBox(height: 20),
                AccountsV2Button(
                  label: _t('v2i_cancel_invoice'),
                  icon: 'x',
                  kind: AccountsV2ButtonKind.ghostDanger,
                  size: AccountsV2ButtonSize.small,
                  onPressed: () => _cancel(d),
                ),
                Text(
                  _t('v2_inv_cancel_hint'),
                  style: v2Style(12, color: AccountsV2Colors.mut),
                ),
              ],
              if (_canRestore(d)) ...[
                const SizedBox(height: 20),
                AccountsV2Button(
                  key: const ValueKey('accounts-v2-restore-invoice'),
                  label: _t('v2r_restore_invoice'),
                  icon: 'history',
                  size: AccountsV2ButtonSize.small,
                  onPressed: () => _restore(d),
                ),
                const SizedBox(height: 4),
                Text(
                  _t('v2r_restore_invoice_hint'),
                  style: v2Style(12, color: AccountsV2Colors.mut),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static double _d(YorksAccountsDecimal? value) =>
      value == null ? 0 : v2Number(value.canonicalText);

  /// A cancelled invoice that no revision replaced. The server re-checks the
  /// rest (claim cap, contract revision) and names the reason if it refuses.
  bool _canRestore(YorksAccountsInvoiceDetailProjection d) =>
      widget.onRestoreInvoice != null &&
      widget.capabilities.manageClientInvoices &&
      d.invoice.status == YorksAccountsInvoiceStatus.cancelled &&
      !widget.all.any(
        (x) => x.inv.replacesReference == d.invoice.invoiceReference,
      );

  bool _canCancel(YorksAccountsInvoiceDetailProjection d) =>
      widget.onCancelInvoice != null &&
      d.commands.cancelInvoice &&
      d.invoice.status != YorksAccountsInvoiceStatus.cancelled &&
      d.invoice.status != YorksAccountsInvoiceStatus.paid &&
      d.invoice.status != YorksAccountsInvoiceStatus.draft;

  Widget _stats(YorksAccountsInvoiceDetailProjection d) {
    final stats = [
      AccountsV2MiniStat(
        label: _t('v2i_invoice_total'),
        value: v2Fmt(v.total),
        caption: '${v2Fmt(v.gross)} ${_t('v2i_plus_vat')}',
      ),
      AccountsV2MiniStat(
        label: _t('v2i_kpi_received'),
        value: v2Fmt(v.received),
        tone: AccountsV2ValueTone.ok,
        caption: v.inHand > _eps
            ? '+ ${v2Fmt(v.inHand)} ${_t('v2i_cheque_word')}'
            : _t('v2i_cleared_lower'),
      ),
      AccountsV2MiniStat(
        label: _t('v2i_c_balance'),
        value: v2Fmt(v.balance),
        tone: v.overdue ? AccountsV2ValueTone.bad : AccountsV2ValueTone.plain,
        caption: v.overdue
            ? '${v.delay} ${_t('v2i_days_overdue')}'
            : '${_t('v2i_due_word')} ${v2Date(inv.dueDate?.postgresText)}',
      ),
    ];
    if (MediaQuery.sizeOf(context).width <= 640) {
      return AccountsV2Stack(gap: 10, children: stats);
    }
    return AccountsV2Grid(columns: 3, gap: 10, children: stats);
  }

  Widget _actions(YorksAccountsInvoiceDetailProjection d) {
    final buttons = <Widget>[];
    if (inv.revisionInProgress) {
      if (widget.onOpenClaims != null) {
        buttons.add(
          AccountsV2Button(
            label: '${_t('v2i_open_claim')} · ${widget.claimLabel}',
            block: true,
            onPressed: () {
              Navigator.of(context).pop();
              widget.onOpenClaims!();
            },
          ),
        );
      }
    } else {
      final latest = d.certifications.isEmpty
          ? null
          : d.certifications.reduce(
              (a, b) => a.revisionNumber >= b.revisionNumber ? a : b,
            );
      final canEditCert =
          latest != null &&
          widget.onCorrectCertification != null &&
          d.commands.correctCertification;
      if (_canCertify || canEditCert) {
        buttons.add(
          AccountsV2Button(
            label: latest == null ? _t('v2i_record_cert') : _t('v2i_edit_cert'),
            icon: 'shield',
            size: AccountsV2ButtonSize.small,
            block: true,
            onPressed: canEditCert
                ? () => _editCertification(d, latest)
                : _certify,
          ),
        );
      }
      if (widget.onPay != null && widget.capabilities.recordClientPayment) {
        buttons.add(
          AccountsV2Button(
            label: _t('v2i_record_payment'),
            icon: 'wallet',
            kind: AccountsV2ButtonKind.primary,
            size: AccountsV2ButtonSize.small,
            block: true,
            onPressed: _canPay ? _pay : null,
          ),
        );
      }
      if (_canCheque) {
        buttons.add(
          AccountsV2Button(
            label: _t('v2i_record_cheque'),
            icon: 'cheque',
            size: AccountsV2ButtonSize.small,
            block: true,
            onPressed: _cheque,
          ),
        );
      }
      if (_canRevise(d)) {
        buttons.add(
          AccountsV2Button(
            label: '${_t('v2i_revise')} (R.$_nextRevision)',
            icon: 'edit',
            size: AccountsV2ButtonSize.small,
            block: true,
            onPressed: () => _revise(d),
          ),
        );
      }
    }
    if (_canPrint) {
      buttons.add(
        AccountsV2Button(
          label: _t('v2i_view_print'),
          icon: 'print',
          size: AccountsV2ButtonSize.small,
          block: true,
          onPressed: _print,
        ),
      );
    }
    if (buttons.isEmpty) return const SizedBox.shrink();
    final grid = AccountsV2Grid(columns: 2, gap: 8, children: buttons);
    final payBlocked = _payBlockedReason;
    if (payBlocked == null) return grid;
    // A greyed-out Record payment says why, instead of leaving people to guess.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        grid,
        const SizedBox(height: 6),
        Text(
          payBlocked,
          key: const ValueKey('accounts-v2-pay-blocked'),
          style: v2Style(12, color: AccountsV2Colors.mut),
        ),
      ],
    );
  }

  /// Why Record payment is shown but unavailable; null when it is available
  /// or not shown at all.
  String? get _payBlockedReason {
    if (inv.revisionInProgress ||
        widget.onPay == null ||
        !widget.capabilities.recordClientPayment ||
        _canPay) {
      return null;
    }
    if (v.paid) return _t('v2b_pay_blocked_paid');
    if (inv.status == YorksAccountsInvoiceStatus.cancelled) {
      return _t('v2b_pay_blocked_cancelled');
    }
    return _t('v2b_pay_blocked_cert');
  }

  List<({String title, String detail, int state})> _timeline(
    YorksAccountsInvoiceDetailProjection d,
  ) {
    final terms = d.invoice.paymentTermsDaysSnapshot;
    final latest = d.certifications.isEmpty
        ? null
        : d.certifications.reduce(
            (a, b) => a.revisionNumber >= b.revisionNumber ? a : b,
          );
    final certified = latest == null ? 0.0 : _d(latest.certifiedExVat);
    final less = v.gross - certified;
    // The date on the invoice itself; when it was recorded only as a fallback.
    final issuedOn =
        d.invoice.invoiceDate?.postgresText ?? d.invoice.createdAt.toLocal();
    return [
      (
        title: _t('v2i_tl_issued'),
        detail: [
          v2Date(issuedOn),
          if (inv.replacesReference != null)
            '${_t('v2i_replaces')} ${inv.replacesReference}',
        ].join(' · '),
        state: 2,
      ),
      (
        title: _t('v2i_tl_submitted'),
        detail:
            '${v2Date(inv.submissionDate?.postgresText)} · ${_t('v2i_due_word')} '
            '${v2Date(inv.dueDate?.postgresText)}'
            '${terms == null ? '' : ' ($terms ${_t('v2i_days')})'}',
        state: 2,
      ),
      (
        title: _t('v2i_tl_certified'),
        detail: latest == null
            ? _t('v2i_waiting_cert')
            : '${v2Date(latest.certificationDate.postgresText)} · '
                  '${v2Money(certified)}'
                  '${less.abs() > _eps ? ' (${v2Money(less)} ${_t('v2i_less_than_invoiced')})' : ''}',
        state: latest == null ? 1 : 2,
      ),
      (
        title: _t('v2i_tl_paid'),
        detail: v.paid
            ? '${v2Date(inv.lastReceiptDate?.postgresText)}'
                  '${v.delay > 0 ? ' · ${v.delay} ${_t('v2i_days_late')}' : ' · ${_t('v2i_on_time').toLowerCase()}'}'
            : v.received > _eps
            ? '${v2Money(v.received)} ${_t('v2i_kpi_received').toLowerCase()} · '
                  '${v2Money(v.balance)} ${_t('v2i_left')}'
            : v.inHand > _eps
            ? _t('v2i_cheque_not_cleared')
            : _t('v2i_nothing_received'),
        state: v.paid ? 2 : (latest != null ? 1 : 0),
      ),
    ];
  }

  String _method(String method) => switch (method) {
    'bank_transfer' => _t('v2i_type_bank'),
    'cash' => _t('v2i_type_cash'),
    'PDC' || 'cheque' => _t('v2i_type_cheque'),
    'reversal' => _t('v2i_type_reversal'),
    _ => method,
  };

  (String, AccountsV2ChipTone) _pdcChip(YorksAccountsPdcStatus s) =>
      switch (s) {
        YorksAccountsPdcStatus.expected => (
          _t('v2i_ps_expected'),
          AccountsV2ChipTone.neutral,
        ),
        YorksAccountsPdcStatus.received => (
          _t('v2i_ps_inhand'),
          AccountsV2ChipTone.vio,
        ),
        YorksAccountsPdcStatus.deposited => (
          _t('v2i_ps_deposited'),
          AccountsV2ChipTone.pri,
        ),
        YorksAccountsPdcStatus.cleared => (
          _t('v2i_ps_cleared'),
          AccountsV2ChipTone.ok,
        ),
        YorksAccountsPdcStatus.bounced => (
          _t('v2i_ps_bounced'),
          AccountsV2ChipTone.bad,
        ),
        YorksAccountsPdcStatus.returned => (
          _t('v2i_ps_returned'),
          AccountsV2ChipTone.bad,
        ),
        YorksAccountsPdcStatus.replaced => (
          _t('v2i_ps_replaced'),
          AccountsV2ChipTone.neutral,
        ),
        YorksAccountsPdcStatus.cancelled => (
          _t('v2i_ps_cancelled'),
          AccountsV2ChipTone.neutral,
        ),
      };

  Widget _payments(YorksAccountsInvoiceDetailProjection d) {
    final reversed = _reversedIds(d);
    Widget menuFor(YorksAccountsClientPayment p) {
      final open = !reversed.contains(p.paymentId);
      final canEdit =
          open && widget.onCorrectPayment != null && d.commands.correctPayment;
      final canReverse =
          open && widget.onReversePayment != null && d.commands.reversePayment;
      if (!canEdit && !canReverse) return const SizedBox.shrink();
      return _RowMenu(
        tooltip: _t('v2i_more'),
        items: [
          if (canEdit) (_t('v2i_edit'), 'edit', () => _editPayment(d, p)),
          if (canReverse) (_t('v2i_reverse'), 'undo', () => _reverse(d, p)),
        ],
      );
    }

    final rows = <AccountsV2Row>[];
    for (final c in d.pdcs) {
      final (label, tone) = _pdcChip(c.status);
      // A cleared cheque carries its payment; that payment is edited or
      // reversed from the cheque's row.
      final linked = d.payments.where(
        (p) =>
            p.pdcId == c.pdcId &&
            p.entryKind == YorksAccountsPaymentEntryKind.receipt,
      );
      rows.add(
        AccountsV2Row([
          Text(_t('v2i_type_cheque')),
          Text(c.chequeNumber),
          Text(v2Date(c.chequeDate.postgresText)),
          Text(v2Fmt(_d(c.amount))),
          AccountsV2Chip(label, tone: tone),
          linked.isEmpty ? const SizedBox.shrink() : menuFor(linked.first),
        ]),
      );
    }
    final chequeIds = {for (final c in d.pdcs) c.pdcId};
    for (final p in d.payments) {
      // A cleared cheque already shows as its cheque row.
      if (p.pdcId != null &&
          chequeIds.contains(p.pdcId) &&
          p.entryKind == YorksAccountsPaymentEntryKind.receipt) {
        continue;
      }
      final isReversal = p.entryKind == YorksAccountsPaymentEntryKind.reversal;
      final wasReversed = reversed.contains(p.paymentId);
      rows.add(
        AccountsV2Row([
          Text(isReversal ? _t('v2i_type_reversal') : _method(p.paymentMethod)),
          Text(p.paymentReference),
          Text(v2Date(p.paymentDate.postgresText)),
          Text(v2Fmt(_d(p.amount))),
          isReversal
              ? AccountsV2Chip(
                  _t('v2i_type_reversal'),
                  tone: AccountsV2ChipTone.warn,
                )
              : wasReversed
              ? AccountsV2Chip(
                  _t('v2i_reversed_chip'),
                  tone: AccountsV2ChipTone.neutral,
                )
              : AccountsV2Chip(
                  _t('v2i_received_chip'),
                  tone: AccountsV2ChipTone.ok,
                ),
          isReversal ? const SizedBox.shrink() : menuFor(p),
        ]),
      );
    }
    if (rows.isEmpty) {
      return Text(
        _t('v2i_no_payments'),
        style: v2Style(12, color: AccountsV2Colors.mut),
      );
    }
    return AccountsV2Table(
      boxed: true,
      minWidth: 520,
      columns: [
        AccountsV2Column(_t('v2i_t_type'), width: 112),
        AccountsV2Column(_t('v2i_t_ref')),
        AccountsV2Column(_t('v2i_t_date'), width: 104),
        AccountsV2Column(_t('v2i_p_amount'), width: 112, numeric: true),
        AccountsV2Column(_t('v2i_c_status'), width: 104, center: true),
        const AccountsV2Column('', width: 44, center: true),
      ],
      rows: rows,
    );
  }

  Widget _files() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (_canPrint)
          AccountsV2FilePill(
            label: '${_t('v2i_invoice_pdf')} · ${inv.invoiceReference}',
            icon: 'pdf',
            onTap: _print,
          ),
        for (final f in widget.files)
          AccountsV2FilePill(label: f.name, onTap: f.onOpen),
        if (widget.onAttach != null)
          AccountsV2FilePill(
            label: _t('v2i_attach'),
            icon: 'plus',
            accent: true,
            onTap: () {
              Navigator.of(context).pop();
              widget.onAttach!();
            },
          ),
      ],
    );
  }

  Widget _earlier() {
    final ref = inv.replacesReference!;
    final prior = widget.all.where((x) => x.inv.invoiceReference == ref);
    final p = prior.isEmpty ? null : prior.first;
    final text = [
      ref,
      if (p != null)
        '${_t('v2_issued')} ${v2Date(p.inv.submissionDate?.postgresText)}',
      if (p != null) '${v2Money(p.gross)} ${_t('v2i_c_excl').toLowerCase()}',
    ].join(' · ');
    return Text(
      '$text — ${_t('v2i_replaced')}',
      style: v2Style(12, color: AccountsV2Colors.mut),
    );
  }
}

/// A "⋯" button opening a short menu of actions for a row.
class _RowMenu extends StatelessWidget {
  const _RowMenu({required this.tooltip, required this.items});

  final String tooltip;
  final List<(String label, String icon, VoidCallback onTap)> items;

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final at = box.localToGlobal(Offset(0, box.size.height), ancestor: overlay);
    final index = await showMenu<int>(
      context: context,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final (i, (label, icon, _)) in items.indexed)
          PopupMenuItem<int>(
            value: i,
            child: Row(
              children: [
                AccountsV2Icon(icon, size: 16, color: AccountsV2Colors.ink2),
                const SizedBox(width: 8),
                Text(label, style: v2Style(13)),
              ],
            ),
          ),
      ],
    );
    if (index != null) items[index].$3();
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) => Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _open(context),
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

// ─── Command dialogs ─────────────────────────────────────────────────────────

class _CertifyDialog extends StatefulWidget {
  const _CertifyDialog({
    required this.projectId,
    required this.invoice,
    required this.language,
    this.onSubmit,
  });

  /// Runs the command while the dialog stays open; null closes with the input.
  final AccountsV2DialogCommand<YorksAccountsCertificationInput>? onSubmit;

  final String projectId;
  final YorksAccountsClientInvoiceSummary invoice;
  final AppLanguage language;

  @override
  State<_CertifyDialog> createState() => _CertifyDialogState();
}

class _CertifyDialogState extends State<_CertifyDialog>
    with AccountsV2SubmitDialog {
  @override
  AppLanguage get submitLanguage => widget.language;

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
    return submitDialog(
      title: Text(_t('v2_cert_title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          submitSummary(
            _t('v2b_sum_claimed')
                .replaceAll('{ref}', widget.invoice.invoiceReference)
                .replaceAll(
                  '{amount}',
                  v2Money(v2Number(widget.invoice.claimedExVat.canonicalText)),
                ),
          ),
          _DialogField(
            label: _t('v2_cert_amount'),
            controller: _amount,
            numeric: true,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          AccountsV2DateField(
            label: _t('v2_cert_date'),
            controller: _date,
            language: widget.language,
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
      actions: submitActions(
        confirmLabel: _t('v2_cert_title'),
        blockedReason: accountsV2FirstBlocker([
          accountsV2NeedAmount(
            widget.language,
            _amount,
            _t('v2_cert_amount'),
            allowZero: true,
          ),
          accountsV2NeedDate(widget.language, _date, _t('v2_cert_date')),
          accountsV2NeedText(
            widget.language,
            _reference,
            _t('v2_cert_reference'),
          ),
          (
            YorksAccountsDecimal.tryParse(
                  _amount.text.trim(),
                )?.compareTo(widget.invoice.claimedExVat) !=
                1,
            _t('v2b_cert_over'),
          ),
          (
            YorksAccountsDecimal.tryParse(_amount.text.trim()) ==
                    widget.invoice.claimedExVat ||
                _reason.text.trim().isNotEmpty,
            _t('v2b_cert_need_reason'),
          ),
        ]),
        onConfirm: valid ? () => submit(input, widget.onSubmit) : null,
      ),
    );
  }
}

class _PayDialog extends StatefulWidget {
  const _PayDialog({
    required this.projectId,
    required this.invoice,
    required this.language,
    this.onSubmit,
  });

  /// Runs the command while the dialog stays open; null closes with the input.
  final AccountsV2DialogCommand<YorksAccountsPaymentInput>? onSubmit;

  final String projectId;
  final YorksAccountsClientInvoiceSummary invoice;
  final AppLanguage language;

  @override
  State<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends State<_PayDialog> with AccountsV2SubmitDialog {
  @override
  AppLanguage get submitLanguage => widget.language;

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
    return submitDialog(
      title: Text(_t('v2_pay_title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          submitSummary(
            _t('v2b_sum_due')
                .replaceAll('{ref}', widget.invoice.invoiceReference)
                .replaceAll(
                  '{amount}',
                  v2Money(v2Number(widget.invoice.stillDue.canonicalText)),
                ),
          ),
          _DialogField(
            label: _t('v2_pay_amount'),
            controller: _amount,
            numeric: true,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          AccountsV2DateField(
            label: _t('v2_pay_date'),
            controller: _date,
            language: widget.language,
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
      actions: submitActions(
        confirmLabel: _t('v2_pay_title'),
        blockedReason: accountsV2FirstBlocker([
          accountsV2NeedAmount(widget.language, _amount, _t('v2_pay_amount')),
          accountsV2NeedDate(widget.language, _date, _t('v2_pay_date')),
          accountsV2NeedText(
            widget.language,
            _reference,
            _t('v2_pay_reference'),
          ),
        ]),
        onConfirm: valid ? () => submit(input, widget.onSubmit) : null,
      ),
    );
  }
}

class _DialogField extends StatelessWidget {
  const _DialogField({
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

// ─── Invoice detail drawer ───────────────────────────────────────────────────

class _ReversalDialog extends StatefulWidget {
  const _ReversalDialog({
    required this.projectId,
    required this.invoiceId,
    required this.expectedVersion,
    required this.payment,
    required this.language,
    this.onSubmit,
  });

  /// Runs the command while the dialog stays open; null closes with the input.
  final AccountsV2DialogCommand<YorksAccountsPaymentReversalInput>? onSubmit;

  final String projectId;
  final String invoiceId;
  final int expectedVersion;
  final YorksAccountsClientPayment payment;
  final AppLanguage language;

  @override
  State<_ReversalDialog> createState() => _ReversalDialogState();
}

class _ReversalDialogState extends State<_ReversalDialog>
    with AccountsV2SubmitDialog {
  @override
  AppLanguage get submitLanguage => widget.language;

  late final TextEditingController _date;
  final _reference = TextEditingController();
  final _reason = TextEditingController();
  YorksAccountsPdcStatus _chequeOutcome = YorksAccountsPdcStatus.deposited;

  String _t(String key) => accountsV2Text(widget.language, key);

  bool get _fromCheque => widget.payment.pdcId != null;

  @override
  void initState() {
    super.initState();
    _date = TextEditingController(text: accountsV2TodayIso());
  }

  @override
  void dispose() {
    _date.dispose();
    _reference.dispose();
    _reason.dispose();
    super.dispose();
  }

  YorksAccountsPaymentReversalInput? _build() {
    final date = YorksAccountsDate.tryParse(_date.text.trim());
    if (date == null) return null;
    return YorksAccountsPaymentReversalInput(
      projectId: widget.projectId,
      invoiceId: widget.invoiceId,
      expectedVersion: widget.expectedVersion,
      originalPaymentId: widget.payment.paymentId,
      reversalDate: date,
      reversalReference: _reference.text.trim(),
      reason: _reason.text.trim(),
      chequeOutcome: _fromCheque ? _chequeOutcome : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final input = _build();
    final valid = input != null && input.isValid;
    return submitDialog(
      title: Text(_t('v2_pay_reverse_title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          submitSummary(
            _t('v2b_sum_payment')
                .replaceAll(
                  '{amount}',
                  widget.payment.amount == null
                      ? '—'
                      : v2Money(v2Number(widget.payment.amount!.canonicalText)),
                )
                .replaceAll(
                  '{date}',
                  v2Date(widget.payment.paymentDate.postgresText),
                ),
          ),
          Text(
            widget.payment.paymentReference,
            style: AppTypography.bodyMedium.copyWith(color: AppColors.ink),
          ),
          const SizedBox(height: AppSpacing.sm),
          AccountsV2DateField(
            label: _t('v2_pay_reverse_date'),
            controller: _date,
            language: widget.language,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_fromCheque) ...[
            DropdownButtonFormField<YorksAccountsPdcStatus>(
              initialValue: _chequeOutcome,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _t('v2_pay_reverse_cheque'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: YorksAccountsPdcStatus.deposited,
                  child: Text(_t('v2_pay_reverse_cheque_deposited')),
                ),
                DropdownMenuItem(
                  value: YorksAccountsPdcStatus.bounced,
                  child: Text(_t('v2_pay_reverse_cheque_bounced')),
                ),
                DropdownMenuItem(
                  value: YorksAccountsPdcStatus.returned,
                  child: Text(_t('v2_pay_reverse_cheque_returned')),
                ),
              ],
              onChanged: (value) => setState(
                () =>
                    _chequeOutcome = value ?? YorksAccountsPdcStatus.deposited,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          _DialogField(
            label: _t('v2_pay_reverse_reason'),
            controller: _reason,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          _DialogField(
            label: _t('v2_pay_reverse_reference_opt'),
            controller: _reference,
            onChanged: () => setState(() {}),
          ),
        ],
      ),
      actions: submitActions(
        confirmLabel: _t('v2_pay_reverse_title'),
        blockedReason: accountsV2FirstBlocker([
          accountsV2NeedDate(widget.language, _date, _t('v2_pay_reverse_date')),
          accountsV2NeedText(
            widget.language,
            _reason,
            _t('v2_pay_reverse_reason'),
          ),
        ]),
        destructive: true,
        onConfirm: valid ? () => submit(input, widget.onSubmit) : null,
      ),
    );
  }
}

// ─── Edit dialogs ────────────────────────────────────────────────────────────

class _EditPaymentDialog extends StatefulWidget {
  const _EditPaymentDialog({
    required this.projectId,
    required this.invoiceId,
    required this.expectedVersion,
    required this.payment,
    required this.language,
    this.onSubmit,
  });

  /// Runs the command while the dialog stays open; null closes with the input.
  final AccountsV2DialogCommand<YorksAccountsPaymentCorrectionInput>? onSubmit;

  final String projectId;
  final String invoiceId;
  final int expectedVersion;
  final YorksAccountsClientPayment payment;
  final AppLanguage language;

  @override
  State<_EditPaymentDialog> createState() => _EditPaymentDialogState();
}

class _EditPaymentDialogState extends State<_EditPaymentDialog>
    with AccountsV2SubmitDialog {
  @override
  AppLanguage get submitLanguage => widget.language;

  late final TextEditingController _amount;
  late final TextEditingController _date;
  late final TextEditingController _reference;
  final _reason = TextEditingController();
  late String _method;

  String _t(String key) => accountsV2Text(widget.language, key);

  bool get _fromCheque => widget.payment.pdcId != null;

  @override
  void initState() {
    super.initState();
    final payment = widget.payment;
    _amount = TextEditingController(text: payment.amount?.canonicalText ?? '');
    _date = TextEditingController(text: payment.paymentDate.postgresText);
    _reference = TextEditingController(text: payment.paymentReference);
    _method = payment.paymentMethod;
  }

  @override
  void dispose() {
    _amount.dispose();
    _date.dispose();
    _reference.dispose();
    _reason.dispose();
    super.dispose();
  }

  YorksAccountsPaymentCorrectionInput? _build() {
    final amount = YorksAccountsDecimal.tryParse(_amount.text.trim());
    final date = YorksAccountsDate.tryParse(_date.text.trim());
    if (amount == null || date == null) return null;
    return YorksAccountsPaymentCorrectionInput(
      projectId: widget.projectId,
      invoiceId: widget.invoiceId,
      expectedVersion: widget.expectedVersion,
      originalPaymentId: widget.payment.paymentId,
      paymentDate: date,
      paymentMethod: _method,
      paymentReference: _reference.text.trim(),
      amount: amount,
      reason: _reason.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final input = _build();
    final valid = input != null && input.isValid;
    return submitDialog(
      title: Text(_t('v2_pay_edit_title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t(_fromCheque ? 'v2_pay_edit_cheque_hint' : 'v2_pay_edit_hint'),
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (!_fromCheque) ...[
              _DialogField(
                label: _t('v2_pay_amount'),
                controller: _amount,
                numeric: true,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            AccountsV2DateField(
              label: _t('v2_pay_date'),
              controller: _date,
              language: widget.language,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (!_fromCheque) ...[
              DropdownButtonFormField<String>(
                initialValue: _method,
                isExpanded: true,
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
                  // A method recorded some other way stays selectable.
                  if (_method != 'bank_transfer' && _method != 'cash')
                    DropdownMenuItem(value: _method, child: Text(_method)),
                ],
                onChanged: (value) =>
                    setState(() => _method = value ?? _method),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            _DialogField(
              label: _t('v2_pay_reference'),
              controller: _reference,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            _DialogField(
              label: _t('v2_pay_reverse_reason'),
              controller: _reason,
              onChanged: () => setState(() {}),
            ),
          ],
        ),
      ),
      actions: submitActions(
        confirmLabel: _t('v2c_save_changes'),
        blockedReason: accountsV2FirstBlocker([
          accountsV2NeedAmount(widget.language, _amount, _t('v2_pay_amount')),
          accountsV2NeedDate(widget.language, _date, _t('v2_pay_date')),
          accountsV2NeedText(
            widget.language,
            _reference,
            _t('v2_pay_reference'),
          ),
          accountsV2NeedText(
            widget.language,
            _reason,
            _t('v2_pay_reverse_reason'),
          ),
        ]),
        onConfirm: valid ? () => submit(input, widget.onSubmit) : null,
      ),
    );
  }
}

class _EditCertificationDialog extends StatefulWidget {
  const _EditCertificationDialog({
    required this.projectId,
    required this.invoiceId,
    required this.expectedVersion,
    required this.certification,
    required this.language,
    this.onSubmit,
  });

  /// Runs the command while the dialog stays open; null closes with the input.
  final AccountsV2DialogCommand<YorksAccountsCertificationCorrectionInput>?
  onSubmit;

  final String projectId;
  final String invoiceId;
  final int expectedVersion;
  final YorksAccountsClientCertification certification;
  final AppLanguage language;

  @override
  State<_EditCertificationDialog> createState() =>
      _EditCertificationDialogState();
}

class _EditCertificationDialogState extends State<_EditCertificationDialog>
    with AccountsV2SubmitDialog {
  @override
  AppLanguage get submitLanguage => widget.language;

  late final TextEditingController _amount;
  late final TextEditingController _date;
  late final TextEditingController _reference;
  final _reason = TextEditingController();

  String _t(String key) => accountsV2Text(widget.language, key);

  @override
  void initState() {
    super.initState();
    final certification = widget.certification;
    _amount = TextEditingController(
      text: certification.certifiedExVat?.canonicalText ?? '',
    );
    _date = TextEditingController(
      text: certification.certificationDate.postgresText,
    );
    _reference = TextEditingController(
      text: certification.certificationReference,
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _date.dispose();
    _reference.dispose();
    _reason.dispose();
    super.dispose();
  }

  YorksAccountsCertificationCorrectionInput? _build() {
    final amount = YorksAccountsDecimal.tryParse(_amount.text.trim());
    final date = YorksAccountsDate.tryParse(_date.text.trim());
    if (amount == null || date == null) return null;
    return YorksAccountsCertificationCorrectionInput(
      projectId: widget.projectId,
      invoiceId: widget.invoiceId,
      expectedVersion: widget.expectedVersion,
      certificationReference: _reference.text.trim(),
      certificationDate: date,
      certifiedExVat: amount,
      reason: _reason.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final input = _build();
    final valid = input != null && input.isValid;
    return submitDialog(
      title: Text(_t('v2_cert_edit_title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('v2_cert_edit_hint'),
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.sm),
            _DialogField(
              label: _t('v2_cert_amount'),
              controller: _amount,
              numeric: true,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            AccountsV2DateField(
              label: _t('v2_cert_date'),
              controller: _date,
              language: widget.language,
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
              label: _t('v2_pay_reverse_reason'),
              controller: _reason,
              onChanged: () => setState(() {}),
            ),
          ],
        ),
      ),
      actions: submitActions(
        confirmLabel: _t('v2c_save_changes'),
        blockedReason: accountsV2FirstBlocker([
          accountsV2NeedAmount(
            widget.language,
            _amount,
            _t('v2_cert_amount'),
            allowZero: true,
          ),
          accountsV2NeedDate(widget.language, _date, _t('v2_cert_date')),
          accountsV2NeedText(
            widget.language,
            _reference,
            _t('v2_cert_reference'),
          ),
          accountsV2NeedText(
            widget.language,
            _reason,
            _t('v2_pay_reverse_reason'),
          ),
        ]),
        onConfirm: valid ? () => submit(input, widget.onSubmit) : null,
      ),
    );
  }
}

class _CancelInvoiceDialog extends StatefulWidget {
  const _CancelInvoiceDialog({required this.language, this.onSubmit});

  /// Runs the command while the dialog stays open; null closes with the input.
  final AccountsV2DialogCommand<String>? onSubmit;

  final AppLanguage language;

  @override
  State<_CancelInvoiceDialog> createState() => _CancelInvoiceDialogState();
}

class _CancelInvoiceDialogState extends State<_CancelInvoiceDialog>
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
      title: Text(_t('v2_inv_cancel')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t('v2_inv_cancel_hint'),
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.sm),
          _DialogField(
            label: _t('v2_pay_reverse_reason'),
            controller: _reason,
            onChanged: () => setState(() {}),
          ),
        ],
      ),
      actions: submitActions(
        confirmLabel: _t('v2_inv_cancel'),
        blockedReason: accountsV2FirstBlocker([
          accountsV2NeedText(
            widget.language,
            _reason,
            _t('v2_pay_reverse_reason'),
          ),
        ]),
        destructive: true,
        cancelLabel: _t('v2b_keep_invoice'),
        onConfirm: reason.isEmpty
            ? null
            : () => submit(reason, widget.onSubmit),
      ),
    );
  }
}

// ─── Record cheque dialog ────────────────────────────────────────────────────

class _ChequeDialog extends StatefulWidget {
  const _ChequeDialog({
    required this.projectId,
    required this.invoice,
    required this.language,
    this.onSubmit,
  });

  /// Runs the command while the dialog stays open; null closes with the input.
  final AccountsV2DialogCommand<YorksAccountsPdcCreateInput>? onSubmit;

  final String projectId;
  final YorksAccountsClientInvoiceSummary invoice;
  final AppLanguage language;

  @override
  State<_ChequeDialog> createState() => _ChequeDialogState();
}

class _ChequeDialogState extends State<_ChequeDialog>
    with AccountsV2SubmitDialog {
  @override
  AppLanguage get submitLanguage => widget.language;

  final _number = TextEditingController();
  late final TextEditingController _date;
  late final TextEditingController _amount;
  final _bank = TextEditingController();

  String _t(String key) => accountsV2Text(widget.language, key);

  @override
  void initState() {
    super.initState();
    _date = TextEditingController(text: accountsV2TodayIso());
    final open = widget.invoice.stillDue - widget.invoice.pdcExposure;
    _amount = TextEditingController(
      text: open.isPositive ? open.canonicalText : '',
    );
  }

  @override
  void dispose() {
    for (final c in [_number, _date, _amount, _bank]) {
      c.dispose();
    }
    super.dispose();
  }

  YorksAccountsPdcCreateInput? _build() {
    final amount = YorksAccountsDecimal.tryParse(_amount.text.trim());
    final date = YorksAccountsDate.tryParse(_date.text.trim());
    if (amount == null || date == null) return null;
    final bank = _bank.text.trim();
    final input = YorksAccountsPdcCreateInput(
      projectId: widget.projectId,
      invoiceId: widget.invoice.invoiceId,
      expectedVersion: widget.invoice.recordVersion,
      chequeNumber: _number.text.trim(),
      chequeDate: date,
      amount: amount,
      bankName: bank.isEmpty ? null : bank,
    );
    return input.isValid ? input : null;
  }

  @override
  Widget build(BuildContext context) {
    final input = _build();
    return submitDialog(
      title: Text(_t('v2_pdc_add_title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.invoice.invoiceReference} · ${_t('v2_pdc_add_hint')}',
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.sm),
            _DialogField(
              label: _t('v2_pdc_add_number'),
              controller: _number,
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
            _DialogField(
              label: _t('v2_pdc_col_amount'),
              controller: _amount,
              numeric: true,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            _DialogField(
              label: _t('v2_pdc_col_bank'),
              controller: _bank,
              onChanged: () => setState(() {}),
            ),
          ],
        ),
      ),
      actions: submitActions(
        confirmLabel: _t('v2_pdc_add_title'),
        blockedReason: accountsV2FirstBlocker([
          accountsV2NeedText(widget.language, _number, _t('v2_pdc_add_number')),
          accountsV2NeedDate(
            widget.language,
            _date,
            _t('v2_pdc_col_cheque_date'),
          ),
          accountsV2NeedAmount(
            widget.language,
            _amount,
            _t('v2_pdc_col_amount'),
          ),
        ]),
        onConfirm: input == null ? null : () => submit(input, widget.onSubmit),
      ),
    );
  }
}

// ─── Revise (R.n) dialog ─────────────────────────────────────────────────────

/// Captures the required reason for revising an issued invoice (R.n).
class _ReviseDialog extends StatefulWidget {
  const _ReviseDialog({
    required this.language,
    this.onSubmit,
    this.titleKey = 'v2_inv_revise_title',
    this.hintKey = 'v2_inv_revise_hint',
    this.reasonKey = 'v2_inv_revise_reason',
    this.confirmKey = 'v2_inv_revise_title',
  });

  /// The copy, so the same reason dialog serves Revise and Restore.
  final String titleKey;
  final String hintKey;
  final String reasonKey;
  final String confirmKey;

  /// Runs the command while the dialog stays open; null closes with the input.
  final AccountsV2DialogCommand<String>? onSubmit;

  final AppLanguage language;

  @override
  State<_ReviseDialog> createState() => _ReviseDialogState();
}

class _ReviseDialogState extends State<_ReviseDialog>
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
    final valid = _reason.text.trim().isNotEmpty;
    return submitDialog(
      title: Text(_t(widget.titleKey)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(widget.hintKey),
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _reason,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: _t(widget.reasonKey),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: submitActions(
        confirmLabel: _t(widget.confirmKey),
        blockedReason: accountsV2FirstBlocker([
          accountsV2NeedText(widget.language, _reason, _t(widget.reasonKey)),
        ]),
        onConfirm: valid
            ? () => submit(_reason.text.trim(), widget.onSubmit)
            : null,
      ),
    );
  }
}

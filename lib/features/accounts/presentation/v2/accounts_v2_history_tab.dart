/// R39 Accounts Workspace V2 — History & Files tab, laid out as the approved
/// prototype: the append-only Activity list (record type and search filters)
/// beside the Evidence register of attached files.
///
/// Entries come from v1_get_accounts_activity. Their before/after data, used
/// for the detail line, is returned only with view_project_commercial_values.
library;

import 'package:flutter/material.dart';

import '../../../../shared/models/app_language.dart';
import '../../domain/accounts_records_models.dart';
import 'accounts_v2_common.dart';
import 'kit/accounts_v2_kit.dart';

/// The prototype's record types, read from an entry's entity and event.
enum _Kind {
  contract('v2h_contract', 'doc', AccountsV2Tone.blue),
  claim('v2h_claims', 'chart', AccountsV2Tone.vio),
  invoice('v2h_invoices', 'receipt', AccountsV2Tone.blue),
  payment('v2h_payments', 'wallet', AccountsV2Tone.green),
  bill('v2h_bills', 'archive', AccountsV2Tone.org),
  other('v2h_all', 'info', AccountsV2Tone.blue);

  const _Kind(this.labelKey, this.icon, this.tone);
  final String labelKey;
  final String icon;
  final AccountsV2Tone tone;

  static _Kind of(YorksAccountsActivityEntry e) {
    final t = '${e.entityType} ${e.eventType}'.toLowerCase();
    if (t.contains('supplier') || t.contains('bill')) return _Kind.bill;
    if (t.contains('pdc') || t.contains('payment')) return _Kind.payment;
    if (t.contains('certification') ||
        (t.contains('invoice') && !t.contains('settings'))) {
      return _Kind.invoice;
    }
    if (t.contains('claim') || t.contains('progress')) return _Kind.claim;
    if (t.contains('baseline') ||
        t.contains('commercial') ||
        t.contains('setup') ||
        t.contains('variation') ||
        t.contains('material_links') ||
        t.contains('settings') ||
        t.contains('import')) {
      return _Kind.contract;
    }
    return _Kind.other;
  }
}

/// Audit event types with a written title, for the timeline.
@visibleForTesting
const yorksAccountsV2HistoryEventKeys = <String, String>{
  'accounts_baseline_initialized': 'v2_ev_baseline',
  'accounts_baseline_revised': 'v2_ev_baseline_revised',
  'accounts_progress_confirmed': 'v2_ev_progress',
  'accounts.progress.imported': 'v2_ev_progress_imported',
  'accounts.source_import.applied': 'v2_ev_import',
  'accounts.material_links.saved': 'v2_ev_material_links',
  'accounts.client_claim.created': 'v2_ev_claim_created',
  'accounts.client_claim.updated': 'v2_ev_claim_updated',
  'accounts.client_claim.ready_for_accounts': 'v2_ev_claim_ready',
  'accounts.client_claim.reopened': 'v2_ev_claim_reopened',
  'accounts.client_claim.cancelled': 'v2_ev_claim_cancelled',
  'accounts.client_claim.deleted': 'v2_ev_claim_deleted',
  'accounts.client_invoice.draft_created': 'v2_ev_invoice_draft',
  'accounts.client_invoice.draft_updated': 'v2_ev_invoice_draft_updated',
  'accounts.client_invoice.submitted': 'v2_ev_invoice_issued',
  'accounts.client_invoice.under_certification': 'v2_ev_invoice_under_cert',
  'accounts.client_invoice.returned': 'v2_ev_invoice_returned',
  'accounts.client_invoice.cancelled': 'v2_ev_invoice_cancelled',
  'accounts.client_invoice.revision_started': 'v2_ev_invoice_revising',
  'accounts.client_invoice.superseded': 'v2_ev_invoice_superseded',
  'accounts.client_certification.recorded': 'v2_ev_certified',
  'accounts.client_payment.recorded': 'v2_ev_payment',
  'accounts.client_payment.reversed': 'v2_ev_payment_reversed',
  'accounts.client_payment.corrected': 'v2_ev_payment_corrected',
  'accounts.client_certification.corrected': 'v2_ev_certification_corrected',
  'accounts.client_pdc.edited': 'v2_ev_cheque_edited',
  'accounts.client_pdc.expected': 'v2_ev_cheque_expected',
  'accounts.supplier_payment.corrected': 'v2_ev_supplier_payment_corrected',
  'accounts.supplier_bill.reopened': 'v2_ev_supplier_reopened',
  'accounts.client_pdc.created': 'v2_ev_cheque_added',
  'accounts.client_pdc.received': 'v2_ev_cheque_received',
  'accounts.client_pdc.deposited': 'v2_ev_cheque_deposited',
  'accounts.client_pdc.cleared': 'v2_ev_cheque_cleared',
  'accounts.client_pdc.returned': 'v2_ev_cheque_returned',
  'accounts.client_pdc.bounced': 'v2_ev_cheque_bounced',
  'accounts.client_pdc.cancelled': 'v2_ev_cheque_cancelled',
  'accounts.client_pdc.replaced': 'v2_ev_cheque_replaced',
  'accounts.supplier_bill.created': 'v2_ev_bill_created',
  'accounts.supplier_bill.updated': 'v2_ev_bill_updated',
  'accounts.supplier_bill.approved': 'v2_ev_bill_approved',
  'accounts.supplier_bill.cancelled': 'v2_ev_bill_cancelled',
  'accounts.supplier_payment.recorded': 'v2_ev_bill_paid',
  'accounts.supplier_payment.reversed': 'v2_ev_bill_payment_reversed',
  'accounts.document.finalized': 'v2_ev_document',
  'accounts.export.generated': 'v2_ev_export',
};

/// A file shown in the Evidence register (name + optional reference/uploader).
typedef YorksAccountsHistoryFile = ({
  String name,
  String? reference,
  String? uploadedBy,
  VoidCallback? onDownload,
  String? id,
});

class AccountsV2HistoryTab extends StatefulWidget {
  const AccountsV2HistoryTab({
    super.key,
    required this.projection,
    required this.language,
    this.files = const [],
    this.onAddFile,
  });

  final YorksAccountsActivityProjection projection;
  final AppLanguage language;

  /// Files attached to the project's Accounts records, newest first.
  final List<YorksAccountsHistoryFile> files;

  /// Adds a file; null for someone who can't.
  final VoidCallback? onAddFile;

  @override
  State<AccountsV2HistoryTab> createState() => _AccountsV2HistoryTabState();
}

class _AccountsV2HistoryTabState extends State<AccountsV2HistoryTab> {
  String _kind = 'all';
  final _search = TextEditingController();

  String _t(String key) => accountsV2Text(widget.language, key);

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _title(YorksAccountsActivityEntry entry) {
    final known = yorksAccountsV2HistoryEventKeys[entry.eventType];
    if (known != null) return _t(known);
    // An event added later still reads as words, never as a raw key.
    final words = entry.eventType
        .replaceFirst(RegExp(r'^accounts[._]'), '')
        .replaceAll(RegExp(r'[._]'), ' ')
        .trim();
    return words.isEmpty
        ? entry.eventType
        : '${words[0].toUpperCase()}${words.substring(1)}';
  }

  /// The prototype's detail line, from what the event recorded.
  String _detail(YorksAccountsActivityEntry entry) {
    final a = entry.afterData ?? const <String, dynamic>{};
    String? text(String key) {
      final v = a[key];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    final parts = <String>[
      ?text('invoice_reference'),
      ?text('claim_reference'),
      ?text('supplier_invoice_reference'),
      ?text('supplier_name'),
      ?text('cheque_number'),
      ?text('payment_reference'),
    ];
    if (a['confirmed_percent'] != null) {
      parts.add(v2Pct(v2Number(a['confirmed_percent'])));
    } else if (a['suggested_percent'] != null) {
      parts.add(
        '${_t('v2h_suggested')} ${v2Pct(v2Number(a['suggested_percent']))}',
      );
    }
    final kind = _Kind.of(entry);
    // A payment event carries its record's running figures, not the payment
    // itself, so it shows an amount only when one was recorded on the event.
    final money = switch (kind) {
      _Kind.contract => a['contract_value'],
      _Kind.payment => a['amount'],
      _ when entry.eventType.contains('certification') => a['certified_ex_vat'],
      _ => a['amount'] ?? a['claimed_ex_vat'] ?? a['total_incl_vat'],
    };
    if (money != null && v2Number(money) != 0) {
      parts.add(
        entry.eventType.contains('certification')
            ? '${_t('v2h_certified')} ${v2Money(v2Number(money))}'
            : v2Money(v2Number(money)),
      );
    }
    final reason = entry.reason?.trim();
    if (reason != null && reason.isNotEmpty) parts.add(reason);
    return parts.join(' · ');
  }

  List<String> _evidenceIds(YorksAccountsActivityEntry entry) {
    final ids = entry.afterData?['evidence_document_ids'];
    return ids is List ? ids.whereType<String>().toList() : const [];
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final entries = widget.projection.entries
        .where((e) {
          if (_kind != 'all' && _Kind.of(e).name != _kind) return false;
          if (q.isEmpty) return true;
          return [
            _title(e),
            _detail(e),
            e.actorDisplayName,
          ].join(' ').toLowerCase().contains(q);
        })
        .toList(growable: false);
    return AccountsV2Split(
      main: _activity(context, entries),
      side: _register(),
    );
  }

  Widget _activity(
    BuildContext context,
    List<YorksAccountsActivityEntry> entries,
  ) {
    final narrow = AccountsV2Breakpoints.isNarrow(context);
    final filtering = _kind != 'all' || _search.text.trim().isNotEmpty;
    final filters = <Widget>[
      AccountsV2Select<String>(
        label: _t('v2h_record_type'),
        value: _kind,
        width: narrow ? null : 228,
        options: [
          ('all', _t('v2h_all')),
          for (final k in const [
            _Kind.contract,
            _Kind.claim,
            _Kind.invoice,
            _Kind.payment,
            _Kind.bill,
          ])
            (k.name, _t(k.labelKey)),
        ],
        onChanged: (v) => setState(() => _kind = v),
      ),
      AccountsV2TextField(
        label: _t('v2h_search'),
        controller: _search,
        hint: _t('v2h_search_hint'),
        search: true,
        width: narrow ? null : 300,
      ),
    ];
    final phone = AccountsV2Breakpoints.isPhone(context);
    return AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2TileHead(
            icon: 'history',
            title: _t('v2h_activity'),
            subtitle: _t('v2h_activity_sub'),
            actions: [AccountsV2Chip(_t('v2h_append_only'))],
          ),
          Padding(
            padding: phone
                ? const EdgeInsets.fromLTRB(14, 16, 14, 10)
                : const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: narrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      filters[0],
                      const SizedBox(height: 10),
                      filters[1],
                    ],
                  )
                : Row(
                    children: [
                      filters[0],
                      const SizedBox(width: 10),
                      filters[1],
                    ],
                  ),
          ),
          if (entries.isEmpty)
            AccountsV2Empty(
              icon: 'history',
              title: _t('v2h_no_records'),
              body: filtering ? _t('v2h_nothing_matches') : null,
            )
          else
            for (final (i, e) in entries.indexed)
              _HistRow(
                first: i == 0,
                kind: _Kind.of(e),
                title: _title(e),
                detail: _detail(e),
                by: '${_t('v2h_by')} ${e.actorDisplayName}',
                when: e.occurredAt.toLocal(),
                files: [
                  for (final id in _evidenceIds(e))
                    for (final f in widget.files)
                      if (f.id == id) f,
                ],
              ),
        ],
      ),
    );
  }

  Widget _register() {
    final files = widget.files;
    return AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2TileHead(
            icon: 'folder',
            title: _t('v2h_register'),
            subtitle: _t('v2h_register_sub'),
            actions: [
              AccountsV2Chip(
                '${files.length} ${files.length == 1 ? _t('v2h_file') : _t('v2h_files')}',
                tone: AccountsV2ChipTone.pri,
              ),
            ],
          ),
          AccountsV2CardBody(
            top: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (files.isEmpty)
                  AccountsV2Empty(
                    icon: 'folder',
                    title: _t('v2h_no_records'),
                    body: _t('v2h_register_empty'),
                  )
                else
                  for (final (i, f) in files.indexed)
                    _FileRow(
                      file: f,
                      last: i == files.length - 1,
                      downloadLabel: _t('v2_files_download'),
                    ),
                if (widget.onAddFile != null) ...[
                  const SizedBox(height: 10),
                  AccountsV2Button(
                    label: _t('v2h_add_file'),
                    icon: 'plus',
                    size: AccountsV2ButtonSize.small,
                    block: true,
                    onPressed: widget.onAddFile,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// One activity entry (`.hist`): tinted icon, title, detail, who, files and
/// when on the right (below on phones).
class _HistRow extends StatelessWidget {
  const _HistRow({
    required this.first,
    required this.kind,
    required this.title,
    required this.detail,
    required this.by,
    required this.when,
    required this.files,
  });

  final bool first;
  final _Kind kind;
  final String title;
  final String detail;
  final String by;
  final DateTime when;
  final List<YorksAccountsHistoryFile> files;

  @override
  Widget build(BuildContext context) {
    final phone = AccountsV2Breakpoints.isPhone(context);
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${two(when.day)} ${_monthNames[when.month - 1]} ${when.year}';
    final time = '${two(when.hour)}:${two(when.minute)}';
    final whenText = Text(
      phone ? '$date · $time' : '$date\n$time',
      textAlign: phone ? TextAlign.left : TextAlign.right,
      style: v2Style(11.5, color: AccountsV2Colors.mut),
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: v2Style(13, weight: FontWeight.w700)),
        if (detail.isNotEmpty)
          Text(detail, style: v2Style(12, color: AccountsV2Colors.ink2)),
        Text(by, style: v2Style(12, color: AccountsV2Colors.mut)),
        if (files.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final f in files)
                  AccountsV2FilePill(label: f.name, onTap: f.onDownload),
              ],
            ),
          ),
        if (phone) ...[const SizedBox(height: 4), whenText],
      ],
    );
    return Container(
      padding: phone
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12)
          : const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        border: first
            ? null
            : const Border(top: BorderSide(color: AccountsV2Colors.line2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2IconTile(
            icon: kind.icon,
            tone: kind.tone,
            size: 38,
            radius: 10,
            iconSize: 18,
          ),
          const SizedBox(width: 12),
          Expanded(child: body),
          if (!phone) ...[
            const SizedBox(width: 12),
            SizedBox(width: 92, child: whenText),
          ],
        ],
      ),
    );
  }
}

/// One file in the Evidence register (`.filerow`).
class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.last,
    required this.downloadLabel,
  });

  final YorksAccountsHistoryFile file;
  final bool last;
  final String downloadLabel;

  @override
  Widget build(BuildContext context) {
    final sheet = RegExp(r'\.xlsx?$', caseSensitive: false).hasMatch(file.name);
    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AccountsV2Colors.line2)),
      ),
      child: Row(
        children: [
          AccountsV2IconTile(
            icon: sheet ? 'sheet' : 'pdf',
            tone: sheet ? AccountsV2Tone.green : AccountsV2Tone.red,
            size: 34,
            radius: 9,
            iconSize: 17,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Tooltip(
              message: file.name,
              child: Text(
                file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: v2Style(12.5, weight: FontWeight.w600),
              ),
            ),
          ),
          if ((file.reference ?? '').isNotEmpty) ...[
            const SizedBox(width: 10),
            AccountsV2Chip(file.reference!, tone: AccountsV2ChipTone.pri),
          ],
        ],
      ),
    );
    if (file.onDownload == null) return row;
    return Tooltip(
      message: downloadLabel,
      child: InkWell(onTap: file.onDownload, child: row),
    );
  }
}

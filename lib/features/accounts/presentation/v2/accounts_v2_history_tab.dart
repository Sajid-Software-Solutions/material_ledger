/// R39 Accounts Workspace V2 — History & files tab.
///
/// Shows the accounts activity timeline from the existing
/// v1_get_accounts_activity projection, with filter segments (All / Contract /
/// Claims / Invoices / Payments / Supplier bills) applied to the loaded
/// entries, beside the files attached to invoices and supplier bills.
library;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/models/app_language.dart';
import '../../domain/accounts_records_models.dart';
import 'accounts_v2_common.dart';

enum _HistFilter {
  all('v2_hist_all'),
  contract('v2_hist_contract'),
  claims('v2_hist_claims'),
  invoices('v2_hist_invoices'),
  payments('v2_hist_payments'),
  supplier('v2_hist_supplier');

  const _HistFilter(this.labelKey);
  final String labelKey;

  bool matches(String entityType) {
    final e = entityType.toLowerCase();
    switch (this) {
      case _HistFilter.all:
        return true;
      case _HistFilter.contract:
        return e.contains('baseline') ||
            e.contains('commercial') ||
            e.contains('setup') ||
            e.contains('invoice_settings');
      case _HistFilter.claims:
        return e.contains('claim');
      case _HistFilter.invoices:
        return e.contains('invoice') && !e.contains('settings');
      case _HistFilter.payments:
        return e.contains('payment') ||
            e.contains('pdc') ||
            e.contains('certification');
      case _HistFilter.supplier:
        return e.contains('supplier') || e.contains('bill');
    }
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

/// A file shown in the History Files panel (name + optional reference/uploader).
typedef YorksAccountsHistoryFile = ({
  String name,
  String? reference,
  String? uploadedBy,
  VoidCallback? onDownload,
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

  /// Files attached to invoices and supplier bills, newest first.
  final List<YorksAccountsHistoryFile> files;

  /// Adds a file; null for someone who can't.
  final VoidCallback? onAddFile;

  @override
  State<AccountsV2HistoryTab> createState() => _AccountsV2HistoryTabState();
}

class _AccountsV2HistoryTabState extends State<AccountsV2HistoryTab> {
  _HistFilter _filter = _HistFilter.all;

  String _t(String key) => accountsV2Text(widget.language, key);

  @override
  Widget build(BuildContext context) {
    final entries = widget.projection.entries
        .where((e) => _filter.matches(e.entityType))
        .toList(growable: false);

    final timeline = AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(_t('v2_hist_title')),
          const SizedBox(height: AppSpacing.sm),
          _FilterBar(
            selected: _filter,
            language: widget.language,
            onSelected: (f) => setState(() => _filter = f),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(_t('v2_hist_empty'), style: AppTypography.bodyMedium),
            )
          else
            for (final entry in entries)
              _TimelineRow(entry: entry, language: widget.language),
        ],
      ),
    );

    final fileItems = widget.files;
    final files = AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: AccountsV2SectionTitle(_t('v2_files_title'))),
              if (widget.onAddFile != null)
                TextButton.icon(
                  onPressed: widget.onAddFile,
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: Text(_t('v2_files_add')),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (fileItems.isEmpty)
            Text(_t('v2_files_empty'), style: AppTypography.bodyMedium)
          else
            for (final file in fileItems)
              _FileRow(file: file, language: widget.language),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= AppSpacing.stackedBreakpoint;
        if (!wide) {
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              timeline,
              const SizedBox(height: AppSpacing.lg),
              files,
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: timeline),
                const SizedBox(width: AppSpacing.lg),
                SizedBox(width: AppSpacing.inspectorWidth, child: files),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.language,
    required this.onSelected,
  });

  final _HistFilter selected;
  final AppLanguage language;
  final ValueChanged<_HistFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final f in _HistFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: _Segment(
                label: accountsV2Text(language, f.labelKey),
                selected: f == selected,
                onTap: () => onSelected(f),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.onPrimary : AppColors.inkSecondary;
    return Material(
      color: selected ? AppColors.primary : AppColors.surfaceContainer,
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Text(
            label,
            style: AppTypography.labelLarge.copyWith(color: fg),
          ),
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.entry, required this.language});

  final YorksAccountsActivityEntry entry;
  final AppLanguage language;

  /// Icon and accent per entry type — colour-codes the timeline by kind, the
  /// way the prototype does, reusing the workspace's colour language.
  ({IconData icon, Color accent}) get _style {
    final e = entry.entityType.toLowerCase();
    if (e.contains('claim')) {
      return (icon: Icons.timeline_outlined, accent: AppColors.primary);
    }
    if (e.contains('invoice') && !e.contains('settings')) {
      return (icon: Icons.receipt_long_outlined, accent: AppColors.primary);
    }
    if (e.contains('payment') ||
        e.contains('pdc') ||
        e.contains('certification')) {
      return (icon: Icons.payments_outlined, accent: AppColors.success);
    }
    if (e.contains('supplier') || e.contains('bill')) {
      return (icon: Icons.local_shipping_outlined, accent: AppColors.purple);
    }
    if (e.contains('baseline') ||
        e.contains('commercial') ||
        e.contains('setup')) {
      return (icon: Icons.description_outlined, accent: AppColors.inkSecondary);
    }
    return (icon: Icons.history_outlined, accent: AppColors.muted);
  }

  String get _title {
    final known = yorksAccountsV2HistoryEventKeys[entry.eventType];
    if (known != null) return accountsV2Text(language, known);
    // An event added later still reads as words, never as a raw key.
    final words = entry.eventType
        .replaceFirst(RegExp(r'^accounts[._]'), '')
        .replaceAll(RegExp(r'[._]'), ' ')
        .trim();
    return words.isEmpty
        ? entry.eventType
        : '${words[0].toUpperCase()}${words.substring(1)}';
  }

  String _two(int v) => v.toString().padLeft(2, '0');
  String get _when {
    final d = entry.occurredAt.toLocal();
    return '${d.year}-${_two(d.month)}-${_two(d.day)} '
        '${_two(d.hour)}:${_two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: style.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(style.icon, size: 16, color: style.accent),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.ink,
                  ),
                ),
                if (entry.reason != null && entry.reason!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxs),
                    child: Text(entry.reason!, style: AppTypography.bodySmall),
                  ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '$_when · ${accountsV2Text(language, 'v2_hist_by')} '
                  '${entry.actorDisplayName}',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One attached file in the Files panel: name + reference/uploader.
class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.language});

  final YorksAccountsHistoryFile file;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (file.reference != null && file.reference!.isNotEmpty) file.reference!,
      if (file.uploadedBy != null && file.uploadedBy!.isNotEmpty)
        '${accountsV2Text(language, 'v2_hist_by')} ${file.uploadedBy}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(
              color: AppColors.blueContainer,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.insert_drive_file_outlined,
              size: 16,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.ink,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    meta,
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.muted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (file.onDownload != null)
            IconButton(
              tooltip: accountsV2Text(language, 'v2_files_download'),
              onPressed: file.onDownload,
              icon: const Icon(Icons.download_outlined, size: 18),
            ),
        ],
      ),
    );
  }
}

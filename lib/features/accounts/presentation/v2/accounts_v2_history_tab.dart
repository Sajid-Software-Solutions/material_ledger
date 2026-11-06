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

/// A file shown in the History Files panel (name + optional reference/uploader).
typedef YorksAccountsHistoryFile = ({
  String name,
  String? reference,
  String? uploadedBy,
});

class AccountsV2HistoryTab extends StatefulWidget {
  const AccountsV2HistoryTab({
    super.key,
    required this.projection,
    required this.language,
    this.files = const [],
  });

  final YorksAccountsActivityProjection projection;
  final AppLanguage language;

  /// Files attached to invoices and supplier bills, newest first.
  final List<YorksAccountsHistoryFile> files;

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
          AccountsV2SectionTitle(_t('v2_files_title')),
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

  String get _title => entry.eventType.replaceAll('_', ' ');

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
        ],
      ),
    );
  }
}

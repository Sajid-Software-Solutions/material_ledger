/// R39 Accounts Workspace V2 — shared presentation helpers (P6).
///
/// The six-tab identity, display-only money/percent formatting and the common
/// card container. Formatting here is for display text only; every stored or
/// transmitted value stays an exact [YorksAccountsDecimal] string. Percentages
/// derived from two decimals are labelled "display only" because they go
/// through a double — they are never saved or sent to the server.
library;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_accounts_strings.dart';
import '../../domain/accounts_decimal.dart';

/// Localized copy for the V2 workspace (echoes the key when missing).
String accountsV2Text(AppLanguage language, String key) =>
    YorksV1AccountsStrings.text(language, key);

/// A clear, localized message for a failed command, from the code the V2
/// controllers return. Unknown codes fall back to the generic message.
String accountsV2ErrorText(AppLanguage language, String? code) {
  final c = code ?? '';
  bool any(List<String> parts) => parts.any(c.contains);
  final key = switch (c) {
    _ when any(['VERSION_CONFLICT', 'STALE_VERSION', 'conflict']) =>
      'v2_err_conflict',
    _ when any(['ACCESS_DENIED', 'unauthorized', 'unauthenticated']) =>
      'v2_err_denied',
    _ when any(['PAYMENT_CAP', 'PDC_EXPOSURE_CAP', 'NOT_PAYABLE']) =>
      'v2_err_over_due',
    _ when c.contains('CLAIM_CAP') => 'v2_err_over_claim',
    _ when c.contains('DUPLICATE') => 'v2_err_duplicate',
    _ when any(['INVOICE_SETTINGS_REQUIRED', 'INVOICE_PREFIX_REQUIRED']) =>
      'v2_err_settings_required',
    _ when c.contains('INVOICE_NOT_REVISABLE') => 'v2_err_not_revisable',
    _ when c.contains('REVISION_ALREADY_OPEN') => 'v2_err_revision_open',
    _ when c.contains('EVIDENCE') => 'v2_err_evidence',
    _ when c.contains('INVALID_STAGE_ITEMS') => 'v2_err_stage_items',
    _ when any(['INVALID_BUILDING_ALLOCATIONS', 'INVALID_STAGE_ALLOCATIONS']) =>
      'v2_err_allocations',
    _ when any(['SUPPLIER_INVOICE_DOCUMENT', 'SUPPLIER_DOCUMENT']) =>
      'v2_err_supplier_document',
    _ when c.contains('NOT_MATCHED') => 'v2_err_not_matched',
    _ when c.contains('BELOW_CLAIMED') => 'v2_err_below_claimed',
    _
        when any([
          'NOT_REOPENABLE',
          'NOT_INVOICEABLE',
          'NOT_EDITABLE',
          'NOT_APPROVABLE',
          'NOT_CANCELLABLE',
          'INVALID_INVOICE_TRANSITION',
          'INVALID_PDC_TRANSITION',
          'invalidTransition',
          'immutableRecord',
        ]) =>
      'v2_err_state',
    _ when any(['backendUnavailable', 'network', 'timeout', 'offline']) =>
      'v2_err_offline',
    _ when any(['INVALID_', 'REQUIRED', 'invalidInput']) => 'v2_err_invalid',
    _ => 'v2_action_failed',
  };
  return accountsV2Text(language, key);
}

/// Today as a `YYYY-MM-DD` string, the format the accounts date inputs use.
String accountsV2TodayIso() {
  final d = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// The six job-shaped tabs, in prototype order.
enum YorksAccountsWorkspaceV2Tab {
  summary('v2_tab_summary', Icons.dashboard_outlined),
  contract('v2_tab_contract', Icons.description_outlined),
  claims('v2_tab_claims', Icons.trending_up_outlined),
  invoices('v2_tab_invoices', Icons.receipt_long_outlined),
  supplierBills('v2_tab_supplier_bills', Icons.local_shipping_outlined),
  history('v2_tab_history', Icons.history_outlined);

  const YorksAccountsWorkspaceV2Tab(this.labelKey, this.icon);

  final String labelKey;
  final IconData icon;
}

/// The tab a project Accounts URL opens, including the old V1 paths that
/// notifications still link to.
YorksAccountsWorkspaceV2Tab yorksAccountsV2TabForPath(
  String path,
) => switch (path.split('/').last) {
  'contract' => YorksAccountsWorkspaceV2Tab.contract,
  'claims' || 'billing' => YorksAccountsWorkspaceV2Tab.claims,
  'client-invoices' || 'receipts-pdc' => YorksAccountsWorkspaceV2Tab.invoices,
  'supplier-bills' => YorksAccountsWorkspaceV2Tab.supplierBills,
  'history' || 'documents' || 'activity' => YorksAccountsWorkspaceV2Tab.history,
  _ => YorksAccountsWorkspaceV2Tab.summary,
};

/// Display-only money and percent formatting for the workspace.
///
/// Grouping mirrors the existing V1 Accounts overview formatter so the two
/// surfaces read identically during rollout.
final class AccountsV2Format {
  const AccountsV2Format({this.currencyCode = 'AED'});

  final String currencyCode;

  /// Grouped money text, e.g. `AED 1,000,000.00`. `—` for a null value.
  String money(YorksAccountsDecimal? value, {bool withCurrency = true}) {
    if (value == null) return '—';
    // Rounded for display only: the server sends some values unrounded.
    final raw = value.displayText(maximumFractionDigits: 2);
    final negative = raw.startsWith('-');
    final parts = (negative ? raw.substring(1) : raw).split('.');
    final whole = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final fraction = parts.length == 1 ? '00' : parts[1].padRight(2, '0');
    final sign = negative ? '-' : '';
    final body = '$sign$whole.$fraction';
    return withCurrency ? '$currencyCode $body' : body;
  }

  /// Ratio a / b in [0, 1] for a display bar. Display only (goes through a
  /// double); never a stored value.
  double ratio(YorksAccountsDecimal? a, YorksAccountsDecimal? b) {
    final numerator = double.tryParse(a?.canonicalText ?? '') ?? 0;
    final denominator = double.tryParse(b?.canonicalText ?? '') ?? 0;
    if (denominator <= 0) return 0;
    return (numerator / denominator).clamp(0, 1).toDouble();
  }

  /// A percent string for a ratio already in [0, 1]. Display only.
  String percentOfRatio(double ratio, {int fractionDigits = 1}) =>
      '${(ratio * 100).toStringAsFixed(fractionDigits)}%';

  /// A percent string straight from a server-provided percent decimal.
  String percent(YorksAccountsDecimal? value, {int maximumFractionDigits = 1}) {
    if (value == null) return '—';
    return '${value.displayText(maximumFractionDigits: maximumFractionDigits)}%';
  }
}

/// A date input: type `YYYY-MM-DD` or pick from a calendar. The text stays the
/// value the accounts commands parse, so both routes behave the same.
class AccountsV2DateField extends StatelessWidget {
  const AccountsV2DateField({
    super.key,
    required this.label,
    required this.controller,
    required this.language,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final AppLanguage language;
  final VoidCallback? onChanged;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(controller.text.trim()) ?? now,
      firstDate: DateTime(2015),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null) return;
    String two(int v) => v.toString().padLeft(2, '0');
    controller.text = '${picked.year}-${two(picked.month)}-${two(picked.day)}';
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.datetime,
      onChanged: onChanged == null ? null : (_) => onChanged!(),
      decoration: InputDecoration(
        labelText: label,
        hintText: 'YYYY-MM-DD',
        isDense: true,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: accountsV2Text(language, 'v2_pick_date'),
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          onPressed: () => _pick(context),
        ),
      ),
    );
  }
}

/// KPI tiles in even rows. Tiles in a short last row share its full width, so a
/// row never ends in an orphan with a gap beside it.
class AccountsV2KpiGrid extends StatelessWidget {
  const AccountsV2KpiGrid({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    const spacing = AppSpacing.md;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = (constraints.maxWidth / 200).floor().clamp(1, 5);
        // Avoid a lone tile on the last row: 5 at a 4-across width becomes 3 + 2.
        final perRow = (tiles.length % fit == 1 && fit > 1) ? fit - 1 : fit;
        final rows = <List<Widget>>[
          for (var i = 0; i < tiles.length; i += perRow)
            tiles.sublist(i, (i + perRow).clamp(0, tiles.length)),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (r, row) in rows.indexed) ...[
              if (r > 0) const SizedBox(height: spacing),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, tile) in row.indexed) ...[
                      if (i > 0) const SizedBox(width: spacing),
                      Expanded(child: tile),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Soft white card used across the workspace (prototype radius 14).
/// One table row as a card, for phone widths, where a desktop table would have to
/// be scrolled sideways to reach its status and actions.
class AccountsV2RecordCard extends StatelessWidget {
  const AccountsV2RecordCard({
    super.key,
    required this.title,
    this.status,
    this.facts = const [],
    this.actions = const [],
  });

  final Widget title;
  final Widget? status;
  final List<(String label, Widget value)> facts;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: title),
              if (status != null) ...[
                const SizedBox(width: AppSpacing.sm),
                status!,
              ],
            ],
          ),
          if (facts.isNotEmpty) const SizedBox(height: AppSpacing.sm),
          for (final (label, value) in facts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                children: [
                  Text(
                    label,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: value,
                    ),
                  ),
                ],
              ),
            ),
          if (actions.isNotEmpty)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actions,
              ),
            ),
        ],
      ),
    );
  }
}

class AccountsV2Card extends StatelessWidget {
  const AccountsV2Card({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.line),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Small section heading used at the top of workspace cards. An optional
/// [number] draws the prototype's numbered-step badge; an optional [subtitle]
/// adds a muted line beneath the title.
class AccountsV2SectionTitle extends StatelessWidget {
  const AccountsV2SectionTitle(
    this.title, {
    super.key,
    this.trailing,
    this.number,
    this.subtitle,
  });

  final String title;
  final Widget? trailing;
  final int? number;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final titleRow = Row(
      children: [
        if (number != null) ...[
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: AppColors.blueContainer,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$number',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(
          child: Text(
            title,
            style: AppTypography.titleSmall.copyWith(color: AppColors.ink),
          ),
        ),
        ?trailing,
      ],
    );
    if (subtitle == null) return titleRow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        titleRow,
        Padding(
          padding: EdgeInsets.only(
            left: number != null ? 24 + AppSpacing.sm : 0,
            top: AppSpacing.xxs,
          ),
          child: Text(
            subtitle!,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
        ),
      ],
    );
  }
}

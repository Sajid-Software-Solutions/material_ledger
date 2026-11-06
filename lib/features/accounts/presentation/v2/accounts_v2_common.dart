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
    final raw = value.canonicalText;
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

/// Soft white card used across the workspace (prototype radius 14).
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

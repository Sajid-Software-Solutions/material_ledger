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

/// Small section heading used at the top of workspace cards.
class AccountsV2SectionTitle extends StatelessWidget {
  const AccountsV2SectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: AppTypography.titleSmall.copyWith(color: AppColors.ink),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

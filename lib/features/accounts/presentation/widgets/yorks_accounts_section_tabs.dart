import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/yorks_mobile_ui.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_permission_management.dart';
import '../../../../shared/models/yorks_v1_shell_strings.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/yorks_v1_permission_provider.dart';

/// One company-wide Accounts page, shown as a tab inside Accounts.
class YorksAccountsSection {
  const YorksAccountsSection(this.path, this.label, this.icon);

  final String path;
  final TranslatableString label;
  final IconData icon;
}

/// Every company-wide Accounts page, in reading order. The sidebar shows a
/// single Accounts entry (a short list for the Accountant); these tabs are
/// how people move between the pages inside it.
const yorksAccountsSections = <YorksAccountsSection>[
  YorksAccountsSection(
    RoutePaths.yorksV1Accounts,
    YorksV1ShellStrings.accountsOverviewTab,
    Icons.dashboard_outlined,
  ),
  YorksAccountsSection(
    RoutePaths.yorksV1AccountsProjects,
    YorksV1ShellStrings.accountsProjectsTab,
    Icons.folder_outlined,
  ),
  YorksAccountsSection(
    RoutePaths.yorksV1AccountsBillingProgress,
    YorksV1ShellStrings.billingProgress,
    Icons.stacked_bar_chart_outlined,
  ),
  YorksAccountsSection(
    RoutePaths.yorksV1AccountsClaims,
    YorksV1ShellStrings.accountsClaims,
    Icons.request_page_outlined,
  ),
  YorksAccountsSection(
    RoutePaths.yorksV1AccountsClientPayments,
    YorksV1ShellStrings.receiptsPdc,
    Icons.account_balance_wallet_outlined,
  ),
  YorksAccountsSection(
    RoutePaths.yorksV1AccountsSupplierBills,
    YorksV1ShellStrings.supplierBills,
    Icons.receipt_long_outlined,
  ),
  YorksAccountsSection(
    RoutePaths.yorksV1AccountsDueSchedule,
    YorksV1ShellStrings.dueSchedule,
    Icons.calendar_month_outlined,
  ),
  YorksAccountsSection(
    RoutePaths.yorksV1AccountsDocuments,
    YorksV1ShellStrings.accountsDocuments,
    Icons.folder_copy_outlined,
  ),
  YorksAccountsSection(
    RoutePaths.yorksV1AccountsReports,
    YorksV1ShellStrings.accountsReports,
    Icons.analytics_outlined,
  ),
  YorksAccountsSection(
    RoutePaths.yorksV1AccountsActivity,
    YorksV1ShellStrings.accountsAuditTrail,
    Icons.history_rounded,
  ),
];

/// A company-wide Accounts page with the Accounts tab row fixed above it.
///
/// Navigation only: each page keeps its own route, guard and server checks.
/// Supplier bills appears only with the supplier-cost capability, matching
/// the route guard.
class YorksAccountsSectionFrame extends ConsumerWidget {
  const YorksAccountsSectionFrame({
    super.key,
    required this.currentPath,
    required this.child,
  });

  final String currentPath;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final permissions = ref.watch(yorksV1CurrentPermissionSnapshotProvider);
    final canSeeSupplierCosts = permissions.hybridAllows(
      YorksV1CapabilityKeys.viewSupplierCosts,
      legacyAllowed: false,
      organizationSummary: true,
    );
    final sections = [
      for (final section in yorksAccountsSections)
        if (section.path != RoutePaths.yorksV1AccountsSupplierBills ||
            canSeeSupplierCosts)
          section,
    ];
    final compact = YorksMobileUi.isActive(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTabs(
          sections: sections,
          currentPath: currentPath,
          compact: compact,
          label: YorksV1ShellStrings.accountsSections.active(language),
          labelFor: (section) => section.label.active(language),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _SectionTabs extends StatefulWidget {
  const _SectionTabs({
    required this.sections,
    required this.currentPath,
    required this.compact,
    required this.label,
    required this.labelFor,
  });

  final List<YorksAccountsSection> sections;
  final String currentPath;
  final bool compact;
  final String label;
  final String Function(YorksAccountsSection section) labelFor;

  @override
  State<_SectionTabs> createState() => _SectionTabsState();
}

class _SectionTabsState extends State<_SectionTabs> {
  final _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Keep the open page's tab in view on a narrow screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _selectedKey.currentContext;
      if (context != null && mounted) {
        Scrollable.ensureVisible(context, alignment: 0.5);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.compact
        ? AppSpacing.mobileScreenHorizontal
        : AppSpacing.xxl;
    return Semantics(
      container: true,
      label: widget.label,
      child: Material(
        key: const ValueKey('accounts-section-tabs'),
        color: AppColors.surfaceContainerLowest,
        shape: const Border(bottom: BorderSide(color: AppColors.line)),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: horizontal - 6),
          child: Row(
            children: [
              for (final section in widget.sections)
                _SectionTab(
                  key: section.path == widget.currentPath
                      ? _selectedKey
                      : ValueKey('accounts-tab-${section.path}'),
                  label: widget.labelFor(section),
                  icon: section.icon,
                  selected: section.path == widget.currentPath,
                  compact: widget.compact,
                  onTap: section.path == widget.currentPath
                      ? null
                      : () => context.go(section.path),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTab extends StatelessWidget {
  const _SectionTab({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.blue : AppColors.inkSecondary;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? AppColors.blue : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!compact) ...[
                Icon(icon, size: 17, color: color),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: AppTypography.labelLarge.copyWith(
                  color: color,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

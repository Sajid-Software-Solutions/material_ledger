import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_audit_workspace.dart';
import '../../../../shared/models/yorks_v1_configuration.dart';
import '../../../../shared/models/yorks_v1_logistics.dart';
import '../../../../shared/models/yorks_v1_material_request.dart';
import '../../../../shared/models/yorks_v1_material_request_strings.dart';
import '../../../../shared/models/yorks_v1_overview_strings.dart';
import '../../../../shared/models/yorks_v1_project.dart';
import '../../../../shared/models/yorks_v1_project_portfolio.dart';
import '../../../../shared/models/yorks_v1_project_strings.dart';
import '../../../../shared/models/yorks_v1_rental.dart';
import '../../../../shared/models/yorks_v1_role.dart';
import '../../../../shared/models/yorks_v1_shell_strings.dart';
import '../../../../shared/models/yorks_v1_team_chat_strings.dart';
import '../../../../shared/models/yorks_v1_feature_flags.dart';
import '../../../../shared/providers/yorks_v1_audit_provider.dart';
import '../../../../shared/providers/yorks_v1_material_request_provider.dart';
import '../../../company_overview/domain/company_analytics_models.dart';
import '../../../company_overview/presentation/company_analytics_screen.dart';

/// Read-only executive command surface for Admin and global engineering roles.
///
/// Every figure comes from an already-authorized projection. Cards only
/// deep-link to the corresponding workspace; no workflow mutation lives here.
class YorksV1ExecutiveOverview extends StatelessWidget {
  const YorksV1ExecutiveOverview({
    super.key,
    required this.language,
    required this.role,
    required this.displayName,
    required this.projects,
    required this.requests,
    required this.inventory,
    required this.configuration,
    required this.rentals,
    required this.audit,
    required this.activeUsers,
    required this.canBrowseInventory,
    required this.canAccessRentals,
    this.canOpenAnalytics = false,
    this.companyAnalytics = const AsyncData(null),
    this.featureFlags = const YorksV1FeatureFlags(),
    required this.onRefresh,
    this.projectOverview,
    this.requestOverview,
  });

  final AppLanguage language;
  final YorksV1Role role;
  final String? displayName;
  final AsyncValue<List<YorksV1ProjectPortfolioItem>> projects;
  final YorksV1ProjectOverview? projectOverview;
  final AsyncValue<List<YorksV1MaterialRequest>> requests;
  final YorksV1MaterialRequestOverview? requestOverview;
  final AsyncValue<YorksV1InventoryWorkspace?> inventory;
  final AsyncValue<YorksV1ConfigurationCentre?> configuration;
  final AsyncValue<YorksV1RentalPortfolio?> rentals;
  final YorksV1AuditViewState? audit;
  final int? activeUsers;
  final bool canBrowseInventory;
  final bool canAccessRentals;
  final bool canOpenAnalytics;
  final AsyncValue<CompanyAnalyticsProjection?> companyAnalytics;
  final YorksV1FeatureFlags featureFlags;
  final Future<void> Function() onRefresh;

  bool get _admin => role == YorksV1Role.admin;

  @override
  Widget build(BuildContext context) {
    final projectItems =
        projects.valueOrNull ?? const <YorksV1ProjectPortfolioItem>[];
    final requestItems =
        requests.valueOrNull ?? const <YorksV1MaterialRequest>[];
    final companyProjection =
        companyAnalytics.hasError || companyAnalytics.isLoading
        ? null
        : companyAnalytics.valueOrNull;
    final stats = _ExecutiveStats(
      projectItems,
      requestItems,
      role,
      projectOverview,
      requestOverview,
    );
    final partial =
        projects.hasError ||
        requests.hasError ||
        inventory.hasError ||
        (_admin &&
            (configuration.hasError ||
                rentals.hasError ||
                audit?.error != null)) ||
        (canOpenAnalytics && companyAnalytics.hasError);

    return ColoredBox(
      color: AppColors.surface,
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            MediaQuery.sizeOf(context).width < 720 ? 14 : 24,
            MediaQuery.sizeOf(context).width < 720 ? 16 : 22,
            MediaQuery.sizeOf(context).width < 720 ? 14 : 24,
            72,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSpacing.pageMaxWidth,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 720;
                  final stacked = constraints.maxWidth < 1040;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ExecutiveHeader(
                        language: language,
                        role: role,
                        displayName: displayName,
                        admin: _admin,
                        compact: compact,
                        canOpenAnalytics: canOpenAnalytics,
                        onRefresh: companyAnalytics.isLoading
                            ? null
                            : onRefresh,
                      ),
                      const SizedBox(height: 20),
                      if (_admin &&
                          canOpenAnalytics &&
                          companyAnalytics.isLoading)
                        const Padding(
                          padding: EdgeInsets.all(AppSpacing.xl),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_admin && companyProjection != null) ...[
                        CompanyAnalyticsOverviewSummary(
                          language: language,
                          projection: companyProjection,
                          flags: featureFlags,
                        ),
                        if (partial) ...[
                          const SizedBox(height: 14),
                          _PartialDataNotice(language: language),
                        ],
                      ] else ...[
                        _KpiStrip(
                          language: language,
                          admin: _admin,
                          compact: compact,
                          stats: stats,
                          projects: projects,
                          requests: requests,
                          inventory: inventory,
                          rentals: rentals,
                          activeUsers: activeUsers,
                          canAccessRentals: canAccessRentals,
                        ),
                        if (partial) ...[
                          const SizedBox(height: 14),
                          _PartialDataNotice(language: language),
                        ],
                        const SizedBox(height: 16),
                        _MainExecutiveGrid(
                          language: language,
                          admin: _admin,
                          stacked: stacked,
                          stats: stats,
                          projects: projectItems,
                          requests: requestItems,
                          inventory: inventory,
                          configuration: configuration,
                          rentals: rentals,
                          audit: audit,
                          canBrowseInventory: canBrowseInventory,
                          canAccessRentals: canAccessRentals,
                          healthLoading: _admin
                              ? requests.isLoading
                              : projects.isLoading,
                          healthError: _admin
                              ? requests.hasError
                              : projects.hasError,
                          coreLoading: projects.isLoading || requests.isLoading,
                          coreError: projects.hasError || requests.hasError,
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (_admin &&
                          companyProjection == null &&
                          !companyAnalytics.isLoading)
                        _AdminControlGrid(
                          language: language,
                          stacked: stacked,
                          configuration: configuration,
                          audit: audit,
                          activeUsers: activeUsers,
                        )
                      else if (!_admin)
                        _LeadershipDetailGrid(
                          language: language,
                          stacked: stacked,
                          stats: stats,
                          projects: projectItems,
                          requests: requestItems,
                        ),
                      const SizedBox(height: 16),
                      if (!_admin ||
                          (companyProjection == null &&
                              !companyAnalytics.isLoading))
                        _WorkspaceLinks(
                          language: language,
                          admin: _admin,
                          role: role,
                          compact: compact,
                          canBrowseInventory: canBrowseInventory,
                          canAccessRentals: canAccessRentals,
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExecutiveStats {
  _ExecutiveStats(
    List<YorksV1ProjectPortfolioItem> projects,
    List<YorksV1MaterialRequest> requests,
    YorksV1Role role,
    YorksV1ProjectOverview? projectOverview,
    YorksV1MaterialRequestOverview? overview,
  ) : totalProjects = projectOverview?.total ?? projects.length,
      totalRequests = overview?.total ?? requests.length,
      activeProjects =
          projectOverview?.active ??
          projects
              .where(
                (item) => item.project.state == YorksV1ProjectLifecycle.active,
              )
              .length,
      projectsOnHold =
          projectOverview?.onHold ??
          projects
              .where(
                (item) => item.project.state == YorksV1ProjectLifecycle.onHold,
              )
              .length,
      completedProjects =
          projectOverview?.completed ??
          projects
              .where(
                (item) =>
                    item.project.state == YorksV1ProjectLifecycle.completed,
              )
              .length,
      openRequests = overview?.open ?? requests.where(_isOpen).length,
      needsAction =
          overview?.needsAction ??
          requests
              .where((item) => yorksV1MaterialRequestNeedsAction(item, role))
              .length,
      approvals =
          overview?.approvals ??
          requests
              .where(
                (item) =>
                    item.state ==
                        YorksV1MaterialRequestState.awaitingRequestApproval ||
                    item.state == YorksV1MaterialRequestState.awaitingApproval,
              )
              .length,
      procurementExceptions =
          overview?.deliveryExceptions ??
          requests
              .where(
                (item) =>
                    item.state ==
                        YorksV1MaterialRequestState.changesRequested ||
                    item.state ==
                        YorksV1MaterialRequestState.partiallyDispatched ||
                    item.state == YorksV1MaterialRequestState.partiallyReceived,
              )
              .length,
      dispatchReady =
          overview?.dispatchReady ??
          requests
              .where(
                (item) =>
                    item.state == YorksV1MaterialRequestState.approved ||
                    item.state ==
                        YorksV1MaterialRequestState.partiallyDispatched,
              )
              .length,
      inTransit =
          overview?.receiptPending ??
          requests
              .where(
                (item) =>
                    item.state == YorksV1MaterialRequestState.dispatched ||
                    item.state == YorksV1MaterialRequestState.partiallyReceived,
              )
              .length,
      received =
          overview?.received ??
          requests
              .where(
                (item) => item.state == YorksV1MaterialRequestState.received,
              )
              .length,
      closed =
          overview?.closed ??
          requests
              .where((item) => item.state == YorksV1MaterialRequestState.closed)
              .length;

  final int totalProjects;
  final int totalRequests;
  final int activeProjects;
  final int projectsOnHold;
  final int completedProjects;
  final int openRequests;
  final int needsAction;
  final int approvals;
  final int procurementExceptions;
  final int dispatchReady;
  final int inTransit;
  final int received;
  final int closed;

  int get managementAttention =>
      projectsOnHold + approvals + procurementExceptions;
}

bool _isOpen(YorksV1MaterialRequest request) =>
    request.state != YorksV1MaterialRequestState.draft &&
    request.state != YorksV1MaterialRequestState.received &&
    request.state != YorksV1MaterialRequestState.closed &&
    request.state != YorksV1MaterialRequestState.cancelled;

class _ExecutiveHeader extends StatelessWidget {
  const _ExecutiveHeader({
    required this.language,
    required this.role,
    required this.displayName,
    required this.admin,
    required this.compact,
    required this.canOpenAnalytics,
    this.onRefresh,
  });

  final AppLanguage language;
  final YorksV1Role role;
  final String? displayName;
  final bool admin;
  final bool compact;
  final bool canOpenAnalytics;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final roleLabel = YorksV1ProjectStrings.roleLabel(
      role.claimValue,
    ).active(language);
    final title =
        (admin
                ? YorksV1OverviewStrings.adminCommandCentre
                : YorksV1OverviewStrings.portfolioOverview)
            .active(language);
    final description =
        (admin
                ? YorksV1OverviewStrings.adminCommandDescription
                : YorksV1OverviewStrings.portfolioOverviewDescription)
            .active(language);
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((displayName ?? '').trim().isNotEmpty)
          Text(
            displayName!.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelLarge.copyWith(
              color: AppColors.inkSecondary,
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            Text(
              title,
              key: const ValueKey('executive-overview-title'),
              style: compact
                  ? AppTypography.headlineMedium
                  : AppTypography.displaySmall,
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.blueContainer,
                border: Border.all(color: AppColors.blueContainerStrong),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Text(
                roleLabel,
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.blue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          description,
          style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
        ),
      ],
    );
    final analyticsAction = canOpenAnalytics
        ? _HeaderButton(
            label: YorksV1ShellStrings.analytics.active(language),
            icon: Icons.insights_outlined,
            primary: false,
            onTap: () => context.go(RoutePaths.yorksV1Analytics),
          )
        : null;
    final projectAction = admin
        ? _HeaderButton(
            label: YorksV1ProjectStrings.newProject.active(language),
            icon: Icons.add_business_outlined,
            primary: true,
            onTap: () => context.push(RoutePaths.engineerCreateProject),
          )
        : null;
    final requestsAction = _HeaderButton(
      label: YorksV1ShellStrings.viewAllRequests.active(language),
      icon: Icons.assignment_outlined,
      primary: !admin,
      onTap: () => context.go(RoutePaths.yorksV1MaterialRequests),
    );
    final actions = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [?analyticsAction, ?projectAction, requestsAction],
    );
    if (admin && canOpenAnalytics) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title,
              key: const ValueKey('executive-overview-title'),
              style: compact
                  ? AppTypography.headlineMedium
                  : AppTypography.headlineLarge,
            ),
          ),
          ?analyticsAction,
          IconButton(
            onPressed: onRefresh,
            tooltip: MaterialLocalizations.of(
              context,
            ).refreshIndicatorSemanticLabel,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      );
    }
    if (compact) {
      final secondaryActions = <Widget>[?analyticsAction, requestsAction];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          copy,
          const SizedBox(height: AppSpacing.lg),
          if (projectAction != null) ...[
            SizedBox(width: double.infinity, child: projectAction),
            const SizedBox(height: AppSpacing.sm),
          ],
          Row(
            children: [
              for (var index = 0; index < secondaryActions.length; index++) ...[
                if (index > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(child: secondaryActions[index]),
              ],
            ],
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: copy),
        const SizedBox(width: AppSpacing.xl),
        actions,
      ],
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.label,
    required this.icon,
    required this.primary,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: AppSpacing.minTapTarget,
    child: primary
        ? FilledButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: AppSpacing.xl),
            label: Text(label),
            style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
          )
        : OutlinedButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: AppSpacing.xl),
            label: Text(label),
          ),
  );
}

class _KpiDatum {
  const _KpiDatum({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.background,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color background;
  final VoidCallback? onTap;
}

class _KpiStrip extends StatelessWidget {
  const _KpiStrip({
    required this.language,
    required this.admin,
    required this.compact,
    required this.stats,
    required this.projects,
    required this.requests,
    required this.inventory,
    required this.rentals,
    required this.activeUsers,
    required this.canAccessRentals,
  });

  final AppLanguage language;
  final bool admin;
  final bool compact;
  final _ExecutiveStats stats;
  final AsyncValue<List<YorksV1ProjectPortfolioItem>> projects;
  final AsyncValue<List<YorksV1MaterialRequest>> requests;
  final AsyncValue<YorksV1InventoryWorkspace?> inventory;
  final AsyncValue<YorksV1RentalPortfolio?> rentals;
  final int? activeUsers;
  final bool canAccessRentals;

  @override
  Widget build(BuildContext context) {
    String projectValue(int value) => projects.isLoading
        ? '…'
        : projects.hasError
        ? '—'
        : '$value';
    String requestValue(int value) => requests.isLoading
        ? '…'
        : requests.hasError
        ? '—'
        : '$value';
    final rentalAttention = !canAccessRentals
        ? '—'
        : rentals.when(
            data: (value) => value == null
                ? '—'
                : '${value.summary.expiringWithin90 + value.summary.chequeAttention}',
            error: (_, _) => '—',
            loading: () => '…',
          );
    final cards = admin
        ? <_KpiDatum>[
            _KpiDatum(
              label: YorksV1OverviewStrings.activeProjects.active(language),
              value: projectValue(stats.activeProjects),
              icon: Icons.folder_open_outlined,
              color: AppColors.blue,
              background: AppColors.blueContainer,
              onTap: () => context.go(RoutePaths.yorksV1Projects),
            ),
            _KpiDatum(
              label: YorksV1ShellStrings.needsYourAction.active(language),
              value: requestValue(stats.needsAction),
              icon: Icons.notifications_active_outlined,
              color: AppColors.warning,
              background: AppColors.warningContainer,
              onTap: () => context.go(RoutePaths.yorksV1MaterialRequests),
            ),
            _KpiDatum(
              label: YorksV1OverviewStrings.openMaterialRequests.active(
                language,
              ),
              value: requestValue(stats.openRequests),
              icon: Icons.assignment_outlined,
              color: AppColors.success,
              background: AppColors.successContainer,
              onTap: () => context.go(RoutePaths.yorksV1MaterialRequests),
            ),
            _KpiDatum(
              label: YorksV1OverviewStrings.procurementExceptions.active(
                language,
              ),
              value: requestValue(stats.procurementExceptions),
              icon: Icons.warning_amber_rounded,
              color: AppColors.purple,
              background: AppColors.purpleContainer,
              onTap: () => context.go(RoutePaths.yorksV1MaterialRequests),
            ),
            _KpiDatum(
              label: YorksV1OverviewStrings.accessAndControls.active(language),
              value: activeUsers == null ? '…' : '$activeUsers',
              icon: Icons.admin_panel_settings_outlined,
              color: AppColors.blue,
              background: AppColors.blueContainer,
              onTap: () => context.go(RoutePaths.users),
            ),
            _KpiDatum(
              label: YorksV1OverviewStrings.rentalAttention.active(language),
              value: rentalAttention,
              icon: Icons.apartment_outlined,
              color: AppColors.warning,
              background: AppColors.warningContainer,
              onTap: canAccessRentals
                  ? () => context.go(RoutePaths.rentals)
                  : null,
            ),
          ]
        : <_KpiDatum>[
            _KpiDatum(
              label: YorksV1OverviewStrings.totalProjects.active(language),
              value: projectValue(stats.totalProjects),
              icon: Icons.account_tree_outlined,
              color: AppColors.blue,
              background: AppColors.blueContainer,
              onTap: () => context.go(RoutePaths.yorksV1Projects),
            ),
            _KpiDatum(
              label: YorksV1OverviewStrings.projectsOnTrack.active(language),
              value: projectValue(stats.activeProjects),
              icon: Icons.fact_check_outlined,
              color: AppColors.success,
              background: AppColors.successContainer,
              onTap: () => context.go(RoutePaths.yorksV1Projects),
            ),
            _KpiDatum(
              label: YorksV1OverviewStrings.managementAttention.active(
                language,
              ),
              value: projects.hasError || requests.hasError
                  ? '—'
                  : projects.isLoading || requests.isLoading
                  ? '…'
                  : '${stats.managementAttention}',
              icon: Icons.notification_important_outlined,
              color: AppColors.warning,
              background: AppColors.warningContainer,
              onTap: () => context.go(RoutePaths.yorksV1MaterialRequests),
            ),
            _KpiDatum(
              label: YorksV1OverviewStrings.openMaterialRequests.active(
                language,
              ),
              value: requestValue(stats.openRequests),
              icon: Icons.assignment_outlined,
              color: AppColors.blue,
              background: AppColors.blueContainer,
              onTap: () => context.go(RoutePaths.yorksV1MaterialRequests),
            ),
            _KpiDatum(
              label: YorksV1OverviewStrings.approvalsWaiting.active(language),
              value: requestValue(stats.approvals),
              icon: Icons.approval_outlined,
              color: AppColors.purple,
              background: AppColors.purpleContainer,
              onTap: () => context.go(RoutePaths.yorksV1MaterialRequests),
            ),
            _KpiDatum(
              label: YorksV1OverviewStrings.deliveryExceptions.active(language),
              value: requestValue(stats.procurementExceptions),
              icon: Icons.schedule_outlined,
              color: AppColors.error,
              background: AppColors.errorContainer,
              onTap: () => context.go(RoutePaths.yorksV1MaterialRequests),
            ),
          ];
    if (compact) {
      return SizedBox(
        height: 116,
        child: ListView.separated(
          key: const ValueKey('executive-overview-metrics'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 2),
          itemCount: cards.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, index) => SizedBox(
            width: 164,
            child: _ExecutiveKpiCard(data: cards[index]),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1240 ? 6 : 3;
        const gap = 10.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          key: const ValueKey('executive-overview-metrics'),
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards)
              SizedBox(
                width: width,
                height: 112,
                child: _ExecutiveKpiCard(data: card),
              ),
          ],
        );
      },
    );
  }
}

class _ExecutiveKpiCard extends StatelessWidget {
  const _ExecutiveKpiCard({required this.data});

  final _KpiDatum data;

  @override
  Widget build(BuildContext context) => Semantics(
    button: data.onTap != null,
    label: '${data.label}: ${data.value}',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 14,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: data.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(data.icon, size: 20, color: data.color),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      data.value,
                      style: AppTypography.headlineMedium.copyWith(
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PartialDataNotice extends StatelessWidget {
  const _PartialDataNotice({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.warningContainer,
      border: Border.all(color: AppColors.warning.withValues(alpha: .24)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.sync_problem_outlined,
          color: AppColors.warning,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            YorksV1OverviewStrings.partialData.active(language),
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onWarningContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _MainExecutiveGrid extends StatelessWidget {
  const _MainExecutiveGrid({
    required this.language,
    required this.admin,
    required this.stacked,
    required this.stats,
    required this.projects,
    required this.requests,
    required this.inventory,
    required this.configuration,
    required this.rentals,
    required this.audit,
    required this.canBrowseInventory,
    required this.canAccessRentals,
    required this.healthLoading,
    required this.healthError,
    required this.coreLoading,
    required this.coreError,
  });

  final AppLanguage language;
  final bool admin;
  final bool stacked;
  final _ExecutiveStats stats;
  final List<YorksV1ProjectPortfolioItem> projects;
  final List<YorksV1MaterialRequest> requests;
  final AsyncValue<YorksV1InventoryWorkspace?> inventory;
  final AsyncValue<YorksV1ConfigurationCentre?> configuration;
  final AsyncValue<YorksV1RentalPortfolio?> rentals;
  final YorksV1AuditViewState? audit;
  final bool canBrowseInventory;
  final bool canAccessRentals;
  final bool healthLoading;
  final bool healthError;
  final bool coreLoading;
  final bool coreError;

  @override
  Widget build(BuildContext context) {
    final health = _HealthPanel(
      language: language,
      admin: admin,
      stats: stats,
      loading: healthLoading,
      error: healthError,
    );
    final attention = _AttentionPanel(
      language: language,
      admin: admin,
      stats: stats,
      inventory: inventory,
      configuration: configuration,
      rentals: rentals,
      audit: audit,
      canBrowseInventory: canBrowseInventory,
      canAccessRentals: canAccessRentals,
      coreLoading: coreLoading,
      coreError: coreError,
    );
    if (stacked) {
      return Column(children: [health, const SizedBox(height: 14), attention]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 13, child: health),
        const SizedBox(width: 14),
        Expanded(flex: 8, child: attention),
      ],
    );
  }
}

class _HealthPanel extends StatelessWidget {
  const _HealthPanel({
    required this.language,
    required this.admin,
    required this.stats,
    required this.loading,
    required this.error,
  });

  final AppLanguage language;
  final bool admin;
  final _ExecutiveStats stats;
  final bool loading;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final slices = admin
        ? <_RingSlice>[
            _RingSlice(stats.approvals, AppColors.blue),
            _RingSlice(stats.dispatchReady, AppColors.warning),
            _RingSlice(stats.inTransit, AppColors.purple),
            _RingSlice(stats.received, AppColors.success),
            _RingSlice(stats.closed, AppColors.mutedLight),
          ]
        : <_RingSlice>[
            _RingSlice(stats.activeProjects, AppColors.success),
            _RingSlice(stats.projectsOnHold, AppColors.warning),
            _RingSlice(stats.completedProjects, AppColors.blue),
            _RingSlice(
              math.max(
                0,
                stats.totalProjects -
                    stats.activeProjects -
                    stats.projectsOnHold -
                    stats.completedProjects,
              ),
              AppColors.mutedLight,
            ),
          ];
    final total = admin ? stats.totalRequests : stats.totalProjects;
    return _ExecutivePanel(
      title:
          (admin
                  ? YorksV1OverviewStrings.operationsHealth
                  : YorksV1OverviewStrings.portfolioHealth)
              .active(language),
      actionLabel:
          (admin
                  ? YorksV1ShellStrings.viewAllRequests
                  : YorksV1OverviewStrings.viewAll)
              .active(language),
      onAction: () => context.go(
        admin ? RoutePaths.yorksV1MaterialRequests : RoutePaths.yorksV1Projects,
      ),
      child: loading
          ? const _LoadingRows()
          : error
          ? _UnavailableState(language: language)
          : LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 620;
                final totalLabel =
                    (admin
                            ? YorksV1OverviewStrings.allMaterialRequests
                            : YorksV1OverviewStrings.totalProjects)
                        .active(language);
                final ring = SizedBox(
                  height: 188,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 150,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              totalLabel,
                              key: const ValueKey(
                                'overview-health-total-label',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.inkSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: 132,
                              height: 132,
                              child: CustomPaint(
                                painter: _RingPainter(slices),
                                child: Center(
                                  child: Text(
                                    '$total',
                                    key: const ValueKey(
                                      'overview-health-total-value',
                                    ),
                                    style: AppTypography.headlineMedium
                                        .copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: admin
                              ? [
                                  _HealthLine(
                                    label: YorksV1OverviewStrings
                                        .approvalsWaiting
                                        .active(language),
                                    value: stats.approvals,
                                    color: AppColors.blue,
                                  ),
                                  _HealthLine(
                                    label: YorksV1OverviewStrings
                                        .readyForDispatch
                                        .active(language),
                                    value: stats.dispatchReady,
                                    color: AppColors.warning,
                                  ),
                                  _HealthLine(
                                    label: YorksV1OverviewStrings.receiptPending
                                        .active(language),
                                    value: stats.inTransit,
                                    color: AppColors.purple,
                                  ),
                                  _HealthLine(
                                    label: YorksV1OverviewStrings.closedRequests
                                        .active(language),
                                    value: stats.closed,
                                    color: AppColors.mutedLight,
                                  ),
                                ]
                              : [
                                  _HealthLine(
                                    label: YorksV1OverviewStrings
                                        .projectsOnTrack
                                        .active(language),
                                    value: stats.activeProjects,
                                    color: AppColors.success,
                                  ),
                                  _HealthLine(
                                    label: YorksV1OverviewStrings.projectsOnHold
                                        .active(language),
                                    value: stats.projectsOnHold,
                                    color: AppColors.warning,
                                  ),
                                  _HealthLine(
                                    label: YorksV1ProjectStrings.completedState
                                        .active(language),
                                    value: stats.completedProjects,
                                    color: AppColors.blue,
                                  ),
                                ],
                        ),
                      ),
                    ],
                  ),
                );
                final delivery = _DeliverySummary(
                  language: language,
                  stats: stats,
                );
                if (narrow) {
                  return Column(children: [ring, const Divider(), delivery]);
                }
                return Row(
                  children: [
                    Expanded(child: ring),
                    const VerticalDivider(width: 30),
                    Expanded(child: delivery),
                  ],
                );
              },
            ),
    );
  }
}

class _DeliverySummary extends StatelessWidget {
  const _DeliverySummary({required this.language, required this.stats});

  final AppLanguage language;
  final _ExecutiveStats stats;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        YorksV1OverviewStrings.deliveryAndReceipt.active(language),
        style: AppTypography.titleSmall,
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: _MiniStat(
              label: YorksV1OverviewStrings.readyForDispatch.active(language),
              value: '${stats.dispatchReady}',
              color: AppColors.blue,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MiniStat(
              label: YorksV1OverviewStrings.receiptPending.active(language),
              value: '${stats.inTransit}',
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MiniStat(
              label: YorksV1MaterialRequestStrings.received.active(language),
              value: '${stats.received}',
              color: AppColors.success,
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          minHeight: 8,
          value: stats.openRequests + stats.received == 0
              ? 0
              : stats.received / (stats.openRequests + stats.received),
          backgroundColor: AppColors.surfaceContainerHighest,
          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.success),
        ),
      ),
    ],
  );
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLow,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelSmall,
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: AppTypography.titleLarge.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _HealthLine extends StatelessWidget {
  const _HealthLine({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall,
          ),
        ),
        Text('$value', style: AppTypography.labelLarge),
      ],
    ),
  );
}

class _RingSlice {
  const _RingSlice(this.value, this.color);
  final int value;
  final Color color;
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.slices);
  final List<_RingSlice> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = math.min(size.width, size.height) * .17;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2 + 2);
    final total = slices.fold<int>(0, (sum, slice) => sum + slice.value);
    final background = Paint()
      ..color = AppColors.surfaceContainerHighest
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(arc, 0, math.pi * 2, false, background);
    if (total == 0) return;
    var start = -math.pi / 2;
    for (final slice in slices) {
      if (slice.value == 0) continue;
      final sweep = math.pi * 2 * slice.value / total;
      canvas.drawArc(
        arc,
        start,
        math.max(0, sweep - .035),
        false,
        Paint()
          ..color = slice.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.slices != slices;
}

class _AttentionRecord {
  const _AttentionRecord({
    required this.title,
    required this.detail,
    required this.icon,
    required this.color,
    required this.route,
  });

  final String title;
  final String detail;
  final IconData icon;
  final Color color;
  final String route;
}

class _AttentionPanel extends StatelessWidget {
  const _AttentionPanel({
    required this.language,
    required this.admin,
    required this.stats,
    required this.inventory,
    required this.configuration,
    required this.rentals,
    required this.audit,
    required this.canBrowseInventory,
    required this.canAccessRentals,
    required this.coreLoading,
    required this.coreError,
  });

  final AppLanguage language;
  final bool admin;
  final _ExecutiveStats stats;
  final AsyncValue<YorksV1InventoryWorkspace?> inventory;
  final AsyncValue<YorksV1ConfigurationCentre?> configuration;
  final AsyncValue<YorksV1RentalPortfolio?> rentals;
  final YorksV1AuditViewState? audit;
  final bool canBrowseInventory;
  final bool canAccessRentals;
  final bool coreLoading;
  final bool coreError;

  @override
  Widget build(BuildContext context) {
    final records = <_AttentionRecord>[];
    if (stats.approvals > 0) {
      records.add(
        _AttentionRecord(
          title: YorksV1OverviewStrings.engineeringApprovals.active(language),
          detail: '${stats.approvals}',
          icon: Icons.approval_outlined,
          color: AppColors.error,
          route: RoutePaths.yorksV1MaterialRequests,
        ),
      );
    }
    if (stats.procurementExceptions > 0) {
      records.add(
        _AttentionRecord(
          title: YorksV1OverviewStrings.procurementExceptions.active(language),
          detail: '${stats.procurementExceptions}',
          icon: Icons.production_quantity_limits_outlined,
          color: AppColors.warning,
          route: RoutePaths.yorksV1MaterialRequests,
        ),
      );
    }
    if (stats.projectsOnHold > 0) {
      records.add(
        _AttentionRecord(
          title: YorksV1OverviewStrings.projectsOnHold.active(language),
          detail: '${stats.projectsOnHold}',
          icon: Icons.pause_circle_outline,
          color: AppColors.warning,
          route: RoutePaths.yorksV1Projects,
        ),
      );
    }
    final inventoryValue = inventory.valueOrNull?.summary.attentionCount;
    if (canBrowseInventory && (inventoryValue ?? 0) > 0) {
      records.add(
        _AttentionRecord(
          title: YorksV1OverviewStrings.inventoryAttention.active(language),
          detail: '$inventoryValue',
          icon: Icons.inventory_2_outlined,
          color: AppColors.purple,
          route: RoutePaths.yorksV1Inventory,
        ),
      );
    }
    if (admin) {
      final config = configuration.valueOrNull;
      if ((config?.validation.blocking.length ?? 0) > 0) {
        records.add(
          _AttentionRecord(
            title: YorksV1OverviewStrings.blockingIssues.active(language),
            detail: '${config!.validation.blocking.length}',
            icon: Icons.settings_suggest_outlined,
            color: AppColors.error,
            route: RoutePaths.yorksV1Configuration,
          ),
        );
      }
      final rental = rentals.valueOrNull?.summary;
      final rentalCount =
          (rental?.expiringWithin90 ?? 0) + (rental?.chequeAttention ?? 0);
      if (canAccessRentals && rentalCount > 0) {
        records.add(
          _AttentionRecord(
            title: YorksV1OverviewStrings.rentalAttention.active(language),
            detail: '$rentalCount',
            icon: Icons.apartment_outlined,
            color: AppColors.warning,
            route: RoutePaths.rentals,
          ),
        );
      }
      final critical = audit?.workspace?.summary.criticalActivities ?? 0;
      if (critical > 0) {
        records.add(
          _AttentionRecord(
            title: YorksV1OverviewStrings.criticalEvents.active(language),
            detail: '$critical',
            icon: Icons.security_outlined,
            color: AppColors.error,
            route: RoutePaths.activityLog,
          ),
        );
      }
    }
    final visible = records.take(6).toList(growable: false);
    return _ExecutivePanel(
      title:
          (admin
                  ? YorksV1OverviewStrings.adminAttention
                  : YorksV1OverviewStrings.managementAttention)
              .active(language),
      actionLabel: YorksV1OverviewStrings.viewAll.active(language),
      onAction: () => context.go(RoutePaths.yorksV1MaterialRequests),
      child: coreLoading
          ? const _LoadingRows()
          : visible.isEmpty && coreError
          ? _UnavailableState(language: language)
          : visible.isEmpty
          ? SizedBox(
              height: 214,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                      color: AppColors.successContainer,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: AppColors.success,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    YorksV1OverviewStrings.allClear.active(language),
                    style: AppTypography.titleMedium,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    YorksV1OverviewStrings.allClearDescription.active(language),
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall,
                  ),
                ],
              ),
            )
          : Column(
              children: [
                for (var index = 0; index < visible.length; index++) ...[
                  _AttentionTile(record: visible[index]),
                  if (index != visible.length - 1) const SizedBox(height: 7),
                ],
              ],
            ),
    );
  }
}

class _AttentionTile extends StatelessWidget {
  const _AttentionTile({required this.record});
  final _AttentionRecord record;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: () => context.go(record.route),
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: record.color.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(record.icon, color: record.color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  record.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                constraints: const BoxConstraints(minWidth: 28),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: record.color.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  record.detail,
                  textAlign: TextAlign.center,
                  style: AppTypography.labelSmall.copyWith(
                    color: record.color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.muted,
                size: 21,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AdminControlGrid extends StatelessWidget {
  const _AdminControlGrid({
    required this.language,
    required this.stacked,
    required this.configuration,
    required this.audit,
    required this.activeUsers,
  });

  final AppLanguage language;
  final bool stacked;
  final AsyncValue<YorksV1ConfigurationCentre?> configuration;
  final YorksV1AuditViewState? audit;
  final int? activeUsers;

  @override
  Widget build(BuildContext context) {
    final security = _ExecutivePanel(
      title: YorksV1OverviewStrings.systemAndSecurity.active(language),
      actionLabel: YorksV1OverviewStrings.openAuditTrail.active(language),
      onAction: () => context.go(RoutePaths.activityLog),
      child: Column(
        children: [
          _ValueRow(
            label: YorksV1OverviewStrings.activeUsers.active(language),
            value: activeUsers == null ? '…' : '$activeUsers',
          ),
          _ValueRow(
            label: YorksV1OverviewStrings.criticalEvents.active(language),
            value: audit == null || audit!.isLoading
                ? '…'
                : audit!.error != null
                ? '—'
                : '${audit!.workspace?.summary.criticalActivities ?? 0}',
          ),
          _ValueRow(
            label: YorksV1OverviewStrings.dataIntegrity.active(language),
            value: audit == null || audit!.isLoading
                ? '…'
                : audit!.error != null
                ? '—'
                : '${(audit!.workspace?.summary.dataIntegrityPercent ?? 0).toStringAsFixed(0)}%',
            last: true,
          ),
        ],
      ),
    );
    final config = _ExecutivePanel(
      title: YorksV1OverviewStrings.configurationStatus.active(language),
      actionLabel: YorksV1ShellStrings.configuration.active(language),
      onAction: () => context.go(RoutePaths.yorksV1Configuration),
      trailing: configuration.valueOrNull == null
          ? null
          : _StatePill(
              label: YorksV1OverviewStrings.published.active(language),
              color: AppColors.success,
            ),
      child: configuration.when(
        data: (value) => value == null
            ? _UnavailableState(language: language)
            : Column(
                children: [
                  _ValueRow(
                    label: YorksV1OverviewStrings.currentVersion.active(
                      language,
                    ),
                    value: value.publishedLabel,
                  ),
                  _ValueRow(
                    label: YorksV1OverviewStrings.draftChanges.active(language),
                    value: '${value.draftChangeCount}',
                  ),
                  _ValueRow(
                    label: YorksV1OverviewStrings.blockingIssues.active(
                      language,
                    ),
                    value: '${value.validation.blocking.length}',
                  ),
                  _ValueRow(
                    label: YorksV1OverviewStrings.recommendations.active(
                      language,
                    ),
                    value: '${value.validation.recommendations.length}',
                    last: true,
                  ),
                ],
              ),
        error: (_, _) => _UnavailableState(language: language),
        loading: () => const _LoadingRows(),
      ),
    );
    final activity = _ExecutivePanel(
      title: YorksV1OverviewStrings.recentCriticalActivity.active(language),
      actionLabel: YorksV1OverviewStrings.viewAll.active(language),
      onAction: () => context.go(RoutePaths.activityLog),
      child: _AuditActivity(language: language, state: audit),
    );
    if (stacked) {
      return Column(
        children: [
          security,
          const SizedBox(height: 14),
          config,
          const SizedBox(height: 14),
          activity,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: security),
        const SizedBox(width: 14),
        Expanded(child: config),
        const SizedBox(width: 14),
        Expanded(child: activity),
      ],
    );
  }
}

class _AuditActivity extends StatelessWidget {
  const _AuditActivity({required this.language, required this.state});
  final AppLanguage language;
  final YorksV1AuditViewState? state;

  @override
  Widget build(BuildContext context) {
    if (state == null || state!.isLoading) return const _LoadingRows();
    if (state!.error != null) return _UnavailableState(language: language);
    final events = (state!.workspace?.events ?? const <YorksV1AuditEvent>[])
        .where((event) => event.severity != YorksV1AuditSeverity.normal)
        .take(4)
        .toList(growable: false);
    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Text(
          YorksV1OverviewStrings.noCriticalActivity.active(language),
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall,
        ),
      );
    }
    return Column(
      children: [
        for (var index = 0; index < events.length; index++) ...[
          _ActivityRow(event: events[index], language: language),
          if (index != events.length - 1) const Divider(height: 13),
        ],
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.event, required this.language});
  final YorksV1AuditEvent event;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: event.severity == YorksV1AuditSeverity.critical
              ? AppColors.errorContainer
              : AppColors.warningContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.history_rounded,
          size: 17,
          color: event.severity == YorksV1AuditSeverity.critical
              ? AppColors.error
              : AppColors.warning,
        ),
      ),
      const SizedBox(width: 9),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              event.reference.isEmpty ? event.eventType : event.reference,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge,
            ),
            Text(
              '${event.actorDisplayName} · ${DateFormat.MMMd().add_jm().format(event.occurredAt)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall,
            ),
          ],
        ),
      ),
    ],
  );
}

class _LeadershipDetailGrid extends StatelessWidget {
  const _LeadershipDetailGrid({
    required this.language,
    required this.stacked,
    required this.stats,
    required this.projects,
    required this.requests,
  });

  final AppLanguage language;
  final bool stacked;
  final _ExecutiveStats stats;
  final List<YorksV1ProjectPortfolioItem> projects;
  final List<YorksV1MaterialRequest> requests;

  @override
  Widget build(BuildContext context) {
    final approvals = _ExecutivePanel(
      title: YorksV1OverviewStrings.engineeringApprovals.active(language),
      actionLabel: YorksV1OverviewStrings.viewAll.active(language),
      onAction: () => context.go(RoutePaths.yorksV1MaterialRequests),
      child: Column(
        children: [
          _ValueRow(
            label: YorksV1OverviewStrings.approvalsWaiting.active(language),
            value: '${stats.approvals}',
          ),
          _ValueRow(
            label: YorksV1OverviewStrings.procurementExceptions.active(
              language,
            ),
            value: '${stats.procurementExceptions}',
          ),
          _ValueRow(
            label: YorksV1OverviewStrings.receiptPending.active(language),
            value: '${stats.inTransit}',
            last: true,
          ),
        ],
      ),
    );
    final activity = _ExecutivePanel(
      title: YorksV1OverviewStrings.recentPortfolioActivity.active(language),
      actionLabel: YorksV1OverviewStrings.viewAll.active(language),
      onAction: () => context.go(RoutePaths.yorksV1MaterialRequests),
      child: _RecentRequestRows(language: language, requests: requests),
    );
    final portfolio = _ExecutivePanel(
      title: YorksV1OverviewStrings.assignedPortfolio.active(language),
      actionLabel: YorksV1OverviewStrings.viewAll.active(language),
      onAction: () => context.go(RoutePaths.yorksV1Projects),
      child: _RecentProjectRows(language: language, projects: projects),
    );
    if (stacked) {
      return Column(
        children: [
          approvals,
          const SizedBox(height: 14),
          activity,
          const SizedBox(height: 14),
          portfolio,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: approvals),
        const SizedBox(width: 14),
        Expanded(child: activity),
        const SizedBox(width: 14),
        Expanded(child: portfolio),
      ],
    );
  }
}

class _RecentRequestRows extends StatelessWidget {
  const _RecentRequestRows({required this.language, required this.requests});
  final AppLanguage language;
  final List<YorksV1MaterialRequest> requests;

  @override
  Widget build(BuildContext context) {
    final recent = [...requests]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (recent.isEmpty) {
      return _EmptyRows(
        label: YorksV1ProjectStrings.noRecentRequests.active(language),
      );
    }
    return Column(
      children: [
        for (final request in recent.take(4))
          _CompactRecordRow(
            icon: Icons.assignment_outlined,
            title:
                request.requestNumber ?? request.title ?? request.projectName,
            subtitle: yorksV1MaterialRequestStateCopy(
              request.state,
            ).active(language),
            onTap: () =>
                context.push(RoutePaths.yorksV1MaterialRequestPath(request.id)),
          ),
      ],
    );
  }
}

class _RecentProjectRows extends StatelessWidget {
  const _RecentProjectRows({required this.language, required this.projects});
  final AppLanguage language;
  final List<YorksV1ProjectPortfolioItem> projects;

  @override
  Widget build(BuildContext context) {
    final recent = [...projects]
      ..sort((a, b) => b.project.updatedAt.compareTo(a.project.updatedAt));
    if (recent.isEmpty) {
      return _EmptyRows(
        label: YorksV1ProjectStrings.noProjects.active(language),
      );
    }
    return Column(
      children: [
        for (final item in recent.take(4))
          _CompactRecordRow(
            icon: Icons.folder_outlined,
            title: '${item.project.reference} · ${item.project.name}',
            subtitle: YorksV1ProjectStrings.stateLabel(
              item.project.state,
            ).active(language),
            onTap: () =>
                context.push(RoutePaths.yorksV1ProjectPath(item.project.id)),
          ),
      ],
    );
  }
}

class _CompactRecordRow extends StatelessWidget {
  const _CompactRecordRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.blueContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppColors.blue, size: 17),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge,
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.mutedLight,
              size: 20,
            ),
          ],
        ),
      ),
    ),
  );
}

class _WorkspaceLink {
  const _WorkspaceLink(this.label, this.icon, this.route);
  final String label;
  final IconData icon;
  final String route;
}

class _WorkspaceLinks extends StatelessWidget {
  const _WorkspaceLinks({
    required this.language,
    required this.admin,
    required this.role,
    required this.compact,
    required this.canBrowseInventory,
    required this.canAccessRentals,
  });

  final AppLanguage language;
  final bool admin;
  final YorksV1Role role;
  final bool compact;
  final bool canBrowseInventory;
  final bool canAccessRentals;

  @override
  Widget build(BuildContext context) {
    final links = <_WorkspaceLink>[
      _WorkspaceLink(
        YorksV1ShellStrings.projects.active(language),
        Icons.account_tree_outlined,
        RoutePaths.yorksV1Projects,
      ),
      _WorkspaceLink(
        YorksV1ShellStrings.materialRequests.active(language),
        Icons.assignment_outlined,
        RoutePaths.yorksV1MaterialRequests,
      ),
      if (canBrowseInventory)
        _WorkspaceLink(
          YorksV1ShellStrings.browseInventory.active(language),
          Icons.inventory_2_outlined,
          RoutePaths.yorksV1Inventory,
        ),
      _WorkspaceLink(
        YorksV1ShellStrings.materialReturns.active(language),
        Icons.assignment_return_outlined,
        RoutePaths.yorksV1Returns,
      ),
      if (admin)
        _WorkspaceLink(
          YorksV1ShellStrings.dispatches.active(language),
          Icons.local_shipping_outlined,
          RoutePaths.yorksV1Dispatches,
        ),
      _WorkspaceLink(
        YorksV1TeamChatStrings.teamChat.active(language),
        Icons.chat_bubble_outline_rounded,
        RoutePaths.yorksV1TeamChat,
      ),
      if (admin)
        _WorkspaceLink(
          YorksV1ShellStrings.configuration.active(language),
          Icons.tune_outlined,
          RoutePaths.yorksV1Configuration,
        ),
      if (admin || role == YorksV1Role.seniorMechanicalEngineer)
        _WorkspaceLink(
          YorksV1ShellStrings.userManagement.active(language),
          Icons.manage_accounts_outlined,
          RoutePaths.users,
        ),
      if (admin)
        _WorkspaceLink(
          YorksV1ShellStrings.auditTrail.active(language),
          Icons.history_outlined,
          RoutePaths.activityLog,
        ),
      if (admin && canAccessRentals)
        _WorkspaceLink(
          YorksV1ShellStrings.rentalProperties.active(language),
          Icons.apartment_outlined,
          RoutePaths.rentals,
        ),
    ];
    return _ExecutivePanel(
      title: YorksV1OverviewStrings.operationalWorkspaces.active(language),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = compact
              ? 2
              : constraints.maxWidth >= 1160
              ? 5
              : 3;
          const gap = 9.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final link in links)
                SizedBox(
                  width: width,
                  child: _WorkspaceLinkButton(link: link),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _WorkspaceLinkButton extends StatelessWidget {
  const _WorkspaceLinkButton({required this.link});
  final _WorkspaceLink link;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: () => context.go(link.route),
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 54),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.blueContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(link.icon, color: AppColors.blue, size: 18),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  link.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge,
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.mutedLight,
                size: 19,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ExecutivePanel extends StatelessWidget {
  const _ExecutivePanel({
    required this.title,
    required this.child,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  final String title;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(13),
      boxShadow: const [
        BoxShadow(
          color: AppColors.shadow,
          blurRadius: 16,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
              if (actionLabel != null && onAction != null)
                TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(padding: const EdgeInsets.all(16), child: child),
      ],
    ),
  );
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.label,
    required this.value,
    this.last = false,
  });

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 42),
        child: Row(
          children: [
            Expanded(child: Text(label, style: AppTypography.bodySmall)),
            const SizedBox(width: 8),
            Text(
              value,
              style: AppTypography.labelLarge.copyWith(color: AppColors.ink),
            ),
          ],
        ),
      ),
      if (!last) const Divider(height: 1),
    ],
  );
}

class _StatePill extends StatelessWidget {
  const _StatePill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: AppTypography.labelSmall.copyWith(
        color: color,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _LoadingRows extends StatelessWidget {
  const _LoadingRows();

  @override
  Widget build(BuildContext context) => Column(
    children: List.generate(
      3,
      (index) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(
          minHeight: 8,
          backgroundColor: AppColors.surfaceContainerHighest,
          color: AppColors.blueContainerStrong,
        ),
      ),
    ),
  );
}

class _UnavailableState extends StatelessWidget {
  const _UnavailableState({required this.language});
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.cloud_off_outlined, size: 18, color: AppColors.muted),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            YorksV1OverviewStrings.partialData.active(language),
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall,
          ),
        ),
      ],
    ),
  );
}

class _EmptyRows extends StatelessWidget {
  const _EmptyRows({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: AppTypography.bodySmall,
    ),
  );
}

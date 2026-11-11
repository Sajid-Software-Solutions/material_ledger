import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_accounts_strings.dart';
import '../../application/accounts_controller.dart';
import '../../application/accounts_portfolio_controller.dart';
import '../../domain/accounts_decimal.dart';
import '../../domain/accounts_portfolio_models.dart';
import '../../domain/accounts_records_models.dart';
import '../widgets/yorks_accounts_records_views.dart';

typedef YorksAccountsOverviewFilterCallback =
    void Function({
      required String? commercialState,
      required String? dueState,
      required String? paymentState,
    });

/// The organization Accounts landing page.
///
/// Every value rendered here comes from the single protected portfolio
/// projection. The widget never starts its own network request, so filtering,
/// refresh, pagination, authorization, and cache invalidation remain owned by
/// the Riverpod controller and server projection.
class YorksAccountsControlCentreOverview extends StatelessWidget {
  const YorksAccountsControlCentreOverview({
    super.key,
    required this.state,
    required this.language,
    required this.searchController,
    required this.commercialState,
    required this.dueState,
    required this.paymentState,
    required this.activeFilterCount,
    required this.onSearchChanged,
    required this.onApplyFilters,
    required this.onClearFilters,
    required this.onRetry,
    required this.onRefresh,
    required this.onLoadMore,
  });

  final YorksAccountsPortfolioState state;
  final AppLanguage language;
  final TextEditingController searchController;
  final String? commercialState;
  final String? dueState;
  final String? paymentState;
  final int activeFilterCount;
  final ValueChanged<String> onSearchChanged;
  final YorksAccountsOverviewFilterCallback onApplyFilters;
  final VoidCallback onClearFilters;
  final VoidCallback onRetry;
  final Future<bool> Function() onRefresh;
  final Future<bool> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    final projection = state.projection;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < AppSpacing.compactBreakpoint;
    final backgroundLoading =
        projection != null && state.status == YorksAccountsViewStatus.loading;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              await onRefresh();
            },
            child: CustomScrollView(
              key: const PageStorageKey('accounts-control-centre-overview'),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    compact
                        ? AppSpacing.mobileScreenHorizontal
                        : AppSpacing.xxl,
                    compact ? AppSpacing.md : AppSpacing.xl,
                    compact
                        ? AppSpacing.mobileScreenHorizontal
                        : AppSpacing.xxl,
                    AppSpacing.colossal,
                  ),
                  sliver: SliverList.list(
                    children: [
                      if (projection == null)
                        _OverviewInitialState(
                          status: state.status,
                          language: language,
                          onRetry: onRetry,
                        )
                      else ...[
                        if (state.error != null)
                          _OverviewRefreshNotice(
                            language: language,
                            onRetry: onRetry,
                          ),
                        if (state.error != null)
                          const SizedBox(height: AppSpacing.md),
                        _OverviewLoaded(
                          projection: projection,
                          state: state,
                          language: language,
                          searchController: searchController,
                          commercialState: commercialState,
                          dueState: dueState,
                          paymentState: paymentState,
                          activeFilterCount: activeFilterCount,
                          onSearchChanged: onSearchChanged,
                          onApplyFilters: onApplyFilters,
                          onClearFilters: onClearFilters,
                          onLoadMore: onLoadMore,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (backgroundLoading)
            const PositionedDirectional(
              start: 0,
              end: 0,
              top: 0,
              child: LinearProgressIndicator(
                key: ValueKey('accounts-portfolio-background-loading'),
                minHeight: 3,
              ),
            ),
        ],
      ),
    );
  }
}

class _OverviewLoaded extends StatelessWidget {
  const _OverviewLoaded({
    required this.projection,
    required this.state,
    required this.language,
    required this.searchController,
    required this.commercialState,
    required this.dueState,
    required this.paymentState,
    required this.activeFilterCount,
    required this.onSearchChanged,
    required this.onApplyFilters,
    required this.onClearFilters,
    required this.onLoadMore,
  });

  final YorksAccountsPortfolioProjection projection;
  final YorksAccountsPortfolioState state;
  final AppLanguage language;
  final TextEditingController searchController;
  final String? commercialState;
  final String? dueState;
  final String? paymentState;
  final int activeFilterCount;
  final ValueChanged<String> onSearchChanged;
  final YorksAccountsOverviewFilterCallback onApplyFilters;
  final VoidCallback onClearFilters;
  final Future<bool> Function() onLoadMore;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 1180;
      final tablet = constraints.maxWidth >= 720;
      final rail = _OverviewRightRail(
        projection: projection,
        language: language,
        horizontal: !desktop && tablet,
      );
      final register = _ProjectAccountsPanel(
        projection: projection,
        state: state,
        language: language,
        searchController: searchController,
        commercialState: commercialState,
        dueState: dueState,
        paymentState: paymentState,
        activeFilterCount: activeFilterCount,
        onSearchChanged: onSearchChanged,
        onApplyFilters: onApplyFilters,
        onClearFilters: onClearFilters,
        onLoadMore: onLoadMore,
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (desktop)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _OverviewMetrics(
                    totals: projection.totals,
                    language: language,
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                SizedBox(
                  width: 304,
                  child: _FinancialHealthCard(
                    projection: projection,
                    language: language,
                  ),
                ),
              ],
            )
          else ...[
            _OverviewMetrics(totals: projection.totals, language: language),
            const SizedBox(height: AppSpacing.md),
            _FinancialHealthCard(projection: projection, language: language),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (desktop)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: register),
                const SizedBox(width: AppSpacing.lg),
                SizedBox(width: 304, child: rail),
              ],
            )
          else ...[
            register,
            const SizedBox(height: AppSpacing.lg),
            rail,
          ],
          const SizedBox(height: AppSpacing.lg),
          _ActionQueuesPanel(projection: projection, language: language),
        ],
      );
    },
  );
}

class _OverviewMetrics extends StatelessWidget {
  const _OverviewMetrics({required this.totals, required this.language});

  final YorksAccountsPortfolioTotals totals;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final metrics = <_MetricData>[
      _MetricData(
        label: _text(language, 'overview_confirmed_work'),
        value: totals.confirmedEligible,
        ratio: _ratio(totals.confirmedEligible, totals.contractBaseline),
        icon: Icons.hub_outlined,
        color: AppColors.blue,
        container: AppColors.blueContainer,
      ),
      _MetricData(
        label: _text(language, 'available'),
        value: totals.availableToClaim,
        ratio: _ratio(totals.availableToClaim, totals.contractBaseline),
        icon: Icons.link_rounded,
        color: AppColors.success,
        container: AppColors.successContainer,
      ),
      _MetricData(
        label: _text(language, 'overview_claimed_submitted'),
        value: totals.claimed,
        ratio: _ratio(totals.claimed, totals.contractBaseline),
        icon: Icons.polyline_outlined,
        color: AppColors.purple,
        container: AppColors.purpleContainer,
      ),
      _MetricData(
        label: _text(language, 'overview_certified_client'),
        value: totals.certified,
        ratio: _ratio(totals.certified, totals.contractBaseline),
        icon: Icons.fact_check_outlined,
        color: AppColors.blue,
        container: AppColors.blueContainer,
      ),
      _MetricData(
        label: _text(language, 'overview_paid_yorks'),
        value: totals.amountPaidTillDate,
        ratio: _ratio(totals.amountPaidTillDate, totals.contractBaseline),
        icon: Icons.account_balance_wallet_outlined,
        color: AppColors.success,
        container: AppColors.successContainer,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 5
            : constraints.maxWidth >= 540
            ? 3
            : 2;
        final gap = constraints.maxWidth < 540 ? AppSpacing.sm : AppSpacing.md;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: _OverviewMetricCard(metric: metric, language: language),
              ),
          ],
        );
      },
    );
  }
}

class _MetricData {
  const _MetricData({
    required this.label,
    required this.value,
    required this.ratio,
    required this.icon,
    required this.color,
    required this.container,
  });

  final String label;
  final YorksAccountsDecimal value;
  final double ratio;
  final IconData icon;
  final Color color;
  final Color container;
}

class _OverviewMetricCard extends StatelessWidget {
  const _OverviewMetricCard({required this.metric, required this.language});

  final _MetricData metric;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => _OverviewPanel(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Semantics(
      label:
          '${metric.label}, ${_compactMoney(metric.value)}, ${_percent(metric.ratio)} ${_text(language, 'overview_of_contract')}',
      child: SizedBox(
        height: 126,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _SmallIcon(
                  icon: metric.icon,
                  color: metric.color,
                  background: metric.container,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    metric.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.inkSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                _compactMoney(metric.value),
                style: AppTypography.headlineSmall,
              ),
            ),
            Text(
              '${_percent(metric.ratio)} ${_text(language, 'overview_of_contract')}',
              style: AppTypography.labelSmall,
            ),
            const Spacer(),
            // The share of the contract, drawn as what it is: not a trend, which
            // there is no history here to show.
            ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                child: LinearProgressIndicator(
                  value: metric.ratio.clamp(0.0, 1.0),
                  minHeight: 6,
                  color: metric.color,
                  backgroundColor: AppColors.surfaceContainerHigh,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _FinancialHealthCard extends StatelessWidget {
  const _FinancialHealthCard({
    required this.projection,
    required this.language,
  });

  final YorksAccountsPortfolioProjection projection;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final projects = projection.projects;
    final overdue = projects.where((item) => item.dueState == 'overdue').length;
    final attention = projects
        .where((item) => item.dueState != 'overdue' && item.actionCount > 0)
        .length;
    final paid = projects
        .where(
          (item) =>
              item.dueState != 'overdue' &&
              item.actionCount == 0 &&
              item.paymentState == 'paid',
        )
        .length;
    final healthy = math.max(0, projects.length - overdue - attention - paid);
    final total = math.max(1, projects.length);
    final segments = <_HealthSegment>[
      _HealthSegment(
        _text(language, 'overview_paid'),
        paid / total,
        AppColors.success,
      ),
      _HealthSegment(
        _text(language, 'overview_due'),
        overdue / total,
        AppColors.error,
      ),
      _HealthSegment(
        _text(language, 'overview_at_risk'),
        attention / total,
        AppColors.warning,
      ),
      _HealthSegment(
        _text(language, 'overview_healthy'),
        healthy / total,
        AppColors.blue,
      ),
    ];
    // A fully paid project is as healthy as one can be.
    final healthRatio = (healthy + paid) / total;
    return _OverviewPanel(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _text(language, 'overview_financial_health'),
            style: AppTypography.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              SizedBox.square(
                dimension: 88,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size.square(88),
                      painter: _HealthDonutPainter(segments: segments),
                    ),
                    // Stay inside the ring (88 px, 12 px stroke) whatever
                    // the value or language.
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _percent(healthRatio),
                              maxLines: 1,
                              style: AppTypography.titleMedium,
                            ),
                            Text(
                              _text(language, 'overview_healthy'),
                              maxLines: 1,
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.inkSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Keep each value next to its label on a wide card.
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Column(
                    children: [
                      for (final segment in segments)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: segment.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  segment.label,
                                  style: AppTypography.bodySmall,
                                ),
                              ),
                              Text(
                                _percent(segment.value),
                                style: AppTypography.labelSmall.copyWith(
                                  color: AppColors.inkSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HealthSegment {
  const _HealthSegment(this.label, this.value, this.color);

  final String label;
  final double value;
  final Color color;
}

class _HealthDonutPainter extends CustomPainter {
  const _HealthDonutPainter({required this.segments});

  final List<_HealthSegment> segments;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(
      rect.deflate(12),
      -math.pi / 2,
      math.pi * 2,
      false,
      paint..color = AppColors.surfaceContainerHighest,
    );
    var start = -math.pi / 2;
    for (final segment in segments) {
      if (segment.value <= 0) continue;
      final sweep = math.pi * 2 * segment.value;
      canvas.drawArc(
        rect.deflate(12),
        start,
        sweep,
        false,
        paint..color = segment.color,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _HealthDonutPainter oldDelegate) {
    if (oldDelegate.segments.length != segments.length) return true;
    for (var index = 0; index < segments.length; index++) {
      final previous = oldDelegate.segments[index];
      final current = segments[index];
      if (previous.value != current.value || previous.color != current.color) {
        return true;
      }
    }
    return false;
  }
}

class _ProjectAccountsPanel extends StatelessWidget {
  const _ProjectAccountsPanel({
    required this.projection,
    required this.state,
    required this.language,
    required this.searchController,
    required this.commercialState,
    required this.dueState,
    required this.paymentState,
    required this.activeFilterCount,
    required this.onSearchChanged,
    required this.onApplyFilters,
    required this.onClearFilters,
    required this.onLoadMore,
  });

  final YorksAccountsPortfolioProjection projection;
  final YorksAccountsPortfolioState state;
  final AppLanguage language;
  final TextEditingController searchController;
  final String? commercialState;
  final String? dueState;
  final String? paymentState;
  final int activeFilterCount;
  final ValueChanged<String> onSearchChanged;
  final YorksAccountsOverviewFilterCallback onApplyFilters;
  final VoidCallback onClearFilters;
  final Future<bool> Function() onLoadMore;

  @override
  Widget build(BuildContext context) => _OverviewPanel(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            0,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final controls = _ProjectControls(
                projection: projection,
                language: language,
                searchController: searchController,
                commercialState: commercialState,
                dueState: dueState,
                paymentState: paymentState,
                activeFilterCount: activeFilterCount,
                onSearchChanged: onSearchChanged,
                onApplyFilters: onApplyFilters,
                onClearFilters: onClearFilters,
              );
              if (constraints.maxWidth < 760) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _text(language, 'overview_project_accounts'),
                      style: AppTypography.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    controls,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      _text(language, 'overview_project_accounts'),
                      style: AppTypography.titleLarge,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Flexible(flex: 2, child: controls),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _ProjectViewTabs(
          projection: projection,
          language: language,
          commercialState: commercialState,
          dueState: dueState,
          paymentState: paymentState,
          onApplyFilters: onApplyFilters,
        ),
        const Divider(height: 1),
        if (projection.projects.isEmpty)
          _ProjectEmptyState(
            language: language,
            hasFilter: projection.authorizedProjectCount > 0,
            onClear: onClearFilters,
          )
        else
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < 820
                ? Column(
                    children: [
                      for (final project in projection.projects)
                        _ProjectAccountCard(
                          project: project,
                          language: language,
                        ),
                    ],
                  )
                : _ProjectAccountsTable(
                    projects: projection.projects,
                    language: language,
                  ),
          ),
        const Divider(height: 1),
        _RegisterFooter(
          projection: projection,
          loadingMore: state.isLoadingMore,
          language: language,
          onLoadMore: onLoadMore,
        ),
      ],
    ),
  );
}

class _ProjectControls extends StatelessWidget {
  const _ProjectControls({
    required this.projection,
    required this.language,
    required this.searchController,
    required this.commercialState,
    required this.dueState,
    required this.paymentState,
    required this.activeFilterCount,
    required this.onSearchChanged,
    required this.onApplyFilters,
    required this.onClearFilters,
  });

  final YorksAccountsPortfolioProjection projection;
  final AppLanguage language;
  final TextEditingController searchController;
  final String? commercialState;
  final String? dueState;
  final String? paymentState;
  final int activeFilterCount;
  final ValueChanged<String> onSearchChanged;
  final YorksAccountsOverviewFilterCallback onApplyFilters;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: SizedBox(
          height: AppSpacing.minTapTarget,
          child: TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              hintText: _text(language, 'search'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              isDense: true,
            ),
          ),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Badge.count(
        count: activeFilterCount,
        isLabelVisible: activeFilterCount > 0,
        child: IconButton.outlined(
          tooltip: _text(language, 'filters'),
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            useSafeArea: true,
            isScrollControlled: true,
            builder: (_) => _OverviewFilterSheet(
              language: language,
              commercialState: commercialState,
              dueState: dueState,
              paymentState: paymentState,
              onApply: onApplyFilters,
              onClear: onClearFilters,
            ),
          ),
          icon: const Icon(Icons.filter_alt_outlined),
        ),
      ),
      if (projection.canExport) ...[
        const SizedBox(width: AppSpacing.sm),
        IconButton.outlined(
          tooltip: _text(language, 'export_excel'),
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            useSafeArea: true,
            isScrollControlled: true,
            builder: (_) => Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: YorksAccountsReportActions(
                kind: YorksAccountsReportKind.portfolio,
                language: language,
              ),
            ),
          ),
          icon: const Icon(Icons.download_outlined),
        ),
      ],
    ],
  );
}

enum _ProjectView { all, attention, dueSoon, overdue }

class _ProjectViewTabs extends StatelessWidget {
  const _ProjectViewTabs({
    required this.projection,
    required this.language,
    required this.commercialState,
    required this.dueState,
    required this.paymentState,
    required this.onApplyFilters,
  });

  final YorksAccountsPortfolioProjection projection;
  final AppLanguage language;
  final String? commercialState;
  final String? dueState;
  final String? paymentState;
  final YorksAccountsOverviewFilterCallback onApplyFilters;

  _ProjectView get selected => switch ((commercialState, dueState)) {
    ('action_required', _) => _ProjectView.attention,
    (_, 'due_soon') => _ProjectView.dueSoon,
    (_, 'overdue') => _ProjectView.overdue,
    _ => _ProjectView.all,
  };

  @override
  Widget build(BuildContext context) {
    final completePage =
        projection.projects.length == projection.filteredProjectCount;
    String count(Iterable<YorksAccountsPortfolioProject> values) {
      final amount = values.length;
      return completePage ? '$amount' : '$amount+';
    }

    final tabs = <(_ProjectView, String, String?)>[
      (
        _ProjectView.all,
        _text(language, 'overview_all_projects'),
        projection.filteredProjectCount.toString(),
      ),
      (
        _ProjectView.attention,
        _text(language, 'overview_attention'),
        count(projection.projects.where((item) => item.actionCount > 0)),
      ),
      (
        _ProjectView.dueSoon,
        _text(language, 'overview_due_soon'),
        count(projection.projects.where((item) => item.dueState == 'due_soon')),
      ),
      (
        _ProjectView.overdue,
        _text(language, 'overview_overdue'),
        count(projection.projects.where((item) => item.dueState == 'overdue')),
      ),
    ];
    return SizedBox(
      height: 46,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.lg),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final active = tab.$1 == selected;
          return InkWell(
            onTap: () {
              switch (tab.$1) {
                case _ProjectView.all:
                  onApplyFilters(
                    commercialState: null,
                    dueState: null,
                    paymentState: paymentState,
                  );
                case _ProjectView.attention:
                  onApplyFilters(
                    commercialState: 'action_required',
                    dueState: null,
                    paymentState: paymentState,
                  );
                case _ProjectView.dueSoon:
                  onApplyFilters(
                    commercialState: null,
                    dueState: 'due_soon',
                    paymentState: paymentState,
                  );
                case _ProjectView.overdue:
                  onApplyFilters(
                    commercialState: null,
                    dueState: 'overdue',
                    paymentState: paymentState,
                  );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: active ? AppColors.blue : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Center(
                child: Text(
                  '${tab.$2} (${tab.$3})',
                  style: AppTypography.labelLarge.copyWith(
                    color: active ? AppColors.blue : AppColors.muted,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProjectAccountsTable extends StatelessWidget {
  const _ProjectAccountsTable({required this.projects, required this.language});

  final List<YorksAccountsPortfolioProject> projects;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 1180),
      child: DataTable(
        headingRowHeight: 44,
        dataRowMinHeight: 68,
        dataRowMaxHeight: 76,
        horizontalMargin: AppSpacing.md,
        columnSpacing: AppSpacing.lg,
        headingRowColor: const WidgetStatePropertyAll(
          AppColors.surfaceContainerLow,
        ),
        columns: [
          DataColumn(label: Text(_text(language, 'project'))),
          DataColumn(label: Text(_text(language, 'client'))),
          DataColumn(label: Text(_text(language, 'contract'))),
          DataColumn(label: Text(_text(language, 'overview_confirmed_work'))),
          DataColumn(label: Text(_text(language, 'available'))),
          DataColumn(label: Text(_text(language, 'certified'))),
          DataColumn(label: Text(_text(language, 'still_due'))),
          DataColumn(label: Text(_text(language, 'overview_last_updated'))),
          DataColumn(label: Text(_text(language, 'office_status'))),
          const DataColumn(label: SizedBox.shrink()),
        ],
        rows: [
          for (final project in projects)
            DataRow(
              cells: [
                DataCell(
                  SizedBox(
                    width: 158,
                    child: _TwoLineText(
                      title: project.projectReference,
                      subtitle: project.projectName,
                      titleColor: AppColors.blue,
                    ),
                  ),
                  onTap: () => _openProject(context, project.projectId),
                ),
                DataCell(
                  SizedBox(
                    width: 92,
                    child: Text(
                      project.clientName ?? '—',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(_MoneyCell(value: project.contractBaseline)),
                DataCell(
                  _MoneyProgressCell(
                    value: project.confirmedEligible,
                    ratio: _ratio(
                      project.confirmedEligible,
                      project.contractBaseline,
                    ),
                    color: AppColors.blue,
                  ),
                ),
                DataCell(
                  _MoneyProgressCell(
                    value: project.availableToClaim,
                    ratio: _ratio(
                      project.availableToClaim,
                      project.contractBaseline,
                    ),
                    color: AppColors.success,
                  ),
                ),
                DataCell(
                  _MoneyProgressCell(
                    value: project.certified,
                    ratio: _ratio(project.certified, project.contractBaseline),
                    color: AppColors.blue,
                  ),
                ),
                DataCell(_MoneyCell(value: project.stillDue, danger: true)),
                DataCell(
                  _TwoLineText(
                    title: DateFormat(
                      'd MMM y',
                    ).format(project.latestActivityAt.toLocal()),
                    subtitle: DateFormat(
                      'HH:mm',
                    ).format(project.latestActivityAt.toLocal()),
                  ),
                ),
                DataCell(
                  _ProjectStatusPill(project: project, language: language),
                ),
                DataCell(_ProjectMenu(project: project, language: language)),
              ],
            ),
        ],
      ),
    ),
  );
}

class _MoneyCell extends StatelessWidget {
  const _MoneyCell({required this.value, this.danger = false});

  final YorksAccountsDecimal value;
  final bool danger;

  @override
  Widget build(BuildContext context) => Text(
    _compactMoney(value),
    style: AppTypography.labelLarge.copyWith(
      color: danger && !value.isZero ? AppColors.error : AppColors.ink,
    ),
  );
}

class _MoneyProgressCell extends StatelessWidget {
  const _MoneyProgressCell({
    required this.value,
    required this.ratio,
    required this.color,
  });

  final YorksAccountsDecimal value;
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 98,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_compactNumber(value), style: AppTypography.labelLarge),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 5,
                  color: color,
                  backgroundColor: AppColors.surfaceContainerHighest,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Text(_percent(ratio), style: AppTypography.labelSmall),
          ],
        ),
      ],
    ),
  );
}

class _ProjectAccountCard extends StatelessWidget {
  const _ProjectAccountCard({required this.project, required this.language});

  final YorksAccountsPortfolioProject project;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => _openProject(context, project.projectId),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _TwoLineText(
                  title: project.projectReference,
                  subtitle: project.projectName,
                  titleColor: AppColors.blue,
                ),
              ),
              _ProjectStatusPill(project: project, language: language),
              const SizedBox(width: AppSpacing.xs),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _MobileProgress(
            label: _text(language, 'overview_confirmed_work'),
            value: project.confirmedEligible,
            ratio: _ratio(project.confirmedEligible, project.contractBaseline),
            color: AppColors.blue,
          ),
          const SizedBox(height: AppSpacing.sm),
          _MobileProgress(
            label: _text(language, 'available'),
            value: project.availableToClaim,
            ratio: _ratio(project.availableToClaim, project.contractBaseline),
            color: AppColors.success,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _MiniValue(
                  label: _text(language, 'certified'),
                  value: _compactMoney(project.certified),
                ),
              ),
              Expanded(
                child: _MiniValue(
                  label: _text(language, 'still_due'),
                  value: _compactMoney(project.stillDue),
                  danger: !project.stillDue.isZero,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _MobileProgress extends StatelessWidget {
  const _MobileProgress({
    required this.label,
    required this.value,
    required this.ratio,
    required this.color,
  });

  final String label;
  final YorksAccountsDecimal value;
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 108, child: Text(label, style: AppTypography.labelSmall)),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            color: color,
            backgroundColor: AppColors.surfaceContainerHighest,
          ),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      SizedBox(
        width: 64,
        child: Text(
          _compactNumber(value),
          textAlign: TextAlign.end,
          style: AppTypography.labelSmall.copyWith(color: AppColors.ink),
        ),
      ),
    ],
  );
}

class _MiniValue extends StatelessWidget {
  const _MiniValue({
    required this.label,
    required this.value,
    this.danger = false,
  });

  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppTypography.labelSmall),
      const SizedBox(height: 3),
      Text(
        value,
        style: AppTypography.labelLarge.copyWith(
          color: danger ? AppColors.error : AppColors.ink,
        ),
      ),
    ],
  );
}

class _ProjectStatusPill extends StatelessWidget {
  const _ProjectStatusPill({required this.project, required this.language});

  final YorksAccountsPortfolioProject project;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final (label, color, background) = switch (project.dueState) {
      'overdue' => (
        _text(language, 'overview_overdue'),
        AppColors.error,
        AppColors.errorContainer,
      ),
      'due_soon' => (
        _text(language, 'overview_due_soon'),
        AppColors.warning,
        AppColors.warningContainer,
      ),
      _ when project.actionCount > 0 => (
        _text(language, 'overview_attention'),
        AppColors.warning,
        AppColors.warningContainer,
      ),
      _ => (
        _text(language, 'overview_on_track'),
        AppColors.success,
        AppColors.successContainer,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(color: color),
      ),
    );
  }
}

class _ProjectMenu extends StatelessWidget {
  const _ProjectMenu({required this.project, required this.language});

  final YorksAccountsPortfolioProject project;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: _text(language, 'action'),
    onSelected: (value) {
      switch (value) {
        case 'overview':
          _openProject(context, project.projectId);
        case 'invoices':
          context.go(
            RoutePaths.yorksV1ProjectAccountsInvoicesPath(project.projectId),
          );
        case 'supplier':
          context.go(
            RoutePaths.yorksV1ProjectAccountsSupplierBillsPath(
              project.projectId,
            ),
          );
      }
    },
    itemBuilder: (_) => [
      PopupMenuItem(
        value: 'overview',
        child: Text(_text(language, 'overview_open_account')),
      ),
      PopupMenuItem(
        value: 'invoices',
        child: Text(_text(language, 'invoices')),
      ),
      if (project.supplierReviewCount != null)
        PopupMenuItem(
          value: 'supplier',
          child: Text(_text(language, 'supplier_bills')),
        ),
    ],
  );
}

class _RegisterFooter extends StatelessWidget {
  const _RegisterFooter({
    required this.projection,
    required this.loadingMore,
    required this.language,
    required this.onLoadMore,
  });

  final YorksAccountsPortfolioProjection projection;
  final bool loadingMore;
  final AppLanguage language;
  final Future<bool> Function() onLoadMore;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '${_text(language, 'overview_showing')} ${projection.projects.length} ${_text(language, 'overview_of')} ${projection.filteredProjectCount}',
            style: AppTypography.bodySmall,
          ),
        ),
        if (projection.nextProjectId != null)
          OutlinedButton.icon(
            onPressed: loadingMore ? null : onLoadMore,
            icon: loadingMore
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.expand_more_rounded),
            label: Text(
              _text(language, loadingMore ? 'loading_more' : 'load_more'),
            ),
          ),
      ],
    ),
  );
}

class _OverviewRightRail extends StatelessWidget {
  const _OverviewRightRail({
    required this.projection,
    required this.language,
    required this.horizontal,
  });

  final YorksAccountsPortfolioProjection projection;
  final AppLanguage language;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final alerts = _AlertsCard(projection: projection, language: language);
    final recent = _RecentActivityCard(
      projection: projection,
      language: language,
    );
    if (horizontal) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: alerts),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: recent),
        ],
      );
    }
    return Column(
      children: [
        alerts,
        const SizedBox(height: AppSpacing.lg),
        recent,
      ],
    );
  }
}

class _AlertsCard extends StatelessWidget {
  const _AlertsCard({required this.projection, required this.language});

  final YorksAccountsPortfolioProjection projection;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => _OverviewPanel(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RailHeader(
          title: _text(language, 'overview_alerts'),
          action: _text(language, 'overview_view_all'),
          onTap: () => context.go(RoutePaths.yorksV1AccountsDueSchedule),
        ),
        const SizedBox(height: AppSpacing.md),
        if (projection.actionQueue.isEmpty)
          _SmallEmpty(
            icon: Icons.check_circle_outline_rounded,
            label: _text(language, 'overview_no_alerts'),
          )
        else
          for (final item in projection.actionQueue.take(5))
            _AlertRow(
              item: item,
              language: language,
              onTap: () => _openAction(context, item),
            ),
      ],
    ),
  );
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({
    required this.item,
    required this.language,
    required this.onTap,
  });

  final YorksAccountsActionItem item;
  final AppLanguage language;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = item.severity == 'critical'
        ? AppColors.error
        : item.severity == 'high'
        ? AppColors.warning
        : AppColors.blue;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            _SmallIcon(
              icon: _actionIcon(item.code),
              color: color,
              background: color.withValues(alpha: .09),
              size: 32,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                _actionLabel(language, item.code),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.inkSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _CountBadge(count: item.count, color: color),
          ],
        ),
      ),
    );
  }
}

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({required this.projection, required this.language});

  final YorksAccountsPortfolioProjection projection;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final projects = [...projection.projects]
      ..sort((a, b) => b.latestActivityAt.compareTo(a.latestActivityAt));
    return _OverviewPanel(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RailHeader(
            title: _text(language, 'overview_recent_activities'),
            action: _text(language, 'overview_view_all'),
            onTap: () => context.go(RoutePaths.yorksV1AccountsActivity),
          ),
          const SizedBox(height: AppSpacing.md),
          if (projects.isEmpty)
            _SmallEmpty(
              icon: Icons.history_rounded,
              label: _text(language, 'overview_no_activity'),
            )
          else
            for (final project in projects.take(4))
              InkWell(
                onTap: () => _openProject(context, project.projectId),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SmallIcon(
                        icon: Icons.history_rounded,
                        color: AppColors.blue,
                        background: AppColors.blueContainer,
                        size: 32,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _TwoLineText(
                          title: _text(language, 'overview_account_updated'),
                          subtitle:
                              '${project.projectReference} · ${DateFormat('d MMM · HH:mm').format(project.latestActivityAt.toLocal())}',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _ActionQueuesPanel extends StatelessWidget {
  const _ActionQueuesPanel({required this.projection, required this.language});

  final YorksAccountsPortfolioProjection projection;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, int>{};
    for (final item in projection.actionQueue) {
      grouped.update(
        item.code,
        (value) => value + item.count,
        ifAbsent: () => item.count,
      );
    }
    final queues = <_QueueData>[
      _QueueData(
        label: _text(language, 'available'),
        value: _compactMoney(projection.totals.availableToClaim),
        detail: _text(language, 'overview_ready_to_claim'),
        icon: Icons.account_balance_wallet_outlined,
        color: AppColors.success,
        route: RoutePaths.yorksV1AccountsClaims,
      ),
      for (final entry in grouped.entries.take(5))
        _QueueData(
          label: _actionLabel(language, entry.key),
          value: '${entry.value}',
          detail: _text(language, 'overview_items'),
          icon: _actionIcon(entry.key),
          color: _actionColor(entry.key),
          route: _officeRouteForAction(entry.key),
        ),
    ];
    return _OverviewPanel(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RailHeader(
            title: _text(language, 'overview_action_queues'),
            action: _text(language, 'overview_view_all_queues'),
            onTap: () => context.go(RoutePaths.yorksV1AccountsDueSchedule),
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1040
                  ? 6
                  : constraints.maxWidth >= 680
                  ? 3
                  : 2;
              final gap = AppSpacing.sm;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final queue in queues)
                    SizedBox(
                      width: width,
                      child: _QueueCard(
                        data: queue,
                        onTap: () => context.go(queue.route),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _QueueData {
  const _QueueData({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
    required this.route,
  });

  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;
  final String route;
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({required this.data, required this.onTap});

  final _QueueData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    child: Container(
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SmallIcon(
            icon: data.icon,
            color: data.color,
            background: data.color.withValues(alpha: .09),
            size: 32,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelSmall,
                ),
                const SizedBox(height: 2),
                Text(data.value, style: AppTypography.titleMedium),
                Text(data.detail, style: AppTypography.labelSmall),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _OverviewFilterSheet extends StatefulWidget {
  const _OverviewFilterSheet({
    required this.language,
    required this.commercialState,
    required this.dueState,
    required this.paymentState,
    required this.onApply,
    required this.onClear,
  });

  final AppLanguage language;
  final String? commercialState;
  final String? dueState;
  final String? paymentState;
  final YorksAccountsOverviewFilterCallback onApply;
  final VoidCallback onClear;

  @override
  State<_OverviewFilterSheet> createState() => _OverviewFilterSheetState();
}

class _OverviewFilterSheetState extends State<_OverviewFilterSheet> {
  late String? commercialState = widget.commercialState;
  late String? dueState = widget.dueState;
  late String? paymentState = widget.paymentState;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.lg,
      MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _text(widget.language, 'filters'),
                style: AppTypography.titleLarge,
              ),
            ),
            IconButton(
              onPressed: Navigator.of(context).pop,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _FilterField(
          label: _text(widget.language, 'commercial_control'),
          value: commercialState,
          values: const ['active', 'not_initialized', 'action_required'],
          language: widget.language,
          onChanged: (value) => setState(() => commercialState = value),
        ),
        const SizedBox(height: AppSpacing.md),
        _FilterField(
          label: _text(widget.language, 'still_due'),
          value: dueState,
          values: const ['current', 'due_soon', 'overdue'],
          language: widget.language,
          onChanged: (value) => setState(() => dueState = value),
        ),
        const SizedBox(height: AppSpacing.md),
        _FilterField(
          label: _text(widget.language, 'paid'),
          value: paymentState,
          values: const ['unpaid', 'partially_paid', 'paid'],
          language: widget.language,
          onChanged: (value) => setState(() => paymentState = value),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: () {
            widget.onApply(
              commercialState: commercialState,
              dueState: dueState,
              paymentState: paymentState,
            );
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.check_rounded),
          label: Text(_text(widget.language, 'apply_filters')),
        ),
        TextButton(
          onPressed: () {
            widget.onClear();
            Navigator.of(context).pop();
          },
          child: Text(_text(widget.language, 'clear')),
        ),
      ],
    ),
  );
}

class _FilterField extends StatelessWidget {
  const _FilterField({
    required this.label,
    required this.value,
    required this.values,
    required this.language,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<String> values;
  final AppLanguage language;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      DropdownMenuItem(value: null, child: Text(_text(language, 'all'))),
      for (final value in values)
        DropdownMenuItem(
          value: value,
          child: Text(_wireLabel(language, value)),
        ),
    ],
    onChanged: onChanged,
  );
}

class _OverviewInitialState extends StatelessWidget {
  const _OverviewInitialState({
    required this.status,
    required this.language,
    required this.onRetry,
  });

  final YorksAccountsViewStatus status;
  final AppLanguage language;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (status == YorksAccountsViewStatus.loading ||
        status == YorksAccountsViewStatus.idle) {
      return const _OverviewSkeleton();
    }
    final key = switch (status) {
      YorksAccountsViewStatus.offline => 'offline',
      YorksAccountsViewStatus.forbidden => 'forbidden',
      YorksAccountsViewStatus.sessionExpired => 'session_expired',
      _ => 'load_failed',
    };
    return _OverviewPanel(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.massive),
        child: Column(
          children: [
            const _SmallIcon(
              icon: Icons.account_balance_wallet_outlined,
              color: AppColors.muted,
              background: AppColors.surfaceContainer,
              size: 52,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(_text(language, key), style: AppTypography.titleLarge),
            if (status != YorksAccountsViewStatus.forbidden &&
                status != YorksAccountsViewStatus.sessionExpired) ...[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(_text(language, 'retry')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OverviewSkeleton extends StatelessWidget {
  const _OverviewSkeleton();

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('accounts-overview-skeleton'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          for (var index = 0; index < 5; index++)
            const SizedBox(width: 190, height: 148, child: _SkeletonBlock()),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
      const SizedBox(height: 520, child: _SkeletonBlock()),
    ],
  );
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock();

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      border: Border.all(color: AppColors.line),
    ),
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Align(
      alignment: Alignment.topLeft,
      child: Container(
        width: 92,
        height: 12,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        ),
      ),
    ),
  );
}

class _OverviewRefreshNotice extends StatelessWidget {
  const _OverviewRefreshNotice({required this.language, required this.onRetry});

  final AppLanguage language;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    decoration: BoxDecoration(
      color: AppColors.warningContainer,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      border: Border.all(color: AppColors.warning.withValues(alpha: .25)),
    ),
    child: Row(
      children: [
        const Icon(Icons.sync_problem_rounded, color: AppColors.warning),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            _text(language, 'overview_refresh_failed'),
            style: AppTypography.bodySmall.copyWith(color: AppColors.ink),
          ),
        ),
        TextButton(onPressed: onRetry, child: Text(_text(language, 'retry'))),
      ],
    ),
  );
}

class _ProjectEmptyState extends StatelessWidget {
  const _ProjectEmptyState({
    required this.language,
    required this.hasFilter,
    required this.onClear,
  });

  final AppLanguage language;
  final bool hasFilter;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.massive),
    child: Column(
      children: [
        const Icon(Icons.folder_off_outlined, color: AppColors.muted, size: 36),
        const SizedBox(height: AppSpacing.md),
        Text(
          _text(language, hasFilter ? 'no_results' : 'no_projects'),
          style: AppTypography.titleSmall,
        ),
        if (hasFilter) ...[
          const SizedBox(height: AppSpacing.md),
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.filter_alt_off_outlined),
            label: Text(_text(language, 'clear')),
          ),
        ],
      ],
    ),
  );
}

class _OverviewPanel extends StatelessWidget {
  const _OverviewPanel({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      border: Border.all(color: AppColors.line),
      boxShadow: const [
        BoxShadow(
          color: AppColors.shadow,
          blurRadius: 16,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    ),
  );
}

class _SmallIcon extends StatelessWidget {
  const _SmallIcon({
    required this.icon,
    required this.color,
    required this.background,
    this.size = 38,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Icon(icon, color: color, size: size * .5),
  );
}

class _RailHeader extends StatelessWidget {
  const _RailHeader({
    required this.title,
    required this.action,
    required this.onTap,
  });

  final String title;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(title, style: AppTypography.titleSmall)),
      TextButton(onPressed: onTap, child: Text(action)),
    ],
  );
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 28),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
    ),
    child: Text(
      '$count',
      textAlign: TextAlign.center,
      style: AppTypography.labelSmall.copyWith(color: color),
    ),
  );
}

class _SmallEmpty extends StatelessWidget {
  const _SmallEmpty({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
    child: Column(
      children: [
        Icon(icon, color: AppColors.muted, size: 28),
        const SizedBox(height: AppSpacing.sm),
        Text(
          label,
          style: AppTypography.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _TwoLineText extends StatelessWidget {
  const _TwoLineText({
    required this.title,
    required this.subtitle,
    this.titleColor,
  });

  final String title;
  final String subtitle;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelLarge.copyWith(color: titleColor),
      ),
      if (subtitle.isNotEmpty)
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelSmall,
        ),
    ],
  );
}

void _openProject(BuildContext context, String projectId) =>
    context.go(RoutePaths.yorksV1ProjectAccountsOverviewPath(projectId));

void _openAction(BuildContext context, YorksAccountsActionItem item) {
  final route = item.code == 'supplier_match_review'
      ? RoutePaths.yorksV1ProjectAccountsSupplierBillsPath(item.projectId)
      : item.code == 'pdc_action_required'
      ? RoutePaths.yorksV1ProjectAccountsReceiptsPdcPath(item.projectId)
      : RoutePaths.yorksV1ProjectAccountsInvoicesPath(item.projectId);
  context.go(route);
}

String _officeRouteForAction(String code) => code == 'supplier_match_review'
    ? RoutePaths.yorksV1AccountsSupplierBills
    : code == 'pdc_action_required'
    ? RoutePaths.yorksV1AccountsClientPayments
    : RoutePaths.yorksV1AccountsClaims;

IconData _actionIcon(String code) => switch (code) {
  'overdue_invoice' => Icons.receipt_long_outlined,
  'pdc_action_required' => Icons.account_balance_wallet_outlined,
  'supplier_match_review' => Icons.rule_folder_outlined,
  'returned_for_correction' => Icons.assignment_return_outlined,
  'due_soon_invoice' => Icons.event_outlined,
  _ => Icons.notification_important_outlined,
};

Color _actionColor(String code) => switch (code) {
  'overdue_invoice' => AppColors.error,
  'pdc_action_required' => AppColors.warning,
  'supplier_match_review' => AppColors.purple,
  'returned_for_correction' => AppColors.warning,
  _ => AppColors.blue,
};

String _actionLabel(AppLanguage language, String code) {
  final key = 'overview_action_$code';
  final localized = _text(language, key);
  return localized == key ? _wireFallback(code) : localized;
}

String _wireLabel(AppLanguage language, String value) {
  final key = 'status_$value';
  final localized = _text(language, key);
  return localized == key ? _wireFallback(value) : localized;
}

String _wireFallback(String value) {
  final normalized = value.replaceAll('_', ' ').trim();
  if (normalized.isEmpty) return '—';
  return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
}

String _text(AppLanguage language, String key) =>
    YorksV1AccountsStrings.text(language, key);

double _decimalDouble(YorksAccountsDecimal value) =>
    double.tryParse(value.canonicalText) ?? 0;

double _ratio(YorksAccountsDecimal value, YorksAccountsDecimal baseline) {
  final denominator = _decimalDouble(baseline);
  if (denominator <= 0) return 0;
  return (_decimalDouble(value) / denominator).clamp(0.0, 1.0);
}

/// A display share: at most one decimal place, never rounded to a value the
/// data does not support (a small share is not "0%", an incomplete one is not
/// "100%"). Exact amounts stay in the money figures beside it.
String _percent(double value) {
  final bounded = value.clamp(0.0, 1.0) * 100;
  if (bounded == 0) return '0%';
  if (bounded == 100) return '100%';
  if (bounded < 0.1) return '<0.1%';
  if (bounded > 99.9) return '>99.9%';
  final rounded = (bounded * 10).round() / 10;
  final text = rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);
  return '$text%';
}

String _compactNumber(YorksAccountsDecimal value) =>
    NumberFormat.compact(locale: 'en').format(_decimalDouble(value));

String _compactMoney(YorksAccountsDecimal value) =>
    'AED ${_compactNumber(value)}';

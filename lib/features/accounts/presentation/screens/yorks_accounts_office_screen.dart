import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/constants.dart';
import '../../../../shared/models/analytics_event.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_accounts_strings.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/services/analytics_service.dart';
import '../../application/accounts_controller.dart';
import '../../application/accounts_office_controller.dart';
import '../../application/accounts_office_providers.dart';
import '../../domain/accounts_decimal.dart';
import '../../domain/accounts_office_models.dart';
import '../../domain/accounts_records_models.dart';
import '../widgets/yorks_accounts_records_views.dart';

class YorksAccountsOfficeScreen extends ConsumerStatefulWidget {
  const YorksAccountsOfficeScreen({super.key, required this.section});

  final YorksAccountsOfficeSection section;

  @override
  ConsumerState<YorksAccountsOfficeScreen> createState() =>
      _YorksAccountsOfficeScreenState();
}

class _YorksAccountsOfficeScreenState
    extends ConsumerState<YorksAccountsOfficeScreen> {
  final _searchController = TextEditingController();
  Timer? _searchTimer;
  String? _status;
  YorksAccountsOfficeSection? _trackedSection;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreAndLoad());
  }

  @override
  void didUpdateWidget(covariant YorksAccountsOfficeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section) {
      _searchTimer?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreAndLoad());
    }
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  YorksAccountsOfficeFilters get _filters => YorksAccountsOfficeFilters(
    search: _searchController.text,
    status: _status,
  );

  void _restoreAndLoad() {
    if (!mounted) return;
    final stored = ref
        .read(yorksAccountsOfficeControllerProvider(widget.section))
        .filters;
    _searchController.text = stored.search ?? '';
    setState(() => _status = stored.status);
    if (_trackedSection != widget.section) {
      _trackedSection = widget.section;
      ref
          .read(analyticsServiceProvider)
          .capture(
            AnalyticsEvent.accountsWorkspaceViewed,
            properties: {
              AnalyticsProperty.source: 'accounts_office',
              AnalyticsProperty.entryPoint: widget.section.wireValue,
            },
          );
    }
    _load();
  }

  void _load() => ref
      .read(yorksAccountsOfficeControllerProvider(widget.section).notifier)
      .load(_filters);

  void _searchChanged(String _) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 320), () {
      _trackFilters();
      _load();
    });
  }

  void _statusChanged(String? value) {
    setState(() => _status = value);
    _trackFilters();
    _load();
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() => _status = null);
    _trackFilters();
    _load();
  }

  void _trackFilters() {
    final hasSearch = _searchController.text.trim().isNotEmpty;
    final hasStatus = _status != null;
    ref
        .read(analyticsServiceProvider)
        .capture(
          AnalyticsEvent.accountsFilterChanged,
          properties: {
            AnalyticsProperty.source: 'accounts_office',
            AnalyticsProperty.entryPoint: widget.section.wireValue,
            AnalyticsProperty.listFilter: hasSearch && hasStatus
                ? 'multiple'
                : hasSearch
                ? 'search'
                : hasStatus
                ? 'status'
                : 'none',
          },
        );
  }

  void _openRecord(YorksAccountsOfficeItem item) {
    ref
        .read(analyticsServiceProvider)
        .capture(
          AnalyticsEvent.accountsRecordOpened,
          properties: {
            AnalyticsProperty.source: 'accounts_office',
            AnalyticsProperty.entryPoint: widget.section.wireValue,
            AnalyticsProperty.objectType: item.recordKind,
            AnalyticsProperty.recordState: item.status,
          },
        );
    context.go(yorksAccountsOfficeItemRoute(widget.section, item));
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final state = ref.watch(
      yorksAccountsOfficeControllerProvider(widget.section),
    );
    final config = _OfficeSectionConfig.forSection(widget.section);
    final projection = state.projection;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < AppSpacing.compactBreakpoint;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: RefreshIndicator(
        onRefresh: () => ref
            .read(
              yorksAccountsOfficeControllerProvider(widget.section).notifier,
            )
            .load(_filters),
        child: CustomScrollView(
          key: PageStorageKey('accounts-office-${widget.section.wireValue}'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                compact ? AppSpacing.mobileScreenHorizontal : AppSpacing.xxl,
                compact ? AppSpacing.mobileScreenVertical : AppSpacing.xxl,
                compact ? AppSpacing.mobileScreenHorizontal : AppSpacing.xxl,
                AppSpacing.colossal,
              ),
              sliver: SliverList.list(
                children: [
                  _OfficeHeader(
                    config: config,
                    language: language,
                    compact: compact,
                    onOpenProjects: () =>
                        context.go(RoutePaths.yorksV1AccountsProjects),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (projection != null)
                    _OfficeSummaryCards(
                      section: widget.section,
                      projection: projection,
                      language: language,
                    )
                  else if (state.status == YorksAccountsViewStatus.loading)
                    const _OfficeLoadingCards(),
                  const SizedBox(height: AppSpacing.lg),
                  _OfficeFilterBar(
                    section: widget.section,
                    language: language,
                    controller: _searchController,
                    status: _status,
                    statuses: config.statuses,
                    onSearchChanged: _searchChanged,
                    onStatusChanged: _statusChanged,
                    onClear: _clearFilters,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _OfficeRegister(
                    section: widget.section,
                    state: state,
                    language: language,
                    onRetry: _load,
                    onOpenItem: _openRecord,
                    onLoadMore: () => ref
                        .read(
                          yorksAccountsOfficeControllerProvider(
                            widget.section,
                          ).notifier,
                        )
                        .loadMore(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class YorksAccountsReportsScreen extends ConsumerWidget {
  const YorksAccountsReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final compact = MediaQuery.sizeOf(context).width < 720;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          compact ? AppSpacing.mobileScreenHorizontal : AppSpacing.xxl,
          compact ? AppSpacing.mobileScreenVertical : AppSpacing.xxl,
          compact ? AppSpacing.mobileScreenHorizontal : AppSpacing.xxl,
          AppSpacing.colossal,
        ),
        children: [
          _OfficeHeader(
            config: const _OfficeSectionConfig(
              titleKey: 'office_reports_title',
              bodyKey: 'office_reports_body',
              icon: Icons.analytics_outlined,
              color: AppColors.purple,
            ),
            language: language,
            compact: compact,
            onOpenProjects: () =>
                context.go(RoutePaths.yorksV1AccountsProjects),
          ),
          const SizedBox(height: AppSpacing.lg),
          _OfficePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _OfficePanelTitle(
                  icon: Icons.account_balance_wallet_outlined,
                  title: _t(language, 'office_portfolio_report'),
                  subtitle: _t(language, 'office_data_current'),
                ),
                const SizedBox(height: AppSpacing.lg),
                YorksAccountsReportActions(
                  kind: YorksAccountsReportKind.portfolio,
                  language: language,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _OfficePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _OfficePanelTitle(
                  icon: Icons.folder_copy_outlined,
                  title: _t(language, 'office_project_reports'),
                  subtitle: _t(language, 'office_project_reports_body'),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: () =>
                      context.go(RoutePaths.yorksV1AccountsProjects),
                  icon: const Icon(Icons.folder_open_outlined),
                  label: Text(_t(language, 'office_open_project')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfficeHeader extends StatelessWidget {
  const _OfficeHeader({
    required this.config,
    required this.language,
    required this.compact,
    required this.onOpenProjects,
  });

  final _OfficeSectionConfig config;
  final AppLanguage language;
  final bool compact;
  final VoidCallback onOpenProjects;

  @override
  Widget build(BuildContext context) {
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t(language, config.titleKey),
          style: compact
              ? AppTypography.headlineSmall
              : AppTypography.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _t(language, config.bodyKey),
          style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
        ),
      ],
    );
    final action = FilledButton.icon(
      onPressed: onOpenProjects,
      icon: const Icon(Icons.folder_open_outlined),
      label: Text(_t(language, 'office_open_project')),
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          copy,
          const SizedBox(height: AppSpacing.md),
          action,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: copy),
        const SizedBox(width: AppSpacing.lg),
        action,
      ],
    );
  }
}

class _OfficeSummaryCards extends StatelessWidget {
  const _OfficeSummaryCards({
    required this.section,
    required this.projection,
    required this.language,
  });

  final YorksAccountsOfficeSection section;
  final YorksAccountsOfficeProjection projection;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final summary = projection.summary;
    final currency = projection.items.firstOrNull?.currencyCode ?? 'AED';
    final items = _summaryMetrics(
      section: section,
      summary: summary,
      total: projection.total,
      currency: currency,
      language: language,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1080
            ? 4
            : constraints.maxWidth >= 680
            ? 3
            : 2;
        final spacing = constraints.maxWidth < 680
            ? AppSpacing.sm
            : AppSpacing.md;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: _OfficeMetricCard(item: item, language: language),
              ),
          ],
        );
      },
    );
  }
}

class _OfficeMetric {
  const _OfficeMetric(
    this.labelKey,
    this.value,
    this.icon,
    this.color, {
    this.caption,
  });
  final String labelKey;
  final String value;
  final IconData icon;
  final Color color;
  final String? caption;
}

List<_OfficeMetric> _summaryMetrics({
  required YorksAccountsOfficeSection section,
  required YorksAccountsOfficeSummary summary,
  required int total,
  required String currency,
  required AppLanguage language,
}) => switch (section) {
  YorksAccountsOfficeSection.claims => [
    _OfficeMetric(
      'claimed',
      _money(currency, summary.amount),
      Icons.request_quote_outlined,
      AppColors.blue,
      caption: '$total ${_t(language, 'office_records').toLowerCase()}',
    ),
    _OfficeMetric(
      'certified',
      _money(currency, summary.secondaryAmount),
      Icons.verified_outlined,
      AppColors.success,
    ),
    _OfficeMetric(
      'office_uncertified',
      _money(currency, summary.balanceAmount),
      Icons.difference_outlined,
      AppColors.purple,
    ),
    _OfficeMetric(
      'office_needs_action',
      '${summary.actionCount}',
      Icons.notification_important_outlined,
      AppColors.error,
    ),
  ],
  YorksAccountsOfficeSection.clientPayments => [
    _OfficeMetric(
      'office_records',
      '$total',
      Icons.receipt_long_outlined,
      AppColors.blue,
    ),
    _OfficeMetric(
      'office_recorded_value',
      _money(currency, summary.amount),
      Icons.account_balance_wallet_outlined,
      AppColors.success,
    ),
    _OfficeMetric(
      'office_needs_action',
      '${summary.actionCount}',
      Icons.notification_important_outlined,
      AppColors.warning,
    ),
  ],
  YorksAccountsOfficeSection.supplierBills => [
    _OfficeMetric(
      'total_incl_vat',
      _money(currency, summary.amount),
      Icons.receipt_long_outlined,
      AppColors.blue,
      caption: '$total ${_t(language, 'supplier_bills').toLowerCase()}',
    ),
    _OfficeMetric(
      'paid_till_date',
      _money(currency, summary.secondaryAmount),
      Icons.check_circle_outline_rounded,
      AppColors.success,
    ),
    _OfficeMetric(
      'still_due',
      _money(currency, summary.balanceAmount),
      Icons.schedule_outlined,
      AppColors.purple,
    ),
    _OfficeMetric(
      'office_needs_action',
      '${summary.actionCount}',
      Icons.notification_important_outlined,
      AppColors.warning,
    ),
  ],
  YorksAccountsOfficeSection.dueSchedule => [
    _OfficeMetric(
      'office_scheduled_value',
      _money(currency, summary.amount),
      Icons.calendar_month_outlined,
      AppColors.blue,
      caption: '$total ${_t(language, 'office_records').toLowerCase()}',
    ),
    _OfficeMetric(
      'office_settled_value',
      _money(currency, summary.secondaryAmount),
      Icons.task_alt_outlined,
      AppColors.success,
    ),
    _OfficeMetric(
      'still_due',
      _money(currency, summary.balanceAmount),
      Icons.payments_outlined,
      AppColors.purple,
    ),
    _OfficeMetric(
      'office_needs_action',
      '${summary.actionCount}',
      Icons.notification_important_outlined,
      AppColors.error,
    ),
  ],
  _ => [
    _OfficeMetric(
      'office_records',
      '$total',
      Icons.inventory_2_outlined,
      AppColors.blue,
    ),
  ],
};

class _OfficeMetricCard extends StatelessWidget {
  const _OfficeMetricCard({required this.item, required this.language});
  final _OfficeMetric item;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => _OfficePanel(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: SizedBox(
      height: 116,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Icon(item.icon, color: item.color, size: 19),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _t(language, item.labelKey),
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
            child: Text(item.value, style: AppTypography.headlineSmall),
          ),
          if (item.caption case final caption?)
            Text(caption, style: AppTypography.labelSmall),
          const Spacer(),
          ExcludeSemantics(
            child: SizedBox(
              width: double.infinity,
              height: 16,
              child: CustomPaint(
                painter: _OfficePositionPainter(color: item.color),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _OfficeLoadingCards extends StatelessWidget {
  const _OfficeLoadingCards();

  @override
  Widget build(BuildContext context) => const Wrap(
    spacing: AppSpacing.md,
    runSpacing: AppSpacing.md,
    children: [
      _OfficeSkeletonBlock(width: 220, height: 148),
      _OfficeSkeletonBlock(width: 220, height: 148),
      _OfficeSkeletonBlock(width: 220, height: 148),
      _OfficeSkeletonBlock(width: 220, height: 148),
    ],
  );
}

class _OfficeSkeletonBlock extends StatelessWidget {
  const _OfficeSkeletonBlock({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
    ),
  );
}

class _OfficePositionPainter extends CustomPainter {
  const _OfficePositionPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(0, size.height - 2);
    for (var index = 1; index <= 7; index++) {
      final t = index / 7;
      final baseline = size.height - 2 - (size.height * .72 * t);
      path.lineTo(
        size.width * t,
        (baseline + (index.isEven ? 2 : -1)).clamp(1, size.height),
      );
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _OfficePositionPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _OfficeFilterBar extends StatelessWidget {
  const _OfficeFilterBar({
    required this.section,
    required this.language,
    required this.controller,
    required this.status,
    required this.statuses,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onClear,
  });

  final YorksAccountsOfficeSection section;
  final AppLanguage language;
  final TextEditingController controller;
  final String? status;
  final List<String> statuses;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onStatusChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final primaryStatuses = _OfficeSectionConfig.forSection(
      section,
    ).primaryStatuses;
    return _OfficePanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (primaryStatuses.isNotEmpty) ...[
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                children: [
                  _OfficeStatusTab(
                    label: _t(language, 'office_all_records'),
                    selected: status == null,
                    onTap: () => onStatusChanged(null),
                  ),
                  for (final value in primaryStatuses)
                    _OfficeStatusTab(
                      label: _status(language, value),
                      selected: status == value,
                      onTap: () => onStatusChanged(value),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final search = TextField(
                  controller: controller,
                  onChanged: onSearchChanged,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: _t(language, 'office_search'),
                  ),
                );
                final statusFilter = DropdownButtonFormField<String>(
                  initialValue: status,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.filter_alt_outlined),
                  ),
                  items: [
                    DropdownMenuItem<String>(
                      value: null,
                      child: Text(_t(language, 'office_all_statuses')),
                    ),
                    for (final value in statuses)
                      DropdownMenuItem(
                        value: value,
                        child: Text(_status(language, value)),
                      ),
                  ],
                  onChanged: onStatusChanged,
                );
                final clear = IconButton.outlined(
                  tooltip: _t(language, 'clear'),
                  onPressed: onClear,
                  icon: const Icon(Icons.filter_alt_off_outlined),
                );
                if (constraints.maxWidth < 720) {
                  return Column(
                    children: [
                      search,
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(child: statusFilter),
                          const SizedBox(width: AppSpacing.sm),
                          clear,
                        ],
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(flex: 2, child: search),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: statusFilter),
                    const SizedBox(width: AppSpacing.sm),
                    clear,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OfficeStatusTab extends StatelessWidget {
  const _OfficeStatusTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      alignment: Alignment.center,
      margin: const EdgeInsetsDirectional.only(end: AppSpacing.lg),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: selected ? AppColors.blue : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Text(
        label,
        style: AppTypography.labelMedium.copyWith(
          color: selected ? AppColors.blue : AppColors.muted,
        ),
      ),
    ),
  );
}

class _OfficeRegister extends StatelessWidget {
  const _OfficeRegister({
    required this.section,
    required this.state,
    required this.language,
    required this.onRetry,
    required this.onOpenItem,
    required this.onLoadMore,
  });

  final YorksAccountsOfficeSection section;
  final YorksAccountsOfficeState state;
  final AppLanguage language;
  final VoidCallback onRetry;
  final ValueChanged<YorksAccountsOfficeItem> onOpenItem;
  final Future<bool> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    final projection = state.projection;
    if (projection == null) {
      if (state.status == YorksAccountsViewStatus.loading ||
          state.status == YorksAccountsViewStatus.idle) {
        return const _OfficePanel(
          child: SizedBox(
            height: 260,
            child: Center(child: CircularProgressIndicator()),
          ),
        );
      }
      return _OfficeStatePanel(
        status: state.status,
        language: language,
        onRetry: onRetry,
      );
    }
    if (projection.items.isEmpty) {
      return _OfficePanel(
        child: SizedBox(
          height: 260,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.inbox_outlined,
                  color: AppColors.muted,
                  size: 38,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  _t(language, 'office_no_records'),
                  style: AppTypography.titleSmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return _OfficePanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.status == YorksAccountsViewStatus.loading)
            const LinearProgressIndicator(minHeight: 3),
          if (state.error != null &&
              state.status != YorksAccountsViewStatus.loading) ...[
            _OfficeRefreshError(language: language, onRetry: onRetry),
            const Divider(height: 1),
          ],
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _t(language, 'office_records'),
                    style: AppTypography.titleMedium,
                  ),
                ),
                Text(
                  '${projection.items.length} / ${projection.total}',
                  style: AppTypography.bodySmall,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < 820
                ? Column(
                    children: [
                      for (final item in projection.items)
                        _OfficeRecordCard(
                          item: item,
                          language: language,
                          onTap: () => onOpenItem(item),
                        ),
                    ],
                  )
                : _OfficeRecordsTable(
                    items: projection.items,
                    language: language,
                    section: section,
                    onOpenItem: onOpenItem,
                  ),
          ),
          if (projection.hasMore) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Center(
                child: OutlinedButton.icon(
                  onPressed: state.isLoadingMore ? null : onLoadMore,
                  icon: state.isLoadingMore
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more_rounded),
                  label: Text(_t(language, 'office_load_more')),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OfficeRefreshError extends StatelessWidget {
  const _OfficeRefreshError({required this.language, required this.onRetry});

  final AppLanguage language;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: ColoredBox(
      color: AppColors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.error,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                _t(language, 'load_failed'),
                style: AppTypography.bodySmall.copyWith(color: AppColors.error),
              ),
            ),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(_t(language, 'retry')),
            ),
          ],
        ),
      ),
    ),
  );
}

class _OfficeRecordsTable extends StatelessWidget {
  const _OfficeRecordsTable({
    required this.items,
    required this.language,
    required this.section,
    required this.onOpenItem,
  });

  final List<YorksAccountsOfficeItem> items;
  final AppLanguage language;
  final YorksAccountsOfficeSection section;
  final ValueChanged<YorksAccountsOfficeItem> onOpenItem;

  @override
  Widget build(BuildContext context) {
    final columns = _officeColumns(section, language);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth:
              columns.fold<double>(72, (sum, column) => sum + column.width) +
              AppSpacing.xxl,
        ),
        child: DataTable(
          headingRowHeight: 44,
          dataRowMinHeight: 64,
          dataRowMaxHeight: 74,
          horizontalMargin: AppSpacing.md,
          columnSpacing: AppSpacing.lg,
          headingRowColor: const WidgetStatePropertyAll(
            AppColors.surfaceContainerLow,
          ),
          columns: [
            for (final column in columns)
              DataColumn(
                numeric: column.numeric,
                label: Text(_t(language, column.labelKey)),
              ),
            const DataColumn(label: SizedBox.shrink()),
          ],
          rows: [
            for (final item in items)
              DataRow(
                onSelectChanged: (_) => onOpenItem(item),
                cells: [
                  for (final column in columns)
                    DataCell(
                      SizedBox(
                        width: column.width,
                        child: column.builder(item),
                      ),
                    ),
                  DataCell(
                    IconButton(
                      tooltip: _t(language, 'office_open_project'),
                      onPressed: () => onOpenItem(item),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _OfficeRecordCard extends StatelessWidget {
  const _OfficeRecordCard({
    required this.item,
    required this.language,
    required this.onTap,
  });

  final YorksAccountsOfficeItem item;
  final AppLanguage language;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final section = _sectionForRecordKind(item.recordKind);
    final fields = _officeCardFields(section, item, language);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _OfficeTwoLine(
                    title: item.reference,
                    subtitle: '${item.projectReference} · ${item.projectName}',
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _OfficeStatusBadge(item: item, language: language),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final fieldWidth = (constraints.maxWidth - AppSpacing.md) / 2;
                return Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: [
                    for (final field in fields)
                      SizedBox(
                        width: fieldWidth,
                        child: _OfficeMiniField(
                          label: _t(language, field.labelKey),
                          value: field.value,
                          danger: field.danger,
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  _t(language, 'office_open_project'),
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.blue,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.blue,
                  size: 20,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

typedef _OfficeCellBuilder = Widget Function(YorksAccountsOfficeItem item);

class _OfficeColumn {
  const _OfficeColumn({
    required this.labelKey,
    required this.width,
    required this.builder,
    this.numeric = false,
  });

  final String labelKey;
  final double width;
  final bool numeric;
  final _OfficeCellBuilder builder;
}

class _OfficeCardField {
  const _OfficeCardField(this.labelKey, this.value, {this.danger = false});

  final String labelKey;
  final String value;
  final bool danger;
}

List<_OfficeColumn> _officeColumns(
  YorksAccountsOfficeSection section,
  AppLanguage language,
) {
  _OfficeColumn text(
    String label,
    double width,
    String Function(YorksAccountsOfficeItem) value,
  ) => _OfficeColumn(
    labelKey: label,
    width: width,
    builder: (item) => _officeText(value(item)),
  );
  _OfficeColumn money(
    String label,
    double width,
    YorksAccountsDecimal? Function(YorksAccountsOfficeItem) value, {
    bool danger = false,
  }) => _OfficeColumn(
    labelKey: label,
    width: width,
    numeric: true,
    builder: (item) => _officeMoney(item, value(item), danger: danger),
  );
  final reference = _OfficeColumn(
    labelKey: 'office_reference',
    width: 154,
    builder: (item) => _OfficeTwoLine(
      title: item.reference,
      subtitle: item.secondaryReference ?? '—',
    ),
  );
  final project = _OfficeColumn(
    labelKey: 'project',
    width: 174,
    builder: (item) => _OfficeTwoLine(
      title: item.projectReference,
      subtitle: item.projectName,
    ),
  );
  final status = _OfficeColumn(
    labelKey: 'office_status',
    width: 132,
    builder: (item) => Align(
      alignment: AlignmentDirectional.centerStart,
      child: _OfficeStatusBadge(item: item, language: language),
    ),
  );
  final eventDate = text(
    'office_date',
    96,
    (item) => _dateText(item.eventDate, language),
  );
  final dueDate = text(
    'office_due_date',
    96,
    (item) => _dateText(item.dueDate, language),
  );
  return switch (section) {
    YorksAccountsOfficeSection.claims => [
      reference,
      project,
      text('client', 130, (item) => item.party ?? '—'),
      text('office_period', 96, (item) => _dateText(item.eventDate, language)),
      money('claimed', 126, (item) => item.amount),
      money('certified', 126, (item) => item.secondaryAmount),
      money('still_due', 126, (item) => item.balanceAmount, danger: true),
      dueDate,
      status,
    ],
    YorksAccountsOfficeSection.clientPayments => [
      reference,
      text(
        'office_record_type',
        108,
        (item) => _recordType(language, item.recordKind),
      ),
      project,
      text('client', 128, (item) => item.party ?? '—'),
      money('office_amount', 126, (item) => item.amount),
      eventDate,
      dueDate,
      text(
        'office_bank_method',
        142,
        (item) =>
            _metadataText(item, 'bank_name') ??
            _metadataText(item, 'payment_method') ??
            '—',
      ),
      status,
    ],
    YorksAccountsOfficeSection.supplierBills => [
      reference,
      text('supplier', 142, (item) => item.party ?? '—'),
      project,
      eventDate,
      money('total_incl_vat', 126, (item) => item.amount),
      money('paid_till_date', 126, (item) => item.secondaryAmount),
      money('still_due', 126, (item) => item.balanceAmount, danger: true),
      dueDate,
      text(
        'match_status',
        118,
        (item) =>
            _status(language, _metadataText(item, 'match_status') ?? 'review'),
      ),
      status,
    ],
    YorksAccountsOfficeSection.dueSchedule => [
      reference,
      text(
        'office_record_type',
        118,
        (item) => _recordType(language, item.recordKind),
      ),
      project,
      text('office_party', 128, (item) => item.party ?? '—'),
      money('office_amount', 126, (item) => item.amount),
      money('paid_till_date', 126, (item) => item.secondaryAmount),
      money('still_due', 126, (item) => item.balanceAmount, danger: true),
      dueDate,
      status,
    ],
    _ => [
      project,
      reference,
      text('office_party', 150, (item) => item.party ?? '—'),
      money('office_amount', 126, (item) => item.amount),
      eventDate,
      dueDate,
      status,
    ],
  };
}

List<_OfficeCardField> _officeCardFields(
  YorksAccountsOfficeSection section,
  YorksAccountsOfficeItem item,
  AppLanguage language,
) => switch (section) {
  YorksAccountsOfficeSection.claims => [
    _OfficeCardField('client', item.party ?? '—'),
    _OfficeCardField('office_period', _dateText(item.eventDate, language)),
    _OfficeCardField('claimed', _moneyOrDash(item, item.amount)),
    _OfficeCardField('certified', _moneyOrDash(item, item.secondaryAmount)),
    _OfficeCardField(
      'still_due',
      _moneyOrDash(item, item.balanceAmount),
      danger: item.balanceAmount?.isZero == false,
    ),
    _OfficeCardField('office_due_date', _dateText(item.dueDate, language)),
  ],
  YorksAccountsOfficeSection.clientPayments => [
    _OfficeCardField('client', item.party ?? '—'),
    _OfficeCardField(
      'office_record_type',
      _recordType(language, item.recordKind),
    ),
    _OfficeCardField('office_amount', _moneyOrDash(item, item.amount)),
    _OfficeCardField('office_date', _dateText(item.eventDate, language)),
    _OfficeCardField('office_due_date', _dateText(item.dueDate, language)),
    _OfficeCardField(
      'office_bank_method',
      _metadataText(item, 'bank_name') ??
          _metadataText(item, 'payment_method') ??
          '—',
    ),
  ],
  YorksAccountsOfficeSection.supplierBills => [
    _OfficeCardField('supplier', item.party ?? '—'),
    _OfficeCardField('total_incl_vat', _moneyOrDash(item, item.amount)),
    _OfficeCardField(
      'paid_till_date',
      _moneyOrDash(item, item.secondaryAmount),
    ),
    _OfficeCardField(
      'still_due',
      _moneyOrDash(item, item.balanceAmount),
      danger: item.balanceAmount?.isZero == false,
    ),
    _OfficeCardField(
      'match_status',
      _status(language, _metadataText(item, 'match_status') ?? 'review'),
    ),
    _OfficeCardField('office_due_date', _dateText(item.dueDate, language)),
  ],
  YorksAccountsOfficeSection.dueSchedule => [
    _OfficeCardField('office_party', item.party ?? '—'),
    _OfficeCardField(
      'office_record_type',
      _recordType(language, item.recordKind),
    ),
    _OfficeCardField('office_amount', _moneyOrDash(item, item.amount)),
    _OfficeCardField(
      'paid_till_date',
      _moneyOrDash(item, item.secondaryAmount),
    ),
    _OfficeCardField(
      'still_due',
      _moneyOrDash(item, item.balanceAmount),
      danger: item.balanceAmount?.isZero == false,
    ),
    _OfficeCardField('office_due_date', _dateText(item.dueDate, language)),
  ],
  _ => [
    _OfficeCardField('office_party', item.party ?? '—'),
    _OfficeCardField('office_amount', _moneyOrDash(item, item.amount)),
    _OfficeCardField('office_date', _dateText(item.eventDate, language)),
    _OfficeCardField('office_due_date', _dateText(item.dueDate, language)),
  ],
};

YorksAccountsOfficeSection _sectionForRecordKind(String recordKind) =>
    switch (recordKind) {
      'claim' => YorksAccountsOfficeSection.claims,
      'client_payment' || 'pdc' => YorksAccountsOfficeSection.clientPayments,
      'supplier_bill' => YorksAccountsOfficeSection.supplierBills,
      'client_invoice_due' ||
      'pdc_due' ||
      'supplier_bill_due' => YorksAccountsOfficeSection.dueSchedule,
      'document' => YorksAccountsOfficeSection.documents,
      _ => YorksAccountsOfficeSection.activity,
    };

String _recordType(AppLanguage language, String recordKind) =>
    _t(language, switch (recordKind) {
      'claim' => 'office_type_claim',
      'client_payment' => 'office_type_receipt',
      'pdc' || 'pdc_due' => 'office_type_pdc',
      'supplier_bill' || 'supplier_bill_due' => 'office_type_supplier_bill',
      'client_invoice_due' => 'office_type_client_invoice',
      'document' => 'office_type_document',
      _ => 'office_type_activity',
    });

String? _metadataText(YorksAccountsOfficeItem item, String key) {
  final value = item.metadata[key];
  if (value == null) return null;
  final normalized = value.toString().trim();
  return normalized.isEmpty ? null : normalized;
}

Widget _officeText(String value) => Text(
  value,
  maxLines: 2,
  overflow: TextOverflow.ellipsis,
  style: AppTypography.bodySmall.copyWith(color: AppColors.inkSecondary),
);

Widget _officeMoney(
  YorksAccountsOfficeItem item,
  YorksAccountsDecimal? value, {
  bool danger = false,
}) => Text(
  _moneyOrDash(item, value),
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: AppTypography.labelLarge.copyWith(
    color: danger && value?.isZero == false ? AppColors.error : AppColors.ink,
  ),
);

String _moneyOrDash(
  YorksAccountsOfficeItem item,
  YorksAccountsDecimal? value,
) => value == null ? '—' : _money(item.currencyCode, value);

class _OfficeStatePanel extends StatelessWidget {
  const _OfficeStatePanel({
    required this.status,
    required this.language,
    required this.onRetry,
  });

  final YorksAccountsViewStatus status;
  final AppLanguage language;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final key = switch (status) {
      YorksAccountsViewStatus.offline => 'offline',
      YorksAccountsViewStatus.forbidden => 'forbidden',
      YorksAccountsViewStatus.unavailable => 'load_failed',
      YorksAccountsViewStatus.sessionExpired => 'forbidden',
      _ => 'load_failed',
    };
    return _OfficePanel(
      child: SizedBox(
        height: 260,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                color: AppColors.muted,
                size: 38,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                _t(language, key),
                style: AppTypography.titleSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(_t(language, 'retry')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfficeStatusBadge extends StatelessWidget {
  const _OfficeStatusBadge({required this.item, required this.language});
  final YorksAccountsOfficeItem item;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final danger = item.status == 'overdue' || item.status == 'returned';
    final warning =
        item.actionRequired ||
        item.status == 'due_soon' ||
        item.status == 'partially_paid' ||
        item.status == 'review';
    final color = danger
        ? AppColors.error
        : warning
        ? AppColors.warning
        : AppColors.success;
    final background = danger
        ? AppColors.errorContainer
        : warning
        ? AppColors.warningContainer
        : AppColors.successContainer;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        _status(language, item.status),
        style: AppTypography.labelSmall.copyWith(color: color),
      ),
    );
  }
}

class _OfficePanel extends StatelessWidget {
  const _OfficePanel({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      boxShadow: const [
        BoxShadow(
          color: AppColors.shadow,
          blurRadius: 16,
          offset: Offset(0, 5),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class _OfficePanelTitle extends StatelessWidget {
  const _OfficePanelTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(width: 0),
      Icon(icon, color: AppColors.blue),
      const SizedBox(width: AppSpacing.md),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTypography.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(subtitle, style: AppTypography.bodySmall),
          ],
        ),
      ),
    ],
  );
}

class _OfficeTwoLine extends StatelessWidget {
  const _OfficeTwoLine({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelLarge.copyWith(color: AppColors.blue),
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.bodySmall,
      ),
    ],
  );
}

class _OfficeMiniField extends StatelessWidget {
  const _OfficeMiniField({
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
      const SizedBox(height: AppSpacing.xs),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelLarge.copyWith(
          color: danger ? AppColors.error : AppColors.ink,
        ),
      ),
    ],
  );
}

class _OfficeSectionConfig {
  const _OfficeSectionConfig({
    required this.titleKey,
    required this.bodyKey,
    required this.icon,
    required this.color,
    this.statuses = const [],
    this.primaryStatuses = const [],
  });

  final String titleKey;
  final String bodyKey;
  final IconData icon;
  final Color color;
  final List<String> statuses;
  final List<String> primaryStatuses;

  static _OfficeSectionConfig forSection(YorksAccountsOfficeSection section) =>
      switch (section) {
        YorksAccountsOfficeSection.claims => const _OfficeSectionConfig(
          titleKey: 'office_claims_title',
          bodyKey: 'office_claims_body',
          icon: Icons.request_page_outlined,
          color: AppColors.blue,
          statuses: [
            'draft',
            'ready_for_accounts',
            'submitted',
            'under_certification',
            'partially_certified',
            'certified',
            'partially_paid',
            'paid',
            'returned',
          ],
          primaryStatuses: ['draft', 'submitted', 'certified', 'returned'],
        ),
        YorksAccountsOfficeSection.clientPayments => const _OfficeSectionConfig(
          titleKey: 'office_payments_title',
          bodyKey: 'office_payments_body',
          icon: Icons.account_balance_wallet_outlined,
          color: AppColors.success,
          statuses: [
            'received',
            'reversed',
            'expected',
            'deposited',
            'cleared',
            'bounced',
            'replaced',
            'cancelled',
          ],
          primaryStatuses: ['received', 'deposited', 'cleared', 'bounced'],
        ),
        YorksAccountsOfficeSection.supplierBills => const _OfficeSectionConfig(
          titleKey: 'supplier_bills',
          bodyKey: 'office_supplier_body',
          icon: Icons.receipt_long_outlined,
          color: AppColors.warning,
          statuses: [
            'draft',
            'review',
            'approved',
            'partially_paid',
            'paid',
            'cancelled',
          ],
          primaryStatuses: ['review', 'approved', 'partially_paid', 'paid'],
        ),
        YorksAccountsOfficeSection.dueSchedule => const _OfficeSectionConfig(
          titleKey: 'office_due_title',
          bodyKey: 'office_due_body',
          icon: Icons.calendar_month_outlined,
          color: AppColors.error,
          statuses: ['current', 'due_soon', 'due_today', 'overdue'],
          primaryStatuses: ['due_soon', 'due_today', 'overdue'],
        ),
        YorksAccountsOfficeSection.documents => const _OfficeSectionConfig(
          titleKey: 'documents',
          bodyKey: 'office_documents_body',
          icon: Icons.folder_copy_outlined,
          color: AppColors.blue,
          statuses: ['active', 'archived'],
        ),
        YorksAccountsOfficeSection.activity => const _OfficeSectionConfig(
          titleKey: 'office_activity_title',
          bodyKey: 'office_activity_body',
          icon: Icons.policy_outlined,
          color: AppColors.purple,
          statuses: ['recorded'],
        ),
      };
}

@visibleForTesting
String yorksAccountsOfficeItemRoute(
  YorksAccountsOfficeSection section,
  YorksAccountsOfficeItem item,
) => switch (section) {
  YorksAccountsOfficeSection.claims =>
    RoutePaths.yorksV1ProjectAccountsInvoicesPath(item.projectId),
  YorksAccountsOfficeSection.clientPayments =>
    RoutePaths.yorksV1ProjectAccountsReceiptsPdcPath(item.projectId),
  YorksAccountsOfficeSection.supplierBills =>
    RoutePaths.yorksV1ProjectAccountsSupplierBillsPath(item.projectId),
  YorksAccountsOfficeSection.dueSchedule
      when item.recordKind == 'supplier_bill_due' =>
    RoutePaths.yorksV1ProjectAccountsSupplierBillsPath(item.projectId),
  YorksAccountsOfficeSection.dueSchedule
      when item.recordKind == 'client_invoice_due' =>
    RoutePaths.yorksV1ProjectAccountsInvoicesPath(item.projectId),
  YorksAccountsOfficeSection.dueSchedule when item.recordKind == 'pdc_due' =>
    RoutePaths.yorksV1ProjectAccountsReceiptsPdcPath(item.projectId),
  YorksAccountsOfficeSection.dueSchedule =>
    RoutePaths.yorksV1ProjectAccountsOverviewPath(item.projectId),
  YorksAccountsOfficeSection.documents =>
    RoutePaths.yorksV1ProjectAccountsDocumentsPath(item.projectId),
  YorksAccountsOfficeSection.activity =>
    RoutePaths.yorksV1ProjectAccountsActivityPath(item.projectId),
};

String _t(AppLanguage language, String key) =>
    YorksV1AccountsStrings.text(language, key);

String _status(AppLanguage language, String status) {
  final translated = _t(language, 'status_$status');
  if (translated != 'status_$status') return translated;
  final words = status.split('_');
  return words
      .map(
        (word) => word.isEmpty
            ? word
            : '${word.substring(0, 1).toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
}

String _money(String currency, YorksAccountsDecimal amount) {
  final canonical = amount.canonicalText;
  final negative = canonical.startsWith('-');
  final unsigned = negative ? canonical.substring(1) : canonical;
  final parts = unsigned.split('.');
  final whole = parts.first;
  final grouped = whole.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final fraction = parts.length == 1
      ? '00'
      : parts[1].padRight(2, '0').substring(0, 2);
  return '$currency ${negative ? '-' : ''}$grouped.$fraction';
}

String _dateText(DateTime? date, AppLanguage language) {
  if (date == null) return '—';
  // DateFormat's default catalogue is bundled with the application. Passing a
  // dynamic locale here would require an asynchronous locale-data bootstrap
  // before this protected register can render.
  return DateFormat.yMMMd().format(date.toLocal());
}

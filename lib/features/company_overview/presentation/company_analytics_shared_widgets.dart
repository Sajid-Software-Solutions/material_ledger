part of 'company_analytics_screen.dart';

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 200,
    constraints: const BoxConstraints(minHeight: 86),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.labelMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(value, style: AppTypography.titleMedium.copyWith(color: color)),
      ],
    ),
  );
}

class _ChartSeries {
  const _ChartSeries(this.label, this.color);

  final String label;
  final Color color;
}

class _ChartPoint {
  const _ChartPoint(this.label, this.values);

  final String label;
  final List<double> values;
}

class _SeriesBarChart extends StatelessWidget {
  const _SeriesBarChart({
    required this.points,
    required this.series,
    required this.language,
  });
  final AppLanguage language;

  final List<_ChartPoint> points;
  final List<_ChartSeries> series;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final maximum = points.fold<double>(
      1,
      (current, point) => point.values.fold<double>(
        current,
        (value, next) => math.max(value, next),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Disclosure(
          title: Text(CompanyAnalyticsStrings.viewTable.active(language)),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  DataColumn(
                    label: Text(
                      CompanyAnalyticsStrings.period.active(language),
                    ),
                  ),
                  for (final item in series)
                    DataColumn(label: Text(item.label), numeric: true),
                ],
                rows: [
                  for (final point in points)
                    DataRow(
                      cells: [
                        DataCell(Text(point.label)),
                        for (final value in point.values)
                          DataCell(
                            Text(NumberFormat('#,##0.##').format(value)),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.sm,
          children: [
            for (final item in series)
              _Legend(label: item.label, color: item.color),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (points.isEmpty)
          const SizedBox.shrink()
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              height: 170 + (textScale - 1) * 40,
              width: math.max(420, points.length * 86),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final point in points)
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          SizedBox(
                            height: 125,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                for (
                                  var index = 0;
                                  index < point.values.length;
                                  index++
                                ) ...[
                                  Container(
                                    width: 12,
                                    height: point.values[index] == 0
                                        ? 3
                                        : math.max(
                                            10,
                                            112 * point.values[index] / maximum,
                                          ),
                                    decoration: BoxDecoration(
                                      color: series[index].color,
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(
                                          AppSpacing.radiusSm,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (index != point.values.length - 1)
                                    const SizedBox(width: 4),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(point.label, style: AppTypography.labelSmall),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _DomainUnavailableCard extends StatelessWidget {
  const _DomainUnavailableCard({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) =>
      _Panel(child: _UnavailableData(language: language));
}

class _ConfirmationLine extends StatelessWidget {
  const _ConfirmationLine({required this.language, required this.value});

  final AppLanguage language;
  final DateTime value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(
        Icons.verified_user_outlined,
        size: 18,
        color: AppColors.success,
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Text(
          '${CompanyAnalyticsStrings.lastConfirmed.active(language)} · '
          '${_formatTimestamp(value.toLocal())}',
          style: AppTypography.bodySmall.copyWith(color: AppColors.success),
        ),
      ),
    ],
  );
}

class _MonthlyMovementCard extends StatelessWidget {
  const _MonthlyMovementCard({required this.language, required this.data});

  final AppLanguage language;
  final CompanyMaterialRequestAnalytics data;

  @override
  Widget build(BuildContext context) {
    final maximum = data.monthlyFlow.fold<int>(
      1,
      (value, item) => math.max(value, math.max(item.submitted, item.closed)),
    );
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final chartHeight = 190 + ((textScale - 1) * 80);
    final plotHeight = 145 + ((textScale - 1) * 60);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            CompanyAnalyticsStrings.monthlyMovement.active(language),
            style: AppTypography.titleMedium,
          ),
          _Disclosure(
            title: Text(CompanyAnalyticsStrings.viewTable.active(language)),
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    DataColumn(
                      label: Text(
                        CompanyAnalyticsStrings.period.active(language),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        CompanyAnalyticsStrings.submitted.active(language),
                      ),
                      numeric: true,
                    ),
                    DataColumn(
                      label: Text(
                        CompanyAnalyticsStrings.closed.active(language),
                      ),
                      numeric: true,
                    ),
                  ],
                  rows: [
                    for (final month in data.monthlyFlow)
                      DataRow(
                        cells: [
                          DataCell(Text(month.month)),
                          DataCell(Text('${month.submitted}')),
                          DataCell(Text('${month.closed}')),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (data.monthlyFlow.length >= 3) ...[
            Text(
              CompanyAnalyticsStrings.monthlyComparison.active(language),
              style: AppTypography.labelLarge,
            ),
            Text(
              '${data.monthlyFlow[data.monthlyFlow.length - 3].month} → ${data.monthlyFlow[data.monthlyFlow.length - 2].month}',
              style: AppTypography.bodySmall,
            ),
            Text(
              '${CompanyAnalyticsStrings.submitted.active(language)}: '
              '${data.monthlyFlow[data.monthlyFlow.length - 3].submitted} → ${data.monthlyFlow[data.monthlyFlow.length - 2].submitted} · '
              '${CompanyAnalyticsStrings.closed.active(language)}: '
              '${data.monthlyFlow[data.monthlyFlow.length - 3].closed} → ${data.monthlyFlow[data.monthlyFlow.length - 2].closed}',
              style: AppTypography.bodyMedium,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.lg,
            children: [
              _Legend(
                label: CompanyAnalyticsStrings.submitted.active(language),
                color: AppColors.blue,
              ),
              _Legend(
                label: CompanyAnalyticsStrings.closed.active(language),
                color: AppColors.success,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          if (data.monthlyFlow.isEmpty)
            _EmptyData(language: language)
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                height: chartHeight,
                width: math.max(
                  MediaQuery.sizeOf(context).width - 96,
                  data.monthlyFlow.length * 78,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final month in data.monthlyFlow)
                      Expanded(
                        child: _MonthBars(
                          month: month,
                          maximum: maximum,
                          plotHeight: plotHeight,
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

class _MonthBars extends StatelessWidget {
  const _MonthBars({
    required this.month,
    required this.maximum,
    required this.plotHeight,
  });

  final CompanyMaterialRequestMonth month;
  final int maximum;
  final double plotHeight;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      SizedBox(
        height: plotHeight,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _SingleBar(
              value: month.submitted,
              maximum: maximum,
              color: AppColors.blue,
            ),
            const SizedBox(width: 5),
            _SingleBar(
              value: month.closed,
              maximum: maximum,
              color: AppColors.success,
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(month.month, style: AppTypography.labelSmall),
    ],
  );
}

class _SingleBar extends StatelessWidget {
  const _SingleBar({
    required this.value,
    required this.maximum,
    required this.color,
  });

  final int value;
  final int maximum;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final height = value == 0
        ? 3.0
        : math.max(12, 118 * value / maximum).toDouble();
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('$value', style: AppTypography.labelSmall),
        const SizedBox(height: AppSpacing.xs),
        Container(
          width: 16,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppSpacing.radiusSm),
            ),
          ),
        ),
      ],
    );
  }
}

class _CoverageCard extends StatelessWidget {
  const _CoverageCard({
    required this.language,
    required this.projection,
    required this.flags,
  });

  final AppLanguage language;
  final CompanyAnalyticsProjection projection;
  final YorksV1FeatureFlags flags;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          CompanyAnalyticsStrings.coverageTitle.active(language),
          style: AppTypography.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          CompanyAnalyticsStrings.coverageDescription.active(language),
          style: AppTypography.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final item in projection.coverage.values)
          _CoverageRow(
            language: language,
            item: item,
            route: _routeFor(item.domain, flags),
          ),
      ],
    ),
  );

  static String? _routeFor(String domain, YorksV1FeatureFlags flags) =>
      switch (domain) {
        'projects' => RoutePaths.yorksV1Projects,
        'material_requests' => RoutePaths.yorksV1MaterialRequests,
        'accounts' when flags.accounts => RoutePaths.yorksV1Accounts,
        'workforce' when flags.workforce => RoutePaths.yorksV1Workforce,
        'rentals' => RoutePaths.rentals,
        'inventory' => RoutePaths.yorksV1Inventory,
        'audit' => RoutePaths.activityLog,
        _ => null,
      };
}

class _CoverageRow extends StatelessWidget {
  const _CoverageRow({
    required this.language,
    required this.item,
    required this.route,
  });

  final AppLanguage language;
  final CompanyAnalyticsCoverageItem item;
  final String? route;

  @override
  Widget build(BuildContext context) {
    final state = item.state;
    final color = switch (state) {
      CompanyAnalyticsCoverageState.available => AppColors.success,
      CompanyAnalyticsCoverageState.sourceOnly => AppColors.blue,
      CompanyAnalyticsCoverageState.denied => AppColors.muted,
    };
    final stateLabel = switch (state) {
      CompanyAnalyticsCoverageState.available =>
        CompanyAnalyticsStrings.available.active(language),
      CompanyAnalyticsCoverageState.sourceOnly =>
        CompanyAnalyticsStrings.sourceOnly.active(language),
      CompanyAnalyticsCoverageState.denied =>
        CompanyAnalyticsStrings.denied.active(language),
    };
    return Container(
      constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Icon(
            state == CompanyAnalyticsCoverageState.denied
                ? Icons.lock_outline_rounded
                : Icons.check_circle_outline_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _domainLabel(item.domain, language),
                  style: AppTypography.titleSmall,
                ),
                Text(
                  stateLabel,
                  style: AppTypography.bodySmall.copyWith(color: color),
                ),
              ],
            ),
          ),
          if (route != null && state != CompanyAnalyticsCoverageState.denied)
            IconButton(
              tooltip: _domainLabel(item.domain, language),
              onPressed: () => context.push(route!),
              icon: const Icon(Icons.arrow_forward_rounded),
              constraints: const BoxConstraints.tightFor(
                width: AppSpacing.minTapTarget,
                height: AppSpacing.minTapTarget,
              ),
            ),
        ],
      ),
    );
  }

  String _domainLabel(String domain, AppLanguage language) => switch (domain) {
    'projects' => CompanyAnalyticsStrings.projectSource.active(language),
    'material_requests' => CompanyAnalyticsStrings.requestsSource.active(
      language,
    ),
    'accounts' => CompanyAnalyticsStrings.accountsSource.active(language),
    'workforce' => CompanyAnalyticsStrings.workforceSource.active(language),
    'rentals' => CompanyAnalyticsStrings.rentalsSource.active(language),
    'inventory' => CompanyAnalyticsStrings.inventorySource.active(language),
    'audit' => CompanyAnalyticsStrings.auditSource.active(language),
    _ => domain,
  };
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.title,
    required this.actionLabel,
    required this.onOpen,
  });

  final String title;
  final String actionLabel;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final action = onOpen == null
          ? null
          : TextButton(
              onPressed: onOpen,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, AppSpacing.minTapTarget),
              ),
              child: Text(actionLabel),
            );
      if (constraints.maxWidth < 420) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTypography.titleMedium),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xs),
              action,
            ],
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: Text(title, style: AppTypography.titleMedium)),
          ?action,
        ],
      );
    },
  );
}

class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      border: Border.all(color: color.withValues(alpha: 0.22)),
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Text(
        '$label · $value',
        style: AppTypography.labelLarge.copyWith(color: color),
      ),
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: AppSpacing.sm),
      Flexible(child: Text(label, style: AppTypography.bodySmall)),
    ],
  );
}

class _UnavailableData extends StatelessWidget {
  const _UnavailableData({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
    child: Row(
      children: [
        const Icon(Icons.lock_outline_rounded, color: AppColors.muted),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            CompanyAnalyticsStrings.denied.active(language),
            style: AppTypography.bodyMedium,
          ),
        ),
      ],
    ),
  );
}

class _EmptyData extends StatelessWidget {
  const _EmptyData({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
    child: Text(
      CompanyAnalyticsStrings.noData.active(language),
      style: AppTypography.bodyMedium,
      textAlign: TextAlign.center,
    ),
  );
}

class _AnalyticsLoading extends StatelessWidget {
  const _AnalyticsLoading();

  @override
  Widget build(BuildContext context) => const _Panel(
    child: SizedBox(
      height: 240,
      child: Center(child: CircularProgressIndicator()),
    ),
  );
}

class _AnalyticsError extends StatelessWidget {
  const _AnalyticsError({
    required this.language,
    required this.error,
    required this.onRetry,
  });

  final AppLanguage language;
  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final code = error is YorksV1DomainException
        ? (error as YorksV1DomainException).code
        : YorksV1DomainErrorCode.backendUnavailable;
    return _Panel(
      color: AppColors.errorContainer,
      borderColor: AppColors.error.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(height: AppSpacing.md),
          Text(
            CompanyAnalyticsStrings.unableTitle.active(language),
            style: AppTypography.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            CompanyAnalyticsStrings.errorFor(code).active(language),
            style: AppTypography.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(CompanyAnalyticsStrings.tryAgain.active(language)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, AppSpacing.minTapTarget),
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    this.color = AppColors.surfaceContainerLowest,
    this.borderColor = AppColors.line,
    this.onTap,
    this.semanticsLabel,
  });

  final Widget child;
  final Color color;
  final Color borderColor;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppSpacing.radiusLg);
    final decoration = BoxDecoration(
      color: color,
      border: Border.all(color: borderColor),
      borderRadius: radius,
    );
    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      child: child,
    );
    if (onTap == null) {
      return DecoratedBox(decoration: decoration, child: content);
    }
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: DecoratedBox(
        decoration: decoration,
        child: Material(
          color: Colors.transparent,
          child: InkWell(onTap: onTap, borderRadius: radius, child: content),
        ),
      ),
    );
  }
}

String _formatTimestamp(DateTime value) {
  String two(int part) => part.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}

String _projectStateLabel(String value, AppLanguage language) {
  final state = YorksV1ProjectLifecycle.fromWireValue(value);
  return state == null
      ? CompanyAnalyticsStrings.status.active(language)
      : YorksV1ProjectStrings.stateLabel(state).active(language);
}

String _requestActionLabel(
  CompanyMaterialRequestAttentionItem item,
  AppLanguage language,
) {
  final direct = switch (item.nextActionCode) {
    'replacement_dispatch_required' =>
      YorksV1MaterialRequestStrings.replacementDispatchRequired,
    'receipt_review_required' => YorksV1MaterialRequestStrings.awaitingReceipt,
    'material_request_close_review' ||
    'close_request' => YorksV1MaterialRequestStrings.closeReviewRequired,
    _ => null,
  };
  if (direct != null) return direct.active(language);
  final state = YorksV1MaterialRequestState.fromWireValue(item.state);
  return state == null
      ? CompanyAnalyticsStrings.actionRequired.active(language)
      : yorksV1MaterialRequestStateCopy(state).active(language);
}

String _minutesToHours(int minutes, AppLanguage language) {
  final whole = minutes ~/ 60;
  final remainder = minutes.remainder(60);
  final hours = CompanyAnalyticsStrings.hoursShort.active(language);
  final minuteUnit = CompanyAnalyticsStrings.minutesShort.active(language);
  if (remainder == 0) return '$whole $hours';
  return '$whole $hours ${remainder.toString().padLeft(2, '0')} $minuteUnit';
}

String _formatMoney(String currency, String decimal) {
  final negative = decimal.startsWith('-');
  final unsigned = negative ? decimal.substring(1) : decimal;
  final parts = unsigned.split('.');
  final whole = parts.first.padLeft(1, '0');
  final grouped = StringBuffer();
  for (var index = 0; index < whole.length; index++) {
    if (index > 0 && (whole.length - index) % 3 == 0) grouped.write(',');
    grouped.write(whole[index]);
  }
  final fraction = parts.length == 1
      ? '00'
      : parts[1].padRight(2, '0').substring(0, 2);
  return '$currency ${negative ? '-' : ''}$grouped.$fraction';
}

String _formatCompactMoney(
  String currency,
  String decimal,
  AppLanguage language,
) {
  final value = double.parse(decimal);
  final formatted = NumberFormat.compact(locale: language.code).format(value);
  return '$currency $formatted';
}

class _Disclosure extends StatelessWidget {
  const _Disclosure({required this.title, required this.children});
  final Widget title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: ExpansionTile(title: title, children: children),
  );
}

class _RecentProjectActivity extends StatelessWidget {
  const _RecentProjectActivity({required this.language, required this.data});
  final AppLanguage language;
  final CompanyProjectAnalytics data;
  @override
  Widget build(BuildContext context) {
    final rows = [...data.register]
      ..sort((a, b) => b.latestActivityAt.compareTo(a.latestActivityAt));
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            CompanyAnalyticsStrings.recentActivity.active(language),
            style: AppTypography.titleMedium,
          ),
          Text(
            CompanyAnalyticsStrings.registerPreview.active(language),
            style: AppTypography.bodySmall,
          ),
          for (final row in rows.take(5))
            _AttentionRow(
              icon: Icons.history_rounded,
              color: AppColors.muted,
              title: '${row.reference} · ${row.name}',
              detail: _formatTimestamp(row.latestActivityAt.toLocal()),
              actionLabel: CompanyAnalyticsStrings.openProjects.active(
                language,
              ),
              onTap: () =>
                  context.push(RoutePaths.yorksV1ProjectPath(row.projectId)),
            ),
          if (rows.isEmpty) _EmptyData(language: language),
        ],
      ),
    );
  }
}

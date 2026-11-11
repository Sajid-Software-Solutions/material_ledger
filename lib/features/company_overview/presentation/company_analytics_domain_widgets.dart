part of 'company_analytics_screen.dart';

class _AccountsPositionCard extends StatelessWidget {
  const _AccountsPositionCard({
    required this.language,
    required this.data,
    required this.selectedCurrency,
    required this.onCurrencyChanged,
    this.onOpen,
  });

  final AppLanguage language;
  final CompanyAccountAnalytics data;
  final String? selectedCurrency;
  final ValueChanged<String?> onCurrencyChanged;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final group = data.currencyGroups.isEmpty
        ? null
        : data.currencyGroups.firstWhere(
            (item) => item.currencyCode == selectedCurrency,
            orElse: () => data.currencyGroups.first,
          );
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(
            title: CompanyAnalyticsStrings.financialStatus.active(language),
            actionLabel: CompanyAnalyticsStrings.openWorkforce.active(language),
            onOpen: onOpen,
          ),
          Text(
            CompanyAnalyticsStrings.currencyBoundary.active(language),
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
          if (data.currencyGroups.length > 1) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: DropdownButton<String>(
                value: group?.currencyCode,
                items: [
                  for (final item in data.currencyGroups)
                    DropdownMenuItem(
                      value: item.currencyCode,
                      child: Text(item.currencyCode),
                    ),
                ],
                onChanged: onCurrencyChanged,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (group == null)
            _EmptyData(language: language)
          else ...[
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                _MoneyMetric(
                  label: CompanyAnalyticsStrings.contractValue.active(language),
                  value: _formatMoney(group.currencyCode, group.contractValue),
                  color: AppColors.blue,
                ),
                _MoneyMetric(
                  label: CompanyAnalyticsStrings.claimed.active(language),
                  value: _formatMoney(group.currencyCode, group.claimed),
                  color: AppColors.tertiary,
                ),
                _MoneyMetric(
                  label: CompanyAnalyticsStrings.certified.active(language),
                  value: _formatMoney(group.currencyCode, group.certified),
                  color: AppColors.warning,
                ),
                _MoneyMetric(
                  label: CompanyAnalyticsStrings.receivedMoney.active(language),
                  value: _formatMoney(group.currencyCode, group.received),
                  color: AppColors.success,
                ),
                _MoneyMetric(
                  label: CompanyAnalyticsStrings.outstanding.active(language),
                  value: _formatMoney(group.currencyCode, group.outstanding),
                  color: AppColors.error,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            _SeriesBarChart(
              language: language,
              points: [
                for (final month in group.monthlyFlow)
                  _ChartPoint(month.month, [
                    double.parse(month.claimed),
                    double.parse(month.certified),
                    double.parse(month.received).abs(),
                  ]),
              ],
              series: [
                _ChartSeries(
                  CompanyAnalyticsStrings.claimed.active(language),
                  AppColors.blue,
                ),
                _ChartSeries(
                  CompanyAnalyticsStrings.certified.active(language),
                  AppColors.warning,
                ),
                _ChartSeries(
                  CompanyAnalyticsStrings.receivedMoney.active(language),
                  AppColors.success,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MoneyMetric extends StatelessWidget {
  const _MoneyMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 170, minHeight: 86),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.06),
      border: Border.all(color: color.withValues(alpha: 0.18)),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
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

class _OverviewFinancialStatusCard extends StatelessWidget {
  const _OverviewFinancialStatusCard({
    required this.language,
    required this.data,
    required this.selectedCurrency,
    required this.onCurrencyChanged,
    required this.onOpen,
  });

  final AppLanguage language;
  final CompanyAccountAnalytics data;
  final String? selectedCurrency;
  final ValueChanged<String?> onCurrencyChanged;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final group = data.currencyGroups.isEmpty
        ? null
        : data.currencyGroups.firstWhere(
            (item) => item.currencyCode == selectedCurrency,
            orElse: () => data.currencyGroups.first,
          );
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(
            title: CompanyAnalyticsStrings.financialStatus.active(language),
            actionLabel: CompanyAnalyticsStrings.openAccounts.active(language),
            onOpen: onOpen,
          ),
          if (data.currencyGroups.length > 1) ...[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: DropdownButton<String>(
                value: group?.currencyCode,
                items: [
                  for (final item in data.currencyGroups)
                    DropdownMenuItem(
                      value: item.currencyCode,
                      child: Text(item.currencyCode),
                    ),
                ],
                onChanged: onCurrencyChanged,
              ),
            ),
          ],
          if (group == null)
            _EmptyData(language: language)
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _OverviewValue(
                    label: CompanyAnalyticsStrings.contractValue.active(
                      language,
                    ),
                    value: _formatMoney(
                      group.currencyCode,
                      group.contractValue,
                    ),
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _OverviewValue(
                    label: CompanyAnalyticsStrings.outstanding.active(language),
                    value: _formatMoney(group.currencyCode, group.outstanding),
                    color: AppColors.error,
                    alignEnd: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _FinancialProgressRow(
              label: CompanyAnalyticsStrings.claimed.active(language),
              value: group.claimed,
              contractValue: group.contractValue,
              formattedValue: _formatCompactMoney(
                group.currencyCode,
                group.claimed,
                language,
              ),
              color: AppColors.blue,
            ),
            const SizedBox(height: AppSpacing.md),
            _FinancialProgressRow(
              label: CompanyAnalyticsStrings.certified.active(language),
              value: group.certified,
              contractValue: group.contractValue,
              formattedValue: _formatCompactMoney(
                group.currencyCode,
                group.certified,
                language,
              ),
              color: AppColors.warning,
            ),
            const SizedBox(height: AppSpacing.md),
            _FinancialProgressRow(
              label: CompanyAnalyticsStrings.receivedMoney.active(language),
              value: group.received,
              contractValue: group.contractValue,
              formattedValue: _formatCompactMoney(
                group.currencyCode,
                group.received,
                language,
              ),
              color: AppColors.success,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              CompanyAnalyticsStrings.receivedAgainstContract.active(language),
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _FinancialProgressRow extends StatelessWidget {
  const _FinancialProgressRow({
    required this.label,
    required this.value,
    required this.contractValue,
    required this.formattedValue,
    required this.color,
  });

  final String label;
  final String value;
  final String contractValue;
  final String formattedValue;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final amount = double.tryParse(value) ?? 0;
    final contract = double.tryParse(contractValue) ?? 0;
    final progress = contract <= 0 ? 0.0 : (amount / contract).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: AppTypography.labelMedium)),
            Text(formattedValue, style: AppTypography.labelLarge),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            color: color,
            backgroundColor: AppColors.surfaceContainerLow,
          ),
        ),
      ],
    );
  }
}

class _OverviewMaterialRequestsCard extends StatelessWidget {
  const _OverviewMaterialRequestsCard({
    required this.language,
    required this.data,
    required this.onOpen,
  });

  final AppLanguage language;
  final CompanyMaterialRequestAnalytics data;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(
          title: CompanyAnalyticsStrings.materialFlowTitle.active(language),
          actionLabel: CompanyAnalyticsStrings.openRequestsButton.active(
            language,
          ),
          onOpen: onOpen,
        ),
        _OverviewStatLine(
          label: CompanyAnalyticsStrings.openRequests.active(language),
          value: '${data.open}',
          color: AppColors.tertiary,
        ),
        _OverviewStatLine(
          label: CompanyAnalyticsStrings.dispatchReady.active(language),
          value: '${data.dispatchReady}',
          color: AppColors.blue,
        ),
        _OverviewStatLine(
          label: CompanyAnalyticsStrings.receiptPending.active(language),
          value: '${data.receiptPending}',
          color: AppColors.warning,
        ),
        const SizedBox(height: AppSpacing.md),
        _OverviewRequestActivityChart(
          language: language,
          months: data.monthlyFlow,
        ),
      ],
    ),
  );
}

class _OverviewRequestActivityChart extends StatelessWidget {
  const _OverviewRequestActivityChart({
    required this.language,
    required this.months,
  });

  final AppLanguage language;
  final List<CompanyMaterialRequestMonth> months;

  @override
  Widget build(BuildContext context) {
    final visible = months.length <= 6
        ? months
        : months.sublist(months.length - 6);
    final maximum = visible.fold<int>(
      1,
      (value, month) =>
          math.max(value, math.max(month.submitted, month.closed)),
    );
    if (visible.isEmpty) return _EmptyData(language: language);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
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
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 104,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final month in visible)
                Expanded(
                  child: _OverviewMonthBars(month: month, maximum: maximum),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OverviewMonthBars extends StatelessWidget {
  const _OverviewMonthBars({required this.month, required this.maximum});

  final CompanyMaterialRequestMonth month;
  final int maximum;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      Expanded(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _OverviewBar(
              value: month.submitted,
              maximum: maximum,
              color: AppColors.blue,
            ),
            const SizedBox(width: 3),
            _OverviewBar(
              value: month.closed,
              maximum: maximum,
              color: AppColors.success,
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(month.month.split('-').last, style: AppTypography.labelSmall),
    ],
  );
}

class _OverviewBar extends StatelessWidget {
  const _OverviewBar({
    required this.value,
    required this.maximum,
    required this.color,
  });

  final int value;
  final int maximum;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: value == 0 ? 3 : math.max(8, 72 * value / maximum).toDouble(),
    decoration: BoxDecoration(
      color: color,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppSpacing.radiusSm),
      ),
    ),
  );
}

class _OverviewWorkforceCard extends StatelessWidget {
  const _OverviewWorkforceCard({
    required this.language,
    required this.data,
    required this.onOpen,
  });

  final AppLanguage language;
  final CompanyWorkforceAnalytics data;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final totalMinutes =
        data.confirmedRegularMinutes + data.confirmedOvertimeMinutes;
    final regularShare = totalMinutes == 0
        ? 0.0
        : data.confirmedRegularMinutes / totalMinutes;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(
            title: CompanyAnalyticsStrings.workforceSource.active(language),
            actionLabel: CompanyAnalyticsStrings.openSource.active(language),
            onOpen: onOpen,
          ),
          _OverviewStatLine(
            label: CompanyAnalyticsStrings.activeWorkers.active(language),
            value: '${data.activeWorkerCount}',
            color: AppColors.blue,
          ),
          _OverviewStatLine(
            label: CompanyAnalyticsStrings.attendanceNotEntered.active(
              language,
            ),
            value: '${data.missingTodayCount}',
            color: AppColors.error,
          ),
          _OverviewStatLine(
            label: CompanyAnalyticsStrings.periodsPending.active(language),
            value: '${data.monthlyPendingCount}',
            color: AppColors.warning,
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _OverviewValue(
                  label: CompanyAnalyticsStrings.regularHours.active(language),
                  value: _minutesToHours(
                    data.confirmedRegularMinutes,
                    language,
                  ),
                  color: AppColors.tertiary,
                ),
              ),
              Expanded(
                child: _OverviewValue(
                  label: CompanyAnalyticsStrings.overtimeHours.active(language),
                  value: _minutesToHours(
                    data.confirmedOvertimeMinutes,
                    language,
                  ),
                  color: AppColors.warning,
                  alignEnd: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  if (regularShare > 0)
                    Expanded(
                      flex: math.max(1, (regularShare * 1000).round()),
                      child: const ColoredBox(color: AppColors.tertiary),
                    ),
                  if (regularShare < 1)
                    Expanded(
                      flex: math.max(1, ((1 - regularShare) * 1000).round()),
                      child: const ColoredBox(color: AppColors.warning),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            CompanyAnalyticsStrings.approvedEvidenceNote.active(language),
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _OverviewRentalCard extends StatelessWidget {
  const _OverviewRentalCard({
    required this.language,
    required this.data,
    required this.onOpen,
  });

  final AppLanguage language;
  final CompanyRentalAnalytics data;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => data.totalProperties == 0
      ? _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PanelHeader(
                title: CompanyAnalyticsStrings.rentalBusiness.active(language),
                actionLabel: CompanyAnalyticsStrings.openRental.active(
                  language,
                ),
                onOpen: onOpen,
              ),
              Text(
                CompanyAnalyticsStrings.noProperties.active(language),
                style: AppTypography.bodyMedium,
              ),
            ],
          ),
        )
      : _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PanelHeader(
                title: CompanyAnalyticsStrings.rentalBusiness.active(language),
                actionLabel: CompanyAnalyticsStrings.openRental.active(
                  language,
                ),
                onOpen: onOpen,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 84,
                        height: 84,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox.expand(
                              child: CircularProgressIndicator(
                                value: (data.occupancyPercent / 100).clamp(
                                  0.0,
                                  1.0,
                                ),
                                strokeWidth: 9,
                                color: AppColors.success,
                                backgroundColor: AppColors.surfaceContainerLow,
                              ),
                            ),
                            Text(
                              '${data.occupancyPercent.round()}%',
                              style: AppTypography.titleMedium,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _OverviewStatLine(
                              label: CompanyAnalyticsStrings.propertiesOccupied
                                  .active(language),
                              value: '${data.occupied}/${data.totalProperties}',
                              color: AppColors.blue,
                            ),
                            _OverviewStatLine(
                              label: CompanyAnalyticsStrings.collectedThisMonth
                                  .active(language),
                              value: _formatCompactMoney(
                                data.currencyCode,
                                data.collectedThisMonth,
                                language,
                              ),
                              color: AppColors.success,
                            ),
                            _OverviewStatLine(
                              label: CompanyAnalyticsStrings.outstanding.active(
                                language,
                              ),
                              value: _formatCompactMoney(
                                data.currencyCode,
                                data.outstanding,
                                language,
                              ),
                              color: AppColors.error,
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
        );
}

class _OverviewStatLine extends StatelessWidget {
  const _OverviewStatLine({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelLarge.copyWith(color: color),
        ),
      ],
    ),
  );
}

class _OverviewValue extends StatelessWidget {
  const _OverviewValue({
    required this.label,
    required this.value,
    required this.color,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: alignEnd
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    children: [
      Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style: AppTypography.titleMedium.copyWith(color: color),
      ),
    ],
  );
}

class _ProjectReviewCard extends StatelessWidget {
  const _ProjectReviewCard({
    required this.language,
    required this.data,
    this.attentionOnly = false,
  });
  final bool attentionOnly;

  final AppLanguage language;
  final CompanyProjectAnalytics data;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(
          title:
              (attentionOnly
                      ? CompanyAnalyticsStrings.projectsAttention
                      : CompanyAnalyticsStrings.projectReview)
                  .active(language),
          actionLabel: CompanyAnalyticsStrings.openProjects.active(language),
          onOpen: () => context.push(RoutePaths.yorksV1Projects),
        ),
        Text(
          CompanyAnalyticsStrings.projectReviewDescription.active(language),
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.lg),
        if ((attentionOnly
                ? data.register.where((p) => p.requestActionCount > 0)
                : data.register)
            .isEmpty)
          _EmptyData(language: language)
        else
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < 720
                ? Column(
                    children: [
                      for (final item
                          in (attentionOnly
                                  ? data.register.where(
                                      (p) => p.requestActionCount > 0,
                                    )
                                  : data.register)
                              .take(8))
                        _ProjectReviewMobileRow(language: language, item: item),
                    ],
                  )
                : _ProjectReviewTable(
                    language: language,
                    rows:
                        (attentionOnly
                                ? data.register
                                      .where((p) => p.requestActionCount > 0)
                                      .take(8)
                                : data.register)
                            .toList(),
                  ),
          ),
      ],
    ),
  );
}

class _ProjectReviewTable extends StatelessWidget {
  const _ProjectReviewTable({required this.language, required this.rows});

  final AppLanguage language;
  final List<CompanyProjectRegisterItem> rows;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(
      headingRowColor: WidgetStateProperty.all(AppColors.surfaceContainerLow),
      columns: [
        DataColumn(
          label: Text(CompanyAnalyticsStrings.project.active(language)),
        ),
        DataColumn(
          label: Text(CompanyAnalyticsStrings.status.active(language)),
        ),
        DataColumn(
          numeric: true,
          label: Text(CompanyAnalyticsStrings.openRequests.active(language)),
        ),
        DataColumn(
          numeric: true,
          label: Text(CompanyAnalyticsStrings.actions.active(language)),
        ),
        DataColumn(label: Text(CompanyAnalyticsStrings.owner.active(language))),
        DataColumn(
          label: Text(CompanyAnalyticsStrings.latest.active(language)),
        ),
      ],
      rows: [
        for (final item in rows.take(12))
          DataRow(
            onSelectChanged: (_) =>
                context.push(RoutePaths.yorksV1ProjectPath(item.projectId)),
            cells: [
              DataCell(
                SizedBox(
                  width: 230,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, overflow: TextOverflow.ellipsis),
                      Text(
                        item.reference,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              DataCell(Text(_projectStateLabel(item.state, language))),
              DataCell(Text('${item.openRequestCount}')),
              DataCell(Text('${item.requestActionCount}')),
              DataCell(
                Text(
                  YorksV1ProjectStrings.roleLabel(
                    item.currentOwnerRole,
                  ).active(language),
                ),
              ),
              DataCell(Text(_formatTimestamp(item.latestActivityAt.toLocal()))),
            ],
          ),
      ],
    ),
  );
}

class _ProjectReviewMobileRow extends StatelessWidget {
  const _ProjectReviewMobileRow({required this.language, required this.item});

  final AppLanguage language;
  final CompanyProjectRegisterItem item;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => context.push(RoutePaths.yorksV1ProjectPath(item.projectId)),
    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    child: Container(
      constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: AppTypography.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${item.reference} · ${_projectStateLabel(item.state, language)}',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _CountPill(
                      label: CompanyAnalyticsStrings.openRequests.active(
                        language,
                      ),
                      value: item.openRequestCount,
                      color: AppColors.blue,
                    ),
                    _CountPill(
                      label: CompanyAnalyticsStrings.actions.active(language),
                      value: item.requestActionCount,
                      color: AppColors.warning,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_rounded),
        ],
      ),
    ),
  );
}

class _MaterialPipelineCard extends StatelessWidget {
  const _MaterialPipelineCard({
    required this.language,
    required this.data,
    this.projectId,
  });
  final String? projectId;

  final AppLanguage language;
  final CompanyMaterialRequestAnalytics data;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(
          title: CompanyAnalyticsStrings.materialPipeline.active(language),
          actionLabel: CompanyAnalyticsStrings.openRequestsButton.active(
            language,
          ),
          onOpen: () => context.push(
            RoutePaths.yorksV1MaterialRequestsPath(projectId: projectId),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            _PipelineStep(
              label: CompanyAnalyticsStrings.awaitingApproval.active(language),
              value: data.awaitingEngineeringApproval,
              color: AppColors.blue,
            ),
            _PipelineStep(
              label: CompanyAnalyticsStrings.toArrange.active(language),
              value: data.toArrange,
              color: AppColors.tertiary,
            ),
            _PipelineStep(
              label: CompanyAnalyticsStrings.dispatchReady.active(language),
              value: data.dispatchReady,
              color: AppColors.warning,
            ),
            _PipelineStep(
              label: CompanyAnalyticsStrings.receiptPending.active(language),
              value: data.receiptPending,
              color: AppColors.success,
            ),
          ],
        ),
        if (data.attention.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          Text(
            CompanyAnalyticsStrings.requestsNeedAction.active(language),
            style: AppTypography.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final item in data.attention.take(6))
            _AttentionRow(
              icon: Icons.assignment_outlined,
              color: item.actorCanAct ? AppColors.blue : AppColors.error,
              title: _requestActionLabel(item, language),
              detail: '${item.requestNumber} · ${item.projectName}',
              actionLabel: CompanyAnalyticsStrings.openRequest.active(language),
              onTap: () => context.push(
                RoutePaths.yorksV1MaterialRequestPath(item.requestId),
              ),
            ),
        ],
      ],
    ),
  );
}

class _PipelineStep extends StatelessWidget {
  const _PipelineStep({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 190,
    constraints: const BoxConstraints(minHeight: 88),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Row(
      children: [
        Text(
          '$value',
          style: AppTypography.headlineSmall.copyWith(color: color),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(label, style: AppTypography.labelLarge)),
      ],
    ),
  );
}

class _WorkforceEvidenceCard extends StatelessWidget {
  const _WorkforceEvidenceCard({
    required this.language,
    required this.data,
    this.onOpen,
  });

  final AppLanguage language;
  final CompanyWorkforceAnalytics data;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(
          title: CompanyAnalyticsStrings.approvedWorkforceEvidence.active(
            language,
          ),
          actionLabel: CompanyAnalyticsStrings.openSource.active(language),
          onOpen: onOpen,
        ),
        Text(
          CompanyAnalyticsStrings.approvedEvidenceNote.active(language),
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            _MetricTile(
              label: CompanyAnalyticsStrings.activeWorkers.active(language),
              value: '${data.activeWorkerCount}',
              color: AppColors.blue,
            ),
            _MetricTile(
              label: CompanyAnalyticsStrings.regularHours.active(language),
              value: _minutesToHours(data.confirmedRegularMinutes, language),
              color: AppColors.success,
            ),
            _MetricTile(
              label: CompanyAnalyticsStrings.overtimeHours.active(language),
              value: _minutesToHours(data.confirmedOvertimeMinutes, language),
              color: AppColors.warning,
            ),
            _MetricTile(
              label: CompanyAnalyticsStrings.attendanceNotEntered.active(
                language,
              ),
              value: '${data.missingTodayCount}',
              color: AppColors.error,
            ),
            _MetricTile(
              label: CompanyAnalyticsStrings.periodsPending.active(language),
              value: '${data.monthlyPendingCount}',
              color: AppColors.tertiary,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        _SeriesBarChart(
          language: language,
          points: [
            for (final month in data.monthlyFlow)
              _ChartPoint(month.month, [
                month.regularMinutes / 60,
                month.overtimeMinutes / 60,
              ]),
          ],
          series: [
            _ChartSeries(
              CompanyAnalyticsStrings.regularHours.active(language),
              AppColors.blue,
            ),
            _ChartSeries(
              CompanyAnalyticsStrings.overtimeHours.active(language),
              AppColors.warning,
            ),
          ],
        ),
      ],
    ),
  );
}

class _RentalBusinessCard extends StatelessWidget {
  const _RentalBusinessCard({
    required this.language,
    required this.data,
    required this.onOpen,
  });

  final AppLanguage language;
  final CompanyRentalAnalytics data;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => data.totalProperties == 0
      ? _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PanelHeader(
                title: CompanyAnalyticsStrings.rentalBusiness.active(language),
                actionLabel: CompanyAnalyticsStrings.openRental.active(
                  language,
                ),
                onOpen: onOpen,
              ),
              Text(
                CompanyAnalyticsStrings.noProperties.active(language),
                style: AppTypography.bodyMedium,
              ),
            ],
          ),
        )
      : _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PanelHeader(
                title: CompanyAnalyticsStrings.rentalBusiness.active(language),
                actionLabel: CompanyAnalyticsStrings.openSource.active(
                  language,
                ),
                onOpen: onOpen,
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  _MetricTile(
                    label: CompanyAnalyticsStrings.propertiesOccupied.active(
                      language,
                    ),
                    value: '${data.occupied}/${data.totalProperties}',
                    color: AppColors.blue,
                  ),
                  _MetricTile(
                    label: CompanyAnalyticsStrings.monthlyRentRoll.active(
                      language,
                    ),
                    value: _formatMoney(
                      data.currencyCode,
                      data.monthlyRentRoll,
                    ),
                    color: AppColors.tertiary,
                  ),
                  _MetricTile(
                    label: CompanyAnalyticsStrings.collectedThisMonth.active(
                      language,
                    ),
                    value: _formatMoney(
                      data.currencyCode,
                      data.collectedThisMonth,
                    ),
                    color: AppColors.success,
                  ),
                  _MetricTile(
                    label: CompanyAnalyticsStrings.outstanding.active(language),
                    value: _formatMoney(data.currencyCode, data.outstanding),
                    color: AppColors.error,
                  ),
                  _MetricTile(
                    label: CompanyAnalyticsStrings.leaseChequeAttention.active(
                      language,
                    ),
                    value: '${data.attentionCount}',
                    color: AppColors.warning,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              _SeriesBarChart(
                language: language,
                points: [
                  for (final month in data.monthlyFlow)
                    _ChartPoint(month.month, [double.parse(month.collected)]),
                ],
                series: [
                  _ChartSeries(
                    CompanyAnalyticsStrings.receivedMoney.active(language),
                    AppColors.success,
                  ),
                ],
              ),
            ],
          ),
        );
}

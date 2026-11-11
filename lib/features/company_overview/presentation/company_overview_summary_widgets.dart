part of 'company_analytics_screen.dart';

class _CompanyKpiGrid extends StatelessWidget {
  const _CompanyKpiGrid({
    required this.language,
    required this.projection,
    required this.flags,
  });

  final AppLanguage language;
  final CompanyAnalyticsProjection projection;
  final YorksV1FeatureFlags flags;

  @override
  Widget build(BuildContext context) {
    final accounts = projection.accounts;
    final cards = <Widget>[
      if (accounts != null)
        _ExecutiveKpiCard(
          label: CompanyAnalyticsStrings.accountsSource.active(language),
          value: accounts.currencyGroups.length == 1
              ? _formatCompactMoney(
                  accounts.currencyGroups.single.currencyCode,
                  accounts.currencyGroups.single.received,
                  language,
                )
              : '${accounts.currencyGroups.length}',
          detail: accounts.currencyGroups.length == 1
              ? CompanyAnalyticsStrings.receivedMoney.active(language)
              : CompanyAnalyticsStrings.currencyGroups.active(language),
          icon: Icons.account_balance_wallet_outlined,
          color: AppColors.success,
          onTap: flags.accounts
              ? () => context.push(RoutePaths.yorksV1Accounts)
              : null,
        ),
      if (projection.projects != null)
        _ExecutiveKpiCard(
          label: CompanyAnalyticsStrings.projectsTitle.active(language),
          value: '${projection.projects!.active}',
          detail: CompanyAnalyticsStrings.active.active(language),
          icon: Icons.account_tree_outlined,
          color: AppColors.blue,
          onTap: () => context.push(RoutePaths.yorksV1Projects),
        ),
      if (projection.materialRequests != null)
        _ExecutiveKpiCard(
          label: CompanyAnalyticsStrings.materialFlowTitle.active(language),
          value: '${projection.materialRequests!.open}',
          detail: CompanyAnalyticsStrings.openRequests.active(language),
          icon: Icons.assignment_outlined,
          color: AppColors.tertiary,
          onTap: () => context.push(
            RoutePaths.yorksV1MaterialRequestsPath(
              projectId: projection.projectId,
            ),
          ),
        ),
      if (projection.workforce != null)
        _ExecutiveKpiCard(
          label: CompanyAnalyticsStrings.workforceSource.active(language),
          value: '${projection.workforce!.activeWorkerCount}',
          detail: CompanyAnalyticsStrings.activeWorkers.active(language),
          icon: Icons.groups_outlined,
          color: AppColors.success,
          onTap: flags.workforce
              ? () => context.push(RoutePaths.yorksV1Workforce)
              : null,
        ),
      if (projection.rentals != null)
        _ExecutiveKpiCard(
          label: CompanyAnalyticsStrings.rentalBusiness.active(language),
          value: projection.rentals!.totalProperties == 0
              ? '—'
              : '${projection.rentals!.occupancyPercent.round()}%',
          detail:
              (projection.rentals!.totalProperties == 0
                      ? CompanyAnalyticsStrings.noProperties
                      : CompanyAnalyticsStrings.propertiesOccupied)
                  .active(language),
          icon: Icons.apartment_outlined,
          color: AppColors.warning,
          onTap: () => context.push(RoutePaths.rentals),
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final compact =
            MediaQuery.sizeOf(context).width <= AppSpacing.compactBreakpoint;
        final columns = compact
            ? 1
            : (width < 680 ? 2 : (width < 1100 ? 3 : 5));
        final gap = AppSpacing.md * (columns - 1);
        final cardWidth = (width - gap) / columns;
        final textScale = MediaQuery.textScalerOf(
          context,
        ).scale(1).clamp(1.0, 2.0);
        final cardHeight =
            (compact ? 112.0 : 150.0) + (textScale - 1) * (compact ? 136 : 132);
        return Wrap(
          key: const ValueKey('company-analytics-kpi-grid'),
          alignment: WrapAlignment.center,
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (var index = 0; index < cards.length; index++)
              SizedBox(
                key: ValueKey('company-analytics-kpi-card-$index'),
                width: cardWidth,
                height: cardHeight,
                child: cards[index],
              ),
          ],
        );
      },
    );
  }
}

class _ExecutiveKpiCard extends StatelessWidget {
  const _ExecutiveKpiCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final iconBox = DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Icon(icon, size: AppSpacing.xl, color: color),
      ),
    );
    final compact =
        MediaQuery.sizeOf(context).width <= AppSpacing.compactBreakpoint;
    if (compact) {
      return _Panel(
        onTap: onTap,
        semanticsLabel: '$label: $value. $detail',
        child: Row(
          children: [
            iconBox,
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTypography.labelMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Flexible(
              child: Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: AppTypography.headlineMedium,
              ),
            ),
          ],
        ),
      );
    }
    return _Panel(
      onTap: onTap,
      semanticsLabel: '$label: $value. $detail',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              iconBox,
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelMedium,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(value, style: AppTypography.headlineMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _ImportantActionsCard extends StatelessWidget {
  const _ImportantActionsCard({
    required this.language,
    required this.projection,
    required this.flags,
    this.maxVisible,
  });

  final AppLanguage language;
  final CompanyAnalyticsProjection projection;
  final YorksV1FeatureFlags flags;
  final int? maxVisible;

  @override
  Widget build(BuildContext context) {
    final items = <_OverviewAttentionAction>[
      for (final request
          in (projection.materialRequests?.attention ?? const []).take(
            maxVisible ?? 5,
          ))
        _OverviewAttentionAction(
          icon: request.actorCanAct
              ? Icons.assignment_turned_in_outlined
              : Icons.report_problem_outlined,
          color: request.actorCanAct ? AppColors.blue : AppColors.error,
          title: _requestActionLabel(request, language),
          detail:
              '${request.requestNumber} · ${request.projectReference} · '
              '${yorksV1MaterialRequestOwnerRoleCopy(request.currentOwnerRole).active(language)} · '
              '${CompanyAnalyticsStrings.updated.active(language)} ${_formatTimestamp(request.updatedAt.toLocal())}',
          actionLabel: CompanyAnalyticsStrings.openRequest.active(language),
          onTap: () => context.push(
            RoutePaths.yorksV1MaterialRequestPath(request.requestId),
          ),
        ),
      if ((projection.accounts?.attentionCount ?? 0) > 0)
        _OverviewAttentionAction(
          icon: Icons.account_balance_wallet_outlined,
          color: AppColors.warning,
          title: CompanyAnalyticsStrings.accountsAttention.active(language),
          detail:
              '${projection.accounts!.attentionCount} · ${CompanyAnalyticsStrings.actionRequired.active(language)}',
          actionLabel: CompanyAnalyticsStrings.openAccounts.active(language),
          onTap: flags.accounts
              ? () => context.push(RoutePaths.yorksV1Accounts)
              : null,
        ),
      if ((projection.workforce?.missingTodayCount ?? 0) > 0)
        _OverviewAttentionAction(
          icon: Icons.groups_outlined,
          color: AppColors.tertiary,
          title: CompanyAnalyticsStrings.completeAttendance.active(language),
          detail:
              '${projection.workforce!.missingTodayCount} ${CompanyAnalyticsStrings.workersWithoutAttendance.active(language)}',
          actionLabel: CompanyAnalyticsStrings.openAttendance.active(language),
          onTap: flags.workforce
              ? () => context.push(RoutePaths.yorksV1WorkforceAttendance)
              : null,
        ),
      if ((projection.workforce?.monthlyPendingCount ?? 0) > 0)
        _OverviewAttentionAction(
          icon: Icons.calendar_month_outlined,
          color: AppColors.tertiary,
          title: CompanyAnalyticsStrings.reviewTimesheets.active(language),
          detail:
              '${projection.workforce!.monthlyPendingCount} ${CompanyAnalyticsStrings.periodsAwaitingReview.active(language)}',
          actionLabel: CompanyAnalyticsStrings.openTimesheets.active(language),
          onTap: flags.workforce
              ? () => context.push(RoutePaths.yorksV1WorkforceTimesheets)
              : null,
        ),
      if ((projection.workforce?.returnedCount ?? 0) > 0)
        _OverviewAttentionAction(
          icon: Icons.assignment_return_outlined,
          color: AppColors.error,
          title: CompanyAnalyticsStrings.correctReturnedTimesheets.active(
            language,
          ),
          detail:
              '${projection.workforce!.returnedCount} ${CompanyAnalyticsStrings.returnedForCorrection.active(language)}',
          actionLabel: CompanyAnalyticsStrings.openTimesheets.active(language),
          onTap: flags.workforce
              ? () => context.push(RoutePaths.yorksV1WorkforceTimesheets)
              : null,
        ),
      if ((projection.workforce?.awaitingFinalCount ?? 0) > 0)
        _OverviewAttentionAction(
          icon: Icons.fact_check_outlined,
          color: AppColors.warning,
          title: CompanyAnalyticsStrings.finalizeTimesheets.active(language),
          detail:
              '${projection.workforce!.awaitingFinalCount} ${CompanyAnalyticsStrings.readyForFinalReview.active(language)}',
          actionLabel: CompanyAnalyticsStrings.openTimesheets.active(language),
          onTap: flags.workforce
              ? () => context.push(RoutePaths.yorksV1WorkforceTimesheets)
              : null,
        ),
      if ((projection.workforce?.reopenRequestCount ?? 0) > 0)
        _OverviewAttentionAction(
          icon: Icons.lock_open_outlined,
          color: AppColors.warning,
          title: CompanyAnalyticsStrings.reviewReopenRequests.active(language),
          detail:
              '${projection.workforce!.reopenRequestCount} ${CompanyAnalyticsStrings.reopenRequestsAwaitingDecision.active(language)}',
          actionLabel: CompanyAnalyticsStrings.openTimesheets.active(language),
          onTap: flags.workforce
              ? () => context.push(RoutePaths.yorksV1WorkforceTimesheets)
              : null,
        ),
      if ((projection.workforce?.configurationIssueCount ?? 0) > 0)
        _OverviewAttentionAction(
          icon: Icons.settings_outlined,
          color: AppColors.error,
          title: CompanyAnalyticsStrings.resolveWorkforceSetup.active(language),
          detail:
              '${projection.workforce!.configurationIssueCount} ${CompanyAnalyticsStrings.setupIssuesRequireAdmin.active(language)}',
          actionLabel: CompanyAnalyticsStrings.openWorkforceAdministration
              .active(language),
          onTap: flags.workforce
              ? () => context.push(RoutePaths.yorksV1WorkforceAdministration)
              : null,
        ),
      if ((projection.rentals?.attentionCount ?? 0) > 0)
        _OverviewAttentionAction(
          icon: Icons.apartment_outlined,
          color: AppColors.warning,
          title: CompanyAnalyticsStrings.rentalFollowUp.active(language),
          detail:
              '${projection.rentals!.attentionCount} · ${CompanyAnalyticsStrings.actionRequired.active(language)}',
          actionLabel: CompanyAnalyticsStrings.openRental.active(language),
          onTap: () => context.push(RoutePaths.rentals),
        ),
    ];
    final visibleItems = items;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.notifications_none_rounded,
                color: AppColors.warning,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  CompanyAnalyticsStrings.importantForYou.active(language),
                  style: AppTypography.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (projection.materialRequests != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => context.push(
                  RoutePaths.yorksV1MaterialRequestsPath(
                    projectId: projection.projectId,
                  ),
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: Text(
                  '${CompanyAnalyticsStrings.requestsNeedAction.active(language)}: '
                  '${projection.materialRequests!.needsAction} · ${CompanyAnalyticsStrings.openRequests.active(language)}: '
                  '${projection.materialRequests!.open}',
                ),
              ),
            ),
          if (visibleItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(
                CompanyAnalyticsStrings.noImportantActions.active(language),
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.muted,
                ),
              ),
            )
          else
            for (final item in visibleItems)
              _AttentionRow(
                icon: item.icon,
                color: item.color,
                title: item.title,
                detail: item.detail,
                actionLabel: item.actionLabel,
                onTap: item.onTap,
              ),
        ],
      ),
    );
  }
}

class _OverviewAttentionAction {
  const _OverviewAttentionAction({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final String actionLabel;
  final VoidCallback? onTap;
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.actionLabel,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final String actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Padding(
                padding: const EdgeInsets.all(9),
                child: Icon(icon, size: 20, color: color),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.titleSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                  if (onTap != null &&
                      MediaQuery.sizeOf(context).width < 720) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      actionLabel,
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.blue,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null) ...[
              if (MediaQuery.sizeOf(context).width >= 720)
                Text(
                  actionLabel,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.blue,
                  ),
                ),
              const SizedBox(width: AppSpacing.sm),
              const Icon(Icons.arrow_forward_rounded, size: 20),
            ],
          ],
        ),
      ),
    ),
  );
}

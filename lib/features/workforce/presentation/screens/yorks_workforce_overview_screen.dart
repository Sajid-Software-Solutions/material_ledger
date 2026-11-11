import 'yorks_workforce_team_workers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_workforce_dashboard_strings.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../application/workforce_dashboard_controller.dart';
import '../../application/workforce_providers.dart';
import '../../domain/workforce_dashboard_models.dart';

class YorksWorkforceOverviewScreen extends ConsumerStatefulWidget {
  const YorksWorkforceOverviewScreen({super.key});

  @override
  ConsumerState<YorksWorkforceOverviewScreen> createState() =>
      _YorksWorkforceOverviewScreenState();
}

class _YorksWorkforceOverviewScreenState
    extends ConsumerState<YorksWorkforceOverviewScreen> {
  bool _loadScheduled = false;

  void _scheduleLoad(YorksWorkforceOverviewState state) {
    if (state.status != YorksWorkforceOverviewStatus.idle) {
      _loadScheduled = false;
      return;
    }
    if (_loadScheduled) return;
    _loadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(yorksWorkforceDashboardControllerProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final state = ref.watch(yorksWorkforceDashboardControllerProvider);
    final authority = ref.watch(yorksWorkforceAuthorityEpochProvider);
    final controller = ref.read(
      yorksWorkforceDashboardControllerProvider.notifier,
    );
    _scheduleLoad(state);
    final compact =
        MediaQuery.sizeOf(context).width < AppSpacing.compactBreakpoint;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            if (state.status == YorksWorkforceOverviewStatus.loading)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: RefreshIndicator(
                onRefresh: controller.load,
                child: ListView(
                  key: const PageStorageKey('workforce-overview'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    compact
                        ? AppSpacing.mobileScreenHorizontal
                        : AppSpacing.xxl,
                    compact ? AppSpacing.mobileScreenVertical : AppSpacing.xxl,
                    compact
                        ? AppSpacing.mobileScreenHorizontal
                        : AppSpacing.xxl,
                    AppSpacing.colossal,
                  ),
                  children: [
                    _OverviewHeader(
                      language: language,
                      compact: compact,
                      projection: state.projection,
                      canManageWorkforce:
                          authority.canManageWorkers ||
                          authority.canManageTeams ||
                          authority.canManageConfiguration,
                      onRefresh: controller.load,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (authority.canManageWorkers ||
                        authority.canMaintainAttendance ||
                        authority.canMaintainTimesheets ||
                        authority.canExportReports)
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          if (authority.canManageWorkers ||
                              (workforceTeamWorkersEnabled &&
                                  authority.canMaintainAttendance))
                            OutlinedButton.icon(
                              key: const Key('workforce-section-workers'),
                              onPressed: () => context.go(
                                authority.canManageWorkers
                                    ? '/yorks/workforce/administration'
                                    : '/yorks/workforce/workers',
                              ),
                              icon: const Icon(Icons.groups_outlined),
                              label: Text(_t(language, 'section_workers')),
                            ),
                          if (authority.canMaintainAttendance ||
                              authority.canMaintainTimesheets)
                            OutlinedButton.icon(
                              key: const Key('workforce-section-attendance'),
                              onPressed: () =>
                                  context.go('/yorks/workforce/attendance'),
                              icon: const Icon(Icons.fact_check_outlined),
                              label: Text(_t(language, 'section_attendance')),
                            ),
                          if (authority.canExportReports)
                            OutlinedButton.icon(
                              key: const Key('workforce-section-reports'),
                              onPressed: () =>
                                  context.go('/yorks/workforce/timesheets'),
                              icon: const Icon(Icons.assessment_outlined),
                              label: Text(_t(language, 'section_reports')),
                            ),
                        ],
                      ),
                    if (authority.canManageWorkers ||
                        authority.canMaintainAttendance ||
                        authority.canMaintainTimesheets ||
                        authority.canExportReports)
                      const SizedBox(height: AppSpacing.lg),
                    _OverviewStateBanner(
                      language: language,
                      state: state,
                      onRetry: controller.load,
                    ),
                    if (state.projection case final projection?) ...[
                      const SizedBox(height: AppSpacing.lg),
                      _AsOfStrip(language: language, projection: projection),
                      if (projection.kind ==
                          YorksWorkforceOverviewKind.supervisor) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _SupervisorContext(
                          language: language,
                          teams: projection.teams,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      _SummaryGrid(language: language, projection: projection),
                      if (projection.teams.isEmpty &&
                          projection.projects.isEmpty &&
                          projection.reviewQueue.isEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _EmptyPanel(language: language),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      if (!compact && projection.projects.isNotEmpty)
                        _ProjectPanel(
                          language: language,
                          projects: projection.projects,
                        ),
                      if (!compact && projection.projects.isNotEmpty)
                        const SizedBox(height: AppSpacing.lg),
                      if (!compact && projection.teams.isNotEmpty)
                        _TeamPanel(
                          language: language,
                          teams: projection.teams,
                          compact: compact,
                        ),
                      if (!compact && projection.reviewQueue.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _QueuePanel(
                          language: language,
                          items: projection.reviewQueue,
                        ),
                      ],
                      if (compact) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _ReadOnlyBoundary(language: language),
                      ],
                    ] else if (state.status ==
                            YorksWorkforceOverviewStatus.idle ||
                        state.status ==
                            YorksWorkforceOverviewStatus.loading) ...[
                      const SizedBox(height: AppSpacing.xxxl),
                      Center(
                        child: Semantics(
                          liveRegion: true,
                          label: _t(language, 'loading'),
                          child: Text(
                            _t(language, 'loading'),
                            style: AppTypography.bodyMedium,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewHeader extends StatelessWidget {
  const _OverviewHeader({
    required this.language,
    required this.compact,
    required this.projection,
    required this.canManageWorkforce,
    required this.onRefresh,
  });

  final AppLanguage language;
  final bool compact;
  final YorksWorkforceOverviewProjection? projection;
  final bool canManageWorkforce;
  final Future<bool> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_t(language, 'title'), style: AppTypography.headlineMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(_t(language, 'body'), style: AppTypography.bodyMedium),
      ],
    );
    // Navigation remains server-authorized on phones as well as desktop.
    final actionSpecs = _overviewActions(
      projection,
      canManageWorkforce: !compact && canManageWorkforce,
    );
    final actions = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final spec in actionSpecs)
          if (spec.primary)
            FilledButton.icon(
              key: Key('workforce-overview-${spec.key}'),
              onPressed: () => context.go(spec.route),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, AppSpacing.minTapTarget),
              ),
              icon: Icon(spec.icon),
              label: Text(_t(language, spec.labelKey)),
            )
          else
            OutlinedButton.icon(
              key: Key('workforce-overview-${spec.key}'),
              onPressed: () => context.go(spec.route),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, AppSpacing.minTapTarget),
              ),
              icon: Icon(spec.icon),
              label: Text(_t(language, spec.labelKey)),
            ),
        IconButton.outlined(
          tooltip: _t(language, 'refresh'),
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
          constraints: const BoxConstraints.tightFor(
            width: AppSpacing.minTapTarget,
            height: AppSpacing.minTapTarget,
          ),
        ),
      ],
    );
    return compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              copy,
              const SizedBox(height: AppSpacing.md),
              actions,
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: copy),
              actions,
            ],
          );
  }
}

typedef _OverviewActionSpec = ({
  String key,
  String labelKey,
  String route,
  IconData icon,
  bool primary,
});

List<_OverviewActionSpec> _overviewActions(
  YorksWorkforceOverviewProjection? projection, {
  required bool canManageWorkforce,
}) => [
  if (canManageWorkforce)
    (
      key: 'administration',
      labelKey: 'administration',
      route: '/yorks/workforce/administration',
      icon: Icons.manage_accounts_outlined,
      primary: projection == null,
    ),
  ...switch (projection?.kind) {
    YorksWorkforceOverviewKind.supervisor => [
      if (projection!.actionFlags['can_complete_today_attendance'] == true)
        (
          key: 'complete-attendance',
          labelKey: 'complete_today_attendance',
          route: '/yorks/workforce/attendance',
          icon: Icons.fact_check_outlined,
          primary: true,
        ),
    ],
    YorksWorkforceOverviewKind.management => [
      if (projection!.actionFlags['can_open_review_queue'] == true)
        (
          key: 'review-queue',
          labelKey: 'open_review_queue',
          route: '/yorks/workforce/timesheets',
          icon: Icons.rate_review_outlined,
          primary: true,
        ),
      if (projection.actionFlags['can_open_final_approval_queue'] == true)
        (
          key: 'final-approval-queue',
          labelKey: 'open_final_approval_queue',
          route: '/yorks/workforce/timesheets',
          icon: Icons.approval_outlined,
          primary: false,
        ),
    ],
    YorksWorkforceOverviewKind.admin => [
      if (projection!.actionFlags['can_open_reopen_queue'] == true)
        (
          key: 'reopen-queue',
          labelKey: 'open_reopen_queue',
          route: '/yorks/workforce/timesheets',
          icon: Icons.lock_open_outlined,
          primary: true,
        ),
      if (projection.actionFlags['can_open_final_approval_queue'] == true)
        (
          key: 'final-approval-queue',
          labelKey: 'open_final_approval_queue',
          route: '/yorks/workforce/timesheets',
          icon: Icons.approval_outlined,
          primary: false,
        ),
    ],
    null => const <_OverviewActionSpec>[],
  },
];

class _OverviewStateBanner extends StatelessWidget {
  const _OverviewStateBanner({
    required this.language,
    required this.state,
    required this.onRetry,
  });

  final AppLanguage language;
  final YorksWorkforceOverviewState state;
  final Future<bool> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final data = switch (state.status) {
      YorksWorkforceOverviewStatus.ready => (
        Icons.cloud_done_outlined,
        AppColors.success,
        AppColors.successContainer,
        _t(language, 'server_confirmed'),
      ),
      YorksWorkforceOverviewStatus.stale => (
        Icons.cloud_off_outlined,
        AppColors.warning,
        AppColors.warningContainer,
        _t(language, 'stale'),
      ),
      YorksWorkforceOverviewStatus.forbidden ||
      YorksWorkforceOverviewStatus.sessionExpired ||
      YorksWorkforceOverviewStatus.unavailable => (
        Icons.lock_outline,
        AppColors.error,
        AppColors.errorContainer,
        _t(language, 'denied'),
      ),
      YorksWorkforceOverviewStatus.failure ||
      YorksWorkforceOverviewStatus.offline => (
        Icons.error_outline,
        AppColors.error,
        AppColors.errorContainer,
        _t(language, 'failed'),
      ),
      _ => null,
    };
    if (data == null) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      label: data.$4,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: data.$3,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: data.$2.withValues(alpha: .28)),
        ),
        child: Row(
          children: [
            Icon(data.$1, color: data.$2),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(data.$4, style: AppTypography.bodyMedium)),
            if (state.status == YorksWorkforceOverviewStatus.failure ||
                state.status == YorksWorkforceOverviewStatus.offline)
              TextButton(
                onPressed: onRetry,
                child: Text(_t(language, 'refresh')),
              ),
          ],
        ),
      ),
    );
  }
}

class _AsOfStrip extends StatelessWidget {
  const _AsOfStrip({required this.language, required this.projection});

  final AppLanguage language;
  final YorksWorkforceOverviewProjection projection;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    children: projection.asOf
        .map(
          (item) => Chip(
            avatar: const Icon(Icons.public, size: 17),
            label: Text(
              '${_t(language, 'local_as_of')} ${item.localDate} · '
              '${item.timezone} · ${item.teamCount} ${_t(language, 'teams')}',
            ),
          ),
        )
        .toList(growable: false),
  );
}

class _SupervisorContext extends StatelessWidget {
  const _SupervisorContext({required this.language, required this.teams});

  final AppLanguage language;
  final List<YorksWorkforceOverviewTeam> teams;

  @override
  Widget build(BuildContext context) => _Panel(
    title: _t(language, 'my_team'),
    child: Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      children: teams
          .map(
            (team) => Semantics(
              label:
                  '${_t(language, 'my_team')} ${team.teamName}, '
                  '${_t(language, 'today_date')} ${team.localDate}',
              child: Container(
                constraints: const BoxConstraints(minWidth: 260),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(team.teamName, style: AppTypography.titleSmall),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _t(language, 'today_date'),
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${team.localDate} · ${team.calendarTimezone}',
                      style: AppTypography.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(growable: false),
    ),
  );
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.language, required this.projection});

  final AppLanguage language;
  final YorksWorkforceOverviewProjection projection;

  @override
  Widget build(BuildContext context) {
    final entries = _summaryEntries(projection);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1250
            ? 5
            : width >= 820
            ? 3
            : width >= 520
            ? 2
            : 1;
        final cardWidth = (width - AppSpacing.md * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: entries
              .map(
                (entry) => SizedBox(
                  width: cardWidth,
                  child: _MetricCard(language: language, entry: entry),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

typedef _MetricEntry = ({String key, num value, IconData icon, Color color});

List<_MetricEntry> _summaryEntries(YorksWorkforceOverviewProjection value) {
  final summary = value.summary;
  if (value.kind == YorksWorkforceOverviewKind.admin) {
    return [
      (
        key: 'active_workers',
        value: summary['active_worker_count']!,
        icon: Icons.groups_2_outlined,
        color: AppColors.primary,
      ),
      (
        key: 'active_supervisors',
        value: summary['active_supervisor_count']!,
        icon: Icons.supervisor_account_outlined,
        color: AppColors.success,
      ),
      (
        key: 'attendance_missing_today',
        value: summary['missing_today_count']!,
        icon: Icons.person_off_outlined,
        color: AppColors.error,
      ),
      (
        key: 'monthly_reports_pending',
        value: summary['monthly_pending_count']!,
        icon: Icons.pending_actions_outlined,
        color: AppColors.warning,
      ),
      (
        key: 'returned_for_correction',
        value: summary['returned_count']!,
        icon: Icons.assignment_return_outlined,
        color: AppColors.error,
      ),
      (
        key: 'awaiting_final_approval',
        value: summary['awaiting_final_count']!,
        icon: Icons.approval_outlined,
        color: AppColors.tertiary,
      ),
      (
        key: 'locked_periods',
        value: summary['locked_count']!,
        icon: Icons.lock_outline,
        color: AppColors.success,
      ),
      (
        key: 'reopen_requests',
        value: summary['reopen_request_count']!,
        icon: Icons.lock_open_outlined,
        color: AppColors.warning,
      ),
      (
        key: 'configuration_issues',
        value: summary['configuration_issue_count']!,
        icon: Icons.build_circle_outlined,
        color: AppColors.warning,
      ),
    ];
  }
  if (value.kind == YorksWorkforceOverviewKind.management) {
    return [
      (
        key: 'active_projects',
        value: summary['active_project_count']!,
        icon: Icons.folder_open_outlined,
        color: AppColors.tertiary,
      ),
      (
        key: 'workers_across_projects',
        value: summary['worker_count']!,
        icon: Icons.groups_2_outlined,
        color: AppColors.primary,
      ),
      (
        key: 'attendance_completion',
        value: summary['today_completion_percent']!,
        icon: Icons.fact_check_outlined,
        color: AppColors.success,
      ),
      (
        key: 'awaiting_review',
        value: summary['review_queue_count']!,
        icon: Icons.rate_review_outlined,
        color: AppColors.warning,
      ),
      (
        key: 'awaiting_approval',
        value: summary['approval_queue_count']!,
        icon: Icons.approval_outlined,
        color: AppColors.tertiary,
      ),
      (
        key: 'missing_attendance',
        value: summary['not_entered_count']!,
        icon: Icons.person_off_outlined,
        color: AppColors.error,
      ),
      (
        key: 'overtime_exceptions',
        value: summary['overtime_exception_count']!,
        icon: Icons.more_time_outlined,
        color: AppColors.warning,
      ),
      (
        key: 'returned_periods',
        value: summary['returned_count']!,
        icon: Icons.assignment_return_outlined,
        color: AppColors.error,
      ),
    ];
  }
  return [
    (
      key: 'workers',
      value: summary['worker_count']!,
      icon: Icons.groups_2_outlined,
      color: AppColors.primary,
    ),
    (
      key: 'present',
      value: summary['present_count']!,
      icon: Icons.how_to_reg_outlined,
      color: AppColors.success,
    ),
    (
      key: 'absent',
      value: summary['absent_count']!,
      icon: Icons.person_off_outlined,
      color: AppColors.error,
    ),
    (
      key: 'leave',
      value: summary['leave_count']!,
      icon: Icons.beach_access_outlined,
      color: AppColors.tertiary,
    ),
    (
      key: 'missing',
      value: summary['not_entered_count']!,
      icon: Icons.pending_actions_outlined,
      color: AppColors.warning,
    ),
    (
      key: 'today_completion',
      value: summary['today_completion_percent']!,
      icon: Icons.today_outlined,
      color: AppColors.primary,
    ),
    (
      key: 'month_completion',
      value: summary['month_completion_percent']!,
      icon: Icons.calendar_month_outlined,
      color: AppColors.success,
    ),
    (
      key: 'warnings',
      value: summary['warning_count']!,
      icon: Icons.warning_amber_outlined,
      color: AppColors.warning,
    ),
    (
      key: 'returned',
      value: summary['returned_correction_count']!,
      icon: Icons.assignment_return_outlined,
      color: AppColors.error,
    ),
  ];
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.language, required this.entry});
  final AppLanguage language;
  final _MetricEntry entry;

  @override
  Widget build(BuildContext context) {
    final percent = entry.key.endsWith('completion');
    final value = percent
        ? '${_formatNumber(entry.value)}%'
        : _formatNumber(entry.value);
    return Semantics(
      label: '${_t(language, entry.key)} $value',
      child: Container(
        constraints: const BoxConstraints(minHeight: 118),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: _cardDecoration,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: entry.color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Icon(entry.icon, color: entry.color),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _t(language, entry.key),
                    style: AppTypography.labelLarge,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(value, style: AppTypography.headlineSmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamPanel extends StatelessWidget {
  const _TeamPanel({
    required this.language,
    required this.teams,
    required this.compact,
  });
  final AppLanguage language;
  final List<YorksWorkforceOverviewTeam> teams;
  final bool compact;

  @override
  Widget build(BuildContext context) => _Panel(
    title: _t(language, 'teams'),
    child: Column(
      children: teams
          .map(
            (team) => Container(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(team.teamName, style: AppTypography.titleSmall),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${team.projectRef ?? '—'} · ${team.localDate} · ${team.calendarTimezone}',
                          style: AppTypography.bodySmall,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          '${_t(language, 'present')}: ${team.metrics.presentCount}  ·  ${_t(language, 'missing')}: ${team.metrics.notEnteredCount}',
                          style: AppTypography.bodyMedium,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                team.teamName,
                                style: AppTypography.titleSmall,
                              ),
                              Text(
                                '${team.projectRef ?? '—'} · ${team.supervisorName ?? '—'}',
                                style: AppTypography.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${team.metrics.workerCount}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${team.metrics.presentCount}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${team.metrics.notEnteredCount}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${_formatNumber(team.metrics.todayCompletionPercent)}%',
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            '${team.localDate}\n${team.calendarTimezone}',
                            style: AppTypography.bodySmall,
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
            ),
          )
          .toList(growable: false),
    ),
  );
}

class _ProjectPanel extends StatelessWidget {
  const _ProjectPanel({required this.language, required this.projects});
  final AppLanguage language;
  final List<YorksWorkforceOverviewProject> projects;

  @override
  Widget build(BuildContext context) => _Panel(
    title: _t(language, 'projects'),
    child: Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: projects
          .map(
            (project) => Container(
              width: 280,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.projectRef,
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    project.projectName,
                    style: AppTypography.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '${project.workerCount} ${_t(language, 'workers')} · ${project.missingTodayCount} ${_t(language, 'missing')}',
                    style: AppTypography.bodySmall,
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
    ),
  );
}

class _QueuePanel extends StatelessWidget {
  const _QueuePanel({required this.language, required this.items});
  final AppLanguage language;
  final List<YorksWorkforceOverviewQueueItem> items;

  @override
  Widget build(BuildContext context) => _Panel(
    title: _t(language, 'review_queue'),
    child: Column(
      children: items
          .map(
            (item) => Container(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: item.blockingIssueCount > 0
                        ? AppColors.errorContainer
                        : AppColors.warningContainer,
                    child: Icon(
                      item.blockingIssueCount > 0
                          ? Icons.error_outline
                          : Icons.rate_review_outlined,
                      color: item.blockingIssueCount > 0
                          ? AppColors.error
                          : AppColors.warning,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${item.teamName} · ${item.periodMonth}',
                                style: AppTypography.titleSmall,
                              ),
                            ),
                            Text(
                              _statusLabel(language, item.status),
                              style: AppTypography.labelMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.lg,
                          runSpacing: AppSpacing.sm,
                          children: [
                            _QueueFact(
                              label: _t(language, 'submitted_by'),
                              value: item.submittedByName ?? '—',
                            ),
                            _QueueFact(
                              label: _t(language, 'team'),
                              value: item.teamName,
                            ),
                            _QueueFact(
                              label: _t(language, 'month'),
                              value: item.periodMonth,
                            ),
                            _QueueFact(
                              label: _t(language, 'worker_count'),
                              value: '${item.workerCount}',
                            ),
                            _QueueFact(
                              label: _t(language, 'regular_ot'),
                              value:
                                  '${item.regularMinutes} / ${item.overtimeMinutes} ${_t(language, 'minutes')}',
                            ),
                            _QueueFact(
                              label: _t(language, 'warnings'),
                              value: '${item.warningCount}',
                            ),
                            _QueueFact(
                              label: _t(language, 'corrections'),
                              value: '${item.reviewerCorrectionCount}',
                            ),
                            _QueueFact(
                              label: _t(
                                language,
                                'missing_supporting_evidence',
                              ),
                              value:
                                  '${item.missingSupportingEvidenceCount} · '
                                  '${_policyLabel(language, item.supportingEvidencePolicy)}',
                            ),
                            _QueueFact(
                              label: _t(language, 'high_overtime'),
                              value:
                                  '${item.highOvertimeExceptionCount} · '
                                  '${_policyLabel(language, item.overtimeLimitPolicy)}',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
    ),
  );
}

class _QueueFact extends StatelessWidget {
  const _QueueFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label $value',
    excludeSemantics: true,
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: AppTypography.labelMedium.copyWith(color: AppColors.muted),
          ),
          TextSpan(text: value, style: AppTypography.bodySmall),
        ],
      ),
    ),
  );
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.language});
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => _Panel(
    title: _t(language, 'teams'),
    child: Semantics(
      liveRegion: true,
      label: _t(language, 'empty'),
      child: Text(_t(language, 'empty'), style: AppTypography.bodyMedium),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: _cardDecoration,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.titleMedium),
        const SizedBox(height: AppSpacing.md),
        child,
      ],
    ),
  );
}

class _ReadOnlyBoundary extends StatelessWidget {
  const _ReadOnlyBoundary({required this.language});
  final AppLanguage language;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.blueContainer,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Row(
      children: [
        const Icon(Icons.visibility_outlined, color: AppColors.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            _t(language, 'read_only_mobile'),
            style: AppTypography.bodyMedium,
          ),
        ),
      ],
    ),
  );
}

BoxDecoration get _cardDecoration => BoxDecoration(
  color: AppColors.surfaceContainerLowest,
  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
  border: Border.all(color: AppColors.line),
  boxShadow: const [
    BoxShadow(color: AppColors.shadow, blurRadius: 16, offset: Offset(0, 5)),
  ],
);

String _t(AppLanguage language, String key) =>
    YorksV1WorkforceDashboardStrings.text(language, key);

String _statusLabel(AppLanguage language, String status) {
  return _t(language, 'status_$status');
}

String _policyLabel(AppLanguage language, String policy) =>
    _t(language, 'policy_$policy');

String _formatNumber(num value) {
  final fixed = value.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}

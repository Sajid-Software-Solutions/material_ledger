/// Workforce attendance V2 — Workforce Overview: today's crews, earlier days
/// still missing, this month's overtime and confirmation, every crew's last
/// eight days and what is happening, newest first.
///
/// With the Workforce Center on (docs/yorks-v1/WORKFORCE_CENTER_DESIGN.md)
/// the same page becomes the register: My work, Crew requests and Crews.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../../../shared/providers/yorks_v1_feature_flags_provider.dart';
import '../../../accounts/presentation/v2/kit/accounts_v2_kit.dart';
import '../../application/attendance_providers.dart';
import '../../application/attendance_role_layout.dart';
import '../../domain/attendance_models.dart';
import '../../domain/attendance_time.dart';
import '../../domain/crew_request_models.dart';
import '../requests/crew_request_common.dart';
import '../requests/crew_request_kit.dart';
import 'attendance_common.dart';

/// Views of the Workforce Center.
enum WorkforceCenterView {
  myWork('my_work'),
  requests('requests'),
  crews('crews');

  const WorkforceCenterView(this.wire);
  final String wire;

  static WorkforceCenterView? from(String? value) {
    for (final view in values) {
      if (view.wire == value) return view;
    }
    return null;
  }
}

class AttendanceOverviewScreen extends ConsumerStatefulWidget {
  const AttendanceOverviewScreen({super.key, this.initialView});

  /// `my_work`, `requests` or `crews` (Workforce Center only).
  final String? initialView;

  @override
  ConsumerState<AttendanceOverviewScreen> createState() =>
      _AttendanceOverviewScreenState();
}

class _AttendanceOverviewScreenState
    extends ConsumerState<AttendanceOverviewScreen> {
  late WorkforceCenterView _view =
      WorkforceCenterView.from(widget.initialView) ??
      WorkforceCenterView.myWork;

  @override
  void didUpdateWidget(covariant AttendanceOverviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = WorkforceCenterView.from(widget.initialView);
    if (next != null && widget.initialView != oldWidget.initialView) {
      _view = next;
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = attendanceLanguage(ref);
    final center = ref.watch(yorksV1FeatureFlagsProvider).workforceCenter;
    final overview = ref.watch(yorksAttendanceOverviewProvider(null));
    return overview.when(
      loading: () => AttendanceLoadState(language: language),
      error: (error, _) => AttendanceLoadState(
        language: language,
        error: error,
        onRetry: () => ref.invalidate(yorksAttendanceOverviewProvider(null)),
      ),
      data: (data) => _OverviewBody(
        overview: data,
        language: language,
        center: center,
        view: _view,
        onView: (view) => setState(() => _view = view),
        onRefresh: () async {
          ref.invalidate(yorksAttendanceOverviewProvider(null));
          ref.invalidate(yorksAttendanceConfirmationsDueProvider);
          if (center) ref.invalidate(yorksCrewRequestsProvider);
        },
      ),
    );
  }
}

class _OverviewBody extends ConsumerWidget {
  const _OverviewBody({
    required this.overview,
    required this.language,
    required this.onRefresh,
    this.center = false,
    this.view = WorkforceCenterView.myWork,
    this.onView,
  });

  final AttendanceOverview overview;
  final AppLanguage language;
  final Future<void> Function() onRefresh;
  final bool center;
  final WorkforceCenterView view;
  final ValueChanged<WorkforceCenterView>? onView;

  bool get _anyTaker => overview.crews.any((c) => c.crew.access.take);
  bool get _readOnly =>
      overview.crews.isNotEmpty &&
      overview.crews.every((c) => c.crew.access.readOnly);

  void _openCrew(BuildContext context, AttendanceCrew crew, AttendanceMonth m) {
    if (crew.access.take || crew.access.confirm) {
      final date = m.missingDays.isNotEmpty
          ? m.missingDays.first
          : overview.today;
      context.go(
        Uri(
          path: RoutePaths.yorksV1WorkforceAttendance,
          queryParameters: {'crew': crew.id, 'date': date},
        ).toString(),
      );
      return;
    }
    context.go(
      Uri(
        path: RoutePaths.yorksV1WorkforceSheets,
        queryParameters: {'crew': crew.id},
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = overview.today;
    final crews = overview.crews;
    final layout = AttendanceRoleLayout.of(
      ref.watch(yorksV1CurrentRoleProvider),
    );
    final summary = overview.todaySummary;
    final enteredToday = crews.where((c) {
      final saved = overview.todayByCrew[c.crew.id];
      final day = c.month.days.where((d) => d.date == today).firstOrNull;
      if (saved != null) {
        return saved.entered || day?.state == AttendanceDayState.off;
      }
      return day != null &&
          (day.state == AttendanceDayState.entered ||
              day.state == AttendanceDayState.question ||
              day.state == AttendanceDayState.locked ||
              day.state == AttendanceDayState.off);
    }).length;
    final missing = <({String crew, String date})>[
      for (final c in crews)
        for (final day in c.month.missingDays)
          if (day != today) (crew: c.crew.name.split(' ').first, date: day),
    ];
    final normalOt = crews.fold<int>(
      0,
      (sum, c) => sum + c.month.normalOvertimeMinutes,
    );
    final holidayOt = crews.fold<int>(
      0,
      (sum, c) => sum + c.month.holidayOvertimeMinutes,
    );
    final reviewCrews = crews.where((c) => c.crew.needsConfirmation).toList();
    final confirmed = reviewCrews
        .where((c) => c.month.state == AttendanceMonthState.confirmed)
        .length;
    final monthEnd = crews.isEmpty ? null : crews.first.month.lastDay;
    final monthEndReached = monthEnd != null && today.compareTo(monthEnd) >= 0;
    final register = center
        ? ref.watch(yorksCrewRequestsProvider).valueOrNull
        : null;
    final canRequest = register?.canRequest ?? false;
    final dueConfirmations = center
        ? ref.watch(yorksAttendanceConfirmationsDueProvider).valueOrNull ??
              const <AttendanceConfirmationDue>[]
        : const <AttendanceConfirmationDue>[];
    final dayItems = [
      for (final c in crews)
        if (c.crew.access.take && c.month.missingDays.isNotEmpty) c,
    ];
    final myWorkCount =
        (register?.mine.length ?? 0) +
        dueConfirmations.length +
        dayItems.length;

    final kpis = AccountsV2KpiRow(
      children: [
        AccountsV2KpiCard(
          icon: 'check',
          label: AS.t(AS.kpiToday, language, {
            'date': attendanceShortDate(today),
          }),
          value: AS.t(AS.kpiCrewsOf, language, {
            'a': enteredToday,
            'b': crews.length,
          }),
          caption: enteredToday == crews.length
              ? AS.t(AS.kpiAllEntered, language)
              : AS.t(AS.kpiNotYet, language, {
                  'n': crews.length - enteredToday,
                }),
          tone: AccountsV2Tone.green,
        ),
        if (summary != null)
          AccountsV2KpiCard(
            key: const ValueKey('attendance-kpi-working-today'),
            icon: 'users',
            label: AS.t(AS.kpiWorkingToday, language),
            value: AS.t(AS.kpiWorkingValue, language, {'n': summary.present}),
            caption: AS.t(AS.kpiWorkingCaption, language, {
              'a': summary.absent,
              'l': summary.leave,
            }),
            tone: AccountsV2Tone.blue,
          )
        else
          AccountsV2KpiCard(
            icon: 'alert',
            label: AS.t(AS.kpiEarlierMissing, language),
            value: '${missing.length}',
            caption: missing.isEmpty
                ? AS.t(AS.kpiNothingMissing, language)
                : missing
                      .take(2)
                      .map((m) => '${m.crew} ${attendanceShortDate(m.date)}')
                      .join(', '),
            tone: missing.isEmpty ? AccountsV2Tone.green : AccountsV2Tone.red,
            valueTone: missing.isEmpty
                ? AccountsV2ValueTone.ok
                : AccountsV2ValueTone.bad,
          ),
        AccountsV2KpiCard(
          icon: 'clock',
          label: AS.t(AS.kpiOvertime, language),
          value: AS.t(AS.kpiHoursNormal, language, {
            'h': formatAttendanceHours(normalOt, zeroAsDash: true),
          }),
          caption: AS.t(AS.kpiHoursHoliday, language, {
            'h': formatAttendanceHours(holidayOt, zeroAsDash: true),
          }),
          tone: AccountsV2Tone.org,
        ),
        AccountsV2KpiCard(
          icon: 'shield',
          label: AS.t(AS.kpiConfirmation, language, {
            'month': attendanceMonthName(overview.month),
          }),
          value: reviewCrews.isEmpty
              ? '—'
              : AS.t(AS.kpiCrewsOf, language, {
                  'a': confirmed,
                  'b': reviewCrews.length,
                }),
          caption: monthEnd == null
              ? ''
              : monthEndReached
              ? AS.t(AS.kpiNotifiedToday, language)
              : AS.t(AS.kpiNotified, language, {
                  'date': attendanceShortDate(monthEnd),
                }),
          tone: AccountsV2Tone.vio,
        ),
        if (center)
          AccountsV2KpiCard(
            icon: 'users',
            label: CRS.t(CRS.kpiOpenRequests, language),
            value: register == null ? '—' : '${register.open}',
            caption: (register?.mine.isEmpty ?? true)
                ? CRS.t(CRS.kpiNothingForYou, language)
                : CRS.t(CRS.kpiWaitingForYou, language, {
                    'n': register!.mine.length,
                  }),
            tone: AccountsV2Tone.blue,
            valueTone: (register?.mine.isEmpty ?? true)
                ? AccountsV2ValueTone.plain
                : AccountsV2ValueTone.bad,
          ),
      ],
    );

    final crewsCard = _CrewsCard(
      overview: overview,
      language: language,
      sites: !layout.isOffice,
      onOpen: (crew, month) => _openCrew(context, crew, month),
    );
    final feedCard = _FeedCard(overview: overview, language: language);
    // The office gets what needs a look beside what happened.
    final lowerCards = layout.isOffice
        ? _SideBySide(
            first: _NeedsLookCard(
              overview: overview,
              language: language,
              onOpen: (crewId, date) => context.go(
                Uri(
                  path: RoutePaths.yorksV1WorkforceAttendance,
                  queryParameters: {'crew': crewId, 'date': date},
                ).toString(),
              ),
            ),
            second: feedCard,
          )
        : feedCard;

    return AttendancePage(
      language: language,
      onRefresh: onRefresh,
      title: center
          ? CRS.t(CRS.centerTitle, language)
          : AS.t(switch (AttendanceRoleLayout.of(
              ref.watch(yorksV1CurrentRoleProvider),
            )) {
              AttendanceRoleLayout.engineer => AS.mySites,
              AttendanceRoleLayout.reader => AS.sites,
              _ => AS.overview,
            }, language),
      subtitle:
          '${center ? CRS.t(CRS.centerIntro, language) : AS.t(_readOnly
                    ? AS.overviewReadOnlyIntro
                    : layout == AttendanceRoleLayout.engineer
                    ? AS.mySitesIntro
                    : layout.isOffice
                    ? AS.officeIntro
                    : AS.overviewIntro, language)}  ·  ${attendanceFullDate(today)}',
      readOnly: _readOnly && !canRequest,
      actions: [
        if (center && canRequest)
          AccountsV2Button(
            key: const ValueKey('workforce-center-request-crew'),
            label: CRS.t(CRS.requestCrew, language),
            icon: 'plus',
            kind: _anyTaker
                ? AccountsV2ButtonKind.normal
                : AccountsV2ButtonKind.primary,
            onPressed: () => context.go(crewRequestNewPath),
          ),
        if (_anyTaker)
          AccountsV2Button(
            key: const ValueKey('attendance-overview-take'),
            label: AS.t(AS.takeAttendance, language),
            icon: 'check',
            kind: AccountsV2ButtonKind.primary,
            onPressed: () => context.go(RoutePaths.yorksV1WorkforceAttendance),
          ),
      ],
      children: [
        ...AttendanceConfirmationsBanner.forPage(
          ref,
          onConfirm: (month) => context.go(
            Uri(
              path: RoutePaths.yorksV1WorkforceConfirm,
              queryParameters: {'month': month},
            ).toString(),
          ),
        ),
        kpis,
        if (!center) ...[
          crewsCard,
          lowerCards,
        ] else ...[
          _CenterViewTabs(
            view: view,
            language: language,
            myWorkCount: myWorkCount,
            requestCount: register?.open ?? 0,
            crewCount: crews.length,
            onView: onView,
          ),
          switch (view) {
            WorkforceCenterView.myWork => _MyWorkCard(
              language: language,
              register: register,
              confirmations: dueConfirmations,
              dayCrews: dayItems,
              today: today,
            ),
            WorkforceCenterView.requests => _RequestsCard(
              language: language,
              register: register,
              error: ref.watch(yorksCrewRequestsProvider).error,
            ),
            WorkforceCenterView.crews => crewsCard,
          },
          if (view == WorkforceCenterView.crews) lowerCards,
        ],
      ],
    );
  }
}

// ─── Workforce Center ────────────────────────────────────────────────────────

class _CenterViewTabs extends StatelessWidget {
  const _CenterViewTabs({
    required this.view,
    required this.language,
    required this.myWorkCount,
    required this.requestCount,
    required this.crewCount,
    this.onView,
  });

  final WorkforceCenterView view;
  final AppLanguage language;
  final int myWorkCount;
  final int requestCount;
  final int crewCount;
  final ValueChanged<WorkforceCenterView>? onView;

  @override
  Widget build(BuildContext context) {
    Widget tab(WorkforceCenterView value, String label, int count) {
      final selected = value == view;
      return Semantics(
        selected: selected,
        button: true,
        child: AccountsV2Button(
          key: ValueKey('workforce-center-view-${value.wire}'),
          label: count > 0 ? '$label · $count' : label,
          kind: selected
              ? AccountsV2ButtonKind.primary
              : AccountsV2ButtonKind.normal,
          onPressed: onView == null ? null : () => onView!(value),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          tab(
            WorkforceCenterView.myWork,
            CRS.t(CRS.viewMyWork, language),
            myWorkCount,
          ),
          const SizedBox(width: 8),
          tab(
            WorkforceCenterView.requests,
            CRS.t(CRS.viewRequests, language),
            requestCount,
          ),
          const SizedBox(width: 8),
          tab(
            WorkforceCenterView.crews,
            CRS.t(CRS.viewCrews, language),
            crewCount,
          ),
        ],
      ),
    );
  }
}

class _WorkItem {
  const _WorkItem({
    required this.key,
    required this.title,
    required this.detail,
    required this.action,
    required this.onTap,
    this.urgent = false,
  });

  final String key;
  final String title;
  final String detail;
  final String action;
  final VoidCallback onTap;
  final bool urgent;
}

class _MyWorkCard extends StatelessWidget {
  const _MyWorkCard({
    required this.language,
    required this.register,
    required this.confirmations,
    required this.dayCrews,
    required this.today,
  });

  final AppLanguage language;
  final CrewRequestRegister? register;
  final List<AttendanceConfirmationDue> confirmations;
  final List<({AttendanceCrew crew, AttendanceMonth month})> dayCrews;
  final String today;

  @override
  Widget build(BuildContext context) {
    final items = <_WorkItem>[
      for (final due in confirmations)
        _WorkItem(
          key: 'confirm-${due.crewId}-${due.month}',
          title: CRS.t(CRS.itemConfirm, language, {
            'month': attendanceMonthYear(due.month),
            'crew': due.crewName,
          }),
          detail: due.overdue
              ? AS.t(AS.dueOverdue, language, {
                  'month': attendanceMonthYear(due.month),
                })
              : AS.t(AS.dueToday, language, {
                  'month': attendanceMonthYear(due.month),
                }),
          action: AS.t(AS.confirmNow, language),
          urgent: due.overdue,
          onTap: () => context.go(
            Uri(
              path: RoutePaths.yorksV1WorkforceConfirm,
              queryParameters: {'month': due.month},
            ).toString(),
          ),
        ),
      for (final request in [
        ...?register?.mine,
      ]..sort((a, b) => a.neededFrom.compareTo(b.neededFrom)))
        _WorkItem(
          key: 'request-${request.id}',
          title: CRS.t(CRS.itemRequest, language, {
            'next': crewRequestNextStep(request, language),
            'number': request.number,
          }),
          detail:
              '${crewRequestWhere(request, language)} · ${crewRequestPeople(request)} · ${crewRequestDates(request, language)}',
          action: CRS.t(CRS.open, language),
          urgent: request.overdue,
          onTap: () => context.go(crewRequestPath(request.id)),
        ),
      for (final item in dayCrews)
        _WorkItem(
          key: 'day-${item.crew.id}',
          title: CRS.t(CRS.itemDayMissing, language, {'crew': item.crew.name}),
          detail: item.month.missingDays
              .take(4)
              .map(attendanceShortDate)
              .join(', '),
          action: AS.t(AS.takeAttendance, language),
          urgent: item.month.missingDays.any((d) => d != today),
          onTap: () => context.go(
            Uri(
              path: RoutePaths.yorksV1WorkforceAttendance,
              queryParameters: {
                'crew': item.crew.id,
                'date': item.month.missingDays.first,
              },
            ).toString(),
          ),
        ),
    ];
    return AccountsV2Panel(
      key: const ValueKey('workforce-center-my-work'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2CardHead(
            title: CRS.t(CRS.viewMyWork, language),
            icon: 'check',
            subtitle: CRS.t(CRS.myWorkSub, language),
          ),
          if (items.isEmpty)
            AccountsV2Empty(
              icon: 'check',
              title: CRS.t(CRS.myWorkEmpty, language),
            )
          else
            for (final item in items)
              InkWell(
                key: ValueKey('workforce-center-item-${item.key}'),
                onTap: item.onTap,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: AccountsV2Colors.line2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: item.urgent
                              ? AccountsV2Colors.bad
                              : AccountsV2Colors.pri,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: v2Style(13.5, weight: FontWeight.w600),
                            ),
                            if (item.detail.isNotEmpty)
                              Text(
                                item.detail,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: v2Style(12, color: AccountsV2Colors.mut),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      AccountsV2Button(
                        label: item.action,
                        size: AccountsV2ButtonSize.small,
                        kind: item.urgent
                            ? AccountsV2ButtonKind.primary
                            : AccountsV2ButtonKind.normal,
                        onPressed: item.onTap,
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

class _RequestsCard extends StatefulWidget {
  const _RequestsCard({
    required this.language,
    required this.register,
    this.error,
  });

  final AppLanguage language;
  final CrewRequestRegister? register;
  final Object? error;

  @override
  State<_RequestsCard> createState() => _RequestsCardState();
}

class _RequestsCardState extends State<_RequestsCard> {
  bool _showFinished = false;

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final register = widget.register;
    if (register == null) {
      return AccountsV2Panel(
        child: widget.error == null
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : AccountsV2Empty(
                icon: 'alert',
                title: crewRequestErrorText(widget.error, language),
              ),
      );
    }
    final rows = [
      for (final request in register.requests)
        if (_showFinished || request.state.isOpen) request,
    ];
    final finished = register.requests.length - register.open;
    return AccountsV2Panel(
      key: const ValueKey('workforce-center-requests'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2CardHead(
            title: CRS.t(CRS.viewRequests, language),
            icon: 'users',
            subtitle: CRS.t(CRS.requestsSub, language),
          ),
          if (finished > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilterChip(
                  key: const ValueKey('workforce-center-show-finished'),
                  label: Text('${CRS.t(CRS.showClosed, language)} · $finished'),
                  selected: _showFinished,
                  onSelected: (value) => setState(() => _showFinished = value),
                ),
              ),
            ),
          if (rows.isEmpty)
            AccountsV2Empty(
              icon: 'users',
              title: CRS.t(CRS.requestsEmpty, language),
              body: CRS.t(CRS.requestsEmptyBody, language),
              action: register.canRequest
                  ? AccountsV2Button(
                      label: CRS.t(CRS.requestCrew, language),
                      icon: 'plus',
                      onPressed: () => context.go(crewRequestNewPath),
                    )
                  : null,
            )
          else ...[
            for (final request in rows)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: CrewRequestCard(
                  key: ValueKey('crew-request-row-${request.id}'),
                  request: request,
                  language: language,
                  onOpen: () => context.go(crewRequestPath(request.id)),
                ),
              ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: AccountsV2Button(
                key: const ValueKey('workforce-center-open-register'),
                label: CRS.t(CRS.openAll, language),
                icon: 'list',
                onPressed: () =>
                    context.go(RoutePaths.yorksV1WorkforceRequests),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CrewsCard extends StatelessWidget {
  const _CrewsCard({
    required this.overview,
    required this.language,
    required this.onOpen,
    this.sites = false,
  });

  final AttendanceOverview overview;
  final AppLanguage language;
  final void Function(AttendanceCrew crew, AttendanceMonth month) onOpen;

  /// Engineers see their projects as Sites; the office sees Places.
  final bool sites;

  /// Today for one place: saved (by whom, when), not saved, or a rest day.
  Widget _today(AttendancePlaceToday? today, AttendanceDayState? state) {
    // Today from the server when it sends it; else the month's day.
    final entered =
        today?.entered ??
        (state == AttendanceDayState.entered ||
            state == AttendanceDayState.question ||
            state == AttendanceDayState.locked);
    final rest = !entered && state == AttendanceDayState.off;
    final by = today?.lastSavedBy;
    final at = today?.lastSavedAt;
    final detail = [
      if (by != null && by.isNotEmpty) by.split(' ').first,
      if (at != null) DateFormat('HH:mm').format(at.toLocal()),
    ].join(' · ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AccountsV2Chip(
          AS.t(
            entered
                ? AS.dayEntered
                : rest
                ? AS.restDay
                : AS.dayNone,
            language,
          ),
          tone: entered
              ? AccountsV2ChipTone.ok
              : rest
              ? AccountsV2ChipTone.neutral
              : AccountsV2ChipTone.bad,
        ),
        if (entered && detail.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: v2Style(11.5, color: AccountsV2Colors.mut),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = overview.today;
    final from = attendanceShift(today, -7);
    final title = AS.t(sites ? AS.sites : AS.crews, language);
    if (overview.crews.isEmpty) {
      return AccountsV2Panel(
        child: AccountsV2Empty(
          icon: 'users',
          title: title,
          body: AS.t(AS.noCrews, language),
          action: AccountsV2Button(
            label: AS.t(AS.takeAttendance, language),
            icon: 'plus',
            onPressed: () => context.go(RoutePaths.yorksV1WorkforceAttendance),
          ),
        ),
      );
    }
    List<({String date, AttendanceDayState state, bool holiday})> last8(
      AttendanceMonth month,
    ) {
      final byDate = {for (final day in month.days) day.date: day};
      return [
        for (var i = 0; i < 8; i++)
          byDate[attendanceShift(from, i)] ??
              (
                date: attendanceShift(from, i),
                state: AttendanceDayState.off,
                holiday: false,
              ),
      ];
    }

    return AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2CardHead(
            title: title,
            icon: 'users',
            subtitle: AS.t(AS.crewsCardSub, language),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: AttendanceLegend(language: language),
          ),
          AccountsV2Table(
            phoneCards: true,
            minWidth: 940,
            columns: [
              AccountsV2Column(
                AS.t(sites ? AS.colSite : AS.colCrew, language),
                flex: 3,
              ),
              AccountsV2Column(AS.t(AS.colToday, language), width: 150),
              AccountsV2Column(AS.t(AS.colLast8, language), width: 200),
              AccountsV2Column(
                AS.t(AS.present, language),
                width: 84,
                numeric: true,
              ),
              AccountsV2Column(
                AS.t(AS.colOtNormal, language),
                width: 116,
                numeric: true,
              ),
              AccountsV2Column(
                AS.t(AS.colOtHoliday, language),
                width: 116,
                numeric: true,
              ),
              AccountsV2Column(AS.t(AS.colMonth, language), width: 220),
            ],
            rows: [
              for (final item in overview.crews)
                AccountsV2Row(
                  key: ValueKey('attendance-crew-${item.crew.id}'),
                  onTap: () => onOpen(item.crew, item.month),
                  [
                    AccountsV2CellStack(
                      primary: item.crew.name,
                      secondary: item.crew.workLabel,
                    ),
                    _today(
                      overview.todayByCrew[item.crew.id],
                      item.month.days
                          .where((d) => d.date == today)
                          .firstOrNull
                          ?.state,
                    ),
                    AttendanceStatusSquares(days: last8(item.month)),
                    Text(
                      switch (overview.todayByCrew[item.crew.id]) {
                        final t? when t.entered => '${t.present}',
                        _ => '—',
                      },
                      key: ValueKey('attendance-present-${item.crew.id}'),
                      style: v2Style(13, tabular: true),
                    ),
                    Text(
                      formatAttendanceHours(
                        item.month.normalOvertimeMinutes,
                        zeroAsDash: true,
                      ),
                      style: v2Style(13, tabular: true),
                    ),
                    Text(
                      formatAttendanceHours(
                        item.month.holidayOvertimeMinutes,
                        zeroAsDash: true,
                      ),
                      style: v2Style(
                        13,
                        tabular: true,
                        color: item.month.holidayOvertimeMinutes > 0
                            ? AccountsV2Colors.vio
                            : AccountsV2Colors.ink,
                      ),
                    ),
                    Builder(
                      builder: (context) {
                        final chip = attendanceMonthChip(item.month, language);
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: AccountsV2Chip(chip.text, tone: chip.tone),
                        );
                      },
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Two cards side by side on a wide screen, one above the other on a phone.
class _SideBySide extends StatelessWidget {
  const _SideBySide({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    if (AccountsV2Breakpoints.isPhone(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          first,
          const SizedBox(height: accountsV2Gap),
          second,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: accountsV2Gap),
        Expanded(child: second),
      ],
    );
  }
}

/// For the office: places not entered today, questions still open and lines
/// changed after they were saved, each opening its day.
class _NeedsLookCard extends StatelessWidget {
  const _NeedsLookCard({
    required this.overview,
    required this.language,
    required this.onOpen,
  });

  final AttendanceOverview overview;
  final AppLanguage language;
  final void Function(String crewId, String date) onOpen;

  List<({String key, String text, String crewId, String date, bool urgent})>
  _items() {
    final today = overview.today;
    final items =
        <({String key, String text, String crewId, String date, bool urgent})>[
          for (final item in overview.crews)
            if (!(overview.todayByCrew[item.crew.id]?.entered ?? true) &&
                item.month.days.any(
                  (d) =>
                      d.date == today &&
                      d.state != AttendanceDayState.off &&
                      d.state != AttendanceDayState.future,
                ))
              (
                key: 'today-${item.crew.id}',
                text: AS.t(AS.lookNotEntered, language, {
                  'place': item.crew.name,
                }),
                crewId: item.crew.id,
                date: today,
                urgent: true,
              ),
        ];
    // The feed is newest first: an answer above a question closes it.
    final answered = <String>{};
    for (final event in overview.feed) {
      final date = event.date;
      if (date == null) continue;
      final dayKey = '${event.crewId}|$date';
      if (event.kind == 'answered') answered.add(dayKey);
      if (event.kind == 'asked' && !answered.contains(dayKey)) {
        items.add((
          key: 'asked-${event.crewId}-$date',
          text: AS.t(AS.lookQuestion, language, {
            'place': event.crewName,
            'date': attendanceShortDate(date),
          }),
          crewId: event.crewId,
          date: date,
          urgent: false,
        ));
      }
      if (event.kind == 'changed') {
        items.add((
          key: 'changed-${event.crewId}-$date-${items.length}',
          text: AS.t(AS.lookChanged, language, {
            'place': event.crewName,
            'by': event.by.split(' ').first,
            'date': attendanceShortDate(date),
          }),
          crewId: event.crewId,
          date: date,
          urgent: false,
        ));
      }
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items();
    return AccountsV2Panel(
      key: const ValueKey('attendance-needs-look'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2CardHead(
            title: AS.t(AS.needsLook, language),
            icon: 'alert',
            subtitle: AS.t(AS.needsLookSub, language),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Text(
                AS.t(AS.needsNothing, language),
                style: v2Style(13, color: AccountsV2Colors.mut),
              ),
            )
          else
            for (final item in items.take(8))
              InkWell(
                key: ValueKey('attendance-look-${item.key}'),
                onTap: () => onOpen(item.crewId, item.date),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: AccountsV2Colors.line2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: item.urgent
                              ? AccountsV2Colors.bad
                              : AccountsV2Colors.warn,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.text,
                          style: v2Style(13, weight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        AS.t(AS.openDay, language),
                        style: v2Style(
                          12.5,
                          weight: FontWeight.w600,
                          color: AccountsV2Colors.pri,
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

class _FeedCard extends StatelessWidget {
  const _FeedCard({required this.overview, required this.language});

  final AttendanceOverview overview;
  final AppLanguage language;

  String _line(AttendanceFeedItem item) {
    final values = {
      'by': item.by,
      'crew': item.crewName,
      'date': item.date == null
          ? ''
          : item.kind == 'confirmed' || item.kind == 'reopened'
          ? attendanceMonthYear(item.date!)
          : attendanceShortDate(item.date!),
    };
    final template = switch (item.kind) {
      'entered' => AS.feedEntered,
      'changed' => AS.feedChanged,
      'asked' => AS.feedAsked,
      'answered' => AS.feedAnswered,
      'confirmed' => AS.feedConfirmed,
      _ => AS.feedReopened,
    };
    return AS.t(template, language, values);
  }

  String _detail(AttendanceFeedItem item) {
    final summary = item.summary;
    if (item.kind == 'asked') return '“${summary['question'] ?? ''}”';
    if (item.kind == 'answered') return '“${summary['answer'] ?? ''}”';
    if (item.kind == 'reopened') return '“${summary['reason'] ?? ''}”';
    if (item.kind == 'confirmed') return '';
    final base = AS.t(AS.feedSummary, language, {
      'p': summary['present'] ?? 0,
      'a': summary['absent'] ?? 0,
      'l': summary['leave'] ?? 0,
    });
    final ot = (summary['normal_overtime_minutes'] as num?)?.toInt() ?? 0;
    final hol = (summary['holiday_overtime_minutes'] as num?)?.toInt() ?? 0;
    final reason = summary['reason'];
    return [
      base,
      if (ot > 0) AS.t(AS.otHours, language, {'h': formatAttendanceHours(ot)}),
      if (hol > 0)
        AS.t(AS.holHours, language, {'h': formatAttendanceHours(hol)}),
      if (reason is String && reason.isNotEmpty) '“$reason”',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2CardHead(
            title: AS.t(AS.feedTitle, language),
            icon: 'history',
            subtitle: AS.t(AS.feedSub, language),
          ),
          if (overview.feed.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Text(
                AS.t(AS.nothingYet, language),
                style: v2Style(13, color: AccountsV2Colors.mut),
              ),
            )
          else
            for (final item in overview.feed.take(7))
              InkWell(
                onTap: item.date == null || item.kind == 'confirmed'
                    ? null
                    : () => context.go(
                        Uri(
                          path: RoutePaths.yorksV1WorkforceAttendance,
                          queryParameters: {
                            'crew': item.crewId,
                            'date': item.date!,
                          },
                        ).toString(),
                      ),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: AccountsV2Colors.line2),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _line(item),
                              style: v2Style(13, weight: FontWeight.w600),
                            ),
                            if (_detail(item).isNotEmpty)
                              Text(
                                _detail(item),
                                style: v2Style(12, color: AccountsV2Colors.mut),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        attendanceStamp(item.at),
                        style: v2Style(12, color: AccountsV2Colors.mut2),
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

/// Workforce attendance V2 — Workforce Overview: today's crews, earlier days
/// still missing, this month's overtime and confirmation, every crew's last
/// eight days and what is happening, newest first.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../shared/models/app_language.dart';
import '../../../accounts/presentation/v2/kit/accounts_v2_kit.dart';
import '../../application/attendance_providers.dart';
import '../../domain/attendance_models.dart';
import '../../domain/attendance_time.dart';
import 'attendance_common.dart';

class AttendanceOverviewScreen extends ConsumerWidget {
  const AttendanceOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = attendanceLanguage(ref);
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
        onRefresh: () async {
          ref.invalidate(yorksAttendanceOverviewProvider(null));
          ref.invalidate(yorksAttendanceConfirmationsDueProvider);
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
  });

  final AttendanceOverview overview;
  final AppLanguage language;
  final Future<void> Function() onRefresh;

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
    final enteredToday = crews.where((c) {
      final day = c.month.days.where((d) => d.date == today).firstOrNull;
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

    return AttendancePage(
      language: language,
      onRefresh: onRefresh,
      title: AS.t(AS.overview, language),
      subtitle:
          '${AS.t(_readOnly ? AS.overviewReadOnlyIntro : AS.overviewIntro, language)}  ·  ${attendanceFullDate(today)}',
      readOnly: _readOnly,
      actions: [
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
        AccountsV2KpiRow(
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
          ],
        ),
        _CrewsCard(
          overview: overview,
          language: language,
          onOpen: (crew, month) => _openCrew(context, crew, month),
        ),
        _FeedCard(overview: overview, language: language),
      ],
    );
  }
}

class _CrewsCard extends StatelessWidget {
  const _CrewsCard({
    required this.overview,
    required this.language,
    required this.onOpen,
  });

  final AttendanceOverview overview;
  final AppLanguage language;
  final void Function(AttendanceCrew crew, AttendanceMonth month) onOpen;

  @override
  Widget build(BuildContext context) {
    final today = overview.today;
    final from = attendanceShift(today, -7);
    if (overview.crews.isEmpty) {
      return AccountsV2Panel(
        child: AccountsV2Empty(
          icon: 'users',
          title: AS.t(AS.crews, language),
          body: AS.t(AS.noCrews, language),
          action: AccountsV2Button(
            label: AS.t(AS.newCrew, language),
            icon: 'plus',
            onPressed: () => context.go(RoutePaths.yorksV1WorkforceCrews),
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
            title: AS.t(AS.crews, language),
            icon: 'users',
            subtitle: AS.t(AS.crewsCardSub, language),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: AttendanceLegend(language: language),
          ),
          AccountsV2Table(
            phoneCards: true,
            minWidth: 860,
            columns: [
              AccountsV2Column(AS.t(AS.colCrew, language), flex: 3),
              AccountsV2Column(AS.t(AS.colLast8, language), width: 200),
              AccountsV2Column(
                AS.t(AS.colDaysEntered, language),
                width: 110,
                numeric: true,
              ),
              AccountsV2Column(
                AS.t(AS.colOtNormal, language),
                width: 124,
                numeric: true,
              ),
              AccountsV2Column(
                AS.t(AS.colOtHoliday, language),
                width: 124,
                numeric: true,
              ),
              AccountsV2Column(AS.t(AS.colMonth, language), width: 250),
            ],
            rows: [
              for (final item in overview.crews)
                AccountsV2Row(
                  key: ValueKey('attendance-crew-${item.crew.id}'),
                  onTap: () => onOpen(item.crew, item.month),
                  [
                    AccountsV2CellStack(
                      primary: item.crew.name,
                      secondary:
                          '${item.crew.workLabel} · ${AS.t(AS.workersCount, language, {'n': item.crew.memberCount})}',
                    ),
                    AttendanceStatusSquares(days: last8(item.month)),
                    Text(
                      AS.t(AS.daysOf, language, {
                        'a': item.month.daysEntered,
                        'b': item.month.workDaysSoFar,
                      }),
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

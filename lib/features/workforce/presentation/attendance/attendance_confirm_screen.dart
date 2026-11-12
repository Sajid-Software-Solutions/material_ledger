/// Workforce attendance V2 — Month confirmation. No daily approval: the
/// confirmer watches each crew's month, steps into any day, and confirms
/// once on the last day when every working day is entered.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../shared/models/app_language.dart';
import '../../../accounts/presentation/v2/kit/accounts_v2_kit.dart';
import '../../application/attendance_providers.dart';
import '../../data/attendance_repository.dart';
import '../../domain/attendance_models.dart';
import '../../domain/attendance_time.dart';
import 'attendance_common.dart';
import 'attendance_dialogs.dart';

class AttendanceConfirmScreen extends ConsumerStatefulWidget {
  const AttendanceConfirmScreen({super.key});

  @override
  ConsumerState<AttendanceConfirmScreen> createState() =>
      _AttendanceConfirmScreenState();
}

class _AttendanceConfirmScreenState
    extends ConsumerState<AttendanceConfirmScreen> {
  /// `YYYY-MM-01`, or null for the current month. Last month stays one tap
  /// away so a month can still be confirmed in the first days after it ends.
  String? _month;

  @override
  Widget build(BuildContext context) {
    final language = attendanceLanguage(ref);
    final overview = ref.watch(yorksAttendanceOverviewProvider(_month));
    return overview.when(
      loading: () => AttendanceLoadState(language: language),
      error: (error, _) => AttendanceLoadState(
        language: language,
        error: error,
        onRetry: () => ref.invalidate(yorksAttendanceOverviewProvider(_month)),
      ),
      data: (data) {
        final crews = [
          for (final item in data.crews)
            if (item.crew.needsConfirmation &&
                (item.crew.access.confirm || item.crew.access.officer))
              item,
        ];
        final lastDay = crews.isEmpty ? null : crews.first.month.lastDay;
        final current = attendanceMonthOf(data.today);
        final months = [
          for (var i = 0; i < 3; i++)
            attendanceMonthOf(
              attendanceIso(
                DateTime(
                  attendanceDate(current).year,
                  attendanceDate(current).month - i,
                ),
              ),
            ),
        ];
        return AttendancePage(
          language: language,
          title: AS.t(AS.monthConfirmation, language),
          subtitle: AS.t(AS.confirmIntro, language),
          onRefresh: () async =>
              ref.invalidate(yorksAttendanceOverviewProvider(_month)),
          actions: [
            AccountsV2Select<String>(
              key: const ValueKey('attendance-confirm-month-picker'),
              label: AS.t(AS.colMonth, language),
              value: data.month,
              width: 190,
              options: [
                for (final month in months) (month, attendanceMonthYear(month)),
              ],
              onChanged: (month) =>
                  setState(() => _month = month == current ? null : month),
            ),
          ],
          children: [
            if (lastDay != null && data.today.compareTo(lastDay) < 0)
              AccountsV2Note(
                child: Text(
                  AS.t(AS.nextConfirmation, language, {
                    'date': attendanceLongDate(lastDay),
                  }),
                ),
              ),
            if (crews.isEmpty)
              AccountsV2Panel(
                child: AccountsV2Empty(
                  icon: 'shield',
                  title: AS.t(AS.monthConfirmation, language),
                  body: AS.t(AS.noReviewCrews, language),
                ),
              ),
            for (final item in crews)
              _CrewMonthCard(
                key: ValueKey('attendance-confirm-${item.crew.id}'),
                crew: item.crew,
                month: item.month,
                today: data.today,
                language: language,
                onChanged: () =>
                    ref.invalidate(yorksAttendanceOverviewProvider(_month)),
              ),
          ],
        );
      },
    );
  }
}

class _CrewMonthCard extends ConsumerStatefulWidget {
  const _CrewMonthCard({
    super.key,
    required this.crew,
    required this.month,
    required this.today,
    required this.language,
    required this.onChanged,
  });

  final AttendanceCrew crew;
  final AttendanceMonth month;
  final String today;
  final AppLanguage language;
  final VoidCallback onChanged;

  @override
  ConsumerState<_CrewMonthCard> createState() => _CrewMonthCardState();
}

class _CrewMonthCardState extends ConsumerState<_CrewMonthCard> {
  bool _busy = false;

  AppLanguage get _language => widget.language;

  List<({String text, AccountsV2ChipTone tone, String date})> _flags(
    AttendanceMonthSheet sheet,
  ) {
    final flags = <({String text, AccountsV2ChipTone tone, String date})>[];
    for (final worker in sheet.workers) {
      for (final day in worker.days) {
        final holiday =
            sheet.month.days
                .where((d) => d.date == day.date)
                .firstOrNull
                ?.holiday ??
            false;
        final minutes = day.row.minutes(holiday: holiday);
        if (minutes.normalOvertime > 120) {
          final note = day.row.overtimeNote;
          flags.add((
            text:
                '${AS.t(AS.flagOvertime, _language, {'worker': worker.worker.name, 'date': attendanceShortDate(day.date), 'h': formatAttendanceHours(minutes.normalOvertime)})}${note == null ? '' : ' — $note'}',
            tone: AccountsV2ChipTone.warn,
            date: day.date,
          ));
        }
        if (minutes.holidayOvertime > 0) {
          flags.add((
            text: AS.t(AS.flagHoliday, _language, {
              'worker': worker.worker.name,
              'date': attendanceShortDate(day.date),
              'h': formatAttendanceHours(minutes.holidayOvertime),
            }),
            tone: AccountsV2ChipTone.vio,
            date: day.date,
          ));
        }
      }
    }
    for (final day in sheet.month.days) {
      if (day.state == AttendanceDayState.question) {
        flags.add((
          text: AS.t(AS.flagQuestion, _language, {
            'date': attendanceShortDate(day.date),
          }),
          tone: AccountsV2ChipTone.bad,
          date: day.date,
        ));
      }
    }
    return flags;
  }

  void _openDay(String date) => context.go(
    Uri(
      path: RoutePaths.yorksV1WorkforceAttendance,
      queryParameters: {'crew': widget.crew.id, 'date': date},
    ).toString(),
  );

  /// The crew, month and totals the confirmer is about to lock.
  String get _summary {
    final month = widget.month;
    return '${widget.crew.name} · ${attendanceMonthYear(month.month)} · '
        '${AS.t(AS.daysOf, _language, {'a': month.daysEntered, 'b': month.workDaysSoFar})} '
        '${AS.t(AS.daysEnteredLabel, _language)} · '
        '${AS.t(AS.otHours, _language, {'h': formatAttendanceHours(month.normalOvertimeMinutes, zeroAsDash: true)})} · '
        '${AS.t(AS.holHours, _language, {'h': formatAttendanceHours(month.holidayOvertimeMinutes, zeroAsDash: true)})}';
  }

  Future<void> _confirm() async {
    final language = _language;
    final monthName = attendanceMonthName(widget.month.month);
    final done = await showAttendanceCommandDialog(
      context,
      language: language,
      title: AS.t(AS.confirmMonthButton, language, {'month': monthName}),
      summary: _summary,
      body: AS.t(AS.confirmMonthQuestion, language, {
        'month': monthName,
        'crew': widget.crew.name,
      }),
      confirmLabel: AS.t(AS.confirmMonthButton, language, {'month': monthName}),
      command: (_) => _command(
        () => ref
            .read(yorksAttendanceRepositoryProvider)
            .confirmMonth(
              crewId: widget.crew.id,
              month: widget.month.month,
              idempotencyKey: YorksAttendanceRepository.newKey(),
            ),
      ),
    );
    if (done == null || !mounted) return;
    _finished(
      AS.t(AS.confirmedToast, language, {
        'crew': widget.crew.name,
        'month': monthName,
      }),
    );
  }

  Future<void> _reopen() async {
    final language = _language;
    final monthName = attendanceMonthName(widget.month.month);
    final reason = await showAttendanceCommandDialog(
      context,
      language: language,
      title: AS.t(AS.reopen, language),
      summary: _summary,
      body: AS.t(AS.reopenQuestion, language, {
        'month': monthName,
        'crew': widget.crew.name,
      }),
      fieldLabel: AS.t(AS.reasonLabel, language),
      confirmLabel: AS.t(AS.reopen, language),
      destructive: true,
      command: (text) => _command(
        () => ref
            .read(yorksAttendanceRepositoryProvider)
            .reopenMonth(
              crewId: widget.crew.id,
              month: widget.month.month,
              reason: text,
              idempotencyKey: YorksAttendanceRepository.newKey(),
            ),
      ),
    );
    if (reason == null || !mounted) return;
    _finished(AS.t(AS.reopenedToast, language, {'month': monthName}));
  }

  /// Runs a month command for the dialog: null when the server confirmed.
  Future<Object?> _command(Future<AttendanceMonth> Function() run) async {
    setState(() => _busy = true);
    try {
      await run();
      return null;
    } catch (error) {
      return error;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _finished(String message) {
    attendanceToast(context, message);
    ref.invalidate(yorksAttendanceOverviewProvider(null));
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final language = _language;
    final crew = widget.crew;
    final month = widget.month;
    final chip = attendanceMonthChip(month, language);
    final sheet = ref.watch(
      yorksAttendanceMonthSheetProvider((crewId: crew.id, month: month.month)),
    );
    final flags = sheet.valueOrNull == null
        ? const <({String text, AccountsV2ChipTone tone, String date})>[]
        : _flags(sheet.valueOrNull!);
    final beforeEnd = widget.today.compareTo(month.lastDay) < 0;
    final missingNow = month.missingDays;

    String footer() {
      if (month.isConfirmed) {
        return AS.t(AS.confirmedAt, language, {
          'name': month.confirmedBy,
          'at': attendanceStamp(month.confirmedAt),
        });
      }
      if (beforeEnd) {
        return AS.t(AS.opensOn, language, {
          'date': attendanceShortDate(month.lastDay),
        });
      }
      if (missingNow.isNotEmpty) {
        return AS.t(AS.daysMissingList, language, {
          'n': missingNow.length,
          'list': missingNow.map(attendanceShortDate).join(', '),
        });
      }
      return AS.t(AS.allEnteredLocks, language);
    }

    return AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2CardHead(
            title: '${crew.name} · ${attendanceMonthYear(month.month)}',
            icon: 'shield',
            subtitle: crew.workLabel,
            actions: [AccountsV2Chip(chip.text, tone: chip.tone)],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
            child: Text(
              AS.t(AS.selectDay, language),
              style: v2Style(12, color: AccountsV2Colors.mut),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: AttendanceDayStrip(
              days: month.days,
              selected: null,
              onSelect: _openDay,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: AccountsV2Grid(
              columns: AccountsV2Breakpoints.isPhone(context) ? 2 : 4,
              children: [
                AccountsV2MiniStat(
                  label: AS.t(AS.daysEnteredLabel, language),
                  value: AS.t(AS.daysOf, language, {
                    'a': month.daysEntered,
                    'b': month.workDaysSoFar,
                  }),
                  caption: '',
                ),
                AccountsV2MiniStat(
                  label: AS.t(AS.notEnteredLabel, language),
                  value: '${missingNow.length}',
                  caption: '',
                  tone: missingNow.isEmpty
                      ? AccountsV2ValueTone.ok
                      : AccountsV2ValueTone.bad,
                ),
                AccountsV2MiniStat(
                  label: AS.t(AS.colOtNormal, language),
                  value: formatAttendanceHours(
                    month.normalOvertimeMinutes,
                    zeroAsDash: true,
                  ),
                  caption: '',
                  tone: AccountsV2ValueTone.warn,
                ),
                AccountsV2MiniStat(
                  label: AS.t(AS.colOtHoliday, language),
                  value: formatAttendanceHours(
                    month.holidayOvertimeMinutes,
                    zeroAsDash: true,
                  ),
                  caption: '',
                  tone: AccountsV2ValueTone.vio,
                ),
              ],
            ),
          ),
          if (flags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AS.t(AS.worthALook, language),
                    style: v2Style(13, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final flag in flags.take(6))
                        InkWell(
                          onTap: () => _openDay(flag.date),
                          borderRadius: BorderRadius.circular(999),
                          child: AccountsV2Chip(flag.text, tone: flag.tone),
                        ),
                      if (flags.length > 6)
                        AccountsV2Chip(
                          AS.t(AS.moreFlags, language, {'n': flags.length - 6}),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AccountsV2Colors.line)),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  footer(),
                  style: v2Style(12.5, color: AccountsV2Colors.mut),
                ),
                if (month.isConfirmed && crew.access.officer)
                  AccountsV2Button(
                    key: ValueKey('attendance-reopen-${crew.id}'),
                    label: AS.t(AS.reopen, language),
                    icon: 'undo',
                    onPressed: _busy ? null : _reopen,
                  )
                else if (!month.isConfirmed && crew.access.confirm)
                  AccountsV2Button(
                    key: ValueKey('attendance-confirm-month-${crew.id}'),
                    label: AS.t(AS.confirmMonthButton, language, {
                      'month': attendanceMonthName(month.month),
                    }),
                    icon: 'check',
                    kind: AccountsV2ButtonKind.primary,
                    onPressed: month.canConfirm && !_busy ? _confirm : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

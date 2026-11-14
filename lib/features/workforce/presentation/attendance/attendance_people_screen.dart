/// Workforce attendance — the monthly overview of everyone, one labourer's
/// timesheet and the workforce year (PRODUCT_DECISIONS section 52).
///
/// Month: every labourer recorded at the places the reader may see, day by
/// day, for this month or any earlier one, filtered by place and searched by
/// name or number. Desktop shows the month as a grid with the names, the
/// days and the totals always in view; phones show one card per labourer.
/// Opening a labourer shows their timesheet across every place, ready to
/// print. Year: totals by month, by place and by labourer. Changing the
/// period keeps the page in place while the next one loads.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../shared/models/app_language.dart';
import '../../../accounts/presentation/v2/kit/accounts_v2_kit.dart';
import '../../application/attendance_providers.dart';
import '../../data/attendance_sheet_service.dart';
import '../../domain/attendance_models.dart';
import '../../domain/attendance_month_models.dart';
import '../../domain/attendance_search.dart';
import '../../domain/attendance_time.dart';
import 'attendance_common.dart';
import 'attendance_inputs.dart';

/// `YYYY-MM-01` of [iso] moved by [months].
String _shiftMonth(String iso, int months) {
  final date = attendanceDate(iso);
  return attendanceIso(DateTime(date.year, date.month + months));
}

class AttendancePeopleScreen extends ConsumerStatefulWidget {
  const AttendancePeopleScreen({
    super.key,
    this.initialView,
    this.initialMonth,
    this.initialYear,
    this.initialWorkerId,
    this.initialPlaceId,
  });

  final String? initialView;
  final String? initialMonth;
  final String? initialYear;
  final String? initialWorkerId;
  final String? initialPlaceId;

  @override
  ConsumerState<AttendancePeopleScreen> createState() =>
      _AttendancePeopleScreenState();
}

class _AttendancePeopleScreenState
    extends ConsumerState<AttendancePeopleScreen> {
  final _search = TextEditingController();

  bool get _yearView => widget.initialView == 'year';

  String get _thisMonth => attendanceMonthOf(attendanceLocalToday());

  String get _month {
    final month = widget.initialMonth;
    if (month == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(month)) {
      return _thisMonth;
    }
    return attendanceMonthOf(month);
  }

  int get _year =>
      int.tryParse(widget.initialYear ?? '') ?? attendanceDate(_thisMonth).year;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _go({
    String? view,
    String? month,
    int? year,
    String? workerId,
    String? placeId,
    bool clearWorker = false,
    bool clearPlace = false,
  }) {
    final params = <String, String>{
      'view': view ?? (_yearView ? 'year' : 'month'),
      'month': month ?? _month,
      'year': '${year ?? _year}',
      if (!clearWorker && (workerId ?? widget.initialWorkerId) != null)
        'worker': workerId ?? widget.initialWorkerId!,
      if (!clearPlace && (placeId ?? widget.initialPlaceId) != null)
        'place': placeId ?? widget.initialPlaceId!,
    };
    context.go(
      Uri(
        path: RoutePaths.yorksV1WorkforceMonth,
        queryParameters: params,
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final language = attendanceLanguage(ref);
    final workerId = widget.initialWorkerId;
    final month = _month;
    final year = _year;
    final thisYear = attendanceDate(_thisMonth).year;

    final toggle = Wrap(
      spacing: 6,
      children: [
        AttendanceChoiceChip(
          key: const ValueKey('attendance-overview-month'),
          label: AS.t(AS.viewMonth, language),
          selected: !_yearView,
          onPressed: () => _go(view: 'month', clearWorker: true),
        ),
        AttendanceChoiceChip(
          key: const ValueKey('attendance-overview-year'),
          label: AS.t(AS.viewYear, language),
          selected: _yearView,
          onPressed: () => _go(view: 'year', clearWorker: true),
        ),
      ],
    );

    final period = _PeriodNavigator(
      label: _yearView ? '$year' : attendanceMonthYear(month),
      language: language,
      onPrevious: () => _yearView
          ? _go(year: year - 1)
          : _go(month: _shiftMonth(month, -1), year: year),
      onNext: _yearView
          ? (year >= thisYear ? null : () => _go(year: year + 1))
          : (month.compareTo(_thisMonth) >= 0
                ? null
                : () => _go(month: _shiftMonth(month, 1))),
    );

    final Widget body;
    if (!_yearView && workerId != null) {
      body = _TimesheetView(
        key: ValueKey('timesheet-$workerId'),
        workerId: workerId,
        month: month,
        language: language,
        period: period,
        onBack: () => _go(clearWorker: true),
      );
    } else if (_yearView) {
      body = _YearView(
        year: year,
        language: language,
        period: period,
        onOpenMonth: (iso) => _go(
          view: 'month',
          month: iso,
          year: attendanceDate(iso).year,
          clearWorker: true,
        ),
        onOpenWorker: (id) => _go(
          view: 'month',
          workerId: id,
          month: year == thisYear ? _thisMonth : '$year-12-01',
        ),
      );
    } else {
      body = _MonthView(
        month: month,
        language: language,
        period: period,
        search: _search,
        placeId: widget.initialPlaceId,
        onPlace: (placeId) => placeId == null
            ? _go(clearPlace: true, clearWorker: true)
            : _go(placeId: placeId, clearWorker: true),
        onOpenWorker: (id) => _go(workerId: id),
      );
    }

    return AttendancePage(
      language: language,
      title: AS.t(AS.monthOverview, language),
      subtitle: AS.t(AS.monthOverviewIntro, language),
      subtitleOnPhone: false,
      actions: [toggle],
      children: [body],
    );
  }
}

/// ‹ November 2026 ›
class _PeriodNavigator extends StatelessWidget {
  const _PeriodNavigator({
    required this.label,
    required this.language,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final AppLanguage language;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const ValueKey('attendance-period-previous'),
          tooltip: AS.t(AS.previousPeriod, language),
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 130),
          child: Text(
            label,
            key: const ValueKey('attendance-period-label'),
            textAlign: TextAlign.center,
            style: v2Style(16, weight: FontWeight.w700),
          ),
        ),
        IconButton(
          key: const ValueKey('attendance-period-next'),
          tooltip: AS.t(AS.nextPeriod, language),
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        ),
      ],
    );
  }
}

/// A thin bar under the period controls while the next period loads.
Widget _loadingBar(bool loading, String label) => SizedBox(
  height: 3,
  child: loading
      ? Semantics(
          label: label,
          child: const LinearProgressIndicator(
            key: ValueKey('attendance-period-loading'),
            minHeight: 3,
          ),
        )
      : null,
);

/// The first load, inside the page rather than over it.
Widget _firstLoad(
  AsyncValue<Object?> value,
  AppLanguage language,
  VoidCallback onRetry,
) => AccountsV2Panel(
  child: value.hasError
      ? AccountsV2Empty(
          icon: 'alert',
          title: attendanceErrorText(value.error, language),
          action: AccountsV2Button(
            label: AS.t(AS.retry, language),
            icon: 'undo',
            onPressed: onRetry,
          ),
        )
      : const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
);

/// Fades the shown period while the next one loads.
Widget _fading(BuildContext context, bool loading, Widget child) =>
    AnimatedOpacity(
      opacity: loading ? 0.5 : 1,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 150),
      child: IgnorePointer(ignoring: loading, child: child),
    );

String _hours(AppLanguage language, int minutes) => AS.t(
  AS.hoursValue,
  language,
  {'h': formatAttendanceHours(minutes, zeroAsDash: true)},
);

// ─── Month ───────────────────────────────────────────────────────────────────

class _MonthView extends ConsumerStatefulWidget {
  const _MonthView({
    required this.month,
    required this.language,
    required this.period,
    required this.search,
    required this.onPlace,
    required this.onOpenWorker,
    this.placeId,
  });

  final String month;
  final AppLanguage language;
  final Widget period;
  final TextEditingController search;
  final String? placeId;
  final ValueChanged<String?> onPlace;
  final ValueChanged<String> onOpenWorker;

  @override
  ConsumerState<_MonthView> createState() => _MonthViewState();
}

class _MonthViewState extends ConsumerState<_MonthView> {
  AttendancePeopleMonth? _shown;

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final value = ref.watch(yorksAttendancePeopleMonthProvider(widget.month));
    final current = value.valueOrNull;
    if (current != null) _shown = current;
    final data = current ?? _shown;
    final loading = current == null && !value.hasError;

    final places = data?.places ?? const <AttendanceMonthPlace>[];
    final placeId = places.any((p) => p.id == widget.placeId)
        ? widget.placeId
        : null;
    final controls = AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 14, 10),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                widget.period,
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (places.length > 1)
                      AccountsV2Select<String>(
                        key: const ValueKey('attendance-overview-place'),
                        label: AS.t(AS.colCrew, language),
                        width: 240,
                        value: placeId ?? '',
                        options: [
                          ('', AS.t(AS.allPlaces, language)),
                          for (final place in places) (place.id, place.label),
                        ],
                        onChanged: (id) =>
                            widget.onPlace(id.isEmpty ? null : id),
                      ),
                    SizedBox(
                      width: AccountsV2Breakpoints.isPhone(context)
                          ? double.infinity
                          : 240,
                      child: AccountsV2TextField(
                        key: const ValueKey('attendance-overview-search'),
                        label: AS.t(AS.searchPeople, language),
                        controller: widget.search,
                        search: true,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _loadingBar(
            loading && data != null,
            AS.t(AS.loadingPeriod, language, {
              'period': attendanceMonthYear(widget.month),
            }),
          ),
        ],
      ),
    );

    if (data == null) {
      return AccountsV2Stack(
        children: [
          controls,
          _firstLoad(
            value,
            language,
            () => ref.invalidate(
              yorksAttendancePeopleMonthProvider(widget.month),
            ),
          ),
        ],
      );
    }

    final everyone = data.people(placeId: placeId);
    final query = widget.search.text.trim();
    final people = query.isEmpty
        ? everyone
        : [
            for (final hit in attendanceFuzzySearch(
              query,
              everyone,
              (p) => '${p.person.name} ${p.person.number}',
              limit: everyone.length,
            ))
              hit.item,
          ];
    final present = everyone.fold(0, (sum, p) => sum + p.presentDays);
    final regular = everyone.fold(0, (sum, p) => sum + p.regular);
    final normalOt = everyone.fold(0, (sum, p) => sum + p.normalOvertime);
    final holidayOt = everyone.fold(0, (sum, p) => sum + p.holidayOvertime);

    final kpis = AccountsV2KpiRow(
      children: [
        AccountsV2KpiCard(
          icon: 'users',
          label: AS.t(AS.kpiLabourers, language),
          value: '${everyone.length}',
          caption: AS.t(AS.kpiLabourersMonth, language),
        ),
        AccountsV2KpiCard(
          icon: 'check',
          label: AS.t(AS.kpiPresentDays, language),
          value: '$present',
          caption: AS.t(AS.kpiPresentDaysCaption, language),
          tone: AccountsV2Tone.green,
        ),
        AccountsV2KpiCard(
          icon: 'clock',
          label: AS.t(AS.kpiNormalHours, language),
          value: _hours(language, regular),
          caption: AS.t(AS.kpiNormalHoursCaption, language),
          tone: AccountsV2Tone.neu,
        ),
        AccountsV2KpiCard(
          icon: 'spark',
          label: AS.t(AS.kpiOvertimeShort, language),
          value: _hours(language, normalOt),
          caption: AS.t(AS.kpiOvertimeHoliday, language, {
            'h': formatAttendanceHours(holidayOt, zeroAsDash: true),
          }),
          tone: AccountsV2Tone.org,
        ),
      ],
    );

    final Widget list;
    if (everyone.isEmpty) {
      list = AccountsV2Panel(
        child: AccountsV2Empty(
          key: const ValueKey('attendance-overview-empty'),
          icon: 'users',
          title: AS.t(AS.monthEmpty, language, {
            'month': attendanceMonthYear(data.month),
          }),
        ),
      );
    } else if (people.isEmpty) {
      list = AccountsV2Panel(
        child: AccountsV2Empty(
          icon: 'search',
          title: AS.t(AS.noMatchWorker, language),
        ),
      );
    } else if (AccountsV2Breakpoints.isNarrow(context)) {
      list = AccountsV2Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final person in people)
              _PersonCard(
                month: person,
                language: language,
                onTap: () => widget.onOpenWorker(person.person.id),
              ),
          ],
        ),
      );
    } else {
      list = AccountsV2Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountsV2CardHead(
              title: attendanceMonthYear(data.month),
              icon: 'grid',
              subtitle: AS.t(AS.monthLegend, language),
            ),
            _MonthGrid(
              key: ValueKey('attendance-month-grid-${data.month}'),
              people: people,
              days: data.days,
              language: language,
              onOpen: widget.onOpenWorker,
            ),
          ],
        ),
      );
    }

    return AccountsV2Stack(
      children: [
        controls,
        _fading(context, loading, AccountsV2Stack(children: [kpis, list])),
      ],
    );
  }
}

/// A labourer's month on a phone.
class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.month,
    required this.language,
    required this.onTap,
  });

  final AttendancePersonMonth month;
  final AppLanguage language;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final person = month.person;
    final parts = [
      month.presentDays == 1
          ? AS.t(AS.daysPresentOne, language)
          : AS.t(AS.daysPresentShort, language, {'n': month.presentDays}),
      _hours(language, month.regular),
      if (month.normalOvertime > 0)
        AS.t(AS.otHours, language, {
          'h': formatAttendanceHours(month.normalOvertime),
        }),
      if (month.holidayOvertime > 0)
        AS.t(AS.holHours, language, {
          'h': formatAttendanceHours(month.holidayOvertime),
        }),
      if (month.absentDays > 0)
        AS.t(AS.absentCount, language, {'n': month.absentDays}),
      if (month.leaveDays > 0)
        AS.t(AS.leaveCount, language, {'n': month.leaveDays}),
    ];
    return Semantics(
      button: true,
      label: AS.t(AS.openTimesheet, language, {'name': person.name}),
      child: InkWell(
        key: ValueKey('attendance-person-${person.id}'),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AccountsV2Colors.line2)),
          ),
          child: Row(
            children: [
              AttendanceAvatar(initials: person.initials, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.name,
                      style: v2Style(14, weight: FontWeight.w700),
                    ),
                    Text(
                      [
                        person.number,
                        person.designation,
                      ].where((p) => p.isNotEmpty).join(' · '),
                      style: v2Style(11.5, color: AccountsV2Colors.mut),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      parts.join(' · '),
                      style: v2Style(12.5, weight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AccountsV2Colors.mut,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Everyone's month as a grid: names on the left, days across, totals on
/// the right; the names, the day row and the totals stay in view while the
/// days scroll.
class _MonthGrid extends StatefulWidget {
  const _MonthGrid({
    super.key,
    required this.people,
    required this.days,
    required this.language,
    required this.onOpen,
  });

  final List<AttendancePersonMonth> people;
  final List<AttendanceCalendarDay> days;
  final AppLanguage language;
  final ValueChanged<String> onOpen;

  @override
  State<_MonthGrid> createState() => _MonthGridState();
}

class _MonthGridState extends State<_MonthGrid> {
  static const _rowHeight = 44.0;
  static const _headHeight = 46.0;
  static const _nameWidth = 230.0;
  static const _dayWidth = 36.0;
  static const _totalWidth = 78.0;

  final _names = ScrollController();
  final _cells = ScrollController();
  final _totals = ScrollController();
  final _across = ScrollController();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    for (final controller in [_names, _cells, _totals]) {
      controller.addListener(() => _sync(controller));
    }
  }

  /// Keeps the three columns scrolled to the same row.
  void _sync(ScrollController from) {
    if (_syncing) return;
    _syncing = true;
    for (final other in [_names, _cells, _totals]) {
      if (other != from && other.hasClients && other.offset != from.offset) {
        other.jumpTo(
          from.offset.clamp(0, other.position.maxScrollExtent).toDouble(),
        );
      }
    }
    _syncing = false;
  }

  @override
  void dispose() {
    for (final controller in [_names, _cells, _totals, _across]) {
      controller.dispose();
    }
    super.dispose();
  }

  TextStyle get _head => v2Style(
    11,
    weight: FontWeight.w700,
    color: AccountsV2Colors.mut,
    letterSpacing: 0.3,
  );

  Widget _cell(
    String workerId,
    AttendanceDayTotal? total,
    AttendanceCalendarDay day,
  ) {
    final language = widget.language;
    final status = total?.status;
    final present = status == AttendanceStatus.present;
    final text = switch (status) {
      null => '',
      AttendanceStatus.present => formatAttendanceHours(
        total!.worked,
        zeroAsDash: true,
      ),
      AttendanceStatus.absent => 'A',
      AttendanceStatus.rest => '–',
      _ => 'L',
    };
    final color = switch (status) {
      AttendanceStatus.present when total!.holidayOvertime > 0 =>
        AccountsV2Colors.vio,
      AttendanceStatus.present when total!.normalOvertime > 0 =>
        AccountsV2Colors.org,
      AttendanceStatus.present => AccountsV2Colors.ink,
      AttendanceStatus.absent => AccountsV2Colors.bad,
      AttendanceStatus.rest || null => AccountsV2Colors.mut,
      _ => AccountsV2Colors.pri,
    };
    final cell = Container(
      key: ValueKey('attendance-month-cell-$workerId-${day.date}'),
      width: _dayWidth,
      height: _rowHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: day.holiday ? AccountsV2Colors.tableHead : null,
        border: const Border(bottom: BorderSide(color: AccountsV2Colors.line2)),
      ),
      child: Text(
        text,
        style: v2Style(
          12.5,
          weight: present ? FontWeight.w700 : FontWeight.w600,
          color: color,
          tabular: true,
        ),
      ),
    );
    if (total == null) return cell;
    final detail = [
      attendanceShortDate(day.date),
      attendanceStatusLabel(status).active(language),
      if (present) _hours(language, total.worked),
      if (total.normalOvertime > 0)
        AS.t(AS.otHours, language, {
          'h': formatAttendanceHours(total.normalOvertime),
        }),
      if (total.holidayOvertime > 0)
        AS.t(AS.holHours, language, {
          'h': formatAttendanceHours(total.holidayOvertime),
        }),
      if (total.places > 1)
        AS.t(AS.placesWorked, language, {'n': total.places}),
    ].join(' · ');
    return Tooltip(message: detail, child: cell);
  }

  Widget _number(int minutes, {Color color = AccountsV2Colors.ink}) =>
      Container(
        width: _totalWidth,
        height: _rowHeight,
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AccountsV2Colors.line2)),
        ),
        child: Text(
          formatAttendanceHours(minutes, zeroAsDash: true),
          style: v2Style(
            12.5,
            weight: FontWeight.w600,
            color: color,
            tabular: true,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final people = widget.people;
    final days = widget.days;
    final height = math.min(
      _headHeight + people.length * _rowHeight + 2,
      MediaQuery.sizeOf(context).height * 0.72,
    );
    final totalsHeads = [
      AS.t(AS.colDays, language),
      AS.t(AS.colNormalH, language),
      AS.t(AS.colOtH, language),
      AS.t(AS.colHolH, language),
    ];

    Widget head(String text, double width, {bool end = false}) => Container(
      width: width,
      height: _headHeight,
      alignment: end
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      padding: EdgeInsetsDirectional.only(
        start: end ? 0 : 14,
        end: end ? 10 : 0,
      ),
      color: AccountsV2Colors.tableHead,
      child: Text(
        text.toUpperCase(),
        maxLines: 2,
        textAlign: end ? TextAlign.end : TextAlign.start,
        style: _head,
      ),
    );

    final names = SizedBox(
      width: _nameWidth,
      child: Column(
        children: [
          head(AS.t(AS.colWorker, language), _nameWidth),
          Expanded(
            child: ListView.builder(
              controller: _names,
              itemExtent: _rowHeight,
              itemCount: people.length,
              itemBuilder: (context, index) {
                final person = people[index].person;
                return Semantics(
                  button: true,
                  label: AS.t(AS.openTimesheet, language, {
                    'name': person.name,
                  }),
                  excludeSemantics: true,
                  child: InkWell(
                    key: ValueKey('attendance-grid-person-${person.id}'),
                    onTap: () => widget.onOpen(person.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: AccountsV2Colors.line2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  person.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: v2Style(
                                    13,
                                    weight: FontWeight.w600,
                                    color: AccountsV2Colors.pri,
                                  ),
                                ),
                                Text(
                                  [
                                    person.number,
                                    person.designation,
                                  ].where((p) => p.isNotEmpty).join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: v2Style(
                                    11,
                                    color: AccountsV2Colors.mut,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );

    final dayHeads = Row(
      children: [
        for (final day in days)
          Container(
            width: _dayWidth,
            height: _headHeight,
            alignment: Alignment.center,
            color: day.holiday
                ? AccountsV2Colors.line2
                : AccountsV2Colors.tableHead,
            child: Tooltip(
              message: day.holidayName ?? attendanceLongDate(day.date),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    attendanceShortDate(day.date).substring(0, 1),
                    style: _head,
                  ),
                  Text(
                    '${attendanceDate(day.date).day}',
                    style: v2Style(
                      12,
                      weight: FontWeight.w700,
                      color: AccountsV2Colors.ink2,
                      tabular: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    final cells = Expanded(
      child: Scrollbar(
        controller: _across,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _across,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: days.length * _dayWidth,
            child: Column(
              children: [
                dayHeads,
                Expanded(
                  child: ListView.builder(
                    controller: _cells,
                    itemExtent: _rowHeight,
                    itemCount: people.length,
                    itemBuilder: (context, index) {
                      final person = people[index];
                      return Row(
                        children: [
                          for (final day in days)
                            _cell(person.person.id, person.days[day.date], day),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final totals = DecoratedBox(
      decoration: const BoxDecoration(
        border: BorderDirectional(
          start: BorderSide(color: AccountsV2Colors.line),
        ),
      ),
      child: SizedBox(
        width: _totalWidth * 4,
        child: Column(
          children: [
            Row(
              children: [
                for (final text in totalsHeads)
                  head(text, _totalWidth, end: true),
              ],
            ),
            Expanded(
              child: ListView.builder(
                controller: _totals,
                itemExtent: _rowHeight,
                itemCount: people.length,
                itemBuilder: (context, index) {
                  final person = people[index];
                  return Row(
                    children: [
                      Container(
                        width: _totalWidth,
                        height: _rowHeight,
                        alignment: AlignmentDirectional.centerEnd,
                        padding: const EdgeInsetsDirectional.only(end: 10),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: AccountsV2Colors.line2),
                          ),
                        ),
                        child: Text(
                          '${person.presentDays}',
                          style: v2Style(
                            12.5,
                            weight: FontWeight.w700,
                            tabular: true,
                          ),
                        ),
                      ),
                      _number(person.regular),
                      _number(
                        person.normalOvertime,
                        color: person.normalOvertime > 0
                            ? AccountsV2Colors.org
                            : AccountsV2Colors.ink,
                      ),
                      _number(
                        person.holidayOvertime,
                        color: person.holidayOvertime > 0
                            ? AccountsV2Colors.vio
                            : AccountsV2Colors.ink,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    return SizedBox(
      key: const ValueKey('attendance-month-grid'),
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [names, cells, totals],
      ),
    );
  }
}

// ─── One labourer's month ────────────────────────────────────────────────────

class _TimesheetView extends ConsumerStatefulWidget {
  const _TimesheetView({
    super.key,
    required this.workerId,
    required this.month,
    required this.language,
    required this.period,
    required this.onBack,
  });

  final String workerId;
  final String month;
  final AppLanguage language;
  final Widget period;
  final VoidCallback onBack;

  @override
  ConsumerState<_TimesheetView> createState() => _TimesheetViewState();
}

class _TimesheetViewState extends ConsumerState<_TimesheetView> {
  AttendanceWorkerMonth? _shown;
  bool _printing = false;

  Future<void> _print(AttendanceWorkerMonth sheet) async {
    setState(() => _printing = true);
    try {
      await const YorksAttendanceSheetService().printWorkerMonth(sheet);
    } catch (_) {
      if (mounted) {
        attendanceToast(context, AS.t(AS.errGeneric, widget.language));
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final key = (workerId: widget.workerId, month: widget.month);
    final value = ref.watch(yorksAttendanceWorkerMonthProvider(key));
    final current = value.valueOrNull;
    if (current != null) _shown = current;
    final data = current ?? _shown;
    final loading = current == null && !value.hasError;
    final phone = AccountsV2Breakpoints.isPhone(context);

    final controls = AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 14, 10),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AccountsV2Button(
                      key: const ValueKey('attendance-timesheet-back'),
                      label: AS.t(AS.backToEveryone, language),
                      icon: 'users',
                      kind: AccountsV2ButtonKind.ghost,
                      onPressed: widget.onBack,
                    ),
                    widget.period,
                  ],
                ),
                AccountsV2Button(
                  key: const ValueKey('attendance-timesheet-print'),
                  label: AS.t(AS.printTimesheet, language),
                  icon: 'print',
                  kind: AccountsV2ButtonKind.primary,
                  onPressed: data == null || loading || _printing
                      ? null
                      : () => _print(data),
                ),
              ],
            ),
          ),
          _loadingBar(
            loading && data != null,
            AS.t(AS.loadingPeriod, language, {
              'period': attendanceMonthYear(widget.month),
            }),
          ),
        ],
      ),
    );

    if (data == null) {
      return AccountsV2Stack(
        children: [
          controls,
          _firstLoad(
            value,
            language,
            () => ref.invalidate(yorksAttendanceWorkerMonthProvider(key)),
          ),
        ],
      );
    }

    final worker = data.worker;
    final holidays = {
      for (final day in data.days)
        if (day.holiday) day.date,
    };
    final head = AccountsV2CardHead(
      title: worker.name,
      icon: 'users',
      subtitle: [
        worker.number,
        worker.designation,
        worker.company,
        AS.t(AS.timesheetTitle, language, {
          'month': attendanceMonthYear(data.month),
        }),
      ].where((p) => p.isNotEmpty).join(' · '),
    );
    final kpis = AccountsV2KpiRow(
      children: [
        AccountsV2KpiCard(
          icon: 'check',
          label: AS.t(AS.kpiPresentDays, language),
          value: '${data.presentDays}',
          caption: AS.t(AS.kpiPresentDaysCaption, language),
          tone: AccountsV2Tone.green,
        ),
        AccountsV2KpiCard(
          icon: 'clock',
          label: AS.t(AS.kpiNormalHours, language),
          value: _hours(language, data.regular),
          caption: AS.t(AS.kpiNormalHoursCaption, language),
          tone: AccountsV2Tone.neu,
        ),
        AccountsV2KpiCard(
          icon: 'spark',
          label: AS.t(AS.kpiOvertimeShort, language),
          value: _hours(language, data.normalOvertime),
          caption: AS.t(AS.kpiOvertimeHoliday, language, {
            'h': formatAttendanceHours(data.holidayOvertime, zeroAsDash: true),
          }),
          tone: AccountsV2Tone.org,
        ),
      ],
    );

    String time(int? minute) => formatAttendanceTime(minute);
    final Widget body;
    if (data.rows.isEmpty) {
      body = AccountsV2Empty(
        key: const ValueKey('attendance-timesheet-empty'),
        icon: 'doc',
        title: AS.t(AS.timesheetEmpty, language, {
          'name': worker.name,
          'month': attendanceMonthYear(data.month),
        }),
      );
    } else if (phone) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in data.rows)
            _TimesheetCard(
              row: row,
              holiday: holidays.contains(row.date),
              language: language,
            ),
        ],
      );
    } else {
      body = AccountsV2Table(
        phoneCards: true,
        minWidth: 1160,
        columns: [
          AccountsV2Column(AS.t(AS.colDate, language), width: 104),
          AccountsV2Column(AS.t(AS.colWhere, language), flex: 3),
          AccountsV2Column(
            AS.t(AS.colStatus, language),
            width: 110,
            cardBadge: true,
          ),
          AccountsV2Column(AS.t(AS.colIn, language), width: 86),
          AccountsV2Column(AS.t(AS.colBreak, language), width: 80),
          AccountsV2Column(AS.t(AS.colBack, language), width: 80),
          AccountsV2Column(AS.t(AS.colOut, language), width: 86),
          AccountsV2Column(
            AS.t(AS.colHours, language),
            width: 70,
            numeric: true,
          ),
          AccountsV2Column(AS.t(AS.colOtH, language), width: 64, numeric: true),
          AccountsV2Column(
            AS.t(AS.colHolH, language),
            width: 90,
            numeric: true,
          ),
          AccountsV2Column(AS.t(AS.colSavedBy, language), flex: 2),
        ],
        rows: [
          for (final row in data.rows)
            AccountsV2Row([
              Text(
                attendanceShortDate(row.date),
                style: v2Style(
                  13,
                  weight: FontWeight.w600,
                  color: holidays.contains(row.date)
                      ? AccountsV2Colors.vio
                      : AccountsV2Colors.ink,
                ),
              ),
              Text(row.where, style: v2Style(13)),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AccountsV2Chip(
                  attendanceStatusLabel(row.row.status).active(language),
                  tone: switch (row.row.status) {
                    AttendanceStatus.present => AccountsV2ChipTone.ok,
                    AttendanceStatus.absent => AccountsV2ChipTone.bad,
                    _ => AccountsV2ChipTone.neutral,
                  },
                ),
              ),
              Text(time(row.row.start), style: v2Style(13, tabular: true)),
              Text(time(row.row.breakStart), style: v2Style(13, tabular: true)),
              Text(
                time(row.row.breakFinish),
                style: v2Style(13, tabular: true),
              ),
              Text(time(row.row.finish), style: v2Style(13, tabular: true)),
              Text(
                formatAttendanceHours(row.worked, zeroAsDash: true),
                style: v2Style(13, weight: FontWeight.w700, tabular: true),
              ),
              Text(
                formatAttendanceHours(row.normalOvertime, zeroAsDash: true),
                style: v2Style(
                  13,
                  tabular: true,
                  color: row.normalOvertime > 0
                      ? AccountsV2Colors.org
                      : AccountsV2Colors.ink,
                ),
              ),
              Text(
                formatAttendanceHours(row.holidayOvertime, zeroAsDash: true),
                style: v2Style(
                  13,
                  tabular: true,
                  color: row.holidayOvertime > 0
                      ? AccountsV2Colors.vio
                      : AccountsV2Colors.ink,
                ),
              ),
              Text(
                row.savedBy ?? '',
                style: v2Style(12.5, color: AccountsV2Colors.mut),
              ),
            ]),
        ],
      );
    }

    return AccountsV2Stack(
      children: [
        controls,
        _fading(
          context,
          loading,
          AccountsV2Stack(
            children: [
              kpis,
              AccountsV2Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    head,
                    body,
                    if (data.rows.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.all(phone ? 12 : 16),
                        child: Text(
                          data.allConfirmed
                              ? AS.t(AS.timesheetConfirmed, language)
                              : AS.t(AS.timesheetNotConfirmed, language),
                          key: const ValueKey('attendance-timesheet-note'),
                          style: v2Style(12.5, color: AccountsV2Colors.mut),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One line of a labourer's timesheet on a phone.
class _TimesheetCard extends StatelessWidget {
  const _TimesheetCard({
    required this.row,
    required this.holiday,
    required this.language,
  });

  final AttendanceTimesheetRow row;
  final bool holiday;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final present = row.row.status == AttendanceStatus.present;
    final times = present
        ? [
            '${formatAttendanceTime(row.row.start)} – ${formatAttendanceTime(row.row.finish)}',
            _hours(language, row.worked),
            if (row.normalOvertime > 0)
              AS.t(AS.otHours, language, {
                'h': formatAttendanceHours(row.normalOvertime),
              }),
            if (row.holidayOvertime > 0)
              AS.t(AS.holHours, language, {
                'h': formatAttendanceHours(row.holidayOvertime),
              }),
          ].join(' · ')
        : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AccountsV2Colors.line2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  attendanceShortDate(row.date),
                  style: v2Style(
                    13.5,
                    weight: FontWeight.w700,
                    color: holiday
                        ? AccountsV2Colors.vio
                        : AccountsV2Colors.ink,
                  ),
                ),
              ),
              AccountsV2Chip(
                attendanceStatusLabel(row.row.status).active(language),
                tone: switch (row.row.status) {
                  AttendanceStatus.present => AccountsV2ChipTone.ok,
                  AttendanceStatus.absent => AccountsV2ChipTone.bad,
                  _ => AccountsV2ChipTone.neutral,
                },
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(row.where, style: v2Style(12.5)),
          if (times != null)
            Text(
              times,
              style: v2Style(12.5, weight: FontWeight.w600, tabular: true),
            ),
          if ((row.savedBy ?? '').isNotEmpty)
            Text(
              AS.t(AS.savedBy, language, {'by': row.savedBy}),
              style: v2Style(11.5, color: AccountsV2Colors.mut),
            ),
        ],
      ),
    );
  }
}

// ─── Year ────────────────────────────────────────────────────────────────────

class _YearView extends ConsumerStatefulWidget {
  const _YearView({
    required this.year,
    required this.language,
    required this.period,
    required this.onOpenMonth,
    required this.onOpenWorker,
  });

  final int year;
  final AppLanguage language;
  final Widget period;
  final ValueChanged<String> onOpenMonth;
  final ValueChanged<String> onOpenWorker;

  @override
  ConsumerState<_YearView> createState() => _YearViewState();
}

class _YearViewState extends ConsumerState<_YearView> {
  AttendanceWorkforceYear? _shown;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<AccountsV2Column> _columns(String first, {bool workers = true}) {
    final language = widget.language;
    return [
      AccountsV2Column(first, flex: 3),
      if (workers)
        AccountsV2Column(
          AS.t(AS.colLabourers, language),
          width: 96,
          numeric: true,
        ),
      AccountsV2Column(
        AS.t(AS.kpiPresentDays, language),
        width: 110,
        numeric: true,
      ),
      AccountsV2Column(AS.t(AS.colNormalH, language), width: 96, numeric: true),
      AccountsV2Column(AS.t(AS.colOtH, language), width: 84, numeric: true),
      AccountsV2Column(AS.t(AS.colHolH, language), width: 96, numeric: true),
    ];
  }

  List<Widget> _cells(AttendanceYearTotals totals, {bool workers = true}) {
    TextStyle style(Color color) => v2Style(13, tabular: true, color: color);
    return [
      AccountsV2CellStack(
        primary: totals.label,
        secondary: totals.subtitle.isEmpty ? null : totals.subtitle,
      ),
      if (workers)
        Text('${totals.workers}', style: style(AccountsV2Colors.ink)),
      Text('${totals.presentDays}', style: style(AccountsV2Colors.ink)),
      Text(
        formatAttendanceHours(totals.regular, zeroAsDash: true),
        style: style(AccountsV2Colors.ink),
      ),
      Text(
        formatAttendanceHours(totals.normalOvertime, zeroAsDash: true),
        style: style(
          totals.normalOvertime > 0
              ? AccountsV2Colors.org
              : AccountsV2Colors.ink,
        ),
      ),
      Text(
        formatAttendanceHours(totals.holidayOvertime, zeroAsDash: true),
        style: style(
          totals.holidayOvertime > 0
              ? AccountsV2Colors.vio
              : AccountsV2Colors.ink,
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final value = ref.watch(yorksAttendanceWorkforceYearProvider(widget.year));
    final current = value.valueOrNull;
    if (current != null) _shown = current;
    final data = current ?? _shown;
    final loading = current == null && !value.hasError;

    final controls = AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 14, 10),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: widget.period,
            ),
          ),
          _loadingBar(
            loading && data != null,
            AS.t(AS.loadingPeriod, language, {'period': '${widget.year}'}),
          ),
        ],
      ),
    );
    if (data == null) {
      return AccountsV2Stack(
        children: [
          controls,
          _firstLoad(
            value,
            language,
            () => ref.invalidate(
              yorksAttendanceWorkforceYearProvider(widget.year),
            ),
          ),
        ],
      );
    }

    final headcount = data.labourHeadcount;
    final kpis = AccountsV2KpiRow(
      children: [
        AccountsV2KpiCard(
          icon: 'users',
          label: AS.t(AS.kpiLabourers, language),
          value: '${data.workersThisYear}',
          caption: headcount == null
              ? AS.t(AS.kpiLabourersYear, language)
              : AS.t(AS.kpiHeadcount, language, {'n': headcount}),
        ),
        AccountsV2KpiCard(
          icon: 'check',
          label: AS.t(AS.kpiPresentDays, language),
          value: '${data.presentDays}',
          caption: AS.t(AS.kpiPresentDaysCaption, language),
          tone: AccountsV2Tone.green,
        ),
        AccountsV2KpiCard(
          icon: 'clock',
          label: AS.t(AS.kpiNormalHours, language),
          value: _hours(language, data.regular),
          caption: AS.t(AS.kpiNormalHoursCaption, language),
          tone: AccountsV2Tone.neu,
        ),
        AccountsV2KpiCard(
          icon: 'spark',
          label: AS.t(AS.kpiOvertimeShort, language),
          value: _hours(language, data.normalOvertime),
          caption: AS.t(AS.kpiOvertimeHoliday, language, {
            'h': formatAttendanceHours(data.holidayOvertime, zeroAsDash: true),
          }),
          tone: AccountsV2Tone.org,
        ),
      ],
    );

    if (data.presentDays == 0 && data.workers.isEmpty) {
      return AccountsV2Stack(
        children: [
          controls,
          _fading(
            context,
            loading,
            AccountsV2Stack(
              children: [
                kpis,
                AccountsV2Panel(
                  child: AccountsV2Empty(
                    key: const ValueKey('attendance-year-empty'),
                    icon: 'chart',
                    title: AS.t(AS.yearEmpty, language, {
                      'year': '${data.year}',
                    }),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final thisMonth = attendanceMonthOf(attendanceLocalToday());
    // Months with attendance, up to this one.
    final months = [
      for (final month in data.months)
        if (month.key.compareTo(thisMonth) <= 0 &&
            month.presentDays + month.absentDays + month.leaveDays > 0)
          month,
    ];
    final query = _search.text.trim();
    final workers = query.isEmpty
        ? data.workers
        : [
            for (final hit in attendanceFuzzySearch(
              query,
              data.workers,
              (w) => '${w.label} ${w.subtitle}',
              limit: data.workers.length,
            ))
              hit.item,
          ];

    Widget section(String title, String icon, Widget table, {Widget? action}) =>
        AccountsV2Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountsV2CardHead(title: title, icon: icon, actions: [?action]),
              table,
            ],
          ),
        );

    return AccountsV2Stack(
      children: [
        controls,
        _fading(
          context,
          loading,
          AccountsV2Stack(
            children: [
              kpis,
              section(
                AS.t(AS.byMonth, language),
                'chart',
                AccountsV2Table(
                  key: const ValueKey('attendance-year-months'),
                  phoneCards: true,
                  minWidth: 720,
                  columns: _columns(AS.t(AS.colMonthName, language)),
                  rows: [
                    for (final month in months)
                      AccountsV2Row(
                        key: ValueKey('attendance-year-month-${month.key}'),
                        onTap: () => widget.onOpenMonth(month.key),
                        _cells(
                          AttendanceYearTotals(
                            key: month.key,
                            label: attendanceMonthYear(month.key),
                            workers: month.workers,
                            presentDays: month.presentDays,
                            regular: month.regular,
                            normalOvertime: month.normalOvertime,
                            holidayOvertime: month.holidayOvertime,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (data.places.isNotEmpty)
                section(
                  AS.t(AS.byPlace, language),
                  'bldg',
                  AccountsV2Table(
                    key: const ValueKey('attendance-year-places'),
                    phoneCards: true,
                    minWidth: 720,
                    columns: _columns(AS.t(AS.colCrew, language)),
                    rows: [
                      for (final place in data.places)
                        AccountsV2Row(_cells(place)),
                    ],
                  ),
                ),
              section(
                AS.t(AS.byLabourer, language),
                'users',
                AccountsV2Table(
                  key: const ValueKey('attendance-year-workers'),
                  phoneCards: true,
                  minWidth: 640,
                  columns: _columns(
                    AS.t(AS.colWorker, language),
                    workers: false,
                  ),
                  rows: [
                    for (final worker in workers)
                      AccountsV2Row(
                        key: ValueKey('attendance-year-worker-${worker.key}'),
                        onTap: () => widget.onOpenWorker(worker.key),
                        _cells(worker, workers: false),
                      ),
                  ],
                ),
                action: SizedBox(
                  width: AccountsV2Breakpoints.isPhone(context) ? 180 : 240,
                  child: AccountsV2TextField(
                    key: const ValueKey('attendance-year-search'),
                    label: AS.t(AS.searchPeople, language),
                    controller: _search,
                    search: true,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

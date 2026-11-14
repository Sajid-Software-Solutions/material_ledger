/// Workforce attendance — everyone's month, one labourer's month and the
/// workforce year (PRODUCT_DECISIONS section 52). Wire shapes of
/// `v1_wf_people_month`, `v1_wf_worker_month` and `v1_wf_workforce_year`.
/// Every figure comes from the server's saved rows; nothing is recomputed
/// beyond adding them up for the places a reader filters to.
library;

import 'attendance_models.dart';

String _s(Object? value) => value?.toString() ?? '';
String? _ns(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int _i(Object? value) => switch (value) {
  final int v => v,
  final num v => v.toInt(),
  final String v => int.tryParse(v) ?? 0,
  _ => 0,
};

int? _ni(Object? value) => value == null ? null : _i(value);

List<Map<String, dynamic>> _maps(Object? value) => [
  for (final item in (value as List? ?? const []))
    if (item is Map) Map<String, dynamic>.from(item),
];

/// A labourer, as the month and year read models name them.
final class AttendancePerson {
  const AttendancePerson({
    required this.id,
    required this.number,
    required this.name,
    this.designation = '',
    this.company = '',
  });

  factory AttendancePerson.fromJson(Map<String, dynamic> json) =>
      AttendancePerson(
        id: _s(json['id']),
        number: _s(json['number']),
        name: _s(json['name']),
        designation: _s(json['designation']),
        company: _s(json['company']),
      );

  final String id;
  final String number;
  final String name;
  final String designation;
  final String company;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final last = parts.length > 1 ? parts.last[0] : '';
    return (parts.first[0] + last).toUpperCase();
  }
}

/// A day of the month and whether it is a Sunday or public holiday.
final class AttendanceCalendarDay {
  const AttendanceCalendarDay({
    required this.date,
    this.holiday = false,
    this.holidayName,
  });

  factory AttendanceCalendarDay.fromJson(Map<String, dynamic> json) =>
      AttendanceCalendarDay(
        date: _s(json['date']),
        holiday: json['day_type'] == 'holiday',
        holidayName: _ns(json['holiday_name']),
      );

  final String date;
  final bool holiday;
  final String? holidayName;
}

/// A place with attendance in the month.
final class AttendanceMonthPlace {
  const AttendanceMonthPlace({
    required this.id,
    required this.name,
    this.projectRef,
    this.projectName,
    this.confirmed = false,
  });

  factory AttendanceMonthPlace.fromJson(Map<String, dynamic> json) =>
      AttendanceMonthPlace(
        id: _s(json['id']),
        name: _s(json['name']),
        projectRef: _ns(json['project_ref']),
        projectName: _ns(json['project_name']),
        confirmed: json['confirmed'] == true,
      );

  final String id;
  final String name;
  final String? projectRef;
  final String? projectName;

  /// The place's month is confirmed.
  final bool confirmed;

  /// "YRA-322 · DF3W", else the sheet's name.
  String get label => projectRef != null && projectName != null
      ? '$projectRef · $projectName'
      : name;
}

/// One labourer's row at one place on one day.
final class AttendanceMonthEntry {
  const AttendanceMonthEntry({
    required this.workerId,
    required this.date,
    required this.placeId,
    required this.status,
    this.worked = 0,
    this.regular = 0,
    this.normalOvertime = 0,
    this.holidayOvertime = 0,
  });

  factory AttendanceMonthEntry.fromJson(Map<String, dynamic> json) =>
      AttendanceMonthEntry(
        workerId: _s(json['w']),
        date: _s(json['d']),
        placeId: _s(json['c']),
        status: AttendanceStatus.fromCode(json['s']),
        worked: _i(json['m']),
        regular: _i(json['r']),
        normalOvertime: _i(json['o']),
        holidayOvertime: _i(json['h']),
      );

  final String workerId;
  final String date;
  final String placeId;
  final AttendanceStatus? status;
  final int worked;
  final int regular;
  final int normalOvertime;
  final int holidayOvertime;
}

/// A labourer's whole day across the places shown.
final class AttendanceDayTotal {
  const AttendanceDayTotal({
    required this.status,
    this.worked = 0,
    this.normalOvertime = 0,
    this.holidayOvertime = 0,
    this.places = 1,
  });

  /// Present when present anywhere; else leave, absent or rest.
  final AttendanceStatus? status;
  final int worked;
  final int normalOvertime;
  final int holidayOvertime;

  /// How many places recorded the labourer that day.
  final int places;

  int get overtime => normalOvertime + holidayOvertime;
}

/// One labourer's month across the places shown.
final class AttendancePersonMonth {
  const AttendancePersonMonth({
    required this.person,
    required this.days,
    this.presentDays = 0,
    this.absentDays = 0,
    this.leaveDays = 0,
    this.worked = 0,
    this.regular = 0,
    this.normalOvertime = 0,
    this.holidayOvertime = 0,
  });

  final AttendancePerson person;

  /// By date (`YYYY-MM-DD`).
  final Map<String, AttendanceDayTotal> days;
  final int presentDays;
  final int absentDays;
  final int leaveDays;
  final int worked;
  final int regular;
  final int normalOvertime;
  final int holidayOvertime;
}

/// Ranks a day's statuses: present anywhere wins, then leave, absent, rest.
int _rank(AttendanceStatus? status) => switch (status) {
  AttendanceStatus.present => 0,
  AttendanceStatus.annualLeave ||
  AttendanceStatus.sickLeave ||
  AttendanceStatus.officialLeave ||
  AttendanceStatus.unpaidLeave => 1,
  AttendanceStatus.absent => 2,
  AttendanceStatus.rest => 3,
  null => 4,
};

/// Everyone's month at the places the reader may see.
final class AttendancePeopleMonth {
  const AttendancePeopleMonth({
    required this.today,
    required this.month,
    required this.lastDay,
    this.days = const [],
    this.workers = const [],
    this.places = const [],
    this.entries = const [],
  });

  factory AttendancePeopleMonth.fromJson(Map<String, dynamic> json) =>
      AttendancePeopleMonth(
        today: _s(json['today']),
        month: _s(json['month']),
        lastDay: _s(json['last_day']),
        days: [
          for (final day in _maps(json['days']))
            AttendanceCalendarDay.fromJson(day),
        ],
        workers: [
          for (final worker in _maps(json['workers']))
            AttendancePerson.fromJson(worker),
        ],
        places: [
          for (final place in _maps(json['places']))
            AttendanceMonthPlace.fromJson(place),
        ],
        entries: [
          for (final entry in _maps(json['entries']))
            AttendanceMonthEntry.fromJson(entry),
        ],
      );

  final String today;

  /// `YYYY-MM-01`.
  final String month;
  final String lastDay;
  final List<AttendanceCalendarDay> days;
  final List<AttendancePerson> workers;
  final List<AttendanceMonthPlace> places;
  final List<AttendanceMonthEntry> entries;

  /// Each labourer's month, counting only [placeId] when given. A labourer
  /// with no row at that place is left out.
  List<AttendancePersonMonth> people({String? placeId}) {
    final byWorker = <String, List<AttendanceMonthEntry>>{};
    for (final entry in entries) {
      if (placeId != null && entry.placeId != placeId) continue;
      byWorker.putIfAbsent(entry.workerId, () => []).add(entry);
    }
    return [
      for (final person in workers)
        if (byWorker[person.id] case final rows?) _personMonth(person, rows),
    ];
  }

  static AttendancePersonMonth _personMonth(
    AttendancePerson person,
    List<AttendanceMonthEntry> rows,
  ) {
    final byDate = <String, List<AttendanceMonthEntry>>{};
    for (final row in rows) {
      byDate.putIfAbsent(row.date, () => []).add(row);
    }
    final days = <String, AttendanceDayTotal>{};
    var present = 0, absent = 0, leave = 0;
    var worked = 0, regular = 0, normalOt = 0, holidayOt = 0;
    for (final MapEntry(key: date, value: dayRows) in byDate.entries) {
      final status = dayRows
          .map((row) => row.status)
          .reduce((a, b) => _rank(a) <= _rank(b) ? a : b);
      final total = AttendanceDayTotal(
        status: status,
        worked: dayRows.fold(0, (sum, row) => sum + row.worked),
        normalOvertime: dayRows.fold(0, (sum, row) => sum + row.normalOvertime),
        holidayOvertime: dayRows.fold(
          0,
          (sum, row) => sum + row.holidayOvertime,
        ),
        places: dayRows.length,
      );
      days[date] = total;
      switch (_rank(status)) {
        case 0:
          present++;
        case 1:
          leave++;
        case 2:
          absent++;
      }
      worked += total.worked;
      regular += dayRows.fold(0, (sum, row) => sum + row.regular);
      normalOt += total.normalOvertime;
      holidayOt += total.holidayOvertime;
    }
    return AttendancePersonMonth(
      person: person,
      days: days,
      presentDays: present,
      absentDays: absent,
      leaveDays: leave,
      worked: worked,
      regular: regular,
      normalOvertime: normalOt,
      holidayOvertime: holidayOt,
    );
  }
}

/// One row of a labourer's month: a place, a day and its times.
final class AttendanceTimesheetRow {
  const AttendanceTimesheetRow({
    required this.date,
    required this.placeId,
    required this.placeName,
    required this.row,
    this.projectRef,
    this.projectName,
    this.building,
    this.worked = 0,
    this.regular = 0,
    this.normalOvertime = 0,
    this.holidayOvertime = 0,
    this.savedBy,
    this.confirmed = false,
    this.confirmedBy,
  });

  factory AttendanceTimesheetRow.fromJson(Map<String, dynamic> json) =>
      AttendanceTimesheetRow(
        date: _s(json['date']),
        placeId: _s(json['crew_id']),
        placeName: _s(json['crew_name']),
        projectRef: _ns(json['project_ref']),
        projectName: _ns(json['project_name']),
        building: switch (_ns(json['work_scope_name'])) {
          'Common / All Buildings' => null,
          final name => name,
        },
        row: AttendanceRow(
          worker: const AttendanceWorker(
            id: '',
            number: '',
            name: '',
            designation: '',
          ),
          status: AttendanceStatus.fromCode(json['status']),
          start: _ni(json['start_minute']),
          breakStart: _ni(json['break_start_minute']),
          breakFinish: _ni(json['break_finish_minute']),
          finish: _ni(json['finish_minute']),
          workLabel: _ns(json['work_label']),
          overtimeNote: _ns(json['overtime_note']),
        ),
        worked: _i(json['worked_minutes']),
        regular: _i(json['regular_minutes']),
        normalOvertime: _i(json['normal_overtime_minutes']),
        holidayOvertime: _i(json['holiday_overtime_minutes']),
        savedBy: _ns(json['updated_by']),
        confirmed: json['confirmed'] == true,
        confirmedBy: _ns(json['confirmed_by']),
      );

  final String date;
  final String placeId;
  final String placeName;
  final String? projectRef;
  final String? projectName;

  /// The building worked at; null for Common or none.
  final String? building;

  /// Status, times and note (the worker card is not filled in).
  final AttendanceRow row;
  final int worked;
  final int regular;
  final int normalOvertime;
  final int holidayOvertime;
  final String? savedBy;
  final bool confirmed;
  final String? confirmedBy;

  /// "YRA-322 · DF3W · Tower A", else the sheet's name.
  String get where {
    final place = projectRef != null && projectName != null
        ? '$projectRef · $projectName'
        : placeName;
    return building == null ? place : '$place · $building';
  }
}

/// One labourer's month at every place the reader may see.
final class AttendanceWorkerMonth {
  const AttendanceWorkerMonth({
    required this.today,
    required this.month,
    required this.lastDay,
    required this.worker,
    this.days = const [],
    this.rows = const [],
  });

  factory AttendanceWorkerMonth.fromJson(Map<String, dynamic> json) =>
      AttendanceWorkerMonth(
        today: _s(json['today']),
        month: _s(json['month']),
        lastDay: _s(json['last_day']),
        worker: AttendancePerson.fromJson(
          Map<String, dynamic>.from(json['worker'] as Map? ?? const {}),
        ),
        days: [
          for (final day in _maps(json['days']))
            AttendanceCalendarDay.fromJson(day),
        ],
        rows: [
          for (final row in _maps(json['rows']))
            AttendanceTimesheetRow.fromJson(row),
        ],
      );

  final String today;
  final String month;
  final String lastDay;
  final AttendancePerson worker;
  final List<AttendanceCalendarDay> days;
  final List<AttendanceTimesheetRow> rows;

  int get presentDays => {
    for (final row in rows)
      if (row.row.status == AttendanceStatus.present) row.date,
  }.length;
  int get regular => rows.fold(0, (sum, row) => sum + row.regular);
  int get normalOvertime =>
      rows.fold(0, (sum, row) => sum + row.normalOvertime);
  int get holidayOvertime =>
      rows.fold(0, (sum, row) => sum + row.holidayOvertime);
  int get worked => rows.fold(0, (sum, row) => sum + row.worked);

  /// Every place's month in it is confirmed.
  bool get allConfirmed => rows.isNotEmpty && rows.every((r) => r.confirmed);
}

/// Totals for a month, a place or a labourer over the year.
final class AttendanceYearTotals {
  const AttendanceYearTotals({
    required this.key,
    required this.label,
    this.subtitle = '',
    this.workers = 0,
    this.presentDays = 0,
    this.absentDays = 0,
    this.leaveDays = 0,
    this.worked = 0,
    this.regular = 0,
    this.normalOvertime = 0,
    this.holidayOvertime = 0,
  });

  factory AttendanceYearTotals.fromJson(
    Map<String, dynamic> json, {
    required String key,
    required String label,
    String subtitle = '',
  }) => AttendanceYearTotals(
    key: key,
    label: label,
    subtitle: subtitle,
    workers: _i(json['workers']),
    presentDays: _i(json['present_days']),
    absentDays: _i(json['absent_days']),
    leaveDays: _i(json['leave_days']),
    worked: _i(json['worked_minutes']),
    regular: _i(json['regular_minutes']),
    normalOvertime: _i(json['normal_overtime_minutes']),
    holidayOvertime: _i(json['holiday_overtime_minutes']),
  );

  /// The month (`YYYY-MM-01`), place id or worker id.
  final String key;
  final String label;
  final String subtitle;
  final int workers;
  final int presentDays;
  final int absentDays;
  final int leaveDays;
  final int worked;
  final int regular;
  final int normalOvertime;
  final int holidayOvertime;
}

/// The workforce year at the places the reader may see.
final class AttendanceWorkforceYear {
  const AttendanceWorkforceYear({
    required this.today,
    required this.year,
    this.labourHeadcount,
    this.months = const [],
    this.places = const [],
    this.workers = const [],
  });

  factory AttendanceWorkforceYear.fromJson(Map<String, dynamic> json) =>
      AttendanceWorkforceYear(
        today: _s(json['today']),
        year: _i(json['year']),
        labourHeadcount: _ni(json['labour_headcount']),
        months: [
          for (final month in _maps(json['months']))
            AttendanceYearTotals.fromJson(
              month,
              key: _s(month['month']),
              label: _s(month['month']),
            ),
        ],
        places: [
          for (final place in _maps(json['places']))
            AttendanceYearTotals.fromJson(
              place,
              key: _s(place['id']),
              label:
                  _ns(place['project_ref']) != null &&
                      _ns(place['project_name']) != null
                  ? '${place['project_ref']} · ${place['project_name']}'
                  : _s(place['name']),
            ),
        ],
        workers: [
          for (final worker in _maps(json['workers']))
            AttendanceYearTotals.fromJson(
              worker,
              key: _s(worker['id']),
              label: _s(worker['name']),
              subtitle: [
                _s(worker['number']),
                _s(worker['designation']),
              ].where((part) => part.isNotEmpty).join(' · '),
            ),
        ],
      );

  final String today;
  final int year;

  /// Active labour on the books; only for readers who see every place.
  final int? labourHeadcount;
  final List<AttendanceYearTotals> months;
  final List<AttendanceYearTotals> places;
  final List<AttendanceYearTotals> workers;

  /// Labourers present at least once this year.
  int get workersThisYear => workers.where((w) => w.presentDays > 0).length;
  int get presentDays => months.fold(0, (sum, m) => sum + m.presentDays);
  int get regular => months.fold(0, (sum, m) => sum + m.regular);
  int get normalOvertime => months.fold(0, (sum, m) => sum + m.normalOvertime);
  int get holidayOvertime =>
      months.fold(0, (sum, m) => sum + m.holidayOvertime);
}

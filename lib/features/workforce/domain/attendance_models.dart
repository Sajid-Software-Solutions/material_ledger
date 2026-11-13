/// Workforce attendance V2 — the server's crew, day, month and overview
/// projections, parsed strictly. Unknown statuses fail closed.
library;

import 'attendance_time.dart';

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? [for (final item in value) _map(item)]
    : const <Map<String, dynamic>>[];

String _s(Object? value) => value?.toString() ?? '';
String? _ns(Object? value) {
  final text = value?.toString();
  return text == null || text.isEmpty ? null : text;
}

int _i(Object? value) => switch (value) {
  final int v => v,
  final num v => v.toInt(),
  final String v => int.tryParse(v) ?? 0,
  _ => 0,
};
int? _ni(Object? value) => value == null ? null : _i(value);
bool _b(Object? value) => value == true;

/// A crew row status.
enum AttendanceStatus {
  present('P'),
  absent('A'),
  rest('OFF'),
  annualLeave('AL'),
  sickLeave('SL'),
  officialLeave('OL'),
  unpaidLeave('UL');

  const AttendanceStatus(this.code);
  final String code;

  static AttendanceStatus? fromCode(Object? code) {
    for (final status in values) {
      if (status.code == code) return status;
    }
    return null;
  }

  bool get isLeave =>
      this == annualLeave ||
      this == sickLeave ||
      this == officialLeave ||
      this == unpaidLeave;
}

/// How a crew day reads on the strips and the overview.
enum AttendanceDayState {
  entered,
  question,
  none,
  off,
  locked,
  future;

  static AttendanceDayState parse(Object? value) => switch (value) {
    'entered' => entered,
    'question' => question,
    'none' => none,
    'off' => off,
    'locked' => locked,
    _ => future,
  };
}

/// A crew's month: recording, ready, confirmed or no confirmation needed.
enum AttendanceMonthState {
  recording,
  ready,
  confirmed,
  notNeeded;

  static AttendanceMonthState parse(Object? value) => switch (value) {
    'ready' => ready,
    'confirmed' => confirmed,
    'not_needed' => notNeeded,
    _ => recording,
  };
}

/// What the signed-in person may do on one crew (server-decided).
final class AttendanceCrewAccess {
  const AttendanceCrewAccess({
    this.view = false,
    this.take = false,
    this.confirm = false,
    this.manage = false,
    this.officer = false,
  });

  factory AttendanceCrewAccess.fromJson(Map<String, dynamic> json) =>
      AttendanceCrewAccess(
        view: _b(json['view']),
        take: _b(json['take']),
        confirm: _b(json['confirm']),
        manage: _b(json['manage']),
        officer: _b(json['officer']),
      );

  final bool view;
  final bool take;
  final bool confirm;
  final bool manage;
  final bool officer;

  bool get readOnly => !take && !confirm && !manage;
}

final class AttendanceCrew {
  const AttendanceCrew({
    required this.id,
    required this.name,
    required this.kind,
    required this.workLabel,
    required this.needsConfirmation,
    required this.shiftStart,
    required this.shiftFinish,
    required this.breakStart,
    required this.breakFinish,
    required this.memberCount,
    required this.recordVersion,
    required this.access,
    this.projectId,
    this.projectRef,
    this.projectName,
    this.isActive = true,
  });

  factory AttendanceCrew.fromJson(Map<String, dynamic> json) => AttendanceCrew(
    id: _s(json['id']),
    name: _s(json['name']),
    kind: _s(json['kind']),
    projectId: _ns(json['project_id']),
    projectRef: _ns(json['project_ref']),
    projectName: _ns(json['project_name']),
    workLabel: _s(json['work_label']),
    needsConfirmation: _b(json['needs_confirmation']),
    shiftStart: _i(json['shift_start_minute']),
    shiftFinish: _i(json['shift_finish_minute']),
    breakStart: _ni(json['break_start_minute']),
    breakFinish: _ni(json['break_finish_minute']),
    memberCount: _i(json['member_count']),
    recordVersion: _i(json['record_version']),
    isActive: json['is_active'] != false,
    access: AttendanceCrewAccess.fromJson(_map(json['access'])),
  );

  final String id;
  final String name;

  /// `project` or `workshop`.
  final String kind;
  final String? projectId;
  final String? projectRef;
  final String? projectName;
  final String workLabel;
  final bool needsConfirmation;
  final int shiftStart;
  final int shiftFinish;
  final int? breakStart;
  final int? breakFinish;
  final int memberCount;
  final int recordVersion;
  final bool isActive;
  final AttendanceCrewAccess access;

  bool get isWorkshop => kind == 'workshop';
}

final class AttendanceWorker {
  const AttendanceWorker({
    required this.id,
    required this.number,
    required this.name,
    required this.designation,
    this.company = '',
    this.crewId,
    this.crewName,
  });

  factory AttendanceWorker.fromJson(Map<String, dynamic> json) =>
      AttendanceWorker(
        id: _s(json['id']),
        number: _s(json['number']),
        name: _s(json['name']),
        designation: _s(json['designation']),
        company: _s(json['company']),
        crewId: _ns(json['crew_id']),
        crewName: _ns(json['crew_name']),
      );

  final String id;
  final String number;
  final String name;
  final String designation;
  final String company;
  final String? crewId;
  final String? crewName;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }
}

/// One worker's line on a day, as saved or being edited.
final class AttendanceRow {
  const AttendanceRow({
    required this.worker,
    this.status,
    this.start,
    this.breakStart,
    this.breakFinish,
    this.finish,
    this.workProjectId,
    this.workLabel,
    this.overtimeNote,
    this.copied = false,
    this.changedAfterEntry = false,
    this.isMember = true,
  });

  factory AttendanceRow.fromJson(Map<String, dynamic> json) => AttendanceRow(
    worker: AttendanceWorker.fromJson(_map(json['worker'])),
    status: AttendanceStatus.fromCode(json['status']),
    start: _ni(json['start_minute']),
    breakStart: _ni(json['break_start_minute']),
    breakFinish: _ni(json['break_finish_minute']),
    finish: _ni(json['finish_minute']),
    workProjectId: _ns(json['work_project_id']),
    workLabel: _ns(json['work_label']),
    overtimeNote: _ns(json['overtime_note']),
    copied: _b(json['copied']),
    changedAfterEntry: _b(json['changed_after_entry']),
    isMember: json['is_member'] != false,
  );

  final AttendanceWorker worker;
  final AttendanceStatus? status;
  final int? start;
  final int? breakStart;
  final int? breakFinish;
  final int? finish;
  final String? workProjectId;
  final String? workLabel;
  final String? overtimeNote;
  final bool copied;
  final bool changedAfterEntry;

  /// False for a worker added to this day only.
  final bool isMember;

  bool get isMarked => status != null;

  AttendanceMinutes minutes({required bool holiday}) =>
      computeAttendanceMinutes(
        present: status == AttendanceStatus.present,
        holiday: holiday,
        start: start,
        breakStart: breakStart,
        breakFinish: breakFinish,
        finish: finish,
      );

  AttendanceRow copyWith({
    AttendanceStatus? status,
    bool clearStatus = false,
    int? start,
    int? breakStart,
    int? breakFinish,
    int? finish,
    bool clearTimes = false,
    bool clearBreak = false,
    String? workProjectId,
    String? workLabel,
    bool clearWork = false,
    String? overtimeNote,
    bool clearNote = false,
    bool? copied,
  }) {
    final nextStatus = clearStatus ? null : (status ?? this.status);
    final keepTimes = !clearTimes && nextStatus == AttendanceStatus.present;
    return AttendanceRow(
      worker: worker,
      status: nextStatus,
      start: keepTimes ? (start ?? this.start) : null,
      breakStart: keepTimes && !clearBreak
          ? (breakStart ?? this.breakStart)
          : null,
      breakFinish: keepTimes && !clearBreak
          ? (breakFinish ?? this.breakFinish)
          : null,
      finish: keepTimes ? (finish ?? this.finish) : null,
      workProjectId: clearWork ? null : (workProjectId ?? this.workProjectId),
      workLabel: clearWork ? null : (workLabel ?? this.workLabel),
      overtimeNote: clearNote ? null : (overtimeNote ?? this.overtimeNote),
      copied: copied ?? this.copied,
      changedAfterEntry: changedAfterEntry,
      isMember: isMember,
    );
  }

  /// The save payload row.
  Map<String, Object?> toPayload() => {
    'worker_id': worker.id,
    'status': status?.code,
    'start_minute': start,
    'break_start_minute': breakStart,
    'break_finish_minute': breakFinish,
    'finish_minute': finish,
    'work_project_id': workProjectId,
    'work_label': workLabel,
    'overtime_note': overtimeNote,
    'copied': copied,
  };

  /// Local draft storage (same shape plus the worker card).
  Map<String, Object?> toDraftJson() => {
    ...toPayload(),
    'worker': {
      'id': worker.id,
      'number': worker.number,
      'name': worker.name,
      'designation': worker.designation,
      'company': worker.company,
      'crew_id': worker.crewId,
      'crew_name': worker.crewName,
    },
    'is_member': isMember,
  };

  /// Compares only what is saved, to tell whether a draft differs.
  bool sameEntry(AttendanceRow other) =>
      status == other.status &&
      start == other.start &&
      breakStart == other.breakStart &&
      breakFinish == other.breakFinish &&
      finish == other.finish &&
      workProjectId == other.workProjectId &&
      (workLabel ?? '') == (other.workLabel ?? '') &&
      (overtimeNote ?? '') == (other.overtimeNote ?? '');
}

final class AttendanceQuestion {
  const AttendanceQuestion({
    required this.id,
    required this.question,
    required this.askedBy,
    required this.askedAt,
    required this.isOpen,
    this.answer,
    this.answeredBy,
    this.answeredAt,
  });

  factory AttendanceQuestion.fromJson(Map<String, dynamic> json) =>
      AttendanceQuestion(
        id: _s(json['id']),
        question: _s(json['question']),
        askedBy: _s(json['asked_by']),
        askedAt: DateTime.tryParse(_s(json['asked_at'])),
        isOpen: _b(json['is_open']),
        answer: _ns(json['answer']),
        answeredBy: _ns(json['answered_by']),
        answeredAt: DateTime.tryParse(_s(json['answered_at'])),
      );

  final String id;
  final String question;
  final String askedBy;
  final DateTime? askedAt;
  final bool isOpen;
  final String? answer;
  final String? answeredBy;
  final DateTime? answeredAt;
}

final class AttendanceChange {
  const AttendanceChange({
    required this.workerName,
    required this.before,
    required this.after,
    required this.reason,
    required this.by,
    required this.at,
  });

  factory AttendanceChange.fromJson(Map<String, dynamic> json) =>
      AttendanceChange(
        workerName: _s(json['worker_name']),
        before: _map(json['before']),
        after: json['after'] == null ? null : _map(json['after']),
        reason: _s(json['reason']),
        by: _s(json['by']),
        at: DateTime.tryParse(_s(json['at'])),
      );

  final String workerName;
  final Map<String, dynamic> before;

  /// Null when the worker was taken off the day.
  final Map<String, dynamic>? after;
  final String reason;
  final String by;
  final DateTime? at;
}

final class AttendanceMonth {
  const AttendanceMonth({
    required this.month,
    required this.lastDay,
    required this.state,
    required this.days,
    required this.missingDays,
    required this.workDaysSoFar,
    required this.daysEntered,
    required this.regularMinutes,
    required this.normalOvertimeMinutes,
    required this.holidayOvertimeMinutes,
    required this.canConfirm,
    required this.recordVersion,
    this.confirmedBy,
    this.confirmedAt,
    this.reopenedBy,
    this.reopenReason,
  });

  factory AttendanceMonth.fromJson(Map<String, dynamic> json) =>
      AttendanceMonth(
        month: _s(json['month']),
        lastDay: _s(json['last_day']),
        state: AttendanceMonthState.parse(json['state']),
        days: [
          for (final day in _maps(json['days']))
            (
              date: _s(day['date']),
              state: AttendanceDayState.parse(day['state']),
              holiday: day['day_type'] == 'holiday',
            ),
        ],
        missingDays: [
          for (final day in (json['missing_days'] as List? ?? const []))
            day.toString(),
        ],
        workDaysSoFar: _i(json['work_days_so_far']),
        daysEntered: _i(json['days_entered']),
        regularMinutes: _i(json['regular_minutes']),
        normalOvertimeMinutes: _i(json['normal_overtime_minutes']),
        holidayOvertimeMinutes: _i(json['holiday_overtime_minutes']),
        canConfirm: _b(json['can_confirm']),
        recordVersion: _i(json['record_version']),
        confirmedBy: _ns(json['confirmed_by']),
        confirmedAt: DateTime.tryParse(_s(json['confirmed_at'])),
        reopenedBy: _ns(json['reopened_by']),
        reopenReason: _ns(json['reopen_reason']),
      );

  final String month;
  final String lastDay;
  final AttendanceMonthState state;
  final List<({String date, AttendanceDayState state, bool holiday})> days;
  final List<String> missingDays;
  final int workDaysSoFar;
  final int daysEntered;
  final int regularMinutes;
  final int normalOvertimeMinutes;
  final int holidayOvertimeMinutes;
  final bool canConfirm;
  final int recordVersion;
  final String? confirmedBy;
  final DateTime? confirmedAt;
  final String? reopenedBy;
  final String? reopenReason;

  bool get isConfirmed => state == AttendanceMonthState.confirmed;
}

final class AttendanceDay {
  const AttendanceDay({
    required this.crew,
    required this.date,
    required this.today,
    required this.holiday,
    required this.saved,
    required this.recordVersion,
    required this.rows,
    required this.changes,
    required this.access,
    required this.month,
    required this.locked,
    required this.isFuture,
    this.holidayName,
    this.enteredBy,
    this.enteredByMe = false,
    this.enteredAt,
    this.enteredLate = false,
    this.lastSavedBy,
    this.lastSavedAt,
    this.previousSameTypeDate,
    this.question,
  });

  factory AttendanceDay.fromJson(Map<String, dynamic> json) => AttendanceDay(
    crew: AttendanceCrew.fromJson(_map(json['crew'])),
    date: _s(json['date']),
    today: _s(json['today']),
    holiday: json['day_type'] == 'holiday',
    holidayName: _ns(json['holiday_name']),
    saved: _b(json['saved']),
    recordVersion: _i(json['record_version']),
    enteredBy: _ns(json['entered_by']),
    enteredByMe: _b(json['entered_by_me']),
    enteredAt: DateTime.tryParse(_s(json['entered_at'])),
    enteredLate: _b(json['entered_late']),
    lastSavedBy: _ns(json['last_saved_by']),
    lastSavedAt: DateTime.tryParse(_s(json['last_saved_at'])),
    locked: _b(json['locked']),
    isFuture: _b(json['is_future']),
    previousSameTypeDate: _ns(json['previous_same_type_date']),
    rows: [for (final row in _maps(json['rows'])) AttendanceRow.fromJson(row)],
    question: json['question'] is Map
        ? AttendanceQuestion.fromJson(_map(json['question']))
        : null,
    changes: [
      for (final change in _maps(json['changes']))
        AttendanceChange.fromJson(change),
    ],
    access: AttendanceCrewAccess.fromJson(_map(json['access'])),
    month: AttendanceMonth.fromJson(_map(json['month'])),
  );

  final AttendanceCrew crew;
  final String date;
  final String today;

  /// Sunday or a public holiday: everyone starts as Rest day.
  final bool holiday;
  final String? holidayName;
  final bool saved;
  final int recordVersion;
  final String? enteredBy;
  final bool enteredByMe;
  final DateTime? enteredAt;
  final bool enteredLate;
  final String? lastSavedBy;
  final DateTime? lastSavedAt;
  final bool locked;
  final bool isFuture;
  final String? previousSameTypeDate;
  final List<AttendanceRow> rows;
  final AttendanceQuestion? question;
  final List<AttendanceChange> changes;
  final AttendanceCrewAccess access;
  final AttendanceMonth month;

  /// The taker may edit until the month is confirmed.
  bool get editable => access.take && !locked && !isFuture;

  /// Changing a day someone else entered needs a reason.
  bool get changeNeedsReason => saved && !enteredByMe;
}

final class AttendanceFeedItem {
  const AttendanceFeedItem({
    required this.kind,
    required this.crewId,
    required this.crewName,
    required this.by,
    required this.summary,
    this.date,
    this.at,
  });

  factory AttendanceFeedItem.fromJson(Map<String, dynamic> json) =>
      AttendanceFeedItem(
        kind: _s(json['kind']),
        crewId: _s(json['crew_id']),
        crewName: _s(json['crew_name']),
        date: _ns(json['date']) ?? _ns(json['month']),
        by: _s(json['by']),
        at: DateTime.tryParse(_s(json['at'])),
        summary: _map(json['summary']),
      );

  final String kind;
  final String crewId;
  final String crewName;
  final String? date;
  final String by;
  final DateTime? at;
  final Map<String, dynamic> summary;
}

final class AttendanceOverview {
  const AttendanceOverview({
    required this.today,
    required this.month,
    required this.crews,
    required this.feed,
  });

  factory AttendanceOverview.fromJson(Map<String, dynamic> json) =>
      AttendanceOverview(
        today: _s(json['today']),
        month: _s(json['month']),
        crews: [
          for (final crew in _maps(json['crews']))
            (
              crew: AttendanceCrew.fromJson(crew),
              month: AttendanceMonth.fromJson(_map(crew['month'])),
            ),
        ],
        feed: [
          for (final item in _maps(json['feed']))
            AttendanceFeedItem.fromJson(item),
        ],
      );

  final String today;
  final String month;
  final List<({AttendanceCrew crew, AttendanceMonth month})> crews;
  final List<AttendanceFeedItem> feed;
}

final class AttendanceSheetDay {
  const AttendanceSheetDay({required this.date, required this.row});

  final String date;
  final AttendanceRow row;
}

final class AttendanceSheetWorker {
  const AttendanceSheetWorker({required this.worker, required this.days});

  final AttendanceWorker worker;
  final List<AttendanceSheetDay> days;
}

final class AttendanceMonthSheet {
  const AttendanceMonthSheet({
    required this.crew,
    required this.month,
    required this.workers,
    required this.enteredBy,
    required this.holidays,
    required this.canExport,
  });

  factory AttendanceMonthSheet.fromJson(Map<String, dynamic> json) {
    final workers = <AttendanceSheetWorker>[];
    for (final item in _maps(json['workers'])) {
      final worker = AttendanceWorker.fromJson(item);
      workers.add(
        AttendanceSheetWorker(
          worker: worker,
          days: [
            for (final day in _maps(item['days']))
              AttendanceSheetDay(
                date: _s(day['date']),
                row: AttendanceRow.fromJson({...day, 'worker': item}),
              ),
          ],
        ),
      );
    }
    return AttendanceMonthSheet(
      crew: AttendanceCrew.fromJson(_map(json['crew'])),
      month: AttendanceMonth.fromJson(_map(json['month'])),
      workers: workers,
      enteredBy: {
        for (final sheet in _maps(json['sheets']))
          _s(sheet['date']): (
            by: _s(sheet['entered_by']),
            changed: _b(sheet['changed']),
          ),
      },
      holidays: {
        for (final holiday in _maps(json['holidays']))
          _s(holiday['date']): _s(holiday['name']),
      },
      canExport: _b(json['can_export']),
    );
  }

  final AttendanceCrew crew;
  final AttendanceMonth month;
  final List<AttendanceSheetWorker> workers;
  final Map<String, ({String by, bool changed})> enteredBy;
  final Map<String, String> holidays;
  final bool canExport;
}

/// A year's public holidays and whether this person may change them.
final class AttendanceHolidays {
  const AttendanceHolidays({
    required this.year,
    required this.canManage,
    required this.holidays,
  });

  factory AttendanceHolidays.fromJson(Map<String, dynamic> json) =>
      AttendanceHolidays(
        year: _i(json['year']),
        canManage: _b(json['can_manage']),
        holidays: [
          for (final row in _maps(json['holidays']))
            (date: _s(row['date']), name: _s(row['name'])),
        ],
      );

  final int year;
  final bool canManage;
  final List<({String date, String name})> holidays;
}

/// A crew month waiting for this person's confirmation.
final class AttendanceConfirmationDue {
  const AttendanceConfirmationDue({
    required this.crewId,
    required this.crewName,
    required this.month,
    required this.lastDay,
    required this.overdue,
    required this.missingDays,
  });

  factory AttendanceConfirmationDue.fromJson(Map<String, dynamic> json) =>
      AttendanceConfirmationDue(
        crewId: _s(json['crew_id']),
        crewName: _s(json['crew_name']),
        month: _s(json['month']),
        lastDay: _s(json['last_day']),
        overdue: _b(json['overdue']),
        missingDays: _i(json['missing_days']),
      );

  final String crewId;
  final String crewName;
  final String month;
  final String lastDay;

  /// The month ended before today.
  final bool overdue;

  /// Working days still not entered (confirming waits for these).
  final int missingDays;
}

/// How a worker's documents stand, as the crew's engineers see it: nothing
/// more than this (PRODUCT_DECISIONS.md section 45).
enum CrewDocumentStatus {
  ok('ok'),
  expiring('expiring'),
  expired('expired');

  const CrewDocumentStatus(this.wire);
  final String wire;

  static CrewDocumentStatus? from(Object? value) {
    for (final status in values) {
      if (status.wire == value) return status;
    }
    return null;
  }
}

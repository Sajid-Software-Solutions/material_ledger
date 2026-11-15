// Attendance prints and place names (PRODUCT_DECISIONS section 59): one
// name for a place on every screen and print, the printed day as saved, and
// the monthly sheet's columns matching its on-screen preview.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/workforce/data/attendance_day_print.dart';
import 'package:material_ledger/features/workforce/data/attendance_sheet_service.dart';
import 'package:material_ledger/features/workforce/domain/attendance_models.dart';

Map<String, Object?> _crew({
  String name = 'YRA-322 DF3W',
  String? placeKind = 'project',
  String? workLabel = 'DF3W · YRA-322',
  bool project = true,
}) => {
  'id': 'c1',
  'name': name,
  'kind': project ? 'project' : 'workshop',
  'project_id': project ? 'p1' : null,
  'project_ref': project ? 'YRA-322' : null,
  'project_name': project ? 'DF3W' : null,
  'work_label': workLabel,
  'needs_confirmation': project,
  'shift_start_minute': 390,
  'shift_finish_minute': 870,
  'record_version': 1,
  'member_count': 0,
  'place_kind': placeKind,
  'access': {'view': true, 'take': true},
};

AttendanceCrew _place() => AttendanceCrew.fromJson(_crew());

AttendanceCrew _workshop() => AttendanceCrew.fromJson(
  _crew(
    name: 'Workshop',
    placeKind: 'location',
    workLabel: 'Workshop',
    project: false,
  ),
);

/// A crew set up before places, with its own name and work label.
AttendanceCrew _oldCrew() => AttendanceCrew.fromJson(
  _crew(name: 'Sweihan site crew', placeKind: null, workLabel: 'Sweihan'),
);

AttendanceRow _row({
  String status = 'P',
  int? start = 390,
  int? finish = 870,
  String? building,
  String? label,
  String? by = 'Imran Qureshi',
  List<Map<String, Object?>> elsewhere = const [],
}) => AttendanceRow.fromJson({
  'worker': {
    'id': 'w1',
    'number': 'L-101',
    'name': 'Gul Zaman',
    'designation': 'Helper',
  },
  'status': status,
  'start_minute': status == 'P' ? start : null,
  'finish_minute': status == 'P' ? finish : null,
  'work_scope_id': building == null ? null : 'b1',
  'work_scope_name': building,
  'work_label': label,
  'updated_by': by,
  'elsewhere': elsewhere,
});

Map<String, Object?> _day({
  Map<String, Object?>? crew,
  List<Map<String, Object?>> rows = const [],
  String dayType = 'work',
  String? holidayName,
  List<Map<String, Object?>> changes = const [],
  String state = 'recording',
}) => {
  'crew': crew ?? _crew(),
  'date': '2026-11-12',
  'today': '2026-11-15',
  'day_type': dayType,
  'holiday_name': holidayName,
  'saved': true,
  'record_version': 2,
  'entered_by': 'Imran Qureshi',
  'entered_at': '2026-11-12T03:10:00Z',
  'last_saved_by': 'Faisal Rahman',
  'last_saved_at': '2026-11-12T09:40:00Z',
  'rows': rows,
  'changes': changes,
  'access': {'view': true},
  'month': {
    'month': '2026-11-01',
    'last_day': '2026-11-30',
    'state': state,
    'confirmed_by': state == 'confirmed' ? 'Faisal Rahman' : null,
    'days': <Object>[],
  },
};

Map<String, Object?> _rowJson(
  String id,
  String name,
  String status, {
  int start = 390,
  int finish = 870,
  String? building = 'Tower A',
  String? by = 'Imran Qureshi',
}) => {
  'worker': {
    'id': id,
    'number': 'L-$id',
    'name': name,
    'designation': 'Helper',
  },
  'status': status,
  'start_minute': status == 'P' ? start : null,
  'finish_minute': status == 'P' ? finish : null,
  'work_scope_id': building == null ? null : 'b1',
  'work_scope_name': building,
  'updated_by': by,
};

void main() {
  // The letterhead loads the logo and fonts from the asset bundle.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('one name for a place', () {
    test('a project place reads "YRA-322 · DF3W", with no second line', () {
      expect(_place().label, 'YRA-322 · DF3W');
      expect(_place().detail, isNull);
    });

    test('an internal place reads its name', () {
      expect(_workshop().label, 'Workshop');
      expect(_workshop().detail, isNull);
    });

    test('a crew from before places keeps its name and work label', () {
      expect(_oldCrew().label, 'Sweihan site crew');
      expect(_oldCrew().detail, 'Sweihan');
      expect(attendancePrintPlace(_oldCrew()), 'Sweihan site crew · Sweihan');
      expect(attendancePrintPlace(_place()), 'YRA-322 · DF3W');
    });
  });

  group('where a line was worked, as printed', () {
    test('a project place: the place and building, Common left out', () {
      expect(
        attendancePrintWhere(_place(), _row(building: 'Tower A')),
        'YRA-322 · DF3W · Tower A',
      );
      expect(
        attendancePrintWhere(
          _place(),
          _row(building: 'Common / All Buildings'),
        ),
        'YRA-322 · DF3W',
      );
    });

    test(
      'an internal place: the project typed on the line, else the place',
      () {
        expect(attendancePrintWhere(_workshop(), _row(label: 'DF3W')), 'DF3W');
        expect(attendancePrintWhere(_workshop(), _row()), 'Workshop');
      },
    );

    test('a crew from before places: the line\'s or the crew\'s label', () {
      expect(
        attendancePrintWhere(_oldCrew(), _row(label: 'Villa 7')),
        'Villa 7',
      );
      expect(attendancePrintWhere(_oldCrew(), _row()), 'Sweihan');
    });
  });

  group('the printed day', () {
    final day = AttendanceDay.fromJson(
      _day(
        rows: [
          _rowJson('101', 'Gul Zaman', 'P', finish: 990),
          _rowJson('102', 'Waqar Ahmed', 'P', by: null),
          _rowJson('103', 'Ravi Kumar', 'A', building: null),
          _rowJson('104', 'Oheedullah Khan', 'SL', building: null),
        ],
      ),
    );

    test('every saved line, times only for those present', () {
      final lines = YorksAttendanceDayPrint.lines(day);
      expect(lines.map((l) => l.name), [
        'Gul Zaman',
        'Waqar Ahmed',
        'Ravi Kumar',
        'Oheedullah Khan',
      ]);
      final gul = lines.first;
      expect((gul.start, gul.finish), ('6:30 AM', '4:30 PM'));
      expect((gul.worked, gul.normalOvertime), (600, 120));
      expect(gul.where, 'Tower A');
      expect(gul.status, 'Present');
      // No one named on the line: the person who entered the day.
      expect(lines[1].savedBy, 'Imran Qureshi');
      final ravi = lines[2];
      expect((ravi.status, ravi.start, ravi.finish), ('Absent', '', ''));
      expect(ravi.worked, 0);
      expect(lines[3].status, 'Sick leave');
    });

    test('the day, the place and the count', () {
      expect(
        YorksAttendanceDayPrint.summary(day),
        '2 present · 1 absent · 1 on leave',
      );
      expect(YorksAttendanceDayPrint.dayType(day), 'Working day');
      expect(YorksAttendanceDayPrint.whereHeading(day.crew), 'Building');
      expect(
        const YorksAttendanceDayPrint().fileStem(day),
        'Yorks-attendance-YRA-322-DF3W-2026-11-12',
      );
    });

    test('a rest day and a public holiday say so', () {
      expect(
        YorksAttendanceDayPrint.dayType(
          AttendanceDay.fromJson(_day(dayType: 'holiday')),
        ),
        'Rest day',
      );
      expect(
        YorksAttendanceDayPrint.dayType(
          AttendanceDay.fromJson(
            _day(dayType: 'holiday', holidayName: 'National Day'),
          ),
        ),
        'Public holiday · National Day',
      );
    });

    test('at the workshop the column is the project typed on each line', () {
      final workshop = AttendanceDay.fromJson(
        _day(
          crew: _crew(
            name: 'Workshop',
            placeKind: 'location',
            workLabel: 'Workshop',
            project: false,
          ),
          rows: [
            {
              ..._rowJson('101', 'Gul Zaman', 'P', building: null),
              'work_label': 'DF3W',
            },
          ],
        ),
      );
      expect(YorksAttendanceDayPrint.whereHeading(workshop.crew), 'Project');
      expect(YorksAttendanceDayPrint.lines(workshop).single.where, 'DF3W');
    });

    test('a change after entry is written out with its reason', () {
      final changed = AttendanceDay.fromJson(
        _day(
          changes: [
            {
              'worker_name': 'Gul Zaman',
              'before': {
                'status': 'P',
                'start_minute': 390,
                'finish_minute': 870,
              },
              'after': {'status': 'A'},
              'reason': 'Left before the shift',
              'by': 'Faisal Rahman',
              'at': '2026-11-12T09:40:00Z',
            },
          ],
        ),
      );
      final text = YorksAttendanceDayPrint.change(changed.changes.single);
      expect(text, startsWith('Faisal Rahman · '));
      expect(
        text,
        endsWith(
          'Gul Zaman from 6:30 AM–2:30 PM to Absent — Left before the shift',
        ),
      );
    });

    test('prints under the letterhead, an empty day too', () async {
      const print = YorksAttendanceDayPrint();
      final bytes = await print.buildPdf(day);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      final empty = await print.buildPdf(
        AttendanceDay.fromJson(_day(state: 'confirmed')),
      );
      expect(String.fromCharCodes(empty.take(4)), '%PDF');
    });
  });

  test('the month note on every print', () {
    AttendanceMonth month(String state) => AttendanceMonth.fromJson({
      'month': '2026-11-01',
      'last_day': '2026-11-30',
      'state': state,
      'confirmed_by': 'Faisal Rahman',
    });
    expect(
      attendancePrintMonthNote(month('confirmed')),
      'Month confirmed by Faisal Rahman.',
    );
    expect(
      attendancePrintMonthNote(month('not_needed')),
      'No month confirmation needed for this place.',
    );
    expect(
      attendancePrintMonthNote(month('recording')),
      'Not yet confirmed: figures can still change.',
    );
  });
}

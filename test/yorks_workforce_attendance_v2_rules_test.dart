// Workforce attendance V2 — the time-entry, hours and search rules from the
// approved prototype and the paper DAILY TIME SHEET.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/workforce/domain/attendance_models.dart';
import 'package:material_ledger/features/workforce/domain/attendance_search.dart';
import 'package:material_ledger/features/workforce/domain/attendance_time.dart';

int? _t(String text, {int? after}) =>
    parseAttendanceTime(text, after: after).minutes;

void main() {
  group('smart time entry', () {
    test('reads the shortcuts the prototype teaches', () {
      expect(_t('630'), 390);
      expect(_t('1230'), 750);
      expect(_t('17:30'), 1050);
      expect(_t('5p'), 1020);
      expect(_t('5.30pm'), 1050);
      expect(_t('12a'), 0);
      expect(_t('6:30 AM'), 390);
    });

    test('a bare hour after the previous field means the afternoon', () {
      expect(_t('5', after: 390), 1020, reason: '5 after 6:30 AM is 5 PM');
      expect(_t('1', after: 750), 780, reason: '1 after 12:30 PM is 1 PM');
      expect(_t('5', after: 780), 1020, reason: '5 after a 1 PM start');
      expect(_t('7'), 420, reason: 'no previous field: morning');
      expect(_t('9', after: 390), 540, reason: '9 after 6:30 is still 9 AM');
    });

    test('empty is allowed, nonsense is not', () {
      expect(parseAttendanceTime('').ok, isTrue);
      expect(parseAttendanceTime('').minutes, isNull);
      expect(parseAttendanceTime('abc').ok, isFalse);
      expect(parseAttendanceTime('25').ok, isFalse);
      expect(parseAttendanceTime('7:75').ok, isFalse);
    });

    test('formats like the paper sheet', () {
      expect(formatAttendanceTime(390), '6:30 AM');
      expect(formatAttendanceTime(1020), '5 PM');
      expect(formatAttendanceTime(0), '12 AM');
      expect(formatAttendanceTimeInput(1050), '5:30p');
      expect(formatAttendanceHours(480), '8');
      expect(formatAttendanceHours(210), '3.5');
      expect(formatAttendanceHours(0), '');
    });
  });

  group('hours', () {
    test('Sunday 6:30-3:00 with a 30-minute break is 8 holiday hours', () {
      final m = computeAttendanceMinutes(
        present: true,
        holiday: true,
        start: 390,
        breakStart: 750,
        breakFinish: 780,
        finish: 900,
      );
      expect(m.worked, 480);
      expect(m.holidayOvertime, 480);
      expect(m.regular, 0);
      expect(m.normalOvertime, 0);
    });

    test('a working day to 7 PM is 8 normal and 4 overtime hours', () {
      final m = computeAttendanceMinutes(
        present: true,
        holiday: false,
        start: 390,
        breakStart: 750,
        breakFinish: 780,
        finish: 1140,
      );
      expect(m.regular, 480);
      expect(m.normalOvertime, 240);
      expect(m.holidayOvertime, 0);
    });

    test('Present without Out is time missing; absent counts nothing', () {
      expect(
        computeAttendanceMinutes(
          present: true,
          holiday: false,
          start: 390,
        ).timeMissing,
        isTrue,
      );
      expect(
        computeAttendanceMinutes(present: false, holiday: false).worked,
        0,
      );
    });

    test('Sunday is the usual rest day; holidays come from the calendar', () {
      expect(attendanceIsRestDay(DateTime(2026, 11, 1)), isTrue);
      expect(attendanceIsRestDay(DateTime(2026, 11, 2)), isFalse);
      expect(
        attendanceIsRestDay(DateTime(2026, 12, 2), holidays: {'2026-12-02'}),
        isTrue,
      );
    });
  });

  group('spelling-tolerant search', () {
    const names = [
      'Oheedullah Khan',
      'Muhammad Waqar',
      'Gul Zaman',
      'SWEIHAN 321 S/S',
      'NEXUS DF3W · YRA-322',
    ];

    List<String> find(String q) => [
      for (final hit in attendanceFuzzySearch(q, names, (n) => n)) hit.item,
    ];

    test('finds the prototype examples', () {
      expect(find('oheed').first, 'Oheedullah Khan');
      expect(find('mohd').first, 'Muhammad Waqar');
      expect(find('swehan 321').first, 'SWEIHAN 321 S/S');
      expect(find('yra 322').first, 'NEXUS DF3W · YRA-322');
    });

    test('corrects a small typo and says so', () {
      final hits = attendanceFuzzySearch('gul zamn', names, (n) => n);
      expect(hits.first.item, 'Gul Zaman');
      final typo = attendanceFuzzySearch('zamen', names, (n) => n);
      expect(typo.first.item, 'Gul Zaman');
      expect(typo.first.isCorrection, isTrue);
    });

    test('unrelated text finds nothing', () {
      expect(find('xyzq'), isEmpty);
    });
  });

  group('several places a day (PRODUCT_DECISIONS 46)', () {
    const worker = AttendanceWorker(
      id: 'w1',
      number: 'W-1',
      name: 'Test Worker',
      designation: 'Helper',
    );
    AttendanceElsewhere store({
      AttendanceStatus status = AttendanceStatus.present,
      int? start = 390,
      int? finish = 720,
    }) => AttendanceElsewhere(
      crewId: 'store',
      crewName: 'Store',
      status: status,
      start: status == AttendanceStatus.present ? start : null,
      finish: status == AttendanceStatus.present ? finish : null,
      worked: status == AttendanceStatus.present ? finish! - start! : 0,
    );
    AttendanceRow here({
      AttendanceStatus? status = AttendanceStatus.present,
      int start = 780,
      int finish = 1140,
      List<AttendanceElsewhere> elsewhere = const [],
    }) => AttendanceRow(
      worker: worker,
      status: status,
      start: status == AttendanceStatus.present ? start : null,
      finish: status == AttendanceStatus.present ? finish : null,
      elsewhere: elsewhere,
    );

    test('the first 8 hours of the whole day are normal, in time order', () {
      // 6:30-12 at the store (5.5 h), 1-7 PM here (6 h): 2.5 h normal here.
      final later = here(elsewhere: [store()]).minutes(holiday: false);
      expect(later.worked, 360);
      expect(later.regular, 150);
      expect(later.normalOvertime, 210);
      // The earlier place keeps its normal hours.
      final earlier = here(
        start: 300,
        finish: 380,
        elsewhere: [store(start: 390, finish: 1140)],
      ).minutes(holiday: false);
      expect(earlier.regular, 80);
      expect(earlier.normalOvertime, 0);
      // A Sunday is all holiday overtime wherever it is worked.
      expect(
        here(elsewhere: [store()]).minutes(holiday: true).holidayOvertime,
        360,
      );
    });

    test('a member recorded elsewhere need not be marked here', () {
      final busy = here(status: null, elsewhere: [store()]);
      expect(busy.busyElsewhere, isTrue);
      expect(busy.needsMarking, isFalse);
      expect(here(status: null).needsMarking, isTrue);
      final absentThere = here(
        status: null,
        elsewhere: [store(status: AttendanceStatus.absent)],
      );
      expect(absentThere.needsMarking, isTrue, reason: 'absent there only');
    });

    test('clashes with the other places are caught before saving', () {
      expect(
        here(start: 600, finish: 900, elsewhere: [store()]).placeConflict,
        AttendancePlaceConflict.overlap,
      );
      expect(
        here(start: 720, finish: 900, elsewhere: [store()]).placeConflict,
        AttendancePlaceConflict.none,
        reason: 'starting when the other place ends is fine',
      );
      expect(
        here(
          elsewhere: [store(status: AttendanceStatus.sickLeave)],
        ).placeConflict,
        AttendancePlaceConflict.onLeaveElsewhere,
      );
      expect(
        here(
          status: AttendanceStatus.annualLeave,
          elsewhere: [store()],
        ).placeConflict,
        AttendancePlaceConflict.presentElsewhere,
      );
      expect(
        here(
          start: 1200,
          finish: 1260,
          elsewhere: [
            store(start: 300, finish: 400),
            store(start: 420, finish: 700),
            store(start: 720, finish: 1100),
          ],
        ).placeConflict,
        AttendancePlaceConflict.tooManyPlaces,
      );
    });

    test('a worker on several sheets reads back from the server', () {
      final read = AttendanceWorker.fromJson({
        'id': 'w1',
        'number': 'W-1',
        'name': 'Test Worker',
        'designation': 'Helper',
        'category': 'labour',
        'crew_id': 'a',
        'crew_name': 'Alpha',
        'crews': [
          {'id': 'a', 'name': 'Alpha'},
          {'id': 'b', 'name': 'Bravo'},
        ],
      });
      expect(read.crews.map((crew) => crew.name), ['Alpha', 'Bravo']);
      expect(read.isStaff, isFalse);
      // An older payload with one crew still reads.
      expect(
        AttendanceWorker.fromJson({
          'id': 'w1',
          'crew_id': 'a',
          'crew_name': 'Alpha',
        }).crews.single.name,
        'Alpha',
      );
    });
  });
}

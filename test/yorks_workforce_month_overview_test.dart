// Workforce monthly overview (PRODUCT_DECISIONS section 52): everyone's
// month as a grid (desktop) or cards (phone), filtered by place and searched,
// earlier months without blanking the page, a labourer's timesheet across
// places with Print under the company letterhead, and the workforce year.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/app/router.dart';
import 'package:material_ledger/features/workforce/application/attendance_providers.dart';
import 'package:material_ledger/features/workforce/data/attendance_repository.dart';
import 'package:material_ledger/features/workforce/data/attendance_sheet_service.dart';
import 'package:material_ledger/features/workforce/data/workforce_repository.dart';
import 'package:material_ledger/features/workforce/domain/attendance_month_models.dart';
import 'package:material_ledger/features/workforce/presentation/attendance/attendance_people_screen.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
// ignore: implementation_imports
import 'package:printing/src/interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/accounts_v2_golden_fonts.dart';

const _month = '2026-10-01';
const _previous = '2026-09-01';

const _flags = YorksV1FeatureFlags(
  foundation: true,
  projects: true,
  boq: true,
  excel: true,
  requests: true,
  arrangement: true,
  logistics: true,
  returnsDocuments: true,
  documents: true,
  workforce: true,
  workforceAttendanceV2: true,
);

List<Map<String, Object?>> _days(String month) {
  final start = DateTime.parse(month);
  final last = DateTime(start.year, start.month + 1, 0).day;
  return [
    for (var d = 1; d <= last; d++)
      {
        'date': '${month.substring(0, 8)}${d.toString().padLeft(2, '0')}',
        'day_type':
            DateTime(start.year, start.month, d).weekday == DateTime.sunday
            ? 'holiday'
            : 'work',
        'holiday_name': null,
      },
  ];
}

Map<String, Object?> _person(String id, String name, String number) => {
  'id': id,
  'number': number,
  'name': name,
  'designation': 'Helper',
  'company': 'Example Manpower LLC',
};

Map<String, Object?> _entry(
  String worker,
  String day,
  String place, {
  String status = 'P',
  int worked = 480,
  int overtime = 0,
  int holiday = 0,
}) => {
  'w': worker,
  'd': '2026-10-$day',
  'c': place,
  's': status,
  'm': worked,
  'r': status == 'P' ? worked - overtime - holiday : 0,
  'o': overtime,
  'h': holiday,
};

Map<String, dynamic> _peopleMonth({String month = _month}) => {
  'today': '2026-11-14',
  'month': month,
  'last_day': month == _month ? '2026-10-31' : '2026-09-30',
  'days': _days(month),
  'workers': month == _month
      ? [
          _person('w1', 'Gul Zaman', 'L-101'),
          _person('w2', 'Ravi Kumar', 'L-102'),
          _person('w3', 'Waqar Ahmed', 'L-103'),
        ]
      : [_person('w9', 'Imran Ali', 'L-109')],
  'places': [
    {
      'id': 'c1',
      'name': 'YRA-322 DF3W',
      'project_ref': 'YRA-322',
      'project_name': 'DF3W',
      'confirmed': true,
    },
    {'id': 'c2', 'name': 'Workshop', 'confirmed': false},
  ],
  'entries': month == _month
      ? [
          // Gul Zaman: two places on the 1st (8 h then 2 h overtime).
          _entry('w1', '01', 'c1', worked: 300),
          _entry('w1', '01', 'c2', worked: 300, overtime: 120),
          _entry('w1', '02', 'c1'),
          _entry('w1', '03', 'c1', status: 'A', worked: 0),
          // A Sunday at the workshop: holiday work.
          _entry('w1', '04', 'c2', worked: 240, holiday: 240),
          _entry('w2', '01', 'c1'),
          _entry('w2', '02', 'c1', status: 'SL', worked: 0),
          _entry('w3', '02', 'c2'),
        ]
      : [_entry('w9', '01', 'c1')],
};

Map<String, dynamic> _workerMonth() => {
  'today': '2026-11-14',
  'month': _month,
  'last_day': '2026-10-31',
  'worker': _person('w1', 'Gul Zaman', 'L-101'),
  'days': _days(_month),
  'rows': [
    {
      'date': '2026-10-01',
      'crew_id': 'c1',
      'crew_name': 'YRA-322 DF3W',
      'project_ref': 'YRA-322',
      'project_name': 'DF3W',
      'work_scope_name': 'Tower A',
      'status': 'P',
      'start_minute': 390,
      'finish_minute': 690,
      'worked_minutes': 300,
      'regular_minutes': 300,
      'updated_by': 'Imran Qureshi',
      'confirmed': true,
    },
    {
      'date': '2026-10-01',
      'crew_id': 'c2',
      'crew_name': 'Workshop',
      'status': 'P',
      'start_minute': 720,
      'finish_minute': 1020,
      'worked_minutes': 300,
      'regular_minutes': 180,
      'normal_overtime_minutes': 120,
      'updated_by': 'Noor Alam',
      'confirmed': false,
    },
    {
      'date': '2026-10-03',
      'crew_id': 'c1',
      'crew_name': 'YRA-322 DF3W',
      'project_ref': 'YRA-322',
      'project_name': 'DF3W',
      'status': 'A',
      'updated_by': 'Imran Qureshi',
      'confirmed': true,
    },
  ],
};

Map<String, dynamic> _year() => {
  'today': '2026-11-14',
  'year': 2026,
  'labour_headcount': 108,
  'months': [
    for (var m = 1; m <= 12; m++)
      {
        'month': '2026-${m.toString().padLeft(2, '0')}-01',
        'workers': m == 10 ? 3 : (m == 11 ? 2 : 0),
        'present_days': m == 10 ? 5 : (m == 11 ? 3 : 0),
        'absent_days': m == 10 ? 1 : 0,
        'leave_days': m == 10 ? 1 : 0,
        'worked_minutes': m == 10 ? 2340 : (m == 11 ? 1440 : 0),
        'regular_minutes': m == 10 ? 1980 : (m == 11 ? 1440 : 0),
        'normal_overtime_minutes': m == 10 ? 120 : 0,
        'holiday_overtime_minutes': m == 10 ? 240 : 0,
      },
  ],
  'places': [
    {
      'id': 'c1',
      'name': 'YRA-322 DF3W',
      'project_ref': 'YRA-322',
      'project_name': 'DF3W',
      'workers': 2,
      'present_days': 5,
      'regular_minutes': 2220,
      'normal_overtime_minutes': 0,
      'holiday_overtime_minutes': 0,
    },
    {
      'id': 'c2',
      'name': 'Workshop',
      'workers': 2,
      'present_days': 3,
      'regular_minutes': 1200,
      'normal_overtime_minutes': 120,
      'holiday_overtime_minutes': 240,
    },
  ],
  'workers': [
    {
      ..._person('w1', 'Gul Zaman', 'L-101'),
      'present_days': 4,
      'absent_days': 1,
      'regular_minutes': 1440,
      'normal_overtime_minutes': 120,
      'holiday_overtime_minutes': 240,
    },
    {
      ..._person('w2', 'Ravi Kumar', 'L-102'),
      'present_days': 2,
      'leave_days': 1,
      'regular_minutes': 960,
    },
  ],
};

final class _FakeRpc implements YorksWorkforceRpcClient {
  _FakeRpc(this.handlers);

  final Map<
    String,
    FutureOr<Map<String, dynamic>> Function(Map<String, Object?>)
  >
  handlers;
  final calls = <(String, Map<String, Object?>)>[];

  @override
  Future<Map<String, dynamic>> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async {
    calls.add((functionName, parameters));
    final handler = handlers[functionName];
    if (handler == null) throw StateError('unexpected $functionName');
    return handler(parameters);
  }
}

final class _Online implements ConnectivityService {
  const _Online();
  @override
  bool get isOnline => true;
  @override
  Stream<bool> get onChange => const Stream.empty();
}

class _CapturePrinting extends PrintingPlatform {
  Uint8List? bytes;
  String? name;

  @override
  Future<bool> layoutPdf(
    Printer? printer,
    LayoutCallback onLayout,
    String name,
    PdfPageFormat format,
    bool dynamicLayout,
    bool usePrinterSettings,
    OutputType outputType,
    bool forceCustomPrintPaper,
    bool windowsModernDialog,
  ) async {
    this.name = name;
    bytes = await onLayout(format);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

_FakeRpc _server({
  FutureOr<Map<String, dynamic>> Function(Map<String, Object?>)? people,
}) => _FakeRpc({
  'v1_wf_people_month':
      people ?? (params) => _peopleMonth(month: params['p_month']! as String),
  'v1_wf_worker_month': (_) => _workerMonth(),
  'v1_wf_workforce_year': (_) => _year(),
});

Future<GoRouter> _pump(
  WidgetTester tester,
  _FakeRpc rpc,
  String location,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: RoutePaths.yorksV1WorkforceMonth,
        builder: (_, state) => Scaffold(
          body: AttendancePeopleScreen(
            initialView: state.uri.queryParameters['view'],
            initialMonth: state.uri.queryParameters['month'],
            initialYear: state.uri.queryParameters['year'],
            initialWorkerId: state.uri.queryParameters['worker'],
            initialPlaceId: state.uri.queryParameters['place'],
          ),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        yorksV1AuthUserIdProvider.overrideWithValue('actor-1'),
        yorksAttendanceRepositoryProvider.overrideWithValue(
          YorksAttendanceRepository(
            featureFlags: _flags,
            connectivity: const _Online(),
            rpcClient: rpc,
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

String _at(String query) => '${RoutePaths.yorksV1WorkforceMonth}?$query';

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAccountsV2GoldenFonts);

  test('a labourer counts once a day across places', () {
    final month = AttendancePeopleMonth.fromJson(_peopleMonth());
    final gul = month.people().firstWhere((p) => p.person.id == 'w1');
    expect(gul.presentDays, 3, reason: '1st (two places), 2nd and 4th');
    expect(gul.absentDays, 1);
    expect(gul.days['2026-10-01']!.places, 2);
    expect(gul.days['2026-10-01']!.worked, 600);
    expect(gul.normalOvertime, 120);
    expect(gul.holidayOvertime, 240);
    final ravi = month.people().firstWhere((p) => p.person.id == 'w2');
    expect(ravi.leaveDays, 1);
    // At the workshop only.
    final workshop = month.people(placeId: 'c2');
    expect(workshop.map((p) => p.person.id), ['w1', 'w3']);
    expect(
      workshop.first.presentDays,
      2,
      reason: 'the 1st and the 4th at the workshop',
    );
  });

  // Before any widget test prints: the logo is loaded once and cached.
  test('the timesheet prints under the letterhead', () async {
    const service = YorksAttendanceSheetService();
    final month = AttendanceWorkerMonth.fromJson(_workerMonth());
    final bytes = await service.buildWorkerMonthPdf(month);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(month.presentDays, 1);
    expect(month.worked, 600);
    expect(month.allConfirmed, isFalse);
  });

  testWidgets('the desktop month grid keeps names, days and totals', (
    tester,
  ) async {
    _size(tester, const Size(1280, 900));
    await _pump(tester, _server(), _at('view=month&month=$_month'));

    expect(find.byKey(const ValueKey('attendance-month-grid')), findsOneWidget);
    expect(find.text('Gul Zaman'), findsOneWidget);
    expect(find.text('October 2026'), findsWidgets);
    // Two places on the 1st: 10 hours that day.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('attendance-month-cell-w1-2026-10-01')),
        matching: find.text('10'),
      ),
      findsOneWidget,
    );
    expect(find.text('A'), findsOneWidget);
    expect(find.text('L'), findsOneWidget);
    // KPIs: 3 labourers, 5 days present (a day at two places counts once).
    expect(find.text('5'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey('attendance-overview-search')),
      'ravi',
    );
    await tester.pumpAndSettle();
    expect(find.text('Gul Zaman'), findsNothing);
    expect(find.text('Ravi Kumar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a place shows only its labourers', (tester) async {
    _size(tester, const Size(1280, 900));
    await _pump(tester, _server(), _at('view=month&month=$_month&place=c2'));
    expect(find.text('Gul Zaman'), findsOneWidget);
    expect(find.text('Waqar Ahmed'), findsOneWidget);
    expect(find.text('Ravi Kumar'), findsNothing);
  });

  testWidgets('an earlier month loads under the same page', (tester) async {
    _size(tester, const Size(1280, 900));
    final september = Completer<Map<String, dynamic>>();
    await _pump(
      tester,
      _server(
        people: (params) =>
            params['p_month'] == _previous ? september.future : _peopleMonth(),
      ),
      _at('view=month&month=$_month'),
    );
    await tester.tap(find.byKey(const ValueKey('attendance-period-previous')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('September 2026'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('attendance-period-loading')),
      findsOneWidget,
    );
    // October stays on screen, faded, until September arrives.
    expect(find.text('Gul Zaman'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    september.complete(_peopleMonth(month: _previous));
    await tester.pumpAndSettle();
    expect(find.text('Gul Zaman'), findsNothing);
    expect(find.text('Imran Ali'), findsOneWidget);
  });

  testWidgets('no month after this one', (tester) async {
    _size(tester, const Size(1280, 900));
    final now = DateTime.now();
    final thisMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    await _pump(tester, _server(), _at('view=month&month=$thisMonth'));
    final next = tester.widget<IconButton>(
      find.byKey(const ValueKey('attendance-period-next')),
    );
    expect(next.onPressed, isNull);
  });

  testWidgets('a phone card opens the timesheet, which prints', (tester) async {
    _size(tester, const Size(360, 800));
    final previous = PrintingPlatform.instance;
    final printer = _CapturePrinting();
    PrintingPlatform.instance = printer;
    addTearDown(() => PrintingPlatform.instance = previous);

    final rpc = _server();
    await _pump(tester, rpc, _at('view=month&month=$_month'));
    expect(find.byKey(const ValueKey('attendance-month-grid')), findsNothing);
    await _tap(tester, find.byKey(const ValueKey('attendance-person-w1')));

    expect(rpc.calls.lastWhere((c) => c.$1 == 'v1_wf_worker_month').$2, {
      'p_worker_id': 'w1',
      'p_month': _month,
    });
    expect(find.text('YRA-322 · DF3W · Tower A'), findsOneWidget);
    expect(find.text('Workshop'), findsWidgets);
    expect(
      find.byKey(const ValueKey('attendance-timesheet-note')),
      findsOneWidget,
    );

    await _tap(
      tester,
      find.byKey(const ValueKey('attendance-timesheet-print')),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 50 && printer.bytes == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();
    expect(printer.name, 'Yorks-timesheet-Gul-Zaman-October-2026');
    expect(String.fromCharCodes(printer.bytes!.take(4)), '%PDF');

    await _tap(tester, find.byKey(const ValueKey('attendance-timesheet-back')));
    expect(find.byKey(const ValueKey('attendance-person-w1')), findsOneWidget);
  });

  testWidgets('the year: by month, place and labourer', (tester) async {
    _size(tester, const Size(1280, 1400));
    await _pump(tester, _server(), _at('view=year&year=2026'));
    expect(find.textContaining('108 labourers on the books'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('attendance-year-months')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('attendance-year-places')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('attendance-year-workers')),
      findsOneWidget,
    );
    await _tap(
      tester,
      find.byKey(const ValueKey('attendance-year-month-2026-10-01')),
    );
    expect(find.byKey(const ValueKey('attendance-month-grid')), findsOneWidget);
  });

  group('screenshots (desktop and 360px phone)', () {
    for (final (name, size) in [
      ('phone', const Size(360, 800)),
      ('desktop', const Size(1280, 900)),
    ]) {
      testWidgets('$name month', (tester) async {
        _size(tester, size);
        await _pump(tester, _server(), _at('view=month&month=$_month'));
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/attendance_month_${name}_overview.png'),
        );
      });

      testWidgets('$name timesheet', (tester) async {
        _size(tester, size);
        await _pump(
          tester,
          _server(),
          _at('view=month&month=$_month&worker=w1'),
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/attendance_month_${name}_timesheet.png'),
        );
      });

      testWidgets('$name year', (tester) async {
        _size(tester, size);
        await _pump(tester, _server(), _at('view=year&year=2026'));
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/attendance_month_${name}_year.png'),
        );
      });
    }
  });
}

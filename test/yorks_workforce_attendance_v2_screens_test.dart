// Workforce attendance V2 — the prototype screens against a fake server:
// a phone crew day (pills, Everyone present, Save), a reason when changing a
// day someone else entered, the desktop grid, month confirmation and the
// monthly sheet.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/app/router.dart';
import 'package:material_ledger/features/workforce/application/attendance_providers.dart';
import 'package:material_ledger/features/workforce/data/attendance_repository.dart';
import 'package:material_ledger/features/workforce/data/workforce_repository.dart';
import 'package:material_ledger/features/workforce/presentation/attendance/attendance_confirm_screen.dart';
import 'package:material_ledger/features/workforce/presentation/attendance/attendance_overview_screen.dart';
import 'package:material_ledger/features/workforce/presentation/attendance/attendance_sheets_screen.dart';
import 'package:material_ledger/features/workforce/presentation/attendance/attendance_take_screen.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/accounts_v2_golden_fonts.dart';

const _crewId = '5a000000-0000-4000-8000-000000000001';
const _today = '2026-11-12';
const _date = '2026-11-10'; // a Tuesday

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

Map<String, Object?> _access({
  bool take = true,
  bool confirm = false,
  bool officer = false,
}) => {
  'view': true,
  'take': take,
  'confirm': confirm,
  'manage': confirm || officer,
  'officer': officer,
};

Map<String, Object?> _crew({Map<String, Object?>? access}) => {
  'id': _crewId,
  'name': 'Sweihan site crew',
  'code': 'CREW-1',
  'kind': 'project',
  'project_id': 'p1',
  'project_ref': 'YRA-321',
  'project_name': 'Sweihan',
  'work_label': 'Sweihan · YRA-321',
  'needs_confirmation': true,
  'shift_start_minute': 390,
  'shift_finish_minute': 1020,
  'break_start_minute': 750,
  'break_finish_minute': 780,
  'is_active': true,
  'record_version': 1,
  'member_count': 2,
  'access': access ?? _access(),
};

Map<String, Object?> _worker(String id, String name) => {
  'id': id,
  'number': 'W-$id',
  'name': name,
  'designation': 'Helper',
  'company': 'Example Manpower LLC',
  'crew_id': _crewId,
  'crew_name': 'Sweihan site crew',
};

Map<String, Object?> _month({
  String state = 'recording',
  List<String> missing = const [_date],
  bool canConfirm = false,
}) => {
  'month': '2026-11-01',
  'last_day': '2026-11-30',
  'state': state,
  'days': [
    for (var d = 1; d <= 30; d++)
      {
        'date': '2026-11-${d.toString().padLeft(2, '0')}',
        'state': d > 12
            ? 'future'
            : DateTime(2026, 11, d).weekday == DateTime.sunday
            ? 'off'
            : missing.contains('2026-11-${d.toString().padLeft(2, '0')}')
            ? 'none'
            : 'entered',
        'day_type': DateTime(2026, 11, d).weekday == DateTime.sunday
            ? 'holiday'
            : 'work',
      },
  ],
  'missing_days': missing,
  'work_days_so_far': 10,
  'days_entered': 10 - missing.length,
  'regular_minutes': 4800,
  'normal_overtime_minutes': 180,
  'holiday_overtime_minutes': 0,
  'can_confirm': canConfirm,
  'record_version': 0,
};

Map<String, Object?> _day({
  bool saved = false,
  bool enteredByMe = true,
  List<Map<String, Object?>>? rows,
  Map<String, Object?>? access,
}) => {
  'schema_version': 'yorks.workforce.day.v2',
  'crew': _crew(access: access),
  'date': _date,
  'today': _today,
  'day_type': 'work',
  'saved': saved,
  'record_version': saved ? 1 : 0,
  'entered_by': saved ? 'Imran Qureshi' : null,
  'entered_by_me': enteredByMe,
  'entered_at': saved ? '2026-11-10T14:00:00Z' : null,
  'locked': false,
  'is_future': false,
  'previous_same_type_date': '2026-11-09',
  'rows':
      rows ??
      [
        {
          'worker_id': 'w1',
          'status': null,
          'worker': _worker('w1', 'Gul Zaman'),
        },
        {
          'worker_id': 'w2',
          'status': null,
          'worker': _worker('w2', 'Waqar Ahmed'),
        },
      ],
  'question': null,
  'changes': <Object>[],
  'access': access ?? _access(),
  'month': _month(),
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

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(WidgetTester tester, _FakeRpc rpc, String location) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: RoutePaths.yorksV1Workforce,
        builder: (_, _) => const Scaffold(body: AttendanceOverviewScreen()),
      ),
      GoRoute(
        path: RoutePaths.yorksV1WorkforceAttendance,
        builder: (_, state) => Scaffold(
          body: AttendanceTakeScreen(
            initialCrewId: state.uri.queryParameters['crew'],
            initialDate: state.uri.queryParameters['date'],
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1WorkforceConfirm,
        builder: (_, _) => const Scaffold(body: AttendanceConfirmScreen()),
      ),
      GoRoute(
        path: RoutePaths.yorksV1WorkforceSheets,
        builder: (_, state) => Scaffold(
          body: AttendanceSheetsScreen(
            initialCrewId: state.uri.queryParameters['crew'],
          ),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
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
}

Map<String, dynamic> _crews(Map<String, Object?> access) => {
  'crews': [_crew(access: access)],
  'can_create_crew': false,
};

void main() {
  testWidgets('a phone crew day: pills, Everyone present and one Save', (
    tester,
  ) async {
    _size(tester, const Size(360, 800));
    Map<String, Object?>? saved;
    final rpc = _FakeRpc({
      'v1_wf_list_crews': (_) => _crews(_access()),
      'v1_wf_list_workers': (_) => {'workers': <Object>[]},
      'v1_wf_get_day': (_) => _day(),
      'v1_wf_save_day': (params) {
        saved = params;
        return _day(
          saved: true,
          rows: [
            for (final row in params['p_rows'] as List)
              {
                ...(row as Map<String, Object?>),
                'worker': _worker(
                  row['worker_id'] as String,
                  row['worker_id'] == 'w1' ? 'Gul Zaman' : 'Waqar Ahmed',
                ),
              },
          ],
        );
      },
    });
    await _pump(
      tester,
      rpc,
      '${RoutePaths.yorksV1WorkforceAttendance}?crew=$_crewId&date=$_date',
    );

    expect(find.text('Gul Zaman'), findsOneWidget);
    expect(find.text('Not marked'), findsNWidgets(2));
    // The pills are 44px tap targets on a phone.
    expect(
      tester.getSize(find.byKey(const ValueKey('attendance-pill-a-w2'))).height,
      greaterThanOrEqualTo(44),
    );
    // Save waits until everyone is marked.
    final save = find.byKey(const ValueKey('attendance-save-day'));
    expect(save, findsOneWidget);

    final pillFinder = find.byKey(const ValueKey('attendance-pill-a-w2'));
    await tester.ensureVisible(pillFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('attendance-pill-a-w2')));
    await tester.pumpAndSettle();
    expect(find.text('Absent'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('attendance-everyone-present')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('attendance-everyone-present')));
    await tester.pumpAndSettle();
    expect(find.textContaining('6:30 AM – 5 PM · break'), findsOneWidget);

    // The unsaved day stays on this device.
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getKeys().any((k) => k.contains('attendance.draft')),
      isTrue,
    );

    // Let the confirmation message clear the Save bar.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(rpc.calls.where((c) => c.$1 == 'v1_wf_save_day'), hasLength(1));
    final rows = saved!['p_rows'] as List;
    expect(rows.map((r) => (r as Map)['status']), ['P', 'A']);
    expect((rows.first as Map)['start_minute'], 390);
    expect((rows.first as Map)['finish_minute'], 1020);
    expect(saved!['p_change_reason'], isNull);
    expect(
      preferences.getKeys().any((k) => k.contains('attendance.draft')),
      isFalse,
      reason: 'the draft is cleared only after the server confirms',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing a day someone else entered asks for a reason', (
    tester,
  ) async {
    _size(tester, const Size(360, 800));
    Map<String, Object?>? saved;
    final enteredRows = [
      {
        'worker_id': 'w1',
        'status': 'P',
        'start_minute': 390,
        'break_start_minute': 750,
        'break_finish_minute': 780,
        'finish_minute': 1020,
        'worker': _worker('w1', 'Gul Zaman'),
      },
      {
        'worker_id': 'w2',
        'status': 'A',
        'worker': _worker('w2', 'Waqar Ahmed'),
      },
    ];
    final rpc = _FakeRpc({
      'v1_wf_list_crews': (_) => _crews(_access(confirm: true)),
      'v1_wf_list_workers': (_) => {'workers': <Object>[]},
      'v1_wf_get_day': (_) => _day(
        saved: true,
        enteredByMe: false,
        rows: enteredRows,
        access: _access(confirm: true),
      ),
      'v1_wf_save_day': (params) {
        saved = params;
        return _day(
          saved: true,
          enteredByMe: false,
          rows: enteredRows,
          access: _access(confirm: true),
        );
      },
    });
    await _pump(
      tester,
      rpc,
      '${RoutePaths.yorksV1WorkforceAttendance}?crew=$_crewId&date=$_date',
    );
    expect(find.textContaining('Entered by Imran Qureshi'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('attendance-pill-p-w2')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('attendance-pill-p-w2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('attendance-save-day')));
    await tester.pumpAndSettle();
    expect(find.text('Why are you changing Tue 10 Nov?'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('attendance-text-dialog-field')),
      'Gate log shows he came',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('attendance-text-dialog-confirm')),
    );
    await tester.pumpAndSettle();
    expect(saved!['p_change_reason'], 'Gate log shows he came');
    expect(saved!['p_expected_version'], 1);
  });

  testWidgets('desktop takes the day in a keyboard grid', (tester) async {
    _size(tester, const Size(1400, 900));
    final rpc = _FakeRpc({
      'v1_wf_list_crews': (_) => _crews(_access()),
      'v1_wf_list_workers': (_) => {'workers': <Object>[]},
      'v1_wf_get_day': (_) => _day(),
    });
    await _pump(
      tester,
      rpc,
      '${RoutePaths.yorksV1WorkforceAttendance}?crew=$_crewId&date=$_date',
    );
    expect(
      find.byKey(const ValueKey('attendance-grid-status-w1')),
      findsOneWidget,
    );
    expect(find.text('IN'), findsOneWidget);
    expect(find.text('OT HOLIDAY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a confirmer confirms a complete month once', (tester) async {
    _size(tester, const Size(1280, 900));
    var confirmed = 0;
    final rpc = _FakeRpc({
      'v1_wf_get_overview': (_) => {
        'today': '2026-11-30',
        'month': '2026-11-01',
        'crews': [
          {
            ..._crew(access: _access(confirm: true)),
            'month': _month(state: 'ready', missing: [], canConfirm: true),
          },
        ],
        'feed': <Object>[],
      },
      'v1_wf_get_month_sheet': (_) => {
        'crew': _crew(),
        'month': _month(state: 'ready', missing: [], canConfirm: true),
        'workers': <Object>[],
        'sheets': <Object>[],
        'holidays': <Object>[],
        'can_export': false,
      },
      'v1_wf_confirm_month': (_) {
        confirmed++;
        return _month(state: 'confirmed', missing: []);
      },
    });
    await _pump(tester, rpc, RoutePaths.yorksV1WorkforceConfirm);
    final button = find.byKey(
      const ValueKey('attendance-confirm-month-$_crewId'),
    );
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.textContaining('The month locks'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('attendance-confirm-month-yes')),
    );
    await tester.pumpAndSettle();
    expect(confirmed, 1);
  });

  testWidgets('the overview shows every crew with its last eight days', (
    tester,
  ) async {
    _size(tester, const Size(360, 800));
    final rpc = _FakeRpc({
      'v1_wf_get_overview': (_) => {
        'today': _today,
        'month': '2026-11-01',
        'crews': [
          {..._crew(), 'month': _month()},
        ],
        'feed': [
          {
            'kind': 'entered',
            'crew_id': _crewId,
            'crew_name': 'Sweihan site crew',
            'date': '2026-11-09',
            'by': 'Imran Qureshi',
            'at': '2026-11-09T15:00:00Z',
            'summary': {'present': 9, 'absent': 1, 'leave': 0},
          },
        ],
      },
    });
    await _pump(tester, rpc, RoutePaths.yorksV1Workforce);
    expect(find.text('Workforce Overview'), findsOneWidget);
    expect(find.text('Sweihan site crew'), findsWidgets);
    expect(find.textContaining('Imran Qureshi entered'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the monthly sheet is the paper DAILY TIME SHEET on desktop', (
    tester,
  ) async {
    _size(tester, const Size(1400, 1000));
    final rpc = _FakeRpc({
      'v1_wf_list_crews': (_) => _crews(_access(take: false)),
      'v1_wf_get_month_sheet': (_) => {
        'crew': _crew(access: _access(take: false)),
        'month': _month(),
        'workers': [
          {
            ..._worker('w1', 'Gul Zaman'),
            'days': [
              {
                'date': '2026-11-02',
                'status': 'P',
                'start_minute': 390,
                'break_start_minute': 750,
                'break_finish_minute': 780,
                'finish_minute': 1140,
              },
            ],
          },
        ],
        'sheets': [
          {
            'date': '2026-11-02',
            'entered_by': 'Imran Qureshi',
            'changed': false,
          },
        ],
        'holidays': <Object>[],
        'can_export': true,
      },
    });
    await _pump(tester, rpc, RoutePaths.yorksV1WorkforceSheets);
    expect(find.text('DAILY TIME SHEET'), findsOneWidget);
    expect(find.text('Read only'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('attendance-sheet-excel')),
      findsOneWidget,
    );
    expect(find.text('7 PM'), findsOneWidget);
    expect(find.text('4'), findsWidgets, reason: '4 h normal overtime');
    expect(tester.takeException(), isNull);
  });

  group('screenshots (desktop and 360px phone)', () {
    setUpAll(loadAccountsV2GoldenFonts);

    Map<String, dynamic> overview() => {
      'today': _today,
      'month': '2026-11-01',
      'crews': [
        {..._crew(), 'month': _month()},
        {
          ..._crew(),
          'id': 'c2',
          'name': 'Workshop crew',
          'kind': 'workshop',
          'work_label': 'Workshop · Mussafah',
          'needs_confirmation': false,
          'member_count': 6,
          'month': _month(state: 'not_needed', missing: []),
        },
      ],
      'feed': [
        {
          'kind': 'entered',
          'crew_id': _crewId,
          'crew_name': 'Sweihan site crew',
          'date': '2026-11-11',
          'by': 'Imran Qureshi',
          'at': '2026-11-11T15:05:00Z',
          'summary': {
            'present': 9,
            'absent': 1,
            'leave': 0,
            'normal_overtime_minutes': 150,
          },
        },
        {
          'kind': 'asked',
          'crew_id': _crewId,
          'crew_name': 'Sweihan site crew',
          'date': '2026-11-06',
          'by': 'Faisal Rahman',
          'at': '2026-11-07T09:12:00Z',
          'summary': {'question': 'Gul Zaman until 7 PM - did the client ask?'},
        },
      ],
    };

    final dayRpc = {
      'v1_wf_list_crews': (_) => _crews(_access()),
      'v1_wf_list_workers': (_) => {'workers': <Object>[]},
      'v1_wf_get_day': (_) => _day(
        rows: [
          {
            'worker_id': 'w1',
            'status': 'P',
            'start_minute': 390,
            'break_start_minute': 750,
            'break_finish_minute': 780,
            'finish_minute': 1140,
            'overtime_note': 'Concrete pour',
            'worker': _worker('w1', 'Gul Zaman'),
          },
          {
            'worker_id': 'w2',
            'status': 'SL',
            'worker': _worker('w2', 'Waqar Ahmed'),
          },
          {
            'worker_id': 'w3',
            'status': null,
            'worker': _worker('w3', 'Oheedullah Khan'),
          },
        ],
      ),
    };

    Future<void> shot(
      WidgetTester tester,
      Size size,
      Map<String, FutureOr<Map<String, dynamic>> Function(Map<String, Object?>)>
      handlers,
      String location,
      String name,
    ) async {
      _size(tester, size);
      await _pump(tester, _FakeRpc(handlers), location);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/attendance_v2_$name.png'),
      );
    }

    const day = '/yorks/workforce/attendance?crew=$_crewId&date=$_date';

    testWidgets('phone take attendance', (tester) async {
      await shot(tester, const Size(360, 800), dayRpc, day, 'phone_take');
    });
    testWidgets('desktop take attendance', (tester) async {
      await shot(tester, const Size(1280, 860), dayRpc, day, 'desktop_take');
    });
    testWidgets('phone overview', (tester) async {
      await shot(
        tester,
        const Size(360, 800),
        {'v1_wf_get_overview': (_) => overview()},
        RoutePaths.yorksV1Workforce,
        'phone_overview',
      );
    });
    testWidgets('desktop overview', (tester) async {
      await shot(
        tester,
        const Size(1280, 900),
        {'v1_wf_get_overview': (_) => overview()},
        RoutePaths.yorksV1Workforce,
        'desktop_overview',
      );
    });
  });
}

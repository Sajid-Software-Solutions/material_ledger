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
import 'package:material_ledger/features/workforce/presentation/attendance/attendance_crews_screen.dart';
import 'package:material_ledger/features/workforce/presentation/attendance/attendance_overview_screen.dart';
import 'package:material_ledger/features/workforce/presentation/attendance/attendance_sheets_screen.dart';
import 'package:material_ledger/features/workforce/presentation/attendance/attendance_take_screen.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_portfolio_provider.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

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

/// A row another keeper saved: changing it needs a reason.
const _savedByOther = <String, Object?>{
  'updated_by': 'Imran Qureshi',
  'updated_by_me': false,
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
    final handler =
        handlers[functionName] ??
        (functionName == 'v1_wf_get_confirmations_due'
            ? (_) => {'due': <Object>[]}
            : null);
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

Future<void> _pump(
  WidgetTester tester,
  _FakeRpc rpc,
  String location, {
  YorksV1FeatureFlags? featureFlags,
}) async {
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
        if (featureFlags != null)
          yorksV1FeatureFlagsProvider.overrideWithValue(featureFlags),
        yorksAttendanceRepositoryProvider.overrideWithValue(
          YorksAttendanceRepository(
            featureFlags: featureFlags ?? _flags,
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
        ..._savedByOther,
      },
      {
        'worker_id': 'w2',
        'status': 'A',
        'worker': _worker('w2', 'Waqar Ahmed'),
        ..._savedByOther,
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

  group('crew document status', () {
    setUpAll(loadAccountsV2GoldenFonts);
    const peopleFlags = YorksV1FeatureFlags(
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
      peopleRecords: true,
    );
    _FakeRpc server() => _FakeRpc({
      'v1_wf_list_crews': (_) => _crews(_access()),
      'v1_wf_list_workers': (_) => {'workers': <Object>[]},
      'v1_wf_get_day': (_) => _day(),
      'v1_wf_crew_document_status': (params) {
        expect(params, {'p_team_id': _crewId});
        return {
          'statuses': {'w1': 'expired', 'w2': 'ok'},
        };
      },
    });

    testWidgets('a phone row says only that documents expired', (tester) async {
      _size(tester, const Size(360, 800));
      final rpc = server();
      await _pump(
        tester,
        rpc,
        '${RoutePaths.yorksV1WorkforceAttendance}?crew=$_crewId&date=$_date',
        featureFlags: peopleFlags,
      );
      expect(find.text('Documents expired'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('crew-doc-status-w2')),
        findsOneWidget,
        reason: 'OK is a small check, not a chip',
      );
      expect(find.text('Documents OK'), findsNothing);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/attendance_v2_phone_doc_status.png'),
      );
      expect(
        rpc.calls.where((c) => c.$1 == 'v1_wf_crew_document_status'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the desktop grid shows an icon beside each name', (
      tester,
    ) async {
      _size(tester, const Size(1400, 900));
      await _pump(
        tester,
        server(),
        '${RoutePaths.yorksV1WorkforceAttendance}?crew=$_crewId&date=$_date',
        featureFlags: peopleFlags,
      );
      expect(find.byKey(const ValueKey('crew-doc-status-w1')), findsOneWidget);
      expect(
        find.byTooltip('Documents expired. Ask HR/PRO to renew them.'),
        findsOneWidget,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/attendance_v2_desktop_doc_status.png'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('with People off nothing is asked or shown', (tester) async {
      _size(tester, const Size(360, 800));
      final rpc = server();
      await _pump(
        tester,
        rpc,
        '${RoutePaths.yorksV1WorkforceAttendance}?crew=$_crewId&date=$_date',
      );
      expect(find.byKey(const ValueKey('crew-doc-status-w1')), findsNothing);
      expect(
        rpc.calls.where((c) => c.$1 == 'v1_wf_crew_document_status'),
        isEmpty,
      );
    });
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
      find.byKey(const ValueKey('attendance-text-dialog-confirm')),
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

  testWidgets('a month waiting for confirmation comes first, one tap away', (
    tester,
  ) async {
    _size(tester, const Size(360, 800));
    String? openedMonth;
    final rpc = _FakeRpc({
      'v1_wf_get_confirmations_due': (_) => {
        'due': [
          {
            'crew_id': _crewId,
            'crew_name': 'Sweihan site crew',
            'month': '2026-10-01',
            'last_day': '2026-10-31',
            'overdue': true,
            'missing_days': 2,
          },
        ],
      },
      'v1_wf_get_overview': (params) {
        openedMonth = params['p_month'] as String?;
        return {
          'today': _today,
          'month': params['p_month'] ?? '2026-11-01',
          'crews': [
            {..._crew(access: _access(confirm: true)), 'month': _month()},
          ],
          'feed': <Object>[],
        };
      },
      'v1_wf_get_month_sheet': (_) => {
        'crew': _crew(),
        'month': _month(),
        'workers': <Object>[],
        'sheets': <Object>[],
        'holidays': <Object>[],
        'can_export': false,
      },
    });
    await _pump(tester, rpc, RoutePaths.yorksV1Workforce);
    final banner = find.byKey(const ValueKey('attendance-confirmations-due'));
    expect(banner, findsOneWidget);
    expect(
      find.text('October 2026 is waiting for your confirmation'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Sweihan site crew (2 days not entered)'),
      findsOneWidget,
    );
    // Shown above everything else on the page.
    expect(
      tester.getTopLeft(banner).dy,
      lessThan(tester.getTopLeft(find.text('Earlier days not entered')).dy),
    );
    await tester.tap(find.byKey(const ValueKey('attendance-confirm-now')));
    await tester.pumpAndSettle();
    expect(openedMonth, '2026-10-01', reason: 'opens on the waiting month');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Everyone present can be undone', (tester) async {
    _size(tester, const Size(360, 800));
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
    final everyone = find.byKey(const ValueKey('attendance-everyone-present'));
    await tester.ensureVisible(everyone);
    await tester.pumpAndSettle();
    await tester.tap(everyone);
    await tester.pumpAndSettle();
    expect(find.text('Not marked'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('attendance-undo')));
    await tester.pumpAndSettle();
    expect(find.text('Not marked'), findsNWidgets(2));
    expect(find.text('Not saved yet'), findsNothing);
  });

  testWidgets('a refused change keeps the reason dialog open with the reason', (
    tester,
  ) async {
    _size(tester, const Size(360, 800));
    final enteredRows = [
      {
        'worker_id': 'w1',
        'status': 'A',
        'worker': _worker('w1', 'Gul Zaman'),
        ..._savedByOther,
      },
      {
        'worker_id': 'w2',
        'status': 'A',
        'worker': _worker('w2', 'Waqar Ahmed'),
        ..._savedByOther,
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
      'v1_wf_save_day': (_) => throw const PostgrestException(
        message: 'V1_WORKFORCE_MONTH_LOCKED',
        code: '55000',
      ),
    });
    await _pump(
      tester,
      rpc,
      '${RoutePaths.yorksV1WorkforceAttendance}?crew=$_crewId&date=$_date',
    );
    final pill = find.byKey(const ValueKey('attendance-pill-p-w2'));
    await tester.ensureVisible(pill);
    await tester.pumpAndSettle();
    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(find.text('Not saved yet'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('attendance-save-day')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('attendance-text-dialog-field')),
      'Came after lunch',
    );
    await tester.tap(
      find.byKey(const ValueKey('attendance-text-dialog-confirm')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('attendance-dialog-error')),
      findsOneWidget,
    );
    expect(find.text('This month is confirmed and locked.'), findsWidgets);
    expect(find.text('Came after lunch'), findsOneWidget);
  });

  testWidgets('after a conflict, Keep my entries saves on the new version', (
    tester,
  ) async {
    _size(tester, const Size(1280, 900));
    var version = 0;
    final saves = <Map<String, Object?>>[];
    final rpc = _FakeRpc({
      'v1_wf_list_crews': (_) => _crews(_access()),
      'v1_wf_list_workers': (_) => {'workers': <Object>[]},
      'v1_wf_get_day': (_) => {..._day(), 'record_version': version},
      'v1_wf_save_day': (params) {
        saves.add(params);
        if (saves.length == 1) {
          version = 1; // someone else saved first
          throw const PostgrestException(
            message: 'V1_WORKFORCE_DAY_VERSION_CONFLICT',
            code: '40001',
          );
        }
        return _day(saved: true);
      },
    });
    await _pump(
      tester,
      rpc,
      '${RoutePaths.yorksV1WorkforceAttendance}?crew=$_crewId&date=$_date',
    );
    await tester.tap(find.byKey(const ValueKey('attendance-everyone-present')));
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('attendance-save-day')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('attendance-keep-mine')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('attendance-keep-mine')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('attendance-save-day')));
    await tester.pumpAndSettle();
    expect(saves, hasLength(2));
    expect(saves.last['p_expected_version'], 1);
    expect((saves.last['p_rows'] as List).map((r) => (r as Map)['status']), [
      'P',
      'P',
    ], reason: 'my entries were kept on top of the saved day');
  });

  testWidgets('Admin and PR manage public holidays on the Crews page', (
    tester,
  ) async {
    _size(tester, const Size(1280, 900));
    final rpc = _FakeRpc({
      'v1_wf_list_crews': (_) => _crews(_access(officer: true)),
      'v1_wf_list_public_holidays': (_) => {
        'year': DateTime.now().year,
        'can_manage': true,
        'holidays': [
          {'date': '${DateTime.now().year}-12-02', 'name': 'National Day'},
        ],
      },
    });
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
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
          yorksV1ProjectPortfolioProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(home: Scaffold(body: AttendanceCrewsScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('National Day'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('attendance-add-holiday')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  group('phone: quick, native and the same everywhere', () {
    setUpAll(loadAccountsV2GoldenFonts);

    Map<String, Object?> poolWorker(String id, String name) => {
      ..._worker(id, name),
      'crew_id': null,
      'crew_name': null,
    };
    Map<String, Object?> otherCrewWorker(String id, String name) => {
      ..._worker(id, name),
      'crew_id': 'c2',
      'crew_name': 'Workshop crew',
    };
    final workers = [
      _worker('w1', 'Gul Zaman'),
      _worker('w2', 'Waqar Ahmed'),
      poolWorker('w3', 'Sajid Khan'),
      otherCrewWorker('w4', 'Noor Alam'),
      poolWorker('w5', 'Imran Ali'),
    ];
    Map<String, FutureOr<Map<String, dynamic>> Function(Map<String, Object?>)>
    day() => {
      'v1_wf_list_crews': (_) => _crews(_access()),
      'v1_wf_list_workers': (_) => {'workers': workers},
      'v1_wf_get_day': (_) => _day(),
    };
    const dayAt =
        '${RoutePaths.yorksV1WorkforceAttendance}?crew=$_crewId&date=$_date';

    testWidgets('each worker is one compact row with the pills beside it', (
      tester,
    ) async {
      _size(tester, const Size(360, 800));
      await _pump(tester, _FakeRpc(day()), dayAt);
      final row = tester.getRect(
        find.byKey(const ValueKey('attendance-row-w1')),
      );
      final pill = tester.getRect(
        find.byKey(const ValueKey('attendance-pill-p-w1')),
      );
      final name = tester.getRect(find.text('Gul Zaman'));
      expect(pill.height, greaterThanOrEqualTo(44));
      expect(pill.top, lessThan(name.bottom + 24), reason: 'beside the name');
      expect(row.height, lessThan(90));
      // Every quick action is in sight on the narrowest phone.
      for (final key in [
        'attendance-everyone-present',
        'attendance-copy-previous',
        'attendance-shift',
        'attendance-add-worker-open',
      ]) {
        final rect = tester.getRect(find.byKey(ValueKey(key)));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(360));
        expect(rect.height, greaterThanOrEqualTo(44));
      }
      expect(
        find.textContaining('Enter your crew for today'),
        findsNothing,
        reason: 'the work starts near the top on a phone',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Add workers picks several from a sheet in one go', (
      tester,
    ) async {
      _size(tester, const Size(360, 800));
      await _pump(tester, _FakeRpc(day()), dayAt);
      await tester.tap(
        find.byKey(const ValueKey('attendance-add-worker-open')),
      );
      await tester.pumpAndSettle();
      // Crew members already on the day are not offered; the labour pool
      // comes first.
      expect(
        find.byKey(const ValueKey('attendance-picker-worker-w1')),
        findsNothing,
      );
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('attendance-picker-worker-w5')),
            )
            .dy,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(const ValueKey('attendance-picker-worker-w4')),
              )
              .dy,
        ),
      );
      // Type and press Enter: the best match is ticked and the box clears
      // for the next name.
      await tester.enterText(
        find.byKey(const ValueKey('attendance-picker-search')),
        'sajid',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('attendance-picker-search')),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        isEmpty,
      );
      await tester.tap(
        find.byKey(const ValueKey('attendance-picker-worker-w4')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add 2'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/attendance_v2_phone_add_workers.png'),
      );
      await tester.tap(find.byKey(const ValueKey('attendance-picker-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('attendance-row-w3')), findsOneWidget);
      expect(find.byKey(const ValueKey('attendance-row-w4')), findsOneWidget);
      expect(find.text('Labour pool'), findsOneWidget);
      expect(find.text('From Workshop crew'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the worker editor keeps Save & next in reach', (tester) async {
      _size(tester, const Size(360, 640));
      await _pump(tester, _FakeRpc(day()), dayAt);
      await tester.tap(find.byKey(const ValueKey('attendance-pill-more-w1')));
      await tester.pumpAndSettle();
      final actions = tester.getRect(
        find.byKey(const ValueKey('attendance-editor-actions')),
      );
      expect(actions.bottom, closeTo(640, 1), reason: 'pinned to the bottom');
      // Entering a time box selects its time, so typing replaces it.
      await tester.tap(find.byKey(const ValueKey('attendance-editor-in')));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('attendance-editor-in')),
          matching: find.byType(TextField),
        ),
      );
      expect(field.controller!.selection.start, 0);
      expect(field.controller!.selection.end, field.controller!.text.length);
      expect(field.keyboardType.decimal, isTrue);
      expect(field.textInputAction, TextInputAction.next);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/attendance_v2_phone_editor.png'),
      );
      expect(tester.takeException(), isNull);
    });

    Future<_FakeRpc> pumpCrews(
      WidgetTester tester,
      Size size, {
      List<Map<String, Object?>> members = const [],
    }) async {
      _size(tester, size);
      final rpc = _FakeRpc({
        'v1_wf_list_crews': (_) => {
          ..._crews(_access(confirm: true)),
          'can_create_crew': true,
        },
        'v1_wf_list_public_holidays': (_) => {
          'year': DateTime.now().year,
          'can_manage': false,
          'holidays': <Object>[],
        },
        'v1_wf_get_crew': (_) => {
          ..._crew(access: _access(confirm: true)),
          'members': members,
        },
        'v1_wf_list_workers': (_) => {'workers': workers},
        'v1_wf_save_crew': (params) => {
          ..._crew(access: _access(confirm: true)),
          'record_version': 2,
        },
        'v1_wf_set_crew_members': (params) => _crew(),
      });
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
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
            yorksV1ProjectPortfolioProvider.overrideWith((ref) async => []),
          ],
          child: const MaterialApp(
            home: Scaffold(body: AttendanceCrewsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return rpc;
    }

    testWidgets('a crew gets its workers from the same picker, saved once', (
      tester,
    ) async {
      final rpc = await pumpCrews(
        tester,
        const Size(360, 800),
        members: [_worker('w1', 'Gul Zaman'), _worker('w2', 'Waqar Ahmed')],
      );
      await tester.tap(find.byKey(ValueKey('attendance-crew-row-$_crewId')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/attendance_v2_phone_crew_editor.png'),
      );
      await tester.tap(
        find.byKey(const ValueKey('attendance-crew-add-worker')),
      );
      await tester.pumpAndSettle();
      // Members are not offered again.
      expect(
        find.byKey(const ValueKey('attendance-picker-worker-w2')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('attendance-picker-worker-w3')),
      );
      await tester.tap(
        find.byKey(const ValueKey('attendance-picker-worker-w4')),
      );
      await tester.pumpAndSettle();
      // The picker names the worker's company, not crews (section 51).
      expect(find.text('W-w4 · Helper · Example Manpower LLC'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('attendance-picker-add')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('attendance-text-dialog-confirm')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('attendance-crew-member-w3')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('attendance-crew-member-w4')),
        findsOneWidget,
      );
      expect(find.text('Members · 4'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('attendance-crew-save')));
      await tester.pumpAndSettle();
      final members = rpc.calls
          .where((c) => c.$1 == 'v1_wf_set_crew_members')
          .toList();
      expect(members, hasLength(1));
      expect(members.single.$2['p_add_worker_ids'], ['w3', 'w4']);
      expect(members.single.$2['p_remove_worker_ids'], isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('desktop: the same picker opens as a dialog', (tester) async {
      await pumpCrews(
        tester,
        const Size(1280, 860),
        members: [_worker('w1', 'Gul Zaman'), _worker('w2', 'Waqar Ahmed')],
      );
      await tester.tap(find.byKey(ValueKey('attendance-crew-row-$_crewId')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('attendance-crew-add-worker')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('attendance-picker-search')),
        'noor',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('attendance-picker-worker-w4')),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/attendance_v2_desktop_crew_picker.png'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the crew editor stays usable above the keyboard', (
      tester,
    ) async {
      await pumpCrews(tester, const Size(360, 640));
      await tester.tap(find.byKey(const ValueKey('attendance-new-crew')));
      await tester.pumpAndSettle();
      final shiftIn = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('attendance-crew-in')),
          matching: find.byType(TextField),
        ),
      );
      expect(shiftIn.keyboardType.decimal, isTrue);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.showKeyboard(
        find.byKey(const ValueKey('attendance-crew-name')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'nothing overflows');
      final save = tester.getRect(
        find.byKey(const ValueKey('attendance-crew-save')),
      );
      expect(save.bottom, lessThanOrEqualTo(340), reason: 'above the keyboard');
    });
  });

  group('several places a day (PRODUCT_DECISIONS 46)', () {
    setUpAll(loadAccountsV2GoldenFonts);

    const store = {
      'crew_id': 'store',
      'crew_name': 'MP Store',
      'status': 'P',
      'start_minute': 390,
      'finish_minute': 720,
      'worked_minutes': 330,
      'locked': false,
    };
    List<Map<String, Object?>> rows({Map<String, Object?>? first}) => [
      {
        'worker_id': 'w1',
        'status': null,
        ...?first,
        'worker': _worker('w1', 'Gul Zaman'),
        'elsewhere': [store],
      },
      {
        'worker_id': 'w2',
        'status': null,
        'worker': _worker('w2', 'Waqar Ahmed'),
      },
    ];
    const dayAt =
        '${RoutePaths.yorksV1WorkforceAttendance}?crew=$_crewId&date=$_date';

    testWidgets('a worker at another place need not be marked here', (
      tester,
    ) async {
      _size(tester, const Size(360, 800));
      Map<String, Object?>? saved;
      final rpc = _FakeRpc({
        'v1_wf_list_crews': (_) => _crews(_access()),
        'v1_wf_list_workers': (_) => {'workers': <Object>[]},
        'v1_wf_get_day': (_) => _day(rows: rows()),
        'v1_wf_save_day': (params) {
          saved = params;
          return _day(saved: true, rows: rows());
        },
      });
      await _pump(tester, rpc, dayAt);
      expect(find.text('At MP Store today · 6:30 AM – 12 PM'), findsOneWidget);
      expect(find.text('Not marked'), findsOneWidget, reason: 'only Waqar');
      expect(find.textContaining('1 at another place'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/attendance_v2_phone_places.png'),
      );

      // Everyone present leaves the worker at the store for the keeper.
      await tester.tap(
        find.byKey(const ValueKey('attendance-everyone-present')),
      );
      await tester.pumpAndSettle();
      expect(find.text('At MP Store today · 6:30 AM – 12 PM'), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('attendance-save-day')));
      await tester.pumpAndSettle();
      final sent = saved!['p_rows'] as List;
      expect(sent.map((row) => (row as Map)['worker_id']), ['w2']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('times that overlap another place stop the save', (
      tester,
    ) async {
      _size(tester, const Size(360, 800));
      final rpc = _FakeRpc({
        'v1_wf_list_crews': (_) => _crews(_access()),
        'v1_wf_list_workers': (_) => {'workers': <Object>[]},
        'v1_wf_get_day': (_) => _day(rows: rows()),
      });
      await _pump(tester, rpc, dayAt);
      await tester.tap(find.byKey(const ValueKey('attendance-pill-p-w1')));
      await tester.tap(find.byKey(const ValueKey('attendance-pill-a-w2')));
      await tester.pumpAndSettle();
      expect(find.text('Overlaps MP Store · 6:30 AM – 12 PM'), findsOneWidget);
      expect(find.textContaining('1 clash with another place'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('attendance-save-day')));
      await tester.pumpAndSettle();
      expect(rpc.calls.where((c) => c.$1 == 'v1_wf_save_day'), isEmpty);

      // The editor shows the other place and the clash.
      await tester.tap(find.byKey(const ValueKey('attendance-pill-more-w1')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('attendance-editor-elsewhere')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('attendance-editor-conflict')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('overtime counts the hours already worked elsewhere', (
      tester,
    ) async {
      _size(tester, const Size(360, 800));
      final rpc = _FakeRpc({
        'v1_wf_list_crews': (_) => _crews(_access()),
        'v1_wf_list_workers': (_) => {'workers': <Object>[]},
        'v1_wf_get_day': (_) => _day(
          rows: rows(
            first: {'status': 'P', 'start_minute': 780, 'finish_minute': 1140},
          ),
        ),
      });
      await _pump(tester, rpc, dayAt);
      // 5.5 h at the store, then 6 h here: 2.5 h normal and 3.5 h overtime.
      expect(find.text('OT 3.5 h'), findsWidgets);
      expect(find.text('Also at MP Store · 6:30 AM – 12 PM'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the desktop grid names the other place', (tester) async {
      _size(tester, const Size(1280, 860));
      final rpc = _FakeRpc({
        'v1_wf_list_crews': (_) => _crews(_access()),
        'v1_wf_list_workers': (_) => {'workers': <Object>[]},
        'v1_wf_get_day': (_) => _day(rows: rows()),
      });
      await _pump(tester, rpc, dayAt);
      expect(
        find.byKey(const ValueKey('attendance-grid-place-w1')),
        findsOneWidget,
      );
      expect(find.text('At MP Store today · 6:30 AM – 12 PM'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
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
    testWidgets('phone overview with a month waiting', (tester) async {
      await shot(
        tester,
        const Size(360, 800),
        {
          'v1_wf_get_overview': (_) => overview(),
          'v1_wf_get_confirmations_due': (_) => {
            'due': [
              {
                'crew_id': _crewId,
                'crew_name': 'Sweihan site crew',
                'month': '2026-10-01',
                'last_day': '2026-10-31',
                'overdue': true,
                'missing_days': 0,
              },
              {
                'crew_id': 'c2',
                'crew_name': 'Nexus DF3W crew',
                'month': '2026-10-01',
                'last_day': '2026-10-31',
                'overdue': true,
                'missing_days': 1,
              },
            ],
          },
        },
        RoutePaths.yorksV1Workforce,
        'phone_overview_due',
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

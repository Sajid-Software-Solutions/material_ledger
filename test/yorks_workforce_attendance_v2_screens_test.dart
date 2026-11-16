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
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/accounts/presentation/v2/kit/accounts_v2_kit.dart';
import 'package:material_ledger/features/workforce/application/attendance_providers.dart';
import 'package:material_ledger/features/workforce/data/attendance_repository.dart';
import 'package:material_ledger/features/workforce/data/workforce_repository.dart';
import 'package:material_ledger/features/workforce/presentation/attendance/attendance_confirm_screen.dart';
import 'package:material_ledger/features/workforce/presentation/attendance/attendance_crews_screen.dart';
import 'package:material_ledger/features/workforce/presentation/attendance/attendance_overview_screen.dart';
import 'package:material_ledger/features/workforce/presentation/attendance/attendance_sheets_screen.dart';
import 'package:material_ledger/features/workforce/presentation/attendance/attendance_take_screen.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
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
  YorksV1Role? role,
  ThemeData? theme,
  AppLanguage? language,
}) async {
  SharedPreferences.setMockInitialValues({
    if (language != null) 'selected_language': language.code,
  });
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
        if (role != null) yorksV1CurrentRoleProvider.overrideWithValue(role),
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
      child: MaterialApp.router(
        theme: theme,
        routerConfig: router,
        // Arabic and Urdu read right to left, as the app's locale makes them.
        builder: language == null
            ? null
            : (context, child) => Directionality(
                textDirection: language.isRtl
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                child: child!,
              ),
      ),
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
      // Entering a time box selects its time, so typing replaces it. Tap
      // the text, not the clock at the box's end.
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('attendance-editor-in')),
          matching: find.byType(TextField),
        ),
      );
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

    // The clock in each time box (PRODUCT_DECISIONS sections 62 and 63).
    Future<void> openEditor(
      WidgetTester tester,
      Size size, {
      ThemeData? theme,
      AppLanguage? language,
    }) async {
      _size(tester, size);
      await _pump(
        tester,
        _FakeRpc(day()),
        dayAt,
        theme: theme,
        language: language,
      );
      final more = find.byKey(const ValueKey('attendance-pill-more-w1'));
      // Phones open a worker from the pills, desktop from the row's pencil.
      await tester.tap(
        more.evaluate().isNotEmpty ? more : find.byTooltip('Edit Gul Zaman'),
      );
      await tester.pumpAndSettle();
    }

    TextInputAction? nextKey(WidgetTester tester, String key) => tester
        .widget<TextField>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(TextField),
          ),
        )
        .textInputAction;

    String boxText(WidgetTester tester, String key) => tester
        .widget<TextField>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(TextField),
          ),
        )
        .controller!
        .text;

    /// Text in the editor itself, not the day behind it.
    Finder inEditor(Finder finder) => find.descendant(
      of: find.byKey(const ValueKey('attendance-editor-scroll')),
      matching: finder,
    );

    /// The text box being typed in, if any: the keyboard is up for it.
    EditableText? typingIn() => FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<EditableText>();

    testWidgets('a time is set on the clock: the dial, in 12-hour time', (
      tester,
    ) async {
      // A phone set to 24-hour time still gets AM and PM, as the app writes.
      tester.platformDispatcher.alwaysUse24HourFormatTestValue = true;
      addTearDown(tester.platformDispatcher.clearAlwaysUse24HourTestValue);
      await openEditor(tester, const Size(360, 800));
      expect(boxText(tester, 'attendance-editor-out'), '5p');

      // The clock is inside the Out box, a 44px target.
      final clock = find.byKey(const ValueKey('attendance-editor-out-clock'));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('attendance-editor-out')),
          matching: clock,
        ),
        findsOneWidget,
      );
      expect(tester.getSize(clock), const Size(44, 44));
      expect(find.byTooltip('Choose Out on the clock'), findsOneWidget);

      // Typing in In, then the Out clock.
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('attendance-editor-in')),
          matching: find.byType(TextField),
        ),
      );
      await tester.pumpAndSettle();
      expect(typingIn(), isNotNull);
      await tester.tap(clock);
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      expect(find.text('Out · Gul Zaman'), findsOneWidget);
      expect(find.text('PM'), findsOneWidget);
      expect(find.text('AM'), findsOneWidget);

      // The dial's own switch to typing the hour and minute.
      await tester.tap(find.byTooltip('Switch to text input mode'));
      await tester.pumpAndSettle();
      final boxes = find.descendant(
        of: find.byType(TimePickerDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(boxes.at(0), '5');
      await tester.enterText(boxes.at(1), '45');
      await tester.tap(find.text('PM'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.byType(TimePickerDialog), findsNothing);
      expect(boxText(tester, 'attendance-editor-out'), '5:45p');
      // The keyboard does not come back after the dial: In was left.
      expect(typingIn(), isNull);
      // 6:30 AM to 5:45 PM less a 30 minute break: 10.75 hours.
      expect(inEditor(find.text('10.8')), findsOneWidget);
      expect(inEditor(find.text('2.8')), findsOneWidget);

      // Typing still works beside the clock, and the Out-at chips too.
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('attendance-editor-out')),
          matching: find.byType(TextField),
        ),
        '6',
      );
      await tester.pumpAndSettle();
      // "6" after a 6:30 AM start is 6 PM: 11 hours less the break.
      expect(inEditor(find.text('11')), findsOneWidget);
      expect(inEditor(find.text('3')), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('attendance-editor-out-at-1140')),
      );
      await tester.pumpAndSettle();
      expect(boxText(tester, 'attendance-editor-out'), '7p');
      expect(tester.takeException(), isNull);
    });

    testWidgets('closing the clock keeps the time; a typo is fixed on it', (
      tester,
    ) async {
      await openEditor(tester, const Size(360, 800));
      await tester.tap(
        find.byKey(const ValueKey('attendance-editor-in-clock')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(boxText(tester, 'attendance-editor-in'), '6:30a');

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('attendance-editor-in')),
          matching: find.byType(TextField),
        ),
        '99',
      );
      await tester.pumpAndSettle();
      // While typing ("63" on the way to "630") the box only turns red;
      // once it is left, its label says why and Done waits.
      expect(find.text('In · Not a time'), findsNothing);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(find.text('In · Not a time'), findsOneWidget);
      expect(
        tester
            .widget<AccountsV2Button>(
              find.byKey(const ValueKey('attendance-editor-done')),
            )
            .onPressed,
        isNull,
      );
      // The clock opens at the place's usual start and puts it right.
      await tester.tap(
        find.byKey(const ValueKey('attendance-editor-in-clock')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(boxText(tester, 'attendance-editor-in'), '6:30a');
      expect(find.text('In · Not a time'), findsNothing);
      expect(find.text('In'), findsOneWidget);
    });

    testWidgets('reduced motion: the clock opens without its animation', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await openEditor(tester, const Size(360, 800));
      await tester.tap(
        find.byKey(const ValueKey('attendance-editor-out-clock')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      final route = ModalRoute.of(
        tester.element(find.byType(TimePickerDialog)),
      )!;
      expect(route.animation!.value, 1, reason: 'no fade or zoom to wait for');
      await tester.pumpAndSettle();
      // The Save bar under the day appears without a zero-length size
      // animation re-laying itself out.
      expect(find.byKey(const ValueKey('attendance-save-bar')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every time box of the desktop editor has its clock', (
      tester,
    ) async {
      await openEditor(tester, const Size(1280, 860));
      for (final box in ['in', 'break', 'back', 'out']) {
        expect(
          find.byKey(ValueKey('attendance-editor-$box-clock')),
          findsOneWidget,
          reason: box,
        );
      }
      await tester.tap(
        find.byKey(const ValueKey('attendance-editor-break-clock')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      expect(find.text('Break · Gul Zaman'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(boxText(tester, 'attendance-editor-break'), '12:30p');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the usual shift is set on the clock too', (tester) async {
      _size(tester, const Size(360, 800));
      await _pump(tester, _FakeRpc(day()), dayAt);
      await tester.tap(find.textContaining('6:30 AM – 5 PM').first);
      await tester.pumpAndSettle();
      // The same clock inside each box as the worker's editor.
      final clock = find.byKey(const ValueKey('attendance-shift-out-clock'));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('attendance-shift-out')),
          matching: clock,
        ),
        findsOneWidget,
      );
      expect(tester.getSize(clock), const Size(44, 44));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/attendance_shift_phone.png'),
      );
      await tester.tap(clock);
      await tester.pumpAndSettle();
      expect(find.text('Usual shift at this place · Out'), findsOneWidget);
      await tester.tap(find.byTooltip('Switch to text input mode'));
      await tester.pumpAndSettle();
      final boxes = find.descendant(
        of: find.byType(TimePickerDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(boxes.at(0), '3');
      await tester.enterText(boxes.at(1), '00');
      await tester.tap(find.text('PM'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(boxText(tester, 'attendance-shift-out'), '3p');
      expect(tester.takeException(), isNull);
    });

    // The editor on a phone (PRODUCT_DECISIONS section 63).
    testWidgets('a phone editor: one row of statuses, the clock in each box', (
      tester,
    ) async {
      await openEditor(tester, const Size(360, 800));
      // Present, Absent and Leave sit on one row.
      final tops = {
        for (final key in ['P', 'A', 'leave'])
          tester
              .getRect(find.byKey(ValueKey('attendance-editor-status-$key')))
              .top,
      };
      expect(tops, hasLength(1));
      // In and Out side by side, the break under them; each box has its
      // clock at its end, as tall as the box, and the time shows once.
      final inBox = tester.getRect(
        find.byKey(const ValueKey('attendance-editor-in')),
      );
      final outBox = tester.getRect(
        find.byKey(const ValueKey('attendance-editor-out')),
      );
      final breakBox = tester.getRect(
        find.byKey(const ValueKey('attendance-editor-break')),
      );
      expect(inBox.top, outBox.top);
      expect(breakBox.top, greaterThan(inBox.bottom));
      expect(inBox.width, greaterThan(140), reason: 'two boxes a row at 360');
      for (final box in ['in', 'out', 'break', 'back']) {
        final field = tester.getRect(
          find.byKey(ValueKey('attendance-editor-$box')),
        );
        final clock = tester.getRect(
          find.byKey(ValueKey('attendance-editor-$box-clock')),
        );
        expect(clock.size, const Size(44, 44), reason: box);
        expect(clock.right, closeTo(field.right, 1.5), reason: box);
        expect(clock.top, greaterThanOrEqualTo(field.top), reason: box);
        expect(clock.bottom, lessThanOrEqualTo(field.bottom), reason: box);
      }
      for (final caption in ['6:30 AM', '12:30 PM', '1 PM', 'Not a time']) {
        expect(find.text(caption), findsNothing, reason: caption);
      }
      // Next goes In, Out, Break and Back; Back shows Done.
      expect(nextKey(tester, 'attendance-editor-in'), TextInputAction.next);
      expect(nextKey(tester, 'attendance-editor-out'), TextInputAction.next);
      expect(nextKey(tester, 'attendance-editor-break'), TextInputAction.next);
      expect(nextKey(tester, 'attendance-editor-back'), TextInputAction.done);
      // Everything to the Done bar fits a 360 x 800 phone.
      final note = tester.getRect(
        find.byKey(const ValueKey('attendance-editor-note')),
      );
      final actions = tester.getRect(
        find.byKey(const ValueKey('attendance-editor-actions')),
      );
      expect(note.bottom, lessThanOrEqualTo(actions.top));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Next on the keyboard goes box to box, past the clocks', (
      tester,
    ) async {
      await openEditor(tester, const Size(360, 800));
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('attendance-editor-in')),
          matching: find.byType(TextField),
        ),
      );
      await tester.pumpAndSettle();
      for (final box in ['out', 'break', 'back']) {
        await tester.testTextInput.receiveAction(TextInputAction.next);
        await tester.pumpAndSettle();
        final typing = typingIn();
        expect(typing, isNotNull, reason: 'the keyboard stays up for $box');
        expect(
          find.descendant(
            of: find.byKey(ValueKey('attendance-editor-$box')),
            matching: find.byWidget(typing!),
          ),
          findsOneWidget,
          reason: box,
        );
      }
    });

    testWidgets('the break has one way in: No break, then Add break', (
      tester,
    ) async {
      await openEditor(tester, const Size(360, 800));
      final toggle = find.byKey(
        const ValueKey('attendance-editor-toggle-break'),
      );
      expect(tester.getSize(toggle).height, greaterThanOrEqualTo(44));
      expect(
        find.descendant(of: toggle, matching: find.text('No break')),
        findsOneWidget,
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('attendance-editor-break')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('attendance-editor-back')),
        findsNothing,
      );
      // 6:30 AM to 5 PM without the break; Out is now the last box.
      expect(inEditor(find.text('10.5')), findsOneWidget);
      expect(nextKey(tester, 'attendance-editor-out'), TextInputAction.done);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/attendance_editor_phone_no_break.png'),
      );

      // Add break brings back the place's usual break.
      expect(
        find.descendant(of: toggle, matching: find.text('Add break')),
        findsOneWidget,
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(boxText(tester, 'attendance-editor-break'), '12:30p');
      expect(boxText(tester, 'attendance-editor-back'), '1p');
      expect(inEditor(find.text('10')), findsOneWidget);
      expect(nextKey(tester, 'attendance-editor-out'), TextInputAction.next);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the four kinds of leave share one chip and its list', (
      tester,
    ) async {
      // The app's own theme, as production draws the list.
      await openEditor(tester, const Size(360, 800), theme: AppTheme.light);
      final leave = find.byKey(
        const ValueKey('attendance-editor-status-leave'),
      );
      expect(tester.getSize(leave).height, greaterThanOrEqualTo(44));
      expect(
        find.descendant(of: leave, matching: find.text('Leave')),
        findsOneWidget,
      );
      // Read as one button that opens a list, with no second, dead tap.
      final semantics = tester.ensureSemantics();
      expect(
        tester.getSemantics(leave),
        isSemantics(
          isButton: true,
          hasTapAction: true,
          isSelected: false,
          tooltip: 'Leave',
        ),
      );
      semantics.dispose();
      await tester.tap(leave);
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/attendance_editor_phone_leave.png'),
      );
      for (final kind in [
        'Annual leave',
        'Sick leave',
        'Official leave',
        'Unpaid leave',
      ]) {
        expect(find.text(kind), findsOneWidget, reason: kind);
      }
      expect(
        tester
            .getSize(find.byKey(const ValueKey('attendance-editor-status-SL')))
            .height,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(find.text('Sick leave'));
      await tester.pumpAndSettle();
      // The chip names the kind chosen; a day on leave has no times.
      expect(
        find.descendant(of: leave, matching: find.text('Sick leave')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('attendance-editor-in')), findsNothing);
      expect(find.text('Time'), findsNothing);

      // Done saves it and moves to the next worker.
      await tester.tap(find.byKey(const ValueKey('attendance-editor-done')));
      await tester.pumpAndSettle();
      expect(inEditor(find.text('Waqar Ahmed')), findsOneWidget);
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('attendance-row-w1')),
          matching: find.text('Sick leave'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced motion: the leave list opens at once', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await openEditor(tester, const Size(360, 800));
      await tester.tap(
        find.byKey(const ValueKey('attendance-editor-status-leave')),
      );
      await tester.pump();
      final route = ModalRoute.of(tester.element(find.text('Annual leave')))!;
      expect(route.animation!.value, 1);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('with the keyboard up, the box and Done stay in sight', (
      tester,
    ) async {
      await openEditor(tester, const Size(360, 740));
      // The lowest box, then the keyboard opens over the lower half.
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('attendance-editor-back')),
          matching: find.byType(TextField),
        ),
      );
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final actions = tester.getRect(
        find.byKey(const ValueKey('attendance-editor-actions')),
      );
      expect(actions.bottom, closeTo(740 - 320, 1), reason: 'above the keys');
      final box = tester.getRect(
        find.byKey(const ValueKey('attendance-editor-back')),
      );
      expect(box.top, greaterThanOrEqualTo(0));
      expect(box.bottom, lessThanOrEqualTo(actions.top));
      expect(typingIn(), isNotNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/attendance_editor_phone_keyboard.png'),
      );
      expect(tester.takeException(), isNull);
    });

    for (final language in [AppLanguage.urdu, AppLanguage.arabic]) {
      testWidgets('${language.name}: right to left, the clock at the end', (
        tester,
      ) async {
        await openEditor(tester, const Size(360, 800), language: language);
        final inBox = tester.getRect(
          find.byKey(const ValueKey('attendance-editor-in')),
        );
        final outBox = tester.getRect(
          find.byKey(const ValueKey('attendance-editor-out')),
        );
        expect(inBox.left, greaterThan(outBox.left), reason: 'In on the right');
        for (final box in ['in', 'out', 'break', 'back']) {
          final field = tester.getRect(
            find.byKey(ValueKey('attendance-editor-$box')),
          );
          final clock = tester.getRect(
            find.byKey(ValueKey('attendance-editor-$box-clock')),
          );
          expect(clock.left, closeTo(field.left, 1.5), reason: box);
          expect(clock.size, const Size(44, 44), reason: box);
        }
        // Times read "3 PM", not "PM 3".
        expect(
          tester
              .widget<Text>(
                find.descendant(
                  of: find.byKey(
                    const ValueKey('attendance-editor-out-at-900'),
                  ),
                  matching: find.byType(Text),
                ),
              )
              .textDirection,
          TextDirection.ltr,
        );
        if (language == AppLanguage.urdu) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/attendance_editor_phone_urdu.png'),
          );
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Hindi fits the same phone editor', (tester) async {
      await openEditor(
        tester,
        const Size(360, 800),
        language: AppLanguage.hindi,
      );
      expect(
        find.byKey(const ValueKey('attendance-editor-in-clock')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    // Screenshots in the app's own theme, as production shows the dial.
    for (final (name, size) in [
      ('phone', const Size(360, 800)),
      ('desktop', const Size(1280, 860)),
    ]) {
      testWidgets('$name editor and its clock, screenshots', (tester) async {
        await openEditor(tester, size, theme: AppTheme.light);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/attendance_clock_${name}_editor.png'),
        );
        await tester.tap(
          find.byKey(const ValueKey('attendance-editor-out-clock')),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/attendance_clock_${name}_dial.png'),
        );
      });
    }

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

  // One name for a place and a month that reads right for each role
  // (PRODUCT_DECISIONS section 59).
  group('places read the same on every screen', () {
    Map<String, Object?> place({Map<String, Object?>? access}) => {
      ..._crew(access: access),
      'name': 'YRA-321 Sweihan',
      'place_key': 'project:p1',
      'place_kind': 'project',
    };
    Map<String, dynamic> overview(Map<String, Object?> crew) => {
      'today': _today,
      'month': '2026-11-01',
      'crews': [
        {...crew, 'month': _month(missing: [])},
      ],
      'feed': [
        {
          'kind': 'entered',
          'crew_id': _crewId,
          // The server sends the sheet's stored name.
          'crew_name': 'YRA-321 Sweihan',
          'date': '2026-11-11',
          'by': 'Imran Qureshi',
          'at': '2026-11-11T15:05:00Z',
          'summary': {'present': 9, 'absent': 1, 'leave': 0},
        },
      ],
    };
    Map<String, dynamic> sheet(Map<String, Object?> crew) => {
      'crew': crew,
      'month': _month(missing: []),
      'workers': [
        {
          ..._worker('w1', 'Gul Zaman'),
          'days': [
            {
              'date': '2026-11-02',
              'status': 'P',
              'start_minute': 390,
              'finish_minute': 870,
              'work_scope_name': 'Tower A',
            },
          ],
        },
      ],
      'sheets': [
        {'date': '2026-11-02', 'entered_by': 'Imran Qureshi', 'changed': false},
      ],
      'holidays': <Object>[],
      'can_export': false,
    };

    testWidgets('the overview names a place once', (tester) async {
      _size(tester, const Size(1280, 900));
      await _pump(
        tester,
        _FakeRpc({'v1_wf_get_overview': (_) => overview(place())}),
        RoutePaths.yorksV1Workforce,
      );
      expect(find.text('YRA-321 · Sweihan'), findsOneWidget);
      // The work label repeated the name the other way round.
      expect(find.text('Sweihan · YRA-321'), findsNothing);
      // The activity feed names it the same way.
      expect(find.textContaining('entered YRA-321 · Sweihan'), findsOneWidget);
    });

    testWidgets('HR/PRO watches the month: told who confirms, and when', (
      tester,
    ) async {
      _size(tester, const Size(1280, 900));
      final watcher = place(access: _access(officer: true));
      await _pump(
        tester,
        _FakeRpc({
          'v1_wf_get_overview': (_) => overview(watcher),
          'v1_wf_get_month_sheet': (_) => sheet(watcher),
        }),
        RoutePaths.yorksV1WorkforceConfirm,
        role: YorksV1Role.pr,
      );
      expect(find.text('YRA-321 · Sweihan · November 2026'), findsOneWidget);
      expect(
        find.textContaining('you can reopen a confirmed month'),
        findsOneWidget,
      );
      expect(
        find.text('Reviewers are reminded from Mon 30 Nov until confirmed'),
        findsOneWidget,
      );
      expect(find.textContaining('You will get a notification'), findsNothing);
      expect(
        find.byKey(const ValueKey('attendance-confirm-month-$_crewId')),
        findsNothing,
      );
      // A place has no missing days, so no "Not entered" count.
      expect(find.text('Days entered'), findsOneWidget);
      expect(find.text('Not entered'), findsNothing);
    });

    testWidgets('a confirmer is told the notification comes', (tester) async {
      _size(tester, const Size(1280, 900));
      final confirmer = place(access: _access(confirm: true));
      await _pump(
        tester,
        _FakeRpc({
          'v1_wf_get_overview': (_) => overview(confirmer),
          'v1_wf_get_month_sheet': (_) => sheet(confirmer),
        }),
        RoutePaths.yorksV1WorkforceConfirm,
        role: YorksV1Role.projectEngineer,
      );
      expect(
        find.text('Opens on Mon 30 Nov. You will get a notification.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('On the last day of the month you get'),
        findsOneWidget,
      );
    });

    testWidgets('a place\'s time sheet leaves empty days blank, as printed', (
      tester,
    ) async {
      _size(tester, const Size(1280, 900));
      final reader = place(access: _access(take: false));
      await _pump(
        tester,
        _FakeRpc({
          'v1_wf_list_crews': (_) => {
            'crews': [reader],
            'can_create_crew': false,
          },
          'v1_wf_get_month_sheet': (_) => sheet(reader),
        }),
        RoutePaths.yorksV1WorkforceSheets,
      );
      expect(find.text('YRA-321 · Sweihan'), findsWidgets);
      expect(find.text('Workers — 1 at YRA-321 · Sweihan'), findsOneWidget);
      expect(find.text('YRA-321 · Sweihan · Tower A'), findsOneWidget);
      expect(find.text('Not entered'), findsNothing);
    });
  });

  group('screenshots (desktop and 360px phone)', () {
    setUpAll(loadAccountsV2GoldenFonts);

    Map<String, dynamic> overview() => {
      'today': _today,
      'month': '2026-11-01',
      'crews': [
        {
          ..._crew(),
          'month': _month(),
          // Today on the overview (PRODUCT_DECISIONS 58).
          'today': {
            'entered': true,
            'entered_by': 'Imran Qureshi',
            'last_saved_by': 'Imran Qureshi',
            'last_saved_at': '2026-11-11T03:42:00Z',
            'present': 9,
            'absent': 1,
            'leave': 0,
            'rest': 0,
          },
        },
        {
          ..._crew(),
          'id': 'c2',
          'name': 'Workshop crew',
          'kind': 'workshop',
          'work_label': 'Workshop · Mussafah',
          'needs_confirmation': false,
          'member_count': 6,
          'month': _month(state: 'not_needed', missing: []),
          'today': {'entered': false, 'present': 0, 'absent': 0, 'leave': 0},
        },
      ],
      'today_summary': {
        'places': 2,
        'places_entered': 1,
        'present': 9,
        'absent': 1,
        'leave': 0,
      },
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
      String name, {
      YorksV1Role? role,
      YorksV1FeatureFlags? featureFlags,
    }) async {
      _size(tester, size);
      await _pump(
        tester,
        _FakeRpc(handlers),
        location,
        role: role,
        featureFlags: featureFlags,
      );
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

    // A Project Engineer's My sites (PRODUCT_DECISIONS 58).
    for (final (name, size) in [
      ('phone', const Size(360, 800)),
      ('desktop', const Size(1280, 900)),
    ]) {
      testWidgets('$name my sites', (tester) async {
        await shot(
          tester,
          size,
          {'v1_wf_get_overview': (_) => overview()},
          RoutePaths.yorksV1Workforce,
          '${name}_my_sites',
          role: YorksV1Role.projectEngineer,
        );
        expect(find.text('My sites'), findsOneWidget);
        expect(find.text('Sites'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('attendance-needs-look')),
          findsNothing,
        );
      });

      // As production runs, with the Workforce Center on: the office's My
      // work with today's figures and what needs a look.
      testWidgets('$name office, Center on', (tester) async {
        await shot(
          tester,
          size,
          {
            'v1_wf_get_overview': (_) => overview(),
            'v1_wf_list_requests': (_) => {
              'today': _date,
              'can_request': true,
              'requests': <Object>[],
            },
          },
          RoutePaths.yorksV1Workforce,
          '${name}_center_office',
          featureFlags: const YorksV1FeatureFlags(
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
            workforceCenter: true,
          ),
        );
        expect(find.text('Workforce Center'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('attendance-kpi-working-today')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('attendance-needs-look')),
          findsOneWidget,
        );
      });
    }
  });
}

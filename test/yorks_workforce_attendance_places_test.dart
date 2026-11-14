// Workforce attendance at places (PRODUCT_DECISIONS section 51): choose a
// place (or go straight to the only one), add workers who start present at
// 06:30 with no overtime and the place's building, save an emptied day, ask
// for a reason only for someone else's rows, and keep the page in place
// while another date loads.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/app/router.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';
import 'package:material_ledger/app/yorks_v1_workspace_shell.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/workforce/application/attendance_providers.dart';
import 'package:material_ledger/features/workforce/data/attendance_repository.dart';
import 'package:material_ledger/features/workforce/data/workforce_repository.dart';
import 'package:material_ledger/features/workforce/presentation/attendance/attendance_take_screen.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/accounts_v2_golden_fonts.dart';

const _placeId = '5b000000-0000-4000-8000-000000000001';
const _otherPlaceId = '5b000000-0000-4000-8000-000000000002';
const _today = '2026-11-12';
const _date = '2026-11-10'; // a Tuesday
const _nextDate = '2026-11-11';

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

const _buildings = [
  {'id': 'b0', 'name': 'Common / All Buildings', 'kind': 'common'},
  {'id': 'b1', 'name': 'Tower A', 'kind': 'building'},
  {'id': 'b2', 'name': 'Tower B', 'kind': 'building'},
];

Map<String, Object?> _place({
  String id = _placeId,
  List<Map<String, Object?>> buildings = _buildings,
}) => {
  'id': id,
  'name': 'YRA-322 DF3W',
  'code': 'PLACE-1',
  'kind': 'project',
  'project_id': 'p1',
  'project_ref': 'YRA-322',
  'project_name': 'DF3W',
  'work_label': 'DF3W · YRA-322',
  'needs_confirmation': true,
  'shift_start_minute': 390,
  'shift_finish_minute': 870,
  'break_start_minute': null,
  'break_finish_minute': null,
  'is_active': true,
  'record_version': 2,
  'member_count': 0,
  'place_key': 'project:p1',
  'place_kind': 'project',
  'buildings': buildings,
  'access': {
    'view': true,
    'take': true,
    'confirm': false,
    'manage': false,
    'officer': false,
  },
};

/// The workshop: an internal place with no project or buildings.
Map<String, Object?> _workshopPlace() => {
  ..._place(id: _otherPlaceId, buildings: const []),
  'name': 'Workshop',
  'kind': 'workshop',
  'project_id': null,
  'project_ref': null,
  'project_name': null,
  'work_label': null,
  'place_key': 'location:workshop',
  'place_kind': 'location',
  'needs_confirmation': false,
};

Map<String, Object?> _worker(String id, String name) => {
  'id': id,
  'number': 'W-$id',
  'name': name,
  'designation': 'Helper',
  'company': 'Example Manpower LLC',
  'crews': <Object>[],
};

Map<String, Object?> _month() => {
  'month': '2026-11-01',
  'last_day': '2026-11-30',
  'state': 'recording',
  'days': [
    for (var d = 1; d <= 30; d++)
      {
        'date': '2026-11-${d.toString().padLeft(2, '0')}',
        'state': d > 12
            ? 'future'
            : DateTime(2026, 11, d).weekday == DateTime.sunday
            ? 'off'
            : d == 10
            ? 'entered'
            : 'none',
        'day_type': DateTime(2026, 11, d).weekday == DateTime.sunday
            ? 'holiday'
            : 'work',
      },
  ],
  // A place has no members: no day is "missing".
  'missing_days': <String>[],
  'work_days_so_far': 10,
  'days_entered': 1,
  'regular_minutes': 960,
  'normal_overtime_minutes': 0,
  'holiday_overtime_minutes': 0,
  'can_confirm': false,
  'record_version': 0,
};

Map<String, Object?> _day({
  String date = _date,
  bool saved = false,
  List<Map<String, Object?>> rows = const [],
  Map<String, Object?>? place,
}) => {
  'schema_version': 'yorks.workforce.day.v2',
  'crew': place ?? _place(),
  'date': date,
  'today': _today,
  'day_type': 'work',
  'saved': saved,
  'record_version': saved ? 3 : 0,
  'entered_by': saved ? 'Imran Qureshi' : null,
  'entered_by_me': false,
  'entered_at': saved ? '2026-11-10T14:00:00Z' : null,
  'locked': false,
  'is_future': false,
  'previous_same_type_date': '2026-11-09',
  'rows': rows,
  'question': null,
  'changes': <Object>[],
  'access': (place ?? _place())['access'],
  'month': _month(),
};

Map<String, Object?> _row(
  String id,
  String name, {
  String status = 'P',
  int? start = 390,
  int? finish = 870,
  String? scope = 'b1',
  bool mine = true,
}) => {
  'worker_id': id,
  'status': status,
  'start_minute': status == 'P' ? start : null,
  'finish_minute': status == 'P' ? finish : null,
  'work_project_id': 'p1',
  'work_scope_id': scope,
  'work_scope_name': scope == 'b1' ? 'Tower A' : null,
  'worker': _worker(id, name),
  'is_member': false,
  'updated_by': mine ? 'Me' : 'Imran Qureshi',
  'updated_by_me': mine,
  'worked_minutes': 480,
  'regular_minutes': 480,
};

Map<String, Object?> _places({
  bool withCrew = true,
  bool second = true,
  bool addLocation = true,
}) => {
  'can_take': true,
  'can_add_location': addLocation,
  'projects': [
    {
      'id': 'p1',
      'ref': 'YRA-322',
      'name': 'DF3W',
      'buildings': _buildings,
      'crew_id': withCrew ? _placeId : null,
      'can_take': true,
      'is_member': true,
    },
    if (second)
      {
        'id': 'p2',
        'ref': 'YRA-330',
        'name': 'Sweihan Villas',
        'buildings': <Object>[],
        'crew_id': null,
        'can_take': true,
        'is_member': false,
      },
  ],
  'locations': [
    if (second)
      {'crew_id': _otherPlaceId, 'name': 'Workshop', 'can_take': true},
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
    final handler =
        handlers[functionName] ??
        switch (functionName) {
          'v1_wf_get_confirmations_due' => (_) => {'due': <Object>[]},
          'v1_wf_list_workers' => (_) => {
            'workers': [
              _worker('w1', 'Gul Zaman'),
              _worker('w2', 'Waqar Ahmed'),
              _worker('w3', 'Ravi Kumar'),
            ],
          },
          _ => null,
        };
    if (handler == null) throw StateError('unexpected $functionName');
    return handler(parameters);
  }

  int count(String name) => calls.where((c) => c.$1 == name).length;
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

Future<GoRouter> _pump(
  WidgetTester tester,
  _FakeRpc rpc,
  String location, {
  Map<String, Object> preferences = const {},
  YorksV1Role? role,
  bool shell = false,
}) async {
  SharedPreferences.setMockInitialValues(preferences);
  final prefs = await SharedPreferences.getInstance();
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: RoutePaths.yorksV1WorkforceAttendance,
        builder: (_, state) {
          final screen = AttendanceTakeScreen(
            initialCrewId: state.uri.queryParameters['crew'],
            initialDate: state.uri.queryParameters['date'],
          );
          // With the workspace shell: the sidebar and the role's tabs.
          return shell
              ? YorksV1WorkspaceShell(child: screen)
              : Scaffold(body: screen);
        },
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        yorksV1AuthUserIdProvider.overrideWithValue('actor-1'),
        yorksV1CurrentRoleProvider.overrideWithValue(role),
        if (shell) yorksV1FeatureFlagsProvider.overrideWithValue(_flags),
        yorksAttendanceRepositoryProvider.overrideWithValue(
          YorksAttendanceRepository(
            featureFlags: _flags,
            connectivity: const _Online(),
            rpcClient: rpc,
          ),
        ),
      ],
      // The shell's tabs take their type from the app theme.
      child: MaterialApp.router(
        theme: shell ? AppTheme.light : null,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// Decodes every image on screen (the shell's logo) before a screenshot, so
/// the picture never depends on how fast an asset loaded.
Future<void> _loadImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAccountsV2GoldenFonts);

  testWidgets('the only project opens straight away', (tester) async {
    _size(tester, const Size(360, 800));
    final rpc = _FakeRpc({
      'v1_wf_list_places': (_) => _places(withCrew: false, second: false),
      'v1_wf_open_place': (_) => _place(),
      'v1_wf_get_day': (_) => _day(),
    });
    await _pump(tester, rpc, RoutePaths.yorksV1WorkforceAttendance);

    expect(rpc.count('v1_wf_open_place'), 1);
    expect(rpc.calls.firstWhere((c) => c.$1 == 'v1_wf_open_place').$2, {
      'p_project_id': 'p1',
      'p_location': null,
    });
    expect(find.text('YRA-322 · DF3W'), findsOneWidget);
    // Nobody recorded yet: one clear next step.
    expect(find.byKey(const ValueKey('attendance-empty-add')), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getStringList('yorks.attendance.places.v1.actor-1'), [
      _placeId,
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('choosing a place: own projects first, search, open once', (
    tester,
  ) async {
    _size(tester, const Size(360, 800));
    final rpc = _FakeRpc({
      'v1_wf_list_places': (_) => _places(withCrew: false),
      'v1_wf_open_place': (params) =>
          _place(id: params['p_project_id'] == 'p2' ? 'x2' : _placeId),
      'v1_wf_get_day': (_) => _day(),
    });
    await _pump(tester, rpc, RoutePaths.yorksV1WorkforceAttendance);

    expect(find.text('Where are you taking attendance?'), findsOneWidget);
    expect(find.text('YOUR PROJECTS'), findsOneWidget);
    expect(find.text('OTHER PROJECTS'), findsOneWidget);
    expect(find.text('WORKSHOP AND OTHER PLACES'), findsOneWidget);
    expect(rpc.count('v1_wf_open_place'), 0);

    await tester.enterText(
      find.byKey(const ValueKey('attendance-place-search')),
      'swehan',
    );
    await tester.pumpAndSettle();
    expect(find.text('YRA-330 · Sweihan Villas'), findsOneWidget);
    expect(find.text('YRA-322 · DF3W'), findsNothing);

    await _tap(tester, find.text('YRA-330 · Sweihan Villas'));
    expect(rpc.count('v1_wf_open_place'), 1);
    expect(
      rpc.calls.lastWhere((c) => c.$1 == 'v1_wf_get_day').$2['p_team_id'],
      'x2',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new place is added by name', (tester) async {
    _size(tester, const Size(360, 800));
    final rpc = _FakeRpc({
      'v1_wf_list_places': (_) => _places(),
      'v1_wf_open_place': (_) => _place(id: 'store'),
      'v1_wf_get_day': (_) => _day(),
    });
    await _pump(tester, rpc, RoutePaths.yorksV1WorkforceAttendance);
    await tester.enterText(
      find.byKey(const ValueKey('attendance-place-search')),
      'Main Store',
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('attendance-place-add')));
    expect(rpc.calls.firstWhere((c) => c.$1 == 'v1_wf_open_place').$2, {
      'p_project_id': null,
      'p_location': 'Main Store',
    });
  });

  testWidgets('only internal-place keepers are offered a new place', (
    tester,
  ) async {
    // Site and Project Engineers keep projects only (PRODUCT_DECISIONS 58).
    _size(tester, const Size(360, 800));
    final rpc = _FakeRpc({
      'v1_wf_list_places': (_) => _places(withCrew: false, addLocation: false),
      'v1_wf_open_place': (_) => _place(),
      'v1_wf_get_day': (_) => _day(),
    });
    await _pump(tester, rpc, RoutePaths.yorksV1WorkforceAttendance);
    await tester.enterText(
      find.byKey(const ValueKey('attendance-place-search')),
      'Main Store',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('attendance-place-add')), findsNothing);
    expect(
      find.text(
        'Not a project? Type a name such as Workshop, Store or Camp to add it.',
      ),
      findsNothing,
    );
    expect(find.text('No project or place matches.'), findsOneWidget);
    expect(rpc.count('v1_wf_open_place'), 0);
  });

  testWidgets('the Workshop In-Charge opens on the workshop by default', (
    tester,
  ) async {
    // PRODUCT_DECISIONS 58: workshop work by default; a project when chosen.
    _size(tester, const Size(360, 800));
    final rpc = _FakeRpc({
      'v1_wf_list_places': (_) => _places(),
      'v1_wf_get_day': (params) => _day(
        place: params['p_team_id'] == _otherPlaceId ? _workshopPlace() : null,
      ),
    });
    final router = await _pump(
      tester,
      rpc,
      RoutePaths.yorksV1WorkforceAttendance,
      // The project was used last on this device.
      preferences: {
        'yorks.attendance.places.v1.actor-1': [_placeId],
      },
      role: YorksV1Role.workshopInCharge,
    );
    expect(
      rpc.calls.firstWhere((c) => c.$1 == 'v1_wf_get_day').$2['p_team_id'],
      _otherPlaceId,
    );

    // He chooses a project; the Workshop tab starts over at the workshop.
    router.go('${RoutePaths.yorksV1WorkforceAttendance}?crew=$_placeId');
    await tester.pumpAndSettle();
    expect(
      rpc.calls.lastWhere((c) => c.$1 == 'v1_wf_get_day').$2['p_team_id'],
      _placeId,
    );
    router.go(RoutePaths.yorksV1WorkforceAttendance);
    await tester.pumpAndSettle();
    expect(
      rpc.calls.lastWhere((c) => c.$1 == 'v1_wf_get_day').$2['p_team_id'],
      _otherPlaceId,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('other roles keep the place used last', (tester) async {
    _size(tester, const Size(360, 800));
    final rpc = _FakeRpc({
      'v1_wf_list_places': (_) => _places(),
      'v1_wf_get_day': (_) => _day(),
    });
    await _pump(
      tester,
      rpc,
      RoutePaths.yorksV1WorkforceAttendance,
      preferences: {
        'yorks.attendance.places.v1.actor-1': [_placeId],
      },
      role: YorksV1Role.accountant,
    );
    expect(
      rpc.calls.firstWhere((c) => c.$1 == 'v1_wf_get_day').$2['p_team_id'],
      _placeId,
    );
  });

  testWidgets('added workers start present at 06:30, no overtime, Tower A', (
    tester,
  ) async {
    _size(tester, const Size(360, 800));
    Map<String, Object?>? saved;
    final rpc = _FakeRpc({
      'v1_wf_list_places': (_) => _places(),
      'v1_wf_get_day': (_) => _day(
        // One building only: new rows take it.
        place: _place(buildings: [_buildings[0], _buildings[1]]),
      ),
      'v1_wf_save_day': (params) {
        saved = params;
        return _day(saved: true, rows: [_row('w1', 'Gul Zaman')]);
      },
    });
    await _pump(
      tester,
      rpc,
      '${RoutePaths.yorksV1WorkforceAttendance}?crew=$_placeId&date=$_date',
    );
    await _tap(tester, find.byKey(const ValueKey('attendance-empty-add')));
    await tester.tap(find.byKey(const ValueKey('attendance-picker-worker-w1')));
    await tester.tap(find.byKey(const ValueKey('attendance-picker-worker-w3')));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('attendance-picker-add')));

    expect(find.text('Gul Zaman'), findsOneWidget);
    expect(find.text('Ravi Kumar'), findsOneWidget);
    // Two rows, and the usual shift on its button.
    expect(find.textContaining('6:30 AM – 2:30 PM'), findsNWidgets(3));
    expect(find.textContaining('OT'), findsNothing);
    // Two rows, and the building new rows start with.
    expect(find.text('Tower A'), findsNWidgets(3));

    await _tap(tester, find.byKey(const ValueKey('attendance-save-day')));
    final rows = (saved!['p_rows'] as List).cast<Map<String, Object?>>();
    expect(rows, hasLength(2));
    expect(rows.first['status'], 'P');
    expect(rows.first['start_minute'], 390);
    expect(rows.first['finish_minute'], 870);
    expect(rows.first['work_project_id'], 'p1');
    expect(rows.first['work_scope_id'], 'b1');
    expect(saved!['p_change_reason'], isNull);
  });

  testWidgets('a building is chosen per row', (tester) async {
    _size(tester, const Size(360, 800));
    Map<String, Object?>? saved;
    final rpc = _FakeRpc({
      'v1_wf_list_places': (_) => _places(),
      'v1_wf_get_day': (_) =>
          _day(saved: true, rows: [_row('w1', 'Gul Zaman')]),
      'v1_wf_save_day': (params) {
        saved = params;
        return _day(saved: true, rows: [_row('w1', 'Gul Zaman', scope: 'b2')]);
      },
    });
    await _pump(
      tester,
      rpc,
      '${RoutePaths.yorksV1WorkforceAttendance}?crew=$_placeId&date=$_date',
    );
    await _tap(
      tester,
      find.byKey(const ValueKey('attendance-row-building-w1')),
    );
    expect(find.text('Common'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('attendance-building-b2')));
    expect(find.text('Tower B'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('attendance-save-day')));
    expect((saved!['p_rows'] as List).single['work_scope_id'], 'b2');
  });

  testWidgets('removing every row of a saved day can be saved', (tester) async {
    _size(tester, const Size(360, 800));
    Map<String, Object?>? saved;
    final rpc = _FakeRpc({
      'v1_wf_list_places': (_) => _places(),
      'v1_wf_get_day': (_) =>
          _day(saved: true, rows: [_row('w1', 'Gul Zaman')]),
      'v1_wf_save_day': (params) {
        saved = params;
        return _day(saved: true);
      },
    });
    await _pump(
      tester,
      rpc,
      '${RoutePaths.yorksV1WorkforceAttendance}?crew=$_placeId&date=$_date',
    );
    await _tap(tester, find.byTooltip('Remove'));
    final save = find.byKey(const ValueKey('attendance-save-day'));
    expect(save, findsOneWidget);
    await _tap(tester, save);
    expect(saved, isNotNull, reason: 'Save stays enabled for an emptied day');
    expect(saved!['p_rows'], isEmpty);
    expect(saved!['p_expected_version'], 3);
  });

  testWidgets('adding to a day someone else saved needs no reason', (
    tester,
  ) async {
    _size(tester, const Size(360, 800));
    Map<String, Object?>? saved;
    final rpc = _FakeRpc({
      'v1_wf_list_places': (_) => _places(),
      'v1_wf_get_day': (_) =>
          _day(saved: true, rows: [_row('w1', 'Gul Zaman', mine: false)]),
      'v1_wf_save_day': (params) {
        saved = params;
        return _day(saved: true);
      },
    });
    await _pump(
      tester,
      rpc,
      '${RoutePaths.yorksV1WorkforceAttendance}?crew=$_placeId&date=$_date',
    );
    expect(find.textContaining('Saved by Imran Qureshi'), findsOneWidget);
    await _tap(
      tester,
      find.byKey(const ValueKey('attendance-add-worker-open')),
    );
    await tester.tap(find.byKey(const ValueKey('attendance-picker-worker-w2')));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('attendance-picker-add')));
    await _tap(tester, find.byKey(const ValueKey('attendance-save-day')));
    expect(
      find.byKey(const ValueKey('attendance-text-dialog-field')),
      findsNothing,
    );
    expect(saved, isNotNull);
    expect(saved!['p_rows'] as List, hasLength(2));
    expect(saved!['p_change_reason'], isNull);
  });

  testWidgets('another date loads under the same page', (tester) async {
    _size(tester, const Size(1280, 900));
    final next = Completer<Map<String, dynamic>>();
    final rpc = _FakeRpc({
      'v1_wf_list_places': (_) => _places(),
      'v1_wf_get_day': (params) => params['p_work_date'] == _nextDate
          ? next.future
          : _day(saved: true, rows: [_row('w1', 'Gul Zaman')]),
    });
    final router = await _pump(
      tester,
      rpc,
      '${RoutePaths.yorksV1WorkforceAttendance}?crew=$_placeId&date=$_date',
    );
    expect(find.text('Gul Zaman'), findsOneWidget);

    router.go(
      '${RoutePaths.yorksV1WorkforceAttendance}?crew=$_placeId&date=$_nextDate',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // No full-page spinner: the place, the strip and the last day stay.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.byKey(const ValueKey('attendance-day-loading')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('attendance-place-button')),
      findsOneWidget,
    );
    expect(find.text('Wednesday 11 November'), findsOneWidget);
    expect(find.text('Gul Zaman'), findsOneWidget);

    next.complete(_day(date: _nextDate));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('attendance-day-loading')), findsNothing);
    expect(find.text('Gul Zaman'), findsNothing);
    expect(find.byKey(const ValueKey('attendance-empty-add')), findsOneWidget);
  });

  group('screenshots (desktop and 360px phone)', () {
    Map<String, FutureOr<Map<String, dynamic>> Function(Map<String, Object?>)>
    server() => {
      'v1_wf_list_places': (_) => _places(),
      'v1_wf_get_day': (_) => _day(
        saved: true,
        rows: [
          _row('w1', 'Gul Zaman'),
          _row('w2', 'Waqar Ahmed', mine: false, scope: null),
          _row('w3', 'Ravi Kumar', status: 'A', scope: null),
        ],
      ),
    };

    for (final (name, size) in [
      ('phone', const Size(360, 800)),
      ('desktop', const Size(1280, 860)),
    ]) {
      testWidgets('$name place day', (tester) async {
        _size(tester, size);
        await _pump(
          tester,
          _FakeRpc(server()),
          '${RoutePaths.yorksV1WorkforceAttendance}?crew=$_placeId&date=$_date',
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/attendance_places_${name}_day.png'),
        );
      });

      // Attendance by role (PRODUCT_DECISIONS 58): the Site Engineer's one
      // screen, and the Workshop In-Charge's Workshop with its tabs.
      testWidgets('$name site engineer attendance', (tester) async {
        _size(tester, size);
        await _pump(
          tester,
          _FakeRpc(server()),
          '${RoutePaths.yorksV1WorkforceAttendance}?crew=$_placeId&date=$_date',
          role: YorksV1Role.siteEngineer,
          shell: true,
        );
        await _loadImages(tester);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/attendance_roles_${name}_site_engineer.png',
          ),
        );
      });

      testWidgets('$name workshop in-charge workshop', (tester) async {
        _size(tester, size);
        await _pump(
          tester,
          _FakeRpc({
            'v1_wf_list_places': (_) => _places(),
            'v1_wf_get_day': (_) => _day(
              saved: true,
              place: _workshopPlace(),
              rows: [
                _row('w1', 'Gul Zaman', scope: null),
                _row('w3', 'Ravi Kumar', mine: false, scope: null),
              ],
            ),
          }),
          '${RoutePaths.yorksV1WorkforceAttendance}?date=$_date',
          role: YorksV1Role.workshopInCharge,
          shell: true,
        );
        await _loadImages(tester);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/attendance_roles_${name}_workshop.png'),
        );
      });

      testWidgets('$name place chooser', (tester) async {
        _size(tester, size);
        await _pump(
          tester,
          _FakeRpc({'v1_wf_list_places': (_) => _places(withCrew: false)}),
          RoutePaths.yorksV1WorkforceAttendance,
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/attendance_places_${name}_chooser.png'),
        );
      });
    }
  });
}

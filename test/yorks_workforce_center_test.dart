// Workforce Center and crew requests against a fake server: the register
// views, raising a request by trade or by name, the Project Engineer's
// decision with a reason, approve-and-assign in one step with the named
// worker's warning, PR's assignment with a short line, taking attendance and
// finishing, and phone layouts.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/app/router.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/workforce/application/attendance_providers.dart';
import 'package:material_ledger/features/workforce/data/attendance_repository.dart';
import 'package:material_ledger/features/workforce/data/workforce_repository.dart';
import 'package:material_ledger/features/workforce/domain/crew_request_models.dart';
import 'package:material_ledger/features/workforce/presentation/attendance/attendance_overview_screen.dart';
import 'package:material_ledger/features/workforce/presentation/requests/crew_request_assign_screen.dart';
import 'package:material_ledger/features/workforce/presentation/requests/crew_request_detail_screen.dart';
import 'package:material_ledger/features/workforce/presentation/requests/crew_request_form_screen.dart';
import 'package:material_ledger/features/workforce/presentation/requests/crew_request_register_screen.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/accounts_v2_golden_fonts.dart';

const _today = '2026-11-12';
const _crewId = '5a000000-0000-4000-8000-000000000001';
const _requestId = '7c000000-0000-4000-8000-000000000001';

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
  workforceCenter: true,
);

Map<String, Object?> _crewAccess({bool take = true}) => {
  'view': true,
  'take': take,
  'confirm': false,
  'manage': false,
  'officer': false,
};

Map<String, Object?> _overview() => {
  'today': _today,
  'month': '2026-11-01',
  'crews': [
    {
      'id': _crewId,
      'name': 'Sweihan site crew',
      'kind': 'project',
      'project_id': 'p1',
      'work_label': 'Sweihan · YRA-321',
      'needs_confirmation': true,
      'shift_start_minute': 390,
      'shift_finish_minute': 1020,
      'is_active': true,
      'record_version': 1,
      'member_count': 2,
      'access': _crewAccess(),
      'month': {
        'month': '2026-11-01',
        'last_day': '2026-11-30',
        'state': 'recording',
        'days': <Object>[],
        'missing_days': ['2026-11-10'],
        'work_days_so_far': 10,
        'days_entered': 9,
        'regular_minutes': 0,
        'normal_overtime_minutes': 0,
        'holiday_overtime_minutes': 0,
        'can_confirm': false,
        'record_version': 0,
      },
    },
  ],
  'feed': <Object>[],
};

Map<String, Object?> _requestAccess({
  bool decide = false,
  bool fulfil = false,
  bool cancel = false,
  bool resubmit = false,
  bool finish = false,
}) => {
  'view': true,
  'decide': decide,
  'fulfil': fulfil,
  'cancel': cancel,
  'resubmit': resubmit,
  'finish': finish,
};

/// Rahim Shah, asked for by name, is on another project's crew.
const _otherCrewId = '5a000000-0000-4000-8000-000000000009';
const _rahim = {
  'id': 'w3',
  'number': 'W-3',
  'name': 'Rahim Shah',
  'designation': 'Duct fitter',
  'crew_id': _otherCrewId,
  'crew_name': 'Ruwais crew',
};

/// A request naming Rahim Shah, plus two helpers by trade.
List<Map<String, Object?>> _namedLines({
  List<Map<String, Object?>> assigned = const [],
}) => [
  {
    'id': 'line-1',
    'line_number': 1,
    'trade': 'Duct fitter',
    'quantity': 1,
    'note': null,
    'decision': null,
    'decision_reason': null,
    'worker': _rahim,
    'assigned': assigned,
  },
  {
    'id': 'line-2',
    'line_number': 2,
    'trade': 'Helper',
    'quantity': 2,
    'note': null,
    'decision': null,
    'decision_reason': null,
    'assigned': <Object>[],
  },
];

const _namedTrades = [
  {'trade': 'Duct fitter', 'quantity': 1, 'worker_name': 'Rahim Shah'},
  {'trade': 'Helper', 'quantity': 2},
];

Map<String, Object?> _request({
  String state = 'submitted',
  String owner = 'project_engineer',
  Map<String, Object?>? access,
  int version = 1,
  List<Map<String, Object?>>? assigned,
  String? reason,
  List<Map<String, Object?>>? lines,
  List<Map<String, Object?>>? trades,
  bool onCrew = false,
}) => {
  'id': _requestId,
  'number': 'CRQ-2026-0001',
  'state': state,
  'crew_kind': 'project',
  'project_id': 'p1',
  'project_name': 'Sweihan',
  'project_ref': 'YRA-321',
  'work_label': 'Level 3 ductwork',
  'target_crew_id': onCrew ? _crewId : null,
  'target_crew_name': onCrew ? 'Sweihan site crew' : null,
  'needed_from': '2026-11-14',
  'needed_until': null,
  'notes': 'Ceiling closes next week',
  'requested_by': {
    'id': 'se-1',
    'name': 'Imran Qureshi',
    'role': 'site_engineer',
  },
  'submitted_at': '2026-11-12T06:00:00Z',
  'decided_by': reason == null
      ? null
      : {'id': 'pe-1', 'name': 'Bilal Khan', 'role': 'project_engineer'},
  'decided_at': reason == null ? null : '2026-11-12T07:00:00Z',
  'decision_reason': reason,
  'last_actor': {'name': 'Imran Qureshi', 'role': 'site_engineer'},
  'updated_at': '2026-11-12T06:00:00Z',
  'record_version': version,
  'owner': owner,
  'overdue': false,
  'requested_count': 5,
  'assigned_count': assigned?.length ?? 0,
  'trades':
      trades ??
      [
        {'trade': 'Duct fitter', 'quantity': 3},
        {'trade': 'Helper', 'quantity': 2},
      ],
  'access': access ?? _requestAccess(),
  'lines':
      lines ??
      [
        {
          'id': 'line-1',
          'line_number': 1,
          'trade': 'Duct fitter',
          'quantity': 3,
          'note': null,
          'decision': null,
          'decision_reason': null,
          'assigned': assigned ?? <Object>[],
        },
        {
          'id': 'line-2',
          'line_number': 2,
          'trade': 'Helper',
          'quantity': 2,
          'note': 'Any helper',
          'decision': null,
          'decision_reason': null,
          'assigned': <Object>[],
        },
      ],
  'events': [
    {
      'type': 'submitted',
      'actor_name': 'Imran Qureshi',
      'actor_role': 'site_engineer',
      'to_state': 'submitted',
      'detail': <String, Object?>{},
      'at': '2026-11-12T06:00:00Z',
    },
  ],
};

Map<String, Object?> _register(
  List<Map<String, Object?>> requests, {
  bool canRequest = true,
}) => {'today': _today, 'can_request': canRequest, 'requests': requests};

Map<String, Object?> _options({bool officer = false, bool named = false}) => {
  'today': _today,
  'workshop': false,
  'projects': [
    {
      'id': 'p1',
      'name': 'Sweihan',
      'ref': 'YRA-321',
      'approved_on_submit': false,
    },
  ],
  'trades': ['Duct fitter', 'Helper'],
  'crews': [
    {
      'id': _crewId,
      'name': 'Sweihan site crew',
      'kind': 'project',
      'project_id': 'p1',
      'shift_start_minute': 390,
      'shift_finish_minute': 1020,
    },
  ],
  'workers': officer || named
      ? [
          for (final (i, name) in [
            'Gul Zaman',
            'Waqar Ahmed',
            'Sajjad Ali',
          ].indexed)
            {
              'id': 'w$i',
              'number': 'W-$i',
              'name': name,
              'designation': 'Duct fitter',
              'company': 'Example Manpower LLC',
              'crew_id': null,
              'crew_name': null,
            },
          {..._rahim, 'company': 'Example Manpower LLC'},
        ]
      : <Object>[],
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

  Map<String, Object?> last(String name) =>
      calls.lastWhere((call) => call.$1 == name).$2;
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
  YorksV1FeatureFlags flags = _flags,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: RoutePaths.yorksV1Workforce,
        builder: (_, state) => Scaffold(
          body: AttendanceOverviewScreen(
            initialView: state.uri.queryParameters['view'],
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1WorkforceRequests,
        builder: (_, _) => const Scaffold(body: CrewRequestRegisterScreen()),
      ),
      GoRoute(
        path: RoutePaths.yorksV1WorkforceRequestNew,
        builder: (_, state) => Scaffold(
          body: CrewRequestFormScreen(
            requestId: state.uri.queryParameters['request'],
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1WorkforceRequest,
        builder: (_, state) => Scaffold(
          body: CrewRequestDetailScreen(
            requestId: state.pathParameters['requestId']!,
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1WorkforceRequestAssign,
        builder: (_, state) => Scaffold(
          body: CrewRequestAssignScreen(
            requestId: state.pathParameters['requestId']!,
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1WorkforceAttendance,
        builder: (_, _) => const Scaffold(body: Text('take attendance')),
      ),
      GoRoute(
        path: RoutePaths.yorksV1WorkforceConfirm,
        builder: (_, _) => const Scaffold(body: Text('confirm')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksV1AuthUserIdProvider.overrideWithValue('actor-1'),
        yorksV1FeatureFlagsProvider.overrideWithValue(flags),
        yorksAttendanceRepositoryProvider.overrideWithValue(
          YorksAttendanceRepository(
            featureFlags: flags,
            connectivity: const _Online(),
            rpcClient: rpc,
          ),
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('My work lists what waits for me, newest views one tap away', (
    tester,
  ) async {
    _size(tester, const Size(1280, 900));
    final rpc = _FakeRpc({
      'v1_wf_get_overview': (_) => _overview(),
      'v1_wf_list_requests': (_) => _register([
        _request(
          state: 'returned',
          owner: 'requester',
          access: _requestAccess(resubmit: true, cancel: true),
          reason: 'Split by level',
        ),
      ]),
    });
    final router = await _pump(tester, rpc, RoutePaths.yorksV1Workforce);

    expect(find.text('Workforce Center'), findsOneWidget);
    expect(find.text('Open crew requests'), findsOneWidget);
    expect(find.text('1 waiting for you'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('workforce-center-request-crew')),
      findsOneWidget,
    );
    // My work: the returned request and the crew's missing day.
    expect(find.text('Fix and resubmit · CRQ-2026-0001'), findsOneWidget);
    expect(find.text('Enter attendance · Sweihan site crew'), findsOneWidget);

    await _tap(
      tester,
      find.byKey(const ValueKey('workforce-center-view-requests')),
    );
    expect(
      find.byKey(const ValueKey('workforce-center-requests')),
      findsOneWidget,
    );
    expect(find.text('3 × Duct fitter, 2 × Helper'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('workforce-center-open-register')),
      findsOneWidget,
    );

    await _tap(
      tester,
      find.byKey(const ValueKey('workforce-center-view-crews')),
    );
    expect(find.text('Sweihan site crew'), findsWidgets);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/yorks/workforce',
    );
  });

  testWidgets('the notification link opens the Crew requests view', (
    tester,
  ) async {
    _size(tester, const Size(1280, 900));
    final rpc = _FakeRpc({
      'v1_wf_get_overview': (_) => _overview(),
      'v1_wf_list_requests': (_) => _register([_request()]),
      'v1_wf_get_request': (_) => _request(),
    });
    await _pump(tester, rpc, '${RoutePaths.yorksV1Workforce}?view=requests');
    expect(
      find.byKey(const ValueKey('workforce-center-requests')),
      findsOneWidget,
    );
    await _tap(
      tester,
      find.byKey(const ValueKey('crew-request-row-$_requestId')),
    );
    // The row opens the request page.
    expect(rpc.calls.map((c) => c.$1), contains('v1_wf_get_request'));
  });

  testWidgets('without the Workforce Center flag the overview is unchanged', (
    tester,
  ) async {
    _size(tester, const Size(1280, 900));
    final rpc = _FakeRpc({'v1_wf_get_overview': (_) => _overview()});
    await _pump(
      tester,
      rpc,
      RoutePaths.yorksV1Workforce,
      flags: const YorksV1FeatureFlags(
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
      ),
    );
    expect(find.text('Workforce Overview'), findsOneWidget);
    expect(find.text('Open crew requests'), findsNothing);
    expect(rpc.calls.map((c) => c.$1), isNot(contains('v1_wf_list_requests')));
  });

  testWidgets('a Site Engineer requests a crew; nothing is sent before Send', (
    tester,
  ) async {
    _size(tester, const Size(1280, 1000));
    final rpc = _FakeRpc({
      'v1_wf_request_options': (_) => _options(),
      'v1_wf_submit_request': (_) => _request(),
      'v1_wf_get_request': (_) => _request(),
    });
    final router = await _pump(
      tester,
      rpc,
      RoutePaths.yorksV1WorkforceRequestNew,
    );

    expect(
      find.text(
        "Goes to the project's Project Engineer, who approves it and assigns the workers.",
      ),
      findsOneWidget,
    );
    await _tap(tester, find.byKey(const ValueKey('crew-request-send')));
    expect(
      find.text('Add at least one trade with how many people.'),
      findsOneWidget,
    );
    expect(rpc.calls.map((c) => c.$1), isNot(contains('v1_wf_submit_request')));

    await tester.enterText(
      find.byKey(const ValueKey('crew-request-trade-0')),
      'Duct fitter',
    );
    await tester.enterText(
      find.byKey(const ValueKey('crew-request-quantity-0')),
      '3',
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('crew-request-send')));

    final sent = rpc.last('v1_wf_submit_request');
    final payload = sent['p_payload'] as Map<String, Object?>;
    expect(payload['project_id'], 'p1');
    expect(payload['crew_kind'], 'project');
    expect(payload['needed_from'], _today);
    expect(payload['lines'], [
      {'trade': 'Duct fitter', 'quantity': 3},
    ]);
    expect(sent['p_idempotency_key'], isNotNull);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/yorks/workforce/requests/$_requestId',
    );
  });

  testWidgets('the Project Engineer returns a request only with a reason', (
    tester,
  ) async {
    _size(tester, const Size(1280, 1000));
    var current = _request(access: _requestAccess(decide: true));
    final rpc = _FakeRpc({
      'v1_wf_get_request': (_) => current,
      'v1_wf_list_requests': (_) => _register([current]),
      'v1_wf_decide_request': (params) {
        current = _request(
          state: 'returned',
          owner: 'requester',
          version: 2,
          reason: params['p_reason'] as String?,
        );
        return current;
      },
    });
    await _pump(tester, rpc, '/yorks/workforce/requests/$_requestId');

    expect(find.text('CRQ-2026-0001'), findsOneWidget);
    expect(find.text('Approve and assign, or return'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('crew-request-return')));
    expect(find.text('Return CRQ-2026-0001?'), findsOneWidget);
    await tester.tap(find.text('Return').last);
    await tester.pumpAndSettle();
    expect(rpc.calls.map((c) => c.$1), isNot(contains('v1_wf_decide_request')));

    await tester.enterText(find.byType(TextField).last, 'Split by level');
    await tester.tap(find.text('Return').last);
    await tester.pumpAndSettle();
    final decided = rpc.last('v1_wf_decide_request');
    expect(decided['p_decision'], 'return');
    expect(decided['p_reason'], 'Split by level');
    expect(decided['p_expected_version'], 1);
    expect(find.text('Returned'), findsWidgets);
    expect(find.text('Bilal Khan: “Split by level”'), findsOneWidget);
  });

  testWidgets('PR assigns two of three fitters and says why one is short', (
    tester,
  ) async {
    _size(tester, const Size(1280, 1400));
    final rpc = _FakeRpc({
      'v1_wf_get_request': (_) => _request(
        state: 'approved',
        owner: 'pr',
        access: _requestAccess(fulfil: true),
        version: 3,
      ),
      'v1_wf_request_options': (_) => _options(officer: true),
      'v1_wf_list_requests': (_) => _register(const []),
      'v1_wf_fulfil_request': (_) => _request(
        state: 'partially_fulfilled',
        owner: 'pr',
        access: _requestAccess(fulfil: true),
        version: 4,
      ),
    });
    await _pump(tester, rpc, '/yorks/workforce/requests/$_requestId/assign');

    expect(find.text('Assign workers · CRQ-2026-0001'), findsOneWidget);
    await _tap(
      tester,
      find.byKey(const ValueKey('crew-request-assign-worker-line-1-w0')),
    );
    await _tap(
      tester,
      find.byKey(const ValueKey('crew-request-assign-worker-line-1-w1')),
    );
    expect(find.text('2 of 3 chosen'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('crew-request-assign-save')));
    expect(
      find.text('Give a reason for each line left short.'),
      findsOneWidget,
    );
    expect(rpc.calls.map((c) => c.$1), isNot(contains('v1_wf_fulfil_request')));

    await tester.enterText(
      find.byKey(const ValueKey('crew-request-assign-reason-line-1')),
      'Third fitter free from Monday',
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('crew-request-assign-save')));

    final sent = rpc.last('v1_wf_fulfil_request');
    expect(sent['p_expected_version'], 3);
    final payload = sent['p_payload'] as Map<String, Object?>;
    expect(payload['crew_id'], _crewId);
    expect(payload.containsKey('new_crew'), isFalse);
    expect(payload['lines'], [
      {
        'line_id': 'line-1',
        'worker_ids': ['w0', 'w1'],
        'decision': 'partial',
        'reason': 'Third fitter free from Monday',
      },
    ]);
  });

  test('a person asked for by name is one person, with their trade', () {
    expect(
      const CrewRequestDraftLine(
        trade: 'Duct fitter',
        quantity: 7,
        workerId: 'w3',
      ).toJson(),
      {'worker_id': 'w3', 'trade': 'Duct fitter', 'quantity': 1},
    );
    expect(
      const CrewRequestDraftLine(trade: ' Helper ', quantity: 2).toJson(),
      {'trade': 'Helper', 'quantity': 2},
    );
    final line = CrewRequestLine.fromJson(_namedLines().first);
    expect(line.worker?.name, 'Rahim Shah');
    expect(line.namedOnOtherCrew, isTrue);
    final assigned = CrewRequestLine.fromJson(
      _namedLines(
        assigned: [
          {
            'worker_id': 'w3',
            'number': 'W-3',
            'name': 'Rahim Shah',
            'designation': 'Duct fitter',
            'crew_id': _crewId,
            'crew_name': 'Sweihan site crew',
          },
        ],
      ).first,
    );
    expect(assigned.namedOnOtherCrew, isFalse);
    expect(CrewRequestState.from('completed').isOpen, isFalse);
    expect(CrewRequestState.from('fulfilled').isOpen, isTrue);
  });

  testWidgets('a Site Engineer names a worker as they type; the warning shows', (
    tester,
  ) async {
    _size(tester, const Size(1280, 1400));
    final rpc = _FakeRpc({
      'v1_wf_request_options': (_) => _options(named: true),
      'v1_wf_submit_request': (_) =>
          _request(lines: _namedLines(), trades: _namedTrades),
      'v1_wf_get_request': (_) =>
          _request(lines: _namedLines(), trades: _namedTrades),
    });
    await _pump(tester, rpc, RoutePaths.yorksV1WorkforceRequestNew);

    await tester.enterText(
      find.byKey(const ValueKey('crew-request-trade-0')),
      'rahim',
    );
    await tester.pumpAndSettle();
    final suggestion = find.byKey(
      const ValueKey('crew-request-suggest-worker-0-w3'),
    );
    expect(suggestion, findsOneWidget);
    expect(find.text('On Ruwais crew'), findsOneWidget);
    await _tap(tester, suggestion);

    expect(find.byKey(const ValueKey('crew-request-named-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('crew-request-quantity-0')), findsNothing);
    expect(find.text('Rahim Shah is on Ruwais crew'), findsOneWidget);
    expect(
      find.text(
        "The approver sees this. If they approve, Rahim Shah moves to this request's crew.",
      ),
      findsOneWidget,
    );

    // A second line by trade; the named person is not offered twice.
    await _tap(tester, find.byKey(const ValueKey('crew-request-add-line')));
    await tester.enterText(
      find.byKey(const ValueKey('crew-request-trade-1')),
      'rahim',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('crew-request-suggest-worker-1-w3')),
      findsNothing,
    );
    await tester.enterText(
      find.byKey(const ValueKey('crew-request-trade-1')),
      'help',
    );
    await tester.pumpAndSettle();
    await _tap(
      tester,
      find.byKey(const ValueKey('crew-request-suggest-trade-1-Helper')),
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('crew-request-quantity-1')),
          )
          .controller!
          .text,
      '1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('crew-request-quantity-1')),
      '2',
    );
    await tester.pumpAndSettle();
    expect(find.text('Rahim Shah (Duct fitter), 2 × Helper'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('crew-request-send')));
    final payload =
        rpc.last('v1_wf_submit_request')['p_payload'] as Map<String, Object?>;
    expect(payload['lines'], [
      {'worker_id': 'w3', 'trade': 'Duct fitter', 'quantity': 1},
      {'trade': 'Helper', 'quantity': 2},
    ]);
  });

  testWidgets('the Project Engineer approves and assigns in one step', (
    tester,
  ) async {
    _size(tester, const Size(1280, 1600));
    final rpc = _FakeRpc({
      'v1_wf_get_request': (_) => _request(
        access: _requestAccess(decide: true),
        lines: _namedLines(),
        trades: _namedTrades,
        version: 2,
      ),
      'v1_wf_request_options': (_) => _options(officer: true),
      'v1_wf_list_requests': (_) => _register(const []),
      'v1_wf_fulfil_request': (_) => _request(
        state: 'partially_fulfilled',
        owner: 'pr',
        access: _requestAccess(fulfil: true),
        lines: _namedLines(),
        trades: _namedTrades,
        version: 3,
      ),
    });
    final router = await _pump(
      tester,
      rpc,
      '/yorks/workforce/requests/$_requestId',
    );

    // The approver sees the requester's warning clearly.
    expect(
      find.byKey(const ValueKey('crew-request-line-warning-line-1')),
      findsOneWidget,
    );
    expect(
      find.text('On Ruwais crew · approving moves them here'),
      findsOneWidget,
    );
    expect(find.text('Rahim Shah (Duct fitter), 2 × Helper'), findsWidgets);
    await _tap(
      tester,
      find.byKey(const ValueKey('crew-request-approve-assign')),
    );
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/yorks/workforce/requests/$_requestId/assign',
    );
    expect(find.text('Approve and assign · CRQ-2026-0001'), findsOneWidget);

    final named = find.byKey(
      const ValueKey('crew-request-assign-worker-line-1-w3'),
    );
    expect(tester.widget<CheckboxListTile>(named).value, isTrue);
    expect(
      find.byKey(const ValueKey('crew-request-assign-moves-w3')),
      findsOneWidget,
    );
    expect(find.text('Moves from Ruwais crew'), findsOneWidget);

    // The approver may remove the named person, then change their mind.
    await _tap(tester, named);
    expect(tester.widget<CheckboxListTile>(named).value, isFalse);
    expect(find.text('Approve only'), findsOneWidget);
    await _tap(tester, named);
    expect(find.text('Approve and assign 1'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('crew-request-assign-save')));
    final sent = rpc.last('v1_wf_fulfil_request');
    expect(sent['p_expected_version'], 2);
    final payload = sent['p_payload'] as Map<String, Object?>;
    expect(payload['approve'], isTrue);
    expect(payload['crew_id'], _crewId);
    expect(payload['lines'], [
      {
        'line_id': 'line-1',
        'worker_ids': ['w3'],
      },
    ]);
  });

  testWidgets('approve only sends every line with no one chosen', (
    tester,
  ) async {
    _size(tester, const Size(1280, 1600));
    final rpc = _FakeRpc({
      'v1_wf_get_request': (_) => _request(
        access: _requestAccess(decide: true),
        lines: _namedLines(),
        trades: _namedTrades,
      ),
      'v1_wf_request_options': (_) => _options(officer: true),
      'v1_wf_list_requests': (_) => _register(const []),
      'v1_wf_fulfil_request': (_) =>
          _request(state: 'approved', owner: 'pr', version: 2),
    });
    await _pump(tester, rpc, '/yorks/workforce/requests/$_requestId/assign');
    await _tap(
      tester,
      find.byKey(const ValueKey('crew-request-assign-worker-line-1-w3')),
    );
    await _tap(tester, find.byKey(const ValueKey('crew-request-assign-save')));
    final payload =
        rpc.last('v1_wf_fulfil_request')['p_payload'] as Map<String, Object?>;
    expect(payload['approve'], isTrue);
    expect(payload.containsKey('crew_id'), isFalse);
    expect(payload['lines'], [
      {'line_id': 'line-1', 'worker_ids': <String>[]},
      {'line_id': 'line-2', 'worker_ids': <String>[]},
    ]);
  });

  testWidgets('the requester takes attendance, then finishes the request', (
    tester,
  ) async {
    _size(tester, const Size(1280, 1200));
    var current = _request(
      state: 'fulfilled',
      owner: 'requester',
      access: _requestAccess(finish: true),
      version: 5,
      onCrew: true,
    );
    final rpc = _FakeRpc({
      'v1_wf_get_request': (_) => current,
      'v1_wf_list_requests': (_) => _register([current]),
      'v1_wf_finish_request': (params) {
        current = _request(
          state: 'completed',
          owner: 'none',
          version: 6,
          onCrew: true,
        );
        return current;
      },
    });
    final router = await _pump(
      tester,
      rpc,
      '/yorks/workforce/requests/$_requestId',
    );

    expect(find.text('Workers on site'), findsWidgets);
    expect(
      find.text('Take attendance · finish when the work is done'),
      findsOneWidget,
    );
    await _tap(
      tester,
      find.byKey(const ValueKey('crew-request-take-attendance')),
    );
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/yorks/workforce/attendance?crew=$_crewId',
    );
    router.go('/yorks/workforce/requests/$_requestId');
    await tester.pumpAndSettle();

    await _tap(tester, find.byKey(const ValueKey('crew-request-finish')));
    expect(find.text('Finish CRQ-2026-0001?'), findsOneWidget);
    expect(rpc.calls.map((c) => c.$1), isNot(contains('v1_wf_finish_request')));
    await tester.tap(find.text('Finish and release workers').last);
    await tester.pumpAndSettle();
    final sent = rpc.last('v1_wf_finish_request');
    expect(sent['p_expected_version'], 5);
    expect(sent['p_idempotency_key'], isNotNull);
    expect(find.text('Finished'), findsWidgets);
    expect(find.byKey(const ValueKey('crew-request-finish')), findsNothing);
  });

  test('engineers and the Accountant reach Workforce by role', () {
    for (final role in [
      YorksV1Role.siteEngineer,
      YorksV1Role.projectEngineer,
      YorksV1Role.seniorMechanicalEngineer,
      YorksV1Role.projectManager,
      YorksV1Role.workshopInCharge,
      YorksV1Role.documentController,
      YorksV1Role.accountant,
    ]) {
      expect(role.reachesWorkforceByRole, isTrue, reason: role.name);
    }
    for (final role in [
      YorksV1Role.procurement,
      YorksV1Role.admin,
      YorksV1Role.pr,
    ]) {
      expect(role.reachesWorkforceByRole, isFalse, reason: role.name);
    }
  });

  testWidgets('the register starts on My work, searches and opens', (
    tester,
  ) async {
    _size(tester, const Size(390, 844));
    final rpc = _FakeRpc({
      'v1_wf_list_requests': (_) => _register([
        _request(
          state: 'returned',
          owner: 'requester',
          access: _requestAccess(resubmit: true, cancel: true),
          reason: 'Split by level',
        ),
        {
          ..._request(state: 'fulfilled', owner: 'none'),
          'id': '7c000000-0000-4000-8000-000000000009',
          'number': 'CRQ-2026-0009',
          'project_ref': 'YRA-400',
          'project_name': 'Ruwais',
        },
      ]),
      'v1_wf_get_request': (_) => _request(),
    });
    await _pump(tester, rpc, RoutePaths.yorksV1WorkforceRequests);

    expect(find.text('Crew Requests'), findsOneWidget);
    expect(find.text('My work · 1'), findsOneWidget);
    expect(find.text('CRQ-2026-0001'), findsOneWidget);
    expect(find.text('CRQ-2026-0009'), findsNothing);
    expect(find.text('Requester · Fix and resubmit'), findsNothing);

    await _tap(tester, find.byKey(const ValueKey('crew-register-all')));
    expect(find.text('CRQ-2026-0009'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('crew-register-search')),
      'ruwais',
    );
    await tester.pumpAndSettle();
    expect(find.text('CRQ-2026-0001'), findsNothing);
    expect(find.text('CRQ-2026-0009'), findsOneWidget);

    await _tap(
      tester,
      find.byKey(
        const ValueKey(
          'crew-request-card-7c000000-0000-4000-8000-000000000009',
        ),
      ),
    );
    expect(rpc.calls.map((c) => c.$1), contains('v1_wf_get_request'));
  });

  testWidgets('on a phone a Site Engineer goes Details, People, Review, Send', (
    tester,
  ) async {
    _size(tester, const Size(390, 844));
    final rpc = _FakeRpc({
      'v1_wf_request_options': (_) => _options(),
      'v1_wf_submit_request': (_) => _request(),
      'v1_wf_get_request': (_) => _request(),
    });
    await _pump(tester, rpc, RoutePaths.yorksV1WorkforceRequestNew);

    expect(find.text('Who needs workers?'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('crew-request-continue')));
    expect(find.text('Which people do you need?'), findsOneWidget);
    // Review waits for a trade and how many.
    final review = tester.widget<FilledButton>(
      find.byKey(const ValueKey('crew-request-review')),
    );
    expect(review.onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('crew-request-trade-0')),
      'Duct fitter',
    );
    await tester.enterText(
      find.byKey(const ValueKey('crew-request-quantity-0')),
      '4',
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('crew-request-review')));
    expect(find.text('Review and send'), findsOneWidget);
    expect(find.text('4 × Duct fitter'), findsOneWidget);
    expect(rpc.calls.map((c) => c.$1), isNot(contains('v1_wf_submit_request')));

    await _tap(tester, find.byKey(const ValueKey('crew-request-send')));
    final payload =
        rpc.calls
                .lastWhere((c) => c.$1 == 'v1_wf_submit_request')
                .$2['p_payload']
            as Map<String, Object?>;
    expect(payload['lines'], [
      {'trade': 'Duct fitter', 'quantity': 4},
    ]);
  });

  for (final (name, location) in [
    ('center', RoutePaths.yorksV1Workforce),
    ('requests', '${RoutePaths.yorksV1Workforce}?view=requests'),
    ('detail', '/yorks/workforce/requests/$_requestId'),
    ('form', RoutePaths.yorksV1WorkforceRequestNew),
    ('register', RoutePaths.yorksV1WorkforceRequests),
    ('assign', '/yorks/workforce/requests/$_requestId/assign'),
  ]) {
    testWidgets('the $name page fits a 360px phone', (tester) async {
      _size(tester, const Size(360, 800));
      final rpc = _FakeRpc({
        'v1_wf_get_overview': (_) => _overview(),
        'v1_wf_list_requests': (_) => _register([_request()]),
        'v1_wf_get_request': (_) => _request(
          state: 'approved',
          owner: 'pr',
          access: _requestAccess(fulfil: true, cancel: true),
        ),
        'v1_wf_request_options': (_) => _options(officer: true),
      });
      await _pump(tester, rpc, location);
      expect(tester.takeException(), isNull);
    });
  }

  group('screenshots (desktop and 360px phone)', () {
    setUpAll(loadAccountsV2GoldenFonts);

    final handlers =
        <String, FutureOr<Map<String, dynamic>> Function(Map<String, Object?>)>{
          'v1_wf_get_overview': (_) => _overview(),
          'v1_wf_list_requests': (_) => _register([
            _request(access: _requestAccess(decide: true)),
            {
              ..._request(
                state: 'partially_fulfilled',
                owner: 'pr',
                assigned: [
                  {
                    'worker_id': 'w0',
                    'number': 'W-0',
                    'name': 'Gul Zaman',
                    'designation': 'Duct fitter',
                    'crew_name': 'Sweihan site crew',
                  },
                ],
              ),
              'id': '7c000000-0000-4000-8000-000000000002',
              'number': 'CRQ-2026-0002',
              'overdue': true,
            },
          ]),
          'v1_wf_get_request': (_) => _request(
            state: 'partially_fulfilled',
            owner: 'pr',
            access: _requestAccess(fulfil: true),
            assigned: [
              {
                'worker_id': 'w0',
                'number': 'W-0',
                'name': 'Gul Zaman',
                'designation': 'Duct fitter',
                'crew_name': 'Sweihan site crew',
              },
            ],
          ),
          'v1_wf_request_options': (_) => _options(officer: true),
        };

    Future<void> shot(
      WidgetTester tester,
      Size size,
      String location,
      String name,
    ) async {
      _size(tester, size);
      await _pump(tester, _FakeRpc(handlers), location);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/workforce_center_$name.png'),
      );
    }

    testWidgets('desktop center', (tester) async {
      await shot(
        tester,
        const Size(1280, 900),
        RoutePaths.yorksV1Workforce,
        'desktop_my_work',
      );
    });
    testWidgets('desktop requests', (tester) async {
      await shot(
        tester,
        const Size(1280, 900),
        '${RoutePaths.yorksV1Workforce}?view=requests',
        'desktop_requests',
      );
    });
    testWidgets('phone center', (tester) async {
      await shot(
        tester,
        const Size(360, 800),
        RoutePaths.yorksV1Workforce,
        'phone_my_work',
      );
    });
    testWidgets('desktop request', (tester) async {
      await shot(
        tester,
        const Size(1280, 1000),
        '/yorks/workforce/requests/$_requestId',
        'desktop_request',
      );
    });
    testWidgets('phone request', (tester) async {
      await shot(
        tester,
        const Size(360, 800),
        '/yorks/workforce/requests/$_requestId',
        'phone_request',
      );
    });
    testWidgets('desktop request form', (tester) async {
      await shot(
        tester,
        const Size(1280, 1000),
        RoutePaths.yorksV1WorkforceRequestNew,
        'desktop_form',
      );
    });
    testWidgets('phone register', (tester) async {
      await shot(
        tester,
        const Size(360, 800),
        RoutePaths.yorksV1WorkforceRequests,
        'phone_register',
      );
    });
    testWidgets('phone request form', (tester) async {
      await shot(
        tester,
        const Size(360, 800),
        RoutePaths.yorksV1WorkforceRequestNew,
        'phone_form',
      );
    });
    testWidgets('desktop approve and assign', (tester) async {
      _size(tester, const Size(1280, 1000));
      await _pump(
        tester,
        _FakeRpc({
          ...handlers,
          'v1_wf_get_request': (_) => _request(
            access: _requestAccess(decide: true),
            lines: _namedLines(),
            trades: _namedTrades,
          ),
        }),
        '/yorks/workforce/requests/$_requestId/assign',
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/workforce_center_desktop_approve_assign.png',
        ),
      );
    });
    testWidgets('phone request named, waiting for approval', (tester) async {
      _size(tester, const Size(360, 800));
      await _pump(
        tester,
        _FakeRpc({
          ...handlers,
          'v1_wf_get_request': (_) => _request(
            access: _requestAccess(decide: true),
            lines: _namedLines(),
            trades: _namedTrades,
          ),
        }),
        '/yorks/workforce/requests/$_requestId',
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/workforce_center_phone_request_named.png'),
      );
    });
    testWidgets('phone request on site', (tester) async {
      _size(tester, const Size(360, 800));
      await _pump(
        tester,
        _FakeRpc({
          ...handlers,
          'v1_wf_get_request': (_) => _request(
            state: 'fulfilled',
            owner: 'requester',
            access: _requestAccess(finish: true),
            onCrew: true,
          ),
        }),
        '/yorks/workforce/requests/$_requestId',
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/workforce_center_phone_request_on_site.png'),
      );
    });
    testWidgets('phone form, a person by name', (tester) async {
      _size(tester, const Size(360, 800));
      await _pump(
        tester,
        _FakeRpc({
          ...handlers,
          'v1_wf_request_options': (_) => _options(named: true),
        }),
        RoutePaths.yorksV1WorkforceRequestNew,
      );
      await _tap(tester, find.byKey(const ValueKey('crew-request-continue')));
      await tester.enterText(
        find.byKey(const ValueKey('crew-request-trade-0')),
        'ra',
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/workforce_center_phone_form_suggest.png'),
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('crew-request-suggest-worker-0-w3')),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/workforce_center_phone_form_named.png'),
      );
    });
    testWidgets('phone assign', (tester) async {
      await shot(
        tester,
        const Size(360, 800),
        '/yorks/workforce/requests/$_requestId/assign',
        'phone_assign',
      );
    });
  });
}

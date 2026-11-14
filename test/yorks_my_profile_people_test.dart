// My Yorks from the People record (PRODUCT_DECISIONS section 54): the Me,
// Work and Settings tabs, the person's own documents, and a note to HR/PRO.
// Fictional fixtures only.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/engineer/presentation/screens/engineer_profile_screen.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_my_profile.dart';
import 'package:material_ledger/shared/models/yorks_v1_my_profile_workspace.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_workspace_status.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_my_profile_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_my_profile_workspace_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_people_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_workspace_status_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_my_profile_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_my_profile_workspace_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_people_repository.dart';
import 'package:material_ledger/shared/services/app_config_service.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'support/accounts_v2_golden_fonts.dart';

const _actor = '10000000-0000-4000-8000-000000000002';
const _role = YorksV1Role.siteEngineer;

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
  peopleRecords: true,
);

Map<String, Object?> _mine({bool linked = true}) => {
  'state': linked ? 'linked' : 'unlinked',
  'today': '2026-11-14',
  'person': linked
      ? {
          'id': '7b000000-0000-4000-8000-000000000041',
          'number': 'WR-000041',
          'name': 'TEST ENGINEER ONE',
          'arabic_name': 'مهندس تجريبي',
          'company': 'Example Contracting LLC',
          'position': 'Site Engineer',
          'id_profession': 'Civil Engineer',
          'category': 'staff',
          'status': 'active',
          'joining_date': '2025-03-01',
          'attention': 'expiring',
          'documents': [
            {
              'kind': 'visa',
              'number_last4': '6789',
              'expiry_date': '2027-03-12',
              'days_left': 118,
              'status': 'ok',
            },
            {
              'kind': 'labour_card',
              'number_last4': '4410',
              'expiry_date': '2026-12-25',
              'days_left': 41,
              'status': 'expiring',
            },
            {
              'kind': 'passport',
              'number_last4': null,
              'expiry_date': '2031-06-04',
              'days_left': 1663,
              'status': 'ok',
            },
            {
              'kind': 'cicpa_pass',
              'number_last4': '0001',
              'expiry_date': '2027-01-18',
              'days_left': 65,
              'status': 'ok',
              'sites': 'Ruwais, Habshan',
            },
          ],
          'crew': {'id': 'crew-1', 'name': 'Example Crew A'},
          'attendance': {
            'month': '2026-11',
            'recorded_days': 12,
            'present_days': 11,
            'absent_days': 1,
            'leave_days': 0,
            'off_days': 0,
            'worked_minutes': 5700,
            'overtime_minutes': 390,
          },
          'notes': <Object?>[],
        }
      : null,
  'projects': [
    {
      'id': 'p0000000-0000-4000-8000-000000000001',
      'ref': 'PRJ-101',
      'name': 'Example Tower',
      'state': 'active',
      'role': 'site_engineer',
    },
    {
      'id': 'p0000000-0000-4000-8000-000000000002',
      'ref': 'PRJ-102',
      'name': 'Example Villas',
      'state': 'active',
      'role': 'project_engineer',
    },
  ],
};

void main() {
  setUpAll(loadAccountsV2GoldenFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a linked person opens on Me with their own documents', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    await _pumpProfile(
      tester,
      _FakeRpc({'v1_people_get_mine': (_) => _mine()}),
    );

    // The header comes from the People record.
    expect(find.text('مهندس تجريبي'), findsOneWidget);
    expect(find.text('Site Engineer · Staff'), findsOneWidget);
    expect(find.text('WR-000041 · Example Contracting LLC'), findsOneWidget);
    expect(find.text('1 expiring soon'), findsOneWidget);
    // The email moves to Settings once the record is linked.
    expect(find.text('engineer@example.test'), findsNothing);

    expect(find.byKey(const ValueKey('my-yorks-documents')), findsOneWidget);
    expect(find.text('ends 6789'), findsOneWidget);
    expect(find.text('41 days left'), findsOneWidget);
    expect(find.text('ends 0001 · Ruwais, Habshan'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('my-yorks-id-profession')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Civil Engineer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Work shows projects and this month; Settings the account', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    await _pumpProfile(
      tester,
      _FakeRpc({'v1_people_get_mine': (_) => _mine()}),
    );

    await _openTab(tester, 'work');
    await tester.ensureVisible(
      find.byKey(const ValueKey('my-yorks-attendance')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Example Tower'), findsOneWidget);
    expect(find.text('PRJ-102 · Project Engineer'), findsOneWidget);
    expect(find.text('11 of 12'), findsOneWidget);
    expect(find.text('6 h 30 min'), findsOneWidget);

    await _openTab(tester, 'settings');
    expect(find.byKey(const ValueKey('my-yorks-account')), findsOneWidget);
    expect(find.text('engineer@example.test'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a note to HR/PRO waits for the server, then shows as sent', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    final rpc = _FakeRpc({
      'v1_people_get_mine': (_) => _mine(),
      'v1_people_send_note': (_) => _mine(),
    });
    await _pumpProfile(tester, rpc);
    await tester.ensureVisible(find.byKey(const ValueKey('my-yorks-tell-hr')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('my-yorks-tell-hr')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('attendance-text-dialog-field')),
      'My labour card was renewed',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();

    final call = rpc.callsTo('v1_people_send_note').single;
    expect(call['p_message'], 'My labour card was renewed');
    expect(call['p_idempotency_key'], isNotEmpty);
    expect(find.text('Sent to HR/PRO'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a sixth note in a day is refused in the dialog', (tester) async {
    await _setViewport(tester, const Size(390, 844));
    final rpc = _FakeRpc({
      'v1_people_get_mine': (_) => _mine(),
      'v1_people_send_note': (_) => throw const PostgrestException(
        message: 'V1_PEOPLE_NOTE_LIMIT',
        code: '22023',
      ),
    });
    await _pumpProfile(tester, rpc);
    await tester.ensureVisible(find.byKey(const ValueKey('my-yorks-tell-hr')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('my-yorks-tell-hr')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('attendance-text-dialog-field')),
      'Another note',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();
    expect(
      find.text('You have sent five notes today. Try again tomorrow.'),
      findsOneWidget,
    );
    expect(find.text('Sent to HR/PRO'), findsNothing);
  });

  testWidgets('before a link the page opens on Work and Me says why', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    await _pumpProfile(
      tester,
      _FakeRpc({'v1_people_get_mine': (_) => _mine(linked: false)}),
    );
    expect(find.byKey(const ValueKey('my-yorks-tab-work')), findsOneWidget);
    // The email stays in the header until the record is linked.
    expect(find.text('engineer@example.test'), findsOneWidget);
    await _openTab(tester, 'me');
    expect(find.text('Not linked to your People record yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('my-yorks-documents')), findsNothing);
  });

  testWidgets('a failed read offers a retry, never an empty record', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    var calls = 0;
    await _pumpProfile(
      tester,
      _FakeRpc({
        'v1_people_get_mine': (_) {
          calls++;
          if (calls == 1) {
            throw const PostgrestException(message: 'down', code: 'PGRST002');
          }
          return _mine();
        },
      }),
    );
    await _openTab(tester, 'me');
    expect(find.text('Your record could not be loaded'), findsOneWidget);
    await tester.tap(find.text('Try again').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('my-yorks-documents')), findsOneWidget);
  });

  for (final visual in const [
    (name: 'phone_me_390x844', size: Size(390, 844), language: 'en'),
    (name: 'phone_me_360x800', size: Size(360, 800), language: 'en'),
    (name: 'phone_me_rtl_ar_390x844', size: Size(390, 844), language: 'ar'),
    (name: 'desktop_1440x900', size: Size(1440, 900), language: 'en'),
  ]) {
    testWidgets('My Yorks visual ${visual.name}', (tester) async {
      SharedPreferences.setMockInitialValues({
        'selected_language': visual.language,
      });
      await _setViewport(tester, visual.size);
      await _pumpProfile(
        tester,
        _FakeRpc({'v1_people_get_mine': (_) => _mine()}),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/my_yorks_people/${visual.name}.png'),
      );
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _openTab(WidgetTester tester, String section) async {
  final tab = find.byKey(ValueKey('my-yorks-section-$section'));
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

Future<void> _pumpProfile(WidgetTester tester, _FakeRpc rpc) async {
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksV1AuthUserIdProvider.overrideWithValue(_actor),
        yorksV1CurrentRoleProvider.overrideWithValue(_role),
        yorksV1FeatureFlagsProvider.overrideWithValue(_flags),
        yorksV1MyProfileRepositoryProvider.overrideWithValue(
          const _ProfileRepository(),
        ),
        yorksV1MyProfileWorkspaceRepositoryProvider.overrideWithValue(
          const _WorkspaceRepository(),
        ),
        yorksV1PeopleRepositoryProvider.overrideWithValue(
          YorksV1PeopleRepository(
            featureFlags: _flags,
            connectivity: const _Online(),
            client: rpc,
          ),
        ),
        yorksV1WorkspaceStatusProvider.overrideWithValue(
          const YorksV1WorkspaceStatus(
            state: YorksV1WorkspaceConnectionState.connected,
          ),
        ),
        appVersionProvider.overrideWithValue(
          const AppVersionInfo(version: '1.0.0', build: 35),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const EngineerProfileScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _FakeRpc implements YorksV1PeopleRpcClient {
  _FakeRpc(this.handlers);

  final Map<String, FutureOr<Object?> Function(Map<String, Object?>)> handlers;
  final calls = <(String, Map<String, Object?>)>[];

  List<Map<String, Object?>> callsTo(String name) => [
    for (final (function, parameters) in calls)
      if (function == name) parameters,
  ];

  @override
  Future<Object?> rpc(
    String functionName,
    Map<String, Object?> parameters,
  ) async {
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

class _ProfileRepository implements YorksV1MyProfileRepository {
  const _ProfileRepository();

  @override
  Future<YorksV1MyProfile> load({
    required String expectedAuthUserId,
    required YorksV1Role expectedRole,
    int projectOffset = 0,
    int projectLimit = 25,
  }) async => YorksV1MyProfile.fromRpcJson({
    'schema_version': 1,
    'generated_at': '2026-11-14T00:00:00Z',
    'next_transition_at': null,
    'permission_revision': 4,
    'account': {
      'auth_user_id': _actor,
      'app_user_id': 'usr-engineer',
      'display_name': 'Test Engineer',
      'email': 'engineer@example.test',
      'exact_role': expectedRole.claimValue,
      'status': 'active',
      'workspace_key': expectedRole.claimValue,
    },
    'work_identity': {
      'legacy_employee': {'state': 'not_projected'},
      'workforce_worker': {
        'state': 'unlinked',
        'worker_id': null,
        'grants_self_service': false,
      },
    },
    'projects': {
      'total': 0,
      'offset': 0,
      'has_more': false,
      'items': <Object?>[],
    },
    'capabilities': <Object?>[
      for (final key in const ['projects.view', 'material_requests.view'])
        {
          'capability_key': key,
          'authorization_mode': 'enforced',
          'requires_record_check': true,
          'organization': {'effective': true, 'source': 'role_default'},
          'projects': <Object?>[],
        },
    ],
    'actions': <Object?>[
      {
        'action_id': 'open_projects',
        'capability_key': 'projects.view',
        'required_feature': 'projects',
        'kind': 'navigation',
      },
      {
        'action_id': 'open_material_requests',
        'capability_key': 'material_requests.view',
        'required_feature': 'requests',
        'kind': 'navigation',
      },
    ],
    'operational_summary_state': 'not_projected',
    'workforce_scope_state': 'requires_work_date_context',
  });
}

class _WorkspaceRepository implements YorksV1MyProfileWorkspaceRepository {
  const _WorkspaceRepository();

  @override
  Future<YorksV1MyProfileWorkspace> load({
    required String expectedAuthUserId,
    required YorksV1Role expectedRole,
    required int expectedPermissionRevision,
  }) async => YorksV1MyProfileWorkspace.fromRpcJson({
    'schema_version': 1,
    'generated_at': '2026-11-14T00:00:00Z',
    'next_transition_at': null,
    'permission_revision': 4,
    'account': {'auth_user_id': _actor, 'exact_role': expectedRole.claimValue},
    'today': {
      'state': 'available',
      'metrics': <Object?>[
        {'metric_key': 'technical_projects', 'value': 2},
        {'metric_key': 'material_requests_needing_action', 'value': 3},
        {'metric_key': 'material_requests_open', 'value': 8},
      ],
    },
    'access_scope': {
      'technical_project_count': 2,
      'accounts_project_count': 0,
      'active_direct_membership_count': 2,
      'effective_source_kinds': <Object?>['direct_membership'],
      'accounts_portfolio_available': false,
    },
    'work_identity': {
      'legacy_employee': {'state': 'not_projected'},
      'workforce_worker': {
        'state': 'unlinked',
        'worker_id': null,
        'worker_number': null,
        'display_name': null,
        'designation': null,
        'department': null,
        'worker_type': null,
        'current_status': null,
        'grants_self_service': false,
      },
    },
  });
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

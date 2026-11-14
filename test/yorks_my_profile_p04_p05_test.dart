import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/app/router.dart';
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
import 'package:material_ledger/shared/providers/yorks_v1_workspace_status_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_my_profile_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_my_profile_workspace_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_permission_repository.dart';
import 'package:material_ledger/shared/services/app_config_service.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _actor = '10000000-0000-4000-8000-000000000004';
const _project = 'bc040000-0000-4000-8000-000000000001';

const _fullFlags = YorksV1FeatureFlags(
  foundation: true,
  projects: true,
  boq: true,
  excel: true,
  requests: true,
  arrangement: true,
  logistics: true,
  returnsDocuments: true,
  documents: true,
  accounts: true,
  analytics: true,
  teamChat: true,
  inventorySuppliers: true,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('P04/P05 workspace model accepts only its safe response shape', () {
    final workspace = YorksV1MyProfileWorkspace.fromRpcJson(_workspaceJson());
    expect(workspace.authUserId, _actor);
    expect(workspace.exactRole, YorksV1Role.admin);
    expect(workspace.permissionRevision, 4);
    expect(workspace.today.metrics, hasLength(4));
    expect(workspace.accessScope.accountsPortfolioAvailable, true);
    expect(workspace.workIdentity.worker.isLinked, true);
    expect(workspace.workIdentity.worker.workerNumber, 'WK-004');
  });

  final corruptions = <String, void Function(Map<String, dynamic>)>{
    'commercial field': (json) => json['unit_cost'] = 10,
    'employee field': (json) =>
        json['work_identity']['workforce_worker']['salary'] = 10,
    'worker self-service': (json) =>
        json['work_identity']['workforce_worker']['grants_self_service'] = true,
    'unknown metric': (json) =>
        json['today']['metrics'][0]['metric_key'] = 'hours_worked',
    'negative count': (json) =>
        json['access_scope']['technical_project_count'] = -1,
    'identity mismatch field': (json) =>
        json['account']['workspace_key'] = 'admin',
    'legacy employee payload': (json) =>
        json['work_identity']['legacy_employee']['employee_id'] = 'legacy-1',
    'unlinked worker data': (json) {
      json['work_identity']['workforce_worker'] = {
        'state': 'unlinked',
        'worker_id': null,
        'worker_number': 'WK-004',
        'display_name': null,
        'designation': null,
        'department': null,
        'worker_type': null,
        'current_status': null,
        'grants_self_service': false,
      };
    },
  };
  for (final corruption in corruptions.entries) {
    test('P04/P05 rejects ${corruption.key}', () {
      final json = _workspaceJson();
      corruption.value(json);
      expect(
        () => YorksV1MyProfileWorkspace.fromRpcJson(json),
        throwsFormatException,
      );
    });
  }

  group('workspace repository', () {
    late DefaultConnectivity connectivity;
    late _FakeRpc rpc;
    late YorksV1SupabaseMyProfileWorkspaceRepository repository;

    setUp(() {
      connectivity = DefaultConnectivity();
      rpc = _FakeRpc();
      repository = YorksV1SupabaseMyProfileWorkspaceRepository(
        enabled: true,
        connectivity: connectivity,
        rpc: rpc,
      );
    });
    tearDown(() => connectivity.dispose());

    Future<YorksV1MyProfileWorkspace> load() => repository.load(
      expectedAuthUserId: _actor,
      expectedRole: YorksV1Role.admin,
      expectedPermissionRevision: 4,
    );

    test('calls the no-argument self RPC and cross-binds P01', () async {
      expect((await load()).authUserId, _actor);
      expect(rpc.functionName, 'v1_get_my_yorks_profile_workspace');
      expect(rpc.parameters, isEmpty);
    });

    test('identity, role, and revision mismatches fail closed', () async {
      for (final change in <void Function(Map<String, dynamic>)>[
        (json) => json['account']['auth_user_id'] = _project,
        (json) => json['account']['exact_role'] = 'accountant',
        (json) => json['permission_revision'] = 5,
      ]) {
        final json = _workspaceJson();
        change(json);
        rpc.response = json;
        await expectLater(
          load(),
          throwsA(
            isA<Exception>().having(
              (error) => error.toString(),
              'message',
              contains('unexpectedResponse'),
            ),
          ),
        );
      }
    });

    test('offline, denied, and timeout paths retain no stale value', () async {
      connectivity.setOnline(false);
      await expectLater(load(), throwsA(isA<Exception>()));
      expect(rpc.functionName, isNull);
      connectivity.setOnline(true);

      rpc.error = const PostgrestException(message: 'denied', code: '42501');
      await expectLater(load(), throwsA(isA<Exception>()));

      rpc.error = null;
      rpc.pending = Completer<Object?>();
      repository = YorksV1SupabaseMyProfileWorkspaceRepository(
        enabled: true,
        connectivity: connectivity,
        rpc: rpc,
        timeout: Duration.zero,
      );
      await expectLater(load(), throwsA(isA<Exception>()));
      rpc.pending!.complete(_workspaceJson());
    });
  });

  testWidgets(
    'confirmed metrics, scope, work identity, and protected actions render',
    (tester) async {
      await _setViewport(tester, const Size(1180, 820));
      await _pumpProfile(tester);

      expect(find.text('Projects you can open'), findsOneWidget);
      expect(find.text('7'), findsNWidgets(2));
      expect(find.text('Direct grant'), findsOneWidget);
      expect(find.text('WK-004'), findsOneWidget);
      expect(find.text('Temporary worker'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('my-yorks-action-open_projects')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('my-yorks-action-open_accounts')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'project-only Accounts claim cannot expose the portfolio action or metric',
    (tester) async {
      await _setViewport(tester, const Size(390, 844));
      await _pumpProfile(
        tester,
        workspace: _WorkspaceRepository(
          workspace: YorksV1MyProfileWorkspace.fromRpcJson(
            _workspaceJson(accountsPortfolioAvailable: false),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('my-yorks-action-open_accounts')),
        findsNothing,
      );
      expect(find.text('Accounts projects'), findsNothing);
      await _openTab(tester, 'settings');
      expect(find.text('Linked Workforce record'), findsOneWidget);
    },
  );

  testWidgets('feature flags remove a shortcut without inventing denial copy', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    await _pumpProfile(
      tester,
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
        analytics: false,
      ),
    );
    expect(
      find.byKey(const ValueKey('my-yorks-action-open_analytics')),
      findsNothing,
    );
    expect(find.text('Analytics'), findsNothing);
  });

  testWidgets(
    'workspace error shows honest retry states and no summary value',
    (tester) async {
      await _setViewport(tester, const Size(390, 844));
      await _pumpProfile(
        tester,
        workspace: _WorkspaceRepository(error: StateError('offline')),
      );

      // Work shows Today; Settings shows access and work identity.
      expect(
        find.text('Your workspace details are unavailable'),
        findsOneWidget,
      );
      expect(find.text('7'), findsNothing);
      expect(find.text('Try again'), findsAtLeastNWidgets(1));
      await _openTab(tester, 'settings');
      expect(
        find.text('Your workspace details are unavailable'),
        findsNWidgets(2),
      );
    },
  );

  testWidgets('unlinked worker remains a valid Yorks account', (tester) async {
    await _setViewport(tester, const Size(390, 844));
    await _pumpProfile(
      tester,
      workspace: _WorkspaceRepository(
        workspace: YorksV1MyProfileWorkspace.fromRpcJson(
          _workspaceJson(linked: false),
        ),
      ),
    );
    await _openTab(tester, 'settings');
    expect(find.text('No Workforce record is linked'), findsOneWidget);
    expect(find.text('Verified account'), findsOneWidget);
    expect(find.text('WK-004'), findsNothing);
  });

  testWidgets('inventory action uses the generic protected inventory route', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1024, 768));
    final router = GoRouter(
      initialLocation: RoutePaths.engineerProfile,
      routes: [
        GoRoute(
          path: RoutePaths.engineerProfile,
          builder: (_, _) => const EngineerProfileScreen(),
        ),
        GoRoute(
          path: RoutePaths.yorksV1Inventory,
          builder: (_, _) => const Scaffold(body: Text('GENERIC INVENTORY')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await _pumpProfile(tester, router: router);
    await tester.drag(
      find.byKey(const ValueKey('canonical-my-yorks-page')),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('my-yorks-action-open_inventory')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('my-yorks-action-open_inventory')),
    );
    await tester.pumpAndSettle();
    expect(find.text('GENERIC INVENTORY'), findsOneWidget);
  });
}

/// Opens a My Yorks tab on phone and tablet.
Future<void> _openTab(WidgetTester tester, String section) async {
  final tab = find.byKey(ValueKey('my-yorks-section-$section'));
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

Future<void> _pumpProfile(
  WidgetTester tester, {
  YorksV1MyProfileRepository profile = const _ProfileRepository(),
  YorksV1MyProfileWorkspaceRepository workspace = const _WorkspaceRepository(),
  YorksV1FeatureFlags flags = _fullFlags,
  GoRouter? router,
}) async {
  final preferences = await SharedPreferences.getInstance();
  final home = ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      yorksV1AuthUserIdProvider.overrideWithValue(_actor),
      yorksV1CurrentRoleProvider.overrideWithValue(YorksV1Role.admin),
      yorksV1FeatureFlagsProvider.overrideWithValue(flags),
      yorksV1MyProfileRepositoryProvider.overrideWithValue(profile),
      yorksV1MyProfileWorkspaceRepositoryProvider.overrideWithValue(workspace),
      yorksV1WorkspaceStatusProvider.overrideWithValue(
        const YorksV1WorkspaceStatus(
          state: YorksV1WorkspaceConnectionState.connected,
        ),
      ),
      appVersionProvider.overrideWithValue(
        const AppVersionInfo(version: '1.0.0', build: 35),
      ),
    ],
    child: router == null
        ? MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const EngineerProfileScreen(),
          )
        : MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            routerConfig: router,
          ),
  );
  await tester.pumpWidget(home);
  await tester.pumpAndSettle();
}

class _ProfileRepository implements YorksV1MyProfileRepository {
  const _ProfileRepository();

  @override
  Future<YorksV1MyProfile> load({
    required String expectedAuthUserId,
    required YorksV1Role expectedRole,
    int projectOffset = 0,
    int projectLimit = 25,
  }) async => YorksV1MyProfile.fromRpcJson(_profileJson());
}

class _WorkspaceRepository implements YorksV1MyProfileWorkspaceRepository {
  const _WorkspaceRepository({this.workspace, this.error});

  final YorksV1MyProfileWorkspace? workspace;
  final Object? error;

  @override
  Future<YorksV1MyProfileWorkspace> load({
    required String expectedAuthUserId,
    required YorksV1Role expectedRole,
    required int expectedPermissionRevision,
  }) async {
    if (error != null) throw error!;
    return workspace ?? YorksV1MyProfileWorkspace.fromRpcJson(_workspaceJson());
  }
}

class _FakeRpc implements YorksV1PermissionRpcClient {
  Object? response = _workspaceJson();
  Object? error;
  Completer<Object?>? pending;
  String? functionName;
  Map<String, Object?>? parameters;

  @override
  Future<Object?> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async {
    this.functionName = functionName;
    this.parameters = parameters;
    if (error != null) throw error!;
    return pending == null ? response : pending!.future;
  }
}

Map<String, dynamic> _profileJson() {
  final actionIds = YorksV1MyProfileAction.contracts.keys.toList();
  return {
    'schema_version': 1,
    'generated_at': '2026-09-05T00:00:00Z',
    'next_transition_at': null,
    'permission_revision': 4,
    'account': {
      'auth_user_id': _actor,
      'app_user_id': 'usr-owner',
      'display_name': 'Owner',
      'email': 'owner@example.test',
      'exact_role': 'admin',
      'status': 'active',
      'workspace_key': 'admin',
    },
    'work_identity': {
      'legacy_employee': {'state': 'not_projected'},
      'workforce_worker': {
        'state': 'linked',
        'worker_id': _project,
        'grants_self_service': false,
      },
    },
    'projects': {
      'total': 0,
      'offset': 0,
      'has_more': false,
      'items': <Object?>[],
    },
    'capabilities': [
      for (final actionId in actionIds)
        {
          'capability_key': YorksV1MyProfileAction.contracts[actionId]!.$1,
          'authorization_mode': 'enforced',
          'requires_record_check': true,
          'organization': {'effective': true, 'source': 'role_default'},
          'projects': <Object?>[],
        },
    ],
    'actions': [
      for (final actionId in actionIds)
        {
          'action_id': actionId,
          'capability_key': YorksV1MyProfileAction.contracts[actionId]!.$1,
          'required_feature': YorksV1MyProfileAction.contracts[actionId]!.$2,
          'kind': 'navigation',
        },
    ],
    'operational_summary_state': 'not_projected',
    'workforce_scope_state': 'requires_work_date_context',
  };
}

Map<String, dynamic> _workspaceJson({
  bool accountsPortfolioAvailable = true,
  bool linked = true,
}) => {
  'schema_version': 1,
  'generated_at': '2026-09-05T00:00:00Z',
  'next_transition_at': null,
  'permission_revision': 4,
  'account': {'auth_user_id': _actor, 'exact_role': 'admin'},
  'today': {
    'state': 'available',
    'metrics': [
      {'metric_key': 'technical_projects', 'value': 7},
      {'metric_key': 'material_requests_needing_action', 'value': 3},
      {'metric_key': 'material_requests_open', 'value': 8},
      {'metric_key': 'accounts_projects', 'value': 6},
    ],
  },
  'access_scope': {
    'technical_project_count': 7,
    'accounts_project_count': 6,
    'active_direct_membership_count': 2,
    'effective_source_kinds': ['role_default', 'explicit_grant'],
    'accounts_portfolio_available': accountsPortfolioAvailable,
  },
  'work_identity': {
    'legacy_employee': {'state': 'not_projected'},
    'workforce_worker': linked
        ? {
            'state': 'linked',
            'worker_id': _project,
            'worker_number': 'WK-004',
            'display_name': 'Owner Work Record',
            'designation': 'Director',
            'department': 'Management',
            'worker_type': 'temporary_worker',
            'current_status': 'active',
            'grants_self_service': false,
          }
        : {
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
};

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

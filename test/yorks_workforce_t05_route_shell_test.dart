import 'dart:io';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/app/router.dart';
import 'package:material_ledger/app/yorks_v1_workspace_search.dart';
import 'package:material_ledger/app/yorks_v1_workspace_shell.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/app_user.dart';
import 'package:material_ledger/shared/models/user_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_permission_management.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_shell_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_workforce_strings.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_permission_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  setUpAll(() async {
    final font = FontLoader('NexusSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    await font.load();
    var cache = File(Platform.resolvedExecutable).parent;
    for (
      var i = 0;
      i < 5 && !Directory('${cache.path}/artifacts').existsSync();
      i++
    ) {
      cache = cache.parent;
    }
    await (FontLoader('MaterialIcons')..addFont(
          Future.value(
            ByteData.sublistView(
              await File(
                '${cache.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytes(),
            ),
          ),
        ))
        .load();
  });

  for (final width in [360.0, 1366.0]) {
    testWidgets('Workforce internal sections at $width', (tester) async {
      _setViewport(tester, Size(width, 800));
      addTearDown(() => _resetViewport(tester));
      await _mountShell(
        tester,
        allowWorkforceView: true,
        allowWorkersManage: true,
        initialPath: RoutePaths.yorksV1Workforce,
      );
      final sections = find.byKey(
        const ValueKey('workspace-internal-sections'),
      );
      expect(sections, findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/workforce_sections_${width.toInt()}.png'),
      );
      if (width == 360) {
        await tester.tap(
          find.descendant(
            of: sections,
            matching: find.byType(DropdownButton<String>),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(YorksV1ShellStrings.workforceAdministration.primary),
          findsWidgets,
        );
      } else {
        expect(
          find.descendant(
            of: sections,
            matching: find.text(
              YorksV1ShellStrings.workforceAdministration.primary,
            ),
          ),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
  test('Timesheets shell and monthly labels cover every app language', () {
    expect(
      AppLanguage.values
          .map(YorksV1ShellStrings.workforceTimesheets.active)
          .toSet(),
      hasLength(AppLanguage.values.length),
    );
    expect(
      AppLanguage.values
          .map(
            (language) =>
                YorksV1WorkforceStrings.text(language, 'monthly_timesheets'),
          )
          .toSet(),
      hasLength(AppLanguage.values.length),
    );
  });

  testWidgets('Workforce routes fail closed while the rollout flag is off', (
    tester,
  ) async {
    final router = _router(workforceEnabled: false, allowWorkforceView: true);
    addTearDown(router.dispose);
    await _mountRouter(tester, router, workforceEnabled: false);

    for (final path in const [
      RoutePaths.yorksV1Workforce,
      RoutePaths.yorksV1WorkforceAdministration,
      RoutePaths.yorksV1WorkforceAttendance,
      RoutePaths.yorksV1WorkforceTimesheets,
    ]) {
      await _go(tester, router, path);
      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.engineerHome,
      );
    }
  });

  testWidgets(
    'Workforce view capability is mandatory and another Workforce grant is insufficient',
    (tester) async {
      final router = _router(workforceEnabled: true, allowWorkforceView: false);
      addTearDown(router.dispose);
      await _mountRouter(tester, router, workforceEnabled: true);

      for (final path in const [
        RoutePaths.yorksV1WorkforceAttendance,
        RoutePaths.yorksV1WorkforceTimesheets,
      ]) {
        await _go(tester, router, path);
        expect(
          router.routeInformationProvider.value.uri.path,
          RoutePaths.engineerHome,
        );
      }
    },
  );

  testWidgets(
    'authorized Workforce root opens the capability-guarded T10 overview',
    (tester) async {
      final decisions = <({String key, bool organizationSummary})>[];
      final router = _router(
        workforceEnabled: true,
        resolver:
            (
              capabilityKey, {
              required legacyAllowed,
              requireWrite = false,
              organizationSummary = false,
              projectId,
            }) {
              decisions.add((
                key: capabilityKey,
                organizationSummary: organizationSummary,
              ));
              return capabilityKey == YorksV1CapabilityKeys.workforceView;
            },
      );
      addTearDown(router.dispose);
      await _mountRouter(tester, router, workforceEnabled: true);

      await _go(tester, router, RoutePaths.yorksV1Workforce);
      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.yorksV1Workforce,
      );
      expect(
        decisions,
        contains((
          key: YorksV1CapabilityKeys.workforceView,
          organizationSummary: true,
        )),
      );
    },
  );

  testWidgets(
    'Workforce Administration requires view plus one management capability',
    (tester) async {
      final deniedRouter = _router(
        workforceEnabled: true,
        resolver:
            (
              capabilityKey, {
              required legacyAllowed,
              requireWrite = false,
              organizationSummary = false,
              projectId,
            }) => capabilityKey == YorksV1CapabilityKeys.workforceView,
      );
      addTearDown(deniedRouter.dispose);
      await _mountRouter(tester, deniedRouter, workforceEnabled: true);
      await _go(
        tester,
        deniedRouter,
        RoutePaths.yorksV1WorkforceAdministration,
      );
      expect(
        deniedRouter.routeInformationProvider.value.uri.path,
        RoutePaths.engineerHome,
      );

      final allowedRouter = _router(
        workforceEnabled: true,
        resolver:
            (
              capabilityKey, {
              required legacyAllowed,
              requireWrite = false,
              organizationSummary = false,
              projectId,
            }) =>
                capabilityKey == YorksV1CapabilityKeys.workforceView ||
                capabilityKey == YorksV1CapabilityKeys.workforceWorkersManage,
      );
      addTearDown(allowedRouter.dispose);
      await _mountRouter(tester, allowedRouter, workforceEnabled: true);
      await _go(
        tester,
        allowedRouter,
        RoutePaths.yorksV1WorkforceAdministration,
      );
      expect(
        allowedRouter.routeInformationProvider.value.uri.path,
        RoutePaths.yorksV1WorkforceAdministration,
      );
    },
  );

  testWidgets(
    'project-scoped Workforce grant opens attendance without technical project membership',
    (tester) async {
      final snapshot = _permissionSnapshot(
        allowWorkforceView: false,
        projectWorkforceView: true,
      );
      final router = _router(
        workforceEnabled: true,
        resolver: _resolverFrom(snapshot),
      );
      addTearDown(router.dispose);
      await _mountRouter(tester, router, workforceEnabled: true);

      await _go(tester, router, RoutePaths.yorksV1WorkforceAttendance);
      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.yorksV1WorkforceAttendance,
      );
    },
  );

  testWidgets('project-scoped Workforce explicit deny remains fail closed', (
    tester,
  ) async {
    final snapshot = _permissionSnapshot(
      allowWorkforceView: false,
      projectWorkforceView: false,
    );
    final router = _router(
      workforceEnabled: true,
      resolver: _resolverFrom(snapshot),
    );
    addTearDown(router.dispose);
    await _mountRouter(tester, router, workforceEnabled: true);

    await _go(tester, router, RoutePaths.yorksV1WorkforceAttendance);
    expect(
      router.routeInformationProvider.value.uri.path,
      RoutePaths.engineerHome,
    );
  });

  testWidgets(
    'authorized Timesheets deep link uses the same organization Workforce view guard',
    (tester) async {
      final decisions = <({String key, bool organizationSummary})>[];
      final router = _router(
        workforceEnabled: true,
        resolver:
            (
              capabilityKey, {
              required legacyAllowed,
              requireWrite = false,
              organizationSummary = false,
              projectId,
            }) {
              decisions.add((
                key: capabilityKey,
                organizationSummary: organizationSummary,
              ));
              return capabilityKey == YorksV1CapabilityKeys.workforceView;
            },
      );
      addTearDown(router.dispose);
      await _mountRouter(tester, router, workforceEnabled: true);

      await _go(tester, router, RoutePaths.yorksV1WorkforceTimesheets);
      expect(
        router.routeInformationProvider.value.uri.path,
        RoutePaths.yorksV1WorkforceTimesheets,
      );
      expect(
        decisions,
        contains((
          key: YorksV1CapabilityKeys.workforceView,
          organizationSummary: true,
        )),
      );
    },
  );

  testWidgets(
    'confirmed Workforce access adds one desktop destination and search target',
    (tester) async {
      _setViewport(tester, const Size(1366, 768));
      addTearDown(() => _resetViewport(tester));
      await _mountShell(tester, allowWorkforceView: true);

      expect(find.text(YorksV1ShellStrings.workforce.primary), findsOneWidget);

      await tester.tap(find.text(YorksV1ShellStrings.searchOrJump.primary));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(YorksV1WorkspaceSearchDialog),
          matching: find.text(YorksV1ShellStrings.workforce.primary),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'delegated manager receives a guarded Workforce administration destination',
    (tester) async {
      _setViewport(tester, const Size(1366, 768));
      addTearDown(() => _resetViewport(tester));
      await _mountShell(
        tester,
        allowWorkforceView: true,
        allowWorkersManage: true,
      );

      expect(
        find.text(YorksV1ShellStrings.workforceAdministration.primary),
        findsNothing,
      );
      await tester.tap(find.text(YorksV1ShellStrings.searchOrJump.primary));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(YorksV1WorkspaceSearchDialog),
          matching: find.text(
            YorksV1ShellStrings.workforceAdministration.primary,
          ),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Timesheets remains under one selected Workforce destination and is searchable',
    (tester) async {
      _setViewport(tester, const Size(1366, 768));
      addTearDown(() => _resetViewport(tester));
      await _mountShell(
        tester,
        allowWorkforceView: true,
        initialPath: RoutePaths.yorksV1WorkforceTimesheets,
      );

      final selectedWorkforce = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == YorksV1ShellStrings.workforce.primary &&
            widget.properties.selected == true,
      );
      expect(selectedWorkforce, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('workspace-internal-sections')),
          matching: find.text(YorksV1ShellStrings.workforceTimesheets.primary),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text(YorksV1ShellStrings.searchOrJump.primary));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(YorksV1WorkspaceSearchDialog),
          matching: find.text(YorksV1ShellStrings.workforceTimesheets.primary),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'denied Workforce access removes both navigation and search target',
    (tester) async {
      _setViewport(tester, const Size(1366, 768));
      addTearDown(() => _resetViewport(tester));
      await _mountShell(tester, allowWorkforceView: false);

      expect(find.text(YorksV1ShellStrings.workforce.primary), findsNothing);
      await tester.tap(find.text(YorksV1ShellStrings.searchOrJump.primary));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(YorksV1WorkspaceSearchDialog),
          matching: find.text(YorksV1ShellStrings.workforce.primary),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(YorksV1WorkspaceSearchDialog),
          matching: find.text(YorksV1ShellStrings.workforceTimesheets.primary),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('confirmed Workforce access is available from mobile More', (
    tester,
  ) async {
    _setViewport(tester, const Size(360, 800));
    addTearDown(() => _resetViewport(tester));
    await _mountShell(tester, allowWorkforceView: true, startOnMore: true);

    expect(find.text(YorksV1ShellStrings.workforce.primary), findsOneWidget);
    final workforceSemantics = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label == YorksV1ShellStrings.workforce.primary,
    );
    expect(workforceSemantics, findsOneWidget);
    expect(tester.getSize(workforceSemantics).height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'confirmed Workforce access remains one guarded destination from tablet More',
    (tester) async {
      _setViewport(tester, const Size(768, 1024));
      addTearDown(() => _resetViewport(tester));
      await _mountShell(tester, allowWorkforceView: true, startOnMore: true);

      expect(find.text(YorksV1ShellStrings.workforce.primary), findsOneWidget);
      final workforceSemantics = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == YorksV1ShellStrings.workforce.primary,
      );
      expect(workforceSemantics, findsOneWidget);
      expect(
        tester.getSize(workforceSemantics).height,
        greaterThanOrEqualTo(44),
      );
      expect(tester.takeException(), isNull);
    },
  );
}

GoRouter _router({
  required bool workforceEnabled,
  bool allowWorkforceView = false,
  YorksV1HybridPermissionResolver? resolver,
}) => createAppRouter(
  isOnboarded: true,
  isLoggedIn: true,
  role: UserRole.engineer,
  user: AppUser(
    id: 'workforce-actor-1',
    fullName: 'Workforce Actor',
    email: 'workforce@yorks.test',
    role: UserRole.engineer,
    yorksV1RoleCache: YorksV1Role.projectEngineer,
    yorksV1Roles: const [YorksV1Role.projectEngineer],
    createdAt: DateTime.utc(2026, 8, 30),
  ),
  yorksV1ProjectsEnabled: true,
  yorksV1BoqEnabled: true,
  yorksV1RequestsEnabled: true,
  yorksV1ArrangementEnabled: true,
  yorksV1LogisticsEnabled: true,
  yorksV1ReturnsDocumentsEnabled: true,
  yorksV1DocumentsEnabled: true,
  yorksV1WorkforceEnabled: workforceEnabled,
  yorksV1Role: YorksV1Role.projectEngineer,
  yorksV1PermissionResolver:
      resolver ??
      (
        capabilityKey, {
        required legacyAllowed,
        requireWrite = false,
        organizationSummary = false,
        projectId,
      }) => capabilityKey == YorksV1CapabilityKeys.workforceView
          ? allowWorkforceView
          : capabilityKey ==
                    YorksV1CapabilityKeys.workforceAttendanceMaintain ||
                capabilityKey ==
                    YorksV1CapabilityKeys.workforceTimesheetsMaintain,
);

Future<void> _mountRouter(
  WidgetTester tester,
  GoRouter router, {
  required bool workforceEnabled,
}) async {
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksV1FeatureFlagsProvider.overrideWithValue(
          _featureFlags(workforce: workforceEnabled),
        ),
        yorksV1CurrentRoleProvider.overrideWithValue(
          YorksV1Role.projectEngineer,
        ),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _mountShell(
  WidgetTester tester, {
  required bool allowWorkforceView,
  bool allowWorkersManage = false,
  bool startOnMore = false,
  String? initialPath,
}) async {
  final preferences = await SharedPreferences.getInstance();
  final client = SupabaseClient(
    'https://example.supabase.co',
    'test-publishable-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  final controller = YorksV1CurrentPermissionSnapshotController(
    enabled: true,
    authUserId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    client: null,
    repository: _ResolvedPermissionRepository(
      _permissionSnapshot(
        allowWorkforceView: allowWorkforceView,
        allowWorkersManage: allowWorkersManage,
      ),
    ),
    revisionSignalSubscription:
        ({required onSignal, required onUnavailable}) async => true,
  );
  await controller.start();
  final router = GoRouter(
    initialLocation:
        initialPath ?? (startOnMore ? RoutePaths.yorksV1MobileMore : '/'),
    routes: [
      GoRoute(
        path: RoutePaths.yorksV1Workforce,
        builder: (_, _) => const YorksV1WorkspaceShell(
          child: Scaffold(body: SizedBox.expand()),
        ),
      ),

      GoRoute(
        path: '/',
        builder: (_, _) => const YorksV1WorkspaceShell(
          child: Scaffold(body: SizedBox.expand()),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1MobileMore,
        builder: (_, _) =>
            const YorksV1WorkspaceShell(child: YorksV1MobileMoreScreen()),
      ),
      GoRoute(
        path: RoutePaths.yorksV1WorkforceTimesheets,
        builder: (_, _) => const YorksV1WorkspaceShell(
          child: Scaffold(body: SizedBox.expand()),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        supabaseClientProvider.overrideWithValue(client),
        yorksV1FeatureFlagsProvider.overrideWithValue(
          _featureFlags(workforce: true),
        ),
        yorksV1CurrentRoleProvider.overrideWithValue(
          YorksV1Role.projectEngineer,
        ),
        yorksV1CurrentPermissionSnapshotProvider.overrideWith(
          (ref) => controller,
        ),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

YorksV1FeatureFlags _featureFlags({required bool workforce}) =>
    YorksV1FeatureFlags(
      foundation: true,
      projects: true,
      boq: true,
      excel: true,
      requests: true,
      arrangement: true,
      logistics: true,
      returnsDocuments: true,
      documents: true,
      workforce: workforce,
    );

YorksV1CurrentPermissionSnapshot _permissionSnapshot({
  required bool allowWorkforceView,
  bool allowWorkersManage = false,
  bool? projectWorkforceView,
}) => YorksV1CurrentPermissionSnapshot.fromRpcJson({
  'schema_version': YorksV1PermissionSchema.current,
  'authorization_mode': 'mixed',
  'generated_at': '2026-08-30T08:00:00Z',
  'next_transition_at': null,
  'user': {
    'app_user_id': 'workforce-actor-1',
    'display_name': 'Workforce Actor',
    'exact_role': 'project_engineer',
    'is_active': true,
  },
  'revision': 1,
  'capabilities': [
    {
      'capability_key': YorksV1CapabilityKeys.workforceView,
      'module_key': 'workforce',
      'action_key': 'view',
      'label': 'View workforce',
      'description': 'View the authorized Workforce workspace.',
      'risk_level': 'high',
      'allowed_scope_kinds': ['organization', 'project'],
      'requires_project_access': false,
      'dependencies': <String>[],
      'runtime_status': 'operational',
      'is_assignable': true,
      'actor_can_delegate': false,
      'actor_delegable_scope_kinds': <String>[],
      'display_order': 400,
      'authorization_mode': 'enforced',
      'role_default': allowWorkforceView,
      'organization_summary_visible': true,
      'authoritative_effective': allowWorkforceView,
      'authoritative_source': allowWorkforceView
          ? 'role_default'
          : 'explicit_deny',
      'candidate_effective': allowWorkforceView,
      'candidate_source': allowWorkforceView ? 'role_default' : 'explicit_deny',
      'parity': true,
      'project_overrides': projectWorkforceView == null
          ? <Object?>[]
          : <Object?>[
              {
                'assignment_id': '22222222-2222-4222-8222-222222222222',
                'project_id': '11111111-1111-4111-8111-111111111111',
                'project_ref': 'YRA-313',
                'project_name': 'Riyadh Substation',
                'effect': projectWorkforceView ? 'grant' : 'deny',
                // Workforce responsibility is independent from technical V1
                // project membership; the roster RPC still filters rows.
                'has_project_access': false,
                'authoritative_effective': projectWorkforceView,
                'authoritative_source': projectWorkforceView
                    ? 'explicit_grant'
                    : 'explicit_deny',
                'candidate_effective': projectWorkforceView,
                'candidate_source': projectWorkforceView
                    ? 'explicit_grant'
                    : 'explicit_deny',
                'parity': true,
                'effective_from': '2026-08-29T08:00:00Z',
                'effective_until': null,
              },
            ],
    },
    if (allowWorkersManage)
      {
        'capability_key': YorksV1CapabilityKeys.workforceWorkersManage,
        'module_key': 'workforce',
        'action_key': 'workers_manage',
        'label': 'Manage workers',
        'description': 'Maintain normalized worker records.',
        'risk_level': 'critical',
        'allowed_scope_kinds': ['organization'],
        'requires_project_access': false,
        'dependencies': [YorksV1CapabilityKeys.workforceView],
        'runtime_status': 'operational',
        'is_assignable': true,
        'actor_can_delegate': false,
        'actor_delegable_scope_kinds': <String>[],
        'display_order': 419,
        'authorization_mode': 'enforced',
        'role_default': false,
        'organization_summary_visible': true,
        'authoritative_effective': true,
        'authoritative_source': 'explicit_grant',
        'candidate_effective': true,
        'candidate_source': 'explicit_grant',
        'parity': true,
        'project_overrides': <Object?>[],
      },
  ],
  'project_access': <Object?>[],
});

YorksV1HybridPermissionResolver _resolverFrom(
  YorksV1CurrentPermissionSnapshot snapshot,
) {
  final state = YorksV1CurrentPermissionSnapshotState(snapshot: snapshot);
  return (
    capabilityKey, {
    required legacyAllowed,
    requireWrite = false,
    organizationSummary = false,
    projectId,
  }) => state.hybridRouteAllows(
    capabilityKey,
    legacyAllowed: legacyAllowed,
    requireWrite: requireWrite,
    organizationSummary: organizationSummary,
    projectId: projectId,
  );
}

class _ResolvedPermissionRepository implements YorksV1PermissionRepository {
  const _ResolvedPermissionRepository(this.snapshot);

  final YorksV1CurrentPermissionSnapshot snapshot;

  @override
  Future<YorksV1CurrentPermissionSnapshot> getCurrentSnapshot() async =>
      snapshot;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _go(WidgetTester tester, GoRouter router, String path) async {
  router.go(path);
  await tester.pumpAndSettle();
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
}

void _resetViewport(WidgetTester tester) {
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

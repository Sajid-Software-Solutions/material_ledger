import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/app/yorks_v1_workspace_shell.dart';
import 'package:material_ledger/features/projects/presentation/screens/yorks_v1_projects_screen.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request.dart';
import 'package:material_ledger/shared/models/yorks_v1_overview_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_project.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_portfolio.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_shell_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_logistics.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_material_request_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_logistics_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_portfolio_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'R35 engineer overview remains laid out at desktop and mobile widths',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                const YorksV1WorkspaceShell(child: YorksV1OverviewScreen()),
          ),
        ],
      );

      for (final size in [
        const Size(1366, 768),
        const Size(1024, 768),
        const Size(768, 900),
        const Size(360, 800),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(preferences),
              yorksV1CurrentRoleProvider.overrideWithValue(
                YorksV1Role.projectEngineer,
              ),
              yorksV1ProjectPortfolioProvider.overrideWith((ref) async => []),
              yorksV1MaterialRequestListProvider(
                null,
              ).overrideWith((ref) async => []),
              yorksV1InventoryWorkspaceProvider(null).overrideWith(
                (ref) async => YorksV1InventoryWorkspace(items: const []),
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets(
    'R35 procurement overview remains laid out at desktop and mobile widths',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                const YorksV1WorkspaceShell(child: YorksV1OverviewScreen()),
          ),
        ],
      );

      for (final size in [
        const Size(1366, 768),
        const Size(1024, 768),
        const Size(360, 800),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(preferences),
              yorksV1CurrentRoleProvider.overrideWithValue(
                YorksV1Role.procurement,
              ),
              yorksV1ProjectPortfolioProvider.overrideWith((ref) async => []),
              yorksV1MaterialRequestListProvider(
                null,
              ).overrideWith((ref) async => []),
              yorksV1InventoryWorkspaceProvider(null).overrideWith(
                (ref) async => YorksV1InventoryWorkspace(items: const []),
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Needs Procurement Action'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'viewport $size');
      }

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets(
    'all exact roles receive a populated and responsive operational lens',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();

      for (final role in YorksV1Role.values) {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(preferences),
              yorksV1CurrentRoleProvider.overrideWithValue(role),
              yorksV1ProjectPortfolioProvider.overrideWith(
                (ref) async => _projects,
              ),
              yorksV1MaterialRequestListProvider(
                null,
              ).overrideWith((ref) async => _requests),
              yorksV1InventoryWorkspaceProvider(null).overrideWith(
                (ref) async => YorksV1InventoryWorkspace(
                  items: const [],
                  summary: const YorksV1InventorySummary(
                    totalActiveItems: 24,
                    lowStockCount: 2,
                    outOfStockCount: 1,
                    reservedCount: 4,
                    incomingCount: 0,
                  ),
                ),
              ),
            ],
            child: MaterialApp.router(routerConfig: _overviewRouter()),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(_roleTitle(role)),
          findsOneWidget,
          reason: role.claimValue,
        );
        if (role == YorksV1Role.pr) {
          expect(
            find.byKey(const ValueKey('pr-overview-icon')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('role-overview-metrics')),
            findsNothing,
          );
          continue;
        }
        if (role == YorksV1Role.accountant) {
          expect(
            find.byKey(const ValueKey('accountant-rollout-locked-icon')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('role-overview-metrics')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('executive-overview-metrics')),
            findsNothing,
          );
        } else {
          expect(
            find.byKey(
              ValueKey(
                role == YorksV1Role.admin || role.isGlobalProjectEngineer
                    ? 'executive-overview-metrics'
                    : 'role-overview-metrics',
              ),
            ),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull, reason: role.claimValue);
      }

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets(
    'Accountant overview stays locked without starting technical providers',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      var liveRefreshStarted = false;
      var projectPortfolioStarted = false;
      var requestListStarted = false;
      var inventoryStarted = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.accountant,
            ),
            yorksV1MaterialRequestLiveRefreshProvider.overrideWith((ref) {
              liveRefreshStarted = true;
            }),
            yorksV1AuthorizedProjectPortfolioProvider.overrideWith((ref) {
              projectPortfolioStarted = true;
              return const AsyncData(<YorksV1ProjectPortfolioItem>[]);
            }),
            yorksV1MaterialRequestListProvider(null).overrideWith((ref) async {
              requestListStarted = true;
              return <YorksV1MaterialRequest>[];
            }),
            yorksV1InventoryWorkspaceProvider(null).overrideWith((ref) async {
              inventoryStarted = true;
              return YorksV1InventoryWorkspace(items: const []);
            }),
          ],
          child: const MaterialApp(home: YorksV1OverviewScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(YorksV1OverviewStrings.accountantRolloutTitle.primary),
        findsOneWidget,
      );
      expect(
        find.text(YorksV1OverviewStrings.accountantRolloutDescription.primary),
        findsOneWidget,
      );
      expect(liveRefreshStarted, isFalse);
      expect(projectPortfolioStarted, isFalse);
      expect(requestListStarted, isFalse);
      expect(inventoryStarted, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'administrator and senior engineer controls remain role bounded',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();

      Future<void> pumpRole(YorksV1Role role) async {
        tester.view.physicalSize = const Size(1366, 768);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(preferences),
              yorksV1CurrentRoleProvider.overrideWithValue(role),
              yorksV1ProjectPortfolioProvider.overrideWith(
                (ref) async => _projects,
              ),
              yorksV1MaterialRequestListProvider(
                null,
              ).overrideWith((ref) async => _requests),
              yorksV1InventoryWorkspaceProvider(null).overrideWith(
                (ref) async => YorksV1InventoryWorkspace(items: const []),
              ),
            ],
            child: MaterialApp.router(routerConfig: _overviewRouter()),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: role.claimValue);
      }

      await pumpRole(YorksV1Role.admin);
      expect(
        find.text(YorksV1OverviewStrings.systemAndSecurity.primary),
        findsOneWidget,
      );
      expect(
        find.text(YorksV1OverviewStrings.configurationStatus.primary),
        findsOneWidget,
      );

      await pumpRole(YorksV1Role.seniorMechanicalEngineer);
      expect(find.text('Browse / Inventory'), findsWidgets);
      expect(find.text('User Management'), findsWidgets);
      expect(
        find.text(YorksV1OverviewStrings.configurationStatus.primary),
        findsNothing,
      );

      await pumpRole(YorksV1Role.projectManager);
      expect(
        find.text(YorksV1OverviewStrings.inventoryControl.primary),
        findsNothing,
      );
      expect(
        find.text(YorksV1OverviewStrings.userAndAccess.primary),
        findsNothing,
      );

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets('operations health keeps its total label above the donut', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          yorksV1CurrentRoleProvider.overrideWithValue(YorksV1Role.admin),
          yorksV1ProjectPortfolioProvider.overrideWith(
            (ref) async => _projects,
          ),
          yorksV1MaterialRequestListProvider(
            null,
          ).overrideWith((ref) async => _requests),
          yorksV1InventoryWorkspaceProvider(null).overrideWith(
            (ref) async => YorksV1InventoryWorkspace(items: const []),
          ),
        ],
        child: MaterialApp.router(routerConfig: _overviewRouter()),
      ),
    );
    await tester.pumpAndSettle();

    final label = find.byKey(const ValueKey('overview-health-total-label'));
    final value = find.byKey(const ValueKey('overview-health-total-value'));
    expect(label, findsOneWidget);
    expect(value, findsOneWidget);
    expect(tester.getTopLeft(label).dy, lessThan(tester.getTopLeft(value).dy));
    expect(tester.takeException(), isNull);

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets(
    'executive workspaces stay usable from small phone through desktop',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      for (final role in [
        YorksV1Role.admin,
        YorksV1Role.seniorMechanicalEngineer,
        YorksV1Role.projectManager,
      ]) {
        for (final size in [
          const Size(360, 640),
          const Size(390, 844),
          const Size(820, 900),
          const Size(1024, 768),
          const Size(1440, 900),
        ]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                sharedPreferencesProvider.overrideWithValue(preferences),
                yorksV1CurrentRoleProvider.overrideWithValue(role),
                yorksV1ProjectPortfolioProvider.overrideWith(
                  (ref) async => _projects,
                ),
                yorksV1MaterialRequestListProvider(
                  null,
                ).overrideWith((ref) async => _requests),
                yorksV1InventoryWorkspaceProvider(null).overrideWith(
                  (ref) async => YorksV1InventoryWorkspace(items: const []),
                ),
              ],
              child: MaterialApp.router(routerConfig: _overviewRouter()),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('executive-overview-metrics')),
            findsOneWidget,
            reason: '${role.claimValue} at $size',
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '${role.claimValue} at $size',
          );
        }
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets('role primary action deep-links to its authoritative workspace', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          yorksV1CurrentRoleProvider.overrideWithValue(YorksV1Role.admin),
          yorksV1ProjectPortfolioProvider.overrideWith(
            (ref) async => _projects,
          ),
          yorksV1MaterialRequestListProvider(
            null,
          ).overrideWith((ref) async => _requests),
          yorksV1InventoryWorkspaceProvider(null).overrideWith(
            (ref) async => YorksV1InventoryWorkspace(items: const []),
          ),
        ],
        child: MaterialApp.router(routerConfig: _overviewRouter()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Project'));
    await tester.pumpAndSettle();

    expect(find.text('create-project-destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

GoRouter _overviewRouter() => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) =>
          const YorksV1WorkspaceShell(child: YorksV1OverviewScreen()),
    ),
    GoRoute(
      path: '/projects/new',
      builder: (_, _) => const Material(
        child: Center(child: Text('create-project-destination')),
      ),
    ),
  ],
);

String _roleTitle(YorksV1Role role) => switch (role) {
  YorksV1Role.admin => YorksV1OverviewStrings.adminCommandCentre.primary,
  YorksV1Role.seniorMechanicalEngineer ||
  YorksV1Role.projectManager ||
  YorksV1Role.workshopInCharge ||
  YorksV1Role.documentController =>
    YorksV1OverviewStrings.portfolioOverview.primary,
  YorksV1Role.siteEngineer => YorksV1OverviewStrings.siteEngineerTitle.primary,
  YorksV1Role.projectEngineer =>
    YorksV1OverviewStrings.projectEngineerTitle.primary,
  YorksV1Role.procurement =>
    'Arrange, approve and dispatch without over-supplying.',
  YorksV1Role.accountant =>
    YorksV1OverviewStrings.accountantRolloutTitle.primary,
  YorksV1Role.pr => YorksV1ShellStrings.prHero.primary,
};

final _projects = <YorksV1ProjectPortfolioItem>[
  _project(
    id: 'project-active',
    reference: 'YRA-322',
    name: 'Nexus Bulk Transmission Phase One',
    state: YorksV1ProjectLifecycle.active,
    daysAgo: 0,
  ),
  _project(
    id: 'project-hold',
    reference: 'YRA-314',
    name: 'Independent Subsea HVDC System',
    state: YorksV1ProjectLifecycle.onHold,
    daysAgo: 1,
  ),
  _project(
    id: 'project-complete',
    reference: 'YRA-319',
    name: 'Taiz Ruwais Derivative Park',
    state: YorksV1ProjectLifecycle.completed,
    daysAgo: 2,
  ),
];

YorksV1ProjectPortfolioItem _project({
  required String id,
  required String reference,
  required String name,
  required YorksV1ProjectLifecycle state,
  required int daysAgo,
}) => YorksV1ProjectPortfolioItem(
  project: YorksV1Project(
    id: id,
    reference: reference,
    name: name,
    state: state,
    version: 1,
    createdAt: DateTime.utc(2026, 8, 1),
    updatedAt: DateTime.utc(2026, 8, 21).subtract(Duration(days: daysAgo)),
    siteLocation: 'Abu Dhabi, UAE',
  ),
  activeBuildingCount: 3,
  activeProjectEngineerCount: 2,
  activeSiteEngineerCount: 2,
);

final _requests = <YorksV1MaterialRequest>[
  _request('approval', YorksV1MaterialRequestState.awaitingRequestApproval),
  _request('changes', YorksV1MaterialRequestState.changesRequested),
  _request('arranging', YorksV1MaterialRequestState.approvedForArrangement),
  _request('approved', YorksV1MaterialRequestState.approved),
  _request('partial-dispatch', YorksV1MaterialRequestState.partiallyDispatched),
  _request('dispatch', YorksV1MaterialRequestState.dispatched),
  _request('partial-receipt', YorksV1MaterialRequestState.partiallyReceived),
  _request('received', YorksV1MaterialRequestState.received),
  _request('closed', YorksV1MaterialRequestState.closed),
];

YorksV1MaterialRequest _request(
  String id,
  YorksV1MaterialRequestState state,
) => YorksV1MaterialRequest(
  id: id,
  projectId: 'project-active',
  projectReference: 'YRA-322',
  projectName: 'Nexus Bulk Transmission Phase One',
  scopeId: 'scope-df6w',
  scopeName: 'DF6W 132/33kV Substation Building',
  state: state,
  recordVersion: 1,
  createdAt: DateTime.utc(2026, 8, 19),
  updatedAt: DateTime.utc(2026, 8, 21).subtract(
    Duration(minutes: YorksV1MaterialRequestState.values.indexOf(state) * 10),
  ),
  lines: const [
    YorksV1MaterialRequestLine(
      id: 'line-1',
      displayOrder: 1,
      source: YorksV1MaterialRequestLineSource.custom,
      description: 'Long controlled material description for responsive proof',
      quantity: '12',
      unit: 'Nos',
    ),
  ],
  timing: YorksV1MaterialRequestTiming.normal,
  requestNumber: 'YRA322-MR-${id.toUpperCase()}',
  title: 'Primary material package for the electrical room and site works',
  currentActionOwnerRole: switch (state) {
    YorksV1MaterialRequestState.approvedForArrangement ||
    YorksV1MaterialRequestState.arranging ||
    YorksV1MaterialRequestState.approved ||
    YorksV1MaterialRequestState.partiallyDispatched => 'procurement',
    _ => 'project_engineer',
  },
);

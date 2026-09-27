import 'dart:async';

import 'package:material_ledger/core/zoom/yorks_workspace_zoom.dart';
import 'package:material_ledger/core/fullscreen/yorks_workspace_fullscreen.dart';
import 'package:material_ledger/core/widgets/yorks_panel_toggle_icon.dart';
import 'package:material_ledger/shared/models/yorks_v1_zoom_strings.dart';
import 'package:material_ledger/shared/models/app_language.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/app/router.dart';
import 'package:material_ledger/app/yorks_v1_workspace_shell.dart';
import 'package:material_ledger/features/login/presentation/screens/login_screen.dart';
import 'package:material_ledger/shared/models/app_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_permission_management.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_shell_strings.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_permission_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final width in [1366.0, 360.0]) {
    for (final companyEnabled in [false, true]) {
      testWidgets('Accountant Company navigation $companyEnabled at $width', (
        tester,
      ) async {
        _setViewport(tester, Size(width, 800));
        addTearDown(() => _resetViewport(tester));
        final preferences = await SharedPreferences.getInstance();
        await tester.pumpWidget(
          _ShellTestApp(
            role: YorksV1Role.accountant,
            preferences: preferences,
            flags: YorksV1FeatureFlags(
              foundation: true,
              projects: true,
              boq: true,
              excel: true,
              requests: true,
              arrangement: true,
              logistics: true,
              returnsDocuments: true,
              documents: true,
              companyMaterialRequests: companyEnabled,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final requests = width < 720
            ? find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics &&
                    widget.properties.label ==
                        YorksV1ShellStrings.materialRequests.primary,
              )
            : find.text(YorksV1ShellStrings.materialRequests.primary);
        expect(requests, companyEnabled ? findsOneWidget : findsNothing);
        expect(find.text(YorksV1ShellStrings.projects.primary), findsNothing);
        expect(
          find.text(YorksV1ShellStrings.browseInventory.primary),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final width in [1366.0, 360.0]) {
    testWidgets('native account menu controls current view at $width', (
      tester,
    ) async {
      _setViewport(tester, Size(width, 800));
      addTearDown(() => _resetViewport(tester));
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        _ShellTestApp(role: YorksV1Role.procurement, preferences: preferences),
      );
      await tester.pumpAndSettle();
      final viewport = tester.element(find.byType(YorksWorkspaceZoomViewport));
      final controller = YorksWorkspaceZoomScope.maybeOf(viewport)!;
      if (width < 720) {
        tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('yorks-account-entry')));
      await tester.pumpAndSettle();
      final zoom = find.text(
        YorksV1ZoomStrings.zoomIn.active(AppLanguage.english),
      );
      expect(zoom, findsOneWidget);
      await tester.ensureVisible(zoom);
      await tester.tap(zoom);
      await tester.pumpAndSettle();
      expect(controller.currentScale, greaterThan(1));
      final reset = find.text(
        YorksV1ZoomStrings.resetZoom.active(AppLanguage.english),
      );
      await tester.ensureVisible(reset);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(controller.currentScale, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('R35 procurement workspace shell renders desktop navigation', (
    tester,
  ) async {
    _setViewport(tester, const Size(1366, 768));
    addTearDown(() => _resetViewport(tester));

    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      _ShellTestApp(role: YorksV1Role.procurement, preferences: preferences),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(YorksV1ShellStrings.companyName.primary),
      findsAtLeastNWidgets(2),
    );
    expect(
      find.text(YorksV1ShellStrings.browseInventory.primary),
      findsOneWidget,
    );
    expect(find.text(YorksV1ShellStrings.viewOnly.primary), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop fullscreen control enters, exits, and follows browser state',
    (tester) async {
      _setViewport(tester, const Size(1366, 768));
      addTearDown(() => _resetViewport(tester));
      final preferences = await SharedPreferences.getInstance();
      final fullscreen = _FakeWorkspaceFullscreenController();

      await tester.pumpWidget(
        _ShellTestApp(
          role: YorksV1Role.procurement,
          preferences: preferences,
          fullscreenController: fullscreen,
        ),
      );
      await tester.pumpAndSettle();

      final toggle = find.byKey(
        const ValueKey('yorks-workspace-fullscreen-toggle'),
      );
      expect(toggle, findsOneWidget);
      expect(
        find.byTooltip(YorksV1ZoomStrings.enterFullscreen.primary),
        findsOneWidget,
      );

      await tester.tap(toggle);
      await tester.pump();

      expect(fullscreen.isFullscreen, isTrue);
      expect(
        find.byTooltip(YorksV1ZoomStrings.exitFullscreen.primary),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.fullscreen_exit_rounded), findsOneWidget);
      expect(
        find.byKey(const ValueKey('yorks-workspace-sidebar-toggle')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('yorks-workspace-fullscreen-exit-surface')),
        findsOneWidget,
      );

      await tester.tap(toggle);
      await tester.pump();

      expect(
        find.byKey(const ValueKey('yorks-workspace-sidebar-toggle')),
        findsOneWidget,
      );

      fullscreen.setFullscreen(true);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(fullscreen.isFullscreen, isFalse);
      expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop places Accounts directly below Material Requests', (
    tester,
  ) async {
    _setViewport(tester, const Size(1366, 768));
    addTearDown(() => _resetViewport(tester));
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
        _permissionSnapshot(usersView: true, accountsView: true),
      ),
      revisionSignalSubscription:
          ({required onSignal, required onUnavailable}) async => true,
    );
    await controller.start();

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
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
          yorksV1CurrentRoleProvider.overrideWithValue(YorksV1Role.admin),
          yorksV1FeatureFlagsProvider.overrideWithValue(
            const YorksV1FeatureFlags(
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
            ),
          ),
          yorksV1CurrentPermissionSnapshotProvider.overrideWith(
            (ref) => controller,
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final requests = tester.getRect(
      find.text(YorksV1ShellStrings.materialRequests.primary),
    );
    final accounts = tester.getRect(
      find.text(YorksV1ShellStrings.accounts.primary),
    );
    expect(accounts.top, greaterThan(requests.top));
    expect(accounts.top - requests.bottom, lessThanOrEqualTo(24));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'authorized senior staff receive the complete Accounts office navigation',
    (tester) async {
      _setViewport(tester, const Size(1366, 1400));
      addTearDown(() => _resetViewport(tester));
      final preferences = await SharedPreferences.getInstance();
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );

      for (final role in const [
        YorksV1Role.admin,
        YorksV1Role.projectManager,
        YorksV1Role.seniorMechanicalEngineer,
      ]) {
        final controller = YorksV1CurrentPermissionSnapshotController(
          enabled: true,
          authUserId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          client: null,
          repository: _ResolvedPermissionRepository(
            _permissionSnapshot(
              usersView: role != YorksV1Role.projectManager,
              accountsView: true,
              supplierCostsView: true,
            ),
          ),
          revisionSignalSubscription:
              ({required onSignal, required onUnavailable}) async => true,
        );
        await controller.start();
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const YorksV1WorkspaceShell(
                child: Scaffold(body: SizedBox.expand()),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey(role),
            overrides: [
              sharedPreferencesProvider.overrideWithValue(preferences),
              supabaseClientProvider.overrideWithValue(client),
              yorksV1CurrentRoleProvider.overrideWithValue(role),
              yorksV1FeatureFlagsProvider.overrideWithValue(
                const YorksV1FeatureFlags(
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
                ),
              ),
              yorksV1CurrentPermissionSnapshotProvider.overrideWith(
                (ref) => controller,
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();

        for (final label in [
          YorksV1ShellStrings.accounts,
          YorksV1ShellStrings.projectAccounts,
          YorksV1ShellStrings.billingProgress,
          YorksV1ShellStrings.accountsClaims,
          YorksV1ShellStrings.receiptsPdc,
          YorksV1ShellStrings.supplierBills,
          YorksV1ShellStrings.dueSchedule,
          YorksV1ShellStrings.accountsDocuments,
          YorksV1ShellStrings.accountsReports,
          YorksV1ShellStrings.accountsAuditTrail,
        ]) {
          expect(find.text(label.primary), findsOneWidget, reason: role.name);
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'senior staff Accounts navigation hides Supplier Bills without supplier-cost authority',
    (tester) async {
      _setViewport(tester, const Size(1366, 1200));
      addTearDown(() => _resetViewport(tester));
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
          _permissionSnapshot(usersView: false, accountsView: true),
        ),
        revisionSignalSubscription:
            ({required onSignal, required onUnavailable}) async => true,
      );
      await controller.start();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
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
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.projectManager,
            ),
            yorksV1FeatureFlagsProvider.overrideWithValue(
              const YorksV1FeatureFlags(
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
              ),
            ),
            yorksV1CurrentPermissionSnapshotProvider.overrideWith(
              (ref) => controller,
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(YorksV1ShellStrings.accounts.primary), findsOneWidget);
      expect(
        find.text(YorksV1ShellStrings.accountsClaims.primary),
        findsOneWidget,
      );
      expect(
        find.text(YorksV1ShellStrings.supplierBills.primary),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('senior staff can reach the complete Accounts office from More', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    addTearDown(() => _resetViewport(tester));
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
          usersView: true,
          accountsView: true,
          supplierCostsView: true,
        ),
      ),
      revisionSignalSubscription:
          ({required onSignal, required onUnavailable}) async => true,
    );
    await controller.start();
    final router = GoRouter(
      initialLocation: RoutePaths.yorksV1MobileMore,
      routes: [
        GoRoute(
          path: RoutePaths.yorksV1MobileMore,
          builder: (_, _) =>
              const YorksV1WorkspaceShell(child: YorksV1MobileMoreScreen()),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          supabaseClientProvider.overrideWithValue(client),
          yorksV1CurrentRoleProvider.overrideWithValue(
            YorksV1Role.seniorMechanicalEngineer,
          ),
          yorksV1FeatureFlagsProvider.overrideWithValue(
            const YorksV1FeatureFlags(
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
            ),
          ),
          yorksV1CurrentPermissionSnapshotProvider.overrideWith(
            (ref) => controller,
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(YorksV1ShellStrings.accounts.primary), findsOneWidget);
    expect(
      find.text(YorksV1ShellStrings.projectAccounts.primary),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text(YorksV1ShellStrings.accountsAuditTrail.primary),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text(YorksV1ShellStrings.accountsAuditTrail.primary),
      findsOneWidget,
    );
    expect(
      find.text(YorksV1ShellStrings.supplierBills.primary),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('R35 workspace shell retains a safe mobile operational nav', (
    tester,
  ) async {
    _setViewport(tester, const Size(360, 800));
    addTearDown(() => _resetViewport(tester));
    final semantics = tester.ensureSemantics();

    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      _ShellTestApp(
        role: YorksV1Role.projectEngineer,
        preferences: preferences,
      ),
    );
    await tester.pumpAndSettle();

    final destinations = [
      AppStrings.home.primary,
      YorksV1ShellStrings.projects.primary,
      YorksV1ShellStrings.materialRequests.primary,
      AppStrings.more.primary,
    ];
    final bounds = <Rect>[];
    for (final destination in destinations) {
      final item = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == destination,
      );
      expect(item, findsOneWidget);
      bounds.add(tester.getRect(item));
    }
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == AppStrings.more.primary,
      ),
      findsOneWidget,
    );
    expect(bounds.map((rect) => rect.top).toSet(), hasLength(1));
    expect(bounds.map((rect) => rect.bottom).toSet(), hasLength(1));
    for (final rect in bounds) {
      expect(rect.width, greaterThanOrEqualTo(44));
      expect(rect.height, greaterThanOrEqualTo(44));
      expect(rect.bottom, lessThanOrEqualTo(800));
    }
    for (var index = 1; index < bounds.length; index++) {
      expect((bounds[index].width - bounds.first.width).abs(), lessThan(0.1));
    }
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets(
    'connected shell verifies first snapshot without painting child or nav',
    (tester) async {
      _setViewport(tester, const Size(360, 800));
      addTearDown(() => _resetViewport(tester));
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
        repository: _PendingPermissionRepository(),
        revisionSignalSubscription:
            ({required onSignal, required onUnavailable}) async => false,
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const YorksV1WorkspaceShell(
              child: SizedBox(key: ValueKey('protected-workspace-child')),
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
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.projectEngineer,
            ),
            yorksV1CurrentPermissionSnapshotProvider.overrideWith(
              (ref) => controller,
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('yorks-permission-verification-shell')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('protected-workspace-child')),
        findsNothing,
      );
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirmed enforced access hides a denied administration module responsively',
    (tester) async {
      addTearDown(() => _resetViewport(tester));
      final preferences = await SharedPreferences.getInstance();
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );

      Future<void> pumpPermission(bool usersView) async {
        final controller = YorksV1CurrentPermissionSnapshotController(
          enabled: true,
          authUserId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          client: null,
          repository: _ResolvedPermissionRepository(
            _permissionSnapshot(usersView: usersView),
          ),
          revisionSignalSubscription:
              ({required onSignal, required onUnavailable}) async => true,
        );
        await controller.start();
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const YorksV1WorkspaceShell(
                child: Scaffold(body: SizedBox.expand()),
              ),
            ),
            GoRoute(
              path: '/yorks/more',
              builder: (_, _) =>
                  const YorksV1WorkspaceShell(child: YorksV1MobileMoreScreen()),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey(usersView),
            overrides: [
              sharedPreferencesProvider.overrideWithValue(preferences),
              supabaseClientProvider.overrideWithValue(client),
              yorksV1CurrentRoleProvider.overrideWithValue(YorksV1Role.admin),
              yorksV1CurrentPermissionSnapshotProvider.overrideWith(
                (ref) => controller,
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
      }

      for (final size in [const Size(1366, 768), const Size(360, 800)]) {
        _setViewport(tester, size);

        await pumpPermission(true);
        if (size.width <= 1000) {
          await tester.tap(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  widget.properties.label == AppStrings.more.primary,
            ),
          );
          await tester.pumpAndSettle();
        }
        expect(
          find.text(YorksV1ShellStrings.userManagement.primary),
          findsOneWidget,
        );

        await pumpPermission(false);
        if (size.width <= 1000) {
          await tester.tap(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  widget.properties.label == AppStrings.more.primary,
            ),
          );
          await tester.pumpAndSettle();
        }
        expect(
          find.text(YorksV1ShellStrings.userManagement.primary),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'Senior Mechanical Engineer sees approved user configuration and read-only inventory destinations',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      for (final size in [const Size(1366, 768), const Size(360, 800)]) {
        _setViewport(tester, size);
        await tester.pumpWidget(
          _ShellTestApp(
            role: YorksV1Role.seniorMechanicalEngineer,
            preferences: preferences,
          ),
        );
        await tester.pumpAndSettle();

        if (size.width <= 1000) {
          await tester.tap(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  widget.properties.label == AppStrings.more.primary,
            ),
          );
          await tester.pumpAndSettle();
        }
        expect(
          find.text(YorksV1ShellStrings.userManagement.primary),
          findsOneWidget,
        );
        expect(
          find.text(YorksV1ShellStrings.browseInventory.primary),
          findsOneWidget,
        );
        expect(
          find.text(YorksV1ShellStrings.viewOnly.primary),
          size.width > 1000 ? findsOneWidget : findsNothing,
        );
        expect(
          find.text(YorksV1ShellStrings.configuration.primary),
          findsNothing,
        );
        expect(find.text(YorksV1ShellStrings.auditTrail.primary), findsNothing);
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/logo.png'),
            tester.element(find.byType(YorksV1WorkspaceShell)),
          ),
        );
        await tester.pump();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            size.width > 1000
                ? 'goldens/r35/senior_user_management_nav_desktop.png'
                : 'goldens/r35/senior_user_management_nav_mobile.png',
          ),
        );
        expect(tester.takeException(), isNull);
      }
      addTearDown(() => _resetViewport(tester));
    },
  );

  testWidgets(
    'Workshop In-Charge and Document Controller use the global engineering workspace',
    (tester) async {
      _setViewport(tester, const Size(1366, 768));
      addTearDown(() => _resetViewport(tester));
      final preferences = await SharedPreferences.getInstance();

      for (final role in [
        YorksV1Role.workshopInCharge,
        YorksV1Role.documentController,
      ]) {
        await tester.pumpWidget(
          _ShellTestApp(role: role, preferences: preferences),
        );
        await tester.pumpAndSettle();

        expect(find.text(YorksV1ShellStrings.projects.primary), findsOneWidget);
        expect(
          find.text(YorksV1ShellStrings.materialRequests.primary),
          findsOneWidget,
        );
        expect(
          find.text(YorksV1ShellStrings.browseInventory.primary),
          findsNothing,
        );
        expect(
          find.text(YorksV1ShellStrings.userManagement.primary),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('R35 workspace search opens a navigable command palette', (
    tester,
  ) async {
    _setViewport(tester, const Size(1366, 768));
    addTearDown(() => _resetViewport(tester));

    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      _ShellTestApp(
        role: YorksV1Role.projectEngineer,
        preferences: preferences,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(YorksV1ShellStrings.searchOrJump.primary));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text(YorksV1ShellStrings.searchHint.primary), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Projects');
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text(YorksV1ShellStrings.projects.primary), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop sidebar contracts immediately and can be reopened', (
    tester,
  ) async {
    _setViewport(tester, const Size(1366, 768));
    addTearDown(() => _resetViewport(tester));

    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      _ShellTestApp(role: YorksV1Role.procurement, preferences: preferences),
    );
    await tester.pumpAndSettle();

    final icon = find.descendant(
      of: find.byKey(const ValueKey('yorks-workspace-sidebar-toggle')),
      matching: find.byType(YorksPanelToggleIcon),
    );
    expect(tester.widget<YorksPanelToggleIcon>(icon).expanded, isTrue);

    expect(
      find.byTooltip(YorksV1ShellStrings.collapsePanel.primary),
      findsOneWidget,
    );
    expect(
      find.text(YorksV1ShellStrings.browseInventory.primary),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip(YorksV1ShellStrings.collapsePanel.primary));
    await tester.pumpAndSettle();
    expect(tester.widget<YorksPanelToggleIcon>(icon).expanded, isFalse);

    expect(
      find.byTooltip(YorksV1ShellStrings.expandPanel.primary),
      findsOneWidget,
    );
    expect(
      find.text(YorksV1ShellStrings.browseInventory.primary),
      findsNothing,
    );

    await tester.tap(find.byTooltip(YorksV1ShellStrings.expandPanel.primary));
    await tester.pumpAndSettle();
    expect(tester.widget<YorksPanelToggleIcon>(icon).expanded, isTrue);
    expect(
      find.text(YorksV1ShellStrings.browseInventory.primary),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Yorks R35 sign-in remains usable at mobile and desktop widths', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    for (final size in [const Size(360, 800), const Size(1366, 768)]) {
      _setViewport(tester, size);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
          child: const MaterialApp(home: LoginScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          size.width <= 720
              ? AppStrings.signIn.primary
              : YorksV1ShellStrings.secureAccess.primary.toUpperCase(),
        ),
        findsOneWidget,
      );
      expect(
        find.text(YorksV1ShellStrings.companyEmail.primary),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    addTearDown(() => _resetViewport(tester));
  });
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
}

void _resetViewport(WidgetTester tester) {
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

class _ShellTestApp extends StatelessWidget {
  const _ShellTestApp({
    required this.role,
    required this.preferences,
    this.fullscreenController,
    this.flags,
  });

  final YorksV1Role role;
  final SharedPreferences preferences;
  final YorksWorkspaceFullscreenController? fullscreenController;
  final YorksV1FeatureFlags? flags;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const YorksV1WorkspaceShell(
            child: Scaffold(body: SizedBox.expand()),
          ),
        ),
        GoRoute(
          path: '/yorks/more',
          builder: (_, _) =>
              const YorksV1WorkspaceShell(child: YorksV1MobileMoreScreen()),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksV1CurrentRoleProvider.overrideWithValue(role),
        if (flags != null)
          yorksV1FeatureFlagsProvider.overrideWithValue(flags!),
        if (fullscreenController != null)
          yorksWorkspaceFullscreenControllerProvider.overrideWith(
            (_) => fullscreenController!,
          ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }
}

class _FakeWorkspaceFullscreenController
    extends YorksWorkspaceFullscreenController {
  bool _isFullscreen = false;

  @override
  bool get isSupported => true;

  @override
  bool get isFullscreen => _isFullscreen;

  @override
  bool get shouldHideWorkspaceChrome => _isFullscreen;

  @override
  Future<void> toggle() async => setFullscreen(!_isFullscreen);

  void setFullscreen(bool value) {
    if (_isFullscreen == value) return;
    _isFullscreen = value;
    notifyListeners();
  }
}

class _PendingPermissionRepository implements YorksV1PermissionRepository {
  @override
  Future<YorksV1CurrentPermissionSnapshot> getCurrentSnapshot() =>
      Completer<YorksV1CurrentPermissionSnapshot>().future;

  @override
  Future<YorksV1UserAdminOptions> getUserAdminOptions({
    String? targetAppUserId,
  }) => throw UnimplementedError();

  @override
  Future<YorksV1UserPermissionWorkspace> getUserWorkspace({
    required String targetAppUserId,
  }) => throw UnimplementedError();

  @override
  Future<YorksV1UserPermissionWorkspace> setAssignment(
    YorksV1SetPermissionAssignmentInput input,
  ) => throw UnimplementedError();

  @override
  Future<YorksV1UserPermissionWorkspace> clearAssignment(
    YorksV1ClearPermissionAssignmentInput input,
  ) => throw UnimplementedError();

  @override
  Future<YorksV1UserPermissionWorkspace> applyChanges(
    YorksV1ApplyPermissionChangesInput input,
  ) => throw UnimplementedError();

  @override
  Future<YorksV1PermissionHistoryPage> listHistory(
    YorksV1PermissionHistoryQuery query,
  ) => throw UnimplementedError();
}

class _ResolvedPermissionRepository implements YorksV1PermissionRepository {
  const _ResolvedPermissionRepository(this.snapshot);

  final YorksV1CurrentPermissionSnapshot snapshot;

  @override
  Future<YorksV1CurrentPermissionSnapshot> getCurrentSnapshot() async =>
      snapshot;

  @override
  Future<YorksV1UserAdminOptions> getUserAdminOptions({
    String? targetAppUserId,
  }) => throw UnimplementedError();

  @override
  Future<YorksV1UserPermissionWorkspace> getUserWorkspace({
    required String targetAppUserId,
  }) => throw UnimplementedError();

  @override
  Future<YorksV1UserPermissionWorkspace> setAssignment(
    YorksV1SetPermissionAssignmentInput input,
  ) => throw UnimplementedError();

  @override
  Future<YorksV1UserPermissionWorkspace> clearAssignment(
    YorksV1ClearPermissionAssignmentInput input,
  ) => throw UnimplementedError();

  @override
  Future<YorksV1UserPermissionWorkspace> applyChanges(
    YorksV1ApplyPermissionChangesInput input,
  ) => throw UnimplementedError();

  @override
  Future<YorksV1PermissionHistoryPage> listHistory(
    YorksV1PermissionHistoryQuery query,
  ) => throw UnimplementedError();
}

YorksV1CurrentPermissionSnapshot _permissionSnapshot({
  required bool usersView,
  bool accountsView = false,
  bool supplierCostsView = false,
}) => YorksV1CurrentPermissionSnapshot.fromRpcJson({
  'schema_version': YorksV1PermissionSchema.current,
  'authorization_mode': 'mixed',
  'generated_at': '2026-08-24T13:00:00Z',
  'next_transition_at': null,
  'user': {
    'app_user_id': 'usr-admin',
    'display_name': 'Admin',
    'exact_role': 'admin',
    'is_active': true,
  },
  'revision': 1,
  'capabilities': [
    {
      'capability_key': YorksV1CapabilityKeys.usersView,
      'module_key': 'users',
      'action_key': 'view',
      'label': 'View user directory',
      'description': 'View the protected user directory.',
      'risk_level': 'high',
      'allowed_scope_kinds': ['organization'],
      'requires_project_access': false,
      'dependencies': <String>[],
      'runtime_status': 'operational',
      'is_assignable': true,
      'actor_can_delegate': usersView,
      'actor_delegable_scope_kinds': usersView ? ['organization'] : <String>[],
      'display_order': 1,
      'authorization_mode': 'enforced',
      'role_default': true,
      'organization_summary_visible': true,
      'authoritative_effective': usersView,
      'authoritative_source': usersView ? 'role_default' : 'explicit_deny',
      'candidate_effective': usersView,
      'candidate_source': usersView ? 'role_default' : 'explicit_deny',
      'parity': true,
      'project_overrides': <Object?>[],
    },
    if (accountsView)
      {
        'capability_key': YorksV1CapabilityKeys.materialRequestsView,
        'module_key': 'material_requests',
        'action_key': 'view',
        'label': 'View material requests',
        'description': 'View authorized material requests.',
        'risk_level': 'medium',
        'allowed_scope_kinds': ['organization', 'project'],
        'requires_project_access': false,
        'dependencies': <String>[],
        'runtime_status': 'operational',
        'is_assignable': true,
        'actor_can_delegate': true,
        'actor_delegable_scope_kinds': ['organization', 'project'],
        'display_order': 2,
        'authorization_mode': 'enforced',
        'role_default': true,
        'organization_summary_visible': true,
        'authoritative_effective': true,
        'authoritative_source': 'role_default',
        'candidate_effective': true,
        'candidate_source': 'role_default',
        'parity': true,
        'project_overrides': <Object?>[],
      },
    if (accountsView)
      {
        'capability_key': YorksV1CapabilityKeys.viewProjectAccounts,
        'module_key': 'accounts',
        'action_key': 'view',
        'label': 'View project accounts',
        'description': 'View authorized project account summaries.',
        'risk_level': 'high',
        'allowed_scope_kinds': ['organization', 'project'],
        'requires_project_access': false,
        'dependencies': <String>[],
        'runtime_status': 'operational',
        'is_assignable': true,
        'actor_can_delegate': true,
        'actor_delegable_scope_kinds': ['organization', 'project'],
        'display_order': 3,
        'authorization_mode': 'enforced',
        'role_default': true,
        'organization_summary_visible': true,
        'authoritative_effective': true,
        'authoritative_source': 'role_default',
        'candidate_effective': true,
        'candidate_source': 'role_default',
        'parity': true,
        'project_overrides': <Object?>[],
      },
    if (supplierCostsView)
      {
        'capability_key': YorksV1CapabilityKeys.viewSupplierCosts,
        'module_key': 'accounts',
        'action_key': 'view_supplier_costs',
        'label': 'View supplier costs',
        'description': 'View protected supplier bill and cost records.',
        'risk_level': 'high',
        'allowed_scope_kinds': ['organization', 'project'],
        'requires_project_access': false,
        'dependencies': <String>[],
        'runtime_status': 'operational',
        'is_assignable': true,
        'actor_can_delegate': true,
        'actor_delegable_scope_kinds': ['organization', 'project'],
        'display_order': 4,
        'authorization_mode': 'enforced',
        'role_default': true,
        'organization_summary_visible': true,
        'authoritative_effective': true,
        'authoritative_source': 'role_default',
        'candidate_effective': true,
        'candidate_source': 'role_default',
        'parity': true,
        'project_overrides': <Object?>[],
      },
  ],
  'project_access': <Object?>[],
});

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/app/router.dart';
import 'package:material_ledger/app/yorks_v1_workspace_shell.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/core/widgets/yorks_mobile_ui.dart';
import 'package:material_ledger/features/admin/presentation/screens/user_management_screen.dart';
import 'package:material_ledger/features/engineer/presentation/screens/engineer_profile_screen.dart';
import 'package:material_ledger/features/engineering_tools/presentation/screens/yorks_v1_engineering_calculator_screens.dart';
import 'package:material_ledger/shared/models/app_user.dart';
import 'package:material_ledger/shared/models/user_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/session_provider.dart';
import 'package:material_ledger/shared/providers/users_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/services/app_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    final nexusFontLoader = FontLoader('NexusSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final arabicFontLoader = FontLoader('NotoSansArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
    final flutterCache = _flutterCacheDirectory();
    final iconBytes = await File(
      '${flutterCache.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    final iconFontLoader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(iconBytes)));
    await Future.wait([
      nexusFontLoader.load(),
      arabicFontLoader.load(),
      iconFontLoader.load(),
    ]);
  });

  testWidgets('mobile user configuration remains readable at 360px', (
    tester,
  ) async {
    await _setViewport(tester, const Size(360, 800));
    final preferences = await _seedUsers();
    final router = GoRouter(
      initialLocation: RoutePaths.users,
      routes: [
        GoRoute(
          path: RoutePaths.users,
          builder: (_, _) =>
              const YorksV1WorkspaceShell(child: UserManagementScreen()),
        ),
        GoRoute(
          path: RoutePaths.yorksV1MobileMore,
          builder: (_, _) =>
              const YorksV1WorkspaceShell(child: YorksV1MobileMoreScreen()),
        ),
        GoRoute(
          path: RoutePaths.engineerProfile,
          builder: (_, _) =>
              const YorksV1WorkspaceShell(child: EngineerProfileScreen()),
        ),
      ],
    );
    await tester.pumpWidget(
      _scope(
        preferences,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Senior Mechanical Engineer'), findsWidgets);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byKey(const ValueKey('user-management-create')), findsOneWidget);
    expect(find.text('New User'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/mobile_touchups/user_management_360x800.png'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop user configuration retains the office directory', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1366, 768));
    final preferences = await _seedUsers();
    final router = GoRouter(
      initialLocation: RoutePaths.users,
      routes: [
        GoRoute(
          path: RoutePaths.users,
          builder: (_, _) =>
              const YorksV1WorkspaceShell(child: UserManagementScreen()),
        ),
      ],
    );
    await tester.pumpWidget(
      _scope(
        preferences,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Total accounts'), findsOneWidget);
    expect(find.byKey(const ValueKey('user-management-search')), findsOneWidget);
    expect(find.text('Senior Mechanical Engineer'), findsWidgets);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/mobile_touchups/user_management_1366x768.png'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile More exposes profile without a duplicate shell toolbar', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    final preferences = await _seedUsers();
    final router = GoRouter(
      initialLocation: RoutePaths.yorksV1MobileMore,
      routes: [
        GoRoute(
          path: RoutePaths.yorksV1MobileMore,
          builder: (_, _) =>
              const YorksV1WorkspaceShell(child: YorksV1MobileMoreScreen()),
        ),
        GoRoute(
          path: RoutePaths.engineerProfile,
          builder: (_, _) =>
              const YorksV1WorkspaceShell(child: EngineerProfileScreen()),
        ),
      ],
    );
    await tester.pumpWidget(
      _scope(
        preferences,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final profileEntry = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile-profile-entry')),
        matching: find.byType(InkWell),
      ),
    );
    profileEntry.onTap!();
    // This route intentionally owns live protected profile projections. A
    // bounded pump completes navigation without waiting for their progress
    // indicators, which may remain active in this offline shell fixture.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(YorksMobileAppBar), findsOneWidget);
    expect(
      find.byKey(const ValueKey('canonical-my-yorks-page')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final tool in [
    (path: RoutePaths.yorksV1DuctSizer, child: const YorksV1DuctSizerScreen()),
    (
      path: RoutePaths.yorksV1EspCalculator,
      child: const YorksV1EspCalculatorScreen(),
    ),
  ]) {
    testWidgets('mobile ${tool.path} back returns a root deep link to More', (
      tester,
    ) async {
      await _setViewport(tester, const Size(360, 800));
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final router = GoRouter(
        initialLocation: tool.path,
        routes: [
          GoRoute(path: tool.path, builder: (_, _) => tool.child),
          GoRoute(
            path: RoutePaths.yorksV1MobileMore,
            builder: (_, _) => const Scaffold(body: Text('More hub')),
          ),
        ],
      );
      await tester.pumpWidget(
        _scope(
          preferences,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('More hub'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Widget _scope(SharedPreferences preferences, {required Widget child}) =>
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        currentUserProvider.overrideWithValue(_admin),
        yorksV1CurrentRoleProvider.overrideWithValue(YorksV1Role.admin),
        yorksV1UserProvisioningEnabledProvider.overrideWithValue(true),
        appVersionProvider.overrideWithValue(
          const AppVersionInfo(version: '1.0.0', build: 35),
        ),
      ],
      child: child,
    );

Future<SharedPreferences> _seedUsers() async {
  final users = [_admin, _seniorMechanicalEngineer, _projectManager];
  SharedPreferences.setMockInitialValues({
    'app_users_v3': jsonEncode(users.map((user) => user.toJson()).toList()),
  });
  return SharedPreferences.getInstance();
}

final _admin = AppUser(
  id: 'admin-fixture',
  fullName: 'Khaled Sleiman',
  email: 'khaled@yorks.ae',
  role: UserRole.admin,
  createdAt: DateTime.utc(2026, 8, 9),
  yorksV1RoleCache: YorksV1Role.admin,
  yorksV1Roles: const [YorksV1Role.admin],
);

final _seniorMechanicalEngineer = AppUser(
  id: 'senior-fixture',
  fullName: 'Noor Zaman',
  email: 'noor@yorks.ae',
  role: UserRole.engineer,
  createdAt: DateTime.utc(2026, 8, 9),
  yorksV1RoleCache: YorksV1Role.seniorMechanicalEngineer,
  yorksV1Roles: const [YorksV1Role.seniorMechanicalEngineer],
);

final _projectManager = AppUser(
  id: 'manager-fixture',
  fullName: 'Ali Hadba',
  email: 'ali@yorks.ae',
  role: UserRole.engineer,
  createdAt: DateTime.utc(2026, 8, 9),
  yorksV1RoleCache: YorksV1Role.projectManager,
  yorksV1Roles: const [YorksV1Role.projectManager],
);

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 26);
  tester.view.viewPadding = const FakeViewPadding(top: 26);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });
}

Directory _flutterCacheDirectory() {
  var directory = File(Platform.resolvedExecutable).parent;
  for (var level = 0; level < 8; level++) {
    if (directory.path.endsWith('${Platform.pathSeparator}cache')) {
      return directory;
    }
    directory = directory.parent;
  }
  throw StateError('Could not locate the Flutter cache from the test runner');
}

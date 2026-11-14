import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/app/router.dart';
import 'package:material_ledger/app/yorks_v1_workspace_shell.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/app_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_my_profile.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_workspace_status.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_my_profile_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_my_profile_repository.dart';
import 'package:material_ledger/shared/widgets/profile_menu_button.dart';
import 'package:material_ledger/shared/widgets/yorks_sign_out_action.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _actor = '10000000-0000-4000-8000-000000000004';

YorksV1MyProfile _profile(YorksV1Role role) => YorksV1MyProfile.fromRpcJson({
  'schema_version': 1,
  'generated_at': '2026-09-05T00:00:00Z',
  'next_transition_at': null,
  'permission_revision': 3,
  'account': {
    'auth_user_id': _actor,
    'app_user_id': 'usr-owner',
    'display_name': 'Owner',
    'email': 'owner@example.test',
    'exact_role': role.claimValue,
    'status': 'active',
    'workspace_key': role.claimValue,
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
  'capabilities': <Object?>[],
  'actions': <Object?>[],
  'operational_summary_state': 'not_projected',
  'workforce_scope_state': 'requires_work_date_context',
});

class _ProfileRepository implements YorksV1MyProfileRepository {
  const _ProfileRepository(this.result, {this.error});
  final YorksV1MyProfile result;
  final Object? error;

  @override
  Future<YorksV1MyProfile> load({
    required String expectedAuthUserId,
    required YorksV1Role expectedRole,
    int projectOffset = 0,
    int projectLimit = 25,
  }) async {
    if (error != null) throw error!;
    return result;
  }
}

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

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('desktop account stamp opens the compact canonical launcher', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = await _pumpAccountApp(tester);
    addTearDown(router.dispose);

    await tester.tap(find.byKey(const ValueKey('yorks-account-entry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('yorks-account-popover')), findsOneWidget);
    expect(find.text('Owner'), findsAtLeastNWidgets(1));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('yorks-account-popover')),
        matching: find.text(AppStrings.adminRole.primary),
      ),
      findsOneWidget,
    );
    // Only the account and its three actions: no status lines, About or
    // zoom controls.
    expect(find.text('owner@example.test'), findsOneWidget);
    expect(find.text(AppStrings.accountActive.primary), findsNothing);
    expect(find.text(AppStrings.verifyingAccount.primary), findsNothing);
    expect(find.text(AppStrings.workspaceSync.primary), findsNothing);
    expect(find.text(AppStrings.profile.primary), findsOneWidget);
    expect(find.text(AppStrings.notifications.primary), findsOneWidget);
    expect(find.text(AppStrings.about.primary), findsNothing);
    expect(find.byIcon(Icons.zoom_in), findsNothing);
    expect(find.text(AppStrings.signOut.primary), findsOneWidget);
    expect(find.text('Assigned projects'), findsNothing);
    expect(find.text('Open requests'), findsNothing);
    expect(find.text('BOQ · MR · Docs'), findsNothing);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/profile_p02/account_popover_1366x768.png'),
    );

    await tester.tap(find.byKey(const ValueKey('open-my-yorks')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('canonical-my-yorks-page')),
      findsOneWidget,
    );
    expect(
      router.routeInformationProvider.value.uri.path,
      RoutePaths.engineerProfile,
    );
  });

  testWidgets('popover uses one localized sign-out confirmation component', (
    tester,
  ) async {
    final router = await _pumpAccountApp(tester);
    addTearDown(router.dispose);
    await tester.tap(find.byKey(const ValueKey('yorks-account-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.signOut.primary));
    await tester.pumpAndSettle();
    expect(find.byType(YorksSignOutConfirmationDialog), findsOneWidget);
    expect(find.text(AppStrings.logoutConfirmBody.primary), findsOneWidget);
    expect(find.text(AppStrings.cancel.primary), findsOneWidget);
    await tester.tap(find.text(AppStrings.cancel.primary));
    await tester.pumpAndSettle();
    expect(find.byType(YorksSignOutConfirmationDialog), findsNothing);
  });

  testWidgets('confirmed shared sign-out routes to the single login target', (
    tester,
  ) async {
    final router = await _pumpAccountApp(tester);
    addTearDown(router.dispose);
    await tester.tap(find.byKey(const ValueKey('yorks-account-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.signOut.primary));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, AppStrings.signOut.primary),
    );
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, RoutePaths.login);
    expect(find.text('login'), findsOneWidget);
  });

  testWidgets('launcher never presents a failed profile read as active', (
    tester,
  ) async {
    final router = await _pumpAccountApp(
      tester,
      repository: _ProfileRepository(
        _profile(YorksV1Role.admin),
        error: const YorksV1DomainException(
          YorksV1DomainErrorCode.backendUnavailable,
        ),
      ),
    );
    addTearDown(router.dispose);
    await tester.tap(find.byKey(const ValueKey('yorks-account-entry')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.accountUnavailable.primary), findsOneWidget);
    expect(find.text(AppStrings.accountActive.primary), findsNothing);
    expect(find.byKey(const ValueKey('open-my-yorks')), findsOneWidget);
  });

  for (final role in YorksV1Role.values) {
    testWidgets('launcher preserves exact ${role.claimValue} role copy', (
      tester,
    ) async {
      final router = await _pumpAccountApp(
        tester,
        role: role,
        repository: _ProfileRepository(_profile(role)),
      );
      addTearDown(router.dispose);
      await tester.tap(find.byKey(const ValueKey('yorks-account-entry')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('yorks-account-popover')),
          matching: find.text(_roleLabel(role)),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('shared avatar entry navigates directly to My Yorks', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: ProfileMenuButton()),
        ),
        GoRoute(
          path: RoutePaths.engineerProfile,
          builder: (_, _) => const Scaffold(
            body: Text('target', key: ValueKey('avatar-profile-target')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.byType(ProfileMenuButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('avatar-profile-target')), findsOneWidget);
  });
}

Future<GoRouter> _pumpAccountApp(
  WidgetTester tester, {
  YorksV1Role role = YorksV1Role.admin,
  YorksV1MyProfileRepository? repository,
}) async {
  final preferences = await SharedPreferences.getInstance();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: SizedBox(
              width: 260,
              height: 68,
              child: YorksAccountEntry(
                displayName: 'Owner',
                role: role,
                language: AppLanguage.english,
                workspaceStatus: const YorksV1WorkspaceStatus(
                  state: YorksV1WorkspaceConnectionState.connected,
                ),
                expanded: true,
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.engineerProfile,
        builder: (_, _) => const Scaffold(
          body: Text('My Yorks', key: ValueKey('canonical-my-yorks-page')),
        ),
      ),
      GoRoute(
        path: RoutePaths.notifications,
        builder: (_, _) => const Scaffold(body: Text('notifications')),
      ),
      GoRoute(
        path: RoutePaths.about,
        builder: (_, _) => const Scaffold(body: Text('about')),
      ),
      GoRoute(
        path: RoutePaths.login,
        builder: (_, _) => const Scaffold(body: Text('login')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksV1AuthUserIdProvider.overrideWithValue(_actor),
        yorksV1CurrentRoleProvider.overrideWithValue(role),
        yorksV1MyProfileRepositoryProvider.overrideWithValue(
          repository ?? _ProfileRepository(_profile(role)),
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
  return router;
}

String _roleLabel(YorksV1Role role) => switch (role) {
  YorksV1Role.projectEngineer => AppStrings.projectEngineerRole.primary,
  YorksV1Role.siteEngineer => AppStrings.siteEngineerRole.primary,
  YorksV1Role.seniorMechanicalEngineer =>
    AppStrings.seniorMechanicalEngineerRole.primary,
  YorksV1Role.projectManager => AppStrings.projectManagerRole.primary,
  YorksV1Role.workshopInCharge => AppStrings.workshopInChargeRole.primary,
  YorksV1Role.documentController => AppStrings.documentControllerRole.primary,
  YorksV1Role.accountant => AppStrings.accountantRole.primary,
  YorksV1Role.pr => AppStrings.prRole.primary,
  YorksV1Role.procurement => AppStrings.procurementRole.primary,
  YorksV1Role.admin => AppStrings.adminRole.primary,
};

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

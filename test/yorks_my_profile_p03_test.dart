import 'dart:async';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/engineer/presentation/screens/engineer_profile_screen.dart';
import 'package:material_ledger/features/engineer/presentation/widgets/yorks_my_profile_components.dart';
import 'package:material_ledger/shared/models/yorks_v1_my_profile.dart';
import 'package:material_ledger/shared/models/yorks_v1_my_profile_workspace.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_workspace_status.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_my_profile_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_my_profile_workspace_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_workspace_status_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_my_profile_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_my_profile_workspace_repository.dart';
import 'package:material_ledger/shared/services/app_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _actor = '10000000-0000-4000-8000-000000000004';

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

  test('layout resolver keeps the three P03 breakpoints explicit', () {
    expect(yorksMyProfileLayoutFor(360), YorksMyProfileLayout.compact);
    expect(yorksMyProfileLayoutFor(720), YorksMyProfileLayout.compact);
    expect(yorksMyProfileLayoutFor(721), YorksMyProfileLayout.medium);
    expect(yorksMyProfileLayoutFor(1099), YorksMyProfileLayout.medium);
    expect(yorksMyProfileLayoutFor(1100), YorksMyProfileLayout.expanded);
  });

  for (final viewport in const [
    (size: Size(1440, 900), twoPanes: true),
    (size: Size(1366, 768), twoPanes: true),
    (size: Size(1180, 820), twoPanes: true),
    (size: Size(1024, 768), twoPanes: false),
    (size: Size(820, 1180), twoPanes: false),
    (size: Size(800, 360), twoPanes: false),
    (size: Size(768, 1024), twoPanes: false),
    (size: Size(844, 390), twoPanes: false),
    (size: Size(430, 932), twoPanes: false),
    (size: Size(390, 844), twoPanes: false),
    (size: Size(360, 800), twoPanes: false),
  ]) {
    testWidgets('same account, preferences and security model adapts at '
        '${viewport.size.width.toInt()}x${viewport.size.height.toInt()}', (
      tester,
    ) async {
      await _setViewport(tester, viewport.size);
      await _pumpProfile(tester);
      if (!viewport.twoPanes) {
        // Phone and tablet show one tab at a time; Work opens first.
        expect(find.text('Preferences'), findsNothing);
        await _openTab(tester, 'settings');
      }

      expect(find.text('Owner'), findsOneWidget);
      expect(find.text('Admin'), findsWidgets);
      expect(find.text('Preferences'), findsWidgets);
      expect(find.text('Help & security'), findsWidgets);
      expect(find.text('Assigned projects'), findsNothing);
      expect(find.text('Open requests'), findsNothing);
      final account = tester.getTopLeft(
        find.byKey(const ValueKey('my-yorks-identity-hero')),
      );
      final preferences = tester.getTopLeft(find.text('Preferences').last);
      if (viewport.twoPanes) {
        expect(preferences.dx, greaterThan(account.dx));
      } else {
        expect(preferences.dy, greaterThan(account.dy));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('phone at 200 percent text keeps every control reachable', (
    tester,
  ) async {
    await _setViewport(tester, const Size(360, 800));
    await _pumpProfile(tester, textScale: 2);

    expect(find.text('Owner'), findsOneWidget);
    await _openTab(tester, 'settings');
    await tester.scrollUntilVisible(
      find.text('Sign Out'),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Sign Out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('RTL localizes the complete page and preserves LTR email', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'selected_language': 'ar'});
    await _setViewport(tester, const Size(820, 1180));
    await _pumpProfile(tester);
    await _openTab(tester, 'settings');

    expect(find.text('يوركس الخاصة بي'), findsOneWidget);
    expect(find.text('التفضيلات'), findsWidgets);
    final directionality = tester.widget<Directionality>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('canonical-my-yorks-page')),
            matching: find.byType(Directionality),
          )
          .first,
    );
    expect(directionality.textDirection, TextDirection.rtl);
    final emailDirection = tester.widget<Directionality>(
      find
          .ancestor(
            of: find.text('owner@example.test'),
            matching: find.byType(Directionality),
          )
          .first,
    );
    expect(emailDirection.textDirection, TextDirection.ltr);
    expect(tester.takeException(), isNull);
  });

  testWidgets('section choice survives an orientation change', (tester) async {
    await _setViewport(tester, const Size(820, 1180));
    await _pumpProfile(tester);
    await tester.tap(find.byKey(const ValueKey('my-yorks-section-settings')));
    await tester.pumpAndSettle();
    expect(
      tester.widget(find.byKey(const ValueKey('my-yorks-section-settings'))),
      isA<FilledButton>(),
    );

    tester.view.physicalSize = const Size(1024, 768);
    await tester.pumpAndSettle();
    expect(
      tester.widget(find.byKey(const ValueKey('my-yorks-section-settings'))),
      isA<FilledButton>(),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion changes sections without an animated wait', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    await _pumpProfile(tester, disableAnimations: true);

    await tester.tap(find.byKey(const ValueKey('my-yorks-section-settings')));
    await tester.pump();
    expect(
      tester.widget(find.byKey(const ValueKey('my-yorks-section-settings'))),
      isA<FilledButton>(),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard activates section navigation in logical order', (
    tester,
  ) async {
    await _setViewport(tester, const Size(820, 1180));
    await _pumpProfile(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      tester.widget(find.byKey(const ValueKey('my-yorks-section-settings'))),
      isA<FilledButton>(),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'screen-reader semantics distinguish account state and controls',
    (tester) async {
      await _setViewport(tester, const Size(390, 844));
      final semantics = tester.ensureSemantics();
      await _pumpProfile(tester);
      await _openTab(tester, 'settings');

      final identity = tester.getSemantics(
        find.byKey(const ValueKey('my-yorks-identity-hero')),
      );
      expect(identity.label, contains('Verified Yorks account identity'));
      expect(identity.label, contains('Owner'));
      expect(find.bySemanticsLabel('App lock'), findsNothing);
      expect(find.bySemanticsLabel('Notifications'), findsOneWidget);
      expect(find.bySemanticsLabel('Workspace sync'), findsOneWidget);
      expect(
        tester.getSize(find.bySemanticsLabel('Notifications')).height,
        greaterThanOrEqualTo(44),
      );
      semantics.dispose();
    },
  );

  testWidgets('profile picker uses centralized copy and selected semantics', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    final semantics = tester.ensureSemantics();
    await _pumpProfile(tester);
    await _openTab(tester, 'settings');
    await tester.scrollUntilVisible(
      find.text('Secondary Language'),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Secondary Language'));
    await tester.pumpAndSettle();

    expect(
      find.text('Choose the language used by Yorks.'),
      findsAtLeastNWidgets(1),
    );
    final english = tester.getSemantics(
      find.bySemanticsLabel('English, English'),
    );
    expect(english.flagsCollection.isSelected, Tristate.isTrue);
    semantics.dispose();
  });

  testWidgets('legacy app lock is removed and company currency stays AED', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'app_lock_enabled': true,
      'selected_currency': 'USD',
    });
    await _setViewport(tester, const Size(390, 844));
    await _pumpProfile(tester);
    await _openTab(tester, 'settings');
    expect(find.bySemanticsLabel('App lock'), findsNothing);
    await tester.scrollUntilVisible(
      find.bySemanticsLabel('Currency'),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('🇦🇪 AED'), findsOneWidget);
    expect(find.text('Contact support'), findsOneWidget);
    expect(find.text('+923159353145'), findsOneWidget);
    final currency = tester.getSemantics(find.bySemanticsLabel('Currency'));
    expect(currency.flagsCollection.isButton, isFalse);
    expect(currency.flagsCollection.isEnabled, Tristate.isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed account proof stays unavailable and provides retry', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    await _pumpProfile(
      tester,
      repository: _ProfileRepository(error: StateError('offline')),
    );

    expect(find.text('Account details are unavailable'), findsWidgets);
    expect(find.text('Verified account'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('my-yorks-identity-hero')),
        matching: find.text('Try again'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading never fabricates active identity or summary zeroes', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    await _pumpProfile(
      tester,
      repository: _DeferredProfileRepository(),
      settle: false,
    );
    await tester.pump();

    expect(find.text('Verifying your account'), findsWidgets);
    expect(find.text('Verified account'), findsNothing);
    expect(find.text('0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final visual in const [
    (name: 'desktop_1440x900', size: Size(1440, 900), scale: 1.0),
    (name: 'tablet_landscape_1024x768', size: Size(1024, 768), scale: 1.0),
    (name: 'tablet_portrait_820x1180', size: Size(820, 1180), scale: 1.0),
    (name: 'phone_portrait_390x844', size: Size(390, 844), scale: 1.0),
    (name: 'phone_landscape_844x390', size: Size(844, 390), scale: 1.0),
    (name: 'phone_200_percent_360x800', size: Size(360, 800), scale: 2.0),
  ]) {
    testWidgets('P04/P05 visual ${visual.name}', (tester) async {
      await _setViewport(tester, visual.size);
      await _pumpProfile(tester, textScale: visual.scale);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/profile_p04_p05/${visual.name}.png'),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('P04/P05 Arabic RTL visual 390x844', (tester) async {
    SharedPreferences.setMockInitialValues({'selected_language': 'ar'});
    await _setViewport(tester, const Size(390, 844));
    await _pumpProfile(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/profile_p04_p05/phone_rtl_ar_390x844.png'),
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpProfile(
  WidgetTester tester, {
  YorksV1MyProfileRepository repository = const _ProfileRepository(),
  double textScale = 1,
  bool disableAnimations = false,
  bool settle = true,
}) async {
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksV1AuthUserIdProvider.overrideWithValue(_actor),
        yorksV1CurrentRoleProvider.overrideWithValue(YorksV1Role.admin),
        yorksV1MyProfileRepositoryProvider.overrideWithValue(repository),
        yorksV1MyProfileWorkspaceRepositoryProvider.overrideWithValue(
          const _WorkspaceRepository(),
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
        home: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: const EngineerProfileScreen(),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

class _ProfileRepository implements YorksV1MyProfileRepository {
  const _ProfileRepository({this.error});

  final Object? error;

  @override
  Future<YorksV1MyProfile> load({
    required String expectedAuthUserId,
    required YorksV1Role expectedRole,
    int projectOffset = 0,
    int projectLimit = 25,
  }) async {
    if (error != null) throw error!;
    return _profile(expectedRole);
  }
}

class _DeferredProfileRepository implements YorksV1MyProfileRepository {
  final completer = Completer<YorksV1MyProfile>();

  @override
  Future<YorksV1MyProfile> load({
    required String expectedAuthUserId,
    required YorksV1Role expectedRole,
    int projectOffset = 0,
    int projectLimit = 25,
  }) => completer.future;
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
    'generated_at': '2026-09-05T00:00:00Z',
    'next_transition_at': null,
    'permission_revision': 4,
    'account': {'auth_user_id': _actor, 'exact_role': 'admin'},
    'today': {
      'state': 'available',
      'metrics': <Object?>[
        {'metric_key': 'technical_projects', 'value': 9},
        {'metric_key': 'material_requests_needing_action', 'value': 5},
        {'metric_key': 'material_requests_open', 'value': 25},
      ],
    },
    'access_scope': {
      'technical_project_count': 9,
      'accounts_project_count': 0,
      'active_direct_membership_count': 0,
      'effective_source_kinds': <Object?>['role_default'],
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

YorksV1MyProfile _profile(YorksV1Role role) => YorksV1MyProfile.fromRpcJson({
  'schema_version': 1,
  'generated_at': '2026-09-05T00:00:00Z',
  'next_transition_at': null,
  'permission_revision': 4,
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
  'capabilities': <Object?>[
    for (final key in const [
      'projects.view',
      'material_requests.view',
      'users.view',
      'audit.view',
    ])
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
    {
      'action_id': 'open_users',
      'capability_key': 'users.view',
      'required_feature': 'foundation',
      'kind': 'navigation',
    },
    {
      'action_id': 'open_audit',
      'capability_key': 'audit.view',
      'required_feature': 'foundation',
      'kind': 'navigation',
    },
  ],
  'operational_summary_state': 'not_projected',
  'workforce_scope_state': 'requires_work_date_context',
});

/// Opens a My Yorks tab on phone and tablet.
Future<void> _openTab(WidgetTester tester, String section) async {
  final tab = find.byKey(ValueKey('my-yorks-section-$section'));
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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

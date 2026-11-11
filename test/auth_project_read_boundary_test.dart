import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/session_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_portfolio_provider.dart';

import 'support/yorks_v1_permission_test_support.dart';

const _user = {
  'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'app_metadata': {'role': 'admin', 'app_user_id': 'app-user'},
  'aud': 'authenticated',
  'created_at': '2026-08-24T09:00:00Z',
};
const _session = {
  'access_token': 'test-access-token',
  'refresh_token': 'test-refresh-token',
  'token_type': 'bearer',
  'user': _user,
};

void main() {
  test('pending persistence cannot restore identity after logout', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final previous = SharedPreferencesStorePlatform.instance;
    final store = _DelayedStore();
    SharedPreferencesStorePlatform.instance = store;
    addTearDown(() => SharedPreferencesStorePlatform.instance = previous);
    final notifier = AuthSessionNotifier(prefs, restoreLocalSession: false);
    addTearDown(notifier.dispose);
    final signingIn = notifier.setUser('app-user');
    final signingOut = notifier.logout();
    expect(notifier.state, isNull);
    store.persisted.complete();
    await signingIn;
    await signingOut;
    expect(notifier.state, isNull);
    expect(prefs.getString(kAuthUserIdPrefKey), isNull);
  });

  test(
    'verified user still receives genuine server permission denial',
    () async {
      final fixture = await _Fixture.create(recover: true, denyProjects: true);
      final restoring = fixture.auth.restoreSupabaseSession();
      await fixture.authStarted.future;
      fixture.authResponse.complete();
      await fixture.profileStarted.future;
      fixture.profileResponse.complete();
      await restoring;
      expect(fixture.container.read(isLoggedInProvider), isTrue);
      await expectLater(
        fixture.container.read(yorksV1ProjectPortfolioProvider.future),
        throwsA(
          isA<YorksV1DomainException>().having(
            (error) => error.code,
            'code',
            YorksV1DomainErrorCode.unauthorized,
          ),
        ),
      );
      expect(fixture.protectedReads, greaterThan(0));
    },
  );

  test(
    'stale local login without a Supabase session never reads projects',
    () async {
      final fixture = await _Fixture.create();
      expect(fixture.container.read(isLoggedInProvider), isFalse);
      await fixture.expectBlocked();
      await fixture.auth.restoreSupabaseSession();
      expect(fixture.prefs.getString(kAuthUserIdPrefKey), isNull);
      await fixture.expectBlocked();
      expect(fixture.protectedReads, 0);
    },
  );

  for (final signIn in [false, true]) {
    test(
      '${signIn ? 'password sign-in' : 'restoration'} waits for delayed Auth and profile before project reads',
      () async {
        final fixture = await _Fixture.create(recover: !signIn);
        final operation = signIn
            ? fixture.auth.signIn(
                email: 'test@example.invalid',
                password: 'test',
              )
            : fixture.auth.restoreSupabaseSession();
        await fixture.authStarted.future;
        await fixture.expectBlocked();
        fixture.authResponse.complete();
        await fixture.profileStarted.future;
        // A Supabase token alone is insufficient: profile validation is pending.
        expect(fixture.client.auth.currentUser, isNotNull);
        await fixture.expectBlocked();
        fixture.profileResponse.complete();
        await operation;
        expect(fixture.container.read(isLoggedInProvider), isTrue);
        expect(
          await fixture.container.read(yorksV1ProjectPortfolioProvider.future),
          isEmpty,
        );
        expect(
          (await fixture.container.read(
            yorksV1ProjectOverviewProvider.future,
          )).total,
          7,
        );
        expect(fixture.protectedReads, greaterThanOrEqualTo(2));

        final before = fixture.protectedReads;
        final clearing = fixture.auth.clearLocalSession();
        expect(fixture.container.read(isLoggedInProvider), isFalse);
        await clearing;
        await fixture.expectBlocked();
        expect(fixture.protectedReads, before);
      },
    );
  }

  test(
    'rejected restored session stays blocked and removes stale login',
    () async {
      final fixture = await _Fixture.create(recover: true, rejectAuth: true);
      final restoring = fixture.auth.restoreSupabaseSession();
      await fixture.authStarted.future;
      await fixture.expectBlocked();
      fixture.authResponse.complete();
      await restoring;
      await fixture.expectBlocked();
      expect(fixture.prefs.getString(kAuthUserIdPrefKey), isNull);
      expect(fixture.protectedReads, 0);
    },
  );

  test(
    'sign-out during delayed profile cannot reopen protected reads',
    () async {
      final fixture = await _Fixture.create(recover: true);
      final restoring = fixture.auth.restoreSupabaseSession();
      await fixture.authStarted.future;
      fixture.authResponse.complete();
      await fixture.profileStarted.future;
      await fixture.auth.clearLocalSession();
      fixture.profileResponse.complete();
      await restoring;
      await fixture.expectBlocked();
      expect(fixture.protectedReads, 0);
    },
  );
}

class _Fixture {
  late HttpServer server;
  late SupabaseClient client;
  late SharedPreferences prefs;
  late ProviderContainer container;
  final authStarted = Completer<void>();
  final authResponse = Completer<void>();
  final profileStarted = Completer<void>();
  final profileResponse = Completer<void>();
  int protectedReads = 0;
  AuthController get auth => container.read(authControllerProvider);

  static Future<_Fixture> create({
    bool recover = false,
    bool rejectAuth = false,
    bool denyProjects = false,
  }) async {
    final f = _Fixture();
    f.server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    f.server.listen((request) async {
      Object result;
      if (request.uri.path.startsWith('/auth/v1/')) {
        if (!f.authStarted.isCompleted) f.authStarted.complete();
        await f.authResponse.future;
        request.response.statusCode = rejectAuth ? 401 : 200;
        result = rejectAuth
            ? {'code': 'invalid_jwt', 'msg': 'Invalid session'}
            : request.uri.path.endsWith('/token')
            ? _session
            : _user;
      } else if (request.uri.path == '/rest/v1/v1_profiles') {
        if (!f.profileStarted.isCompleted) f.profileStarted.complete();
        await f.profileResponse.future;
        result = {'is_active': true, 'canonical_role_snapshot': 'admin'};
      } else {
        f.protectedReads++;
        if (denyProjects) request.response.statusCode = 403;
        result = denyProjects
            ? {'code': '42501', 'message': 'permission denied'}
            : request.uri.path.endsWith('/v1_project_overview')
            ? {
                'items': [],
                'counts': {
                  'total': 7,
                  'active': 7,
                  'on_hold': 0,
                  'completed': 0,
                },
              }
            : [];
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(result));
      await request.response.close();
    });
    SharedPreferences.setMockInitialValues({kAuthUserIdPrefKey: 'app-user'});
    f.prefs = await SharedPreferences.getInstance();
    f.client = SupabaseClient(
      'http://127.0.0.1:${f.server.port}',
      'test-publishable-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    if (recover) await f.client.auth.recoverSession(jsonEncode(_session));
    f.container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(f.prefs),
        supabaseClientProvider.overrideWithValue(f.client),
        yorksV1FeatureFlagsProvider.overrideWithValue(
          const YorksV1FeatureFlags(foundation: true, projects: true),
        ),
        yorksV1CurrentPermissionSnapshotProvider.overrideWith(
          (ref) => YorksV1TestPermissionController(
            yorksV1TrustedFeaturePermissionState(),
          ),
        ),
      ],
    );
    // Keep the real providers mounted through authentication transitions.
    f.container.listen(yorksV1ProjectPortfolioProvider, (_, _) {});
    f.container.listen(yorksV1ProjectOverviewProvider, (_, _) {});
    addTearDown(() async {
      if (!f.authResponse.isCompleted) f.authResponse.complete();
      if (!f.profileResponse.isCompleted) f.profileResponse.complete();
      f.container.dispose();
      await f.client.dispose();
      await f.server.close(force: true);
    });
    return f;
  }

  Future<void> expectBlocked() async {
    expect(container.read(isLoggedInProvider), isFalse);
    final denied = throwsA(
      isA<YorksV1DomainException>().having(
        (error) => error.code,
        'code',
        YorksV1DomainErrorCode.unauthenticated,
      ),
    );
    await expectLater(
      container.read(yorksV1ProjectPortfolioProvider.future),
      denied,
    );
    await expectLater(
      container.read(yorksV1ProjectOverviewProvider.future),
      denied,
    );
  }
}

class _DelayedStore extends InMemorySharedPreferencesStore {
  _DelayedStore() : super.empty();
  final persisted = Completer<void>();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final result = await super.setValue(valueType, key, value);
    await persisted.future;
    return result;
  }
}

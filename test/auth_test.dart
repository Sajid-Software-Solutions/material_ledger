import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:material_ledger/shared/models/user_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/session_provider.dart';
import 'package:material_ledger/shared/providers/users_provider.dart';
import 'package:material_ledger/shared/services/password_hasher.dart';

const _testLocalPassword = 'test-only-local-password';

void main() {
  test(
    'session restoration distinguishes revoked credentials from outages',
    () {
      expect(
        yorksV1IsConfirmedAuthRejection(
          AuthRetryableFetchException(statusCode: '503'),
        ),
        isFalse,
      );
      expect(
        yorksV1IsConfirmedAuthRejection(
          const AuthApiException('temporarily unavailable', statusCode: '503'),
        ),
        isFalse,
      );
      expect(
        yorksV1IsConfirmedAuthRejection(
          const AuthApiException('invalid token', statusCode: '401'),
        ),
        isTrue,
      );
    },
  );

  test('restored mobile session survives a temporary Auth outage', () async {
    var responseStatus = HttpStatus.serviceUnavailable;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serverSubscription = server.listen((request) async {
      request.response.statusCode = responseStatus;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'code': responseStatus == HttpStatus.unauthorized
              ? 'invalid_jwt'
              : 'service_unavailable',
          'msg': 'Verification unavailable',
        }),
      );
      await request.response.close();
    });
    addTearDown(() async {
      await serverSubscription.cancel();
      await server.close(force: true);
    });

    SharedPreferences.setMockInitialValues({kAuthUserIdPrefKey: 'app-user'});
    final prefs = await SharedPreferences.getInstance();
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-publishable-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-access-token',
        'refresh_token': 'test-refresh-token',
        'token_type': 'bearer',
        'user': {
          'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'app_metadata': {'role': 'admin', 'app_user_id': 'app-user'},
          'aud': 'authenticated',
          'created_at': '2026-08-24T09:00:00Z',
        },
      }),
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        supabaseClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(authControllerProvider);

    await controller.restoreSupabaseSession();
    expect(container.read(authSessionProvider), 'app-user');
    expect(prefs.getString(kAuthUserIdPrefKey), 'app-user');

    responseStatus = HttpStatus.unauthorized;
    await controller.restoreSupabaseSession();
    expect(container.read(authSessionProvider), isNull);
  });

  test('late Auth verification cannot restore a signed-out identity', () async {
    final requestStarted = Completer<void>();
    final releaseResponse = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serverSubscription = server.listen((request) async {
      if (!requestStarted.isCompleted) requestStarted.complete();
      await releaseResponse.future;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'app_metadata': {'role': 'admin', 'app_user_id': 'app-user'},
          'aud': 'authenticated',
          'created_at': '2026-08-24T09:00:00Z',
        }),
      );
      await request.response.close();
    });
    addTearDown(() async {
      if (!releaseResponse.isCompleted) releaseResponse.complete();
      await serverSubscription.cancel();
      await server.close(force: true);
    });

    SharedPreferences.setMockInitialValues({kAuthUserIdPrefKey: 'app-user'});
    final prefs = await SharedPreferences.getInstance();
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-publishable-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-access-token',
        'refresh_token': 'test-refresh-token',
        'token_type': 'bearer',
        'user': {
          'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'app_metadata': {'role': 'admin', 'app_user_id': 'app-user'},
          'aud': 'authenticated',
          'created_at': '2026-08-24T09:00:00Z',
        },
      }),
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        supabaseClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(authControllerProvider);

    final verification = controller.restoreSupabaseSession();
    await requestStarted.future;
    await controller.clearLocalSession();
    releaseResponse.complete();
    await verification;

    expect(container.read(authSessionProvider), isNull);
    expect(prefs.getString(kAuthUserIdPrefKey), isNull);
  });

  group('PasswordHasher', () {
    test('verify accepts the right password and rejects others', () {
      final pw = PasswordHasher.create('s3cret!');
      expect(PasswordHasher.verify('s3cret!', pw.hash, pw.salt), true);
      expect(PasswordHasher.verify('wrong', pw.hash, pw.salt), false);
    });

    test('empty hash/salt never verifies', () {
      expect(PasswordHasher.verify('anything', '', ''), false);
    });

    test('salts are random — same password yields different hashes', () {
      final a = PasswordHasher.create('same');
      final b = PasswordHasher.create('same');
      expect(a.hash == b.hash, false);
    });
  });

  group('Credential sign-in', () {
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          localDemoPasswordProvider.overrideWithValue(_testLocalPassword),
        ],
      );
      addTearDown(container.dispose);
    });

    AuthController auth() => container.read(authControllerProvider);

    test(
      'valid seed credentials sign in and set the role from the user',
      () async {
        final result = await auth().signIn(
          email: 'owner@gmail.com',
          password: _testLocalPassword,
        );
        expect(result, SignInResult.ok);
        expect(container.read(isLoggedInProvider), true);
        expect(container.read(currentUserProvider)?.role, UserRole.admin);
        expect(container.read(currentRoleProvider), UserRole.admin);
      },
    );

    test('engineer creds load the engineer role', () async {
      await auth().signIn(
        email: 'imrankhan@gmail.com',
        password: _testLocalPassword,
      );
      expect(container.read(currentRoleProvider), UserRole.engineer);
    });

    test('wrong password is rejected and no session opens', () async {
      final result = await auth().signIn(
        email: 'owner@gmail.com',
        password: 'nope',
      );
      expect(result, SignInResult.invalidCredentials);
      expect(container.read(isLoggedInProvider), false);
    });

    test('unknown email is rejected', () async {
      final result = await auth().signIn(
        email: 'ghost@yorksac.ae',
        password: _testLocalPassword,
      );
      expect(result, SignInResult.invalidCredentials);
    });

    test(
      'a deactivated account is blocked even with the right password',
      () async {
        // Deactivate the procurement seed, then try to sign in.
        final proc = container
            .read(usersProvider)
            .firstWhere((u) => u.role == UserRole.procurement);
        await container.read(usersProvider.notifier).setActive(proc.id, false);
        final result = await auth().signIn(
          email: proc.email,
          password: _testLocalPassword,
        );
        expect(result, SignInResult.deactivated);
        expect(container.read(isLoggedInProvider), false);
      },
    );

    test(
      'an admin-created user must change password on first sign-in',
      () async {
        final u = await container
            .read(usersProvider.notifier)
            .createUser(
              fullName: 'Temp User',
              email: 'temp@yorksac.ae',
              role: UserRole.engineer,
              password: 'temp1234',
            );
        final result = await auth().signIn(
          email: u.email,
          password: 'temp1234',
        );
        expect(result, SignInResult.mustChangePassword);

        // After they set their own password, normal sign-in.
        await container
            .read(usersProvider.notifier)
            .setPassword(u.id, 'mine5678');
        await auth().signOut();
        final after = await auth().signIn(email: u.email, password: 'mine5678');
        expect(after, SignInResult.ok);
      },
    );

    test(
      'self-service changeOwnPassword clears the must-change flag and sets the new password',
      () async {
        final u = await container
            .read(usersProvider.notifier)
            .createUser(
              fullName: 'Temp User 2',
              email: 'temp2@yorksac.ae',
              role: UserRole.engineer,
              password: 'temp1234',
            );
        // First sign-in is forced to change (admin-set temporary password).
        expect(
          await auth().signIn(email: u.email, password: 'temp1234'),
          SignInResult.mustChangePassword,
        );

        // The change-password screen's actual path — self-service, not the
        // admin-only reset. Must clear the flag so the router gate stops looping.
        await auth().changeOwnPassword('mine5678');
        expect(container.read(currentUserProvider)?.mustChangePassword, false);

        // Re-login with the new password is a clean OK (no second forced change).
        await auth().signOut();
        expect(
          await auth().signIn(email: u.email, password: 'mine5678'),
          SignInResult.ok,
        );
      },
    );

    test('signOut clears the session', () async {
      await auth().signIn(
        email: 'owner@gmail.com',
        password: _testLocalPassword,
      );
      expect(container.read(isLoggedInProvider), true);
      await auth().signOut();
      expect(container.read(isLoggedInProvider), false);
      expect(container.read(currentUserProvider), isNull);
    });

    test('reapplying the same session id is notification-free', () async {
      await container
          .read(authSessionProvider.notifier)
          .setUser('stable-session-user');
      final changes = <String?>[];
      final subscription = container.listen<String?>(
        authSessionProvider,
        (_, next) => changes.add(next),
      );
      addTearDown(subscription.close);

      await container
          .read(authSessionProvider.notifier)
          .setUser('stable-session-user');
      expect(changes, isEmpty);

      await container
          .read(authSessionProvider.notifier)
          .setUser('different-session-user');
      expect(changes, ['different-session-user']);
    });

    test(
      'session lifecycle increments the exact-role invalidation revision',
      () async {
        final before = container.read(authSessionRevisionProvider);
        await auth().signIn(
          email: 'owner@gmail.com',
          password: _testLocalPassword,
        );
        expect(container.read(authSessionRevisionProvider), before + 1);

        await auth().signOut();
        expect(container.read(authSessionRevisionProvider), before + 2);
      },
    );
  });

  group('Security baseline', () {
    test(
      'sign-in Auth failures are classified without exposing server detail',
      () {
        expect(
          signInResultForAuthException(
            const AuthException('Invalid login credentials', statusCode: '400'),
          ),
          SignInResult.invalidCredentials,
        );
        expect(
          signInResultForAuthException(
            const AuthException(
              'Email not confirmed',
              code: 'email_not_confirmed',
            ),
          ),
          SignInResult.emailNotConfirmed,
        );
        expect(
          signInResultForAuthException(
            const AuthException('Too many requests', statusCode: '429'),
          ),
          SignInResult.rateLimited,
        );
        expect(
          signInResultForAuthException(
            const AuthException(
              'Unexpected upstream failure',
              statusCode: '500',
            ),
          ),
          SignInResult.networkError,
        );
      },
    );

    test('roles are accepted only from exact app_metadata values', () {
      expect(userRoleFromAppMetadata({'role': 'admin'}), UserRole.admin);
      expect(
        userRoleFromAppMetadata({'role': 'procurement'}),
        UserRole.procurement,
      );
      // Exact Yorks V1 claims are only a compatibility-shell mapping here.
      // V1 command authority stays in yorksV1CurrentRoleProvider and never
      // infers Project Engineer access from this legacy UserRole value.
      expect(
        userRoleFromAppMetadata({'role': 'project_engineer'}),
        UserRole.engineer,
      );
      expect(
        userRoleFromAppMetadata({'role': 'site_engineer'}),
        UserRole.engineer,
      );
      expect(
        userRoleFromAppMetadata({'role': 'senior_mechanical_engineer'}),
        UserRole.engineer,
      );
      expect(
        userRoleFromAppMetadata({'role': 'project_manager'}),
        UserRole.engineer,
      );
      expect(userRoleFromAppMetadata({'role': 'owner'}), isNull);
      expect(userRoleFromAppMetadata({'role': 'Admin'}), isNull);
      expect(userRoleFromAppMetadata({'role': 1}), isNull);
      expect(userRoleFromAppMetadata({}), isNull);
    });

    test(
      'local sign-in is closed when no demo password is configured',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final locked = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(locked.dispose);

        final result = await locked
            .read(authControllerProvider)
            .signIn(email: 'owner@gmail.com', password: 'any-password');
        expect(result, SignInResult.invalidCredentials);
        expect(locked.read(isLoggedInProvider), false);
      },
    );

    test(
      'connected mode removes local password material from the roster',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final client = SupabaseClient(
          'https://example.supabase.co',
          'test-publishable-key',
        );
        final connected = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            localDemoPasswordProvider.overrideWithValue(_testLocalPassword),
            supabaseClientProvider.overrideWithValue(client),
          ],
        );
        addTearDown(connected.dispose);

        final users = connected.read(usersProvider);
        expect(users, isNotEmpty);
        expect(users.every((user) => user.passwordHash.isEmpty), true);
        expect(users.every((user) => user.passwordSalt.isEmpty), true);
      },
    );

    test('explicit local password rotates historical seed hashes', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final oldContainer = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          localDemoPasswordProvider.overrideWithValue('old-local-password'),
        ],
      );
      oldContainer.read(usersProvider);
      oldContainer.dispose();

      final rotated = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          localDemoPasswordProvider.overrideWithValue('new-local-password'),
        ],
      );
      addTearDown(rotated.dispose);
      final auth = rotated.read(authControllerProvider);

      expect(
        await auth.signIn(
          email: 'owner@gmail.com',
          password: 'old-local-password',
        ),
        SignInResult.invalidCredentials,
      );
      expect(
        await auth.signIn(
          email: 'owner@gmail.com',
          password: 'new-local-password',
        ),
        SignInResult.ok,
      );
    });
  });
}

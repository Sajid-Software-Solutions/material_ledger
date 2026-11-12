import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/app_user.dart';
import '../models/effective_permissions.dart';
import '../models/role_permissions.dart';
import '../models/user_role.dart';
import '../models/yorks_v1_role.dart';
import '../repositories/collection_store.dart';
import '../repositories/storage.dart';
import '../services/password_hasher.dart';
import 'language_provider.dart';
import 'role_permissions_provider.dart';
import 'yorks_v1_feature_flags_provider.dart';

// Bumped to v3 to re-seed the simplified one-account-per-role set (owner /
// alasad / imrankhan) over any previously-seeded users.
const _kUsersKey = 'app_users_v3';
const _uuid = Uuid();
const _seedUserIds = {'usr-admin', 'usr-proc', 'usr-eng'};

const _configuredLocalDemoPassword = String.fromEnvironment(
  'LOCAL_DEMO_PASSWORD',
);

/// Explicit credential gate for non-production local development. Empty by
/// default, which makes seeded local accounts non-authenticating. Tests override
/// this provider without placing a reusable credential in application source.
final localDemoPasswordProvider = Provider<String>(
  (ref) => _configuredLocalDemoPassword,
);

/// The only client-side gateway to the privileged `admin-users` function.
/// Widgets work through [UsersNotifier], never this gateway. The provider also
/// gives focused tests a safe fake without a real backend or service credential.
typedef AdminUsersInvocation =
    Future<Map<String, dynamic>?> Function(Map<String, dynamic> body);

final adminUsersInvocationProvider = Provider<AdminUsersInvocation>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return (body) async {
    if (client == null) return null;
    try {
      final res = await client.functions.invoke('admin-users', body: body);
      final data = res.data;
      if (data is Map && (data['ok'] == true || data['authUserId'] != null)) {
        return Map<String, dynamic>.from(data);
      }
      throw Exception(
        'User service error: ${data is Map ? data['error'] : data}',
      );
    } on FunctionException catch (e) {
      final d = e.details;
      final msg = (d is Map && d['error'] != null)
          ? d['error']
          : (e.reasonPhrase ?? 'request failed');
      throw Exception('User service error: $msg');
    }
  };
});

/// True only for the connected Yorks V1 provisioning experience. Exact V1
/// claims stay behind the rollout flag; a flag-off or offline shell keeps its
/// retained legacy roster flow during migration.
final yorksV1UserProvisioningEnabledProvider = Provider<bool>((ref) {
  return ref.watch(yorksV1FeatureFlagsProvider).foundation &&
      ref.watch(supabaseClientProvider) != null;
});

/// All system user accounts. Admin-managed only (no self-signup).
///
/// When Supabase is configured, every account operation that must reach the
/// identity provider (create, change role/claims, reset password, deactivate,
/// delete) is executed by the `admin-users` Edge Function using the service_role
/// key — the client never holds that key. The local list is the admin-facing
/// roster/cache; the JWT is the source of truth for identity, role and caps.
final usersProvider = StateNotifierProvider<UsersNotifier, List<AppUser>>((
  ref,
) {
  return UsersNotifier(
    ref,
    ref
        .watch(storageProvider)
        .collection<AppUser>(
          _kUsersKey,
          toJson: (u) => u.toJson(),
          fromJson: AppUser.fromJson,
        ),
    seedPassword: ref.watch(localDemoPasswordProvider),
  );
});

class UsersNotifier extends StateNotifier<List<AppUser>> {
  UsersNotifier(this._ref, this._store, {required String seedPassword})
    : super([]) {
    state = _store.isSeeded ? _store.readAll() : _seed(seedPassword);
    // A connected app never retains legacy/local password material. Supabase
    // Auth is authoritative and local fallback is prohibited in this mode.
    if (_client != null) {
      state = [
        for (final user in state)
          if (user.passwordHash.isNotEmpty || user.passwordSalt.isNotEmpty)
            user.copyWith(passwordHash: '', passwordSalt: '')
          else
            user,
      ];
    } else if (seedPassword.isNotEmpty) {
      // Rotate only the built-in local-development identities to the explicit
      // current value. This replaces hashes left by older prototype versions
      // without changing passwords for locally created test users.
      state = [
        for (final user in state)
          if (_seedUserIds.contains(user.id))
            () {
              final digest = PasswordHasher.create(seedPassword);
              return user.copyWith(
                passwordHash: digest.hash,
                passwordSalt: digest.salt,
              );
            }()
          else
            user,
      ];
    }
    if (!_store.isSeeded) _store.writeAll(state);
    if (_client != null || seedPassword.isNotEmpty) _store.writeAll(state);
  }

  final Ref _ref;
  final CollectionStore<AppUser> _store;
  final Map<String, String> _pendingRestampIdempotencyKeys = {};
  Future<void>? _directoryRefreshInFlight;

  SupabaseClient? get _client => _ref.read(supabaseClientProvider);

  /// Refresh the Admin roster from the authoritative Supabase Auth directory.
  /// The local collection remains a cache only; a failed refresh never erases
  /// the last known roster or invents users.
  /// [permissionConfirmed] is the presentation layer's retained, protected
  /// `users.view` decision. It lets an enforced viewer refresh without
  /// inheriting the old configuration roles. The Edge Function repeats the
  /// capability check and remains the authority even if a caller is tampered.
  Future<void> refreshFromServer({bool permissionConfirmed = false}) {
    final active = _directoryRefreshInFlight;
    if (active != null) return active;
    final operation = _refreshFromServerOnce(
      permissionConfirmed: permissionConfirmed,
    );
    _directoryRefreshInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_directoryRefreshInFlight, operation)) {
        _directoryRefreshInFlight = null;
      }
    });
  }

  Future<void> _refreshFromServerOnce({
    required bool permissionConfirmed,
  }) async {
    if (_client == null) return;
    if (_usesYorksV1IdentityProvisioning) {
      final exactRole = YorksV1Role.fromServerClaim(
        _client?.auth.currentUser?.appMetadata['role'],
      );
      if (!permissionConfirmed && !(exactRole?.canConfigureUsers ?? false)) {
        throw StateError(
          'A confirmed users.view permission is required to refresh the user directory.',
        );
      }
    }
    final response = await _adminFn({'action': 'list'});
    final rows = response?['users'];
    if (rows is! List) return;
    final previous = {for (final user in state) user.id: user};
    final refreshed = <AppUser>[];
    for (final raw in rows) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final id = _string(row['appUserId']) ?? _string(row['authUserId']);
      if (id == null) continue;
      final primary = YorksV1Role.fromServerClaim(row['role']);
      final effectiveRoles = primary == null
          ? const <YorksV1Role>[]
          : <YorksV1Role>[primary];
      final existing = previous[id];
      final compatibilityRole = primary == null
          ? existing?.role ?? UserRole.engineer
          : _compatibilityShellRoleForYorksV1(primary);
      final createdAt =
          DateTime.tryParse(_string(row['createdAt']) ?? '') ??
          existing?.createdAt ??
          DateTime.now();
      final candidate = AppUser(
        id: id,
        fullName: _string(row['fullName']) ?? existing?.fullName ?? id,
        email: _string(row['email']) ?? existing?.email ?? '',
        role: compatibilityRole,
        active: row['active'] as bool? ?? true,
        inventoryAccess: existing?.inventoryAccess ?? true,
        createdAt: createdAt,
        mustChangePassword: existing?.mustChangePassword ?? false,
        employeeId: existing?.employeeId,
        canSeeCostOverride: existing?.canSeeCostOverride,
        canViewFinanceOverride: existing?.canViewFinanceOverride,
        canSeeSalaryOverride: existing?.canSeeSalaryOverride,
        canAccessRentalsOverride: existing?.canAccessRentalsOverride,
        canAccessPeopleOverride: existing?.canAccessPeopleOverride,
        canReceiveGoodsOverride: existing?.canReceiveGoodsOverride,
        yorksV1RoleCache: primary,
        yorksV1Roles: effectiveRoles,
      );
      refreshed.add(
        existing != null && _sameUser(existing, candidate)
            ? existing
            : candidate,
      );
    }
    if (_sameUserLists(state, refreshed)) return;
    state = refreshed;
    await _store.writeAll(state);
  }

  bool _sameUserLists(List<AppUser> left, List<AppUser> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!identical(left[index], right[index]) &&
          !_sameUser(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }

  bool _sameUser(AppUser left, AppUser right) {
    return left.id == right.id &&
        left.fullName == right.fullName &&
        left.email == right.email &&
        left.role == right.role &&
        left.active == right.active &&
        left.inventoryAccess == right.inventoryAccess &&
        left.createdAt == right.createdAt &&
        left.passwordHash == right.passwordHash &&
        left.passwordSalt == right.passwordSalt &&
        left.mustChangePassword == right.mustChangePassword &&
        left.employeeId == right.employeeId &&
        left.canSeeCostOverride == right.canSeeCostOverride &&
        left.canViewFinanceOverride == right.canViewFinanceOverride &&
        left.canSeeSalaryOverride == right.canSeeSalaryOverride &&
        left.canAccessRentalsOverride == right.canAccessRentalsOverride &&
        left.canAccessPeopleOverride == right.canAccessPeopleOverride &&
        left.canReceiveGoodsOverride == right.canReceiveGoodsOverride &&
        left.yorksV1RoleCache == right.yorksV1RoleCache &&
        _sameRoles(left.yorksV1Roles, right.yorksV1Roles);
  }

  String? _string(Object? value) {
    final text = value is String ? value.trim() : '';
    return text.isEmpty ? null : text;
  }

  bool get _usesYorksV1IdentityProvisioning =>
      _ref.read(yorksV1UserProvisioningEnabledProvider);

  /// The retained-shell capabilities to stamp into legacy JWT claims. This
  /// calculation is deliberately unavailable to the V1 exact-role commands:
  /// V1 commercial authorization is resolved by protected database rules.
  List<String> _claimCaps(AppUser user) {
    final permissions = _ref.read(rolePermissionsProvider);
    return [
      for (final capability in RoleCapability.values)
        if (resolveCapability(user, user.role, permissions, capability))
          capability.name,
    ];
  }

  /// Marks a request as the flag-off compatibility shell, allowing the Edge
  /// Function to apply its fixed legacy capability allow-list. The server never
  /// copies these values blindly, and Yorks V1 requests must not use this map.
  Map<String, dynamic> _legacyShellClaimPayload(AppUser user) => {
    'legacyShell': true,
    'caps': _claimCaps(user),
  };

  /// Refresh every (non-admin) account of [role] after the retained legacy role
  /// matrix changes. Exact V1 claims receive only server-owned defaults;
  /// legacy-engineer records use their quarantined compatibility endpoint. A
  /// no-op (returns 0) when Supabase isn't configured (tests / offline).
  ///
  /// Returns the number of users whose re-stamp FAILED. One user's failure
  /// doesn't block the rest, but the count is surfaced to the admin rather than
  /// swallowed — a partial failure means those users' server-side access lags
  /// the matrix until they next sign in (which re-issues a fresh claim).
  Future<int> restampRoleClaims(UserRole role) async {
    // V1 commercial permissions are resolved by protected database
    // capabilities, not legacy JWT `caps`. Do not send a legacy role string to
    // the exact-role Edge Function while V1 provisioning is active.
    if (_usesYorksV1IdentityProvisioning ||
        _client == null ||
        role == UserRole.admin) {
      return 0;
    }
    var failures = 0;
    for (final u in state) {
      if (u.role != role) continue;
      final legacyClaims = _legacyShellClaimPayload(u);
      final caps = List<String>.from(legacyClaims['caps'] as List);
      final commandFingerprint = [
        _legacyClaimActionFor(u.role),
        u.id,
        u.role.name,
        caps.join(','),
      ].join('|');
      final idempotencyKey = _pendingRestampIdempotencyKeys.putIfAbsent(
        commandFingerprint,
        () => _uuid.v4(),
      );
      try {
        await _adminFn({
          'action': _legacyClaimActionFor(u.role),
          'appUserId': u.id,
          'role': u.role.name,
          'idempotencyKey': idempotencyKey,
          ...legacyClaims,
        });
        _pendingRestampIdempotencyKeys.remove(commandFingerprint);
      } catch (_) {
        failures++;
      }
    }
    return failures;
  }

  /// Calls the privileged `admin-users` gateway. A no-op (returns null) when no
  /// Supabase backend is configured — widget tests and pure-offline dev keep the
  /// legacy local-only behaviour. Throws on a remote failure so the caller can
  /// surface it and NOT apply the local change (keeps the two in step).
  Future<Map<String, dynamic>?> _adminFn(Map<String, dynamic> body) async {
    // Every Auth-mutating command carries a client-generated idempotency key.
    // The Edge Function converts this into transient, server-validated audit
    // context; Postgres atomically deduplicates the trusted audit effect. UI
    // busy guards prevent duplicate taps, while a caller can provide a stable
    // key explicitly when it owns an application-level retry.
    const mutatingActions = {
      'create',
      'createLegacy',
      'updateClaims',
      'updateLegacyClaims',
      'setPassword',
      'setActive',
    };
    final action = body['action'];
    final command = action is String && mutatingActions.contains(action)
        ? {...body, 'idempotencyKey': body['idempotencyKey'] ?? _uuid.v4()}
        : body;
    return _ref.read(adminUsersInvocationProvider)(command);
  }

  /// The isolated legacy endpoint can only carry the ambiguous historical
  /// `engineer` role. Procurement and Admin retain their exact role literals
  /// and therefore use the normal server allow-list even while V1 UI is off.
  String _legacyCreateActionFor(UserRole role) {
    return _client != null && role == UserRole.engineer
        ? 'createLegacy'
        : 'create';
  }

  String _legacyClaimActionFor(UserRole role) {
    return _client != null && role == UserRole.engineer
        ? 'updateLegacyClaims'
        : 'updateClaims';
  }

  Future<AppUser> createUser({
    required String fullName,
    required String email,
    required UserRole role,
    required String password,
    String? idempotencyKey,
    String? appUserId,
  }) async {
    if (_usesYorksV1IdentityProvisioning) {
      throw StateError(
        'Use the exact Yorks V1 role provisioning command while V1 is enabled.',
      );
    }
    final id = appUserId ?? 'usr-${_uuid.v4().substring(0, 8)}';
    final draft = AppUser(
      id: id,
      fullName: fullName,
      email: email,
      role: role,
      yorksV1RoleCache: _client == null
          ? null
          : YorksV1Role.fromServerClaim(role.name),
      createdAt: DateTime.now(),
    );
    // Provision in the identity provider first; a failure (e.g. duplicate email)
    // throws before anything is written locally.
    await _adminFn({
      'action': _legacyCreateActionFor(role),
      'email': email,
      'password': password,
      'fullName': fullName,
      'role': role.name,
      'appUserId': id,
      'idempotencyKey': ?idempotencyKey,
      ..._legacyShellClaimPayload(draft),
    });
    final pw = _client == null
        ? PasswordHasher.create(password)
        : (hash: '', salt: '');
    final user = draft.copyWith(
      passwordHash: pw.hash,
      passwordSalt: pw.salt,
      // The admin set a temporary password; the user changes it on first login.
      mustChangePassword: true,
    );
    state = [user, ...state.where((existing) => existing.id != user.id)];
    await _store.writeAll(state);
    return user;
  }

  /// Provisions a connected Yorks V1 identity with one exact accepted server
  /// role claim. The retained [AppUser.role] is written only
  /// as a downward compatibility-shell projection; it is never used to infer a
  /// V1 role and legacy `engineer` records are never promoted by this method.
  Future<AppUser> createYorksV1User({
    required String fullName,
    required String email,
    required YorksV1Role role,
    required String password,
    String? idempotencyKey,
    String? appUserId,
  }) async {
    _requireYorksV1IdentityProvisioning();

    final id = appUserId ?? 'usr-${_uuid.v4().substring(0, 8)}';
    final draft = AppUser(
      id: id,
      fullName: fullName,
      email: email,
      role: _compatibilityShellRoleForYorksV1(role),
      yorksV1RoleCache: role,
      yorksV1Roles: <YorksV1Role>[role],
      createdAt: DateTime.now(),
    );
    // The Edge Function owns the exact role allow-list and all default claim
    // capabilities. Do not send client-calculated legacy caps with V1 roles.
    await _adminFn({
      'action': 'create',
      'email': email,
      'password': password,
      'fullName': fullName,
      'role': role.claimValue,
      'appUserId': id,
      'idempotencyKey': ?idempotencyKey,
    });
    final user = draft.copyWith(
      passwordHash: '',
      passwordSalt: '',
      // The admin set a temporary password; the user changes it on first login.
      mustChangePassword: true,
    );
    state = [user, ...state.where((existing) => existing.id != user.id)];
    await _store.writeAll(state);
    return user;
  }

  /// Materialise a user from their JWT claims when they aren't already in this
  /// device's roster (they were provisioned on another device). Existing records
  /// retain local overrides / employee links while trusted claim projections are
  /// refreshed.
  Future<void> upsertFromClaims({
    required String id,
    required String email,
    required UserRole role,
    required YorksV1Role? yorksV1Role,
    required String fullName,
    bool mustChangePassword = false,
  }) async {
    final exactRoles = yorksV1Role == null
        ? const <YorksV1Role>[]
        : <YorksV1Role>[yorksV1Role];
    final existing = _byId(id);
    if (existing != null) {
      // A legacy engineer still receives `null` for [yorksV1Role], so it cannot
      // become either V1 engineering role through this reconciliation.
      if (existing.mustChangePassword != mustChangePassword ||
          existing.role != role ||
          existing.yorksV1RoleCache != yorksV1Role ||
          !_sameRoles(existing.yorksV1Roles, exactRoles)) {
        state = [
          for (final u in state)
            if (u.id == id)
              u.copyWith(
                role: role,
                yorksV1RoleCache: yorksV1Role,
                yorksV1Roles: exactRoles,
                mustChangePassword: mustChangePassword,
              )
            else
              u,
        ];
        await _store.writeAll(state);
      }
      return;
    }
    final user = AppUser(
      id: id,
      fullName: fullName.trim().isEmpty ? email : fullName,
      email: email,
      role: role,
      yorksV1RoleCache: yorksV1Role,
      yorksV1Roles: exactRoles,
      mustChangePassword: mustChangePassword,
      createdAt: DateTime.now(),
    );
    state = [user, ...state];
    await _store.writeAll(state);
  }

  bool _sameRoles(List<YorksV1Role> left, List<YorksV1Role> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  Future<void> update(AppUser updated) async {
    state = [
      for (final u in state)
        if (u.id == updated.id) updated else u,
    ];
    await _store.writeAll(state);
  }

  AppUser? _byId(String id) {
    for (final u in state) {
      if (u.id == id) return u;
    }
    return null;
  }

  /// True if [id] is the ONLY currently-active admin — used to block the last
  /// admin from being demoted or deactivated, which would lock everyone out of
  /// the admin panel with no in-app recovery.
  bool _isLastActiveAdmin(String id) {
    final admins = state.where((u) => u.role == UserRole.admin && u.active);
    return admins.length == 1 && admins.first.id == id;
  }

  /// Update ONLY the local roster's password hash + must-change flag, WITHOUT
  /// calling the privileged admin Edge Function. Used by self-service password
  /// change ([AuthController.changeOwnPassword]), where the identity provider is
  /// updated separately via the caller's own GoTrue self-update — so a non-admin
  /// never has to (and can't) hit the admin-only function. Keeps local + cloud
  /// in step for the credential fallback / offline sign-in.
  Future<void> applyLocalPassword(
    String id,
    String newPassword, {
    required bool mustChange,
  }) async {
    final pw = _client == null
        ? PasswordHasher.create(newPassword)
        : (hash: '', salt: '');
    state = [
      for (final u in state)
        if (u.id == id)
          u.copyWith(
            passwordHash: pw.hash,
            passwordSalt: pw.salt,
            mustChangePassword: mustChange,
          )
        else
          u,
    ];
    await _store.writeAll(state);
  }

  /// Set a new password. [temporary] true (admin reset) forces a change on next
  /// sign-in; false (user changed their own) clears the flag.
  Future<void> setPassword(
    String id,
    String newPassword, {
    bool temporary = false,
    String? idempotencyKey,
  }) async {
    await _adminFn({
      'action': 'setPassword',
      'appUserId': id,
      'password': newPassword,
      'idempotencyKey': ?idempotencyKey,
    });
    final pw = _client == null
        ? PasswordHasher.create(newPassword)
        : (hash: '', salt: '');
    state = [
      for (final u in state)
        if (u.id == id)
          u.copyWith(
            passwordHash: pw.hash,
            passwordSalt: pw.salt,
            mustChangePassword: temporary,
          )
        else
          u,
    ];
    await _store.writeAll(state);
  }

  /// Activate/deactivate an account. Refuses to deactivate the last active admin
  /// (would lock everyone out). Returns false if blocked. A deactivated user is
  /// banned in the identity provider, so they can no longer sign in on ANY device.
  Future<bool> setActive(
    String id,
    bool active, {
    String? idempotencyKey,
  }) async {
    if (!active && _isLastActiveAdmin(id)) return false;
    await _adminFn({
      'action': 'setActive',
      'appUserId': id,
      'active': active,
      'idempotencyKey': ?idempotencyKey,
    });
    state = [
      for (final u in state)
        if (u.id == id) u.copyWith(active: active) else u,
    ];
    await _store.writeAll(state);
    return true;
  }

  /// Inventory access is an engineer-only flag (office roles get materials via
  /// their own tabs) — ignore it for any other role. Local-only (not an identity
  /// concern), so no remote call.
  Future<void> setInventoryAccess(String id, bool access) async {
    if (_byId(id)?.role != UserRole.engineer) return;
    state = [
      for (final u in state)
        if (u.id == id) u.copyWith(inventoryAccess: access) else u,
    ];
    await _store.writeAll(state);
  }

  /// Set (or clear, with `null`) a retained-shell permission override. Clearing
  /// returns that capability to the role default. V1 authorization never reads
  /// this local compatibility state; its protected capability rules remain
  /// server-owned and this method fails closed while V1 provisioning is active.
  Future<void> setPermissionOverride(
    String id,
    PermissionKey key,
    bool? value, {
    String? idempotencyKey,
  }) async {
    if (_usesYorksV1IdentityProvisioning) {
      throw StateError(
        'Yorks V1 capabilities are controlled by protected server rules.',
      );
    }
    // Admin always hard-grants everything, so an override would be dead state.
    final current = _byId(id);
    if (current == null || current.role == UserRole.admin) return;
    final updated = _applyOverride(current, key, value);
    await _adminFn({
      'action': _legacyClaimActionFor(updated.role),
      'appUserId': id,
      'role': updated.role.name,
      'idempotencyKey': ?idempotencyKey,
      ..._legacyShellClaimPayload(updated),
    });
    state = [
      for (final u in state)
        if (u.id == id) updated else u,
    ];
    await _store.writeAll(state);
  }

  AppUser _applyOverride(AppUser u, PermissionKey key, bool? value) =>
      switch (key) {
        PermissionKey.viewCommercials => u.copyWith(canSeeCostOverride: value),
        PermissionKey.finance => u.copyWith(canViewFinanceOverride: value),
        PermissionKey.salary => u.copyWith(canSeeSalaryOverride: value),
        PermissionKey.rentals => u.copyWith(canAccessRentalsOverride: value),
        PermissionKey.people => u.copyWith(canAccessPeopleOverride: value),
        PermissionKey.goods => u.copyWith(canReceiveGoodsOverride: value),
      };

  /// Change a user's role (changes which side they load on next sign-in, and
  /// re-stamps their JWT role/caps claims). Refuses to demote the last active
  /// admin. Returns false if blocked.
  Future<bool> setRole(
    String id,
    UserRole role, {
    String? idempotencyKey,
  }) async {
    if (_usesYorksV1IdentityProvisioning) {
      throw StateError(
        'Use the exact Yorks V1 role command while V1 is enabled.',
      );
    }
    if (role != UserRole.admin && _isLastActiveAdmin(id)) return false;
    final current = _byId(id);
    if (current == null) return false;
    final updated = current.copyWith(
      role: role,
      yorksV1RoleCache: _client == null
          ? null
          : YorksV1Role.fromServerClaim(role.name),
    );
    await _adminFn({
      'action': _legacyClaimActionFor(role),
      'appUserId': id,
      'role': role.name,
      'idempotencyKey': ?idempotencyKey,
      ..._legacyShellClaimPayload(updated),
    });
    state = [
      for (final u in state)
        if (u.id == id) updated else u,
    ];
    await _store.writeAll(state);
    return true;
  }

  /// Explicitly maps a roster account to an exact Yorks V1 role. This is the
  /// only retained User Management path that can turn a legacy `engineer`
  /// account into a V1 Project Engineer or Site Engineer, and it does so only
  /// after the server accepts the Admin's command.
  Future<bool> setYorksV1Role(
    String id,
    YorksV1Role role, {
    String? idempotencyKey,
  }) async {
    _requireYorksV1IdentityProvisioning();
    if (role != YorksV1Role.admin && _isLastActiveAdmin(id)) return false;
    final current = _byId(id);
    if (current == null) return false;
    final updated = current.copyWith(
      role: _compatibilityShellRoleForYorksV1(role),
      yorksV1RoleCache: role,
      yorksV1Roles: <YorksV1Role>[role],
    );
    await _adminFn({
      'action': 'updateClaims',
      'appUserId': id,
      'role': role.claimValue,
      'idempotencyKey': ?idempotencyKey,
    });
    state = [
      for (final u in state)
        if (u.id == id) updated else u,
    ];
    await _store.writeAll(state);
    return true;
  }

  void _requireYorksV1IdentityProvisioning() {
    if (_usesYorksV1IdentityProvisioning) return;
    throw StateError(
      'Yorks V1 role provisioning requires an enabled connected V1 foundation.',
    );
  }

  /// Safe one-way compatibility mapping. This deliberately has no inverse:
  /// [UserRole.engineer] alone is never evidence of a Yorks V1 role.
  static UserRole _compatibilityShellRoleForYorksV1(YorksV1Role role) =>
      switch (role) {
        YorksV1Role.projectEngineer ||
        YorksV1Role.siteEngineer ||
        YorksV1Role.seniorMechanicalEngineer ||
        YorksV1Role.projectManager ||
        YorksV1Role.workshopInCharge ||
        YorksV1Role.documentController => UserRole.engineer,
        YorksV1Role.accountant => UserRole.accountant,
        YorksV1Role.pr => UserRole.pr,
        YorksV1Role.procurement => UserRole.procurement,
        YorksV1Role.admin => UserRole.admin,
      };

  /// Deletes only an offline/local development account. Connected identities
  /// may already be referenced by project and audit history, so the server
  /// path deactivates them rather than issuing an irreversible Auth deletion.
  /// Returns false when the last active Admin would be affected.
  Future<bool> deleteUser(String id, {String? idempotencyKey}) async {
    if (_isLastActiveAdmin(id)) return false;
    if (_client != null) {
      await _adminFn({
        'action': 'setActive',
        'appUserId': id,
        'active': false,
        'idempotencyKey': ?idempotencyKey,
      });
      state = [
        for (final user in state)
          if (user.id == id) user.copyWith(active: false) else user,
      ];
    } else {
      state = state.where((u) => u.id != id).toList();
    }
    await _store.writeAll(state);
    return true;
  }

  /// Link (or unlink, with `null`) this login to an HR roster [Employee] — so
  /// the person's leave requests, balance, and HR profile become one record.
  /// Local-only (an HR mapping, not an identity-provider concern). An employee
  /// maps to exactly one login, so a duplicate link is rejected. Returns false
  /// if blocked.
  Future<bool> setEmployeeLink(String id, String? employeeId) async {
    if (employeeId != null &&
        state.any((u) => u.id != id && u.employeeId == employeeId)) {
      return false;
    }
    state = [
      for (final u in state)
        if (u.id == id) u.copyWith(employeeId: employeeId) else u,
    ];
    await _store.writeAll(state);
    return true;
  }

  static List<AppUser> _seed(String seedPassword) {
    final now = DateTime.now();
    AppUser seed({
      required String id,
      required String fullName,
      required String email,
      required UserRole role,
      required DateTime createdAt,
      String? employeeId,
    }) {
      final pw = seedPassword.isEmpty
          ? (hash: '', salt: '')
          : PasswordHasher.create(seedPassword);
      return AppUser(
        id: id,
        fullName: fullName,
        email: email,
        role: role,
        createdAt: createdAt,
        passwordHash: pw.hash,
        passwordSalt: pw.salt,
        employeeId: employeeId,
      );
    }

    // Exactly one account per role, so the dev role-switcher signs into a
    // distinct person each time (not one identity wearing three hats).
    return [
      seed(
        id: 'usr-admin',
        fullName: 'Owner',
        email: 'owner@gmail.com',
        role: UserRole.admin,
        createdAt: DateTime(now.year - 2, 1, 1),
      ),
      seed(
        id: 'usr-proc',
        fullName: 'Al Asad',
        email: 'alasad@gmail.com',
        role: UserRole.procurement,
        createdAt: DateTime(now.year - 2, 7, 10),
        employeeId: 'emp-002', // linked to the HR roster
      ),
      seed(
        id: 'usr-eng',
        fullName: 'Imran Khan',
        email: 'imrankhan@gmail.com',
        role: UserRole.engineer,
        createdAt: DateTime(now.year - 3, 2, 1),
        employeeId: 'emp-001', // linked to the HR roster
      ),
    ];
  }
}

/// Active-account count (admin dashboard figure).
final activeUserCountProvider = Provider<int>((ref) {
  return ref.watch(usersProvider).where((u) => u.active).length;
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/role_permissions.dart';
import '../models/user_role.dart';
import '../repositories/collection_store.dart';
import '../repositories/storage.dart';
import '../sync/sync_engine.dart';
import 'users_provider.dart';

const _kRolePermsKey = 'role_permissions_v1';

/// Admin-editable role-level permission defaults. Persisted (and Firebase-ready
/// via the sync seam); seeded from the `UserRole` baseline so behaviour is
/// unchanged until an Admin edits the Access & Roles matrix.
final rolePermissionsProvider =
    StateNotifierProvider<RolePermissionsNotifier, RolePermissions>((ref) {
      return RolePermissionsNotifier(
        ref,
        ref
            .watch(storageProvider)
            .collection<RolePermissions>(
              _kRolePermsKey,
              toJson: (p) => p.toJson(),
              fromJson: RolePermissions.fromJson,
            ),
      );
    });

class RolePermissionsNotifier extends StateNotifier<RolePermissions> {
  RolePermissionsNotifier(this._ref, this._store) : super(_load(_store)) {
    if (!_store.isSeeded) _store.writeAll([state]);
  }

  final Ref _ref;
  final CollectionStore<RolePermissions> _store;

  static RolePermissions _load(CollectionStore<RolePermissions> store) {
    if (!store.isSeeded) return RolePermissions.fromRoleDefaults();
    final all = store.readAll();
    return all.isEmpty ? RolePermissions.fromRoleDefaults() : all.first;
  }

  Future<void> _persist() async {
    await _store.writeAll([state]);
    // Config change → route through the outbox (idempotent on a single doc).
    await _ref.enqueueSync(
      collection: 'config',
      docId: 'rolePermissions',
      kind: 'rolePermissions.update',
      label: 'Role permissions',
      payload: state.toJson(),
    );
  }

  /// Grant/revoke [cap] for [role] (Admin/structural caps are ignored). After
  /// persisting, the affected role's users have their JWT caps re-stamped so the
  /// server enforces exactly what the matrix now shows. Returns the number of
  /// users whose re-stamp failed (0 = fully applied), so the UI can tell the
  /// admin if some users' server-side access lags the matrix.
  Future<int> setCapability(
    UserRole role,
    RoleCapability cap,
    bool value,
  ) async {
    final next = state.setCapability(role, cap, value);
    if (identical(next, state)) return 0; // not editable → no-op
    state = next;
    await _persist();
    return _ref.read(usersProvider.notifier).restampRoleClaims(role);
  }

  Future<int> resetRole(UserRole role) async {
    state = state.resetRole(role);
    await _persist();
    return _ref.read(usersProvider.notifier).restampRoleClaims(role);
  }

  Future<int> resetAll() async {
    state = RolePermissions.fromRoleDefaults();
    await _persist();
    var failures = 0;
    for (final role in editableRoles) {
      failures += await _ref
          .read(usersProvider.notifier)
          .restampRoleClaims(role);
    }
    return failures;
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/role_permissions.dart';
import '../models/yorks_v1_permission_management.dart';
import 'role_permissions_provider.dart';
import 'session_provider.dart';
import 'language_provider.dart' show supabaseClientProvider;
import 'yorks_v1_feature_flags_provider.dart';
import 'yorks_v1_identity_provider.dart';
import 'yorks_v1_permission_provider.dart';

/// Effective-capability providers — the single place UI/guards read access from.
/// Resolution layers (highest wins): per-user override → editable role default
/// (Access & Roles matrix) → built-in `UserRole` baseline. Watching
/// [rolePermissionsProvider] is what makes an Admin's matrix edits take effect
/// across the app instantly.
bool _cap(Ref ref, RoleCapability cap) {
  final user = ref.watch(currentUserProvider);
  final role = ref.watch(currentRoleProvider);
  final perms = ref.watch(rolePermissionsProvider);
  return resolveCapability(user, role, perms, cap);
}

/// The retained capability matrix remains the authority for the flag-off
/// legacy shell. An exact connected V1 identity instead waits for the protected
/// current-session snapshot. Loading/failure is deny-by-default, which lets a
/// revocation signal purge cost projections before any later reload.
bool _usesProtectedYorksV1CommercialAuthority(Ref ref) {
  final flags = ref.watch(yorksV1FeatureFlagsProvider);
  return flags.foundation &&
      ref.watch(supabaseClientProvider) != null &&
      ref.watch(yorksV1CurrentRoleProvider) != null;
}

/// Reuses the global current-session permission snapshot for the two
/// commercial boundaries. This avoids a second capability RPC and two extra
/// Realtime channels while preserving the original fail-closed guarantee.
///
/// A plain confirmed snapshot is not sufficient: commercial projections are
/// trusted only while the user is active, the revision signal is healthy and
/// no permission replacement is pending. Postgres RLS/RPC checks remain the
/// final authority for every protected read and command.
bool yorksV1TrustedCommercialAccess(
  YorksV1CurrentPermissionSnapshotState state,
  String capabilityKey,
) =>
    state.error == null &&
    // Commercial values are a stricter read boundary than ordinary workflow
    // CTAs: revoke local cost visibility when invalidation health is unknown.
    state.isRevisionSignalHealthy &&
    state.isTrustedForWrites &&
    state.allows(capabilityKey);

final canViewCommercialsProvider = Provider<bool>((ref) {
  if (!_usesProtectedYorksV1CommercialAuthority(ref)) {
    return _cap(ref, RoleCapability.viewCommercials);
  }
  return yorksV1TrustedCommercialAccess(
    ref.watch(yorksV1CurrentPermissionSnapshotProvider),
    YorksV1CapabilityKeys.commercialsView,
  );
});

/// V1 commercial writes require the separate protected `manage_commercials`
/// capability. Legacy deployments retain their historical view/write policy
/// until their account is explicitly moved to an exact V1 identity.
final canManageCommercialsProvider = Provider<bool>((ref) {
  if (!_usesProtectedYorksV1CommercialAuthority(ref)) {
    return _cap(ref, RoleCapability.viewCommercials);
  }
  return yorksV1TrustedCommercialAccess(
    ref.watch(yorksV1CurrentPermissionSnapshotProvider),
    YorksV1CapabilityKeys.commercialsManage,
  );
});

/// Transitional alias for existing cost-aware widgets.
final canSeeCostProvider = Provider<bool>(
  (ref) => ref.watch(canViewCommercialsProvider),
);
final canViewFinanceProvider = Provider<bool>(
  (ref) => _cap(ref, RoleCapability.finance),
);
final canSeeSalaryProvider = Provider<bool>(
  (ref) => _cap(ref, RoleCapability.salary),
);
final canAccessRentalsProvider = Provider<bool>(
  (ref) => _cap(ref, RoleCapability.rentals),
);
final canAccessPeopleProvider = Provider<bool>(
  (ref) => _cap(ref, RoleCapability.people),
);
final canReceiveGoodsProvider = Provider<bool>(
  (ref) => _cap(ref, RoleCapability.goods),
);

// Writes require both the (possibly overridden) access AND the role-level write
// right — revoking access revokes writing too.
final canWriteRentalsProvider = Provider<bool>(
  (ref) =>
      _cap(ref, RoleCapability.rentals) &&
      _cap(ref, RoleCapability.writeRentals),
);
final canWritePeopleProvider = Provider<bool>(
  (ref) =>
      _cap(ref, RoleCapability.people) && _cap(ref, RoleCapability.writePeople),
);

// Approve/reject engineer leave requests (procurement & admin; editable).
final canApproveLeaveProvider = Provider<bool>(
  (ref) => _cap(ref, RoleCapability.approveLeave),
);

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_role.dart';
import '../models/yorks_v1_role.dart';
import 'language_provider.dart'
    show authSessionProvider, supabaseClientProvider;
import 'session_provider.dart'
    show authSessionRevisionProvider, currentRoleProvider, currentUserProvider;
import 'users_provider.dart' show localDemoPasswordProvider;

/// The immutable Supabase Auth identity for V1 local-draft isolation. In the
/// explicit local demo build only, the seeded local account ID is used for
/// creator-owned draft recovery; production and connected builds remain Auth
/// JWT based.
final yorksV1AuthUserIdProvider = Provider<String?>((ref) {
  // The Supabase client instance is stable across sign-in/out. Watching the
  // session revision makes this projection refresh on token/user updates too,
  // without treating the legacy app-user ID as authority.
  ref.watch(authSessionProvider);
  ref.watch(authSessionRevisionProvider);
  final client = ref.watch(supabaseClientProvider);
  final authUserId = client?.auth.currentUser?.id;
  if (authUserId != null) return authUserId;

  // Local-only identity for the interactive demo. Committed V1 commands still
  // stop at their repository backend guard until Supabase is configured.
  if (client == null && ref.read(localDemoPasswordProvider).trim().isNotEmpty) {
    return ref.watch(currentUserProvider)?.id;
  }
  return null;
});

/// V1 client eligibility reads only the exact, server-controlled JWT
/// `app_metadata.role` claim. Missing, altered or legacy claims resolve to no
/// privileged V1 role and remain fail-closed.
final yorksV1CurrentRoleProvider = Provider<YorksV1Role?>((ref) {
  // This is an invalidation trigger only. The exact V1 role still comes solely
  // from the current Supabase Auth user's server-controlled app metadata.
  ref.watch(authSessionProvider);
  ref.watch(authSessionRevisionProvider);
  final appMetadata = ref
      .watch(supabaseClientProvider)
      ?.auth
      .currentUser
      ?.appMetadata;
  final serverRole = YorksV1Role.fromServerClaim(appMetadata?['role']);
  if (serverRole != null) return serverRole;

  // The explicit local demo build has no Auth JWT by design. Give its three
  // fixed local personas a V1 presentation role so the complete transformed
  // UI can be demonstrated without weakening connected-environment
  // authorization. This branch is unreachable unless local development was
  // explicitly compiled with LOCAL_DEMO_PASSWORD; Supabase builds remain
  // strictly claim-based and fail closed when a claim is absent.
  final client = ref.read(supabaseClientProvider);
  if (client == null && ref.read(localDemoPasswordProvider).trim().isNotEmpty) {
    return switch (ref.watch(currentRoleProvider)) {
      // The local engineer persona is the seeded Project Engineer demo.
      // A real connected account must receive project_engineer from the JWT.
      UserRole.engineer => YorksV1Role.projectEngineer,
      UserRole.procurement => YorksV1Role.procurement,
      UserRole.accountant => YorksV1Role.accountant,
      UserRole.pr => YorksV1Role.pr,
      UserRole.admin => YorksV1Role.admin,
    };
  }
  return null;
});

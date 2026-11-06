import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/language_provider.dart';
import '../../../shared/providers/yorks_v1_feature_flags_provider.dart';
import '../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../../shared/providers/yorks_v1_permission_provider.dart';
import '../../../shared/services/yorks_v1_critical_command_key_store.dart';
import '../../../shared/sync/connectivity_service.dart';
import '../data/accounts_repository.dart';
import '../data/accounts_evidence_repository.dart';
import '../../../shared/providers/yorks_v1_documents_repository_provider.dart';
import 'accounts_controller.dart';

final yorksAccountsRpcClientProvider = Provider<YorksAccountsRpcClient?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseYorksAccountsRpcClient(client);
});

final yorksAccountsRepositoryProvider = Provider<YorksAccountsRepository>((
  ref,
) {
  return YorksSupabaseAccountsRepository(
    featureFlags: ref.watch(yorksV1FeatureFlagsProvider),
    connectivity: ref.watch(connectivityProvider),
    rpcClient: ref.watch(yorksAccountsRpcClientProvider),
  );
});

/// Ephemeral project-scoped evidence access. Never caches document bytes.
final yorksAccountsEvidenceRepositoryProvider =
    Provider<YorksAccountsEvidenceRepository>((ref) {
      ref.watch(yorksV1CurrentRoleProvider);
      ref.watch(yorksAccountsPermissionEpochProvider);
      final rpc = ref.watch(yorksAccountsRpcClientProvider);
      if (rpc == null) {
        throw StateError('Accounts evidence backend unavailable.');
      }
      return YorksSupabaseAccountsEvidenceRepository(
        rpcClient: rpc,
        documentsRepository: ref.watch(yorksV1DocumentsRepositoryProvider),
      );
    });

typedef YorksAccountsPermissionEpoch = ({
  int? revision,
  bool trusted,
  bool stale,
  bool revisionSignalHealthy,
});

/// Small, overrideable invalidation seam. It carries no commercial values.
final yorksAccountsPermissionEpochProvider =
    Provider<YorksAccountsPermissionEpoch>(
      (ref) => ref.watch(
        yorksV1CurrentPermissionSnapshotProvider.select(
          (state) => (
            revision: state.snapshot?.revision,
            trusted: state.isTrustedForWrites,
            stale: state.isStale,
            revisionSignalHealthy: state.isRevisionSignalHealthy,
          ),
        ),
      ),
    );

/// No route or screen consumes this provider until the later R39 UI rollout.
/// It already watches the immutable auth identity so a role/session change
/// disposes the old controller and its protected in-memory projection.
final yorksAccountsProjectControllerProvider = StateNotifierProvider.autoDispose
    .family<YorksAccountsProjectController, YorksAccountsProjectState, String>((
      ref,
      projectId,
    ) {
      // Route changes must not discard a confirmed project ledger. Watched
      // authority inputs still recreate the provider immediately on access
      // or identity changes, so protected data never survives revocation.
      ref.keepAlive();
      // Recreate even when a token refresh keeps the same auth-user ID but
      // changes the exact server-controlled role claim.
      ref.watch(yorksV1CurrentRoleProvider);
      // Revision and trust changes dispose protected cached projections. This
      // includes same-role person-specific capability revocation.
      ref.watch(yorksAccountsPermissionEpochProvider);
      final actorAuthUserId = ref.watch(yorksV1AuthUserIdProvider) ?? '';
      return YorksAccountsProjectController(
        projectId: projectId,
        repository: ref.watch(yorksAccountsRepositoryProvider),
        commandKeys: YorksV1CriticalCommandKeyStore(
          preferences: ref.watch(sharedPreferencesProvider),
          actorAuthUserId: actorAuthUserId,
        ),
      );
    });

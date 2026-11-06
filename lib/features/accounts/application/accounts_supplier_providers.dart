import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/language_provider.dart';
import '../../../shared/providers/yorks_v1_feature_flags_provider.dart';
import '../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../../shared/services/yorks_v1_critical_command_key_store.dart';
import '../../../shared/sync/connectivity_service.dart';
import '../data/accounts_supplier_repository.dart';
import '../domain/accounts_supplier_models.dart';
import 'accounts_providers.dart';
import 'accounts_supplier_controller.dart';

final yorksAccountsSupplierRepositoryProvider =
    Provider<YorksAccountsSupplierRepository>((ref) {
      return YorksSupabaseAccountsSupplierRepository(
        featureFlags: ref.watch(yorksV1FeatureFlagsProvider),
        connectivity: ref.watch(connectivityProvider),
        rpcClient: ref.watch(yorksAccountsRpcClientProvider),
      );
    });

/// Confirmed deliveries a supplier bill on the project can cite.
final yorksAccountsSupplierDeliveryOptionsProvider = FutureProvider.autoDispose
    .family<List<YorksAccountsAcceptedDelivery>, String>(
      (ref, projectId) => ref
          .watch(yorksAccountsSupplierRepositoryProvider)
          .listDeliveryOptions(projectId),
    );

/// T04 remains route-less until the Accounts UI release gate. Exact-role,
/// permission-epoch and immutable-auth changes dispose protected supplier data.
final yorksAccountsSupplierControllerProvider = StateNotifierProvider
    .autoDispose
    .family<
      YorksAccountsSupplierController,
      YorksAccountsSupplierState,
      String
    >((ref, projectId) {
      ref.keepAlive();
      ref.watch(yorksV1CurrentRoleProvider);
      ref.watch(yorksAccountsPermissionEpochProvider);
      final actorAuthUserId = ref.watch(yorksV1AuthUserIdProvider) ?? '';
      return YorksAccountsSupplierController(
        projectId: projectId,
        repository: ref.watch(yorksAccountsSupplierRepositoryProvider),
        commandKeys: YorksV1CriticalCommandKeyStore(
          preferences: ref.watch(sharedPreferencesProvider),
          actorAuthUserId: actorAuthUserId,
        ),
      );
    });

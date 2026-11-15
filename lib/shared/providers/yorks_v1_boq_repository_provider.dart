import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/yorks_v1_boq_contract_status.dart';
import '../repositories/yorks_v1_boq_contract_status_repository.dart';
import '../repositories/yorks_v1_boq_repository.dart';
import '../sync/connectivity_service.dart';
import 'language_provider.dart';
import 'yorks_v1_feature_flags_provider.dart';

final yorksV1BoqRpcClientProvider = Provider<YorksV1BoqRpcClient?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseYorksV1BoqRpcClient(client);
});

final yorksV1BoqRepositoryProvider = Provider<YorksV1BoqRepository>((ref) {
  return YorksV1SupabaseBoqRepository(
    featureFlags: ref.watch(yorksV1FeatureFlagsProvider),
    connectivity: ref.watch(connectivityProvider),
    rpcClient: ref.watch(yorksV1BoqRpcClientProvider),
  );
});

final yorksV1BoqContractStatusRepositoryProvider =
    Provider<YorksV1BoqContractStatusRepository>((ref) {
      return YorksV1BoqContractStatusRepository(
        featureFlags: ref.watch(yorksV1FeatureFlagsProvider),
        rpcClient: ref.watch(yorksV1BoqRpcClientProvider),
      );
    });

/// A BOQ folder's contract line status, or null when contract materials are
/// off. A failed read leaves the worksheet as it is: the status is an extra
/// view, never a reason to block the sheet.
final yorksV1BoqContractStatusProvider = FutureProvider.autoDispose
    .family<YorksV1BoqContractStatus?, String>((ref, groupId) async {
      try {
        return await ref
            .watch(yorksV1BoqContractStatusRepositoryProvider)
            .getStatus(groupId);
      } catch (_) {
        return null;
      }
    });

/// Configuration workspace — providers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/language_provider.dart';
import '../../../shared/providers/yorks_v1_configuration_provider.dart';
import '../../../shared/sync/connectivity_service.dart';
import '../data/configuration_workspace_repository.dart';
import '../domain/configuration_workspace_models.dart';

final configRpcClientProvider = Provider<ConfigRpcClient?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseConfigRpcClient(client);
});

final configWorkspaceRepositoryProvider = Provider<ConfigWorkspaceRepository>(
  (ref) => ConfigWorkspaceRepository(
    connectivity: ref.watch(connectivityProvider),
    rpcClient: ref.watch(configRpcClientProvider),
  ),
);

final configWorkspaceProvider = FutureProvider.autoDispose<ConfigWorkspace>(
  (ref) => ref.watch(configWorkspaceRepositoryProvider).getWorkspace(),
);

/// After a save: the workspace, the history and every runtime reader.
void refreshConfiguration(WidgetRef ref) {
  ref.invalidate(configWorkspaceProvider);
  ref.invalidate(yorksV1ConfigurationCentreProvider);
  ref.invalidate(yorksV1RuntimeConfigurationProvider);
  ref.invalidate(yorksV1ConfigurationUnitCodesProvider);
}

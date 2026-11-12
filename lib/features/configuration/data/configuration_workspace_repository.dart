/// Configuration workspace — trusted RPC access. Saving needs the connection
/// and the server's confirmation; nothing is shown as saved before it answers.
library;

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/models/yorks_v1_domain_error.dart';
import '../../../shared/sync/connectivity_service.dart';
import '../domain/configuration_workspace_models.dart';

/// The RPC seam (a fake in tests).
abstract interface class ConfigRpcClient {
  Future<Object?> invoke(String functionName, Map<String, Object?> parameters);
}

final class SupabaseConfigRpcClient implements ConfigRpcClient {
  const SupabaseConfigRpcClient(this._client);

  final SupabaseClient _client;

  @override
  Future<Object?> invoke(
    String functionName,
    Map<String, Object?> parameters,
  ) => _client.rpc(functionName, params: parameters);
}

final class ConfigWorkspaceRepository {
  ConfigWorkspaceRepository({
    required ConnectivityService connectivity,
    required ConfigRpcClient? rpcClient,
  }) : _connectivity = connectivity,
       _rpc = rpcClient;

  final ConnectivityService _connectivity;
  final ConfigRpcClient? _rpc;

  static String newKey() => const Uuid().v4();

  Future<ConfigWorkspace> getWorkspace() async {
    final json = await _invoke('v1_cfg_get_workspace', const {});
    return ConfigWorkspace.fromJson(Map<String, dynamic>.from(json! as Map));
  }

  /// Saves one section's [changes] with [reason]. Returns the new version.
  Future<int> apply({
    required ConfigSection section,
    required List<ConfigChange> changes,
    required String reason,
    required int expectedVersion,
    required String idempotencyKey,
  }) async {
    final json = await _invoke('v1_cfg_apply', {
      'p_section': section.wire,
      'p_changes': [for (final change in changes) change.json],
      'p_reason': reason.trim(),
      'p_expected_version': expectedVersion,
      'p_idempotency_key': idempotencyKey,
    });
    final map = Map<String, dynamic>.from(json! as Map);
    return (map['version'] as num?)?.toInt() ?? expectedVersion + 1;
  }

  Future<Object?> _invoke(
    String functionName,
    Map<String, Object?> parameters,
  ) async {
    if (!_connectivity.isOnline) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.offline);
    }
    final rpc = _rpc;
    if (rpc == null) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
    try {
      return await rpc.invoke(functionName, parameters);
    } on YorksV1DomainException {
      rethrow;
    } on PostgrestException catch (error) {
      final code = switch (error.code) {
        'PGRST301' ||
        'PGRST302' ||
        'PGRST303' ||
        '28000' => YorksV1DomainErrorCode.unauthenticated,
        '42501' => YorksV1DomainErrorCode.unauthorized,
        '40001' => YorksV1DomainErrorCode.conflict,
        '22023' ||
        '22P02' ||
        '23505' ||
        '23514' => YorksV1DomainErrorCode.invalidInput,
        _ => YorksV1DomainErrorCode.serverRejected,
      };
      throw YorksV1DomainException(
        code,
        serverCode: error.code,
        serverMessage: error.message,
        cause: error,
      );
    } catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
        cause: error,
      );
    }
  }
}

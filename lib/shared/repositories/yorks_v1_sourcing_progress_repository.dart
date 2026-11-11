import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/yorks_v1_domain_error.dart';
import '../models/yorks_v1_sourcing_progress.dart';
import '../sync/connectivity_service.dart';
import 'yorks_v1_material_request_repository.dart';

abstract interface class YorksV1SourcingProgressRepository {
  Future<YorksV1SourcingProgress?> read(YorksV1SourcingScope scope);
  Future<YorksV1SourcingProgress> save(
    Map<String, Object?> payload,
    String key,
  );
}

class YorksV1SupabaseSourcingProgressRepository
    implements YorksV1SourcingProgressRepository {
  const YorksV1SupabaseSourcingProgressRepository({
    required this.connectivity,
    this.rpc,
  });
  final ConnectivityService connectivity;
  final YorksV1MaterialRequestRpcClient? rpc;
  @override
  Future<YorksV1SourcingProgress?> read(YorksV1SourcingScope scope) async {
    final raw = await _invoke('v1_get_arrangement_sourcing_progress', {
      'p_request_id': scope.requestId,
      'p_arrangement_id': scope.arrangementId,
    });
    return raw == null ? null : _decode(raw);
  }

  @override
  Future<YorksV1SourcingProgress> save(
    Map<String, Object?> payload,
    String key,
  ) async => _decode(
    await _invoke('v1_save_arrangement_sourcing_progress', {
      'p_payload': payload,
      'p_idempotency_key': key,
    }),
  );
  YorksV1SourcingProgress _decode(Object? raw) {
    if (raw is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1SourcingProgress.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<Object?> _invoke(
    String function,
    Map<String, Object?> parameters,
  ) async {
    if (!connectivity.isOnline) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.offline);
    }
    if (rpc == null) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
    try {
      return await rpc!
          .invoke(functionName: function, parameters: parameters)
          .timeout(const Duration(seconds: 20));
    } on PostgrestException catch (e) {
      throw YorksV1DomainException(
        switch (e.code) {
          '42501' || '28000' => YorksV1DomainErrorCode.unauthorized,
          '40001' || '23505' => YorksV1DomainErrorCode.conflict,
          '22023' || '23514' || '22P02' => YorksV1DomainErrorCode.invalidInput,
          _ => YorksV1DomainErrorCode.serverRejected,
        },
        serverCode: e.code,
        cause: e,
      );
    } on YorksV1DomainException {
      rethrow;
    } catch (e) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
        cause: e,
      );
    }
  }
}

import '../models/yorks_v1_boq_contract_status.dart';
import '../models/yorks_v1_domain_error.dart';
import '../models/yorks_v1_feature_flags.dart';
import 'yorks_v1_boq_repository.dart' show YorksV1BoqRpcClient;

/// Reads a BOQ folder's contract line status (PRODUCT_DECISIONS.md §61).
///
/// Kept apart from [YorksV1BoqRepository] so the worksheet's own reads and
/// saves are untouched: the status is an extra view over rows tied to
/// contract lines, and returns null when contract materials are off.
class YorksV1BoqContractStatusRepository {
  const YorksV1BoqContractStatusRepository({
    required YorksV1FeatureFlags featureFlags,
    YorksV1BoqRpcClient? rpcClient,
  }) : _featureFlags = featureFlags,
       _rpcClient = rpcClient;

  final YorksV1FeatureFlags _featureFlags;
  final YorksV1BoqRpcClient? _rpcClient;

  Future<YorksV1BoqContractStatus?> getStatus(String groupId) async {
    if (!_featureFlags.boq || !_featureFlags.contractMaterials) return null;
    final rpc = _rpcClient;
    if (rpc == null) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
    final response = await rpc.invoke(
      functionName: 'v1_get_boq_contract_status',
      parameters: {'p_group_id': groupId},
    );
    if (response is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1BoqContractStatus.fromJson(
      Map<String, dynamic>.from(response),
    );
  }
}

import 'dart:async';
import '../models/yorks_v1_command_outcome.dart';
import '../models/yorks_v1_domain_error.dart';
import 'yorks_v1_material_request_repository.dart';

class YorksV1WorkflowCommandOutcome {
  const YorksV1WorkflowCommandOutcome({
    required this.confirmed,
    this.response,
    this.receipt,
  });
  final bool confirmed;
  final Map<String, dynamic>? response;
  final YorksV1CommandReceipt? receipt;
}

abstract interface class YorksV1CommandOutcomeRepository {
  Future<YorksV1WorkflowCommandOutcome> check(String command, String key);
}

class YorksV1RpcCommandOutcomeRepository
    implements YorksV1CommandOutcomeRepository {
  const YorksV1RpcCommandOutcomeRepository(this.rpc);
  final YorksV1MaterialRequestRpcClient rpc;
  @override
  Future<YorksV1WorkflowCommandOutcome> check(
    String command,
    String key,
  ) async {
    final raw = await rpc
        .invoke(
          functionName: 'v1_get_material_workflow_command_outcome',
          parameters: {'p_command_name': command, 'p_idempotency_key': key},
        )
        .timeout(const Duration(seconds: 4));
    if (raw is! Map ||
        raw['command_name'] != command ||
        raw['command_key'] != key) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    if (raw['status'] != 'confirmed') {
      return const YorksV1WorkflowCommandOutcome(confirmed: false);
    }
    final id = raw['entity_id'];
    if (id is! String || id.isEmpty) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    Map<String, dynamic>? response;
    try {
      if (raw['response'] is Map) {
        response = Map<String, dynamic>.from(raw['response'] as Map);
      }
    } catch (_) {
      /* Optional malformed workspace cannot erase the receipt. */
    }
    return YorksV1WorkflowCommandOutcome(
      confirmed: true,
      receipt: YorksV1CommandReceipt(
        commandName: command,
        commandKey: key,
        entityId: id,
        recordVersion: int.tryParse('${raw['record_version']}'),
      ),
      response: response,
    );
  }
}

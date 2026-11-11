import 'dart:async';
import '../models/yorks_v1_command_outcome.dart';
import '../models/yorks_v1_domain_error.dart';
import 'yorks_v1_material_request_repository.dart';

class YorksV1WorkflowCommandOutcome {
  const YorksV1WorkflowCommandOutcome({
    required this.confirmed,
    this.response,
    this.receipt,
    Future<Map<String, dynamic>?> Function()? loadResponse,
  }) : _loadResponse = loadResponse;
  final bool confirmed;
  final Map<String, dynamic>? response;
  final YorksV1CommandReceipt? receipt;
  final Future<Map<String, dynamic>?> Function()? _loadResponse;

  /// Optional view loading starts only after the caller has acknowledged the
  /// receipt. Its latency or failure cannot turn a committed command unknown.
  Future<Map<String, dynamic>?> loadResponse() async =>
      _loadResponse == null ? response : await _loadResponse();
}

abstract interface class YorksV1CommandOutcomeRepository {
  Future<YorksV1WorkflowCommandOutcome> check(String command, String key);
}

class YorksV1RpcCommandOutcomeRepository
    implements YorksV1CommandOutcomeRepository {
  const YorksV1RpcCommandOutcomeRepository(
    this.rpc, {
    this.receiptTimeout = const Duration(seconds: 4),
    this.viewTimeout = const Duration(seconds: 4),
  });
  final YorksV1MaterialRequestRpcClient rpc;
  final Duration receiptTimeout;
  final Duration viewTimeout;
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
        .timeout(receiptTimeout);
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
    return YorksV1WorkflowCommandOutcome(
      confirmed: true,
      receipt: YorksV1CommandReceipt(
        commandName: command,
        commandKey: key,
        entityId: id,
        recordVersion: int.tryParse('${raw['record_version']}'),
      ),
      loadResponse: () => _loadResponse(command, key, id),
    );
  }

  Future<Map<String, dynamic>?> _loadResponse(
    String command,
    String key,
    String entityId,
  ) async {
    final raw = await rpc
        .invoke(
          functionName: 'v1_get_material_workflow_command_view',
          parameters: {'p_command_name': command, 'p_idempotency_key': key},
        )
        .timeout(viewTimeout);
    if (raw is! Map ||
        raw['status'] != 'confirmed' ||
        raw['command_name'] != command ||
        raw['command_key'] != key ||
        raw['entity_id'] != entityId ||
        raw['response'] is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return Map<String, dynamic>.from(raw['response'] as Map);
  }
}

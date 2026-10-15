import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_material_request_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_procurement_progress_repository.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';

void main() {
  Map<String, Object?> result() => {
    'request_id': 'request',
    'command_name': 'v1_dispatch_materials',
    'idempotency_key': 'key',
    'status': 'confirmed',
    'receipt': {
      'effect_id': 'dispatch-exact',
      'effect_reference': 'DN-EXACT',
      'committed_version': 7,
    },
  };
  Future<YorksV1ProcurementCommandOutcome> read(
    _Rpc rpc, {
    bool automatic = false,
  }) =>
      YorksV1SupabaseProcurementProgressRepository(
        connectivity: DefaultConnectivity(),
        rpcClient: rpc,
      ).outcome(
        requestId: 'request',
        commandName: 'v1_dispatch_materials',
        commandKey: 'key',
        automatic: automatic,
      );

  test('minimal receipt confirms without a workspace', () async {
    final rpc = _Rpc(result());
    final outcome = await read(rpc, automatic: true);
    expect(outcome.isConfirmed, isTrue);
    expect(outcome.effectId, 'dispatch-exact');
    expect(outcome.effectReference, 'DN-EXACT');
    expect(outcome.workspace, isNull);
    expect(rpc.function, 'v1_reconcile_procurement_command_outcome');
    expect(rpc.parameters?['p_automatic'], isTrue);
  });
  test('unusable optional workspace cannot erase receipt', () async {
    final outcome = await read(_Rpc({...result(), 'workspace': 'malformed'}));
    expect(outcome.isConfirmed, isTrue);
    expect(outcome.workspace, isNull);
  });
  test('foreign command receipt cannot confirm this attempt', () async {
    await expectLater(
      read(_Rpc({...result(), 'idempotency_key': 'other-key'})),
      throwsA(
        isA<YorksV1DomainException>().having(
          (e) => e.code,
          'code',
          YorksV1DomainErrorCode.unexpectedResponse,
        ),
      ),
    );
  });
  test('confirmed status requires an exact effect identity', () async {
    final raw = result()..remove('receipt');
    await expectLater(read(_Rpc(raw)), throwsA(isA<YorksV1DomainException>()));
  });
  test('outcome lookup has its own short bounded transport budget', () async {
    final repository = YorksV1SupabaseProcurementProgressRepository(
      connectivity: DefaultConnectivity(),
      rpcClient: _Rpc(Completer<Object?>().future),
      outcomeTimeout: const Duration(milliseconds: 1),
    );
    await expectLater(
      repository.outcome(
        requestId: 'request',
        commandName: 'v1_dispatch_materials',
        commandKey: 'key',
      ),
      throwsA(
        isA<YorksV1DomainException>().having(
          (e) => e.code,
          'code',
          YorksV1DomainErrorCode.backendUnavailable,
        ),
      ),
    );
  });
  test(
    'server budget and backoff do not turn pending into a rejection',
    () async {
      final outcome = await read(
        _Rpc({
          ...result(),
          'status': 'pending',
          'receipt': null,
          'automatic_checks_remaining': 0,
          'retry_after_ms': 0,
          'check_deferred': true,
        }),
      );
      expect(outcome.status, 'pending');
      expect(outcome.automaticChecksRemaining, 0);
      expect(outcome.checkDeferred, isTrue);
      expect(outcome.isConfirmed, isFalse);
    },
  );
}

class _Rpc implements YorksV1MaterialRequestRpcClient {
  _Rpc(this.response);
  final Object? response;
  String? function;
  Map<String, dynamic>? parameters;
  @override
  Future<Object?> invoke({
    required String functionName,
    required Map<String, dynamic> parameters,
  }) async {
    function = functionName;
    this.parameters = parameters;
    if (response is Future<Object?>) return await (response as Future<Object?>);
    return response;
  }
}

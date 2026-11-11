import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_command_outcome_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_material_request_repository.dart';

const _command = 'v1_decide_material_request';
const _key = 'original-key';
const _receipt = <String, Object?>{
  'status': 'confirmed',
  'command_name': _command,
  'command_key': _key,
  'entity_id': 'mr',
  'record_version': 4,
  'response': null,
};

void main() {
  test(
    'a slow screen projection cannot delay the exact command receipt',
    () async {
      final view = Completer<Object?>();
      final rpc = _Rpc(view: view.future);
      final repository = YorksV1RpcCommandOutcomeRepository(rpc);

      final result = await repository.check(_command, _key);

      expect(result.confirmed, isTrue);
      expect(result.receipt!.entityId, 'mr');
      expect(result.receipt!.commandKey, _key);
      expect(result.response, isNull);
      expect(rpc.calls, ['v1_get_material_workflow_command_outcome']);

      final loading = result.loadResponse();
      await Future<void>.delayed(Duration.zero);
      expect(rpc.calls.last, 'v1_get_material_workflow_command_view');
      expect(result.confirmed, isTrue);
      view.complete({
        ..._receipt,
        'response': {'id': 'mr', 'state': 'arranging'},
      });
      expect((await loading)!['id'], 'mr');
      expect(rpc.keys, everyElement(_key));
    },
  );

  test(
    'a hung view times out separately after the receipt is confirmed',
    () async {
      final view = Completer<Object?>();
      final repository = YorksV1RpcCommandOutcomeRepository(
        _Rpc(view: view.future),
        viewTimeout: const Duration(milliseconds: 15),
      );
      final result = await repository.check(_command, _key);
      await expectLater(
        result.loadResponse(),
        throwsA(isA<TimeoutException>()),
      );
      expect(result.confirmed, isTrue);
      expect(result.receipt!.recordVersion, 4);
      view.complete({
        ..._receipt,
        'response': {'id': 'mr'},
      });
      expect(result.confirmed, isTrue);
    },
  );

  test(
    'a late view denial cannot change the known committed receipt',
    () async {
      final view = Completer<Object?>();
      final repository = YorksV1RpcCommandOutcomeRepository(
        _Rpc(view: view.future),
      );
      final result = await repository.check(_command, _key);
      final loading = result.loadResponse();
      view.completeError(
        const YorksV1DomainException(YorksV1DomainErrorCode.unauthorized),
      );
      await expectLater(loading, throwsA(isA<YorksV1DomainException>()));
      expect(result.confirmed, isTrue);
      expect(result.receipt!.entityId, 'mr');
    },
  );

  for (final field in ['command_name', 'command_key', 'entity_id']) {
    test('separate hydration rejects a mismatched $field envelope', () async {
      final repository = YorksV1RpcCommandOutcomeRepository(
        _Rpc(
          view: Future.value({
            ..._receipt,
            field: 'foreign',
            'response': {'id': 'mr'},
          }),
        ),
      );
      final result = await repository.check(_command, _key);
      await expectLater(
        result.loadResponse(),
        throwsA(isA<YorksV1DomainException>()),
      );
      expect(result.confirmed, isTrue);
    });
  }

  test('an unknown original command never loads screen data', () async {
    final rpc = _Rpc(
      receipt: {..._receipt, 'status': 'unknown'},
      view: Future.value(null),
    );
    final result = await YorksV1RpcCommandOutcomeRepository(
      rpc,
    ).check(_command, _key);
    expect(result.confirmed, isFalse);
    expect(await result.loadResponse(), isNull);
    expect(rpc.calls, ['v1_get_material_workflow_command_outcome']);
  });
}

class _Rpc implements YorksV1MaterialRequestRpcClient {
  _Rpc({this.receipt = _receipt, required this.view});
  final Object? receipt;
  final Future<Object?> view;
  final calls = <String>[];
  final keys = <Object?>[];

  @override
  Future<Object?> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async {
    calls.add(functionName);
    keys.add(parameters['p_idempotency_key']);
    if (functionName == 'v1_get_material_workflow_command_outcome') {
      return receipt;
    }
    return view;
  }
}

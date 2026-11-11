import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/controllers/yorks_v1_material_workflow_command_controller.dart';
import 'package:material_ledger/shared/models/yorks_v1_arrangement.dart';
import 'package:material_ledger/shared/models/yorks_v1_logistics.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_arrangement_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_logistics_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_material_request_repository.dart';
import 'package:material_ledger/shared/services/yorks_v1_critical_command_key_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'dispatch waits for durable preparation and uses exactly its acquired key',
    () async {
      final logistics = _Logistics();
      final gate = Completer<void>();
      final controller = YorksV1MaterialWorkflowCommandController(
        materialRequests: _UnusedRequests(),
        arrangements: _Arrangements(),
        logistics: logistics,
        commandKeys: YorksV1CriticalCommandKeyStore(
          preferences: await SharedPreferences.getInstance(),
          actorAuthUserId: 'actor',
          uuidFactory: () => 'durable-key',
        ),
      );
      String? preparedKey;
      final future = controller.dispatch(
        _dispatch(),
        beforeInvoke: (key) async {
          preparedKey = key;
          await gate.future;
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(preparedKey, 'durable-key');
      expect(logistics.keys, isEmpty);
      gate.complete();
      await expectLater(future, throwsA(isA<_Invoked>()));
      expect(logistics.keys, ['durable-key']);
    },
  );

  test(
    'failed preparation never invokes final command and retains retry identity',
    () async {
      final logistics = _Logistics();
      final controller = YorksV1MaterialWorkflowCommandController(
        materialRequests: _UnusedRequests(),
        arrangements: _Arrangements(),
        logistics: logistics,
        commandKeys: YorksV1CriticalCommandKeyStore(
          preferences: await SharedPreferences.getInstance(),
          actorAuthUserId: 'actor',
          uuidFactory: () => 'durable-key',
        ),
      );
      await expectLater(
        controller.dispatch(
          _dispatch(),
          beforeInvoke: (_) async {
            throw TimeoutException('prepare');
          },
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(logistics.keys, isEmpty);
      String? retryKey;
      await expectLater(
        controller.dispatch(
          _dispatch(),
          beforeInvoke: (key) async {
            retryKey = key;
          },
        ),
        throwsA(isA<_Invoked>()),
      );
      expect(retryKey, 'durable-key');
    },
  );

  test(
    'recovered key bypasses creation of a different final-command identity',
    () async {
      final logistics = _Logistics();
      final controller = YorksV1MaterialWorkflowCommandController(
        materialRequests: _UnusedRequests(),
        arrangements: _Arrangements(),
        logistics: logistics,
        commandKeys: YorksV1CriticalCommandKeyStore(
          preferences: await SharedPreferences.getInstance(),
          actorAuthUserId: 'actor',
          uuidFactory: () => throw StateError('must not mint'),
        ),
      );
      await expectLater(
        controller.dispatch(
          _dispatch(),
          recoveredIdempotencyKey: 'server-prepared-key',
        ),
        throwsA(isA<_Invoked>()),
      );
      expect(logistics.keys, ['server-prepared-key']);
    },
  );
}

YorksV1DispatchInput _dispatch() => YorksV1DispatchInput(
  requestId: 'request',
  expectedRequestVersion: 2,
  dispatchDate: DateTime.utc(2026, 10, 8),
  deliveryReference: 'ref',
  lines: const [
    YorksV1DispatchLineInput(requestLineId: 'line', dispatchQuantity: '1'),
  ],
  idempotencyKey: 'ignored-widget-key',
);

class _Invoked implements Exception {}

class _Logistics implements YorksV1LogisticsRepository {
  final keys = <String>[];
  @override
  Future<YorksV1LogisticsWorkspace> dispatch(YorksV1DispatchInput input) async {
    keys.add(input.idempotencyKey);
    throw _Invoked();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Arrangements implements YorksV1ArrangementRepository {
  @override
  Future<YorksV1ArrangementWorkspace> save(
    YorksV1SaveArrangementInput input,
  ) async => throw _Invoked();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedRequests implements YorksV1MaterialRequestRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

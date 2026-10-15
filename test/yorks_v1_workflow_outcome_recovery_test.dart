import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_ledger/shared/controllers/yorks_v1_material_workflow_command_controller.dart';
import 'package:material_ledger/shared/models/yorks_v1_command_outcome.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_logistics.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_command_outcome_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_arrangement_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_material_request_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_logistics_repository.dart';
import 'package:material_ledger/shared/services/yorks_v1_critical_command_key_store.dart';

const _response = <String, dynamic>{
  'request_id': 'mr',
  'project_id': 'project',
  'request_state': 'received',
  'request_record_version': 4,
  'project_name': 'Project',
  'scope_name': 'Main',
  'dispatch_candidates': [],
  'dispatches': [],
};
const _receipt = YorksV1CommandReceipt(
  commandName: 'v1_confirm_receipt',
  commandKey: 'key',
  entityId: 'mr',
  recordVersion: 4,
);
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<YorksV1MaterialWorkflowCommandController> controller(
    _Logistics logistics,
    _Outcomes outcomes, {
    YorksV1CriticalCommandKeyStore? store,
  }) async => YorksV1MaterialWorkflowCommandController(
    materialRequests: _Requests(),
    arrangements: _Arrangements(),
    logistics: logistics,
    commandKeys:
        store ??
        YorksV1CriticalCommandKeyStore(
          preferences: await SharedPreferences.getInstance(),
          actorAuthUserId: 'actor',
          uuidFactory: () => 'key',
        ),
    outcomes: outcomes,
    delay: (_) async {},
  );
  YorksV1ReceiptConfirmationInput input() => YorksV1ReceiptConfirmationInput(
    requestId: 'mr',
    dispatchId: 'dispatch',
    expectedRequestVersion: 3,
    expectedDispatchVersion: 1,
    lines: const [],
    idempotencyKey: 'ignored',
  );
  test(
    'lost response reconciles exact receipt without sending a second mutation',
    () async {
      final logistics = _Logistics();
      final outcomes = _Outcomes([
        const YorksV1WorkflowCommandOutcome(confirmed: false),
        const YorksV1WorkflowCommandOutcome(
          confirmed: true,
          response: _response,
          receipt: _receipt,
        ),
      ]);
      final c = await controller(logistics, outcomes);
      final result = await c.confirmReceipt(input());
      expect(result.requestRecordVersion, 4);
      expect(logistics.calls, 1);
      expect(outcomes.calls, 2);
    },
  );
  test(
    'lookup miss never frees an unknown command, including controller reconstruction',
    () async {
      final logistics = _Logistics();
      final outcomes = _Outcomes([]);
      final c = await controller(logistics, outcomes);
      await expectLater(
        c.confirmReceipt(input()),
        throwsA(isA<YorksV1CommandOutcomeUnknown>()),
      );
      final resumed = await controller(logistics, outcomes);
      await expectLater(
        resumed.confirmReceipt(input()),
        throwsA(isA<YorksV1CommandOutcomeUnknown>()),
      );
      expect(logistics.calls, 1);
    },
  );
  test(
    'confirmed commit with broken view remains a confirmed receipt',
    () async {
      final c = await controller(
        _Logistics(),
        _Outcomes([
          const YorksV1WorkflowCommandOutcome(
            confirmed: true,
            receipt: _receipt,
          ),
        ]),
      );
      await expectLater(
        c.confirmReceipt(input()),
        throwsA(
          isA<YorksV1CommittedViewUnavailable>().having(
            (e) => e.receipt.entityId,
            'effect',
            'mr',
          ),
        ),
      );
    },
  );
  test(
    'local cleanup failure cannot reject acknowledged server success',
    () async {
      final store = _BrokenCleanup(
        preferences: await SharedPreferences.getInstance(),
        actorAuthUserId: 'actor',
      );
      final logistics = _Logistics()..error = null;
      final c = await controller(logistics, _Outcomes([]), store: store);
      expect((await c.confirmReceipt(input())).requestRecordVersion, 4);
    },
  );
  test(
    'explicit rejection is retained and never reconciled into fabricated success',
    () async {
      final logistics = _Logistics()
        ..error = const YorksV1DomainException(
          YorksV1DomainErrorCode.unauthorized,
          serverCode: '42501',
        );
      final outcomes = _Outcomes([]);
      final c = await controller(logistics, outcomes);
      await expectLater(
        c.confirmReceipt(input()),
        throwsA(
          isA<YorksV1DomainException>().having(
            (e) => e.code,
            'code',
            YorksV1DomainErrorCode.unauthorized,
          ),
        ),
      );
      expect(outcomes.calls, 0);
    },
  );
  test('duplicate click shares a single active command', () async {
    final gate = Completer<void>();
    final logistics = _Logistics()
      ..error = null
      ..gate = gate;
    final c = await controller(logistics, _Outcomes([]));
    final one = c.confirmReceipt(input());
    final two = c.confirmReceipt(input());
    gate.complete();
    await Future.wait([one, two]);
    expect(logistics.calls, 1);
  });
}

class _BrokenCleanup extends YorksV1CriticalCommandKeyStore {
  _BrokenCleanup({required super.preferences, required super.actorAuthUserId});
  @override
  Future<void> confirm({
    required String operation,
    required String entityId,
    required String idempotencyKey,
  }) async => throw StateError('disk');
}

class _Logistics implements YorksV1LogisticsRepository {
  int calls = 0;
  Object? error = const YorksV1DomainException(
    YorksV1DomainErrorCode.backendUnavailable,
  );
  Completer<void>? gate;
  @override
  Future<YorksV1LogisticsWorkspace> confirmReceipt(
    YorksV1ReceiptConfirmationInput input,
  ) async {
    calls++;
    await gate?.future;
    if (error != null) throw error!;
    return YorksV1LogisticsWorkspace.fromRpcJson(_response);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Outcomes implements YorksV1CommandOutcomeRepository {
  _Outcomes(this.values);
  final List<YorksV1WorkflowCommandOutcome> values;
  int calls = 0;
  @override
  Future<YorksV1WorkflowCommandOutcome> check(
    String command,
    String key,
  ) async {
    expect(command, 'v1_confirm_receipt');
    expect(key, 'key');
    calls++;
    return values.isEmpty
        ? const YorksV1WorkflowCommandOutcome(confirmed: false)
        : values.removeAt(0);
  }
}

class _Requests implements YorksV1MaterialRequestRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Arrangements implements YorksV1ArrangementRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

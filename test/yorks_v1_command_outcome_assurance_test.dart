import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Used for deterministic platform-persistence failure injection.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
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
    void Function(String, YorksV1CommandPhase)? onPhase,
    void Function() Function()? beginActivity,
    bool Function()? authority,
  }) async => YorksV1MaterialWorkflowCommandController(
    materialRequests: _Requests(),
    arrangements: _Arrangements(),
    logistics: logistics,
    outcomes: outcomes,
    commandKeys:
        store ??
        YorksV1CriticalCommandKeyStore(
          preferences: await SharedPreferences.getInstance(),
          actorAuthUserId: 'actor',
          uuidFactory: () => 'key',
        ),
    delay: (_) async {},
    onPhase: onPhase,
    beginActivity: beginActivity,
    isCurrentAuthority: authority,
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
    'restored decision budget survives reconstruction; manual read remains available',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = YorksV1CriticalCommandKeyStore(
        preferences: prefs,
        actorAuthUserId: 'actor',
        uuidFactory: () => 'key',
      );
      await store.acquire(
        operation: 'decide_material_request_approved',
        entityId: 'mr',
        payload: const {},
        trackSendState: true,
      );
      await store.markDispatched(
        'decide_material_request_approved',
        'mr',
        'key',
      );
      final outcomes = _Outcomes();
      final phases = <YorksV1CommandPhase>[];
      final c = await controller(
        _Logistics(),
        outcomes,
        store: store,
        onPhase: (_, phase) => phases.add(phase),
      );
      expect(await c.restoreDecisionStatus('mr'), isNull);
      expect(outcomes.calls, 3);
      expect(phases.first, YorksV1CommandPhase.unknown);
      expect(phases, contains(YorksV1CommandPhase.checking));
      final resumed = await controller(
        _Logistics(),
        outcomes,
        store: YorksV1CriticalCommandKeyStore(
          preferences: prefs,
          actorAuthUserId: 'actor',
          uuidFactory: () => 'different',
        ),
      );
      expect(await resumed.restoreDecisionStatus('mr'), isNull);
      expect(outcomes.calls, 3);
      await expectLater(
        resumed.checkDecisionStatus('mr'),
        throwsA(isA<YorksV1CommandOutcomeUnknown>()),
      );
      expect(outcomes.calls, 4);
    },
  );
  test('restoration skips proven not sent leases and never mutates', () async {
    final store = YorksV1CriticalCommandKeyStore(
      preferences: await SharedPreferences.getInstance(),
      actorAuthUserId: 'actor',
      uuidFactory: () => 'key',
    );
    await store.acquire(
      operation: 'decide_material_request_approved',
      entityId: 'mr',
      payload: const {},
      trackSendState: true,
    );
    final outcomes = _Outcomes();
    final phases = <YorksV1CommandPhase>[];
    final c = await controller(
      _Logistics(),
      outcomes,
      store: store,
      onPhase: (_, phase) => phases.add(phase),
    );
    expect(await c.restoreDecisionStatus('mr'), isNull);
    expect(outcomes.calls, 0);
    expect(phases.single, YorksV1CommandPhase.notSent);
  });
  test(
    'restoration acknowledges exact receipt even without optional view',
    () async {
      final store = YorksV1CriticalCommandKeyStore(
        preferences: await SharedPreferences.getInstance(),
        actorAuthUserId: 'actor',
        uuidFactory: () => 'key',
      );
      await store.acquire(
        operation: 'decide_material_request_approved',
        entityId: 'mr',
        payload: const {},
      );
      final phases = <YorksV1CommandPhase>[];
      final outcomes = _Outcomes(
        const YorksV1WorkflowCommandOutcome(
          confirmed: true,
          receipt: YorksV1CommandReceipt(
            commandName: 'v1_decide_material_request',
            commandKey: 'key',
            entityId: 'mr',
          ),
        ),
      );
      final c = await controller(
        _Logistics(),
        outcomes,
        store: store,
        onPhase: (_, phase) => phases.add(phase),
      );
      await expectLater(
        c.restoreDecisionStatus('mr'),
        throwsA(isA<YorksV1CommittedViewUnavailable>()),
      );
      expect(phases.last, YorksV1CommandPhase.confirmedViewUnavailable);
      expect(
        store.pendingKey('decide_material_request_approved', 'mr'),
        isNull,
      );
      expect(outcomes.calls, 1);
    },
  );
  test(
    'offline receipt lease does not lock a new receipt editor into status checks',
    () async {
      final logistics = _Logistics()
        ..error = const YorksV1DomainException(YorksV1DomainErrorCode.offline);
      final c = await controller(logistics, _Outcomes());
      await expectLater(
        c.confirmReceipt(input()),
        throwsA(isA<YorksV1DomainException>()),
      );
      expect(c.hasPendingReceipt('dispatch'), isFalse);
    },
  );
  test(
    'receipt manual read resumes exact durable key without another mutation',
    () async {
      final logistics = _Logistics();
      final store = YorksV1CriticalCommandKeyStore(
        preferences: await SharedPreferences.getInstance(),
        actorAuthUserId: 'actor',
        uuidFactory: () => 'key',
      );
      await store.acquire(
        operation: 'confirm_receipt',
        entityId: 'dispatch',
        payload: const {},
        trackSendState: true,
      );
      await store.markDispatched('confirm_receipt', 'dispatch', 'key');
      final c = await controller(
        logistics,
        _Outcomes(
          const YorksV1WorkflowCommandOutcome(
            confirmed: true,
            receipt: _receipt,
            response: _response,
          ),
        ),
        store: store,
      );
      expect(c.hasPendingReceipt('dispatch'), isTrue);
      expect((await c.checkReceiptStatus('mr', 'dispatch'))!.requestId, 'mr');
      expect(c.hasPendingReceipt('dispatch'), isFalse);
      expect(logistics.calls, 0);
    },
  );
  test(
    'raw local decode exception reconciles instead of claiming rejection',
    () async {
      final logistics = _Logistics()
        ..error = const FormatException('malformed response');
      final outcomes = _Outcomes(
        const YorksV1WorkflowCommandOutcome(
          confirmed: true,
          response: _response,
          receipt: _receipt,
        ),
      );
      final c = await controller(logistics, outcomes);
      expect((await c.confirmReceipt(input())).requestRecordVersion, 4);
      expect(logistics.calls, 1);
      expect(outcomes.calls, 1);
    },
  );
  test(
    'known receipt survives throwing phase observer and activity cleanup',
    () async {
      final logistics = _Logistics();
      final c = await controller(
        logistics,
        _Outcomes(),
        onPhase: (_, _) => throw StateError('presentation disposed'),
        beginActivity: () =>
            () => throw StateError('read gate disposed'),
      );
      expect((await c.confirmReceipt(input())).requestRecordVersion, 4);
      expect(logistics.calls, 1);
    },
  );
  test(
    'first offline preflight is not sent; reconnect permits the original intent',
    () async {
      final logistics = _Logistics()
        ..error = const YorksV1DomainException(YorksV1DomainErrorCode.offline);
      final outcomes = _Outcomes();
      final phases = <YorksV1CommandPhase>[];
      final c = await controller(
        logistics,
        outcomes,
        onPhase: (_, value) => phases.add(value),
      );
      await expectLater(
        c.confirmReceipt(input()),
        throwsA(isA<YorksV1DomainException>()),
      );
      expect(outcomes.calls, 0);
      expect(phases.last, YorksV1CommandPhase.notSent);
      logistics.error = null;
      expect((await c.confirmReceipt(input())).requestRecordVersion, 4);
      expect(logistics.calls, 2);
    },
  );
  test(
    'proven not-sent state remains retryable across controller reconstruction',
    () async {
      final logistics = _Logistics()
        ..error = const YorksV1DomainException(YorksV1DomainErrorCode.offline);
      final outcomes = _Outcomes();
      final c = await controller(logistics, outcomes);
      await expectLater(
        c.confirmReceipt(input()),
        throwsA(isA<YorksV1DomainException>()),
      );
      logistics.error = null;
      final resumed = await controller(logistics, outcomes);
      expect((await resumed.confirmReceipt(input())).requestRecordVersion, 4);
      expect(logistics.calls, 2);
      expect(outcomes.calls, 0);
    },
  );
  test(
    'genuinely unknown send is never reset by a later offline retry',
    () async {
      final logistics = _Logistics()
        ..error = const YorksV1DomainException(
          YorksV1DomainErrorCode.backendUnavailable,
        );
      final outcomes = _Outcomes();
      final c = await controller(logistics, outcomes);
      await expectLater(
        c.confirmReceipt(input()),
        throwsA(isA<YorksV1CommandOutcomeUnknown>()),
      );
      logistics.error = const YorksV1DomainException(
        YorksV1DomainErrorCode.offline,
      );
      final resumed = await controller(logistics, outcomes);
      await expectLater(
        resumed.confirmReceipt(input()),
        throwsA(isA<YorksV1CommandOutcomeUnknown>()),
      );
      expect(logistics.calls, 1);
    },
  );
  test('foreign receipt cannot confirm a crossed device lease', () async {
    final logistics = _Logistics()
      ..error = const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    final outcomes = _Outcomes(
      const YorksV1WorkflowCommandOutcome(
        confirmed: true,
        response: _response,
        receipt: YorksV1CommandReceipt(
          commandName: 'v1_confirm_receipt',
          commandKey: 'key',
          entityId: 'different-mr',
        ),
      ),
    );
    final c = await controller(logistics, outcomes);
    await expectLater(
      c.confirmReceipt(input()),
      throwsA(isA<YorksV1CommandOutcomeUnknown>()),
    );
    expect(logistics.calls, 1);
  });
  test(
    'wrong optional response cannot replace the confirmed request view',
    () async {
      final logistics = _Logistics()
        ..error = const YorksV1DomainException(
          YorksV1DomainErrorCode.backendUnavailable,
        );
      final outcomes = _Outcomes(
        YorksV1WorkflowCommandOutcome(
          confirmed: true,
          response: {..._response, 'request_id': 'different-mr'},
          receipt: _receipt,
        ),
      );
      final c = await controller(logistics, outcomes);
      await expectLater(
        c.confirmReceipt(input()),
        throwsA(isA<YorksV1CommittedViewUnavailable>()),
      );
    },
  );
  test(
    'failed lease write cannot be trusted from the preferences cache on a second click',
    () async {
      final platform = _FailingStore()..rejectAll = true;
      SharedPreferencesStorePlatform.instance = platform;
      final prefs = await SharedPreferences.getInstance();
      final store = YorksV1CriticalCommandKeyStore(
        preferences: prefs,
        actorAuthUserId: 'actor',
        uuidFactory: () => 'key',
      );
      for (var attempt = 0; attempt < 2; attempt++) {
        await expectLater(
          store.acquire(
            operation: 'confirm_receipt',
            entityId: 'dispatch',
            payload: const {'request_id': 'mr'},
          ),
          throwsA(isA<YorksV1DomainException>()),
        );
      }
      expect(await platform.getAll(), isEmpty);
      expect(prefs.getKeys(), isEmpty);
    },
  );
  test(
    'acknowledged cleanup failure and reload cannot restore an unknown panel lease',
    () async {
      final platform = _FailingStore();
      SharedPreferencesStorePlatform.instance = platform;
      final prefs = await SharedPreferences.getInstance();
      var serial = 0;
      final store = YorksV1CriticalCommandKeyStore(
        preferences: prefs,
        actorAuthUserId: 'actor',
        uuidFactory: () => 'key-${serial++}',
      );
      for (final operation in [
        'close_material_request',
        'save_arrangement',
        'dispatch_materials',
      ]) {
        final entity = operation == 'save_arrangement' ? 'arrangement' : 'mr';
        final key = await store.acquire(
          operation: operation,
          entityId: entity,
          payload: const {'request_id': 'mr'},
          trackSendState: true,
        );
        await store.markDispatched(operation, entity, key);
        platform.rejectRemove = true;
        await store.confirm(
          operation: operation,
          entityId: entity,
          idempotencyKey: key,
        );
        await prefs.reload();
        expect(
          store.pendingKey(operation, entity),
          key,
          reason: 'Durable recovery evidence stays on disk',
        );
        expect(store.hasPendingDispatch(operation, entity), isFalse);
        expect(store.hasTrackedPendingDispatch(operation, entity), isFalse);
      }
      final c = await controller(_Logistics(), _Outcomes(), store: store);
      expect(
        c.pendingCommandsForRequest('mr', arrangementIds: ['arrangement']),
        isEmpty,
      );
      // A fresh instance still sees the retained lease and checks its receipt;
      // this in-memory acknowledgement filter never discards restart evidence.
      final restarted = YorksV1CriticalCommandKeyStore(
        preferences: prefs,
        actorAuthUserId: 'actor',
        uuidFactory: () => 'different',
      );
      expect(
        restarted.hasPendingDispatch('close_material_request', 'mr'),
        isTrue,
      );
    },
  );

  test('failed dispatched marker is never trusted as a sent request', () async {
    final platform = _FailingStore();
    SharedPreferencesStorePlatform.instance = platform;
    final prefs = await SharedPreferences.getInstance();
    final store = YorksV1CriticalCommandKeyStore(
      preferences: prefs,
      actorAuthUserId: 'actor',
      uuidFactory: () => 'key',
    );
    await store.acquire(
      operation: 'confirm_receipt',
      entityId: 'dispatch',
      payload: const {'request_id': 'mr'},
    );
    platform.rejectSent = true;
    await expectLater(
      store.markDispatched('confirm_receipt', 'dispatch', 'key'),
      throwsA(isA<YorksV1DomainException>()),
    );
    expect(
      await store.wasDispatched('confirm_receipt', 'dispatch', 'key'),
      isFalse,
    );
    platform.rejectSent = false;
    await store.markDispatched('confirm_receipt', 'dispatch', 'key');
    expect(
      await store.wasDispatched('confirm_receipt', 'dispatch', 'key'),
      isTrue,
    );
  });
  test(
    'manual decision check preserves confirmed acknowledgement when decoding fails',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = YorksV1CriticalCommandKeyStore(
        preferences: prefs,
        actorAuthUserId: 'actor',
        uuidFactory: () => 'key',
      );
      await store.acquire(
        operation: 'decide_material_request_approved',
        entityId: 'mr',
        payload: const {'request_id': 'mr'},
      );
      final outcomes = _Outcomes(
        const YorksV1WorkflowCommandOutcome(
          confirmed: true,
          response: {'id': 'mr', 'broken': true},
          receipt: YorksV1CommandReceipt(
            commandName: 'v1_decide_material_request',
            commandKey: 'key',
            entityId: 'mr',
          ),
        ),
      );
      final c = await controller(_Logistics(), outcomes, store: store);
      await expectLater(
        c.checkDecisionStatus('mr'),
        throwsA(isA<YorksV1CommittedViewUnavailable>()),
      );
      expect(
        store.pendingKey('decide_material_request_approved', 'mr'),
        isNull,
      );
    },
  );
  test(
    'manual decision check fences an authority change before reading its response',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = YorksV1CriticalCommandKeyStore(
        preferences: prefs,
        actorAuthUserId: 'actor',
        uuidFactory: () => 'key',
      );
      await store.acquire(
        operation: 'decide_material_request_approved',
        entityId: 'mr',
        payload: const {'request_id': 'mr'},
      );
      final outcomes = _Outcomes(
        const YorksV1WorkflowCommandOutcome(
          confirmed: true,
          response: {'id': 'mr'},
          receipt: YorksV1CommandReceipt(
            commandName: 'v1_decide_material_request',
            commandKey: 'key',
            entityId: 'mr',
          ),
        ),
      );
      final c = await controller(
        _Logistics(),
        outcomes,
        store: store,
        authority: () => false,
      );
      await expectLater(
        c.checkDecisionStatus('mr'),
        throwsA(
          isA<YorksV1DomainException>().having(
            (e) => e.code,
            'code',
            YorksV1DomainErrorCode.unauthenticated,
          ),
        ),
      );
    },
  );
  test(
    'optional malformed map and version do not erase a valid generic receipt',
    () async {
      final repo = YorksV1RpcCommandOutcomeRepository(
        _Rpc({
          'status': 'confirmed',
          'command_name': 'v1_confirm_receipt',
          'command_key': 'key',
          'entity_id': 'mr',
          'record_version': {'unexpected': true},
          'response': {3: 'invalid key'},
        }),
      );
      final result = await repo.check('v1_confirm_receipt', 'key');
      expect(result.confirmed, isTrue);
      expect(result.receipt!.entityId, 'mr');
      expect(result.receipt!.recordVersion, isNull);
      expect(result.response, isNull);
    },
  );
}

class _FailingStore extends InMemorySharedPreferencesStore {
  _FailingStore() : super.empty();
  bool rejectAll = false, rejectSent = false, rejectRemove = false;
  @override
  Future<bool> remove(String key) async {
    if (rejectRemove) return false;
    return super.remove(key);
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (rejectAll ||
        (rejectSent && value.toString().contains('"dispatched":true'))) {
      return false;
    }
    return super.setValue(type, key, value);
  }
}

class _Logistics implements YorksV1LogisticsRepository {
  int calls = 0;
  Object? error;
  @override
  Future<YorksV1LogisticsWorkspace> confirmReceipt(
    YorksV1ReceiptConfirmationInput input,
  ) async {
    calls++;
    if (error != null) throw error!;
    return YorksV1LogisticsWorkspace.fromRpcJson(_response);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Outcomes implements YorksV1CommandOutcomeRepository {
  _Outcomes([
    this.result = const YorksV1WorkflowCommandOutcome(confirmed: false),
  ]);
  final YorksV1WorkflowCommandOutcome result;
  int calls = 0;
  @override
  Future<YorksV1WorkflowCommandOutcome> check(
    String command,
    String key,
  ) async {
    calls++;
    return result;
  }
}

class _Rpc implements YorksV1MaterialRequestRpcClient {
  _Rpc(this.response);
  final Object? response;
  @override
  Future<Object?> invoke({
    required String functionName,
    required Map<String, dynamic> parameters,
  }) async => response;
}

class _Requests implements YorksV1MaterialRequestRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Arrangements implements YorksV1ArrangementRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

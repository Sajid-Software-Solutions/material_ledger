import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/controllers/yorks_v1_project_setup_coordinator.dart';
import 'package:material_ledger/shared/models/analytics_event.dart';
import 'package:material_ledger/shared/models/yorks_v1_document.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_project.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_setup_operation.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_documents_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_draft_store.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_setup_journal_store.dart';
import 'package:material_ledger/shared/services/analytics_service.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';

void main() {
  test('canonical intent is immutable and detects corrupt payload/hash', () {
    final payload = <String, dynamic>{
      'a': <String, dynamic>{'value': 1},
    };
    final command = YorksV1ProjectSetupCommand(
      kind: YorksV1ProjectSetupCommandKind.create,
      idempotencyKey: 'key',
      payload: payload,
    );
    (payload['a'] as Map)['value'] = 2;
    expect(command.payload['a']['value'], 1);
    final json = command.toJson();
    (json['payload'] as Map)['changed'] = true;
    expect(
      () => YorksV1ProjectSetupCommand.fromJson(json),
      throwsFormatException,
    );
  });

  test(
    'no request can leave before the intent write is acknowledged',
    () async {
      final fixture = _Fixture();
      fixture.storage.failNextWrite = true;
      await expectLater(
        fixture.coordinator.prepareCreate(_input()),
        throwsA(isA<YorksV1ProjectSetupRecoveryException>()),
      );
      expect(fixture.repository.calls, isEmpty);
      expect(fixture.coordinator.currentState.operation, isNull);
    },
  );

  test(
    'response lost after commit reloads and replays one exact core effect',
    () async {
      final fixture = _Fixture();
      fixture.repository.loseNextResponse = true;
      await fixture.coordinator.prepareCreate(_input());
      await expectLater(
        fixture.coordinator.submitCore(),
        throwsA(isA<YorksV1DomainException>()),
      );
      final original = fixture.coordinator.currentState.operation!.core;
      expect(
        original.status,
        YorksV1ProjectSetupCommandStatus.outcomeUncertain,
      );
      final restored = fixture.restore();
      expect(restored.currentState.project, isNull);
      final project = await restored.reconcileCore();
      expect(project.id, 'project-1');
      expect(fixture.repository.effects, 1);
      expect(
        fixture.repository.calls.map((call) => call.idempotencyKey).toSet(),
        {original.idempotencyKey},
      );
      expect(
        fixture.repository.calls.map((call) => call.canonicalPayload).toSet(),
        {original.canonicalPayload},
      );
    },
  );

  test(
    'explicit reconciliation waits persisted jittered eligibility after reload',
    () async {
      final fixture = _Fixture();
      fixture.repository.loseNextResponse = true;
      await fixture.coordinator.prepareCreate(_input());
      await expectLater(
        fixture.coordinator.submitCore(),
        throwsA(isA<YorksV1DomainException>()),
      );
      final first = fixture.coordinator.currentState.operation!.core;
      expect(
        first.nextRetryAt,
        fixture.now.add(const Duration(milliseconds: 625)),
      );
      fixture.retryGate = Completer<void>();
      final restored = fixture.restore();
      final retry = restored.reconcileCore();
      expect(
        await fixture.retryDelayStarted.future,
        const Duration(milliseconds: 625),
      );
      expect(fixture.repository.calls, hasLength(1));
      expect(restored.currentState.operation!.core.attempts, 1);
      expect(restored.currentState.busy, isTrue);
      fixture.retryGate!.complete();
      expect((await retry).id, 'project-1');
      expect(fixture.repository.calls, hasLength(2));
      expect(restored.currentState.operation!.core.attempts, 2);
      expect(
        restored.currentState.operation!.core.nextRetryAt,
        fixture.now.add(const Duration(milliseconds: 1250)),
      );
      expect(
        fixture.repository.calls.map((call) => call.idempotencyKey).toSet(),
        {first.idempotencyKey},
      );
    },
  );

  test(
    'slow uncertain response starts backoff from observed failure',
    () async {
      final fixture = _Fixture();
      fixture.repository.loseNextResponse = true;
      fixture.repository.onResponseLoss = () {
        fixture.now = fixture.now.add(const Duration(seconds: 5));
      };
      await fixture.coordinator.prepareCreate(_input());
      await expectLater(
        fixture.coordinator.submitCore(),
        throwsA(isA<YorksV1DomainException>()),
      );
      expect(
        fixture.coordinator.currentState.operation!.core.nextRetryAt,
        fixture.now.add(const Duration(milliseconds: 625)),
      );
      await fixture.restore().reconcileCore();
      expect(fixture.delays, const [Duration(milliseconds: 625)]);
      expect(fixture.repository.effects, 1);
    },
  );

  test(
    'older unresolved journal gains acknowledged retry schedule before replay',
    () async {
      final fixture = _Fixture();
      fixture.repository.loseNextResponse = true;
      await fixture.coordinator.prepareCreate(_input());
      await expectLater(
        fixture.coordinator.submitCore(),
        throwsA(isA<YorksV1DomainException>()),
      );
      final json =
          jsonDecode(fixture.storage.values['scope:journal:draft-1']!)
              as Map<String, dynamic>;
      (json['core'] as Map).remove('next_retry_at');
      fixture.storage.values['scope:journal:draft-1'] = jsonEncode(json);
      fixture.retryGate = Completer<void>();
      final retry = fixture.restore().reconcileCore();
      await fixture.retryDelayStarted.future;
      final duringDelay = fixture.restore().currentState.operation!.core;
      expect(duringDelay.nextRetryAt, isNotNull);
      expect(duringDelay.attempts, 1);
      expect(fixture.repository.calls, hasLength(1));
      fixture.retryGate!.complete();
      await retry;
      expect(fixture.repository.effects, 1);
    },
  );

  test('known denial, invalid input and conflict are never replayed', () async {
    for (final code in [
      YorksV1DomainErrorCode.unauthorized,
      YorksV1DomainErrorCode.invalidInput,
      YorksV1DomainErrorCode.conflict,
    ]) {
      final fixture = _Fixture();
      fixture.repository.rejection = code;
      await fixture.coordinator.prepareCreate(_input());
      await expectLater(
        fixture.coordinator.submitCore(),
        throwsA(isA<YorksV1DomainException>()),
      );
      fixture.repository.rejection = null;
      await expectLater(
        fixture.restore().reconcileCore(),
        throwsA(isA<YorksV1DomainException>()),
      );
      expect(fixture.repository.calls, hasLength(1));
      expect(fixture.delays, isEmpty);
      expect(fixture.repository.effects, 0);
    }
  });

  test(
    'changed input cannot reuse or replace an unresolved reviewed intent',
    () async {
      final fixture = _Fixture();
      fixture.repository.loseNextResponse = true;
      await fixture.coordinator.prepareCreate(_input());
      await expectLater(
        fixture.coordinator.submitCore(),
        throwsA(isA<YorksV1DomainException>()),
      );
      final key =
          fixture.coordinator.currentState.operation!.core.idempotencyKey;
      await expectLater(
        fixture.coordinator.prepareCreate(_input(name: 'Changed')),
        throwsA(isA<YorksV1ProjectSetupRecoveryException>()),
      );
      expect(
        fixture.coordinator.currentState.operation!.core.idempotencyKey,
        key,
      );
    },
  );

  test(
    'denied replay after uncertain dispatch cannot disprove original commit',
    () async {
      final fixture = _Fixture();
      fixture.repository.loseNextResponse = true;
      await fixture.coordinator.prepareCreate(_input());
      await expectLater(
        fixture.coordinator.submitCore(),
        throwsA(isA<YorksV1DomainException>()),
      );
      fixture.repository.rejection = YorksV1DomainErrorCode.unauthorized;
      await expectLater(
        fixture.coordinator.reconcileCore(),
        throwsA(isA<YorksV1DomainException>()),
      );
      expect(
        fixture.coordinator.currentState.operation!.core.status,
        YorksV1ProjectSetupCommandStatus.outcomeUncertain,
      );
      await expectLater(
        fixture.coordinator.prepareCreate(_input(name: 'Changed')),
        throwsA(isA<YorksV1ProjectSetupRecoveryException>()),
      );
      expect(fixture.repository.effects, 1);
    },
  );

  test(
    'known pre-send offline attempts do not exhaust reconciliation budget',
    () async {
      final fixture = _Fixture();
      await fixture.coordinator.prepareCreate(_input());
      fixture.repository.preSendOffline = true;
      for (var i = 0; i < 4; i++) {
        await expectLater(
          fixture.coordinator.submitCore(),
          throwsA(isA<YorksV1DomainException>()),
        );
      }
      expect(fixture.coordinator.currentState.operation!.core.attempts, 0);
      fixture.repository.preSendOffline = false;
      expect((await fixture.coordinator.submitCore()).id, 'project-1');
    },
  );

  test(
    'update version and physical scope identity persist across replay',
    () async {
      final fixture = _Fixture(
        mode: YorksV1ProjectSetupMode.edit,
        projectId: 'project-1',
      );
      await fixture.coordinator.prepareUpdate(
        YorksV1ProjectUpdateInput(
          idempotencyKey: 'input-key',
          projectId: 'project-1',
          expectedProjectVersion: 7,
          project: _input(scopeId: 'scope-existing'),
        ),
      );
      fixture.repository.loseNextResponse = true;
      await expectLater(
        fixture.coordinator.submitCore(),
        throwsA(isA<YorksV1DomainException>()),
      );
      await fixture.restore().reconcileCore();
      expect(
        fixture.repository.calls.every(
          (command) =>
              command.expectedVersion == 7 &&
              (command.payload['buildings'] as List).first['id'] ==
                  'scope-existing',
        ),
        isTrue,
      );
    },
  );

  test(
    'activation failure preserves known Draft project and its stable phase intent',
    () async {
      final fixture = _Fixture();
      await fixture.coordinator.prepareCreate(_input());
      await fixture.coordinator.submitCore();
      fixture.repository.loseNextResponse = true;
      await expectLater(
        fixture.coordinator.activate(),
        throwsA(isA<YorksV1DomainException>()),
      );
      final key = fixture
          .coordinator
          .currentState
          .operation!
          .activation!
          .idempotencyKey;
      expect(fixture.coordinator.currentState.project!.id, 'project-1');
      expect(
        fixture.coordinator.currentState.project!.state,
        YorksV1ProjectLifecycle.draft,
      );
      final restored = fixture.restore();
      expect((await restored.activate()).state, YorksV1ProjectLifecycle.active);
      expect(
        fixture.repository.calls
            .where(
              (call) => call.kind == YorksV1ProjectSetupCommandKind.activate,
            )
            .map((call) => call.idempotencyKey)
            .toSet(),
        {key},
      );
      expect(
        fixture.repository.calls
            .where((call) => call.kind == YorksV1ProjectSetupCommandKind.create)
            .length,
        1,
      );
    },
  );

  test(
    'confirmed core response survives result journal acknowledgement failure',
    () async {
      final fixture = _Fixture();
      await fixture.coordinator.prepareCreate(_input());
      fixture.repository.afterResponse = () =>
          fixture.storage.failNextWrite = true;
      expect((await fixture.coordinator.submitCore()).id, 'project-1');
      expect(fixture.coordinator.currentState.project!.id, 'project-1');
      expect(
        fixture.coordinator.currentState.recoveryError,
        YorksV1ProjectSetupRecoveryError.journalUnavailable,
      );
      fixture.repository.afterResponse = null;
      expect((await fixture.restore().reconcileCore()).id, 'project-1');
      expect(fixture.repository.effects, 1);
    },
  );

  test(
    'same-page repair keeps confirmed core durable before activation dispatch',
    () async {
      final fixture = _Fixture();
      await fixture.coordinator.prepareCreate(_input());
      fixture.repository.afterResponse = () =>
          fixture.storage.failNextWrite = true;
      await fixture.coordinator.submitCore();
      expect(fixture.coordinator.currentState.operation!.coreSucceeded, isTrue);
      fixture.repository.afterResponse = null;
      final project = await fixture.coordinator.activate();
      expect(project.state, YorksV1ProjectLifecycle.active);
      expect(fixture.coordinator.currentState.operation!.coreSucceeded, isTrue);
      expect(fixture.restore().currentState.operation!.coreSucceeded, isTrue);
      expect(
        fixture.restore().currentState.project!.state,
        YorksV1ProjectLifecycle.active,
      );
      expect(
        fixture.repository.calls
            .where(
              (command) =>
                  command.kind == YorksV1ProjectSetupCommandKind.create,
            )
            .length,
        1,
      );
      expect(fixture.repository.effects, 2);
    },
  );

  test(
    'core acknowledgement repairs the receipt without replay or cleanup',
    () async {
      final fixture = _Fixture();
      await fixture.coordinator.prepareCreate(_input(), files: [_file()]);
      fixture.repository.afterResponse = () =>
          fixture.storage.failNextWrite = true;
      await fixture.coordinator.submitCore();
      fixture.repository.afterResponse = null;
      final known = fixture.coordinator.currentState.operation!;
      final acknowledged = await fixture.coordinator.acknowledgeConfirmedCore();
      expect(acknowledged.core.canonicalResult, known.core.canonicalResult);
      expect(acknowledged.core.idempotencyKey, known.core.idempotencyKey);
      expect(acknowledged.filesPending, isTrue);
      expect(acknowledged.cleanupComplete, isFalse);
      expect(fixture.restore().currentState.operation!.coreSucceeded, isTrue);
      expect(fixture.repository.calls, hasLength(1));
      expect(fixture.repository.effects, 1);
    },
  );

  test(
    'fresh creation skips confirmed follow-up but preserves its project locator',
    () async {
      final fixture = _Fixture();
      await fixture.coordinator.prepareCreate(_input(), files: [_file()]);
      await fixture.coordinator.submitCore();
      final completed = await fixture.coordinator.acknowledgeConfirmedCore();
      final original = fixture.storage.values['scope:journal:draft-1'];
      await fixture.storage.transaction('scope', (tx) {
        YorksV1ProjectSetupJournalStore.retainCompletedOperation(
          tx,
          scopeKey: 'scope',
          operation: completed,
        );
      });
      // Match the installed latest-pointer namespace for project discovery.
      fixture.storage.values['scope:latest_operation'] =
          fixture.storage.values['scope:latest']!;
      final fresh = fixture.restore(
        draftId: 'draft-2',
        restoreConfirmedFollowUps: false,
      );
      expect(fresh.currentState.operation, isNull);
      final next = await fresh.prepareCreate(_input(name: 'Next project'));
      expect(next.draftId, 'draft-2');
      expect(next.core.idempotencyKey, isNot(completed.core.idempotencyKey));
      fixture.storage.values['scope:latest_operation'] =
          fixture.storage.values['scope:latest']!;
      final pending = YorksV1ProjectSetupJournalStore.completedForProject(
        storage: fixture.storage,
        scopeKey: 'scope',
        backendIdentity: 'backend',
        ownerAuthUserId: 'owner',
        projectId: 'project-1',
        mode: YorksV1ProjectSetupMode.create,
      );
      expect(pending.single.draftId, 'draft-1');
      expect(
        pending.single.files.single.toJson(),
        completed.files.single.toJson(),
      );
      expect(
        pending.single.core.canonicalPayload,
        completed.core.canonicalPayload,
      );
      expect(fixture.storage.values['scope:journal:draft-1'], original);
      expect(fixture.repository.calls, hasLength(1));
    },
  );

  test(
    'fresh creation still guards the original unresolved core intent',
    () async {
      final fixture = _Fixture();
      await fixture.coordinator.prepareCreate(_input());
      fixture.repository.loseNextResponse = true;
      await expectLater(
        fixture.coordinator.submitCore(),
        throwsA(isA<YorksV1DomainException>()),
      );
      final original = fixture.coordinator.currentState.operation!;
      final fresh = fixture.restore(
        draftId: 'draft-2',
        restoreConfirmedFollowUps: false,
      );
      expect(fresh.currentState.operation!.draftId, 'draft-1');
      await expectLater(
        fresh.prepareCreate(_input(name: 'Changed intent')),
        throwsA(isA<YorksV1ProjectSetupRecoveryException>()),
      );
      expect(
        fresh.currentState.operation!.core.idempotencyKey,
        original.core.idempotencyKey,
      );
      expect(
        fresh.currentState.operation!.core.canonicalPayload,
        original.core.canonicalPayload,
      );
      expect(fixture.repository.calls, hasLength(1));
    },
  );

  test(
    'historical latest-pointer recovery stays discoverable before rotation',
    () async {
      final fixture = _Fixture();
      await fixture.coordinator.prepareCreate(_input(), files: [_file()]);
      await fixture.coordinator.submitCore();
      fixture.storage.values['scope:latest_operation'] =
          fixture.storage.values['scope:latest']!;
      final original = Map.of(fixture.storage.values);
      final pending = YorksV1ProjectSetupJournalStore.completedForProject(
        storage: fixture.storage,
        scopeKey: 'scope',
        backendIdentity: 'backend',
        ownerAuthUserId: 'owner',
        projectId: 'project-1',
        mode: YorksV1ProjectSetupMode.create,
      );
      expect(pending.single.files.single.idempotencyKey, 'upload-key');
      expect(fixture.storage.values, original);
    },
  );

  test(
    'historical follow-up cannot replace a newer unresolved active pointer',
    () async {
      final fixture = _Fixture();
      await fixture.coordinator.prepareCreate(_input(), files: [_file()]);
      await fixture.coordinator.submitCore();
      final old = fixture.coordinator.currentState.operation!;
      final fresh = fixture.restore(
        draftId: 'draft-2',
        restoreConfirmedFollowUps: false,
      );
      await fresh.prepareCreate(_input(name: 'New active project'));
      fixture.repository.loseNextResponse = true;
      await expectLater(
        fresh.submitCore(),
        throwsA(isA<YorksV1DomainException>()),
      );
      final activeRaw = fixture.storage.values['scope:journal:draft-2'];
      final pointer = fixture.storage.values['scope:latest'];
      final historical = fixture.restore(
        draftId: old.draftId,
        updateLatestOperation: false,
      );
      await historical.removePendingFile('file-1');
      expect(fixture.storage.values['scope:latest'], pointer);
      expect(fixture.storage.values['scope:journal:draft-2'], activeRaw);
      expect(
        historical.currentState.operation!.files.single.idempotencyKey,
        old.files.single.idempotencyKey,
      );
      final next = fixture.restore(
        draftId: 'draft-3',
        restoreConfirmedFollowUps: false,
      );
      expect(next.currentState.operation!.draftId, 'draft-2');
      expect(
        next.currentState.operation!.core.status,
        YorksV1ProjectSetupCommandStatus.outcomeUncertain,
      );
      expect(fixture.repository.calls, hasLength(2));
    },
  );

  test(
    'corrupt/future journal blocks writes and preserves original raw data',
    () async {
      final fixture = _Fixture();
      fixture.storage.values['scope:journal:draft-1'] = '{"schema_version":99}';
      final restored = fixture.restore();
      await expectLater(
        restored.prepareCreate(_input()),
        throwsA(isA<YorksV1ProjectSetupRecoveryException>()),
      );
      expect(
        fixture.storage.values['scope:journal:draft-1'],
        '{"schema_version":99}',
      );
      expect(fixture.repository.calls, isEmpty);
    },
  );

  test(
    'bounded uncertain retries retain the original journal for support',
    () async {
      final fixture = _Fixture();
      await fixture.coordinator.prepareCreate(_input());
      fixture.repository.alwaysLoseResponse = true;
      for (var i = 0; i < 3; i++) {
        await expectLater(
          fixture.coordinator.submitCore(),
          throwsA(isA<YorksV1DomainException>()),
        );
      }
      final raw = fixture.storage.values['scope:journal:draft-1'];
      await expectLater(
        fixture.coordinator.submitCore(),
        throwsA(isA<YorksV1ProjectSetupRecoveryException>()),
      );
      expect(fixture.storage.values['scope:journal:draft-1'], raw);
      expect(fixture.repository.effects, 1);
      expect(fixture.restore().currentState.operation!.core.attempts, 3);
      expect(fixture.delays, const [
        Duration(milliseconds: 625),
        Duration(milliseconds: 1250),
      ]);
    },
  );

  test(
    'new draft ID discovers prior known result and pending file after restart',
    () async {
      final fixture = _Fixture();
      await fixture.coordinator.prepareCreate(_input(), files: [_file()]);
      await fixture.coordinator.submitCore();
      final restarted = fixture.restore(draftId: 'draft-new');
      expect(restarted.currentState.project!.id, 'project-1');
      expect(restarted.currentState.operation!.filesPending, isTrue);
      await expectLater(
        restarted.markCleanupComplete(),
        throwsA(isA<YorksV1ProjectSetupRecoveryException>()),
      );
      final documents = _Documents();
      await restarted.uploadFile(
        localId: 'file-1',
        bytes: Uint8List.fromList([1, 2, 3]),
        documents: documents,
      );
      await restarted.markCleanupComplete();
      expect(
        fixture.restore(draftId: 'draft-next').currentState.operation,
        isNull,
      );
    },
  );

  test(
    'file reselection validates actual bytes and retains one upload key',
    () async {
      final fixture = _Fixture();
      await fixture.coordinator.prepareCreate(_input(), files: [_file()]);
      await fixture.coordinator.submitCore();
      final documents = _Documents()..loseNext = true;
      await expectLater(
        fixture.coordinator.uploadFile(
          localId: 'file-1',
          bytes: Uint8List.fromList([3, 2, 1]),
          documents: documents,
        ),
        throwsA(isA<YorksV1ProjectSetupRecoveryException>()),
      );
      expect(documents.keys, isEmpty);
      await expectLater(
        fixture.coordinator.uploadFile(
          localId: 'file-1',
          bytes: Uint8List.fromList([1, 2, 3]),
          documents: documents,
        ),
        throwsA(isA<YorksV1DomainException>()),
      );
      final restored = fixture.restore();
      expect(restored.currentState.project!.id, 'project-1');
      await restored.uploadFile(
        localId: 'file-1',
        bytes: Uint8List.fromList([1, 2, 3]),
        documents: documents,
      );
      expect(documents.keys.toSet(), {'upload-key'});
      expect(documents.effects, 1);
      expect(
        restored.currentState.operation!.files.single.status,
        YorksV1ProjectSetupFileStatus.ready,
      );
    },
  );

  test(
    'removing never-dispatched pending file preserves a durable tombstone',
    () async {
      final fixture = _Fixture();
      await fixture.coordinator.prepareCreate(_input(), files: [_file()]);
      await fixture.coordinator.submitCore();
      await fixture.coordinator.removePendingFile('file-1');
      final restored = fixture.restore();
      final removed = restored.currentState.operation!.files.single;
      expect(removed.status, YorksV1ProjectSetupFileStatus.removed);
      expect(removed.idempotencyKey, 'upload-key');
      expect(removed.contentHash, _file().contentHash);
      expect(restored.currentState.operation!.filesPending, isFalse);
      final documents = _Documents();
      await restored.uploadFile(
        localId: 'file-1',
        bytes: Uint8List.fromList([1, 2, 3]),
        documents: documents,
      );
      expect(documents.keys, isEmpty);
      await restored.markCleanupComplete();
      expect(
        fixture.restore().currentState.operation!.files.single.status,
        YorksV1ProjectSetupFileStatus.removed,
      );
    },
  );

  test(
    'unknown and finalized file attempts cannot be removed from recovery',
    () async {
      final fixture = _Fixture();
      await fixture.coordinator.prepareCreate(_input(), files: [_file()]);
      await fixture.coordinator.submitCore();
      final documents = _Documents()..loseNext = true;
      await expectLater(
        fixture.coordinator.uploadFile(
          localId: 'file-1',
          bytes: Uint8List.fromList([1, 2, 3]),
          documents: documents,
        ),
        throwsA(isA<YorksV1DomainException>()),
      );
      await expectLater(
        fixture.coordinator.removePendingFile('file-1'),
        throwsA(isA<YorksV1ProjectSetupRecoveryException>()),
      );
      expect(fixture.coordinator.currentState.operation!.filesPending, isTrue);
      await fixture.coordinator.uploadFile(
        localId: 'file-1',
        bytes: Uint8List.fromList([1, 2, 3]),
        documents: documents,
      );
      await expectLater(
        fixture.coordinator.removePendingFile('file-1'),
        throwsA(isA<YorksV1ProjectSetupRecoveryException>()),
      );
      expect(
        fixture.coordinator.currentState.operation!.files.single.status,
        YorksV1ProjectSetupFileStatus.ready,
      );
      expect(documents.effects, 1);
    },
  );

  test(
    'wrong edit project context blocks an internally valid recovery record',
    () async {
      final fixture = _Fixture(
        mode: YorksV1ProjectSetupMode.edit,
        projectId: 'project-1',
      );
      await fixture.coordinator.prepareUpdate(
        YorksV1ProjectUpdateInput(
          idempotencyKey: 'key',
          projectId: 'project-1',
          expectedProjectVersion: 1,
          project: _input(),
        ),
      );
      final restored = fixture.restore(projectId: 'another-project');
      expect(
        restored.currentState.recoveryError,
        YorksV1ProjectSetupRecoveryError.recoveryBlocked,
      );
      await expectLater(
        restored.submitCore(),
        throwsA(isA<YorksV1ProjectSetupRecoveryException>()),
      );
      expect(fixture.repository.calls, isEmpty);
    },
  );

  test(
    'reviewed core success and setup outcome are reported once across replay/reload',
    () async {
      final fixture = _Fixture();
      fixture.repository.loseNextResponse = true;
      await fixture.coordinator.prepareCreate(_input());
      await expectLater(
        fixture.coordinator.submitCore(),
        throwsA(isA<YorksV1DomainException>()),
      );
      final restored = fixture.restore();
      await restored.reconcileCore();
      await restored.captureKnownOutcome();
      await restored.captureKnownOutcome();
      await fixture.restore().submitCore();
      await fixture.restore().captureKnownOutcome();
      expect(
        fixture.analytics.events
            .where((event) => event == AnalyticsEvent.projectCreated)
            .length,
        1,
      );
      expect(
        fixture.analytics.events
            .where((event) => event == AnalyticsEvent.projectSetupCompleted)
            .length,
        1,
      );
    },
  );

  test(
    'throwing instrumentation cannot alter delayed explicit reconciliation',
    () async {
      final fixture = _Fixture();
      final coordinator = fixture.restore(
        analyticsService: _ThrowingAnalytics(),
      );
      await coordinator.prepareCreate(_input());
      fixture.repository.loseNextResponse = true;
      await expectLater(
        coordinator.submitCore(),
        throwsA(isA<YorksV1DomainException>()),
      );
      expect((await coordinator.reconcileCore()).id, 'project-1');
      await coordinator.captureKnownOutcome();
      expect(coordinator.currentState.operation!.coreSucceeded, isTrue);
      expect(fixture.repository.effects, 1);
      expect(fixture.delays, const [Duration(milliseconds: 625)]);
    },
  );

  test(
    'instrumentation failure before/after RPC cannot alter confirmed result',
    () async {
      final connectivity = DefaultConnectivity(online: true);
      final repository = YorksV1SupabaseProjectRepository(
        featureFlags: const YorksV1FeatureFlags(
          foundation: true,
          projects: true,
        ),
        connectivity: connectivity,
        rpcClient: _Rpc(),
        analytics: _ThrowingAnalytics(),
      );
      final command = YorksV1ProjectSetupCommand(
        kind: YorksV1ProjectSetupCommandKind.create,
        idempotencyKey: 'key',
        payload: _input().toRpcPayload(),
      );
      final response = await repository.executeReviewedCommand(command);
      expect(response['project']['id'], 'project-1');
    },
  );
}

YorksV1ProjectCreationInput _input({
  String name = 'Reviewed',
  String? scopeId,
}) => YorksV1ProjectCreationInput(
  idempotencyKey: 'input-key',
  reference: 'REF-1',
  name: name,
  buildings: [
    YorksV1ProjectBuildingInput(
      name: 'Building',
      code: 'b1',
      sourceScopeId: scopeId,
    ),
  ],
);
YorksV1ProjectSetupFile _file() => YorksV1ProjectSetupFile(
  localId: 'file-1',
  idempotencyKey: 'upload-key',
  fileName: 'plan.pdf',
  mimeType: 'application/pdf',
  sizeBytes: 3,
  classification: YorksV1DocumentClassification.operational,
  contentHash: sha256.convert([1, 2, 3]).toString(),
  status: YorksV1ProjectSetupFileStatus.selected,
);
Map<String, dynamic> _result(YorksV1ProjectSetupCommandKind kind) => {
  'project': {
    'id': 'project-1',
    'reference': 'REF-1',
    'name': 'Reviewed',
    'state': kind == YorksV1ProjectSetupCommandKind.activate
        ? 'active'
        : 'draft',
    'record_version': kind == YorksV1ProjectSetupCommandKind.activate ? 2 : 1,
    'created_at': '2026-10-03T00:00:00Z',
    'updated_at': '2026-10-03T00:00:00Z',
  },
  'members': [],
  'scopes': [],
};

class _Fixture {
  _Fixture({this.mode = YorksV1ProjectSetupMode.create, this.projectId}) {
    coordinator = restore();
  }
  final YorksV1ProjectSetupMode mode;
  final String? projectId;
  final storage = _AtomicStorage();
  final repository = _Server();
  final analytics = _RecordingAnalytics();
  late YorksV1ProjectSetupCoordinator coordinator;
  int key = 0;
  DateTime now = DateTime.utc(2026, 10, 3);
  final delays = <Duration>[];
  final retryDelayStarted = Completer<Duration>();
  Completer<void>? retryGate;
  YorksV1ProjectSetupCoordinator restore({
    String draftId = 'draft-1',
    String? projectId,
    AnalyticsService? analyticsService,
    bool restoreConfirmedFollowUps = true,
    bool updateLatestOperation = true,
  }) => YorksV1ProjectSetupCoordinator(
    store: YorksV1ProjectSetupJournalStore(
      storage: storage,
      journalKey: 'scope:journal:$draftId',
      latestOperationKey: 'scope:latest',
      backendIdentity: 'backend',
      ownerAuthUserId: 'owner',
      draftId: draftId,
      expectedMode: mode,
      projectId: projectId ?? this.projectId,
      restoreConfirmedFollowUps: restoreConfirmedFollowUps,
      updateLatestOperation: updateLatestOperation,
      atomicOwned: <T>(work) => storage.transaction('scope', work),
    ),
    repository: repository,
    analytics: analyticsService ?? analytics,
    keyFactory: () => 'key-${++key}',
    clock: () => now,
    retryRandom: () => 0.5,
    retryDelay: (duration) async {
      delays.add(duration);
      if (!retryDelayStarted.isCompleted) retryDelayStarted.complete(duration);
      if (retryGate != null) await retryGate!.future;
      now = now.add(duration);
    },
  );
}

class _AtomicStorage implements ProjectDraftAtomicStorage {
  final values = <String, String>{};
  bool failNextWrite = false;
  Future<void> serial = Future.value();
  @override
  bool get supportsAtomicOwnership => true;
  @override
  String? read(String key) => values[key];
  @override
  Future<T> transaction<T>(
    String lockKey,
    T Function(ProjectDraftAtomicTransaction) work,
  ) {
    final done = Completer<T>();
    serial = serial.then((_) {
      try {
        final next = Map<String, String>.of(values);
        final result = work(_Transaction(next));
        if (failNextWrite) {
          failNextWrite = false;
          throw const ProjectDraftStorageException('quota');
        }
        values
          ..clear()
          ..addAll(next);
        done.complete(result);
      } catch (error, stack) {
        done.completeError(error, stack);
      }
    });
    return done.future;
  }
}

class _Transaction implements ProjectDraftAtomicTransaction {
  _Transaction(this.values);
  final Map<String, String> values;
  @override
  String? read(String key) => values[key];
  @override
  void write(String key, String value) => values[key] = value;
  @override
  void remove(String key) => values.remove(key);
}

class _Server implements YorksV1ProjectReviewedCommandRepository {
  final calls = <YorksV1ProjectSetupCommand>[];
  final responses = <String, Map<String, dynamic>>{};
  final hashes = <String, String>{};
  bool loseNextResponse = false,
      alwaysLoseResponse = false,
      preSendOffline = false;
  YorksV1DomainErrorCode? rejection;
  void Function()? afterResponse;
  void Function()? onResponseLoss;
  int effects = 0;
  @override
  Future<Map<String, dynamic>> executeReviewedCommand(
    YorksV1ProjectSetupCommand command,
  ) async {
    if (preSendOffline) {
      throw const YorksV1ProjectCommandNotDispatchedException(
        YorksV1DomainException(YorksV1DomainErrorCode.offline),
      );
    }
    calls.add(command);
    if (rejection != null) throw YorksV1DomainException(rejection!);
    if (hashes.containsKey(command.idempotencyKey) &&
        hashes[command.idempotencyKey] != command.payloadHash) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    hashes[command.idempotencyKey] = command.payloadHash;
    final response = responses.putIfAbsent(command.idempotencyKey, () {
      effects++;
      return _result(command.kind);
    });
    if (loseNextResponse || alwaysLoseResponse) {
      loseNextResponse = false;
      onResponseLoss?.call();
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
    afterResponse?.call();
    return jsonDecode(jsonEncode(response)) as Map<String, dynamic>;
  }
}

class _Documents implements YorksV1DocumentsRepository {
  final keys = <String>[];
  final committed = <String>{};
  bool loseNext = false;
  int effects = 0;
  @override
  Future<YorksV1DocumentWorkspace> upload(
    YorksV1DocumentUploadInput input,
  ) async {
    keys.add(input.idempotencyKey);
    if (committed.add(input.idempotencyKey)) effects++;
    if (loseNext) {
      loseNext = false;
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
    return YorksV1DocumentWorkspace(
      projectId: input.projectId,
      documents: const [],
      auditEntries: const [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Rpc implements YorksV1ProjectRpcClient {
  @override
  Future<Map<String, dynamic>> invoke({
    required String functionName,
    required Map<String, dynamic> parameters,
  }) async => _result(YorksV1ProjectSetupCommandKind.create);
}

class _ThrowingAnalytics extends NoopAnalyticsService {
  @override
  void capture(
    AnalyticsEvent event, {
    AnalyticsProperties properties = const {},
  }) => throw StateError('Telemetry unavailable');
}

class _RecordingAnalytics extends NoopAnalyticsService {
  final events = <AnalyticsEvent>[];
  @override
  void capture(
    AnalyticsEvent event, {
    AnalyticsProperties properties = const {},
  }) => events.add(event);
}

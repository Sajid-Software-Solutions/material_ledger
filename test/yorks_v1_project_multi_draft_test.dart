import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:material_ledger/shared/controllers/yorks_v1_project_creation_draft_controller.dart';
import 'package:material_ledger/shared/models/yorks_v1_document.dart';
import 'package:material_ledger/shared/models/yorks_v1_project.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_creation_draft.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_local_creation_draft.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_setup_operation.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_creation_draft_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_setup_coordinator_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_setup_journal_store.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_creation_draft_catalogue.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_draft_store.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_local_creation_draft_repository.dart';

const _owner = 'multi-draft-owner';
const _backend = 'staging';
const _scope = 'owner-backend-create-scope';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'anchoring a new route to Resume reuses the exact provider and writer lease',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final storage = _OrderedStorage();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          yorksV1ProjectDraftBackendIdentityProvider.overrideWithValue(
            _backend,
          ),
          yorksV1ProjectDraftAtomicStorageProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);
      const freshContext = YorksV1ProjectCreationDraftContext(
        ownerAuthUserId: _owner,
        draftId: 'anchored-proposal',
        entry: YorksV1ProjectCreationDraftEntry.newProposal,
      );
      const resumeContext = YorksV1ProjectCreationDraftContext(
        ownerAuthUserId: _owner,
        draftId: 'anchored-proposal',
      );
      final freshProvider = yorksV1ProjectSetupCreationDraftByIdProvider(
        freshContext,
      );
      final fresh = container.read(freshProvider.notifier);
      await fresh.initialized;
      await fresh.save(fresh.state.copyWith(name: 'Current anchored proposal'));
      final envelope = storage.read(fresh.storageKey);
      final resumed = container.read(
        yorksV1ProjectSetupCreationDraftByIdProvider(resumeContext).notifier,
      );
      expect(resumed, same(fresh));
      expect(resumed.state.name, 'Current anchored proposal');
      expect(resumed.writable, true);
      expect(storage.read(fresh.storageKey), envelope);
    },
  );

  test(
    'invalid selected route ID cannot read unrelated records or become a blank editable draft',
    () async {
      SharedPreferences.setMockInitialValues({});
      final storage = _OrderedStorage()
        ..values['unrelated-private-record'] = 'Retain unrelated private bytes';
      final original = Map.of(storage.values);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          yorksV1ProjectDraftBackendIdentityProvider.overrideWithValue(
            _backend,
          ),
          yorksV1ProjectDraftAtomicStorageProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);
      final selected = container.read(
        yorksV1ProjectSetupCreationDraftByIdProvider(
          const YorksV1ProjectCreationDraftContext(
            ownerAuthUserId: _owner,
            draftId: '../../unrelated-private-record',
          ),
        ).notifier,
      );
      await selected.initialized;
      expect(
        selected.state.storageState,
        YorksV1ProjectDraftStorageState.recoveryRequired,
      );
      expect(selected.writable, false);
      expect(selected.state.name, isEmpty);
      expect(storage.values, original);
      expect(storage.readKeys, isNot(contains('unrelated-private-record')));
    },
  );

  test(
    'saving B preserves exact A; repeated saves update one catalogue item',
    () async {
      final storage = _OrderedStorage();
      final a = _writer(storage, 'proposal-a');
      addTearDown(a.dispose);
      await a.initialized;
      await a.save(_richProposal(a.state));
      final original = storage.read(a.storageKey);
      final b = _writer(storage, 'proposal-b');
      addTearDown(b.dispose);
      await b.initialized;
      expect(b.state.draftId, 'proposal-b');
      expect(
        b.state.creationIdempotencyKey,
        isNot(a.state.creationIdempotencyKey),
      );
      expect(b.state.hasRecoverableContent, false);
      expect(b.state.currentStage, YorksV1ProjectCreationStage.projectDetails);
      expect(_readCatalogue(storage).summaries.map((item) => item.draftId), [
        'proposal-a',
      ]);
      await b.save(b.state.copyWith(reference: 'B', name: 'Independent B'));
      await b.save(b.state.copyWith(name: 'B latest'));
      expect(storage.read(a.storageKey), original);
      expect(_catalogue().ids(storage.read(_catalogue().indexKey)), [
        'proposal-a',
        'proposal-b',
      ]);
      final resumedA = _writer(storage, 'proposal-a', resume: true);
      final resumedB = _writer(storage, 'proposal-b', resume: true);
      addTearDown(resumedA.dispose);
      addTearDown(resumedB.dispose);
      await Future.wait([resumedA.initialized, resumedB.initialized]);
      final originalProposal = YorksV1ProjectCreationDraft.fromJson(
        Map<String, dynamic>.from(
          (jsonDecode(original!) as Map)['draft'] as Map,
        ),
      );
      _expectSameProposal(resumedA.state, originalProposal);
      expect(resumedB.state.name, 'B latest');
      expect(resumedB.state.attachments, isEmpty);
      expect(resumedB.state.rawEditorState, isEmpty);
      expect(
        resumedA.state.attachments.single.category,
        YorksV1ProjectAttachmentCategory.drawing,
      );
      final summary = _readCatalogue(storage);
      expect(summary.summaries.map((item) => item.draftId).toSet(), {
        'proposal-a',
        'proposal-b',
      });
    },
  );

  test(
    'partial first-envelope acknowledgement leaves scoped recovery and keeps A',
    () async {
      final storage = _OrderedStorage();
      final a = _writer(storage, 'acknowledged-a');
      addTearDown(a.dispose);
      await a.initialized;
      await a.save(a.state.copyWith(name: 'Acknowledged A'));
      final exactA = storage.read(a.storageKey);
      storage.failWriteKey = _catalogue().recordKey('failed-b');
      final b = _writer(storage, 'failed-b');
      addTearDown(b.dispose);
      await b.initialized;
      expect(b.state.isAcknowledged, false);
      expect(b.state.storageState, YorksV1ProjectDraftStorageState.failed);
      expect(storage.read(b.storageKey), isNull);
      expect(storage.read(a.storageKey), exactA);
      final failed = _readCatalogue(storage);
      expect(failed.summaries.single.name, 'Acknowledged A');
      expect(failed.recoveryDraftIds, contains('failed-b'));
      await b.save(
        b.state.copyWith(name: 'B after retry'),
        saveTrigger: 'manual',
      );
      await b.flush(saveTrigger: 'manual');
      expect(b.state.isAcknowledged, true);
      expect(storage.read(a.storageKey), exactA);
      expect(_catalogue().ids(storage.read(_catalogue().indexKey)), [
        'acknowledged-a',
        'failed-b',
      ]);
      expect(_readCatalogue(storage).recoveryDraftIds, isEmpty);
      expect(_readCatalogue(storage).summaries, hasLength(2));
    },
  );

  test(
    'explicit Resume acquires the latest saved A and fences every old snapshot without changing B',
    () async {
      final storage = _OrderedStorage();
      final first = _writer(storage, 'direct-resume-a');
      final b = _writer(storage, 'independent-resume-b');
      addTearDown(first.dispose);
      addTearDown(b.dispose);
      await Future.wait([first.initialized, b.initialized]);
      await first.save(_richProposal(first.state));
      await b.save(b.state.copyWith(reference: 'B', name: 'Separate B'));
      final selected = _writer(storage, first.state.draftId, resume: true);
      addTearDown(selected.dispose);
      await selected.initialized;
      final capturedSelectedSnapshot = selected.state;
      await first.save(
        first.state.copyWith(
          name: 'Latest persisted Alpha',
          notes: 'Latest exact notes   ',
        ),
      );
      final latest = first.state;
      final envelope =
          jsonDecode(storage.read(first.storageKey)!) as Map<String, dynamic>;
      storage.values[first.storageKey] = jsonEncode({
        ...envelope,
        'future_envelope_data': {'keep': true},
      });
      final original = _operation(
        latest,
        YorksV1ProjectSetupCommandStatus.outcomeUncertain,
      );
      final journalKey = '$_scope:journal:${latest.draftId}';
      storage.values[journalKey] = jsonEncode(original.toJson());
      final exactJournal = storage.read(journalKey);
      final exactB = storage.read(b.storageKey);
      final acquisition = selected.resumeEditing(
        expectedDraftId: latest.draftId,
        canAcquire: () => true,
      );
      // A callback invoked against the old cached epoch cannot borrow the
      // explicit Resume grant while its initial await/storage request settles.
      var staleJournalRan = false;
      final staleJournal = selected.atomicOwned((tx) {
        staleJournalRan = true;
        tx.write(journalKey, 'stale callback overwrite');
      });
      final staleRejected = expectLater(
        staleJournal,
        throwsA(isA<ProjectDraftStorageException>()),
      );
      expect(await acquisition, true);
      await staleRejected;
      expect(staleJournalRan, false);
      expect(selected.writable, true);
      expect(selected.state.isReadOnly, false);
      expect(selected.state.writerEpoch, greaterThan(latest.writerEpoch));
      _expectSameProposal(selected.state, latest);
      expect(
        (jsonDecode(storage.read(first.storageKey)!)
            as Map)['future_envelope_data'],
        {'keep': true},
      );
      expect(storage.read(journalKey), exactJournal);
      expect(storage.read(b.storageKey), exactB);
      final exactSelected = storage.read(selected.storageKey);
      await expectLater(
        first.save(latest.copyWith(name: 'Former writer stale save')),
        throwsA(isA<ProjectDraftStorageException>()),
      );
      await expectLater(
        selected.save(
          capturedSelectedSnapshot.copyWith(name: 'Late callback stale epoch'),
        ),
        throwsA(isA<ProjectDraftStorageException>()),
      );
      expect(storage.read(selected.storageKey), exactSelected);
      expect(storage.read(b.storageKey), exactB);
      expect(storage.read(journalKey), exactJournal);
      await selected.save(
        selected.state.copyWith(name: 'Directly edited Alpha'),
      );
      expect(selected.state.isAcknowledged, true);
    },
  );

  test(
    'Resume preserves unacknowledged old input instead of replacing the latest acknowledged draft',
    () async {
      final storage = _OrderedStorage();
      final old = _writer(storage, 'buffered-resume');
      addTearDown(old.dispose);
      await old.initialized;
      await old.save(old.state.copyWith(name: 'Original acknowledged'));
      final current = _writer(storage, old.state.draftId, resume: true);
      addTearDown(current.dispose);
      await current.initialized;
      await current.takeOver();
      await current.save(
        current.state.copyWith(name: 'Other tab latest acknowledged'),
      );
      final exactLatest = storage.read(current.storageKey);
      await expectLater(
        old.save(
          old.state.copyWith(
            name: 'Private unsaved old typing',
            rawEditorState: {'dateStartText': '12/'},
          ),
        ),
        throwsA(isA<ProjectDraftStorageException>()),
      );
      expect(old.state.isAcknowledged, false);
      expect(
        await old.resumeEditing(
          expectedDraftId: old.state.draftId,
          canAcquire: () => true,
        ),
        false,
      );
      expect(
        old.state.storageState,
        YorksV1ProjectDraftStorageState.recoveryRequired,
      );
      expect(storage.read(current.storageKey), exactLatest);
      final preserved = storage.values.entries
          .where(
            (entry) => entry.key.startsWith('${old.storageKey}:quarantine:'),
          )
          .map((entry) => jsonDecode(entry.value) as Map)
          .toList();
      expect(preserved, hasLength(1));
      final snapshot = jsonDecode(preserved.single['raw'] as String) as Map;
      expect((snapshot['draft'] as Map)['name'], 'Private unsaved old typing');
      expect(
        (snapshot['draft'] as Map)['rawEditorState']['dateStartText'],
        '12/',
      );
    },
  );

  test(
    'Resume rechecks authorization after waiting for its storage lock',
    () async {
      final storage = _OrderedStorage();
      final first = _writer(storage, 'guarded-resume');
      addTearDown(first.dispose);
      await first.initialized;
      await first.save(
        first.state.copyWith(name: 'Retain authorized proposal'),
      );
      final selected = _writer(storage, first.state.draftId, resume: true);
      addTearDown(selected.dispose);
      await selected.initialized;
      final exact = Map.of(storage.values);
      final gate = Completer<void>();
      storage.blockBeforeNextWork = gate;
      var authorized = true;
      final resume = selected.resumeEditing(
        expectedDraftId: first.state.draftId,
        canAcquire: () => authorized,
      );
      await Future<void>.delayed(Duration.zero);
      authorized = false;
      gate.complete();
      expect(await resume, false);
      expect(storage.values, exact);
      expect(selected.state.isReadOnly, true);
    },
  );

  for (final competitor in [false, true]) {
    test(
      'lost Resume acknowledgement retries only its own lease, competitor=$competitor',
      () async {
        final storage = _OrderedStorage();
        final original = _writer(storage, 'retry-resume');
        addTearDown(original.dispose);
        await original.initialized;
        await original.save(
          original.state.copyWith(name: 'Latest saved before resume'),
        );
        final selected = _writer(storage, original.state.draftId, resume: true);
        addTearDown(selected.dispose);
        await selected.initialized;
        storage.failAfterWriteKey = selected.storageKey;
        expect(
          await selected.resumeEditing(
            expectedDraftId: original.state.draftId,
            canAcquire: () => true,
          ),
          false,
        );
        final grantedEnvelope = storage.read(selected.storageKey)!;
        final grantedEpoch =
            (jsonDecode(grantedEnvelope) as Map)['writerEpoch'];
        if (competitor) {
          final other = _writer(storage, original.state.draftId, resume: true);
          addTearDown(other.dispose);
          await other.initialized;
          await other.takeOver();
          await other.save(
            other.state.copyWith(name: 'Competing latest owner'),
          );
          final exactOther = storage.read(other.storageKey);
          expect(
            await selected.retryResumeOwnership(
              expectedDraftId: original.state.draftId,
              canAcquire: () => true,
            ),
            false,
          );
          expect(storage.read(other.storageKey), exactOther);
        } else {
          expect(
            await selected.retryResumeOwnership(
              expectedDraftId: original.state.draftId,
              canAcquire: () => true,
            ),
            true,
          );
          expect(selected.state.name, 'Latest saved before resume');
          expect(selected.state.writerEpoch, grantedEpoch);
          expect(
            (jsonDecode(storage.read(selected.storageKey)!)
                as Map)['writerEpoch'],
            grantedEpoch,
          );
          await selected.save(
            selected.state.copyWith(name: 'Editable after acknowledgement'),
          );
          expect(selected.state.isAcknowledged, true);
        }
      },
    );
  }

  test(
    'same-ID takeover fences A while another proposal remains independently writable',
    () async {
      final storage = _OrderedStorage();
      final a = _writer(storage, 'leased-a');
      addTearDown(a.dispose);
      await a.initialized;
      await a.save(a.state.copyWith(name: 'Original A'));
      final secondA = _writer(storage, 'leased-a', resume: true);
      final b = _writer(storage, 'independent-b');
      addTearDown(secondA.dispose);
      addTearDown(b.dispose);
      await Future.wait([secondA.initialized, b.initialized]);
      expect(
        secondA.state.storageState,
        YorksV1ProjectDraftStorageState.ownedElsewhere,
      );
      expect(b.writable, true);
      await b.save(b.state.copyWith(name: 'Independent B'));
      final exactB = storage.read(b.storageKey);
      await secondA.takeOver();
      await secondA.save(secondA.state.copyWith(name: 'New owner A'));
      await expectLater(
        a.save(a.state.copyWith(name: 'Stale A')),
        throwsA(isA<ProjectDraftStorageException>()),
      );
      expect(storage.read(b.storageKey), exactB);
      expect(
        _readCatalogue(storage).summaries.map((item) => item.name).toSet(),
        {'New owner A', 'Independent B'},
      );
      expect(storage.lockKeys.toSet(), {_scope});
    },
  );

  for (final status in [
    YorksV1ProjectSetupCommandStatus.outcomeUncertain,
    YorksV1ProjectSetupCommandStatus.confirmedSuccess,
  ]) {
    test(
      'fresh B preserves original ${status.name} journal and per-file intent',
      () async {
        final storage = _OrderedStorage();
        final a = _writer(storage, 'intent-a');
        addTearDown(a.dispose);
        await a.initialized;
        await a.save(_richProposal(a.state));
        final operation = _operation(a.state, status);
        final journalKey = '$_scope:journal:${a.state.draftId}';
        final journal = jsonEncode(operation.toJson());
        storage.values[journalKey] = journal;
        storage.values['$_scope:latest_operation'] = jsonEncode({
          'journal_key': journalKey,
        });
        final aEnvelope = storage.read(a.storageKey);
        final b = _writer(storage, 'intent-b');
        addTearDown(b.dispose);
        await b.initialized;
        await b.save(b.state.copyWith(name: 'B without original intent'));
        expect(storage.read(a.storageKey), aEnvelope);
        expect(storage.read(journalKey), journal);
        expect(
          storage.read('$_scope:latest_operation'),
          jsonEncode({'journal_key': journalKey}),
        );
        expect(b.state.attachments, isEmpty);
        final summary = _readCatalogue(storage);
        expect(
          summary.summaries.any((item) => item.draftId == 'intent-b'),
          true,
        );
        if (status == YorksV1ProjectSetupCommandStatus.outcomeUncertain) {
          expect(summary.outcomeUncertain, true);
          expect(
            summary.summaries.any((item) => item.draftId == 'intent-a'),
            true,
          );
        } else {
          expect(
            summary.summaries.any((item) => item.draftId == 'intent-a'),
            false,
          );
        }
      },
    );
  }

  test(
    'legacy singleton remains exact and resolves beside an independent indexed draft',
    () async {
      final storage = _OrderedStorage();
      final legacy = YorksV1ProjectCreationDraftController(
        ownerAuthUserId: _owner,
        backendIdentity: _backend,
        storageKey: _scope,
        storage: storage,
        idempotencyKeyFactory: () => 'legacy-${storage.nextId++}',
      );
      addTearDown(legacy.dispose);
      await legacy.initialized;
      await legacy.save(_richProposal(legacy.state));
      final exact = storage.read(_scope);
      final b = _writer(storage, 'post-legacy-b');
      addTearDown(b.dispose);
      await b.initialized;
      await b.save(b.state.copyWith(name: 'New independent proposal'));
      expect(storage.read(_scope), exact);
      final summary = _readCatalogue(storage);
      expect(summary.summaries.map((item) => item.draftId).toSet(), {
        legacy.state.draftId,
        'post-legacy-b',
      });
      final resumed = _writer(storage, legacy.state.draftId, resume: true);
      addTearDown(resumed.dispose);
      await resumed.initialized;
      expect(resumed.storageKey, _scope);
      _expectSameProposal(resumed.state, legacy.state);
      expect(
        storage.read(_catalogue().recordKey(legacy.state.draftId)),
        isNull,
      );
    },
  );

  test(
    'missing or corrupt selected Resume never creates a writable blank proposal',
    () async {
      for (final raw in [null, '{private invalid bytes']) {
        final storage = _OrderedStorage();
        final key = _catalogue().recordKey('missing-resume');
        if (raw != null) storage.values[key] = raw;
        final resumed = _writer(storage, 'missing-resume', resume: true);
        addTearDown(resumed.dispose);
        await resumed.initialized;
        expect(
          resumed.state.storageState,
          YorksV1ProjectDraftStorageState.recoveryRequired,
        );
        expect(resumed.writable, false);
        final retained = Map.of(storage.values);
        expect(
          await resumed.resumeEditing(
            expectedDraftId: 'missing-resume',
            canAcquire: () => true,
          ),
          false,
        );
        expect(storage.values, retained);
        expect(storage.read(key), raw);
        expect(storage.read(_catalogue().indexKey), isNull);
      }
    },
  );
  test(
    'Resume cannot claim a foreign owner/backend record or a different selected ID',
    () async {
      for (final mismatch in [
        'ownerAuthUserId',
        'backendIdentity',
        'draftId',
      ]) {
        final storage = _OrderedStorage();
        final original = _writer(storage, 'private-resume');
        addTearDown(original.dispose);
        await original.initialized;
        await original.save(
          original.state.copyWith(name: 'Retain private original'),
        );
        final envelope =
            jsonDecode(storage.read(original.storageKey)!)
                as Map<String, dynamic>;
        final draft = Map<String, dynamic>.from(envelope['draft'] as Map);
        draft[mismatch] = mismatch == 'backendIdentity'
            ? 'production'
            : 'foreign-value';
        storage.values[original.storageKey] = jsonEncode({
          ...envelope,
          'draft': draft,
        });
        final selected = _writer(storage, 'private-resume', resume: true);
        addTearDown(selected.dispose);
        await selected.initialized;
        final retained = Map.of(storage.values);
        expect(
          await selected.resumeEditing(
            expectedDraftId: 'private-resume',
            canAcquire: () => true,
          ),
          false,
        );
        expect(selected.writable, false);
        expect(selected.state.name, isEmpty);
        expect(storage.values, retained);
      }
    },
  );

  for (final failure in ['locator', 'confirmed-journal']) {
    test(
      '$failure partial commit keeps original intent reachable until known project recovery is durable',
      () async {
        final storage = _OrderedStorage();
        final writer = _writer(storage, 'confirmed-follow-up-a');
        addTearDown(writer.dispose);
        await writer.initialized;
        await writer.save(_richProposal(writer.state));
        final original = _operation(
          writer.state,
          YorksV1ProjectSetupCommandStatus.outcomeUncertain,
        );
        final journalKey = '$_scope:journal:${writer.state.draftId}';
        final originalJson = jsonEncode(original.toJson());
        storage.values[journalKey] = originalJson;
        final known = original.copyWith(
          core: original.core.withOutcome(
            status: YorksV1ProjectSetupCommandStatus.confirmedSuccess,
            result: {
              'idempotency_key': original.core.idempotencyKey,
              'project': {
                'id': 'known-follow-up-project',
                'reference': 'A-REF',
                'name': 'Saved incomplete A',
                'state': 'draft',
                'record_version': 1,
                'created_at': '2026-10-05T00:00:00Z',
              },
            },
          ),
        );
        final locatorKey = YorksV1ProjectSetupJournalStore.completedProjectKey(
          _scope,
          'known-follow-up-project',
        );
        final store = YorksV1ProjectSetupJournalStore(
          storage: storage,
          journalKey: journalKey,
          backendIdentity: _backend,
          ownerAuthUserId: _owner,
          draftId: writer.state.draftId,
          expectedMode: YorksV1ProjectSetupMode.create,
          atomicOwned: writer.atomicOwned,
        );
        storage.failWriteKey = failure == 'locator' ? locatorKey : journalKey;
        await expectLater(
          store.change((_) => known),
          throwsA(isA<ProjectDraftStorageException>()),
        );
        expect(storage.read(journalKey), originalJson);
        expect(_readCatalogue(storage).summaries.single.outcomeUncertain, true);
        expect(
          _readCatalogue(storage).summaries.single.draftId,
          writer.state.draftId,
        );
        expect(
          storage.read(locatorKey),
          failure == 'locator' ? isNull : isNotNull,
        );
        await store.change((_) => known);
        final pending = YorksV1ProjectSetupJournalStore.completedForProject(
          storage: storage,
          scopeKey: _scope,
          backendIdentity: _backend,
          ownerAuthUserId: _owner,
          projectId: 'known-follow-up-project',
          mode: YorksV1ProjectSetupMode.create,
        );
        expect(pending.single.draftId, writer.state.draftId);
        expect(
          pending.single.core.idempotencyKey,
          original.core.idempotencyKey,
        );
        expect(pending.single.core.payloadHash, original.core.payloadHash);
        expect(
          pending.single.files.single.idempotencyKey,
          'original-upload-intent',
        );
        expect(pending.single.files.single.contentHash, 'exact-original-hash');
        expect(_readCatalogue(storage).summaries, isEmpty);
        storage.failWriteKey = '$_scope:retired:${writer.state.draftId}';
        await expectLater(
          writer.retireConfirmedOperation(known),
          throwsA(isA<ProjectDraftStorageException>()),
        );
        expect(
          YorksV1ProjectSetupJournalStore.completedForProject(
            storage: storage,
            scopeKey: _scope,
            backendIdentity: _backend,
            ownerAuthUserId: _owner,
            projectId: 'known-follow-up-project',
            mode: YorksV1ProjectSetupMode.create,
          ).single.files.single.idempotencyKey,
          'original-upload-intent',
        );
      },
    );
  }

  test(
    'explicit legacy recovery reconciles original A while ordinary C stays exact and unretired',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final storage = _OrderedStorage();
      final repository = _OriginalOutcomeRepository();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          yorksV1AuthUserIdProvider.overrideWithValue(_owner),
          yorksV1ProjectDraftBackendIdentityProvider.overrideWithValue(
            _backend,
          ),
          yorksV1ProjectDraftAtomicStorageProvider.overrideWithValue(storage),
          yorksV1ProjectReviewedCommandRepositoryProvider.overrideWithValue(
            repository,
          ),
        ],
      );
      addTearDown(container.dispose);
      final c = container.read(
        yorksV1ProjectSetupCreationDraftProvider(_owner).notifier,
      );
      await c.initialized;
      await c.save(c.state.copyWith(name: 'Unrelated acknowledged C'));
      final originalA = c.state.copyWith(
        draftId: 'missing-original-a',
        creationIdempotencyKey: 'original-a-command-key',
        reference: 'ORIGINAL-A',
        name: 'Unknown original A',
      );
      final operation = _operation(
        originalA,
        YorksV1ProjectSetupCommandStatus.outcomeUncertain,
      );
      final root = c.journalScopeKey;
      final journalKey = '$root:journal:${originalA.draftId}';
      final pointer = jsonEncode({'journal_key': journalKey});
      storage.values[journalKey] = jsonEncode(operation.toJson());
      storage.values['$root:latest_operation'] = pointer;
      final exactC = storage.read(c.storageKey);
      final scope = (
        ownerAuthUserId: _owner,
        draftId: c.state.draftId,
        projectId: null as String?,
      );
      final ordinary = container.read(
        yorksV1ProjectSetupCoordinatorProvider(scope).notifier,
      );
      expect(ordinary.currentState.operation, isNull);
      final recovery = container.read(
        yorksV1ProjectLegacyRecoveryCoordinatorProvider(scope).notifier,
      );
      expect(recovery.currentState.operation!.draftId, originalA.draftId);
      expect(
        recovery.currentState.operation!.core.payloadHash,
        operation.core.payloadHash,
      );
      expect(repository.commands, isEmpty);
      final project = await recovery.reconcileCore();
      expect(project.id, 'original-a-project');
      expect(repository.commands, hasLength(1));
      expect(
        repository.commands.single.idempotencyKey,
        operation.core.idempotencyKey,
      );
      expect(repository.commands.single.payload, operation.core.payload);
      expect(
        repository.commands.single.payloadHash,
        operation.core.payloadHash,
      );
      expect(
        await c.retireConfirmedOperation(recovery.currentState.operation!),
        false,
      );
      expect(storage.read(c.storageKey), exactC);
      expect(storage.read('$root:latest_operation'), pointer);
      final confirmed = YorksV1ProjectSetupOperation.fromJson(
        Map<String, dynamic>.from(jsonDecode(storage.read(journalKey)!) as Map),
      );
      expect(confirmed.coreSucceeded, true);
      expect(confirmed.files.single.idempotencyKey, 'original-upload-intent');
      expect(confirmed.files.single.contentHash, 'exact-original-hash');
      expect(storage.read('$root:retired:${c.state.draftId}'), isNull);
    },
  );

  test(
    'a missing original legacy intent stays actionable without hydrating or replacing proposal C',
    () async {
      final storage = _OrderedStorage();
      final c = YorksV1ProjectCreationDraftController(
        ownerAuthUserId: _owner,
        backendIdentity: _backend,
        storageKey: _scope,
        storage: storage,
        idempotencyKeyFactory: () => 'legacy-c-${storage.nextId++}',
      );
      addTearDown(c.dispose);
      await c.initialized;
      await c.save(c.state.copyWith(name: 'Unrelated retained C'));
      final originalA = c.state.copyWith(
        draftId: 'original-a',
        creationIdempotencyKey: 'exact-original-a-core-key',
        reference: 'ORIGINAL-A',
        name: 'Original unknown A',
      );
      final operation = _operation(
        originalA,
        YorksV1ProjectSetupCommandStatus.outcomeUncertain,
      );
      final journalKey = '$_scope:journal:original-a';
      storage.values[journalKey] = jsonEncode(operation.toJson());
      storage.values['$_scope:latest_operation'] = jsonEncode({
        'journal_key': journalKey,
      });
      final exact = Map.of(storage.values);
      final summary = _readCatalogue(storage);
      expect(summary.summaries.single.name, 'Unrelated retained C');
      expect(summary.summaries.single.outcomeUncertain, false);
      expect(summary.recoveryDraftIds, contains('original-a'));
      expect(summary.legacyRecoveryDraftIds, contains('original-a'));
      expect(summary.hasLegacyRecovery, false);
      expect(storage.values, exact);
      final b = _writer(storage, 'fresh-independent-b');
      addTearDown(b.dispose);
      await b.initialized;
      await b.save(b.state.copyWith(name: 'Independent B'));
      expect(storage.read(_scope), exact[_scope]);
      expect(storage.read(journalKey), exact[journalKey]);
      expect(
        storage.read('$_scope:latest_operation'),
        exact['$_scope:latest_operation'],
      );
      expect(b.state.reference, isEmpty);
      expect(b.state.attachments, isEmpty);
      final after = _readCatalogue(storage);
      expect(after.legacyRecoveryDraftIds, contains('original-a'));
      expect(after.summaries.map((item) => item.name).toSet(), {
        'Unrelated retained C',
        'Independent B',
      });
    },
  );

  for (final corruption in ['malformed', 'foreign-owner']) {
    test(
      'legacy original intent recovery remains reachable beside $corruption indexed A and valid C',
      () async {
        final storage = _OrderedStorage();
        final c = YorksV1ProjectCreationDraftController(
          ownerAuthUserId: _owner,
          backendIdentity: _backend,
          storageKey: _scope,
          storage: storage,
          idempotencyKeyFactory: () => 'retained-c-${storage.nextId++}',
        );
        addTearDown(c.dispose);
        await c.initialized;
        await c.save(c.state.copyWith(name: 'Preserve independent C'));
        final a = c.state.copyWith(
          draftId: 'invalid-a',
          creationIdempotencyKey: 'original-a-intent',
          name: 'Original A',
        );
        final operation = _operation(
          a,
          YorksV1ProjectSetupCommandStatus.outcomeUncertain,
        );
        final journalKey = '$_scope:journal:invalid-a';
        storage.values[journalKey] = jsonEncode(operation.toJson());
        storage.values['$_scope:latest_operation'] = jsonEncode({
          'journal_key': journalKey,
        });
        storage.values[_catalogue().recordKey(
          'invalid-a',
        )] = corruption == 'malformed'
            ? '{private retained undecodable A'
            : jsonEncode({
                'recordVersion': 1,
                'ownerWriterId': 'foreign-owner-lease',
                'writerEpoch': a.writerEpoch,
                'retired': false,
                'draft': {...a.toJson(), 'ownerAuthUserId': 'different-owner'},
              });
        final original = Map.of(storage.values);
        final state = _readCatalogue(storage);
        expect(state.summaries.single.name, 'Preserve independent C');
        expect(state.recoveryDraftIds, contains('invalid-a'));
        expect(state.legacyRecoveryDraftIds, contains('invalid-a'));
        expect(storage.values, original);
        expect(
          storage.lockKeys,
          isNotEmpty,
        ); // Initial C, never the read projection.
        final beforeReadLocks = storage.lockKeys.length;
        _readCatalogue(storage);
        expect(storage.lockKeys.length, beforeReadLocks);
      },
    );
  }

  test(
    'malformed catalogue never hides or rewrites an acknowledged legacy proposal',
    () async {
      final storage = _OrderedStorage();
      final legacy = YorksV1ProjectCreationDraftController(
        ownerAuthUserId: _owner,
        backendIdentity: _backend,
        storageKey: _scope,
        storage: storage,
        idempotencyKeyFactory: () => 'retained-legacy-${storage.nextId++}',
      );
      addTearDown(legacy.dispose);
      await legacy.initialized;
      await legacy.save(legacy.state.copyWith(name: 'Retained legacy Alpha'));
      storage.values[_catalogue().indexKey] = '{private future catalogue bytes';
      final original = Map.of(storage.values);
      for (var refresh = 0; refresh < 2; refresh++) {
        final summary = _readCatalogue(storage);
        expect(summary.summaries.single.name, 'Retained legacy Alpha');
        expect(summary.hasCatalogueRecovery, true);
        expect(summary.hasLegacyRecovery, false);
        expect(storage.values, original);
      }
    },
  );

  for (final mismatch in ['owner', 'backend', 'schema_version', 'path']) {
    test(
      'catalogue $mismatch mismatch preserves private bytes and exposes no summary',
      () {
        final storage = _OrderedStorage();
        final index = <String, dynamic>{
          'schema_version': 1,
          'owner': _owner,
          'backend': _backend,
          'draft_ids': ['private-id'],
        };
        switch (mismatch) {
          case 'owner':
            index['owner'] = 'different-owner';
          case 'backend':
            index['backend'] = 'production';
          case 'schema_version':
            index['schema_version'] = 99;
          case 'path':
            index['draft_ids'] = ['../../foreign-private-record'];
        }
        storage.values[_catalogue().indexKey] = jsonEncode(index);
        storage.values['foreign-private-record'] = 'Private unrelated bytes';
        final original = Map.of(storage.values);
        final summary = _readCatalogue(storage);
        expect(
          summary.status,
          YorksV1ProjectLocalCreationDraftStatus.recoveryRequired,
        );
        expect(summary.summaries, isEmpty);
        expect(storage.values, original);
        expect(storage.readKeys, isNot(contains('foreign-private-record')));
        expect(storage.lockKeys, isEmpty);
      },
    );
  }
}

YorksV1ProjectCreationDraftCatalogue _catalogue() =>
    const YorksV1ProjectCreationDraftCatalogue(
      scopeKey: _scope,
      ownerAuthUserId: _owner,
      backendIdentity: _backend,
    );

YorksV1ProjectCreationDraftController _writer(
  _OrderedStorage storage,
  String id, {
  bool resume = false,
}) {
  final catalogue = _catalogue();
  return YorksV1ProjectCreationDraftController(
    ownerAuthUserId: _owner,
    backendIdentity: _backend,
    storageKey: catalogue.resolveRecordKey(storage.read, id),
    storage: storage,
    idempotencyKeyFactory: () => 'intent-${storage.nextId++}',
    initialDraftId: id,
    requireExistingRecord: resume,
    catalogue: catalogue,
    journalScopeKey: _scope,
  );
}

YorksV1ProjectLocalCreationDraftState _readCatalogue(_OrderedStorage storage) =>
    YorksV1ProjectLocalCreationDraftRepository(storage).readCatalogue(
      storageKey: _scope,
      ownerAuthUserId: _owner,
      backendIdentity: _backend,
    );

YorksV1ProjectCreationDraft _richProposal(YorksV1ProjectCreationDraft draft) =>
    draft.copyWith(
      reference: 'A-REF',
      name: 'Saved incomplete A',
      clientName: 'Private client',
      notes: 'Keep exact spacing   ',
      currentStage: YorksV1ProjectCreationStage.buildings,
      visitedStages: {
        YorksV1ProjectCreationStage.projectDetails,
        YorksV1ProjectCreationStage.buildings,
      },
      attachments: const [
        YorksV1ProjectAttachmentInput(
          fileName: 'private-plan.pdf',
          mimeType: 'application/pdf',
          sizeBytes: 3,
          localId: 'original-file-id',
          contentHash: 'exact-original-hash',
          categoryKey: 'drawing',
          retainedFields: {'future_file_metadata': 'preserve'},
        ),
      ],
      buildings: [
        YorksV1ProjectBuildingInput(
          name: 'Original building',
          localRowId: 'original-row-id',
          hasFrpRoom: false,
        ),
      ],
      rawEditorState: const {
        'dateStartText': '12/',
        'buildingName': 'Unfinished second building',
        'buildingLocalId': 'unfinished-row-id',
        'buildingFloors': 'Ground, Roof,',
        'subcontractorText': 'Unfinished subcontractor',
      },
      retainedFields: const {
        'future_proposal_metadata': {'keep': true},
      },
    );

void _expectSameProposal(
  YorksV1ProjectCreationDraft actual,
  YorksV1ProjectCreationDraft expected,
) {
  final left = actual.toJson();
  final right = expected.toJson();
  for (final json in [left, right]) {
    json.remove('writerEpoch');
    json.remove('storageState');
    json.remove('acknowledgedRevision');
    json.remove('visitedStages');
  }
  expect(actual.visitedStages, expected.visitedStages);
  expect(left, right);
}

YorksV1ProjectSetupOperation _operation(
  YorksV1ProjectCreationDraft draft,
  YorksV1ProjectSetupCommandStatus status,
) => YorksV1ProjectSetupOperation(
  backendIdentity: _backend,
  ownerAuthUserId: _owner,
  draftId: draft.draftId,
  mode: YorksV1ProjectSetupMode.create,
  core: YorksV1ProjectSetupCommand(
    kind: YorksV1ProjectSetupCommandKind.create,
    idempotencyKey: draft.creationIdempotencyKey,
    payload: draft.toCreationInput().toRpcPayload(),
    status: status,
    attempts: 1,
    result: status == YorksV1ProjectSetupCommandStatus.confirmedSuccess
        ? {
            'project': {'id': 'confirmed-original-project'},
          }
        : null,
  ),
  files: const [
    YorksV1ProjectSetupFile(
      localId: 'original-file-id',
      idempotencyKey: 'original-upload-intent',
      fileName: 'private-plan.pdf',
      mimeType: 'application/pdf',
      sizeBytes: 3,
      contentHash: 'exact-original-hash',
      classification: YorksV1DocumentClassification.operational,
      categoryKey: 'drawing',
      status: YorksV1ProjectSetupFileStatus.needsReselect,
    ),
  ],
);

/// Like the production adapters, acknowledges staged writes in order. A later
/// failure deliberately retains earlier writes, exercising partial local I/O.
class _OrderedStorage implements ProjectDraftAtomicStorage {
  final Map<String, String> values = {};
  final List<String> lockKeys = [];
  final List<String> readKeys = [];
  Future<void> _tail = Future.value();
  String? failWriteKey;
  String? failAfterWriteKey;
  Completer<void>? blockBeforeNextWork;
  int nextId = 0;
  @override
  bool get supportsAtomicOwnership => true;
  @override
  String? read(String key) {
    readKeys.add(key);
    return values[key];
  }

  @override
  Future<T> transaction<T>(
    String lockKey,
    T Function(ProjectDraftAtomicTransaction) work,
  ) async {
    lockKeys.add(lockKey);
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    try {
      await previous;
      final gate = blockBeforeNextWork;
      blockBeforeNextWork = null;
      if (gate != null) await gate.future;
      final tx = _Transaction(values);
      final result = work(tx);
      for (final entry in tx.writes.entries) {
        if (entry.key == failWriteKey) {
          failWriteKey = null;
          throw const ProjectDraftStorageException('write_not_acknowledged');
        }
        if (entry.value == null) {
          values.remove(entry.key);
        } else {
          values[entry.key] = entry.value!;
        }
        if (entry.key == failAfterWriteKey) {
          failAfterWriteKey = null;
          throw const ProjectDraftStorageException('write_not_acknowledged');
        }
      }
      return result;
    } finally {
      done.complete();
    }
  }
}

class _Transaction implements ProjectDraftAtomicTransaction {
  _Transaction(this.values);
  final Map<String, String> values;
  final Map<String, String?> writes = {};
  @override
  String? read(String key) =>
      writes.containsKey(key) ? writes[key] : values[key];
  @override
  void write(String key, String value) => writes[key] = value;
  @override
  void remove(String key) => writes[key] = null;
}

class _OriginalOutcomeRepository
    implements YorksV1ProjectReviewedCommandRepository {
  final List<YorksV1ProjectSetupCommand> commands = [];
  @override
  Future<Map<String, dynamic>> executeReviewedCommand(
    YorksV1ProjectSetupCommand command,
  ) async {
    commands.add(command);
    return {
      'idempotency_key': command.idempotencyKey,
      'project': {
        'id': 'original-a-project',
        'reference': 'ORIGINAL-A',
        'name': 'Unknown original A',
        'state': 'draft',
        'record_version': 1,
        'created_at': '2026-10-05T00:00:00Z',
        'updated_at': '2026-10-05T00:00:00Z',
      },
    };
  }
}

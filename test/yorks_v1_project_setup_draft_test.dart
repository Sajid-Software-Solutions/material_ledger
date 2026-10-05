import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:material_ledger/shared/controllers/yorks_v1_project_creation_draft_controller.dart';
import 'package:material_ledger/shared/models/yorks_v1_project.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_creation_draft.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_setup_operation.dart';
import 'package:material_ledger/shared/models/yorks_v1_document.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_creation_draft_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_setup_coordinator_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_draft_store.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_setup_journal_store.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_repository.dart';

void main() {
  test(
    'optional attachment category defaults locally and preserves historical JSON',
    () {
      final old = {
        'file_name': 'legacy.pdf',
        'mime_type': 'application/pdf',
        'size_bytes': 3,
        'local_id': 'legacy-file',
        'content_hash': 'retained-hash',
        'future_metadata': {'provenance': 'keep'},
      };
      final attachment = YorksV1ProjectAttachmentInput.fromDraftJson(old);
      expect(attachment.category, YorksV1ProjectAttachmentCategory.general);
      expect(attachment.toDraftJson(), old);
      final serverPayload = attachment.toRpcJson();
      final changed = attachment.copyWith(
        categoryKey: YorksV1ProjectAttachmentCategory.materialList.wireValue,
      );
      expect(changed.category, YorksV1ProjectAttachmentCategory.materialList);
      expect(changed.toRpcJson(), serverPayload);
      expect(changed.localId, attachment.localId);
      expect(changed.contentHash, attachment.contentHash);
      expect(changed.retainedFields, attachment.retainedFields);
      final restored = YorksV1ProjectAttachmentInput.fromDraftJson(
        jsonDecode(jsonEncode(changed.toDraftJson())) as Map<String, dynamic>,
      );
      expect(restored.categoryKey, 'material_list');
      expect(restored.toDraftJson(), changed.toDraftJson());
      final future = YorksV1ProjectAttachmentInput.fromDraftJson({
        ...old,
        'category': 'future-category',
      });
      expect(future.category, isNull);
      expect(
        future.copyWith(fileName: 'renamed.pdf').categoryKey,
        'future-category',
      );
      expect(future.copyWith(fileName: 'renamed.pdf').retainedFields, {
        'future_metadata': {'provenance': 'keep'},
      });
      expect(future.toDraftJson()['category'], 'future-category');
      expect(future.toRpcJson(), serverPayload);
    },
  );

  test(
    'file outcome changes preserve protected classification and unknown journal metadata',
    () {
      final original = {
        'local_id': 'pending-file',
        'key': 'original-file-command',
        'file_name': 'commercial.pdf',
        'mime_type': 'application/pdf',
        'size_bytes': 3,
        'classification': 'commercial',
        'content_hash': 'original-byte-hash',
        'status': 'outcomeUncertain',
        'error_code': null,
        'category': 'future-category',
        'future_upload_receipt': {'version': 9, 'token': 'retained'},
      };
      final file = YorksV1ProjectSetupFile.fromJson(original);
      expect(file.toJson(), original);
      expect(file.category, isNull);
      final resolved = file.withOutcome(YorksV1ProjectSetupFileStatus.ready);
      expect(resolved.toJson(), {...original, 'status': 'ready'});
      expect(resolved.classification, YorksV1DocumentClassification.commercial);
      expect(resolved.idempotencyKey, 'original-file-command');
      expect(resolved.contentHash, 'original-byte-hash');
      final old = {...original}..remove('category');
      final historical = YorksV1ProjectSetupFile.fromJson(old);
      expect(historical.category, YorksV1ProjectAttachmentCategory.general);
      expect(
        historical
            .withOutcome(YorksV1ProjectSetupFileStatus.needsReselect)
            .toJson(),
        {...old, 'status': 'needsReselect'},
      );
    },
  );

  test(
    'historical coordinator rebinds after rotation and cannot alter fresh draft or switched owner',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final storage = _AtomicMemoryStore();
      final repository = _NoReviewedDispatch();
      var auth = 'owner';
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          yorksV1AuthUserIdProvider.overrideWith((_) => auth),
          yorksV1ProjectDraftBackendIdentityProvider.overrideWithValue(
            'staging',
          ),
          yorksV1ProjectDraftAtomicStorageProvider.overrideWithValue(storage),
          yorksV1ProjectReviewedCommandRepositoryProvider.overrideWithValue(
            repository,
          ),
        ],
      );
      addTearDown(container.dispose);
      final draftProvider = yorksV1ProjectSetupCreationDraftProvider('owner');
      final first = container.read(draftProvider.notifier);
      await first.initialized;
      await first.save(first.state.copyWith(name: 'Confirmed'));
      final operation = _confirmedOperation(first.state.draftId);
      final journalKey = '${first.storageKey}:journal:${operation.draftId}';
      await first.atomicOwned((tx) {
        tx.write(journalKey, jsonEncode(operation.toJson()));
        tx.write(
          '${first.storageKey}:latest_operation',
          jsonEncode({'journal_key': journalKey}),
        );
      });
      final scope = (
        ownerAuthUserId: 'owner',
        draftId: operation.draftId,
        projectId: null as String?,
      );
      final old = container.read(
        yorksV1ProjectSetupCoordinatorProvider(scope).notifier,
      );
      await first.retireConfirmedOperation(operation);
      container.invalidate(draftProvider);
      final fresh = container.read(draftProvider.notifier);
      await fresh.initialized;
      final historical = container.read(
        yorksV1ProjectSetupCoordinatorProvider(scope).notifier,
      );
      expect(historical, isNot(same(old)));
      expect(fresh.state.name, isEmpty);
      final freshScope = (
        ownerAuthUserId: 'owner',
        draftId: fresh.state.draftId,
        projectId: null as String?,
      );
      await container
          .read(yorksV1ProjectSetupCoordinatorProvider(freshScope).notifier)
          .prepareCreate(
            YorksV1ProjectCreationInput(
              idempotencyKey: 'next',
              reference: 'R2',
              name: 'Next',
              buildings: [YorksV1ProjectBuildingInput(name: 'Next building')],
            ),
          );
      final envelope = storage.values[fresh.storageKey];
      final pointer = storage.values['${fresh.storageKey}:latest_operation'];
      await historical.removePendingFile('file-1');
      expect(storage.values[fresh.storageKey], envelope);
      expect(storage.values['${fresh.storageKey}:latest_operation'], pointer);
      expect(
        historical.currentState.operation!.core.idempotencyKey,
        'retained-core-key',
      );
      expect(
        historical.currentState.operation!.files.single.idempotencyKey,
        'retained-file-key',
      );
      auth = 'other';
      container.invalidate(yorksV1AuthUserIdProvider);
      await expectLater(historical.markCleanupComplete(), throwsA(anything));
      expect(storage.values[fresh.storageKey], envelope);
      expect(storage.values['${fresh.storageKey}:latest_operation'], pointer);
      expect(repository.calls, 0);
    },
  );
  test(
    'pending project discovery is owner/backend scoped and reads installed history',
    () {
      final storage = _AtomicMemoryStore();
      final scopeKey = yorksV1ProjectDraftStorageKey(
        backendIdentity: 'staging',
        ownerAuthUserId: 'owner',
        mode: YorksV1ProjectDraftMode.create,
      );
      final operation = YorksV1ProjectSetupOperation(
        backendIdentity: 'staging',
        ownerAuthUserId: 'owner',
        draftId: 'completed-draft',
        mode: YorksV1ProjectSetupMode.create,
        core: YorksV1ProjectSetupCommand(
          kind: YorksV1ProjectSetupCommandKind.create,
          idempotencyKey: 'retained-key',
          payload: {'name': 'Known'},
          status: YorksV1ProjectSetupCommandStatus.confirmedSuccess,
          result: {
            'project': {
              'id': 'project-result',
              'reference': 'R1',
              'name': 'Known',
              'state': 'draft',
              'record_version': 1,
              'created_at': '2026-10-03T00:00:00Z',
              'updated_at': '2026-10-03T00:00:00Z',
            },
          },
        ),
      );
      final journalKey = '$scopeKey:journal:${operation.draftId}';
      storage.values[journalKey] = jsonEncode(operation.toJson());
      storage.values['$scopeKey:latest_operation'] = jsonEncode({
        'journal_key': journalKey,
      });
      final original = Map.of(storage.values);
      ProviderContainer container({
        String owner = 'owner',
        String backend = 'staging',
      }) => ProviderContainer(
        overrides: [
          yorksV1AuthUserIdProvider.overrideWithValue(owner),
          yorksV1ProjectDraftBackendIdentityProvider.overrideWithValue(backend),
          yorksV1ProjectDraftAtomicStorageProvider.overrideWithValue(storage),
        ],
      );
      final sameOwner = container();
      final otherOwner = container(owner: 'other');
      final production = container(backend: 'production');
      addTearDown(sameOwner.dispose);
      addTearDown(otherOwner.dispose);
      addTearDown(production.dispose);
      final pending = yorksV1ProjectSetupPendingOperationsProvider((
        ownerAuthUserId: 'owner',
        projectId: 'project-result',
      ));
      final row = sameOwner.read(pending).single;
      expect(row.scope, (
        ownerAuthUserId: 'owner',
        draftId: 'completed-draft',
        projectId: null,
      ));
      expect(row.operation.toJson(), operation.toJson());
      expect(otherOwner.read(pending), isEmpty);
      expect(production.read(pending), isEmpty);
      expect(storage.values, original);

      storage.values[YorksV1ProjectSetupJournalStore.completedProjectKey(
        scopeKey,
        'project-result',
      )] = jsonEncode({
        'schema_version': 1,
        'backend': 'staging',
        'owner': 'owner',
        'project_id': 'project-result',
        'journal_keys': ['foreign-scope:journal:completed-draft'],
      });
      final corruptOriginal = Map.of(storage.values);
      sameOwner.invalidate(pending);
      expect(() => sameOwner.read(pending), throwsA(isA<FormatException>()));
      expect(storage.values, corruptOriginal);
    },
  );
  test(
    'edit serialization retains scope identity, flags and explicit FRP no',
    () {
      final base = YorksV1ProjectBuildingInput.fromDraftJson({
        'sourceScopeId': 'existing-scope',
        'localRowId': 'local-row',
        'code': ' B01 ',
        'name': ' Main building ',
        'floors_levels': ['B1', 'Ground', 'Roof'],
        'flags': {'has_frp_room': true, 'retained_flag': 'keep'},
        'future_local_metadata': {'preserve': true},
      });
      final edited = base.copyWith(hasFrpRoom: false);
      final restored = YorksV1ProjectBuildingInput.fromDraftJson(
        edited.toDraftJson(),
      );
      expect(restored.sourceScopeId, 'existing-scope');
      expect(restored.localRowId, 'local-row');
      expect(restored.name, ' Main building ');
      expect(restored.toUpdateRpcJson()['id'], 'existing-scope');
      expect(restored.toRpcJson()['flags'], {
        'has_frp_room': false,
        'retained_flag': 'keep',
      });
      expect(restored.retainedFields['future_local_metadata'], {
        'preserve': true,
      });
      expect(
        restored.toRpcJson().containsKey('future_local_metadata'),
        isFalse,
      );
      expect(restored.floorsOrLevels, ['B1', 'Ground', 'Roof']);
    },
  );

  test(
    'complete proposal preserves raw text and unknown supported metadata',
    () {
      final original =
          YorksV1ProjectCreationDraft.empty(
            ownerAuthUserId: 'owner',
            creationIdempotencyKey: 'intent',
            backendIdentity: 'https://staging.example',
            mode: YorksV1ProjectDraftMode.edit,
            projectId: 'project',
          ).copyWith(
            baseVersion: 12,
            baseSnapshot: {'reference': 'R1', 'scope_id': 'scope'},
            clientContactName: ' Hidden contact ',
            clientContactEmail: 'contact@example.test',
            notes: 'unfinished   ',
            rawEditorState: {
              'buildingLocalId': 'row-1',
              'buildingFloors': 'B1, G,',
              'dateStartText': '2026-0',
              'buildingFrp': true,
            },
            visitedStages: {
              YorksV1ProjectCreationStage.projectDetails,
              YorksV1ProjectCreationStage.reviewAndCreate,
            },
            retainedFields: {
              'unknown_supported': {'nested': 5},
            },
          );
      final roundTrip = YorksV1ProjectCreationDraft.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(roundTrip.toJson(), original.toJson());
      expect(roundTrip.toCreationInput().clientContactName, ' Hidden contact ');
      expect(roundTrip.mode, YorksV1ProjectDraftMode.edit);
      expect(roundTrip.baseVersion, 12);
      expect(roundTrip.isAcknowledged, isFalse);
    },
  );

  test('base snapshot cannot change when source nested collections mutate', () {
    final source = <String, dynamic>{
      'buildings': [
        <String, dynamic>{'name': 'Original'},
      ],
    };
    final draft = YorksV1ProjectCreationDraft.empty(
      ownerAuthUserId: 'owner',
      creationIdempotencyKey: 'intent',
    ).copyWith(baseSnapshot: source);
    (source['buildings'] as List).single['name'] = 'Mutated source';
    expect(
      (draft.baseSnapshot['buildings'] as List).single['name'],
      'Original',
    );
    expect(
      () => (draft.baseSnapshot['buildings'] as List).single['name'] =
          'Mutated draft',
      throwsUnsupportedError,
    );
  });

  test(
    'unknown party kind, invalid rows and future schema cannot become valid input',
    () {
      final json = YorksV1ProjectCreationDraft.empty(
        ownerAuthUserId: 'owner',
        creationIdempotencyKey: 'intent',
      ).toJson();
      expect(
        () => YorksV1ProjectCreationDraft.fromJson({
          ...json,
          'schemaVersion': 99,
        }),
        throwsFormatException,
      );
      expect(
        () => YorksV1ProjectCreationDraft.fromJson({
          ...json,
          'parties': [
            {'kind': 'authority', 'name': 'Legacy authority'},
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => YorksV1ProjectCreationDraft.fromJson({
          ...json,
          'buildings': [
            {'name': 'Building'},
            'bad-row',
          ],
        }),
        throwsFormatException,
      );
    },
  );

  group('acknowledged writer', () {
    late _AtomicMemoryStore store;
    var sequence = 0;
    YorksV1ProjectCreationDraftController controller({
      String key = 'draft',
      String? legacyRaw,
      String backend = 'staging',
      YorksV1ProjectDraftMode mode = YorksV1ProjectDraftMode.create,
      String? projectId,
    }) => YorksV1ProjectCreationDraftController(
      ownerAuthUserId: 'owner',
      backendIdentity: backend,
      storageKey: key,
      storage: store,
      idempotencyKeyFactory: () => 'key-${++sequence}',
      mode: mode,
      projectId: projectId,
      legacyRaw: legacyRaw,
    );
    setUp(() {
      store = _AtomicMemoryStore();
      sequence = 0;
    });

    test(
      'older acknowledgment cannot mark newer input saved; writes coalesce',
      () async {
        final writer = controller();
        addTearDown(writer.dispose);
        await writer.verifyOwnership();
        final barrier1 = Completer<void>();
        final barrier2 = Completer<void>();
        store.barriers.addAll([barrier1, barrier2]);
        final first = writer.save(writer.state.copyWith(name: 'First'));
        await Future<void>.delayed(Duration.zero);
        final second = writer.save(writer.state.copyWith(name: 'Second'));
        final third = writer.save(writer.state.copyWith(name: 'Latest'));
        expect(writer.state.isAcknowledged, isFalse);
        barrier1.complete();
        await first;
        expect(writer.state.acknowledgedRevision, 1);
        expect(writer.state.revision, 3);
        expect(writer.state.isAcknowledged, isFalse);
        barrier2.complete();
        await Future.wait([second, third]);
        expect(writer.state.isAcknowledged, isTrue);
        final persisted = jsonDecode(store.values['draft']!) as Map;
        expect((persisted['draft'] as Map)['name'], 'Latest');
        expect((persisted['draft'] as Map)['revision'], 3);
        expect(store.commitCount, 3); // claim, first, coalesced latest
      },
    );

    test(
      'failed write keeps latest typing and flush retries acknowledged revision',
      () async {
        final writer = controller();
        addTearDown(writer.dispose);
        await writer.verifyOwnership();
        store.failNextWrite = true;
        await expectLater(
          writer.save(writer.state.copyWith(name: 'Keep me')),
          throwsA(isA<ProjectDraftStorageException>()),
        );
        expect(writer.state.name, 'Keep me');
        expect(writer.state.acknowledgedRevision, 0);
        expect(
          writer.state.storageState,
          YorksV1ProjectDraftStorageState.failed,
        );
        await writer.flush();
        expect(writer.state.isAcknowledged, isTrue);
        expect(writer.state.name, 'Keep me');
      },
    );

    test('manual save retries a failed initial ownership claim', () async {
      store.failNextWrite = true;
      final writer = controller();
      addTearDown(writer.dispose);
      await writer.initialized;
      expect(writer.state.storageState, YorksV1ProjectDraftStorageState.failed);
      expect(store.values['draft'], isNull);

      await writer.save(
        writer.state.copyWith(name: 'Keep input after storage recovers'),
        saveTrigger: 'manual',
      );
      await writer.flush(saveTrigger: 'manual');

      expect(writer.state.isAcknowledged, isTrue);
      final persisted = jsonDecode(store.values['draft']!) as Map;
      expect(
        (persisted['draft'] as Map)['name'],
        'Keep input after storage recovers',
      );
    });

    test('a recovered claim never takes over another tab', () async {
      store.failNextWrite = true;
      final first = controller();
      addTearDown(first.dispose);
      await first.initialized;
      final second = controller();
      addTearDown(second.dispose);
      await second.initialized;
      await second.save(second.state.copyWith(name: 'Other tab owns this'));

      await expectLater(
        first.save(
          first.state.copyWith(name: 'Must not overwrite other tab'),
          saveTrigger: 'manual',
        ),
        throwsA(isA<ProjectDraftStorageException>()),
      );
      expect(
        first.state.storageState,
        YorksV1ProjectDraftStorageState.ownedElsewhere,
      );
      expect(first.state.name, 'Must not overwrite other tab');
      final persisted = jsonDecode(store.values['draft']!) as Map;
      expect((persisted['draft'] as Map)['name'], 'Other tab owns this');
      expect(second.state.isAcknowledged, isTrue);
      final recovered = store.values.entries
          .where((entry) => entry.key.startsWith('draft:quarantine:'))
          .single;
      final raw = (jsonDecode(recovered.value) as Map)['raw'] as String;
      expect(
        ((jsonDecode(raw) as Map)['draft'] as Map)['name'],
        'Must not overwrite other tab',
      );
    });

    test(
      'a failed quarantine keeps unpublished input writable and blocks exit acknowledgement',
      () async {
        store.failNextWrite = true;
        final first = controller();
        addTearDown(first.dispose);
        await first.initialized;
        final second = controller();
        addTearDown(second.dispose);
        await second.initialized;
        await second.save(second.state.copyWith(name: 'Other durable owner'));
        final original = store.values['draft'];
        store.failNextWrite = true;
        await expectLater(
          first.save(
            first.state.copyWith(name: 'Unpublished until storage recovers'),
          ),
          throwsA(isA<ProjectDraftStorageException>()),
        );
        expect(first.state.name, 'Unpublished until storage recovers');
        expect(
          first.state.storageState,
          YorksV1ProjectDraftStorageState.failed,
        );
        expect(first.state.isReadOnly, isFalse);
        expect(first.state.isAcknowledged, isFalse);
        expect(store.values['draft'], original);
        expect(
          store.values.keys.where((key) => key.startsWith('draft:quarantine:')),
          isEmpty,
        );
      },
    );

    for (final foreignOwner in [true, false]) {
      test(
        'a delayed ${foreignOwner ? 'foreign-owner' : 'retained-draft'} refusal preserves typing until quarantine acknowledgement',
        () async {
          store.failNextWrite = true;
          final writer = controller();
          addTearDown(writer.dispose);
          await writer.initialized;
          final retainedOwner = controller();
          await retainedOwner.initialized;
          await retainedOwner.save(
            retainedOwner.state.copyWith(name: 'Existing durable input'),
          );
          if (foreignOwner) {
            addTearDown(retainedOwner.dispose);
          } else {
            retainedOwner.dispose();
            await store.transaction('draft', (_) {});
          }
          final original = store.values['draft'];
          final proposalId = writer.state.draftId;
          final proposalIntent = writer.state.creationIdempotencyKey;
          final firstAcknowledgement = Completer<void>();
          final latestAcknowledgement = Completer<void>();
          store.barriers.addAll([firstAcknowledgement, latestAcknowledgement]);
          final first = writer.save(
            writer.state.copyWith(name: 'Earlier unpublished input'),
          );
          final firstRejected = expectLater(
            first,
            throwsA(isA<ProjectDraftStorageException>()),
          );
          await Future<void>.delayed(Duration.zero);
          final latest = writer.save(
            writer.state.copyWith(
              name: 'Latest typing during acknowledgement',
              rawEditorState: {'dateStartText': '2026-10-'},
            ),
          );
          var latestCompleted = false;
          final latestRejected = expectLater(
            latest.whenComplete(() => latestCompleted = true),
            throwsA(isA<ProjectDraftStorageException>()),
          );

          firstAcknowledgement.complete();
          await Future<void>.delayed(Duration.zero);
          expect(latestCompleted, isFalse);
          expect(writer.state.isReadOnly, isFalse);
          expect(writer.state.name, 'Latest typing during acknowledgement');
          expect(store.values['draft'], original);

          latestAcknowledgement.complete();
          await Future.wait([firstRejected, latestRejected]);
          expect(writer.state.name, 'Latest typing during acknowledgement');
          expect(writer.state.rawEditorState['dateStartText'], '2026-10-');
          expect(writer.state.draftId, proposalId);
          expect(writer.state.creationIdempotencyKey, proposalIntent);
          expect(writer.state.isAcknowledged, isFalse);
          expect(
            writer.state.storageState,
            foreignOwner
                ? YorksV1ProjectDraftStorageState.ownedElsewhere
                : YorksV1ProjectDraftStorageState.recoveryRequired,
          );
          expect(store.values['draft'], original);
          final recovered = store.values.entries
              .where((entry) => entry.key.startsWith('draft:quarantine:'))
              .single;
          expect(recovered.key, contains(proposalId));
          final raw = (jsonDecode(recovered.value) as Map)['raw'] as String;
          final proposal = (jsonDecode(raw) as Map)['draft'] as Map;
          expect(proposal['name'], 'Latest typing during acknowledgement');
          expect(
            (proposal['rawEditorState'] as Map)['dateStartText'],
            '2026-10-',
          );
          expect(proposal['draftId'], proposalId);
          expect(proposal['creationIdempotencyKey'], proposalIntent);
          expect(proposal['revision'], writer.state.revision);
        },
      );
    }

    test(
      'a failed newer quarantine acknowledgement keeps latest input and blocks read-only exit',
      () async {
        store.failNextWrite = true;
        final writer = controller();
        addTearDown(writer.dispose);
        await writer.initialized;
        final retainedOwner = controller();
        addTearDown(retainedOwner.dispose);
        await retainedOwner.initialized;
        await retainedOwner.save(
          retainedOwner.state.copyWith(name: 'Other durable owner'),
        );
        final original = store.values['draft'];
        final firstAcknowledgement = Completer<void>();
        final latestAcknowledgement = Completer<void>();
        store.barriers.addAll([firstAcknowledgement, latestAcknowledgement]);
        final first = writer.save(writer.state.copyWith(name: 'Earlier input'));
        final firstRejected = expectLater(
          first,
          throwsA(isA<ProjectDraftStorageException>()),
        );
        await Future<void>.delayed(Duration.zero);
        final latest = writer.save(writer.state.copyWith(name: 'Keep latest'));
        final latestRejected = expectLater(
          latest,
          throwsA(isA<ProjectDraftStorageException>()),
        );
        firstAcknowledgement.complete();
        await Future<void>.delayed(Duration.zero);
        store.failNextWrite = true;
        latestAcknowledgement.complete();
        await Future.wait([firstRejected, latestRejected]);

        expect(writer.state.name, 'Keep latest');
        expect(writer.state.isAcknowledged, isFalse);
        expect(writer.state.isReadOnly, isFalse);
        expect(
          writer.state.storageState,
          YorksV1ProjectDraftStorageState.failed,
        );
        expect(store.values['draft'], original);

        await expectLater(
          writer.flush(),
          throwsA(isA<ProjectDraftStorageException>()),
        );
        expect(writer.state.name, 'Keep latest');
        expect(
          writer.state.storageState,
          YorksV1ProjectDraftStorageState.ownedElsewhere,
        );
        final recovered = store.values.entries
            .where((entry) => entry.key.startsWith('draft:quarantine:'))
            .single;
        final raw = (jsonDecode(recovered.value) as Map)['raw'] as String;
        expect(
          ((jsonDecode(raw) as Map)['draft'] as Map)['name'],
          'Keep latest',
        );
        expect(store.values['draft'], original);
      },
    );

    for (final sameDraftId in [false, true]) {
      test(
        'failed claim recovery preserves ${sameDraftId ? 'newer revision' : 'different draft'} and unpublished input',
        () async {
          final retained =
              YorksV1ProjectCreationDraft.empty(
                ownerAuthUserId: 'owner',
                backendIdentity: 'staging',
                creationIdempotencyKey: 'retained-intent',
              ).copyWith(
                draftId: sameDraftId ? 'key-2' : 'retained-id',
                name: 'Previously durable proposal',
                revision: 5,
                acknowledgedRevision: 5,
              );
          final original = jsonEncode({
            'recordVersion': 1,
            'ownerWriterId': null,
            'writerEpoch': 3,
            'retired': false,
            'draft': retained.toJson(),
          });
          store.values['draft'] = original;
          store.readMissingOnce = true;
          store.failNextWrite = true;
          final writer = controller();
          addTearDown(writer.dispose);
          await writer.initialized;
          final unpublishedId = writer.state.draftId;
          final unpublishedIntent = writer.state.creationIdempotencyKey;
          await expectLater(
            writer.save(
              writer.state.copyWith(name: 'Input typed during failure'),
            ),
            throwsA(isA<ProjectDraftStorageException>()),
          );
          expect(
            writer.state.storageState,
            YorksV1ProjectDraftStorageState.recoveryRequired,
          );
          expect(writer.state.name, 'Input typed during failure');
          expect(writer.state.draftId, unpublishedId);
          expect(writer.state.creationIdempotencyKey, unpublishedIntent);
          expect(store.values['draft'], original);
          final recovered = store.values.entries
              .where((entry) => entry.key.startsWith('draft:quarantine:'))
              .single;
          final raw = (jsonDecode(recovered.value) as Map)['raw'] as String;
          final proposal = (jsonDecode(raw) as Map)['draft'] as Map;
          expect(proposal['name'], 'Input typed during failure');
          expect(proposal['draftId'], unpublishedId);
          expect(proposal['creationIdempotencyKey'], unpublishedIntent);
        },
      );
    }

    test(
      'disposing a queued recovery claim writes no owner envelope',
      () async {
        store.failNextWrite = true;
        final writer = controller();
        await writer.initialized;
        final blocked = Completer<void>();
        store.barriers.add(blocked);
        final preceding = store.transaction(
          'unrelated',
          (tx) => tx.write('unrelated', 'keep'),
        );
        await Future<void>.delayed(Duration.zero);
        final save = writer.save(
          writer.state.copyWith(name: 'Cancelled pending recovery'),
          saveTrigger: 'manual',
        );
        final rejected = expectLater(
          save,
          throwsA(isA<ProjectDraftStorageException>()),
        );
        await Future<void>.delayed(Duration.zero);
        writer.dispose();
        blocked.complete();
        await preceding;
        await rejected;
        await store.transaction('drain', (_) {});
        expect(store.values['draft'], isNull);
        expect(store.values['unrelated'], 'keep');
      },
    );

    test(
      'flush awaits newer edits while the manual save is committing',
      () async {
        final writer = controller();
        addTearDown(writer.dispose);
        await writer.initialized;
        final firstWrite = Completer<void>();
        final newestWrite = Completer<void>();
        store.barriers.addAll([firstWrite, newestWrite]);
        final manual = writer.save(
          writer.state.copyWith(name: 'Manual snapshot'),
          saveTrigger: 'manual',
        );
        await Future<void>.delayed(Duration.zero);
        final latest = writer.save(writer.state.copyWith(name: 'Newer typing'));
        var flushed = false;
        final flush = writer.flush(saveTrigger: 'manual').then((_) {
          flushed = true;
        });
        firstWrite.complete();
        await manual;
        await Future<void>.delayed(Duration.zero);
        expect(flushed, isFalse);
        expect(writer.state.isAcknowledged, isFalse);
        newestWrite.complete();
        await Future.wait([latest, flush]);
        expect(writer.state.isAcknowledged, isTrue);
        expect(writer.state.name, 'Newer typing');
        final persisted = jsonDecode(store.values['draft']!) as Map;
        expect((persisted['draft'] as Map)['name'], 'Newer typing');
      },
    );

    test(
      'takeover reloads acknowledged data and fences a resumed writer',
      () async {
        final first = controller();
        final second = controller();
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        await first.verifyOwnership();
        await first.save(first.state.copyWith(name: 'Latest on disk'));
        await Future<void>.delayed(Duration.zero);
        expect(
          second.state.storageState,
          YorksV1ProjectDraftStorageState.ownedElsewhere,
        );
        await second.takeOver();
        expect(second.state.name, 'Latest on disk');
        await second.save(second.state.copyWith(name: 'New owner'));
        await expectLater(
          first.save(first.state.copyWith(name: 'Sleeping old tab')),
          throwsA(isA<ProjectDraftStorageException>()),
        );
        expect(
          first.state.storageState,
          YorksV1ProjectDraftStorageState.ownedElsewhere,
        );
        final persisted = jsonDecode(store.values['draft']!) as Map;
        expect((persisted['draft'] as Map)['name'], 'New owner');
      },
    );

    test(
      'initial claim rereads latest data after a stale synchronous restore',
      () async {
        final first = controller();
        await first.verifyOwnership();
        await first.save(first.state.copyWith(name: 'Older restore snapshot'));
        final staleRead = store.values['draft'];
        await first.save(first.state.copyWith(name: 'Latest before release'));
        first.dispose();
        await store.transaction('draft', (_) {});
        store.readOverrideOnce = staleRead;
        final next = controller();
        addTearDown(next.dispose);
        expect(next.state.name, 'Older restore snapshot');
        await next.initialized;
        expect(next.state.name, 'Latest before release');
        final persisted = jsonDecode(store.values['draft']!) as Map;
        expect((persisted['draft'] as Map)['name'], 'Latest before release');
      },
    );

    test(
      'retirement fences late writes and preserves result plus journal',
      () async {
        final first = controller();
        addTearDown(first.dispose);
        await first.verifyOwnership();
        await first.save(first.state.copyWith(name: 'Created'));
        await first.atomicOwned(
          (tx) => tx.write('draft:journal:${first.state.draftId}', 'confirmed'),
        );
        final retiredId = first.state.draftId;
        await first.retire(resultProjectId: 'project-result');
        final next = controller();
        addTearDown(next.dispose);
        await next.verifyOwnership();
        expect(next.state.name, isEmpty);
        expect(next.state.draftId, isNot(retiredId));
        await expectLater(
          first.save(first.state.copyWith(name: 'Resurrect')),
          throwsA(isA<ProjectDraftStorageException>()),
        );
        expect(store.values['draft:journal:$retiredId'], 'confirmed');
        final tombstone =
            jsonDecode(store.values['draft:retired:$retiredId']!) as Map;
        expect(tombstone['resultProjectId'], 'project-result');
      },
    );

    test(
      'confirmed core frees the slot while retaining exact pending follow-up',
      () async {
        final first = controller();
        addTearDown(first.dispose);
        await first.initialized;
        await first.save(first.state.copyWith(name: 'Confirmed project'));
        final operation = YorksV1ProjectSetupOperation(
          backendIdentity: 'staging',
          ownerAuthUserId: 'owner',
          draftId: first.state.draftId,
          mode: YorksV1ProjectSetupMode.create,
          core: YorksV1ProjectSetupCommand(
            kind: YorksV1ProjectSetupCommandKind.create,
            idempotencyKey: 'original-core-key',
            payload: {'name': 'Confirmed project'},
            status: YorksV1ProjectSetupCommandStatus.confirmedSuccess,
            result: {
              'project': {
                'id': 'project-result',
                'reference': 'R1',
                'name': 'Confirmed project',
                'state': 'draft',
                'record_version': 1,
                'created_at': '2026-10-03T00:00:00Z',
                'updated_at': '2026-10-03T00:00:00Z',
              },
            },
          ),
          activation: YorksV1ProjectSetupCommand(
            kind: YorksV1ProjectSetupCommandKind.activate,
            idempotencyKey: 'original-activation-key',
            payload: {'project_id': 'project-result', 'expected_version': 1},
            status: YorksV1ProjectSetupCommandStatus.outcomeUncertain,
          ),
          files: [
            YorksV1ProjectSetupFile(
              localId: 'file-1',
              idempotencyKey: 'original-file-key',
              fileName: 'plan.pdf',
              mimeType: 'application/pdf',
              sizeBytes: 3,
              classification: YorksV1DocumentClassification.operational,
              contentHash: 'retained-hash',
              status: YorksV1ProjectSetupFileStatus.needsReselect,
            ),
          ],
        );
        final journalKey = 'draft:journal:${first.state.draftId}';
        await first.atomicOwned(
          (tx) => tx.write(journalKey, jsonEncode(operation.toJson())),
        );
        final original = store.values[journalKey];
        await first.retireConfirmedOperation(operation);
        await first.retireConfirmedOperation(operation); // acknowledged retry
        final next = controller();
        addTearDown(next.dispose);
        await next.initialized;
        expect(next.state.name, isEmpty);
        expect(next.state.draftId, isNot(operation.draftId));
        expect(store.values[journalKey], original);
        final pending = YorksV1ProjectSetupJournalStore.completedForProject(
          storage: store,
          scopeKey: 'draft',
          backendIdentity: 'staging',
          ownerAuthUserId: 'owner',
          projectId: 'project-result',
          mode: YorksV1ProjectSetupMode.create,
        );
        expect(pending.single.toJson(), operation.toJson());
        final tombstone =
            jsonDecode(store.values['draft:retired:${operation.draftId}']!)
                as Map;
        expect(tombstone['resultProjectId'], 'project-result');
        await expectLater(
          first.save(first.state.copyWith(name: 'Resurrect')),
          throwsA(isA<ProjectDraftStorageException>()),
        );
        expect(next.state.name, isEmpty);

        // Historical follow-up mutates only its original journal under the new
        // current owner's fence, without changing the fresh editable proposal.
        final envelope = store.values['draft'];
        final recoveryStore = YorksV1ProjectSetupJournalStore(
          storage: store,
          journalKey: journalKey,
          backendIdentity: 'staging',
          ownerAuthUserId: 'owner',
          draftId: operation.draftId,
          expectedMode: YorksV1ProjectSetupMode.create,
          atomicOwned: next.atomicOwned,
        );
        await recoveryStore.change(
          (current) => current!.copyWith(revision: current.revision + 1),
        );
        expect(store.values['draft'], envelope);
        expect(recoveryStore.read()!.core.idempotencyKey, 'original-core-key');
        expect(
          recoveryStore.read()!.files.single.idempotencyKey,
          'original-file-key',
        );
      },
    );

    test(
      'unacknowledged or unresolved core cannot release the draft slot',
      () async {
        final writer = controller();
        addTearDown(writer.dispose);
        await writer.initialized;
        await writer.save(
          writer.state.copyWith(name: 'Keep unresolved proposal'),
        );
        final original = store.values['draft'];
        final unresolved = YorksV1ProjectSetupOperation(
          backendIdentity: 'staging',
          ownerAuthUserId: 'owner',
          draftId: writer.state.draftId,
          mode: YorksV1ProjectSetupMode.create,
          core: YorksV1ProjectSetupCommand(
            kind: YorksV1ProjectSetupCommandKind.create,
            idempotencyKey: 'unknown-core',
            payload: {'name': 'Keep unresolved proposal'},
            status: YorksV1ProjectSetupCommandStatus.outcomeUncertain,
          ),
        );
        await writer.atomicOwned(
          (tx) => tx.write(
            'draft:journal:${writer.state.draftId}',
            jsonEncode(unresolved.toJson()),
          ),
        );
        await expectLater(
          writer.retireConfirmedOperation(unresolved),
          throwsA(isA<ProjectDraftStorageException>()),
        );
        final known = unresolved.copyWith(
          core: unresolved.core.withOutcome(
            status: YorksV1ProjectSetupCommandStatus.confirmedSuccess,
            result: {
              'project': {
                'id': 'project-result',
                'reference': 'R1',
                'name': 'Keep unresolved proposal',
                'state': 'draft',
                'record_version': 1,
                'created_at': '2026-10-03T00:00:00Z',
                'updated_at': '2026-10-03T00:00:00Z',
              },
            },
          ),
        );
        await expectLater(
          writer.retireConfirmedOperation(known),
          throwsA(isA<ProjectDraftStorageException>()),
        );
        expect(store.values['draft'], original);
        expect(
          store.values.keys.where((key) => key.contains(':completed_project:')),
          isEmpty,
        );
        expect(writer.state.name, 'Keep unresolved proposal');
      },
    );

    test(
      'confirmed original recovery indexes without retiring a different active proposal',
      () async {
        final writer = controller();
        addTearDown(writer.dispose);
        await writer.initialized;
        await writer.save(
          writer.state.copyWith(
            name: 'Different unpublished proposal',
            notes: ' Keep exact current input ',
            rawEditorState: {
              'dateStartText': '2026-10-',
              'buildingName': 'Unapplied building',
            },
          ),
        );
        final current = writer.state.toJson();
        final original = _confirmedOperation('earlier-draft');
        final originalKey = 'draft:journal:${original.draftId}';
        await writer.atomicOwned((tx) {
          tx.write(originalKey, jsonEncode(original.toJson()));
          tx.write(
            'draft:latest_operation',
            jsonEncode({'journal_key': originalKey}),
          );
          tx.write(
            'draft:retired:${original.draftId}',
            'retained historical tombstone',
          );
        });
        final envelope = store.values['draft'];
        final journal = store.values[originalKey];
        final pointer = store.values['draft:latest_operation'];
        expect(await writer.retireConfirmedOperation(original), isFalse);
        expect(writer.state.toJson(), current);
        expect(store.values['draft'], envelope);
        expect(store.values[originalKey], journal);
        expect(store.values['draft:latest_operation'], pointer);
        expect(
          store.values['draft:retired:${original.draftId}'],
          'retained historical tombstone',
        );
        final pending = YorksV1ProjectSetupJournalStore.completedForProject(
          storage: store,
          scopeKey: 'draft',
          backendIdentity: 'staging',
          ownerAuthUserId: 'owner',
          projectId: 'project-result',
          mode: YorksV1ProjectSetupMode.create,
        );
        expect(pending.single.toJson(), original.toJson());
        await writer.save(
          writer.state.copyWith(notes: 'Current proposal remains writable'),
        );
        expect(writer.state.isAcknowledged, isTrue);
        expect(writer.state.draftId, current['draftId']);
        expect(store.values[originalKey], journal);
      },
    );

    test(
      'corrupt raw data is quarantined without overwriting its source',
      () async {
        store.values['draft'] = '{bad json';
        final writer = controller();
        addTearDown(writer.dispose);
        await Future<void>.delayed(Duration.zero);
        expect(
          writer.state.storageState,
          YorksV1ProjectDraftStorageState.recoveryRequired,
        );
        expect(store.values['draft'], '{bad json');
        expect(
          (jsonDecode(store.values['draft:quarantine']!) as Map)['raw'],
          '{bad json',
        );
        await expectLater(
          writer.save(writer.state.copyWith(name: 'overwrite')),
          throwsA(isA<ProjectDraftStorageException>()),
        );
      },
    );

    test(
      'legacy backend provenance requires explicit review and adoption',
      () async {
        final legacy =
            YorksV1ProjectCreationDraft.empty(
              ownerAuthUserId: 'owner',
              creationIdempotencyKey: 'old-intent',
            ).copyWith(
              name: 'Legacy proposal',
              rawEditorState: {'dateStartText': '2026-'},
            );
        final raw = jsonEncode([legacy.toJson()..remove('backendIdentity')]);
        final writer = controller(legacyRaw: raw);
        addTearDown(writer.dispose);
        await Future<void>.delayed(Duration.zero);
        expect(
          writer.state.storageState,
          YorksV1ProjectDraftStorageState.recoveryRequired,
        );
        expect(writer.readQuarantinedProposal()?.name, 'Legacy proposal');
        await writer.adoptQuarantinedProposal();
        expect(writer.state.name, 'Legacy proposal');
        expect(writer.state.backendIdentity, 'staging');
        expect(writer.state.rawEditorState['dateStartText'], '2026-');
        expect(writer.state.isAcknowledged, isTrue);
        expect(
          (jsonDecode(store.values['draft:quarantine']!) as Map)['raw'],
          raw,
        );
      },
    );
  });

  test(
    'create, edit and environments restore to separate namespaces',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      ProviderContainer context(String backend) => ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          yorksV1ProjectDraftBackendIdentityProvider.overrideWithValue(backend),
        ],
      );
      var staging = context('staging');
      final create = staging.read(
        yorksV1ProjectSetupCreationDraftProvider('owner').notifier,
      );
      await create.save(create.state.copyWith(name: 'Staging create'));
      final editKey = YorksV1ProjectEditDraftContext(
        ownerAuthUserId: 'owner',
        projectId: 'existing',
      );
      final edit = staging.read(
        yorksV1ProjectEditDraftProvider(editKey).notifier,
      );
      await edit.initializeEdit(
        YorksV1ProjectCreationDraft.empty(
          ownerAuthUserId: 'owner',
          creationIdempotencyKey: 'seed',
          mode: YorksV1ProjectDraftMode.edit,
          projectId: 'existing',
        ).copyWith(
          name: 'Edit proposal',
          baseVersion: 8,
          baseSnapshot: {'name': 'Original'},
        ),
      );
      staging.dispose();
      staging = context('staging');
      final production = context('production');
      addTearDown(staging.dispose);
      addTearDown(production.dispose);
      expect(
        staging.read(yorksV1ProjectSetupCreationDraftProvider('owner')).name,
        'Staging create',
      );
      final restoredEdit = staging.read(
        yorksV1ProjectEditDraftProvider(editKey),
      );
      expect(restoredEdit.name, 'Edit proposal');
      expect(restoredEdit.baseVersion, 8);
      expect(restoredEdit.baseSnapshot, {'name': 'Original'});
      expect(
        production.read(yorksV1ProjectSetupCreationDraftProvider('owner')).name,
        isEmpty,
      );
      expect(
        staging.read(yorksV1ProjectSetupCreationDraftProvider('other')).name,
        isEmpty,
      );
    },
  );
}

YorksV1ProjectSetupOperation _confirmedOperation(String draftId) =>
    YorksV1ProjectSetupOperation(
      backendIdentity: 'staging',
      ownerAuthUserId: 'owner',
      draftId: draftId,
      mode: YorksV1ProjectSetupMode.create,
      core: YorksV1ProjectSetupCommand(
        kind: YorksV1ProjectSetupCommandKind.create,
        idempotencyKey: 'retained-core-key',
        payload: {'name': 'Confirmed'},
        status: YorksV1ProjectSetupCommandStatus.confirmedSuccess,
        result: {
          'project': {
            'id': 'project-result',
            'reference': 'R1',
            'name': 'Confirmed',
            'state': 'draft',
            'record_version': 1,
            'created_at': '2026-10-03T00:00:00Z',
            'updated_at': '2026-10-03T00:00:00Z',
          },
        },
      ),
      files: [
        YorksV1ProjectSetupFile(
          localId: 'file-1',
          idempotencyKey: 'retained-file-key',
          fileName: 'plan.pdf',
          mimeType: 'application/pdf',
          sizeBytes: 3,
          classification: YorksV1DocumentClassification.operational,
          contentHash: 'retained-hash',
          status: YorksV1ProjectSetupFileStatus.needsReselect,
        ),
      ],
    );

class _NoReviewedDispatch implements YorksV1ProjectReviewedCommandRepository {
  int calls = 0;
  @override
  Future<Map<String, dynamic>> executeReviewedCommand(
    YorksV1ProjectSetupCommand command,
  ) async {
    calls++;
    throw StateError('No command expected during local recovery rotation');
  }
}

/// Unit race/failure fixture only. Browser tests exercise the real Web Locks
/// adapter separately; this fake is not evidence of cross-tab browser safety.
class _AtomicMemoryStore implements ProjectDraftAtomicStorage {
  final Map<String, String> values = {};
  Future<void> _tail = Future<void>.value();
  final List<Completer<void>> barriers = [];
  bool failNextWrite = false;
  int commitCount = 0;
  String? readOverrideOnce;
  bool readMissingOnce = false;
  @override
  bool get supportsAtomicOwnership => true;
  @override
  String? read(String key) {
    if (readMissingOnce) {
      readMissingOnce = false;
      return null;
    }
    final override = readOverrideOnce;
    readOverrideOnce = null;
    return override ?? values[key];
  }

  @override
  Future<T> transaction<T>(
    String lockKey,
    T Function(ProjectDraftAtomicTransaction) work,
  ) async {
    final previous = _tail;
    final finished = Completer<void>();
    _tail = finished.future;
    try {
      await previous;
      final tx = _MemoryTransaction(values);
      final result = work(tx);
      if (tx.writes.isNotEmpty) {
        if (barriers.isNotEmpty) await barriers.removeAt(0).future;
        if (failNextWrite) {
          failNextWrite = false;
          throw const ProjectDraftStorageException('synthetic_failure');
        }
        for (final entry in tx.writes.entries) {
          if (entry.value == null) {
            values.remove(entry.key);
          } else {
            values[entry.key] = entry.value!;
          }
        }
        commitCount++;
      }
      return result;
    } finally {
      finished.complete();
    }
  }
}

class _MemoryTransaction implements ProjectDraftAtomicTransaction {
  _MemoryTransaction(this.values);
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

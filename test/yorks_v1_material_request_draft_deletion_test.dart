import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_ledger/shared/controllers/yorks_v1_material_request_draft_controller.dart';
import 'package:material_ledger/shared/models/analytics_event.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request.dart';
import 'package:material_ledger/shared/repositories/collection_store.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_material_request_draft_store.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_material_request_repository.dart';
import 'package:material_ledger/shared/services/analytics_service.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Store store;
  late _Repository repository;
  late _Analytics analytics;
  late YorksV1MaterialRequestDraftController controller;
  var currentOwner = true;

  setUp(() {
    currentOwner = true;
    store = _Store([_draft(), _draft(id: 'other')]);
    repository = _Repository();
    analytics = _Analytics();
    controller = YorksV1MaterialRequestDraftController(
      ownerAuthUserId: 'owner',
      draftId: 'draft',
      store: store,
      repository: repository,
      analytics: analytics,
      isCurrentOwner: () => currentOwner,
      privateSyncDebounce: Duration.zero,
    );
  });
  tearDown(() => controller.dispose());

  test(
    'confirmed deletion removes only its own draft and reports success once',
    () async {
      await controller.discardLocal(requireServerConfirmation: true);
      expect(store.readAll().map((d) => d.id), ['other']);
      expect(repository.deletes, [0]);
      expect(analytics.events, [
        AnalyticsEvent.materialRequestDraftDeleteAttempted,
        AnalyticsEvent.materialRequestDraftDeleted,
      ]);
      expect(analytics.properties.toString(), isNot(contains('Private title')));
      expect(analytics.properties.toString(), isNot(contains('owner')));
      await controller.setTitle('Cannot revive');
      expect(store.readAll().map((d) => d.id), ['other']);
    },
  );

  for (final error in [
    YorksV1DomainErrorCode.offline,
    YorksV1DomainErrorCode.conflict,
    YorksV1DomainErrorCode.backendUnavailable,
    YorksV1DomainErrorCode.unauthorized,
  ]) {
    test('$error preserves local data and never reports success', () async {
      repository.deleteError = YorksV1DomainException(error);
      await expectLater(
        controller.discardLocal(requireServerConfirmation: true),
        throwsA(isA<YorksV1DomainException>()),
      );
      expect(store.readAll().length, 2);
      expect(
        analytics.events.last,
        AnalyticsEvent.materialRequestDraftDeleteFailed,
      );
      expect(
        analytics.events,
        isNot(contains(AnalyticsEvent.materialRequestDraftDeleted)),
      );
    });
  }

  test(
    'duplicate delete, Save, Submit and edits cannot race a pending delete',
    () async {
      repository.deleteBlock = Completer<void>();
      final deleting = controller.discardLocal(requireServerConfirmation: true);
      await repository.deleteStarted.future;
      await expectLater(
        controller.discardLocal(requireServerConfirmation: true),
        throwsA(isA<YorksV1DomainException>()),
      );
      expect(await controller.saveDraft(), isFalse);
      expect(await controller.saveConnected(), isFalse);
      expect(await controller.submit(), isNull);
      await controller.setTitle('Must not change');
      expect(controller.currentDraft.title, 'Private title');
      expect(repository.deletes.length, 1);
      repository.deleteBlock!.complete();
      await deleting;
      expect(store.readAll().map((d) => d.id), ['other']);
    },
  );

  test(
    'in-flight autosave settles before delete uses its current version',
    () async {
      repository.syncBlock = Completer<void>();
      await controller.setTitle('Changed locally');
      await repository.syncStarted.future;
      final deleting = controller.discardLocal(requireServerConfirmation: true);
      await Future<void>.delayed(Duration.zero);
      expect(repository.deletes, isEmpty);
      repository.syncBlock!.complete();
      await deleting;
      expect(repository.deletes, [1]);
      expect(repository.remote, isNull);
      expect(store.readAll().map((d) => d.id), ['other']);
    },
  );

  test('newer account copy is preserved for review', () async {
    repository.remote = _record(
      _draft().copyWith(updatedAt: DateTime.utc(2027)),
      2,
    );
    await expectLater(
      controller.discardLocal(requireServerConfirmation: true),
      throwsA(
        isA<YorksV1DomainException>().having(
          (e) => e.code,
          'code',
          YorksV1DomainErrorCode.conflict,
        ),
      ),
    );
    expect(repository.deletes, isEmpty);
    expect(store.readAll().length, 2);
  });

  test('owner change during network wait never deletes local data', () async {
    repository.getBlock = Completer<void>();
    final deleting = controller.discardLocal(requireServerConfirmation: true);
    final expectation = expectLater(
      deleting,
      throwsA(isA<YorksV1DomainException>()),
    );
    await repository.getStarted.future;
    currentOwner = false;
    repository.getBlock!.complete();
    await expectation;
    expect(repository.deletes, isEmpty);
    expect(store.readAll().length, 2);
  });

  test(
    'storage failure after server delete remains retryable and honest',
    () async {
      store.failure = StateError('Device full');
      await expectLater(
        controller.discardLocal(requireServerConfirmation: true),
        throwsStateError,
      );
      expect(store.readAll().length, 2);
      expect(
        analytics.events.last,
        AnalyticsEvent.materialRequestDraftDeleteFailed,
      );
      store.failure = null;
      await controller.discardLocal(requireServerConfirmation: true);
      expect(store.readAll().map((d) => d.id), ['other']);
      expect(
        analytics.events
            .where((e) => e == AnalyticsEvent.materialRequestDraftDeleted)
            .length,
        1,
      );
    },
  );

  for (final draft in [
    _draft().copyWith(
      pendingSaveOperationId: 'pending',
      pendingSaveExpectedVersion: 0,
      pendingSaveRevision: 0,
      pendingSavePayloadHash: 'hash',
    ),
    _draft().copyWith(pendingSubmissionApproval: false),
    _draft().copyWith(serverRecordVersion: 1),
  ]) {
    test(
      'saved or unresolved workflow input cannot be deleted: ${draft.toJson()}',
      () async {
        store.items[0] = draft;
        final c = YorksV1MaterialRequestDraftController(
          ownerAuthUserId: 'owner',
          draftId: 'draft',
          store: store,
          repository: repository,
        );
        addTearDown(c.dispose);
        await expectLater(
          c.discardLocal(requireServerConfirmation: true),
          throwsA(isA<YorksV1DomainException>()),
        );
        expect(repository.deletes, isEmpty);
        expect(store.readAll().length, 2);
      },
    );
  }

  test('late hydration cannot replace a newer draft during deletion', () async {
    repository.getBlock = Completer<void>();
    repository.remote = _record(
      _draft().copyWith(updatedAt: DateTime.utc(2027)),
      2,
    );
    final hydration = controller.hydratePrivateDraft();
    await repository.getStarted.future;
    final deleting = controller.discardLocal(requireServerConfirmation: true);
    final expectation = expectLater(
      deleting,
      throwsA(isA<YorksV1DomainException>()),
    );
    repository.getBlock!.complete();
    await hydration;
    await expectation;
    expect(repository.deletes, isEmpty);
    expect(store.readAll().first.title, 'Private title');
  });

  test(
    'one actor store serializes separate editor mutations and preserves unknown data',
    () async {
      SharedPreferences.setMockInitialValues({
        'drafts': jsonEncode([
          {
            ..._draft().toJson(),
            'future_extension': {'keep': true},
          },
          _draft(id: 'other').toJson(),
          {'unreadable': 'quarantined'},
        ]),
      });
      final preferences = await SharedPreferences.getInstance();
      final device = YorksV1MaterialRequestDraftStore(
        preferences: preferences,
        key: 'drafts',
      );
      await Future.wait([
        device.mutate((all) => all.where((d) => d.id != 'other').toList()),
        device.mutate((all) => [...all, _draft(id: 'new')]),
      ]);
      final raw = jsonDecode(preferences.getString('drafts')!) as List;
      expect(raw.where((r) => r['unreadable'] == 'quarantined'), hasLength(1));
      expect(raw.first['future_extension'], {'keep': true});
      expect(device.readAll().map((d) => d.id), ['draft', 'new']);
    },
  );

  test(
    'corrupt whole collection refuses writes and preserves original bytes',
    () async {
      SharedPreferences.setMockInitialValues({'drafts': '{broken'});
      final preferences = await SharedPreferences.getInstance();
      final device = YorksV1MaterialRequestDraftStore(
        preferences: preferences,
        key: 'drafts',
      );
      await expectLater(device.writeAll([_draft()]), throwsFormatException);
      expect(preferences.getString('drafts'), '{broken');
    },
  );

  test('confirmed retirement removes an old device copy on resume', () async {
    repository.getError = const YorksV1DomainException(
      YorksV1DomainErrorCode.invalidTransition,
      serverMessage: 'V1_PRIVATE_DRAFT_DELETED',
    );
    await controller.hydratePrivateDraft();
    expect(store.readAll().map((d) => d.id), ['other']);
    expect(
      controller.state.status,
      YorksV1MaterialRequestDraftSyncStatus.deleted,
    );
    expect(await controller.saveDraft(), isFalse);
    expect(repository.deletes, isEmpty);
  });
  test('retired input stays blocked if device cleanup fails', () async {
    repository.getError = const YorksV1DomainException(
      YorksV1DomainErrorCode.invalidTransition,
      serverMessage: 'V1_PRIVATE_DRAFT_DELETED',
    );
    store.failure = StateError('Device full');
    await controller.hydratePrivateDraft();
    expect(store.readAll().length, 2);
    expect(
      controller.state.status,
      YorksV1MaterialRequestDraftSyncStatus.deleted,
    );
    expect(controller.state.localPersistenceFailed, isTrue);
    expect(await controller.saveDraft(), isFalse);
  });
  test('retry completes cleanup after an earlier server retirement', () async {
    repository.getError = const YorksV1DomainException(
      YorksV1DomainErrorCode.invalidTransition,
      serverMessage: 'V1_PRIVATE_DRAFT_DELETED',
    );
    await controller.discardLocal(requireServerConfirmation: true);
    expect(store.readAll().map((d) => d.id), ['other']);
    expect(analytics.events.last, AnalyticsEvent.materialRequestDraftDeleted);
  });
  for (final response in [
    null,
    {},
    {'deleted': false, 'draft_id': 'draft'},
    {'deleted': true, 'draft_id': 'wrong'},
  ]) {
    test(
      'repository requires a matching server deletion acknowledgment: $response',
      () async {
        final repo = YorksV1SupabaseMaterialRequestRepository(
          featureFlags: const YorksV1FeatureFlags.fromEnvironment(),
          connectivity: _Online(),
          rpcClient: _Rpc(response),
        );
        await expectLater(
          repo.deletePrivateDraft(
            draftId: 'draft',
            expectedSyncVersion: 0,
            idempotencyKey: 'key',
          ),
          throwsA(isA<YorksV1DomainException>()),
        );
      },
    );
  }
}

YorksV1MaterialRequestDraft _draft({String id = 'draft'}) =>
    YorksV1MaterialRequestDraft(
      id: id,
      ownerAuthUserId: 'owner',
      submissionIdempotencyKey: 'submit',
      updatedAt: DateTime.utc(2026),
      title: 'Private title',
    );
YorksV1PrivateMaterialRequestDraftRecord _record(
  YorksV1MaterialRequestDraft d,
  int version,
) => YorksV1PrivateMaterialRequestDraftRecord(
  draftId: d.id,
  syncVersion: version,
  draft: d.copyWith(privateSyncVersion: version),
  clientUpdatedAt: d.updatedAt,
  serverUpdatedAt: d.updatedAt,
);

class _Store implements CollectionStore<YorksV1MaterialRequestDraft> {
  _Store(this.items);
  final List<YorksV1MaterialRequestDraft> items;
  Object? failure;
  @override
  bool get isSeeded => true;
  @override
  List<YorksV1MaterialRequestDraft> readAll() => List.of(items);
  @override
  Future<void> writeAll(List<YorksV1MaterialRequestDraft> next) async {
    if (failure != null) throw failure!;
    items
      ..clear()
      ..addAll(next);
  }
}

class _Repository extends Fake
    implements
        YorksV1MaterialRequestRepository,
        YorksV1MaterialRequestPhase2Repository {
  YorksV1PrivateMaterialRequestDraftRecord? remote;
  Completer<void>? getBlock, deleteBlock, syncBlock;
  final getStarted = Completer<void>();
  final deleteStarted = Completer<void>();
  final syncStarted = Completer<void>();
  Object? deleteError;
  Object? getError;
  final deletes = <int>[];
  @override
  Future<YorksV1PrivateMaterialRequestDraftRecord?> getPrivateDraft({
    required String draftId,
    required String ownerAuthUserId,
    required String submissionIdempotencyKey,
  }) async {
    if (!getStarted.isCompleted) getStarted.complete();
    await getBlock?.future;
    if (getError != null) throw getError!;
    return remote;
  }

  @override
  Future<void> deletePrivateDraft({
    required String draftId,
    required int expectedSyncVersion,
    required String idempotencyKey,
  }) async {
    deletes.add(expectedSyncVersion);
    if (!deleteStarted.isCompleted) deleteStarted.complete();
    await deleteBlock?.future;
    if (deleteError != null) throw deleteError!;
    if (remote != null && remote!.syncVersion != expectedSyncVersion) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.conflict);
    }
    remote = null;
  }

  @override
  Future<YorksV1PrivateMaterialRequestDraftRecord> syncPrivateDraft(
    YorksV1SyncPrivateMaterialRequestDraftInput input,
  ) async {
    if (!syncStarted.isCompleted) syncStarted.complete();
    await syncBlock?.future;
    return remote = _record(input.draft, (remote?.syncVersion ?? 0) + 1);
  }
}

class _Analytics extends NoopAnalyticsService {
  final events = <AnalyticsEvent>[];
  final properties = <AnalyticsProperties>[];
  @override
  void capture(
    AnalyticsEvent event, {
    AnalyticsProperties properties = const {},
  }) {
    events.add(event);
    this.properties.add(properties);
  }
}

class _Online implements ConnectivityService {
  @override
  bool get isOnline => true;
  @override
  Stream<bool> get onChange => const Stream.empty();
}

class _Rpc implements YorksV1MaterialRequestRpcClient {
  _Rpc(this.response);
  final Object? response;
  @override
  Future<Object?> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async => response;
}

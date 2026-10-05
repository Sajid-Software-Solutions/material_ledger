import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_creation_draft.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_setup_operation.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_creation_draft_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_local_creation_draft_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_draft_storage_native.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_draft_store.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_local_creation_draft_repository.dart';

import 'support/yorks_v1_permission_test_support.dart';

const _owner = 'local-owner';
const _backend = 'staging';
const _flags = YorksV1FeatureFlags(
  foundation: true,
  projects: true,
  projectSetup: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('summary is a minimal read of acknowledged foreign-writer data', () {
    final storage = _Storage();
    final draft = _draft().copyWith(
      name: 'Saved setup',
      reference: 'YRA-009',
      currentStage: YorksV1ProjectCreationStage.buildings,
      rawEditorState: {'subcontractorText': 'private unfinished contractor'},
    );
    storage.values[_key()] = _record(draft);
    final original = Map.of(storage.values);
    final state = _read(storage);
    expect(state.status, YorksV1ProjectLocalCreationDraftStatus.saved);
    expect(state.summary!.name, draft.name);
    expect(state.summary!.reference, draft.reference);
    expect(state.summary!.currentStage, draft.currentStage);
    expect(state.summary!.savedAt, draft.updatedAt);
    expect(state.summary!.acknowledgedRevision, 4);
    expect(state.outcomeUncertain, false);
    expect(storage.values, original);
    expect(storage.transactions, 0);
    expect(storage.reads.every((key) => key.startsWith(_key())), true);
  });

  test('no record and navigation-only drafts are omitted without writes', () {
    final storage = _Storage();
    expect(_read(storage).status, YorksV1ProjectLocalCreationDraftStatus.empty);
    storage.values[_key()] = _record(
      _draft().copyWith(
        rawEditorState: {
          'sectionContext': {
            'projectDetails': {'scroll': 1, 'focusedField': 'startDate'},
          },
          'contactsExpanded': true,
          'buildingLocalId': 'presentation-row-id',
          'buildingFrp': false,
          'dateStartText': '',
        },
      ),
    );
    expect(_read(storage).status, YorksV1ProjectLocalCreationDraftStatus.empty);
    expect(storage.transactions, 0);
  });

  for (final raw in [
    {'dateStartText': '12/'},
    {'subcontractorText': 'Unfinished contractor'},
    {'buildingCode': 'Unfinished building'},
    {'buildingFrp': true},
  ]) {
    test('unfinished ${raw.keys.single} remains recoverable', () {
      final storage = _Storage();
      storage.values[_key()] = _record(_draft().copyWith(rawEditorState: raw));
      expect(
        _read(storage).status,
        YorksV1ProjectLocalCreationDraftStatus.saved,
      );
      expect(storage.transactions, 0);
    });
  }

  final invalid = <String, Map<String, dynamic> Function(Map<String, dynamic>)>{
    'unsupported record version': (record) => record..['recordVersion'] = 9,
    'unsupported draft schema': (record) =>
        record..['draft'] = {...record['draft'] as Map, 'schemaVersion': 99},
    'foreign owner': (record) =>
        record
          ..['draft'] = {...record['draft'] as Map, 'ownerAuthUserId': 'other'},
    'foreign backend': (record) => record
      ..['draft'] = {
        ...record['draft'] as Map,
        'backendIdentity': 'production',
      },
    'edit mode': (record) =>
        record..['draft'] = {...record['draft'] as Map, 'mode': 'edit'},
    'unacknowledged revision': (record) =>
        record
          ..['draft'] = {...record['draft'] as Map, 'acknowledgedRevision': 3},
    'writer epoch mismatch': (record) => record..['writerEpoch'] = 9,
    'invalid updated time': (record) =>
        record
          ..['draft'] = {...record['draft'] as Map, 'updatedAt': 'not a date'},
  };
  for (final entry in invalid.entries) {
    test('${entry.key} is preserved without private summary or repair', () {
      final storage = _Storage();
      final record = entry.value(
        jsonDecode(_record(_draft())) as Map<String, dynamic>,
      );
      storage.values[_key()] = jsonEncode(record);
      final original = Map.of(storage.values);
      final state = _read(storage);
      expect(
        state.status,
        YorksV1ProjectLocalCreationDraftStatus.recoveryRequired,
      );
      expect(state.summary, isNull);
      expect(storage.values, original);
      expect(storage.transactions, 0);
    });
  }

  test('corrupt and quarantined bytes stay untouched and discoverable', () {
    final storage = _Storage()..values[_key()] = '{private undecodable bytes';
    expect(
      _read(storage).status,
      YorksV1ProjectLocalCreationDraftStatus.recoveryRequired,
    );
    expect(storage.values[_key()], '{private undecodable bytes');
    storage.values.clear();
    storage.values['${_key()}:quarantine'] = 'private quarantined bytes';
    expect(
      _read(storage).status,
      YorksV1ProjectLocalCreationDraftStatus.recoveryRequired,
    );
    expect(storage.transactions, 0);
  });

  test(
    'matching confirmed core is omitted but a historical pointer cannot hide new work',
    () {
      final storage = _Storage();
      final draft = _draft().copyWith(name: 'Confirmed original');
      storage.values[_key()] = _record(draft);
      _storeOperation(storage, _operation(draft.draftId, confirmed: true));
      expect(
        _read(storage).status,
        YorksV1ProjectLocalCreationDraftStatus.empty,
      );
      final fresh = draft.copyWith(
        draftId: 'different-new-proposal',
        name: 'New input',
      );
      storage.values[_key()] = _record(fresh);
      final state = _read(storage);
      expect(state.status, YorksV1ProjectLocalCreationDraftStatus.saved);
      expect(state.summary!.draftId, fresh.draftId);
      expect(state.summary!.name, 'New input');
      expect(storage.transactions, 0);
    },
  );

  test(
    'retired or cleared confirmed input is omitted without pruning journals',
    () {
      final storage = _Storage();
      final draft = _draft().copyWith(name: 'Committed');
      storage.values[_key()] = _record(draft, retired: true);
      _storeOperation(storage, _operation(draft.draftId, confirmed: true));
      final original = Map.of(storage.values);
      expect(
        _read(storage).status,
        YorksV1ProjectLocalCreationDraftStatus.empty,
      );
      expect(storage.values, original);
      storage.values.remove(_key());
      expect(
        _read(storage).status,
        YorksV1ProjectLocalCreationDraftStatus.empty,
      );
      expect(storage.transactions, 0);
    },
  );

  for (final envelope in ['normal', 'missing', 'retired', 'different']) {
    test('$envelope proposal cannot hide an unresolved original command', () {
      final storage = _Storage();
      final draft = _draft().copyWith(name: 'Original uncertain');
      if (envelope != 'missing') {
        storage.values[_key()] = _record(
          envelope == 'different'
              ? draft.copyWith(
                  draftId: 'fresh-proposal',
                  name: 'New local proposal',
                )
              : draft,
          retired: envelope == 'retired',
        );
      }
      _storeOperation(storage, _operation(draft.draftId));
      final original = Map.of(storage.values);
      final state = _read(storage);
      expect(state.outcomeUncertain, true);
      expect(
        state.status,
        envelope == 'missing' || envelope == 'retired'
            ? YorksV1ProjectLocalCreationDraftStatus.recoveryRequired
            : YorksV1ProjectLocalCreationDraftStatus.saved,
      );
      expect(storage.values, original);
      expect(storage.transactions, 0);
    });
  }

  test(
    'foreign journal pointer and malformed journal never expose command data',
    () {
      final storage = _Storage()
        ..values[_key()] = _record(_draft().copyWith(name: 'Input'));
      storage.values['${_key()}:latest_operation'] = jsonEncode({
        'journal_key': 'foreign:journal:private',
      });
      expect(
        _read(storage).status,
        YorksV1ProjectLocalCreationDraftStatus.recoveryRequired,
      );
      expect(storage.reads.contains('foreign:journal:private'), false);
      storage.values['${_key()}:latest_operation'] = jsonEncode({
        'journal_key': '${_key()}:journal:private',
      });
      storage.values['${_key()}:journal:private'] = '{private invalid command';
      expect(_read(storage).summary, isNull);
      expect(
        storage.values['${_key()}:journal:private'],
        '{private invalid command',
      );
      expect(storage.transactions, 0);
    },
  );

  test(
    'storage failures and unverified legacy input remain explicit without mutation',
    () {
      final storage = _Storage()..failRead = true;
      expect(
        _read(storage).status,
        YorksV1ProjectLocalCreationDraftStatus.unavailable,
      );
      storage.failRead = false;
      final state = YorksV1ProjectLocalCreationDraftRepository(storage).read(
        storageKey: _key(),
        ownerAuthUserId: _owner,
        backendIdentity: _backend,
        legacyRaw: '[{"privateLegacy":true}]',
      );
      expect(
        state.status,
        YorksV1ProjectLocalCreationDraftStatus.recoveryRequired,
      );
      expect(state.summary, isNull);
      expect(storage.transactions, 0);
    },
  );

  test(
    'arbitrary platform read denial reports unavailable, not malformed bytes',
    () {
      final storage = _Storage()
        ..platformReadError = StateError('Synthetic browser SecurityError');
      expect(
        _read(storage).status,
        YorksV1ProjectLocalCreationDraftStatus.unavailable,
      );
      expect(storage.transactions, 0);
    },
  );

  test(
    'invalid legacy preference type cannot escape the readonly provider',
    () async {
      final storage = _Storage();
      final container = await _container(
        storage,
        preferenceValues: {'yorks_v1_project_creation_draft_v1_$_owner': true},
      );
      addTearDown(container.dispose);
      final state = container.read(yorksV1ProjectLocalCreationDraftProvider);
      expect(state.status, YorksV1ProjectLocalCreationDraftStatus.unavailable);
      expect(state.summary, isNull);
      expect(storage.transactions, 0);
    },
  );

  for (final gate in [
    'flag',
    'signed-out',
    'procurement',
    'accountant',
    'denied',
    'loading',
    'stale',
  ]) {
    test('$gate provider gate does not even read local storage', () async {
      final storage = _Storage();
      final container = await _container(
        storage,
        flags: gate == 'flag' ? const YorksV1FeatureFlags() : _flags,
        owner: gate == 'signed-out' ? null : _owner,
        role: gate == 'procurement'
            ? YorksV1Role.procurement
            : gate == 'accountant'
            ? YorksV1Role.accountant
            : YorksV1Role.projectEngineer,
        permission: gate == 'loading'
            ? const YorksV1CurrentPermissionSnapshotState(
                isInitialLoading: true,
              )
            : yorksV1TrustedFeaturePermissionState(
                capabilities: gate == 'denied' ? const [] : nullCapabilities,
                stale: gate == 'stale',
              ),
      );
      addTearDown(container.dispose);
      expect(
        container.read(yorksV1ProjectLocalCreationDraftProvider).status,
        YorksV1ProjectLocalCreationDraftStatus.empty,
      );
      expect(storage.reads, isEmpty);
      expect(storage.transactions, 0);
    });
  }

  test(
    'provider reads exact owner/backend, switches safely and never constructs controller',
    () async {
      final storage = _Storage();
      storage.values[_key()] = _record(
        _draft().copyWith(name: 'Owner staging'),
      );
      var owner = _owner;
      var backend = _backend;
      final container = await _container(
        storage,
        ownerRead: () => owner,
        backendRead: () => backend,
      );
      addTearDown(container.dispose);
      final listener = container.listen(
        yorksV1ProjectLocalCreationDraftProvider,
        (_, _) {},
      );
      addTearDown(listener.close);
      expect(listener.read().summary!.name, 'Owner staging');
      owner = 'different-owner';
      container.invalidate(yorksV1AuthUserIdProvider);
      expect(
        listener.read().status,
        YorksV1ProjectLocalCreationDraftStatus.empty,
      );
      backend = 'production';
      container.invalidate(yorksV1ProjectDraftBackendIdentityProvider);
      expect(
        listener.read().status,
        YorksV1ProjectLocalCreationDraftStatus.empty,
      );
      expect(storage.transactions, 0);
      expect(
        storage.reads.any((key) => key.contains('creation_draft_v1')),
        false,
      );
    },
  );

  test(
    'scoped storage hints refresh cached summary and unsubscribe without writes',
    () async {
      final storage = _Storage();
      final container = await _container(storage);
      addTearDown(container.dispose);
      var rebuilds = 0;
      final listener = container.listen(
        yorksV1ProjectLocalCreationDraftProvider,
        (_, _) => rebuilds++,
      );
      expect(
        listener.read().status,
        YorksV1ProjectLocalCreationDraftStatus.empty,
      );
      final reads = storage.reads.length;
      storage.hints.add({_key(owner: 'other-owner')});
      await _settle(container);
      expect(storage.reads.length, reads);
      storage.values[_key()] = _record(
        _draft().copyWith(name: 'New acknowledged save'),
      );
      storage.hints.add({_key()});
      storage.hints.add({'${_key()}:latest_operation'});
      await _settle(container);
      expect(listener.read().summary!.name, 'New acknowledged save');
      expect(rebuilds, 1);
      storage.values.clear();
      storage.hints.add(const {});
      await _settle(container);
      expect(
        listener.read().status,
        YorksV1ProjectLocalCreationDraftStatus.empty,
      );
      listener.close();
      await container.pump();
      expect(storage.hints.hasListener, false);
      expect(storage.transactions, 0);
    },
  );

  test('native adapter emits only asynchronous changed-key commits', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final storage = SharedPreferencesProjectDraftStorage(preferences);
    final events = <Set<String>>[];
    final sub = storage.changes.listen(events.add);
    addTearDown(sub.cancel);
    await storage.transaction('native', (tx) {
      tx.read('native');
    });
    await storage.transaction('native', (tx) {
      tx.remove('missing');
    });
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);
    await storage.transaction('native', (tx) {
      tx.write('native', 'acknowledged');
      expect(events, isEmpty);
    });
    await Future<void>.delayed(Duration.zero);
    expect(events, [
      {'native'},
    ]);
    await storage.transaction('native', (tx) {
      tx.write('native', 'acknowledged');
    });
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));
    await storage.transaction('native', (tx) {
      tx.remove('native');
    });
    await Future<void>.delayed(Duration.zero);
    expect(events, [
      {'native'},
      {'native'},
    ]);
  });
}

// Explicitly use the same trusted fixture catalogue as feature UI tests.
const nullCapabilities = yorksV1EnforcedFeatureActionCapabilities;

String _key({String owner = _owner, String backend = _backend}) =>
    yorksV1ProjectDraftStorageKey(
      ownerAuthUserId: owner,
      backendIdentity: backend,
      mode: YorksV1ProjectDraftMode.create,
    );

YorksV1ProjectCreationDraft _draft() =>
    YorksV1ProjectCreationDraft.empty(
      ownerAuthUserId: _owner,
      backendIdentity: _backend,
      creationIdempotencyKey: 'retained-proposal-key',
    ).copyWith(
      draftId: 'saved-proposal',
      revision: 4,
      acknowledgedRevision: 4,
      writerEpoch: 7,
      updatedAt: DateTime.utc(2026, 10, 5, 9),
    );

String _record(YorksV1ProjectCreationDraft draft, {bool retired = false}) =>
    jsonEncode({
      'recordVersion': 1,
      'ownerWriterId': 'another-live-tab',
      'writerEpoch': draft.writerEpoch,
      'retired': retired,
      'draft': draft.toJson(),
      'unknownEnvelope': {'preserve': true},
    });

YorksV1ProjectLocalCreationDraftState _read(_Storage storage) =>
    YorksV1ProjectLocalCreationDraftRepository(storage).read(
      storageKey: _key(),
      ownerAuthUserId: _owner,
      backendIdentity: _backend,
    );

YorksV1ProjectSetupOperation _operation(
  String draftId, {
  bool confirmed = false,
}) => YorksV1ProjectSetupOperation(
  backendIdentity: _backend,
  ownerAuthUserId: _owner,
  draftId: draftId,
  mode: YorksV1ProjectSetupMode.create,
  core: YorksV1ProjectSetupCommand(
    kind: YorksV1ProjectSetupCommandKind.create,
    idempotencyKey: 'original-core-key',
    payload: {'name': 'Private original command'},
    status: confirmed
        ? YorksV1ProjectSetupCommandStatus.confirmedSuccess
        : YorksV1ProjectSetupCommandStatus.outcomeUncertain,
    result: confirmed
        ? {
            'project': {
              'id': 'confirmed-project',
              'reference': 'YRA-001',
              'name': 'Confirmed',
              'state': 'draft',
              'record_version': 1,
              'created_at': '2026-10-05T00:00:00Z',
              'updated_at': '2026-10-05T00:00:00Z',
            },
          }
        : null,
  ),
);

void _storeOperation(_Storage storage, YorksV1ProjectSetupOperation operation) {
  final key = '${_key()}:journal:${operation.draftId}';
  storage.values[key] = jsonEncode(operation.toJson());
  storage.values['${_key()}:latest_operation'] = jsonEncode({
    'journal_key': key,
  });
}

Future<ProviderContainer> _container(
  _Storage storage, {
  YorksV1FeatureFlags flags = _flags,
  String? owner = _owner,
  YorksV1Role role = YorksV1Role.projectEngineer,
  YorksV1CurrentPermissionSnapshotState? permission,
  String Function()? ownerRead,
  String Function()? backendRead,
  Map<String, Object> preferenceValues = const {},
}) async {
  SharedPreferences.setMockInitialValues(preferenceValues);
  final preferences = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      yorksV1FeatureFlagsProvider.overrideWithValue(flags),
      yorksV1AuthUserIdProvider.overrideWith((_) => ownerRead?.call() ?? owner),
      yorksV1CurrentRoleProvider.overrideWithValue(role),
      yorksV1CurrentPermissionSnapshotProvider.overrideWith(
        (_) => YorksV1TestPermissionController(
          permission ?? yorksV1TrustedFeaturePermissionState(),
        ),
      ),
      yorksV1ProjectDraftBackendIdentityProvider.overrideWith(
        (_) => backendRead?.call() ?? _backend,
      ),
      yorksV1ProjectDraftAtomicStorageProvider.overrideWithValue(storage),
      yorksV1ProjectSetupCreationDraftProvider.overrideWith(
        (_, _) => throw StateError('Portfolio must not construct a writer'),
      ),
      yorksV1ProjectEditDraftProvider.overrideWith(
        (_, _) =>
            throw StateError('Portfolio must not construct an edit writer'),
      ),
    ],
  );
}

Future<void> _settle(ProviderContainer container) async {
  await Future<void>.delayed(Duration.zero);
  await container.pump();
}

class _Storage
    implements ProjectDraftAtomicStorage, ProjectDraftStorageChanges {
  final values = <String, String>{};
  final reads = <String>[];
  final hints = StreamController<Set<String>>.broadcast();
  var transactions = 0;
  var failRead = false;
  Object? platformReadError;

  @override
  Stream<Set<String>> get changes => hints.stream;
  @override
  bool get supportsAtomicOwnership => true;
  @override
  String? read(String key) {
    reads.add(key);
    if (platformReadError != null) throw platformReadError!;
    if (failRead) throw const ProjectDraftStorageException('read_unavailable');
    return values[key];
  }

  @override
  Future<T> transaction<T>(
    String lockKey,
    T Function(ProjectDraftAtomicTransaction) work,
  ) {
    transactions++;
    throw StateError('Discovery must never transact');
  }
}

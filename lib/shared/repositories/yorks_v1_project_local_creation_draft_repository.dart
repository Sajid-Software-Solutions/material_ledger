import 'dart:convert';

import '../models/yorks_v1_project_creation_draft.dart';
import '../models/yorks_v1_project_local_creation_draft.dart';
import '../models/yorks_v1_project_setup_operation.dart';
import 'yorks_v1_project_draft_store.dart';
import 'yorks_v1_project_creation_draft_catalogue.dart';
import 'yorks_v1_project_setup_journal_store.dart';

/// Read-only discovery of owner/backend-scoped local Create proposals. Reading never
/// claims a writer, creates IDs, repairs receipts, migrates or quarantines data.
class YorksV1ProjectLocalCreationDraftRepository {
  const YorksV1ProjectLocalCreationDraftRepository(this.storage);

  final ProjectDraftAtomicStorage storage;

  YorksV1ProjectLocalCreationDraftState readCatalogue({
    required String storageKey,
    required String ownerAuthUserId,
    required String backendIdentity,
    String? legacyRaw,
  }) {
    final summaries = <YorksV1ProjectLocalCreationDraftSummary>[];
    final recoveryIds = <String>{};
    final legacyRecoveryIds = <String>{};
    var recoveryRequired = false;
    var unavailable = false;
    var uncertain = false;
    var catalogueRecovery = false;
    var legacyPointerRecovery = false;
    void collect(YorksV1ProjectLocalCreationDraftState state, {String? id}) {
      if (state.summary case final summary?) summaries.add(summary);
      recoveryIds.addAll(state.recoveryDraftIds);
      recoveryRequired |= state.recoveryDraftIds.isNotEmpty;
      if (state.status ==
          YorksV1ProjectLocalCreationDraftStatus.recoveryRequired) {
        recoveryRequired = true;
        if (id != null) recoveryIds.add(id);
      }
      unavailable |=
          state.status == YorksV1ProjectLocalCreationDraftStatus.unavailable;
      uncertain |= state.outcomeUncertain;
    }

    final legacy = read(
      storageKey: storageKey,
      ownerAuthUserId: ownerAuthUserId,
      backendIdentity: backendIdentity,
      legacyRaw: legacyRaw,
    );
    collect(legacy);
    try {
      final reader = _ReadOnlyDraftStorage(storage);
      final catalogue = YorksV1ProjectCreationDraftCatalogue(
        scopeKey: storageKey,
        ownerAuthUserId: ownerAuthUserId,
        backendIdentity: backendIdentity,
      );
      bool independentlyResumable(String id) {
        final raw = reader.read(catalogue.recordKey(id));
        if (raw == null) return false;
        try {
          return !_envelope(
            raw,
            ownerAuthUserId: ownerAuthUserId,
            backendIdentity: backendIdentity,
            expectedDraftId: id,
          ).retired;
        } catch (_) {
          // Preserve unsupported/foreign bytes. The verified original intent
          // still has its independent guarded recovery in the original slot.
          return false;
        }
      }

      if (legacy.outcomeUncertain) {
        for (final id in legacy.recoveryDraftIds) {
          if (YorksV1ProjectCreationDraftCatalogue.validDraftId(id) &&
              !independentlyResumable(id)) {
            legacyRecoveryIds.add(id);
          }
        }
      }
      // The original pointer is independent of the root envelope's exact
      // journal. Confirming C must not hide an older unknown A whose complete
      // original command still needs a deliberate status check.
      try {
        final pointerRaw = reader.read('$storageKey:latest_operation');
        if (pointerRaw != null) {
          final pointer = jsonDecode(pointerRaw) as Map;
          final key = pointer['journal_key'];
          final prefix = '$storageKey:journal:';
          if (key is! String ||
              !key.startsWith(prefix) ||
              key.length == prefix.length) {
            throw const FormatException('Local original intent scope mismatch');
          }
          final id = key.substring(prefix.length);
          final operation = _operation(
            storageKey,
            id,
            ownerAuthUserId,
            backendIdentity,
          );
          if (operation == null) {
            throw const FormatException('Missing local original intent');
          }
          if (!operation.coreSucceeded && operation.core.status.unresolved) {
            uncertain = true;
            recoveryRequired = true;
            if (!YorksV1ProjectCreationDraftCatalogue.validDraftId(id)) {
              legacyPointerRecovery = true;
            } else {
              recoveryIds.add(id);
              if (!independentlyResumable(id)) {
                legacyRecoveryIds.add(id);
              }
            }
          }
        }
      } on ProjectDraftStorageException {
        rethrow;
      } catch (_) {
        recoveryRequired = true;
        legacyPointerRecovery = true;
      }
      for (final id in catalogue.ids(reader.read(catalogue.indexKey))) {
        collect(
          read(
            storageKey: catalogue.recordKey(id),
            journalScopeKey: storageKey,
            expectedDraftId: id,
            followLatestOperation: false,
            ownerAuthUserId: ownerAuthUserId,
            backendIdentity: backendIdentity,
          ),
          id: id,
        );
      }
    } on ProjectDraftStorageException {
      unavailable = true;
    } catch (_) {
      recoveryRequired = true;
      catalogueRecovery = true;
    }
    final distinct = <String, YorksV1ProjectLocalCreationDraftSummary>{
      for (final summary in summaries) summary.draftId: summary,
    }.values.toList()..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return YorksV1ProjectLocalCreationDraftState(
      status: unavailable
          ? YorksV1ProjectLocalCreationDraftStatus.unavailable
          : recoveryRequired
          ? YorksV1ProjectLocalCreationDraftStatus.recoveryRequired
          : distinct.isNotEmpty
          ? YorksV1ProjectLocalCreationDraftStatus.saved
          : YorksV1ProjectLocalCreationDraftStatus.empty,
      summary: distinct.isEmpty ? null : distinct.first,
      summaries: List.unmodifiable(distinct),
      recoveryDraftIds: List.unmodifiable(recoveryIds),
      legacyRecoveryDraftIds: List.unmodifiable(legacyRecoveryIds),
      outcomeUncertain: uncertain,
      hasCatalogueRecovery: catalogueRecovery,
      hasLegacyRecovery:
          legacyPointerRecovery ||
          legacy.status ==
                  YorksV1ProjectLocalCreationDraftStatus.recoveryRequired &&
              legacy.recoveryDraftIds.isEmpty,
    );
  }

  YorksV1ProjectLocalCreationDraftState read({
    required String storageKey,
    required String ownerAuthUserId,
    required String backendIdentity,
    String? legacyRaw,
    String? journalScopeKey,
    String? expectedDraftId,
    bool followLatestOperation = true,
  }) {
    try {
      final reader = _ReadOnlyDraftStorage(storage);
      final raw = reader.read(storageKey);
      final journals = journalScopeKey ?? storageKey;
      if (raw == null && expectedDraftId != null) {
        return YorksV1ProjectLocalCreationDraftState(
          status: YorksV1ProjectLocalCreationDraftStatus.recoveryRequired,
          recoveryDraftIds: [expectedDraftId],
        );
      }
      YorksV1ProjectCreationDraft? draft;
      var retired = false;
      if (raw != null) {
        final envelope = _envelope(
          raw,
          ownerAuthUserId: ownerAuthUserId,
          backendIdentity: backendIdentity,
          expectedDraftId: expectedDraftId,
        );
        draft = envelope.draft;
        retired = envelope.retired;
      }

      // An exact current journal has priority, matching setup restoration. A
      // historical confirmed pointer never hides a different active proposal.
      var operation = draft == null
          ? null
          : _operation(
              journals,
              draft.draftId,
              ownerAuthUserId,
              backendIdentity,
            );
      if (operation == null && followLatestOperation) {
        final pointerRaw = reader.read('$journals:latest_operation');
        if (pointerRaw != null) {
          final pointer = jsonDecode(pointerRaw) as Map;
          final key = pointer['journal_key'];
          final prefix = '$journals:journal:';
          if (key is! String ||
              !key.startsWith(prefix) ||
              key.length == prefix.length) {
            throw const FormatException('Local project journal scope mismatch');
          }
          operation = _operation(
            journals,
            key.substring(prefix.length),
            ownerAuthUserId,
            backendIdentity,
          );
          if (operation == null) {
            throw const FormatException(
              'Missing local project recovery record',
            );
          }
        }
      }
      final matchingOperation =
          operation != null && operation.draftId == draft?.draftId;
      if (matchingOperation && operation.coreSucceeded) {
        return const YorksV1ProjectLocalCreationDraftState();
      }
      final uncertain =
          operation != null &&
          !operation.coreSucceeded &&
          operation.core.status.unresolved;
      final pendingIntent =
          operation != null &&
          !operation.coreSucceeded &&
          (matchingOperation || uncertain || operation.filesPending);
      if (draft == null || retired || !_meaningful(draft)) {
        if (pendingIntent ||
            reader.read('$storageKey:quarantine') != null ||
            legacyRaw != null && legacyRaw.isNotEmpty && legacyRaw != '[]') {
          return YorksV1ProjectLocalCreationDraftState(
            status: YorksV1ProjectLocalCreationDraftStatus.recoveryRequired,
            outcomeUncertain: uncertain,
            recoveryDraftIds: pendingIntent ? [operation.draftId] : const [],
          );
        }
        return const YorksV1ProjectLocalCreationDraftState();
      }
      return YorksV1ProjectLocalCreationDraftState(
        status: YorksV1ProjectLocalCreationDraftStatus.saved,
        summary: YorksV1ProjectLocalCreationDraftSummary(
          draftId: draft.draftId,
          reference: draft.reference,
          name: draft.name,
          currentStage: draft.currentStage,
          savedAt: draft.updatedAt,
          acknowledgedRevision: draft.acknowledgedRevision,
          outcomeUncertain: uncertain && matchingOperation,
        ),
        outcomeUncertain: uncertain,
        recoveryDraftIds: uncertain && !matchingOperation
            ? [operation.draftId]
            : const [],
      );
    } on ProjectDraftStorageException {
      return const YorksV1ProjectLocalCreationDraftState(
        status: YorksV1ProjectLocalCreationDraftStatus.unavailable,
      );
    } catch (_) {
      // Unsupported/invalid bytes remain in place for the guarded recovery
      // route. A portfolio projection must not silently omit or reinterpret it.
      return const YorksV1ProjectLocalCreationDraftState(
        status: YorksV1ProjectLocalCreationDraftStatus.recoveryRequired,
      );
    }
  }

  YorksV1ProjectSetupOperation? _operation(
    String key,
    String draftId,
    String owner,
    String backend,
  ) => YorksV1ProjectSetupJournalStore(
    storage: _ReadOnlyDraftStorage(storage),
    journalKey: '$key:journal:$draftId',
    backendIdentity: backend,
    ownerAuthUserId: owner,
    draftId: draftId,
    expectedMode: YorksV1ProjectSetupMode.create,
    atomicOwned: <T>(_) => throw StateError('Read-only local project summary'),
  ).read();

  ({YorksV1ProjectCreationDraft draft, bool retired}) _envelope(
    String raw, {
    required String ownerAuthUserId,
    required String backendIdentity,
    String? expectedDraftId,
  }) {
    final record = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    if (record['recordVersion'] != 1 ||
        record['retired'] is! bool ||
        record['writerEpoch'] is! int ||
        record['ownerWriterId'] != null && record['ownerWriterId'] is! String ||
        record['draft'] is! Map) {
      throw const FormatException('Unsupported local project record');
    }
    final json = Map<String, dynamic>.from(record['draft'] as Map);
    final draft = YorksV1ProjectCreationDraft.fromJson(json);
    if (draft.ownerAuthUserId != ownerAuthUserId ||
        draft.backendIdentity != backendIdentity ||
        draft.mode != YorksV1ProjectDraftMode.create ||
        draft.projectId != null ||
        draft.draftId.isEmpty ||
        expectedDraftId != null && draft.draftId != expectedDraftId ||
        draft.creationIdempotencyKey.isEmpty ||
        draft.revision < 0 ||
        draft.acknowledgedRevision != draft.revision ||
        draft.writerEpoch < 0 ||
        record['writerEpoch'] != draft.writerEpoch ||
        json['updatedAt'] is! String ||
        DateTime.tryParse(json['updatedAt'] as String) == null) {
      throw const FormatException('Local project scope or revision mismatch');
    }
    return (draft: draft, retired: record['retired'] as bool);
  }

  bool _meaningful(YorksV1ProjectCreationDraft draft) {
    final raw = Map<String, dynamic>.from(draft.rawEditorState)
      ..remove('sectionContext')
      ..remove('contactsExpanded')
      ..remove('buildingLocalId');
    return draft.copyWith(rawEditorState: raw).hasRecoverableContent;
  }
}

/// Browser storage denial is an availability failure, not evidence of corrupt
/// recovery bytes. Keep decoding/scope failures separate from unreadable data.
class _ReadOnlyDraftStorage implements ProjectDraftAtomicStorage {
  const _ReadOnlyDraftStorage(this.inner);
  final ProjectDraftAtomicStorage inner;

  @override
  String? read(String key) {
    try {
      return inner.read(key);
    } catch (_) {
      throw const ProjectDraftStorageException('read_unavailable');
    }
  }

  @override
  bool get supportsAtomicOwnership => false;

  @override
  Future<T> transaction<T>(
    String lockKey,
    T Function(ProjectDraftAtomicTransaction) work,
  ) => throw StateError('Read-only local project discovery');
}

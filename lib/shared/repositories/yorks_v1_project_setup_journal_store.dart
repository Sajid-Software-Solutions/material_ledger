import 'dart:convert';

import '../models/yorks_v1_project_setup_operation.dart';
import 'yorks_v1_project_draft_store.dart';

typedef YorksV1ProjectSetupOwnedTransaction =
    Future<T> Function<T>(T Function(ProjectDraftAtomicTransaction tx) work);

/// Journal writes share the proposal's atomic writer fence. The records have
/// separate keys so retiring a proposal never deletes unresolved follow-up.
class YorksV1ProjectSetupJournalStore {
  const YorksV1ProjectSetupJournalStore({
    required this.storage,
    required this.journalKey,
    required this.backendIdentity,
    required this.ownerAuthUserId,
    required this.draftId,
    required this.atomicOwned,
    this.latestOperationKey,
    this.expectedMode,
    this.projectId,
    this.restoreConfirmedFollowUps = true,
    this.updateLatestOperation = true,
    this.preferLatestOperation = false,
  });

  final ProjectDraftAtomicStorage storage;
  final String journalKey;
  final String backendIdentity;
  final String ownerAuthUserId;
  final String draftId;
  final String? latestOperationKey;
  final YorksV1ProjectSetupMode? expectedMode;
  final String? projectId;
  final bool restoreConfirmedFollowUps;
  final bool updateLatestOperation;

  /// Explicit singleton recovery can follow its original unknown intent even
  /// after a different proposal gains an exact acknowledged journal.
  final bool preferLatestOperation;
  final YorksV1ProjectSetupOwnedTransaction atomicOwned;

  YorksV1ProjectSetupOperation? read() => _readFrom(storage.read);

  Future<YorksV1ProjectSetupOperation> change(
    YorksV1ProjectSetupOperation Function(YorksV1ProjectSetupOperation? current)
    transform,
  ) => atomicOwned((tx) {
    final current = _readFrom(tx.read);
    final next = transform(current);
    _verifyScope(next);
    if (current == null && next.draftId != draftId) {
      throw const FormatException('Project operation draft mismatch');
    }
    final key = next.draftId == draftId
        ? journalKey
        : '${journalKey.substring(0, journalKey.lastIndexOf(':journal:'))}:journal:${next.draftId}';
    if (next.coreSucceeded) {
      // Some adapters acknowledge staged writes sequentially. Make the
      // confirmed result discoverable before its exact journal can hide the
      // editable proposal, even if later retirement housekeeping fails.
      retainCompletedOperation(
        tx,
        scopeKey: journalKey.substring(0, journalKey.lastIndexOf(':journal:')),
        operation: next,
      );
    }
    tx.write(key, jsonEncode(next.toJson()));
    if (latestOperationKey != null && updateLatestOperation) {
      tx.write(latestOperationKey!, jsonEncode({'journal_key': key}));
    }
    return next;
  });

  YorksV1ProjectSetupOperation? _readFrom(String? Function(String) read) {
    if (!preferLatestOperation) {
      final current = _decode(read(journalKey), expectedDraftId: draftId);
      if (current != null) return current;
    }
    final pointer = latestOperationKey == null
        ? null
        : read(latestOperationKey!);
    if (preferLatestOperation && pointer == null) {
      final current = _decode(read(journalKey), expectedDraftId: draftId);
      if (current != null) return current;
    }
    if (pointer == null) return null;
    final key = (jsonDecode(pointer) as Map)['journal_key'] as String;
    final prefix = journalKey.substring(0, journalKey.lastIndexOf(':journal:'));
    if (!key.startsWith('$prefix:journal:')) {
      throw const FormatException('Project operation pointer scope mismatch');
    }
    final prior = _decode(
      read(key),
      expectedDraftId: key.substring('$prefix:journal:'.length),
    );
    if (prior == null) {
      throw const FormatException('Project operation recovery record missing');
    }
    // A new editable proposal is independent of a previously committed core.
    // Unknown core outcomes remain guarded by their original intent; known
    // activation/file follow-up is exposed from its authorized project context.
    if (prior.coreSucceeded && !restoreConfirmedFollowUps) return null;
    // A single unresolved follow-up stays discoverable after a proposal is
    // retired/replaced. This does not create a general multi-draft catalogue.
    return prior.hasUnresolvedCommand ||
            prior.filesPending ||
            (!prior.cleanupComplete && prior.coreSucceeded)
        ? prior
        : null;
  }

  static String completedProjectKey(String scopeKey, String projectId) =>
      '$scopeKey:completed_project:$projectId';

  /// Retains a discovery link before acknowledging the confirmed core or
  /// freeing its proposal slot. Each exact journal stays independent, so a
  /// later project/edit cannot hide an older pending file or activation intent
  /// by replacing the latest pointer.
  static void retainCompletedOperation(
    ProjectDraftAtomicTransaction tx, {
    required String scopeKey,
    required YorksV1ProjectSetupOperation operation,
  }) {
    if (!operation.coreSucceeded || operation.project == null) {
      throw const FormatException('Project operation core is not confirmed');
    }
    final key = completedProjectKey(scopeKey, operation.project!.id);
    final raw = tx.read(key);
    final index = raw == null
        ? <String, dynamic>{
            'schema_version': 1,
            'backend': operation.backendIdentity,
            'owner': operation.ownerAuthUserId,
            'project_id': operation.project!.id,
            'journal_keys': <String>[],
          }
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    _verifyCompletedIndex(
      index,
      backendIdentity: operation.backendIdentity,
      ownerAuthUserId: operation.ownerAuthUserId,
      projectId: operation.project!.id,
      scopeKey: scopeKey,
    );
    final keys = (index['journal_keys'] as List).cast<String>();
    final journal = '$scopeKey:journal:${operation.draftId}';
    tx.write(
      key,
      jsonEncode({
        ...index,
        'journal_keys': {...keys, journal}.toList(),
      }),
    );
  }

  /// Includes historical latest-pointer discovery for installed versions that
  /// have not yet retired/indexed their confirmed result. Reading never clears
  /// a pointer, journal, manifest or unsupported record.
  static List<YorksV1ProjectSetupOperation> completedForProject({
    required ProjectDraftAtomicStorage storage,
    required String scopeKey,
    required String backendIdentity,
    required String ownerAuthUserId,
    required String projectId,
    required YorksV1ProjectSetupMode mode,
  }) {
    final indexedKeys = <String>{};
    final raw = storage.read(completedProjectKey(scopeKey, projectId));
    if (raw != null) {
      final index = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      _verifyCompletedIndex(
        index,
        backendIdentity: backendIdentity,
        ownerAuthUserId: ownerAuthUserId,
        projectId: projectId,
        scopeKey: scopeKey,
      );
      indexedKeys.addAll((index['journal_keys'] as List).cast<String>());
    }
    final keys = {...indexedKeys};
    final latestRaw = storage.read('$scopeKey:latest_operation');
    if (latestRaw != null) {
      final latest = (jsonDecode(latestRaw) as Map)['journal_key'] as String;
      _verifyJournalKey(latest, scopeKey);
      keys.add(latest);
    }
    final result = <YorksV1ProjectSetupOperation>[];
    for (final key in keys) {
      final draftId = key.substring('$scopeKey:journal:'.length);
      final store = YorksV1ProjectSetupJournalStore(
        storage: storage,
        journalKey: key,
        backendIdentity: backendIdentity,
        ownerAuthUserId: ownerAuthUserId,
        draftId: draftId,
        expectedMode: mode,
        projectId: mode == YorksV1ProjectSetupMode.edit ? projectId : null,
        atomicOwned: <T>(_) => throw StateError('Read-only recovery discovery'),
      );
      final operation = store.read();
      if (operation == null) {
        throw const FormatException(
          'Project operation recovery record missing',
        );
      }
      if (indexedKeys.contains(key) &&
          (!operation.coreSucceeded || operation.project!.id != projectId)) {
        throw const FormatException(
          'Project operation recovery scope mismatch',
        );
      }
      if (operation.coreSucceeded &&
          operation.project!.id == projectId &&
          (operation.filesPending ||
              operation.hasUnresolvedCommand ||
              !operation.cleanupComplete)) {
        result.add(operation);
      }
    }
    return List.unmodifiable(result);
  }

  static void _verifyCompletedIndex(
    Map<String, dynamic> index, {
    required String backendIdentity,
    required String ownerAuthUserId,
    required String projectId,
    required String scopeKey,
  }) {
    if (index['schema_version'] != 1 ||
        index['backend'] != backendIdentity ||
        index['owner'] != ownerAuthUserId ||
        index['project_id'] != projectId ||
        index['journal_keys'] is! List) {
      throw const FormatException('Project operation recovery index mismatch');
    }
    for (final key in (index['journal_keys'] as List).cast<String>()) {
      _verifyJournalKey(key, scopeKey);
    }
  }

  static void _verifyJournalKey(String key, String scopeKey) {
    if (!key.startsWith('$scopeKey:journal:') ||
        key.length == '$scopeKey:journal:'.length) {
      throw const FormatException('Project operation pointer scope mismatch');
    }
  }

  YorksV1ProjectSetupOperation? _decode(
    String? raw, {
    String? expectedDraftId,
  }) {
    if (raw == null) return null;
    final decoded = YorksV1ProjectSetupOperation.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
    _verifyScope(decoded);
    if (expectedDraftId != null && decoded.draftId != expectedDraftId) {
      throw const FormatException('Project operation draft mismatch');
    }
    return decoded;
  }

  void _verifyScope(YorksV1ProjectSetupOperation operation) {
    if (operation.backendIdentity != backendIdentity ||
        operation.ownerAuthUserId != ownerAuthUserId ||
        (expectedMode != null && operation.mode != expectedMode) ||
        (operation.mode == YorksV1ProjectSetupMode.create &&
            operation.core.kind != YorksV1ProjectSetupCommandKind.create) ||
        (operation.mode == YorksV1ProjectSetupMode.edit &&
            (operation.core.kind != YorksV1ProjectSetupCommandKind.update ||
                (projectId != null &&
                    operation.core.payload['project_id'] != projectId))) ||
        (operation.activation != null &&
            operation.activation!.payload['project_id'] !=
                operation.core.project?.id)) {
      throw const FormatException('Project operation scope mismatch');
    }
  }
}

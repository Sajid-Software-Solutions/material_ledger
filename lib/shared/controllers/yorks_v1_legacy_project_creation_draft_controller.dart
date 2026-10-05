import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/yorks_v1_domain_error.dart';
import '../models/yorks_v1_project_creation_draft.dart';
import '../repositories/collection_store.dart';

/// Local-only recovery controller for the five-stage V1 project creation form.
/// Its persisted record is private input on this device; it never writes a
/// project or membership through the legacy generic collection sync path.
class YorksV1LegacyProjectCreationDraftController
    extends StateNotifier<YorksV1ProjectCreationDraft> {
  YorksV1LegacyProjectCreationDraftController({
    required String ownerAuthUserId,
    required CollectionStore<YorksV1ProjectCreationDraft> store,
    required String Function() idempotencyKeyFactory,
  }) : _ownerAuthUserId = ownerAuthUserId,
       _store = store,
       _idempotencyKeyFactory = idempotencyKeyFactory,
       super(
         _restoreOrEmpty(
           ownerAuthUserId: ownerAuthUserId,
           store: store,
           idempotencyKeyFactory: idempotencyKeyFactory,
         ),
       );

  final String _ownerAuthUserId;
  final CollectionStore<YorksV1ProjectCreationDraft> _store;
  final String Function() _idempotencyKeyFactory;

  static YorksV1ProjectCreationDraft _restoreOrEmpty({
    required String ownerAuthUserId,
    required CollectionStore<YorksV1ProjectCreationDraft> store,
    required String Function() idempotencyKeyFactory,
  }) {
    final stored = store.readAll();
    if (stored.length == 1 &&
        stored.single.ownerAuthUserId == ownerAuthUserId) {
      final draft = stored.single;
      if (draft.creationIdempotencyKey.trim().isNotEmpty) return draft;
      // Preserve recoverable form input from an interrupted pre-command save;
      // only the client idempotency token needs regeneration.
      return draft.copyWith(creationIdempotencyKey: idempotencyKeyFactory());
    }
    return YorksV1ProjectCreationDraft.empty(
      ownerAuthUserId: ownerAuthUserId,
      creationIdempotencyKey: idempotencyKeyFactory(),
    );
  }

  /// Autosave a whole immutable draft snapshot. The creation idempotency key is
  /// preserved so a create retry refers to the same pending command.
  Future<void> save(YorksV1ProjectCreationDraft draft) async {
    if (draft.ownerAuthUserId != _ownerAuthUserId ||
        draft.creationIdempotencyKey.trim().isEmpty) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    final stamped = draft.copyWith(updatedAt: DateTime.now().toUtc());
    state = stamped;
    await _store.writeAll([stamped]);
  }

  Future<void> update(
    YorksV1ProjectCreationDraft Function(YorksV1ProjectCreationDraft current)
    transform,
  ) {
    return save(transform(state));
  }

  Future<void> setStage(YorksV1ProjectCreationStage stage) {
    return update((current) => current.copyWith(currentStage: stage));
  }

  /// Clears local input only after the user explicitly abandons it or the
  /// corresponding connected create command has returned successfully.
  Future<void> discard() async {
    final fresh = YorksV1ProjectCreationDraft.empty(
      ownerAuthUserId: _ownerAuthUserId,
      creationIdempotencyKey: _idempotencyKeyFactory(),
    );
    state = fresh;
    await _store.writeAll(const []);
  }
}

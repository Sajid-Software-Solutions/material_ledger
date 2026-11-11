import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/collection_store.dart';
import '../repositories/storage.dart';
import 'mutation_op.dart';

const _kOutboxKey = 'sync_outbox_v1';

/// The durable, ordered queue of pending mutations. Persisted through the same
/// repository layer as everything else, so it survives app restarts. The UI
/// watches this to show pending / queued / failed counts.
final outboxProvider = StateNotifierProvider<OutboxNotifier, List<MutationOp>>((
  ref,
) {
  return OutboxNotifier(
    ref
        .watch(storageProvider)
        .collection<MutationOp>(
          _kOutboxKey,
          toJson: (o) => o.toJson(),
          fromJson: MutationOp.fromJson,
        ),
  );
});

class OutboxNotifier extends StateNotifier<List<MutationOp>> {
  OutboxNotifier(this._store) : super(_store.readAll());

  final CollectionStore<MutationOp> _store;

  /// Current queue snapshot (public read for the engine).
  List<MutationOp> get ops => state;

  Future<void> _persist() => _store.writeAll(state);

  /// Enqueue, oldest-first.
  ///
  /// Idempotent and loss-free: if an op with the same
  /// [MutationOp.idempotencyKey] is already queued, the two are *coalesced* into
  /// a single entry carrying the newest snapshot (latest [MutationOp.payload] /
  /// kind / label) instead of appending a duplicate. The original queue position
  /// (`createdAt`) and `id` are preserved so ordering and any in-flight Retry
  /// stay stable, while retry/backoff state is reset so the fresh write flushes
  /// promptly. This means rapid repeated writes to the same record (e.g. two
  /// partial dispatches of one request) never create duplicates *and* never
  /// silently drop the later state. Returns true when a new entry was appended,
  /// false when an existing one was updated in place.
  Future<bool> enqueue(MutationOp op) async {
    final idx = state.indexWhere((e) => e.idempotencyKey == op.idempotencyKey);
    if (idx >= 0) {
      final existing = state[idx];
      final merged = existing.copyWith(
        kind: op.kind,
        label: op.label,
        payload: op.payload,
        isTransactional: existing.isTransactional || op.isTransactional,
        status: SyncOpStatus.pending,
        attempts: 0,
        clearNextAttempt: true,
        lastError: '',
      );
      state = [
        for (var i = 0; i < state.length; i++)
          if (i == idx) merged else state[i],
      ];
      await _persist();
      return false;
    }
    state = [...state, op];
    await _persist();
    return true;
  }

  Future<void> update(MutationOp op) async {
    state = [
      for (final e in state)
        if (e.id == op.id) op else e,
    ];
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((e) => e.id != id).toList();
    await _persist();
  }

  /// Pending ops whose backoff window has elapsed, oldest first.
  List<MutationOp> readyOps(DateTime now) =>
      (state.where((e) => e.readyAt(now)).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
}

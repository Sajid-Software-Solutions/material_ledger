import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../services/observability_service.dart';
import 'connectivity_service.dart';
import 'mutation_op.dart';
import 'outbox.dart';
import 'sync_backend.dart';

const _uuid = Uuid();

/// Drains the outbox against a [SyncBackend] with ordered, idempotent,
/// exponentially-backed-off retries. Flushes on enqueue, on reconnect, and on a
/// periodic timer. Never drops a write: transient failures retry indefinitely;
/// permanent failures are dead-lettered (status=failed) and surfaced with Retry.
class SyncEngine {
  SyncEngine({
    required SyncBackend backend,
    required OutboxNotifier outbox,
    required ConnectivityService connectivity,
    DateTime Function()? clock,
    Duration timerInterval = const Duration(seconds: 5),
    ObservabilityService? observability,
  }) : _backend = backend,
       _outbox = outbox,
       _connectivity = connectivity,
       _clock = clock ?? DateTime.now,
       _interval = timerInterval,
       _observability = observability;

  final SyncBackend _backend;
  final OutboxNotifier _outbox;
  final ConnectivityService _connectivity;
  final DateTime Function() _clock;
  final Duration _interval;
  final ObservabilityService? _observability;

  StreamSubscription<bool>? _connSub;
  Timer? _timer;
  bool _flushing = false;

  /// Begin auto-syncing: flush on reconnect, on a heartbeat, and resume any ops
  /// left over from a previous session. Not started in unit tests (they drive
  /// [flush] directly).
  void start() {
    _connSub = _connectivity.onChange.listen((online) {
      if (online) flush();
    });
    _timer = Timer.periodic(_interval, (_) => flush());
    flush();
  }

  void dispose() {
    _connSub?.cancel();
    _timer?.cancel();
  }

  Duration backoffFor(int attempts) =>
      Duration(seconds: min(pow(2, attempts).toInt(), 64));

  /// Enqueue a mutation and try to flush immediately. [idempotencyKey] defaults
  /// to `collection:docId` — document-oriented, so every write to the same
  /// record (create, then dispatch, then receipt, …) coalesces into one queued
  /// op carrying the latest snapshot. A resend can therefore never create a
  /// duplicate document, and a rapid second write never loses the later state.
  Future<void> enqueue({
    required String collection,
    required String docId,
    required String kind,
    required String label,
    required Map<String, dynamic> payload,
    bool transactional = false,
    String? idempotencyKey,
  }) async {
    final op = MutationOp(
      id: 'op-${_uuid.v4().substring(0, 8)}',
      idempotencyKey: idempotencyKey ?? '$collection:$docId',
      collection: collection,
      docId: docId,
      kind: kind,
      label: label,
      payload: payload,
      isTransactional: transactional,
      createdAt: _clock(),
    );
    await _outbox.enqueue(op);
    await flush();
  }

  /// Apply ready ops in order. Re-entrancy- and offline-safe.
  Future<void> flush() async {
    if (_flushing || !_connectivity.isOnline) return;
    _flushing = true;
    try {
      for (final op in _outbox.readyOps(_clock())) {
        if (!_connectivity.isOnline) break; // connection lost mid-flush
        try {
          await _backend.apply(op);
          await _outbox.remove(op.id); // confirmed → leaves the queue
        } on PermanentSyncException catch (e, stack) {
          await _outbox.update(
            op.copyWith(status: SyncOpStatus.failed, lastError: e.message),
          );
          // A dead-lettered write means data isn't reaching the backend — it's
          // caught here so it never hits the global hooks. Surface it explicitly.
          _observability?.recordError(
            e,
            stack,
            reason: 'sync-permanent:${op.collection}/${op.kind}',
          );
        } catch (e) {
          // Transient (TransientSyncException, timeout, anything else): keep the
          // op and back off — it will be retried.
          final attempts = op.attempts + 1;
          await _outbox.update(
            op.copyWith(
              attempts: attempts,
              nextAttemptAt: _clock().add(backoffFor(attempts)),
              lastError: e.toString(),
            ),
          );
        }
      }
    } finally {
      _flushing = false;
    }
  }

  /// Re-queue a dead-lettered op (user tapped Retry). Never loses it.
  Future<void> retry(String id) async {
    MutationOp? op;
    for (final e in _outbox.ops) {
      if (e.id == id) {
        op = e;
        break;
      }
    }
    if (op == null) return;
    await _outbox.update(
      op.copyWith(
        status: SyncOpStatus.pending,
        attempts: 0,
        clearNextAttempt: true,
        lastError: '',
      ),
    );
    await flush();
  }

  /// Re-queue every dead-lettered op (user tapped "Retry all" on the banner).
  Future<void> retryAll() async {
    final failedIds = [
      for (final e in _outbox.ops)
        if (e.status == SyncOpStatus.failed) e.id,
    ];
    for (final id in failedIds) {
      await retry(id);
    }
  }
}

/// The always-on engine (read once at app start so the timer/listener run and
/// pending ops resume). Wires the real backend, outbox and connectivity (DI).
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(
    backend: ref.watch(syncBackendProvider),
    outbox: ref.watch(outboxProvider.notifier),
    connectivity: ref.watch(connectivityProvider),
    observability: ref.watch(observabilityProvider),
  );
  engine.start();
  ref.onDispose(engine.dispose);
  return engine;
});

/// Coarse sync state for the global banner.
enum SyncState { synced, offlineQueued, syncing, error }

final syncStatusProvider = Provider<SyncState>((ref) {
  final ops = ref.watch(outboxProvider);
  final online = ref.watch(isOnlineProvider);
  if (ops.any((o) => o.status == SyncOpStatus.failed)) return SyncState.error;
  final hasPending = ops.any((o) => o.status == SyncOpStatus.pending);
  if (!hasPending) return SyncState.synced;
  return online ? SyncState.syncing : SyncState.offlineQueued;
});

/// Number of operations still waiting to commit.
final pendingSyncCountProvider = Provider<int>(
  (ref) => ref
      .watch(outboxProvider)
      .where((o) => o.status == SyncOpStatus.pending)
      .length,
);

/// Dead-lettered ops needing user attention (Retry).
final failedSyncProvider = Provider<List<MutationOp>>(
  (ref) => ref
      .watch(outboxProvider)
      .where((o) => o.status == SyncOpStatus.failed)
      .toList(),
);

/// Whether a specific record (by client doc id) still has a queued/failed op —
/// drives the per-record "pending sync" indicator.
final recordPendingProvider = Provider.family<bool, String>(
  (ref, docId) => ref.watch(outboxProvider).any((o) => o.docId == docId),
);

/// Per-record sync state for a list-row badge.
enum RecordSyncState { none, pending, failed }

final recordSyncStateProvider = Provider.family<RecordSyncState, String>((
  ref,
  docId,
) {
  var result = RecordSyncState.none;
  for (final o in ref.watch(outboxProvider)) {
    if (o.docId != docId) continue;
    if (o.status == SyncOpStatus.failed) return RecordSyncState.failed;
    result = RecordSyncState.pending;
  }
  return result;
});

/// DI helper so any screen can enqueue a durable, idempotent write the same way
/// it writes the audit log: `await ref.enqueueSync(...)`.
extension AppSyncX on WidgetRef {
  Future<void> enqueueSync({
    required String collection,
    required String docId,
    required String kind,
    required String label,
    required Map<String, dynamic> payload,
    bool transactional = false,
  }) {
    return read(syncEngineProvider).enqueue(
      collection: collection,
      docId: docId,
      kind: kind,
      label: label,
      payload: payload,
      transactional: transactional,
    );
  }
}

/// Same DI helper for provider/notifier code (which holds a [Ref], not a
/// [WidgetRef]). Lets every notifier route its critical writes through the same
/// durable outbox without each one re-reading the engine provider by hand.
extension AppSyncRefX on Ref {
  Future<void> enqueueSync({
    required String collection,
    required String docId,
    required String kind,
    required String label,
    required Map<String, dynamic> payload,
    bool transactional = false,
  }) {
    return read(syncEngineProvider).enqueue(
      collection: collection,
      docId: docId,
      kind: kind,
      label: label,
      payload: payload,
      transactional: transactional,
    );
  }
}

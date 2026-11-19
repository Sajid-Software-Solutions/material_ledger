import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:material_ledger/shared/repositories/storage.dart';
import 'package:material_ledger/shared/services/observability_service.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';
import 'package:material_ledger/shared/sync/mutation_op.dart';
import 'package:material_ledger/shared/sync/outbox.dart';
import 'package:material_ledger/shared/sync/sync_backend.dart';
import 'package:material_ledger/shared/sync/sync_engine.dart';

/// In-memory "server" with fault injection — the test double for [SyncBackend].
class FakeSyncBackend implements SyncBackend {
  final Map<String, Map<String, dynamic>> server = {}; // docId -> payload
  final List<String> appliedOrder = [];
  int applyCount = 0;
  bool offline = false;
  int failTransientTimes = 0;
  final Set<String> permanentDocIds = {};

  @override
  Future<void> apply(MutationOp op) async {
    applyCount++;
    if (permanentDocIds.contains(op.docId)) {
      throw const PermanentSyncException('permission-denied');
    }
    if (offline) throw const TransientSyncException('offline');
    if (failTransientTimes > 0) {
      failTransientTimes--;
      throw const TransientSyncException('flaky network');
    }
    server[op.docId] = op.payload; // idempotent set on a client-generated id
    appliedOrder.add(op.docId);
  }
}

void main() {
  late SharedPreferences prefs;
  late DateTime now;
  late DefaultConnectivity conn;
  late FakeSyncBackend backend;
  late OutboxNotifier outbox;
  late SyncEngine engine;

  OutboxNotifier buildOutbox() => OutboxNotifier(
    LocalStorage(prefs).collection<MutationOp>(
      'sync_outbox_v1',
      toJson: (o) => o.toJson(),
      fromJson: MutationOp.fromJson,
    ),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime(2026, 1, 1, 9);
    conn = DefaultConnectivity(online: true);
    backend = FakeSyncBackend();
    outbox = buildOutbox();
    engine = SyncEngine(
      backend: backend,
      outbox: outbox,
      connectivity: conn,
      clock: () => now,
    );
  });

  Future<void> enqueue(String docId, {bool transactional = false}) async {
    now = now.add(
      const Duration(seconds: 1),
    ); // distinct createdAt for ordering
    await engine.enqueue(
      collection: 'materialRequests',
      docId: docId,
      kind: 'request.create',
      label: 'Material request',
      payload: {'id': docId, 'value': 1},
      transactional: transactional,
    );
  }

  group('Offline → reconnect (in order, zero loss, survives restart)', () {
    test('queues offline, flushes in order on reconnect', () async {
      conn.setOnline(false);
      await enqueue('req-A');
      await enqueue('req-B');
      await enqueue('req-C');

      // Nothing reached the server while offline; all three are queued.
      expect(backend.applyCount, 0);
      expect(backend.server, isEmpty);
      expect(outbox.ops.length, 3);

      // Survives a "restart": a fresh outbox over the same storage still has them.
      final reopened = buildOutbox();
      expect(reopened.ops.length, 3);

      // Reconnect → flush.
      conn.setOnline(true);
      await engine.flush();

      expect(backend.server.keys.toSet(), {'req-A', 'req-B', 'req-C'});
      expect(backend.appliedOrder, ['req-A', 'req-B', 'req-C']); // in order
      expect(outbox.ops, isEmpty); // zero loss, all confirmed & cleared
    });
  });

  group('Duplicate resend (zero duplicates)', () {
    test('same key queued twice → single op, applied once', () async {
      // While still queued (offline), a resend with the same key is deduped.
      conn.setOnline(false);
      await enqueue('req-X');
      now = now.add(const Duration(seconds: 1));
      await engine.enqueue(
        collection: 'materialRequests',
        docId: 'req-X',
        kind: 'request.create',
        label: 'Material request',
        payload: {'id': 'req-X', 'value': 1},
      );
      expect(outbox.ops.length, 1); // second was deduped in the queue

      conn.setOnline(true);
      await engine.flush();
      expect(backend.applyCount, 1);
      expect(backend.server.length, 1);
      expect(outbox.ops, isEmpty);
    });

    test(
      'repeated offline writes to one record coalesce to the latest snapshot',
      () async {
        // Models two partial dispatches of the same request while offline: the
        // second write must NOT be dropped (zero loss) and must NOT create a
        // second op/document (zero duplicates) — the queue holds one op carrying
        // the latest cumulative state.
        conn.setOnline(false);
        now = now.add(const Duration(seconds: 1));
        await engine.enqueue(
          collection: 'materialRequests',
          docId: 'req-D',
          kind: 'request.dispatch',
          label: 'Dispatch',
          payload: {'id': 'req-D', 'dispatched': 5},
        );
        now = now.add(const Duration(seconds: 1));
        await engine.enqueue(
          collection: 'materialRequests',
          docId: 'req-D',
          kind: 'request.dispatch',
          label: 'Dispatch',
          payload: {'id': 'req-D', 'dispatched': 12}, // cumulative latest
        );

        expect(outbox.ops.length, 1); // coalesced, not duplicated
        expect(outbox.ops.first.payload['dispatched'], 12); // latest wins

        conn.setOnline(true);
        await engine.flush();
        expect(backend.applyCount, 1);
        expect(backend.server['req-D']!['dispatched'], 12); // server has latest
        expect(outbox.ops, isEmpty);
      },
    );

    test('a fresh write resets a dead-lettered op and lets it re-sync', () async {
      // First write hits a permanent failure and is dead-lettered.
      backend.permanentDocIds.add('req-E');
      await enqueue('req-E');
      expect(outbox.ops.single.status, SyncOpStatus.failed);

      // Permission fixed AND the user edits the record again: the new write
      // coalesces onto the failed op, flipping it back to pending so it flushes.
      backend.permanentDocIds.remove('req-E');
      now = now.add(const Duration(seconds: 1));
      await engine.enqueue(
        collection: 'materialRequests',
        docId: 'req-E',
        kind: 'request.status',
        label: 'Material request',
        payload: {'id': 'req-E', 'value': 2},
      );
      expect(backend.server.containsKey('req-E'), true);
      expect(outbox.ops, isEmpty); // recovered without an explicit Retry tap
    });

    test('re-applying the same op is idempotent on the server', () async {
      final op = MutationOp(
        id: 'op-1',
        idempotencyKey: 'request.create:req-Y',
        collection: 'materialRequests',
        docId: 'req-Y',
        kind: 'request.create',
        label: 'x',
        payload: {'id': 'req-Y'},
        createdAt: now,
      );
      await backend.apply(op);
      await backend.apply(op); // resend
      expect(backend.server.length, 1); // one document, never duplicated
    });
  });

  group('Mid-write disconnection (retry to success)', () {
    test(
      'transient failure keeps the op and retries until confirmed',
      () async {
        backend.failTransientTimes = 1; // first apply "disconnects" mid-write
        await enqueue('req-M');

        // Failed once, still queued, backed off.
        expect(backend.server, isEmpty);
        expect(outbox.ops.length, 1);
        expect(outbox.ops.first.attempts, 1);
        expect(outbox.ops.first.status, SyncOpStatus.pending);

        // Within the backoff window it is not retried yet.
        await engine.flush();
        expect(backend.server, isEmpty);

        // After the backoff window elapses, it succeeds.
        now = now.add(const Duration(minutes: 5));
        await engine.flush();
        expect(backend.server.containsKey('req-M'), true);
        expect(outbox.ops, isEmpty);
        expect(backend.server.length, 1); // zero duplicates despite the retry
      },
    );
  });

  group('Best-effort notification copies', () {
    test('a refused notification copy is dropped, not parked', () async {
      final events = <String>[];
      engine = SyncEngine(
        backend: backend,
        outbox: outbox,
        connectivity: conn,
        clock: () => now,
        observability: _RecordingObservability(events),
      );
      backend.permanentDocIds.addAll({'notif-1', 'req-N'});
      await engine.enqueue(
        collection: 'notifications',
        docId: 'notif-1',
        kind: 'notification.create',
        label: 'Notification',
        payload: const {'id': 'notif-1'},
      );
      await enqueue('req-N');

      // The notification is gone; the user's own refused work stays visible.
      expect(outbox.ops.map((o) => o.docId), ['req-N']);
      expect(outbox.ops.single.status, SyncOpStatus.failed);
      expect(events, ['sync_best_effort_refused_dropped']);
    });

    test('a transient notification failure still retries', () async {
      backend.failTransientTimes = 1;
      await engine.enqueue(
        collection: 'notifications',
        docId: 'notif-2',
        kind: 'notification.create',
        label: 'Notification',
        payload: const {'id': 'notif-2'},
      );
      expect(outbox.ops.single.status, SyncOpStatus.pending);
      now = now.add(const Duration(minutes: 5));
      await engine.flush();
      expect(backend.server.containsKey('notif-2'), isTrue);
      expect(outbox.ops, isEmpty);
    });

    test('start clears notification copies an older build parked', () async {
      final at = DateTime(2026, 1, 1);
      await outbox.enqueue(
        MutationOp(
          id: 'op-old-notif',
          idempotencyKey: 'notifications:notif-3',
          collection: 'notifications',
          docId: 'notif-3',
          kind: 'notification.read',
          label: 'Notification',
          payload: const {'id': 'notif-3'},
          createdAt: at,
        ),
      );
      await outbox.enqueue(
        MutationOp(
          id: 'op-old-req',
          idempotencyKey: 'materialRequests:req-O',
          collection: 'materialRequests',
          docId: 'req-O',
          kind: 'request.update',
          label: 'Material request',
          payload: const {'id': 'req-O'},
          createdAt: at,
        ),
      );
      for (final op in [...outbox.ops]) {
        await outbox.update(op.copyWith(status: SyncOpStatus.failed));
      }

      engine.start();
      await Future<void>.delayed(Duration.zero);
      engine.dispose();

      expect(outbox.ops.map((o) => o.docId), ['req-O']);
      expect(buildOutbox().ops.map((o) => o.docId), ['req-O']);
    });
  });

  group('Permanent failure (dead-letter + Retry, never dropped)', () {
    test(
      'permission denied is dead-lettered then recoverable via retry',
      () async {
        backend.permanentDocIds.add('req-P');
        await enqueue('req-P');

        // Not applied, not dropped — surfaced as failed for a Retry action.
        expect(backend.server, isEmpty);
        expect(outbox.ops.length, 1);
        expect(outbox.ops.first.status, SyncOpStatus.failed);

        // Permission fixed server-side; user taps Retry.
        backend.permanentDocIds.remove('req-P');
        final id = outbox.ops.first.id;
        await engine.retry(id);

        expect(backend.server.containsKey('req-P'), true);
        expect(outbox.ops, isEmpty); // recovered, zero loss
      },
    );

    test('a refused change can be discarded; a pending one cannot', () async {
      backend.permanentDocIds.add('req-D');
      await enqueue('req-D');
      conn.setOnline(false);
      await enqueue('req-Q'); // stays pending while offline
      final failedId = outbox.ops
          .firstWhere((o) => o.status == SyncOpStatus.failed)
          .id;
      final pendingId = outbox.ops
          .firstWhere((o) => o.status == SyncOpStatus.pending)
          .id;

      expect(await engine.discard(pendingId), isFalse);
      expect(await engine.discard('missing'), isFalse);
      expect(await engine.discard(failedId), isTrue);

      expect(outbox.ops.map((o) => o.docId), ['req-Q']);
      expect(backend.server, isEmpty);
      // Persisted: a fresh read of the queue no longer has the refused change.
      expect(buildOutbox().ops.map((o) => o.docId), ['req-Q']);
    });
  });
}

class _RecordingObservability implements ObservabilityService {
  _RecordingObservability(this.events);

  final List<String> events;

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    String? reason,
  }) async {}

  @override
  void logEvent(String name, {Map<String, Object?> params = const {}}) =>
      events.add(name);
}

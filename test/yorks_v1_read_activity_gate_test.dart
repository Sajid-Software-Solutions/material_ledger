import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/sync/yorks_v1_read_activity_gate.dart';
import 'package:material_ledger/shared/sync/yorks_v1_protected_read_coordinator.dart';

void main() {
  test(
    'invalidations while a register waits for a command share its post-command read',
    () async {
      final gate = YorksV1ReadActivityGate();
      addTearDown(gate.dispose);
      final coordinator = YorksV1ProtectedReadCoordinator<String>(
        beforeRead: gate.waitForIdle,
      );
      final release = gate.begin();
      var reads = 0;
      Future<String> read() async {
        reads++;
        return 'confirmed-current-register';
      }

      final pending = <Future<String>>[
        coordinator.load(key: 'register', read: read),
      ];
      for (var index = 0; index < 20; index++) {
        coordinator.markStale('register');
        pending.add(coordinator.load(key: 'register', read: read));
      }
      expect(reads, 0);
      release();
      expect(
        await Future.wait(pending),
        everyElement('confirmed-current-register'),
      );
      expect(reads, 1);
    },
  );
  test('Realtime burst waits for the command and refreshes once', () async {
    final gate = YorksV1ReadActivityGate();
    addTearDown(gate.dispose);
    final release = gate.begin();
    var reads = 0;
    for (var index = 0; index < 20; index++) {
      gate.whenIdle('register', () => reads++);
    }
    var idle = false;
    unawaited(gate.waitForIdle().then((_) => idle = true));
    await Future<void>.delayed(Duration.zero);
    expect(reads, 0);
    expect(idle, isFalse);

    release();
    release();
    await Future<void>.delayed(Duration.zero);
    expect(idle, isTrue);
    expect(reads, 1);
  });

  test(
    'overlapping commands and an immediate next command retain priority',
    () async {
      final gate = YorksV1ReadActivityGate();
      addTearDown(gate.dispose);
      final first = gate.begin();
      final second = gate.begin();
      var reads = 0;
      gate.whenIdle('register', () => reads++);
      first();
      await Future<void>.delayed(Duration.zero);
      expect(reads, 0);
      second();
      final third = gate.begin();
      await Future<void>.delayed(Duration.zero);
      expect(reads, 0);
      third();
      await Future<void>.delayed(Duration.zero);
      expect(reads, 1);
    },
  );

  test(
    'disposed routes and authority scopes cannot run deferred refreshes',
    () async {
      final gate = YorksV1ReadActivityGate();
      final release = gate.begin();
      var reads = 0;
      gate.whenIdle('disposed-route', () => reads++);
      gate.cancel('disposed-route');
      gate.whenIdle('old-authority', () => reads++);
      final waiting = gate.waitForIdle();
      gate.dispose();
      release();
      await waiting;
      await Future<void>.delayed(Duration.zero);
      expect(reads, 0);
    },
  );
}

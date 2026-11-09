import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/sync/yorks_v1_protected_read_coordinator.dart';

void main() {
  testWidgets('pausing a projection cancels its pending retry timer', (
    tester,
  ) async {
    final coordinator = YorksV1ProtectedReadCoordinator<String>(
      retryDelays: const [Duration(milliseconds: 350)],
    );
    addTearDown(coordinator.dispose);
    var calls = 0;
    final pending = coordinator.load(
      key: 'request-a',
      read: () async {
        calls++;
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.backendUnavailable,
        );
      },
    );
    await tester.pump();
    final cancelled = expectLater(
      pending,
      throwsA(isA<YorksV1ProtectedReadCancelled>()),
    );
    coordinator.pause();
    await tester.pump();
    await cancelled;
    expect(calls, 1);
    coordinator.resume();
    expect(
      await coordinator.load(key: 'request-a', read: () async => 'new'),
      'new',
    );
  });

  test(
    'disposing an authority scope discards a late protected response',
    () async {
      final response = Completer<String>();
      final coordinator = YorksV1ProtectedReadCoordinator<String>();
      final pending = coordinator.load(
        key: 'request-a',
        read: () => response.future,
      );
      final cancelled = expectLater(
        pending,
        throwsA(isA<YorksV1ProtectedReadCancelled>()),
      );
      coordinator.dispose();
      response.complete('old-authority-data');
      await cancelled;
      expect(coordinator.isStale('request-a'), isFalse);
    },
  );

  group('YorksV1ProtectedReadCoordinator', () {
    test(
      'a transient read retries once without turning it into denial',
      () async {
        final delays = <Duration>[];
        final coordinator = YorksV1ProtectedReadCoordinator<String>(
          retryDelays: const [Duration(milliseconds: 350)],
          delay: (delay) async => delays.add(delay),
        );
        var calls = 0;
        final result = await coordinator.load(
          key: 'request-a',
          read: () async {
            if (++calls == 1) {
              throw const YorksV1DomainException(
                YorksV1DomainErrorCode.backendUnavailable,
              );
            }
            return 'server-confirmed';
          },
        );
        expect(result, 'server-confirmed');
        expect(calls, 2);
        expect(delays, [const Duration(milliseconds: 350)]);
      },
    );

    test('an authoritative denial is never retried', () async {
      final coordinator = YorksV1ProtectedReadCoordinator<String>(
        retryDelays: const [Duration(milliseconds: 350)],
        delay: (_) async => fail('Denial must not enter backoff'),
      );
      var calls = 0;
      await expectLater(
        coordinator.load(
          key: 'request-a',
          read: () async {
            calls++;
            throw const YorksV1DomainException(
              YorksV1DomainErrorCode.unauthorized,
            );
          },
        ),
        throwsA(isA<YorksV1DomainException>()),
      );
      expect(calls, 1);
    });

    test(
      'transient fallback remains stale and the next read checks the server',
      () async {
        final coordinator = YorksV1ProtectedReadCoordinator<String>();
        await coordinator.load(key: 'a', read: () async => 'old');
        coordinator.markStale('a');
        final stale = await coordinator.load(
          key: 'a',
          read: () async => throw const YorksV1DomainException(
            YorksV1DomainErrorCode.backendUnavailable,
          ),
        );
        expect(stale, 'old');
        expect(coordinator.isStale('a'), isTrue);
        expect(
          await coordinator.load(key: 'a', read: () async => 'new'),
          'new',
        );
        expect(coordinator.isStale('a'), isFalse);
      },
    );

    test(
      'register can report refresh failure while retaining its own authorized view',
      () async {
        final coordinator = YorksV1ProtectedReadCoordinator<String>(
          allowStaleFallback: false,
        );
        await coordinator.load(key: 'a', read: () async => 'old');
        coordinator.markAllStale();
        await expectLater(
          coordinator.load(
            key: 'a',
            read: () async => throw const YorksV1DomainException(
              YorksV1DomainErrorCode.backendUnavailable,
            ),
          ),
          throwsA(isA<YorksV1DomainException>()),
        );
      },
    );

    test('the same record requested twice in flight uses one read', () async {
      final coordinator = YorksV1ProtectedReadCoordinator<String>();
      final response = Completer<String>();
      var reads = 0;

      Future<String> read() {
        reads++;
        return response.future;
      }

      final first = coordinator.load(key: 'request-a', read: read);
      final second = coordinator.load(key: 'request-a', read: read);
      expect(reads, 1);

      response.complete('request-a');
      expect(await first, 'request-a');
      expect(await second, 'request-a');
      expect(reads, 1);
    });

    test('an in-flight invalidation creates only one trailing read', () async {
      final coordinator = YorksV1ProtectedReadCoordinator<String>();
      final firstResponse = Completer<String>();
      final secondResponse = Completer<String>();
      var reads = 0;

      Future<String> read() {
        reads++;
        return reads == 1 ? firstResponse.future : secondResponse.future;
      }

      final first = coordinator.load(key: 'request-a', read: read);
      coordinator.markStale('request-a');
      final trailing = coordinator.load(key: 'request-a', read: read);
      coordinator.markStale('request-a');
      final sameTrailing = coordinator.load(key: 'request-a', read: read);
      expect(reads, 1);

      firstResponse.complete('old');
      expect(await first, 'old');
      await Future<void>.delayed(Duration.zero);
      expect(reads, 2);
      secondResponse.complete('fresh');
      expect(await trailing, 'fresh');
      expect(await sameTrailing, 'fresh');
      expect(reads, 2);
    });

    test(
      'a delayed old record cannot replace a newer selected record',
      () async {
        final coordinator = YorksV1ProtectedReadCoordinator<String>();
        final oldResponse = Completer<String>();
        final newResponse = Completer<String>();
        var selectedKey = 'request-a';
        String? visible;

        final oldRead = coordinator
            .load(key: 'request-a', read: () => oldResponse.future)
            .then((value) {
              if (selectedKey == 'request-a') visible = value;
            });
        selectedKey = 'request-b';
        final newRead = coordinator
            .load(key: 'request-b', read: () => newResponse.future)
            .then((value) {
              if (selectedKey == 'request-b') visible = value;
            });

        newResponse.complete('new');
        await newRead;
        oldResponse.complete('old');
        await oldRead;

        expect(visible, 'new');
      },
    );

    test('a timeout preserves the last authorized success', () async {
      var now = DateTime(2026, 10, 5);
      final coordinator = YorksV1ProtectedReadCoordinator<String>(
        freshCacheDuration: Duration.zero,
        now: () => now,
      );
      expect(
        await coordinator.load(
          key: 'request-a',
          read: () async => 'authorized-state',
        ),
        'authorized-state',
      );

      now = now.add(const Duration(seconds: 1));
      coordinator.markStale('request-a');
      final result = await coordinator.load(
        key: 'request-a',
        read: () async => throw YorksV1DomainException(
          YorksV1DomainErrorCode.backendUnavailable,
          cause: TimeoutException('read timed out'),
        ),
      );

      expect(result, 'authorized-state');
    });

    for (final failure in YorksV1DomainErrorCode.values.where(
      (code) =>
          code != YorksV1DomainErrorCode.offline &&
          code != YorksV1DomainErrorCode.backendUnavailable,
    )) {
      test('${failure.name} purges earlier authorization evidence', () async {
        final coordinator = YorksV1ProtectedReadCoordinator<String>(
          // Keep every read inside the fresh-navigation window so the test
          // cannot pass merely because the preceding projection expired.
          now: () => DateTime.utc(2026, 10, 6),
        );
        var reads = 0;
        await coordinator.load(
          key: 'request-a',
          read: () async {
            reads++;
            return 'allowed';
          },
        );
        coordinator.markStale('request-a');

        Future<String> deniedRead() async {
          reads++;
          throw YorksV1DomainException(failure);
        }

        final denied = throwsA(
          isA<YorksV1DomainException>().having(
            (error) => error.code,
            'code',
            failure,
          ),
        );
        await expectLater(
          coordinator.load(key: 'request-a', read: deniedRead),
          denied,
        );
        await expectLater(
          coordinator.load(key: 'request-a', read: deniedRead),
          denied,
        );
        expect(reads, 3, reason: 'Rapid navigation must recheck the server');

        await expectLater(
          coordinator.load(
            key: 'request-a',
            read: () async {
              reads++;
              throw YorksV1DomainException(
                YorksV1DomainErrorCode.backendUnavailable,
                cause: TimeoutException('read timed out after denial'),
              );
            },
          ),
          throwsA(
            isA<YorksV1DomainException>().having(
              (error) => error.code,
              'code',
              YorksV1DomainErrorCode.backendUnavailable,
            ),
          ),
        );
        expect(reads, 4, reason: 'A timeout cannot restore pre-denial data');
      });
    }

    test('denial purges only the affected record', () async {
      final coordinator = YorksV1ProtectedReadCoordinator<String>(
        now: () => DateTime.utc(2026, 10, 6),
      );
      await coordinator.load(key: 'request-a', read: () async => 'a');
      await coordinator.load(key: 'request-b', read: () async => 'b');
      coordinator.markStale('request-a');
      await expectLater(
        coordinator.load(
          key: 'request-a',
          read: () async => throw const YorksV1DomainException(
            YorksV1DomainErrorCode.unauthorized,
          ),
        ),
        throwsA(isA<YorksV1DomainException>()),
      );

      var requestBReads = 0;
      expect(
        await coordinator.load(
          key: 'request-b',
          read: () async {
            requestBReads++;
            return 'unexpected refetch';
          },
        ),
        'b',
      );
      expect(requestBReads, 0);
    });

    test('a new authority scope cannot reuse the old cache', () async {
      final oldAuthority = YorksV1ProtectedReadCoordinator<String>();
      await oldAuthority.load(key: 'request-a', read: () async => 'old-role');

      final newAuthority = YorksV1ProtectedReadCoordinator<String>();
      var reads = 0;
      final result = await newAuthority.load(
        key: 'request-a',
        read: () async {
          reads++;
          return 'new-role';
        },
      );

      expect(result, 'new-role');
      expect(reads, 1);
    });

    test('rapid route returns use the short fresh cache', () async {
      var reads = 0;
      final coordinator = YorksV1ProtectedReadCoordinator<String>();
      Future<String> read() async {
        reads++;
        return 'request-a';
      }

      await coordinator.load(key: 'request-a', read: read);
      await coordinator.load(key: 'request-a', read: read);
      await coordinator.load(key: 'request-a', read: read);

      expect(reads, 1);
    });

    test('coordination observations contain no record key', () async {
      final observations = <YorksV1ProtectedReadObservation>[];
      final response = Completer<String>();
      final coordinator = YorksV1ProtectedReadCoordinator<String>(
        onObservation: observations.add,
      );

      final first = coordinator.load(
        key: 'protected-request-id',
        read: () => response.future,
      );
      final second = coordinator.load(
        key: 'protected-request-id',
        read: () => response.future,
        trigger: YorksV1ProtectedReadTrigger.realtime,
      );
      response.complete('confirmed');
      await Future.wait([first, second]);
      await coordinator.load(
        key: 'protected-request-id',
        read: () async => 'unused',
      );

      expect(
        observations.map((item) => item.outcome),
        containsAll(<YorksV1ProtectedReadOutcome>[
          YorksV1ProtectedReadOutcome.coalesced,
          YorksV1ProtectedReadOutcome.freshFetch,
          YorksV1ProtectedReadOutcome.freshCache,
        ]),
      );
      expect(observations.every((item) => item.generation == 1), isTrue);
      expect(
        observations
            .map((item) => '${item.trigger}:${item.cacheState}')
            .join('|'),
        isNot(contains('protected-request-id')),
      );
    });
  });
}

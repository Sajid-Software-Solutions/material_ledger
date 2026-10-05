@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'package:material_ledger/shared/controllers/yorks_v1_project_creation_draft_controller.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_creation_draft.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_draft_storage_web.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_draft_store.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_creation_draft_catalogue.dart';

void main() {
  var sequence = 0;
  final prefix =
      'yorks-setup-browser-test-${DateTime.now().microsecondsSinceEpoch}';
  YorksV1ProjectCreationDraftController writer(String key) =>
      YorksV1ProjectCreationDraftController(
        ownerAuthUserId: 'synthetic-owner',
        backendIdentity: 'synthetic-backend',
        storageKey: key,
        storage: BrowserProjectDraftStorage(),
        idempotencyKeyFactory: () => '$prefix-${++sequence}',
      );

  tearDown(() {
    final storage = web.window.localStorage;
    final keys = <String>[];
    for (var i = 0; i < storage.length; i++) {
      final key = storage.key(i);
      if (key != null && key.startsWith(prefix)) keys.add(key);
    }
    for (final key in keys) {
      storage.removeItem(key);
    }
  });

  test('real Web Locks serialize separate adapter contexts', () async {
    final first = BrowserProjectDraftStorage();
    final second = BrowserProjectDraftStorage();
    expect(first.supportsAtomicOwnership, isTrue);
    final key = '$prefix-counter';
    await Future.wait([
      for (var i = 0; i < 40; i++)
        (i.isEven ? first : second).transaction(key, (tx) {
          final count = int.parse(tx.read(key) ?? '0');
          tx.write(key, '${count + 1}');
        }),
    ]);
    expect(first.read(key), '40');
  });

  test(
    'explicit browser Resume acquires only selected A and fences it while B stays writable',
    () async {
      final root = '$prefix-multiple-create';
      final catalogue = YorksV1ProjectCreationDraftCatalogue(
        scopeKey: root,
        ownerAuthUserId: 'synthetic-owner',
        backendIdentity: 'synthetic-backend',
      );
      YorksV1ProjectCreationDraftController selected(
        String id, {
        bool resume = false,
      }) => YorksV1ProjectCreationDraftController(
        ownerAuthUserId: 'synthetic-owner',
        backendIdentity: 'synthetic-backend',
        storageKey: catalogue.recordKey(id),
        storage: BrowserProjectDraftStorage(),
        idempotencyKeyFactory: () => '$prefix-${++sequence}',
        initialDraftId: id,
        requireExistingRecord: resume,
        catalogue: catalogue,
        journalScopeKey: root,
      );
      final writers = [for (var i = 0; i < 8; i++) selected('proposal-$i')];
      for (final current in writers) {
        addTearDown(current.dispose);
      }
      await Future.wait(writers.map((current) => current.initialized));
      expect(
        catalogue
            .ids(BrowserProjectDraftStorage().read(catalogue.indexKey))
            .toSet(),
        {for (var i = 0; i < 8; i++) 'proposal-$i'},
      );
      await writers[0].save(writers[0].state.copyWith(name: 'Original A'));
      await writers[1].save(writers[1].state.copyWith(name: 'Independent B'));
      final exactB = BrowserProjectDraftStorage().read(writers[1].storageKey);
      final secondA = selected('proposal-0', resume: true);
      addTearDown(secondA.dispose);
      await secondA.initialized;
      expect(
        secondA.state.storageState,
        YorksV1ProjectDraftStorageState.ownedElsewhere,
      );
      expect(
        await secondA.resumeEditing(
          expectedDraftId: 'proposal-0',
          canAcquire: () => true,
        ),
        true,
      );
      expect(secondA.writable, true);
      expect(secondA.state.name, 'Original A');
      await secondA.save(secondA.state.copyWith(name: 'Selected A newest'));
      await expectLater(
        writers[0].save(writers[0].state.copyWith(name: 'Stale A')),
        throwsA(isA<ProjectDraftStorageException>()),
      );
      expect(BrowserProjectDraftStorage().read(writers[1].storageKey), exactB);
      expect(writers[1].writable, true);
      await writers[1].save(
        writers[1].state.copyWith(name: 'B still writable'),
      );
      expect(secondA.state.name, 'Selected A newest');
    },
  );

  test(
    'browser refresh hints are asynchronous and emitted only for changed commits',
    () async {
      final first = BrowserProjectDraftStorage();
      final second = BrowserProjectDraftStorage();
      final key = '$prefix-change-events';
      final events = <Set<String>>[];
      final listener = second.changes.listen(events.add);
      addTearDown(listener.cancel);
      await first.transaction(key, (tx) {
        tx.read(key);
      });
      await first.transaction(key, (tx) {
        tx.remove(key);
      });
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      var deliveredDuringCommit = false;
      await first.transaction(key, (tx) {
        tx.write(key, 'acknowledged');
        deliveredDuringCommit = events.isNotEmpty;
      });
      expect(deliveredDuringCommit, false);
      await Future<void>.delayed(Duration.zero);
      expect(events, [
        {key},
      ]);
      await first.transaction(key, (tx) {
        tx.write(key, 'acknowledged');
      });
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      await first.transaction(key, (tx) {
        tx.remove(key);
      });
      await Future<void>.delayed(Duration.zero);
      expect(events, [
        {key},
        {key},
      ]);
    },
  );

  test(
    'takeover fences a resumed writer through the actual browser adapter',
    () async {
      final key = '$prefix-fencing';
      final first = writer(key);
      final second = writer(key);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await first.verifyOwnership();
      await first.save(first.state.copyWith(name: 'First owner latest'));
      await second.initialized;
      expect(
        second.state.storageState,
        YorksV1ProjectDraftStorageState.ownedElsewhere,
      );
      await second.takeOver();
      expect(second.state.name, 'First owner latest');
      await second.save(second.state.copyWith(name: 'Second owner latest'));
      await expectLater(
        first.save(first.state.copyWith(name: 'Suspended stale text')),
        throwsA(isA<ProjectDraftStorageException>()),
      );
      final record = jsonDecode(web.window.localStorage.getItem(key)!) as Map;
      expect((record['draft'] as Map)['name'], 'Second owner latest');
    },
  );

  test(
    'an independent browser window takeover fences the compiled adapter',
    () async {
      final key = '$prefix-independent-window';
      final primary = writer(key);
      addTearDown(primary.dispose);
      await primary.verifyOwnership();
      await primary.save(primary.state.copyWith(name: 'Primary window'));
      final child = web.window.open('about:blank', '$prefix-independent');
      expect(
        child,
        isNotNull,
        reason: 'Independent-window browser evidence requires popup access',
      );
      addTearDown(() => child!.close());
      final done = Completer<void>();
      final storageHint = Completer<Set<String>>();
      final subscription = BrowserProjectDraftStorage().changes.listen((keys) {
        if (keys.contains(key) && !storageHint.isCompleted) {
          storageHint.complete(keys);
        }
      });
      addTearDown(subscription.cancel);
      final token = '$prefix-child-done';
      final listener = ((web.Event event) {
        final message = event as web.MessageEvent;
        if (message.data != null &&
            message.data.typeofEquals('string') &&
            (message.data as JSString).toDart == token &&
            !done.isCompleted) {
          done.complete();
        }
      }).toJS;
      web.window.addEventListener('message', listener);
      try {
        // A second top-level browsing context uses the real browser primitive.
        // The parent writer remains the compiled Dart production adapter.
        child!.document.write(
          """<!doctype html><script>
        navigator.locks.request(${jsonEncode(key)}, () => {
          const key = ${jsonEncode(key)};
          const record = JSON.parse(localStorage.getItem(key));
          record.ownerWriterId = 'synthetic-independent-window';
          record.writerEpoch += 1;
          record.draft.writerEpoch = record.writerEpoch;
          record.draft.name = 'Independent window newest';
          record.draft.revision += 1;
          record.draft.acknowledgedRevision = record.draft.revision;
          localStorage.setItem(key, JSON.stringify(record));
        }).then(() => opener.postMessage(${jsonEncode(token)}, '*'));
        </script>"""
              .toJS,
        );
        child.document.close();
        await done.future.timeout(const Duration(seconds: 10));
        expect(await storageHint.future.timeout(const Duration(seconds: 10)), {
          key,
        });
        await expectLater(
          primary.save(primary.state.copyWith(name: 'Primary resumed stale')),
          throwsA(isA<ProjectDraftStorageException>()),
        );
        expect(
          primary.state.storageState,
          YorksV1ProjectDraftStorageState.ownedElsewhere,
        );
        final record = jsonDecode(web.window.localStorage.getItem(key)!) as Map;
        expect((record['draft'] as Map)['name'], 'Independent window newest');
      } finally {
        web.window.removeEventListener('message', listener);
      }
    },
  );

  test(
    'browser corruption keeps raw input and creates a separate quarantine',
    () async {
      final key = '$prefix-corrupt';
      web.window.localStorage.setItem(key, '{not json');
      final current = writer(key);
      addTearDown(current.dispose);
      await current.initialized;
      expect(
        current.state.storageState,
        YorksV1ProjectDraftStorageState.recoveryRequired,
      );
      expect(web.window.localStorage.getItem(key), '{not json');
      expect(
        (jsonDecode(web.window.localStorage.getItem('$key:quarantine')!)
            as Map)['raw'],
        '{not json',
      );
    },
  );

  test(
    'failure between retirement writes leaves the active record retired',
    () async {
      final key = '$prefix-partial-retirement';
      final current = writer(key);
      addTearDown(current.dispose);
      await current.verifyOwnership();
      await current.save(current.state.copyWith(name: 'Confirmed core result'));
      // Inject a quota-like exception at the real browser Storage.setItem seam.
      // This exercises partial multi-key failure, not physical device quota size.
      final storageConstructor = globalContext.getProperty<JSObject>(
        'Storage'.toJS,
      );
      final prototype = storageConstructor.getProperty<JSObject>(
        'prototype'.toJS,
      );
      final original = prototype.getProperty<JSFunction>('setItem'.toJS);
      prototype.setProperty(
        'setItem'.toJS,
        ((JSString storageKey, JSString value) {
          if (storageKey.toDart == '$key:retired:${current.state.draftId}') {
            throw const ProjectDraftStorageException('injected_browser_quota');
          }
          original.callAsFunction(web.window.localStorage, storageKey, value);
        }).toJS,
      );
      try {
        await expectLater(
          current.retire(resultProjectId: 'synthetic-result'),
          throwsA(anything),
        );
        final record = jsonDecode(web.window.localStorage.getItem(key)!) as Map;
        expect(record['retired'], isTrue);
        expect(record['resultProjectId'], 'synthetic-result');
        await expectLater(
          current.verifyOwnership(),
          throwsA(isA<ProjectDraftStorageException>()),
        );
      } finally {
        prototype.setProperty('setItem'.toJS, original);
      }
    },
  );
}

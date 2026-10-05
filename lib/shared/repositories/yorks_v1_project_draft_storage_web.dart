import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

import 'yorks_v1_project_draft_store.dart';

ProjectDraftAtomicStorage createProjectDraftAtomicStorage(
  SharedPreferences preferences,
) => BrowserProjectDraftStorage();

/// Web Locks serialize the ownership check and the synchronous localStorage
/// commit across tabs. Persisted fencing epochs protect resumed former writers.
/// Broadcast delivery is not part of correctness. Browsers lacking Web Locks
/// fail closed rather than falling back to a read/check/write race.
class BrowserProjectDraftStorage
    implements ProjectDraftAtomicStorage, ProjectDraftStorageChanges {
  static final JSFunction _storageListener = ((web.StorageEvent event) {
    final key = event.key;
    _changes.add(key == null ? const {} : {key});
  }).toJS;
  static final _changes = StreamController<Set<String>>.broadcast(
    onListen: () => web.window.addEventListener('storage', _storageListener),
    onCancel: () => web.window.removeEventListener('storage', _storageListener),
  );

  @override
  Stream<Set<String>> get changes => _changes.stream;
  @override
  bool get supportsAtomicOwnership =>
      web.window.isSecureContext &&
      web.window.navigator.hasProperty('locks'.toJS).toDart;

  @override
  String? read(String key) => web.window.localStorage.getItem(key);

  @override
  Future<T> transaction<T>(
    String lockKey,
    T Function(ProjectDraftAtomicTransaction transaction) work,
  ) async {
    if (!supportsAtomicOwnership) {
      throw const ProjectDraftStorageException('atomic_ownership_unavailable');
    }
    late T result;
    Object? failure;
    StackTrace? failureStack;
    await web.window.navigator.locks
        .request(
          lockKey,
          ((web.Lock lock) {
            try {
              final tx = _BrowserTransaction();
              result = work(tx);
              tx.commit();
              if (tx.changedKeys.isNotEmpty) {
                _changes.add(Set.unmodifiable(tx.changedKeys));
              }
            } catch (error, stack) {
              failure = error;
              failureStack = stack;
            }
            return null;
          }).toJS,
        )
        .toDart;
    if (failure != null) {
      Error.throwWithStackTrace(failure!, failureStack!);
    }
    return result;
  }
}

class _BrowserTransaction implements ProjectDraftAtomicTransaction {
  final Map<String, String?> _writes = {};
  final Set<String> changedKeys = {};

  @override
  String? read(String key) => _writes.containsKey(key)
      ? _writes[key]
      : web.window.localStorage.getItem(key);

  @override
  void write(String key, String value) => _writes[key] = value;

  @override
  void remove(String key) => _writes[key] = null;

  void commit() {
    for (final entry in _writes.entries) {
      final previous = web.window.localStorage.getItem(entry.key);
      if (entry.value == null) {
        web.window.localStorage.removeItem(entry.key);
      } else {
        web.window.localStorage.setItem(entry.key, entry.value!);
      }
      if (previous != entry.value) changedKeys.add(entry.key);
    }
  }
}

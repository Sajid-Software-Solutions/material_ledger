import 'dart:async';

/// A dedicated recovery boundary. It does not change generic CollectionStore
/// behavior or put local proposals into a server collection.
abstract interface class ProjectDraftAtomicStorage {
  String? read(String key);

  /// The callback contains local reads/writes only. It never awaits a network
  /// operation. Completion acknowledges every staged write or throws.
  Future<T> transaction<T>(
    String lockKey,
    T Function(ProjectDraftAtomicTransaction transaction) work,
  );

  /// True only when the platform coordinates independent browser tabs/processes.
  bool get supportsAtomicOwnership;
}

/// Refresh hints only. An empty set means the storage area was cleared. Readers
/// must re-read and validate their own scope; events never convey draft data or
/// transfer ownership. Implementations emit asynchronously after local commits.
abstract interface class ProjectDraftStorageChanges {
  Stream<Set<String>> get changes;
}

abstract interface class ProjectDraftAtomicTransaction {
  String? read(String key);
  void write(String key, String value);
  void remove(String key);
}

class ProjectDraftStorageException implements Exception {
  const ProjectDraftStorageException(this.reason);
  final String reason;
}

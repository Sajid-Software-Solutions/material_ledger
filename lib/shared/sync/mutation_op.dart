import 'dart:convert';

/// Lifecycle of a queued mutation.
enum SyncOpStatus {
  /// Waiting to be sent (or waiting for its backoff window).
  pending,

  /// Permanently rejected by the server (e.g. permission denied). Surfaced to
  /// the user with a Retry action — never silently dropped.
  failed,
}

/// A durable, idempotent unit of work in the outbox.
///
/// Persisted across restarts. Carries everything needed to (re)apply the write
/// exactly once: a deterministic [idempotencyKey], a client-generated [docId]
/// (so a resend `set`s the same document — never a duplicate), and the target
/// [collection] + [payload]. [isTransactional] ops (stock/balance) must be
/// applied atomically by the backend (a Firestore `runTransaction`).
class MutationOp {
  const MutationOp({
    required this.id,
    required this.idempotencyKey,
    required this.collection,
    required this.docId,
    required this.kind,
    required this.label,
    required this.payload,
    required this.createdAt,
    this.isTransactional = false,
    this.attempts = 0,
    this.nextAttemptAt,
    this.status = SyncOpStatus.pending,
    this.lastError,
  });

  /// Unique id for this queue entry.
  final String id;

  /// Deduplication key — the outbox refuses to enqueue a second op with the same
  /// key, and the backend apply is idempotent on it.
  final String idempotencyKey;

  /// Target collection name (matches the repository collection key).
  final String collection;

  /// Client-generated document id (idempotent writes).
  final String docId;

  /// Semantic operation kind, e.g. `request.create`, `request.dispatch`.
  final String kind;

  /// Short human label for the pending-sync UI, e.g. "Material request".
  final String label;

  /// The document/fields to write.
  final Map<String, dynamic> payload;

  final bool isTransactional;
  final DateTime createdAt;
  final int attempts;

  /// Earliest time this op may be retried (exponential backoff). Null = now.
  final DateTime? nextAttemptAt;

  final SyncOpStatus status;
  final String? lastError;

  bool readyAt(DateTime now) =>
      status == SyncOpStatus.pending &&
      (nextAttemptAt == null || !now.isBefore(nextAttemptAt!));

  MutationOp copyWith({
    String? kind,
    String? label,
    Map<String, dynamic>? payload,
    bool? isTransactional,
    int? attempts,
    DateTime? nextAttemptAt,
    SyncOpStatus? status,
    String? lastError,
    bool clearNextAttempt = false,
  }) => MutationOp(
    id: id,
    idempotencyKey: idempotencyKey,
    collection: collection,
    docId: docId,
    kind: kind ?? this.kind,
    label: label ?? this.label,
    payload: payload ?? this.payload,
    createdAt: createdAt,
    isTransactional: isTransactional ?? this.isTransactional,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: clearNextAttempt
        ? null
        : (nextAttemptAt ?? this.nextAttemptAt),
    status: status ?? this.status,
    lastError: lastError ?? this.lastError,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'idempotencyKey': idempotencyKey,
    'collection': collection,
    'docId': docId,
    'kind': kind,
    'label': label,
    'payload': jsonEncode(payload),
    'createdAt': createdAt.toIso8601String(),
    'isTransactional': isTransactional,
    'attempts': attempts,
    'nextAttemptAt': nextAttemptAt?.toIso8601String(),
    'status': status.name,
    'lastError': lastError,
  };

  factory MutationOp.fromJson(Map<String, dynamic> json) => MutationOp(
    id: json['id'] as String,
    idempotencyKey: json['idempotencyKey'] as String,
    collection: json['collection'] as String,
    docId: json['docId'] as String,
    kind: json['kind'] as String,
    label: json['label'] as String? ?? '',
    payload: jsonDecode(json['payload'] as String) as Map<String, dynamic>,
    createdAt: DateTime.parse(json['createdAt'] as String),
    isTransactional: json['isTransactional'] as bool? ?? false,
    attempts: json['attempts'] as int? ?? 0,
    nextAttemptAt: json['nextAttemptAt'] == null
        ? null
        : DateTime.parse(json['nextAttemptAt'] as String),
    status: SyncOpStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => SyncOpStatus.pending,
    ),
    lastError: json['lastError'] as String?,
  );
}

/// Backend signals which kind of failure occurred so the engine can decide to
/// retry (transient) or dead-letter (permanent).
class TransientSyncException implements Exception {
  const TransientSyncException(this.message);
  final String message;
  @override
  String toString() => 'TransientSyncException: $message';
}

class PermanentSyncException implements Exception {
  const PermanentSyncException(this.message);
  final String message;
  @override
  String toString() => 'PermanentSyncException: $message';
}

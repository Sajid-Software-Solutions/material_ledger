import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/audit_log.dart';
import '../models/user_role.dart';
import '../repositories/collection_store.dart';
import '../repositories/storage.dart';
import 'session_provider.dart';

const _kAuditKey = 'activity_log_v2';
const _uuid = Uuid();

/// The append-only activity log (newest first). Mutating notifiers across every
/// module call `ref.read(auditLogProvider.notifier).log(...)` so the trail
/// captures actor + role + timestamp for each action.
final auditLogProvider =
    StateNotifierProvider<AuditLogNotifier, List<AuditEntry>>((ref) {
      return AuditLogNotifier(
        ref
            .watch(storageProvider)
            .collection<AuditEntry>(
              _kAuditKey,
              toJson: (e) => e.toJson(),
              fromJson: AuditEntry.fromJson,
            ),
      );
    });

class AuditLogNotifier extends StateNotifier<List<AuditEntry>> {
  AuditLogNotifier(this._store)
    : super(_store.isSeeded ? _store.readAll() : _seed()) {
    if (!_store.isSeeded) _store.writeAll(state);
  }

  final CollectionStore<AuditEntry> _store;

  Future<void> _persist() => _store.writeAll(state);

  /// Append a new entry. The trail is never edited or deleted from the client.
  Future<void> log({
    required String action,
    required String actorName,
    required UserRole actorRole,
    required AuditModule module,
    String? refId,
    String? detail,
  }) async {
    final entry = AuditEntry(
      id: 'log-${_uuid.v4().substring(0, 8)}',
      action: action,
      actorName: actorName,
      actorRole: actorRole,
      module: module,
      timestamp: DateTime.now(),
      refId: refId,
      detail: detail,
    );
    state = [entry, ...state];
    await _persist();
  }

  /// Entries scoped to a single module (for module-specific trails).
  List<AuditEntry> forModule(AuditModule module) =>
      state.where((e) => e.module == module).toList();

  /// A small, realistic history so the trail isn't empty on first launch.
  // No canned demo history — the real trail accrues as the app is used.
  static List<AuditEntry> _seed() => [];
}

/// One-liner audit logging from any screen. Reads the acting role/name from the
/// session and appends an entry — keeps every call site to a single line and
/// stamps actor + role + timestamp consistently. When real auth lands the
/// actor comes from the signed-in user instead of the dev session.
extension AuditLogX on WidgetRef {
  Future<void> logAudit({
    required String action,
    required AuditModule module,
    String? refId,
    String? detail,
  }) {
    return read(auditLogProvider.notifier).log(
      action: action,
      actorName: read(actorNameProvider),
      actorRole: read(currentRoleProvider),
      module: module,
      refId: refId,
      detail: detail,
    );
  }
}

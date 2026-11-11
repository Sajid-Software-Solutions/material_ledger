import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/yorks_v1_procurement_progress.dart';

class YorksV1ProcurementRecovery {
  const YorksV1ProcurementRecovery({
    required this.draft,
    required this.accountRevision,
    required this.generation,
    required this.savedAt,
    this.pendingCommand,
  });
  final YorksV1ProcurementProgressDraft draft;
  final int accountRevision;
  final int generation;
  final DateTime savedAt;
  final YorksV1ProcurementPendingCommand? pendingCommand;
}

class YorksV1ProcurementRecoveryRead {
  const YorksV1ProcurementRecoveryRead({this.recovery, this.isCorrupt = false});
  final YorksV1ProcurementRecovery? recovery;
  final bool isCorrupt;
}

/// Serialized noncommercial device recovery. Invalid/unknown data remains at
/// its original key and prevents replacement until an explicit discard.
class YorksV1ProcurementRecoveryStore {
  YorksV1ProcurementRecoveryStore({
    required SharedPreferences preferences,
    required String backendIdentity,
    required String actorAuthUserId,
    DateTime Function()? now,
  }) : _preferences = preferences,
       _namespace = '$backendIdentity|$actorAuthUserId',
       _now = now ?? DateTime.now {
    if (backendIdentity.trim().isEmpty || actorAuthUserId.trim().isEmpty) {
      throw ArgumentError(
        'Recovery requires a backend and authenticated actor',
      );
    }
  }

  final SharedPreferences _preferences;
  final String _namespace;
  final DateTime Function() _now;
  Future<void> _tail = Future<void>.value();

  String storageKey(YorksV1ProcurementProgressScope scope) =>
      'yorks_v1_procurement_recovery_v1_${sha256.convert(utf8.encode('$_namespace|${scope.requestId}|${scope.editorKind.name}|${scope.arrangementId ?? ''}'))}';

  Future<YorksV1ProcurementRecoveryRead> load(
    YorksV1ProcurementProgressScope scope,
  ) async {
    await _tail;
    return _read(scope);
  }

  YorksV1ProcurementRecoveryRead _read(YorksV1ProcurementProgressScope scope) {
    final raw = _preferences.getString(storageKey(scope));
    if (raw == null) return const YorksV1ProcurementRecoveryRead();
    try {
      final json = jsonDecode(raw);
      if (json is! Map ||
          json['schema_version'] != 1 ||
          json.keys.any(
            (key) => !{
              'schema_version',
              'draft',
              'account_revision',
              'generation',
              'saved_at',
              'pending_command',
            }.contains(key),
          )) {
        throw const FormatException('Unsupported recovery');
      }
      final rawDraft = Map<String, Object?>.from(json['draft'] as Map);
      // Reject, never restore, a foreign/old payload containing commercial data.
      if (rawDraft.containsKey('commercial_inputs')) {
        throw const FormatException('Protected recovery');
      }
      final draft = YorksV1ProcurementProgressDraft.fromJson(rawDraft);
      if (draft.scope != scope ||
          json['account_revision'] is! int ||
          json['generation'] is! int ||
          (json['account_revision'] as int) < 0 ||
          (json['generation'] as int) < 0) {
        throw const FormatException('Wrong recovery scope');
      }
      return YorksV1ProcurementRecoveryRead(
        recovery: YorksV1ProcurementRecovery(
          draft: draft,
          accountRevision: json['account_revision'] as int,
          generation: json['generation'] as int,
          savedAt: DateTime.parse(json['saved_at'] as String).toUtc(),
          pendingCommand: json['pending_command'] == null
              ? null
              : YorksV1ProcurementPendingCommand.fromJson(
                  Map<String, Object?>.from(json['pending_command'] as Map),
                ),
        ),
      );
    } catch (_) {
      return const YorksV1ProcurementRecoveryRead(isCorrupt: true);
    }
  }

  Future<void> save({
    required YorksV1ProcurementProgressDraft draft,
    required int accountRevision,
    required int generation,
    YorksV1ProcurementPendingCommand? pendingCommand,
  }) => _serialize(() async {
    if (_read(draft.scope).isCorrupt) {
      throw const FormatException('Recovery preserved for review');
    }
    final value = jsonEncode({
      'schema_version': 1,
      // Always serialize from the strict model allowlist, never arbitrary maps.
      'draft': draft.toJson(includeCommercial: false),
      'account_revision': accountRevision, 'generation': generation,
      'saved_at': _now().toUtc().toIso8601String(),
      if (pendingCommand != null) 'pending_command': pendingCommand.toJson(),
    });
    if (!await _preferences.setString(storageKey(draft.scope), value)) {
      throw StateError('Recovery write failed');
    }
  });

  Future<void> clear(YorksV1ProcurementProgressScope scope) =>
      _serialize(() async {
        if (!await _preferences.remove(storageKey(scope))) {
          throw StateError('Recovery clear failed');
        }
      });

  Future<void> _serialize(Future<void> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

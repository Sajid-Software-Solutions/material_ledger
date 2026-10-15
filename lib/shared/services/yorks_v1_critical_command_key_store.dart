import 'dart:convert';
import '../models/yorks_v1_domain_error.dart';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Device-persistent idempotency leases for online-only workflow commands.
///
/// Only a SHA-256 payload fingerprint, opaque UUID and recovery flags/counts
/// are stored. Protected
/// commercial values, notes and workflow quantities never enter preferences.
/// A lease is cleared only after the repository returns a confirmed response;
/// timeouts and transport failures therefore retry with the same server key.
class YorksV1CriticalCommandKeyStore {
  YorksV1CriticalCommandKeyStore({
    required SharedPreferences preferences,
    required String actorAuthUserId,
    String Function() uuidFactory = _uuidV4,
    String backendNamespace = 'legacy',
  }) : _preferences = preferences,
       _actorAuthUserId = actorAuthUserId.trim(),
       _uuidFactory = uuidFactory,
       _backendNamespace = backendNamespace;

  static const _prefix = 'yorks_v1_critical_command_key_v1';

  final SharedPreferences _preferences;
  final String _actorAuthUserId;
  final String Function() _uuidFactory;
  final String _backendNamespace;
  final Set<String> _acknowledged = {};
  final Set<String> _knownNotSent = {};
  bool _persistenceUnverified = false;

  Future<void> _verifyPersistence() async {
    if (!_persistenceUnverified) return;
    try {
      await _preferences.reload();
      _persistenceUnverified = false;
    } catch (_) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
  }

  Future<void> _persist(String key, String value) async {
    try {
      if (!await _preferences.setString(key, value)) {
        throw StateError('command_lease_not_persisted');
      }
    } catch (error) {
      // SharedPreferences changes its cache before the platform write. Restore
      // durable state so another click cannot trust a failed cached marker.
      _persistenceUnverified = true;
      try {
        await _verifyPersistence();
      } catch (_) {
        /* Further sends stay blocked until persistent state can be read. */
      }
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
        cause: error,
      );
    }
  }

  Future<String> acquire({
    required String operation,
    required String entityId,
    required Map<String, Object?> payload,
    bool preservePending = false,
    bool trackSendState = false,
  }) async {
    await _verifyPersistence();
    final storageKey = _storageKey(operation, entityId);
    final fingerprint = sha256
        .convert(utf8.encode(jsonEncode(payload)))
        .toString();
    var existing = _decode(_preferences.getString(storageKey));
    if (existing == null && _backendNamespace != 'legacy') {
      // Adopt the older actor-scoped opaque lease once; never mint a new key
      // solely because the client upgraded its storage namespace.
      final oldKey = _legacyStorageKey(operation, entityId);
      final raw = _preferences.getString(oldKey);
      final legacy = _decode(raw);
      if (legacy != null) {
        await _persist(storageKey, raw!);
        existing = legacy;
        try {
          await _preferences.remove(oldKey);
        } catch (_) {
          /* Confirmation also retires the legacy lease. */
        }
      }
    }
    if (existing != null && existing.fingerprint == fingerprint) {
      return existing.idempotencyKey;
    }
    if (preservePending &&
        existing != null &&
        existing.dispatched != false &&
        !_acknowledged.contains(existing.idempotencyKey)) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.conflict);
    }
    final idempotencyKey = _uuidFactory();
    await _persist(
      storageKey,
      jsonEncode({
        'fingerprint': fingerprint,
        'idempotency_key': idempotencyKey,
        if (trackSendState) 'dispatched': false,
      }),
    );
    return idempotencyKey;
  }

  String? pendingKey(String operation, String entityId) => _decode(
    _preferences.getString(_storageKey(operation, entityId)),
  )?.idempotencyKey;

  bool hasPendingDispatch(String operation, String entityId) {
    final pending = _decode(
      _preferences.getString(_storageKey(operation, entityId)),
    );
    return pending != null &&
        pending.dispatched != false &&
        !_knownNotSent.contains(pending.idempotencyKey) &&
        !_acknowledged.contains(pending.idempotencyKey);
  }

  /// New generic commands persist a send marker. Prepared Procurement commands
  /// own a separate recovery surface and intentionally do not create this flag.
  bool hasTrackedPendingDispatch(String operation, String entityId) {
    final pending = _decode(
      _preferences.getString(_storageKey(operation, entityId)),
    );
    return pending?.dispatched == true &&
        !_knownNotSent.contains(pending!.idempotencyKey) &&
        !_acknowledged.contains(pending.idempotencyKey);
  }

  Future<bool> wasDispatched(
    String operation,
    String entityId,
    String key,
  ) async {
    await _verifyPersistence();
    if (_knownNotSent.contains(key)) return false;
    final raw = _preferences.getString(_storageKey(operation, entityId));
    if (raw == null) return false;
    final value = jsonDecode(raw);
    return value is Map &&
        value['idempotency_key'] == key &&
        value['dispatched'] != false;
  }

  /// A durable budget on the existing opaque lease; remounting cannot restart
  /// automatic reads. Explicit status checks do not consume this budget.
  Future<bool> claimAutomaticCheck(
    String operation,
    String entityId,
    String key, {
    int limit = 3,
  }) async {
    await _verifyPersistence();
    await _preferences.reload();
    final storageKey = _storageKey(operation, entityId);
    final raw = _preferences.getString(storageKey);
    if (raw == null) return false;
    final value = jsonDecode(raw);
    if (value is! Map || value['idempotency_key'] != key) return false;
    final count = value['automatic_check_count'] is int
        ? value['automatic_check_count'] as int
        : 0;
    if (count >= limit) return false;
    await _persist(
      storageKey,
      jsonEncode({...value, 'automatic_check_count': count + 1}),
    );
    return true;
  }

  Future<void> markDispatched(
    String operation,
    String entityId,
    String key,
  ) async {
    await _verifyPersistence();
    final storageKey = _storageKey(operation, entityId);
    final raw = _preferences.getString(storageKey);
    if (raw == null) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.conflict);
    }
    final value = jsonDecode(raw);
    if (value is! Map || value['idempotency_key'] != key) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.conflict);
    }
    try {
      await _persist(storageKey, jsonEncode({...value, 'dispatched': true}));
      _knownNotSent.remove(key);
    } catch (_) {
      _knownNotSent.add(key); // The final RPC has not started.
      _acknowledged.add(key);
      rethrow;
    }
  }

  /// Only repository preflight can establish this state; an unknown transport
  /// result must never call this method. Keep the existing key for safe retry.
  Future<void> markNotSent(
    String operation,
    String entityId,
    String key,
  ) async {
    _knownNotSent.add(key);
    _acknowledged.add(key);
    final storageKey = _storageKey(operation, entityId);
    final raw = _preferences.getString(storageKey);
    if (raw == null) return;
    final value = jsonDecode(raw);
    if (value is Map && value['idempotency_key'] == key) {
      await _persist(storageKey, jsonEncode({...value, 'dispatched': false}));
    }
  }

  Future<void> confirm({
    required String operation,
    required String entityId,
    required String idempotencyKey,
  }) async {
    _acknowledged.add(idempotencyKey);
    final storageKey = _storageKey(operation, entityId);
    final existing = _decode(_preferences.getString(storageKey));
    if (existing?.idempotencyKey == idempotencyKey) {
      await _preferences.remove(storageKey);
    }
    if (_backendNamespace != 'legacy') {
      final legacyKey = _legacyStorageKey(operation, entityId);
      if (_decode(_preferences.getString(legacyKey))?.idempotencyKey ==
          idempotencyKey) {
        await _preferences.remove(legacyKey);
      }
    }
  }

  String _legacyStorageKey(String operation, String entityId) {
    final hash = sha256
        .convert(
          utf8.encode(
            '$_actorAuthUserId:${operation.trim()}:${entityId.trim()}',
          ),
        )
        .toString();
    return '${_prefix}_$hash';
  }

  String _storageKey(String operation, String entityId) {
    if (_backendNamespace == 'legacy') {
      return _legacyStorageKey(operation, entityId);
    }
    final namespace = sha256
        .convert(
          utf8.encode(
            '$_backendNamespace:$_actorAuthUserId:${operation.trim()}:${entityId.trim()}',
          ),
        )
        .toString();
    return '${_prefix}_$namespace';
  }

  static _StoredCommandKey? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final fingerprint = json['fingerprint'];
      final idempotencyKey = json['idempotency_key'];
      if (fingerprint is! String || idempotencyKey is! String) return null;
      return _StoredCommandKey(
        fingerprint: fingerprint,
        idempotencyKey: idempotencyKey,
        dispatched: json['dispatched'] is bool
            ? json['dispatched'] as bool
            : null,
      );
    } on FormatException {
      return null;
    }
  }
}

String _uuidV4() => const Uuid().v4();

class _StoredCommandKey {
  const _StoredCommandKey({
    required this.fingerprint,
    required this.idempotencyKey,
    this.dispatched,
  });

  final String fingerprint;
  final String idempotencyKey;
  final bool? dispatched;
}

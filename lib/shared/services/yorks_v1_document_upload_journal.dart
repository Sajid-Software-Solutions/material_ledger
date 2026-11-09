import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/yorks_v1_document.dart';
import '../models/yorks_v1_domain_error.dart';
import '../repositories/yorks_v1_project_draft_store.dart';

/// Durable metadata for one immutable upload intent. File bytes, Storage paths,
/// commercial metadata and document contents never enter this journal.
class YorksV1DocumentUploadJournal {
  YorksV1DocumentUploadJournal({
    required this.storage,
    required this.backend,
    required this.owner,
  });

  final ProjectDraftAtomicStorage storage;
  final String backend;
  final String owner;
  final Set<String> _confirmedKeys = {};

  String get _key =>
      'yorks_document_uploads_v1_${sha256.convert(utf8.encode(jsonEncode([backend, owner])))}';

  Map<String, dynamic> _read(String? raw) {
    if (raw == null) {
      return {'schema': 1, 'backend': backend, 'owner': owner, 'intents': {}};
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded['schema'] != 1 ||
        decoded['backend'] != backend ||
        decoded['owner'] != owner ||
        decoded['intents'] is! Map) {
      throw const FormatException('Upload journal unavailable');
    }
    // Unknown root/record fields remain intact on every acknowledged mutation.
    return Map<String, dynamic>.from(decoded);
  }

  String _slot(YorksV1DocumentUploadInput input, String operation) => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            operation,
            input.projectId,
            input.entityType.wireValue,
            input.entityId,
            input.documentId,
            input.fileName,
          ]),
        ),
      )
      .toString();

  Future<String> acquire({
    required YorksV1DocumentUploadInput input,
    required String operation,
    required String contentHash,
    required Map<String, Object?> payload,
  }) async {
    if (owner.trim().isEmpty || backend.trim().isEmpty) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unauthenticated,
      );
    }
    final fingerprint = sha256
        .convert(utf8.encode(jsonEncode(payload)))
        .toString();
    final slot = _slot(input, operation);
    return storage.transaction(_key, (tx) {
      final journal = _read(tx.read(_key));
      final intents = Map<String, dynamic>.from(journal['intents'] as Map);
      final previous = intents[slot];
      if (previous != null) {
        if (previous is! Map ||
            previous['key'] is! String ||
            previous['fingerprint'] is! String) {
          throw const FormatException('Upload intent unavailable');
        }
        if (previous['fingerprint'] != fingerprint ||
            previous['content_hash'] != contentHash) {
          throw const YorksV1DomainException(YorksV1DomainErrorCode.conflict);
        }
        return previous['key'] as String;
      }
      if (intents.length >= 100) {
        throw const YorksV1DomainException(YorksV1DomainErrorCode.conflict);
      }
      intents[slot] = {
        'key': input.idempotencyKey,
        'fingerprint': fingerprint,
        'content_hash': contentHash,
        'operation': operation,
        'project_id': input.projectId,
        'entity_type': input.entityType.wireValue,
        'entity_id': input.entityId,
        'document_id': input.documentId,
        'classification': input.classification.wireValue,
        'file_name': input.fileName,
        'mime_type': input.mimeType,
        'byte_size': input.bytes.length,
      };
      tx.write(_key, jsonEncode({...journal, 'intents': intents}));
      return input.idempotencyKey;
    });
  }

  Future<void> confirm({
    required YorksV1DocumentUploadInput input,
    required String operation,
    required String key,
  }) {
    _confirmedKeys.add(key);
    return storage.transaction(_key, (tx) {
      final journal = _read(tx.read(_key));
      final intents = Map<String, dynamic>.from(journal['intents'] as Map);
      final slot = _slot(input, operation);
      final previous = intents[slot];
      if (previous == null) return;
      if (previous is! Map || previous['key'] != key) {
        throw const YorksV1DomainException(YorksV1DomainErrorCode.conflict);
      }
      intents.remove(slot);
      tx.write(_key, jsonEncode({...journal, 'intents': intents}));
    });
  }

  List<Map<String, dynamic>> pending(String projectId) {
    final journal = _read(storage.read(_key));
    final values = (journal['intents'] as Map).values;
    for (final value in values) {
      if (value is! Map ||
          value['key'] is! String ||
          value['file_name'] is! String ||
          value['mime_type'] is! String ||
          value['content_hash'] is! String ||
          value['byte_size'] is! int ||
          value['project_id'] is! String ||
          value['entity_id'] is! String ||
          YorksV1DocumentClassification.fromWireValue(
                value['classification'],
              ) ==
              null) {
        throw const FormatException('Upload recovery metadata unavailable');
      }
    }
    return [
      for (final value in values)
        if (value is Map &&
            value['project_id'] == projectId &&
            !_confirmedKeys.contains(value['key']))
          Map<String, dynamic>.from(value),
    ];
  }
}

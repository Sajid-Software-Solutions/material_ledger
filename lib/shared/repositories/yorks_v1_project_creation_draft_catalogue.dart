import 'dart:convert';

import '../models/yorks_v1_project_creation_draft.dart';
import 'yorks_v1_project_draft_store.dart';

/// An additive device-only index. Entries contain identifiers, never proposal
/// fields or server authority. The original singleton envelope stays in place.
class YorksV1ProjectCreationDraftCatalogue {
  const YorksV1ProjectCreationDraftCatalogue({
    required this.scopeKey,
    required this.ownerAuthUserId,
    required this.backendIdentity,
  });

  final String scopeKey;
  final String ownerAuthUserId;
  final String backendIdentity;

  String get indexKey => '$scopeKey:catalogue';

  static bool validDraftId(String id) =>
      RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id);

  String recordKey(String draftId) {
    if (!validDraftId(draftId)) {
      throw const FormatException('Invalid local project draft identifier');
    }
    return '$scopeKey:draft:$draftId';
  }

  List<String> ids(String? raw) {
    final index = _decode(raw);
    return List.unmodifiable((index['draft_ids'] as List).cast<String>());
  }

  /// Records are not moved or rewritten merely to give them a selected route.
  /// A matching legacy ID resolves to its original lease and journal scope.
  String resolveRecordKey(String? Function(String) read, String draftId) {
    final keyed = recordKey(draftId);
    if (read(keyed) != null) return keyed;
    final legacyRaw = read(scopeKey);
    if (legacyRaw != null) {
      try {
        final record = jsonDecode(legacyRaw) as Map;
        final draft = YorksV1ProjectCreationDraft.fromJson(
          Map<String, dynamic>.from(record['draft'] as Map),
        );
        if (record['recordVersion'] == 1 &&
            draft.ownerAuthUserId == ownerAuthUserId &&
            draft.backendIdentity == backendIdentity &&
            draft.mode == YorksV1ProjectDraftMode.create &&
            draft.projectId == null &&
            draft.draftId == draftId) {
          return scopeKey;
        }
      } catch (_) {
        // Unsupported original bytes are retained for their recovery boundary;
        // they are never copied into a new proposal or rebound to another ID.
      }
    }
    return keyed;
  }

  void register(ProjectDraftAtomicTransaction tx, String draftId) {
    recordKey(draftId);
    final index = _decode(tx.read(indexKey));
    final ids = (index['draft_ids'] as List).cast<String>();
    if (ids.contains(draftId)) return;
    tx.write(
      indexKey,
      jsonEncode({
        ...index,
        'draft_ids': [...ids, draftId],
      }),
    );
  }

  Map<String, dynamic> _decode(String? raw) {
    if (raw == null) {
      return {
        'schema_version': 1,
        'owner': ownerAuthUserId,
        'backend': backendIdentity,
        'draft_ids': <String>[],
      };
    }
    final index = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    if (index['schema_version'] != 1 ||
        index['owner'] != ownerAuthUserId ||
        index['backend'] != backendIdentity ||
        index['draft_ids'] is! List) {
      throw const FormatException('Local project draft catalogue mismatch');
    }
    final ids = (index['draft_ids'] as List).cast<String>();
    if (ids.any((id) => !validDraftId(id)) ||
        ids.toSet().length != ids.length) {
      throw const FormatException('Invalid local project draft catalogue');
    }
    return index;
  }
}

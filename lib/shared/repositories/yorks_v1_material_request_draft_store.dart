import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/yorks_v1_material_request.dart';
import 'collection_store.dart';

/// One actor-scoped queue for all MR editors sharing this device collection.
/// Unknown fields and unreadable rows survive a mutation of another draft.
class YorksV1MaterialRequestDraftStore
    implements CollectionStore<YorksV1MaterialRequestDraft> {
  YorksV1MaterialRequestDraftStore({
    required this.preferences,
    required this.key,
  });

  final SharedPreferences preferences;
  final String key;
  Future<void> _queue = Future<void>.value();

  List<dynamic> _rawRows() {
    final raw = preferences.getString(key);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException('Invalid MR draft store');
    return decoded;
  }

  YorksV1MaterialRequestDraft? _decode(dynamic row) {
    try {
      final draft = YorksV1MaterialRequestDraft.fromJson(
        Map<String, dynamic>.from(row as Map),
      );
      return draft.id.isEmpty || draft.ownerAuthUserId.isEmpty ? null : draft;
    } catch (_) {
      return null;
    }
  }

  @override
  List<YorksV1MaterialRequestDraft> readAll() {
    try {
      return _rawRows()
          .map(_decode)
          .whereType<YorksV1MaterialRequestDraft>()
          .toList();
    } catch (_) {
      // Keep the original bytes. A write must fail until they can be recovered.
      return [];
    }
  }

  Future<void> mutate(
    List<YorksV1MaterialRequestDraft> Function(
      List<YorksV1MaterialRequestDraft>,
    )
    change,
  ) {
    final operation = _queue.then((_) => _write(change(readAll())));
    _queue = operation.catchError((_) {});
    return operation;
  }

  Future<void> _write(List<YorksV1MaterialRequestDraft> drafts) async {
    final rows = _rawRows(); // Corrupt whole blobs cannot be overwritten.
    final incoming = {
      for (final draft in drafts) (draft.ownerAuthUserId, draft.id): draft,
    };
    final retainedIds = incoming.keys.toSet();
    final result = <dynamic>[];
    for (final row in rows) {
      final decoded = _decode(row);
      if (decoded == null) {
        result.add(row); // Preserve and quarantine; never discard on deletion.
        continue;
      }
      final next = incoming.remove((decoded.ownerAuthUserId, decoded.id));
      if (next != null) {
        result.add({
          ...Map<String, dynamic>.from(row as Map),
          ...next.toJson(),
        });
      } else if (retainedIds.contains((decoded.ownerAuthUserId, decoded.id))) {
        result.add(row); // Preserve a historical duplicate for reconciliation.
      }
    }
    result.addAll(incoming.values.map((draft) => draft.toJson()));
    if (!await preferences.setString(key, jsonEncode(result))) {
      throw StateError('MR draft persistence was not acknowledged');
    }
  }

  @override
  Future<void> writeAll(List<YorksV1MaterialRequestDraft> items) =>
      mutate((_) => items);

  @override
  bool get isSeeded => preferences.containsKey(key);
}

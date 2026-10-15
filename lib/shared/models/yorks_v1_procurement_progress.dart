import 'dart:convert';

import 'package:crypto/crypto.dart';

enum YorksV1ProcurementEditorKind { arrangement, dispatch }

/// A private editor identity. It is not a workflow state or a stock command.
class YorksV1ProcurementProgressScope {
  const YorksV1ProcurementProgressScope({
    required this.requestId,
    required this.editorKind,
    this.arrangementId,
  });

  final String requestId;
  final YorksV1ProcurementEditorKind editorKind;
  final String? arrangementId;

  @override
  bool operator ==(Object other) =>
      other is YorksV1ProcurementProgressScope &&
      requestId == other.requestId &&
      editorKind == other.editorKind &&
      arrangementId == other.arrangementId;

  @override
  int get hashCode => Object.hash(requestId, editorKind, arrangementId);
}

/// Raw text is intentional: incomplete decimals and dates are saveable progress.
/// Only the final business command validates operational completeness.
class YorksV1ProcurementProgressDraft {
  YorksV1ProcurementProgressDraft({
    required this.requestId,
    required this.editorKind,
    this.arrangementId,
    required this.baseRequestVersion,
    this.baseArrangementVersion,
    required Map<String, Object?> inputs,
    Map<String, Object?>? commercialInputs,
  }) : inputs = _freezeMap(inputs),
       commercialInputs = commercialInputs == null
           ? null
           : _freezeMap(commercialInputs) {
    _validateInputs(editorKind, this.inputs);
    if (this.commercialInputs != null) {
      if (editorKind != YorksV1ProcurementEditorKind.arrangement) {
        throw const FormatException('Dispatch has no commercial progress');
      }
      _validateCommercial(this.commercialInputs!);
    }
    if (requestId.isEmpty ||
        baseRequestVersion < 0 ||
        (baseArrangementVersion != null && baseArrangementVersion! < 0)) {
      throw const FormatException('Invalid progress identity');
    }
  }

  static const schemaVersion = 1;
  final String requestId;
  final YorksV1ProcurementEditorKind editorKind;
  final String? arrangementId;
  final int baseRequestVersion;
  final int? baseArrangementVersion;
  final Map<String, Object?> inputs;
  final Map<String, Object?>? commercialInputs;

  YorksV1ProcurementProgressScope get scope => YorksV1ProcurementProgressScope(
    requestId: requestId,
    editorKind: editorKind,
    arrangementId: arrangementId,
  );

  Map<String, Object?> toJson({bool includeCommercial = true}) => {
    'request_id': requestId,
    'editor_kind': editorKind.name,
    'arrangement_id': arrangementId,
    'base_request_version': baseRequestVersion,
    'base_arrangement_version': baseArrangementVersion,
    'schema_version': schemaVersion,
    'inputs': inputs,
    if (includeCommercial && commercialInputs != null)
      'commercial_inputs': commercialInputs,
  };

  factory YorksV1ProcurementProgressDraft.fromJson(Map<String, Object?> json) {
    _onlyKeys(json, {
      'id',
      'request_id',
      'editor_kind',
      'arrangement_id',
      'base_request_version',
      'base_arrangement_version',
      'schema_version',
      'inputs',
      'commercial_inputs',
      'revision',
      'saved_at',
      'pending_command',
      'discarded',
    });
    if (json['schema_version'] != schemaVersion) {
      throw const FormatException('Unsupported progress schema');
    }
    final kind = switch (json['editor_kind']) {
      'arrangement' => YorksV1ProcurementEditorKind.arrangement,
      'dispatch' => YorksV1ProcurementEditorKind.dispatch,
      _ => throw const FormatException('Invalid editor kind'),
    };
    return YorksV1ProcurementProgressDraft(
      requestId: _string(json['request_id']),
      editorKind: kind,
      arrangementId: _nullableString(json['arrangement_id']),
      baseRequestVersion: _integer(json['base_request_version']),
      baseArrangementVersion: json['base_arrangement_version'] == null
          ? null
          : _integer(json['base_arrangement_version']),
      inputs: _map(json['inputs']),
      commercialInputs: json['commercial_inputs'] == null
          ? null
          : _map(json['commercial_inputs']),
    );
  }

  bool hasSameBase(YorksV1ProcurementProgressDraft other) =>
      scope == other.scope &&
      baseRequestVersion == other.baseRequestVersion &&
      baseArrangementVersion == other.baseArrangementVersion;

  String get fingerprint => _fingerprint(toJson());
  String get operationalFingerprint =>
      _fingerprint(toJson(includeCommercial: false));
  String get commercialFingerprint => _fingerprint(commercialInputs);

  YorksV1ProcurementProgressDraft withoutCommercial() =>
      YorksV1ProcurementProgressDraft.fromJson(
        toJson(includeCommercial: false),
      );
}

class YorksV1ProcurementProgressCheckpoint {
  const YorksV1ProcurementProgressCheckpoint({
    required this.draft,
    required this.revision,
    required this.savedAt,
  });
  final YorksV1ProcurementProgressDraft draft;
  final int revision;
  final DateTime savedAt;

  factory YorksV1ProcurementProgressCheckpoint.fromJson(
    Map<String, Object?> json,
  ) {
    final revision = _integer(json['revision']);
    if (revision < 1) {
      throw const FormatException('Invalid checkpoint revision');
    }
    return YorksV1ProcurementProgressCheckpoint(
      draft: YorksV1ProcurementProgressDraft.fromJson(json),
      revision: revision,
      savedAt: DateTime.parse(_string(json['saved_at'])).toUtc(),
    );
  }
}

/// Device recovery holds opaque identifiers and bounded retry metadata only.
class YorksV1ProcurementPendingCommand {
  const YorksV1ProcurementPendingCommand({
    required this.attemptId,
    required this.commandName,
    required this.commandKey,
    this.automaticChecks = 0,
    this.automaticCheckAfter,
  });

  /// Preserve the exact submitted body, including nested rows, between checks.
  static Map<String, Object?> freezePayload(Map<String, Object?> value) =>
      _freezeMap(value);

  final String attemptId;
  final String commandName;
  final String commandKey;
  final int automaticChecks;
  final DateTime? automaticCheckAfter;
  YorksV1ProcurementPendingCommand withAutomaticCheck(DateTime after) =>
      YorksV1ProcurementPendingCommand(
        attemptId: attemptId,
        commandName: commandName,
        commandKey: commandKey,
        automaticChecks: automaticChecks + 1,
        automaticCheckAfter: after,
      );
  Map<String, Object?> toJson() => {
    'attempt_id': attemptId,
    'command_name': commandName,
    'command_key': commandKey,
    'automatic_checks': automaticChecks,
    if (automaticCheckAfter != null)
      'automatic_check_after': automaticCheckAfter!.toUtc().toIso8601String(),
  };
  factory YorksV1ProcurementPendingCommand.fromJson(Map<String, Object?> json) {
    _onlyKeys(json, {
      'attempt_id',
      'command_name',
      'command_key',
      'automatic_checks',
      'automatic_check_after',
    });
    final checks = json['automatic_checks'] ?? 0;
    if (checks is! int || checks < 0 || checks > 4) {
      throw const FormatException('Invalid command recovery budget');
    }
    final command = _string(json['command_name']);
    if (command != 'v1_save_arrangement' &&
        command != 'v1_dispatch_materials') {
      throw const FormatException('Invalid procurement command');
    }
    return YorksV1ProcurementPendingCommand(
      attemptId: _string(json['attempt_id']),
      commandName: command,
      commandKey: _string(json['command_key']),
      automaticChecks: checks,
      automaticCheckAfter: json['automatic_check_after'] == null
          ? null
          : DateTime.parse(_string(json['automatic_check_after'])).toUtc(),
    );
  }
}

void _validateInputs(
  YorksV1ProcurementEditorKind kind,
  Map<String, Object?> data,
) {
  final arrangement = kind == YorksV1ProcurementEditorKind.arrangement;
  final textKeys = arrangement
      ? {'note'}
      : {
          'dispatch_date',
          'delivery_reference',
          'driver_name',
          'vehicle_reference',
        };
  _onlyKeys(data, {...textKeys, 'lines'});
  for (final key in textKeys) {
    if (data.containsKey(key)) _boundedText(data[key]);
  }
  final lines = data['lines'];
  if (lines is! List || lines.length > 2000) {
    throw const FormatException('Invalid progress lines');
  }
  final ids = <String>{};
  for (final raw in lines) {
    final line = _map(raw);
    final allowed = arrangement
        ? {
            'arrangement_line_id',
            'decision',
            'source_kind',
            'inventory_item_id',
            'arranged_qty',
            'reason',
            'external_supplier',
            'external_ready',
            'expected_available_date',
            'external_reference',
          }
        : {'request_line_id', 'dispatch_qty'};
    _onlyKeys(line, allowed);
    final id = _string(
      line[arrangement ? 'arrangement_line_id' : 'request_line_id'],
    );
    if (id.isEmpty || !ids.add(id)) {
      throw const FormatException('Duplicate progress line');
    }
    for (final entry in line.entries) {
      if (entry.key == 'external_ready') {
        if (entry.value is! bool) {
          throw const FormatException('Invalid readiness');
        }
      } else if (entry.key == 'inventory_item_id' && entry.value == null) {
        continue;
      } else {
        _boundedText(entry.value);
      }
    }
  }
}

void _validateCommercial(Map<String, Object?> data) {
  if (data.isEmpty) return;
  _onlyKeys(data, {'lines'});
  final lines = data['lines'];
  if (lines is! List || lines.length > 2000) {
    throw const FormatException('Invalid commercial lines');
  }
  final ids = <String>{};
  for (final raw in lines) {
    final line = _map(raw);
    _onlyKeys(line, {'arrangement_line_id', 'unit_cost'});
    final id = _string(line['arrangement_line_id']);
    if (id.isEmpty || !ids.add(id)) {
      throw const FormatException('Duplicate commercial line');
    }
    _boundedText(line['unit_cost']);
  }
}

void _onlyKeys(Map<String, Object?> value, Set<String> allowed) {
  if (value.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('Unsupported progress field');
  }
}

void _boundedText(Object? value) {
  if (value is! String || value.length > 10000) {
    throw const FormatException('Invalid progress text');
  }
}

String _string(Object? value) =>
    value is String ? value : throw const FormatException('Expected text');
String? _nullableString(Object? value) => value == null ? null : _string(value);
int _integer(Object? value) =>
    value is int ? value : throw const FormatException('Expected integer');
Map<String, Object?> _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Expected object');
  }
  return Map<String, Object?>.from(value);
}

Map<String, Object?> _freezeMap(Map<String, Object?> value) =>
    Map<String, Object?>.unmodifiable(
      value.map((key, value) => MapEntry(key, _freeze(value))),
    );
Object? _freeze(Object? value) {
  if (value is Map) return _freezeMap(_map(value));
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  throw const FormatException('Invalid progress value');
}

Object? _canonical(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

String _fingerprint(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(_canonical(value)))).toString();

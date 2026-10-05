import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'yorks_v1_domain_error.dart';
import 'yorks_v1_document.dart';
import 'yorks_v1_project.dart';

enum YorksV1ProjectSetupMode { create, edit }

enum YorksV1ProjectSetupCommandKind {
  create('v1_create_project'),
  update('v1_update_project'),
  activate('v1_set_project_state');

  const YorksV1ProjectSetupCommandKind(this.functionName);
  final String functionName;
}

enum YorksV1ProjectSetupCommandStatus {
  notSent,
  submitting,
  confirmedSuccess,
  confirmedRejected,
  outcomeUncertain,
  reconciling;

  bool get unresolved =>
      this == submitting || this == outcomeUncertain || this == reconciling;
}

enum YorksV1ProjectSetupFileStatus {
  selected,
  needsReselect,
  uploading,
  ready,
  failed,
  outcomeUncertain,
  removed,
}

/// An immutable, reviewed server intent. Its key and canonical payload are
/// local recovery data and must never enter analytics or application logs.
class YorksV1ProjectSetupCommand {
  YorksV1ProjectSetupCommand({
    required this.kind,
    required this.idempotencyKey,
    required Map<String, dynamic> payload,
    this.status = YorksV1ProjectSetupCommandStatus.notSent,
    this.attempts = 0,
    this.errorCode,
    this.nextRetryAt,
    Map<String, dynamic>? result,
  }) : canonicalPayload = yorksV1CanonicalSetupJson(payload),
       canonicalResult = result == null
           ? null
           : yorksV1CanonicalSetupJson(result);

  final YorksV1ProjectSetupCommandKind kind;
  final String idempotencyKey;
  final String canonicalPayload;
  final String? canonicalResult;
  final YorksV1ProjectSetupCommandStatus status;
  final int attempts;
  final YorksV1DomainErrorCode? errorCode;
  final DateTime? nextRetryAt;

  String get payloadHash =>
      sha256.convert(utf8.encode(canonicalPayload)).toString();
  Map<String, dynamic> get payload =>
      Map<String, dynamic>.from(jsonDecode(canonicalPayload) as Map);
  Map<String, dynamic>? get result => canonicalResult == null
      ? null
      : Map<String, dynamic>.from(jsonDecode(canonicalResult!) as Map);
  int? get expectedVersion => payload['expected_version'] as int?;

  YorksV1Project? get project {
    final value = result;
    if (value == null) return null;
    final nested = value['project'];
    return YorksV1Project.fromRpcJson(
      nested is Map ? Map<String, dynamic>.from(nested) : value,
    );
  }

  YorksV1ProjectSetupCommand withOutcome({
    required YorksV1ProjectSetupCommandStatus status,
    int? attempts,
    YorksV1DomainErrorCode? errorCode,
    DateTime? nextRetryAt,
    Map<String, dynamic>? result,
  }) => YorksV1ProjectSetupCommand(
    kind: kind,
    idempotencyKey: idempotencyKey,
    payload: payload,
    status: status,
    attempts: attempts ?? this.attempts,
    errorCode: errorCode,
    nextRetryAt: nextRetryAt ?? this.nextRetryAt,
    result: result ?? this.result,
  );

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'key': idempotencyKey,
    'payload': payload,
    'payload_hash': payloadHash,
    'expected_version': expectedVersion,
    'status': status.name,
    'attempts': attempts,
    'error_code': errorCode?.name,
    'next_retry_at': nextRetryAt?.toUtc().toIso8601String(),
    'result': result,
  };

  factory YorksV1ProjectSetupCommand.fromJson(Map<String, dynamic> json) {
    final command = YorksV1ProjectSetupCommand(
      kind: _enumValue(YorksV1ProjectSetupCommandKind.values, json['kind']),
      idempotencyKey: json['key'] as String,
      payload: Map<String, dynamic>.from(json['payload'] as Map),
      status: _enumValue(
        YorksV1ProjectSetupCommandStatus.values,
        json['status'],
      ),
      attempts: json['attempts'] as int,
      errorCode: json['error_code'] == null
          ? null
          : _enumValue(YorksV1DomainErrorCode.values, json['error_code']),
      nextRetryAt: json['next_retry_at'] == null
          ? null
          : DateTime.parse(json['next_retry_at'] as String).toUtc(),
      result: json['result'] == null
          ? null
          : Map<String, dynamic>.from(json['result'] as Map),
    );
    if (command.idempotencyKey.isEmpty ||
        command.attempts < 0 ||
        command.payloadHash != json['payload_hash'] ||
        command.expectedVersion != json['expected_version'] ||
        (command.status == YorksV1ProjectSetupCommandStatus.confirmedSuccess &&
            command.result == null) ||
        (command.result != null &&
            command.status !=
                YorksV1ProjectSetupCommandStatus.confirmedSuccess)) {
      throw const FormatException('Invalid project operation intent');
    }
    if (command.status == YorksV1ProjectSetupCommandStatus.confirmedSuccess) {
      final project = command.project!;
      if (command.kind != YorksV1ProjectSetupCommandKind.create &&
          project.id != command.payload['project_id']) {
        throw const FormatException(
          'Project operation result identity mismatch',
        );
      }
    }
    return command;
  }
}

/// File identity includes the actual selected byte hash. Metadata alone is
/// never evidence that a document was uploaded or that reselected bytes match.
class YorksV1ProjectSetupFile {
  const YorksV1ProjectSetupFile({
    required this.localId,
    required this.idempotencyKey,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.classification,
    this.contentHash,
    this.status = YorksV1ProjectSetupFileStatus.needsReselect,
    this.errorCode,
    this.categoryKey,
    this.retainedFields = const {},
  });

  final String localId;
  final String idempotencyKey;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final YorksV1DocumentClassification classification;
  final String? contentHash;
  final YorksV1ProjectSetupFileStatus status;
  final YorksV1DomainErrorCode? errorCode;
  // Organization metadata is independent of the protected classification and
  // the exact idempotent upload intent. Older manifests retain an omitted key.
  final String? categoryKey;
  final Map<String, dynamic> retainedFields;

  YorksV1ProjectAttachmentCategory? get category =>
      YorksV1ProjectAttachmentCategory.fromWireValue(effectiveCategoryKey);
  String get effectiveCategoryKey =>
      categoryKey ?? YorksV1ProjectAttachmentCategory.general.wireValue;

  YorksV1ProjectSetupFile withOutcome(
    YorksV1ProjectSetupFileStatus status, {
    String? contentHash,
    YorksV1DomainErrorCode? errorCode,
  }) => YorksV1ProjectSetupFile(
    localId: localId,
    idempotencyKey: idempotencyKey,
    fileName: fileName,
    mimeType: mimeType,
    sizeBytes: sizeBytes,
    classification: classification,
    contentHash: contentHash ?? this.contentHash,
    status: status,
    errorCode: errorCode,
    categoryKey: categoryKey,
    retainedFields: retainedFields,
  );

  Map<String, dynamic> toJson() => {
    ...retainedFields,
    'local_id': localId,
    'key': idempotencyKey,
    'file_name': fileName,
    'mime_type': mimeType,
    'size_bytes': sizeBytes,
    'classification': classification.wireValue,
    'content_hash': contentHash,
    'status': status.name,
    'error_code': errorCode?.name,
    if (categoryKey != null) 'category': categoryKey,
  };

  factory YorksV1ProjectSetupFile.fromJson(Map<String, dynamic> json) {
    final file = YorksV1ProjectSetupFile(
      localId: json['local_id'] as String,
      idempotencyKey: json['key'] as String,
      fileName: json['file_name'] as String,
      mimeType: json['mime_type'] as String,
      sizeBytes: json['size_bytes'] as int,
      classification:
          YorksV1DocumentClassification.fromWireValue(json['classification']) ??
          (throw const FormatException(
            'Unreviewed project file classification',
          )),
      contentHash: json['content_hash'] as String?,
      status: _enumValue(YorksV1ProjectSetupFileStatus.values, json['status']),
      errorCode: json['error_code'] == null
          ? null
          : _enumValue(YorksV1DomainErrorCode.values, json['error_code']),
      categoryKey: json['category'] as String?,
      retainedFields: Map.unmodifiable({
        for (final entry in json.entries)
          if (!const {
            'local_id',
            'key',
            'file_name',
            'mime_type',
            'size_bytes',
            'classification',
            'content_hash',
            'status',
            'error_code',
            'category',
          }.contains(entry.key))
            entry.key: entry.value,
      }),
    );
    if (file.localId.isEmpty ||
        file.idempotencyKey.isEmpty ||
        file.sizeBytes < 0) {
      throw const FormatException('Invalid project file recovery record');
    }
    return file;
  }
}

/// Separate from the creation/edit proposal. Retirement of a proposal leaves
/// this journal intact, including confirmed results and unfinished files.
class YorksV1ProjectSetupOperation {
  const YorksV1ProjectSetupOperation({
    required this.backendIdentity,
    required this.ownerAuthUserId,
    required this.draftId,
    required this.mode,
    required this.core,
    this.activation,
    this.files = const [],
    this.revision = 1,
    this.cleanupComplete = false,
    this.coreSuccessReported = false,
    this.reportedOutcome,
  });

  final String backendIdentity;
  final String ownerAuthUserId;
  final String draftId;
  final YorksV1ProjectSetupMode mode;
  final YorksV1ProjectSetupCommand core;
  final YorksV1ProjectSetupCommand? activation;
  final List<YorksV1ProjectSetupFile> files;
  final int revision;
  final bool cleanupComplete;
  final bool coreSuccessReported;
  final String? reportedOutcome;

  /// Opaque local recovery locator; never contains project or submitted data.
  /// It is displayed for authorized device diagnostics, not sent to telemetry.
  String get supportReference =>
      'SETUP-${sha256.convert(utf8.encode('$backendIdentity|$draftId')).toString().substring(0, 12).toUpperCase()}';

  bool get coreSucceeded =>
      core.status == YorksV1ProjectSetupCommandStatus.confirmedSuccess;
  YorksV1Project? get project =>
      activation?.status == YorksV1ProjectSetupCommandStatus.confirmedSuccess
      ? activation!.project
      : core.project;
  bool get filesPending => files.any(
    (file) =>
        file.status != YorksV1ProjectSetupFileStatus.ready &&
        file.status != YorksV1ProjectSetupFileStatus.removed,
  );
  bool get hasUnresolvedCommand =>
      core.status.unresolved || (activation?.status.unresolved ?? false);

  YorksV1ProjectSetupOperation copyWith({
    YorksV1ProjectSetupCommand? core,
    YorksV1ProjectSetupCommand? activation,
    List<YorksV1ProjectSetupFile>? files,
    int? revision,
    bool? cleanupComplete,
    bool? coreSuccessReported,
    String? reportedOutcome,
  }) => YorksV1ProjectSetupOperation(
    backendIdentity: backendIdentity,
    ownerAuthUserId: ownerAuthUserId,
    draftId: draftId,
    mode: mode,
    core: core ?? this.core,
    activation: activation ?? this.activation,
    files: files ?? this.files,
    revision: revision ?? this.revision,
    cleanupComplete: cleanupComplete ?? this.cleanupComplete,
    coreSuccessReported: coreSuccessReported ?? this.coreSuccessReported,
    reportedOutcome: reportedOutcome ?? this.reportedOutcome,
  );

  Map<String, dynamic> toJson() => {
    'schema_version': 1,
    'backend': backendIdentity,
    'owner': ownerAuthUserId,
    'draft_id': draftId,
    'mode': mode.name,
    'core': core.toJson(),
    'activation': activation?.toJson(),
    'files': files.map((file) => file.toJson()).toList(),
    'revision': revision,
    'cleanup_complete': cleanupComplete,
    'core_success_reported': coreSuccessReported,
    'reported_outcome': reportedOutcome,
  };

  factory YorksV1ProjectSetupOperation.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != 1) {
      throw const FormatException('Unsupported project operation version');
    }
    final operation = YorksV1ProjectSetupOperation(
      backendIdentity: json['backend'] as String,
      ownerAuthUserId: json['owner'] as String,
      draftId: json['draft_id'] as String,
      mode: _enumValue(YorksV1ProjectSetupMode.values, json['mode']),
      core: YorksV1ProjectSetupCommand.fromJson(
        Map<String, dynamic>.from(json['core'] as Map),
      ),
      activation: json['activation'] == null
          ? null
          : YorksV1ProjectSetupCommand.fromJson(
              Map<String, dynamic>.from(json['activation'] as Map),
            ),
      files: [
        for (final file in json['files'] as List)
          YorksV1ProjectSetupFile.fromJson(
            Map<String, dynamic>.from(file as Map),
          ),
      ],
      revision: json['revision'] as int,
      cleanupComplete: json['cleanup_complete'] as bool,
      coreSuccessReported: json['core_success_reported'] as bool? ?? false,
      reportedOutcome: json['reported_outcome'] as String?,
    );
    if (operation.backendIdentity.isEmpty ||
        operation.ownerAuthUserId.isEmpty ||
        operation.draftId.isEmpty ||
        operation.revision < 1 ||
        (operation.coreSuccessReported && !operation.coreSucceeded)) {
      throw const FormatException('Invalid project operation envelope');
    }
    return operation;
  }
}

String yorksV1CanonicalSetupJson(Object? value) {
  Object? canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: canonical(value[key])};
    }
    if (value is List) return value.map(canonical).toList(growable: false);
    if (value == null || value is String || value is bool || value is num) {
      return value;
    }
    throw const FormatException('Unsupported project operation value');
  }

  return jsonEncode(canonical(value));
}

T _enumValue<T extends Enum>(List<T> values, Object? name) =>
    values.singleWhere((value) => value.name == name);

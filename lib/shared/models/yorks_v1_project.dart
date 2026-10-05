import 'yorks_v1_domain_error.dart';
import 'yorks_v1_project_attachment_category.dart';
import 'yorks_v1_role.dart';

export 'yorks_v1_project_attachment_category.dart';

/// The only Yorks V1 project lifecycle. This intentionally coexists with the
/// legacy [ProjectState] and [ProjectLifecycleStatus] types until their screens
/// have moved to the normalized V1 read path.
enum YorksV1ProjectLifecycle {
  draft('draft'),
  active('active'),
  onHold('on_hold'),
  completed('completed'),
  archived('archived');

  const YorksV1ProjectLifecycle(this.wireValue);

  final String wireValue;

  static YorksV1ProjectLifecycle? fromWireValue(Object? value) {
    if (value is! String) return null;
    for (final state in YorksV1ProjectLifecycle.values) {
      if (state.wireValue == value) return state;
    }
    return null;
  }

  /// Client-side preflight only. The server checks this again under the project
  /// row lock before committing a state command.
  bool canTransitionTo(YorksV1ProjectLifecycle target) {
    return switch (this) {
      YorksV1ProjectLifecycle.draft => target == YorksV1ProjectLifecycle.active,
      YorksV1ProjectLifecycle.active =>
        target == YorksV1ProjectLifecycle.onHold ||
            target == YorksV1ProjectLifecycle.completed,
      YorksV1ProjectLifecycle.onHold =>
        target == YorksV1ProjectLifecycle.active ||
            target == YorksV1ProjectLifecycle.completed,
      YorksV1ProjectLifecycle.completed =>
        target == YorksV1ProjectLifecycle.archived,
      YorksV1ProjectLifecycle.archived => false,
    };
  }

  bool requiresReasonFor(YorksV1ProjectLifecycle target) {
    return (this == YorksV1ProjectLifecycle.active &&
            target == YorksV1ProjectLifecycle.onHold) ||
        (this == YorksV1ProjectLifecycle.onHold &&
            target == YorksV1ProjectLifecycle.active) ||
        (this == YorksV1ProjectLifecycle.completed &&
            target == YorksV1ProjectLifecycle.archived);
  }
}

/// Scope records are the single project destination authority. A `common`
/// scope is created by the server once per project; clients never submit it as
/// another physical building.
enum YorksV1ProjectScopeKind {
  common('common'),
  building('building');

  const YorksV1ProjectScopeKind(this.wireValue);

  final String wireValue;

  static YorksV1ProjectScopeKind? fromWireValue(Object? value) {
    if (value is! String) return null;
    for (final kind in YorksV1ProjectScopeKind.values) {
      if (kind.wireValue == value) return kind;
    }
    return null;
  }
}

/// The role recorded against a dated project membership. This is deliberately
/// narrower than platform roles: Procurement and Admin do not gain project
/// membership by being placed in this list.
enum YorksV1ProjectMembershipRole {
  projectEngineer('project_engineer'),
  siteEngineer('site_engineer');

  const YorksV1ProjectMembershipRole(this.wireValue);

  final String wireValue;

  static YorksV1ProjectMembershipRole? fromWireValue(Object? value) {
    if (value is! String) return null;
    for (final role in YorksV1ProjectMembershipRole.values) {
      if (role.wireValue == value) return role;
    }
    return null;
  }
}

enum YorksV1ProjectPartyKind {
  client('client'),
  consultant('consultant'),
  mainContractor('main_contractor'),
  subcontractor('subcontractor'),
  otherContractor('other_contractor');

  const YorksV1ProjectPartyKind(this.wireValue);

  final String wireValue;

  static YorksV1ProjectPartyKind? fromWireValue(Object? value) {
    if (value is! String) return null;
    for (final kind in YorksV1ProjectPartyKind.values) {
      if (kind.wireValue == value) return kind;
    }
    return null;
  }
}

enum YorksV1ProjectValidationCode {
  missingIdempotencyKey,
  missingProjectId,
  missingProjectReference,
  missingProjectName,
  invalidDateRange,
  unsupportedProjectDate,
  invalidProjectParty,
  duplicateProjectParty,
  invalidAttachment,
  missingBuilding,
  invalidBuilding,
  duplicateBuildingCode,
  duplicateMember,
  missingMemberAuthUserId,
  missingMembershipReason,
  invalidMembershipRange,
  invalidVersion,
  missingStateReason,
  invalidStateTransition,
}

/// Project dates are calendar values.  Fifty years either side of today is a
/// deliberately generous operational window that catches accidental
/// century-scale selections while allowing legacy/current construction work.
const yorksV1ProjectDateWindowYears = 50;

bool yorksV1ProjectDateIsSupported(DateTime value, {DateTime? referenceDate}) {
  final reference = referenceDate ?? DateTime.now();
  final earliest = DateTime(reference.year - yorksV1ProjectDateWindowYears);
  final latest = DateTime(
    reference.year + yorksV1ProjectDateWindowYears,
    12,
    31,
  );
  final date = DateTime(value.year, value.month, value.day);
  return !date.isBefore(earliest) && !date.isAfter(latest);
}

/// An authoritative non-commercial project projection returned by a V1 RPC or
/// secure V1 query. Commercial fields are intentionally absent from this type.
class YorksV1Project {
  const YorksV1Project({
    required this.id,
    required this.reference,
    required this.name,
    required this.state,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.clientName,
    this.jobOrContractReference,
    this.siteLocation,
    this.clientContactName,
    this.clientContactPhone,
    this.city,
    this.countryCode,
    this.startDate,
    this.endDate,
    this.notes,
    this.currentActionOwnerProfileId,
    this.currentActionOwnerRole,
    this.currentActionCode,
    this.createdByAuthUserId,
  });

  final String id;
  final String reference;
  final String name;
  final YorksV1ProjectLifecycle state;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? clientName;
  final String? jobOrContractReference;
  final String? siteLocation;
  final String? clientContactName;
  final String? clientContactPhone;
  final String? city;
  final String? countryCode;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? notes;
  final String? currentActionOwnerProfileId;
  final String? currentActionOwnerRole;

  /// A server-provided code, not presentation copy.
  final String? currentActionCode;
  final String? createdByAuthUserId;

  /// Exact V1 database terminology. [version] remains a concise controller
  /// alias for optimistic-write input construction.
  int get recordVersion => version;

  factory YorksV1Project.fromRpcJson(Map<String, dynamic> json) {
    final state = YorksV1ProjectLifecycle.fromWireValue(
      json['state'] ?? json['lifecycle_state'],
    );
    if (state == null) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1Project(
      id: _requiredString(json, 'id', fallback: 'project_id'),
      reference: _requiredString(json, 'reference', fallback: 'project_ref'),
      name: _requiredString(json, 'name'),
      state: state,
      version: _nonNegativeInt(json['record_version'] ?? json['version']),
      createdAt: _requiredDate(json, 'created_at', fallback: 'createdAt'),
      updatedAt:
          _nullableDate(json['updated_at'] ?? json['updatedAt']) ??
          _requiredDate(json, 'created_at', fallback: 'createdAt'),
      clientName: _nullableString(json['client_name'] ?? json['clientName']),
      jobOrContractReference: _nullableString(
        json['job_contract_reference'] ?? json['contract_or_job_number'],
      ),
      siteLocation: _nullableString(
        json['project_site'] ?? json['siteLocation'],
      ),
      clientContactName: _nullableString(
        json['client_contact_name'] ?? json['clientContactName'],
      ),
      clientContactPhone: _nullableString(
        json['client_contact_phone'] ?? json['clientContactPhone'],
      ),
      city: _nullableString(json['city']),
      countryCode: _nullableString(json['country_code'] ?? json['countryCode']),
      startDate: _nullableDate(json['start_date'] ?? json['startDate']),
      endDate: _nullableDate(json['target_completion_date'] ?? json['endDate']),
      notes: _nullableString(json['notes']),
      currentActionOwnerProfileId: _nullableString(
        json['current_action_owner_profile_id'] ??
            json['currentActionOwnerProfileId'],
      ),
      currentActionOwnerRole: _nullableString(
        json['current_action_owner_role'] ?? json['currentActionOwnerRole'],
      ),
      currentActionCode: _nullableString(
        json['current_action_code'] ?? json['currentActionCode'],
      ),
      createdByAuthUserId: _nullableString(
        json['created_by_auth_user_id'] ?? json['createdByAuthUserId'],
      ),
    );
  }
}

class YorksV1ProjectScope {
  const YorksV1ProjectScope({
    required this.id,
    required this.projectId,
    required this.kind,
    required this.code,
    required this.name,
    required this.active,
    this.floorsOrLevels = const [],
    this.hasFrpRoom = false,
    this.deliveryAddress,
    this.flags = const {},
    this.notes,
  });

  final String id;
  final String projectId;
  final YorksV1ProjectScopeKind kind;
  final String code;
  final String name;
  final bool active;
  final List<String> floorsOrLevels;
  final bool hasFrpRoom;
  final String? deliveryAddress;
  final Map<String, dynamic> flags;
  final String? notes;

  bool get isCommon => kind == YorksV1ProjectScopeKind.common;
  bool get isImmutable => isCommon;

  factory YorksV1ProjectScope.fromRpcJson(Map<String, dynamic> json) {
    final kind = YorksV1ProjectScopeKind.fromWireValue(
      json['scope_kind'] ?? json['kind'] ?? json['scope_type'],
    );
    if (kind == null) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    final flags = _map(json['flags'] ?? json['scope_flags']);
    return YorksV1ProjectScope(
      id: _requiredString(json, 'id'),
      projectId: _requiredString(json, 'project_id', fallback: 'projectId'),
      kind: kind,
      // The trusted create RPC uses the concise projection key `code`; a
      // future authorized direct read of the normalized relation returns its
      // physical column name `scope_code`. Both describe the same immutable
      // scope identifier and must decode without a lossy adapter.
      code: _requiredString(json, 'code', fallback: 'scope_code'),
      name: _requiredString(json, 'name'),
      active: _bool(json['is_active'] ?? json['active'], defaultValue: true),
      floorsOrLevels: _strings(
        json['floors_levels'] ??
            json['floors_or_levels'] ??
            json['floorsOrLevels'],
      ),
      hasFrpRoom: _bool(
        flags['has_frp_room'] ?? json['has_frp_room'] ?? json['hasFrpRoom'],
        defaultValue: false,
      ),
      deliveryAddress: _nullableString(
        json['delivery_address'] ?? json['deliveryAddress'],
      ),
      flags: Map.unmodifiable(flags),
      notes: _nullableString(json['notes']),
    );
  }
}

/// A dated membership history row. Revoking access closes this record rather
/// than deleting it, preserving the actor and project-role history.
class YorksV1ProjectMember {
  const YorksV1ProjectMember({
    required this.id,
    required this.projectId,
    required this.memberAuthUserId,
    required this.projectRole,
    required this.effectiveFrom,
    required this.createdAt,
    this.displayName,
    this.effectiveTo,
    this.reason,
    this.assignedByAuthUserId,
    this.assignedByRole,
    this.revokedByAuthUserId,
    this.revokedByRole,
    this.revokedReason,
  });

  final String id;
  final String projectId;
  final String memberAuthUserId;
  final YorksV1ProjectMembershipRole projectRole;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;
  final DateTime createdAt;
  final String? displayName;
  final String? reason;
  final String? assignedByAuthUserId;
  final String? assignedByRole;
  final String? revokedByAuthUserId;
  final String? revokedByRole;
  final String? revokedReason;

  /// Compatibility alias for callers which predate V1 membership history.
  String? get createdByAuthUserId => assignedByAuthUserId;

  bool isActiveAt(DateTime instant) {
    final point = instant.toUtc();
    final begins = !point.isBefore(effectiveFrom.toUtc());
    final ends = effectiveTo == null || point.isBefore(effectiveTo!.toUtc());
    return begins && ends;
  }

  factory YorksV1ProjectMember.fromRpcJson(Map<String, dynamic> json) {
    final projectRole = YorksV1ProjectMembershipRole.fromWireValue(
      json['project_role'] ?? json['role'],
    );
    if (projectRole == null) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    final effectiveFrom = _requiredDate(
      json,
      'effective_from',
      fallback: 'effectiveFrom',
    );
    return YorksV1ProjectMember(
      id: _requiredString(json, 'id'),
      projectId: _requiredString(json, 'project_id', fallback: 'projectId'),
      memberAuthUserId: _requiredString(
        json,
        'member_auth_user_id',
        fallback: 'auth_user_id',
      ),
      projectRole: projectRole,
      effectiveFrom: effectiveFrom,
      effectiveTo: _nullableDate(json['effective_to'] ?? json['effectiveTo']),
      createdAt: _requiredDate(json, 'created_at', fallback: 'createdAt'),
      displayName: _nullableString(json['display_name'] ?? json['displayName']),
      reason: _nullableString(json['reason']),
      assignedByAuthUserId: _nullableString(
        json['assigned_by_auth_user_id'] ??
            json['created_by_auth_user_id'] ??
            json['assignedByAuthUserId'] ??
            json['createdByAuthUserId'],
      ),
      assignedByRole: _nullableString(
        json['assigned_by_role'] ?? json['assignedByRole'],
      ),
      revokedByAuthUserId: _nullableString(
        json['revoked_by_auth_user_id'] ?? json['revokedByAuthUserId'],
      ),
      revokedByRole: _nullableString(
        json['revoked_by_role'] ?? json['revokedByRole'],
      ),
      revokedReason: _nullableString(
        json['revoked_reason'] ?? json['revokedReason'],
      ),
    );
  }
}

class YorksV1ProjectPartyInput {
  const YorksV1ProjectPartyInput({
    required this.kind,
    required this.name,
    this.contactName,
    this.contactPhone,
    this.contactEmail,
    this.address,
    this.retainedFields = const {},
  });

  final YorksV1ProjectPartyKind kind;
  final String name;
  final String? contactName;
  final String? contactPhone;
  final String? contactEmail;
  final String? address;

  /// Unknown local metadata is retained for recovery, never promoted to an RPC.
  final Map<String, dynamic> retainedFields;

  Map<String, dynamic> toPartyRpcJson() => {
    'name': name.trim(),
    'contact_name': _trimToNull(contactName),
    'contact_phone': _trimToNull(contactPhone),
    'contact_email': _trimToNull(contactEmail),
    'address': _trimToNull(address),
  };

  Map<String, dynamic> toDraftJson() => {
    ...retainedFields,
    'kind': kind.wireValue,
    'name': name,
    'contact_name': contactName,
    'contact_phone': contactPhone,
    'contact_email': contactEmail,
    'address': address,
  };

  factory YorksV1ProjectPartyInput.fromDraftJson(Map<String, dynamic> json) {
    final kind = YorksV1ProjectPartyKind.fromWireValue(json['kind']);
    if (kind == null) {
      // A future/legacy party is quarantined by the draft adapter, not guessed.
      throw const FormatException('Unsupported project party kind');
    }
    return YorksV1ProjectPartyInput(
      kind: kind,
      name: json['name'] as String? ?? '',
      contactName:
          (json.containsKey('contact_name')
                  ? json['contact_name']
                  : json['contactName'])
              as String?,
      contactPhone:
          (json.containsKey('contact_phone')
                  ? json['contact_phone']
                  : json['contactPhone'])
              as String?,
      contactEmail:
          (json.containsKey('contact_email')
                  ? json['contact_email']
                  : json['contactEmail'])
              as String?,
      address: json['address'] as String?,
      retainedFields: {
        for (final entry in json.entries)
          if (!const {
            'kind',
            'name',
            'contact_name',
            'contactName',
            'contact_phone',
            'contactPhone',
            'contact_email',
            'contactEmail',
            'address',
          }.contains(entry.key))
            entry.key: entry.value,
      },
    );
  }
}

class YorksV1ProjectBuildingInput {
  const YorksV1ProjectBuildingInput({
    this.sourceScopeId,
    this.code = '',
    required this.name,
    this.deliveryAddress,
    this.floorsOrLevels = const [],
    this.hasFrpRoom = false,
    this.flags = const {},
    this.localRowId,
    this.retainedFields = const {},
  });

  final String code;

  /// The normalized scope identity for edit mode. It is never supplied during
  /// creation, so a project update can retain request/receipt attribution.
  final String? sourceScopeId;
  final String name;
  final String? deliveryAddress;
  final List<String> floorsOrLevels;
  final bool hasFrpRoom;
  final Map<String, dynamic> flags;
  final String? localRowId;
  final Map<String, dynamic> retainedFields;

  YorksV1ProjectBuildingInput copyWith({
    String? code,
    String? name,
    String? deliveryAddress,
    List<String>? floorsOrLevels,
    bool? hasFrpRoom,
    String? localRowId,
  }) => YorksV1ProjectBuildingInput(
    sourceScopeId: sourceScopeId,
    code: code ?? this.code,
    name: name ?? this.name,
    deliveryAddress: deliveryAddress ?? this.deliveryAddress,
    floorsOrLevels: floorsOrLevels ?? this.floorsOrLevels,
    hasFrpRoom: hasFrpRoom ?? this.hasFrpRoom,
    flags: flags,
    localRowId: localRowId ?? this.localRowId,
    retainedFields: retainedFields,
  );

  String get normalizedCode => code.trim().toUpperCase();

  bool get isValid => name.trim().isNotEmpty;

  Map<String, dynamic> toRpcJson() => {
    'code': normalizedCode.isEmpty ? null : normalizedCode,
    'name': name.trim(),
    'floors_levels': [
      for (final floor in floorsOrLevels)
        if (floor.trim().isNotEmpty) floor.trim(),
    ],
    'flags': {...flags, 'has_frp_room': hasFrpRoom},
    'delivery_address': _trimToNull(deliveryAddress),
  };

  Map<String, dynamic> toUpdateRpcJson() => {
    if (_trimToNull(sourceScopeId) != null) 'id': sourceScopeId!.trim(),
    ...toRpcJson(),
  };

  Map<String, dynamic> toDraftJson() => {
    ...retainedFields,
    if (sourceScopeId != null) 'sourceScopeId': sourceScopeId,
    'localRowId': localRowId,
    'code': code,
    'name': name,
    'floors_levels': floorsOrLevels,
    'flags': {...flags, 'has_frp_room': hasFrpRoom},
    'delivery_address': deliveryAddress,
  };

  factory YorksV1ProjectBuildingInput.fromDraftJson(Map<String, dynamic> json) {
    if (json['flags'] != null && json['flags'] is! Map) {
      throw const FormatException('Invalid building flags');
    }
    final floors = json['floors_levels'] ?? json['floorsOrLevels'];
    if (floors != null &&
        (floors is! List || floors.any((value) => value is! String))) {
      throw const FormatException('Invalid building floor labels');
    }
    return YorksV1ProjectBuildingInput(
      sourceScopeId: _nullableString(json['id'] ?? json['sourceScopeId']),
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? '',
      deliveryAddress:
          (json['delivery_address'] ?? json['deliveryAddress']) as String?,
      floorsOrLevels: floors == null ? const [] : List<String>.from(floors),
      hasFrpRoom: _bool(
        json.containsKey('hasFrpRoom')
            ? json['hasFrpRoom']
            : _map(json['flags'])['has_frp_room'],
        defaultValue: false,
      ),
      flags: _map(json['flags']),
      localRowId: json['localRowId'] as String?,
      retainedFields: {
        for (final entry in json.entries)
          if (!const {
            'id',
            'sourceScopeId',
            'localRowId',
            'code',
            'name',
            'delivery_address',
            'deliveryAddress',
            'floors_levels',
            'floorsOrLevels',
            'hasFrpRoom',
            'flags',
          }.contains(entry.key))
            entry.key: entry.value,
      },
    );
  }
}

/// B2 attachment-intake metadata accepted by the creation transaction.
///
/// Storage object paths, hashes and document links are deliberately absent:
/// Batch 9 will create those only through a classified, authorized document
/// command. A creation attachment is therefore never an access grant.
class YorksV1ProjectAttachmentInput {
  const YorksV1ProjectAttachmentInput({
    required this.fileName,
    this.mimeType,
    this.sizeBytes,
    this.localId,
    this.contentHash,
    this.categoryKey,
    this.retainedFields = const {},
  });

  final String fileName;
  final String? mimeType;
  final int? sizeBytes;
  final String? localId;
  final String? contentHash;
  // Keep absence and unknown values for exact historical local round-trips.
  // This metadata never enters the reviewed server creation/upload payload.
  final String? categoryKey;
  final Map<String, dynamic> retainedFields;

  YorksV1ProjectAttachmentCategory? get category =>
      YorksV1ProjectAttachmentCategory.fromWireValue(effectiveCategoryKey);
  String get effectiveCategoryKey =>
      categoryKey ?? YorksV1ProjectAttachmentCategory.general.wireValue;

  YorksV1ProjectAttachmentInput copyWith({
    String? fileName,
    String? mimeType,
    int? sizeBytes,
    String? localId,
    String? contentHash,
    String? categoryKey,
  }) => YorksV1ProjectAttachmentInput(
    fileName: fileName ?? this.fileName,
    mimeType: mimeType ?? this.mimeType,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    localId: localId ?? this.localId,
    contentHash: contentHash ?? this.contentHash,
    categoryKey: categoryKey ?? this.categoryKey,
    retainedFields: retainedFields,
  );

  Map<String, dynamic> toRpcJson() => {
    'file_name': fileName.trim(),
    'mime_type': _trimToNull(mimeType),
    'size_bytes': sizeBytes,
  };

  Map<String, dynamic> toDraftJson() => {
    ...retainedFields,
    ...toRpcJson(),
    'local_id': localId,
    'content_hash': contentHash,
    if (categoryKey != null) 'category': categoryKey,
  };

  factory YorksV1ProjectAttachmentInput.fromDraftJson(
    Map<String, dynamic> json,
  ) {
    return YorksV1ProjectAttachmentInput(
      fileName:
          json['file_name'] as String? ?? json['fileName'] as String? ?? '',
      mimeType: _nullableString(json['mime_type'] ?? json['mimeType']),
      sizeBytes: ((json['size_bytes'] ?? json['sizeBytes']) as num?)?.toInt(),
      localId: json['local_id'] as String?,
      contentHash: json['content_hash'] as String?,
      categoryKey: json['category'] as String?,
      retainedFields: Map.unmodifiable({
        for (final entry in json.entries)
          if (!const {
            'file_name',
            'fileName',
            'mime_type',
            'mimeType',
            'size_bytes',
            'sizeBytes',
            'local_id',
            'content_hash',
            'category',
          }.contains(entry.key))
            entry.key: entry.value,
      }),
    );
  }
}

/// Creation-time project memberships. The server derives audit actor/role and
/// records the creation reason; callers never supply either authority value.
class YorksV1InitialProjectMemberInput {
  const YorksV1InitialProjectMemberInput({
    required this.authUserId,
    required this.projectRole,
    this.reason,
  });

  final String authUserId;
  final YorksV1ProjectMembershipRole projectRole;
  final String? reason;

  Map<String, dynamic> toRpcJson() => {
    'auth_user_id': authUserId.trim(),
    'project_role': projectRole.wireValue,
    'reason': _trimToNull(reason),
  };

  Map<String, dynamic> toDraftJson() => toRpcJson();

  factory YorksV1InitialProjectMemberInput.fromDraftJson(
    Map<String, dynamic> json,
  ) {
    final role = YorksV1ProjectMembershipRole.fromWireValue(
      json['project_role'] ?? json['projectRole'],
    );
    return YorksV1InitialProjectMemberInput(
      authUserId:
          json['auth_user_id'] as String? ??
          json['authUserId'] as String? ??
          '',
      projectRole: role ?? YorksV1ProjectMembershipRole.siteEngineer,
      reason: _nullableString(json['reason']),
    );
  }
}

/// Typed input to the one connected `v1_create_project` command.
///
/// It never carries an actor ID, platform role, timestamps asserted as audit
/// truth, an initial Common scope, or a client-selected lifecycle state.
class YorksV1ProjectCreationInput {
  const YorksV1ProjectCreationInput({
    required this.idempotencyKey,
    required this.reference,
    required this.name,
    this.clientName,
    this.jobOrContractReference,
    this.siteLocation,
    this.clientContactName,
    this.clientContactPhone,
    this.clientContactEmail,
    this.clientAddress,
    this.startDate,
    this.endDate,
    this.notes,
    this.parties = const [],
    this.initialMembers = const [],
    this.buildings = const [],
    this.attachments = const [],
  });

  final String idempotencyKey;
  final String reference;
  final String name;
  final String? clientName;
  final String? jobOrContractReference;
  final String? siteLocation;
  final String? clientContactName;
  final String? clientContactPhone;
  final String? clientContactEmail;
  final String? clientAddress;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? notes;
  final List<YorksV1ProjectPartyInput> parties;
  final List<YorksV1InitialProjectMemberInput> initialMembers;
  final List<YorksV1ProjectBuildingInput> buildings;
  final List<YorksV1ProjectAttachmentInput> attachments;

  Set<YorksV1ProjectValidationCode> validate() {
    final errors = <YorksV1ProjectValidationCode>{};
    if (idempotencyKey.trim().isEmpty) {
      errors.add(YorksV1ProjectValidationCode.missingIdempotencyKey);
    }
    if (reference.trim().isEmpty) {
      errors.add(YorksV1ProjectValidationCode.missingProjectReference);
    }
    if (name.trim().isEmpty) {
      errors.add(YorksV1ProjectValidationCode.missingProjectName);
    }
    if (startDate != null &&
        endDate != null &&
        endDate!.toUtc().isBefore(startDate!.toUtc())) {
      errors.add(YorksV1ProjectValidationCode.invalidDateRange);
    }
    if ((startDate != null && !yorksV1ProjectDateIsSupported(startDate!)) ||
        (endDate != null && !yorksV1ProjectDateIsSupported(endDate!))) {
      errors.add(YorksV1ProjectValidationCode.unsupportedProjectDate);
    }
    if (buildings.isEmpty) {
      errors.add(YorksV1ProjectValidationCode.missingBuilding);
    }
    if (buildings.any((building) => !building.isValid)) {
      errors.add(YorksV1ProjectValidationCode.invalidBuilding);
    }
    final buildingCodes = <String>{};
    if (buildings.any(
      (building) =>
          building.normalizedCode.isNotEmpty &&
          !buildingCodes.add(building.normalizedCode),
    )) {
      errors.add(YorksV1ProjectValidationCode.duplicateBuildingCode);
    }
    final memberAuthUsers = <String>{};
    if (initialMembers.any((member) {
      final authUserId = member.authUserId.trim();
      if (authUserId.isEmpty) return true;
      return !memberAuthUsers.add(authUserId);
    })) {
      errors.add(YorksV1ProjectValidationCode.duplicateMember);
    }
    if (initialMembers.any((member) => member.authUserId.trim().isEmpty)) {
      errors.add(YorksV1ProjectValidationCode.missingMemberAuthUserId);
    }
    if (parties.any((party) => party.name.trim().isEmpty)) {
      errors.add(YorksV1ProjectValidationCode.invalidProjectParty);
    }
    for (final kind in const [
      YorksV1ProjectPartyKind.client,
      YorksV1ProjectPartyKind.consultant,
      YorksV1ProjectPartyKind.mainContractor,
    ]) {
      if (parties.where((party) => party.kind == kind).length > 1) {
        errors.add(YorksV1ProjectValidationCode.duplicateProjectParty);
      }
    }
    if (_trimToNull(clientName) != null &&
        parties.any((party) => party.kind == YorksV1ProjectPartyKind.client)) {
      errors.add(YorksV1ProjectValidationCode.duplicateProjectParty);
    }
    if (attachments.any(
      (attachment) =>
          attachment.fileName.trim().isEmpty ||
          (attachment.sizeBytes != null && attachment.sizeBytes! < 0),
    )) {
      errors.add(YorksV1ProjectValidationCode.invalidAttachment);
    }
    return errors;
  }

  /// Client-side action availability for the creation-time exception. The RPC
  /// derives and enforces the same role rule from the authenticated claim.
  bool initialMembersAllowedFor(YorksV1Role role) {
    if (role == YorksV1Role.projectEngineer ||
        role.isGlobalProjectEngineer ||
        role == YorksV1Role.admin) {
      return true;
    }
    if (role != YorksV1Role.siteEngineer) return false;
    return initialMembers.length <= 1 &&
        initialMembers.every(
          (member) =>
              member.projectRole ==
              YorksV1ProjectMembershipRole.projectEngineer,
        );
  }

  Map<String, dynamic> toRpcPayload() {
    return {
      'project_ref': reference.trim(),
      'name': name.trim(),
      'job_contract_reference': _trimToNull(jobOrContractReference),
      'project_site': _trimToNull(siteLocation),
      'start_date': _dateOnly(startDate),
      'target_completion_date': _dateOnly(endDate),
      'notes': _trimToNull(notes),
      'parties': _partiesRpcJson(),
      'initial_members': [
        for (final member in initialMembers) member.toRpcJson(),
      ],
      'buildings': [for (final building in buildings) building.toRpcJson()],
      'attachments': [
        for (final attachment in attachments) attachment.toRpcJson(),
      ],
    };
  }

  Map<String, dynamic> _partiesRpcJson() {
    YorksV1ProjectPartyInput? partyFor(YorksV1ProjectPartyKind kind) {
      for (final party in parties) {
        if (party.kind == kind) return party;
      }
      if (kind == YorksV1ProjectPartyKind.client &&
          _trimToNull(clientName) != null) {
        return YorksV1ProjectPartyInput(
          kind: YorksV1ProjectPartyKind.client,
          name: clientName!,
          contactName: clientContactName,
          contactPhone: clientContactPhone,
          contactEmail: clientContactEmail,
          address: clientAddress,
        );
      }
      return null;
    }

    final client = partyFor(YorksV1ProjectPartyKind.client);
    final consultant = partyFor(YorksV1ProjectPartyKind.consultant);
    final mainContractor = partyFor(YorksV1ProjectPartyKind.mainContractor);
    return {
      if (client != null) 'client': client.toPartyRpcJson(),
      if (consultant != null) 'consultant': consultant.toPartyRpcJson(),
      if (mainContractor != null)
        'main_contractor': mainContractor.toPartyRpcJson(),
      'subcontractors': [
        for (final party in parties)
          if (party.kind == YorksV1ProjectPartyKind.subcontractor)
            party.toPartyRpcJson(),
      ],
      'other_contractors': [
        for (final party in parties)
          if (party.kind == YorksV1ProjectPartyKind.otherContractor)
            party.toPartyRpcJson(),
      ],
    };
  }
}

/// Typed input to `v1_assign_project_member`. A replacement/revocation is a
/// new dated history row; the RPC closes any prior current record atomically.
class YorksV1AssignProjectMemberInput {
  const YorksV1AssignProjectMemberInput({
    required this.idempotencyKey,
    required this.projectId,
    required this.memberAuthUserId,
    required this.projectRole,
    required this.expectedProjectVersion,
    required this.reason,
  });

  final String idempotencyKey;
  final String projectId;
  final String memberAuthUserId;
  final YorksV1ProjectMembershipRole projectRole;
  final int expectedProjectVersion;
  final String reason;

  Set<YorksV1ProjectValidationCode> validate() {
    final errors = <YorksV1ProjectValidationCode>{};
    if (idempotencyKey.trim().isEmpty) {
      errors.add(YorksV1ProjectValidationCode.missingIdempotencyKey);
    }
    if (projectId.trim().isEmpty) {
      errors.add(YorksV1ProjectValidationCode.missingProjectId);
    }
    if (memberAuthUserId.trim().isEmpty) {
      errors.add(YorksV1ProjectValidationCode.missingMemberAuthUserId);
    }
    if (expectedProjectVersion < 0) {
      errors.add(YorksV1ProjectValidationCode.invalidVersion);
    }
    if (reason.trim().isEmpty) {
      errors.add(YorksV1ProjectValidationCode.missingMembershipReason);
    }
    return errors;
  }

  Map<String, dynamic> toRpcPayload() => {
    'project_id': projectId.trim(),
    'member_auth_user_id': memberAuthUserId.trim(),
    'project_role': projectRole.wireValue,
    'expected_version': expectedProjectVersion,
    'reason': reason.trim(),
  };
}

/// Typed input to `v1_revoke_project_member`. Revocation closes the current
/// dated membership record; it never deletes the historical assignment.
class YorksV1RevokeProjectMemberInput {
  const YorksV1RevokeProjectMemberInput({
    required this.idempotencyKey,
    required this.projectId,
    required this.memberAuthUserId,
    required this.projectRole,
    required this.expectedProjectVersion,
    required this.reason,
  });

  final String idempotencyKey;
  final String projectId;
  final String memberAuthUserId;
  final YorksV1ProjectMembershipRole projectRole;
  final int expectedProjectVersion;
  final String reason;

  Set<YorksV1ProjectValidationCode> validate() {
    final errors = <YorksV1ProjectValidationCode>{};
    if (idempotencyKey.trim().isEmpty) {
      errors.add(YorksV1ProjectValidationCode.missingIdempotencyKey);
    }
    if (projectId.trim().isEmpty) {
      errors.add(YorksV1ProjectValidationCode.missingProjectId);
    }
    if (memberAuthUserId.trim().isEmpty) {
      errors.add(YorksV1ProjectValidationCode.missingMemberAuthUserId);
    }
    if (expectedProjectVersion < 0) {
      errors.add(YorksV1ProjectValidationCode.invalidVersion);
    }
    if (reason.trim().isEmpty) {
      errors.add(YorksV1ProjectValidationCode.missingMembershipReason);
    }
    return errors;
  }

  Map<String, dynamic> toRpcPayload() => {
    'project_id': projectId.trim(),
    'member_auth_user_id': memberAuthUserId.trim(),
    'project_role': projectRole.wireValue,
    'expected_version': expectedProjectVersion,
    'reason': reason.trim(),
  };
}

/// Typed input to `v1_set_project_state`. The expected current state is used
/// only for immediate client validation; the stored row remains the authority.
class YorksV1SetProjectStateInput {
  const YorksV1SetProjectStateInput({
    required this.idempotencyKey,
    required this.projectId,
    required this.currentState,
    required this.targetState,
    required this.expectedProjectVersion,
    this.reason,
  });

  final String idempotencyKey;
  final String projectId;
  final YorksV1ProjectLifecycle currentState;
  final YorksV1ProjectLifecycle targetState;
  final int expectedProjectVersion;
  final String? reason;

  Set<YorksV1ProjectValidationCode> validate() {
    final errors = <YorksV1ProjectValidationCode>{};
    if (idempotencyKey.trim().isEmpty) {
      errors.add(YorksV1ProjectValidationCode.missingIdempotencyKey);
    }
    if (projectId.trim().isEmpty) {
      errors.add(YorksV1ProjectValidationCode.missingProjectId);
    }
    if (expectedProjectVersion < 0) {
      errors.add(YorksV1ProjectValidationCode.invalidVersion);
    }
    if (!currentState.canTransitionTo(targetState)) {
      errors.add(YorksV1ProjectValidationCode.invalidStateTransition);
    }
    if (currentState.requiresReasonFor(targetState) &&
        _trimToNull(reason) == null) {
      errors.add(YorksV1ProjectValidationCode.missingStateReason);
    }
    return errors;
  }

  Map<String, dynamic> toRpcPayload() => {
    'project_id': projectId.trim(),
    'state': targetState.wireValue,
    'expected_version': expectedProjectVersion,
    'reason': _trimToNull(reason),
  };
}

/// Typed input for the trusted project-setup update command. It intentionally
/// omits lifecycle and membership authority; team changes remain their own
/// dated assignment commands and project deletion is an Admin archive command.
class YorksV1ProjectUpdateInput {
  const YorksV1ProjectUpdateInput({
    required this.idempotencyKey,
    required this.projectId,
    required this.expectedProjectVersion,
    required this.project,
  });

  final String idempotencyKey;
  final String projectId;
  final int expectedProjectVersion;
  final YorksV1ProjectCreationInput project;

  Set<YorksV1ProjectValidationCode> validate() {
    final errors = <YorksV1ProjectValidationCode>{...project.validate()};
    if (projectId.trim().isEmpty) {
      errors.add(YorksV1ProjectValidationCode.missingProjectId);
    }
    if (expectedProjectVersion < 1) {
      errors.add(YorksV1ProjectValidationCode.invalidVersion);
    }
    return errors;
  }

  Map<String, dynamic> toRpcPayload() {
    final payload = project.toRpcPayload();
    return {
      'project_id': projectId.trim(),
      'expected_version': expectedProjectVersion,
      'project_ref': payload['project_ref'],
      'name': payload['name'],
      'job_contract_reference': payload['job_contract_reference'],
      'project_site': payload['project_site'],
      'start_date': payload['start_date'],
      'target_completion_date': payload['target_completion_date'],
      'notes': payload['notes'],
      'parties': payload['parties'],
      'buildings': [
        for (final building in project.buildings) building.toUpdateRpcJson(),
      ],
    };
  }
}

/// Typed input for Admin-only safe deletion. The server archives instead of
/// removing the project and blocks the command while operational requests are
/// still open.
class YorksV1ArchiveProjectInput {
  const YorksV1ArchiveProjectInput({
    required this.idempotencyKey,
    required this.projectId,
    required this.expectedProjectVersion,
    required this.reason,
  });

  final String idempotencyKey;
  final String projectId;
  final int expectedProjectVersion;
  final String reason;

  Set<YorksV1ProjectValidationCode> validate() {
    final errors = <YorksV1ProjectValidationCode>{};
    if (idempotencyKey.trim().isEmpty) {
      errors.add(YorksV1ProjectValidationCode.missingIdempotencyKey);
    }
    if (projectId.trim().isEmpty) {
      errors.add(YorksV1ProjectValidationCode.missingProjectId);
    }
    if (expectedProjectVersion < 1) {
      errors.add(YorksV1ProjectValidationCode.invalidVersion);
    }
    if (reason.trim().isEmpty) {
      errors.add(YorksV1ProjectValidationCode.missingStateReason);
    }
    return errors;
  }

  Map<String, dynamic> toRpcPayload() => {
    'project_id': projectId.trim(),
    'expected_version': expectedProjectVersion,
    'reason': reason.trim(),
  };
}

class YorksV1ProjectCreationResult {
  const YorksV1ProjectCreationResult({
    required this.project,
    required this.scopes,
    required this.members,
    required this.parties,
    required this.attachments,
    this.commonScopeId,
    this.idempotencyKey,
  });

  final YorksV1Project project;
  final List<YorksV1ProjectScope> scopes;
  final List<YorksV1ProjectMember> members;
  final List<YorksV1ProjectPartyInput> parties;
  final List<YorksV1ProjectAttachmentInput> attachments;
  final String? commonScopeId;
  final String? idempotencyKey;

  factory YorksV1ProjectCreationResult.fromRpcJson(Map<String, dynamic> json) {
    final projectJson = _nestedMapOrSelf(json, 'project');
    return YorksV1ProjectCreationResult(
      project: YorksV1Project.fromRpcJson(projectJson),
      scopes: _mapList(
        json['scopes'],
      ).map(YorksV1ProjectScope.fromRpcJson).toList(growable: false),
      members: _mapList(
        json['members'] ?? json['project_members'],
      ).map(YorksV1ProjectMember.fromRpcJson).toList(growable: false),
      parties: _partiesFromRpc(json['parties']),
      attachments: _mapList(json['attachments'])
          .map(YorksV1ProjectAttachmentInput.fromDraftJson)
          .toList(growable: false),
      commonScopeId: _nullableString(
        json['common_scope_id'] ?? json['commonScopeId'],
      ),
      idempotencyKey: _nullableString(
        json['idempotency_key'] ?? json['idempotencyKey'],
      ),
    );
  }
}

class YorksV1ProjectMembershipResult {
  const YorksV1ProjectMembershipResult({
    required this.project,
    required this.member,
    this.idempotencyKey,
  });

  final YorksV1Project project;
  final YorksV1ProjectMember member;
  final String? idempotencyKey;

  factory YorksV1ProjectMembershipResult.fromRpcJson(
    Map<String, dynamic> json,
  ) {
    return YorksV1ProjectMembershipResult(
      project: YorksV1Project.fromRpcJson(_nestedMapOrSelf(json, 'project')),
      member: YorksV1ProjectMember.fromRpcJson(_requiredMap(json, 'member')),
      idempotencyKey: _nullableString(
        json['idempotency_key'] ?? json['idempotencyKey'],
      ),
    );
  }
}

Map<String, dynamic> _nestedMapOrSelf(Map<String, dynamic> json, String key) {
  final nested = json[key];
  return nested is Map ? _mapFrom(nested) : json;
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String key) {
  final raw = json[key];
  if (raw is Map) return _mapFrom(raw);
  throw const YorksV1DomainException(YorksV1DomainErrorCode.unexpectedResponse);
}

Map<String, dynamic> _mapFrom(Map raw) => Map<String, dynamic>.from(raw);

Map<String, dynamic> _map(Object? raw) {
  if (raw is! Map) return const {};
  return Map<String, dynamic>.from(raw);
}

List<Map<String, dynamic>> _mapList(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map) _mapFrom(item),
  ];
}

List<YorksV1ProjectPartyInput> _partiesFromRpc(Object? raw) {
  if (raw is List) {
    final result = <YorksV1ProjectPartyInput>[];
    for (final party in _mapList(raw)) {
      final kind = YorksV1ProjectPartyKind.fromWireValue(
        party['party_kind'] ?? party['kind'],
      );
      if (kind != null) result.add(_partyFromRpc(kind, party));
    }
    return List.unmodifiable(result);
  }

  final parties = _map(raw);
  YorksV1ProjectPartyInput? single(YorksV1ProjectPartyKind kind, String key) {
    final value = parties[key];
    if (value is! Map) return null;
    return _partyFromRpc(kind, _mapFrom(value));
  }

  final client = single(YorksV1ProjectPartyKind.client, 'client');
  final consultant = single(YorksV1ProjectPartyKind.consultant, 'consultant');
  final mainContractor = single(
    YorksV1ProjectPartyKind.mainContractor,
    'main_contractor',
  );
  final result = <YorksV1ProjectPartyInput>[];
  if (client != null) result.add(client);
  if (consultant != null) result.add(consultant);
  if (mainContractor != null) result.add(mainContractor);
  result.addAll([
    for (final item in _mapList(parties['subcontractors']))
      _partyFromRpc(YorksV1ProjectPartyKind.subcontractor, item),
    for (final item in _mapList(parties['other_contractors']))
      _partyFromRpc(YorksV1ProjectPartyKind.otherContractor, item),
  ]);
  return List.unmodifiable(result);
}

YorksV1ProjectPartyInput _partyFromRpc(
  YorksV1ProjectPartyKind kind,
  Map<String, dynamic> json,
) {
  return YorksV1ProjectPartyInput(
    kind: kind,
    name: json['name'] as String? ?? json['party_name'] as String? ?? '',
    contactName: _nullableString(json['contact_name'] ?? json['contactName']),
    contactPhone: _nullableString(
      json['contact_phone'] ?? json['contactPhone'],
    ),
    contactEmail: _nullableString(
      json['contact_email'] ?? json['contactEmail'],
    ),
    address: _nullableString(json['address']),
  );
}

String _requiredString(
  Map<String, dynamic> json,
  String key, {
  String? fallback,
}) {
  final value = json[key] ?? (fallback == null ? null : json[fallback]);
  if (value is String && value.trim().isNotEmpty) return value;
  throw const YorksV1DomainException(YorksV1DomainErrorCode.unexpectedResponse);
}

String? _nullableString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _trimToNull(String? value) => _nullableString(value);

DateTime _requiredDate(
  Map<String, dynamic> json,
  String key, {
  String? fallback,
}) {
  final value = json[key] ?? (fallback == null ? null : json[fallback]);
  final date = _nullableDate(value);
  if (date != null) return date;
  throw const YorksV1DomainException(YorksV1DomainErrorCode.unexpectedResponse);
}

DateTime? _nullableDate(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  final text = value.trim();
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  // PostgreSQL `date` values are calendar values, not instants. Converting a
  // date-only value to UTC can move it to the previous local calendar day and
  // later re-submit the wrong project date.
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return parsed;
  return parsed.toUtc();
}

int _nonNegativeInt(Object? value) {
  final parsed = switch (value) {
    int value => value,
    num value => value.toInt(),
    String value => int.tryParse(value),
    _ => null,
  };
  if (parsed != null && parsed >= 0) return parsed;
  throw const YorksV1DomainException(YorksV1DomainErrorCode.unexpectedResponse);
}

bool _bool(Object? value, {required bool defaultValue}) =>
    value is bool ? value : defaultValue;

List<String> _strings(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}

String? _dateOnly(DateTime? value) {
  if (value == null) return null;
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

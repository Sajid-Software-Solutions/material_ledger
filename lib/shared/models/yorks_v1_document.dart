import 'dart:typed_data';

import 'yorks_v1_domain_error.dart';

enum YorksV1DocumentClassification {
  operational('operational'),
  commercial('commercial'),
  adminRestricted('admin_restricted');

  const YorksV1DocumentClassification(this.wireValue);

  final String wireValue;

  static YorksV1DocumentClassification? fromWireValue(Object? value) {
    if (value is! String) return null;
    for (final classification in values) {
      if (classification.wireValue == value) return classification;
    }
    return null;
  }
}

enum YorksV1DocumentEntityType {
  project('project'),
  boqGroup('boq_group'),
  materialRequest('material_request'),
  dispatch('dispatch'),
  receiptReview('receipt_review'),
  materialReturn('material_return'),
  deliveryOrder('delivery_order'),
  rentalProperty('rental_property'),
  supplier('supplier'),
  supplierReceiptBatch('supplier_receipt_batch'),
  accountsBaselineRevision('accounts_baseline_revision'),
  accountsBillingProgressRevision('accounts_billing_progress_revision'),
  accountsClientClaim('accounts_client_claim'),
  accountsClientInvoice('accounts_client_invoice'),
  accountsClientCertification('accounts_client_certification'),
  accountsClientPayment('accounts_client_payment'),
  accountsClientPdc('accounts_client_pdc'),
  accountsSupplierBill('accounts_supplier_bill'),
  accountsSupplierMatch('accounts_supplier_match');

  const YorksV1DocumentEntityType(this.wireValue);

  final String wireValue;

  static YorksV1DocumentEntityType? fromWireValue(Object? value) {
    if (value is! String) return null;
    for (final entityType in values) {
      if (entityType.wireValue == value) return entityType;
    }
    return null;
  }
}

enum YorksV1AccountsDocumentType {
  contract('contract'),
  contractVariation('contract_variation'),
  progressEvidence('progress_evidence'),
  clientClaim('client_claim'),
  clientInvoice('client_invoice'),
  clientCertification('client_certification'),
  paymentCertificate('payment_certificate'),
  pdcCopy('pdc_copy'),
  paymentReceipt('payment_receipt'),
  supplierInvoice('supplier_invoice'),
  poLpo('po_lpo'),
  deliveryReceipt('delivery_receipt'),
  paymentAdvice('payment_advice'),
  commercialCorrespondence('commercial_correspondence'),
  other('other');

  const YorksV1AccountsDocumentType(this.wireValue);

  final String wireValue;

  static YorksV1AccountsDocumentType? fromWireValue(Object? value) {
    if (value is! String) return null;
    for (final type in values) {
      if (type.wireValue == value) return type;
    }
    return null;
  }
}

enum YorksV1DocumentOrigin {
  uploaded('uploaded'),
  generated('generated');

  const YorksV1DocumentOrigin(this.wireValue);

  final String wireValue;

  static YorksV1DocumentOrigin? fromWireValue(Object? value) {
    if (value is! String) return null;
    for (final origin in values) {
      if (origin.wireValue == value) return origin;
    }
    return null;
  }
}

/// Controlled business identity for evidence stored inside a Supplier folder.
///
/// This is intentionally separate from MIME type and document classification:
/// MIME describes the file, classification controls authorization, and this
/// value describes the supplier business record represented by the file.
enum YorksV1SupplierDocumentType {
  deliveryNote('delivery_note'),
  invoice('invoice'),
  packingList('packing_list'),
  productDataSheet('product_data_sheet'),
  other('other');

  const YorksV1SupplierDocumentType(this.wireValue);

  final String wireValue;

  bool get requiresBusinessReference => this == deliveryNote || this == invoice;

  static YorksV1SupplierDocumentType? fromWireValue(Object? value) {
    if (value is! String) return null;
    for (final type in values) {
      if (type.wireValue == value) return type;
    }
    return null;
  }
}

class YorksV1DocumentVersion {
  const YorksV1DocumentVersion({
    required this.id,
    required this.revisionNumber,
    required this.bucketId,
    required this.objectPath,
    required this.fileName,
    required this.mimeType,
    required this.byteSize,
    required this.sha256,
    required this.origin,
    required this.uploadedAt,
    required this.uploadedByAuthUserId,
    required this.uploadedByRole,
    required this.uploadedByDisplayName,
    this.sourceEntityType,
    this.sourceEntityId,
    this.sourceRevision,
    this.supplierDocumentType,
    this.businessReference,
    this.supplierDocumentNotes,
  });

  final String id;
  final int revisionNumber;
  final String bucketId;
  final String objectPath;
  final String fileName;
  final String mimeType;
  final int byteSize;
  final String sha256;
  final YorksV1DocumentOrigin origin;
  final DateTime uploadedAt;
  final String uploadedByAuthUserId;
  final String uploadedByRole;
  final String uploadedByDisplayName;
  final YorksV1DocumentEntityType? sourceEntityType;
  final String? sourceEntityId;
  final String? sourceRevision;
  final YorksV1SupplierDocumentType? supplierDocumentType;
  final String? businessReference;
  final String? supplierDocumentNotes;

  factory YorksV1DocumentVersion.fromRpcJson(Map<String, dynamic> json) {
    final origin = YorksV1DocumentOrigin.fromWireValue(json['origin']);
    final rawSupplierDocumentType = json['supplier_document_type'];
    final supplierDocumentType = YorksV1SupplierDocumentType.fromWireValue(
      rawSupplierDocumentType,
    );
    final businessReference = _nullableString(json['business_reference']);
    final supplierDocumentNotes = _nullableString(
      json['supplier_document_notes'],
    );
    if (origin == null) _unexpected();
    if ((rawSupplierDocumentType != null && supplierDocumentType == null) ||
        (supplierDocumentType == null &&
            (businessReference != null || supplierDocumentNotes != null)) ||
        (supplierDocumentType?.requiresBusinessReference ?? false) &&
            businessReference == null) {
      _unexpected();
    }
    return YorksV1DocumentVersion(
      id: _requiredString(json, 'id'),
      revisionNumber: _positiveInt(json['revision_number']),
      bucketId: _requiredString(json, 'bucket_id'),
      objectPath: _requiredString(json, 'object_path'),
      fileName: _requiredString(json, 'original_file_name'),
      mimeType: _requiredString(json, 'mime_type'),
      byteSize: _positiveInt(json['byte_size']),
      sha256: _requiredString(json, 'sha256'),
      origin: origin,
      uploadedAt: _requiredDate(json, 'uploaded_at'),
      uploadedByAuthUserId: _requiredString(json, 'uploaded_by_auth_user_id'),
      uploadedByRole: _requiredString(json, 'uploaded_by_role'),
      uploadedByDisplayName: _requiredString(json, 'uploaded_by_display_name'),
      sourceEntityType: YorksV1DocumentEntityType.fromWireValue(
        json['source_entity_type'],
      ),
      sourceEntityId: _nullableString(json['source_entity_id']),
      sourceRevision: _nullableString(json['source_revision']),
      supplierDocumentType: supplierDocumentType,
      businessReference: businessReference,
      supplierDocumentNotes: supplierDocumentNotes,
    );
  }
}

class YorksV1DocumentLink {
  const YorksV1DocumentLink({
    required this.id,
    required this.projectId,
    required this.entityType,
    required this.entityId,
    required this.linkedAt,
    this.crossProjectReason,
  });

  final String id;
  final String projectId;
  final YorksV1DocumentEntityType entityType;
  final String entityId;
  final DateTime linkedAt;
  final String? crossProjectReason;

  factory YorksV1DocumentLink.fromRpcJson(Map<String, dynamic> json) {
    final entityType = YorksV1DocumentEntityType.fromWireValue(
      json['entity_type'],
    );
    if (entityType == null) _unexpected();
    return YorksV1DocumentLink(
      id: _requiredString(json, 'id'),
      projectId: _requiredString(json, 'project_id'),
      entityType: entityType,
      entityId: _requiredString(json, 'entity_id'),
      linkedAt: _requiredDate(json, 'linked_at'),
      crossProjectReason: _nullableString(json['cross_project_reason']),
    );
  }
}

class YorksV1Document {
  const YorksV1Document({
    required this.id,
    required this.classification,
    required this.createdAt,
    required this.currentVersion,
    required this.links,
    this.versions = const [],
    this.accountsDocumentType,
    this.isArchived = false,
  });

  final String id;
  final YorksV1DocumentClassification classification;
  final DateTime createdAt;
  final YorksV1DocumentVersion currentVersion;
  final List<YorksV1DocumentLink> links;
  final List<YorksV1DocumentVersion> versions;
  final YorksV1AccountsDocumentType? accountsDocumentType;
  final bool isArchived;

  factory YorksV1Document.fromRpcJson(Map<String, dynamic> json) {
    final classification = YorksV1DocumentClassification.fromWireValue(
      json['classification'],
    );
    final version = _jsonObject(json['current_version']);
    if (classification == null || version == null) _unexpected();
    final currentVersion = YorksV1DocumentVersion.fromRpcJson(version);
    if (currentVersion.supplierDocumentType ==
            YorksV1SupplierDocumentType.invoice &&
        classification != YorksV1DocumentClassification.commercial) {
      _unexpected();
    }
    final rawAccountsType = json['accounts_document_type'];
    final accountsType = YorksV1AccountsDocumentType.fromWireValue(
      rawAccountsType,
    );
    if (rawAccountsType != null && accountsType == null) _unexpected();
    final versions = json.containsKey('versions')
        ? _jsonList(
            json['versions'],
          ).map(YorksV1DocumentVersion.fromRpcJson).toList(growable: false)
        : <YorksV1DocumentVersion>[currentVersion];
    return YorksV1Document(
      id: _requiredString(json, 'id'),
      classification: classification,
      createdAt: _requiredDate(json, 'created_at'),
      currentVersion: currentVersion,
      links: _jsonList(
        json['links'],
      ).map(YorksV1DocumentLink.fromRpcJson).toList(growable: false),
      versions: versions,
      accountsDocumentType: accountsType,
      isArchived: json['archived'] == true,
    );
  }

  bool isLinkedTo(YorksV1DocumentEntityType type, String entityId) =>
      links.any((link) => link.entityType == type && link.entityId == entityId);
}

class YorksV1AccountsDocumentTarget {
  const YorksV1AccountsDocumentTarget({
    required this.entityType,
    required this.entityId,
    required this.label,
  });

  final YorksV1DocumentEntityType entityType;
  final String entityId;
  final String label;

  factory YorksV1AccountsDocumentTarget.fromRpcJson(Map<String, dynamic> json) {
    final entityType = YorksV1DocumentEntityType.fromWireValue(
      json['entity_type'],
    );
    if (entityType == null || !entityType.wireValue.startsWith('accounts_')) {
      _unexpected();
    }
    return YorksV1AccountsDocumentTarget(
      entityType: entityType,
      entityId: _requiredString(json, 'entity_id'),
      label: _requiredString(json, 'label'),
    );
  }
}

class YorksV1AccountsDocumentWorkspace {
  const YorksV1AccountsDocumentWorkspace({
    required this.projectId,
    required this.documents,
    required this.uploadTargets,
    required this.canUpload,
  });

  final String projectId;
  final List<YorksV1Document> documents;
  final List<YorksV1AccountsDocumentTarget> uploadTargets;
  final bool canUpload;

  factory YorksV1AccountsDocumentWorkspace.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksV1AccountsDocumentWorkspace(
    projectId: _requiredString(json, 'project_id'),
    documents: _jsonList(
      json['documents'],
    ).map(YorksV1Document.fromRpcJson).toList(growable: false),
    uploadTargets: _jsonList(
      json['upload_targets'],
    ).map(YorksV1AccountsDocumentTarget.fromRpcJson).toList(growable: false),
    canUpload: json['can_upload'] == true,
  );
}

class YorksV1AuditEvent {
  const YorksV1AuditEvent({
    required this.id,
    required this.eventType,
    required this.entityType,
    required this.entityId,
    required this.occurredAt,
    required this.actorAuthUserId,
    required this.actorDisplayName,
    required this.actorRole,
    this.reason,
  });

  final String id;
  final String eventType;
  final String entityType;
  final String entityId;
  final DateTime occurredAt;
  final String actorAuthUserId;
  final String actorDisplayName;
  final String actorRole;
  final String? reason;

  factory YorksV1AuditEvent.fromRpcJson(Map<String, dynamic> json) =>
      YorksV1AuditEvent(
        id: _requiredString(json, 'id'),
        eventType: _requiredString(json, 'event_type'),
        entityType: _requiredString(json, 'entity_type'),
        entityId: _requiredString(json, 'entity_id'),
        occurredAt: _requiredDate(json, 'occurred_at'),
        actorAuthUserId: _requiredString(json, 'actor_auth_user_id'),
        actorDisplayName: _requiredString(json, 'actor_display_name'),
        actorRole: _requiredString(json, 'actor_role'),
        reason: _nullableString(json['reason']),
      );
}

class YorksV1DocumentWorkspace {
  const YorksV1DocumentWorkspace({
    required this.projectId,
    required this.documents,
    required this.auditEntries,
  });

  final String projectId;
  final List<YorksV1Document> documents;
  final List<YorksV1AuditEvent> auditEntries;

  factory YorksV1DocumentWorkspace.fromRpcJson(Map<String, dynamic> json) =>
      YorksV1DocumentWorkspace(
        projectId: _requiredString(json, 'project_id'),
        documents: _jsonList(
          json['documents'],
        ).map(YorksV1Document.fromRpcJson).toList(growable: false),
        auditEntries: _jsonList(
          json['audit_entries'],
        ).map(YorksV1AuditEvent.fromRpcJson).toList(growable: false),
      );
}

class YorksV1DocumentUploadIntent {
  const YorksV1DocumentUploadIntent({
    required this.id,
    required this.bucketId,
    required this.objectPath,
    required this.mimeType,
    required this.byteSize,
    required this.expiresAt,
    required this.plannedRevisionNumber,
    this.finalizedDocumentId,
    this.finalizedVersionId,
  });

  final String id;
  final String bucketId;
  final String objectPath;
  final String mimeType;
  final int byteSize;
  final DateTime expiresAt;
  final int plannedRevisionNumber;
  final String? finalizedDocumentId;
  final String? finalizedVersionId;

  factory YorksV1DocumentUploadIntent.fromRpcJson(Map<String, dynamic> json) {
    final plannedRevision = _positiveInt(json['planned_revision_number']);
    final finalizedDocumentId = json['finalized_document_id'] == null
        ? null
        : _requiredString(json, 'finalized_document_id');
    final finalizedVersionId = json['finalized_version_id'] == null
        ? null
        : _requiredString(json, 'finalized_version_id');
    if ((finalizedDocumentId == null) != (finalizedVersionId == null)) {
      _unexpected();
    }

    String? retainedDocumentId;
    String? retainedVersionId;
    if ([
      'document_id',
      'document_version_id',
      'revision_number',
    ].any(json.containsKey)) {
      // The service-only finalizer appends this exact receipt to the original
      // prepare response. Recognize it before attempting another immutable
      // Storage insert, which is no longer permitted after finalization.
      retainedDocumentId = _requiredString(json, 'document_id');
      retainedVersionId = _requiredString(json, 'document_version_id');
      final revision = json['revision_number'];
      if (json['planned_revision_number'] is! int ||
          revision is! int ||
          revision != plannedRevision) {
        _unexpected();
      }
      if (finalizedDocumentId != null &&
          (finalizedDocumentId != retainedDocumentId ||
              finalizedVersionId != retainedVersionId)) {
        _unexpected();
      }
    }

    return YorksV1DocumentUploadIntent(
      id: _requiredString(json, 'upload_intent_id'),
      bucketId: _requiredString(json, 'bucket_id'),
      objectPath: _requiredString(json, 'object_path'),
      mimeType: _requiredString(json, 'mime_type'),
      byteSize: _positiveInt(json['byte_size']),
      expiresAt: _requiredDate(json, 'expires_at'),
      plannedRevisionNumber: plannedRevision,
      finalizedDocumentId: retainedDocumentId ?? finalizedDocumentId,
      finalizedVersionId: retainedVersionId ?? finalizedVersionId,
    );
  }
}

class YorksV1DocumentUploadInput {
  const YorksV1DocumentUploadInput({
    required this.projectId,
    required this.entityType,
    required this.entityId,
    required this.classification,
    required this.fileName,
    required this.mimeType,
    required this.bytes,
    required this.idempotencyKey,
    this.documentId,
    this.origin = YorksV1DocumentOrigin.uploaded,
    this.sourceEntityType,
    this.sourceEntityId,
    this.sourceRevision,
    this.supplierDocumentType,
    this.businessReference,
    this.supplierDocumentNotes,
    this.accountsDocumentType,
  });

  final String projectId;
  final YorksV1DocumentEntityType entityType;
  final String entityId;
  final YorksV1DocumentClassification classification;
  final String fileName;
  final String mimeType;
  final Uint8List bytes;
  final String idempotencyKey;
  final String? documentId;
  final YorksV1DocumentOrigin origin;
  final YorksV1DocumentEntityType? sourceEntityType;
  final String? sourceEntityId;
  final String? sourceRevision;
  final YorksV1SupplierDocumentType? supplierDocumentType;
  final String? businessReference;
  final String? supplierDocumentNotes;
  final YorksV1AccountsDocumentType? accountsDocumentType;

  Map<String, Object?> toRpcPayload(String sha256) => {
    'project_id': projectId,
    'entity_type': entityType.wireValue,
    'entity_id': entityId,
    'document_id': _nullableString(documentId),
    'classification': classification.wireValue,
    'file_name': fileName.trim(),
    'mime_type': mimeType,
    'byte_size': bytes.lengthInBytes,
    'sha256': sha256,
    'origin': origin.wireValue,
    'source_entity_type': sourceEntityType?.wireValue,
    'source_entity_id': _nullableString(sourceEntityId),
    'source_revision': _nullableString(sourceRevision),
  };

  /// Supplier-only payload extension. Generic, project, and rental upload
  /// callers continue to use [toRpcPayload] and therefore never emit these
  /// business-metadata keys.
  Map<String, Object?> toSupplierRpcPayload(String sha256) => {
    ...toRpcPayload(sha256),
    'supplier_document_type': supplierDocumentType?.wireValue,
    'business_reference': _nullableString(businessReference),
    'supplier_document_notes': _nullableString(supplierDocumentNotes),
  };

  Map<String, Object?> toAccountsRpcPayload(String sha256) => {
    ...toRpcPayload(sha256),
    'accounts_document_type': accountsDocumentType?.wireValue,
  };
}

class YorksV1DocumentLinkInput {
  const YorksV1DocumentLinkInput({
    required this.documentId,
    required this.entityType,
    required this.entityId,
    required this.idempotencyKey,
    this.crossProjectReason,
  });

  final String documentId;
  final YorksV1DocumentEntityType entityType;
  final String entityId;
  final String idempotencyKey;
  final String? crossProjectReason;

  Map<String, Object?> toRpcPayload() => {
    'document_id': documentId,
    'entity_type': entityType.wireValue,
    'entity_id': entityId,
    'cross_project_reason': _nullableString(crossProjectReason),
  };
}

class YorksV1DocumentLinkRemovalInput {
  const YorksV1DocumentLinkRemovalInput({
    required this.documentLinkId,
    required this.reason,
    required this.idempotencyKey,
  });

  final String documentLinkId;
  final String reason;
  final String idempotencyKey;

  Map<String, Object?> toRpcPayload() => {
    'document_link_id': documentLinkId,
    'reason': reason.trim(),
  };
}

Never _unexpected() => throw const YorksV1DomainException(
  YorksV1DomainErrorCode.unexpectedResponse,
);

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _nullableString(json[key]);
  if (value == null) _unexpected();
  return value;
}

String? _nullableString(Object? value) {
  if (value is! String) return null;
  final result = value.trim();
  return result.isEmpty ? null : result;
}

int _positiveInt(Object? value) {
  final result = switch (value) {
    int value => value,
    num value => value.toInt(),
    String value => int.tryParse(value.trim()),
    _ => null,
  };
  if (result == null || result <= 0) _unexpected();
  return result;
}

DateTime _requiredDate(Map<String, dynamic> json, String key) {
  final raw = _nullableString(json[key]);
  final value = raw == null ? null : DateTime.tryParse(raw);
  if (value == null) _unexpected();
  return value.toLocal();
}

Map<String, dynamic>? _jsonObject(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

List<Map<String, dynamic>> _jsonList(Object? value) {
  if (value is! List) _unexpected();
  return [
    for (final item in value)
      if (item is Map) Map<String, dynamic>.from(item) else _unexpected(),
  ];
}

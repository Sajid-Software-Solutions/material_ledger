import 'yorks_v1_domain_error.dart';
import 'yorks_v1_quantity.dart';
import 'yorks_v1_material_request.dart';

/// The only source options in Yorks V1. Supplier text is intentionally a
/// lightweight external source; RFQ, quotation and PO flows are deferred.
enum YorksV1ArrangementSource {
  warehouse('warehouse'),
  externalSupplier('external_supplier');

  const YorksV1ArrangementSource(this.wireValue);
  final String wireValue;

  static YorksV1ArrangementSource fromWireValue(Object? value) =>
      switch (value) {
        'external_supplier' => YorksV1ArrangementSource.externalSupplier,
        _ => YorksV1ArrangementSource.warehouse,
      };
}

enum YorksV1ArrangementDecision {
  full('full'),
  partial('partial'),
  unavailable('unavailable');

  const YorksV1ArrangementDecision(this.wireValue);
  final String wireValue;

  static YorksV1ArrangementDecision? fromWireValue(Object? value) {
    if (value is! String) return null;
    for (final item in values) {
      if (item.wireValue == value) return item;
    }
    return null;
  }
}

/// Infers fulfilment only from a complete, valid quantity. Incomplete typing,
/// negatives and quantities over the approved need have no fulfilment status.
YorksV1ArrangementDecision? yorksV1ArrangementDecisionForQuantity({
  required String requestedQuantity,
  required String arrangedQuantity,
}) {
  final requested = YorksV1DecimalQuantity.tryParse(requestedQuantity);
  final arranged = YorksV1DecimalQuantity.tryParse(arrangedQuantity);
  if (requested == null ||
      !requested.isPositive ||
      arranged == null ||
      arranged.isNegative ||
      arranged.compareTo(requested) > 0) {
    return null;
  }
  if (arranged.isZero) return YorksV1ArrangementDecision.unavailable;
  return arranged == requested
      ? YorksV1ArrangementDecision.full
      : YorksV1ArrangementDecision.partial;
}

/// Only one exact operational match may be selected automatically. Stock is
/// not identity: an out-of-stock match remains a real warehouse item.
YorksV1InventoryItem? yorksV1ArrangementInventoryMatch(
  YorksV1ArrangementLine line,
  List<YorksV1InventoryItem> inventory,
) {
  String normalized(String? value) =>
      (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final matches = inventory
      .where(
        (item) =>
            normalized(item.unit) == normalized(line.unit) &&
            normalized(item.description) == normalized(line.description) &&
            (normalized(line.brandOrigin).isEmpty ||
                normalized(item.brandOrigin) == normalized(line.brandOrigin)),
      )
      .toList();
  return matches.length == 1 ? matches.single : null;
}

enum YorksV1ArrangementStatus {
  working('working'),
  awaitingApproval('awaiting_approval'),
  approved('approved'),
  returned('returned'),
  superseded('superseded'),
  cancelled('cancelled');

  const YorksV1ArrangementStatus(this.wireValue);
  final String wireValue;

  static YorksV1ArrangementStatus? fromWireValue(Object? value) {
    if (value is! String) return null;
    for (final item in values) {
      if (item.wireValue == value) return item;
    }
    return null;
  }
}

enum YorksV1ArrangementReviewDecision {
  approved('approved'),
  returned('returned');

  const YorksV1ArrangementReviewDecision(this.wireValue);
  final String wireValue;
}

/// Operational warehouse context only. It carries no cost, supplier commercial
/// record or movement ledger data and is exposed solely to Procurement/Admin.
class YorksV1InventoryItem {
  const YorksV1InventoryItem({
    required this.id,
    required this.description,
    required this.unit,
    required this.onHandQuantity,
    required this.reservedQuantity,
    required this.availableQuantity,
    required this.recordVersion,
    this.itemCode,
    this.brandOrigin,
    this.locationBin,
  });

  final String id;
  final String? itemCode;
  final String description;
  final String? brandOrigin;
  final String? locationBin;
  final String unit;
  final String onHandQuantity;
  final String reservedQuantity;
  final String availableQuantity;
  final int recordVersion;

  factory YorksV1InventoryItem.fromRpcJson(Map<String, dynamic> json) {
    return YorksV1InventoryItem(
      id: _requiredString(json, 'id'),
      itemCode: _trimToNull(json['item_code']),
      description: _requiredString(json, 'item_description'),
      brandOrigin: _trimToNull(json['brand_origin']),
      locationBin: _trimToNull(json['location_bin']),
      unit: _requiredString(json, 'unit'),
      onHandQuantity: _string(json['on_hand_qty']),
      reservedQuantity: _string(json['reserved_qty']),
      availableQuantity: _string(json['available_qty']),
      recordVersion: _positiveInt(json['record_version']),
    );
  }
}

class YorksV1ArrangementLine {
  const YorksV1ArrangementLine({
    required this.id,
    required this.requestLineId,
    required this.displayOrder,
    required this.description,
    required this.requestedQuantity,
    required this.unit,
    required this.source,
    this.brandOrigin,
    this.requestedDescription,
    this.modelReference,
    this.requestedModelReference,
    this.procurementClarificationVersion = 0,
    this.procurementClarifiedAt,
    this.procurementClarifiedByDisplayName,
    this.externalSupplier,
    this.externalSourceReady = false,
    this.externalExpectedDate,
    this.externalReference,
    this.decision,
    this.arrangedQuantity,
    this.reason,
    this.unitCost,
    this.inventoryItemId,
    this.inventoryItemDescription,
    this.warehouseAvailableAtSave,
    this.reservationState,
    this.reservedQuantity,
    this.requestSourceKind,
    this.sourceBoqGroupId,
    this.sourceBoqRowId,
    this.sourceBoqGroupName,
    this.sourceScopeName,
  });

  final String id;
  final String requestLineId;
  final int displayOrder;
  final String description;
  final String? brandOrigin;
  final String? requestedDescription;
  final String? modelReference;
  final String? requestedModelReference;
  final int procurementClarificationVersion;
  final DateTime? procurementClarifiedAt;
  final String? procurementClarifiedByDisplayName;
  final String requestedQuantity;
  final String unit;
  final YorksV1ArrangementSource source;
  final String? externalSupplier;
  final bool externalSourceReady;
  final DateTime? externalExpectedDate;
  final String? externalReference;
  final YorksV1ArrangementDecision? decision;
  final String? arrangedQuantity;
  final String? reason;

  /// Procurement-only commercial input. The database deliberately omits this
  /// field from non-commercial arrangement projections.
  final String? unitCost;
  final String? inventoryItemId;
  final String? inventoryItemDescription;
  final String? warehouseAvailableAtSave;
  final String? reservationState;
  final String? reservedQuantity;

  /// Immutable request-line provenance. This is descriptive correlation only:
  /// Procurement still chooses the actual warehouse item or external source,
  /// and the server validates stock only when the arrangement is saved.
  final String? requestSourceKind;
  final String? sourceBoqGroupId;
  final String? sourceBoqRowId;
  final String? sourceBoqGroupName;
  final String? sourceScopeName;

  bool get isBoqCorrelated =>
      requestSourceKind == 'boq' && sourceBoqRowId != null;

  bool get wasProcurementClarified =>
      procurementClarificationVersion > 0 ||
      description.trim() != (requestedDescription ?? description).trim() ||
      (modelReference ?? '').trim() !=
          (requestedModelReference ?? modelReference ?? '').trim();

  factory YorksV1ArrangementLine.fromRpcJson(Map<String, dynamic> json) {
    return YorksV1ArrangementLine(
      id: _requiredString(json, 'id'),
      requestLineId: _requiredString(json, 'request_line_id'),
      displayOrder: _positiveInt(json['display_order']),
      description: _requiredString(json, 'item_description'),
      brandOrigin: _trimToNull(json['brand_origin']),
      requestedDescription: _trimToNull(json['requested_item_description']),
      modelReference: _trimToNull(json['model_reference']),
      requestedModelReference: _trimToNull(json['requested_model_reference']),
      procurementClarificationVersion: _nonNegativeInt(
        json['procurement_clarification_version'],
      ),
      procurementClarifiedAt: _nullableDate(json['procurement_clarified_at']),
      procurementClarifiedByDisplayName: _trimToNull(
        json['procurement_clarified_by_display_name'],
      ),
      requestedQuantity: _string(json['requested_qty']),
      unit: _requiredString(json, 'unit'),
      source: YorksV1ArrangementSource.fromWireValue(json['source_kind']),
      externalSupplier: _trimToNull(json['external_supplier']),
      externalSourceReady: json['external_source_ready'] == true,
      externalExpectedDate: _nullableDate(json['external_expected_date']),
      externalReference: _trimToNull(json['external_reference']),
      decision: YorksV1ArrangementDecision.fromWireValue(json['decision']),
      arrangedQuantity: _trimToNull(json['arranged_qty']),
      reason: _trimToNull(json['reason']),
      unitCost: _trimToNull(json['unit_cost']),
      inventoryItemId: _trimToNull(json['inventory_item_id']),
      inventoryItemDescription: _trimToNull(json['inventory_item_description']),
      warehouseAvailableAtSave: _trimToNull(
        json['warehouse_available_at_save'],
      ),
      reservationState: _trimToNull(json['reservation_state']),
      reservedQuantity: _trimToNull(json['reserved_qty']),
      requestSourceKind: _trimToNull(json['request_source_kind']),
      sourceBoqGroupId: _trimToNull(json['source_boq_group_id']),
      sourceBoqRowId: _trimToNull(json['source_boq_row_id']),
      sourceBoqGroupName: _trimToNull(json['source_boq_group_name']),
      sourceScopeName: _trimToNull(json['source_scope_name']),
    );
  }
}

class YorksV1ProcurementArrangement {
  YorksV1ProcurementArrangement({
    required this.id,
    required this.version,
    required this.status,
    required this.isCurrent,
    required this.recordVersion,
    required this.startedByDisplayName,
    required this.startedAt,
    required List<YorksV1ArrangementLine> lines,
    this.savedAt,
    this.savedByDisplayName,
    this.reviewDecision,
    this.reviewReason,
    this.decidedByDisplayName,
    this.decidedByRole,
    this.decidedAt,
    this.procurementNote,
  }) : lines = List.unmodifiable(lines);

  final String id;
  final int version;
  final YorksV1ArrangementStatus status;
  final bool isCurrent;
  final int recordVersion;
  final String startedByDisplayName;
  final DateTime startedAt;
  final DateTime? savedAt;
  final String? savedByDisplayName;
  final YorksV1ArrangementReviewDecision? reviewDecision;
  final String? reviewReason;
  final String? decidedByDisplayName;
  final String? decidedByRole;
  final DateTime? decidedAt;

  /// Procurement-only overall arrangement context; never inferred from lines.
  final String? procurementNote;
  final List<YorksV1ArrangementLine> lines;

  factory YorksV1ProcurementArrangement.fromRpcJson(Map<String, dynamic> json) {
    final status = YorksV1ArrangementStatus.fromWireValue(json['status']);
    if (status == null || json['lines'] is! List) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    final reviewDecision = switch (json['decision']) {
      'approved' => YorksV1ArrangementReviewDecision.approved,
      'returned' => YorksV1ArrangementReviewDecision.returned,
      _ => null,
    };
    return YorksV1ProcurementArrangement(
      id: _requiredString(json, 'id'),
      version: _positiveInt(json['arrangement_version']),
      status: status,
      isCurrent: json['is_current'] == true,
      recordVersion: _positiveInt(json['record_version']),
      startedByDisplayName: _requiredString(json, 'started_by_display_name'),
      startedAt: _requiredDate(json, 'started_at'),
      savedAt: _nullableDate(json['saved_at']),
      savedByDisplayName: _trimToNull(json['saved_by_display_name']),
      reviewDecision: reviewDecision,
      reviewReason: _trimToNull(json['decision_reason']),
      decidedByDisplayName: _trimToNull(json['decided_by_display_name']),
      decidedByRole: _trimToNull(json['decided_by_role']),
      decidedAt: _nullableDate(json['decided_at']),
      procurementNote: _trimToNull(json['procurement_note']),
      lines: [
        for (final line in json['lines'] as List)
          if (line is Map)
            YorksV1ArrangementLine.fromRpcJson(Map<String, dynamic>.from(line)),
      ],
    );
  }
}

/// Role-safe view of the complete arrangement history for one Material Request.
class YorksV1ArrangementWorkspace {
  YorksV1ArrangementWorkspace({
    required this.requestId,
    required this.requestState,
    required this.requestRecordVersion,
    required this.canBegin,
    required this.canSave,
    required this.canDecide,
    required List<YorksV1ProcurementArrangement> arrangements,
    this.externalSourceReadinessRequired = false,
    this.clarificationReviewRequired = false,
    this.canClarify = false,
    this.procurementClarificationRevision = 0,
    this.approvedProcurementClarificationRevision = 0,
    this.requestNumber,
    this.timing = YorksV1MaterialRequestTiming.normal,
    this.scheduledDate,
  }) : arrangements = List.unmodifiable(arrangements);

  final String requestId;
  final String? requestNumber;
  final YorksV1MaterialRequestTiming timing;
  final DateTime? scheduledDate;
  final String requestState;
  final int requestRecordVersion;
  final bool canBegin;
  final bool canSave;
  final bool canDecide;
  final bool externalSourceReadinessRequired;
  final bool clarificationReviewRequired;
  final bool canClarify;
  final int procurementClarificationRevision;
  final int approvedProcurementClarificationRevision;
  final List<YorksV1ProcurementArrangement> arrangements;

  YorksV1ProcurementArrangement? get workingArrangement {
    for (final arrangement in arrangements) {
      if (arrangement.status == YorksV1ArrangementStatus.working) {
        return arrangement;
      }
    }
    return null;
  }

  YorksV1ProcurementArrangement? get currentArrangement {
    for (final arrangement in arrangements) {
      if (arrangement.isCurrent) return arrangement;
    }
    return null;
  }

  factory YorksV1ArrangementWorkspace.fromRpcJson(Map<String, dynamic> json) {
    final rawArrangements = json['arrangements'];
    if (rawArrangements is! List) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1ArrangementWorkspace(
      requestId: _requiredString(json, 'request_id'),
      requestNumber: _trimToNull(json['request_number']),
      timing:
          YorksV1MaterialRequestTiming.fromWireValue(json['timing']) ??
          YorksV1MaterialRequestTiming.normal,
      scheduledDate: _nullableDate(json['scheduled_date']),
      requestState: _requiredString(json, 'request_state'),
      requestRecordVersion: _positiveInt(json['request_record_version']),
      canBegin: json['can_begin'] == true,
      canSave: json['can_save'] == true,
      canDecide: json['can_decide'] == true,
      externalSourceReadinessRequired:
          json['external_source_readiness_required'] == true,
      clarificationReviewRequired:
          json['clarification_review_required'] == true,
      canClarify: json['can_clarify'] == true,
      procurementClarificationRevision: _nonNegativeInt(
        json['procurement_clarification_revision'],
      ),
      approvedProcurementClarificationRevision: _nonNegativeInt(
        json['approved_procurement_clarification_revision'],
      ),
      arrangements: [
        for (final arrangement in rawArrangements)
          if (arrangement is Map)
            YorksV1ProcurementArrangement.fromRpcJson(
              Map<String, dynamic>.from(arrangement),
            ),
      ],
    );
  }
}

class YorksV1ArrangementLineInput {
  const YorksV1ArrangementLineInput({
    required this.arrangementLineId,
    required this.source,
    required this.decision,
    required this.arrangedQuantity,
    this.externalSupplier,
    this.externalSourceReady = false,
    this.externalExpectedDate,
    this.externalReference,
    this.inventoryItemId,
    this.reason,
    this.unitCost,
  });

  final String arrangementLineId;
  final YorksV1ArrangementSource source;
  final YorksV1ArrangementDecision decision;
  final String arrangedQuantity;
  final String? externalSupplier;
  final bool externalSourceReady;
  final String? externalExpectedDate;
  final String? externalReference;
  final String? inventoryItemId;
  final String? reason;
  final String? unitCost;

  Map<String, Object?> toRpcJson() => {
    'arrangement_line_id': arrangementLineId,
    'source_kind': source.wireValue,
    'external_supplier': _trimToNull(externalSupplier),
    'external_source_ready': externalSourceReady,
    'external_expected_date': _trimToNull(externalExpectedDate),
    'external_reference': _trimToNull(externalReference),
    'inventory_item_id': _trimToNull(inventoryItemId),
    'decision': decision.wireValue,
    'arranged_qty': arrangedQuantity.trim(),
    'reason': _trimToNull(reason),
    if (_trimToNull(unitCost) != null) 'unit_cost': _trimToNull(unitCost),
  };
}

class YorksV1BeginArrangementInput {
  const YorksV1BeginArrangementInput({
    required this.requestId,
    required this.expectedRequestVersion,
    required this.idempotencyKey,
  });

  final String requestId;
  final int expectedRequestVersion;
  final String idempotencyKey;

  Map<String, Object?> toRpcPayload() => {
    'request_id': requestId,
    'expected_version': expectedRequestVersion,
  };
}

class YorksV1UpdateProcurementMaterialItemInput {
  const YorksV1UpdateProcurementMaterialItemInput({
    required this.requestId,
    required this.requestLineId,
    required this.expectedRequestVersion,
    required this.itemDescription,
    required this.idempotencyKey,
    this.modelReference,
  });

  final String requestId;
  final String requestLineId;
  final int expectedRequestVersion;
  final String itemDescription;
  final String? modelReference;
  final String idempotencyKey;

  Map<String, Object?> toRpcPayload() => {
    'request_id': requestId,
    'request_line_id': requestLineId,
    'expected_request_version': expectedRequestVersion,
    'item_description': itemDescription.trim(),
    'model_reference': _trimToNull(modelReference),
  };
}

class YorksV1SaveArrangementInput {
  YorksV1SaveArrangementInput({
    required this.requestId,
    required this.arrangementId,
    required this.expectedRequestVersion,
    required this.expectedArrangementVersion,
    required List<YorksV1ArrangementLineInput> lines,
    required this.idempotencyKey,
    this.procurementNote,
  }) : lines = List.unmodifiable(lines);

  final String requestId;
  final String arrangementId;
  final int expectedRequestVersion;
  final int expectedArrangementVersion;
  final List<YorksV1ArrangementLineInput> lines;
  final String idempotencyKey;
  final String? procurementNote;

  Map<String, Object?> toRpcPayload() => {
    'request_id': requestId,
    'arrangement_id': arrangementId,
    'expected_request_version': expectedRequestVersion,
    'expected_arrangement_version': expectedArrangementVersion,
    'procurement_note': _trimToNull(procurementNote),
    'lines': [for (final line in lines) line.toRpcJson()],
  };
}

class YorksV1DecideArrangementInput {
  const YorksV1DecideArrangementInput({
    required this.requestId,
    required this.arrangementId,
    required this.expectedRequestVersion,
    required this.expectedArrangementVersion,
    required this.decision,
    required this.idempotencyKey,
    this.reason,
  });

  final String requestId;
  final String arrangementId;
  final int expectedRequestVersion;
  final int expectedArrangementVersion;
  final YorksV1ArrangementReviewDecision decision;
  final String idempotencyKey;
  final String? reason;

  Map<String, Object?> toRpcPayload() => {
    'request_id': requestId,
    'arrangement_id': arrangementId,
    'expected_request_version': expectedRequestVersion,
    'expected_arrangement_version': expectedArrangementVersion,
    'decision': decision.wireValue,
    'reason': _trimToNull(reason),
  };
}

String _string(Object? value) => switch (value) {
  String text => text,
  num number => number.toString(),
  _ => '',
};

int _nonNegativeInt(Object? value) => switch (value) {
  int number when number >= 0 => number,
  num number when number >= 0 => number.toInt(),
  String text => int.tryParse(text) ?? 0,
  _ => 0,
};

String? _trimToNull(Object? value) {
  final text = _string(value).trim();
  return text.isEmpty ? null : text;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _trimToNull(json[key]);
  if (value == null) {
    throw const YorksV1DomainException(
      YorksV1DomainErrorCode.unexpectedResponse,
    );
  }
  return value;
}

int _positiveInt(Object? value) {
  final parsed = switch (value) {
    int integer => integer,
    num number => number.toInt(),
    String text => int.tryParse(text) ?? 0,
    _ => 0,
  };
  return parsed > 0 ? parsed : 1;
}

DateTime _requiredDate(Map<String, dynamic> json, String key) {
  final date = _nullableDate(json[key]);
  if (date == null) {
    throw const YorksV1DomainException(
      YorksV1DomainErrorCode.unexpectedResponse,
    );
  }
  return date;
}

DateTime? _nullableDate(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  final normalized = value.trim();
  final calendarDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  if (calendarDate.hasMatch(normalized)) {
    final parts = normalized.split('-');
    return DateTime.utc(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }
  return DateTime.tryParse(normalized)?.toUtc();
}

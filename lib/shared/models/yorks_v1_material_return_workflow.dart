import 'yorks_v1_domain_error.dart';
import 'yorks_v1_material_return_candidates.dart';

/// Project-wide controlled Material Return state.
///
/// The warehouse balance changes only in [confirmed]. Every earlier state is
/// an operational document or transport fact, never an optimistic stock fact.
enum YorksV1ProjectMaterialReturnState {
  draft('draft'),
  awaitingApproval('awaiting_approval'),
  returnedForChanges('returned_for_changes'),
  approved('approved'),
  dispatched('dispatched'),
  confirmed('confirmed'),
  rejected('rejected'),
  cancelled('cancelled');

  const YorksV1ProjectMaterialReturnState(this.wireValue);

  final String wireValue;

  static YorksV1ProjectMaterialReturnState fromWireValue(Object? value) {
    for (final state in values) {
      if (state.wireValue == value) return state;
    }
    throw const YorksV1DomainException(
      YorksV1DomainErrorCode.unexpectedResponse,
    );
  }
}

enum YorksV1ReturnLineOrigin {
  delivered('delivered'),
  custom('custom');

  const YorksV1ReturnLineOrigin(this.wireValue);

  final String wireValue;

  static YorksV1ReturnLineOrigin fromWireValue(Object? value) =>
      value == custom.wireValue ? custom : delivered;
}

class YorksV1MaterialReturnRegisterItem {
  const YorksV1MaterialReturnRegisterItem({
    required this.id,
    required this.state,
    required this.recordVersion,
    required this.projectId,
    required this.projectReference,
    required this.projectName,
    required this.scopeId,
    required this.scopeName,
    required this.draftedByDisplayName,
    required this.lineCount,
    required this.totalQuantity,
    required this.updatedAt,
    this.number,
    this.purpose,
    this.attentionOwner,
  });

  final String id;
  final String? number;
  final YorksV1ProjectMaterialReturnState state;
  final int recordVersion;
  final String projectId;
  final String projectReference;
  final String projectName;
  final String scopeId;
  final String scopeName;
  final String? purpose;
  final String draftedByDisplayName;
  final int lineCount;
  final String totalQuantity;
  final DateTime updatedAt;
  final String? attentionOwner;

  factory YorksV1MaterialReturnRegisterItem.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksV1MaterialReturnRegisterItem(
    id: _requiredString(json, 'id'),
    number: _optionalString(json['return_number']),
    state: YorksV1ProjectMaterialReturnState.fromWireValue(json['state']),
    recordVersion: _int(json['record_version']),
    projectId: _requiredString(json, 'project_id'),
    projectReference: _requiredString(json, 'project_ref'),
    projectName: _requiredString(json, 'project_name'),
    scopeId: _requiredString(json, 'scope_id'),
    scopeName: _requiredString(json, 'scope_name'),
    purpose: _optionalString(json['purpose']),
    draftedByDisplayName: _requiredString(json, 'drafted_by_display_name'),
    lineCount: _int(json['line_count']),
    totalQuantity: _decimal(json['total_quantity']),
    updatedAt: _date(json['updated_at']),
    attentionOwner: _optionalString(json['attention_owner']),
  );
}

class YorksV1MaterialReturnScope {
  const YorksV1MaterialReturnScope({
    required this.id,
    required this.name,
    required this.kind,
  });

  final String id;
  final String name;
  final String kind;

  bool get isCommon => kind == 'common';

  factory YorksV1MaterialReturnScope.fromRpcJson(Map<String, dynamic> json) =>
      YorksV1MaterialReturnScope(
        id: _requiredString(json, 'id'),
        name: _requiredString(json, 'name'),
        kind: _requiredString(json, 'scope_kind'),
      );
}

class YorksV1MaterialReturnCandidate {
  const YorksV1MaterialReturnCandidate({
    required this.receiptReviewLineId,
    required this.requestId,
    required this.requestNumber,
    required this.dispatchId,
    required this.dispatchNumber,
    required this.scopeId,
    required this.scopeName,
    required this.description,
    required this.unit,
    required this.sourceKind,
    required this.goodReceivedQuantity,
    required this.committedReturnQuantity,
    required this.eligibleReturnQuantity,
    this.brandOrigin,
  });

  final String receiptReviewLineId;
  final String requestId;
  final String requestNumber;
  final String dispatchId;
  final String dispatchNumber;
  final String scopeId;
  final String scopeName;
  final String description;
  final String? brandOrigin;
  final String unit;
  final String sourceKind;
  final String goodReceivedQuantity;
  final String committedReturnQuantity;
  final String eligibleReturnQuantity;

  factory YorksV1MaterialReturnCandidate.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksV1MaterialReturnCandidate(
    receiptReviewLineId: _requiredString(json, 'receipt_review_line_id'),
    requestId: _requiredString(json, 'request_id'),
    requestNumber:
        _optionalString(json['request_number']) ??
        _requiredString(json, 'request_id'),
    dispatchId: _requiredString(json, 'dispatch_id'),
    dispatchNumber: _requiredString(json, 'dispatch_number'),
    scopeId: _requiredString(json, 'scope_id'),
    scopeName: _requiredString(json, 'scope_name'),
    description: _requiredString(json, 'item_description'),
    brandOrigin: _optionalString(json['brand_origin']),
    unit: _requiredString(json, 'unit'),
    sourceKind: _requiredString(json, 'source_kind'),
    goodReceivedQuantity: _decimal(json['good_received_qty']),
    committedReturnQuantity: _decimal(json['committed_return_qty']),
    eligibleReturnQuantity: _decimal(json['eligible_return_qty']),
  );
}

class YorksV1MaterialReturnLineRecord {
  const YorksV1MaterialReturnLineRecord({
    required this.id,
    required this.origin,
    required this.displayOrder,
    required this.description,
    required this.unit,
    required this.sourceKind,
    required this.returnQuantity,
    this.receiptReviewLineId,
    this.dispatchLineId,
    this.requestLineId,
    this.basisKind,
    this.sourceRequestId,
    this.sourceRequestNumber,
    this.sourceDispatchId,
    this.sourceDispatchNumber,
    this.sourceScopeId,
    this.sourceScopeName,
    this.brandOrigin,
    this.size,
    this.model,
    this.equipmentTag,
    this.itemCode,
    this.goodQuantitySnapshot,
    this.eligibleQuantityAtSubmit,
    this.lineNote,
    this.receivedGoodQuantity,
    this.receivedDamagedQuantity,
    this.notReceivedQuantity,
    this.receiptNote,
    this.sourceInventoryItemId,
    this.targetInventoryItemId,
  });

  final String id;
  final YorksV1ReturnLineOrigin origin;
  final String? receiptReviewLineId;
  final String? dispatchLineId;
  final String? requestLineId;

  /// Null for custom lines and for responses from servers before 4 Nov 2026.
  final YorksV1ReturnBasisKind? basisKind;
  final String? sourceRequestId;
  final String? sourceRequestNumber;
  final String? sourceDispatchId;
  final String? sourceDispatchNumber;
  final String? sourceScopeId;
  final String? sourceScopeName;
  final int displayOrder;
  final String description;
  final String? brandOrigin;
  final String? size;
  final String? model;
  final String? equipmentTag;
  final String? itemCode;
  final String unit;
  final String sourceKind;
  final String? goodQuantitySnapshot;
  final String? eligibleQuantityAtSubmit;
  final String returnQuantity;
  final String? lineNote;
  final String? receivedGoodQuantity;
  final String? receivedDamagedQuantity;
  final String? notReceivedQuantity;
  final String? receiptNote;
  final String? sourceInventoryItemId;
  final String? targetInventoryItemId;

  factory YorksV1MaterialReturnLineRecord.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksV1MaterialReturnLineRecord(
    id: _requiredString(json, 'id'),
    origin: YorksV1ReturnLineOrigin.fromWireValue(json['origin_kind']),
    receiptReviewLineId: _optionalString(json['receipt_review_line_id']),
    dispatchLineId: _optionalString(json['dispatch_line_id']),
    requestLineId: _optionalString(json['request_line_id']),
    basisKind: YorksV1ReturnBasisKind.fromWireValue(json['basis_kind']),
    sourceRequestId: _optionalString(json['source_request_id']),
    sourceRequestNumber: _optionalString(json['source_request_number']),
    sourceDispatchId: _optionalString(json['source_dispatch_id']),
    sourceDispatchNumber: _optionalString(json['source_dispatch_number']),
    sourceScopeId: _optionalString(json['source_scope_id']),
    sourceScopeName: _optionalString(json['source_scope_name']),
    displayOrder: _int(json['display_order']),
    description: _requiredString(json, 'item_description'),
    brandOrigin: _optionalString(json['brand_origin']),
    size: _optionalString(json['size']),
    model: _optionalString(json['model']),
    equipmentTag: _optionalString(json['equipment_tag']),
    itemCode: _optionalString(json['item_code']),
    unit: _requiredString(json, 'unit'),
    sourceKind: _requiredString(json, 'source_kind'),
    goodQuantitySnapshot: _optionalDecimal(json['good_quantity_snapshot']),
    eligibleQuantityAtSubmit: _optionalDecimal(
      json['eligible_quantity_at_submit'],
    ),
    returnQuantity: _decimal(json['return_quantity']),
    lineNote: _optionalString(json['line_note']),
    receivedGoodQuantity: _optionalDecimal(json['received_good_quantity']),
    receivedDamagedQuantity: _optionalDecimal(
      json['received_damaged_quantity'],
    ),
    notReceivedQuantity: _optionalDecimal(json['not_received_quantity']),
    receiptNote: _optionalString(json['receipt_note']),
    sourceInventoryItemId: _optionalString(json['source_inventory_item_id']),
    targetInventoryItemId: _optionalString(json['target_inventory_item_id']),
  );
}

class YorksV1MaterialReturnInventoryOption {
  const YorksV1MaterialReturnInventoryOption({
    required this.id,
    required this.description,
    required this.unit,
    this.brandOrigin,
  });

  final String id;
  final String description;
  final String? brandOrigin;
  final String unit;

  factory YorksV1MaterialReturnInventoryOption.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksV1MaterialReturnInventoryOption(
    id: _requiredString(json, 'id'),
    description: _requiredString(json, 'item_description'),
    brandOrigin: _optionalString(json['brand_origin']),
    unit: _requiredString(json, 'unit'),
  );
}

class YorksV1ProjectMaterialReturn {
  YorksV1ProjectMaterialReturn({
    required this.id,
    required this.state,
    required this.recordVersion,
    required this.projectId,
    required this.projectReference,
    required this.projectName,
    required this.scopeId,
    required this.scopeName,
    required this.draftedAt,
    required this.draftedByAuthUserId,
    required this.draftedByDisplayName,
    required this.draftedByRole,
    required this.canEdit,
    required this.canSubmit,
    required this.canApprove,
    required this.canReturnForChanges,
    required this.canDispatch,
    required this.canConfirm,
    required this.canCancel,
    required List<YorksV1MaterialReturnLineRecord> lines,
    required List<YorksV1MaterialReturnInventoryOption> inventoryItems,
    this.number,
    this.purpose,
    this.note,
    this.requestedReturnDate,
    this.submittedAt,
    this.submittedByDisplayName,
    this.approvedAt,
    this.approvedByDisplayName,
    this.approvedByExactRole,
    this.approvalNote,
    this.returnedForChangesReason,
    this.dispatchedAt,
    this.dispatchedByDisplayName,
    this.driverName,
    this.vehicleReference,
    this.deliveryNoteReference,
    this.confirmedAt,
    this.confirmedByDisplayName,
    this.warehouseReceiptNote,
    this.rejectionReason,
    this.cancelledAt,
    this.cancelledByDisplayName,
    this.cancellationReason,
  }) : lines = List.unmodifiable(lines),
       inventoryItems = List.unmodifiable(inventoryItems);

  final String id;
  final String? number;
  final YorksV1ProjectMaterialReturnState state;
  final int recordVersion;
  final String projectId;
  final String projectReference;
  final String projectName;
  final String scopeId;
  final String scopeName;
  final String? purpose;
  final String? note;
  final DateTime? requestedReturnDate;
  final DateTime draftedAt;
  final String draftedByAuthUserId;
  final String draftedByDisplayName;
  final String draftedByRole;
  final DateTime? submittedAt;
  final String? submittedByDisplayName;
  final DateTime? approvedAt;
  final String? approvedByDisplayName;
  final String? approvedByExactRole;
  final String? approvalNote;
  final String? returnedForChangesReason;
  final DateTime? dispatchedAt;
  final String? dispatchedByDisplayName;
  final String? driverName;
  final String? vehicleReference;
  final String? deliveryNoteReference;
  final DateTime? confirmedAt;
  final String? confirmedByDisplayName;
  final String? warehouseReceiptNote;
  final String? rejectionReason;
  final DateTime? cancelledAt;
  final String? cancelledByDisplayName;
  final String? cancellationReason;
  final bool canEdit;
  final bool canSubmit;
  final bool canApprove;
  final bool canReturnForChanges;
  final bool canDispatch;
  final bool canConfirm;
  final bool canCancel;
  final List<YorksV1MaterialReturnLineRecord> lines;
  final List<YorksV1MaterialReturnInventoryOption> inventoryItems;

  factory YorksV1ProjectMaterialReturn.fromRpcJson(Map<String, dynamic> json) {
    final rawLines = json['lines'];
    final rawInventory = json['inventory_items'];
    if (rawLines is! List || rawInventory is! List) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1ProjectMaterialReturn(
      id: _requiredString(json, 'id'),
      number: _optionalString(json['return_number']),
      state: YorksV1ProjectMaterialReturnState.fromWireValue(json['state']),
      recordVersion: _int(json['record_version']),
      projectId: _requiredString(json, 'project_id'),
      projectReference: _requiredString(json, 'project_ref'),
      projectName: _requiredString(json, 'project_name'),
      scopeId: _requiredString(json, 'scope_id'),
      scopeName: _requiredString(json, 'scope_name'),
      purpose: _optionalString(json['purpose']),
      note: _optionalString(json['note']),
      requestedReturnDate: _optionalDate(json['requested_return_date']),
      draftedAt: _date(json['drafted_at']),
      draftedByAuthUserId: _requiredString(json, 'drafted_by_auth_user_id'),
      draftedByDisplayName: _requiredString(json, 'drafted_by_display_name'),
      draftedByRole: _requiredString(json, 'drafted_by_role'),
      submittedAt: _optionalDate(json['submitted_at']),
      submittedByDisplayName: _optionalString(
        json['submitted_by_display_name'],
      ),
      approvedAt: _optionalDate(json['approved_at']),
      approvedByDisplayName: _optionalString(json['approved_by_display_name']),
      approvedByExactRole: _optionalString(json['approved_by_exact_role']),
      approvalNote: _optionalString(json['approval_note']),
      returnedForChangesReason: _optionalString(
        json['returned_for_changes_reason'],
      ),
      dispatchedAt: _optionalDate(json['dispatched_at']),
      dispatchedByDisplayName: _optionalString(
        json['dispatched_by_display_name'],
      ),
      driverName: _optionalString(json['driver_name']),
      vehicleReference: _optionalString(json['vehicle_reference']),
      deliveryNoteReference: _optionalString(json['delivery_note_reference']),
      confirmedAt: _optionalDate(json['confirmed_at']),
      confirmedByDisplayName: _optionalString(
        json['confirmed_by_display_name'],
      ),
      warehouseReceiptNote: _optionalString(json['warehouse_receipt_note']),
      rejectionReason: _optionalString(json['rejection_reason']),
      cancelledAt: _optionalDate(json['cancelled_at']),
      cancelledByDisplayName: _optionalString(
        json['cancelled_by_display_name'],
      ),
      cancellationReason: _optionalString(json['cancellation_reason']),
      canEdit: json['can_edit'] == true,
      canSubmit: json['can_submit'] == true,
      canApprove: json['can_approve'] == true,
      canReturnForChanges: json['can_return_for_changes'] == true,
      canDispatch: json['can_dispatch'] == true,
      canConfirm: json['can_confirm'] == true,
      canCancel: json['can_cancel'] == true,
      lines: [
        for (final row in rawLines)
          if (row is Map)
            YorksV1MaterialReturnLineRecord.fromRpcJson(
              Map<String, dynamic>.from(row),
            ),
      ],
      inventoryItems: [
        for (final row in rawInventory)
          if (row is Map)
            YorksV1MaterialReturnInventoryOption.fromRpcJson(
              Map<String, dynamic>.from(row),
            ),
      ],
    );
  }
}

class YorksV1MaterialReturnCreationWorkspace {
  YorksV1MaterialReturnCreationWorkspace({
    required this.projectId,
    required this.projectReference,
    required this.projectName,
    required List<YorksV1MaterialReturnScope> scopes,
    required List<YorksV1MaterialReturnCandidate> candidates,
    required List<String> units,
    this.draft,
  }) : scopes = List.unmodifiable(scopes),
       candidates = List.unmodifiable(candidates),
       units = List.unmodifiable(units);

  final String projectId;
  final String projectReference;
  final String projectName;
  final List<YorksV1MaterialReturnScope> scopes;
  final List<YorksV1MaterialReturnCandidate> candidates;
  final List<String> units;
  final YorksV1ProjectMaterialReturn? draft;

  factory YorksV1MaterialReturnCreationWorkspace.fromRpcJson(
    Map<String, dynamic> json,
  ) {
    final scopes = json['scopes'];
    final candidates = json['candidates'];
    final units = json['units'];
    if (scopes is! List || candidates is! List || units is! List) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    final draft = json['draft'];
    return YorksV1MaterialReturnCreationWorkspace(
      projectId: _requiredString(json, 'project_id'),
      projectReference: _requiredString(json, 'project_ref'),
      projectName: _requiredString(json, 'project_name'),
      scopes: [
        for (final row in scopes)
          if (row is Map)
            YorksV1MaterialReturnScope.fromRpcJson(
              Map<String, dynamic>.from(row),
            ),
      ],
      candidates: [
        for (final row in candidates)
          if (row is Map)
            YorksV1MaterialReturnCandidate.fromRpcJson(
              Map<String, dynamic>.from(row),
            ),
      ],
      units: units
          .map(_optionalString)
          .whereType<String>()
          .toList(growable: false),
      draft: draft is Map
          ? YorksV1ProjectMaterialReturn.fromRpcJson(
              Map<String, dynamic>.from(draft),
            )
          : null,
    );
  }
}

class YorksV1MaterialReturnDraftLineInput {
  const YorksV1MaterialReturnDraftLineInput({
    required this.origin,
    required this.quantity,
    this.receiptReviewLineId,
    this.dispatchLineId,
    this.description,
    this.brandOrigin,
    this.unit,
    this.size,
    this.model,
    this.equipmentTag,
    this.note,
  });

  final YorksV1ReturnLineOrigin origin;
  final String? receiptReviewLineId;

  /// Delivered lines anchor on the dispatch line (servers from 4 Nov 2026).
  final String? dispatchLineId;
  final String? description;
  final String? brandOrigin;
  final String? unit;
  final String? size;
  final String? model;
  final String? equipmentTag;
  final String quantity;
  final String? note;

  Map<String, Object?> toRpcJson() => {
    'origin_kind': origin.wireValue,
    'dispatch_line_id': ?_trim(dispatchLineId),
    'receipt_review_line_id': _trim(receiptReviewLineId),
    'item_description': _trim(description),
    'brand_origin': _trim(brandOrigin),
    'unit': _trim(unit),
    if (origin == YorksV1ReturnLineOrigin.custom) ...{
      'size': _trim(size),
      'model': _trim(model),
      'equipment_tag': _trim(equipmentTag),
    },
    'return_qty': quantity.trim(),
    'note': _trim(note),
  };
}

class YorksV1SaveMaterialReturnDraftInput {
  YorksV1SaveMaterialReturnDraftInput({
    required this.projectId,
    required this.scopeId,
    required this.expectedVersion,
    required this.purpose,
    required List<YorksV1MaterialReturnDraftLineInput> lines,
    required this.idempotencyKey,
    this.returnId,
    this.note,
    this.requestedReturnDate,
  }) : lines = List.unmodifiable(lines);

  final String? returnId;
  final String projectId;
  final String scopeId;
  final int expectedVersion;
  final String purpose;
  final String? note;
  final DateTime? requestedReturnDate;
  final List<YorksV1MaterialReturnDraftLineInput> lines;
  final String idempotencyKey;

  Map<String, Object?> toRpcPayload() => {
    'return_id': _trim(returnId),
    'project_id': projectId,
    'scope_id': scopeId,
    'expected_version': expectedVersion,
    'purpose': purpose.trim(),
    'note': _trim(note),
    'requested_return_date': requestedReturnDate == null
        ? null
        : _dateOnly(requestedReturnDate!),
    'lines': [for (final line in lines) line.toRpcJson()],
  };
}

class YorksV1MaterialReturnCommandInput {
  const YorksV1MaterialReturnCommandInput({
    required this.returnId,
    required this.expectedVersion,
    required this.idempotencyKey,
  });

  final String returnId;
  final int expectedVersion;
  final String idempotencyKey;

  Map<String, Object?> toRpcPayload() => {
    'return_id': returnId,
    'expected_version': expectedVersion,
  };
}

class YorksV1MaterialReturnDecisionInput
    extends YorksV1MaterialReturnCommandInput {
  const YorksV1MaterialReturnDecisionInput({
    required super.returnId,
    required super.expectedVersion,
    required super.idempotencyKey,
    required this.decision,
    this.reason,
  });

  final YorksV1ProjectMaterialReturnState decision;
  final String? reason;

  @override
  Map<String, Object?> toRpcPayload() => {
    ...super.toRpcPayload(),
    'decision': decision.wireValue,
    'reason': _trim(reason),
  };
}

class YorksV1MaterialReturnCancellationInput
    extends YorksV1MaterialReturnCommandInput {
  const YorksV1MaterialReturnCancellationInput({
    required super.returnId,
    required super.expectedVersion,
    required super.idempotencyKey,
    required this.reason,
  });

  final String reason;

  @override
  Map<String, Object?> toRpcPayload() => {
    ...super.toRpcPayload(),
    'reason': reason.trim(),
  };
}

class YorksV1MaterialReturnDispatchInput
    extends YorksV1MaterialReturnCommandInput {
  const YorksV1MaterialReturnDispatchInput({
    required super.returnId,
    required super.expectedVersion,
    required super.idempotencyKey,
    required this.driverName,
    required this.deliveryNoteReference,
    this.vehicleReference,
  });

  final String driverName;
  final String deliveryNoteReference;
  final String? vehicleReference;

  @override
  Map<String, Object?> toRpcPayload() => {
    ...super.toRpcPayload(),
    'driver_name': driverName.trim(),
    'vehicle_reference': _trim(vehicleReference),
    'delivery_note_reference': deliveryNoteReference.trim(),
  };
}

class YorksV1MaterialReturnReceiptLineInput {
  const YorksV1MaterialReturnReceiptLineInput({
    required this.returnLineId,
    required this.receivedGoodQuantity,
    required this.damagedQuantity,
    required this.notReceivedQuantity,
    this.inventoryItemId,
    this.newItemDescription,
    this.newItemBrandOrigin,
    this.unit,
    this.note,
  });

  final String returnLineId;
  final String receivedGoodQuantity;
  final String damagedQuantity;
  final String notReceivedQuantity;
  final String? inventoryItemId;
  final String? newItemDescription;
  final String? newItemBrandOrigin;
  final String? unit;
  final String? note;

  Map<String, Object?> toRpcJson() => {
    'return_line_id': returnLineId,
    'received_good_qty': receivedGoodQuantity.trim(),
    'damaged_qty': damagedQuantity.trim(),
    'not_received_qty': notReceivedQuantity.trim(),
    'inventory_item_id': _trim(inventoryItemId),
    'new_inventory_item': _trim(newItemDescription) == null
        ? null
        : {
            'item_description': newItemDescription!.trim(),
            'brand_origin': _trim(newItemBrandOrigin),
            'unit': unit?.trim(),
          },
    'note': _trim(note),
  };
}

class YorksV1MaterialReturnReceiptInput
    extends YorksV1MaterialReturnCommandInput {
  YorksV1MaterialReturnReceiptInput({
    required super.returnId,
    required super.expectedVersion,
    required super.idempotencyKey,
    required List<YorksV1MaterialReturnReceiptLineInput> lineReceipts,
    this.receiptNote,
  }) : lineReceipts = List.unmodifiable(lineReceipts);

  final String? receiptNote;
  final List<YorksV1MaterialReturnReceiptLineInput> lineReceipts;

  @override
  Map<String, Object?> toRpcPayload() => {
    ...super.toRpcPayload(),
    'receipt_note': _trim(receiptNote),
    'line_receipts': [for (final line in lineReceipts) line.toRpcJson()],
  };
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _optionalString(json[key]);
  if (value == null) {
    throw const YorksV1DomainException(
      YorksV1DomainErrorCode.unexpectedResponse,
    );
  }
  return value;
}

String? _optionalString(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

String _decimal(Object? value) => value?.toString() ?? '0';

String? _optionalDecimal(Object? value) => value?.toString();

int _int(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime _date(Object? value) {
  final parsed = _optionalDate(value);
  if (parsed == null) {
    throw const YorksV1DomainException(
      YorksV1DomainErrorCode.unexpectedResponse,
    );
  }
  return parsed;
}

DateTime? _optionalDate(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());

String? _trim(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

String _dateOnly(DateTime value) {
  final date = value.toLocal();
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

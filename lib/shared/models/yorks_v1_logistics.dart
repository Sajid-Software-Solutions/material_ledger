import 'yorks_v1_domain_error.dart';
import 'yorks_v1_item_description.dart';

enum YorksV1LogisticsSource {
  warehouse('warehouse'),
  externalSupplier('external_supplier');

  const YorksV1LogisticsSource(this.wireValue);
  final String wireValue;

  static YorksV1LogisticsSource fromWireValue(Object? value) => switch (value) {
    'external_supplier' => YorksV1LogisticsSource.externalSupplier,
    _ => YorksV1LogisticsSource.warehouse,
  };
}

enum YorksV1DispatchState {
  receiptPending('receipt_pending'),
  partiallyReceived('partially_received'),
  received('received');

  const YorksV1DispatchState(this.wireValue);
  final String wireValue;

  static YorksV1DispatchState? fromWireValue(Object? value) {
    if (value is! String) return null;
    for (final state in values) {
      if (state.wireValue == value) return state;
    }
    return null;
  }
}

enum YorksV1ReceiptOutcome {
  received('received'),
  missing('missing'),
  damaged('damaged'),
  mixed('mixed');

  const YorksV1ReceiptOutcome(this.wireValue);
  final String wireValue;

  static YorksV1ReceiptOutcome? fromWireValue(Object? value) {
    if (value is! String) return null;
    for (final outcome in values) {
      if (outcome.wireValue == value) return outcome;
    }
    return null;
  }
}

enum YorksV1ProjectMaterialMovementKind {
  dispatched('dispatched'),
  returned('returned');

  const YorksV1ProjectMaterialMovementKind(this.wireValue);

  final String wireValue;

  static YorksV1ProjectMaterialMovementKind? fromWireValue(Object? value) {
    for (final kind in values) {
      if (kind.wireValue == value) return kind;
    }
    return null;
  }
}

/// Read-only project movement fact. This projection intentionally contains no
/// stock command, valuation or mutable workflow state.
class YorksV1ProjectMaterialMovement {
  const YorksV1ProjectMaterialMovement({
    required this.id,
    required this.kind,
    required this.reference,
    required this.requestId,
    required this.requestNumber,
    required this.itemDescription,
    required this.unit,
    required this.quantity,
    required this.actorDisplayName,
    required this.occurredAt,
    this.brandOrigin,
  });

  final String id;
  final YorksV1ProjectMaterialMovementKind kind;
  final String reference;
  final String requestId;
  final String requestNumber;
  final String itemDescription;
  final String? brandOrigin;
  final String unit;
  final String quantity;
  final String actorDisplayName;
  final DateTime occurredAt;

  factory YorksV1ProjectMaterialMovement.fromRpcJson(
    Map<String, dynamic> json,
  ) {
    final kind = YorksV1ProjectMaterialMovementKind.fromWireValue(
      json['movement_kind'],
    );
    if (kind == null) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1ProjectMaterialMovement(
      id: _requiredString(json, 'id'),
      kind: kind,
      reference: _requiredString(json, 'reference'),
      requestId: _requiredString(json, 'request_id'),
      requestNumber: _requiredString(json, 'request_number'),
      itemDescription: normalizeYorksV1ItemDescription(
        _requiredString(json, 'item_description'),
      ),
      brandOrigin: _trimToNull(json['brand_origin']),
      unit: _requiredString(json, 'unit'),
      quantity: _string(json['quantity']),
      actorDisplayName: _requiredString(json, 'actor_display_name'),
      occurredAt: _requiredDate(json, 'occurred_at'),
    );
  }
}

/// Operational-only warehouse item. This intentionally contains no supplier
/// commercial record, rate, unit cost or valuation field.
class YorksV1LogisticsInventoryItem {
  const YorksV1LogisticsInventoryItem({
    required this.id,
    required this.description,
    required this.unit,
    required this.isActive,
    required this.onHandQuantity,
    required this.reservedQuantity,
    required this.availableQuantity,
    required this.recordVersion,
    this.itemCode,
    this.categoryId,
    this.categoryName,
    this.categoryPath,
    this.brandOrigin,
    this.sizeText,
    this.modelReference,
    this.minimumStock,
    this.locationBin,
    this.notes,
    this.movementCount,
    this.lastMovementAt,
    this.createdAt,
    this.updatedAt,
    this.metadataRecordVersion,
  });

  final String id;
  final String? itemCode;
  final String description;
  final String? categoryId;
  final String? categoryName;
  final String? categoryPath;
  final String? brandOrigin;
  final String? sizeText;
  final String? modelReference;
  final String unit;
  final String? minimumStock;
  final String? locationBin;
  final String? notes;
  final bool isActive;
  final String onHandQuantity;
  final String reservedQuantity;
  final String availableQuantity;
  final int recordVersion;
  final int? metadataRecordVersion;
  final int? movementCount;
  final DateTime? lastMovementAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasMinimumStock => _decimal(minimumStock ?? '') != null;
  bool get isOutOfStock => (_decimal(availableQuantity) ?? 0) <= 0;
  bool get isLowStock {
    final available = _decimal(availableQuantity);
    final minimum = _decimal(minimumStock ?? '');
    return available != null &&
        minimum != null &&
        available > 0 &&
        available <= minimum;
  }

  factory YorksV1LogisticsInventoryItem.fromRpcJson(Map<String, dynamic> json) {
    return YorksV1LogisticsInventoryItem(
      id: _requiredString(json, 'id'),
      itemCode: _trimToNull(json['item_code']),
      description: normalizeYorksV1ItemDescription(
        _requiredString(json, 'item_description'),
      ),
      categoryId: _trimToNull(json['category_id']),
      categoryName: _trimToNull(json['category_name']),
      categoryPath: _trimToNull(json['category_path']),
      brandOrigin: _trimToNull(json['brand_origin']),
      sizeText: _trimToNull(json['size_text']),
      modelReference: _trimToNull(json['model_reference']),
      unit: _requiredString(json, 'unit'),
      minimumStock: _trimToNull(json['minimum_stock']),
      locationBin: _trimToNull(json['location_bin']),
      notes: _trimToNull(json['notes']),
      isActive: json['is_active'] != false,
      onHandQuantity: _string(json['on_hand_qty']),
      reservedQuantity: _string(json['reserved_qty']),
      availableQuantity: _string(json['available_qty']),
      recordVersion: _positiveInt(json['record_version']),
      metadataRecordVersion: _nullableInt(json['metadata_record_version']),
      movementCount: _nullableInt(json['movement_count']),
      lastMovementAt: _nullableDate(json['last_movement_at']),
      createdAt: _nullableDate(json['created_at']),
      updatedAt: _nullableDate(json['updated_at']),
    );
  }
}

class YorksV1InventoryCategory {
  YorksV1InventoryCategory({
    required this.id,
    required this.name,
    required this.isSystem,
    required this.isActive,
    required this.recordVersion,
    required this.itemCount,
    required List<String> aliases,
    required this.createdByDisplayName,
    required this.createdAt,
    this.parentCategoryId,
    this.parentName,
    String? displayPath,
  }) : aliases = List.unmodifiable(aliases),
       displayPath =
           displayPath ?? (parentName == null ? name : '$parentName › $name');

  final String id;
  final String name;
  final String? parentCategoryId;
  final String? parentName;
  final String displayPath;
  final bool isSystem;
  final bool isActive;
  final int recordVersion;
  final int itemCount;
  final List<String> aliases;
  final String createdByDisplayName;
  final DateTime createdAt;

  factory YorksV1InventoryCategory.fromRpcJson(Map<String, dynamic> json) {
    final rawAliases = json['aliases'];
    return YorksV1InventoryCategory(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      parentCategoryId: _trimToNull(json['parent_category_id']),
      parentName: _trimToNull(json['parent_name']),
      displayPath: _trimToNull(json['display_path']),
      isSystem: json['is_system'] == true,
      isActive: json['is_active'] != false,
      recordVersion: _positiveInt(json['record_version']),
      itemCount: _nonNegativeInt(json['item_count']),
      aliases: [
        if (rawAliases is List)
          for (final alias in rawAliases) ?_trimToNull(alias),
      ],
      createdByDisplayName: _requiredString(json, 'created_by_display_name'),
      createdAt: _requiredDate(json, 'created_at'),
    );
  }
}

class YorksV1InventoryCategorySearchResult {
  const YorksV1InventoryCategorySearchResult({
    required this.categoryId,
    required this.name,
    required this.displayPath,
    required this.matchKind,
    this.parentName,
    this.matchedAlias,
    this.similarityScore,
  });

  final String categoryId;
  final String name;
  final String? parentName;
  final String displayPath;
  final String matchKind;
  final String? matchedAlias;
  final double? similarityScore;

  factory YorksV1InventoryCategorySearchResult.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksV1InventoryCategorySearchResult(
    categoryId: _requiredString(json, 'category_id'),
    name: _requiredString(json, 'name'),
    parentName: _trimToNull(json['parent_name']),
    displayPath: _requiredString(json, 'display_path'),
    matchKind: _requiredString(json, 'match_kind'),
    matchedAlias: _trimToNull(json['matched_alias']),
    similarityScore: _nullableDouble(json['similarity_score']),
  );
}

class YorksV1InventoryMovement {
  const YorksV1InventoryMovement({
    required this.id,
    required this.movementType,
    required this.quantityDelta,
    required this.onHandAfterQuantity,
    required this.reason,
    required this.actorDisplayName,
    required this.createdAt,
    this.inventoryItemId,
    this.itemCode,
    this.itemDescription,
    this.unit,
    this.sourceEntityType,
    this.sourceEntityId,
  });

  final String id;
  final String? inventoryItemId;
  final String? itemCode;
  final String? itemDescription;
  final String? unit;
  final String movementType;
  final String quantityDelta;
  final String onHandAfterQuantity;
  final String reason;
  final String actorDisplayName;
  final DateTime createdAt;
  final String? sourceEntityType;
  final String? sourceEntityId;

  factory YorksV1InventoryMovement.fromRpcJson(Map<String, dynamic> json) {
    return YorksV1InventoryMovement(
      id: _requiredString(json, 'id'),
      inventoryItemId: _trimToNull(json['inventory_item_id']),
      itemCode: _trimToNull(json['item_code']),
      itemDescription: _normalizedDescriptionOrNull(json['item_description']),
      unit: _trimToNull(json['unit']),
      movementType: _requiredString(json, 'movement_type'),
      quantityDelta: _string(json['quantity_delta']),
      onHandAfterQuantity: _string(json['on_hand_after_qty']),
      reason: _requiredString(json, 'reason'),
      actorDisplayName: _requiredString(json, 'actor_display_name'),
      createdAt: _requiredDate(json, 'created_at'),
      sourceEntityType: _trimToNull(json['source_entity_type']),
      sourceEntityId: _trimToNull(json['source_entity_id']),
    );
  }
}

class YorksV1InventoryReservation {
  const YorksV1InventoryReservation({
    required this.id,
    required this.inventoryItemId,
    required this.itemDescription,
    required this.unit,
    required this.requestId,
    this.requestKind = 'project',
    required this.requestNumber,
    required this.projectName,
    required this.scopeName,
    required this.reservedQuantity,
    required this.remainingQuantity,
    required this.state,
    required this.createdAt,
    this.itemCode,
  });

  final String id;
  final String inventoryItemId;
  final String? itemCode;
  final String itemDescription;
  final String unit;
  final String requestId;
  final String requestKind;
  final String requestNumber;
  final String projectName;
  final String scopeName;
  final String reservedQuantity;
  final String remainingQuantity;
  final String state;
  final DateTime createdAt;

  factory YorksV1InventoryReservation.fromRpcJson(Map<String, dynamic> json) =>
      YorksV1InventoryReservation(
        id: _requiredString(json, 'id'),
        inventoryItemId: _requiredString(json, 'inventory_item_id'),
        itemCode: _trimToNull(json['item_code']),
        itemDescription: normalizeYorksV1ItemDescription(
          _requiredString(json, 'item_description'),
        ),
        unit: _requiredString(json, 'unit'),
        requestId: _requiredString(json, 'request_id'),
        requestKind: _trimToNull(json['request_kind']) ?? 'project',
        requestNumber: _requiredString(json, 'request_number'),
        projectName: _requiredString(json, 'project_name'),
        scopeName: _requiredString(json, 'scope_name'),
        reservedQuantity: _string(json['reserved_qty']),
        remainingQuantity: _string(json['remaining_qty']),
        state: _requiredString(json, 'state'),
        createdAt: _requiredDate(json, 'created_at'),
      );
}

class YorksV1InventoryItemDetail {
  YorksV1InventoryItemDetail({
    required this.item,
    required List<YorksV1InventoryMovement> movements,
  }) : movements = List.unmodifiable(movements);

  final YorksV1LogisticsInventoryItem item;
  final List<YorksV1InventoryMovement> movements;

  factory YorksV1InventoryItemDetail.fromRpcJson(Map<String, dynamic> json) {
    final rawItem = json['item'];
    final rawMovements = json['movements'];
    if (rawItem is! Map || rawMovements is! List) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1InventoryItemDetail(
      item: YorksV1LogisticsInventoryItem.fromRpcJson(
        Map<String, dynamic>.from(rawItem),
      ),
      movements: [
        for (final movement in rawMovements)
          if (movement is Map)
            YorksV1InventoryMovement.fromRpcJson(
              Map<String, dynamic>.from(movement),
            ),
      ],
    );
  }
}

class YorksV1DispatchCandidate {
  const YorksV1DispatchCandidate({
    required this.requestLineId,
    required this.displayOrder,
    required this.description,
    required this.unit,
    required this.approvedQuantity,
    required this.goodReceivedQuantity,
    required this.inTransitQuantity,
    required this.stillNeededQuantity,
    required this.source,
    this.brandOrigin,
    this.externalSupplier,
    this.inventoryItemId,
    this.reservedRemainingQuantity,
    this.warehouseAvailableQuantity,
  });

  final String requestLineId;
  final int displayOrder;
  final String description;
  final String? brandOrigin;
  final String unit;
  final String approvedQuantity;
  final String goodReceivedQuantity;
  final String inTransitQuantity;
  final String stillNeededQuantity;
  final YorksV1LogisticsSource source;
  final String? externalSupplier;
  final String? inventoryItemId;
  final String? reservedRemainingQuantity;
  final String? warehouseAvailableQuantity;

  factory YorksV1DispatchCandidate.fromRpcJson(Map<String, dynamic> json) {
    return YorksV1DispatchCandidate(
      requestLineId: _requiredString(json, 'request_line_id'),
      displayOrder: _positiveInt(json['display_order']),
      description: normalizeYorksV1ItemDescription(
        _requiredString(json, 'item_description'),
      ),
      brandOrigin: _trimToNull(json['brand_origin']),
      unit: _requiredString(json, 'unit'),
      approvedQuantity: _string(json['approved_qty']),
      goodReceivedQuantity: _string(json['good_received_qty']),
      inTransitQuantity: _string(json['in_transit_qty']),
      stillNeededQuantity: _string(json['still_needed_qty']),
      source: YorksV1LogisticsSource.fromWireValue(json['source_kind']),
      externalSupplier: _trimToNull(json['external_supplier']),
      inventoryItemId: _trimToNull(json['inventory_item_id']),
      reservedRemainingQuantity: _trimToNull(json['reserved_remaining_qty']),
      warehouseAvailableQuantity: _trimToNull(json['warehouse_available_qty']),
    );
  }
}

class YorksV1DispatchLine {
  const YorksV1DispatchLine({
    required this.id,
    required this.requestLineId,
    required this.description,
    required this.unit,
    required this.source,
    required this.dispatchedQuantity,
    required this.approvedQuantity,
    this.brandOrigin,
    this.externalSupplier,
    this.receiptOutcome,
    this.goodQuantity,
    this.missingQuantity,
    this.damagedQuantity,
    this.exceptionQuantity,
    this.receiptNote,
  });

  final String id;
  final String requestLineId;
  final String description;
  final String? brandOrigin;
  final String unit;
  final YorksV1LogisticsSource source;
  final String dispatchedQuantity;
  final String approvedQuantity;
  final String? externalSupplier;
  final YorksV1ReceiptOutcome? receiptOutcome;
  final String? goodQuantity;
  final String? missingQuantity;
  final String? damagedQuantity;
  final String? exceptionQuantity;
  final String? receiptNote;

  factory YorksV1DispatchLine.fromRpcJson(Map<String, dynamic> json) {
    return YorksV1DispatchLine(
      id: _requiredString(json, 'id'),
      requestLineId: _requiredString(json, 'request_line_id'),
      description: normalizeYorksV1ItemDescription(
        _requiredString(json, 'item_description'),
      ),
      brandOrigin: _trimToNull(json['brand_origin']),
      unit: _requiredString(json, 'unit'),
      source: YorksV1LogisticsSource.fromWireValue(json['source_kind']),
      dispatchedQuantity: _string(json['dispatched_qty']),
      approvedQuantity: _string(json['approved_qty_snapshot']),
      externalSupplier: _trimToNull(json['external_supplier']),
      receiptOutcome: YorksV1ReceiptOutcome.fromWireValue(
        json['receipt_outcome'],
      ),
      goodQuantity: _trimToNull(json['good_qty']),
      missingQuantity: _trimToNull(json['missing_qty']),
      damagedQuantity: _trimToNull(json['damaged_qty']),
      exceptionQuantity: _trimToNull(json['exception_qty']),
      receiptNote: _trimToNull(json['receipt_note']),
    );
  }
}

class YorksV1ReceiptReview {
  const YorksV1ReceiptReview({
    required this.id,
    required this.reviewedAt,
    required this.reviewedByDisplayName,
    this.reviewedByRole,
  });

  final String id;
  final DateTime reviewedAt;
  final String reviewedByDisplayName;
  final String? reviewedByRole;

  factory YorksV1ReceiptReview.fromRpcJson(Map<String, dynamic> json) {
    return YorksV1ReceiptReview(
      id: _requiredString(json, 'id'),
      reviewedAt: _requiredDate(json, 'reviewed_at'),
      reviewedByDisplayName: _requiredString(json, 'reviewed_by_display_name'),
      reviewedByRole: _trimToNull(json['reviewed_by_role']),
    );
  }
}

class YorksV1MaterialDispatch {
  YorksV1MaterialDispatch({
    required this.id,
    required this.number,
    required this.dispatchDate,
    required this.state,
    required this.recordVersion,
    required this.dispatchedByDisplayName,
    required this.dispatchedAt,
    required this.canConfirmReceipt,
    required List<YorksV1DispatchLine> lines,
    this.driverName,
    this.vehicleReference,
    this.deliveryReference,
    this.dispatchedByRole,
    this.receiptReview,
  }) : lines = List.unmodifiable(lines);

  final String id;
  final String number;
  final DateTime dispatchDate;
  final YorksV1DispatchState state;
  final int recordVersion;
  final String dispatchedByDisplayName;
  final DateTime dispatchedAt;
  final bool canConfirmReceipt;
  final String? driverName;
  final String? vehicleReference;
  final String? deliveryReference;
  final String? dispatchedByRole;
  final YorksV1ReceiptReview? receiptReview;
  final List<YorksV1DispatchLine> lines;

  factory YorksV1MaterialDispatch.fromRpcJson(Map<String, dynamic> json) {
    final rawLines = json['lines'];
    final state = YorksV1DispatchState.fromWireValue(json['state']);
    if (rawLines is! List || state == null) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    final rawReview = json['receipt_review'];
    return YorksV1MaterialDispatch(
      id: _requiredString(json, 'id'),
      number: _requiredString(json, 'dispatch_number'),
      dispatchDate: _requiredDate(json, 'dispatch_date'),
      state: state,
      recordVersion: _positiveInt(json['record_version']),
      dispatchedByDisplayName: _requiredString(
        json,
        'dispatched_by_display_name',
      ),
      dispatchedAt: _requiredDate(json, 'dispatched_at'),
      canConfirmReceipt: json['can_confirm_receipt'] == true,
      driverName: _trimToNull(json['driver_name']),
      vehicleReference: _trimToNull(json['vehicle_reference']),
      deliveryReference: _trimToNull(json['delivery_reference']),
      dispatchedByRole: _trimToNull(json['dispatched_by_role']),
      receiptReview: rawReview is Map
          ? YorksV1ReceiptReview.fromRpcJson(
              Map<String, dynamic>.from(rawReview),
            )
          : null,
      lines: [
        for (final line in rawLines)
          if (line is Map)
            YorksV1DispatchLine.fromRpcJson(Map<String, dynamic>.from(line)),
      ],
    );
  }
}

/// Role-safe request-level logistics workspace. General warehouse availability
/// is server-filtered and never derived from the client role label.
class YorksV1LogisticsWorkspace {
  YorksV1LogisticsWorkspace({
    required this.requestId,
    required this.projectId,
    required this.requestState,
    required this.requestRecordVersion,
    required this.projectName,
    required this.scopeName,
    required this.canDispatch,
    required this.canConfirmReceipt,
    required List<YorksV1DispatchCandidate> dispatchCandidates,
    required List<YorksV1MaterialDispatch> dispatches,
    this.requestNumber,
  }) : dispatchCandidates = List.unmodifiable(dispatchCandidates),
       dispatches = List.unmodifiable(dispatches);

  final String requestId;
  final String projectId;
  final String? requestNumber;
  final String requestState;
  final int requestRecordVersion;
  final String projectName;
  final String scopeName;
  final bool canDispatch;
  final bool canConfirmReceipt;
  final List<YorksV1DispatchCandidate> dispatchCandidates;
  final List<YorksV1MaterialDispatch> dispatches;

  factory YorksV1LogisticsWorkspace.fromRpcJson(Map<String, dynamic> json) {
    final rawCandidates = json['dispatch_candidates'];
    final rawDispatches = json['dispatches'];
    if (rawCandidates is! List || rawDispatches is! List) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1LogisticsWorkspace(
      requestId: _requiredString(json, 'request_id'),
      projectId: _requiredString(json, 'project_id'),
      requestNumber: _trimToNull(json['request_number']),
      requestState: _requiredString(json, 'request_state'),
      requestRecordVersion: _positiveInt(json['request_record_version']),
      projectName: _requiredString(json, 'project_name'),
      scopeName: _requiredString(json, 'scope_name'),
      canDispatch: json['can_dispatch'] == true,
      canConfirmReceipt: json['can_confirm_receipt'] == true,
      dispatchCandidates: [
        for (final candidate in rawCandidates)
          if (candidate is Map)
            YorksV1DispatchCandidate.fromRpcJson(
              Map<String, dynamic>.from(candidate),
            ),
      ],
      dispatches: [
        for (final dispatch in rawDispatches)
          if (dispatch is Map)
            YorksV1MaterialDispatch.fromRpcJson(
              Map<String, dynamic>.from(dispatch),
            ),
      ],
    );
  }
}

class YorksV1InventoryWorkspace {
  YorksV1InventoryWorkspace({
    required List<YorksV1LogisticsInventoryItem> items,
    List<YorksV1InventoryCategory> categories = const [],
    List<YorksV1InventoryMovement> recentMovements = const [],
    List<YorksV1InventoryReservation> reservations = const [],
    YorksV1InventorySummary? summary,
    this.fetchedAt,
    this.totalMatches,
    this.pageOffset = 0,
    this.hasMore = false,
    this.availableUnits = const [],
  }) : items = List.unmodifiable(items),
       categories = List.unmodifiable(categories),
       recentMovements = List.unmodifiable(recentMovements),
       reservations = List.unmodifiable(reservations),
       summary = summary ?? YorksV1InventorySummary.fromItems(items);

  final List<YorksV1LogisticsInventoryItem> items;
  final List<YorksV1InventoryCategory> categories;
  final List<YorksV1InventoryMovement> recentMovements;
  final List<YorksV1InventoryReservation> reservations;
  final YorksV1InventorySummary summary;
  final DateTime? fetchedAt;
  final int? totalMatches;
  final int pageOffset;
  final bool hasMore;
  final List<String> availableUnits;

  factory YorksV1InventoryWorkspace.fromRpcJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final rawCategories = json['categories'];
    final rawMovements = json['recent_movements'];
    final rawReservations = json['reservations'];
    if (rawItems is! List) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    final items = [
      for (final item in rawItems)
        if (item is Map)
          YorksV1LogisticsInventoryItem.fromRpcJson(
            Map<String, dynamic>.from(item),
          ),
    ];
    final rawSummary = json['summary'];
    return YorksV1InventoryWorkspace(
      fetchedAt: DateTime.now(),
      totalMatches: json['total_matches'] as int?,
      pageOffset: json['page_offset'] as int? ?? 0,
      hasMore: json['has_more'] == true,
      availableUnits:
          (json['available_units'] as List?)?.cast<String>() ?? const [],
      items: items,
      categories: [
        if (rawCategories is List)
          for (final category in rawCategories)
            if (category is Map)
              YorksV1InventoryCategory.fromRpcJson(
                Map<String, dynamic>.from(category),
              ),
      ],
      recentMovements: [
        if (rawMovements is List)
          for (final movement in rawMovements)
            if (movement is Map)
              YorksV1InventoryMovement.fromRpcJson(
                Map<String, dynamic>.from(movement),
              ),
      ],
      reservations: [
        if (rawReservations is List)
          for (final reservation in rawReservations)
            if (reservation is Map)
              YorksV1InventoryReservation.fromRpcJson(
                Map<String, dynamic>.from(reservation),
              ),
      ],
      summary: rawSummary is Map
          ? YorksV1InventorySummary.fromRpcJson(
              Map<String, dynamic>.from(rawSummary),
            )
          : YorksV1InventorySummary.fromItems(items),
    );
  }
}

/// Role-safe inventory counts derived only from the operational projection.
///
/// The server still owns availability arithmetic. The Flutter value is a
/// display summary over the exact items that Procurement/Admin has already
/// been authorized to read; it never exposes commercial information.
class YorksV1InventorySummary {
  const YorksV1InventorySummary({
    required this.totalActiveItems,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.reservedCount,
    required this.incomingCount,
  });

  final int totalActiveItems;
  final int lowStockCount;
  final int outOfStockCount;
  final int reservedCount;
  final int incomingCount;

  int get attentionCount => lowStockCount + outOfStockCount;

  factory YorksV1InventorySummary.fromItems(
    List<YorksV1LogisticsInventoryItem> items,
  ) {
    var totalActiveItems = 0;
    var outOfStockCount = 0;
    var reservedCount = 0;
    for (final item in items) {
      if (!item.isActive) continue;
      totalActiveItems++;
      if ((_decimal(item.availableQuantity) ?? 0) <= 0) outOfStockCount++;
      if ((_decimal(item.reservedQuantity) ?? 0) > 0) reservedCount++;
    }
    // Yorks V1 does not yet model inbound purchase orders. Returning zero is
    // an honest projection of that deferred capability, not a fake stock count.
    return YorksV1InventorySummary(
      totalActiveItems: totalActiveItems,
      lowStockCount: 0,
      outOfStockCount: outOfStockCount,
      reservedCount: reservedCount,
      incomingCount: 0,
    );
  }

  factory YorksV1InventorySummary.fromRpcJson(Map<String, dynamic> json) =>
      YorksV1InventorySummary(
        totalActiveItems: _nonNegativeInt(json['total_active_items']),
        lowStockCount: _nonNegativeInt(json['low_stock_count']),
        outOfStockCount: _nonNegativeInt(json['out_of_stock_count']),
        reservedCount: _nonNegativeInt(json['reserved_count']),
        incomingCount: _nonNegativeInt(json['incoming_count']),
      );
}

enum YorksV1MaterialReturnState {
  draft('draft'),
  submitted('submitted'),
  awaitingApproval('awaiting_approval'),
  returnedForChanges('returned_for_changes'),
  approved('approved'),
  dispatched('dispatched'),
  confirmed('confirmed'),
  rejected('rejected'),
  cancelled('cancelled');

  const YorksV1MaterialReturnState(this.wireValue);
  final String wireValue;

  static YorksV1MaterialReturnState? fromWireValue(Object? value) {
    if (value is! String) return null;
    for (final state in values) {
      if (state.wireValue == value) return state;
    }
    return null;
  }
}

/// The exactly-four-column, cost-free payload retained for a Delivery Order.
class YorksV1DeliveryOrderLine {
  const YorksV1DeliveryOrderLine({
    required this.serialNumber,
    required this.description,
    required this.quantity,
    required this.unit,
    this.size,
    this.model,
  });

  final int serialNumber;
  final String description;
  final String quantity;
  final String unit;
  final String? size;
  final String? model;

  factory YorksV1DeliveryOrderLine.fromRpcJson(Map<String, dynamic> json) {
    return YorksV1DeliveryOrderLine(
      serialNumber: _positiveInt(json['s_no']),
      description: normalizeYorksV1ItemDescription(
        _requiredString(json, 'item_description'),
      ),
      size: _trimToNull(json['size']),
      model: _trimToNull(json['model']),
      quantity: _string(json['quantity']),
      unit: _requiredString(json, 'unit'),
    );
  }
}

/// Identifies the immutable evidence captured by a Delivery Order revision.
///
/// A dispatch snapshot records what Procurement committed. A receipt-review
/// snapshot records the confirmed good quantity for that same dispatch without
/// rewriting the original dispatch evidence.
enum YorksV1DeliveryOrderSnapshotKind {
  dispatch('dispatch'),
  receiptReview('receipt_review');

  const YorksV1DeliveryOrderSnapshotKind(this.wireValue);

  final String wireValue;

  static YorksV1DeliveryOrderSnapshotKind fromWireValue(Object? value) {
    if (value is String) {
      for (final kind in values) {
        if (kind.wireValue == value) return kind;
      }
    }
    // Revisions created before the explicit discriminator were generated only
    // from confirmed receipt-good lines. Preserve that provenance rather than
    // relabelling them as dispatch snapshots.
    return receiptReview;
  }
}

class YorksV1DeliveryOrderRevision {
  YorksV1DeliveryOrderRevision({
    required this.id,
    required this.revisionNumber,
    required this.isCurrent,
    required this.generatedAt,
    required this.generatedByDisplayName,
    required List<YorksV1DeliveryOrderLine> lines,
    this.snapshotKind = YorksV1DeliveryOrderSnapshotKind.dispatch,
    this.generatedByRole,
    this.documentIdentity,
    this.documentIdentityVerified = false,
  }) : lines = List.unmodifiable(lines);

  final String id;
  final int revisionNumber;
  final bool isCurrent;
  final DateTime generatedAt;
  final String generatedByDisplayName;
  final YorksV1DeliveryOrderSnapshotKind snapshotKind;
  final String? generatedByRole;
  final YorksV1DeliveryOrderDocumentIdentity? documentIdentity;
  final bool documentIdentityVerified;
  final List<YorksV1DeliveryOrderLine> lines;

  factory YorksV1DeliveryOrderRevision.fromRpcJson(Map<String, dynamic> json) {
    final rawLines = json['lines'];
    if (rawLines is! List) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1DeliveryOrderRevision(
      id: _requiredString(json, 'id'),
      revisionNumber: _positiveInt(json['revision_number']),
      isCurrent: json['is_current'] == true,
      generatedAt: _requiredDate(json, 'generated_at'),
      generatedByDisplayName: _requiredString(
        json,
        'generated_by_display_name',
      ),
      snapshotKind: YorksV1DeliveryOrderSnapshotKind.fromWireValue(
        json['snapshot_kind'],
      ),
      generatedByRole: _trimToNull(json['generated_by_role']),
      documentIdentity: json['document_identity'] is Map
          ? YorksV1DeliveryOrderDocumentIdentity.fromRpcJson(
              Map<String, dynamic>.from(json['document_identity'] as Map),
            )
          : null,
      documentIdentityVerified: json['document_identity_verified'] == true,
      lines: [
        for (final line in rawLines)
          if (line is Map)
            YorksV1DeliveryOrderLine.fromRpcJson(
              Map<String, dynamic>.from(line),
            ),
      ],
    );
  }
}

class YorksV1DeliveryOrderDocumentIdentity {
  const YorksV1DeliveryOrderDocumentIdentity({
    required this.projectId,
    required this.projectReference,
    required this.projectName,
    required this.scopeId,
    required this.scopeName,
    required this.dispatchId,
    required this.dispatchNumber,
    required this.dispatchDate,
    this.jobContractReference,
    this.scopeCode,
    this.mainContractorName,
    this.deliveryAddress,
    this.materialContext,
    this.requestNumber,
    this.deliveryReference,
    this.driverName,
    this.vehicleReference,
    this.dispatchedAt,
    this.dispatchedByDisplayName,
    this.dispatchedByExactRole,
  });

  final String projectId;
  final String projectReference;
  final String projectName;
  final String? jobContractReference;
  final String scopeId;
  final String scopeName;
  final String? scopeCode;
  final String? mainContractorName;
  final String? deliveryAddress;
  final String? materialContext;
  final String? requestNumber;
  final String dispatchId;
  final String dispatchNumber;
  final String? deliveryReference;
  final DateTime dispatchDate;
  final String? driverName;
  final String? vehicleReference;
  final DateTime? dispatchedAt;
  final String? dispatchedByDisplayName;
  final String? dispatchedByExactRole;

  factory YorksV1DeliveryOrderDocumentIdentity.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksV1DeliveryOrderDocumentIdentity(
    projectId: _requiredString(json, 'project_id'),
    projectReference: _requiredString(json, 'project_ref'),
    projectName: _requiredString(json, 'project_name'),
    jobContractReference: _trimToNull(json['job_contract_reference']),
    scopeId: _requiredString(json, 'scope_id'),
    scopeName: _requiredString(json, 'scope_name'),
    scopeCode: _trimToNull(json['scope_code']),
    mainContractorName: _trimToNull(json['main_contractor_name']),
    deliveryAddress: _trimToNull(json['delivery_address']),
    materialContext: _trimToNull(json['material_context']),
    requestNumber: _trimToNull(json['request_number']),
    dispatchId: _requiredString(json, 'dispatch_id'),
    dispatchNumber: _requiredString(json, 'dispatch_number'),
    deliveryReference: _trimToNull(json['delivery_reference']),
    dispatchDate: _requiredDate(json, 'dispatch_date'),
    driverName: _trimToNull(json['driver_name']),
    vehicleReference: _trimToNull(json['vehicle_reference']),
    dispatchedAt: _nullableDate(json['dispatched_at']),
    dispatchedByDisplayName: _trimToNull(json['dispatched_by_display_name']),
    dispatchedByExactRole: _trimToNull(json['dispatched_by_exact_role']),
  );
}

class YorksV1DeliveryOrder {
  YorksV1DeliveryOrder({
    required this.id,
    required this.dispatchId,
    required this.reference,
    required this.recordVersion,
    required List<YorksV1DeliveryOrderRevision> revisions,
    this.currentRevisionId,
  }) : revisions = List.unmodifiable(revisions);

  final String id;
  final String dispatchId;
  final String reference;
  final int recordVersion;
  final String? currentRevisionId;
  final List<YorksV1DeliveryOrderRevision> revisions;

  YorksV1DeliveryOrderRevision? get currentRevision {
    for (final revision in revisions) {
      if (revision.isCurrent || revision.id == currentRevisionId) {
        return revision;
      }
    }
    return revisions.isEmpty ? null : revisions.first;
  }

  factory YorksV1DeliveryOrder.fromRpcJson(Map<String, dynamic> json) {
    final rawRevisions = json['revisions'];
    if (rawRevisions is! List) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1DeliveryOrder(
      id: _requiredString(json, 'id'),
      dispatchId: _requiredString(json, 'dispatch_id'),
      reference: _requiredString(json, 'delivery_order_reference'),
      recordVersion: _positiveInt(json['record_version']),
      currentRevisionId: _trimToNull(json['current_revision_id']),
      revisions: [
        for (final revision in rawRevisions)
          if (revision is Map)
            YorksV1DeliveryOrderRevision.fromRpcJson(
              Map<String, dynamic>.from(revision),
            ),
      ],
    );
  }
}

class YorksV1DeliveryOrderDispatch {
  const YorksV1DeliveryOrderDispatch({
    required this.dispatchId,
    required this.dispatchNumber,
    required this.dispatchDate,
    required this.dispatchRecordVersion,
    required this.canGenerate,
    this.receiptReviewedAt,
    this.deliveryReference,
    this.deliveryOrder,
  });

  final String dispatchId;
  final String dispatchNumber;
  final DateTime dispatchDate;
  final int dispatchRecordVersion;
  final bool canGenerate;
  final DateTime? receiptReviewedAt;
  final String? deliveryReference;
  final YorksV1DeliveryOrder? deliveryOrder;

  factory YorksV1DeliveryOrderDispatch.fromRpcJson(Map<String, dynamic> json) {
    final rawOrder = json['delivery_order'];
    return YorksV1DeliveryOrderDispatch(
      dispatchId: _requiredString(json, 'dispatch_id'),
      dispatchNumber: _requiredString(json, 'dispatch_number'),
      dispatchDate: _requiredDate(json, 'dispatch_date'),
      dispatchRecordVersion: _positiveInt(json['dispatch_record_version']),
      canGenerate: json['can_generate'] == true,
      receiptReviewedAt: _nullableDate(json['receipt_reviewed_at']),
      deliveryReference: _trimToNull(json['delivery_reference']),
      deliveryOrder: rawOrder is Map
          ? YorksV1DeliveryOrder.fromRpcJson(
              Map<String, dynamic>.from(rawOrder),
            )
          : null,
    );
  }
}

class YorksV1ReturnCandidate {
  const YorksV1ReturnCandidate({
    required this.receiptReviewLineId,
    required this.dispatchNumber,
    required this.displayOrder,
    required this.description,
    required this.unit,
    required this.source,
    required this.goodReceivedQuantity,
    required this.confirmedReturnQuantity,
    required this.eligibleReturnQuantity,
    this.brandOrigin,
    this.sourceInventoryItemId,
  });

  final String receiptReviewLineId;
  final String dispatchNumber;
  final int displayOrder;
  final String description;
  final String? brandOrigin;
  final String unit;
  final YorksV1LogisticsSource source;
  final String goodReceivedQuantity;
  final String confirmedReturnQuantity;
  final String eligibleReturnQuantity;
  final String? sourceInventoryItemId;

  factory YorksV1ReturnCandidate.fromRpcJson(Map<String, dynamic> json) {
    return YorksV1ReturnCandidate(
      receiptReviewLineId: _requiredString(json, 'receipt_review_line_id'),
      dispatchNumber: _requiredString(json, 'dispatch_number'),
      displayOrder: _positiveInt(json['display_order']),
      description: normalizeYorksV1ItemDescription(
        _requiredString(json, 'item_description'),
      ),
      brandOrigin: _trimToNull(json['brand_origin']),
      unit: _requiredString(json, 'unit'),
      source: YorksV1LogisticsSource.fromWireValue(json['source_kind']),
      goodReceivedQuantity: _string(json['good_received_qty']),
      confirmedReturnQuantity: _string(json['confirmed_return_qty']),
      eligibleReturnQuantity: _string(json['eligible_return_qty']),
      sourceInventoryItemId: _trimToNull(json['source_inventory_item_id']),
    );
  }
}

class YorksV1ReturnInventoryItem {
  const YorksV1ReturnInventoryItem({
    required this.id,
    required this.description,
    required this.unit,
    this.brandOrigin,
  });

  final String id;
  final String description;
  final String? brandOrigin;
  final String unit;

  factory YorksV1ReturnInventoryItem.fromRpcJson(Map<String, dynamic> json) {
    return YorksV1ReturnInventoryItem(
      id: _requiredString(json, 'id'),
      description: normalizeYorksV1ItemDescription(
        _requiredString(json, 'item_description'),
      ),
      brandOrigin: _trimToNull(json['brand_origin']),
      unit: _requiredString(json, 'unit'),
    );
  }
}

class YorksV1MaterialReturnLine {
  const YorksV1MaterialReturnLine({
    required this.id,
    required this.receiptReviewLineId,
    required this.dispatchNumber,
    required this.displayOrder,
    required this.description,
    required this.unit,
    required this.source,
    required this.goodQuantitySnapshot,
    required this.returnQuantity,
    this.brandOrigin,
    this.eligibleQuantityAtSubmit,
    this.targetInventoryItemId,
  });

  final String id;
  final String receiptReviewLineId;
  final String dispatchNumber;
  final int displayOrder;
  final String description;
  final String? brandOrigin;
  final String unit;
  final YorksV1LogisticsSource source;
  final String goodQuantitySnapshot;
  final String? eligibleQuantityAtSubmit;
  final String returnQuantity;
  final String? targetInventoryItemId;

  factory YorksV1MaterialReturnLine.fromRpcJson(Map<String, dynamic> json) {
    return YorksV1MaterialReturnLine(
      id: _requiredString(json, 'id'),
      receiptReviewLineId: _requiredString(json, 'receipt_review_line_id'),
      dispatchNumber: _requiredString(json, 'dispatch_number'),
      displayOrder: _positiveInt(json['display_order']),
      description: normalizeYorksV1ItemDescription(
        _requiredString(json, 'item_description'),
      ),
      brandOrigin: _trimToNull(json['brand_origin']),
      unit: _requiredString(json, 'unit'),
      source: YorksV1LogisticsSource.fromWireValue(json['source_kind']),
      goodQuantitySnapshot: _string(json['good_quantity_snapshot']),
      eligibleQuantityAtSubmit: _trimToNull(
        json['eligible_quantity_at_submit'],
      ),
      returnQuantity: _string(json['return_quantity']),
      targetInventoryItemId: _trimToNull(json['target_inventory_item_id']),
    );
  }
}

class YorksV1MaterialReturn {
  YorksV1MaterialReturn({
    required this.id,
    required this.state,
    required this.recordVersion,
    required this.draftedAt,
    required this.draftedByDisplayName,
    required this.canEditDraft,
    required this.canSubmit,
    required this.canConfirm,
    required this.canReject,
    required List<YorksV1MaterialReturnLine> lines,
    this.number,
    this.note,
    this.submittedAt,
    this.submittedByDisplayName,
    this.decidedAt,
    this.decidedByDisplayName,
    this.rejectionReason,
  }) : lines = List.unmodifiable(lines);

  final String id;
  final String? number;
  final YorksV1MaterialReturnState state;
  final String? note;
  final int recordVersion;
  final DateTime draftedAt;
  final String draftedByDisplayName;
  final DateTime? submittedAt;
  final String? submittedByDisplayName;
  final DateTime? decidedAt;
  final String? decidedByDisplayName;
  final String? rejectionReason;
  final bool canEditDraft;
  final bool canSubmit;
  final bool canConfirm;
  final bool canReject;
  final List<YorksV1MaterialReturnLine> lines;

  factory YorksV1MaterialReturn.fromRpcJson(Map<String, dynamic> json) {
    final rawLines = json['lines'];
    final state = YorksV1MaterialReturnState.fromWireValue(json['state']);
    if (rawLines is! List || state == null) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1MaterialReturn(
      id: _requiredString(json, 'id'),
      number: _trimToNull(json['return_number']),
      state: state,
      note: _trimToNull(json['note']),
      recordVersion: _positiveInt(json['record_version']),
      draftedAt: _requiredDate(json, 'drafted_at'),
      draftedByDisplayName: _requiredString(json, 'drafted_by_display_name'),
      submittedAt: _nullableDate(json['submitted_at']),
      submittedByDisplayName: _trimToNull(json['submitted_by_display_name']),
      decidedAt: _nullableDate(json['decided_at']),
      decidedByDisplayName: _trimToNull(json['decided_by_display_name']),
      rejectionReason: _trimToNull(json['rejection_reason']),
      canEditDraft: json['can_edit_draft'] == true,
      canSubmit: json['can_submit'] == true,
      canConfirm: json['can_confirm'] == true,
      canReject: json['can_reject'] == true,
      lines: [
        for (final line in rawLines)
          if (line is Map)
            YorksV1MaterialReturnLine.fromRpcJson(
              Map<String, dynamic>.from(line),
            ),
      ],
    );
  }
}

class YorksV1ReturnsDocumentsWorkspace {
  YorksV1ReturnsDocumentsWorkspace({
    required this.requestId,
    required this.projectId,
    required this.requestState,
    required this.requestRecordVersion,
    required this.projectName,
    required this.projectReference,
    required this.scopeName,
    required this.canGenerateDeliveryOrder,
    required this.canSubmitMaterialReturn,
    required this.canConfirmMaterialReturn,
    required List<YorksV1DeliveryOrderDispatch> deliveryOrderDispatches,
    required List<YorksV1ReturnCandidate> returnCandidates,
    required List<YorksV1MaterialReturn> materialReturns,
    required List<YorksV1ReturnInventoryItem> returnInventoryItems,
    this.requestNumber,
    this.jobContractReference,
    this.scopeCode,
    this.mainContractorName,
    this.deliveryAddress,
    this.materialContext,
  }) : deliveryOrderDispatches = List.unmodifiable(deliveryOrderDispatches),
       returnCandidates = List.unmodifiable(returnCandidates),
       materialReturns = List.unmodifiable(materialReturns),
       returnInventoryItems = List.unmodifiable(returnInventoryItems);

  final String requestId;
  final String projectId;
  final String? requestNumber;
  final String requestState;
  final int requestRecordVersion;
  final String projectName;
  final String projectReference;
  final String? jobContractReference;
  final String scopeName;
  final String? scopeCode;
  final String? mainContractorName;
  final String? deliveryAddress;
  final String? materialContext;
  final bool canGenerateDeliveryOrder;
  final bool canSubmitMaterialReturn;
  final bool canConfirmMaterialReturn;
  final List<YorksV1DeliveryOrderDispatch> deliveryOrderDispatches;
  final List<YorksV1ReturnCandidate> returnCandidates;
  final List<YorksV1MaterialReturn> materialReturns;
  final List<YorksV1ReturnInventoryItem> returnInventoryItems;

  factory YorksV1ReturnsDocumentsWorkspace.fromRpcJson(
    Map<String, dynamic> json,
  ) {
    final rawOrders = json['delivery_orders'];
    final rawCandidates = json['return_candidates'];
    final rawReturns = json['returns'];
    final rawInventoryItems = json['return_inventory_items'];
    if (rawOrders is! List ||
        rawCandidates is! List ||
        rawReturns is! List ||
        rawInventoryItems is! List) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1ReturnsDocumentsWorkspace(
      requestId: _requiredString(json, 'request_id'),
      projectId: _requiredString(json, 'project_id'),
      requestNumber: _trimToNull(json['request_number']),
      requestState: _requiredString(json, 'request_state'),
      requestRecordVersion: _positiveInt(json['request_record_version']),
      projectName: _requiredString(json, 'project_name'),
      projectReference: _requiredString(json, 'project_ref'),
      jobContractReference: _trimToNull(json['job_contract_reference']),
      scopeName: _requiredString(json, 'scope_name'),
      scopeCode: _trimToNull(json['scope_code']),
      mainContractorName: _trimToNull(json['main_contractor_name']),
      deliveryAddress: _trimToNull(json['delivery_address']),
      materialContext: _trimToNull(json['material_context']),
      canGenerateDeliveryOrder: json['can_generate_delivery_order'] == true,
      canSubmitMaterialReturn: json['can_submit_material_return'] == true,
      canConfirmMaterialReturn: json['can_confirm_material_return'] == true,
      deliveryOrderDispatches: [
        for (final dispatch in rawOrders)
          if (dispatch is Map)
            YorksV1DeliveryOrderDispatch.fromRpcJson(
              Map<String, dynamic>.from(dispatch),
            ),
      ],
      returnCandidates: [
        for (final candidate in rawCandidates)
          if (candidate is Map)
            YorksV1ReturnCandidate.fromRpcJson(
              Map<String, dynamic>.from(candidate),
            ),
      ],
      materialReturns: [
        for (final materialReturn in rawReturns)
          if (materialReturn is Map)
            YorksV1MaterialReturn.fromRpcJson(
              Map<String, dynamic>.from(materialReturn),
            ),
      ],
      returnInventoryItems: [
        for (final item in rawInventoryItems)
          if (item is Map)
            YorksV1ReturnInventoryItem.fromRpcJson(
              Map<String, dynamic>.from(item),
            ),
      ],
    );
  }
}

class YorksV1InventoryAdjustmentInput {
  const YorksV1InventoryAdjustmentInput({
    required this.quantityDelta,
    required this.reason,
    required this.idempotencyKey,
    this.inventoryItemId,
    this.description,
    this.itemCode,
    this.categoryId,
    this.newCategoryName,
    this.sourceCategoryText,
    this.brandOrigin,
    this.unit,
    this.minimumStock,
    this.locationBin,
    this.notes,
    this.sizeText,
    this.modelReference,
    this.newCategoryParentId,
    this.expectedVersion,
    this.action,
    this.reference,
  });

  final String quantityDelta;
  final String reason;
  final String idempotencyKey;
  final String? inventoryItemId;
  final String? description;
  final String? itemCode;
  final String? categoryId;
  final String? newCategoryName;
  final String? sourceCategoryText;
  final String? brandOrigin;
  final String? unit;
  final String? minimumStock;
  final String? locationBin;
  final String? notes;
  final String? sizeText;
  final String? modelReference;
  final String? newCategoryParentId;
  final int? expectedVersion;
  final String? action;
  final String? reference;

  Map<String, Object?> toRecoveryJson() => {
    'quantityDelta': quantityDelta,
    'reason': reason,
    'idempotencyKey': idempotencyKey,
    'inventoryItemId': inventoryItemId,
    'description': description,
    'itemCode': itemCode,
    'categoryId': categoryId,
    'newCategoryName': newCategoryName,
    'sourceCategoryText': sourceCategoryText,
    'brandOrigin': brandOrigin,
    'unit': unit,
    'minimumStock': minimumStock,
    'locationBin': locationBin,
    'notes': notes,
    'sizeText': sizeText,
    'modelReference': modelReference,
    'newCategoryParentId': newCategoryParentId,
    'expectedVersion': expectedVersion,
    'action': action,
    'reference': reference,
  };

  factory YorksV1InventoryAdjustmentInput.fromRecoveryJson(
    Map<String, dynamic> json,
  ) {
    final value = YorksV1InventoryAdjustmentInput(
      quantityDelta: json['quantityDelta'] as String,
      reason: json['reason'] as String,
      idempotencyKey: json['idempotencyKey'] as String,
      inventoryItemId: json['inventoryItemId'] as String?,
      description: json['description'] as String?,
      itemCode: json['itemCode'] as String?,
      categoryId: json['categoryId'] as String?,
      newCategoryName: json['newCategoryName'] as String?,
      sourceCategoryText: json['sourceCategoryText'] as String?,
      brandOrigin: json['brandOrigin'] as String?,
      unit: json['unit'] as String?,
      minimumStock: json['minimumStock'] as String?,
      locationBin: json['locationBin'] as String?,
      notes: json['notes'] as String?,
      sizeText: json['sizeText'] as String?,
      modelReference: json['modelReference'] as String?,
      newCategoryParentId: json['newCategoryParentId'] as String?,
      expectedVersion: json['expectedVersion'] as int?,
      action: json['action'] as String?,
      reference: json['reference'] as String?,
    );
    if (json.keys.any((key) => !value.toRecoveryJson().containsKey(key))) {
      throw const FormatException('Unsupported stock recovery fields');
    }
    return value;
  }

  bool get createsItem => _trimToNull(inventoryItemId) == null;

  YorksV1InventoryAdjustmentInput withIdempotencyKey(String value) =>
      YorksV1InventoryAdjustmentInput(
        quantityDelta: quantityDelta,
        reason: reason,
        idempotencyKey: value,
        inventoryItemId: inventoryItemId,
        description: description,
        itemCode: itemCode,
        categoryId: categoryId,
        newCategoryName: newCategoryName,
        sourceCategoryText: sourceCategoryText,
        brandOrigin: brandOrigin,
        unit: unit,
        minimumStock: minimumStock,
        locationBin: locationBin,
        notes: notes,
        sizeText: sizeText,
        modelReference: modelReference,
        newCategoryParentId: newCategoryParentId,
        expectedVersion: expectedVersion,
        action: action,
        reference: reference,
      );

  Map<String, Object?> toCreateItemRpcPayload() => {
    'item_code': _trimToNull(itemCode),
    'item_description': _normalizedDescriptionOrNull(description),
    'category_id': _trimToNull(categoryId),
    'new_category_name': _trimToNull(newCategoryName),
    'new_category_parent_id': _trimToNull(newCategoryParentId),
    'source_category_text': _trimToNull(sourceCategoryText),
    'brand_origin': normalizeYorksV1OptionalItemText(brandOrigin),
    'size_text': normalizeYorksV1OptionalItemText(sizeText),
    'model_reference': normalizeYorksV1OptionalItemText(modelReference),
    'unit': _trimToNull(unit),
    'minimum_stock': _trimToNull(minimumStock),
    'location_bin': _trimToNull(locationBin),
    'notes': _trimToNull(notes),
    'opening_quantity': quantityDelta.trim(),
    'opening_reference': _trimToNull(reference),
    'reason': reason.trim(),
  };

  Map<String, Object?> toStockMovementRpcPayload() => {
    'inventory_item_id': inventoryItemId,
    'expected_version': expectedVersion,
    'action': action,
    'quantity': quantityDelta.trim(),
    'reason': reason.trim(),
    'reference': _trimToNull(reference),
  };

  Map<String, Object?> toRpcPayload() => {
    'inventory_item_id': _trimToNull(inventoryItemId),
    'item_code': _trimToNull(itemCode),
    'item_description': _normalizedDescriptionOrNull(description),
    'category_id': _trimToNull(categoryId),
    'new_category_name': _trimToNull(newCategoryName),
    'source_category_text': _trimToNull(sourceCategoryText),
    'brand_origin': normalizeYorksV1OptionalItemText(brandOrigin),
    'unit': _trimToNull(unit),
    'minimum_stock': _trimToNull(minimumStock),
    'location_bin': _trimToNull(locationBin),
    'notes': _trimToNull(notes),
    'quantity_delta': quantityDelta.trim(),
    'reason': reason.trim(),
  };
}

/// A metadata-only item-master command. Quantity and reservations deliberately
/// do not appear in this payload: the server owns them through append-only
/// movements and approved Material Request arrangements.
class YorksV1InventoryItemMetadataInput {
  const YorksV1InventoryItemMetadataInput({
    required this.inventoryItemId,
    required this.expectedMetadataVersion,
    required this.itemCode,
    required this.description,
    required this.categoryId,
    required this.brandOrigin,
    required this.sizeText,
    required this.modelReference,
    required this.unit,
    required this.minimumStock,
    required this.locationBin,
    required this.notes,
    required this.idempotencyKey,
    this.newCategoryName,
    this.newCategoryParentId,
    this.sourceCategoryText,
  });

  final String inventoryItemId;
  final int expectedMetadataVersion;
  final String? itemCode;
  final String description;
  final String? categoryId;
  final String? newCategoryName;
  final String? newCategoryParentId;
  final String? sourceCategoryText;
  final String? brandOrigin;
  final String? sizeText;
  final String? modelReference;
  final String unit;
  final String? minimumStock;
  final String? locationBin;
  final String? notes;
  final String idempotencyKey;

  Map<String, Object?> toRpcPayload() => {
    'inventory_item_id': inventoryItemId,
    'expected_metadata_version': expectedMetadataVersion,
    'item_code': _trimToNull(itemCode),
    'item_description': normalizeYorksV1ItemDescription(description),
    'category_id': _trimToNull(categoryId),
    'new_category_name': _trimToNull(newCategoryName),
    'new_category_parent_id': _trimToNull(newCategoryParentId),
    'source_category_text': _trimToNull(sourceCategoryText),
    'brand_origin': normalizeYorksV1OptionalItemText(brandOrigin),
    'size_text': normalizeYorksV1OptionalItemText(sizeText),
    'model_reference': normalizeYorksV1OptionalItemText(modelReference),
    'unit': unit.trim(),
    'minimum_stock': _trimToNull(minimumStock),
    'location_bin': _trimToNull(locationBin),
    'notes': _trimToNull(notes),
  };
}

class YorksV1InventoryCategoryCreationInput {
  const YorksV1InventoryCategoryCreationInput({
    required this.name,
    required this.idempotencyKey,
    this.parentCategoryId,
  });

  final String name;
  final String idempotencyKey;
  final String? parentCategoryId;

  Map<String, Object?> toRpcPayload() => {
    'name': name.trim(),
    'parent_category_id': _trimToNull(parentCategoryId),
  };
}

class YorksV1InventoryImportRowInput {
  const YorksV1InventoryImportRowInput({
    required this.sourceRowNumber,
    required this.description,
    required this.unit,
    required this.stockAction,
    required this.quantity,
    required this.reason,
    this.inventoryItemId,
    this.itemCode,
    this.categoryId,
    this.newCategoryName,
    this.sourceCategoryText,
    this.brandOrigin,
    this.minimumStock,
    this.locationBin,
    this.notes,
  });

  final int sourceRowNumber;
  final String? inventoryItemId;
  final String? itemCode;
  final String description;
  final String? categoryId;
  final String? newCategoryName;
  final String? sourceCategoryText;
  final String? brandOrigin;
  final String unit;
  final String stockAction;
  final String quantity;
  final String reason;
  final String? minimumStock;
  final String? locationBin;
  final String? notes;

  factory YorksV1InventoryImportRowInput.fromRecoveryJson(
    Map<String, dynamic> json,
  ) {
    final value = YorksV1InventoryImportRowInput(
      sourceRowNumber: json['source_row_number'] as int,
      inventoryItemId: json['inventory_item_id'] as String?,
      itemCode: json['item_code'] as String?,
      description: json['item_description'] as String,
      categoryId: json['category_id'] as String?,
      newCategoryName: json['new_category_name'] as String?,
      sourceCategoryText: json['source_category_text'] as String?,
      brandOrigin: json['brand_origin'] as String?,
      unit: json['unit'] as String,
      stockAction: json['stock_action'] as String,
      quantity: json['quantity'] as String,
      reason: json['reason'] as String,
      minimumStock: json['minimum_stock'] as String?,
      locationBin: json['location_bin'] as String?,
      notes: json['notes'] as String?,
    );
    if (json.keys.any((key) => !value.toRpcJson().containsKey(key))) {
      throw const FormatException('Unsupported import recovery fields');
    }
    return value;
  }

  Map<String, Object?> toRpcJson() => {
    'source_row_number': sourceRowNumber,
    'inventory_item_id': _trimToNull(inventoryItemId),
    'item_code': _trimToNull(itemCode),
    'item_description': normalizeYorksV1ItemDescription(description),
    'category_id': _trimToNull(categoryId),
    'new_category_name': _trimToNull(newCategoryName),
    'source_category_text': _trimToNull(sourceCategoryText),
    'brand_origin': normalizeYorksV1OptionalItemText(brandOrigin),
    'unit': unit.trim(),
    'stock_action': stockAction.trim(),
    'quantity': quantity.trim(),
    'reason': reason.trim(),
    'minimum_stock': _trimToNull(minimumStock),
    'location_bin': _trimToNull(locationBin),
    'notes': _trimToNull(notes),
  };
}

class YorksV1InventoryImportInput {
  YorksV1InventoryImportInput({
    required this.fileName,
    required List<YorksV1InventoryImportRowInput> rows,
    required this.idempotencyKey,
  }) : rows = List.unmodifiable(rows);

  final String fileName;
  final List<YorksV1InventoryImportRowInput> rows;
  final String idempotencyKey;

  Map<String, Object?> toRpcPayload() => {
    'file_name': fileName.trim(),
    'rows': [for (final row in rows) row.toRpcJson()],
  };
}

class YorksV1InventoryImportResult {
  const YorksV1InventoryImportResult({
    required this.importBatchId,
    required this.rowCount,
    required this.createdItems,
    required this.updatedItems,
    required this.createdCategories,
    this.createdSuppliers = 0,
    this.receiptBatches = 0,
    this.movements = 0,
    this.warningCount = 0,
    this.excludedCount = 0,
    this.unknownSupplierRows = 0,
    this.unitTotals = const [],
  });

  final String importBatchId;
  final int rowCount;
  final int createdItems;
  final int updatedItems;
  final int createdCategories;
  final int createdSuppliers;
  final int receiptBatches;
  final int movements;
  final int warningCount;
  final int excludedCount;
  final int unknownSupplierRows;
  final List<YorksV1InventoryImportUnitTotal> unitTotals;

  factory YorksV1InventoryImportResult.fromRpcJson(Map<String, dynamic> json) =>
      YorksV1InventoryImportResult(
        importBatchId: _requiredString(json, 'import_batch_id'),
        rowCount: _nonNegativeInt(json['row_count']),
        createdItems: _nonNegativeInt(json['created_items']),
        updatedItems: _nonNegativeInt(json['updated_items']),
        createdCategories: _nonNegativeInt(json['created_categories']),
        createdSuppliers: _nonNegativeInt(json['created_suppliers'] ?? 0),
        receiptBatches: _nonNegativeInt(json['receipt_batches'] ?? 0),
        movements: _nonNegativeInt(json['movements'] ?? 0),
        warningCount: _nonNegativeInt(json['warning_count'] ?? 0),
        excludedCount: _nonNegativeInt(json['excluded_count'] ?? 0),
        unknownSupplierRows: _nonNegativeInt(
          json['unknown_supplier_rows'] ?? 0,
        ),
        unitTotals: _jsonList(json['unit_totals'])
            .map(YorksV1InventoryImportUnitTotal.fromRpcJson)
            .toList(growable: false),
      );
}

class YorksV1InventoryImportUnitTotal {
  const YorksV1InventoryImportUnitTotal({
    required this.unit,
    required this.acceptedQuantity,
    required this.damagedQuantity,
    required this.rejectedQuantity,
  });

  final String unit;
  final String acceptedQuantity;
  final String damagedQuantity;
  final String rejectedQuantity;

  factory YorksV1InventoryImportUnitTotal.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksV1InventoryImportUnitTotal(
    unit: _requiredString(json, 'unit'),
    acceptedQuantity: _string(json['accepted_qty']),
    damagedQuantity: _string(json['damaged_qty']),
    rejectedQuantity: _string(json['rejected_qty']),
  );
}

class YorksV1InventoryItemStateInput {
  const YorksV1InventoryItemStateInput({
    required this.inventoryItemId,
    required this.expectedVersion,
    required this.isActive,
    required this.reason,
    required this.idempotencyKey,
  });

  final String inventoryItemId;
  final int expectedVersion;
  final bool isActive;
  final String reason;
  final String idempotencyKey;

  Map<String, Object?> toRpcPayload() => {
    'inventory_item_id': inventoryItemId,
    'expected_version': expectedVersion,
    'is_active': isActive,
    'reason': reason.trim(),
  };
}

class YorksV1DispatchLineInput {
  const YorksV1DispatchLineInput({
    required this.requestLineId,
    required this.dispatchQuantity,
  });

  final String requestLineId;
  final String dispatchQuantity;

  Map<String, Object?> toRpcJson() => {
    'request_line_id': requestLineId,
    'dispatch_qty': dispatchQuantity.trim(),
  };
}

class YorksV1DispatchInput {
  YorksV1DispatchInput({
    required this.requestId,
    required this.expectedRequestVersion,
    required this.dispatchDate,
    required this.deliveryReference,
    required List<YorksV1DispatchLineInput> lines,
    required this.idempotencyKey,
    this.driverName,
    this.vehicleReference,
  }) : lines = List.unmodifiable(lines);

  final String requestId;
  final int expectedRequestVersion;
  final DateTime dispatchDate;
  final String deliveryReference;
  final List<YorksV1DispatchLineInput> lines;
  final String idempotencyKey;
  final String? driverName;
  final String? vehicleReference;

  Map<String, Object?> toRpcPayload() => {
    'request_id': requestId,
    'expected_version': expectedRequestVersion,
    'dispatch_date': _dateOnly(dispatchDate),
    'delivery_reference': _trimToNull(deliveryReference),
    'driver_name': _trimToNull(driverName),
    'vehicle_reference': _trimToNull(vehicleReference),
    'lines': [for (final line in lines) line.toRpcJson()],
  };
}

class YorksV1ReceiptLineInput {
  const YorksV1ReceiptLineInput({
    required this.dispatchLineId,
    required this.outcome,
    required this.goodQuantity,
    this.missingQuantity,
    this.damagedQuantity,
    this.note,
  });

  final String dispatchLineId;
  final YorksV1ReceiptOutcome outcome;
  final String goodQuantity;
  final String? missingQuantity;
  final String? damagedQuantity;
  final String? note;

  Map<String, Object?> toRpcJson() => {
    'dispatch_line_id': dispatchLineId,
    'outcome': outcome.wireValue,
    'good_qty': goodQuantity.trim(),
    'missing_qty': _trimToNull(missingQuantity),
    'damaged_qty': _trimToNull(damagedQuantity),
    'note': _trimToNull(note),
  };
}

class YorksV1ReceiptConfirmationInput {
  YorksV1ReceiptConfirmationInput({
    required this.requestId,
    required this.dispatchId,
    required this.expectedRequestVersion,
    required this.expectedDispatchVersion,
    required List<YorksV1ReceiptLineInput> lines,
    required this.idempotencyKey,
  }) : lines = List.unmodifiable(lines);

  final String requestId;
  final String dispatchId;
  final int expectedRequestVersion;
  final int expectedDispatchVersion;
  final List<YorksV1ReceiptLineInput> lines;
  final String idempotencyKey;

  Map<String, Object?> toRpcPayload() => {
    'request_id': requestId,
    'dispatch_id': dispatchId,
    'expected_request_version': expectedRequestVersion,
    'expected_dispatch_version': expectedDispatchVersion,
    'lines': [for (final line in lines) line.toRpcJson()],
  };
}

class YorksV1DeliveryOrderGenerationInput {
  const YorksV1DeliveryOrderGenerationInput({
    required this.requestId,
    required this.dispatchId,
    required this.expectedRequestVersion,
    required this.expectedDispatchVersion,
    required this.deliveryOrderReference,
    required this.idempotencyKey,
  });

  final String requestId;
  final String dispatchId;
  final int expectedRequestVersion;
  final int expectedDispatchVersion;
  final String deliveryOrderReference;
  final String idempotencyKey;

  Map<String, Object?> toRpcPayload() => {
    'request_id': requestId,
    'dispatch_id': dispatchId,
    'expected_request_version': expectedRequestVersion,
    'expected_dispatch_version': expectedDispatchVersion,
    'delivery_order_reference': _normalizeDeliveryOrderReference(
      deliveryOrderReference,
    ),
  };
}

class YorksV1MaterialReturnDraftLineInput {
  const YorksV1MaterialReturnDraftLineInput({
    required this.receiptReviewLineId,
    required this.returnQuantity,
  });

  final String receiptReviewLineId;
  final String returnQuantity;

  Map<String, Object?> toRpcJson() => {
    'receipt_review_line_id': receiptReviewLineId,
    'return_qty': returnQuantity.trim(),
  };
}

class YorksV1MaterialReturnDraftInput {
  YorksV1MaterialReturnDraftInput({
    required this.requestId,
    required this.expectedVersion,
    required List<YorksV1MaterialReturnDraftLineInput> lines,
    required this.idempotencyKey,
    this.returnId,
    this.note,
  }) : lines = List.unmodifiable(lines);

  final String? returnId;
  final String requestId;
  final int expectedVersion;
  final String? note;
  final List<YorksV1MaterialReturnDraftLineInput> lines;
  final String idempotencyKey;

  Map<String, Object?> toRpcPayload() => {
    'return_id': _trimToNull(returnId),
    'request_id': requestId,
    'expected_version': expectedVersion,
    'note': _trimToNull(note),
    'lines': [for (final line in lines) line.toRpcJson()],
  };
}

class YorksV1MaterialReturnSubmissionInput {
  const YorksV1MaterialReturnSubmissionInput({
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

class YorksV1NewReturnInventoryItemInput {
  const YorksV1NewReturnInventoryItemInput({
    required this.description,
    required this.unit,
    this.brandOrigin,
  });

  final String description;
  final String? brandOrigin;
  final String unit;

  Map<String, Object?> toRpcJson() => {
    'item_description': normalizeYorksV1ItemDescription(description),
    'brand_origin': _trimToNull(brandOrigin),
    'unit': unit.trim(),
  };
}

class YorksV1MaterialReturnLineMappingInput {
  const YorksV1MaterialReturnLineMappingInput({
    required this.returnLineId,
    this.inventoryItemId,
    this.newInventoryItem,
  });

  final String returnLineId;
  final String? inventoryItemId;
  final YorksV1NewReturnInventoryItemInput? newInventoryItem;

  Map<String, Object?> toRpcJson() => {
    'return_line_id': returnLineId,
    'inventory_item_id': _trimToNull(inventoryItemId),
    'new_inventory_item': newInventoryItem?.toRpcJson(),
  };
}

class YorksV1MaterialReturnConfirmationInput {
  YorksV1MaterialReturnConfirmationInput({
    required this.returnId,
    required this.expectedVersion,
    required List<YorksV1MaterialReturnLineMappingInput> lineMappings,
    required this.idempotencyKey,
  }) : lineMappings = List.unmodifiable(lineMappings);

  final String returnId;
  final int expectedVersion;
  final List<YorksV1MaterialReturnLineMappingInput> lineMappings;
  final String idempotencyKey;

  Map<String, Object?> toRpcPayload() => {
    'return_id': returnId,
    'expected_version': expectedVersion,
    'line_mappings': [for (final mapping in lineMappings) mapping.toRpcJson()],
  };
}

class YorksV1MaterialReturnRejectionInput {
  const YorksV1MaterialReturnRejectionInput({
    required this.returnId,
    required this.expectedVersion,
    required this.reason,
    required this.idempotencyKey,
  });

  final String returnId;
  final int expectedVersion;
  final String reason;
  final String idempotencyKey;

  Map<String, Object?> toRpcPayload() => {
    'return_id': returnId,
    'expected_version': expectedVersion,
    'reason': reason.trim(),
  };
}

String _dateOnly(DateTime date) {
  final local = date.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

String _normalizeDeliveryOrderReference(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();

String _string(Object? value) => switch (value) {
  String text => text,
  num number => number.toString(),
  _ => '',
};

String? _trimToNull(Object? value) {
  final text = _string(value).trim();
  return text.isEmpty ? null : text;
}

String? _normalizedDescriptionOrNull(Object? value) {
  final trimmed = _trimToNull(value);
  return trimmed == null ? null : normalizeYorksV1ItemDescription(trimmed);
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

int? _nullableInt(Object? value) {
  return switch (value) {
    int integer => integer,
    num number => number.toInt(),
    String text => int.tryParse(text),
    _ => null,
  };
}

double? _nullableDouble(Object? value) {
  return switch (value) {
    num number => number.toDouble(),
    String text => double.tryParse(text),
    _ => null,
  };
}

int _nonNegativeInt(Object? value) {
  final parsed = _nullableInt(value) ?? 0;
  return parsed < 0 ? 0 : parsed;
}

num? _decimal(String value) => num.tryParse(value.trim());

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
  return DateTime.tryParse(value)?.toUtc();
}

List<Map<String, dynamic>> _jsonList(Object? value) {
  if (value == null) return const [];
  if (value is! List) {
    throw const YorksV1DomainException(
      YorksV1DomainErrorCode.unexpectedResponse,
    );
  }
  return [
    for (final entry in value)
      if (entry is Map)
        Map<String, dynamic>.from(entry)
      else
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.unexpectedResponse,
        ),
  ];
}

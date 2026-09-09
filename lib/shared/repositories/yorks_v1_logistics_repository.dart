import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/yorks_v1_domain_error.dart';
import '../models/analytics_event.dart';
import '../models/yorks_v1_feature_flags.dart';
import '../models/yorks_v1_logistics.dart';
import '../models/yorks_v1_material_return_workflow.dart';
import '../models/yorks_v1_material_request.dart';
import '../sync/connectivity_service.dart';
import '../services/analytics_service.dart';
import 'yorks_v1_material_request_repository.dart';

/// Typed Batch 7 server boundary. Widgets can neither access a Supabase client
/// nor mutate local stock/request state; every committed effect is an RPC.
abstract interface class YorksV1LogisticsRepository {
  Future<YorksV1InventoryWorkspace> getInventory({String? search});

  Future<YorksV1InventoryItemDetail> getInventoryItem(String inventoryItemId);

  Future<YorksV1LogisticsInventoryItem> adjustInventory(
    YorksV1InventoryAdjustmentInput input,
  );

  Future<YorksV1InventoryCategory> createInventoryCategory(
    YorksV1InventoryCategoryCreationInput input,
  );

  Future<YorksV1InventoryImportResult> importInventory(
    YorksV1InventoryImportInput input,
  );

  Future<YorksV1LogisticsInventoryItem> setInventoryItemActive(
    YorksV1InventoryItemStateInput input,
  );

  Future<YorksV1LogisticsWorkspace> getWorkspace(String requestId);

  Future<List<YorksV1ProjectMaterialMovement>> getProjectMaterialMovements(
    String projectId,
  );

  Future<YorksV1LogisticsWorkspace> dispatch(YorksV1DispatchInput input);

  Future<YorksV1LogisticsWorkspace> confirmReceipt(
    YorksV1ReceiptConfirmationInput input,
  );

  Future<YorksV1ReturnsDocumentsWorkspace> getReturnsDocumentsWorkspace(
    String requestId,
  );

  Future<YorksV1ReturnsDocumentsWorkspace> generateDeliveryOrder(
    YorksV1DeliveryOrderGenerationInput input,
  );

  Future<YorksV1ReturnsDocumentsWorkspace> saveMaterialReturnDraft(
    YorksV1MaterialReturnDraftInput input,
  );

  Future<YorksV1ReturnsDocumentsWorkspace> submitMaterialReturn(
    YorksV1MaterialReturnSubmissionInput input,
  );

  Future<YorksV1ReturnsDocumentsWorkspace> confirmMaterialReturn(
    YorksV1MaterialReturnConfirmationInput input,
  );

  Future<YorksV1ReturnsDocumentsWorkspace> rejectMaterialReturn(
    YorksV1MaterialReturnRejectionInput input,
  );
}

/// Optional project-wide return boundary. Keeping the new controlled workflow
/// separate lets deterministic inventory/dispatch test repositories remain
/// deliberately small while production exposes the complete return lifecycle.
abstract interface class YorksV1ProjectMaterialReturnRepository {
  Future<List<YorksV1MaterialRequestProjectOption>>
  listMaterialReturnProjects();

  Future<List<YorksV1MaterialReturnRegisterItem>> listProjectMaterialReturns({
    String? projectId,
    String? state,
    String? search,
  });

  Future<YorksV1ProjectMaterialReturn> getProjectMaterialReturn(
    String returnId,
  );

  Future<YorksV1MaterialReturnCreationWorkspace>
  getMaterialReturnCreationWorkspace({
    required String projectId,
    String? returnId,
  });

  Future<YorksV1ProjectMaterialReturn> saveProjectMaterialReturnDraft(
    YorksV1SaveMaterialReturnDraftInput input,
  );

  Future<YorksV1ProjectMaterialReturn> submitProjectMaterialReturn(
    YorksV1MaterialReturnCommandInput input,
  );

  Future<YorksV1ProjectMaterialReturn> decideProjectMaterialReturn(
    YorksV1MaterialReturnDecisionInput input,
  );

  Future<YorksV1ProjectMaterialReturn> dispatchProjectMaterialReturn(
    YorksV1MaterialReturnDispatchInput input,
  );

  Future<YorksV1ProjectMaterialReturn> confirmProjectMaterialReturn(
    YorksV1MaterialReturnReceiptInput input,
  );

  Future<YorksV1ProjectMaterialReturn> cancelProjectMaterialReturn(
    YorksV1MaterialReturnCancellationInput input,
  );
}

/// Optional read-only smart-category boundary. Keeping this separate preserves
/// compatibility with deterministic test repositories while production uses
/// the server-ranked, role-checked projection.
abstract interface class YorksV1InventoryCategorySuggestionRepository {
  Future<List<YorksV1InventoryCategorySearchResult>> suggestInventoryCategories(
    String query, {
    int limit = 8,
  });
}

/// Optional item-master command boundary. It is deliberately separate from
/// the stock command so existing clients cannot accidentally submit a balance
/// mutation while editing descriptive item data.
abstract interface class YorksV1InventoryItemMetadataRepository {
  Future<YorksV1LogisticsInventoryItem> updateInventoryItemMetadata(
    YorksV1InventoryItemMetadataInput input,
  );
}

class YorksV1SupabaseLogisticsRepository
    implements
        YorksV1LogisticsRepository,
        YorksV1ProjectMaterialReturnRepository,
        YorksV1InventoryCategorySuggestionRepository,
        YorksV1InventoryItemMetadataRepository {
  const YorksV1SupabaseLogisticsRepository({
    required YorksV1FeatureFlags featureFlags,
    required ConnectivityService connectivity,
    YorksV1MaterialRequestRpcClient? rpcClient,
    Duration rpcTimeout = const Duration(seconds: 20),
    AnalyticsService analytics = const NoopAnalyticsService(),
  }) : _featureFlags = featureFlags,
       _connectivity = connectivity,
       _rpcClient = rpcClient,
       _rpcTimeout = rpcTimeout,
       _analytics = analytics;

  final YorksV1FeatureFlags _featureFlags;
  final ConnectivityService _connectivity;
  final YorksV1MaterialRequestRpcClient? _rpcClient;
  final Duration _rpcTimeout;
  final AnalyticsService _analytics;

  @override
  Future<YorksV1InventoryWorkspace> getInventory({String? search}) async {
    final stopwatch = Stopwatch()..start();
    final query = search?.trim() ?? '';
    final operation = _analytics.beginOperation(
      query.isEmpty ? 'inventory_load' : 'inventory_search',
      properties: const {AnalyticsProperty.workflow: 'inventory'},
    );
    try {
      final response = await _invoke(
        functionName: 'v1_inventory_workspace_projection',
        parameters: {'p_search': query.isEmpty ? null : query},
      );
      final workspace = _inventoryWorkspace(response);
      operation.complete(resultCount: workspace.items.length);
      if (query.isNotEmpty) {
        _analytics.recordMaterialSearch(
          queryLength: query.length,
          resultCount: workspace.items.length,
          duration: stopwatch.elapsed,
          context: AnalyticsSearchContext.inventory,
        );
      }
      return workspace;
    } catch (error) {
      operation.fail(error);
      rethrow;
    }
  }

  @override
  Future<YorksV1InventoryItemDetail> getInventoryItem(
    String inventoryItemId,
  ) async {
    final response = await _invoke(
      functionName: 'v1_inventory_item_workspace_projection',
      parameters: {'p_inventory_item_id': inventoryItemId},
    );
    final detail = _inventoryItemDetail(response);
    _analytics.recordMaterialSearchSelection();
    _analytics.capture(
      AnalyticsEvent.inventoryItemSelected,
      properties: const {AnalyticsProperty.source: 'detail_opened'},
    );
    return detail;
  }

  @override
  Future<YorksV1LogisticsInventoryItem> adjustInventory(
    YorksV1InventoryAdjustmentInput input,
  ) async {
    final functionName = input.createsItem
        ? 'v1_create_inventory_item'
        : input.action != null
        ? 'v1_adjust_inventory_stock'
        : 'v1_adjust_inventory';
    final action = input.createsItem
        ? 'create_item'
        : input.action ?? 'update_item';
    final properties = <AnalyticsProperty, Object?>{
      AnalyticsProperty.inventoryAction: action,
    };
    _analytics.capture(
      AnalyticsEvent.inventoryActionStarted,
      properties: properties,
    );
    final operation = _analytics.beginOperation(
      'inventory_adjust',
      properties: properties,
    );
    try {
      final response = await _invoke(
        functionName: functionName,
        parameters: {
          'p_payload': input.createsItem
              ? input.toCreateItemRpcPayload()
              : input.action != null
              ? input.toStockMovementRpcPayload()
              : input.toRpcPayload(),
          'p_idempotency_key': input.idempotencyKey,
        },
      );
      final item = _inventoryItem(response);
      operation.complete();
      _analytics.capture(
        AnalyticsEvent.inventoryActionCompleted,
        properties: {...properties, AnalyticsProperty.success: true},
      );
      if (input.createsItem) {
        _analytics.capture(
          AnalyticsEvent.inventoryItemCreated,
          properties: properties,
        );
      }
      return item;
    } catch (error) {
      operation.fail(error);
      _analytics.capture(
        AnalyticsEvent.inventoryActionFailed,
        properties: {
          ...properties,
          AnalyticsProperty.errorCategory: analyticsErrorCategory(error),
        },
      );
      rethrow;
    }
  }

  @override
  Future<YorksV1LogisticsInventoryItem> updateInventoryItemMetadata(
    YorksV1InventoryItemMetadataInput input,
  ) async {
    final response = await _invoke(
      functionName: 'v1_update_inventory_item',
      parameters: {
        'p_payload': input.toRpcPayload(),
        'p_idempotency_key': input.idempotencyKey,
      },
    );
    return _inventoryItem(response);
  }

  @override
  Future<List<YorksV1InventoryCategorySearchResult>> suggestInventoryCategories(
    String query, {
    int limit = 8,
  }) async {
    final response = await _invoke(
      functionName: 'v1_inventory_category_suggestions',
      parameters: {'p_query': query.trim(), 'p_limit': limit},
    );
    if (response is! List) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return [
      for (final row in response)
        if (row is Map)
          YorksV1InventoryCategorySearchResult.fromRpcJson(
            Map<String, dynamic>.from(row),
          ),
    ];
  }

  @override
  Future<YorksV1InventoryCategory> createInventoryCategory(
    YorksV1InventoryCategoryCreationInput input,
  ) async {
    final response = await _invoke(
      functionName: 'v1_create_inventory_category',
      parameters: {
        'p_payload': input.toRpcPayload(),
        'p_idempotency_key': input.idempotencyKey,
      },
    );
    return _inventoryCategory(response);
  }

  @override
  Future<YorksV1InventoryImportResult> importInventory(
    YorksV1InventoryImportInput input,
  ) async {
    final properties = <AnalyticsProperty, Object?>{
      AnalyticsProperty.inventoryAction: 'import',
      AnalyticsProperty.itemCount: input.rows.length,
    };
    _analytics.capture(
      AnalyticsEvent.inventoryImportStarted,
      properties: properties,
    );
    final operation = _analytics.beginOperation(
      'inventory_import',
      properties: properties,
    );
    try {
      final response = await _invoke(
        functionName: 'v1_import_inventory',
        parameters: {
          'p_payload': input.toRpcPayload(),
          'p_idempotency_key': input.idempotencyKey,
        },
      );
      final result = _inventoryImportResult(response);
      operation.complete(resultCount: result.rowCount);
      _analytics.capture(
        AnalyticsEvent.inventoryImportCompleted,
        properties: {
          ...properties,
          AnalyticsProperty.success: true,
          AnalyticsProperty.resultCount: result.rowCount,
        },
      );
      return result;
    } catch (error) {
      operation.fail(error);
      _analytics.capture(
        AnalyticsEvent.inventoryImportFailed,
        properties: {
          ...properties,
          AnalyticsProperty.errorCategory: analyticsErrorCategory(error),
        },
      );
      rethrow;
    }
  }

  @override
  Future<YorksV1LogisticsInventoryItem> setInventoryItemActive(
    YorksV1InventoryItemStateInput input,
  ) async {
    final response = await _invoke(
      functionName: 'v1_set_inventory_item_active',
      parameters: {
        'p_payload': input.toRpcPayload(),
        'p_idempotency_key': input.idempotencyKey,
      },
    );
    return _inventoryItem(response);
  }

  @override
  Future<YorksV1LogisticsWorkspace> getWorkspace(String requestId) async {
    final response = await _invoke(
      functionName: 'v1_logistics_workspace_projection',
      parameters: {'p_request_id': requestId},
    );
    return _workspace(response);
  }

  @override
  Future<List<YorksV1ProjectMaterialMovement>> getProjectMaterialMovements(
    String projectId,
  ) async {
    final response = await _invoke(
      functionName: 'v1_project_material_movements',
      parameters: {'p_project_id': projectId},
    );
    if (response is! List) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return [
      for (final row in response)
        if (row is Map)
          YorksV1ProjectMaterialMovement.fromRpcJson(
            Map<String, dynamic>.from(row),
          ),
    ];
  }

  @override
  Future<YorksV1LogisticsWorkspace> dispatch(YorksV1DispatchInput input) async {
    final properties = <AnalyticsProperty, Object?>{
      AnalyticsProperty.itemCount: input.lines.length,
    };
    _analytics.capture(
      AnalyticsEvent.dispatchAttempted,
      properties: properties,
    );
    final operation = _analytics.beginOperation(
      'dispatch_materials',
      properties: {...properties, AnalyticsProperty.workflow: 'procurement'},
    );
    try {
      final response = await _invoke(
        functionName: 'v1_dispatch_materials',
        parameters: {
          'p_payload': input.toRpcPayload(),
          'p_idempotency_key': input.idempotencyKey,
        },
      );
      final workspace = _workspace(response);
      operation.complete();
      _analytics.capture(
        AnalyticsEvent.dispatchCompleted,
        properties: {...properties, AnalyticsProperty.success: true},
      );
      return workspace;
    } catch (error) {
      operation.fail(error);
      _analytics.capture(
        AnalyticsEvent.dispatchFailed,
        properties: {
          ...properties,
          AnalyticsProperty.errorCategory: analyticsErrorCategory(error),
        },
      );
      rethrow;
    }
  }

  @override
  Future<YorksV1LogisticsWorkspace> confirmReceipt(
    YorksV1ReceiptConfirmationInput input,
  ) async {
    final operation = _analytics.beginOperation(
      'receipt_review',
      properties: {
        AnalyticsProperty.workflow: 'procurement',
        AnalyticsProperty.itemCount: input.lines.length,
      },
    );
    try {
      final response = await _invoke(
        functionName: 'v1_confirm_receipt',
        parameters: {
          'p_payload': input.toRpcPayload(),
          'p_idempotency_key': input.idempotencyKey,
        },
      );
      final workspace = _workspace(response);
      operation.complete();
      final exceptionLineCount = input.lines
          .where((line) => line.outcome != YorksV1ReceiptOutcome.received)
          .length;
      _analytics.capture(
        AnalyticsEvent.receiptReviewCompleted,
        properties: {
          AnalyticsProperty.itemCount: input.lines.length,
          AnalyticsProperty.receivedLineCount:
              input.lines.length - exceptionLineCount,
          AnalyticsProperty.exceptionLineCount: exceptionLineCount,
          AnalyticsProperty.hasExceptions: exceptionLineCount > 0,
          AnalyticsProperty.receiptOutcome: exceptionLineCount == 0
              ? 'all_received'
              : 'exceptions_present',
        },
      );
      return workspace;
    } catch (error) {
      operation.fail(error);
      rethrow;
    }
  }

  @override
  Future<YorksV1ReturnsDocumentsWorkspace> getReturnsDocumentsWorkspace(
    String requestId,
  ) async {
    final response = await _invoke(
      functionName: 'v1_returns_documents_workspace_projection',
      parameters: {'p_request_id': requestId},
      requiresReturnsDocuments: true,
    );
    return _returnsDocumentsWorkspace(response);
  }

  @override
  Future<YorksV1ReturnsDocumentsWorkspace> generateDeliveryOrder(
    YorksV1DeliveryOrderGenerationInput input,
  ) async {
    final response = await _invoke(
      functionName: 'v1_generate_delivery_order',
      parameters: {
        'p_payload': input.toRpcPayload(),
        'p_idempotency_key': input.idempotencyKey,
      },
      requiresReturnsDocuments: true,
    );
    return _returnsDocumentsWorkspace(response);
  }

  @override
  Future<YorksV1ReturnsDocumentsWorkspace> saveMaterialReturnDraft(
    YorksV1MaterialReturnDraftInput input,
  ) async {
    final response = await _invoke(
      functionName: 'v1_save_material_return_draft',
      parameters: {
        'p_payload': input.toRpcPayload(),
        'p_idempotency_key': input.idempotencyKey,
      },
      requiresReturnsDocuments: true,
    );
    return _returnsDocumentsWorkspace(response);
  }

  @override
  Future<YorksV1ReturnsDocumentsWorkspace> submitMaterialReturn(
    YorksV1MaterialReturnSubmissionInput input,
  ) async {
    final response = await _invoke(
      functionName: 'v1_submit_material_return',
      parameters: {
        'p_payload': input.toRpcPayload(),
        'p_idempotency_key': input.idempotencyKey,
      },
      requiresReturnsDocuments: true,
    );
    return _returnsDocumentsWorkspace(response);
  }

  @override
  Future<YorksV1ReturnsDocumentsWorkspace> confirmMaterialReturn(
    YorksV1MaterialReturnConfirmationInput input,
  ) async {
    final response = await _invoke(
      functionName: 'v1_confirm_material_return',
      parameters: {
        'p_payload': input.toRpcPayload(),
        'p_idempotency_key': input.idempotencyKey,
      },
      requiresReturnsDocuments: true,
    );
    return _returnsDocumentsWorkspace(response);
  }

  @override
  Future<YorksV1ReturnsDocumentsWorkspace> rejectMaterialReturn(
    YorksV1MaterialReturnRejectionInput input,
  ) async {
    final response = await _invoke(
      functionName: 'v1_reject_material_return',
      parameters: {
        'p_payload': input.toRpcPayload(),
        'p_idempotency_key': input.idempotencyKey,
      },
      requiresReturnsDocuments: true,
    );
    return _returnsDocumentsWorkspace(response);
  }

  @override
  Future<List<YorksV1MaterialRequestProjectOption>>
  listMaterialReturnProjects() async {
    final response = await _invoke(
      functionName: 'v1_list_material_return_projects',
      parameters: const {},
      requiresReturnsDocuments: true,
    );
    if (response is! List) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return [
      for (final row in response)
        if (row is Map)
          YorksV1MaterialRequestProjectOption.fromRpcJson(
            Map<String, dynamic>.from(row),
          ),
    ];
  }

  @override
  Future<List<YorksV1MaterialReturnRegisterItem>> listProjectMaterialReturns({
    String? projectId,
    String? state,
    String? search,
  }) async {
    final response = await _invoke(
      functionName: 'v1_list_material_returns',
      parameters: {
        'p_project_id': _trimToNull(projectId),
        'p_state': _trimToNull(state),
        'p_search': _trimToNull(search),
      },
      requiresReturnsDocuments: true,
    );
    if (response is! List) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return [
      for (final row in response)
        if (row is Map)
          YorksV1MaterialReturnRegisterItem.fromRpcJson(
            Map<String, dynamic>.from(row),
          ),
    ];
  }

  @override
  Future<YorksV1ProjectMaterialReturn> getProjectMaterialReturn(
    String returnId,
  ) async {
    final response = await _invoke(
      functionName: 'v1_material_return_detail_projection',
      parameters: {'p_return_id': returnId},
      requiresReturnsDocuments: true,
    );
    return _projectMaterialReturn(response);
  }

  @override
  Future<YorksV1MaterialReturnCreationWorkspace>
  getMaterialReturnCreationWorkspace({
    required String projectId,
    String? returnId,
  }) async {
    final response = await _invoke(
      functionName: 'v1_material_return_creation_workspace',
      parameters: {
        'p_project_id': projectId,
        'p_return_id': _trimToNull(returnId),
      },
      requiresReturnsDocuments: true,
    );
    if (response is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1MaterialReturnCreationWorkspace.fromRpcJson(
      Map<String, dynamic>.from(response),
    );
  }

  @override
  Future<YorksV1ProjectMaterialReturn> saveProjectMaterialReturnDraft(
    YorksV1SaveMaterialReturnDraftInput input,
  ) async {
    final response = await _invoke(
      functionName: 'v1_save_project_material_return_draft',
      parameters: {
        'p_payload': input.toRpcPayload(),
        'p_idempotency_key': input.idempotencyKey,
      },
      requiresReturnsDocuments: true,
    );
    return _projectMaterialReturn(response);
  }

  @override
  Future<YorksV1ProjectMaterialReturn> submitProjectMaterialReturn(
    YorksV1MaterialReturnCommandInput input,
  ) async {
    final response = await _invoke(
      functionName: 'v1_submit_project_material_return',
      parameters: {
        'p_payload': input.toRpcPayload(),
        'p_idempotency_key': input.idempotencyKey,
      },
      requiresReturnsDocuments: true,
    );
    return _projectMaterialReturn(response);
  }

  @override
  Future<YorksV1ProjectMaterialReturn> decideProjectMaterialReturn(
    YorksV1MaterialReturnDecisionInput input,
  ) async {
    final response = await _invoke(
      functionName: 'v1_decide_project_material_return',
      parameters: {
        'p_payload': input.toRpcPayload(),
        'p_idempotency_key': input.idempotencyKey,
      },
      requiresReturnsDocuments: true,
    );
    return _projectMaterialReturn(response);
  }

  @override
  Future<YorksV1ProjectMaterialReturn> dispatchProjectMaterialReturn(
    YorksV1MaterialReturnDispatchInput input,
  ) async {
    final response = await _invoke(
      functionName: 'v1_dispatch_project_material_return',
      parameters: {
        'p_payload': input.toRpcPayload(),
        'p_idempotency_key': input.idempotencyKey,
      },
      requiresReturnsDocuments: true,
    );
    return _projectMaterialReturn(response);
  }

  @override
  Future<YorksV1ProjectMaterialReturn> confirmProjectMaterialReturn(
    YorksV1MaterialReturnReceiptInput input,
  ) async {
    final response = await _invoke(
      functionName: 'v1_confirm_project_material_return',
      parameters: {
        'p_payload': input.toRpcPayload(),
        'p_idempotency_key': input.idempotencyKey,
      },
      requiresReturnsDocuments: true,
    );
    return _projectMaterialReturn(response);
  }

  @override
  Future<YorksV1ProjectMaterialReturn> cancelProjectMaterialReturn(
    YorksV1MaterialReturnCancellationInput input,
  ) async {
    final response = await _invoke(
      functionName: 'v1_cancel_project_material_return',
      parameters: {
        'p_payload': input.toRpcPayload(),
        'p_idempotency_key': input.idempotencyKey,
      },
      requiresReturnsDocuments: true,
    );
    return _projectMaterialReturn(response);
  }

  Future<Object?> _invoke({
    required String functionName,
    required Map<String, Object?> parameters,
    bool requiresReturnsDocuments = false,
  }) async {
    if (!_featureFlags.logistics ||
        (requiresReturnsDocuments && !_featureFlags.returnsDocuments)) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.featureDisabled,
      );
    }
    if (!_connectivity.isOnline) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.offline);
    }
    final rpc = _rpcClient;
    if (rpc == null) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
    try {
      return await rpc
          .invoke(functionName: functionName, parameters: parameters)
          .timeout(_rpcTimeout);
    } on YorksV1DomainException {
      rethrow;
    } on PostgrestException catch (error) {
      throw _mapPostgrestException(error);
    } on TimeoutException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
        cause: error,
      );
    } catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
        cause: error,
      );
    }
  }

  static YorksV1InventoryWorkspace _inventoryWorkspace(Object? response) {
    if (response is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1InventoryWorkspace.fromRpcJson(
      Map<String, dynamic>.from(response),
    );
  }

  static YorksV1ProjectMaterialReturn _projectMaterialReturn(Object? response) {
    if (response is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1ProjectMaterialReturn.fromRpcJson(
      Map<String, dynamic>.from(response),
    );
  }

  static YorksV1InventoryItemDetail _inventoryItemDetail(Object? response) {
    if (response is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1InventoryItemDetail.fromRpcJson(
      Map<String, dynamic>.from(response),
    );
  }

  static YorksV1LogisticsInventoryItem _inventoryItem(Object? response) {
    if (response is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1LogisticsInventoryItem.fromRpcJson(
      Map<String, dynamic>.from(response),
    );
  }

  static YorksV1InventoryCategory _inventoryCategory(Object? response) {
    if (response is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1InventoryCategory.fromRpcJson(
      Map<String, dynamic>.from(response),
    );
  }

  static YorksV1InventoryImportResult _inventoryImportResult(Object? response) {
    if (response is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1InventoryImportResult.fromRpcJson(
      Map<String, dynamic>.from(response),
    );
  }

  static YorksV1LogisticsWorkspace _workspace(Object? response) {
    if (response is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1LogisticsWorkspace.fromRpcJson(
      Map<String, dynamic>.from(response),
    );
  }

  static YorksV1ReturnsDocumentsWorkspace _returnsDocumentsWorkspace(
    Object? response,
  ) {
    if (response is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1ReturnsDocumentsWorkspace.fromRpcJson(
      Map<String, dynamic>.from(response),
    );
  }

  static YorksV1DomainException _mapPostgrestException(
    PostgrestException error,
  ) {
    final serverMessage = error.message.toUpperCase();
    final code = switch (serverMessage) {
      final value
          when value.contains('V1_DISPATCH_STOCK_CAP_EXCEEDED') ||
              value.contains('V1_DISPATCH_INVENTORY_ITEM_INVALID') =>
        YorksV1DomainErrorCode.insufficientStock,
      final value
          when value.contains('V1_DISPATCH_APPROVED_CAP_EXCEEDED') ||
              value.contains('V1_DISPATCH_LINE_NOT_APPROVED') =>
        YorksV1DomainErrorCode.quantityCapExceeded,
      final value
          when value.contains('V1_DELIVERY_ORDER_REFERENCE_IMMUTABLE') =>
        YorksV1DomainErrorCode.immutableRecord,
      final value
          when value.contains('V1_RECEIPT_LINES_INCOMPLETE') ||
              value.contains('V1_RECEIPT_LINE_INVALID') =>
        YorksV1DomainErrorCode.incompleteReview,
      final value
          when value.contains('STATE_') || value.contains('NOT_AWAITING') =>
        YorksV1DomainErrorCode.invalidTransition,
      _ => switch (error.code) {
        '42501' || '28000' => YorksV1DomainErrorCode.unauthorized,
        '40001' || '23505' || '55P03' => YorksV1DomainErrorCode.conflict,
        '22023' ||
        '22007' ||
        '22P02' ||
        '23514' => YorksV1DomainErrorCode.invalidInput,
        _ => YorksV1DomainErrorCode.serverRejected,
      },
    };
    return YorksV1DomainException(code, serverCode: error.code, cause: error);
  }
}

String? _trimToNull(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

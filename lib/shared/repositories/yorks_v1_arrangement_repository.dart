import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/yorks_v1_arrangement.dart';
import '../models/analytics_event.dart';
import '../models/yorks_v1_domain_error.dart';
import '../models/yorks_v1_feature_flags.dart';
import '../sync/connectivity_service.dart';
import '../services/analytics_service.dart';
import 'yorks_v1_material_request_repository.dart';

/// Typed server boundary for the Batch 6 inventory/arrangement slice. Widgets
/// never receive a Supabase client and cannot write stock or reservations.
abstract interface class YorksV1ArrangementRepository {
  Future<YorksV1ArrangementWorkspace> getWorkspace(String requestId);

  Future<List<YorksV1InventoryItem>> listInventoryItems();

  Future<YorksV1ArrangementWorkspace> begin(YorksV1BeginArrangementInput input);

  Future<YorksV1ArrangementWorkspace> updateProcurementItem(
    YorksV1UpdateProcurementMaterialItemInput input,
  );

  Future<YorksV1ArrangementWorkspace> save(YorksV1SaveArrangementInput input);

  Future<YorksV1ArrangementWorkspace> decide(
    YorksV1DecideArrangementInput input,
  );
}

class YorksV1SupabaseArrangementRepository
    implements YorksV1ArrangementRepository {
  const YorksV1SupabaseArrangementRepository({
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
  Future<YorksV1ArrangementWorkspace> getWorkspace(String requestId) async {
    final operation = _analytics.beginOperation(
      'procurement_workspace_load',
      properties: const {AnalyticsProperty.workflow: 'procurement'},
    );
    try {
      final response = await _invoke(
        functionName: 'v1_arrangement_projection',
        parameters: {'p_request_id': requestId},
      );
      final workspace = _workspace(response);
      operation.complete();
      return workspace;
    } catch (error) {
      operation.fail(error);
      rethrow;
    }
  }

  @override
  Future<List<YorksV1InventoryItem>> listInventoryItems() async {
    final response = await _invoke(
      functionName: 'v1_list_arrangement_inventory_items',
      parameters: const {},
    );
    if (response is! List) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return [
      for (final item in response)
        if (item is Map)
          YorksV1InventoryItem.fromRpcJson(Map<String, dynamic>.from(item)),
    ];
  }

  @override
  Future<YorksV1ArrangementWorkspace> begin(
    YorksV1BeginArrangementInput input,
  ) async {
    final operation = _analytics.beginOperation(
      'arrangement_begin',
      properties: const {AnalyticsProperty.workflow: 'procurement'},
    );
    try {
      final response = await _invoke(
        functionName: 'v1_begin_arrangement',
        parameters: {
          'p_payload': input.toRpcPayload(),
          'p_idempotency_key': input.idempotencyKey,
        },
      );
      final workspace = _workspace(response);
      operation.complete();
      _analytics.capture(AnalyticsEvent.arrangementStarted);
      return workspace;
    } catch (error) {
      operation.fail(error);
      _analytics.capture(
        AnalyticsEvent.procurementActionFailed,
        properties: {
          AnalyticsProperty.actionType: 'begin_arrangement',
          AnalyticsProperty.errorCategory: analyticsErrorCategory(error),
        },
      );
      rethrow;
    }
  }

  @override
  Future<YorksV1ArrangementWorkspace> updateProcurementItem(
    YorksV1UpdateProcurementMaterialItemInput input,
  ) async {
    final response = await _invoke(
      functionName: 'v1_update_material_request_procurement_item',
      parameters: {
        'p_payload': input.toRpcPayload(),
        'p_idempotency_key': input.idempotencyKey,
      },
    );
    return _workspace(response);
  }

  @override
  Future<YorksV1ArrangementWorkspace> save(
    YorksV1SaveArrangementInput input,
  ) async {
    final properties = <AnalyticsProperty, Object?>{
      AnalyticsProperty.itemCount: input.lines.length,
    };
    _analytics.capture(
      AnalyticsEvent.arrangementSaveAttempted,
      properties: properties,
    );
    final operation = _analytics.beginOperation(
      'arrangement_save',
      properties: {...properties, AnalyticsProperty.workflow: 'procurement'},
    );
    try {
      final response = await _invoke(
        functionName: 'v1_save_arrangement',
        parameters: {
          'p_payload': input.toRpcPayload(),
          'p_idempotency_key': input.idempotencyKey,
        },
      );
      final workspace = _workspace(response);
      operation.complete();
      _analytics.capture(
        AnalyticsEvent.arrangementSaveCompleted,
        properties: {...properties, AnalyticsProperty.success: true},
      );
      return workspace;
    } catch (error) {
      operation.fail(error);
      _analytics.capture(
        AnalyticsEvent.procurementActionFailed,
        properties: {
          ...properties,
          AnalyticsProperty.errorCategory: analyticsErrorCategory(error),
        },
      );
      rethrow;
    }
  }

  @override
  Future<YorksV1ArrangementWorkspace> decide(
    YorksV1DecideArrangementInput input,
  ) async {
    final properties = <AnalyticsProperty, Object?>{
      AnalyticsProperty.actionType: input.decision.wireValue,
    };
    _analytics.capture(
      AnalyticsEvent.approvalActionStarted,
      properties: properties,
    );
    final operation = _analytics.beginOperation(
      'arrangement_decide',
      properties: const {AnalyticsProperty.workflow: 'approval'},
    );
    try {
      final response = await _invoke(
        functionName: 'v1_decide_arrangement',
        parameters: {
          'p_payload': input.toRpcPayload(),
          'p_idempotency_key': input.idempotencyKey,
        },
      );
      final workspace = _workspace(response);
      operation.complete();
      _analytics.capture(
        AnalyticsEvent.approvalActionCompleted,
        properties: {...properties, AnalyticsProperty.success: true},
      );
      return workspace;
    } catch (error) {
      operation.fail(error);
      _analytics.capture(
        AnalyticsEvent.approvalActionCompleted,
        properties: {
          ...properties,
          AnalyticsProperty.success: false,
          AnalyticsProperty.errorCategory: analyticsErrorCategory(error),
        },
      );
      rethrow;
    }
  }

  Future<Object?> _invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async {
    if (!_featureFlags.arrangement) {
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

  static YorksV1ArrangementWorkspace _workspace(Object? response) {
    if (response is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1ArrangementWorkspace.fromRpcJson(
      Map<String, dynamic>.from(response),
    );
  }

  static YorksV1DomainException _mapPostgrestException(
    PostgrestException error,
  ) {
    final serverMessage = error.message.toUpperCase();
    final code = switch (serverMessage) {
      final value
          when value.contains('V1_INVENTORY_RESERVATION_EXCEEDS_AVAILABLE') ||
              value.contains('V1_ARRANGEMENT_INVENTORY_ITEM_INVALID') =>
        YorksV1DomainErrorCode.insufficientStock,
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

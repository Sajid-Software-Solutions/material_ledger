import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/yorks_v1_domain_error.dart';
import '../models/analytics_event.dart';
import '../models/yorks_v1_feature_flags.dart';
import '../models/yorks_v1_material_request.dart';
import '../models/yorks_v1_material_request_document.dart';
import '../sync/connectivity_service.dart';
import '../services/analytics_service.dart';

/// Narrow RPC boundary for V1 requests. It prevents widgets and local draft
/// storage from ever constructing a direct database mutation.
abstract interface class YorksV1MaterialRequestRpcClient {
  Future<Object?> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  });
}

class SupabaseYorksV1MaterialRequestRpcClient
    implements YorksV1MaterialRequestRpcClient {
  const SupabaseYorksV1MaterialRequestRpcClient(this._client);

  final SupabaseClient _client;

  @override
  Future<Object?> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) => _client.rpc(functionName, params: parameters);
}

abstract interface class YorksV1MaterialRequestRepository {
  Future<List<YorksV1MaterialRequestProjectOption>> listDraftProjects();

  Future<List<YorksV1MaterialRequestScopeOption>> listScopes(String projectId);

  Future<List<YorksV1MaterialRequest>> listRequests({String? projectId});

  Future<YorksV1MaterialRequest> getRequest(String requestId);

  Future<YorksV1MaterialRequestDocumentModel> getDocumentModel(
    String requestId,
  );

  Future<YorksV1MaterialRequest> saveDraft(
    YorksV1SaveMaterialRequestDraftInput input,
  );

  /// Atomically persists the current draft snapshot and submits it.  A
  /// workflow transition must never depend on a second client request after a
  /// draft version has changed on the server.
  Future<YorksV1MaterialRequest> saveAndSubmit(
    YorksV1MaterialRequestDraft draft,
  );

  Future<YorksV1MaterialRequest> updateForApproval(
    YorksV1UpdateMaterialRequestForApprovalInput input,
  );

  Future<YorksV1MaterialRequest> decideRequest(
    YorksV1DecideMaterialRequestInput input,
  );

  Future<List<YorksV1MaterialRequestMention>> listMentionCandidates(
    String requestId,
  );

  Future<List<YorksV1MaterialRequestInventorySuggestion>> searchInventory({
    required String projectId,
    required String scopeId,
    required String query,
  });

  Future<List<YorksV1MaterialRequestComment>> addComment(
    YorksV1AddMaterialRequestCommentInput input,
  );

  Future<void> deleteDraft(String requestId);

  Future<YorksV1MaterialRequest> submit(
    YorksV1SubmitMaterialRequestInput input,
  );

  Future<YorksV1MaterialRequest> cancel(
    YorksV1CancelMaterialRequestInput input,
  );

  Future<YorksV1MaterialRequest> close(YorksV1CloseMaterialRequestInput input);
}

/// Additive Phase 2 collaboration boundary. Keeping it separate preserves
/// source compatibility for existing test and rollout repositories while the
/// production Supabase repository exposes the new server-paginated features.
abstract interface class YorksV1MaterialRequestPhase2Repository {
  Future<YorksV1MaterialRequestSummaryPage> listRequestSummaries(
    YorksV1MaterialRequestSummaryQuery query,
  );

  Future<YorksV1MaterialRequestCommentPage> listComments({
    required String requestId,
    DateTime? beforeCreatedAt,
    String? beforeId,
    int limit = 20,
  });

  Future<List<YorksV1MaterialRequestComment>> getCommentWindow({
    required String requestId,
    required String commentId,
    int radius = 10,
  });

  Future<YorksV1MaterialRequestWorkAssignment> getWorkAssignment(
    String requestId,
  );

  Future<List<YorksV1MaterialRequestMention>> listWorkCandidates(
    String requestId,
  );

  Future<YorksV1MaterialRequestWorkAssignment> assignWork(
    YorksV1AssignMaterialRequestWorkInput input,
  );

  Future<YorksV1MaterialRequestChangeSummary?> getChangeSummary(
    String requestId,
  );

  Future<YorksV1PrivateMaterialRequestDraftRecord> syncPrivateDraft(
    YorksV1SyncPrivateMaterialRequestDraftInput input,
  );

  Future<YorksV1PrivateMaterialRequestDraftRecord?> getPrivateDraft({
    required String draftId,
    required String ownerAuthUserId,
    required String submissionIdempotencyKey,
  });

  Future<List<YorksV1PrivateMaterialRequestDraftRecord>> listPrivateDrafts({
    required String ownerAuthUserId,
    required String Function() submissionIdempotencyKeyFactory,
    int limit = 50,
  });

  Future<void> deletePrivateDraft({
    required String draftId,
    required int expectedSyncVersion,
    required String idempotencyKey,
  });
}

/// Additive Phase 3 policy and all-unavailable replacement boundary.
abstract interface class YorksV1MaterialRequestPhase3Repository {
  Future<YorksV1MaterialRequestPhase3Policy> getPhase3Policy(String requestId);

  Future<YorksV1MaterialRequest> createReplacement(
    YorksV1CreateReplacementMaterialRequestInput input,
  );
}

/// Additive read-only action queue and operational reporting boundary.
abstract interface class YorksV1MaterialRequestOperationsRepository {
  Future<YorksV1MaterialRequestOverview> getOverview({int limit = 6});

  Future<YorksV1MaterialRequestOperationsDashboard> getOperationsDashboard({
    String? projectId,
  });
}

/// Server-backed normalized MR repository. The only local persistence lives in
/// a creator-owned recoverable draft controller; submitted state never falls
/// back to the legacy collection/outbox authority.
class YorksV1SupabaseMaterialRequestRepository
    implements
        YorksV1MaterialRequestRepository,
        YorksV1MaterialRequestPhase2Repository,
        YorksV1MaterialRequestPhase3Repository,
        YorksV1MaterialRequestOperationsRepository {
  const YorksV1SupabaseMaterialRequestRepository({
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
  Future<List<YorksV1MaterialRequestProjectOption>> listDraftProjects() async {
    final response = await _invoke(
      functionName: 'v1_list_material_request_projects',
      parameters: const {},
    );
    return _list(response)
        .map((item) {
          return YorksV1MaterialRequestProjectOption.fromRpcJson(item);
        })
        .toList(growable: false);
  }

  @override
  Future<List<YorksV1MaterialRequestScopeOption>> listScopes(
    String projectId,
  ) async {
    final response = await _invoke(
      functionName: 'v1_list_material_request_scopes',
      parameters: {'p_project_id': projectId},
    );
    return _list(response)
        .map((item) {
          return YorksV1MaterialRequestScopeOption.fromRpcJson(item);
        })
        .toList(growable: false);
  }

  @override
  Future<List<YorksV1MaterialRequest>> listRequests({String? projectId}) async {
    final response = await _invoke(
      functionName: 'v1_list_material_requests',
      parameters: {'p_project_id': projectId},
    );
    return _list(
      response,
    ).map(YorksV1MaterialRequest.fromRpcJson).toList(growable: false);
  }

  @override
  Future<YorksV1MaterialRequestSummaryPage> listRequestSummaries(
    YorksV1MaterialRequestSummaryQuery query,
  ) async {
    final response = await _invoke(
      functionName: 'v1_list_material_request_summaries',
      parameters: query.toRpcParameters(),
    );
    if (response is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1MaterialRequestSummaryPage.fromRpcJson(
      Map<String, dynamic>.from(response),
    );
  }

  @override
  Future<YorksV1MaterialRequestOperationsDashboard> getOperationsDashboard({
    String? projectId,
  }) async {
    final response = await _invoke(
      functionName: 'v1_material_request_operations_dashboard',
      parameters: {
        'p_project_id': projectId?.trim().isEmpty == true ? null : projectId,
      },
    );
    if (response is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1MaterialRequestOperationsDashboard.fromRpcJson(
      Map<String, dynamic>.from(response),
    );
  }

  @override
  Future<YorksV1MaterialRequestOverview> getOverview({int limit = 6}) async {
    final response = await _invoke(
      functionName: 'v1_material_request_overview',
      parameters: {'p_limit': limit},
    );
    if (response is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1MaterialRequestOverview.fromRpcJson(
      Map<String, dynamic>.from(response),
    );
  }

  @override
  Future<YorksV1MaterialRequest> getRequest(String requestId) async {
    final operation = _analytics.beginOperation(
      'material_request_load',
      properties: const {AnalyticsProperty.workflow: 'material_request'},
    );
    try {
      final response = await _invoke(
        functionName: 'v1_material_request_projection',
        parameters: {'p_request_id': requestId},
      );
      final request = _single(response);
      operation.complete();
      return request;
    } catch (error) {
      operation.fail(error);
      rethrow;
    }
  }

  @override
  Future<YorksV1MaterialRequestPhase3Policy> getPhase3Policy(
    String requestId,
  ) async {
    final response = await _invoke(
      functionName: 'v1_material_request_phase3_policy_projection',
      parameters: {'p_request_id': requestId},
    );
    return YorksV1MaterialRequestPhase3Policy.fromRpcJson(_map(response));
  }

  @override
  Future<YorksV1MaterialRequest> createReplacement(
    YorksV1CreateReplacementMaterialRequestInput input,
  ) async {
    final response = await _invoke(
      functionName: 'v1_create_replacement_material_request',
      parameters: {
        'p_payload': input.toRpcPayload(),
        'p_idempotency_key': input.idempotencyKey,
      },
    );
    return _single(response);
  }

  @override
  Future<YorksV1MaterialRequestDocumentModel> getDocumentModel(
    String requestId,
  ) async {
    final response = await _invoke(
      functionName: 'v1_material_request_document_projection',
      parameters: {'p_request_id': requestId},
    );
    if (response is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1MaterialRequestDocumentModel.fromRpcJson(
      Map<String, dynamic>.from(response),
    );
  }

  @override
  Future<YorksV1MaterialRequest> saveDraft(
    YorksV1SaveMaterialRequestDraftInput input,
  ) async {
    final response = await _invoke(
      functionName: 'v1_save_material_request_draft',
      parameters: {'p_payload': input.toRpcPayload()},
    );
    return _single(response);
  }

  @override
  Future<YorksV1MaterialRequest> saveAndSubmit(
    YorksV1MaterialRequestDraft draft,
  ) async {
    final response = await _invoke(
      functionName: 'v1_save_and_submit_material_request',
      parameters: {
        'p_payload': draft.toSaveInput().toRpcPayload(),
        'p_idempotency_key': draft.submissionIdempotencyKey,
      },
    );
    return _single(response);
  }

  @override
  Future<YorksV1MaterialRequest> updateForApproval(
    YorksV1UpdateMaterialRequestForApprovalInput input,
  ) async {
    final response = await _invoke(
      functionName: 'v1_update_material_request_for_approval',
      parameters: {
        'p_payload': input.toRpcPayload(),
        'p_idempotency_key': input.idempotencyKey,
      },
    );
    return _single(response);
  }

  @override
  Future<YorksV1MaterialRequest> decideRequest(
    YorksV1DecideMaterialRequestInput input,
  ) async {
    final properties = <AnalyticsProperty, Object?>{
      AnalyticsProperty.actionType: input.decision.wireValue,
    };
    _analytics.recordActionAttempt(
      action: input.decision == YorksV1MaterialRequestReviewDecision.approved
          ? 'approve_material_request'
          : 'return_material_request',
      screen: AnalyticsScreen.materialRequestDetail,
      operationWasLoading: false,
    );
    final operation = _analytics.beginOperation(
      'material_request_decide',
      properties: const {AnalyticsProperty.workflow: 'material_request'},
    );
    try {
      final response = await _invoke(
        functionName: 'v1_decide_material_request',
        parameters: {
          'p_payload': input.toRpcPayload(),
          'p_idempotency_key': input.idempotencyKey,
        },
      );
      final request = _single(response);
      operation.complete();
      _analytics.capture(
        input.decision == YorksV1MaterialRequestReviewDecision.approved
            ? AnalyticsEvent.materialRequestApproved
            : AnalyticsEvent.materialRequestReturned,
        properties: properties,
      );
      return request;
    } catch (error) {
      operation.fail(error);
      _analytics.capture(
        AnalyticsEvent.materialRequestDecisionFailed,
        properties: {
          ...properties,
          AnalyticsProperty.success: false,
          AnalyticsProperty.errorCategory: analyticsErrorCategory(error),
        },
      );
      rethrow;
    }
  }

  @override
  Future<List<YorksV1MaterialRequestMention>> listMentionCandidates(
    String requestId,
  ) async {
    final response = await _invoke(
      functionName: 'v1_list_material_request_mention_candidates',
      parameters: {'p_request_id': requestId},
    );
    return _list(
      response,
    ).map(YorksV1MaterialRequestMention.fromRpcJson).toList(growable: false);
  }

  @override
  Future<List<YorksV1MaterialRequestInventorySuggestion>> searchInventory({
    required String projectId,
    required String scopeId,
    required String query,
  }) async {
    if (query.trim().length < 2) return const [];
    final stopwatch = Stopwatch()..start();
    final response = await _invoke(
      functionName: 'v1_search_material_request_candidates',
      parameters: {
        'p_project_id': projectId,
        'p_scope_id': scopeId,
        'p_query': query.trim(),
        'p_limit': 18,
      },
    );
    final results = _list(response)
        .map(YorksV1MaterialRequestInventorySuggestion.fromRpcJson)
        .toList(growable: false);
    _analytics.recordMaterialSearch(
      queryLength: query.trim().length,
      resultCount: results.length,
      duration: stopwatch.elapsed,
      context: AnalyticsSearchContext.materialRequest,
    );
    return results;
  }

  @override
  Future<List<YorksV1MaterialRequestComment>> addComment(
    YorksV1AddMaterialRequestCommentInput input,
  ) async {
    final response = await _invoke(
      functionName: 'v1_add_material_request_comment',
      parameters: {
        'p_payload': input.toRpcPayload(),
        'p_idempotency_key': input.idempotencyKey,
      },
    );
    if (response is! Map || response['comments'] is! List) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return _list(
      response['comments'],
    ).map(YorksV1MaterialRequestComment.fromRpcJson).toList(growable: false);
  }

  @override
  Future<YorksV1MaterialRequestCommentPage> listComments({
    required String requestId,
    DateTime? beforeCreatedAt,
    String? beforeId,
    int limit = 20,
  }) async {
    final response = await _invoke(
      functionName: 'v1_list_material_request_comments',
      parameters: {
        'p_request_id': requestId,
        'p_before_created_at': beforeCreatedAt?.toUtc().toIso8601String(),
        'p_before_id': beforeId,
        'p_limit': limit,
      },
    );
    if (response is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1MaterialRequestCommentPage.fromRpcJson(
      Map<String, dynamic>.from(response),
    );
  }

  @override
  Future<List<YorksV1MaterialRequestComment>> getCommentWindow({
    required String requestId,
    required String commentId,
    int radius = 10,
  }) async {
    final response = await _invoke(
      functionName: 'v1_get_material_request_comment_window',
      parameters: {
        'p_request_id': requestId,
        'p_comment_id': commentId,
        'p_radius': radius,
      },
    );
    if (response is! Map || response['items'] is! List) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return _list(
      response['items'],
    ).map(YorksV1MaterialRequestComment.fromRpcJson).toList(growable: false);
  }

  @override
  Future<YorksV1MaterialRequestWorkAssignment> getWorkAssignment(
    String requestId,
  ) async {
    final response = await _invoke(
      functionName: 'v1_get_material_request_work_assignment',
      parameters: {'p_request_id': requestId},
    );
    return YorksV1MaterialRequestWorkAssignment.fromRpcJson(_map(response));
  }

  @override
  Future<List<YorksV1MaterialRequestMention>> listWorkCandidates(
    String requestId,
  ) async {
    final response = await _invoke(
      functionName: 'v1_list_material_request_work_candidates',
      parameters: {'p_request_id': requestId},
    );
    return _list(
      response,
    ).map(YorksV1MaterialRequestMention.fromRpcJson).toList(growable: false);
  }

  @override
  Future<YorksV1MaterialRequestWorkAssignment> assignWork(
    YorksV1AssignMaterialRequestWorkInput input,
  ) async {
    final response = await _invoke(
      functionName: 'v1_assign_material_request_work',
      parameters: {
        'p_payload': input.toRpcPayload(),
        'p_idempotency_key': input.idempotencyKey,
      },
    );
    return YorksV1MaterialRequestWorkAssignment.fromRpcJson(_map(response));
  }

  @override
  Future<YorksV1MaterialRequestChangeSummary?> getChangeSummary(
    String requestId,
  ) async {
    final response = await _invoke(
      functionName: 'v1_material_request_change_summary',
      parameters: {'p_request_id': requestId},
    );
    if (response == null) return null;
    return YorksV1MaterialRequestChangeSummary.fromRpcJson(_map(response));
  }

  @override
  Future<YorksV1PrivateMaterialRequestDraftRecord> syncPrivateDraft(
    YorksV1SyncPrivateMaterialRequestDraftInput input,
  ) async {
    final response = await _invoke(
      functionName: 'v1_sync_material_request_private_draft',
      parameters: {
        'p_payload': input.toRpcPayload(),
        'p_idempotency_key': input.idempotencyKey,
      },
    );
    return YorksV1PrivateMaterialRequestDraftRecord.fromRpcJson(
      _map(response),
      ownerAuthUserId: input.draft.ownerAuthUserId,
      submissionIdempotencyKey: input.draft.submissionIdempotencyKey,
    );
  }

  @override
  Future<YorksV1PrivateMaterialRequestDraftRecord?> getPrivateDraft({
    required String draftId,
    required String ownerAuthUserId,
    required String submissionIdempotencyKey,
  }) async {
    final response = await _invoke(
      functionName: 'v1_get_my_material_request_private_draft',
      parameters: {'p_draft_id': draftId},
    );
    if (response == null) return null;
    return YorksV1PrivateMaterialRequestDraftRecord.fromRpcJson(
      _map(response),
      ownerAuthUserId: ownerAuthUserId,
      submissionIdempotencyKey: submissionIdempotencyKey,
    );
  }

  @override
  Future<List<YorksV1PrivateMaterialRequestDraftRecord>> listPrivateDrafts({
    required String ownerAuthUserId,
    required String Function() submissionIdempotencyKeyFactory,
    int limit = 50,
  }) async {
    final response = await _invoke(
      functionName: 'v1_list_my_material_request_private_drafts',
      parameters: {'p_limit': limit},
    );
    return _list(response)
        .map(
          (json) => YorksV1PrivateMaterialRequestDraftRecord.fromRpcJson(
            json,
            ownerAuthUserId: ownerAuthUserId,
            submissionIdempotencyKey: submissionIdempotencyKeyFactory(),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> deletePrivateDraft({
    required String draftId,
    required int expectedSyncVersion,
    required String idempotencyKey,
  }) async {
    await _invoke(
      functionName: 'v1_delete_my_material_request_private_draft',
      parameters: {
        'p_payload': {
          'draft_id': draftId,
          'expected_sync_version': expectedSyncVersion,
        },
        'p_idempotency_key': idempotencyKey,
      },
    );
  }

  @override
  Future<void> deleteDraft(String requestId) async {
    await _invoke(
      functionName: 'v1_delete_material_request_draft',
      parameters: {'p_request_id': requestId},
    );
  }

  @override
  Future<YorksV1MaterialRequest> submit(
    YorksV1SubmitMaterialRequestInput input,
  ) async {
    final response = await _invoke(
      functionName: 'v1_submit_material_request',
      parameters: {
        'p_payload': input.toRpcPayload(),
        'p_idempotency_key': input.idempotencyKey,
      },
    );
    return _single(response);
  }

  @override
  Future<YorksV1MaterialRequest> cancel(
    YorksV1CancelMaterialRequestInput input,
  ) async {
    final response = await _invoke(
      functionName: 'v1_cancel_material_request',
      parameters: {
        'p_payload': input.toRpcPayload(),
        'p_idempotency_key': input.idempotencyKey,
      },
    );
    return _single(response);
  }

  @override
  Future<YorksV1MaterialRequest> close(
    YorksV1CloseMaterialRequestInput input,
  ) async {
    final response = await _invoke(
      functionName: 'v1_close_material_request',
      parameters: {
        'p_payload': input.toRpcPayload(),
        'p_idempotency_key': input.idempotencyKey,
      },
    );
    return _single(response);
  }

  Future<Object?> _invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async {
    if (!_featureFlags.requests) {
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

  static List<Map<String, dynamic>> _list(Object? response) {
    if (response is! List) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return [
      for (final item in response)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }

  static Map<String, dynamic> _map(Object? response) {
    if (response is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return Map<String, dynamic>.from(response);
  }

  static YorksV1MaterialRequest _single(Object? response) {
    if (response is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1MaterialRequest.fromRpcJson(
      Map<String, dynamic>.from(response),
    );
  }

  static YorksV1DomainException _mapPostgrestException(
    PostgrestException error,
  ) {
    final code = switch (error.code) {
      '42501' || '28000' => YorksV1DomainErrorCode.unauthorized,
      '40001' || '23505' || '55P03' => YorksV1DomainErrorCode.conflict,
      'PGRST002' || 'PGRST003' => YorksV1DomainErrorCode.backendUnavailable,
      '22023' ||
      '22007' ||
      '22P02' ||
      '23514' => YorksV1DomainErrorCode.invalidInput,
      _ => YorksV1DomainErrorCode.serverRejected,
    };
    return YorksV1DomainException(code, serverCode: error.code, cause: error);
  }
}

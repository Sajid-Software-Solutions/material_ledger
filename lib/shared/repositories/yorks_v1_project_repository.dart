import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/yorks_v1_domain_error.dart';
import '../models/analytics_event.dart';
import '../models/yorks_v1_feature_flags.dart';
import '../models/yorks_v1_project.dart';
import '../services/analytics_service.dart';
import '../sync/connectivity_service.dart';

/// Narrow RPC seam for the normalized Yorks V1 project domain.
///
/// It makes repository tests independent of a live Supabase client and keeps
/// raw PostgREST values out of controller and widget code.
abstract interface class YorksV1ProjectRpcClient {
  Future<Map<String, dynamic>> invoke({
    required String functionName,
    required Map<String, dynamic> parameters,
  });
}

class SupabaseYorksV1ProjectRpcClient implements YorksV1ProjectRpcClient {
  const SupabaseYorksV1ProjectRpcClient(this._client);

  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>> invoke({
    required String functionName,
    required Map<String, dynamic> parameters,
  }) async {
    final response = await _client.rpc(functionName, params: parameters);
    if (response is Map) return Map<String, dynamic>.from(response);
    if (response is List && response.length == 1 && response.single is Map) {
      return Map<String, dynamic>.from(response.single as Map);
    }
    throw const YorksV1DomainException(
      YorksV1DomainErrorCode.unexpectedResponse,
    );
  }
}

/// Normalized project commands. Reads are intentionally not added here until
/// Batch 2 secure views and route integration establish their projection shape.
abstract interface class YorksV1ProjectRepository {
  Future<YorksV1ProjectCreationResult> createProject(
    YorksV1ProjectCreationInput input,
  );

  Future<YorksV1ProjectMembershipResult> assignProjectMember(
    YorksV1AssignProjectMemberInput input,
  );

  Future<YorksV1ProjectMembershipResult> revokeProjectMember(
    YorksV1RevokeProjectMemberInput input,
  );

  Future<YorksV1Project> setProjectState(YorksV1SetProjectStateInput input);

  Future<YorksV1Project> updateProject(YorksV1ProjectUpdateInput input);

  Future<YorksV1Project> archiveProject(YorksV1ArchiveProjectInput input);
}

/// Connected V1 implementation. There is deliberately no local project-write
/// fallback: creation, membership and state changes require an online trusted
/// Postgres transaction.
class YorksV1SupabaseProjectRepository implements YorksV1ProjectRepository {
  const YorksV1SupabaseProjectRepository({
    required YorksV1FeatureFlags featureFlags,
    required ConnectivityService connectivity,
    YorksV1ProjectRpcClient? rpcClient,
    AnalyticsService analytics = const NoopAnalyticsService(),
  }) : _featureFlags = featureFlags,
       _connectivity = connectivity,
       _rpcClient = rpcClient,
       _analytics = analytics;

  final YorksV1FeatureFlags _featureFlags;
  final ConnectivityService _connectivity;
  final YorksV1ProjectRpcClient? _rpcClient;
  final AnalyticsService _analytics;

  @override
  Future<YorksV1ProjectCreationResult> createProject(
    YorksV1ProjectCreationInput input,
  ) async {
    final validationErrors = input.validate();
    if (validationErrors.isNotEmpty) {
      _analytics.capture(
        AnalyticsEvent.formValidationFailed,
        properties: {
          AnalyticsProperty.formType: 'project_creation',
          AnalyticsProperty.validationReason: 'invalid_input',
          AnalyticsProperty.errorCategory: AnalyticsErrorCategory.validation,
          AnalyticsProperty.resultCount: validationErrors.length,
        },
      );
    }
    _throwIfInvalid(validationErrors);
    _analytics.capture(
      AnalyticsEvent.projectCreationAttempted,
      properties: {
        AnalyticsProperty.buildingCount: input.buildings.length,
        AnalyticsProperty.attachmentCount: input.attachments.length,
      },
    );
    _analytics.recordActionAttempt(
      action: 'create_project',
      screen: AnalyticsScreen.projectCreate,
      operationWasLoading: false,
    );
    final operation = _analytics.beginOperation(
      'project_create',
      properties: {
        AnalyticsProperty.workflow: 'project_creation',
        AnalyticsProperty.buildingCount: input.buildings.length,
        AnalyticsProperty.attachmentCount: input.attachments.length,
      },
    );
    try {
      final rpc = _readyRpc();
      final response = await rpc.invoke(
        functionName: 'v1_create_project',
        parameters: {
          'p_payload': input.toRpcPayload(),
          'p_idempotency_key': input.idempotencyKey.trim(),
        },
      );
      final result = YorksV1ProjectCreationResult.fromRpcJson(response);
      operation.complete();
      _analytics.capture(
        AnalyticsEvent.projectCreated,
        properties: {
          AnalyticsProperty.buildingCount: input.buildings.length,
          AnalyticsProperty.attachmentCount: input.attachments.length,
        },
      );
      return result;
    } on YorksV1DomainException catch (error) {
      operation.fail(error);
      _captureProjectCreationFailure(error);
      rethrow;
    } on PostgrestException catch (error) {
      final mapped = _mapPostgrestException(error);
      operation.fail(mapped);
      _captureProjectCreationFailure(mapped);
      throw mapped;
    } catch (error) {
      final mapped = YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
        cause: error,
      );
      operation.fail(mapped);
      _captureProjectCreationFailure(mapped);
      throw mapped;
    }
  }

  void _captureProjectCreationFailure(Object error) {
    _analytics.capture(
      AnalyticsEvent.projectCreationFailed,
      properties: {
        AnalyticsProperty.errorCategory: analyticsErrorCategory(error),
      },
    );
  }

  @override
  Future<YorksV1ProjectMembershipResult> assignProjectMember(
    YorksV1AssignProjectMemberInput input,
  ) async {
    _throwIfInvalid(input.validate());
    final rpc = _readyRpc();
    const action = 'member_assigned';
    final operation = _analytics.beginOperation(
      'project_access_change',
      properties: const {AnalyticsProperty.actionType: action},
    );
    try {
      final response = await rpc.invoke(
        functionName: 'v1_assign_project_member',
        parameters: {
          'p_payload': input.toRpcPayload(),
          'p_idempotency_key': input.idempotencyKey.trim(),
        },
      );
      final result = YorksV1ProjectMembershipResult.fromRpcJson(response);
      operation.complete();
      _captureProjectAccessChange(action: action, success: true);
      return result;
    } on YorksV1DomainException catch (error) {
      operation.fail(error);
      _captureProjectAccessChange(action: action, success: false, error: error);
      rethrow;
    } on PostgrestException catch (error) {
      final mapped = _mapPostgrestException(error);
      operation.fail(mapped);
      _captureProjectAccessChange(
        action: action,
        success: false,
        error: mapped,
      );
      throw mapped;
    } catch (error) {
      final mapped = YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
        cause: error,
      );
      operation.fail(mapped);
      _captureProjectAccessChange(
        action: action,
        success: false,
        error: mapped,
      );
      throw mapped;
    }
  }

  @override
  Future<YorksV1ProjectMembershipResult> revokeProjectMember(
    YorksV1RevokeProjectMemberInput input,
  ) async {
    _throwIfInvalid(input.validate());
    final rpc = _readyRpc();
    const action = 'member_revoked';
    final operation = _analytics.beginOperation(
      'project_access_change',
      properties: const {AnalyticsProperty.actionType: action},
    );
    try {
      final response = await rpc.invoke(
        functionName: 'v1_revoke_project_member',
        parameters: {
          'p_payload': input.toRpcPayload(),
          'p_idempotency_key': input.idempotencyKey.trim(),
        },
      );
      final result = YorksV1ProjectMembershipResult.fromRpcJson(response);
      operation.complete();
      _captureProjectAccessChange(action: action, success: true);
      return result;
    } on YorksV1DomainException catch (error) {
      operation.fail(error);
      _captureProjectAccessChange(action: action, success: false, error: error);
      rethrow;
    } on PostgrestException catch (error) {
      final mapped = _mapPostgrestException(error);
      operation.fail(mapped);
      _captureProjectAccessChange(
        action: action,
        success: false,
        error: mapped,
      );
      throw mapped;
    } catch (error) {
      final mapped = YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
        cause: error,
      );
      operation.fail(mapped);
      _captureProjectAccessChange(
        action: action,
        success: false,
        error: mapped,
      );
      throw mapped;
    }
  }

  @override
  Future<YorksV1Project> setProjectState(
    YorksV1SetProjectStateInput input,
  ) async {
    _throwIfInvalid(input.validate());
    final rpc = _readyRpc();
    try {
      final response = await rpc.invoke(
        functionName: 'v1_set_project_state',
        parameters: {
          'p_payload': input.toRpcPayload(),
          'p_idempotency_key': input.idempotencyKey.trim(),
        },
      );
      final projectJson = response['project'];
      if (projectJson is Map) {
        return YorksV1Project.fromRpcJson(
          Map<String, dynamic>.from(projectJson),
        );
      }
      return YorksV1Project.fromRpcJson(response);
    } on YorksV1DomainException {
      rethrow;
    } on PostgrestException catch (error) {
      throw _mapPostgrestException(error);
    } catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
        cause: error,
      );
    }
  }

  @override
  Future<YorksV1Project> updateProject(YorksV1ProjectUpdateInput input) async {
    final validationErrors = input.validate();
    if (validationErrors.isNotEmpty) {
      _captureProjectUpdateFailure(
        const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput),
      );
    }
    _throwIfInvalid(validationErrors);
    final rpc = _readyRpc();
    final operation = _analytics.beginOperation(
      'project_update',
      properties: const {AnalyticsProperty.workflow: 'project'},
    );
    try {
      final response = await rpc.invoke(
        functionName: 'v1_update_project',
        parameters: {
          'p_payload': input.toRpcPayload(),
          'p_idempotency_key': input.idempotencyKey.trim(),
        },
      );
      final project = YorksV1Project.fromRpcJson(_projectJson(response));
      operation.complete();
      _analytics.capture(AnalyticsEvent.projectUpdated);
      return project;
    } on YorksV1DomainException catch (error) {
      operation.fail(error);
      _captureProjectUpdateFailure(error);
      rethrow;
    } on PostgrestException catch (error) {
      final mapped = _mapPostgrestException(error);
      operation.fail(mapped);
      _captureProjectUpdateFailure(mapped);
      throw mapped;
    } catch (error) {
      final mapped = YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
        cause: error,
      );
      operation.fail(mapped);
      _captureProjectUpdateFailure(mapped);
      throw mapped;
    }
  }

  void _captureProjectAccessChange({
    required String action,
    required bool success,
    Object? error,
  }) {
    _analytics.capture(
      AnalyticsEvent.projectAccessChanged,
      properties: {
        AnalyticsProperty.actionType: action,
        AnalyticsProperty.success: success,
        if (error != null)
          AnalyticsProperty.errorCategory: analyticsErrorCategory(error),
      },
    );
  }

  void _captureProjectUpdateFailure(Object error) {
    _analytics.capture(
      AnalyticsEvent.projectUpdateFailed,
      properties: {
        AnalyticsProperty.errorCategory: analyticsErrorCategory(error),
      },
    );
  }

  @override
  Future<YorksV1Project> archiveProject(
    YorksV1ArchiveProjectInput input,
  ) async {
    _throwIfInvalid(input.validate());
    final rpc = _readyRpc();
    try {
      final response = await rpc.invoke(
        functionName: 'v1_archive_project',
        parameters: {
          'p_payload': input.toRpcPayload(),
          'p_idempotency_key': input.idempotencyKey.trim(),
        },
      );
      return YorksV1Project.fromRpcJson(_projectJson(response));
    } on YorksV1DomainException {
      rethrow;
    } on PostgrestException catch (error) {
      throw _mapPostgrestException(error);
    } catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
        cause: error,
      );
    }
  }

  Map<String, dynamic> _projectJson(Map<String, dynamic> response) {
    final project = response['project'];
    return project is Map ? Map<String, dynamic>.from(project) : response;
  }

  YorksV1ProjectRpcClient _readyRpc() {
    if (!_featureFlags.projects) {
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
    return rpc;
  }

  void _throwIfInvalid(Set<YorksV1ProjectValidationCode> errors) {
    if (errors.isEmpty) return;
    throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
  }

  YorksV1DomainException _mapPostgrestException(PostgrestException error) {
    final code = error.code;
    final domainCode = switch (code) {
      '42501' || '28000' => YorksV1DomainErrorCode.unauthorized,
      '23505' || '40001' => YorksV1DomainErrorCode.conflict,
      'PGRST002' || 'PGRST003' => YorksV1DomainErrorCode.backendUnavailable,
      '22023' ||
      '22007' ||
      '22P02' ||
      '23514' => YorksV1DomainErrorCode.invalidInput,
      _ => YorksV1DomainErrorCode.serverRejected,
    };
    return YorksV1DomainException(domainCode, serverCode: code, cause: error);
  }
}

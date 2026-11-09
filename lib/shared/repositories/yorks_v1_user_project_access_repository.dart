import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/yorks_v1_domain_error.dart';
import '../models/yorks_v1_project.dart';
import '../models/yorks_v1_user_project_access.dart';

/// Input for assigning, changing or removing one user's role on one project.
class YorksV1SetUserProjectMembershipInput {
  const YorksV1SetUserProjectMembershipInput({
    required this.appUserId,
    required this.projectId,
    required this.role,
    required this.expectedProjectVersion,
    required this.reason,
    required this.idempotencyKey,
  });

  final String appUserId;
  final String projectId;

  /// Null removes the user from the project team.
  final YorksV1ProjectMembershipRole? role;
  final int expectedProjectVersion;
  final String reason;
  final String idempotencyKey;
}

class YorksV1SetUserProjectMembershipResult {
  const YorksV1SetUserProjectMembershipResult({
    required this.changed,
    required this.projectRecordVersion,
  });

  final bool changed;
  final int projectRecordVersion;
}

abstract interface class YorksV1UserProjectAccessRepository {
  Future<YorksV1UserProjectAccessDirectory> load();

  Future<YorksV1SetUserProjectMembershipResult> setMembership(
    YorksV1SetUserProjectMembershipInput input,
  );
}

/// Reads and changes project access by stable app user ID. Auth UUIDs never
/// reach the client; the database resolves them.
class YorksV1SupabaseUserProjectAccessRepository
    implements YorksV1UserProjectAccessRepository {
  const YorksV1SupabaseUserProjectAccessRepository(
    this._client, {
    Duration timeout = const Duration(seconds: 20),
  }) : _timeout = timeout;

  final SupabaseClient _client;
  final Duration _timeout;

  @override
  Future<YorksV1UserProjectAccessDirectory> load() async {
    final response = await _invoke('v1_list_user_project_access', const {});
    if (response is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1UserProjectAccessDirectory.fromRpcJson(
      Map<String, dynamic>.from(response),
    );
  }

  @override
  Future<YorksV1SetUserProjectMembershipResult> setMembership(
    YorksV1SetUserProjectMembershipInput input,
  ) async {
    final response = await _invoke('v1_set_user_project_membership', {
      'p_payload': {
        'app_user_id': input.appUserId,
        'project_id': input.projectId,
        'project_role': input.role?.wireValue,
        'expected_version': input.expectedProjectVersion,
        'reason': input.reason,
      },
      'p_idempotency_key': input.idempotencyKey,
    });
    if (response is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    final version = response['project_record_version'];
    return YorksV1SetUserProjectMembershipResult(
      changed: response['changed'] == true,
      projectRecordVersion: version is num
          ? version.toInt()
          : input.expectedProjectVersion,
    );
  }

  Future<Object?> _invoke(
    String functionName,
    Map<String, Object?> parameters,
  ) async {
    try {
      return await _client
          .rpc(functionName, params: parameters)
          .timeout(_timeout);
    } on TimeoutException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
        cause: error,
      );
    } on PostgrestException catch (error) {
      throw yorksV1UserProjectAccessFailure(error.code, error.message);
    } on YorksV1DomainException {
      rethrow;
    } catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
        cause: error,
      );
    }
  }
}

/// Maps a database failure to a typed error. The message is kept so the
/// screen can explain the exact rule that refused a team change.
YorksV1DomainException yorksV1UserProjectAccessFailure(
  String? code,
  String? message,
) {
  final mapped = switch (code) {
    '42501' || '28000' => YorksV1DomainErrorCode.unauthorized,
    '40001' || '55P03' || '23505' => YorksV1DomainErrorCode.conflict,
    '55000' => YorksV1DomainErrorCode.invalidTransition,
    '22023' || '22P02' || 'P0002' => YorksV1DomainErrorCode.invalidInput,
    'PGRST002' ||
    'PGRST003' ||
    'PGRST202' ||
    '57014' => YorksV1DomainErrorCode.backendUnavailable,
    _ => YorksV1DomainErrorCode.serverRejected,
  };
  return YorksV1DomainException(
    mapped,
    serverCode: code,
    serverMessage: message,
  );
}

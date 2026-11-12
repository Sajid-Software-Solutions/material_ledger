/// Workforce attendance V2 — trusted RPC access. Every command needs the
/// connection and a server confirmation; nothing here is optimistic.
library;

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/models/yorks_v1_domain_error.dart';
import '../../../shared/models/yorks_v1_feature_flags.dart';
import '../../../shared/sync/connectivity_service.dart';
import '../domain/attendance_models.dart';
import 'workforce_repository.dart';

final class YorksAttendanceRepository {
  YorksAttendanceRepository({
    required YorksV1FeatureFlags featureFlags,
    required ConnectivityService connectivity,
    required YorksWorkforceRpcClient? rpcClient,
  }) : _featureFlags = featureFlags,
       _connectivity = connectivity,
       _rpcClient = rpcClient;

  final YorksV1FeatureFlags _featureFlags;
  final ConnectivityService _connectivity;
  final YorksWorkforceRpcClient? _rpcClient;

  static String newKey() => const Uuid().v4();

  Future<AttendanceOverview> getOverview({String? month}) async =>
      AttendanceOverview.fromJson(
        await _invoke('v1_wf_get_overview', {'p_month': month}),
      );

  Future<List<AttendanceCrew>> listCrews() async {
    final json = await _invoke('v1_wf_list_crews', const {});
    return [
      for (final crew in (json['crews'] as List? ?? const []))
        AttendanceCrew.fromJson(Map<String, dynamic>.from(crew as Map)),
    ];
  }

  Future<bool> canCreateCrew() async =>
      (await _invoke('v1_wf_list_crews', const {}))['can_create_crew'] == true;

  Future<({AttendanceCrew crew, List<AttendanceWorker> members})> getCrew(
    String crewId,
  ) async {
    final json = await _invoke('v1_wf_get_crew', {'p_team_id': crewId});
    return (
      crew: AttendanceCrew.fromJson(json),
      members: [
        for (final member in (json['members'] as List? ?? const []))
          AttendanceWorker.fromJson(Map<String, dynamic>.from(member as Map)),
      ],
    );
  }

  Future<AttendanceDay> getDay({
    required String crewId,
    required String date,
  }) async => AttendanceDay.fromJson(
    await _invoke('v1_wf_get_day', {'p_team_id': crewId, 'p_work_date': date}),
  );

  Future<AttendanceDay> saveDay({
    required String crewId,
    required String date,
    required List<AttendanceRow> rows,
    required int expectedVersion,
    required String idempotencyKey,
    String? changeReason,
  }) async => AttendanceDay.fromJson(
    await _invoke('v1_wf_save_day', {
      'p_team_id': crewId,
      'p_work_date': date,
      'p_rows': [for (final row in rows) row.toPayload()],
      'p_expected_version': expectedVersion,
      'p_change_reason': changeReason,
      'p_idempotency_key': idempotencyKey,
    }),
  );

  Future<AttendanceDay> askDay({
    required String crewId,
    required String date,
    required String question,
    required String idempotencyKey,
  }) async => AttendanceDay.fromJson(
    await _invoke('v1_wf_ask_day', {
      'p_team_id': crewId,
      'p_work_date': date,
      'p_question': question,
      'p_idempotency_key': idempotencyKey,
    }),
  );

  Future<AttendanceDay> answerDay({
    required String crewId,
    required String date,
    required String answer,
    required String idempotencyKey,
  }) async => AttendanceDay.fromJson(
    await _invoke('v1_wf_answer_day', {
      'p_team_id': crewId,
      'p_work_date': date,
      'p_answer': answer,
      'p_idempotency_key': idempotencyKey,
    }),
  );

  Future<AttendanceMonth> confirmMonth({
    required String crewId,
    required String month,
    required String idempotencyKey,
  }) async => AttendanceMonth.fromJson(
    await _invoke('v1_wf_confirm_month', {
      'p_team_id': crewId,
      'p_month': month,
      'p_idempotency_key': idempotencyKey,
    }),
  );

  Future<AttendanceMonth> reopenMonth({
    required String crewId,
    required String month,
    required String reason,
    required String idempotencyKey,
  }) async => AttendanceMonth.fromJson(
    await _invoke('v1_wf_reopen_month', {
      'p_team_id': crewId,
      'p_month': month,
      'p_reason': reason,
      'p_idempotency_key': idempotencyKey,
    }),
  );

  Future<AttendanceMonthSheet> getMonthSheet({
    required String crewId,
    required String month,
  }) async => AttendanceMonthSheet.fromJson(
    await _invoke('v1_wf_get_month_sheet', {
      'p_team_id': crewId,
      'p_month': month,
    }),
  );

  Future<List<AttendanceWorker>> listWorkers() async {
    final json = await _invoke('v1_wf_list_workers', const {});
    return [
      for (final worker in (json['workers'] as List? ?? const []))
        AttendanceWorker.fromJson(Map<String, dynamic>.from(worker as Map)),
    ];
  }

  Future<AttendanceCrew> saveCrew({
    required Map<String, Object?> payload,
    required int expectedVersion,
    required String idempotencyKey,
  }) async => AttendanceCrew.fromJson(
    await _invoke('v1_wf_save_crew', {
      'p_payload': payload,
      'p_expected_version': expectedVersion,
      'p_idempotency_key': idempotencyKey,
    }),
  );

  Future<AttendanceCrew> setCrewMembers({
    required String crewId,
    List<String> add = const [],
    List<String> remove = const [],
    required String idempotencyKey,
  }) async => AttendanceCrew.fromJson(
    await _invoke('v1_wf_set_crew_members', {
      'p_team_id': crewId,
      'p_add_worker_ids': add,
      'p_remove_worker_ids': remove,
      'p_idempotency_key': idempotencyKey,
    }),
  );

  Future<Map<String, dynamic>> _invoke(
    String functionName,
    Map<String, Object?> parameters,
  ) async {
    if (!_featureFlags.workforceAttendanceV2) {
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
      return await rpc.invoke(
        functionName: functionName,
        parameters: parameters,
      );
    } on YorksV1DomainException {
      rethrow;
    } on PostgrestException catch (error) {
      final code = switch (error.code) {
        'PGRST301' ||
        'PGRST302' ||
        'PGRST303' ||
        '28000' => YorksV1DomainErrorCode.unauthenticated,
        '42501' => YorksV1DomainErrorCode.unauthorized,
        '40001' => YorksV1DomainErrorCode.conflict,
        '55000' => YorksV1DomainErrorCode.invalidTransition,
        '22023' || '22P02' || '23505' => YorksV1DomainErrorCode.invalidInput,
        'PGRST002' || 'PGRST003' => YorksV1DomainErrorCode.backendUnavailable,
        _ => YorksV1DomainErrorCode.serverRejected,
      };
      throw YorksV1DomainException(
        code,
        serverCode: error.code,
        serverMessage: error.message,
        cause: error,
      );
    } catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
        cause: error,
      );
    }
  }
}

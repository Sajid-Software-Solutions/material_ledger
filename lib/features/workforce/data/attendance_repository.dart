/// Workforce attendance V2 — trusted RPC access. Every command needs the
/// connection and a server confirmation; nothing here is optimistic.
library;

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/models/yorks_v1_domain_error.dart';
import '../../../shared/models/yorks_v1_feature_flags.dart';
import '../../../shared/sync/connectivity_service.dart';
import '../domain/attendance_models.dart';
import '../domain/attendance_month_models.dart';
import '../domain/crew_request_models.dart';
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

  Future<List<AttendanceConfirmationDue>> confirmationsDue() async {
    final json = await _invoke('v1_wf_get_confirmations_due', const {});
    return [
      for (final row in (json['due'] as List? ?? const []))
        AttendanceConfirmationDue.fromJson(
          Map<String, dynamic>.from(row as Map),
        ),
    ];
  }

  Future<List<AttendanceCrew>> listCrews() async {
    final json = await _invoke('v1_wf_list_crews', const {});
    return [
      for (final crew in (json['crews'] as List? ?? const []))
        AttendanceCrew.fromJson(Map<String, dynamic>.from(crew as Map)),
    ];
  }

  /// Projects and internal locations the signed-in person may keep or read
  /// attendance at (PRODUCT_DECISIONS section 51).
  Future<AttendancePlaces> listPlaces() async =>
      AttendancePlaces.fromJson(await _invoke('v1_wf_list_places', const {}));

  /// Opens the shared sheet for a project or an internal location: the one
  /// already open, else the project's old sheet, else a new one. Opening is
  /// a find-or-create on the place, so a retry gets the same sheet.
  Future<AttendanceCrew> openPlace({
    String? projectId,
    String? location,
  }) async => AttendanceCrew.fromJson(
    await _invoke('v1_wf_open_place', {
      'p_project_id': projectId,
      'p_location': location,
    }),
  );

  /// Everyone's month (`YYYY-MM-01`) at the places the reader may see.
  Future<AttendancePeopleMonth> peopleMonth(String month) async =>
      AttendancePeopleMonth.fromJson(
        await _invoke('v1_wf_people_month', {'p_month': month}),
      );

  /// One labourer's month at every place the reader may see.
  Future<AttendanceWorkerMonth> workerMonth({
    required String workerId,
    required String month,
  }) async => AttendanceWorkerMonth.fromJson(
    await _invoke('v1_wf_worker_month', {
      'p_worker_id': workerId,
      'p_month': month,
    }),
  );

  /// The workforce year: by month, place and labourer.
  Future<AttendanceWorkforceYear> workforceYear(int year) async =>
      AttendanceWorkforceYear.fromJson(
        await _invoke('v1_wf_workforce_year', {'p_year': year}),
      );

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

  /// Status only (expired, expiring, OK) of the documents of a crew's
  /// workers, by worker id. No document kind, number or date is returned.
  Future<Map<String, CrewDocumentStatus>> crewDocumentStatus(
    String crewId,
  ) async {
    final json = await _invoke('v1_wf_crew_document_status', {
      'p_team_id': crewId,
    });
    final statuses = json['statuses'];
    return {
      if (statuses is Map)
        for (final MapEntry(:key, :value) in statuses.entries)
          key.toString(): ?CrewDocumentStatus.from(value),
    };
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
      // A member recorded at another place and not marked here is left out.
      'p_rows': [
        for (final row in rows)
          if (row.isMarked) row.toPayload(),
      ],
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

  Future<AttendanceHolidays> listHolidays(int year) async =>
      AttendanceHolidays.fromJson(
        await _invoke('v1_wf_list_public_holidays', {'p_year': year}),
      );

  Future<AttendanceHolidays> saveHoliday({
    required String date,
    String? name,
    bool remove = false,
  }) async => AttendanceHolidays.fromJson(
    await _invoke('v1_wf_save_public_holiday', {
      'p_holiday_date': date,
      'p_holiday_name': name,
      'p_remove': remove,
    }),
  );

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

  // ─── Crew requests (Workforce Center) ─────────────────────────────────────

  Future<CrewRequestRegister> listRequests() async =>
      CrewRequestRegister.fromJson(
        await _invokeCenter('v1_wf_list_requests', const {}),
      );

  Future<CrewRequest> getRequest(String requestId) async =>
      CrewRequest.fromJson(
        await _invokeCenter('v1_wf_get_request', {'p_request_id': requestId}),
      );

  Future<CrewRequestOptions> requestOptions() async =>
      CrewRequestOptions.fromJson(
        await _invokeCenter('v1_wf_request_options', const {}),
      );

  /// Raises a request, or resubmits a returned one when [requestId] is set.
  Future<CrewRequest> submitRequest({
    String? requestId,
    required String crewKind,
    String? projectId,
    String? workLabel,
    String? targetCrewId,
    required String neededFrom,
    String? neededUntil,
    String? notes,
    required List<CrewRequestDraftLine> lines,
    int? expectedVersion,
    required String idempotencyKey,
  }) async => CrewRequest.fromJson(
    await _invokeCenter('v1_wf_submit_request', {
      'p_payload': {
        'request_id': ?requestId,
        'crew_kind': crewKind,
        'project_id': ?projectId,
        if (workLabel != null && workLabel.trim().isNotEmpty)
          'work_label': workLabel.trim(),
        'target_crew_id': ?targetCrewId,
        'needed_from': neededFrom,
        'needed_until': ?neededUntil,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        'lines': [for (final line in lines) line.toJson()],
      },
      'p_expected_version': expectedVersion,
      'p_idempotency_key': idempotencyKey,
    }),
  );

  /// [decision] is `approve`, `return` or `reject`.
  Future<CrewRequest> decideRequest({
    required String requestId,
    required String decision,
    String? reason,
    required int expectedVersion,
    required String idempotencyKey,
  }) async => CrewRequest.fromJson(
    await _invokeCenter('v1_wf_decide_request', {
      'p_request_id': requestId,
      'p_decision': decision,
      'p_reason': reason,
      'p_expected_version': expectedVersion,
      'p_idempotency_key': idempotencyKey,
    }),
  );

  Future<CrewRequest> cancelRequest({
    required String requestId,
    String? reason,
    required int expectedVersion,
    required String idempotencyKey,
  }) async => CrewRequest.fromJson(
    await _invokeCenter('v1_wf_cancel_request', {
      'p_request_id': requestId,
      'p_reason': reason,
      'p_expected_version': expectedVersion,
      'p_idempotency_key': idempotencyKey,
    }),
  );

  /// Assigns workers into [crewId], or into a new crew described by
  /// [newCrew] (`name`, `shift_start_minute`, `shift_finish_minute`, and
  /// optionally a break).
  Future<CrewRequest> fulfilRequest({
    required String requestId,
    String? crewId,
    Map<String, Object?>? newCrew,
    required List<CrewRequestFulfilLine> lines,
    required int expectedVersion,
    required String idempotencyKey,
    bool approve = false,
  }) async => CrewRequest.fromJson(
    await _invokeCenter('v1_wf_fulfil_request', {
      'p_request_id': requestId,
      'p_payload': {
        if (approve) 'approve': true,
        'crew_id': ?crewId,
        'new_crew': ?newCrew,
        'lines': [for (final line in lines) line.toJson()],
      },
      'p_expected_version': expectedVersion,
      'p_idempotency_key': idempotencyKey,
    }),
  );

  /// Work done: the request finishes and its workers leave the crew.
  Future<CrewRequest> finishRequest({
    required String requestId,
    String? reason,
    required int expectedVersion,
    required String idempotencyKey,
  }) async => CrewRequest.fromJson(
    await _invokeCenter('v1_wf_finish_request', {
      'p_request_id': requestId,
      'p_reason': reason,
      'p_expected_version': expectedVersion,
      'p_idempotency_key': idempotencyKey,
    }),
  );

  /// One worker is no longer needed and leaves the crew. The last one out
  /// of a fully assigned request finishes it.
  Future<CrewRequest> releaseWorker({
    required String requestId,
    required String workerId,
    String? reason,
    required int expectedVersion,
    required String idempotencyKey,
  }) async => CrewRequest.fromJson(
    await _invokeCenter('v1_wf_release_request_worker', {
      'p_request_id': requestId,
      'p_worker_id': workerId,
      'p_reason': reason,
      'p_expected_version': expectedVersion,
      'p_idempotency_key': idempotencyKey,
    }),
  );

  Future<CrewRequest> closeRequest({
    required String requestId,
    required String reason,
    required int expectedVersion,
    required String idempotencyKey,
  }) async => CrewRequest.fromJson(
    await _invokeCenter('v1_wf_close_request', {
      'p_request_id': requestId,
      'p_reason': reason,
      'p_expected_version': expectedVersion,
      'p_idempotency_key': idempotencyKey,
    }),
  );

  Future<Map<String, dynamic>> _invokeCenter(
    String functionName,
    Map<String, Object?> parameters,
  ) {
    if (!_featureFlags.workforceCenter) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.featureDisabled,
      );
    }
    return _invoke(functionName, parameters);
  }

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

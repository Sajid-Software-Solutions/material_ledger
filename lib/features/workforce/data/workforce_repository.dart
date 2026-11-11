import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/yorks_v1_domain_error.dart';
import '../../../shared/models/yorks_v1_feature_flags.dart';
import '../../../shared/sync/connectivity_service.dart';
import '../../../shared/repositories/yorks_v1_documents_repository.dart';
import '../domain/workforce_attendance_models.dart';
import '../domain/workforce_administration_models.dart';
import '../domain/workforce_configuration_models.dart';
import '../domain/workforce_collaboration_models.dart';
import '../domain/workforce_daily_roster_models.dart';
import '../domain/workforce_dashboard_models.dart';
import '../domain/workforce_foundation_models.dart';
import '../domain/workforce_monthly_period_models.dart';
import '../domain/workforce_report_models.dart';
import '../domain/workforce_review_models.dart';
import '../domain/workforce_timesheet_models.dart';

abstract interface class YorksWorkforceRpcClient {
  Future<Map<String, dynamic>> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  });
}

final class SupabaseYorksWorkforceRpcClient implements YorksWorkforceRpcClient {
  const SupabaseYorksWorkforceRpcClient(this._client);

  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async {
    final response = await _client.rpc(functionName, params: parameters);
    return switch (response) {
      final Map value => Map<String, dynamic>.from(value),
      final List value when value.length == 1 && value.single is Map =>
        Map<String, dynamic>.from(value.single as Map),
      _ => throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      ),
    };
  }
}

abstract interface class YorksWorkforceRepository {
  Future<YorksWorkforceMonthlyTeamProjection> listMonthlyTeams(
    YorksWorkforceMonthlyTeamFilters filters,
  );

  Future<YorksWorkforceMonthlyProjection> getMonthlyPeriod(
    YorksWorkforceMonthlyFilters filters,
  );

  Future<YorksWorkforceMonthlyWorkerDetail> getMonthlyWorkerDetail({
    required String periodId,
    required String validationRunId,
    required String workerId,
  });

  Future<YorksWorkforceMonthlyIssueProjection> listMonthlyIssues(
    YorksWorkforceMonthlyIssueFilters filters,
  );

  Future<YorksWorkforceMonthlyValidationResult> validateMonthlyPeriod({
    required String teamId,
    required String periodMonth,
    required int? expectedPeriodVersion,
    required String idempotencyKey,
  });

  Future<YorksWorkforceDailyRosterProjection> getDailyRoster({
    required String workDate,
    YorksWorkforceRosterFilters filters = const YorksWorkforceRosterFilters(),
  });

  Future<YorksWorkforceDailyRosterSaveResult> saveDailyRoster({
    required String workDate,
    required List<YorksWorkforceDailyRosterSaveRow> rows,
    required String reason,
    required String idempotencyKey,
  });

  Future<YorksWorkforceTimesheetProjection> getTimesheetAllocations({
    required String workDate,
    String? workerId,
  });

  Future<YorksWorkforceAttendanceProjection> getAttendance({
    required String workDate,
    String? workerId,
  });

  Future<YorksWorkforceConfigurationProjection> getConfiguration({
    String? onDate,
  });

  Future<YorksWorkforceAdministrationOptions> getAdministrationOptions({
    String? onDate,
  });

  Future<YorksWorkforceFoundationProjection> getFoundation({
    String? query,
    YorksWorkforceWorkerStatus? status,
    int limit = 50,
    int offset = 0,
    String? onDate,
  });

  Future<YorksWorkforceCommandResult> saveTrade(
    Map<String, Object?> payload, {
    int? expectedVersion,
    required String idempotencyKey,
  });

  Future<YorksWorkforceCommandResult> saveInternalLocation(
    Map<String, Object?> payload, {
    int? expectedVersion,
    required String idempotencyKey,
  });

  Future<YorksWorkforceCommandResult> saveWorker(
    Map<String, Object?> payload, {
    int? expectedVersion,
    required String idempotencyKey,
  });

  Future<YorksWorkforceCommandResult> saveTeam(
    Map<String, Object?> payload, {
    int? expectedVersion,
    required String idempotencyKey,
  });

  Future<YorksWorkforceCommandResult> saveWorkerAssignment(
    Map<String, Object?> payload, {
    int? expectedVersion,
    required String idempotencyKey,
  });

  Future<YorksWorkforceCommandResult> transferWorkerAssignment(
    Map<String, Object?> payload, {
    String? expectedCurrentAssignmentId,
    int? expectedCurrentVersion,
    required String idempotencyKey,
  });

  Future<YorksWorkforceCommandResult> saveResponsibilityAssignment(
    Map<String, Object?> payload, {
    int? expectedVersion,
    required String idempotencyKey,
  });

  Future<YorksWorkforceCommandResult> saveCalendar(
    Map<String, Object?> payload, {
    int? expectedVersion,
    required String idempotencyKey,
  });

  Future<YorksWorkforceCommandResult> saveCalendarDate(
    Map<String, Object?> payload, {
    int? expectedVersion,
    required String idempotencyKey,
  });

  Future<YorksWorkforceCommandResult> saveShiftTemplate(
    Map<String, Object?> payload, {
    int? expectedVersion,
    required String idempotencyKey,
  });

  Future<YorksWorkforceCommandResult> saveTeamSchedule(
    Map<String, Object?> payload, {
    int? expectedVersion,
    required String idempotencyKey,
  });

  Future<YorksWorkforceCommandResult> saveAttendanceDay(
    YorksWorkforceAttendanceInput input, {
    int? expectedVersion,
    required String idempotencyKey,
  });

  Future<YorksWorkforceTimesheetCommandResult> saveTimesheetAllocations(
    YorksWorkforceTimesheetAllocationInput input, {
    int? expectedVersion,
    required String idempotencyKey,
  });

  Future<YorksWorkforceTimesheetCommandResult> withdrawTimesheetAllocations({
    required String attendanceDayId,
    required String reason,
    required int expectedVersion,
    required String idempotencyKey,
  });
}

/// T07 lifecycle boundary, intentionally separate from the accepted T01-T06
/// repository contract so earlier test doubles and consumers do not inherit
/// review or approval authority.
abstract interface class YorksWorkforceReviewRepository {
  Future<YorksWorkforceReviewQueue> listMonthlyApprovalQueue({
    YorksWorkforceMonthlyPeriodStatus? status,
    int limit = 50,
    int offset = 0,
  });

  Future<YorksWorkforceReviewLifecycle> getMonthlyLifecycle(String periodId);

  Future<YorksWorkforceReviewLifecycle> submitMonthlyPeriod({
    required String periodId,
    required Iterable<String> warningIssueIds,
    required String reason,
    required int expectedVersion,
    required String idempotencyKey,
  });

  Future<YorksWorkforceReviewLifecycle> returnMonthlyPeriod({
    required String periodId,
    required Iterable<YorksWorkforceAffectedEntry> affectedEntries,
    required String reason,
    String? attachmentReference,
    required int expectedVersion,
    required String idempotencyKey,
  });

  Future<YorksWorkforceReviewLifecycle> correctMonthlyEntryDuringReview({
    required String periodId,
    required String workDate,
    required YorksWorkforceDailyRosterSaveRow row,
    required String reason,
    required int expectedVersion,
    required String idempotencyKey,
  });

  Future<YorksWorkforceReviewLifecycle> verifyMonthlyPeriod({
    required String periodId,
    required String reason,
    required int expectedVersion,
    required String idempotencyKey,
  });

  Future<YorksWorkforceReviewLifecycle> approveAndLockMonthlyPeriod({
    required String periodId,
    required String reason,
    required int expectedVersion,
    required String idempotencyKey,
  });

  Future<YorksWorkforceReviewLifecycle> requestMonthlyReopen({
    required String periodId,
    required Iterable<YorksWorkforceAffectedEntry> affectedEntries,
    required String reason,
    String? attachmentReference,
    required int expectedVersion,
    required String idempotencyKey,
  });

  Future<YorksWorkforceReviewLifecycle> authorizeMonthlyReopen({
    required String periodId,
    required String requestId,
    required String reason,
    required int expectedVersion,
    required String idempotencyKey,
  });
}

/// T08 collaboration/evidence boundary. It deliberately reuses the accepted
/// Chat, Documents and Notifications services through dedicated role-safe RPCs
/// without turning comment text into lifecycle authority.
abstract interface class YorksWorkforceCollaborationRepository {
  Future<YorksWorkforceCollaborationProjection> getCollaboration(
    String periodId,
  );

  Future<YorksWorkforceDiscussionResult> openDiscussion({
    required String periodId,
    required String idempotencyKey,
  });

  Future<YorksWorkforceDiscussionMessageResult> sendDiscussionMessage(
    YorksWorkforceDiscussionMessageInput input, {
    required String idempotencyKey,
  });

  Future<YorksWorkforceEvidenceProjection> listEvidence({
    String? periodId,
    String? attendanceDayId,
    String? workerId,
  });

  Future<YorksWorkforceEvidenceUploadIntent> prepareEvidenceUpload(
    YorksWorkforceEvidenceUploadInput input, {
    required String idempotencyKey,
  });

  Future<YorksWorkforceEvidenceProjection> uploadEvidence(
    YorksWorkforceEvidenceUploadInput input, {
    required Uint8List bytes,
    required String idempotencyKey,
  });
}

/// T09 protected reporting boundary. Server-produced projections are the only
/// input to local XLSX/PDF renderers; binaries never reconstruct authority.
abstract interface class YorksWorkforceReportRepository {
  Future<YorksWorkforceReportArtifact> generateReport(
    YorksWorkforceReportRequest request, {
    required String idempotencyKey,
  });

  Future<YorksWorkforceReportHistory> listReportArtifacts({
    int limit = 25,
    int offset = 0,
  });

  Future<YorksWorkforceReportIssueReceipt> issueReportExport(
    YorksWorkforceReportIssueRequest request, {
    required String idempotencyKey,
  });
}

/// T10 read-only dashboard boundary. It owns no command or export method.
abstract interface class YorksWorkforceDashboardRepository {
  Future<YorksWorkforceOverviewProjection> getOverview(
    YorksWorkforceOverviewRequest request,
  );
}

abstract interface class YorksWorkforceTeamWorkerRepository {
  Future<Map<String, dynamic>> getTeamWorkers({String? teamId, int offset = 0});
  Future<Map<String, dynamic>> createTeamWorker(
    String teamId,
    Map<String, Object?> payload,
    String idempotencyKey,
  );
}

final class YorksSupabaseWorkforceRepository
    implements
        YorksWorkforceRepository,
        YorksWorkforceReviewRepository,
        YorksWorkforceCollaborationRepository,
        YorksWorkforceReportRepository,
        YorksWorkforceDashboardRepository,
        YorksWorkforceTeamWorkerRepository {
  const YorksSupabaseWorkforceRepository({
    required YorksV1FeatureFlags featureFlags,
    required ConnectivityService connectivity,
    YorksWorkforceRpcClient? rpcClient,
    YorksV1DocumentStorageClient? documentStorageClient,
    YorksV1DocumentFinalizerClient? documentFinalizerClient,
  }) : _featureFlags = featureFlags,
       _connectivity = connectivity,
       _rpcClient = rpcClient,
       _documentStorageClient = documentStorageClient,
       _documentFinalizerClient = documentFinalizerClient;

  final YorksV1FeatureFlags _featureFlags;
  final ConnectivityService _connectivity;
  final YorksWorkforceRpcClient? _rpcClient;
  final YorksV1DocumentStorageClient? _documentStorageClient;
  final YorksV1DocumentFinalizerClient? _documentFinalizerClient;

  @override
  Future<Map<String, dynamic>> getTeamWorkers({
    String? teamId,
    int offset = 0,
  }) => _invoke('v1_get_workforce_team_workers', {
    'p_team_id': teamId,
    'p_offset': offset,
  });

  @override
  Future<Map<String, dynamic>> createTeamWorker(
    String teamId,
    Map<String, Object?> payload,
    String idempotencyKey,
  ) => _invoke('v1_create_workforce_team_worker', {
    'p_team_id': teamId,
    'p_payload': payload,
    'p_idempotency_key': idempotencyKey,
  });

  @override
  Future<YorksWorkforceOverviewProjection> getOverview(
    YorksWorkforceOverviewRequest request,
  ) async {
    Map<String, Object?> payload;
    try {
      payload = request.toRpcJson();
    } on FormatException {
      return _invalidInput();
    }
    final response = await _invoke('v1_get_workforce_overview', {
      'p_request': payload,
    });
    try {
      final projection = YorksWorkforceOverviewProjection.fromRpcJson(response);
      if (projection.kind != request.kind) {
        throw const FormatException('Overview request mismatch');
      }
      return projection;
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<YorksWorkforceReportArtifact> generateReport(
    YorksWorkforceReportRequest request, {
    required String idempotencyKey,
  }) async {
    final normalizedKey = idempotencyKey.trim();
    if (!_isUuid(normalizedKey)) return _invalidInput();
    Map<String, Object?> payload;
    try {
      payload = request.toRpcJson();
    } on FormatException {
      return _invalidInput();
    }
    final response = await _invoke('v1_generate_workforce_report', {
      'p_payload': payload,
      'p_idempotency_key': normalizedKey,
    });
    try {
      return YorksWorkforceReportArtifact.fromRpcJson(response);
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<YorksWorkforceReportHistory> listReportArtifacts({
    int limit = 25,
    int offset = 0,
  }) async {
    if (limit < 1 || limit > 100 || offset < 0) return _invalidInput();
    final response = await _invoke('v1_list_workforce_report_artifacts', {
      'p_limit': limit,
      'p_offset': offset,
    });
    try {
      final result = YorksWorkforceReportHistory.fromRpcJson(response);
      if (result.limit != limit || result.offset != offset) {
        throw const FormatException('Report history request mismatch');
      }
      return result;
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<YorksWorkforceReportIssueReceipt> issueReportExport(
    YorksWorkforceReportIssueRequest request, {
    required String idempotencyKey,
  }) async {
    final normalizedKey = idempotencyKey.trim();
    if (!_isUuid(normalizedKey)) return _invalidInput();
    Map<String, Object?> payload;
    try {
      payload = request.toRpcJson();
    } on FormatException {
      return _invalidInput();
    }
    final response = await _invoke('v1_issue_workforce_report_export', {
      'p_payload': payload,
      'p_idempotency_key': normalizedKey,
    });
    try {
      final receipt = YorksWorkforceReportIssueReceipt.fromRpcJson(response);
      if (receipt.artifactId != request.artifactId ||
          receipt.format != request.format ||
          receipt.action != request.action) {
        throw const FormatException('Report issuance request mismatch');
      }
      return receipt;
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<YorksWorkforceCollaborationProjection> getCollaboration(
    String periodId,
  ) async {
    final normalizedPeriod = periodId.trim();
    if (!_isUuid(normalizedPeriod)) return _invalidInput();
    final response = await _invoke('v1_get_workforce_collaboration', {
      'p_period_id': normalizedPeriod,
    });
    try {
      final projection = YorksWorkforceCollaborationProjection.fromRpcJson(
        response,
      );
      if (projection.periodId != normalizedPeriod) {
        throw const FormatException('Collaboration period mismatch');
      }
      return projection;
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<YorksWorkforceDiscussionResult> openDiscussion({
    required String periodId,
    required String idempotencyKey,
  }) async {
    final normalizedPeriod = periodId.trim();
    final normalizedKey = idempotencyKey.trim();
    if (!_isUuid(normalizedPeriod) || !_isUuid(normalizedKey)) {
      return _invalidInput();
    }
    final response = await _invoke('v1_open_workforce_timesheet_discussion', {
      'p_period_id': normalizedPeriod,
      'p_idempotency_key': normalizedKey,
    });
    try {
      final result = YorksWorkforceDiscussionResult.fromRpcJson(response);
      if (result.periodId != normalizedPeriod ||
          result.thread.conversation.id.isEmpty) {
        throw const FormatException('Discussion context mismatch');
      }
      return result;
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<YorksWorkforceDiscussionMessageResult> sendDiscussionMessage(
    YorksWorkforceDiscussionMessageInput input, {
    required String idempotencyKey,
  }) async {
    final normalizedKey = idempotencyKey.trim();
    if (!input.isValid || !_isUuid(normalizedKey)) return _invalidInput();
    final response = await _invoke('v1_send_workforce_timesheet_message', {
      'p_payload': input.toRpcJson(),
      'p_idempotency_key': normalizedKey,
    });
    try {
      final result = YorksWorkforceDiscussionMessageResult.fromRpcJson(
        response,
      );
      if (result.periodId != input.periodId.trim() ||
          result.message.conversationId != result.conversation.id) {
        throw const FormatException('Message context mismatch');
      }
      return result;
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<YorksWorkforceEvidenceProjection> listEvidence({
    String? periodId,
    String? attendanceDayId,
    String? workerId,
  }) async {
    final normalizedPeriod = _nullableTrimmed(periodId);
    final normalizedDay = _nullableTrimmed(attendanceDayId);
    final normalizedWorker = _nullableTrimmed(workerId);
    if ((normalizedPeriod == null &&
            normalizedDay == null &&
            normalizedWorker == null) ||
        (normalizedPeriod != null && !_isUuid(normalizedPeriod)) ||
        (normalizedDay != null && !_isUuid(normalizedDay)) ||
        (normalizedWorker != null && !_isUuid(normalizedWorker))) {
      return _invalidInput();
    }
    final response = await _invoke('v1_list_workforce_documents', {
      'p_period_id': normalizedPeriod,
      'p_attendance_day_id': normalizedDay,
      'p_worker_id': normalizedWorker,
    });
    try {
      return YorksWorkforceEvidenceProjection.fromRpcJson(response);
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<YorksWorkforceEvidenceUploadIntent> prepareEvidenceUpload(
    YorksWorkforceEvidenceUploadInput input, {
    required String idempotencyKey,
  }) async {
    final normalizedKey = idempotencyKey.trim();
    if (!input.isValid || !_isUuid(normalizedKey)) return _invalidInput();
    final response = await _invoke('v1_prepare_workforce_document_upload', {
      'p_payload': input.toRpcJson(),
      'p_idempotency_key': normalizedKey,
    });
    try {
      return YorksWorkforceEvidenceUploadIntent.fromRpcJson(response);
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<YorksWorkforceEvidenceProjection> uploadEvidence(
    YorksWorkforceEvidenceUploadInput input, {
    required Uint8List bytes,
    required String idempotencyKey,
  }) async {
    final storage = _documentStorageClient;
    final finalizer = _documentFinalizerClient;
    if (!input.isValid ||
        bytes.isEmpty ||
        bytes.lengthInBytes != input.byteSize ||
        sha256.convert(bytes).toString() != input.sha256.toLowerCase()) {
      return _invalidInput();
    }
    if (storage == null || finalizer == null) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
    final intent = await prepareEvidenceUpload(
      input,
      idempotencyKey: idempotencyKey,
    );
    try {
      await storage.upload(
        bucketId: intent.bucketId,
        objectPath: intent.objectPath,
        bytes: bytes,
        mimeType: intent.mimeType,
      );
    } on StorageException catch (error) {
      if (!error.message.toLowerCase().contains('already exists')) {
        throw YorksV1DomainException(
          YorksV1DomainErrorCode.backendUnavailable,
          cause: error,
        );
      }
    } catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
        cause: error,
      );
    }
    try {
      await finalizer.finalize(intent.id);
    } on FunctionException catch (error) {
      throw YorksV1DomainException(
        error.status == 401 || error.status == 403
            ? YorksV1DomainErrorCode.unauthorized
            : YorksV1DomainErrorCode.conflict,
        cause: error,
      );
    } catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
        cause: error,
      );
    }
    return listEvidence(
      periodId: input.periodId,
      attendanceDayId: input.attendanceDayId,
      workerId: input.workerId,
    );
  }

  @override
  Future<YorksWorkforceMonthlyTeamProjection> listMonthlyTeams(
    YorksWorkforceMonthlyTeamFilters filters,
  ) async {
    if (!filters.isValid) return _invalidInput();
    final response = await _invoke(
      'v1_list_workforce_monthly_teams',
      filters.toRpcParameters(),
    );
    try {
      final projection = YorksWorkforceMonthlyTeamProjection.fromRpcJson(
        response,
      );
      final echoed = projection.filters;
      if (echoed.periodMonth != filters.periodMonth.trim() ||
          echoed.query != filters.query.trim() ||
          echoed.limit != filters.limit ||
          echoed.offset != filters.offset ||
          projection.teams.length > filters.limit ||
          (projection.teams.isNotEmpty &&
              filters.offset + projection.teams.length >
                  projection.totalCount) ||
          (filters.offset < projection.totalCount &&
              projection.teams.isEmpty)) {
        throw const FormatException('Monthly team context mismatch');
      }
      return projection;
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<YorksWorkforceMonthlyProjection> getMonthlyPeriod(
    YorksWorkforceMonthlyFilters filters,
  ) async {
    if (!filters.isValid) return _invalidInput();
    final response = await _invoke(
      'v1_get_workforce_monthly_period',
      filters.toRpcParameters(),
    );
    try {
      final projection = YorksWorkforceMonthlyProjection.fromRpcJson(response);
      final echoed = projection.filters;
      if (echoed.teamId != filters.teamId.trim() ||
          echoed.periodMonth != filters.periodMonth.trim() ||
          echoed.query != filters.query.trim() ||
          echoed.issueSeverity != filters.issueSeverity ||
          echoed.issueCode != _nullableTrimmed(filters.issueCode) ||
          echoed.workerLimit != filters.workerLimit ||
          echoed.workerOffset != filters.workerOffset ||
          projection.workers.length > filters.workerLimit ||
          (projection.workers.isNotEmpty &&
              filters.workerOffset + projection.workers.length >
                  projection.totalCount) ||
          (filters.workerOffset < projection.totalCount &&
              projection.workers.isEmpty)) {
        throw const FormatException('Monthly read context mismatch');
      }
      return projection;
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<YorksWorkforceMonthlyWorkerDetail> getMonthlyWorkerDetail({
    required String periodId,
    required String validationRunId,
    required String workerId,
  }) async {
    final normalizedPeriod = periodId.trim();
    final normalizedRun = validationRunId.trim();
    final normalizedWorker = workerId.trim();
    if (!_isUuid(normalizedPeriod) ||
        !_isUuid(normalizedRun) ||
        !_isUuid(normalizedWorker)) {
      return _invalidInput();
    }
    final response = await _invoke('v1_get_workforce_monthly_worker_detail', {
      'p_period_id': normalizedPeriod,
      'p_validation_run_id': normalizedRun,
      'p_worker_id': normalizedWorker,
    });
    try {
      final projection = YorksWorkforceMonthlyWorkerDetail.fromRpcJson(
        response,
      );
      if (projection.period.id != normalizedPeriod ||
          projection.validationRun.id != normalizedRun ||
          projection.worker.workerId != normalizedWorker) {
        throw const FormatException('Monthly detail context mismatch');
      }
      return projection;
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<YorksWorkforceMonthlyIssueProjection> listMonthlyIssues(
    YorksWorkforceMonthlyIssueFilters filters,
  ) async {
    if (!filters.isValid) return _invalidInput();
    final response = await _invoke(
      'v1_list_workforce_monthly_issues',
      filters.toRpcParameters(),
    );
    try {
      final projection = YorksWorkforceMonthlyIssueProjection.fromRpcJson(
        response,
      );
      final echoed = projection.filters;
      if (echoed.periodId != filters.periodId.trim() ||
          echoed.validationRunId != filters.validationRunId.trim() ||
          echoed.severity != filters.severity ||
          echoed.issueCode != _nullableTrimmed(filters.issueCode) ||
          echoed.workerId != _nullableTrimmed(filters.workerId) ||
          echoed.limit != filters.limit ||
          echoed.offset != filters.offset ||
          projection.issues.length > filters.limit ||
          (projection.issues.isNotEmpty &&
              filters.offset + projection.issues.length >
                  projection.totalCount) ||
          (filters.offset < projection.totalCount &&
              projection.issues.isEmpty)) {
        throw const FormatException('Monthly issue context mismatch');
      }
      return projection;
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<YorksWorkforceMonthlyValidationResult> validateMonthlyPeriod({
    required String teamId,
    required String periodMonth,
    required int? expectedPeriodVersion,
    required String idempotencyKey,
  }) async {
    final normalizedTeam = teamId.trim();
    final normalizedMonth = periodMonth.trim();
    final normalizedKey = idempotencyKey.trim();
    if (!_isUuid(normalizedTeam) ||
        !_isFirstOfMonth(normalizedMonth) ||
        (expectedPeriodVersion != null && expectedPeriodVersion < 1) ||
        !_isUuid(normalizedKey)) {
      return _invalidInput();
    }
    final response = await _invoke('v1_validate_workforce_monthly_period', {
      'p_payload': {'team_id': normalizedTeam, 'period_month': normalizedMonth},
      'p_expected_period_version': expectedPeriodVersion,
      'p_idempotency_key': normalizedKey,
    });
    try {
      final result = YorksWorkforceMonthlyValidationResult.fromRpcJson(
        response,
      );
      if (result.projection.filters.teamId != normalizedTeam ||
          result.projection.filters.periodMonth != normalizedMonth) {
        throw const FormatException('Monthly validation context mismatch');
      }
      return result;
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<YorksWorkforceReviewQueue> listMonthlyApprovalQueue({
    YorksWorkforceMonthlyPeriodStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    if (limit < 1 ||
        limit > yorksWorkforceReviewQueueMaxPageSize ||
        offset < 0) {
      return _invalidInput();
    }
    final response = await _invoke('v1_list_workforce_monthly_approval_queue', {
      'p_status': status?.wireValue,
      'p_limit': limit,
      'p_offset': offset,
    });
    try {
      final queue = YorksWorkforceReviewQueue.fromRpcJson(response);
      if (queue.statusFilter != status ||
          queue.limit != limit ||
          queue.offset != offset) {
        throw const FormatException('Review queue context mismatch');
      }
      return queue;
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<YorksWorkforceReviewLifecycle> getMonthlyLifecycle(
    String periodId,
  ) async {
    final normalized = periodId.trim();
    if (!_isUuid(normalized)) return _invalidInput();
    final response = await _invoke('v1_get_workforce_monthly_lifecycle', {
      'p_period_id': normalized,
    });
    return _decodeLifecycle(response, periodId: normalized);
  }

  @override
  Future<YorksWorkforceReviewLifecycle> submitMonthlyPeriod({
    required String periodId,
    required Iterable<String> warningIssueIds,
    required String reason,
    required int expectedVersion,
    required String idempotencyKey,
  }) {
    final warnings = warningIssueIds.map((value) => value.trim()).toList();
    if (warnings.any((value) => !_isUuid(value)) ||
        warnings.toSet().length != warnings.length) {
      return _invalidInput();
    }
    return _reviewCommand(
      'v1_submit_workforce_monthly_period',
      periodId: periodId,
      payload: {
        'period_id': periodId.trim(),
        'warning_issue_ids': warnings,
        'reason': reason.trim(),
      },
      expectedVersion: expectedVersion,
      idempotencyKey: idempotencyKey,
    );
  }

  @override
  Future<YorksWorkforceReviewLifecycle> returnMonthlyPeriod({
    required String periodId,
    required Iterable<YorksWorkforceAffectedEntry> affectedEntries,
    required String reason,
    String? attachmentReference,
    required int expectedVersion,
    required String idempotencyKey,
  }) => _affectedEntryCommand(
    'v1_return_workforce_monthly_period',
    periodId: periodId,
    affectedEntries: affectedEntries,
    reason: reason,
    attachmentReference: attachmentReference,
    expectedVersion: expectedVersion,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<YorksWorkforceReviewLifecycle> correctMonthlyEntryDuringReview({
    required String periodId,
    required String workDate,
    required YorksWorkforceDailyRosterSaveRow row,
    required String reason,
    required int expectedVersion,
    required String idempotencyKey,
  }) {
    if (!_isIsoDate(workDate.trim()) || !row.isValid) return _invalidInput();
    return _reviewCommand(
      'v1_correct_workforce_monthly_entry_during_review',
      periodId: periodId,
      payload: {
        'period_id': periodId.trim(),
        'row': {...row.toRpcJson(), 'work_date': workDate.trim()},
        'reason': reason.trim(),
      },
      expectedVersion: expectedVersion,
      idempotencyKey: idempotencyKey,
    );
  }

  @override
  Future<YorksWorkforceReviewLifecycle> verifyMonthlyPeriod({
    required String periodId,
    required String reason,
    required int expectedVersion,
    required String idempotencyKey,
  }) => _simpleReviewCommand(
    'v1_verify_workforce_monthly_period',
    periodId: periodId,
    reason: reason,
    expectedVersion: expectedVersion,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<YorksWorkforceReviewLifecycle> approveAndLockMonthlyPeriod({
    required String periodId,
    required String reason,
    required int expectedVersion,
    required String idempotencyKey,
  }) => _simpleReviewCommand(
    'v1_approve_lock_workforce_monthly_period',
    periodId: periodId,
    reason: reason,
    expectedVersion: expectedVersion,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<YorksWorkforceReviewLifecycle> requestMonthlyReopen({
    required String periodId,
    required Iterable<YorksWorkforceAffectedEntry> affectedEntries,
    required String reason,
    String? attachmentReference,
    required int expectedVersion,
    required String idempotencyKey,
  }) => _affectedEntryCommand(
    'v1_request_workforce_monthly_reopen',
    periodId: periodId,
    affectedEntries: affectedEntries,
    reason: reason,
    attachmentReference: attachmentReference,
    expectedVersion: expectedVersion,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<YorksWorkforceReviewLifecycle> authorizeMonthlyReopen({
    required String periodId,
    required String requestId,
    required String reason,
    required int expectedVersion,
    required String idempotencyKey,
  }) {
    if (!_isUuid(requestId.trim())) return _invalidInput();
    return _reviewCommand(
      'v1_authorize_workforce_monthly_reopen',
      periodId: periodId,
      payload: {
        'period_id': periodId.trim(),
        'request_id': requestId.trim(),
        'reason': reason.trim(),
      },
      expectedVersion: expectedVersion,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<YorksWorkforceReviewLifecycle> _simpleReviewCommand(
    String functionName, {
    required String periodId,
    required String reason,
    required int expectedVersion,
    required String idempotencyKey,
  }) => _reviewCommand(
    functionName,
    periodId: periodId,
    payload: {'period_id': periodId.trim(), 'reason': reason.trim()},
    expectedVersion: expectedVersion,
    idempotencyKey: idempotencyKey,
  );

  Future<YorksWorkforceReviewLifecycle> _affectedEntryCommand(
    String functionName, {
    required String periodId,
    required Iterable<YorksWorkforceAffectedEntry> affectedEntries,
    required String reason,
    required String? attachmentReference,
    required int expectedVersion,
    required String idempotencyKey,
  }) {
    final entries = affectedEntries.toList();
    final identities = entries
        .map((entry) => '${entry.workerId.trim()}:${entry.workDate.trim()}')
        .toSet();
    if (entries.isEmpty ||
        entries.length > 500 ||
        entries.any((entry) => !entry.isValid) ||
        identities.length != entries.length ||
        (attachmentReference?.trim().length ?? 0) > 500) {
      return _invalidInput();
    }
    return _reviewCommand(
      functionName,
      periodId: periodId,
      payload: {
        'period_id': periodId.trim(),
        'reason': reason.trim(),
        'affected_entries': entries
            .map((entry) => entry.toRpcJson())
            .toList(growable: false),
        if (_nullableTrimmed(attachmentReference) != null)
          'attachment_reference': attachmentReference!.trim(),
      },
      expectedVersion: expectedVersion,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<YorksWorkforceReviewLifecycle> _reviewCommand(
    String functionName, {
    required String periodId,
    required Map<String, Object?> payload,
    required int expectedVersion,
    required String idempotencyKey,
  }) async {
    final normalizedPeriod = periodId.trim();
    final normalizedReason = (payload['reason'] as String?)?.trim() ?? '';
    final normalizedKey = idempotencyKey.trim();
    if (!_isUuid(normalizedPeriod) ||
        normalizedReason.isEmpty ||
        normalizedReason.length > 2000 ||
        expectedVersion < 1 ||
        !_isUuid(normalizedKey)) {
      return _invalidInput();
    }
    final response = await _invoke(functionName, {
      'p_payload': payload,
      'p_expected_period_version': expectedVersion,
      'p_idempotency_key': normalizedKey,
    });
    return _decodeLifecycle(response, periodId: normalizedPeriod);
  }

  YorksWorkforceReviewLifecycle _decodeLifecycle(
    Map<String, dynamic> response, {
    required String periodId,
  }) {
    try {
      final lifecycle = YorksWorkforceReviewLifecycle.fromRpcJson(response);
      if (lifecycle.periodId != periodId) {
        throw const FormatException('Lifecycle period mismatch');
      }
      return lifecycle;
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<YorksWorkforceDailyRosterProjection> getDailyRoster({
    required String workDate,
    YorksWorkforceRosterFilters filters = const YorksWorkforceRosterFilters(),
  }) async {
    final normalizedDate = workDate.trim();
    if (!_isIsoDate(normalizedDate) || !filters.isValid) {
      return _invalidInput();
    }
    final response = await _invoke(
      'v1_get_workforce_daily_roster',
      filters.toRpcParameters(normalizedDate),
    );
    try {
      final projection = YorksWorkforceDailyRosterProjection.fromRpcJson(
        response,
      );
      if (!_rosterResponseMatchesRequest(projection, normalizedDate, filters)) {
        throw const FormatException('Roster read context mismatch');
      }
      return projection;
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<YorksWorkforceDailyRosterSaveResult> saveDailyRoster({
    required String workDate,
    required List<YorksWorkforceDailyRosterSaveRow> rows,
    required String reason,
    required String idempotencyKey,
  }) async {
    final normalizedDate = workDate.trim();
    final normalizedReason = reason.trim();
    final normalizedKey = idempotencyKey.trim();
    final workerIds = rows.map((row) => row.workerId.trim()).toList();
    if (!_isIsoDate(normalizedDate) ||
        rows.isEmpty ||
        rows.length > yorksWorkforceRosterMaxCommandRows ||
        rows.any((row) => !row.isValid) ||
        workerIds.toSet().length != workerIds.length ||
        normalizedReason.isEmpty ||
        normalizedReason.length > 2000 ||
        !_isUuid(normalizedKey)) {
      return _invalidInput();
    }
    final response = await _invoke('v1_save_workforce_daily_roster', {
      'p_work_date': normalizedDate,
      'p_rows': rows.map((row) => row.toRpcJson()).toList(growable: false),
      'p_reason': normalizedReason,
      'p_idempotency_key': normalizedKey,
    });
    try {
      final result = YorksWorkforceDailyRosterSaveResult.fromRpcJson(response);
      if (result.workDate != normalizedDate ||
          result.rows
              .map((row) => row.workerId)
              .toSet()
              .difference(workerIds.toSet())
              .isNotEmpty ||
          result.rowCount != rows.length) {
        throw const FormatException('Roster save context mismatch');
      }
      return result;
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<YorksWorkforceTimesheetProjection> getTimesheetAllocations({
    required String workDate,
    String? workerId,
  }) async {
    final normalizedDate = workDate.trim();
    final normalizedWorkerId = _nullableTrimmed(workerId);
    if (!_isIsoDate(normalizedDate) ||
        (normalizedWorkerId != null && !_isUuid(normalizedWorkerId))) {
      return _invalidInput();
    }
    final response = await _invoke('v1_get_workforce_timesheet_allocations', {
      'p_work_date': normalizedDate,
      'p_worker_id': normalizedWorkerId,
    });
    try {
      return YorksWorkforceTimesheetProjection.fromRpcJson(response);
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<YorksWorkforceAttendanceProjection> getAttendance({
    required String workDate,
    String? workerId,
  }) async {
    final normalizedDate = workDate.trim();
    final normalizedWorkerId = _nullableTrimmed(workerId);
    if (!_isIsoDate(normalizedDate) ||
        (normalizedWorkerId != null && !_isUuid(normalizedWorkerId))) {
      return _invalidInput();
    }
    final response = await _invoke('v1_get_workforce_attendance', {
      'p_work_date': normalizedDate,
      'p_worker_id': normalizedWorkerId,
    });
    try {
      return YorksWorkforceAttendanceProjection.fromRpcJson(response);
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<YorksWorkforceConfigurationProjection> getConfiguration({
    String? onDate,
  }) async {
    final normalizedDate = onDate?.trim();
    if (normalizedDate != null &&
        (normalizedDate.isEmpty || !_isIsoDate(normalizedDate))) {
      return _invalidInput();
    }
    final parameters = <String, Object?>{};
    if (normalizedDate != null) parameters['p_on_date'] = normalizedDate;
    final response = await _invoke(
      'v1_get_workforce_configuration',
      parameters,
    );
    try {
      return YorksWorkforceConfigurationProjection.fromRpcJson(response);
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<YorksWorkforceAdministrationOptions> getAdministrationOptions({
    String? onDate,
  }) async {
    final normalizedDate = onDate?.trim();
    if (normalizedDate != null &&
        (normalizedDate.isEmpty || !_isIsoDate(normalizedDate))) {
      return _invalidInput();
    }
    final parameters = <String, Object?>{};
    if (normalizedDate != null) parameters['p_on_date'] = normalizedDate;
    final response = await _invoke(
      'v1_get_workforce_administration_options',
      parameters,
    );
    try {
      return YorksWorkforceAdministrationOptions.fromRpcJson(response);
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<YorksWorkforceFoundationProjection> getFoundation({
    String? query,
    YorksWorkforceWorkerStatus? status,
    int limit = 50,
    int offset = 0,
    String? onDate,
  }) async {
    if (limit < 1 || limit > 100 || offset < 0) return _invalidInput();
    final normalizedDate = onDate?.trim();
    if (normalizedDate != null &&
        (normalizedDate.isEmpty || DateTime.tryParse(normalizedDate) == null)) {
      return _invalidInput();
    }
    final parameters = <String, Object?>{
      'p_query': _nullableTrimmed(query),
      'p_status': status?.wireValue,
      'p_limit': limit,
      'p_offset': offset,
    };
    if (normalizedDate != null) parameters['p_on_date'] = normalizedDate;
    final response = await _invoke('v1_get_workforce_foundation', parameters);
    try {
      return YorksWorkforceFoundationProjection.fromRpcJson(response);
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<YorksWorkforceCommandResult> saveTrade(
    Map<String, Object?> payload, {
    int? expectedVersion,
    required String idempotencyKey,
  }) => _save(
    'v1_save_workforce_trade',
    payload,
    expectedVersion: expectedVersion,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<YorksWorkforceCommandResult> saveInternalLocation(
    Map<String, Object?> payload, {
    int? expectedVersion,
    required String idempotencyKey,
  }) => _save(
    'v1_save_workforce_internal_location',
    payload,
    expectedVersion: expectedVersion,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<YorksWorkforceCommandResult> saveWorker(
    Map<String, Object?> payload, {
    int? expectedVersion,
    required String idempotencyKey,
  }) => _save(
    'v1_save_workforce_worker',
    payload,
    expectedVersion: expectedVersion,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<YorksWorkforceCommandResult> saveTeam(
    Map<String, Object?> payload, {
    int? expectedVersion,
    required String idempotencyKey,
  }) => _save(
    'v1_save_workforce_team',
    payload,
    expectedVersion: expectedVersion,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<YorksWorkforceCommandResult> saveWorkerAssignment(
    Map<String, Object?> payload, {
    int? expectedVersion,
    required String idempotencyKey,
  }) => _save(
    'v1_save_workforce_worker_assignment',
    payload,
    expectedVersion: expectedVersion,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<YorksWorkforceCommandResult> transferWorkerAssignment(
    Map<String, Object?> payload, {
    String? expectedCurrentAssignmentId,
    int? expectedCurrentVersion,
    required String idempotencyKey,
  }) async {
    final normalizedKey = idempotencyKey.trim();
    final normalizedAssignmentId = _nullableTrimmed(
      expectedCurrentAssignmentId,
    );
    if (!_isUuid(normalizedKey) ||
        (normalizedAssignmentId != null && !_isUuid(normalizedAssignmentId)) ||
        (normalizedAssignmentId == null) != (expectedCurrentVersion == null) ||
        (expectedCurrentVersion != null && expectedCurrentVersion < 1)) {
      return _invalidInput();
    }
    final response = await _invoke('v1_transfer_workforce_worker_assignment', {
      'p_payload': payload,
      'p_expected_current_assignment_id': normalizedAssignmentId,
      'p_expected_current_version': expectedCurrentVersion,
      'p_idempotency_key': normalizedKey,
    });
    try {
      return YorksWorkforceCommandResult.fromRpcJson(response);
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<YorksWorkforceCommandResult> saveResponsibilityAssignment(
    Map<String, Object?> payload, {
    int? expectedVersion,
    required String idempotencyKey,
  }) => _save(
    'v1_save_workforce_responsibility_assignment',
    payload,
    expectedVersion: expectedVersion,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<YorksWorkforceCommandResult> saveCalendar(
    Map<String, Object?> payload, {
    int? expectedVersion,
    required String idempotencyKey,
  }) => _save(
    'v1_save_workforce_calendar',
    payload,
    expectedVersion: expectedVersion,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<YorksWorkforceCommandResult> saveCalendarDate(
    Map<String, Object?> payload, {
    int? expectedVersion,
    required String idempotencyKey,
  }) => _save(
    'v1_save_workforce_calendar_date',
    payload,
    expectedVersion: expectedVersion,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<YorksWorkforceCommandResult> saveShiftTemplate(
    Map<String, Object?> payload, {
    int? expectedVersion,
    required String idempotencyKey,
  }) => _save(
    'v1_save_workforce_shift_template',
    payload,
    expectedVersion: expectedVersion,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<YorksWorkforceCommandResult> saveTeamSchedule(
    Map<String, Object?> payload, {
    int? expectedVersion,
    required String idempotencyKey,
  }) => _save(
    'v1_save_workforce_team_schedule',
    payload,
    expectedVersion: expectedVersion,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<YorksWorkforceCommandResult> saveAttendanceDay(
    YorksWorkforceAttendanceInput input, {
    int? expectedVersion,
    required String idempotencyKey,
  }) async {
    final normalizedKey = idempotencyKey.trim();
    if (!input.isValid || !_isUuid(normalizedKey)) return _invalidInput();
    return _save(
      'v1_save_workforce_attendance_day',
      input.toRpcJson(),
      expectedVersion: expectedVersion,
      idempotencyKey: normalizedKey,
    );
  }

  @override
  Future<YorksWorkforceTimesheetCommandResult> saveTimesheetAllocations(
    YorksWorkforceTimesheetAllocationInput input, {
    int? expectedVersion,
    required String idempotencyKey,
  }) async {
    final normalizedKey = idempotencyKey.trim();
    if (!input.isValid ||
        !_isUuid(normalizedKey) ||
        (expectedVersion != null && expectedVersion < 1)) {
      return _invalidInput();
    }
    final response = await _invoke('v1_save_workforce_timesheet_allocations', {
      'p_payload': input.toRpcJson(),
      'p_expected_version': expectedVersion,
      'p_idempotency_key': normalizedKey,
    });
    return _decodeTimesheetCommand(response);
  }

  @override
  Future<YorksWorkforceTimesheetCommandResult> withdrawTimesheetAllocations({
    required String attendanceDayId,
    required String reason,
    required int expectedVersion,
    required String idempotencyKey,
  }) async {
    final normalizedAttendanceId = attendanceDayId.trim();
    final normalizedReason = reason.trim();
    final normalizedKey = idempotencyKey.trim();
    if (!_isUuid(normalizedAttendanceId) ||
        normalizedReason.isEmpty ||
        normalizedReason.length > 2000 ||
        expectedVersion < 1 ||
        !_isUuid(normalizedKey)) {
      return _invalidInput();
    }
    final response =
        await _invoke('v1_withdraw_workforce_timesheet_allocations', {
          'p_attendance_day_id': normalizedAttendanceId,
          'p_reason': normalizedReason,
          'p_expected_version': expectedVersion,
          'p_idempotency_key': normalizedKey,
        });
    return _decodeTimesheetCommand(response);
  }

  YorksWorkforceTimesheetCommandResult _decodeTimesheetCommand(
    Map<String, dynamic> response,
  ) {
    try {
      return YorksWorkforceTimesheetCommandResult.fromRpcJson(response);
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  Future<YorksWorkforceCommandResult> _save(
    String functionName,
    Map<String, Object?> payload, {
    int? expectedVersion,
    required String idempotencyKey,
  }) async {
    if ((expectedVersion != null && expectedVersion < 1) ||
        idempotencyKey.trim().isEmpty) {
      return _invalidInput();
    }
    final response = await _invoke(functionName, {
      'p_payload': payload,
      'p_expected_version': expectedVersion,
      'p_idempotency_key': idempotencyKey.trim(),
    });
    try {
      return YorksWorkforceCommandResult.fromRpcJson(response);
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  Future<Map<String, dynamic>> _invoke(
    String functionName,
    Map<String, Object?> parameters,
  ) async {
    if (!_featureFlags.workforce) {
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
      final message = [
        error.message,
        error.details?.toString(),
        error.hint?.toString(),
      ].whereType<String>().join(' ').toUpperCase();
      final code = switch (error.code) {
        'PGRST301' ||
        'PGRST302' ||
        'PGRST303' ||
        '28000' => YorksV1DomainErrorCode.unauthenticated,
        '42501' => YorksV1DomainErrorCode.unauthorized,
        '40001' => YorksV1DomainErrorCode.conflict,
        '22023' || '22P02' =>
          message.contains('IDEMPOTENCY_KEY_REUSED')
              ? YorksV1DomainErrorCode.conflict
              : YorksV1DomainErrorCode.invalidInput,
        'PGRST002' || 'PGRST003' => YorksV1DomainErrorCode.backendUnavailable,
        _ when message.contains('STALE_VERSION') =>
          YorksV1DomainErrorCode.conflict,
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

bool _rosterResponseMatchesRequest(
  YorksWorkforceDailyRosterProjection projection,
  String workDate,
  YorksWorkforceRosterFilters requested,
) {
  final echoed = projection.filters;
  final rows = projection.rows;
  if (projection.workDate != workDate ||
      echoed.teamId != _nullableTrimmed(requested.teamId) ||
      echoed.projectId != _nullableTrimmed(requested.projectId) ||
      echoed.projectScopeId != _nullableTrimmed(requested.projectScopeId) ||
      echoed.internalLocationId !=
          _nullableTrimmed(requested.internalLocationId) ||
      echoed.query != (requested.query.trim()) ||
      echoed.limit != requested.limit ||
      echoed.offset != requested.offset ||
      rows.length > requested.limit ||
      (rows.isNotEmpty &&
          requested.offset + rows.length > projection.totalCount) ||
      (requested.offset < projection.totalCount && rows.isEmpty)) {
    return false;
  }
  for (final row in rows) {
    final assignment = row.assignment;
    if ((requested.teamId != null &&
            assignment.teamId != _nullableTrimmed(requested.teamId)) ||
        (requested.projectId != null &&
            assignment.projectId != _nullableTrimmed(requested.projectId)) ||
        (requested.projectScopeId != null &&
            assignment.projectScopeId !=
                _nullableTrimmed(requested.projectScopeId)) ||
        (requested.internalLocationId != null &&
            assignment.internalLocationId !=
                _nullableTrimmed(requested.internalLocationId))) {
      return false;
    }
  }
  return true;
}

String? _nullableTrimmed(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

bool _isIsoDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return false;
  final normalized = [
    parsed.year.toString().padLeft(4, '0'),
    parsed.month.toString().padLeft(2, '0'),
    parsed.day.toString().padLeft(2, '0'),
  ].join('-');
  return normalized == value;
}

bool _isFirstOfMonth(String value) =>
    _isIsoDate(value) && value.endsWith('-01');

bool _isUuid(String value) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
).hasMatch(value);

Never _invalidInput() =>
    throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);

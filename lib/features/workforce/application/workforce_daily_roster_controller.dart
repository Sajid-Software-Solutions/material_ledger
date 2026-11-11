import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/yorks_v1_domain_error.dart';
import '../../../shared/services/yorks_v1_critical_command_key_store.dart';
import '../../../shared/sync/connectivity_service.dart';
import '../data/workforce_repository.dart';
import '../domain/workforce_attendance_models.dart';
import '../domain/workforce_daily_roster_models.dart';
import '../domain/workforce_timesheet_models.dart';

enum YorksWorkforceDailyRosterStatus {
  idle,
  loading,
  ready,
  reviewing,
  saving,
  saved,
  offline,
  conflict,
  uncertain,
  forbidden,
  sessionExpired,
  unavailable,
  failure,
}

enum YorksWorkforceRosterDraftSource {
  committed,
  empty,
  manual,
  scheduleStandard,
  previousDay,
}

final class YorksWorkforceDailyRosterDraftRow {
  const YorksWorkforceDailyRosterDraftRow({
    required this.source,
    required this.status,
    required this.regularMinutes,
    required this.overtimeMinutes,
    required this.overtimeReason,
    required this.reason,
    required this.draftSource,
    required this.originalStatus,
    required this.originalRegularMinutes,
    required this.originalOvertimeMinutes,
    required this.originalOvertimeReason,
    required this.expectedAttendanceVersion,
    required this.expectedAllocationVersion,
    required this.allocations,
    required this.originalAllocationFingerprint,
    required this.originalAllocationWasActive,
  });

  factory YorksWorkforceDailyRosterDraftRow.fromProjection(
    YorksWorkforceDailyRosterRow row,
  ) {
    final attendance = row.attendance;
    final allocations = _allocationInputs(row.allocationSet);
    return YorksWorkforceDailyRosterDraftRow(
      source: row,
      status: attendance?.status ?? YorksWorkforceAttendanceStatus.notEntered,
      regularMinutes: attendance?.regularMinutes ?? 0,
      overtimeMinutes: attendance?.overtimeMinutes ?? 0,
      overtimeReason: attendance?.overtimeReason,
      reason: attendance?.reason ?? _rowEditReason,
      draftSource: attendance == null
          ? YorksWorkforceRosterDraftSource.empty
          : YorksWorkforceRosterDraftSource.committed,
      originalStatus:
          attendance?.status ?? YorksWorkforceAttendanceStatus.notEntered,
      originalRegularMinutes: attendance?.regularMinutes ?? 0,
      originalOvertimeMinutes: attendance?.overtimeMinutes ?? 0,
      originalOvertimeReason: attendance?.overtimeReason,
      expectedAttendanceVersion: attendance?.recordVersion,
      expectedAllocationVersion: row.allocationSet?.recordVersion,
      allocations: allocations,
      originalAllocationFingerprint: _allocationFingerprint(allocations),
      originalAllocationWasActive: row.allocationSet?.state == 'active',
    );
  }

  final YorksWorkforceDailyRosterRow source;
  final YorksWorkforceAttendanceStatus status;
  final int regularMinutes;
  final int overtimeMinutes;
  final String? overtimeReason;
  final String reason;
  final YorksWorkforceRosterDraftSource draftSource;
  final YorksWorkforceAttendanceStatus originalStatus;
  final int originalRegularMinutes;
  final int originalOvertimeMinutes;
  final String? originalOvertimeReason;
  final int? expectedAttendanceVersion;
  final int? expectedAllocationVersion;
  final List<YorksWorkforceAllocationInput> allocations;
  final String originalAllocationFingerprint;
  final bool originalAllocationWasActive;

  String get workerId => source.workerId;
  bool get isEditable =>
      source.canMaintainAttendance &&
      (!source.hasActiveAllocationLock ||
          (source.canMaintainTimesheet && !source.allocationDetailsRestricted));
  bool get canEditAttendanceEvidence => source.canMaintainAttendance;
  bool get isAllocationEditable =>
      source.canMaintainTimesheet && !source.allocationDetailsRestricted;
  bool get wasCommitted => expectedAttendanceVersion != null;
  bool get isDirty =>
      status != originalStatus ||
      regularMinutes != originalRegularMinutes ||
      overtimeMinutes != originalOvertimeMinutes ||
      _normalized(overtimeReason) != _normalized(originalOvertimeReason) ||
      allocationsDirty;
  bool get allocationsDirty =>
      _allocationFingerprint(allocations) != originalAllocationFingerprint;
  bool get attendanceAllocationBasisChanged =>
      status != originalStatus ||
      regularMinutes != originalRegularMinutes ||
      overtimeMinutes != originalOvertimeMinutes;

  bool get isValid {
    final total = regularMinutes + overtimeMinutes;
    final allocationRegular = allocations.fold<int>(
      0,
      (sum, row) => sum + row.regularMinutes,
    );
    final allocationOvertime = allocations.fold<int>(
      0,
      (sum, row) => sum + row.overtimeMinutes,
    );
    final validAllocations =
        allocations.isEmpty ||
        (status == YorksWorkforceAttendanceStatus.present &&
            allocations.every((row) => row.isValid) &&
            allocationRegular == regularMinutes &&
            allocationOvertime == overtimeMinutes);
    return regularMinutes >= 0 &&
        overtimeMinutes >= 0 &&
        total <= 1440 &&
        (status == YorksWorkforceAttendanceStatus.present
            ? total > 0
            : total == 0) &&
        (_normalized(overtimeReason)?.length ?? 0) <= 2000 &&
        validAllocations &&
        reason.trim().isNotEmpty &&
        reason.trim().length <= 2000;
  }

  YorksWorkforceDailyRosterDraftRow copyWith({
    YorksWorkforceDailyRosterRow? source,
    YorksWorkforceAttendanceStatus? status,
    int? regularMinutes,
    int? overtimeMinutes,
    String? overtimeReason,
    bool clearOvertimeReason = false,
    String? reason,
    YorksWorkforceRosterDraftSource? draftSource,
    YorksWorkforceAttendanceStatus? originalStatus,
    int? originalRegularMinutes,
    int? originalOvertimeMinutes,
    String? originalOvertimeReason,
    bool clearOriginalOvertimeReason = false,
    int? expectedAttendanceVersion,
    int? expectedAllocationVersion,
    List<YorksWorkforceAllocationInput>? allocations,
    String? originalAllocationFingerprint,
    bool? originalAllocationWasActive,
  }) => YorksWorkforceDailyRosterDraftRow(
    source: source ?? this.source,
    status: status ?? this.status,
    regularMinutes: regularMinutes ?? this.regularMinutes,
    overtimeMinutes: overtimeMinutes ?? this.overtimeMinutes,
    overtimeReason: clearOvertimeReason
        ? null
        : overtimeReason ?? this.overtimeReason,
    reason: reason ?? this.reason,
    draftSource: draftSource ?? this.draftSource,
    originalStatus: originalStatus ?? this.originalStatus,
    originalRegularMinutes:
        originalRegularMinutes ?? this.originalRegularMinutes,
    originalOvertimeMinutes:
        originalOvertimeMinutes ?? this.originalOvertimeMinutes,
    originalOvertimeReason: clearOriginalOvertimeReason
        ? null
        : originalOvertimeReason ?? this.originalOvertimeReason,
    expectedAttendanceVersion:
        expectedAttendanceVersion ?? this.expectedAttendanceVersion,
    expectedAllocationVersion:
        expectedAllocationVersion ?? this.expectedAllocationVersion,
    allocations: List.unmodifiable(allocations ?? this.allocations),
    originalAllocationFingerprint:
        originalAllocationFingerprint ?? this.originalAllocationFingerprint,
    originalAllocationWasActive:
        originalAllocationWasActive ?? this.originalAllocationWasActive,
  );

  YorksWorkforceDailyRosterDraftRow withSaved(
    YorksWorkforceDailyRosterSaveResultRow result,
  ) {
    final savedAllocations = _allocationInputs(result.allocationSet);
    return copyWith(
      status: result.attendance.status,
      regularMinutes: result.attendance.regularMinutes,
      overtimeMinutes: result.attendance.overtimeMinutes,
      overtimeReason: result.attendance.overtimeReason,
      clearOvertimeReason: result.attendance.overtimeReason == null,
      originalStatus: result.attendance.status,
      originalRegularMinutes: result.attendance.regularMinutes,
      originalOvertimeMinutes: result.attendance.overtimeMinutes,
      originalOvertimeReason: result.attendance.overtimeReason,
      clearOriginalOvertimeReason: result.attendance.overtimeReason == null,
      expectedAttendanceVersion: result.attendanceRecordVersion,
      expectedAllocationVersion: result.allocationSetRecordVersion,
      allocations: savedAllocations,
      originalAllocationFingerprint: _allocationFingerprint(savedAllocations),
      originalAllocationWasActive:
          result.allocationState == 'active' ||
          (result.allocationState == null && source.hasActiveAllocationLock),
      draftSource: YorksWorkforceRosterDraftSource.committed,
    );
  }

  YorksWorkforceDailyRosterSaveRow toSaveRow() {
    final action =
        allocationsDirty ||
            (originalAllocationWasActive && attendanceAllocationBasisChanged)
        ? allocations.isEmpty
              ? YorksWorkforceRosterAllocationAction.withdraw
              : YorksWorkforceRosterAllocationAction.replace
        : YorksWorkforceRosterAllocationAction.preserve;
    return YorksWorkforceDailyRosterSaveRow(
      workerId: workerId,
      expectedAttendanceVersion: expectedAttendanceVersion,
      status: status,
      regularMinutes: regularMinutes,
      overtimeMinutes: overtimeMinutes,
      overtimeReason: _normalized(overtimeReason),
      reason: reason,
      allocationAction: action,
      expectedAllocationVersion: expectedAllocationVersion,
      allocations: action == YorksWorkforceRosterAllocationAction.replace
          ? allocations
          : null,
    );
  }
}

final class YorksWorkforceDailyRosterState {
  YorksWorkforceDailyRosterState({
    this.status = YorksWorkforceDailyRosterStatus.idle,
    this.workDate = '',
    this.filters = const YorksWorkforceRosterFilters(),
    this.projection,
    Iterable<YorksWorkforceDailyRosterDraftRow> rows = const [],
    Set<String> selectedWorkerIds = const {},
    this.error,
    this.lastSavedAt,
    this.isOnline = true,
  }) : rows = List.unmodifiable(rows),
       selectedWorkerIds = Set.unmodifiable(selectedWorkerIds);

  final YorksWorkforceDailyRosterStatus status;
  final String workDate;
  final YorksWorkforceRosterFilters filters;
  final YorksWorkforceDailyRosterProjection? projection;
  final List<YorksWorkforceDailyRosterDraftRow> rows;
  final Set<String> selectedWorkerIds;
  final YorksV1DomainException? error;
  final String? lastSavedAt;
  final bool isOnline;

  bool get isReviewing => status == YorksWorkforceDailyRosterStatus.reviewing;
  bool get isBusy =>
      status == YorksWorkforceDailyRosterStatus.loading ||
      status == YorksWorkforceDailyRosterStatus.saving;
  List<YorksWorkforceDailyRosterDraftRow> get dirtyRows =>
      rows.where((row) => row.isDirty).toList(growable: false);
  Set<String> get invalidWorkerIds =>
      dirtyRows.where((row) => !row.isValid).map((row) => row.workerId).toSet();
  bool get canLoadMore =>
      projection != null && rows.length < projection!.totalCount;

  YorksWorkforceDailyRosterState copyWith({
    YorksWorkforceDailyRosterStatus? status,
    String? workDate,
    YorksWorkforceRosterFilters? filters,
    YorksWorkforceDailyRosterProjection? projection,
    Iterable<YorksWorkforceDailyRosterDraftRow>? rows,
    Set<String>? selectedWorkerIds,
    YorksV1DomainException? error,
    String? lastSavedAt,
    bool? isOnline,
    bool clearProjection = false,
    bool clearError = false,
    bool clearLastSaved = false,
  }) => YorksWorkforceDailyRosterState(
    status: status ?? this.status,
    workDate: workDate ?? this.workDate,
    filters: filters ?? this.filters,
    projection: clearProjection ? null : projection ?? this.projection,
    rows: rows ?? this.rows,
    selectedWorkerIds: selectedWorkerIds ?? this.selectedWorkerIds,
    error: clearError ? null : error ?? this.error,
    lastSavedAt: clearLastSaved ? null : lastSavedAt ?? this.lastSavedAt,
    isOnline: isOnline ?? this.isOnline,
  );
}

final class YorksWorkforceDailyRosterController
    extends StateNotifier<YorksWorkforceDailyRosterState> {
  YorksWorkforceDailyRosterController({
    required YorksWorkforceRepository repository,
    required YorksV1CriticalCommandKeyStore commandKeys,
    required ConnectivityService connectivity,
    DateTime Function()? clock,
  }) : _repository = repository,
       _commandKeys = commandKeys,
       _connectivity = connectivity,
       _clock = clock ?? DateTime.now,
       super(
         YorksWorkforceDailyRosterState(
           workDate: _isoDate((clock ?? DateTime.now)()),
           isOnline: connectivity.isOnline,
         ),
       ) {
    _connectivitySubscription = _connectivity.onChange.listen(
      _onConnectivityChanged,
    );
  }

  static const operation = 'save_workforce_daily_roster';
  final YorksWorkforceRepository _repository;
  final YorksV1CriticalCommandKeyStore _commandKeys;
  final ConnectivityService _connectivity;
  final DateTime Function() _clock;
  StreamSubscription<bool>? _connectivitySubscription;
  int _generation = 0;
  final Map<String, YorksWorkforceDailyRosterDraftRow> _retainedDrafts = {};

  Future<bool> load({
    String? workDate,
    YorksWorkforceRosterFilters? filters,
    bool preserveDrafts = false,
  }) async {
    final generation = ++_generation;
    final nextDate = workDate ?? state.workDate;
    final nextFilters = filters ?? state.filters;
    final dateChanged = nextDate != state.workDate;
    if (dateChanged || !preserveDrafts) {
      _retainedDrafts.clear();
    } else {
      for (final row in state.dirtyRows) {
        _retainedDrafts[row.workerId] = row;
      }
    }
    if (!_connectivity.isOnline) {
      state = state.copyWith(
        status: YorksWorkforceDailyRosterStatus.offline,
        workDate: nextDate,
        filters: nextFilters,
        rows: dateChanged
            ? const <YorksWorkforceDailyRosterDraftRow>[]
            : state.rows,
        isOnline: false,
        clearProjection: dateChanged,
      );
      return false;
    }
    state = state.copyWith(
      status: YorksWorkforceDailyRosterStatus.loading,
      workDate: nextDate,
      filters: nextFilters,
      rows: dateChanged
          ? const <YorksWorkforceDailyRosterDraftRow>[]
          : state.rows,
      isOnline: true,
      clearError: true,
      clearProjection: dateChanged,
    );
    try {
      final projection = await _repository.getDailyRoster(
        workDate: nextDate,
        filters: nextFilters,
      );
      if (generation != _generation) return false;
      final rows = projection.rows
          .map((row) {
            final retained = _retainedDrafts[row.workerId];
            final next = retained != null && _canRebase(retained, row)
                ? retained.copyWith(source: row)
                : YorksWorkforceDailyRosterDraftRow.fromProjection(row);
            if (next.isDirty) {
              _retainedDrafts[row.workerId] = next;
            } else {
              _retainedDrafts.remove(row.workerId);
            }
            return next;
          })
          .toList(growable: false);
      state = YorksWorkforceDailyRosterState(
        status: YorksWorkforceDailyRosterStatus.ready,
        workDate: projection.workDate,
        filters: nextFilters,
        projection: projection,
        rows: rows,
        isOnline: true,
      );
      return true;
    } on YorksV1DomainException catch (error) {
      if (generation == _generation) _setFailure(error, command: false);
      return false;
    } catch (error) {
      if (generation == _generation) {
        _setFailure(
          YorksV1DomainException(
            YorksV1DomainErrorCode.backendUnavailable,
            cause: error,
          ),
          command: false,
        );
      }
      return false;
    }
  }

  Future<bool> loadMore() async {
    final projection = state.projection;
    if (projection == null || !state.canLoadMore || state.isBusy) return false;
    final generation = ++_generation;
    final filters = state.filters.copyWith(offset: state.rows.length);
    try {
      final next = await _repository.getDailyRoster(
        workDate: state.workDate,
        filters: filters,
      );
      if (generation != _generation) return false;
      final known = state.rows.map((row) => row.workerId).toSet();
      final appended = next.rows.where((row) => known.add(row.workerId)).map((
        row,
      ) {
        final retained = _retainedDrafts[row.workerId];
        return retained != null && _canRebase(retained, row)
            ? retained.copyWith(source: row)
            : YorksWorkforceDailyRosterDraftRow.fromProjection(row);
      });
      final sourceRows = <String, YorksWorkforceDailyRosterRow>{
        for (final row in projection.rows) row.workerId: row,
        for (final row in next.rows) row.workerId: row,
      };
      state = state.copyWith(
        status: YorksWorkforceDailyRosterStatus.ready,
        rows: [...state.rows, ...appended],
        projection: YorksWorkforceDailyRosterProjection(
          schemaVersion: next.schemaVersion,
          authorizationMode: next.authorizationMode,
          actorAuthUserId: next.actorAuthUserId,
          workDate: next.workDate,
          isFuture: next.isFuture,
          serverTime: next.serverTime,
          filters: state.filters,
          capabilities: next.capabilities,
          selectors: next.selectors,
          allocationTargets: next.allocationTargets,
          totalCount: next.totalCount,
          rows: sourceRows.values,
        ),
        clearError: true,
      );
      return true;
    } on YorksV1DomainException catch (error) {
      if (generation == _generation) _setFailure(error, command: false);
      return false;
    }
  }

  Future<bool> changeDate(String workDate) =>
      load(workDate: workDate, filters: state.filters.copyWith(offset: 0));

  Future<bool> changeFilters(YorksWorkforceRosterFilters filters) =>
      load(filters: filters.copyWith(offset: 0), preserveDrafts: true);

  void updateRow(
    String workerId, {
    YorksWorkforceAttendanceStatus? status,
    int? regularMinutes,
    int? overtimeMinutes,
    String? overtimeReason,
    bool clearOvertimeReason = false,
    YorksWorkforceRosterDraftSource source =
        YorksWorkforceRosterDraftSource.manual,
  }) {
    _replaceRow(workerId, (row) {
      final changesAttendanceValues =
          status != null || regularMinutes != null || overtimeMinutes != null;
      if ((changesAttendanceValues
              ? !row.isEditable
              : !row.canEditAttendanceEvidence) ||
          state.isBusy ||
          state.isReviewing) {
        return row;
      }
      final nextStatus = status ?? row.status;
      final isPresent = nextStatus == YorksWorkforceAttendanceStatus.present;
      final nextRegular = isPresent ? regularMinutes ?? row.regularMinutes : 0;
      final nextOvertime = isPresent
          ? overtimeMinutes ?? row.overtimeMinutes
          : 0;
      return row.copyWith(
        status: nextStatus,
        regularMinutes: nextRegular,
        overtimeMinutes: nextOvertime,
        overtimeReason: isPresent ? overtimeReason : null,
        clearOvertimeReason: !isPresent || clearOvertimeReason,
        allocations: isPresent
            ? _rebalanceSingleAllocation(
                row.allocations,
                nextRegular,
                nextOvertime,
              )
            : const <YorksWorkforceAllocationInput>[],
        reason: _rowEditReason,
        draftSource: source,
      );
    });
  }

  /// Marks a single worker using retained shift hours. Returns false when
  /// hours must be entered explicitly; never invents an eight-hour shift.
  bool markPresent(String workerId) {
    final row = _find(workerId);
    if (row == null || !row.isEditable || state.isBusy || state.isReviewing) {
      return false;
    }
    if (row.status == YorksWorkforceAttendanceStatus.present) return true;
    final minutes = row.source.scheduleSuggestion.suggestedRegularMinutes;
    if (minutes <= 0) return false;
    updateRow(
      workerId,
      status: YorksWorkforceAttendanceStatus.present,
      regularMinutes: minutes,
      overtimeMinutes: 0,
      clearOvertimeReason: true,
      source: YorksWorkforceRosterDraftSource.scheduleStandard,
    );
    return true;
  }

  YorksWorkforceDailyRosterDraftRow? currentRow(String workerId) =>
      _find(workerId);

  /// Undo only the exact still-current local edit. A refresh, newer edit,
  /// save, or authority purge invalidates the captured row identity.
  void undoQuickMark(
    YorksWorkforceDailyRosterDraftRow before,
    YorksWorkforceDailyRosterDraftRow after,
  ) {
    if (state.isBusy ||
        state.isReviewing ||
        !identical(_find(after.workerId), after)) {
      return;
    }
    _replaceRow(
      after.workerId,
      (current) => current.isEditable ? before : current,
    );
  }

  void toggleSelection(String workerId) {
    final selected = {...state.selectedWorkerIds};
    if (!selected.add(workerId)) selected.remove(workerId);
    state = state.copyWith(selectedWorkerIds: selected);
  }

  void selectVisible() => state = state.copyWith(
    selectedWorkerIds: state.rows
        .where((row) => row.isEditable)
        .map((row) => row.workerId)
        .toSet(),
  );

  void clearSelection() =>
      state = state.copyWith(selectedWorkerIds: <String>{});

  void selectTeam(String teamId) =>
      _selectMatching((row) => row.source.assignment.teamId == teamId.trim());

  void selectTrade(String tradeId) =>
      _selectMatching((row) => row.source.tradeId == tradeId.trim());

  void selectMissing() => _selectMatching(
    (row) => row.status == YorksWorkforceAttendanceStatus.notEntered,
  );

  void applyStandardMinutes() {
    for (final workerId in state.selectedWorkerIds) {
      final row = _find(workerId);
      if (row == null || !row.isEditable) continue;
      updateRow(
        workerId,
        status: row.source.scheduleSuggestion.suggestedStatus,
        regularMinutes: row.source.scheduleSuggestion.suggestedRegularMinutes,
        overtimeMinutes: row.source.scheduleSuggestion.suggestedOvertimeMinutes,
        clearOvertimeReason: true,
        source: YorksWorkforceRosterDraftSource.scheduleStandard,
      );
    }
  }

  void markAbsent() {
    for (final workerId in state.selectedWorkerIds) {
      updateRow(
        workerId,
        status: YorksWorkforceAttendanceStatus.absent,
        regularMinutes: 0,
        overtimeMinutes: 0,
        clearOvertimeReason: true,
      );
    }
  }

  void setRegularMinutesForSelected(int minutes) {
    if (minutes < 0 || minutes > 1440) return;
    for (final workerId in state.selectedWorkerIds) {
      final row = _find(workerId);
      if (row == null || !row.isEditable) continue;
      updateRow(
        workerId,
        status: YorksWorkforceAttendanceStatus.present,
        regularMinutes: minutes,
      );
    }
  }

  void setOvertimeForSelected(int minutes, {String? overtimeReason}) {
    if (minutes < 0 || minutes > 1440) return;
    for (final workerId in state.selectedWorkerIds) {
      final row = _find(workerId);
      if (row == null || !row.isEditable) continue;
      updateRow(
        workerId,
        status: YorksWorkforceAttendanceStatus.present,
        overtimeMinutes: minutes,
        overtimeReason: overtimeReason,
        clearOvertimeReason: _normalized(overtimeReason) == null,
      );
    }
  }

  void assignProjectToSelected({
    required String projectId,
    required String projectScopeId,
  }) {
    for (final workerId in state.selectedWorkerIds) {
      _setSingleTarget(
        workerId,
        targetKind: YorksWorkforceAllocationTargetKind.projectWork,
        projectId: projectId,
        projectScopeId: projectScopeId,
      );
    }
  }

  void assignInternalLocationToSelected(String internalLocationId) {
    for (final workerId in state.selectedWorkerIds) {
      _setSingleTarget(
        workerId,
        targetKind: YorksWorkforceAllocationTargetKind.internalWork,
        internalLocationId: internalLocationId,
      );
    }
  }

  void applyActivityToSelected(String? activity) {
    for (final workerId in state.selectedWorkerIds) {
      _updateAllocationText(
        workerId,
        activityTask: activity,
        updateActivity: true,
      );
    }
  }

  void applyNoteToSelected(String? note) {
    for (final workerId in state.selectedWorkerIds) {
      _updateAllocationText(workerId, notes: note, updateNotes: true);
    }
  }

  void assignProject(
    String workerId, {
    required String projectId,
    required String projectScopeId,
  }) => _setSingleTarget(
    workerId,
    targetKind: YorksWorkforceAllocationTargetKind.projectWork,
    projectId: projectId,
    projectScopeId: projectScopeId,
  );

  void assignInternalLocation(String workerId, String internalLocationId) =>
      _setSingleTarget(
        workerId,
        targetKind: YorksWorkforceAllocationTargetKind.internalWork,
        internalLocationId: internalLocationId,
      );

  void updateActivity(String workerId, String? activity) =>
      _updateAllocationText(
        workerId,
        activityTask: activity,
        updateActivity: true,
      );

  void updateAllocationNote(String workerId, String? note) =>
      _updateAllocationText(workerId, notes: note, updateNotes: true);

  /// Replaces the local allocation draft for one visible worker.
  ///
  /// The server remains authoritative when Save Day is confirmed. This method
  /// only permits targets included in the protected roster projection and
  /// deliberately allows temporarily unbalanced minutes so the focused editor
  /// can show validation feedback while a supervisor is splitting time.
  void replaceAllocations(
    String workerId,
    List<YorksWorkforceAllocationInput> allocations,
  ) {
    final targets = state.projection?.allocationTargets;
    if (targets == null ||
        allocations.any(
          (allocation) => !_isAllowedTarget(allocation, targets),
        )) {
      return;
    }
    _replaceRow(workerId, (row) {
      if (!row.isAllocationEditable ||
          state.isBusy ||
          state.isReviewing ||
          row.status != YorksWorkforceAttendanceStatus.present ||
          row.regularMinutes + row.overtimeMinutes <= 0) {
        return row;
      }
      return row.copyWith(
        allocations: List<YorksWorkforceAllocationInput>.unmodifiable(
          allocations,
        ),
        reason: _rowEditReason,
        draftSource: YorksWorkforceRosterDraftSource.manual,
      );
    });
  }

  bool _isAllowedTarget(
    YorksWorkforceAllocationInput allocation,
    YorksWorkforceRosterAllocationTargets targets,
  ) => switch (allocation.targetKind) {
    YorksWorkforceAllocationTargetKind.projectWork =>
      allocation.projectId != null &&
          allocation.projectScopeId != null &&
          allocation.internalLocationId == null &&
          targets.projects.any((item) => item.id == allocation.projectId) &&
          targets.projectScopes.any(
            (item) =>
                item.projectId == allocation.projectId &&
                item.id == allocation.projectScopeId,
          ),
    YorksWorkforceAllocationTargetKind.internalWork =>
      allocation.projectId == null &&
          allocation.projectScopeId == null &&
          allocation.internalLocationId != null &&
          targets.internalLocations.any(
            (item) => item.id == allocation.internalLocationId,
          ),
  };

  Future<int> copyPreviousDay() async {
    if (!_connectivity.isOnline || state.selectedWorkerIds.isEmpty) return 0;
    final workDate = state.workDate;
    final current = DateTime.tryParse(workDate);
    if (current == null) return 0;
    final previousDate = _isoDate(current.subtract(const Duration(days: 1)));
    final generation = _generation;
    final selected = Set<String>.unmodifiable(state.selectedWorkerIds);
    try {
      final byWorker = <String, YorksWorkforceDailyRosterRow>{};
      final seenWorkers = <String>{};
      int? totalCount;
      var offset = 0;
      while (offset < yorksWorkforceRosterMaxPageSize) {
        final remaining = yorksWorkforceRosterMaxPageSize - offset;
        final page = await _repository.getDailyRoster(
          workDate: previousDate,
          filters: state.filters.copyWith(
            limit: remaining < yorksWorkforceRosterCopyPageSize
                ? remaining
                : yorksWorkforceRosterCopyPageSize,
            offset: offset,
          ),
        );
        if (generation != _generation ||
            state.workDate != workDate ||
            state.selectedWorkerIds.length != selected.length ||
            !state.selectedWorkerIds.containsAll(selected)) {
          return 0;
        }
        totalCount ??= page.totalCount;
        if (page.totalCount != totalCount ||
            (page.rows.isNotEmpty &&
                page.rows.any((row) => !seenWorkers.add(row.workerId)))) {
          _setFailure(
            const YorksV1DomainException(
              YorksV1DomainErrorCode.unexpectedResponse,
            ),
            command: false,
          );
          return 0;
        }
        for (final row in page.rows) {
          if (selected.contains(row.workerId)) byWorker[row.workerId] = row;
        }
        offset += page.rows.length;
        if (selected.every(byWorker.containsKey) || offset >= page.totalCount) {
          break;
        }
        if (page.rows.isEmpty) {
          _setFailure(
            const YorksV1DomainException(
              YorksV1DomainErrorCode.unexpectedResponse,
            ),
            command: false,
          );
          return 0;
        }
      }
      if (selected.any((workerId) => !byWorker.containsKey(workerId)) &&
          (totalCount ?? 0) > offset &&
          offset >= yorksWorkforceRosterMaxPageSize) {
        _setFailure(
          const YorksV1DomainException(
            YorksV1DomainErrorCode.unexpectedResponse,
          ),
          command: false,
        );
        return 0;
      }
      var copied = 0;
      for (final workerId in selected) {
        final target = _find(workerId);
        final previousRow = byWorker[workerId];
        final attendance = previousRow?.attendance;
        if (target == null ||
            !target.isEditable ||
            target.wasCommitted ||
            target.isDirty ||
            attendance?.status != YorksWorkforceAttendanceStatus.present) {
          continue;
        }
        final suggestion = target.source.scheduleSuggestion;
        if (suggestion.suggestedStatus !=
            YorksWorkforceAttendanceStatus.present) {
          continue;
        }
        final safeAllocation =
            target.isAllocationEditable && previousRow != null
            ? _safeCopiedAllocation(
                previousRow.allocationSet,
                state.projection?.allocationTargets,
                suggestion.suggestedRegularMinutes,
              )
            : null;
        updateRow(
          workerId,
          status: suggestion.suggestedStatus,
          regularMinutes: suggestion.suggestedRegularMinutes,
          overtimeMinutes: 0,
          clearOvertimeReason: true,
          source: YorksWorkforceRosterDraftSource.previousDay,
        );
        if (safeAllocation != null) {
          _replaceRow(
            workerId,
            (row) => row.copyWith(
              allocations: [safeAllocation],
              draftSource: YorksWorkforceRosterDraftSource.previousDay,
            ),
          );
        }
        copied += 1;
      }
      return copied;
    } on YorksV1DomainException catch (error) {
      _setFailure(error, command: false);
      return 0;
    }
  }

  void _setSingleTarget(
    String workerId, {
    required YorksWorkforceAllocationTargetKind targetKind,
    String? projectId,
    String? projectScopeId,
    String? internalLocationId,
  }) {
    final targets = state.projection?.allocationTargets;
    final validTarget = switch (targetKind) {
      YorksWorkforceAllocationTargetKind.projectWork =>
        targets != null &&
            targets.projects.any((row) => row.id == projectId?.trim()) &&
            targets.projectScopes.any(
              (row) =>
                  row.projectId == projectId?.trim() &&
                  row.id == projectScopeId?.trim(),
            ) &&
            internalLocationId == null,
      YorksWorkforceAllocationTargetKind.internalWork =>
        targets != null &&
            projectId == null &&
            projectScopeId == null &&
            targets.internalLocations.any(
              (row) => row.id == internalLocationId?.trim(),
            ),
    };
    if (!validTarget) return;
    _replaceRow(workerId, (row) {
      if (!row.isAllocationEditable ||
          state.isBusy ||
          state.isReviewing ||
          row.status != YorksWorkforceAttendanceStatus.present ||
          row.regularMinutes + row.overtimeMinutes <= 0) {
        return row;
      }
      final prior = row.allocations.length == 1 ? row.allocations.single : null;
      return row.copyWith(
        allocations: [
          YorksWorkforceAllocationInput(
            targetKind: targetKind,
            projectId: projectId,
            projectScopeId: projectScopeId,
            internalLocationId: internalLocationId,
            activityTask: prior?.activityTask,
            notes: prior?.notes,
            regularMinutes: row.regularMinutes,
            overtimeMinutes: row.overtimeMinutes,
          ),
        ],
        reason: _rowEditReason,
        draftSource: YorksWorkforceRosterDraftSource.manual,
      );
    });
  }

  void _updateAllocationText(
    String workerId, {
    String? activityTask,
    String? notes,
    bool updateActivity = false,
    bool updateNotes = false,
  }) {
    _replaceRow(workerId, (row) {
      if (!row.isAllocationEditable || row.allocations.isEmpty) return row;
      return row.copyWith(
        allocations: row.allocations
            .map(
              (allocation) => _copyAllocation(
                allocation,
                activityTask: activityTask,
                notes: notes,
                updateActivity: updateActivity,
                updateNotes: updateNotes,
              ),
            )
            .toList(growable: false),
        reason: _rowEditReason,
        draftSource: YorksWorkforceRosterDraftSource.manual,
      );
    });
  }

  bool reviewDay() {
    if (!_connectivity.isOnline) {
      state = state.copyWith(
        status: YorksWorkforceDailyRosterStatus.offline,
        isOnline: false,
      );
      return false;
    }
    if (state.dirtyRows.isEmpty || state.invalidWorkerIds.isNotEmpty) {
      return false;
    }
    if (state.dirtyRows.length > yorksWorkforceRosterMaxCommandRows) {
      state = state.copyWith(
        status: YorksWorkforceDailyRosterStatus.failure,
        error: const YorksV1DomainException(
          YorksV1DomainErrorCode.invalidInput,
        ),
      );
      return false;
    }
    state = state.copyWith(status: YorksWorkforceDailyRosterStatus.reviewing);
    return true;
  }

  void backToEdit() {
    if (state.isReviewing) {
      state = state.copyWith(status: YorksWorkforceDailyRosterStatus.ready);
    }
  }

  Future<YorksWorkforceDailyRosterSaveResult?> saveDay() async {
    final dirty = state.dirtyRows;
    if (!state.isReviewing ||
        dirty.isEmpty ||
        state.invalidWorkerIds.isNotEmpty ||
        !_connectivity.isOnline) {
      return null;
    }
    final rows = dirty.map((row) => row.toSaveRow()).toList(growable: false);
    final payload = <String, Object?>{
      'work_date': state.workDate,
      'rows': rows.map((row) => row.toRpcJson()).toList(growable: false),
      'reason': _batchSaveReason,
    };
    state = state.copyWith(
      status: YorksWorkforceDailyRosterStatus.saving,
      clearError: true,
    );
    try {
      final key = await _commandKeys.acquire(
        operation: operation,
        entityId: state.workDate,
        payload: payload,
      );
      final result = await _repository.saveDailyRoster(
        workDate: state.workDate,
        rows: rows,
        reason: _batchSaveReason,
        idempotencyKey: key,
      );
      await _commandKeys.confirm(
        operation: operation,
        entityId: state.workDate,
        idempotencyKey: key,
      );
      final saved = {for (final row in result.rows) row.workerId: row};
      state = state.copyWith(
        status: YorksWorkforceDailyRosterStatus.saved,
        rows: state.rows.map((row) {
          final resultRow = saved[row.workerId];
          return resultRow == null ? row : row.withSaved(resultRow);
        }),
        selectedWorkerIds: <String>{},
        lastSavedAt: result.savedAt,
        clearError: true,
      );
      for (final workerId in saved.keys) {
        _retainedDrafts.remove(workerId);
      }
      return result;
    } on YorksV1DomainException catch (error) {
      _setFailure(error, command: true);
      return null;
    } catch (error) {
      _setFailure(
        YorksV1DomainException(
          YorksV1DomainErrorCode.backendUnavailable,
          cause: error,
        ),
        command: true,
      );
      return null;
    }
  }

  void purgeProtectedState({bool unavailable = false}) {
    _generation += 1;
    _retainedDrafts.clear();
    state = YorksWorkforceDailyRosterState(
      status: unavailable
          ? YorksWorkforceDailyRosterStatus.unavailable
          : YorksWorkforceDailyRosterStatus.forbidden,
      workDate: _isoDate(_clock()),
      isOnline: _connectivity.isOnline,
    );
  }

  void _replaceRow(
    String workerId,
    YorksWorkforceDailyRosterDraftRow Function(
      YorksWorkforceDailyRosterDraftRow row,
    )
    transform,
  ) {
    var changed = false;
    final rows = state.rows
        .map((row) {
          if (row.workerId != workerId) return row;
          final next = transform(row);
          changed = !identical(next, row);
          return next;
        })
        .toList(growable: false);
    if (changed) {
      final changedRow = rows.firstWhere((row) => row.workerId == workerId);
      if (changedRow.isDirty) {
        _retainedDrafts[workerId] = changedRow;
      } else {
        _retainedDrafts.remove(workerId);
      }
      state = state.copyWith(
        status: YorksWorkforceDailyRosterStatus.ready,
        rows: rows,
        clearError: true,
        clearLastSaved: true,
      );
    }
  }

  void _selectMatching(
    bool Function(YorksWorkforceDailyRosterDraftRow row) predicate,
  ) {
    state = state.copyWith(
      selectedWorkerIds: state.rows
          .where((row) => row.isEditable && predicate(row))
          .map((row) => row.workerId)
          .toSet(),
    );
  }

  YorksWorkforceDailyRosterDraftRow? _find(String workerId) {
    for (final row in state.rows) {
      if (row.workerId == workerId) return row;
    }
    return null;
  }

  bool _canRebase(
    YorksWorkforceDailyRosterDraftRow draft,
    YorksWorkforceDailyRosterRow source,
  ) {
    if (draft.expectedAttendanceVersion != source.attendance?.recordVersion ||
        draft.expectedAllocationVersion !=
            source.allocationSet?.recordVersion) {
      return false;
    }
    final changesProtectedValues =
        draft.attendanceAllocationBasisChanged || draft.allocationsDirty;
    return changesProtectedValues
        ? source.isAttendanceEditable
        : source.canMaintainAttendance;
  }

  void _onConnectivityChanged(bool online) {
    if (!mounted) return;
    state = state.copyWith(
      status: online && state.status == YorksWorkforceDailyRosterStatus.offline
          ? YorksWorkforceDailyRosterStatus.ready
          : online
          ? state.status
          : YorksWorkforceDailyRosterStatus.offline,
      isOnline: online,
    );
  }

  void _setFailure(YorksV1DomainException error, {required bool command}) {
    final status = switch (error.code) {
      YorksV1DomainErrorCode.unauthorized =>
        YorksWorkforceDailyRosterStatus.forbidden,
      YorksV1DomainErrorCode.unauthenticated =>
        YorksWorkforceDailyRosterStatus.sessionExpired,
      YorksV1DomainErrorCode.offline => YorksWorkforceDailyRosterStatus.offline,
      YorksV1DomainErrorCode.conflict =>
        YorksWorkforceDailyRosterStatus.conflict,
      YorksV1DomainErrorCode.featureDisabled =>
        YorksWorkforceDailyRosterStatus.unavailable,
      YorksV1DomainErrorCode.backendUnavailable when command =>
        YorksWorkforceDailyRosterStatus.uncertain,
      _ => YorksWorkforceDailyRosterStatus.failure,
    };
    if (status == YorksWorkforceDailyRosterStatus.forbidden ||
        status == YorksWorkforceDailyRosterStatus.sessionExpired ||
        status == YorksWorkforceDailyRosterStatus.unavailable) {
      _generation += 1;
      _retainedDrafts.clear();
      state = YorksWorkforceDailyRosterState(
        status: status,
        workDate: _isoDate(_clock()),
        error: error,
        isOnline: _connectivity.isOnline,
      );
      return;
    }
    state = state.copyWith(
      status: status,
      error: error,
      isOnline: _connectivity.isOnline,
    );
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}

const _rowEditReason = 'Daily roster attendance edit';
const _batchSaveReason = 'Daily roster attendance save';

String? _normalized(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}

String _isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

List<YorksWorkforceAllocationInput> _allocationInputs(
  YorksWorkforceTimesheetDay? set,
) {
  if (set == null || set.state != 'active') {
    return const <YorksWorkforceAllocationInput>[];
  }
  return List.unmodifiable(
    set.allocations.map(
      (row) => YorksWorkforceAllocationInput(
        targetKind: row.target.kind,
        projectId: row.target.projectId,
        projectScopeId: row.target.projectScopeId,
        internalLocationId: row.target.internalLocationId,
        activityTask: row.activityTask,
        notes: row.notes,
        regularMinutes: row.regularMinutes,
        overtimeMinutes: row.overtimeMinutes,
        startTime: row.startTime,
        endTime: row.endTime,
      ),
    ),
  );
}

String _allocationFingerprint(List<YorksWorkforceAllocationInput> rows) =>
    jsonEncode(rows.map((row) => row.toRpcJson()).toList(growable: false));

YorksWorkforceAllocationInput _copyAllocation(
  YorksWorkforceAllocationInput source, {
  int? regularMinutes,
  int? overtimeMinutes,
  String? activityTask,
  String? notes,
  bool updateActivity = false,
  bool updateNotes = false,
}) => YorksWorkforceAllocationInput(
  targetKind: source.targetKind,
  projectId: source.projectId,
  projectScopeId: source.projectScopeId,
  internalLocationId: source.internalLocationId,
  activityTask: updateActivity
      ? _normalized(activityTask)
      : source.activityTask,
  notes: updateNotes ? _normalized(notes) : source.notes,
  regularMinutes: regularMinutes ?? source.regularMinutes,
  overtimeMinutes: overtimeMinutes ?? source.overtimeMinutes,
  startTime: source.startTime,
  endTime: source.endTime,
);

List<YorksWorkforceAllocationInput> _rebalanceSingleAllocation(
  List<YorksWorkforceAllocationInput> allocations,
  int regularMinutes,
  int overtimeMinutes,
) {
  if (allocations.length != 1) return allocations;
  return [
    _copyAllocation(
      allocations.single,
      regularMinutes: regularMinutes,
      overtimeMinutes: overtimeMinutes,
    ),
  ];
}

YorksWorkforceAllocationInput? _safeCopiedAllocation(
  YorksWorkforceTimesheetDay? previous,
  YorksWorkforceRosterAllocationTargets? targets,
  int regularMinutes,
) {
  if (previous == null ||
      previous.state != 'active' ||
      previous.allocations.length != 1 ||
      targets == null ||
      regularMinutes <= 0) {
    return null;
  }
  final source = previous.allocations.single.target;
  if (source.kind == YorksWorkforceAllocationTargetKind.projectWork) {
    final projectId = source.projectId;
    final scopeId = source.projectScopeId;
    final projectAllowed = targets.projects.any((row) => row.id == projectId);
    final scopeAllowed = targets.projectScopes.any(
      (row) => row.id == scopeId && row.projectId == projectId,
    );
    if (!projectAllowed || !scopeAllowed) return null;
    return YorksWorkforceAllocationInput(
      targetKind: source.kind,
      projectId: projectId,
      projectScopeId: scopeId,
      regularMinutes: regularMinutes,
      overtimeMinutes: 0,
    );
  }
  final locationId = source.internalLocationId;
  if (!targets.internalLocations.any((row) => row.id == locationId)) {
    return null;
  }
  return YorksWorkforceAllocationInput(
    targetKind: source.kind,
    internalLocationId: locationId,
    regularMinutes: regularMinutes,
    overtimeMinutes: 0,
  );
}

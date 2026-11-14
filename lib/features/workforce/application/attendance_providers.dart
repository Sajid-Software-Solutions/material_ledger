/// Workforce attendance V2 — providers and the crew-day controller.
///
/// A day is edited locally (kept on the device as you go) and saved in one
/// command. The server confirms every save; nothing is shown as saved before
/// it answers.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/models/yorks_v1_domain_error.dart';
import '../../../shared/providers/language_provider.dart';
import '../../../shared/providers/yorks_v1_feature_flags_provider.dart';
import '../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../../shared/sync/connectivity_service.dart';
import '../data/attendance_repository.dart';
import '../domain/attendance_models.dart';
import '../domain/crew_request_models.dart';
import '../domain/attendance_time.dart';
import 'workforce_providers.dart';

final yorksAttendanceRepositoryProvider = Provider<YorksAttendanceRepository>(
  (ref) => YorksAttendanceRepository(
    featureFlags: ref.watch(yorksV1FeatureFlagsProvider),
    connectivity: ref.watch(connectivityProvider),
    rpcClient: ref.watch(yorksWorkforceRpcClientProvider),
  ),
);

/// The overview for a month (`YYYY-MM-01`), or the current month when null.
final yorksAttendanceOverviewProvider = FutureProvider.autoDispose
    .family<AttendanceOverview, String?>(
      (ref, month) => ref
          .watch(yorksAttendanceRepositoryProvider)
          .getOverview(month: month),
    );

/// Crew months waiting for the signed-in person's confirmation (the month
/// ended, or ends today). Empty for people who do not confirm.
final yorksAttendanceConfirmationsDueProvider =
    FutureProvider.autoDispose<List<AttendanceConfirmationDue>>(
      (ref) => ref.watch(yorksAttendanceRepositoryProvider).confirmationsDue(),
    );

final yorksAttendanceCrewsProvider =
    FutureProvider.autoDispose<List<AttendanceCrew>>(
      (ref) => ref.watch(yorksAttendanceRepositoryProvider).listCrews(),
    );

/// Status only of each crew worker's documents, when People is on.
final yorksCrewDocumentStatusProvider = FutureProvider.autoDispose
    .family<Map<String, CrewDocumentStatus>, String>((ref, crewId) {
      if (!ref.watch(yorksV1FeatureFlagsProvider).peopleRecords) {
        return const {};
      }
      return ref
          .watch(yorksAttendanceRepositoryProvider)
          .crewDocumentStatus(crewId);
    });

final yorksAttendanceCrewDetailProvider = FutureProvider.autoDispose
    .family<({AttendanceCrew crew, List<AttendanceWorker> members}), String>(
      (ref, crewId) =>
          ref.watch(yorksAttendanceRepositoryProvider).getCrew(crewId),
    );

final yorksAttendanceHolidaysProvider = FutureProvider.autoDispose
    .family<AttendanceHolidays, int>(
      (ref, year) =>
          ref.watch(yorksAttendanceRepositoryProvider).listHolidays(year),
    );

/// Whether the signed-in person may create attendance sheets.
final yorksAttendanceCanCreateCrewProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(yorksAttendanceRepositoryProvider).canCreateCrew(),
);

final yorksAttendanceWorkersProvider =
    FutureProvider.autoDispose<List<AttendanceWorker>>(
      (ref) => ref.watch(yorksAttendanceRepositoryProvider).listWorkers(),
    );

final yorksAttendanceMonthSheetProvider = FutureProvider.autoDispose
    .family<AttendanceMonthSheet, ({String crewId, String month})>(
      (ref, key) => ref
          .watch(yorksAttendanceRepositoryProvider)
          .getMonthSheet(crewId: key.crewId, month: key.month),
    );

/// Crew requests the signed-in person may see (Workforce Center).
final yorksCrewRequestsProvider =
    FutureProvider.autoDispose<CrewRequestRegister>(
      (ref) => ref.watch(yorksAttendanceRepositoryProvider).listRequests(),
    );

final yorksCrewRequestProvider = FutureProvider.autoDispose
    .family<CrewRequest, String>(
      (ref, requestId) =>
          ref.watch(yorksAttendanceRepositoryProvider).getRequest(requestId),
    );

/// Projects, trades, crews and (for PR/Admin) workers for request forms.
final yorksCrewRequestOptionsProvider =
    FutureProvider.autoDispose<CrewRequestOptions>(
      (ref) => ref.watch(yorksAttendanceRepositoryProvider).requestOptions(),
    );

typedef AttendanceDayKey = ({String crewId, String date});

final yorksAttendanceDayControllerProvider = StateNotifierProvider.autoDispose
    .family<AttendanceDayController, AttendanceDayEditState, AttendanceDayKey>((
      ref,
      key,
    ) {
      final controller = AttendanceDayController(
        repository: ref.watch(yorksAttendanceRepositoryProvider),
        preferences: ref.watch(sharedPreferencesProvider),
        actorId: ref.watch(yorksV1AuthUserIdProvider) ?? 'anonymous',
        key: key,
      );
      controller.load();
      return controller;
    });

/// The state of one crew day on screen.
final class AttendanceDayEditState {
  const AttendanceDayEditState({
    this.day,
    this.rows = const [],
    this.loading = true,
    this.saving = false,
    this.error,
    this.dirty = false,
  });

  /// The server's day, as last confirmed.
  final AttendanceDay? day;

  /// The rows being edited (equal to the server's when not [dirty]).
  final List<AttendanceRow> rows;
  final bool loading;
  final bool saving;
  final YorksV1DomainException? error;

  /// True when [rows] differ from the server's day.
  final bool dirty;

  bool get holiday => day?.holiday ?? false;

  /// Rows on this device that differ from the server's day.
  bool get hasLocalChanges {
    final saved = day?.rows ?? const <AttendanceRow>[];
    if (saved.length != rows.length) return true;
    final byId = {for (final row in saved) row.worker.id: row};
    for (final row in rows) {
      final other = byId[row.worker.id];
      if (other == null || !row.sameEntry(other)) return true;
    }
    return false;
  }

  int get presentCount =>
      rows.where((row) => row.status == AttendanceStatus.present).length;
  int get absentCount =>
      rows.where((row) => row.status == AttendanceStatus.absent).length;
  int get leaveCount =>
      rows.where((row) => row.status?.isLeave ?? false).length;

  /// Still to be marked: not marked here and not recorded at another place.
  int get unmarkedCount => rows.where((row) => row.needsMarking).length;

  /// Members recorded at another place today and not marked here.
  int get elsewhereCount =>
      rows.where((row) => !row.isMarked && row.busyElsewhere).length;

  /// Lines that clash with the worker's other places today.
  int get conflictCount => rows
      .where((row) => row.placeConflict != AttendancePlaceConflict.none)
      .length;
  int get timeMissingCount =>
      rows.where((row) => row.minutes(holiday: holiday).timeMissing).length;
  int get normalOvertime => rows.fold(
    0,
    (sum, row) => sum + row.minutes(holiday: holiday).normalOvertime,
  );
  int get holidayOvertime => rows.fold(
    0,
    (sum, row) => sum + row.minutes(holiday: holiday).holidayOvertime,
  );

  /// Ready to save: every worker marked (or recorded at another place),
  /// every present worker timed, nothing clashing with another place.
  bool get canSave =>
      rows.isNotEmpty &&
      unmarkedCount == 0 &&
      timeMissingCount == 0 &&
      conflictCount == 0 &&
      !saving &&
      (dirty || !(day?.saved ?? false));

  AttendanceDayEditState copyWith({
    AttendanceDay? day,
    List<AttendanceRow>? rows,
    bool? loading,
    bool? saving,
    YorksV1DomainException? error,
    bool clearError = false,
    bool? dirty,
  }) => AttendanceDayEditState(
    day: day ?? this.day,
    rows: rows ?? this.rows,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    error: clearError ? null : (error ?? this.error),
    dirty: dirty ?? this.dirty,
  );
}

final class AttendanceDayController
    extends StateNotifier<AttendanceDayEditState> {
  AttendanceDayController({
    required YorksAttendanceRepository repository,
    required SharedPreferences preferences,
    required String actorId,
    required this.key,
  }) : _repository = repository,
       _preferences = preferences,
       _actorId = actorId,
       super(const AttendanceDayEditState());

  final YorksAttendanceRepository _repository;
  final SharedPreferences _preferences;
  final String _actorId;
  final AttendanceDayKey key;
  String? _pendingSaveKey;

  /// The current state, for flows that span several sheets.
  AttendanceDayEditState get current => state;

  String get _draftKey =>
      'yorks.attendance.draft.v1.$_actorId.${key.crewId}.${key.date}';

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final day = await _repository.getDay(crewId: key.crewId, date: key.date);
      if (!mounted) return;
      final base = _startingRows(day);
      final draft = _withServerPlaces(_readDraft(day), day);
      state = AttendanceDayEditState(
        day: day,
        rows: draft ?? base,
        loading: false,
        dirty: draft != null && !_same(draft, day.rows),
      );
    } on YorksV1DomainException catch (error) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: error);
    }
  }

  /// A new rest day starts with everyone on Rest day, as on paper, except
  /// those recorded at another place.
  List<AttendanceRow> _startingRows(AttendanceDay day) {
    if (day.saved || !day.holiday) return day.rows;
    return [
      for (final row in day.rows)
        row.isMarked || row.busyElsewhere
            ? row
            : row.copyWith(status: AttendanceStatus.rest),
    ];
  }

  /// Rows kept on this device carry the server's latest view of the other
  /// places, never the one saved with the draft.
  List<AttendanceRow>? _withServerPlaces(
    List<AttendanceRow>? rows,
    AttendanceDay day,
  ) {
    if (rows == null) return null;
    final places = {for (final row in day.rows) row.worker.id: row.elsewhere};
    return [
      for (final row in rows)
        row.withElsewhere(places[row.worker.id] ?? const []),
    ];
  }

  bool _same(List<AttendanceRow> a, List<AttendanceRow> b) {
    if (a.length != b.length) return false;
    final byId = {for (final row in b) row.worker.id: row};
    for (final row in a) {
      final other = byId[row.worker.id];
      if (other == null || !row.sameEntry(other)) return false;
    }
    return true;
  }

  List<AttendanceRow>? _readDraft(AttendanceDay day) {
    if (!day.editable) return null;
    final raw = _preferences.getString(_draftKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['base_version'] != day.recordVersion) {
        // The day changed on the server since this draft was started; keep
        // the server's day rather than overwrite it silently.
        _preferences.remove(_draftKey);
        return null;
      }
      return [
        for (final row in (json['rows'] as List))
          AttendanceRow.fromJson(Map<String, dynamic>.from(row as Map)),
      ];
    } catch (_) {
      _preferences.remove(_draftKey);
      return null;
    }
  }

  void _writeDraft(List<AttendanceRow> rows) {
    final day = state.day;
    if (day == null) return;
    final dirty = !_same(rows, day.rows) || !day.saved;
    state = state.copyWith(rows: rows, dirty: dirty, clearError: true);
    if (!_same(rows, day.rows)) {
      _preferences.setString(
        _draftKey,
        jsonEncode({
          'base_version': day.recordVersion,
          'rows': [for (final row in rows) row.toDraftJson()],
        }),
      );
    } else {
      _preferences.remove(_draftKey);
    }
  }

  void setRow(String workerId, AttendanceRow row) {
    _writeDraft([
      for (final existing in state.rows)
        existing.worker.id == workerId ? row : existing,
    ]);
  }

  /// Present on the usual shift, with the crew's break and place.
  AttendanceRow presentOnShift(AttendanceRow row) {
    final crew = state.day!.crew;
    final holiday = state.holiday;
    return row.copyWith(
      status: AttendanceStatus.present,
      start: row.start ?? crew.shiftStart,
      finish: row.finish ?? (holiday ? 900 : crew.shiftFinish),
      breakStart: row.start == null ? crew.breakStart : row.breakStart,
      breakFinish: row.start == null ? crew.breakFinish : row.breakFinish,
      workProjectId: row.workProjectId ?? crew.projectId,
      workLabel: row.workLabel ?? crew.workLabel,
    );
  }

  void setStatus(String workerId, AttendanceStatus status) {
    final row = state.rows.firstWhere((row) => row.worker.id == workerId);
    setRow(
      workerId,
      status == AttendanceStatus.present
          ? presentOnShift(row)
          : row.copyWith(status: status, clearTimes: true),
    );
  }

  /// Everyone still to be marked is present on the usual shift; workers
  /// recorded at another place today are left for the keeper to decide.
  void everyonePresent() {
    _writeDraft([
      for (final row in state.rows)
        row.needsMarking ? presentOnShift(row) : row,
    ]);
  }

  /// Applies the crew's usual shift to every present worker.
  void applyShift(int start, int finish) {
    _writeDraft([
      for (final row in state.rows)
        row.status == AttendanceStatus.present
            ? row.copyWith(start: start, finish: finish)
            : row,
    ]);
  }

  /// Copies an earlier saved day of the same kind, keeping only workers who
  /// are still on this day.
  Future<bool> copyFrom(String date) async {
    try {
      final source = await _repository.getDay(crewId: key.crewId, date: date);
      final byId = {for (final row in source.rows) row.worker.id: row};
      AttendanceRow copyOf(AttendanceRow row, AttendanceRow copied) =>
          AttendanceRow(
            worker: row.worker,
            status: copied.status,
            start: copied.start,
            breakStart: copied.breakStart,
            breakFinish: copied.breakFinish,
            finish: copied.finish,
            workProjectId: copied.workProjectId,
            workLabel: copied.workLabel,
            copied: true,
            isMember: row.isMember,
            elsewhere: row.elsewhere,
          );
      _writeDraft([
        for (final row in state.rows)
          if (byId[row.worker.id] case final copied? when copied.isMarked)
            // A copy that would clash with another place today is skipped.
            if (copyOf(row, copied).placeConflict ==
                AttendancePlaceConflict.none)
              copyOf(row, copied)
            else
              row
          else
            row,
      ]);
      return true;
    } on YorksV1DomainException catch (error) {
      state = state.copyWith(error: error);
      return false;
    }
  }

  /// Adds a worker to this day only (borrowed or from the labour pool).
  void addWorkerForDay(AttendanceWorker worker) {
    if (state.rows.any((row) => row.worker.id == worker.id)) return;
    final added = AttendanceRow(
      worker: worker,
      isMember: false,
      status: state.holiday ? AttendanceStatus.rest : null,
    );
    _writeDraft([...state.rows, added]);
  }

  void removeDayOnly(String workerId) {
    _writeDraft([
      for (final row in state.rows)
        if (row.worker.id != workerId || row.isMember) row,
    ]);
  }

  /// Puts back rows saved before a one-tap change (Undo).
  void restoreRows(List<AttendanceRow> rows) => _writeDraft(rows);

  /// After a conflict: load the day someone else saved, keep this person's
  /// entries on top of it and save against the new version.
  Future<void> reloadKeepingMine() async {
    final mine = state.rows;
    try {
      final day = await _repository.getDay(crewId: key.crewId, date: key.date);
      if (!mounted) return;
      final byId = {for (final row in mine) row.worker.id: row};
      final merged = [
        for (final row in day.rows)
          byId.remove(row.worker.id)?.withElsewhere(row.elsewhere) ?? row,
        // Workers added for the day on this device stay too.
        ...byId.values.where((row) => !row.isMember),
      ];
      state = AttendanceDayEditState(day: day, rows: merged, loading: false);
      _writeDraft(merged);
    } on YorksV1DomainException catch (error) {
      if (mounted) state = state.copyWith(error: error);
    }
  }

  /// After a conflict: drop this device's entries and show the saved day.
  Future<void> useTheirs() async {
    _preferences.remove(_draftKey);
    await load();
  }

  void discard() {
    _preferences.remove(_draftKey);
    final day = state.day;
    if (day == null) return;
    state = state.copyWith(
      rows: _startingRows(day),
      dirty: !day.saved && day.holiday,
      clearError: true,
    );
  }

  /// Saves the whole day. Returns the server's day, or null on failure (the
  /// error is in the state and the draft stays on the device).
  Future<AttendanceDay?> save({String? changeReason}) async {
    final day = state.day;
    if (day == null || state.saving) return null;
    _pendingSaveKey ??= YorksAttendanceRepository.newKey();
    state = state.copyWith(saving: true, clearError: true);
    try {
      final saved = await _repository.saveDay(
        crewId: key.crewId,
        date: key.date,
        rows: state.rows,
        expectedVersion: day.recordVersion,
        changeReason: changeReason,
        idempotencyKey: _pendingSaveKey!,
      );
      _pendingSaveKey = null;
      _preferences.remove(_draftKey);
      if (!mounted) return saved;
      state = AttendanceDayEditState(
        day: saved,
        rows: saved.rows,
        loading: false,
      );
      return saved;
    } on YorksV1DomainException catch (error) {
      // A rejected command did not commit; a new attempt uses a new key.
      if (error.code != YorksV1DomainErrorCode.offline &&
          error.code != YorksV1DomainErrorCode.backendUnavailable) {
        _pendingSaveKey = null;
      }
      if (mounted) state = state.copyWith(saving: false, error: error);
      return null;
    }
  }

  Future<bool> ask(String question) => _command(
    () => _repository.askDay(
      crewId: key.crewId,
      date: key.date,
      question: question,
      idempotencyKey: YorksAttendanceRepository.newKey(),
    ),
  );

  Future<bool> answer(String answer) => _command(
    () => _repository.answerDay(
      crewId: key.crewId,
      date: key.date,
      answer: answer,
      idempotencyKey: YorksAttendanceRepository.newKey(),
    ),
  );

  Future<bool> _command(Future<AttendanceDay> Function() run) async {
    state = state.copyWith(saving: true, clearError: true);
    try {
      final day = await run();
      if (!mounted) return true;
      state = state.copyWith(
        day: day,
        saving: false,
        rows: state.dirty ? state.rows : day.rows,
      );
      return true;
    } on YorksV1DomainException catch (error) {
      if (mounted) state = state.copyWith(saving: false, error: error);
      return false;
    }
  }
}

/// The working days of a month up to today that have no entry, from a month
/// projection (used for "Next not entered").
String? nextMissingDay(AttendanceMonth month, {String? after}) {
  for (final day in month.missingDays) {
    if (after == null || day.compareTo(after) > 0) return day;
  }
  return month.missingDays.isEmpty ? null : month.missingDays.first;
}

/// `YYYY-MM-01` for the month containing [iso].
String attendanceMonthOf(String iso) => '${iso.substring(0, 7)}-01';

/// Today's date on this device, used only before the server answers.
String attendanceLocalToday() => attendanceIso(DateTime.now());

/// Dates of [crewId] with entries kept on this device and not yet saved.
Set<String> attendanceDraftDates(
  SharedPreferences preferences, {
  required String actorId,
  required String crewId,
}) {
  final prefix = 'yorks.attendance.draft.v1.$actorId.$crewId.';
  return {
    for (final key in preferences.getKeys())
      if (key.startsWith(prefix)) key.substring(prefix.length),
  };
}

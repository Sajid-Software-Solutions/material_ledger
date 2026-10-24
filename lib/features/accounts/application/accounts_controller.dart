import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/yorks_v1_domain_error.dart';
import '../../../shared/services/yorks_v1_critical_command_key_store.dart';
import '../data/accounts_repository.dart';
import '../domain/accounts_inputs.dart';
import '../domain/accounts_models.dart';

enum YorksAccountsViewStatus {
  idle,
  loading,
  success,
  forbidden,
  offline,
  conflict,
  uncertain,
  sessionExpired,
  unavailable,
  failure,
}

final class YorksAccountsProjectState {
  const YorksAccountsProjectState({
    this.status = YorksAccountsViewStatus.idle,
    this.baseline,
    this.progress,
    this.revisionHistory,
    this.error,
    this.isMutating = false,
    this.hasPendingCommand = false,
  });

  final YorksAccountsViewStatus status;
  final YorksAccountsBaselineProjection? baseline;
  final YorksAccountsProgressProjection? progress;
  final YorksAccountsProgressRevisionProjection? revisionHistory;
  final YorksV1DomainException? error;
  final bool isMutating;
  final bool hasPendingCommand;

  bool get hasProtectedValues =>
      baseline?.capabilities.canViewValues == true ||
      progress?.capabilities.canViewValues == true;

  YorksAccountsProjectState copyWith({
    YorksAccountsViewStatus? status,
    YorksAccountsBaselineProjection? baseline,
    YorksAccountsProgressProjection? progress,
    YorksAccountsProgressRevisionProjection? revisionHistory,
    YorksV1DomainException? error,
    bool? isMutating,
    bool? hasPendingCommand,
    bool clearBaseline = false,
    bool clearProgress = false,
    bool clearRevisionHistory = false,
    bool clearError = false,
  }) {
    return YorksAccountsProjectState(
      status: status ?? this.status,
      baseline: clearBaseline ? null : baseline ?? this.baseline,
      progress: clearProgress ? null : progress ?? this.progress,
      revisionHistory: clearRevisionHistory
          ? null
          : revisionHistory ?? this.revisionHistory,
      error: clearError ? null : error ?? this.error,
      isMutating: isMutating ?? this.isMutating,
      hasPendingCommand: hasPendingCommand ?? this.hasPendingCommand,
    );
  }

  YorksAccountsProjectState withoutProtectedValues({
    YorksAccountsViewStatus? status,
    YorksV1DomainException? error,
  }) {
    return YorksAccountsProjectState(
      status: status ?? this.status,
      baseline: baseline?.withoutProtectedValues(),
      progress: progress?.withoutProtectedValues(),
      revisionHistory: null,
      error: error,
      isMutating: false,
      hasPendingCommand: hasPendingCommand,
    );
  }
}

/// R39 Accounts application boundary for one project.
///
/// Critical writes keep their key lease until a confirmed RPC response. A
/// network failure therefore enters [YorksAccountsViewStatus.uncertain] and a
/// retry of the same typed intent uses the same key/payload, allowing the
/// server's idempotency record to reconcile a lost response safely.
final class YorksAccountsProjectController
    extends StateNotifier<YorksAccountsProjectState> {
  YorksAccountsProjectController({
    required String projectId,
    required YorksAccountsRepository repository,
    required YorksV1CriticalCommandKeyStore commandKeys,
  }) : _projectId = projectId.trim(),
       _repository = repository,
       _commandKeys = commandKeys,
       super(const YorksAccountsProjectState());

  final String _projectId;
  final YorksAccountsRepository _repository;
  final YorksV1CriticalCommandKeyStore _commandKeys;
  Future<YorksAccountsCommandResult?>? _inFlight;
  _PendingAccountsCommand? _pendingCommand;
  String? _buildingScopeId;
  String? _stageKey;
  String? _actionOwner;
  bool? _hasEvidence;

  /// Refresh the currently visible workbench, including its active filters.
  Future<bool> refresh() => load(
    buildingScopeId: _buildingScopeId,
    stageKey: _stageKey,
    actionOwner: _actionOwner,
    hasEvidence: _hasEvidence,
  );

  Future<bool> load({
    String? buildingScopeId,
    String? stageKey,
    String? actionOwner,
    bool? hasEvidence,
  }) async {
    _buildingScopeId = buildingScopeId;
    _stageKey = stageKey;
    _actionOwner = actionOwner;
    _hasEvidence = hasEvidence;
    state = state.copyWith(
      status: YorksAccountsViewStatus.loading,
      clearError: true,
    );
    try {
      var baseline = await _repository.getBaseline(_projectId);
      var progress = await _repository.listProgress(
        _projectId,
        buildingScopeId: buildingScopeId,
        stageKey: stageKey,
        actionOwner: actionOwner,
        hasEvidence: hasEvidence,
      );
      final baselineRevisionId = baseline.baseline?.revisionId;
      if (baselineRevisionId != progress.baselineRevisionId) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.unexpectedResponse,
        );
      }
      // A non-money engineering persona may legitimately receive both
      // projections without values and still retain suggest/confirm actions.
      // Only a mismatched downgrade across the two reads invalidates the
      // combined command surface; typed decoding already rejects money keys
      // in either no-value response.
      if (baseline.capabilities.canViewValues !=
          progress.capabilities.canViewValues) {
        baseline = baseline.withoutProtectedValues();
        progress = progress.withoutProtectedValues();
      }
      state = YorksAccountsProjectState(
        status: _pendingCommand == null
            ? YorksAccountsViewStatus.success
            : YorksAccountsViewStatus.uncertain,
        baseline: baseline,
        progress: progress,
        hasPendingCommand: _pendingCommand != null,
      );
      return true;
    } on YorksV1DomainException catch (error) {
      _setFailure(error, commandMayHaveCommitted: false);
      return false;
    } catch (error) {
      _setFailure(
        YorksV1DomainException(
          YorksV1DomainErrorCode.backendUnavailable,
          cause: error,
        ),
        commandMayHaveCommitted: false,
      );
      return false;
    }
  }

  Future<bool> loadRevisionHistory(
    String progressEntryId, {
    int? beforeRevisionNumber,
    int limit = 50,
  }) async {
    state = state.copyWith(
      status: YorksAccountsViewStatus.loading,
      clearError: true,
    );
    try {
      final history = await _repository.listProgressRevisions(
        _projectId,
        progressEntryId,
        beforeRevisionNumber: beforeRevisionNumber,
        limit: limit,
      );
      state = state.copyWith(
        status: YorksAccountsViewStatus.success,
        revisionHistory: history,
        clearError: true,
      );
      return true;
    } on YorksV1DomainException catch (error) {
      _setFailure(error, commandMayHaveCommitted: false);
      return false;
    } catch (error) {
      _setFailure(
        YorksV1DomainException(
          YorksV1DomainErrorCode.backendUnavailable,
          cause: error,
        ),
        commandMayHaveCommitted: false,
      );
      return false;
    }
  }

  Future<YorksAccountsCommandResult?> initializeBaseline(
    YorksAccountsBaselineInput input,
  ) {
    if (!_matchesProject(input.projectId)) {
      return _rejectProjectMismatch();
    }
    return _runCommand(
      operation: 'initialize_project_commercial_baseline',
      entityId: input.projectId,
      payload: input.idempotencyPayload(),
      invoke: (key) =>
          _repository.initializeBaseline(input, idempotencyKey: key),
    );
  }

  Future<YorksAccountsCommandResult?> reviseBaseline(
    YorksAccountsBaselineInput input,
  ) {
    if (!_matchesProject(input.projectId)) {
      return _rejectProjectMismatch();
    }
    return _runCommand(
      operation: 'revise_project_commercial_baseline',
      entityId: input.projectId,
      payload: input.idempotencyPayload(),
      invoke: (key) => _repository.reviseBaseline(input, idempotencyKey: key),
    );
  }

  Future<YorksAccountsCommandResult?> suggestProgress(
    YorksAccountsProgressInput input,
  ) {
    if (!_matchesProject(input.projectId)) {
      return _rejectProjectMismatch();
    }
    return _runCommand(
      operation: 'suggest_billing_progress',
      entityId: input.progressEntryId,
      payload: input.idempotencyPayload(),
      invoke: (key) => _repository.suggestProgress(input, idempotencyKey: key),
    );
  }

  Future<YorksAccountsCommandResult?> confirmProgress(
    YorksAccountsProgressInput input,
  ) {
    if (!_matchesProject(input.projectId)) {
      return _rejectProjectMismatch();
    }
    return _runCommand(
      operation: 'confirm_billing_progress',
      entityId: input.progressEntryId,
      payload: input.idempotencyPayload(),
      invoke: (key) => _repository.confirmProgress(input, idempotencyKey: key),
    );
  }

  Future<YorksAccountsCommandResult?> reviewProgress(
    YorksAccountsReviewInput input,
  ) {
    if (!_matchesProject(input.projectId)) {
      return _rejectProjectMismatch();
    }
    return _runCommand(
      operation: 'review_commercial_progress',
      entityId: input.progressEntryId,
      payload: input.idempotencyPayload(),
      invoke: (key) => _repository.reviewProgress(input, idempotencyKey: key),
    );
  }

  /// Explicitly removes every cached monetary value when a capability/session
  /// refresh revokes protected access. Provider recreation on role changes also
  /// starts from an empty state, so commercial data cannot cross identities.
  void purgeProtectedValues() {
    _pendingCommand = null;
    state = state.withoutProtectedValues().copyWith(hasPendingCommand: false);
  }

  bool _matchesProject(String inputProjectId) =>
      _projectId.isNotEmpty && inputProjectId.trim() == _projectId;

  Future<YorksAccountsCommandResult?> _rejectProjectMismatch() {
    _setFailure(
      const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput),
      commandMayHaveCommitted: false,
    );
    return Future<YorksAccountsCommandResult?>.value();
  }

  /// Replays the exact unresolved intent, never values from a reopened editor.
  Future<YorksAccountsCommandResult?> reconcilePendingCommand() {
    final pending = _pendingCommand;
    if (pending == null) return Future.value();
    return _runCommand(
      operation: pending.operation,
      entityId: pending.entityId,
      payload: pending.payload,
      invoke: pending.invoke,
    );
  }

  Future<YorksAccountsCommandResult?> _runCommand({
    required String operation,
    required String entityId,
    required Map<String, Object?> payload,
    required Future<YorksAccountsCommandResult> Function(String key) invoke,
  }) {
    // Set the single-flight guard before the first asynchronous key-store call.
    // A second click must not race acquire/confirm or generate a second key.
    if (_inFlight != null) return Future.value();
    final pending = _pendingCommand;
    if (pending != null && !pending.matches(operation, entityId, payload)) {
      return Future.value();
    }
    final intent =
        pending ??
        _PendingAccountsCommand(
          operation: operation,
          entityId: entityId,
          payload: payload,
          invoke: invoke,
        );
    final future = _executeCommand(intent);
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  Future<YorksAccountsCommandResult?> _executeCommand(
    _PendingAccountsCommand intent,
  ) async {
    state = state.copyWith(isMutating: true, clearError: true);
    try {
      final key = await _commandKeys.acquire(
        operation: intent.operation,
        entityId: intent.entityId,
        payload: intent.payload,
      );
      final result = await intent.invoke(key);
      await _commandKeys.confirm(
        operation: intent.operation,
        entityId: intent.entityId,
        idempotencyKey: key,
      );
      _pendingCommand = null;
      state = state.copyWith(
        isMutating: false,
        hasPendingCommand: false,
        clearError: true,
      );
      await refresh();
      return result;
    } on YorksV1DomainException catch (error) {
      if (error.code == YorksV1DomainErrorCode.backendUnavailable ||
          error.code == YorksV1DomainErrorCode.unexpectedResponse) {
        _pendingCommand = intent;
      } else if (error.code != YorksV1DomainErrorCode.offline) {
        _pendingCommand = null;
      }
      _setFailure(error, commandMayHaveCommitted: true);
      return null;
    } catch (error) {
      _pendingCommand = intent;
      _setFailure(
        YorksV1DomainException(
          YorksV1DomainErrorCode.backendUnavailable,
          cause: error,
        ),
        commandMayHaveCommitted: true,
      );
      return null;
    }
  }

  void _setFailure(
    YorksV1DomainException error, {
    required bool commandMayHaveCommitted,
  }) {
    final status = switch (error.code) {
      YorksV1DomainErrorCode.unauthorized => YorksAccountsViewStatus.forbidden,
      YorksV1DomainErrorCode.unauthenticated =>
        YorksAccountsViewStatus.sessionExpired,
      YorksV1DomainErrorCode.offline => YorksAccountsViewStatus.offline,
      YorksV1DomainErrorCode.conflict => YorksAccountsViewStatus.conflict,
      YorksV1DomainErrorCode.featureDisabled =>
        YorksAccountsViewStatus.unavailable,
      YorksV1DomainErrorCode.backendUnavailable ||
      YorksV1DomainErrorCode.unexpectedResponse when commandMayHaveCommitted =>
        YorksAccountsViewStatus.uncertain,
      _ => YorksAccountsViewStatus.failure,
    };
    if (status == YorksAccountsViewStatus.forbidden ||
        status == YorksAccountsViewStatus.sessionExpired ||
        status == YorksAccountsViewStatus.unavailable) {
      // These failures may mean the entire project/view scope was revoked, so
      // even non-money project and evidence metadata must leave memory.
      _pendingCommand = null;
      state = YorksAccountsProjectState(status: status, error: error);
      return;
    }
    state = state.copyWith(
      status: status,
      error: error,
      isMutating: false,
      hasPendingCommand: _pendingCommand != null,
    );
  }
}

final class _PendingAccountsCommand {
  _PendingAccountsCommand({
    required this.operation,
    required this.entityId,
    required Map<String, Object?> payload,
    required this.invoke,
  }) : payload = Map.unmodifiable(payload),
       fingerprint = jsonEncode(payload);

  final String operation;
  final String entityId;
  final Map<String, Object?> payload;
  final String fingerprint;
  final Future<YorksAccountsCommandResult> Function(String key) invoke;

  bool matches(
    String operation,
    String entityId,
    Map<String, Object?> payload,
  ) =>
      this.operation == operation &&
      this.entityId == entityId &&
      fingerprint == jsonEncode(payload);
}

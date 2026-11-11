import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/yorks_v1_domain_error.dart';
import '../models/analytics_event.dart';
import '../services/analytics_service.dart';
import '../models/yorks_v1_procurement_progress.dart';
import '../repositories/yorks_v1_procurement_progress_repository.dart';
import '../services/yorks_v1_procurement_recovery_store.dart';

enum YorksV1ProcurementCommandPhase {
  notSent,
  inFlight,
  unknown,
  confirmed,
  rejected,
  viewRefreshDegraded,
}

class YorksV1ProcurementProgressState {
  const YorksV1ProcurementProgressState({
    this.current,
    this.accepted,
    this.checkpoint,
    this.deviceRecovery,
    this.pendingCommand,
    this.outcome,
    this.error,
    this.recoveryError,
    this.isRetired = false,
    this.isLoading = false,
    this.isSaving = false,
    this.isChecking = false,
    this.isRecovering = false,
    this.commandPhase = YorksV1ProcurementCommandPhase.notSent,
    this.deviceSaved = false,
    this.needsRecoveryChoice = false,
    this.hasVersionConflict = false,
    this.recoveryCorrupt = false,
    this.accountRevision = 0,
  });
  final YorksV1ProcurementProgressDraft? current;
  final YorksV1ProcurementProgressDraft? accepted;
  final YorksV1ProcurementProgressCheckpoint? checkpoint;
  final YorksV1ProcurementRecovery? deviceRecovery;
  final YorksV1ProcurementPendingCommand? pendingCommand;
  final YorksV1ProcurementCommandOutcome? outcome;
  final Object? error;
  final Object? recoveryError;
  final bool isRetired,
      isLoading,
      isSaving,
      isChecking,
      isRecovering,
      deviceSaved;
  final YorksV1ProcurementCommandPhase commandPhase;
  bool get automaticCheckExhausted =>
      (pendingCommand?.automaticChecks ?? 0) >= 4 ||
      outcome?.automaticChecksRemaining == 0;
  final bool needsRecoveryChoice, hasVersionConflict, recoveryCorrupt;
  final int accountRevision;
  bool get isDirty =>
      current != null && current!.fingerprint != accepted?.fingerprint;
  bool get hasUnsavedCommercialChanges =>
      current != null &&
      current!.commercialFingerprint != accepted?.commercialFingerprint;
  bool get isPending =>
      pendingCommand != null &&
      outcome?.isConfirmed != true &&
      outcome?.status != 'rejected';
  bool get canEdit =>
      current != null &&
      !isRetired &&
      !isLoading &&
      pendingCommand == null &&
      !needsRecoveryChoice &&
      !hasVersionConflict;
}

/// Shared desktop/mobile editor persistence. It never commits workflow or stock.
/// The widget initializes only after an authorized live workspace is available.
class YorksV1ProcurementProgressController extends ChangeNotifier {
  YorksV1ProcurementProgressController({
    required YorksV1ProcurementProgressRepository repository,
    required YorksV1ProcurementRecoveryStore recoveryStore,
    required YorksV1ProcurementProgressScope scope,
    Duration debounce = const Duration(milliseconds: 500),
    String Function()? uuidFactory,
    AnalyticsService analytics = const NoopAnalyticsService(),
    bool Function()? isOnline,
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
  }) : _analytics = analytics,
       _repository = repository,
       _recoveryStore = recoveryStore,
       _scope = scope,
       _debounce = debounce,
       _uuid = uuidFactory ?? const Uuid().v4,
       _isOnline = isOnline ?? (() => true),
       _now = now ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed;

  final AnalyticsService _analytics;
  final YorksV1ProcurementProgressRepository _repository;
  final YorksV1ProcurementRecoveryStore _recoveryStore;
  final YorksV1ProcurementProgressScope _scope;
  final Duration _debounce;
  final String Function() _uuid;
  final bool Function() _isOnline;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;
  Future<YorksV1ProcurementCommandOutcome?>? _checkFuture;
  Future<void>? _automaticFuture;
  bool _recovering = false;
  int _resolutionEpoch = 0;
  YorksV1ProcurementCommandPhase _commandPhase =
      YorksV1ProcurementCommandPhase.notSent;
  YorksV1ProcurementProgressDraft? _initial, _current, _accepted;
  YorksV1ProcurementProgressCheckpoint? _checkpoint;
  YorksV1ProcurementRecovery? _deviceRecovery;
  YorksV1ProcurementPendingCommand? _pending;
  YorksV1ProcurementCommandOutcome? _outcome;
  Object? _error, _recoveryError;
  bool _loading = false, _saving = false, _checking = false;
  bool _deviceSaved = false,
      _choice = false,
      _conflict = false,
      _corrupt = false;
  bool _disposed = false, _retired = false;
  int _generation = 0, _accountRevision = 0, _lifecycle = 0;
  Timer? _timer;
  Future<void> _recoveryTail = Future<void>.value();
  String? _saveKey, _saveFingerprint;
  Map<String, Object?>? _frozenPayload;

  YorksV1ProcurementProgressState get state => YorksV1ProcurementProgressState(
    current: _current,
    accepted: _accepted,
    checkpoint: _checkpoint,
    deviceRecovery: _deviceRecovery,
    pendingCommand: _pending,
    outcome: _outcome,
    error: _error,
    recoveryError: _recoveryError,
    isRetired: _retired,
    isLoading: _loading,
    isSaving: _saving,
    isChecking: _checking,
    isRecovering: _recovering,
    commandPhase: _commandPhase,
    deviceSaved: _deviceSaved,
    needsRecoveryChoice: _choice,
    hasVersionConflict: _conflict,
    recoveryCorrupt: _corrupt,
    accountRevision: _accountRevision,
  );

  /// Only exists in memory; never copied into device recovery.
  Map<String, Object?>? get pendingCommandPayload => _frozenPayload;

  Future<void> initialize(YorksV1ProcurementProgressDraft initial) async {
    if (_initial != null) return;
    _checkScope(initial);
    _retired = false;
    _initial = _current = _accepted = initial;
    _loading = true;
    _notify();
    final lifecycle = _lifecycle;
    final authorityEpoch = _resolutionEpoch;
    try {
      final local = await _recoveryStore.load(_scope);
      if (!_alive(lifecycle)) return;
      _corrupt = local.isCorrupt;
      _deviceRecovery = local.recovery;
      _pending = local.recovery?.pendingCommand;
      final remote = await _repository.get(_scope);
      if (!_alive(lifecycle)) return;
      _accountRevision = remote.revision;
      _checkpoint = authorityEpoch == _resolutionEpoch
          ? remote.checkpoint
          : null;
      final remotePending = remote.pendingCommand;
      if (remotePending != null) {
        // Account hydration must not reset a device's consumed retry budget.
        if (_pending?.commandKey == remotePending.commandKey) {
          _pending = YorksV1ProcurementPendingCommand(
            attemptId: remotePending.attemptId,
            commandName: remotePending.commandName,
            commandKey: remotePending.commandKey,
            automaticChecks:
                _pending!.automaticChecks > remotePending.automaticChecks
                ? _pending!.automaticChecks
                : remotePending.automaticChecks,
            automaticCheckAfter:
                _pending!.automaticCheckAfter != null &&
                    (remotePending.automaticCheckAfter == null ||
                        _pending!.automaticCheckAfter!.isAfter(
                          remotePending.automaticCheckAfter!,
                        ))
                ? _pending!.automaticCheckAfter
                : remotePending.automaticCheckAfter,
          );
        } else {
          _pending = remotePending;
        }
      }
      if (_pending != null) {
        _commandPhase = YorksV1ProcurementCommandPhase.unknown;
      }
      final account = authorityEpoch == _resolutionEpoch
          ? remote.checkpoint?.draft
          : remote.checkpoint?.draft.withoutCommercial();
      if (account != null) {
        if (!initial.hasSameBase(account)) {
          _conflict = true;
        } else {
          _current = _accepted = account;
        }
      }
      final recovery = local.recovery;
      if (recovery != null) {
        final sameBase = initial.hasSameBase(recovery.draft);
        final sameAccount = recovery.accountRevision == remote.revision;
        final sameContent =
            recovery.draft.operationalFingerprint ==
            (_current ?? initial).operationalFingerprint;
        if (!sameBase || (!sameAccount && !sameContent)) {
          _choice = true;
          _conflict = !sameBase;
        } else if (!sameContent) {
          _choice = true;
        } else {
          _deviceSaved = true;
        }
      }
    } catch (error) {
      if (!_alive(lifecycle)) return;
      _error = error;
      if (_isDenied(error)) {
        await revoke();
        return;
      }
      // An account lookup failure cannot imply that a device copy is newer.
      _choice = _deviceRecovery != null;
      if (_deviceRecovery != null &&
          !initial.hasSameBase(_deviceRecovery!.draft)) {
        _conflict = true;
      }
    } finally {
      if (_alive(lifecycle)) {
        _loading = false;
        _notify();
      }
    }
    if (_alive(lifecycle) && _pending != null) await recoverPendingCommand();
  }

  void observeLiveVersions({
    required int requestVersion,
    int? arrangementVersion,
  }) {
    if (_initial != null &&
        (_initial!.baseRequestVersion != requestVersion ||
            _initial!.baseArrangementVersion != arrangementVersion)) {
      _conflict = true;
      _notify();
    }
  }

  void observeLiveBase(YorksV1ProcurementProgressDraft latest) {
    _checkScope(latest);
    if (_initial != null && !_initial!.hasSameBase(latest)) {
      _conflict = true;
      _notify();
    }
  }

  /// Explicit reload after the caller resolves/discards changes. A refresh
  /// cannot silently replace the base of an edited or pending submission.
  Future<void> reload(YorksV1ProcurementProgressDraft latest) async {
    _checkScope(latest);
    if (state.isDirty || state.isPending || _saving || _loading) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.conflict);
    }
    _lifecycle++;
    _timer?.cancel();
    await _recoveryTail;
    _initial = _current = _accepted = null;
    _checkpoint = null;
    _deviceRecovery = null;
    _outcome = null;
    _error = _recoveryError = null;
    _choice = _conflict = _corrupt = _deviceSaved = false;
    await initialize(latest);
  }

  void update(YorksV1ProcurementProgressDraft draft) {
    _checkScope(draft);
    if (_disposed || _initial == null || !state.canEdit) return;
    if (!_initial!.hasSameBase(draft)) {
      _conflict = true;
      _notify();
      return;
    }
    if (_current?.fingerprint == draft.fingerprint) return;
    _current = draft;
    _generation++;
    _deviceSaved = false;
    _error = null;
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      unawaited(flushRecovery());
    });
    _notify();
  }

  Future<bool> flushRecovery({bool forPendingCommand = false}) async {
    _timer?.cancel();
    // Retry metadata may advance without choosing/overwriting a newer device
    // draft. Its operational inputs stay at the preserved recovery boundary.
    final draft = forPendingCommand && _choice
        ? _deviceRecovery?.draft ?? _current
        : _current;
    if (draft == null ||
        _disposed ||
        _retired ||
        (_choice && !forPendingCommand) ||
        _corrupt) {
      return false;
    }
    final generation = _generation;
    final lifecycle = _lifecycle;
    final revision = _accountRevision;
    final pending = _pending;
    var succeeded = false;
    final next = _recoveryTail.then((_) async {
      if (!_alive(lifecycle)) return;
      try {
        await _recoveryStore.save(
          draft: draft,
          accountRevision: revision,
          generation: generation,
          pendingCommand: pending,
        );
        succeeded = true;
        if (_alive(lifecycle) && generation == _generation) {
          _deviceSaved = true;
          _recoveryError = null;
          _notify();
        }
      } catch (error) {
        if (_alive(lifecycle)) {
          _recoveryError = error;
          _deviceSaved = false;
          _notify();
        }
      }
    });
    _recoveryTail = next;
    await next;
    return succeeded;
  }

  Future<bool> saveProgress() async {
    if (_disposed ||
        _retired ||
        _saving ||
        _loading ||
        _current == null ||
        _choice ||
        _conflict ||
        state.isPending) {
      return false;
    }
    final snapshot = _current!;
    final fingerprint = '$_accountRevision:${snapshot.fingerprint}';
    if (_saveFingerprint != fingerprint) {
      _saveKey = _uuid();
      _saveFingerprint = fingerprint;
    }
    final stopwatch = Stopwatch()..start();
    final lifecycle = _lifecycle;
    final authorityEpoch = _resolutionEpoch;
    _saving = true;
    _error = null;
    _notify();
    try {
      final saved = await _repository.save(
        draft: snapshot,
        expectedRevision: _accountRevision,
        idempotencyKey: _saveKey!,
      );
      if (!_alive(lifecycle)) return false;
      if (saved.draft.scope != _scope || !snapshot.hasSameBase(saved.draft)) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.unexpectedResponse,
        );
      }
      _checkpoint = authorityEpoch == _resolutionEpoch ? saved : null;
      _accountRevision = saved.revision;
      // The acknowledged boundary is the submitted snapshot, never late edits.
      // A late response cannot restore commercial data after authority changed.
      _accepted = authorityEpoch == _resolutionEpoch
          ? snapshot
          : snapshot.withoutCommercial();
      _saveKey = _saveFingerprint = null;
      await flushRecovery();
      _analytics.capture(
        AnalyticsEvent.procurementProgressSaved,
        properties: {
          AnalyticsProperty.mode: _scope.editorKind.name,
          AnalyticsProperty.itemCount:
              (snapshot.inputs['lines'] as List).length,
          AnalyticsProperty.durationMs: stopwatch.elapsedMilliseconds,
        },
      );
      return true;
    } catch (error) {
      _analytics.capture(
        AnalyticsEvent.procurementProgressFailed,
        properties: {
          AnalyticsProperty.mode: _scope.editorKind.name,
          AnalyticsProperty.errorCategory: error is YorksV1DomainException
              ? error.code.name
              : 'unavailable',
        },
      );
      if (_alive(lifecycle)) {
        _error = error;
        if (_isDenied(error)) {
          await revoke();
          return false;
        }
        if (error is YorksV1DomainException &&
            error.code == YorksV1DomainErrorCode.conflict) {
          _conflict = true;
        }
      }
      return false;
    } finally {
      if (_alive(lifecycle)) {
        _saving = false;
        _notify();
      }
    }
  }

  void acceptDeviceRecovery() {
    final recovery = _deviceRecovery;
    if (recovery == null ||
        _initial == null ||
        _pending != null ||
        !recovery.draft.hasSameBase(_initial!)) {
      return;
    }
    // Device recovery does not have costs. Preserve only the current authorized
    // account cost checkpoint; the UI must explain unsaved costs were excluded.
    _current = YorksV1ProcurementProgressDraft.fromJson({
      ...recovery.draft.toJson(includeCommercial: false),
      if (_accepted?.commercialInputs != null)
        'commercial_inputs': _accepted!.commercialInputs,
    });
    _analytics.capture(
      AnalyticsEvent.procurementProgressRestored,
      properties: {
        AnalyticsProperty.mode: _scope.editorKind.name,
        AnalyticsProperty.storageScope: 'device',
      },
    );
    _generation++;
    _choice = false;
    _conflict = false;
    _deviceSaved = true;
    _notify();
  }

  /// Deliberate choice; this never silently rebases an obsolete checkpoint.
  void useAccountProgress() {
    if (_initial == null || _pending != null) return;
    final account = _checkpoint?.draft;
    if (account != null && !account.hasSameBase(_initial!)) return;
    _current = _accepted = account ?? _initial;
    _generation++;
    _choice = false;
    _conflict = false;
    _deviceSaved = false;
    _notify();
    unawaited(flushRecovery());
  }

  Future<void> discardChanges() async {
    if (_saving || state.isPending || _disposed) return;
    _current = _accepted;
    _generation++;
    _choice = false;
    _error = null;
    _notify();
    await flushRecovery();
  }

  Future<bool> discardSavedProgress() async {
    if (_saving || state.isPending || _disposed) return false;
    _saving = true;
    _timer?.cancel();
    final lifecycle = _lifecycle;
    _notify();
    try {
      final revision = await _repository.discard(
        scope: _scope,
        expectedRevision: _accountRevision,
        idempotencyKey: _uuid(),
      );
      if (!_alive(lifecycle)) return false;
      await _recoveryTail;
      await _recoveryStore.clear(_scope);
      if (!_alive(lifecycle)) return false;
      _accountRevision = revision;
      _checkpoint = null;
      _current = _accepted = _initial;
      _deviceRecovery = null;
      _choice = _conflict = _corrupt = _deviceSaved = false;
      _error = _recoveryError = null;
      _generation++;
      return true;
    } catch (error) {
      if (_alive(lifecycle)) _error = error;
      return false;
    } finally {
      if (_alive(lifecycle)) {
        _saving = false;
        _notify();
      }
    }
  }

  /// Called after the existing workflow controller acquires its durable key,
  /// but before it invokes the final RPC. A failed checkpoint/prepare blocks it.
  Future<void> prepareFinalIntent({
    required String commandName,
    required String commandKey,
    required Map<String, Object?> commandPayload,
  }) async {
    if (_disposed || _retired || _initial == null) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.unauthorized);
    }
    final lifecycle = _lifecycle;
    final authorityEpoch = _resolutionEpoch;
    if (_pending != null) {
      if (_pending!.commandName == commandName &&
          _pending!.commandKey == commandKey) {
        return;
      }
      throw const YorksV1DomainException(YorksV1DomainErrorCode.conflict);
    }
    final snapshotFingerprint = _current?.fingerprint;
    if (!await saveProgress()) {
      throw _error ??
          const YorksV1DomainException(YorksV1DomainErrorCode.conflict);
    }
    if (!_alive(lifecycle) || authorityEpoch != _resolutionEpoch) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.unauthorized);
    }
    if (_current?.fingerprint != snapshotFingerprint) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.conflict);
    }
    // Freeze the known key before preparation so a lost prepare response is
    // recoverable as an uncertain attempt rather than editable untracked work.
    _pending = YorksV1ProcurementPendingCommand(
      attemptId: '',
      commandName: commandName,
      commandKey: commandKey,
    );
    final frozenPayload = YorksV1ProcurementPendingCommand.freezePayload(
      commandPayload,
    );
    _frozenPayload = frozenPayload;
    _notify();
    await flushRecovery();
    final prepared = await _repository.prepare(
      scope: _scope,
      checkpointRevision: _accountRevision,
      commandName: commandName,
      commandKey: commandKey,
      commandPayload: frozenPayload,
      idempotencyKey: commandKey,
    );
    if (!_alive(lifecycle) || authorityEpoch != _resolutionEpoch) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.unauthorized);
    }
    _pending = prepared;
    _frozenPayload = frozenPayload;
    _outcome = null;
    _notify();
    // Protected server preparation is durable even if local storage fails.
    await flushRecovery();
  }

  /// Single-flight status reads are fenced by command identity and lifecycle.
  Future<YorksV1ProcurementCommandOutcome?> checkCommandStatus({
    bool automatic = false,
  }) {
    if (_outcome?.isConfirmed == true) return Future.value(_outcome);
    if (_checkFuture != null) return _checkFuture!;
    if (_pending == null || _disposed) return Future.value(_outcome);
    final future = _checkCommandStatus(automatic: automatic);
    _checkFuture = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_checkFuture, future)) _checkFuture = null;
      }),
    );
    return future;
  }

  Future<YorksV1ProcurementCommandOutcome?> _checkCommandStatus({
    required bool automatic,
  }) async {
    final pending = _pending!;
    final lifecycle = _lifecycle;
    final epoch = _resolutionEpoch;
    _checking = true;
    _notify();
    try {
      final result = await _repository.outcome(
        requestId: _scope.requestId,
        commandName: pending.commandName,
        commandKey: pending.commandKey,
        automatic: automatic,
      );
      if (!_alive(lifecycle) ||
          epoch != _resolutionEpoch ||
          _pending?.commandKey != pending.commandKey) {
        return _outcome;
      }
      _outcome = result;
      _commandPhase = result.isConfirmed
          ? YorksV1ProcurementCommandPhase.confirmed
          : result.status == 'rejected' || result.status == 'abandoned'
          ? YorksV1ProcurementCommandPhase.rejected
          : YorksV1ProcurementCommandPhase.unknown;
      _analytics.capture(
        AnalyticsEvent.procurementCommandReconciled,
        properties: {
          AnalyticsProperty.mode: _scope.editorKind.name,
          AnalyticsProperty.outcome: result.status,
        },
      );
      _analytics.capture(
        AnalyticsEvent.commandOutcomeChanged,
        properties: {
          AnalyticsProperty.operation: pending.commandName,
          AnalyticsProperty.commandFingerprint: analyticsCommandFingerprint(
            pending.commandName,
            pending.commandKey,
          ),
          AnalyticsProperty.commandPhase: 'reconciliation',
          AnalyticsProperty.outcome: result.isConfirmed
              ? 'confirmed'
              : 'unknown',
        },
      );
      _frozenPayload = result.isAccessChanged
          ? null
          : result.commandPayload == null
          ? _frozenPayload
          : YorksV1ProcurementPendingCommand.freezePayload(
              result.commandPayload!,
            );
      if (result.isAccessChanged) {
        _current = _current?.withoutCommercial();
        _accepted = _accepted?.withoutCommercial();
        _checkpoint = null;
      }
      _error = null;
      return result;
    } catch (error) {
      if (_alive(lifecycle) &&
          epoch == _resolutionEpoch &&
          _pending?.commandKey == pending.commandKey &&
          _outcome?.isConfirmed != true) {
        _error = error;
        _commandPhase = YorksV1ProcurementCommandPhase.unknown;
        if (error is YorksV1DomainException &&
            error.code == YorksV1DomainErrorCode.unauthenticated) {
          // Auth refresh is separate from command truth. Actual account/role
          // loss is revoked by the provider; retain this actor's opaque intent.
          clearCommercialInputs();
        } else if (_isDenied(error)) {
          await revoke();
        }
      }
      return _outcome;
    } finally {
      if (_alive(lifecycle)) {
        _checking = false;
        _notify();
      }
    }
  }

  /// Automatic reads never replay a write. Both the saved device budget and
  /// the server intent budget survive reconnects, reloads and competing tabs.
  Future<void> recoverPendingCommand() {
    if (_automaticFuture != null) return _automaticFuture!;
    if (_pending == null ||
        _disposed ||
        _retired ||
        _outcome?.isConfirmed == true) {
      return Future.value();
    }
    final future = _recoverPendingCommand();
    _automaticFuture = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_automaticFuture, future)) _automaticFuture = null;
      }),
    );
    return future;
  }

  Future<void> _recoverPendingCommand() async {
    final lifecycle = _lifecycle;
    final commandKey = _pending!.commandKey;
    _recovering = true;
    _commandPhase = YorksV1ProcurementCommandPhase.unknown;
    _notify();
    try {
      while (_alive(lifecycle) &&
          !_retired &&
          _pending?.commandKey == commandKey &&
          _outcome?.isConfirmed != true &&
          _outcome?.status != 'rejected' &&
          _outcome?.status != 'abandoned' &&
          _outcome?.isAccessChanged != true &&
          !state.automaticCheckExhausted &&
          _isOnline()) {
        final after = _pending!.automaticCheckAfter;
        final remaining = after?.difference(_now()) ?? Duration.zero;
        // A device clock jump or stale timestamp must not create an unbounded
        // background timer. The server still enforces the actual backoff.
        final wait = remaining > const Duration(seconds: 8)
            ? const Duration(seconds: 8)
            : remaining;
        if (wait > Duration.zero) await _delay(wait);
        if (!_alive(lifecycle) ||
            _retired ||
            !_isOnline() ||
            _pending?.commandKey != commandKey ||
            _outcome?.isConfirmed == true) {
          break;
        }
        final checks = _pending!.automaticChecks;
        _pending = _pending!.withAutomaticCheck(
          _now().add(Duration(seconds: 1 << checks)),
        );
        // This metadata contains no payload/costs. A failed local checkpoint
        // stops automatic polling rather than resetting its reload budget.
        if (!await flushRecovery(forPendingCommand: true) && !_corrupt) break;
        final result = await checkCommandStatus(automatic: true);
        if (_error is YorksV1DomainException &&
            (_error as YorksV1DomainException).code ==
                YorksV1DomainErrorCode.unauthenticated) {
          break; // The auth-session listener resumes the remaining budget.
        }
        if (result?.retryAfter case final Duration delay
            when delay > Duration.zero) {
          if (_pending?.commandKey == commandKey) {
            final pending = _pending!;
            _pending = YorksV1ProcurementPendingCommand(
              attemptId: pending.attemptId,
              commandName: pending.commandName,
              commandKey: pending.commandKey,
              automaticChecks: pending.automaticChecks,
              automaticCheckAfter: _now().add(delay),
            );
            await flushRecovery(forPendingCommand: true);
          }
        }
      }
    } finally {
      if (_alive(lifecycle)) {
        _recovering = false;
        _notify();
      }
    }
  }

  void markFinalCommandSent() {
    if (_pending == null || _outcome?.isConfirmed == true) return;
    _commandPhase = YorksV1ProcurementCommandPhase.inFlight;
    _notify();
  }

  void markViewRefreshDegraded() {
    if (_outcome?.isConfirmed != true && !_retired) return;
    _commandPhase = YorksV1ProcurementCommandPhase.viewRefreshDegraded;
    _notify();
  }

  /// Only a definite server rejection may unlock a different final payload.
  /// A timeout, transport failure or lookup miss must remain frozen.
  Future<void> rejectFinalIntent(Object error) async {
    // A late transport failure may not erase a newer authoritative receipt.
    if (_disposed || _retired || _outcome?.isConfirmed == true) return;
    if (error is! YorksV1DomainException ||
        {
          YorksV1DomainErrorCode.backendUnavailable,
          YorksV1DomainErrorCode.offline,
          YorksV1DomainErrorCode.unexpectedResponse,
        }.contains(error.code)) {
      _error = error;
      _commandPhase = _pending == null
          ? YorksV1ProcurementCommandPhase.notSent
          : YorksV1ProcurementCommandPhase.unknown;
      _notify();
      if (_pending != null) await recoverPendingCommand();
      return;
    }
    _error = error;
    _commandPhase = YorksV1ProcurementCommandPhase.rejected;
    if (_pending != null) await resumeEditingAfterCheck();
    if (error.code == YorksV1DomainErrorCode.conflict) _conflict = true;
    _notify();
  }

  /// Explicit abandonment is server locked against an in-flight final command.
  /// It never assumes that a missing result means an earlier command failed.
  Future<bool> resumeEditingAfterCheck() async {
    final pending = _pending;
    if (pending == null || _checking || _disposed) return false;
    _checking = true;
    _notify();
    try {
      final result = await _repository.abandon(
        requestId: _scope.requestId,
        commandName: pending.commandName,
        commandKey: pending.commandKey,
      );
      if (_disposed) return false;
      if (result == 'confirmed') {
        _checking = false;
        await checkCommandStatus();
        return false;
      }
      _resolutionEpoch++;
      _pending = null;
      _frozenPayload = null;
      _outcome = null;
      await flushRecovery();
      return true;
    } catch (error) {
      if (!_disposed) _error = error;
      return false;
    } finally {
      if (!_disposed) {
        _checking = false;
        _notify();
      }
    }
  }

  /// Called only after the final command or authoritative readback confirms.
  Future<void> retireAfterCommit() async {
    if (_retired) return;
    _retired = true;
    _resolutionEpoch++;
    _commandPhase = YorksV1ProcurementCommandPhase.confirmed;
    _timer?.cancel();
    _pending = null;
    _frozenPayload = null;
    _accepted = _current;
    _generation++;
    await _recoveryTail;
    try {
      await _recoveryStore.clear(_scope);
    } catch (error) {
      _recoveryError = error;
    }
    _deviceSaved = false;
    _notify();
    // Cleanup is independent: a retained checkpoint can be resolved on reopen.
    // It must never turn confirmed workflow success into a retry invitation.
    try {
      _accountRevision = await _repository.discard(
        scope: _scope,
        expectedRevision: _accountRevision,
        idempotencyKey: _uuid(),
      );
      _checkpoint = null;
    } catch (error) {
      _recoveryError = error;
    }
    _notify();
  }

  /// Authorization loss clears protected memory before asynchronous cleanup.
  Future<void> revoke() async {
    _lifecycle++;
    _resolutionEpoch++;
    _timer?.cancel();
    _initial = _current = _accepted = null;
    _checkpoint = null;
    _deviceRecovery = null;
    _pending = null;
    _outcome = null;
    _frozenPayload = null;
    _loading = _saving = _checking = false;
    _choice = _conflict = _corrupt = _deviceSaved = false;
    _notify();
    await _recoveryTail;
    await _recoveryStore.clear(_scope);
  }

  /// Re-check authority after permission revision without replacing typed work.
  Future<void> revalidateAuthority() async {
    if (_initial == null || _disposed) return;
    final lifecycle = _lifecycle;
    try {
      await _repository.get(_scope);
    } catch (error) {
      if (_alive(lifecycle) && _isDenied(error)) await revoke();
    }
  }

  void clearCommercialInputs() {
    _resolutionEpoch++;
    _initial = _initial?.withoutCommercial();
    _current = _current?.withoutCommercial();
    _accepted = _accepted?.withoutCommercial();
    _checkpoint = null;
    _frozenPayload = null;
    _notify();
  }

  bool _isDenied(Object error) =>
      error is YorksV1DomainException &&
      (error.code == YorksV1DomainErrorCode.unauthorized ||
          error.code == YorksV1DomainErrorCode.unauthenticated);

  void _checkScope(YorksV1ProcurementProgressDraft draft) {
    if (draft.scope != _scope) throw ArgumentError('Progress scope mismatch');
  }

  bool _alive(int lifecycle) => !_disposed && lifecycle == _lifecycle;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _lifecycle++;
    _timer?.cancel();
    _initial = _current = _accepted = null;
    _checkpoint = null;
    _deviceRecovery = null;
    _frozenPayload = null;
    super.dispose();
  }
}

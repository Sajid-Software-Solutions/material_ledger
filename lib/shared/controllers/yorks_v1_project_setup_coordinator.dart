import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/analytics_event.dart';
import '../models/yorks_v1_document.dart';
import '../models/yorks_v1_domain_error.dart';
import '../models/yorks_v1_project.dart';
import '../models/yorks_v1_project_setup_operation.dart';
import '../repositories/yorks_v1_documents_repository.dart';
import '../repositories/yorks_v1_project_repository.dart';
import '../repositories/yorks_v1_project_setup_journal_store.dart';
import '../services/analytics_service.dart';

enum YorksV1ProjectSetupRecoveryError {
  journalUnavailable,
  changedUnresolvedIntent,
  recoveryBlocked,
  fileMismatch,
  retryLimit,
}

class YorksV1ProjectSetupRecoveryException implements Exception {
  const YorksV1ProjectSetupRecoveryException(this.code);
  final YorksV1ProjectSetupRecoveryError code;
}

class YorksV1ProjectSetupState {
  const YorksV1ProjectSetupState({
    this.operation,
    this.recoveryError,
    this.busy = false,
  });

  final YorksV1ProjectSetupOperation? operation;
  final YorksV1ProjectSetupRecoveryError? recoveryError;
  final bool busy;
  YorksV1Project? get project => operation?.project;
  bool get outcomeUncertain => operation?.hasUnresolvedCommand ?? false;
}

/// Explicit connected submission/reconciliation. Restoring the journal never
/// dispatches a command, and the editable proposal never becomes replay input.
class YorksV1ProjectSetupCoordinator
    extends StateNotifier<YorksV1ProjectSetupState> {
  YorksV1ProjectSetupCoordinator({
    required YorksV1ProjectSetupJournalStore store,
    required YorksV1ProjectReviewedCommandRepository repository,
    required String Function() keyFactory,
    AnalyticsService analytics = const NoopAnalyticsService(),
    int maxAttempts = 3,
    DateTime Function()? clock,
    Future<void> Function(Duration)? retryDelay,
    double Function()? retryRandom,
  }) : _store = store,
       _repository = repository,
       _keyFactory = keyFactory,
       _analytics = analytics,
       _maxAttempts = maxAttempts,
       _clock = clock ?? DateTime.now,
       _retryDelay = retryDelay ?? Future<void>.delayed,
       _retryRandom = retryRandom ?? Random().nextDouble,
       super(const YorksV1ProjectSetupState()) {
    try {
      state = YorksV1ProjectSetupState(operation: _store.read());
    } catch (_) {
      state = const YorksV1ProjectSetupState(
        recoveryError: YorksV1ProjectSetupRecoveryError.recoveryBlocked,
      );
    }
  }

  final YorksV1ProjectSetupJournalStore _store;
  final YorksV1ProjectReviewedCommandRepository _repository;
  final String Function() _keyFactory;
  final AnalyticsService _analytics;
  final int _maxAttempts;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _retryDelay;
  final double Function() _retryRandom;

  YorksV1ProjectSetupState get currentState => state;

  Future<YorksV1ProjectSetupOperation> prepareCreate(
    YorksV1ProjectCreationInput input, {
    List<YorksV1ProjectSetupFile> files = const [],
  }) {
    _validate(input.validate());
    return _prepare(
      mode: YorksV1ProjectSetupMode.create,
      kind: YorksV1ProjectSetupCommandKind.create,
      payload: input.toRpcPayload(),
      files: files,
    );
  }

  Future<YorksV1ProjectSetupOperation> prepareUpdate(
    YorksV1ProjectUpdateInput input, {
    List<YorksV1ProjectSetupFile> files = const [],
  }) {
    _validate(input.validate());
    return _prepare(
      mode: YorksV1ProjectSetupMode.edit,
      kind: YorksV1ProjectSetupCommandKind.update,
      payload: input.toRpcPayload(),
      files: files,
    );
  }

  Future<YorksV1ProjectSetupOperation> _prepare({
    required YorksV1ProjectSetupMode mode,
    required YorksV1ProjectSetupCommandKind kind,
    required Map<String, dynamic> payload,
    required List<YorksV1ProjectSetupFile> files,
  }) async {
    _requireRecoverable();
    final canonical = yorksV1CanonicalSetupJson(payload);
    return _persist((current) {
      if (current != null) {
        if (current.coreSucceeded) return current;
        if (current.core.status.unresolved &&
            current.core.canonicalPayload != canonical) {
          throw const YorksV1ProjectSetupRecoveryException(
            YorksV1ProjectSetupRecoveryError.changedUnresolvedIntent,
          );
        }
        if (current.core.canonicalPayload == canonical &&
            current.core.status !=
                YorksV1ProjectSetupCommandStatus.confirmedRejected) {
          return current;
        }
      }
      return YorksV1ProjectSetupOperation(
        backendIdentity: _store.backendIdentity,
        ownerAuthUserId: _store.ownerAuthUserId,
        draftId: _store.draftId,
        mode: mode,
        core: YorksV1ProjectSetupCommand(
          kind: kind,
          idempotencyKey: _keyFactory(),
          payload: payload,
        ),
        files: List.unmodifiable(files),
        revision: (current?.revision ?? 0) + 1,
      );
    });
  }

  /// No changed input is accepted here. An explicit retry always sends the
  /// original persisted payload, hash, key and expected version.
  Future<YorksV1Project> submitCore() => _execute(activation: false);

  Future<YorksV1Project> reconcileCore() => _execute(activation: false);

  Future<YorksV1Project> activate() async {
    _requireRecoverable();
    await _repairConfirmedReceipts();
    final current = state.operation;
    final project = current?.project;
    if (current == null || !current.coreSucceeded || project == null) {
      throw const YorksV1ProjectSetupRecoveryException(
        YorksV1ProjectSetupRecoveryError.recoveryBlocked,
      );
    }
    if (project.state != YorksV1ProjectLifecycle.draft) return project;
    if (current.activation == null) {
      await _persist((latest) {
        _requireSameCore(current, latest);
        return latest!.copyWith(
          activation: YorksV1ProjectSetupCommand(
            kind: YorksV1ProjectSetupCommandKind.activate,
            idempotencyKey: _keyFactory(),
            payload: YorksV1SetProjectStateInput(
              idempotencyKey: 'prepared',
              projectId: project.id,
              currentState: project.state,
              targetState: YorksV1ProjectLifecycle.active,
              expectedProjectVersion: project.recordVersion,
            ).toRpcPayload(),
          ),
          revision: latest.revision + 1,
        );
      });
    }
    return _execute(activation: true);
  }

  Future<YorksV1Project> _execute({required bool activation}) async {
    _requireRecoverable();
    if (state.busy) {
      throw const YorksV1ProjectSetupRecoveryException(
        YorksV1ProjectSetupRecoveryError.recoveryBlocked,
      );
    }
    final operation = state.operation!;
    var command = activation ? operation.activation! : operation.core;
    if (command.status == YorksV1ProjectSetupCommandStatus.confirmedSuccess) {
      try {
        await _repairConfirmedReceipts();
      } catch (_) {
        // The project is already confirmed. A failed repair prevents later
        // phase dispatch, while this successful core result stays visible.
        return command.project!;
      }
      if (!activation) await _captureCoreSuccessOnce();
      return command.project!;
    }
    if (command.status == YorksV1ProjectSetupCommandStatus.confirmedRejected) {
      throw YorksV1DomainException(
        command.errorCode ?? YorksV1DomainErrorCode.serverRejected,
      );
    }
    if (command.attempts >= _maxAttempts) {
      throw const YorksV1ProjectSetupRecoveryException(
        YorksV1ProjectSetupRecoveryError.retryLimit,
      );
    }
    final wasUnresolved = command.status.unresolved;
    late final YorksV1ProjectSetupCommand dispatched;
    state = YorksV1ProjectSetupState(operation: state.operation, busy: true);
    try {
      if (wasUnresolved && command.attempts > 0) {
        command = await _waitBeforeRetry(
          operation,
          command,
          activation: activation,
        );
      }
      dispatched = command.withOutcome(
        status: wasUnresolved
            ? YorksV1ProjectSetupCommandStatus.reconciling
            : YorksV1ProjectSetupCommandStatus.submitting,
        attempts: command.attempts + 1,
        // Persist before dispatch, including a crash before response handling.
        nextRetryAt: _clock().toUtc().add(_retryBackoff(command.attempts + 1)),
      );
      await _replaceCommand(operation, dispatched, activation: activation);
    } catch (_) {
      state = YorksV1ProjectSetupState(
        operation: state.operation,
        recoveryError: state.recoveryError,
      );
      rethrow;
    }
    try {
      final response = await _repository.executeReviewedCommand(dispatched);
      final confirmed = dispatched.withOutcome(
        status: YorksV1ProjectSetupCommandStatus.confirmedSuccess,
        result: response,
      );
      // Validate result before persisting a success marker.
      final project = confirmed.project!;
      // A server-confirmed result is kept in memory even if its local
      // acknowledgement fails. Reload then reconciles the prior intent.
      final confirmedOperation = activation
          ? state.operation!.copyWith(activation: confirmed)
          : state.operation!.copyWith(core: confirmed);
      state = YorksV1ProjectSetupState(
        operation: confirmedOperation,
        busy: true,
      );
      try {
        await _replaceCommand(operation, confirmed, activation: activation);
      } catch (_) {
        state = YorksV1ProjectSetupState(
          operation: confirmedOperation,
          recoveryError: YorksV1ProjectSetupRecoveryError.journalUnavailable,
        );
      }
      if (wasUnresolved) {
        _capture(
          AnalyticsEvent.projectCommandReconciled,
          dispatched.kind,
          outcome: 'confirmed',
        );
      }
      if (!activation) await _captureCoreSuccessOnce();
      return project;
    } on YorksV1ProjectCommandNotDispatchedException catch (failure) {
      await _recordFailure(
        operation,
        command.withOutcome(
          status: wasUnresolved
              ? YorksV1ProjectSetupCommandStatus.outcomeUncertain
              : YorksV1ProjectSetupCommandStatus.notSent,
          errorCode: failure.error.code,
        ),
        activation: activation,
      );
      throw failure.error;
    } on YorksV1DomainException catch (error) {
      final rejected = _definitive(error);
      // Reauthorization/schema checks may reject a retry before reaching the
      // original stored response. Such rejection cannot disprove an earlier
      // commit, so its previously unknown outcome must remain unresolved.
      final status = wasUnresolved
          ? YorksV1ProjectSetupCommandStatus.outcomeUncertain
          : error.code == YorksV1DomainErrorCode.offline
          ? YorksV1ProjectSetupCommandStatus.notSent
          : rejected
          ? YorksV1ProjectSetupCommandStatus.confirmedRejected
          : YorksV1ProjectSetupCommandStatus.outcomeUncertain;
      final failed = dispatched.withOutcome(
        status: status,
        attempts: !wasUnresolved && error.code == YorksV1DomainErrorCode.offline
            ? command.attempts
            : dispatched.attempts,
        errorCode: error.code,
        nextRetryAt: status == YorksV1ProjectSetupCommandStatus.outcomeUncertain
            ? _clock().toUtc().add(_retryBackoff(dispatched.attempts))
            : null,
      );
      await _recordFailure(operation, failed, activation: activation);
      if (status == YorksV1ProjectSetupCommandStatus.outcomeUncertain) {
        _capture(
          AnalyticsEvent.projectCommandOutcomeUncertain,
          dispatched.kind,
          error: error,
        );
      }
      rethrow;
    } catch (error) {
      final uncertain = dispatched.withOutcome(
        status: YorksV1ProjectSetupCommandStatus.outcomeUncertain,
        errorCode: YorksV1DomainErrorCode.backendUnavailable,
        nextRetryAt: _clock().toUtc().add(_retryBackoff(dispatched.attempts)),
      );
      await _recordFailure(operation, uncertain, activation: activation);
      _capture(
        AnalyticsEvent.projectCommandOutcomeUncertain,
        dispatched.kind,
        error: error,
      );
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    } finally {
      state = YorksV1ProjectSetupState(
        operation: state.operation,
        recoveryError: state.recoveryError,
      );
    }
  }

  Duration _retryBackoff(int attempts) => Duration(
    milliseconds:
        (500 *
                (1 << min(attempts - 1, 1)) *
                (1 + 0.5 * _retryRandom().clamp(0.0, 1.0)))
            .round(),
  );

  Future<YorksV1ProjectSetupCommand> _waitBeforeRetry(
    YorksV1ProjectSetupOperation operation,
    YorksV1ProjectSetupCommand command, {
    required bool activation,
  }) async {
    if (command.nextRetryAt == null) {
      // Backward-compatible journals receive one acknowledged schedule, so a
      // refresh cannot continually reset or bypass the reconciliation delay.
      command = command.withOutcome(
        status: command.status,
        nextRetryAt: _clock().toUtc().add(_retryBackoff(command.attempts)),
      );
      await _replaceCommand(operation, command, activation: activation);
    }
    final remaining = command.nextRetryAt!.difference(_clock().toUtc());
    if (remaining > Duration.zero) {
      // A changed device clock cannot turn this short wait into a long hang.
      await _retryDelay(
        remaining > const Duration(milliseconds: 1500)
            ? const Duration(milliseconds: 1500)
            : remaining,
      );
    }
    if (!mounted) {
      throw const YorksV1ProjectSetupRecoveryException(
        YorksV1ProjectSetupRecoveryError.recoveryBlocked,
      );
    }
    return command;
  }

  Future<void> _recordFailure(
    YorksV1ProjectSetupOperation operation,
    YorksV1ProjectSetupCommand command, {
    required bool activation,
  }) async {
    try {
      await _replaceCommand(operation, command, activation: activation);
    } catch (_) {
      final current = state.operation!;
      state = YorksV1ProjectSetupState(
        operation: activation
            ? current.copyWith(activation: command)
            : current.copyWith(core: command),
        recoveryError: YorksV1ProjectSetupRecoveryError.journalUnavailable,
      );
    }
  }

  Future<YorksV1ProjectSetupOperation> _replaceCommand(
    YorksV1ProjectSetupOperation original,
    YorksV1ProjectSetupCommand command, {
    required bool activation,
  }) => _persist((latest) {
    _requireSameCore(original, latest);
    final existing = activation ? latest!.activation : latest!.core;
    if (existing == null ||
        existing.idempotencyKey != command.idempotencyKey ||
        existing.canonicalPayload != command.canonicalPayload) {
      throw const YorksV1ProjectSetupRecoveryException(
        YorksV1ProjectSetupRecoveryError.changedUnresolvedIntent,
      );
    }
    if (existing.status == YorksV1ProjectSetupCommandStatus.confirmedSuccess) {
      return latest;
    }
    return latest.copyWith(
      core: activation ? null : command,
      activation: activation ? command : null,
      revision: latest.revision + 1,
    );
  });

  Future<void> uploadFile({
    required String localId,
    required Uint8List bytes,
    required YorksV1DocumentsRepository documents,
  }) async {
    _requireRecoverable();
    await _repairConfirmedReceipts();
    final current = state.operation!;
    final project = current.project;
    if (!current.coreSucceeded || project == null) {
      throw const YorksV1ProjectSetupRecoveryException(
        YorksV1ProjectSetupRecoveryError.recoveryBlocked,
      );
    }
    final file = current.files.singleWhere((file) => file.localId == localId);
    if (file.status == YorksV1ProjectSetupFileStatus.ready ||
        file.status == YorksV1ProjectSetupFileStatus.removed) {
      return;
    }
    final hash = sha256.convert(bytes).toString();
    if (bytes.length != file.sizeBytes ||
        (file.contentHash != null && file.contentHash != hash)) {
      throw const YorksV1ProjectSetupRecoveryException(
        YorksV1ProjectSetupRecoveryError.fileMismatch,
      );
    }
    final started = file.withOutcome(
      YorksV1ProjectSetupFileStatus.uploading,
      contentHash: hash,
    );
    // This acknowledgement precedes prepare/upload/finalize dispatch. Bytes
    // are deliberately not stored; reselection must reproduce this hash.
    await _replaceFile(current, started);
    try {
      await documents.upload(
        YorksV1DocumentUploadInput(
          projectId: project.id,
          entityType: YorksV1DocumentEntityType.project,
          entityId: project.id,
          classification: file.classification,
          fileName: file.fileName,
          mimeType: file.mimeType,
          bytes: bytes,
          idempotencyKey: file.idempotencyKey,
        ),
      );
      await _replaceFile(
        current,
        started.withOutcome(YorksV1ProjectSetupFileStatus.ready),
      );
    } catch (error) {
      final domain = error is YorksV1DomainException ? error : null;
      try {
        await _replaceFile(
          current,
          started.withOutcome(
            domain != null && _definitive(domain)
                ? YorksV1ProjectSetupFileStatus.failed
                : YorksV1ProjectSetupFileStatus.outcomeUncertain,
            errorCode:
                domain?.code ?? YorksV1DomainErrorCode.backendUnavailable,
          ),
        );
      } catch (_) {
        // The persisted uploading marker is sufficient to recover the same
        // key/hash. Never replace the known core success with a file error.
      }
      rethrow;
    }
  }

  Future<YorksV1ProjectSetupOperation> _replaceFile(
    YorksV1ProjectSetupOperation original,
    YorksV1ProjectSetupFile file,
  ) => _persist((latest) {
    _requireSameCore(original, latest);
    final previous = latest!.files.singleWhere(
      (item) => item.localId == file.localId,
    );
    if (previous.idempotencyKey != file.idempotencyKey ||
        (previous.contentHash != null &&
            previous.contentHash != file.contentHash)) {
      throw const YorksV1ProjectSetupRecoveryException(
        YorksV1ProjectSetupRecoveryError.fileMismatch,
      );
    }
    if (previous.status == YorksV1ProjectSetupFileStatus.ready) return latest;
    // A concurrent, explicitly removed never-dispatched file cannot be
    // resurrected by a stale selection or a delayed upload-start write.
    if (previous.status == YorksV1ProjectSetupFileStatus.removed) {
      throw const YorksV1ProjectSetupRecoveryException(
        YorksV1ProjectSetupRecoveryError.recoveryBlocked,
      );
    }
    return latest.copyWith(
      files: [
        for (final item in latest.files)
          if (item.localId == file.localId) file else item,
      ],
      revision: latest.revision + 1,
    );
  });

  /// Remove only optional work that never reached upload dispatch. The
  /// tombstone preserves the reviewed manifest; it never deletes a document.
  Future<void> removePendingFile(String localId) async {
    _requireRecoverable();
    await _repairConfirmedReceipts();
    final original = state.operation;
    if (original == null || !original.coreSucceeded) {
      throw const YorksV1ProjectSetupRecoveryException(
        YorksV1ProjectSetupRecoveryError.recoveryBlocked,
      );
    }
    await _persist((latest) {
      _requireSameCore(original, latest);
      final file = latest!.files.singleWhere((file) => file.localId == localId);
      if (file.status == YorksV1ProjectSetupFileStatus.removed) return latest;
      if (file.status != YorksV1ProjectSetupFileStatus.selected &&
          file.status != YorksV1ProjectSetupFileStatus.needsReselect) {
        throw const YorksV1ProjectSetupRecoveryException(
          YorksV1ProjectSetupRecoveryError.recoveryBlocked,
        );
      }
      return latest.copyWith(
        files: [
          for (final item in latest.files)
            if (item.localId == localId)
              item.withOutcome(YorksV1ProjectSetupFileStatus.removed)
            else
              item,
        ],
        revision: latest.revision + 1,
      );
    });
  }

  /// Housekeeping acknowledgement is independent from the server result.
  Future<YorksV1ProjectSetupOperation> acknowledgeConfirmedCore() async {
    _requireRecoverable();
    if (state.operation?.coreSucceeded != true || state.busy) {
      throw const YorksV1ProjectSetupRecoveryException(
        YorksV1ProjectSetupRecoveryError.recoveryBlocked,
      );
    }
    await _repairConfirmedReceipts();
    return state.operation!;
  }

  /// Housekeeping acknowledgement is independent from the server result.
  Future<void> markCleanupComplete() async {
    await _repairConfirmedReceipts();
    final original = state.operation!;
    if (!original.coreSucceeded) return;
    if (original.filesPending || original.hasUnresolvedCommand) {
      throw const YorksV1ProjectSetupRecoveryException(
        YorksV1ProjectSetupRecoveryError.recoveryBlocked,
      );
    }
    await _persist((latest) {
      _requireSameCore(original, latest);
      return latest!.copyWith(
        cleanupComplete: true,
        revision: latest.revision + 1,
      );
    });
  }

  /// Receiving a server result and acknowledging its journal write are
  /// independent. Repair the known receipt using its original key before
  /// starting any subsequent critical phase; never replay the core to do it.
  Future<void> _repairConfirmedReceipts() async {
    final known = state.operation;
    if (known == null || !known.coreSucceeded) return;
    final persisted = _store.read();
    final coreMatches =
        persisted?.core.canonicalResult == known.core.canonicalResult &&
        persisted?.coreSucceeded == true;
    final knownActivation = known.activation;
    final activationMatches =
        knownActivation?.status !=
            YorksV1ProjectSetupCommandStatus.confirmedSuccess ||
        persisted?.activation?.canonicalResult ==
            knownActivation?.canonicalResult;
    if (coreMatches && activationMatches && state.recoveryError == null) return;
    await _persist((latest) {
      _requireSameCore(known, latest);
      if (latest!.coreSucceeded &&
          latest.core.canonicalResult != known.core.canonicalResult) {
        throw const YorksV1ProjectSetupRecoveryException(
          YorksV1ProjectSetupRecoveryError.recoveryBlocked,
        );
      }
      var activation = latest.activation;
      if (knownActivation?.status ==
          YorksV1ProjectSetupCommandStatus.confirmedSuccess) {
        if (activation?.idempotencyKey != knownActivation!.idempotencyKey ||
            activation?.canonicalPayload != knownActivation.canonicalPayload) {
          throw const YorksV1ProjectSetupRecoveryException(
            YorksV1ProjectSetupRecoveryError.changedUnresolvedIntent,
          );
        }
        activation = knownActivation;
      }
      return latest.copyWith(
        core: known.core,
        activation: activation,
        revision: latest.revision + 1,
      );
    });
  }

  Future<void> _captureCoreSuccessOnce() async {
    final original = state.operation;
    if (original == null ||
        !original.coreSucceeded ||
        original.coreSuccessReported) {
      return;
    }
    var shouldCapture = false;
    try {
      await _persist((latest) {
        _requireSameCore(original, latest);
        if (!latest!.coreSucceeded) {
          throw const YorksV1ProjectSetupRecoveryException(
            YorksV1ProjectSetupRecoveryError.journalUnavailable,
          );
        }
        if (latest.coreSuccessReported) return latest;
        shouldCapture = true;
        return latest.copyWith(
          coreSuccessReported: true,
          revision: latest.revision + 1,
        );
      });
      if (!shouldCapture) return;
      final create = original.mode == YorksV1ProjectSetupMode.create;
      _analytics.capture(
        create ? AnalyticsEvent.projectCreated : AnalyticsEvent.projectUpdated,
        properties: create
            ? {
                AnalyticsProperty.buildingCount:
                    (original.core.payload['buildings'] as List).length,
                AnalyticsProperty.attachmentCount:
                    (original.core.payload['attachments'] as List).length,
              }
            : const {},
      );
    } catch (_) {
      // The marker is committed before emission, giving at-most-once counts.
      // Missing telemetry never changes a known business success.
    }
  }

  Future<void> captureKnownOutcome() async {
    final operation = state.operation;
    if (operation == null || !operation.coreSucceeded) return;
    final outcome = operation.filesPending
        ? 'saved_files_pending'
        : operation.mode == YorksV1ProjectSetupMode.edit
        ? 'updated'
        : operation.project?.state == YorksV1ProjectLifecycle.active
        ? 'active'
        : 'draft_pending_activation';
    if (operation.reportedOutcome == outcome) return;
    var shouldCapture = false;
    try {
      await _persist((latest) {
        _requireSameCore(operation, latest);
        if (latest!.reportedOutcome == outcome) return latest;
        shouldCapture = true;
        return latest.copyWith(
          reportedOutcome: outcome,
          revision: latest.revision + 1,
        );
      });
      if (!shouldCapture) return;
      _analytics.capture(
        AnalyticsEvent.projectSetupCompleted,
        properties: {
          AnalyticsProperty.mode: operation.mode.name,
          AnalyticsProperty.outcome: outcome,
        },
      );
    } catch (_) {
      // Telemetry is never part of the business commit outcome.
    }
  }

  Future<YorksV1ProjectSetupOperation> _persist(
    YorksV1ProjectSetupOperation Function(YorksV1ProjectSetupOperation?) change,
  ) async {
    try {
      final acknowledged = await _store.change(change);
      state = YorksV1ProjectSetupState(
        operation: acknowledged,
        busy: state.busy,
      );
      return acknowledged;
    } on YorksV1ProjectSetupRecoveryException {
      rethrow;
    } catch (_) {
      state = YorksV1ProjectSetupState(
        operation: state.operation,
        recoveryError: YorksV1ProjectSetupRecoveryError.journalUnavailable,
        busy: state.busy,
      );
      throw const YorksV1ProjectSetupRecoveryException(
        YorksV1ProjectSetupRecoveryError.journalUnavailable,
      );
    }
  }

  void _requireRecoverable() {
    if (state.recoveryError ==
        YorksV1ProjectSetupRecoveryError.recoveryBlocked) {
      throw const YorksV1ProjectSetupRecoveryException(
        YorksV1ProjectSetupRecoveryError.recoveryBlocked,
      );
    }
  }

  static void _requireSameCore(
    YorksV1ProjectSetupOperation original,
    YorksV1ProjectSetupOperation? current,
  ) {
    if (current == null ||
        original.core.idempotencyKey != current.core.idempotencyKey ||
        original.core.canonicalPayload != current.core.canonicalPayload) {
      throw const YorksV1ProjectSetupRecoveryException(
        YorksV1ProjectSetupRecoveryError.changedUnresolvedIntent,
      );
    }
  }

  static void _validate(Set<YorksV1ProjectValidationCode> errors) {
    if (errors.isNotEmpty) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
  }

  static bool _definitive(YorksV1DomainException error) => switch (error.code) {
    YorksV1DomainErrorCode.backendUnavailable ||
    YorksV1DomainErrorCode.unexpectedResponse => false,
    _ => error.serverCode != '55P03',
  };

  void _capture(
    AnalyticsEvent event,
    YorksV1ProjectSetupCommandKind kind, {
    String? outcome,
    Object? error,
  }) {
    final phase = switch (kind) {
      YorksV1ProjectSetupCommandKind.create => 'create',
      YorksV1ProjectSetupCommandKind.update => 'update',
      YorksV1ProjectSetupCommandKind.activate => 'activation',
    };
    try {
      _analytics.capture(
        event,
        properties: {
          AnalyticsProperty.operation: 'project_$phase',
          AnalyticsProperty.phase: phase,
          AnalyticsProperty.outcome: ?outcome,
          if (error != null)
            AnalyticsProperty.errorCategory: analyticsErrorCategory(error),
        },
      );
    } catch (_) {
      // Telemetry is never part of the business commit outcome.
    }
  }
}

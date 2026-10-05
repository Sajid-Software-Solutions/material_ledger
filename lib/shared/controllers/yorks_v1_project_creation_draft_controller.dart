import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/analytics_event.dart';
import '../models/yorks_v1_domain_error.dart';
import '../models/yorks_v1_project_creation_draft.dart';
import '../models/yorks_v1_project_setup_operation.dart';
import '../repositories/yorks_v1_project_creation_draft_catalogue.dart';
import '../repositories/yorks_v1_project_draft_store.dart';
import '../repositories/yorks_v1_project_setup_journal_store.dart';
import '../services/analytics_service.dart';

/// Complete local proposals, serialized acknowledgments and fenced ownership.
/// This controller never changes a live project or uploads selected file bytes.
class YorksV1ProjectCreationDraftController
    extends StateNotifier<YorksV1ProjectCreationDraft> {
  YorksV1ProjectCreationDraftController({
    required String ownerAuthUserId,
    required String backendIdentity,
    required this.storageKey,
    required ProjectDraftAtomicStorage storage,
    required String Function() idempotencyKeyFactory,
    YorksV1ProjectDraftMode mode = YorksV1ProjectDraftMode.create,
    String? projectId,
    String? legacyRaw,
    String? initialDraftId,
    bool requireExistingRecord = false,
    this.catalogue,
    String? journalScopeKey,
    AnalyticsService analytics = const NoopAnalyticsService(),
  }) : _ownerAuthUserId = ownerAuthUserId,
       _backendIdentity = backendIdentity,
       _storage = storage,
       _idempotencyKeyFactory = idempotencyKeyFactory,
       _writerId = idempotencyKeyFactory(),
       _analytics = analytics,
       _legacyRaw = legacyRaw,
       _selectedDraftId = initialDraftId,
       _requireExistingRecord = requireExistingRecord,
       journalScopeKey = journalScopeKey ?? storageKey,
       super(
         _restoreOrEmpty(
           ownerAuthUserId: ownerAuthUserId,
           backendIdentity: backendIdentity,
           mode: mode,
           projectId: projectId,
           storage: storage,
           storageKey: storageKey,
           idempotencyKeyFactory: idempotencyKeyFactory,
           legacyRaw: legacyRaw,
           initialDraftId: initialDraftId,
           requireExistingRecord: requireExistingRecord,
         ),
       ) {
    _initialization = _claim(
      legacyRaw: legacyRaw,
    ).whenComplete(() => _initializationComplete = true);
  }

  final String _ownerAuthUserId;
  final String _backendIdentity;
  final ProjectDraftAtomicStorage _storage;
  final String Function() _idempotencyKeyFactory;
  final String _writerId;
  final AnalyticsService _analytics;
  final String? _legacyRaw;
  final String? _selectedDraftId;
  final bool _requireExistingRecord;
  final YorksV1ProjectCreationDraftCatalogue? catalogue;
  final String storageKey;

  /// Original command journals and completed-project locators never move when
  /// the editable envelopes become individually addressable.
  final String journalScopeKey;
  String get _lockKey => catalogue?.scopeKey ?? storageKey;
  late final Future<void> _initialization;
  bool _initializationComplete = false;
  YorksV1ProjectCreationDraft? _pending;
  Future<void>? _draining;
  final List<({int revision, Completer<void> completion})> _waiters = [];
  bool _disposed = false;
  bool _reportedSaved = false;
  bool _ownershipClaimed = false;
  bool _resuming = false;
  Future<bool>? _resumeAcquisition;
  int? _attemptedResumeEpoch;

  Future<void> get initialized => _initialization;
  String get currentDraftId => state.draftId;

  bool get writable =>
      !state.isReadOnly &&
      !_resuming &&
      state.storageState != YorksV1ProjectDraftStorageState.initializing;
  bool get hasCrossProcessOwnership => _storage.supportsAtomicOwnership;

  static YorksV1ProjectCreationDraft _restoreOrEmpty({
    required String ownerAuthUserId,
    required String backendIdentity,
    required YorksV1ProjectDraftMode mode,
    required String? projectId,
    required ProjectDraftAtomicStorage storage,
    required String storageKey,
    required String Function() idempotencyKeyFactory,
    required String? legacyRaw,
    required String? initialDraftId,
    required bool requireExistingRecord,
  }) {
    final empty = YorksV1ProjectCreationDraft.empty(
      ownerAuthUserId: ownerAuthUserId,
      creationIdempotencyKey: idempotencyKeyFactory(),
      backendIdentity: backendIdentity,
      mode: mode,
      projectId: projectId,
    ).copyWith(draftId: initialDraftId);
    try {
      final raw = storage.read(storageKey);
      if (raw == null) {
        if (requireExistingRecord) {
          return empty.copyWith(
            storageState: YorksV1ProjectDraftStorageState.recoveryRequired,
          );
        }
        // Old keys contain no verified backend provenance. Preserve them for
        // explicit recovery; assigning them to the active backend could leak a
        // staging proposal into production.
        if (legacyRaw != null && legacyRaw.isNotEmpty && legacyRaw != '[]') {
          return empty.copyWith(
            storageState: YorksV1ProjectDraftStorageState.recoveryRequired,
          );
        }
        return empty.copyWith(
          storageState: YorksV1ProjectDraftStorageState.initializing,
        );
      }
      final record = _record(raw);
      if (record['retired'] == true) {
        if (requireExistingRecord || initialDraftId != null) {
          return empty.copyWith(
            storageState: YorksV1ProjectDraftStorageState.recoveryRequired,
          );
        }
        return empty.copyWith(
          writerEpoch: (record['writerEpoch'] as int? ?? 0) + 1,
          storageState: YorksV1ProjectDraftStorageState.initializing,
        );
      }
      final draft = _draftFromRecord(record);
      if (draft.ownerAuthUserId != ownerAuthUserId ||
          draft.backendIdentity != backendIdentity ||
          draft.mode != mode ||
          draft.projectId != projectId ||
          initialDraftId != null && draft.draftId != initialDraftId) {
        throw const FormatException('Project draft context mismatch');
      }
      return draft.copyWith(
        storageState: YorksV1ProjectDraftStorageState.initializing,
      );
    } catch (_) {
      return empty.copyWith(
        storageState: YorksV1ProjectDraftStorageState.recoveryRequired,
      );
    }
  }

  Future<void> _claim({
    String? legacyRaw,
    bool takeOver = false,
    bool recoveringFailedClaim = false,
  }) async {
    if (_disposed) return;
    void preserveProposal(
      ProjectDraftAtomicTransaction tx,
      YorksV1ProjectCreationDraft proposal,
      String reason,
    ) {
      tx.write(
        '$storageKey:quarantine:${proposal.draftId}:$_writerId',
        jsonEncode({
          'raw': _encodeRecord(proposal),
          'reason': reason,
          'ownerAuthUserId': _ownerAuthUserId,
          'backendIdentity': _backendIdentity,
          'capturedAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    }

    try {
      if (state.storageState ==
          YorksV1ProjectDraftStorageState.recoveryRequired) {
        await _storage.transaction(_lockKey, (tx) {
          final raw = tx.read(storageKey) ?? legacyRaw;
          if (raw != null) {
            // Raw data and the original key are retained. No parse/coercion is
            // attempted when its version or provenance is unsupported.
            tx.write(
              '$storageKey:quarantine',
              jsonEncode({
                'raw': raw,
                'ownerAuthUserId': _ownerAuthUserId,
                'backendIdentity': _backendIdentity,
                'capturedAt': DateTime.now().toUtc().toIso8601String(),
              }),
            );
          }
        });
        return;
      }
      final claimed = await _storage.transaction(_lockKey, (tx) {
        if (_disposed) {
          throw const ProjectDraftStorageException('controller_disposed');
        }
        final raw = tx.read(storageKey);
        if (_requireExistingRecord && raw == null) {
          throw const ProjectDraftStorageException('selected_draft_missing');
        }
        final record = raw == null ? <String, dynamic>{} : _record(raw);
        final retained = raw == null ? null : _draftFromRecord(record);
        if (_selectedDraftId != null &&
            retained != null &&
            !(recoveringFailedClaim && _pending != null) &&
            (retained.draftId != _selectedDraftId ||
                record['retired'] == true)) {
          throw const ProjectDraftStorageException('selected_draft_changed');
        }
        if (retained != null &&
            (retained.ownerAuthUserId != _ownerAuthUserId ||
                retained.backendIdentity != _backendIdentity ||
                retained.mode != state.mode ||
                retained.projectId != state.projectId)) {
          throw const FormatException('Project draft context mismatch');
        }
        final owner = record['ownerWriterId'] as String?;
        final epoch = record['writerEpoch'] as int? ?? 0;
        if (record['retired'] != true &&
            owner != null &&
            owner != _writerId &&
            !takeOver) {
          final hasUnpublishedRecovery =
              recoveringFailedClaim && _pending != null;
          final quarantineReason = hasUnpublishedRecovery
              ? 'owner_acquired_during_failed_claim'
              : null;
          if (hasUnpublishedRecovery) {
            preserveProposal(tx, state, quarantineReason!);
          }
          return (
            draft: hasUnpublishedRecovery ? state : retained!,
            acquired: false,
            recoveryRequired: false,
            quarantineReason: quarantineReason,
          );
        }
        if (recoveringFailedClaim &&
            _pending != null &&
            retained != null &&
            (record['retired'] == true ||
                retained.draftId != state.draftId ||
                retained.revision > state.acknowledgedRevision)) {
          // Storage may have changed while the initial read/claim was failing.
          // A proposal typed against that uncertain snapshot must not replace
          // a different or newer durable draft, or resurrect a retired result.
          // Keep both complete records for explicit recovery without taking
          // ownership or silently assigning one proposal to the other's ID.
          const quarantineReason = 'retained_draft_changed_during_failed_claim';
          preserveProposal(tx, state, quarantineReason);
          return (
            draft: state,
            acquired: false,
            recoveryRequired: true,
            quarantineReason: quarantineReason,
          );
        }
        // Initial restoration may race the previous owner's last save/release.
        // Every ownership acquisition reads the latest proposal under the lock.
        final latest = raw != null && record['retired'] != true
            ? _draftFromRecord(record)
            : state;
        final draft = latest.copyWith(writerEpoch: epoch + 1);
        // Index first: adapters acknowledge staged writes sequentially. A
        // failed first-envelope commit then leaves a discoverable recovery ID,
        // never an acknowledged but invisible proposal. Existing IDs/unknown
        // index fields are retained under this same owner/backend lock.
        if (storageKey != catalogue?.scopeKey) {
          catalogue?.register(tx, draft.draftId);
        }
        if (record['retired'] == true) {
          tx.write(
            '$storageKey:retired:${_draftFromRecord(record).draftId}',
            raw!,
          );
        }
        tx.write(storageKey, _encodeRecord(draft));
        return (
          draft: draft,
          acquired: true,
          recoveryRequired: false,
          quarantineReason: null,
        );
      });
      if (_disposed) return;
      if (!claimed.acquired) {
        _ownershipClaimed = false;
        var preserved = claimed.draft;
        final quarantineReason = claimed.quarantineReason;
        // Native storage acknowledges writes asynchronously. Input can advance
        // while an unpublished proposal is being quarantined. Preserve each
        // newer revision before publishing a read-only refusal, so the final
        // proposal and durable recovery record cannot fall back to older input.
        while (!_disposed &&
            quarantineReason != null &&
            (state.draftId != preserved.draftId ||
                state.revision != preserved.revision)) {
          preserved = await _storage.transaction(_lockKey, (tx) {
            if (_disposed) {
              throw const ProjectDraftStorageException('controller_disposed');
            }
            final proposal = state;
            preserveProposal(tx, proposal, quarantineReason);
            return proposal;
          });
        }
        if (_disposed) return;
        state = preserved.copyWith(
          storageState: claimed.recoveryRequired
              ? YorksV1ProjectDraftStorageState.recoveryRequired
              : YorksV1ProjectDraftStorageState.ownedElsewhere,
        );
        _capture(AnalyticsEvent.projectSetupConflictDetected, {
          AnalyticsProperty.mode: state.mode.name,
          AnalyticsProperty.conflictType: claimed.recoveryRequired
              ? 'stale_prerequisite'
              : 'local_owner',
        });
        return;
      }
      _ownershipClaimed = true;
      final changedWhileInitializing =
          !takeOver && state.revision > claimed.draft.revision;
      state = (changedWhileInitializing ? state : claimed.draft).copyWith(
        writerEpoch: claimed.draft.writerEpoch,
        storageState: changedWhileInitializing
            ? YorksV1ProjectDraftStorageState.dirty
            : (claimed.draft.acknowledgedRevision == claimed.draft.revision &&
                  claimed.draft.revision > 0)
            ? YorksV1ProjectDraftStorageState.saved
            : YorksV1ProjectDraftStorageState.dirty,
      );
      if (claimed.draft.hasRecoverableContent && !changedWhileInitializing) {
        _capture(AnalyticsEvent.projectDraftRestored, {
          AnalyticsProperty.mode: state.mode.name,
          AnalyticsProperty.source: 'device',
          AnalyticsProperty.step: _stepName(state.currentStage),
        });
      }
    } catch (_) {
      _ownershipClaimed = false;
      if (!_disposed) {
        state = state.copyWith(
          storageState: YorksV1ProjectDraftStorageState.failed,
        );
      }
    }
  }

  /// The same lock and fencing check can protect an operation journal write.
  /// The callback must remain synchronous and contain local operations only.
  Future<T> atomicOwned<T>(
    T Function(ProjectDraftAtomicTransaction tx) work,
  ) async {
    // Even awaiting an already-completed future yields. A callback invoked
    // before explicit Resume must retain its old fence through that yield.
    final invocationEpoch = _initializationComplete ? state.writerEpoch : null;
    final invocationDraftId = _initializationComplete ? state.draftId : null;
    await _initialization;
    final expectedEpoch = invocationEpoch ?? state.writerEpoch;
    final expectedDraftId = invocationDraftId ?? state.draftId;
    return _storage.transaction(_lockKey, (tx) {
      if (_disposed) {
        throw const ProjectDraftStorageException('controller_disposed');
      }
      final raw = tx.read(storageKey);
      if (raw == null) {
        throw const ProjectDraftStorageException('owner_missing');
      }
      final record = _record(raw);
      if (record['ownerWriterId'] != _writerId ||
          record['writerEpoch'] != expectedEpoch ||
          state.writerEpoch != expectedEpoch ||
          state.draftId != expectedDraftId ||
          record['retired'] == true ||
          _draftFromRecord(record).draftId != expectedDraftId) {
        if (!_disposed &&
            state.writerEpoch == expectedEpoch &&
            state.draftId == expectedDraftId) {
          state = state.copyWith(
            storageState: YorksV1ProjectDraftStorageState.ownedElsewhere,
          );
        }
        throw const ProjectDraftStorageException('writer_fenced');
      }
      if (storageKey != catalogue?.scopeKey) {
        catalogue?.register(tx, state.draftId);
      }
      return work(tx);
    });
  }

  Future<void> verifyOwnership() => atomicOwned((_) {});

  /// A deliberate selected Resume/Edit entry transfers this exact proposal's
  /// local writer lease. Rebuild, focus and ordinary retries never call this.
  /// The latest acknowledged snapshot is read under the existing root lock.
  Future<bool> resumeEditing({
    required String expectedDraftId,
    required bool Function() canAcquire,
  }) => _resume(
    expectedDraftId: expectedDraftId,
    canAcquire: canAcquire,
    transferOwnership: true,
  );

  /// Retry an uncertain acknowledgement without taking a lease from another
  /// writer. A partially committed grant can be recognized by its exact epoch.
  Future<bool> retryResumeOwnership({
    required String expectedDraftId,
    required bool Function() canAcquire,
  }) => _resume(
    expectedDraftId: expectedDraftId,
    canAcquire: canAcquire,
    transferOwnership: false,
  );

  Future<bool> _resume({
    required String expectedDraftId,
    required bool Function() canAcquire,
    required bool transferOwnership,
  }) {
    final current = _resumeAcquisition;
    if (current != null) return current;
    _resuming = true;
    final acquisition =
        _acquireResume(
          expectedDraftId: expectedDraftId,
          canAcquire: canAcquire,
          transferOwnership: transferOwnership,
        ).whenComplete(() {
          _resumeAcquisition = null;
          _resuming = false;
        });
    _resumeAcquisition = acquisition;
    return acquisition;
  }

  Future<bool> _acquireResume({
    required String expectedDraftId,
    required bool Function() canAcquire,
    required bool transferOwnership,
  }) async {
    await _initialization;
    // Finish an already queued save under its original fence. No stale buffer
    // may restart a drain after the selected latest snapshot is acquired.
    while (_draining != null) {
      try {
        await _draining;
      } catch (_) {
        // A failed buffer is retained below, never silently overwritten.
      }
    }
    if (_disposed) return false;
    final prior = state;
    final unacknowledged = prior.revision > prior.acknowledgedRevision;
    if (transferOwnership) _attemptedResumeEpoch = null;
    state = prior.copyWith(
      storageState: YorksV1ProjectDraftStorageState.initializing,
    );
    try {
      final claim = await _storage.transaction(_lockKey, (tx) {
        if (_disposed || !canAcquire()) {
          throw const ProjectDraftStorageException('resume_not_authorized');
        }
        void preserveUnacknowledged() {
          if (!unacknowledged) return;
          tx.write(
            '$storageKey:quarantine:${prior.draftId}:$_writerId',
            jsonEncode({
              'raw': _encodeRecord(prior),
              'reason': 'unacknowledged_input_before_explicit_resume',
              'ownerAuthUserId': _ownerAuthUserId,
              'backendIdentity': _backendIdentity,
              'capturedAt': DateTime.now().toUtc().toIso8601String(),
            }),
          );
        }

        final raw = tx.read(storageKey);
        Map<String, dynamic> record;
        YorksV1ProjectCreationDraft latest;
        try {
          if (raw == null) {
            throw const FormatException('Selected proposal missing');
          }
          record = _record(raw);
          latest = _draftFromRecord(record);
          if (!YorksV1ProjectCreationDraftCatalogue.validDraftId(
                expectedDraftId,
              ) ||
              expectedDraftId != prior.draftId ||
              _selectedDraftId != null && expectedDraftId != _selectedDraftId ||
              latest.draftId != expectedDraftId ||
              latest.ownerAuthUserId != _ownerAuthUserId ||
              latest.backendIdentity != _backendIdentity ||
              latest.mode != prior.mode ||
              latest.projectId != prior.projectId ||
              latest.creationIdempotencyKey.trim().isEmpty ||
              record['retired'] != false ||
              record['ownerWriterId'] != null &&
                  record['ownerWriterId'] is! String ||
              record['writerEpoch'] is! int ||
              latest.writerEpoch < 0 ||
              record['writerEpoch'] != latest.writerEpoch ||
              latest.revision < 0 ||
              latest.acknowledgedRevision != latest.revision ||
              (record['draft'] as Map)['updatedAt'] is! String ||
              DateTime.tryParse((record['draft'] as Map)['updatedAt']) ==
                  null) {
            throw const FormatException('Selected proposal scope mismatch');
          }
        } catch (_) {
          preserveUnacknowledged();
          return (
            acquired: false,
            draft: prior.copyWith(
              storageState: YorksV1ProjectDraftStorageState.recoveryRequired,
            ),
          );
        }
        if (unacknowledged && _resumeContent(prior) != _resumeContent(latest)) {
          preserveUnacknowledged();
          return (
            acquired: false,
            draft: prior.copyWith(
              storageState: YorksV1ProjectDraftStorageState.recoveryRequired,
            ),
          );
        }
        final epoch = latest.writerEpoch;
        if (!transferOwnership &&
            (record['ownerWriterId'] != _writerId ||
                epoch != prior.writerEpoch && epoch != _attemptedResumeEpoch)) {
          return (
            acquired: false,
            draft: latest.copyWith(
              storageState: YorksV1ProjectDraftStorageState.ownedElsewhere,
            ),
          );
        }
        final nextEpoch = transferOwnership ? epoch + 1 : epoch;
        if (storageKey != catalogue?.scopeKey) {
          // Retrying an already-owned grant also validates discoverability.
          // It cannot acknowledge an unsupported catalogue or leave a missing
          // index link behind after a partial storage failure.
          catalogue?.register(tx, latest.draftId);
        }
        if (transferOwnership) {
          _attemptedResumeEpoch = nextEpoch;
          // Keep schema, saved time, payload and unknown envelope/draft fields
          // byte-equivalent in meaning; only the fenced ownership changes.
          tx.write(
            storageKey,
            jsonEncode({
              ...record,
              'ownerWriterId': _writerId,
              'writerEpoch': nextEpoch,
              'draft': {
                ...Map<String, dynamic>.from(record['draft'] as Map),
                'writerEpoch': nextEpoch,
              },
            }),
          );
        }
        return (
          acquired: true,
          draft: latest.copyWith(
            writerEpoch: nextEpoch,
            storageState: latest.revision > 0
                ? YorksV1ProjectDraftStorageState.saved
                : YorksV1ProjectDraftStorageState.dirty,
          ),
        );
      });
      if (_disposed) return false;
      _pending = null;
      _ownershipClaimed = claim.acquired;
      state = claim.draft;
      return claim.acquired;
    } on ProjectDraftStorageException catch (error) {
      _ownershipClaimed = false;
      if (!_disposed) {
        state = prior.copyWith(
          storageState: error.reason == 'resume_not_authorized'
              ? YorksV1ProjectDraftStorageState.ownedElsewhere
              : YorksV1ProjectDraftStorageState.failed,
        );
      }
      return false;
    } catch (_) {
      _ownershipClaimed = false;
      if (!_disposed) {
        state = prior.copyWith(
          storageState: YorksV1ProjectDraftStorageState.failed,
        );
      }
      return false;
    }
  }

  Future<void> takeOver() async {
    await _initialization;
    await _claim(takeOver: true);
  }

  /// Available only for a supported legacy payload whose owner is verified.
  /// The UI must show its contents and request an explicit backend rebind.
  YorksV1ProjectCreationDraft? readQuarantinedProposal() {
    if (state.storageState !=
            YorksV1ProjectDraftStorageState.recoveryRequired ||
        _legacyRaw == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(_legacyRaw);
      if (decoded is! List || decoded.length != 1 || decoded.single is! Map) {
        return null;
      }
      final draft = YorksV1ProjectCreationDraft.fromJson(
        Map<String, dynamic>.from(decoded.single as Map),
      );
      return draft.ownerAuthUserId == _ownerAuthUserId ? draft : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> adoptQuarantinedProposal() async {
    await _initialization;
    final proposal = readQuarantinedProposal();
    if (proposal == null) {
      throw const ProjectDraftStorageException('unsupported_legacy_recovery');
    }
    // Rebinding is deliberate. Provenance and original raw data are retained.
    state = proposal.copyWith(
      backendIdentity: _backendIdentity,
      mode: state.mode,
      projectId: state.projectId,
      draftId: state.draftId,
      creationIdempotencyKey: state.creationIdempotencyKey,
      revision: 0,
      acknowledgedRevision: 0,
      retainedFields: {
        ...proposal.retainedFields,
        'legacyRecoveryProvenance': 'owner-key-with-unverified-backend',
      },
      storageState: YorksV1ProjectDraftStorageState.dirty,
    );
    await _claim(takeOver: true);
    await save(state);
  }

  /// Restore an existing edit proposal or persist its immutable starting base.
  Future<void> initializeEdit(YorksV1ProjectCreationDraft seed) async {
    await _initialization;
    if (state.mode != YorksV1ProjectDraftMode.edit ||
        seed.ownerAuthUserId != _ownerAuthUserId ||
        seed.projectId != state.projectId ||
        seed.baseVersion == null) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    if (state.baseVersion != null || state.isReadOnly) return;
    await save(
      seed.copyWith(
        backendIdentity: _backendIdentity,
        mode: state.mode,
        draftId: state.draftId,
        creationIdempotencyKey: state.creationIdempotencyKey,
        writerEpoch: state.writerEpoch,
      ),
    );
  }

  Future<void> save(
    YorksV1ProjectCreationDraft draft, {
    String saveTrigger = 'checkpoint',
  }) {
    if (draft.ownerAuthUserId != _ownerAuthUserId ||
        draft.draftId != state.draftId ||
        draft.writerEpoch != state.writerEpoch ||
        draft.creationIdempotencyKey.trim().isEmpty ||
        draft.mode != state.mode ||
        draft.projectId != state.projectId ||
        state.isReadOnly ||
        _resuming ||
        _disposed) {
      return Future.error(
        const ProjectDraftStorageException('draft_not_writable'),
      );
    }
    final stamped = draft.copyWith(
      backendIdentity: _backendIdentity,
      draftId: state.draftId,
      writerEpoch: state.writerEpoch,
      revision: state.revision + 1,
      acknowledgedRevision: state.acknowledgedRevision,
      updatedAt: DateTime.now().toUtc(),
      storageState: YorksV1ProjectDraftStorageState.dirty,
      buildings: [
        for (final building in draft.buildings)
          building.localRowId == null
              ? building.copyWith(localRowId: _idempotencyKeyFactory())
              : building,
      ],
    );
    state = stamped;
    _pending = stamped;
    final waiter = Completer<void>();
    _waiters.add((revision: stamped.revision, completion: waiter));
    _startDrain(saveTrigger);
    return waiter.future;
  }

  void _startDrain(String saveTrigger) {
    if (_draining != null) return;
    _draining = _drain(saveTrigger).whenComplete(() {
      _draining = null;
      if (_pending != null && !_disposed) _startDrain(saveTrigger);
    });
  }

  Future<void> _drain(String saveTrigger) async {
    await _initialization;
    // An initial local-storage failure can happen before an owner envelope
    // exists. Retry the same fenced acquisition when storage recovers; an
    // ordinary atomic write alone would remain stuck on owner_missing forever.
    // The claim retains newer in-memory input and never takes over another tab.
    if (!_ownershipClaimed && !state.isReadOnly) {
      await _claim(recoveringFailedClaim: true);
    }
    if (!_disposed && (!_ownershipClaimed || state.isReadOnly)) {
      _pending = null;
      for (final waiter in _waiters) {
        waiter.completion.completeError(
          ProjectDraftStorageException(
            state.isReadOnly ? 'draft_not_writable' : 'owner_claim_failed',
          ),
        );
      }
      _waiters.clear();
      return;
    }
    while (_pending != null && !_disposed) {
      final snapshot = _pending!.copyWith(writerEpoch: state.writerEpoch);
      _pending = null;
      state = state.copyWith(
        storageState: YorksV1ProjectDraftStorageState.saving,
      );
      try {
        final acknowledged = snapshot.copyWith(
          acknowledgedRevision: snapshot.revision,
        );
        await atomicOwned(
          (tx) => tx.write(storageKey, _encodeRecord(acknowledged)),
        );
        if (_disposed) break;
        state = state.copyWith(
          acknowledgedRevision: snapshot.revision,
          storageState: state.revision == snapshot.revision
              ? YorksV1ProjectDraftStorageState.saved
              : YorksV1ProjectDraftStorageState.dirty,
        );
        final completed = _waiters
            .where((item) => item.revision <= snapshot.revision)
            .toList();
        _waiters.removeWhere((item) => item.revision <= snapshot.revision);
        for (final waiter in completed) {
          waiter.completion.complete();
        }
        if (!_reportedSaved ||
            saveTrigger == 'manual' ||
            saveTrigger == 'navigation') {
          _capture(AnalyticsEvent.projectDraftSaved, {
            AnalyticsProperty.mode: state.mode.name,
            AnalyticsProperty.storageScope: 'device',
            AnalyticsProperty.saveTrigger: saveTrigger,
          });
          _reportedSaved = true;
        }
      } catch (error, stack) {
        if (!_disposed && !state.isReadOnly) {
          state = state.copyWith(
            storageState: YorksV1ProjectDraftStorageState.failed,
          );
        }
        _pending = null;
        for (final waiter in _waiters) {
          waiter.completion.completeError(error, stack);
        }
        _waiters.clear();
        _capture(AnalyticsEvent.projectDraftSaveFailed, {
          AnalyticsProperty.mode: state.mode.name,
          AnalyticsProperty.errorCategory: 'storage',
        });
        return;
      }
    }
  }

  Future<void> flush({String saveTrigger = 'navigation'}) async {
    await _initialization;
    if (state.isReadOnly) {
      throw const ProjectDraftStorageException('draft_not_writable');
    }
    if (state.acknowledgedRevision < state.revision &&
        _pending == null &&
        _draining == null) {
      _pending = state;
      final waiter = Completer<void>();
      _waiters.add((revision: state.revision, completion: waiter));
      _startDrain(saveTrigger);
      await waiter.future;
    }
    await _draining;
    if (state.storageState == YorksV1ProjectDraftStorageState.failed) {
      throw const ProjectDraftStorageException('write_failed');
    }
  }

  Future<void> update(
    YorksV1ProjectCreationDraft Function(YorksV1ProjectCreationDraft current)
    transform,
  ) => save(transform(state));

  Future<void> setStage(YorksV1ProjectCreationStage stage) => save(
    state.copyWith(
      currentStage: stage,
      visitedStages: {...state.visitedStages, stage},
    ),
    saveTrigger: 'navigation',
  );

  /// A durable tombstone is written before resetting the active form. Journals
  /// and file follow-up manifests are intentionally independent of retirement.
  Future<void> retire({required String resultProjectId}) async {
    await flush();
    await atomicOwned((tx) {
      final tombstone = jsonEncode({
        'recordVersion': 1,
        'ownerWriterId': _writerId,
        'writerEpoch': state.writerEpoch,
        'retired': true,
        'draft': state.toJson(),
        'resultProjectId': resultProjectId,
        'retiredAt': DateTime.now().toUtc().toIso8601String(),
      });
      // Retire the active envelope first. A quota/crash failure while copying
      // its historical tombstone then still fences the old writer. A new claim
      // copies the retired envelope before reusing this slot.
      tx.write(storageKey, tombstone);
      tx.write('$journalScopeKey:retired:${state.draftId}', tombstone);
    });
  }

  /// A confirmed core releases its matching editable slot even when files or
  /// activation need attention. A reconciled earlier core only retains its
  /// project locator; the different active proposal remains untouched. Returns
  /// whether this active slot was retired. Exact journals stay independent.
  Future<bool> retireConfirmedOperation(
    YorksV1ProjectSetupOperation operation,
  ) async {
    if (!operation.coreSucceeded ||
        operation.project == null ||
        operation.backendIdentity != _backendIdentity ||
        operation.ownerAuthUserId != _ownerAuthUserId ||
        operation.mode.name != state.mode.name ||
        (state.mode == YorksV1ProjectDraftMode.edit &&
            operation.project!.id != state.projectId)) {
      throw const ProjectDraftStorageException('confirmed_core_scope_mismatch');
    }
    await flush();
    return _storage.transaction(_lockKey, (tx) {
      if (_disposed) {
        throw const ProjectDraftStorageException('controller_disposed');
      }
      final raw = tx.read(storageKey);
      if (raw == null) {
        throw const ProjectDraftStorageException('owner_missing');
      }
      final record = _record(raw);
      if (record['ownerWriterId'] != _writerId ||
          record['writerEpoch'] != state.writerEpoch ||
          _draftFromRecord(record).draftId != state.draftId) {
        throw const ProjectDraftStorageException('writer_fenced');
      }
      final journalRaw = tx.read(
        '$journalScopeKey:journal:${operation.draftId}',
      );
      if (journalRaw == null) {
        throw const ProjectDraftStorageException(
          'confirmed_core_not_acknowledged',
        );
      }
      final persisted = YorksV1ProjectSetupOperation.fromJson(
        Map<String, dynamic>.from(jsonDecode(journalRaw) as Map),
      );
      if (!persisted.coreSucceeded ||
          persisted.backendIdentity != _backendIdentity ||
          persisted.ownerAuthUserId != _ownerAuthUserId ||
          persisted.draftId != operation.draftId ||
          persisted.mode != operation.mode ||
          persisted.core.idempotencyKey != operation.core.idempotencyKey ||
          persisted.core.canonicalPayload != operation.core.canonicalPayload ||
          persisted.core.canonicalResult != operation.core.canonicalResult) {
        throw const ProjectDraftStorageException(
          'confirmed_core_not_acknowledged',
        );
      }
      final matchingProposal = operation.draftId == state.draftId;
      if (record['retired'] == true && !matchingProposal) {
        throw const ProjectDraftStorageException('writer_fenced');
      }
      if (record['retired'] == true &&
          record['resultProjectId'] != persisted.project!.id) {
        throw const ProjectDraftStorageException('retired_result_mismatch');
      }
      // Discovery is acknowledged first. A quota failure cannot free the slot
      // before the pending manifest has a project-scoped recovery locator.
      YorksV1ProjectSetupJournalStore.retainCompletedOperation(
        tx,
        scopeKey: journalScopeKey,
        operation: persisted,
      );
      if (!matchingProposal) {
        return false;
      }
      final tombstone = record['retired'] == true
          ? raw
          : jsonEncode({
              'recordVersion': 1,
              'ownerWriterId': _writerId,
              'writerEpoch': state.writerEpoch,
              'retired': true,
              'draft': state.toJson(),
              'resultProjectId': persisted.project!.id,
              'retiredAt': DateTime.now().toUtc().toIso8601String(),
            });
      tx.write(storageKey, tombstone);
      tx.write('$journalScopeKey:retired:${operation.draftId}', tombstone);
      return true;
    });
  }

  Future<void> discard() async {
    await retire(resultProjectId: 'explicit_discard');
    if (_disposed) return;
    if (_selectedDraftId != null) {
      // A selected URL keeps its identity. Explicit discard retires that
      // identity; a separate fresh entry allocates the next proposal.
      state = state.copyWith(
        storageState: YorksV1ProjectDraftStorageState.recoveryRequired,
      );
      return;
    }
    state = YorksV1ProjectCreationDraft.empty(
      ownerAuthUserId: _ownerAuthUserId,
      creationIdempotencyKey: _idempotencyKeyFactory(),
      backendIdentity: _backendIdentity,
      mode: state.mode,
      projectId: state.projectId,
    );
    await _claim(takeOver: true);
  }

  String _encodeRecord(YorksV1ProjectCreationDraft draft) => jsonEncode({
    'recordVersion': 1,
    'ownerWriterId': _writerId,
    'writerEpoch': draft.writerEpoch,
    'retired': false,
    'draft': draft.toJson(),
  });

  void _capture(AnalyticsEvent event, AnalyticsProperties properties) {
    // Recovery is independent of analytics availability and transport errors.
    try {
      _analytics.capture(event, properties: properties);
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    for (final waiter in _waiters) {
      if (!waiter.completion.isCompleted) {
        waiter.completion.completeError(
          const ProjectDraftStorageException('controller_disposed'),
        );
      }
    }
    _waiters.clear();
    unawaited(
      _storage
          .transaction(_lockKey, (tx) {
            final raw = tx.read(storageKey);
            if (raw == null) return;
            final record = _record(raw);
            if (record['ownerWriterId'] == _writerId) {
              record['ownerWriterId'] = null;
              tx.write(storageKey, jsonEncode(record));
            }
          })
          .catchError((Object _) {}),
    );
    super.dispose();
  }
}

Map<String, dynamic> _record(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map ||
      decoded['recordVersion'] != 1 ||
      decoded['draft'] is! Map) {
    throw const FormatException('Unsupported project recovery record');
  }
  return Map<String, dynamic>.from(decoded);
}

YorksV1ProjectCreationDraft _draftFromRecord(Map<String, dynamic> record) =>
    YorksV1ProjectCreationDraft.fromJson(
      Map<String, dynamic>.from(record['draft'] as Map),
    );

String _resumeContent(YorksV1ProjectCreationDraft draft) {
  final json = draft.toJson();
  for (final key in const {
    'revision',
    'acknowledgedRevision',
    'writerEpoch',
    'updatedAt',
    'currentStage',
    'visitedStages',
  }) {
    json.remove(key);
  }
  json['rawEditorState'] = {
    for (final entry in draft.rawEditorState.entries)
      if (!const {
            'sectionContext',
            'contactsExpanded',
            'buildingLocalId',
          }.contains(entry.key) &&
          entry.value != null &&
          entry.value != '' &&
          entry.value != false)
        entry.key: entry.value,
  };
  return yorksV1CanonicalSetupJson(json);
}

String _stepName(YorksV1ProjectCreationStage stage) => switch (stage) {
  YorksV1ProjectCreationStage.projectDetails => 'project_details',
  YorksV1ProjectCreationStage.partiesAndAccess => 'parties_and_access',
  YorksV1ProjectCreationStage.buildings => 'buildings',
  YorksV1ProjectCreationStage.attachments => 'attachments',
  YorksV1ProjectCreationStage.reviewAndCreate => 'review',
};

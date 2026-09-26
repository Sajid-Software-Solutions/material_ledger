import 'yorks_v1_material_line_editor.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/yorks_v1_boq.dart';
import '../models/analytics_event.dart';
import '../models/yorks_v1_domain_error.dart';
import '../models/yorks_v1_item_description.dart';
import '../models/yorks_v1_material_request.dart';
import '../repositories/collection_store.dart';
import '../repositories/yorks_v1_material_request_draft_store.dart';
import '../repositories/yorks_v1_material_request_repository.dart';
import '../services/analytics_service.dart';

enum YorksV1MaterialRequestDraftSyncStatus {
  local,
  syncingToAccount,
  savedToAccount,
  saving,
  saved,
  submitting,
  submitted,
  deleting,
  deleted,
  outcomeUnknown,
  checkingSave,
  checkingSubmission,
  conflict,
  failed,
}

class YorksV1MaterialRequestDraftState {
  const YorksV1MaterialRequestDraftState({
    required this.draft,
    this.status = YorksV1MaterialRequestDraftSyncStatus.local,
    this.errorCode,
    this.canRetryUnconfirmed = false,
    this.localPersistenceFailed = false,
  });

  final YorksV1MaterialRequestDraft draft;
  final YorksV1MaterialRequestDraftSyncStatus status;
  final YorksV1DomainErrorCode? errorCode;
  final bool canRetryUnconfirmed;
  final bool localPersistenceFailed;
}

class _DraftSaveResult {
  const _DraftSaveResult({required this.acknowledged, this.request});

  final bool acknowledged;
  final YorksV1MaterialRequest? request;
}

/// Local-recovery plus connected-command controller. Editing remains private
/// on the device until a Save/Submit operation reaches the normalized server.
/// Only Submit is an idempotent critical workflow transition.
class YorksV1MaterialRequestDraftController
    extends StateNotifier<YorksV1MaterialRequestDraftState>
    implements YorksV1MaterialLineEditor {
  YorksV1MaterialRequestDraftController({
    required String ownerAuthUserId,
    required String draftId,
    required CollectionStore<YorksV1MaterialRequestDraft> store,
    required YorksV1MaterialRequestRepository repository,
    String Function()? uuidFactory,
    VoidCallback? onLocalDraftsChanged,
    bool Function()? isCurrentOwner,
    VoidCallback Function()? retainForDeletion,
    AnalyticsService analytics = const NoopAnalyticsService(),
    Duration privateSyncDebounce = const Duration(milliseconds: 1200),
  }) : _ownerAuthUserId = ownerAuthUserId,
       _draftId = draftId,
       _store = store,
       _repository = repository,
       _uuidFactory = uuidFactory ?? const Uuid().v4,
       _onLocalDraftsChanged = onLocalDraftsChanged,
       _isCurrentOwner = isCurrentOwner,
       _retainForDeletion = retainForDeletion,
       _analytics = analytics,
       _privateSyncDebounceDuration = privateSyncDebounce,
       super(
         YorksV1MaterialRequestDraftState(
           draft: _restoreOrEmpty(
             ownerAuthUserId: ownerAuthUserId,
             draftId: draftId,
             store: store,
             uuidFactory: uuidFactory ?? const Uuid().v4,
           ),
         ),
       ) {
    _acceptedDraft = state.draft;
    if (state.draft.pendingSubmissionApproval != null ||
        state.draft.hasPendingSave) {
      state = YorksV1MaterialRequestDraftState(
        draft: state.draft,
        status: YorksV1MaterialRequestDraftSyncStatus.outcomeUnknown,
        canRetryUnconfirmed: state.draft.hasPendingSave,
      );
    }
  }

  final String _ownerAuthUserId;
  final String _draftId;
  final CollectionStore<YorksV1MaterialRequestDraft> _store;
  final YorksV1MaterialRequestRepository _repository;
  final String Function() _uuidFactory;
  final VoidCallback? _onLocalDraftsChanged;
  final bool Function()? _isCurrentOwner;
  final VoidCallback Function()? _retainForDeletion;
  final AnalyticsService _analytics;
  final Duration _privateSyncDebounceDuration;
  Future<void> _persistQueue = Future<void>.value();
  bool _connectedCommandInFlight = false;
  // A connected command supersedes older recovery reads/writes, including
  // responses that arrive after the command has finished.
  int _recoveryGeneration = 0;
  Object? _connectedFailure;

  void _beginConnectedCommand() {
    _connectedCommandInFlight = true;
    _connectedFailure = null;
    _recoveryGeneration++;
    _privateSyncDebounce?.cancel();
    _privateSyncRequested = false;
  }

  bool _recoveryIsCurrent(int generation) =>
      !_inactive && generation == _recoveryGeneration;
  bool _editingBeforeApproval = false;
  Timer? _privateSyncDebounce;
  Future<void>? _privateHydration;
  bool _privateHydrationCompleted = false;
  bool _privateSyncInFlight = false;
  bool _privateSyncRequested = false;
  bool _disposed = false;
  bool _discardInFlight = false;
  bool _discarded = false;
  Future<void>? _privateSyncDrain;
  bool get _inactive =>
      _disposed || _discarded || !(_isCurrentOwner?.call() ?? true);
  late YorksV1MaterialRequestDraft _acceptedDraft;

  /// Read-only snapshot for UI callbacks that need to guard a deferred
  /// default (for example the Common scope) against a newer project choice.
  YorksV1MaterialRequestDraft get currentDraft => state.draft;

  /// The most recent draft the user deliberately saved or originally opened.
  /// Autosaved keystrokes remain recoverable but do not move this boundary,
  /// allowing presentation code to offer an honest Discard Changes action.
  YorksV1MaterialRequestDraft get acceptedDraft => _acceptedDraft;

  /// Last connected-operation error exposed without making widgets reach into
  /// StateNotifier's protected [state] member.
  YorksV1DomainErrorCode? get lastErrorCode => state.errorCode;

  bool get isEditingBeforeApproval => _editingBeforeApproval;

  void recordReviewReached() {
    _analytics.capture(
      AnalyticsEvent.materialRequestReviewOpened,
      properties: {
        AnalyticsProperty.itemCount: state.draft.lines.length,
        AnalyticsProperty.entryPoint: 'draft_flow',
      },
    );
  }

  YorksV1MaterialRequestPhase2Repository? get _phase2Repository =>
      _repository is YorksV1MaterialRequestPhase2Repository
      ? _repository as YorksV1MaterialRequestPhase2Repository
      : null;

  /// Reconciles the owner-only cross-device recovery copy before an untouched
  /// editor starts. A newer local crash-recovery copy always wins; a newer
  /// account copy replaces only an untouched/older device copy.
  Future<void> hydratePrivateDraft() {
    if (_inactive ||
        _discardInFlight ||
        state.draft.pendingSubmissionApproval != null ||
        _privateHydrationCompleted ||
        state.draft.serverRecordVersion > 0) {
      return Future<void>.value();
    }
    return _privateHydration ??= _hydratePrivateDraftOnce().whenComplete(() {
      _privateHydrationCompleted = true;
      _privateHydration = null;
    });
  }

  Future<void> _hydratePrivateDraftOnce() async {
    final repository = _phase2Repository;
    if (repository == null || state.draft.serverRecordVersion > 0) return;
    final initialLocal = state.draft;
    final generation = _recoveryGeneration;
    try {
      final remote = await repository.getPrivateDraft(
        draftId: _draftId,
        ownerAuthUserId: _ownerAuthUserId,
        submissionIdempotencyKey: initialLocal.submissionIdempotencyKey,
      );
      if (!_recoveryIsCurrent(generation)) return;
      final current = state.draft;
      final editedWhileLoading = current.updatedAt != initialLocal.updatedAt;
      if (remote == null) {
        if (current.hasRecoverableContent) _schedulePrivateSync();
        return;
      }
      if (!editedWhileLoading &&
          (!current.hasRecoverableContent ||
              remote.clientUpdatedAt.isAfter(current.updatedAt))) {
        _acceptedDraft = remote.draft;
        state = YorksV1MaterialRequestDraftState(
          draft: remote.draft,
          status: YorksV1MaterialRequestDraftSyncStatus.savedToAccount,
        );
        await _persist(remote.draft);
        return;
      }
      if (editedWhileLoading &&
          remote.clientUpdatedAt.isAfter(initialLocal.updatedAt)) {
        // Both copies changed while the remote recovery read was pending.
        // Keep every character entered in this editor, but do not adopt the
        // remote version and silently overwrite the other device on the next
        // sync. The visible conflict can then be resolved deliberately.
        state = YorksV1MaterialRequestDraftState(
          draft: current,
          status: YorksV1MaterialRequestDraftSyncStatus.conflict,
          errorCode: YorksV1DomainErrorCode.conflict,
        );
        return;
      }
      // A delayed hydration response may arrive after the engineer has begun
      // typing. Preserve that live editor state and merge only the server's
      // concurrency metadata before scheduling the newest copy for sync.
      final reconciled = current.copyWith(
        privateSyncVersion: remote.syncVersion,
        privateSyncedAt: remote.serverUpdatedAt,
      );
      state = YorksV1MaterialRequestDraftState(draft: reconciled);
      await _persist(reconciled);
      if (editedWhileLoading ||
          current.updatedAt.isAfter(remote.clientUpdatedAt)) {
        _schedulePrivateSync();
      }
    } on YorksV1DomainException catch (error) {
      if (!_recoveryIsCurrent(generation)) return;
      if (error.serverMessage == 'V1_PRIVATE_DRAFT_DELETED') {
        await _clearRetiredRecovery();
        return;
      }
      if (error.code == YorksV1DomainErrorCode.conflict) {
        state = YorksV1MaterialRequestDraftState(
          draft: state.draft,
          status: YorksV1MaterialRequestDraftSyncStatus.conflict,
          errorCode: error.code,
        );
      }
      // Offline/account-unavailable startup never threatens the device copy.
    } catch (_) {
      // Device-local recovery remains authoritative for this editing session.
    }
  }

  static YorksV1MaterialRequestDraft _restoreOrEmpty({
    required String ownerAuthUserId,
    required String draftId,
    required CollectionStore<YorksV1MaterialRequestDraft> store,
    required String Function() uuidFactory,
  }) {
    for (final draft in store.readAll()) {
      if (draft.id == draftId && draft.ownerAuthUserId == ownerAuthUserId) {
        if (draft.submissionIdempotencyKey.trim().isNotEmpty) return draft;
        return YorksV1MaterialRequestDraft(
          id: draft.id,
          ownerAuthUserId: draft.ownerAuthUserId,
          submissionIdempotencyKey: uuidFactory(),
          serverRecordVersion: draft.serverRecordVersion,
          localRevision: draft.localRevision,
          pendingSaveOperationId: draft.pendingSaveOperationId,
          pendingSaveExpectedVersion: draft.pendingSaveExpectedVersion,
          pendingSaveRevision: draft.pendingSaveRevision,
          pendingSavePayloadHash: draft.pendingSavePayloadHash,
          privateSyncVersion: draft.privateSyncVersion,
          privateSyncedAt: draft.privateSyncedAt,
          projectId: draft.projectId,
          scopeId: draft.scopeId,
          title: draft.title,
          timing: draft.timing,
          scheduledDate: draft.scheduledDate,
          deliveryNote: draft.deliveryNote,
          lines: draft.lines,
          updatedAt: draft.updatedAt,
        );
      }
    }
    return YorksV1MaterialRequestDraft.empty(
      id: draftId,
      ownerAuthUserId: ownerAuthUserId,
      submissionIdempotencyKey: uuidFactory(),
    );
  }

  Future<void> update(
    YorksV1MaterialRequestDraft Function(YorksV1MaterialRequestDraft current)
    transform,
  ) => _replace(transform(state.draft));

  /// Changes the project without allowing a row to retain BOQ provenance from
  /// the old project. A caller may preserve the engineer's entered rows; BOQ
  /// rows then become descriptive custom snapshots while Excel/custom rows
  /// retain their source kind. The server still re-checks the new project and
  /// scope before a connected save or submit.
  Future<bool> setProject(
    String? projectId, {
    bool discardExistingLines = false,
    bool preserveExistingLines = false,
  }) async {
    final draft = state.draft;
    if (projectId == draft.projectId) return true;
    if (draft.lines.isNotEmpty &&
        !discardExistingLines &&
        !preserveExistingLines) {
      return false;
    }
    final retainedLines = preserveExistingLines
        ? [
            for (final line in draft.lines)
              line.source == YorksV1MaterialRequestLineSource.boq
                  ? line.copyWith(
                      source: YorksV1MaterialRequestLineSource.custom,
                      sourceBoqGroupId: null,
                      sourceBoqRowId: null,
                    )
                  : line,
          ]
        : const <YorksV1MaterialRequestLine>[];
    await update(
      (current) => current.copyWith(
        projectId: projectId,
        scopeId: null,
        lines: retainedLines,
      ),
    );
    return true;
  }

  /// Changes the request scope without permitting controlled BOQ rows to
  /// follow it across Common/building boundaries. Custom and imported lines
  /// stay available; the presentation layer must obtain confirmation before
  /// asking to discard BOQ-derived rows.
  Future<bool> setScope(
    String? scopeId, {
    bool discardIncompatibleBoqRows = false,
  }) async {
    final draft = state.draft;
    if (scopeId == draft.scopeId) return true;
    final hasBoqRows = draft.lines.any(
      (line) => line.source == YorksV1MaterialRequestLineSource.boq,
    );
    if (hasBoqRows && !discardIncompatibleBoqRows) return false;
    await update(
      (current) => current.copyWith(
        scopeId: scopeId,
        lines: hasBoqRows
            ? current.lines
                  .where(
                    (line) =>
                        line.source != YorksV1MaterialRequestLineSource.boq,
                  )
                  .toList(growable: false)
            : current.lines,
      ),
    );
    return true;
  }

  Future<void> setTitle(String? title) =>
      update((draft) => draft.copyWith(title: title));

  Future<void> setTiming(YorksV1MaterialRequestTiming timing) => update(
    (draft) => draft.copyWith(
      timing: timing,
      scheduledDate: timing == YorksV1MaterialRequestTiming.scheduled
          ? draft.scheduledDate
          : null,
    ),
  );

  Future<void> setScheduledDate(DateTime? scheduledDate) =>
      update((draft) => draft.copyWith(scheduledDate: scheduledDate));

  Future<void> setDeliveryNote(String? deliveryNote) =>
      update((draft) => draft.copyWith(deliveryNote: deliveryNote));

  /// Restores a server-saved draft when it is opened from the request queue
  /// after local recovery has no copy. This is deliberately one-way and only
  /// applies to an untouched local draft; unsaved local edits must never be
  /// overwritten by a later refresh.
  Future<bool> hydrateFromServer(YorksV1MaterialRequest request) async {
    final current = state.draft;
    if (request.id != _draftId ||
        (!request.state.isDraft &&
            !request.canEditBeforeApproval &&
            !request.canEditPostApproval)) {
      return false;
    }
    if (current.serverRecordVersion != 0 ||
        current.updatedAt.millisecondsSinceEpoch != 0) {
      if (current.serverRecordVersion != request.recordVersion) {
        state = YorksV1MaterialRequestDraftState(
          draft: current,
          status: YorksV1MaterialRequestDraftSyncStatus.conflict,
          errorCode: YorksV1DomainErrorCode.conflict,
        );
        return false;
      }
      _editingBeforeApproval =
          request.canEditBeforeApproval || request.canEditPostApproval;
      return true;
    }
    // The existing-record command also handles a delegated approved edit.
    // A new draft alone may use the draft save RPC or local-only recovery.
    _editingBeforeApproval =
        request.canEditBeforeApproval || request.canEditPostApproval;
    final hydrated = YorksV1MaterialRequestDraft(
      id: current.id,
      ownerAuthUserId: current.ownerAuthUserId,
      submissionIdempotencyKey: current.submissionIdempotencyKey,
      serverRecordVersion: request.recordVersion,
      localRevision: current.localRevision,
      projectId: request.projectId,
      scopeId: request.scopeId,
      title: request.title,
      timing: request.timing,
      scheduledDate: request.scheduledDate,
      deliveryNote: request.deliveryNote,
      lines: request.lines,
      updatedAt: request.updatedAt,
    );
    _acceptedDraft = hydrated;
    state = YorksV1MaterialRequestDraftState(
      draft: hydrated,
      status: YorksV1MaterialRequestDraftSyncStatus.saved,
    );
    await _persist(hydrated);
    return true;
  }

  @override
  Future<void> addCustomLine({String? afterLineId}) async {
    final draft = state.draft;
    final insertIndex = afterLineId == null
        ? draft.lines.length
        : draft.lines.indexWhere((line) => line.id == afterLineId) + 1;
    final safeInsertIndex = insertIndex <= 0 || insertIndex > draft.lines.length
        ? draft.lines.length
        : insertIndex;
    final lines = [...draft.lines]
      ..insert(
        safeInsertIndex,
        YorksV1MaterialRequestLine(
          id: _uuidFactory(),
          displayOrder: safeInsertIndex + 1,
          source: YorksV1MaterialRequestLineSource.custom,
          description: '',
          quantity: '',
          // Unit choices are server-controlled. Leaving a new row blank
          // keeps the local draft recoverable without inventing a value
          // when the Configuration control plane is unavailable.
          unit: '',
        ),
      );
    await _replace(draft.copyWith(lines: _reindexLines(lines)));
    _captureItemChange('add_custom');
  }

  Future<void> addBlankLine() => addCustomLine();

  /// Inserts a directly editable copy immediately after the selected line
  /// without retaining a BOQ source pointer. This keeps a Similar Row useful
  /// for repeated items while preventing an accidental second request against
  /// the same source snapshot.
  @override
  Future<void> addSimilarLine({String? afterLineId}) async {
    final draft = state.draft;
    final sourceIndex = afterLineId == null
        ? draft.lines.length - 1
        : draft.lines.indexWhere((line) => line.id == afterLineId);
    final source = sourceIndex < 0 ? null : draft.lines[sourceIndex];
    if (source == null) return addBlankLine();
    final lines = [...draft.lines]
      ..insert(
        sourceIndex + 1,
        YorksV1MaterialRequestLine(
          id: _uuidFactory(),
          displayOrder: sourceIndex + 2,
          source: YorksV1MaterialRequestLineSource.custom,
          description: source.description,
          brandOrigin: source.brandOrigin,
          size: source.size,
          // Model/tag and quantity identify the original equipment; a
          // Similar MR row must not accidentally request a second unit.
          quantity: '',
          unit: source.unit,
        ),
      );
    await _replace(draft.copyWith(lines: _reindexLines(lines)));
    _captureItemChange('add_similar');
  }

  Future<void> addBoqRows({
    required YorksV1BoqWorksheet worksheet,
    required Iterable<String> rowIds,
  }) async {
    final selected = rowIds.toSet();
    if (selected.isEmpty) return;
    final draft = state.draft;
    // The All BOQ view is a read-only aggregate, so a controlled BOQ source
    // may only be copied when the worksheet is owned by the chosen MR scope.
    // The trusted draft RPC enforces this again before persisting a line.
    if (draft.scopeId == null ||
        !worksheet.group.isScopeAssigned ||
        worksheet.group.scopeId != draft.scopeId) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    final existingSourceRows = draft.lines
        .map((line) => line.sourceBoqRowId)
        .whereType<String>()
        .toSet();
    final additions = <YorksV1MaterialRequestLine>[];
    for (final row in worksheet.rows) {
      if (!selected.contains(row.id)) continue;
      // A BOQ row is a controlled source. Adding it twice must not silently
      // create a second request line or inflate the requested quantity.
      if (existingSourceRows.contains(row.id)) continue;
      final tag = _boqValue(
        worksheet,
        row,
        YorksV1BoqCanonicalField.equipmentTag,
        headingPattern: r'tag|equipment\s*tag|fan\s*tag',
      );
      final description = _boqValue(
        worksheet,
        row,
        YorksV1BoqCanonicalField.description,
        headingPattern: r'description|serving\s*area|location|equipment|item',
      );
      final explicitQuantity = _canonicalValue(
        worksheet,
        row,
        YorksV1BoqCanonicalField.quantity,
      );
      final hasSuggestedQuantity = explicitQuantity.isEmpty && tag.isNotEmpty;
      final rawModel = _boqValue(
        worksheet,
        row,
        YorksV1BoqCanonicalField.model,
        headingPattern: r'(^|\b)(model|fan\s*model)(\b|$)',
      );
      additions.add(
        YorksV1MaterialRequestLine(
          id: _uuidFactory(),
          displayOrder: draft.lines.length + additions.length + 1,
          source: YorksV1MaterialRequestLineSource.boq,
          sourceBoqGroupId: worksheet.group.id,
          sourceBoqRowId: row.id,
          description: normalizeYorksV1MaterialRequestItemDescription(
            _composeDescription(tag: tag, context: description),
          ),
          brandOrigin: normalizeYorksV1OptionalItemText(
            _boqValue(
              worksheet,
              row,
              YorksV1BoqCanonicalField.brandOrigin,
              headingPattern: r'brand|make|manufacturer|origin',
            ),
          ),
          size: normalizeYorksV1OptionalItemText(
            _boqValue(
              worksheet,
              row,
              YorksV1BoqCanonicalField.size,
              headingPattern: r'size|dimension',
            ),
          ),
          // A tag identifies equipment but is not a manufacturer model. Keep
          // it separate so PDFs and Procurement screens do not render the
          // same value twice as both Model and Tag.
          model: normalizeYorksV1OptionalItemText(rawModel),
          equipmentTag: normalizeYorksV1OptionalItemText(tag),
          planningModelTag: normalizeYorksV1OptionalItemText(
            _canonicalValue(
              worksheet,
              row,
              YorksV1BoqCanonicalField.planningModelTag,
              nullable: true,
            ),
          ),
          quantity: hasSuggestedQuantity ? '1' : explicitQuantity,
          quantityIsSuggested: hasSuggestedQuantity,
          unit:
              _canonicalValue(
                worksheet,
                row,
                YorksV1BoqCanonicalField.unit,
              ).trim().isEmpty
              ? 'Nos'
              : _canonicalValue(worksheet, row, YorksV1BoqCanonicalField.unit),
        ),
      );
    }
    if (additions.isEmpty) return;
    await _replace(draft.copyWith(lines: [...draft.lines, ...additions]));
    _captureItemChange('add_boq', count: additions.length);
  }

  Future<void> addExcelLines(
    Iterable<YorksV1MaterialRequestLine> imported,
  ) async {
    final draft = state.draft;
    final importedLines = imported.toList(growable: false);
    final additions = [
      for (var index = 0; index < importedLines.length; index++)
        YorksV1MaterialRequestLine(
          id: _uuidFactory(),
          displayOrder: draft.lines.length + index + 1,
          source: YorksV1MaterialRequestLineSource.excel,
          description: normalizeYorksV1MaterialRequestItemDescription(
            importedLines[index].description,
          ),
          brandOrigin: normalizeYorksV1OptionalItemText(
            importedLines[index].brandOrigin,
          ),
          size: normalizeYorksV1OptionalItemText(importedLines[index].size),
          model: normalizeYorksV1OptionalItemText(importedLines[index].model),
          equipmentTag: normalizeYorksV1OptionalItemText(
            importedLines[index].equipmentTag,
          ),
          planningModelTag: normalizeYorksV1OptionalItemText(
            importedLines[index].planningModelTag,
          ),
          quantityIsSuggested: importedLines[index].quantityIsSuggested,
          quantity: importedLines[index].quantity,
          unit: importedLines[index].unit,
        ),
    ];
    if (additions.isEmpty) return;
    await _replace(draft.copyWith(lines: [...draft.lines, ...additions]));
    _captureItemChange('add_excel', count: additions.length);
  }

  @override
  Future<void> updateLine(
    String lineId,
    YorksV1MaterialRequestLine Function(YorksV1MaterialRequestLine line)
    transform,
  ) async {
    final draft = state.draft;
    await _replace(
      draft.copyWith(
        lines: [
          for (final line in draft.lines)
            line.id == lineId ? transform(line) : line,
        ],
      ),
    );
  }

  @override
  Future<void> removeLine(String lineId) async {
    final remaining = state.draft.lines
        .where((line) => line.id != lineId)
        .toList(growable: false);
    await _replace(state.draft.copyWith(lines: _reindexLines(remaining)));
    _captureItemChange('remove');
  }

  void _captureItemChange(String action, {int count = 1}) {
    _analytics.capture(
      action == 'remove'
          ? AnalyticsEvent.materialRequestItemRemoved
          : AnalyticsEvent.materialRequestItemAdded,
      properties: {
        AnalyticsProperty.actionType: action,
        AnalyticsProperty.itemCount: count,
      },
    );
  }

  List<YorksV1MaterialRequestLine> _reindexLines(
    List<YorksV1MaterialRequestLine> lines,
  ) => [
    for (var index = 0; index < lines.length; index++)
      YorksV1MaterialRequestLine(
        id: lines[index].id,
        displayOrder: index + 1,
        source: lines[index].source,
        description: lines[index].description,
        brandOrigin: lines[index].brandOrigin,
        size: lines[index].size,
        model: lines[index].model,
        equipmentTag: lines[index].equipmentTag,
        planningModelTag: lines[index].planningModelTag,
        quantityIsSuggested: lines[index].quantityIsSuggested,
        quantity: lines[index].quantity,
        unit: lines[index].unit,
        sourceBoqGroupId: lines[index].sourceBoqGroupId,
        sourceBoqRowId: lines[index].sourceBoqRowId,
        unitCost: lines[index].unitCost,
        totalCost: lines[index].totalCost,
        currencyCode: lines[index].currencyCode,
      ),
  ];

  /// Saves the current draft without pretending that an incomplete draft was
  /// accepted by the server.  Incomplete input is still durable on this
  /// device and can be reopened and edited later; complete input is synced
  /// through the versioned draft RPC.
  Future<bool> saveDraft() async {
    if (_inactive ||
        _discardInFlight ||
        state.draft.pendingSubmissionApproval != null) {
      return false;
    }
    final draft = state.draft;
    if (!_editingBeforeApproval && !draft.canSubmitLocally) {
      await _persist(draft);
      _acceptedDraft = draft;
      state = YorksV1MaterialRequestDraftState(
        draft: draft,
        status: YorksV1MaterialRequestDraftSyncStatus.local,
      );
      _analytics.capture(
        AnalyticsEvent.materialRequestDraftSaved,
        properties: {
          AnalyticsProperty.source: 'local_recovery',
          AnalyticsProperty.itemCount: draft.lines.length,
        },
      );
      return true;
    }
    return saveConnected();
  }

  Future<bool> saveConnected() async {
    if (_inactive ||
        _discardInFlight ||
        state.draft.pendingSubmissionApproval != null) {
      return false;
    }
    if (state.draft.hasPendingSave) {
      return reconcileDraftSave(retryIfAbsent: true);
    }
    final feedback = _analytics.expectFeedback(
      action: 'save_material_request_draft',
      screen: AnalyticsScreen.materialRequestDraft,
      operationWasLoading: _connectedCommandInFlight,
    );
    if (_inactive || _discardInFlight || _connectedCommandInFlight) {
      return false;
    }
    _beginConnectedCommand();
    final operation = _analytics.beginOperation(
      'material_request_save_draft',
      properties: {
        AnalyticsProperty.workflow: 'material_request',
        AnalyticsProperty.itemCount: state.draft.lines.length,
      },
    );
    try {
      final pending = _saveConnected();
      feedback.feedbackObserved();
      final result = await pending;
      if (_inactive) return false;
      if (!result.acknowledged) {
        operation.fail(
          YorksV1DomainException(
            state.errorCode ?? YorksV1DomainErrorCode.backendUnavailable,
          ),
        );
      } else {
        operation.complete();
        _analytics.capture(
          AnalyticsEvent.materialRequestDraftSaved,
          properties: {
            AnalyticsProperty.source: 'server',
            AnalyticsProperty.itemCount: state.draft.lines.length,
          },
        );
      }
      return result.acknowledged;
    } finally {
      _connectedCommandInFlight = false;
    }
  }

  Future<_DraftSaveResult> _saveConnected() async {
    var draft = state.draft;
    if (!draft.canSubmitLocally) {
      _analytics.capture(
        AnalyticsEvent.formValidationFailed,
        properties: const {
          AnalyticsProperty.formType: 'material_request',
          AnalyticsProperty.validationReason: 'incomplete_request',
          AnalyticsProperty.errorCategory: AnalyticsErrorCategory.validation,
        },
      );
      state = YorksV1MaterialRequestDraftState(
        draft: draft,
        status: YorksV1MaterialRequestDraftSyncStatus.failed,
        errorCode: YorksV1DomainErrorCode.invalidInput,
      );
      return const _DraftSaveResult(acknowledged: false);
    }
    final receiptRepository =
        _repository is YorksV1MaterialRequestDraftSaveRecoveryRepository
        ? _repository as YorksV1MaterialRequestDraftSaveRecoveryRepository
        : null;
    if (!_editingBeforeApproval && receiptRepository != null) {
      final operationId = _uuidFactory();
      final payloadHash = draft.savePayloadHash();
      draft = draft.copyWith(
        pendingSaveOperationId: operationId,
        pendingSaveExpectedVersion: draft.serverRecordVersion,
        pendingSaveRevision: draft.localRevision,
        pendingSavePayloadHash: payloadHash,
      );
      await _persist(draft);
      if (_inactive) {
        return const _DraftSaveResult(acknowledged: false);
      }
    }
    state = YorksV1MaterialRequestDraftState(
      draft: draft,
      status: YorksV1MaterialRequestDraftSyncStatus.saving,
    );
    try {
      final saved = _editingBeforeApproval
          ? await _repository.updateForApproval(
              YorksV1UpdateMaterialRequestForApprovalInput(
                draft: draft,
                idempotencyKey: draft.submissionIdempotencyKey,
              ),
            )
          : null;
      final acknowledgement =
          !_editingBeforeApproval && receiptRepository != null
          ? await receiptRepository.saveDraftIdempotent(
              draft.toSaveInput(),
              operationId: draft.pendingSaveOperationId!,
            )
          : null;
      final legacySaved = !_editingBeforeApproval && receiptRepository == null
          ? await _repository.saveDraft(draft.toSaveInput())
          : null;
      if (_inactive) {
        return const _DraftSaveResult(acknowledged: false);
      }
      final recordVersion =
          acknowledgement?.recordVersion ??
          saved?.recordVersion ??
          legacySaved!.recordVersion;
      final updated = draft.copyWith(
        serverRecordVersion: recordVersion,
        pendingSaveOperationId: null,
        pendingSaveExpectedVersion: null,
        pendingSaveRevision: null,
        pendingSavePayloadHash: null,
        submissionIdempotencyKey: _editingBeforeApproval
            ? _uuidFactory()
            : draft.submissionIdempotencyKey,
        updatedAt: acknowledgement?.committedAt ?? DateTime.now().toUtc(),
      );
      _acceptedDraft = updated;
      state = YorksV1MaterialRequestDraftState(
        draft: updated,
        status: YorksV1MaterialRequestDraftSyncStatus.saved,
      );
      try {
        await _persist(updated);
      } catch (_) {
        if (!_inactive) {
          state = YorksV1MaterialRequestDraftState(
            draft: updated,
            status: YorksV1MaterialRequestDraftSyncStatus.saved,
            localPersistenceFailed: true,
          );
        }
      }
      return _DraftSaveResult(
        acknowledged: true,
        request: saved ?? legacySaved,
      );
    } on YorksV1DomainException catch (error) {
      if (_inactive) return const _DraftSaveResult(acknowledged: false);
      final outcomeUnknown =
          draft.hasPendingSave &&
          error.code == YorksV1DomainErrorCode.backendUnavailable;
      final retained = outcomeUnknown
          ? draft
          : draft.copyWith(
              pendingSaveOperationId: null,
              pendingSaveExpectedVersion: null,
              pendingSaveRevision: null,
              pendingSavePayloadHash: null,
            );
      if (!outcomeUnknown && draft.hasPendingSave) {
        try {
          await _persist(retained);
        } catch (_) {}
      }
      state = YorksV1MaterialRequestDraftState(
        draft: retained,
        status: outcomeUnknown
            ? YorksV1MaterialRequestDraftSyncStatus.outcomeUnknown
            : error.code == YorksV1DomainErrorCode.conflict
            ? YorksV1MaterialRequestDraftSyncStatus.conflict
            : YorksV1MaterialRequestDraftSyncStatus.failed,
        errorCode: error.code,
        canRetryUnconfirmed: outcomeUnknown,
      );
      return const _DraftSaveResult(acknowledged: false);
    } catch (error) {
      if (_inactive) return const _DraftSaveResult(acknowledged: false);
      state = YorksV1MaterialRequestDraftState(
        draft: draft,
        status: draft.hasPendingSave
            ? YorksV1MaterialRequestDraftSyncStatus.outcomeUnknown
            : YorksV1MaterialRequestDraftSyncStatus.failed,
        errorCode: YorksV1DomainErrorCode.backendUnavailable,
        canRetryUnconfirmed: draft.hasPendingSave,
      );
      return const _DraftSaveResult(acknowledged: false);
    }
  }

  Future<YorksV1MaterialRequest?> submit() async {
    return _submitWorkflow(approveImmediately: false);
  }

  /// Runs the approved creation-form fast path as one server transaction. It
  /// deliberately cannot be used while re-editing a returned request: that
  /// workflow must remain independently reviewable.
  Future<YorksV1MaterialRequest?> submitAndApprove() async {
    return _submitWorkflow(approveImmediately: true);
  }

  Future<bool> reconcileDraftSave({bool retryIfAbsent = false}) async {
    if (_inactive || _discardInFlight || _connectedCommandInFlight) {
      return false;
    }
    final draft = state.draft;
    final repository =
        _repository is YorksV1MaterialRequestDraftSaveRecoveryRepository
        ? _repository as YorksV1MaterialRequestDraftSaveRecoveryRepository
        : null;
    if (!draft.hasPendingSave || repository == null) return false;
    if (draft.pendingSaveExpectedVersion != draft.serverRecordVersion ||
        draft.pendingSaveRevision != draft.localRevision ||
        draft.pendingSavePayloadHash != draft.savePayloadHash()) {
      state = YorksV1MaterialRequestDraftState(
        draft: draft,
        status: YorksV1MaterialRequestDraftSyncStatus.conflict,
        errorCode: YorksV1DomainErrorCode.conflict,
      );
      return false;
    }
    _beginConnectedCommand();
    state = YorksV1MaterialRequestDraftState(
      draft: draft,
      status: YorksV1MaterialRequestDraftSyncStatus.checkingSave,
    );
    try {
      var acknowledgement = await repository.findDraftSaveResult(
        draft.toSaveInput(),
        operationId: draft.pendingSaveOperationId!,
      );
      if (_inactive) return false;
      if (acknowledgement == null && retryIfAbsent) {
        acknowledgement = await repository.saveDraftIdempotent(
          draft.toSaveInput(),
          operationId: draft.pendingSaveOperationId!,
        );
      }
      if (_inactive) return false;
      if (acknowledgement == null) {
        state = YorksV1MaterialRequestDraftState(
          draft: draft,
          status: YorksV1MaterialRequestDraftSyncStatus.outcomeUnknown,
          errorCode: YorksV1DomainErrorCode.backendUnavailable,
          canRetryUnconfirmed: true,
        );
        return false;
      }
      return await _acceptDraftSaveAcknowledgement(draft, acknowledgement);
    } on YorksV1DomainException catch (error) {
      if (!_inactive) {
        state = YorksV1MaterialRequestDraftState(
          draft: draft,
          status: YorksV1MaterialRequestDraftSyncStatus.outcomeUnknown,
          errorCode: error.code,
          canRetryUnconfirmed:
              error.code == YorksV1DomainErrorCode.backendUnavailable,
        );
      }
      return false;
    } catch (_) {
      if (!_inactive) {
        state = YorksV1MaterialRequestDraftState(
          draft: draft,
          status: YorksV1MaterialRequestDraftSyncStatus.outcomeUnknown,
          errorCode: YorksV1DomainErrorCode.backendUnavailable,
          canRetryUnconfirmed: true,
        );
      }
      return false;
    } finally {
      _connectedCommandInFlight = false;
    }
  }

  Future<bool> _acceptDraftSaveAcknowledgement(
    YorksV1MaterialRequestDraft draft,
    YorksV1MaterialRequestDraftSaveAcknowledgement acknowledgement,
  ) async {
    if (acknowledgement.requestId != draft.id ||
        acknowledgement.operationId != draft.pendingSaveOperationId ||
        acknowledgement.recordVersion <= draft.serverRecordVersion) {
      state = YorksV1MaterialRequestDraftState(
        draft: draft,
        status: YorksV1MaterialRequestDraftSyncStatus.conflict,
        errorCode: YorksV1DomainErrorCode.unexpectedResponse,
      );
      return false;
    }
    final updated = draft.copyWith(
      serverRecordVersion: acknowledgement.recordVersion,
      pendingSaveOperationId: null,
      pendingSaveExpectedVersion: null,
      pendingSaveRevision: null,
      pendingSavePayloadHash: null,
      updatedAt: acknowledgement.committedAt,
    );
    _acceptedDraft = updated;
    state = YorksV1MaterialRequestDraftState(
      draft: updated,
      status: YorksV1MaterialRequestDraftSyncStatus.saved,
    );
    try {
      await _persist(updated);
    } catch (_) {
      if (!_inactive) {
        state = YorksV1MaterialRequestDraftState(
          draft: updated,
          status: YorksV1MaterialRequestDraftSyncStatus.saved,
          localPersistenceFailed: true,
        );
      }
    }
    return true;
  }

  Future<YorksV1MaterialRequest?> _submitWorkflow({
    required bool approveImmediately,
    bool retryUnconfirmed = false,
  }) async {
    if (_inactive ||
        _discardInFlight ||
        _connectedCommandInFlight ||
        state.draft.hasPendingSave) {
      return null;
    }
    if (state.draft.pendingSubmissionApproval != null && !retryUnconfirmed) {
      return reconcileSubmission();
    }
    if (approveImmediately && _editingBeforeApproval) {
      state = YorksV1MaterialRequestDraftState(
        draft: state.draft,
        status: YorksV1MaterialRequestDraftSyncStatus.failed,
        errorCode: YorksV1DomainErrorCode.invalidInput,
      );
      return null;
    }
    final action = approveImmediately
        ? 'submit_and_approve_material_request'
        : 'submit_material_request';
    final feedback = _analytics.expectFeedback(
      action: action,
      screen: AnalyticsScreen.materialRequestDraft,
      operationWasLoading: _connectedCommandInFlight,
    );
    if (_inactive || _discardInFlight || _connectedCommandInFlight) return null;
    _beginConnectedCommand();
    final source = approveImmediately
        ? 'new_submit_and_approve'
        : _editingBeforeApproval
        ? 'edit_before_approval'
        : 'new';
    _analytics.capture(
      AnalyticsEvent.materialRequestSubmissionAttempted,
      properties: {
        AnalyticsProperty.source: source,
        AnalyticsProperty.itemCount: state.draft.lines.length,
        AnalyticsProperty.requestTiming: state.draft.timing,
      },
    );
    final operation = _analytics.beginOperation(
      approveImmediately
          ? 'material_request_submit_and_approve'
          : 'material_request_submit',
      properties: {
        AnalyticsProperty.workflow: 'material_request',
        AnalyticsProperty.source: source,
        AnalyticsProperty.itemCount: state.draft.lines.length,
      },
    );
    try {
      final pending = _submitConnected(
        approveImmediately: approveImmediately,
        preserveUnconfirmed: retryUnconfirmed,
      );
      feedback.feedbackObserved();
      final result = await pending;
      if (_inactive) return null;
      if (result == null) {
        final error =
            _connectedFailure ??
            YorksV1DomainException(
              state.errorCode ?? YorksV1DomainErrorCode.backendUnavailable,
            );
        final unknown =
            state.status ==
            YorksV1MaterialRequestDraftSyncStatus.outcomeUnknown;
        operation.fail(
          error,
          properties: {
            AnalyticsProperty.outcome: unknown ? 'unknown' : 'rejected',
          },
        );
        _analytics.capture(
          unknown
              ? AnalyticsEvent.materialRequestSubmissionUnconfirmed
              : AnalyticsEvent.materialRequestSubmissionFailed,
          properties: {
            AnalyticsProperty.source: source,
            AnalyticsProperty.errorCategory: analyticsErrorCategory(error),
          },
        );
      } else {
        operation.complete();
        _analytics.capture(
          AnalyticsEvent.materialRequestSubmitted,
          properties: {
            AnalyticsProperty.source: source,
            AnalyticsProperty.itemCount: state.draft.lines.length,
          },
        );
        if (approveImmediately) {
          _analytics.capture(
            AnalyticsEvent.materialRequestApproved,
            properties: const {
              AnalyticsProperty.actionType: 'approved',
              AnalyticsProperty.source: 'creation_form',
            },
          );
        }
      }
      return result;
    } finally {
      _connectedCommandInFlight = false;
    }
  }

  Future<YorksV1MaterialRequest?> _submitConnected({
    required bool approveImmediately,
    bool preserveUnconfirmed = false,
  }) async {
    if (_editingBeforeApproval) {
      final saved = await _saveConnected();
      if (_inactive) return null;
      if (saved.acknowledged) {
        // A returned request may pass through this edit/approval cycle more
        // than once. Once this version reaches the server, its local recovery
        // copy must not survive as the starting point for a later return: the
        // next editor visit must hydrate the newer authoritative record
        // version. The auto-disposed family provider drops the in-memory
        // session when the route closes; this removes its persisted twin.
        try {
          await discardLocal(submissionConfirmed: true);
        } catch (_) {
          // The connected command already committed. As with first submit,
          // local cleanup is best effort and cannot turn it into a failure.
        }
        if (_inactive) return null;
        state = YorksV1MaterialRequestDraftState(
          draft: state.draft,
          status: YorksV1MaterialRequestDraftSyncStatus.submitted,
        );
      }
      return saved.request;
    }
    var draft = state.draft;
    if (!draft.canSubmitLocally) {
      _analytics.capture(
        AnalyticsEvent.formValidationFailed,
        properties: const {
          AnalyticsProperty.formType: 'material_request',
          AnalyticsProperty.validationReason: 'incomplete_request',
          AnalyticsProperty.errorCategory: AnalyticsErrorCategory.validation,
        },
      );
      state = YorksV1MaterialRequestDraftState(
        draft: draft,
        status: YorksV1MaterialRequestDraftSyncStatus.failed,
        errorCode: YorksV1DomainErrorCode.invalidInput,
      );
      return null;
    }
    draft = draft.copyWith(pendingSubmissionApproval: approveImmediately);
    state = YorksV1MaterialRequestDraftState(
      draft: draft,
      status: YorksV1MaterialRequestDraftSyncStatus.submitting,
    );
    try {
      await _persist(draft);
    } catch (_) {
      if (_inactive) return null;
      if (preserveUnconfirmed) {
        _markSubmissionUnknown(
          draft,
          YorksV1DomainErrorCode.backendUnavailable,
        );
        return null;
      }
      state = YorksV1MaterialRequestDraftState(
        draft: draft.copyWith(pendingSubmissionApproval: null),
        status: YorksV1MaterialRequestDraftSyncStatus.failed,
        errorCode: YorksV1DomainErrorCode.backendUnavailable,
      );
      return null; // No RPC was issued without a durable intent.
    }
    if (_inactive) return null;
    YorksV1MaterialRequest? submitted;
    try {
      submitted = approveImmediately
          ? await _repository.saveSubmitAndApprove(draft)
          : await _repository.saveAndSubmit(draft);
    } on YorksV1DomainException catch (error) {
      if (_inactive) return null;
      _connectedFailure = error;
      if (preserveUnconfirmed ||
          (error.code == YorksV1DomainErrorCode.backendUnavailable &&
              error.serverCode == null) ||
          error.code == YorksV1DomainErrorCode.unexpectedResponse) {
        _markSubmissionUnknown(draft, error.code);
        return null;
      }
      draft = draft.copyWith(pendingSubmissionApproval: null);
      try {
        await _persist(draft);
      } catch (_) {
        /* Retain recovery conservatively. */
      }
      if (_inactive) return null;
      if (error.code == YorksV1DomainErrorCode.conflict) {
        final rebased = await _rebaseAmbiguousInitialSave(draft);
        if (_inactive) return null;
        if (rebased != null) {
          return _submitConnected(approveImmediately: approveImmediately);
        } else {
          state = YorksV1MaterialRequestDraftState(
            draft: draft,
            status: YorksV1MaterialRequestDraftSyncStatus.conflict,
            errorCode: error.code,
          );
          return null;
        }
      }
      if (submitted == null) {
        var nextDraft = draft;
        final shouldRefreshIdempotency =
            error.code != YorksV1DomainErrorCode.conflict &&
            error.serverCode != null &&
            (error.serverCode == '22023' || error.serverCode == '55P03');
        if (shouldRefreshIdempotency) {
          nextDraft = draft.copyWith(
            submissionIdempotencyKey: _uuidFactory(),
            updatedAt: DateTime.now().toUtc(),
          );
          state = YorksV1MaterialRequestDraftState(
            draft: nextDraft,
            status: YorksV1MaterialRequestDraftSyncStatus.failed,
            errorCode: error.code,
          );
          await _persist(nextDraft);
          if (_inactive) return null;
        }
        state = YorksV1MaterialRequestDraftState(
          draft: nextDraft,
          status: error.code == YorksV1DomainErrorCode.conflict
              ? YorksV1MaterialRequestDraftSyncStatus.conflict
              : YorksV1MaterialRequestDraftSyncStatus.failed,
          errorCode: error.code,
        );
        return null;
      }
    } catch (error) {
      if (_inactive) return null;
      _connectedFailure = error;
      _markSubmissionUnknown(draft, YorksV1DomainErrorCode.backendUnavailable);
      return null;
    }

    if (_inactive) return null;

    // The server transition has succeeded. Local cleanup is best effort and
    // must never turn an authoritative submission into a false failure state
    // (for example when browser storage is unavailable or a late draft write
    // is still draining).
    try {
      await discardLocal(submissionConfirmed: true);
    } catch (_) {
      // The submitted server record remains authoritative; the next refresh
      // can safely reconcile any stale local recovery copy.
    }
    if (_inactive) return null;
    state = YorksV1MaterialRequestDraftState(
      draft: state.draft,
      status: YorksV1MaterialRequestDraftSyncStatus.submitted,
    );
    return submitted;
  }

  void _markSubmissionUnknown(
    YorksV1MaterialRequestDraft draft,
    YorksV1DomainErrorCode? error,
  ) {
    state = YorksV1MaterialRequestDraftState(
      draft: draft,
      status: YorksV1MaterialRequestDraftSyncStatus.outcomeUnknown,
      errorCode: error,
    );
  }

  Future<YorksV1MaterialRequest?> reconcileSubmission() async {
    if (_inactive || _discardInFlight || _connectedCommandInFlight) return null;
    final draft = state.draft;
    final mode = draft.pendingSubmissionApproval;
    final repository = _repository;
    if (mode == null ||
        repository is! YorksV1MaterialRequestSubmissionRecoveryRepository) {
      return null;
    }
    _beginConnectedCommand();
    state = YorksV1MaterialRequestDraftState(
      draft: draft,
      status: YorksV1MaterialRequestDraftSyncStatus.checkingSubmission,
    );
    try {
      final result =
          await (repository
                  as YorksV1MaterialRequestSubmissionRecoveryRepository)
              .findSubmissionResult(draft, approveImmediately: mode);
      if (_inactive) return null;
      if (result == null) {
        state = YorksV1MaterialRequestDraftState(
          draft: draft,
          status: YorksV1MaterialRequestDraftSyncStatus.outcomeUnknown,
          canRetryUnconfirmed: true,
        );
        return null;
      }
      try {
        await discardLocal(submissionConfirmed: true);
      } catch (_) {}
      if (_inactive) return null;
      state = YorksV1MaterialRequestDraftState(
        draft: draft,
        status: YorksV1MaterialRequestDraftSyncStatus.submitted,
      );
      _analytics.capture(AnalyticsEvent.materialRequestSubmissionReconciled);
      return result;
    } on YorksV1DomainException catch (error) {
      if (!_inactive) _markSubmissionUnknown(draft, error.code);
      return null;
    } catch (_) {
      if (!_inactive) {
        _markSubmissionUnknown(
          draft,
          YorksV1DomainErrorCode.backendUnavailable,
        );
      }
      return null;
    } finally {
      _connectedCommandInFlight = false;
    }
  }

  Future<YorksV1MaterialRequest?> retryUnconfirmedSubmission() async {
    if (_inactive ||
        _discardInFlight ||
        !state.canRetryUnconfirmed ||
        _connectedCommandInFlight) {
      return null;
    }
    final mode = state.draft.pendingSubmissionApproval;
    if (mode == null) return null;
    return _submitWorkflow(approveImmediately: mode, retryUnconfirmed: true);
  }

  /// Recovers the one safe stale-version case caused by an ambiguous first
  /// save response: the server committed version 1, while the browser still
  /// holds version 0. A later version remains a real competing-writer conflict
  /// and is never rebased automatically.
  ///
  /// The remote rows must still be present in the local draft. This permits a
  /// user to append more rows after the response was lost, while refusing to
  /// overwrite a different first-save snapshot or a draft changed elsewhere.
  Future<YorksV1MaterialRequestDraft?> _rebaseAmbiguousInitialSave(
    YorksV1MaterialRequestDraft draft,
  ) async {
    if (draft.serverRecordVersion != 0) return null;
    try {
      final remote = await _repository.getRequest(draft.id);
      if (_inactive) return null;
      final localLineIds = draft.lines.map((line) => line.id).toSet();
      final sameDraftBoundary =
          remote.state.isDraft &&
          remote.recordVersion == 1 &&
          remote.projectId == draft.projectId &&
          remote.scopeId == draft.scopeId &&
          remote.lines.every((line) => localLineIds.contains(line.id));
      if (!sameDraftBoundary) return null;

      final rebased = draft.copyWith(
        serverRecordVersion: remote.recordVersion,
        submissionIdempotencyKey: _uuidFactory(),
        updatedAt: DateTime.now().toUtc(),
      );
      await _persist(rebased);
      if (_inactive) return null;
      state = YorksV1MaterialRequestDraftState(
        draft: rebased,
        status: YorksV1MaterialRequestDraftSyncStatus.submitting,
      );
      return rebased;
    } catch (_) {
      return null;
    }
  }

  Future<void> discardLocal({
    bool requireServerConfirmation = false,
    bool submissionConfirmed = false,
    YorksV1MaterialRequestDraft? expectedDraft,
  }) async {
    var ownsDiscard = false;
    VoidCallback? releaseRetention;
    final operation = requireServerConfirmation
        ? _analytics.beginOperation(
            'material_request_draft_delete',
            properties: const {
              AnalyticsProperty.workflow: 'material_request',
              AnalyticsProperty.source: 'recovery_list',
            },
          )
        : null;
    if (requireServerConfirmation) {
      _analytics.capture(AnalyticsEvent.materialRequestDraftDeleteAttempted);
    }
    try {
      if (_inactive ||
          _discardInFlight ||
          (!submissionConfirmed &&
              (_connectedCommandInFlight ||
                  state.draft.pendingSubmissionApproval != null ||
                  state.draft.hasPendingSave))) {
        if (requireServerConfirmation) {
          throw const YorksV1DomainException(
            YorksV1DomainErrorCode.invalidTransition,
          );
        }
        return;
      }
      final displayed = expectedDraft ?? state.draft;
      if (displayed.id != _draftId ||
          displayed.ownerAuthUserId != _ownerAuthUserId ||
          (requireServerConfirmation && displayed.serverRecordVersion > 0)) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.invalidTransition,
        );
      }
      if (requireServerConfirmation &&
          state.draft.hasRecoverableContent &&
          state.draft.updatedAt.isAfter(displayed.updatedAt)) {
        throw const YorksV1DomainException(YorksV1DomainErrorCode.conflict);
      }
      _discardInFlight = true;
      ownsDiscard = true;
      releaseRetention = _retainForDeletion?.call();
      _privateSyncRequested = false;
      _privateSyncDebounce?.cancel();
      // Let a previously issued sync settle before retiring its server copy.
      // New edits/syncs are blocked during this barrier.
      if (requireServerConfirmation) {
        await _privateHydration;
        await _privateSyncDrain;
      }
      _recoveryGeneration++;
      if (requireServerConfirmation &&
          state.draft.hasRecoverableContent &&
          state.draft.updatedAt.isAfter(displayed.updatedAt)) {
        throw const YorksV1DomainException(YorksV1DomainErrorCode.conflict);
      }
      await _persistQueue;
      if (_inactive) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.unauthenticated,
        );
      }
      final repository = _phase2Repository;
      var syncVersion = displayed.privateSyncVersion;
      if (state.draft.updatedAt == displayed.updatedAt) {
        syncVersion = state.draft.privateSyncVersion > syncVersion
            ? state.draft.privateSyncVersion
            : syncVersion;
      }
      if (requireServerConfirmation) {
        state = YorksV1MaterialRequestDraftState(
          draft: displayed,
          status: YorksV1MaterialRequestDraftSyncStatus.deleting,
        );
        if (repository != null) {
          if (syncVersion == 0) {
            YorksV1PrivateMaterialRequestDraftRecord? remote;
            try {
              remote = await repository.getPrivateDraft(
                draftId: _draftId,
                ownerAuthUserId: _ownerAuthUserId,
                submissionIdempotencyKey: displayed.submissionIdempotencyKey,
              );
            } on YorksV1DomainException catch (error) {
              if (error.serverMessage != 'V1_PRIVATE_DRAFT_DELETED') rethrow;
              // A prior delete committed but device cleanup failed. Retrying
              // remains safe even though the private row no longer exists.
            }
            if (_inactive) {
              throw const YorksV1DomainException(
                YorksV1DomainErrorCode.unauthenticated,
              );
            }
            if (remote != null &&
                (remote.clientUpdatedAt.isAfter(displayed.updatedAt) ||
                    remote.draft.savePayloadHash() !=
                        displayed.savePayloadHash())) {
              throw const YorksV1DomainException(
                YorksV1DomainErrorCode.conflict,
              );
            }
            syncVersion = remote?.syncVersion ?? 0;
          }
          await repository.deletePrivateDraft(
            draftId: _draftId,
            expectedSyncVersion: syncVersion,
            idempotencyKey: _uuidFactory(),
          );
          if (_inactive) {
            throw const YorksV1DomainException(
              YorksV1DomainErrorCode.unauthenticated,
            );
          }
        }
      }
      await _mutateStore(
        (all) => all
            .where(
              (draft) =>
                  draft.id != _draftId ||
                  draft.ownerAuthUserId != _ownerAuthUserId,
            )
            .toList(growable: false),
      );
      if (_inactive) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.unauthenticated,
        );
      }
      _onLocalDraftsChanged?.call();
      if (!requireServerConfirmation && repository != null && syncVersion > 0) {
        try {
          await repository.deletePrivateDraft(
            draftId: _draftId,
            expectedSyncVersion: syncVersion,
            idempotencyKey: _uuidFactory(),
          );
        } catch (_) {
          /* Confirmed workflow outcome remains authoritative. */
        }
      }
      if (requireServerConfirmation) {
        state = YorksV1MaterialRequestDraftState(
          draft: displayed,
          status: YorksV1MaterialRequestDraftSyncStatus.deleted,
        );
        _discarded = true;
        _analytics.capture(
          AnalyticsEvent.materialRequestDraftDeleted,
          properties: const {AnalyticsProperty.success: true},
        );
        operation?.complete();
      }
    } catch (error) {
      if (requireServerConfirmation) {
        _analytics.capture(
          AnalyticsEvent.materialRequestDraftDeleteFailed,
          properties: {
            AnalyticsProperty.success: false,
            AnalyticsProperty.errorCategory: analyticsErrorCategory(error),
          },
        );
        operation?.fail(error);
        if (!_inactive) {
          state = YorksV1MaterialRequestDraftState(
            draft: state.draft,
            status: YorksV1MaterialRequestDraftSyncStatus.failed,
            errorCode: error is YorksV1DomainException
                ? error.code
                : YorksV1DomainErrorCode.backendUnavailable,
          );
        }
      }
      rethrow;
    } finally {
      if (ownsDiscard) _discardInFlight = false;
      releaseRetention?.call();
    }
  }

  /// Retire a stale device copy only after the trusted owner RPC confirms it.
  Future<void> _clearRetiredRecovery() async {
    if (_inactive ||
        _discardInFlight ||
        _connectedCommandInFlight ||
        state.draft.serverRecordVersion > 0 ||
        state.draft.hasPendingSave ||
        state.draft.pendingSubmissionApproval != null) {
      return;
    }
    _discardInFlight = true;
    _privateSyncRequested = false;
    _privateSyncDebounce?.cancel();
    _recoveryGeneration++;
    try {
      await _persistQueue;
      if (_inactive) return;
      await _mutateStore(
        (all) => all
            .where(
              (draft) =>
                  draft.id != _draftId ||
                  draft.ownerAuthUserId != _ownerAuthUserId,
            )
            .toList(),
      );
      if (_inactive) return;
      state = YorksV1MaterialRequestDraftState(
        draft: state.draft,
        status: YorksV1MaterialRequestDraftSyncStatus.deleted,
      );
      _discarded = true;
      _onLocalDraftsChanged?.call();
    } catch (_) {
      if (!_inactive) {
        state = YorksV1MaterialRequestDraftState(
          draft: state.draft,
          status: YorksV1MaterialRequestDraftSyncStatus.deleted,
          errorCode: YorksV1DomainErrorCode.backendUnavailable,
          localPersistenceFailed: true,
        );
        _discarded = true;
      }
    } finally {
      _discardInFlight = false;
    }
  }

  Future<void> _mutateStore(
    List<YorksV1MaterialRequestDraft> Function(
      List<YorksV1MaterialRequestDraft>,
    )
    change,
  ) async {
    final store = _store;
    if (store is YorksV1MaterialRequestDraftStore) {
      await store.mutate(change);
    } else {
      await store.writeAll(change(store.readAll()));
    }
  }

  /// Restores the last deliberately accepted draft snapshot when an editor
  /// chooses to discard only the changes made during its current visit.
  ///
  /// Text fields autosave for crash recovery, so simply leaving the route
  /// would otherwise make "Discard changes" misleading. The presentation
  /// layer owns the baseline choice; this controller only validates ownership
  /// and persists that immutable snapshot through the normal draft store.
  Future<void> restoreLocalSnapshot(
    YorksV1MaterialRequestDraft snapshot,
  ) async {
    if (_inactive ||
        _discardInFlight ||
        state.draft.pendingSubmissionApproval != null) {
      return;
    }
    if (snapshot.id != _draftId ||
        snapshot.ownerAuthUserId != _ownerAuthUserId) {
      throw ArgumentError('The draft snapshot does not belong to this editor.');
    }
    await _persist(snapshot);
    _acceptedDraft = snapshot;
    state = YorksV1MaterialRequestDraftState(
      draft: snapshot,
      status: snapshot.serverRecordVersion > 0
          ? YorksV1MaterialRequestDraftSyncStatus.saved
          : YorksV1MaterialRequestDraftSyncStatus.local,
    );
  }

  Future<void> _replace(YorksV1MaterialRequestDraft draft) async {
    if (_inactive ||
        _discardInFlight ||
        _connectedCommandInFlight ||
        state.draft.hasPendingSave ||
        state.draft.pendingSubmissionApproval != null ||
        state.status == YorksV1MaterialRequestDraftSyncStatus.submitted) {
      return;
    }
    final updated = draft.copyWith(
      localRevision: state.draft.localRevision + 1,
      submissionIdempotencyKey: _uuidFactory(),
      updatedAt: DateTime.now().toUtc(),
    );
    // Update the in-memory state before awaiting device storage. Text-field
    // callbacks are intentionally fire-and-forget; waiting here made the
    // submit button observe the previous line values when a user typed and
    // submitted quickly.
    state = YorksV1MaterialRequestDraftState(draft: updated);
    await _persist(updated);
    _schedulePrivateSync();
  }

  void _schedulePrivateSync() {
    if (_inactive ||
        _discardInFlight ||
        _connectedCommandInFlight ||
        state.draft.hasPendingSave ||
        state.draft.pendingSubmissionApproval != null ||
        state.status == YorksV1MaterialRequestDraftSyncStatus.submitted) {
      return;
    }
    if (_phase2Repository == null || state.draft.serverRecordVersion > 0) {
      return;
    }
    _privateSyncDebounce?.cancel();
    _privateSyncDebounce = Timer(
      _privateSyncDebounceDuration,
      _requestPrivateSync,
    );
  }

  void _requestPrivateSync() {
    if (_inactive || _discardInFlight || _connectedCommandInFlight) return;
    _privateSyncRequested = true;
    if (_privateSyncInFlight) return;
    _startPrivateSync();
  }

  void _startPrivateSync() {
    _privateSyncDrain ??= _drainPrivateSync().whenComplete(() {
      _privateSyncDrain = null;
      if (_privateSyncRequested && !_inactive && !_discardInFlight) {
        _startPrivateSync();
      }
    });
  }

  Future<void> _drainPrivateSync() async {
    if (_privateSyncInFlight || _inactive) return;
    _privateSyncInFlight = true;
    try {
      while (_privateSyncRequested && !_inactive) {
        _privateSyncRequested = false;
        await _syncPrivateDraftOnce();
      }
    } finally {
      _privateSyncInFlight = false;
      // Close the narrow hand-off race where a debounce fires after the loop
      // observes no queued work but before this in-flight flag is released.
    }
  }

  Future<void> _syncPrivateDraftOnce() async {
    final repository = _phase2Repository;
    final snapshot = state.draft;
    final generation = _recoveryGeneration;
    if (_connectedCommandInFlight) return;
    if (repository == null || snapshot.serverRecordVersion > 0) return;
    if (!snapshot.hasRecoverableContent) return;
    state = YorksV1MaterialRequestDraftState(
      draft: snapshot,
      status: YorksV1MaterialRequestDraftSyncStatus.syncingToAccount,
    );
    try {
      final remote = await repository.syncPrivateDraft(
        YorksV1SyncPrivateMaterialRequestDraftInput(
          draft: snapshot,
          idempotencyKey: _uuidFactory(),
        ),
      );
      if (!_recoveryIsCurrent(generation)) return;
      final current = state.draft;
      final reconciled = current.copyWith(
        privateSyncVersion: remote.syncVersion,
        privateSyncedAt: remote.serverUpdatedAt,
      );
      state = YorksV1MaterialRequestDraftState(
        draft: reconciled,
        status: current.updatedAt == snapshot.updatedAt
            ? YorksV1MaterialRequestDraftSyncStatus.savedToAccount
            : YorksV1MaterialRequestDraftSyncStatus.local,
      );
      await _persist(reconciled);
    } on YorksV1DomainException catch (error) {
      if (!_recoveryIsCurrent(generation)) return;
      if (error.serverMessage == 'V1_PRIVATE_DRAFT_DELETED') {
        await _clearRetiredRecovery();
        return;
      }
      final current = state.draft;
      state = YorksV1MaterialRequestDraftState(
        draft: current,
        status: error.code == YorksV1DomainErrorCode.conflict
            ? YorksV1MaterialRequestDraftSyncStatus.conflict
            : YorksV1MaterialRequestDraftSyncStatus.local,
        errorCode: error.code == YorksV1DomainErrorCode.conflict
            ? error.code
            : null,
      );
    } catch (_) {
      if (!_recoveryIsCurrent(generation)) return;
      state = YorksV1MaterialRequestDraftState(
        draft: state.draft,
        status: YorksV1MaterialRequestDraftSyncStatus.local,
      );
    }
  }

  Future<void> _persist(YorksV1MaterialRequestDraft draft) async {
    final operation = _persistQueue.then((_) async {
      if (_inactive) return;
      await _mutateStore((all) {
        final replaced = <YorksV1MaterialRequestDraft>[];
        var found = false;
        for (final stored in all) {
          if (stored.id == _draftId &&
              stored.ownerAuthUserId == _ownerAuthUserId) {
            replaced.add(draft);
            found = true;
          } else {
            replaced.add(stored);
          }
        }
        if (!found) replaced.add(draft);
        return replaced;
      });
      if (!_inactive) _onLocalDraftsChanged?.call();
    });
    // Keep the queue usable after an individual local-storage failure while
    // still returning the original error to the caller.
    _persistQueue = operation.catchError((_) {});
    await operation;
  }

  @override
  void dispose() {
    _disposed = true;
    _privateSyncDebounce?.cancel();
    super.dispose();
  }

  static String _canonicalValue(
    YorksV1BoqWorksheet worksheet,
    YorksV1BoqRow row,
    YorksV1BoqCanonicalField field, {
    bool nullable = false,
  }) {
    final value = row.canonicalValues[field.wireValue];
    if (value != null && '$value'.trim().isNotEmpty) return '$value'.trim();
    final column = worksheet.columns
        .where((item) => item.canonicalField == field)
        .firstOrNull;
    final fallback = column == null ? null : row.valueFor(column.id);
    final text = fallback?.toString().trim() ?? '';
    return nullable && text.isEmpty ? '' : text;
  }

  static String _boqValue(
    YorksV1BoqWorksheet worksheet,
    YorksV1BoqRow row,
    YorksV1BoqCanonicalField field, {
    required String headingPattern,
  }) {
    final canonical = _canonicalValue(worksheet, row, field, nullable: true);
    if (canonical.isNotEmpty) return canonical;
    final matcher = RegExp(headingPattern, caseSensitive: false);
    for (final column in worksheet.columns) {
      if (!matcher.hasMatch(column.heading)) continue;
      final value = row.valueFor(column.id)?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static String _composeDescription({
    required String tag,
    required String context,
  }) {
    if (tag.isEmpty) return context;
    if (context.isEmpty || context.toLowerCase() == tag.toLowerCase()) {
      return tag;
    }
    return '$tag — $context';
  }
}

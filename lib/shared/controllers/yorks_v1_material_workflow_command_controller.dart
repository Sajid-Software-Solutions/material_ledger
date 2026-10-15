import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/yorks_v1_arrangement.dart';
import '../models/analytics_event.dart';
import '../models/yorks_v1_command_outcome.dart';
import '../repositories/yorks_v1_command_outcome_repository.dart';
import '../services/analytics_service.dart';
import '../models/yorks_v1_domain_error.dart';
import '../models/yorks_v1_logistics.dart';
import '../models/yorks_v1_material_request.dart';
import '../repositories/yorks_v1_arrangement_repository.dart';
import '../repositories/yorks_v1_logistics_repository.dart';
import '../repositories/yorks_v1_material_request_repository.dart';
import '../services/yorks_v1_critical_command_key_store.dart';

/// An existing opaque command lease in this request's known entity scope.
/// It contains no saved business payload and can only be checked, never replayed.
class YorksV1PendingWorkflowCommand {
  const YorksV1PendingWorkflowCommand({
    required this.operation,
    required this.entityId,
    required this.requestId,
  });
  final String operation;
  final String entityId;
  final String requestId;
}

/// Presentation-facing boundary for critical Material Request transitions.
///
/// Widgets supply typed intent only. This controller owns persistent retry
/// keys and delegates the server-confirmed mutation to the correct repository.
class YorksV1MaterialWorkflowCommandController {
  YorksV1MaterialWorkflowCommandController({
    required YorksV1MaterialRequestRepository materialRequests,
    required YorksV1ArrangementRepository arrangements,
    required YorksV1LogisticsRepository logistics,
    required YorksV1CriticalCommandKeyStore commandKeys,
    YorksV1CommandOutcomeRepository? outcomes,
    AnalyticsService analytics = const NoopAnalyticsService(),
    void Function() Function()? beginActivity,
    bool Function()? isCurrentAuthority,
    void Function(String entityId, YorksV1CommandPhase phase)? onPhase,
    Future<void> Function(Duration duration)? delay,
  }) : _materialRequests = materialRequests,
       _arrangements = arrangements,
       _logistics = logistics,
       _commandKeys = commandKeys,
       _outcomes = outcomes,
       _analytics = analytics,
       _beginActivity = beginActivity,
       _isCurrentAuthority = isCurrentAuthority,
       _onPhase = onPhase,
       _delay = delay ?? Future<void>.delayed;

  final YorksV1MaterialRequestRepository _materialRequests;
  final YorksV1ArrangementRepository _arrangements;
  final YorksV1LogisticsRepository _logistics;
  final YorksV1CriticalCommandKeyStore _commandKeys;
  final YorksV1CommandOutcomeRepository? _outcomes;
  final AnalyticsService _analytics;
  final void Function() Function()? _beginActivity;
  final bool Function()? _isCurrentAuthority;
  final void Function(String, YorksV1CommandPhase)? _onPhase;
  final Future<void> Function(Duration) _delay;
  final Map<String, Future<Object?>> _inFlight = {};
  final Map<String, String> _activePayloads = {};
  final Map<String, Future<YorksV1MaterialRequest?>> _decisionRestores = {};
  final Map<String, Future<YorksV1WorkflowCommandOutcome>> _manualChecks = {};

  bool hasPendingCommand(String operation, String entityId) =>
      _commandName(operation) != null &&
      _commandKeys.hasPendingDispatch(operation, entityId);

  /// Enumerates only existing leases belonging to the currently readable
  /// request and its known arrangement/dispatch identities. Prepared Procurement
  /// saves and dispatches retain their dedicated recovery panel and budget.
  List<YorksV1PendingWorkflowCommand> pendingCommandsForRequest(
    String requestId, {
    Iterable<String> arrangementIds = const [],
    Iterable<String> dispatchIds = const [],
  }) => [
    for (final operation in const [
      'decide_material_request_approved',
      'decide_material_request_returned',
      'begin_arrangement',
      'cancel_material_request',
      'close_material_request',
    ])
      if (hasPendingCommand(operation, requestId))
        YorksV1PendingWorkflowCommand(
          operation: operation,
          entityId: requestId,
          requestId: requestId,
        ),
    if (_commandKeys.hasTrackedPendingDispatch('dispatch_materials', requestId))
      YorksV1PendingWorkflowCommand(
        operation: 'dispatch_materials',
        entityId: requestId,
        requestId: requestId,
      ),
    for (final id in arrangementIds.toSet())
      if (_commandKeys.hasTrackedPendingDispatch('save_arrangement', id))
        YorksV1PendingWorkflowCommand(
          operation: 'save_arrangement',
          entityId: id,
          requestId: requestId,
        ),
    for (final id in arrangementIds.toSet())
      for (final operation in const [
        'decide_arrangement_approved',
        'decide_arrangement_returned',
      ])
        if (hasPendingCommand(operation, id))
          YorksV1PendingWorkflowCommand(
            operation: operation,
            entityId: id,
            requestId: requestId,
          ),
    for (final id in dispatchIds.toSet())
      for (final operation in const [
        'confirm_receipt',
        'generate_delivery_order',
      ])
        if (hasPendingCommand(operation, id))
          YorksV1PendingWorkflowCommand(
            operation: operation,
            entityId: id,
            requestId: requestId,
          ),
  ];

  /// An explicit read of the original key. Automatic retry limits never apply
  /// to this user action, and no payload or replacement key is reconstructed.
  Future<YorksV1CommandReceipt?> checkCommandStatus(
    YorksV1PendingWorkflowCommand pending,
  ) async {
    final key = _commandKeys.pendingKey(pending.operation, pending.entityId);
    if (key == null ||
        !hasPendingCommand(pending.operation, pending.entityId)) {
      return null;
    }
    final result = await _manualOutcome(
      pending.operation,
      pending.entityId,
      pending.requestId,
      key,
    );
    return result.receipt;
  }

  Future<YorksV1WorkflowCommandOutcome> _manualOutcome(
    String operation,
    String entityId,
    String requestId,
    String key,
  ) {
    final identity = '$operation:$entityId:$key';
    return _manualChecks.putIfAbsent(identity, () async {
      try {
        return await _lookupOriginalOutcome(
          operation,
          entityId,
          requestId,
          key,
        );
      } finally {
        _manualChecks.remove(identity);
      }
    });
  }

  Future<YorksV1WorkflowCommandOutcome> _lookupOriginalOutcome(
    String operation,
    String entityId,
    String requestId,
    String key,
  ) async {
    final command = _commandName(operation);
    if (command == null) throw ArgumentError.value(operation, 'operation');
    if (_isCurrentAuthority?.call() == false) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unauthenticated,
      );
    }
    _emit(command, key, entityId, YorksV1CommandPhase.checking);
    try {
      final result = await _outcomes?.check(command, key);
      if (_isCurrentAuthority?.call() == false) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.unauthenticated,
        );
      }
      final receipt = result?.receipt;
      if (result?.confirmed == true &&
          receipt != null &&
          receipt.commandKey == key &&
          receipt.commandName == command &&
          receipt.entityId == requestId) {
        _emit(command, key, entityId, YorksV1CommandPhase.confirmed);
        await _retire(operation, entityId, key);
        if (_isCurrentAuthority?.call() == false) {
          throw const YorksV1DomainException(
            YorksV1DomainErrorCode.unauthenticated,
          );
        }
        return result!;
      }
    } on YorksV1DomainException catch (error) {
      if (error.code == YorksV1DomainErrorCode.unauthenticated) rethrow;
    } catch (_) {
      // An unavailable read never establishes that the original command failed.
    }
    _emit(command, key, entityId, YorksV1CommandPhase.unknown);
    throw YorksV1CommandOutcomeUnknown(key);
  }

  Future<T> _loadConfirmedView<T>(
    YorksV1WorkflowCommandOutcome outcome,
    String operation,
    String entityId,
    String requestId,
    String key,
  ) async {
    try {
      final response = await outcome.loadResponse();
      if (_isCurrentAuthority?.call() == false) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.unauthenticated,
        );
      }
      if (response == null ||
          (response['request_id'] ?? response['id']) != requestId) {
        throw StateError('view_unavailable');
      }
      return _decode<T>(response);
    } catch (error) {
      if (_isCurrentAuthority?.call() == false) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.unauthenticated,
        );
      }
      _emit(
        _commandName(operation)!,
        key,
        entityId,
        YorksV1CommandPhase.confirmedViewUnavailable,
      );
      throw YorksV1CommittedViewUnavailable(outcome.receipt!, cause: error);
    }
  }

  void _emit(
    String operation,
    String key,
    String entityId,
    YorksV1CommandPhase phase,
  ) {
    if (_isCurrentAuthority?.call() == false) return;
    try {
      _onPhase?.call(entityId, phase);
    } catch (_) {
      /* Disposed presentation cannot reject an acknowledged command. */
    }
    try {
      _analytics.capture(
        AnalyticsEvent.commandOutcomeChanged,
        properties: {
          AnalyticsProperty.operation: operation,
          AnalyticsProperty.commandFingerprint: sha256
              .convert(utf8.encode('$operation|$key'))
              .toString()
              .substring(0, 32),
          AnalyticsProperty.commandPhase: 'command',
          AnalyticsProperty.outcome: phase.name,
        },
      );
    } catch (_) {
      /* Telemetry cannot change command truth. */
    }
  }

  Future<YorksV1MaterialRequest> decideMaterialRequest(
    YorksV1DecideMaterialRequestInput input,
  ) => _run(
    operation: 'decide_material_request_${input.decision.wireValue}',
    entityId: input.requestId,
    payload: input.toRpcPayload(),
    invoke: (key) => _materialRequests.decideRequest(
      YorksV1DecideMaterialRequestInput(
        requestId: input.requestId,
        expectedVersion: input.expectedVersion,
        decision: input.decision,
        reason: input.reason,
        idempotencyKey: key,
      ),
    ),
  );

  /// Restore only the status of an existing decision. Never resend a mutation.
  Future<YorksV1MaterialRequest?> restoreDecisionStatus(String requestId) {
    final active = _decisionRestores[requestId];
    if (active != null) return active;
    late final Future<YorksV1MaterialRequest?> future;
    future = _restoreDecisionStatus(requestId).whenComplete(() {
      if (identical(_decisionRestores[requestId], future)) {
        _decisionRestores.remove(requestId);
      }
    });
    _decisionRestores[requestId] = future;
    return future;
  }

  Future<YorksV1MaterialRequest?> _restoreDecisionStatus(
    String requestId,
  ) async {
    if (_outcomes == null || _isCurrentAuthority?.call() == false) return null;
    for (final decision in ['approved', 'returned']) {
      final operation = 'decide_material_request_$decision';
      final key = _commandKeys.pendingKey(operation, requestId);
      if (key == null) continue;
      if (!await _commandKeys.wasDispatched(operation, requestId, key)) {
        _emit(
          'v1_decide_material_request',
          key,
          requestId,
          YorksV1CommandPhase.notSent,
        );
        continue;
      }
      _emit(
        'v1_decide_material_request',
        key,
        requestId,
        YorksV1CommandPhase.unknown,
      );
      for (var attempt = 0; attempt < 3; attempt++) {
        if (_isCurrentAuthority?.call() == false) return null;
        bool claimed;
        try {
          claimed = await _commandKeys.claimAutomaticCheck(
            operation,
            requestId,
            key,
          );
        } catch (_) {
          // No durable budget means no automatic read can safely be scheduled.
          break;
        }
        if (!claimed) break;
        if (attempt > 0) await _delay(Duration(milliseconds: 500 * attempt));
        try {
          return await checkDecisionStatus(requestId);
        } on YorksV1CommandOutcomeUnknown {
          // Bounded status reads only; the frozen command is never replayed.
        }
      }
      _emit(
        'v1_decide_material_request',
        key,
        requestId,
        YorksV1CommandPhase.unknown,
      );
      return null;
    }
    return null;
  }

  Future<YorksV1MaterialRequest?> checkDecisionStatus(String requestId) async {
    if (_outcomes == null) return null;
    for (final decision in ['approved', 'returned']) {
      final operation = 'decide_material_request_$decision';
      final key = _commandKeys.pendingKey(operation, requestId);
      if (key == null) continue;
      final outcome = await _manualOutcome(
        operation,
        requestId,
        requestId,
        key,
      );
      return _loadConfirmedView<YorksV1MaterialRequest>(
        outcome,
        operation,
        requestId,
        requestId,
        key,
      );
    }
    return null;
  }

  bool hasPendingReceipt(String dispatchId) =>
      _commandKeys.hasPendingDispatch('confirm_receipt', dispatchId);

  /// The receipt payload is deliberately not reconstructed or replayed.
  Future<YorksV1LogisticsWorkspace?> checkReceiptStatus(
    String requestId,
    String dispatchId,
  ) async {
    final key = _commandKeys.pendingKey('confirm_receipt', dispatchId);
    if (_outcomes == null || key == null) return null;
    final outcome = await _manualOutcome(
      'confirm_receipt',
      dispatchId,
      requestId,
      key,
    );
    return _loadConfirmedView<YorksV1LogisticsWorkspace>(
      outcome,
      'confirm_receipt',
      dispatchId,
      requestId,
      key,
    );
  }

  Future<List<YorksV1MaterialRequestComment>> addMaterialRequestComment(
    YorksV1AddMaterialRequestCommentInput input,
  ) => _run(
    operation: 'add_material_request_comment',
    entityId: input.requestId,
    payload: input.toRpcPayload(),
    invoke: (key) => _materialRequests.addComment(
      YorksV1AddMaterialRequestCommentInput(
        requestId: input.requestId,
        body: input.body,
        mentionedAuthUserIds: input.mentionedAuthUserIds,
        attachmentIds: input.attachmentIds,
        parentCommentId: input.parentCommentId,
        contextType: input.contextType,
        contextEntityId: input.contextEntityId,
        idempotencyKey: key,
      ),
    ),
  );

  Future<YorksV1ArrangementWorkspace> beginArrangement(
    YorksV1BeginArrangementInput input,
  ) => _run(
    operation: 'begin_arrangement',
    entityId: input.requestId,
    payload: input.toRpcPayload(),
    invoke: (key) => _arrangements.begin(
      YorksV1BeginArrangementInput(
        requestId: input.requestId,
        expectedRequestVersion: input.expectedRequestVersion,
        idempotencyKey: key,
      ),
    ),
  );

  Future<YorksV1ArrangementWorkspace> saveArrangement(
    YorksV1SaveArrangementInput input, {
    Future<void> Function(String key)? beforeInvoke,
    String? recoveredIdempotencyKey,
  }) => _run(
    operation: 'save_arrangement',
    beforeInvoke: beforeInvoke,
    recoveredIdempotencyKey: recoveredIdempotencyKey,
    entityId: input.arrangementId,
    payload: input.toRpcPayload(),
    invoke: (key) => _arrangements.save(
      YorksV1SaveArrangementInput(
        requestId: input.requestId,
        arrangementId: input.arrangementId,
        expectedRequestVersion: input.expectedRequestVersion,
        expectedArrangementVersion: input.expectedArrangementVersion,
        lines: input.lines,
        idempotencyKey: key,
        procurementNote: input.procurementNote,
      ),
    ),
  );

  Future<YorksV1ArrangementWorkspace> updateProcurementMaterialItem(
    YorksV1UpdateProcurementMaterialItemInput input,
  ) => _run(
    operation: 'update_procurement_material_item',
    entityId: input.requestLineId,
    payload: input.toRpcPayload(),
    invoke: (key) => _arrangements.updateProcurementItem(
      YorksV1UpdateProcurementMaterialItemInput(
        requestId: input.requestId,
        requestLineId: input.requestLineId,
        expectedRequestVersion: input.expectedRequestVersion,
        itemDescription: input.itemDescription,
        modelReference: input.modelReference,
        idempotencyKey: key,
      ),
    ),
  );

  Future<YorksV1MaterialRequest> createReplacementMaterialRequest(
    YorksV1CreateReplacementMaterialRequestInput input,
  ) {
    final repository = _materialRequests;
    if (repository is! YorksV1MaterialRequestPhase3Repository) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.featureDisabled,
      );
    }
    return _run(
      operation: 'create_replacement_material_request',
      entityId: input.sourceRequestId,
      payload: input.toRpcPayload(),
      invoke: (key) => (repository as YorksV1MaterialRequestPhase3Repository)
          .createReplacement(
            YorksV1CreateReplacementMaterialRequestInput(
              sourceRequestId: input.sourceRequestId,
              expectedSourceVersion: input.expectedSourceVersion,
              idempotencyKey: key,
            ),
          ),
    );
  }

  Future<YorksV1ArrangementWorkspace> decideArrangement(
    YorksV1DecideArrangementInput input,
  ) => _run(
    operation: 'decide_arrangement_${input.decision.wireValue}',
    entityId: input.arrangementId,
    payload: input.toRpcPayload(),
    invoke: (key) => _arrangements.decide(
      YorksV1DecideArrangementInput(
        requestId: input.requestId,
        arrangementId: input.arrangementId,
        expectedRequestVersion: input.expectedRequestVersion,
        expectedArrangementVersion: input.expectedArrangementVersion,
        decision: input.decision,
        idempotencyKey: key,
        reason: input.reason,
      ),
    ),
  );

  Future<YorksV1MaterialRequest> cancelMaterialRequest(
    YorksV1CancelMaterialRequestInput input,
  ) => _run(
    operation: 'cancel_material_request',
    entityId: input.requestId,
    payload: input.toRpcPayload(),
    invoke: (key) => _materialRequests.cancel(
      YorksV1CancelMaterialRequestInput(
        requestId: input.requestId,
        expectedVersion: input.expectedVersion,
        reason: input.reason,
        idempotencyKey: key,
      ),
    ),
  );

  Future<YorksV1MaterialRequest> closeMaterialRequest(
    YorksV1CloseMaterialRequestInput input,
  ) => _run(
    operation: 'close_material_request',
    entityId: input.requestId,
    payload: input.toRpcPayload(),
    invoke: (key) => _materialRequests.close(
      YorksV1CloseMaterialRequestInput(
        requestId: input.requestId,
        expectedVersion: input.expectedVersion,
        idempotencyKey: key,
      ),
    ),
  );

  Future<YorksV1LogisticsWorkspace> dispatch(
    YorksV1DispatchInput input, {
    Future<void> Function(String key)? beforeInvoke,
    String? recoveredIdempotencyKey,
  }) => _run(
    operation: 'dispatch_materials',
    beforeInvoke: beforeInvoke,
    recoveredIdempotencyKey: recoveredIdempotencyKey,
    entityId: input.requestId,
    payload: input.toRpcPayload(),
    invoke: (key) => _logistics.dispatch(
      YorksV1DispatchInput(
        requestId: input.requestId,
        expectedRequestVersion: input.expectedRequestVersion,
        dispatchDate: input.dispatchDate,
        deliveryReference: input.deliveryReference,
        lines: input.lines,
        idempotencyKey: key,
        driverName: input.driverName,
        vehicleReference: input.vehicleReference,
      ),
    ),
  );

  Future<YorksV1LogisticsInventoryItem> createInventoryItem({
    required String requestLineId,
    required YorksV1InventoryAdjustmentInput input,
  }) {
    if (!input.createsItem) {
      throw ArgumentError.value(
        input.inventoryItemId,
        'input.inventoryItemId',
        'The arrangement create command must not target an existing item.',
      );
    }
    return _run(
      operation: 'create_arrangement_inventory_item',
      entityId: requestLineId,
      payload: input.toCreateItemRpcPayload(),
      invoke: (key) =>
          _logistics.adjustInventory(input.withIdempotencyKey(key)),
    );
  }

  Future<YorksV1LogisticsWorkspace> confirmReceipt(
    YorksV1ReceiptConfirmationInput input,
  ) => _run(
    operation: 'confirm_receipt',
    entityId: input.dispatchId,
    payload: input.toRpcPayload(),
    invoke: (key) => _logistics.confirmReceipt(
      YorksV1ReceiptConfirmationInput(
        requestId: input.requestId,
        dispatchId: input.dispatchId,
        expectedRequestVersion: input.expectedRequestVersion,
        expectedDispatchVersion: input.expectedDispatchVersion,
        lines: input.lines,
        idempotencyKey: key,
      ),
    ),
  );

  Future<YorksV1ReturnsDocumentsWorkspace> generateDeliveryOrder(
    YorksV1DeliveryOrderGenerationInput input,
  ) => _run(
    operation: 'generate_delivery_order',
    entityId: input.dispatchId,
    payload: input.toRpcPayload(),
    invoke: (key) => _logistics.generateDeliveryOrder(
      YorksV1DeliveryOrderGenerationInput(
        requestId: input.requestId,
        dispatchId: input.dispatchId,
        expectedRequestVersion: input.expectedRequestVersion,
        expectedDispatchVersion: input.expectedDispatchVersion,
        deliveryOrderReference: input.deliveryOrderReference,
        idempotencyKey: key,
      ),
    ),
  );

  /// Release a command key only after the server fenced its prepared attempt.
  Future<void> releaseRejectedPreparedCommand({
    required String operation,
    required String entityId,
    required String idempotencyKey,
  }) => _retire(operation, entityId, idempotencyKey);

  Future<T> _run<T>({
    required String operation,
    required String entityId,
    required Map<String, Object?> payload,
    required Future<T> Function(String idempotencyKey) invoke,
    Future<void> Function(String key)? beforeInvoke,
    String? recoveredIdempotencyKey,
  }) async {
    final identity = '$operation:$entityId';
    final fingerprint = sha256
        .convert(utf8.encode(jsonEncode(payload)))
        .toString();
    final active = _inFlight[identity];
    if (active != null) {
      if (_activePayloads[identity] != fingerprint) {
        throw const YorksV1DomainException(YorksV1DomainErrorCode.conflict);
      }
      return (await active) as T;
    }
    final future = _execute<T>(
      operation: operation,
      entityId: entityId,
      payload: payload,
      invoke: invoke,
      beforeInvoke: beforeInvoke,
      recoveredIdempotencyKey: recoveredIdempotencyKey,
    );
    _inFlight[identity] = future;
    _activePayloads[identity] = fingerprint;
    try {
      return await future;
    } finally {
      if (identical(_inFlight[identity], future)) {
        _inFlight.remove(identity);
        _activePayloads.remove(identity);
      }
    }
  }

  Future<T> _execute<T>({
    required String operation,
    required String entityId,
    required Map<String, Object?> payload,
    required Future<T> Function(String) invoke,
    Future<void> Function(String)? beforeInvoke,
    String? recoveredIdempotencyKey,
  }) async {
    final command = _commandName(operation);
    final prepared = beforeInvoke != null || recoveredIdempotencyKey != null;
    final tracked = !prepared && _outcomes != null && command != null;
    final pendingKey = tracked
        ? _commandKeys.pendingKey(operation, entityId)
        : null;
    if (pendingKey != null &&
        await _commandKeys.wasDispatched(operation, entityId, pendingKey)) {
      // Repeating an action is an explicit status check, even after the durable
      // automatic budget is exhausted. Never resend or acquire a new key.
      final outcome = await _manualOutcome(
        operation,
        entityId,
        payload['request_id'] as String,
        pendingKey,
      );
      return _loadConfirmedView<T>(
        outcome,
        operation,
        entityId,
        payload['request_id'] as String,
        pendingKey,
      );
    }
    final key =
        recoveredIdempotencyKey ??
        await _commandKeys.acquire(
          operation: operation,
          entityId: entityId,
          payload: payload,
          preservePending: _outcomes != null && beforeInvoke == null,
          trackSendState: tracked,
        );
    await beforeInvoke?.call(
      key,
    ); // A preparation failure means final command was not sent.
    final release = _beginActivity?.call();
    try {
      final wasDispatched =
          tracked && await _commandKeys.wasDispatched(operation, entityId, key);
      if (tracked && !wasDispatched) {
        try {
          await _commandKeys.markDispatched(operation, entityId, key);
        } catch (_) {
          _emit(command, key, entityId, YorksV1CommandPhase.notSent);
          rethrow;
        }
      }
      _emit(command ?? operation, key, entityId, YorksV1CommandPhase.inFlight);
      T result;
      try {
        if (wasDispatched) throw YorksV1CommandOutcomeUnknown(key);
        result = await invoke(key);
        if (_isCurrentAuthority?.call() == false) {
          await _retire(operation, entityId, key);
          throw const YorksV1DomainException(
            YorksV1DomainErrorCode.unauthenticated,
          );
        }
      } catch (error) {
        if (!wasDispatched &&
            !prepared &&
            error is YorksV1DomainException &&
            error.code == YorksV1DomainErrorCode.offline) {
          try {
            await _commandKeys.markNotSent(operation, entityId, key);
          } catch (_) {
            /* The command was not sent even if local cleanup is unavailable. */
          }
          _emit(
            command ?? operation,
            key,
            entityId,
            YorksV1CommandPhase.notSent,
          );
          rethrow;
        }
        if (_outcomes == null ||
            command == null ||
            !_uncertain(error) ||
            ((operation == 'save_arrangement' ||
                    operation == 'dispatch_materials') &&
                (beforeInvoke != null || recoveredIdempotencyKey != null))) {
          if (error is YorksV1DomainException && !_uncertain(error)) {
            await _retire(operation, entityId, key);
          }
          _emit(
            command ?? operation,
            key,
            entityId,
            _uncertain(error)
                ? YorksV1CommandPhase.unknown
                : YorksV1CommandPhase.rejected,
          );
          rethrow;
        }
        _emit(command, key, entityId, YorksV1CommandPhase.checking);
        YorksV1WorkflowCommandOutcome? confirmed;
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            if (!await _commandKeys.claimAutomaticCheck(
              operation,
              entityId,
              key,
            )) {
              break;
            }
          } catch (_) {
            break;
          }
          if (attempt > 0) await _delay(Duration(milliseconds: 500 * attempt));
          try {
            final outcome = await _outcomes.check(command, key);
            if (_isCurrentAuthority?.call() == false) {
              throw const YorksV1DomainException(
                YorksV1DomainErrorCode.unauthenticated,
              );
            }
            if (outcome.confirmed) {
              final receipt = outcome.receipt;
              if (receipt == null ||
                  receipt.commandKey != key ||
                  receipt.commandName != command ||
                  receipt.entityId != payload['request_id']) {
                throw const YorksV1DomainException(
                  YorksV1DomainErrorCode.unexpectedResponse,
                );
              }
              confirmed = outcome;
              break;
            }
          } catch (_) {
            /* An unavailable lookup cannot establish rejection. */
          }
        }
        if (confirmed == null) {
          _emit(command, key, entityId, YorksV1CommandPhase.unknown);
          throw YorksV1CommandOutcomeUnknown(key, cause: error);
        }
        _emit(command, key, entityId, YorksV1CommandPhase.confirmed);
        await _retire(operation, entityId, key);
        return await _loadConfirmedView<T>(
          confirmed,
          operation,
          entityId,
          payload['request_id'] as String,
          key,
        );
      }
      // Acknowledgement is final. Storage cleanup is a separate best-effort step.
      _emit(command ?? operation, key, entityId, YorksV1CommandPhase.confirmed);
      await _retire(operation, entityId, key);
      return result;
    } finally {
      try {
        release?.call();
      } catch (_) {
        /* Read scheduling cannot override a committed result. */
      }
    }
  }

  Future<void> _retire(String operation, String entityId, String key) async {
    try {
      await _commandKeys.confirm(
        operation: operation,
        entityId: entityId,
        idempotencyKey: key,
      );
    } catch (_) {
      /* Same-key replay remains safe if local cleanup fails. */
    }
  }

  static bool _uncertain(Object error) =>
      error is! YorksV1DomainException ||
      error.code == YorksV1DomainErrorCode.unexpectedResponse ||
      error.code == YorksV1DomainErrorCode.backendUnavailable ||
      error.code == YorksV1DomainErrorCode.offline;

  static String? _commandName(String operation) => switch (operation) {
    'decide_material_request_approved' ||
    'decide_material_request_returned' => 'v1_decide_material_request',
    'decide_arrangement_approved' ||
    'decide_arrangement_returned' => 'v1_decide_arrangement',
    'begin_arrangement' => 'v1_begin_arrangement',
    'save_arrangement' => 'v1_save_arrangement',
    'dispatch_materials' => 'v1_dispatch_materials',
    'confirm_receipt' => 'v1_confirm_receipt',
    'cancel_material_request' => 'v1_cancel_material_request',
    'close_material_request' => 'v1_close_material_request',
    'generate_delivery_order' => 'v1_generate_delivery_order',
    _ => null,
  };

  static T _decode<T>(Map<String, dynamic> json) {
    if (T == YorksV1MaterialRequest) {
      return YorksV1MaterialRequest.fromRpcJson(json) as T;
    }
    if (T == YorksV1ArrangementWorkspace) {
      return YorksV1ArrangementWorkspace.fromRpcJson(json) as T;
    }
    if (T == YorksV1LogisticsWorkspace) {
      return YorksV1LogisticsWorkspace.fromRpcJson(json) as T;
    }
    if (T == YorksV1ReturnsDocumentsWorkspace) {
      return YorksV1ReturnsDocumentsWorkspace.fromRpcJson(json) as T;
    }
    throw StateError('unsupported_command_response');
  }
}

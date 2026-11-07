import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/yorks_v1_domain_error.dart';
import '../../../shared/services/yorks_v1_critical_command_key_store.dart';
import '../data/accounts_supplier_repository.dart';
import '../domain/accounts_supplier_inputs.dart';
import '../domain/accounts_supplier_models.dart';
import 'accounts_controller.dart';

final class YorksAccountsSupplierState {
  const YorksAccountsSupplierState({
    this.status = YorksAccountsViewStatus.idle,
    this.bills,
    this.selectedBill,
    this.error,
    this.isMutating = false,
  });

  final YorksAccountsViewStatus status;
  final YorksAccountsSupplierBillsProjection? bills;
  final YorksAccountsSupplierBillDetailProjection? selectedBill;
  final YorksV1DomainException? error;
  final bool isMutating;

  bool get hasProtectedSupplierCosts => bills != null || selectedBill != null;

  YorksAccountsSupplierState copyWith({
    YorksAccountsViewStatus? status,
    YorksAccountsSupplierBillsProjection? bills,
    YorksAccountsSupplierBillDetailProjection? selectedBill,
    YorksV1DomainException? error,
    bool? isMutating,
    bool clearBills = false,
    bool clearSelectedBill = false,
    bool clearError = false,
  }) => YorksAccountsSupplierState(
    status: status ?? this.status,
    bills: clearBills ? null : bills ?? this.bills,
    selectedBill: clearSelectedBill ? null : selectedBill ?? this.selectedBill,
    error: clearError ? null : error ?? this.error,
    isMutating: isMutating ?? this.isMutating,
  );
}

/// Route-less T04 boundary for protected supplier costs.
///
/// Critical commands are never optimistic. A permission/session/feature loss
/// replaces the complete state so stale supplier values cannot remain cached.
final class YorksAccountsSupplierController
    extends StateNotifier<YorksAccountsSupplierState> {
  YorksAccountsSupplierController({
    required String projectId,
    required YorksAccountsSupplierRepository repository,
    required YorksV1CriticalCommandKeyStore commandKeys,
  }) : _projectId = projectId.trim(),
       _repository = repository,
       _commandKeys = commandKeys,
       super(const YorksAccountsSupplierState());

  final String _projectId;
  final YorksAccountsSupplierRepository _repository;
  final YorksV1CriticalCommandKeyStore _commandKeys;

  Future<bool> loadBills({
    String? search,
    YorksAccountsSupplierMatchStatus? matchStatus,
    YorksAccountsSupplierPaymentStatus? paymentStatus,
    YorksAccountsSupplierBillCursor? before,
    int limit = 25,
  }) => _load(
    () => _repository.listBills(
      _projectId,
      search: search,
      matchStatus: matchStatus,
      paymentStatus: paymentStatus,
      before: before,
      limit: limit,
    ),
    (projection) => state.copyWith(
      status: YorksAccountsViewStatus.success,
      bills: projection,
      clearError: true,
    ),
  );

  Future<bool> loadBill(String supplierBillId) {
    final normalized = supplierBillId.trim();
    if (normalized.isEmpty) return _rejectInvalidRead();
    return _load(
      () => _repository.getBill(_projectId, normalized),
      (projection) => state.copyWith(
        status: YorksAccountsViewStatus.success,
        selectedBill: projection,
        clearError: true,
      ),
    );
  }

  Future<YorksAccountsSupplierCommandResult?> createBillDraft(
    YorksAccountsSupplierBillDraftInput input,
  ) => _projectCommand(
    input.projectId,
    operation: 'create_supplier_bill_draft',
    entityId: _projectId,
    payload: input.idempotencyPayload(),
    invoke: (key) => _repository.createBillDraft(input, idempotencyKey: key),
    reconcile: loadBills,
  );

  Future<YorksAccountsSupplierCommandResult?> updateBillDraft(
    YorksAccountsSupplierBillDraftInput input,
  ) => _projectCommand(
    input.projectId,
    operation: 'update_supplier_bill_draft',
    entityId: input.supplierBillId ?? '',
    payload: input.idempotencyPayload(),
    invoke: (key) => _repository.updateBillDraft(input, idempotencyKey: key),
    reconcile: () => _reconcileBill(input.supplierBillId ?? ''),
  );

  Future<YorksAccountsSupplierCommandResult?> approveBill(
    YorksAccountsSupplierBillApprovalInput input,
  ) => _projectCommand(
    input.projectId,
    operation: 'approve_supplier_bill',
    entityId: input.supplierBillId,
    payload: input.idempotencyPayload(),
    invoke: (key) => _repository.approveBill(input, idempotencyKey: key),
    reconcile: () => _reconcileBill(input.supplierBillId),
  );

  Future<YorksAccountsSupplierCommandResult?> recordPayment(
    YorksAccountsSupplierPaymentInput input,
  ) => _projectCommand(
    input.projectId,
    operation: 'record_supplier_payment',
    entityId: input.supplierBillId,
    payload: input.idempotencyPayload(),
    invoke: (key) => _repository.recordPayment(input, idempotencyKey: key),
    reconcile: () => _reconcileBill(input.supplierBillId),
  );

  Future<YorksAccountsSupplierCommandResult?> reversePayment(
    YorksAccountsSupplierPaymentReversalInput input,
  ) => _projectCommand(
    input.projectId,
    operation: 'reverse_supplier_payment',
    entityId: input.originalPaymentId,
    payload: input.idempotencyPayload(),
    invoke: (key) => _repository.reversePayment(input, idempotencyKey: key),
    reconcile: () => _reconcileBill(input.supplierBillId),
  );

  Future<YorksAccountsSupplierCommandResult?> cancelBill(
    YorksAccountsSupplierBillCancelInput input,
  ) => _projectCommand(
    input.projectId,
    operation: 'cancel_supplier_bill',
    entityId: input.supplierBillId,
    payload: input.idempotencyPayload(),
    invoke: (key) => _repository.cancelBill(input, idempotencyKey: key),
    reconcile: () => _reconcileBill(input.supplierBillId),
  );

  Future<YorksAccountsSupplierCommandResult?> correctPayment(
    YorksAccountsSupplierPaymentCorrectionInput input,
  ) => _projectCommand(
    input.projectId,
    operation: 'correct_supplier_payment',
    entityId: input.originalPaymentId,
    payload: input.idempotencyPayload(),
    invoke: (key) => _repository.correctPayment(input, idempotencyKey: key),
    reconcile: () => _reconcileBill(input.supplierBillId),
  );

  Future<YorksAccountsSupplierCommandResult?> reopenBill(
    YorksAccountsSupplierBillCancelInput input,
  ) => _projectCommand(
    input.projectId,
    operation: 'reopen_supplier_bill',
    entityId: input.supplierBillId,
    payload: input.idempotencyPayload(),
    invoke: (key) => _repository.reopenBill(input, idempotencyKey: key),
    reconcile: () => _reconcileBill(input.supplierBillId),
  );

  void purgeAll() {
    state = const YorksAccountsSupplierState();
  }

  Future<bool> _reconcileBill(String supplierBillId) async {
    final selectedId = state.selectedBill?.supplierBill.supplierBillId;
    if (selectedId == supplierBillId) return loadBill(supplierBillId);
    return loadBills();
  }

  Future<bool> _load<T>(
    Future<T> Function() invoke,
    YorksAccountsSupplierState Function(T value) success,
  ) async {
    if (!mounted) return false;
    state = state.copyWith(
      status: YorksAccountsViewStatus.loading,
      clearError: true,
    );
    try {
      final value = await invoke();
      if (!mounted) return false;
      state = success(value);
      return true;
    } on YorksV1DomainException catch (error) {
      if (!mounted) return false;
      _setFailure(error, commandMayHaveCommitted: false);
      return false;
    } catch (error) {
      if (!mounted) return false;
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

  Future<YorksAccountsSupplierCommandResult?> _projectCommand(
    String inputProjectId, {
    required String operation,
    required String entityId,
    required Map<String, Object?> payload,
    required Future<YorksAccountsSupplierCommandResult> Function(String key)
    invoke,
    required Future<bool> Function() reconcile,
  }) {
    if (!_matchesProject(inputProjectId) || entityId.trim().isEmpty) {
      return _rejectInvalidCommand();
    }
    return _runCommand(
      operation: operation,
      entityId: entityId,
      payload: payload,
      invoke: invoke,
      reconcile: reconcile,
    );
  }

  Future<YorksAccountsSupplierCommandResult?> _runCommand({
    required String operation,
    required String entityId,
    required Map<String, Object?> payload,
    required Future<YorksAccountsSupplierCommandResult> Function(String key)
    invoke,
    required Future<bool> Function() reconcile,
  }) async {
    if (state.isMutating) return null;
    state = state.copyWith(isMutating: true, clearError: true);
    try {
      final key = await _commandKeys.acquire(
        operation: operation,
        entityId: entityId,
        payload: payload,
      );
      final result = await invoke(key);
      await _commandKeys.confirm(
        operation: operation,
        entityId: entityId,
        idempotencyKey: key,
      );
      state = state.copyWith(
        status: YorksAccountsViewStatus.success,
        isMutating: false,
        clearError: true,
      );
      await reconcile();
      return result;
    } on YorksV1DomainException catch (error) {
      _setFailure(error, commandMayHaveCommitted: true);
      return null;
    } catch (error) {
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

  bool _matchesProject(String projectId) =>
      _projectId.isNotEmpty && projectId.trim() == _projectId;

  Future<bool> _rejectInvalidRead() {
    _setFailure(
      const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput),
      commandMayHaveCommitted: false,
    );
    return Future<bool>.value(false);
  }

  Future<YorksAccountsSupplierCommandResult?> _rejectInvalidCommand() {
    _setFailure(
      const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput),
      commandMayHaveCommitted: false,
    );
    return Future<YorksAccountsSupplierCommandResult?>.value();
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
      YorksV1DomainErrorCode.backendUnavailable when commandMayHaveCommitted =>
        YorksAccountsViewStatus.uncertain,
      _ => YorksAccountsViewStatus.failure,
    };
    if (status == YorksAccountsViewStatus.forbidden ||
        status == YorksAccountsViewStatus.sessionExpired ||
        status == YorksAccountsViewStatus.unavailable) {
      state = YorksAccountsSupplierState(status: status, error: error);
      return;
    }
    state = state.copyWith(status: status, error: error, isMutating: false);
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/yorks_v1_domain_error.dart';
import '../../../shared/models/yorks_v1_feature_flags.dart';
import '../../../shared/sync/connectivity_service.dart';
import '../domain/accounts_supplier_inputs.dart';
import '../domain/accounts_supplier_models.dart';
import 'accounts_repository.dart';

abstract interface class YorksAccountsSupplierRepository {
  Future<YorksAccountsSupplierBillsProjection> listBills(
    String projectId, {
    String? search,
    YorksAccountsSupplierMatchStatus? matchStatus,
    YorksAccountsSupplierPaymentStatus? paymentStatus,
    YorksAccountsSupplierBillCursor? before,
    int limit = 25,
  });

  Future<YorksAccountsSupplierBillDetailProjection> getBill(
    String projectId,
    String supplierBillId,
  );

  /// Confirmed deliveries a bill on this project can cite, newest first.
  Future<List<YorksAccountsAcceptedDelivery>> listDeliveryOptions(
    String projectId,
  );

  Future<YorksAccountsSupplierCommandResult> createBillDraft(
    YorksAccountsSupplierBillDraftInput input, {
    required String idempotencyKey,
  });

  Future<YorksAccountsSupplierCommandResult> updateBillDraft(
    YorksAccountsSupplierBillDraftInput input, {
    required String idempotencyKey,
  });

  Future<YorksAccountsSupplierCommandResult> approveBill(
    YorksAccountsSupplierBillApprovalInput input, {
    required String idempotencyKey,
  });

  Future<YorksAccountsSupplierCommandResult> recordPayment(
    YorksAccountsSupplierPaymentInput input, {
    required String idempotencyKey,
  });

  Future<YorksAccountsSupplierCommandResult> reversePayment(
    YorksAccountsSupplierPaymentReversalInput input, {
    required String idempotencyKey,
  });

  Future<YorksAccountsSupplierCommandResult> cancelBill(
    YorksAccountsSupplierBillCancelInput input, {
    required String idempotencyKey,
  });

  Future<YorksAccountsSupplierCommandResult> correctPayment(
    YorksAccountsSupplierPaymentCorrectionInput input, {
    required String idempotencyKey,
  });

  /// Returns an approved or cancelled bill to draft. Takes the same fields as a
  /// cancellation: the bill, its version and a reason.
  Future<YorksAccountsSupplierCommandResult> reopenBill(
    YorksAccountsSupplierBillCancelInput input, {
    required String idempotencyKey,
  });
}

final class YorksSupabaseAccountsSupplierRepository
    implements YorksAccountsSupplierRepository {
  const YorksSupabaseAccountsSupplierRepository({
    required YorksV1FeatureFlags featureFlags,
    required ConnectivityService connectivity,
    YorksAccountsRpcClient? rpcClient,
  }) : _featureFlags = featureFlags,
       _connectivity = connectivity,
       _rpcClient = rpcClient;

  final YorksV1FeatureFlags _featureFlags;
  final ConnectivityService _connectivity;
  final YorksAccountsRpcClient? _rpcClient;

  @override
  Future<YorksAccountsSupplierBillsProjection> listBills(
    String projectId, {
    String? search,
    YorksAccountsSupplierMatchStatus? matchStatus,
    YorksAccountsSupplierPaymentStatus? paymentStatus,
    YorksAccountsSupplierBillCursor? before,
    int limit = 25,
  }) async {
    final normalizedProjectId = projectId.trim();
    if (normalizedProjectId.isEmpty ||
        limit < 1 ||
        limit > 100 ||
        (search != null && search.trim().isEmpty) ||
        (before != null && before.supplierBillId.trim().isEmpty)) {
      return _invalidInput();
    }
    final response = await _invoke('v1_list_supplier_bills', {
      'p_project_id': normalizedProjectId,
      'p_search': _nullableTrimmed(search),
      'p_match_status': matchStatus?.wireValue,
      'p_payment_status': paymentStatus?.wireValue,
      'p_cursor_updated_at': before?.updatedAt.toUtc().toIso8601String(),
      'p_cursor_id': before?.supplierBillId,
      'p_limit': limit,
    });
    return _decode(() {
      final projection = YorksAccountsSupplierBillsProjection.fromRpcJson(
        response,
      );
      _requireId(projection.projectId, normalizedProjectId);
      for (final bill in projection.items) {
        _requireId(bill.projectId, normalizedProjectId);
      }
      return projection;
    });
  }

  @override
  Future<YorksAccountsSupplierBillDetailProjection> getBill(
    String projectId,
    String supplierBillId,
  ) async {
    final normalizedProjectId = projectId.trim();
    final normalizedBillId = supplierBillId.trim();
    if (normalizedProjectId.isEmpty || normalizedBillId.isEmpty) {
      return _invalidInput();
    }
    final response = await _invoke('v1_get_supplier_bill', {
      'p_project_id': normalizedProjectId,
      'p_supplier_bill_id': normalizedBillId,
    });
    return _decode(() {
      final projection = YorksAccountsSupplierBillDetailProjection.fromRpcJson(
        response,
      );
      _requireId(projection.projectId, normalizedProjectId);
      _requireId(projection.supplierBill.projectId, normalizedProjectId);
      _requireId(projection.supplierBill.supplierBillId, normalizedBillId);
      return projection;
    });
  }

  @override
  Future<List<YorksAccountsAcceptedDelivery>> listDeliveryOptions(
    String projectId,
  ) async {
    final normalizedProjectId = projectId.trim();
    if (normalizedProjectId.isEmpty) return _invalidInput();
    final response = await _invoke('v1_list_supplier_bill_delivery_options', {
      'p_project_id': normalizedProjectId,
    });
    return _decode(() {
      _requireId(response['project_id'] as String? ?? '', normalizedProjectId);
      return [
        for (final item in response['deliveries'] as List<dynamic>)
          YorksAccountsAcceptedDelivery.fromRpcJson(
            Map<String, dynamic>.from(item as Map),
          ),
      ];
    });
  }

  @override
  Future<YorksAccountsSupplierCommandResult> createBillDraft(
    YorksAccountsSupplierBillDraftInput input, {
    required String idempotencyKey,
  }) {
    if (input.isUpdate || !input.isValid) return _invalidInput();
    return _billCommand(
      'v1_create_supplier_bill_draft',
      _draftParameters(input, idempotencyKey),
      input.projectId,
      idempotencyKey,
    );
  }

  @override
  Future<YorksAccountsSupplierCommandResult> updateBillDraft(
    YorksAccountsSupplierBillDraftInput input, {
    required String idempotencyKey,
  }) {
    if (!input.isUpdate || !input.isValid) return _invalidInput();
    return _billCommand(
      'v1_update_supplier_bill_draft',
      _draftParameters(input, idempotencyKey),
      input.projectId,
      idempotencyKey,
      expectedBillId: input.supplierBillId,
    );
  }

  @override
  Future<YorksAccountsSupplierCommandResult> approveBill(
    YorksAccountsSupplierBillApprovalInput input, {
    required String idempotencyKey,
  }) {
    if (!input.isValid) return _invalidInput();
    return _billCommand(
      'v1_approve_supplier_bill',
      {
        'p_project_id': input.projectId.trim(),
        'p_supplier_bill_id': input.supplierBillId.trim(),
        'p_expected_version': input.expectedVersion,
        'p_admin_exception_reason': _nullableTrimmed(
          input.adminExceptionReason,
        ),
        'p_idempotency_key': idempotencyKey.trim(),
      },
      input.projectId,
      idempotencyKey,
      expectedBillId: input.supplierBillId,
    );
  }

  @override
  Future<YorksAccountsSupplierCommandResult> recordPayment(
    YorksAccountsSupplierPaymentInput input, {
    required String idempotencyKey,
  }) {
    if (!input.isValid) return _invalidInput();
    return _paymentCommand(
      'v1_record_supplier_payment',
      {
        'p_project_id': input.projectId.trim(),
        'p_supplier_bill_id': input.supplierBillId.trim(),
        'p_expected_version': input.expectedVersion,
        'p_payment_date': input.paymentDate.postgresText,
        'p_payment_method': input.paymentMethod.trim(),
        'p_payment_reference': input.paymentReference.trim(),
        'p_amount': input.amount.postgresText,
        'p_reason': _nullableTrimmed(input.reason),
        'p_admin_exception_reason': _nullableTrimmed(
          input.adminExceptionReason,
        ),
        'p_idempotency_key': idempotencyKey.trim(),
      },
      input.projectId,
      input.supplierBillId,
      idempotencyKey,
      expectReversal: false,
    );
  }

  @override
  Future<YorksAccountsSupplierCommandResult> reversePayment(
    YorksAccountsSupplierPaymentReversalInput input, {
    required String idempotencyKey,
  }) {
    if (!input.isValid) return _invalidInput();
    return _paymentCommand(
      'v1_reverse_supplier_payment',
      {
        'p_project_id': input.projectId.trim(),
        'p_supplier_bill_id': input.supplierBillId.trim(),
        'p_expected_version': input.expectedVersion,
        'p_original_payment_id': input.originalPaymentId.trim(),
        'p_reversal_date': input.reversalDate.postgresText,
        'p_reversal_reference': input.reversalReference.trim(),
        'p_reason': input.reason.trim(),
        'p_idempotency_key': idempotencyKey.trim(),
      },
      input.projectId,
      input.supplierBillId,
      idempotencyKey,
      expectReversal: true,
    );
  }

  @override
  Future<YorksAccountsSupplierCommandResult> cancelBill(
    YorksAccountsSupplierBillCancelInput input, {
    required String idempotencyKey,
  }) {
    if (!input.isValid) return _invalidInput();
    return _billCommand(
      'v1_cancel_supplier_bill',
      {
        'p_project_id': input.projectId.trim(),
        'p_supplier_bill_id': input.supplierBillId.trim(),
        'p_expected_version': input.expectedVersion,
        'p_reason': input.reason.trim(),
        'p_idempotency_key': idempotencyKey.trim(),
      },
      input.projectId,
      idempotencyKey,
      expectedBillId: input.supplierBillId,
    );
  }

  @override
  Future<YorksAccountsSupplierCommandResult> correctPayment(
    YorksAccountsSupplierPaymentCorrectionInput input, {
    required String idempotencyKey,
  }) {
    if (!input.isValid) return _invalidInput();
    return _paymentCommand(
      'v1_correct_supplier_payment',
      {
        'p_project_id': input.projectId.trim(),
        'p_supplier_bill_id': input.supplierBillId.trim(),
        'p_expected_version': input.expectedVersion,
        'p_original_payment_id': input.originalPaymentId.trim(),
        'p_payment_date': input.paymentDate.postgresText,
        'p_payment_method': input.paymentMethod.trim(),
        'p_payment_reference': input.paymentReference.trim(),
        'p_amount': input.amount.postgresText,
        'p_reason': input.reason.trim(),
        'p_idempotency_key': idempotencyKey.trim(),
      },
      input.projectId,
      input.supplierBillId,
      idempotencyKey,
      expectReversal: false,
    );
  }

  @override
  Future<YorksAccountsSupplierCommandResult> reopenBill(
    YorksAccountsSupplierBillCancelInput input, {
    required String idempotencyKey,
  }) {
    if (!input.isValid) return _invalidInput();
    return _billCommand(
      'v1_reopen_supplier_bill',
      {
        'p_project_id': input.projectId.trim(),
        'p_supplier_bill_id': input.supplierBillId.trim(),
        'p_expected_version': input.expectedVersion,
        'p_reason': input.reason.trim(),
        'p_idempotency_key': idempotencyKey.trim(),
      },
      input.projectId,
      idempotencyKey,
      expectedBillId: input.supplierBillId,
    );
  }

  Map<String, Object?> _draftParameters(
    YorksAccountsSupplierBillDraftInput input,
    String idempotencyKey,
  ) => {
    'p_project_id': input.projectId.trim(),
    if (input.supplierBillId != null)
      'p_supplier_bill_id': input.supplierBillId!.trim(),
    if (input.expectedVersion != null)
      'p_expected_version': input.expectedVersion,
    'p_supplier_id': _nullableTrimmed(input.supplierId),
    'p_supplier_name': _nullableTrimmed(input.supplierName),
    'p_supplier_invoice_reference': input.supplierInvoiceReference.trim(),
    'p_invoice_date': input.invoiceDate.postgresText,
    'p_due_date': input.dueDate.postgresText,
    'p_ex_vat_amount': input.exVatAmount.postgresText,
    'p_vat_rate_percent': input.vatRatePercent.postgresText,
    'p_po_lpo_reference': _nullableTrimmed(input.poLpoReference),
    'p_po_lpo_document_id': _nullableTrimmed(input.poLpoDocumentId),
    'p_accepted_receipt_review_id': _nullableTrimmed(
      input.acceptedReceiptReviewId,
    ),
    'p_supplier_invoice_document_id': _nullableTrimmed(
      input.supplierInvoiceDocumentId,
    ),
    'p_explicit_mismatch_reason': _nullableTrimmed(
      input.explicitMismatchReason,
    ),
    'p_notes': _nullableTrimmed(input.notes),
    'p_idempotency_key': idempotencyKey.trim(),
  };

  Future<YorksAccountsSupplierCommandResult> _billCommand(
    String functionName,
    Map<String, Object?> parameters,
    String expectedProjectId,
    String idempotencyKey, {
    String? expectedBillId,
  }) async {
    final projectId = expectedProjectId.trim();
    if (projectId.isEmpty || idempotencyKey.trim().isEmpty) {
      return _invalidInput();
    }
    final response = await _invoke(functionName, parameters);
    return _decode(() {
      final result = YorksAccountsSupplierCommandResult.fromRpcJson(response);
      _requireId(result.projectId, projectId);
      if (expectedBillId != null) {
        _requireId(result.supplierBillId, expectedBillId.trim());
      }
      if (result.entityId != result.supplierBillId ||
          result.paymentId != null ||
          result.reversalId != null) {
        throw const FormatException('Expected a supplier bill command.');
      }
      return result;
    });
  }

  Future<YorksAccountsSupplierCommandResult> _paymentCommand(
    String functionName,
    Map<String, Object?> parameters,
    String expectedProjectId,
    String expectedBillId,
    String idempotencyKey, {
    required bool expectReversal,
  }) async {
    if (expectedProjectId.trim().isEmpty ||
        expectedBillId.trim().isEmpty ||
        idempotencyKey.trim().isEmpty) {
      return _invalidInput();
    }
    final response = await _invoke(functionName, parameters);
    return _decode(() {
      final result = YorksAccountsSupplierCommandResult.fromRpcJson(response);
      _requireId(result.projectId, expectedProjectId.trim());
      _requireId(result.supplierBillId, expectedBillId.trim());
      if (expectReversal != (result.reversalId != null) ||
          expectReversal == (result.paymentId != null)) {
        throw const FormatException('Wrong supplier payment command kind.');
      }
      return result;
    });
  }

  Future<Map<String, dynamic>> _invoke(
    String functionName,
    Map<String, Object?> parameters,
  ) async {
    final rpc = _readyRpc();
    try {
      return await rpc.invoke(
        functionName: functionName,
        parameters: parameters,
      );
    } on YorksV1DomainException {
      rethrow;
    } on PostgrestException catch (error) {
      throw _mapPostgrest(error);
    } catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
        cause: error,
      );
    }
  }

  YorksAccountsRpcClient _readyRpc() {
    if (!_featureFlags.accounts) {
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
    return rpc;
  }

  YorksV1DomainException _mapPostgrest(PostgrestException error) {
    final message = [
      error.message,
      error.details?.toString(),
      error.hint?.toString(),
    ].whereType<String>().join(' ').toUpperCase();
    final mapped = switch (error.code) {
      'PGRST301' ||
      'PGRST302' ||
      'PGRST303' ||
      '28000' => YorksV1DomainErrorCode.unauthenticated,
      '42501' => YorksV1DomainErrorCode.unauthorized,
      'PGRST002' || 'PGRST003' => YorksV1DomainErrorCode.backendUnavailable,
      '40001' => YorksV1DomainErrorCode.conflict,
      _
          when message.contains('VERSION_CONFLICT') ||
              message.contains('IDEMPOTENCY_KEY_REUSED') ||
              message.contains('IDEMPOTENCY_PAYLOAD_MISMATCH') ||
              error.code == '23505' =>
        YorksV1DomainErrorCode.conflict,
      _ when message.contains('IDEMPOTENCY_IN_PROGRESS') =>
        YorksV1DomainErrorCode.backendUnavailable,
      _ when message.contains('PAYMENT_CAP_EXCEEDED') =>
        YorksV1DomainErrorCode.quantityCapExceeded,
      _ when message.contains('APPEND_ONLY') =>
        YorksV1DomainErrorCode.immutableRecord,
      _
          when message.contains('_NOT_PAYABLE') ||
              message.contains('_NOT_APPROVABLE') ||
              message.contains('_NOT_CANCELLABLE') ||
              message.contains('_HAS_PAYMENTS') ||
              message.contains('_ALREADY_REVERSED') ||
              error.code == '55000' ||
              error.code == 'P0002' =>
        YorksV1DomainErrorCode.invalidTransition,
      _
          when message.contains('INVALID_') ||
              message.contains('_REQUIRED') ||
              message.contains('_NOT_MATCHED') ||
              error.code == '22023' ||
              error.code == '23514' =>
        YorksV1DomainErrorCode.invalidInput,
      _ => YorksV1DomainErrorCode.serverRejected,
    };
    return YorksV1DomainException(
      mapped,
      serverCode: error.code,
      serverMessage: error.message,
      cause: error,
    );
  }
}

T _decode<T>(T Function() decode) {
  try {
    return decode();
  } on FormatException catch (error) {
    throw YorksV1DomainException(
      YorksV1DomainErrorCode.unexpectedResponse,
      cause: error,
    );
  }
}

void _requireId(String actual, String expected) {
  if (expected.isEmpty || actual != expected) {
    throw const FormatException(
      'Supplier Accounts response identity mismatch.',
    );
  }
}

String? _nullableTrimmed(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

Future<T> _invalidInput<T>() => Future.error(
  const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput),
);

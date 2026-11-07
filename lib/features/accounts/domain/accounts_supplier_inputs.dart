import 'accounts_decimal.dart';
import 'accounts_receivables_inputs.dart';

final class YorksAccountsSupplierBillDraftInput {
  const YorksAccountsSupplierBillDraftInput({
    required this.projectId,
    required this.supplierName,
    required this.supplierInvoiceReference,
    required this.invoiceDate,
    required this.dueDate,
    required this.exVatAmount,
    required this.vatRatePercent,
    required this.poLpoReference,
    required this.poLpoDocumentId,
    required this.acceptedReceiptReviewId,
    required this.supplierInvoiceDocumentId,
    required this.explicitMismatchReason,
    required this.notes,
    this.supplierId,
    this.supplierBillId,
    this.expectedVersion,
  });

  final String projectId;
  final String? supplierBillId;
  final int? expectedVersion;
  final String? supplierId;
  final String? supplierName;
  final String supplierInvoiceReference;
  final YorksAccountsDate invoiceDate;
  final YorksAccountsDate dueDate;
  final YorksAccountsDecimal exVatAmount;
  final YorksAccountsDecimal vatRatePercent;
  final String? poLpoReference;
  final String? poLpoDocumentId;
  final String? acceptedReceiptReviewId;
  final String? supplierInvoiceDocumentId;
  final String? explicitMismatchReason;
  final String? notes;

  bool get isUpdate => supplierBillId != null || expectedVersion != null;

  bool get isValid {
    if (projectId.trim().isEmpty ||
        supplierInvoiceReference.trim().isEmpty ||
        dueDate.compareTo(invoiceDate) < 0 ||
        !exVatAmount.isPositive ||
        exVatAmount.fractionDigits > 2 ||
        vatRatePercent.isNegative ||
        vatRatePercent.compareTo(YorksAccountsDecimal.hundred) > 0 ||
        vatRatePercent.fractionDigits > 4) {
      return false;
    }
    if (_nullableTrimmed(supplierId) == null &&
        _nullableTrimmed(supplierName) == null) {
      return false;
    }
    if (!_optionalValuesAreNonblank([
      poLpoReference,
      poLpoDocumentId,
      acceptedReceiptReviewId,
      supplierInvoiceDocumentId,
      explicitMismatchReason,
      notes,
    ])) {
      return false;
    }
    if (isUpdate) {
      return _nullableTrimmed(supplierBillId) != null &&
          expectedVersion != null &&
          expectedVersion! > 0;
    }
    return supplierBillId == null && expectedVersion == null;
  }

  Map<String, Object?> idempotencyPayload() => {
    'project_id': projectId.trim(),
    if (supplierBillId != null) 'supplier_bill_id': supplierBillId!.trim(),
    if (expectedVersion != null) 'expected_version': expectedVersion,
    'supplier_id': _nullableTrimmed(supplierId),
    'supplier_name': _nullableTrimmed(supplierName),
    'supplier_invoice_reference': supplierInvoiceReference.trim(),
    'invoice_date': invoiceDate.postgresText,
    'due_date': dueDate.postgresText,
    'ex_vat_amount': exVatAmount.postgresText,
    'vat_rate_percent': vatRatePercent.postgresText,
    'po_lpo_reference': _nullableTrimmed(poLpoReference),
    'po_lpo_document_id': _nullableTrimmed(poLpoDocumentId),
    'accepted_receipt_review_id': _nullableTrimmed(acceptedReceiptReviewId),
    'supplier_invoice_document_id': _nullableTrimmed(supplierInvoiceDocumentId),
    'explicit_mismatch_reason': _nullableTrimmed(explicitMismatchReason),
    'notes': _nullableTrimmed(notes),
  };
}

final class YorksAccountsSupplierBillApprovalInput {
  const YorksAccountsSupplierBillApprovalInput({
    required this.projectId,
    required this.supplierBillId,
    required this.expectedVersion,
    this.adminExceptionReason,
  });

  final String projectId;
  final String supplierBillId;
  final int expectedVersion;
  final String? adminExceptionReason;

  bool get isValid =>
      projectId.trim().isNotEmpty &&
      supplierBillId.trim().isNotEmpty &&
      expectedVersion > 0 &&
      _optionalValuesAreNonblank([adminExceptionReason]);

  Map<String, Object?> idempotencyPayload() => {
    'project_id': projectId.trim(),
    'supplier_bill_id': supplierBillId.trim(),
    'expected_version': expectedVersion,
    'admin_exception_reason': _nullableTrimmed(adminExceptionReason),
  };
}

final class YorksAccountsSupplierPaymentInput {
  const YorksAccountsSupplierPaymentInput({
    required this.projectId,
    required this.supplierBillId,
    required this.expectedVersion,
    required this.paymentDate,
    required this.paymentMethod,
    required this.paymentReference,
    required this.amount,
    this.reason,
    this.adminExceptionReason,
  });

  final String projectId;
  final String supplierBillId;
  final int expectedVersion;
  final YorksAccountsDate paymentDate;
  final String paymentMethod;
  final String paymentReference;
  final YorksAccountsDecimal amount;
  final String? reason;
  final String? adminExceptionReason;

  bool get isValid =>
      projectId.trim().isNotEmpty &&
      supplierBillId.trim().isNotEmpty &&
      expectedVersion > 0 &&
      paymentMethod.trim().isNotEmpty &&
      paymentReference.trim().isNotEmpty &&
      amount.isPositive &&
      amount.fractionDigits <= 2 &&
      _optionalValuesAreNonblank([reason, adminExceptionReason]);

  Map<String, Object?> idempotencyPayload() => {
    'project_id': projectId.trim(),
    'supplier_bill_id': supplierBillId.trim(),
    'expected_version': expectedVersion,
    'payment_date': paymentDate.postgresText,
    'payment_method': paymentMethod.trim(),
    'payment_reference': paymentReference.trim(),
    'amount': amount.postgresText,
    'reason': _nullableTrimmed(reason),
    'admin_exception_reason': _nullableTrimmed(adminExceptionReason),
  };
}

final class YorksAccountsSupplierPaymentReversalInput {
  const YorksAccountsSupplierPaymentReversalInput({
    required this.projectId,
    required this.supplierBillId,
    required this.expectedVersion,
    required this.originalPaymentId,
    required this.reversalDate,
    required this.reversalReference,
    required this.reason,
  });

  final String projectId;
  final String supplierBillId;
  final int expectedVersion;
  final String originalPaymentId;
  final YorksAccountsDate reversalDate;
  final String reversalReference;
  final String reason;

  bool get isValid =>
      projectId.trim().isNotEmpty &&
      supplierBillId.trim().isNotEmpty &&
      expectedVersion > 0 &&
      originalPaymentId.trim().isNotEmpty &&
      reason.trim().isNotEmpty;

  Map<String, Object?> idempotencyPayload() => {
    'project_id': projectId.trim(),
    'supplier_bill_id': supplierBillId.trim(),
    'expected_version': expectedVersion,
    'original_payment_id': originalPaymentId.trim(),
    'reversal_date': reversalDate.postgresText,
    'reversal_reference': reversalReference.trim(),
    'reason': reason.trim(),
  };
}

final class YorksAccountsSupplierBillCancelInput {
  const YorksAccountsSupplierBillCancelInput({
    required this.projectId,
    required this.supplierBillId,
    required this.expectedVersion,
    required this.reason,
  });

  final String projectId;
  final String supplierBillId;
  final int expectedVersion;
  final String reason;

  bool get isValid =>
      projectId.trim().isNotEmpty &&
      supplierBillId.trim().isNotEmpty &&
      expectedVersion > 0 &&
      reason.trim().isNotEmpty;

  Map<String, Object?> idempotencyPayload() => {
    'project_id': projectId.trim(),
    'supplier_bill_id': supplierBillId.trim(),
    'expected_version': expectedVersion,
    'reason': reason.trim(),
  };
}

/// Edits a payment in one step: a reversal and a new payment, together.
final class YorksAccountsSupplierPaymentCorrectionInput {
  const YorksAccountsSupplierPaymentCorrectionInput({
    required this.projectId,
    required this.supplierBillId,
    required this.expectedVersion,
    required this.originalPaymentId,
    required this.paymentDate,
    required this.paymentMethod,
    required this.paymentReference,
    required this.amount,
    required this.reason,
  });

  final String projectId;
  final String supplierBillId;
  final int expectedVersion;
  final String originalPaymentId;
  final YorksAccountsDate paymentDate;
  final String paymentMethod;
  final String paymentReference;
  final YorksAccountsDecimal amount;
  final String reason;

  bool get isValid =>
      projectId.trim().isNotEmpty &&
      supplierBillId.trim().isNotEmpty &&
      expectedVersion > 0 &&
      originalPaymentId.trim().isNotEmpty &&
      paymentMethod.trim().isNotEmpty &&
      paymentReference.trim().isNotEmpty &&
      amount.isPositive &&
      reason.trim().isNotEmpty;

  Map<String, Object?> idempotencyPayload() => {
    'project_id': projectId.trim(),
    'supplier_bill_id': supplierBillId.trim(),
    'expected_version': expectedVersion,
    'original_payment_id': originalPaymentId.trim(),
    'payment_date': paymentDate.postgresText,
    'payment_method': paymentMethod.trim(),
    'payment_reference': paymentReference.trim(),
    'amount': amount.postgresText,
    'reason': reason.trim(),
  };
}

bool _optionalValuesAreNonblank(Iterable<String?> values) =>
    values.every((value) => value == null || value.trim().isNotEmpty);

String? _nullableTrimmed(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

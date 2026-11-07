import 'accounts_decimal.dart';
import 'accounts_receivables_inputs.dart';

enum YorksAccountsSupplierMatchStatus {
  blocked('blocked'),
  review('review'),
  matched('matched');

  const YorksAccountsSupplierMatchStatus(this.wireValue);
  final String wireValue;

  static YorksAccountsSupplierMatchStatus? tryParse(Object? raw) =>
      _parseEnum(raw, values, (value) => value.wireValue);
}

enum YorksAccountsSupplierBillStatus {
  draft('draft'),
  approved('approved'),
  cancelled('cancelled');

  const YorksAccountsSupplierBillStatus(this.wireValue);
  final String wireValue;

  static YorksAccountsSupplierBillStatus? tryParse(Object? raw) =>
      _parseEnum(raw, values, (value) => value.wireValue);
}

enum YorksAccountsSupplierPaymentStatus {
  pending('pending'),
  approved('approved'),
  partiallyPaid('partially_paid'),
  paid('paid'),
  blocked('blocked'),
  cancelled('cancelled');

  const YorksAccountsSupplierPaymentStatus(this.wireValue);
  final String wireValue;

  static YorksAccountsSupplierPaymentStatus? tryParse(Object? raw) =>
      _parseEnum(raw, values, (value) => value.wireValue);
}

enum YorksAccountsSupplierPaymentEntryKind {
  payment('payment'),
  reversal('reversal');

  const YorksAccountsSupplierPaymentEntryKind(this.wireValue);
  final String wireValue;

  static YorksAccountsSupplierPaymentEntryKind? tryParse(Object? raw) =>
      _parseEnum(raw, values, (value) => value.wireValue);
}

final class YorksAccountsSupplierCapabilities {
  const YorksAccountsSupplierCapabilities({
    required this.manageSupplierBills,
    required this.approveSupplierBillPayment,
    required this.viewSupplierCosts,
  });

  final bool manageSupplierBills;
  final bool approveSupplierBillPayment;
  final bool viewSupplierCosts;

  factory YorksAccountsSupplierCapabilities.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksAccountsSupplierCapabilities(
    manageSupplierBills: _requiredBool(json, 'manage_supplier_bills'),
    approveSupplierBillPayment: _requiredBool(
      json,
      'approve_supplier_bill_payment',
    ),
    viewSupplierCosts: _requiredBool(json, 'view_supplier_costs'),
  );
}

final class YorksAccountsSupplierCommands {
  const YorksAccountsSupplierCommands({
    required this.createBill,
    required this.editBill,
    required this.approveBill,
    required this.recordPayment,
    required this.reversePayment,
    required this.cancelBill,
    this.correctPayment = false,
    this.reopenBill = false,
  });

  final bool createBill;
  final bool editBill;
  final bool approveBill;
  final bool recordPayment;
  final bool reversePayment;
  final bool cancelBill;
  final bool correctPayment;
  final bool reopenBill;

  factory YorksAccountsSupplierCommands.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksAccountsSupplierCommands(
    createBill: _requiredBool(json, 'create_bill'),
    editBill: _requiredBool(json, 'edit_bill'),
    approveBill: _requiredBool(json, 'approve_bill'),
    recordPayment: _requiredBool(json, 'record_payment'),
    reversePayment: _requiredBool(json, 'reverse_payment'),
    cancelBill: _requiredBool(json, 'cancel_bill'),
    correctPayment: json['correct_payment'] == true,
    reopenBill: json['reopen_bill'] == true,
  );
}

final class YorksAccountsAcceptedDelivery {
  const YorksAccountsAcceptedDelivery({
    required this.receiptReviewId,
    required this.deliveryReference,
    required this.dispatchId,
    required this.dispatchNumber,
    required this.reviewedAt,
    required this.acceptedGoodQuantity,
  });

  final String receiptReviewId;
  final String deliveryReference;
  final String dispatchId;
  final String dispatchNumber;
  final DateTime reviewedAt;
  final YorksAccountsDecimal acceptedGoodQuantity;

  factory YorksAccountsAcceptedDelivery.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksAccountsAcceptedDelivery(
    receiptReviewId: _requiredString(json, 'receipt_review_id'),
    deliveryReference: _requiredString(json, 'delivery_reference'),
    dispatchId: _requiredString(json, 'dispatch_id'),
    dispatchNumber: _requiredString(json, 'dispatch_number'),
    reviewedAt: _requiredDateTime(json, 'reviewed_at'),
    acceptedGoodQuantity: _requiredDecimal(json, 'accepted_good_quantity'),
  );
}

final class YorksAccountsSupplierBill {
  const YorksAccountsSupplierBill({
    required this.supplierBillId,
    required this.projectId,
    required this.supplierId,
    required this.supplierName,
    required this.supplierInvoiceReference,
    required this.invoiceDate,
    required this.dueDate,
    required this.exVatAmount,
    required this.vatRatePercent,
    required this.vatAmount,
    required this.totalInclVat,
    required this.poLpoReference,
    required this.poLpoDocumentId,
    required this.acceptedReceiptReviewId,
    required this.acceptedDeliveryReference,
    required this.acceptedDelivery,
    required this.supplierInvoiceDocumentId,
    required this.explicitMismatchReason,
    required this.matchStatus,
    required this.status,
    required this.paymentStatus,
    required this.paidAmount,
    required this.outstandingAmount,
    required this.approvalAdminExceptionReason,
    required this.approvedAt,
    required this.approvedByAuthUserId,
    required this.approvedByExactRole,
    required this.cancelledAt,
    required this.cancellationReason,
    required this.notes,
    required this.recordVersion,
    required this.createdByAuthUserId,
    required this.createdByExactRole,
    required this.createdAt,
    required this.updatedAt,
  });

  final String supplierBillId;
  final String projectId;
  final String? supplierId;
  final String supplierName;
  final String supplierInvoiceReference;
  final YorksAccountsDate invoiceDate;
  final YorksAccountsDate dueDate;
  final YorksAccountsDecimal exVatAmount;
  final YorksAccountsDecimal vatRatePercent;
  final YorksAccountsDecimal vatAmount;
  final YorksAccountsDecimal totalInclVat;
  final String? poLpoReference;
  final String? poLpoDocumentId;
  final String? acceptedReceiptReviewId;
  final String? acceptedDeliveryReference;
  final YorksAccountsAcceptedDelivery? acceptedDelivery;
  final String? supplierInvoiceDocumentId;
  final String? explicitMismatchReason;
  final YorksAccountsSupplierMatchStatus matchStatus;
  final YorksAccountsSupplierBillStatus status;
  final YorksAccountsSupplierPaymentStatus paymentStatus;
  final YorksAccountsDecimal paidAmount;
  final YorksAccountsDecimal outstandingAmount;
  final String? approvalAdminExceptionReason;
  final DateTime? approvedAt;
  final String? approvedByAuthUserId;
  final String? approvedByExactRole;
  final DateTime? cancelledAt;
  final String? cancellationReason;
  final String? notes;
  final int recordVersion;
  final String createdByAuthUserId;
  final String createdByExactRole;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory YorksAccountsSupplierBill.fromRpcJson(Map<String, dynamic> json) {
    final matchStatus = YorksAccountsSupplierMatchStatus.tryParse(
      json['match_status'],
    );
    final status = YorksAccountsSupplierBillStatus.tryParse(json['status']);
    final paymentStatus = YorksAccountsSupplierPaymentStatus.tryParse(
      json['payment_status'],
    );
    if (matchStatus == null || status == null || paymentStatus == null) {
      throw const FormatException('Invalid supplier bill lifecycle status.');
    }
    final acceptedDeliveryJson = _optionalMap(json['accepted_delivery']);
    final bill = YorksAccountsSupplierBill(
      supplierBillId: _requiredString(json, 'supplier_bill_id'),
      projectId: _requiredString(json, 'project_id'),
      supplierId: _optionalString(json['supplier_id']),
      supplierName: _requiredString(json, 'supplier_name'),
      supplierInvoiceReference: _requiredString(
        json,
        'supplier_invoice_reference',
      ),
      invoiceDate: _requiredDate(json, 'invoice_date'),
      dueDate: _requiredDate(json, 'due_date'),
      exVatAmount: _requiredMoney(json, 'ex_vat_amount'),
      vatRatePercent: _requiredPercent(json, 'vat_rate_percent'),
      vatAmount: _requiredMoney(json, 'vat_amount'),
      totalInclVat: _requiredMoney(json, 'total_incl_vat'),
      poLpoReference: _optionalString(json['po_lpo_reference']),
      poLpoDocumentId: _optionalString(json['po_lpo_document_id']),
      acceptedReceiptReviewId: _optionalString(
        json['accepted_receipt_review_id'],
      ),
      acceptedDeliveryReference: _optionalString(
        json['accepted_delivery_reference'],
      ),
      acceptedDelivery: acceptedDeliveryJson == null
          ? null
          : YorksAccountsAcceptedDelivery.fromRpcJson(acceptedDeliveryJson),
      supplierInvoiceDocumentId: _optionalString(
        json['supplier_invoice_document_id'],
      ),
      explicitMismatchReason: _optionalString(json['explicit_mismatch_reason']),
      matchStatus: matchStatus,
      status: status,
      paymentStatus: paymentStatus,
      paidAmount: _requiredMoney(json, 'paid_amount'),
      outstandingAmount: _requiredMoney(json, 'outstanding_amount'),
      approvalAdminExceptionReason: _optionalString(
        json['approval_admin_exception_reason'],
      ),
      approvedAt: _optionalDateTime(json['approved_at']),
      approvedByAuthUserId: _optionalString(json['approved_by_auth_user_id']),
      approvedByExactRole: _optionalString(json['approved_by_exact_role']),
      cancelledAt: _optionalDateTime(json['cancelled_at']),
      cancellationReason: _optionalString(json['cancellation_reason']),
      notes: _optionalString(json['notes']),
      recordVersion: _requiredInt(json, 'record_version'),
      createdByAuthUserId: _requiredString(json, 'created_by_auth_user_id'),
      createdByExactRole: _requiredString(json, 'created_by_exact_role'),
      createdAt: _requiredDateTime(json, 'created_at'),
      updatedAt: _requiredDateTime(json, 'updated_at'),
    );
    if (bill.dueDate.compareTo(bill.invoiceDate) < 0 ||
        bill.exVatAmount + bill.vatAmount != bill.totalInclVat ||
        bill.paidAmount.isNegative ||
        bill.outstandingAmount.isNegative ||
        ((bill.acceptedReceiptReviewId == null) !=
            (bill.acceptedDeliveryReference == null)) ||
        ((bill.acceptedDelivery == null) !=
            (bill.acceptedReceiptReviewId == null)) ||
        (bill.acceptedDelivery != null &&
            (bill.acceptedDelivery!.receiptReviewId !=
                    bill.acceptedReceiptReviewId ||
                bill.acceptedDelivery!.deliveryReference !=
                    bill.acceptedDeliveryReference))) {
      throw const FormatException('Inconsistent supplier bill response.');
    }
    return bill;
  }
}

final class YorksAccountsSupplierPayment {
  const YorksAccountsSupplierPayment({
    required this.paymentId,
    required this.entryKind,
    required this.originalPaymentId,
    required this.paymentDate,
    required this.paymentMethod,
    required this.paymentReference,
    required this.amount,
    required this.reason,
    required this.adminExceptionReason,
    required this.actorAuthUserId,
    required this.actorExactRole,
    required this.createdAt,
  });

  final String paymentId;
  final YorksAccountsSupplierPaymentEntryKind entryKind;
  final String? originalPaymentId;
  final YorksAccountsDate paymentDate;
  final String paymentMethod;
  final String paymentReference;
  final YorksAccountsDecimal amount;
  final String? reason;
  final String? adminExceptionReason;
  final String actorAuthUserId;
  final String actorExactRole;
  final DateTime createdAt;

  factory YorksAccountsSupplierPayment.fromRpcJson(Map<String, dynamic> json) {
    final kind = YorksAccountsSupplierPaymentEntryKind.tryParse(
      json['entry_kind'],
    );
    if (kind == null) {
      throw FormatException('Invalid supplier payment kind.', json);
    }
    final payment = YorksAccountsSupplierPayment(
      paymentId: _requiredString(json, 'payment_id'),
      entryKind: kind,
      originalPaymentId: _optionalString(json['original_payment_id']),
      paymentDate: _requiredDate(json, 'payment_date'),
      paymentMethod: _requiredString(json, 'payment_method'),
      paymentReference: _requiredString(json, 'payment_reference'),
      amount: _requiredMoney(json, 'amount'),
      reason: _optionalString(json['reason']),
      adminExceptionReason: _optionalString(json['admin_exception_reason']),
      actorAuthUserId: _requiredString(json, 'actor_auth_user_id'),
      actorExactRole: _requiredString(json, 'actor_exact_role'),
      createdAt: _requiredDateTime(json, 'created_at'),
    );
    if (!payment.amount.isPositive ||
        (kind == YorksAccountsSupplierPaymentEntryKind.payment &&
            payment.originalPaymentId != null) ||
        (kind == YorksAccountsSupplierPaymentEntryKind.reversal &&
            (payment.originalPaymentId == null || payment.reason == null))) {
      throw const FormatException('Inconsistent supplier payment response.');
    }
    return payment;
  }
}

final class YorksAccountsSupplierBillCursor {
  const YorksAccountsSupplierBillCursor({
    required this.updatedAt,
    required this.supplierBillId,
  });

  final DateTime updatedAt;
  final String supplierBillId;

  factory YorksAccountsSupplierBillCursor.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksAccountsSupplierBillCursor(
    updatedAt: _requiredDateTime(json, 'updated_at'),
    supplierBillId: _requiredString(json, 'supplier_bill_id'),
  );
}

final class YorksAccountsSupplierBillsProjection {
  YorksAccountsSupplierBillsProjection({
    required this.projectId,
    required List<YorksAccountsSupplierBill> items,
    required this.nextCursor,
    required this.capabilities,
    required this.commands,
  }) : items = List.unmodifiable(items);

  final String projectId;
  final List<YorksAccountsSupplierBill> items;
  final YorksAccountsSupplierBillCursor? nextCursor;
  final YorksAccountsSupplierCapabilities capabilities;
  final YorksAccountsSupplierCommands commands;

  factory YorksAccountsSupplierBillsProjection.fromRpcJson(
    Map<String, dynamic> json,
  ) {
    _requireSchemaVersion(json);
    final items = _requiredList(json, 'items')
        .map(
          (item) => YorksAccountsSupplierBill.fromRpcJson(_requiredMap(item)),
        )
        .toList(growable: false);
    final cursor = _optionalMap(json['next_cursor']);
    return YorksAccountsSupplierBillsProjection(
      projectId: _requiredString(json, 'project_id'),
      items: items,
      nextCursor: cursor == null
          ? null
          : YorksAccountsSupplierBillCursor.fromRpcJson(cursor),
      capabilities: YorksAccountsSupplierCapabilities.fromRpcJson(
        _requiredMap(json['capabilities']),
      ),
      commands: YorksAccountsSupplierCommands.fromRpcJson(
        _requiredMap(json['commands']),
      ),
    );
  }
}

final class YorksAccountsSupplierBillDetailProjection {
  YorksAccountsSupplierBillDetailProjection({
    required this.projectId,
    required this.supplierBill,
    required List<YorksAccountsSupplierPayment> payments,
    required this.capabilities,
    required this.commands,
  }) : payments = List.unmodifiable(payments);

  final String projectId;
  final YorksAccountsSupplierBill supplierBill;
  final List<YorksAccountsSupplierPayment> payments;
  final YorksAccountsSupplierCapabilities capabilities;
  final YorksAccountsSupplierCommands commands;

  factory YorksAccountsSupplierBillDetailProjection.fromRpcJson(
    Map<String, dynamic> json,
  ) {
    _requireSchemaVersion(json);
    return YorksAccountsSupplierBillDetailProjection(
      projectId: _requiredString(json, 'project_id'),
      supplierBill: YorksAccountsSupplierBill.fromRpcJson(
        _requiredMap(json['supplier_bill']),
      ),
      payments: _requiredList(json, 'payments')
          .map(
            (payment) =>
                YorksAccountsSupplierPayment.fromRpcJson(_requiredMap(payment)),
          )
          .toList(growable: false),
      capabilities: YorksAccountsSupplierCapabilities.fromRpcJson(
        _requiredMap(json['capabilities']),
      ),
      commands: YorksAccountsSupplierCommands.fromRpcJson(
        _requiredMap(json['commands']),
      ),
    );
  }
}

final class YorksAccountsSupplierCommandResult {
  const YorksAccountsSupplierCommandResult({
    required this.projectId,
    required this.entityId,
    required this.supplierBillId,
    required this.paymentId,
    required this.reversalId,
    required this.recordVersion,
    required this.status,
    required this.matchStatus,
    required this.paymentStatus,
    required this.amount,
    required this.replayed,
    required this.updatedAt,
  });

  final String projectId;
  final String entityId;
  final String supplierBillId;
  final String? paymentId;
  final String? reversalId;
  final int? recordVersion;
  final YorksAccountsSupplierBillStatus? status;
  final YorksAccountsSupplierMatchStatus? matchStatus;
  final YorksAccountsSupplierPaymentStatus? paymentStatus;
  final YorksAccountsDecimal? amount;
  final bool replayed;
  final DateTime updatedAt;

  factory YorksAccountsSupplierCommandResult.fromRpcJson(
    Map<String, dynamic> json,
  ) {
    _requireSchemaVersion(json);
    final entityId = _requiredString(json, 'entity_id');
    final supplierBillId = _requiredString(json, 'supplier_bill_id');
    final paymentId = _optionalString(json['payment_id']);
    final reversalId = _optionalString(json['reversal_id']);
    if (paymentId != null && reversalId != null) {
      throw const FormatException('Ambiguous supplier command entity.');
    }
    if ((paymentId ?? reversalId) != null &&
        (paymentId ?? reversalId) != entityId) {
      throw const FormatException('Supplier command entity mismatch.');
    }
    if (paymentId == null && reversalId == null && entityId != supplierBillId) {
      throw const FormatException('Supplier bill command entity mismatch.');
    }
    return YorksAccountsSupplierCommandResult(
      projectId: _requiredString(json, 'project_id'),
      entityId: entityId,
      supplierBillId: supplierBillId,
      paymentId: paymentId,
      reversalId: reversalId,
      recordVersion: _optionalInt(
        json['record_version'] ?? json['supplier_bill_record_version'],
      ),
      status: _optionalEnum(
        json['status'],
        YorksAccountsSupplierBillStatus.tryParse,
      ),
      matchStatus: _optionalEnum(
        json['match_status'],
        YorksAccountsSupplierMatchStatus.tryParse,
      ),
      paymentStatus: _optionalEnum(
        json['payment_status'],
        YorksAccountsSupplierPaymentStatus.tryParse,
      ),
      amount: json['amount'] == null ? null : _requiredMoney(json, 'amount'),
      replayed: _requiredBool(json, 'replayed'),
      updatedAt: _requiredDateTime(json, 'updated_at'),
    );
  }
}

T? _parseEnum<T>(Object? raw, Iterable<T> values, String Function(T) wire) {
  if (raw is! String) return null;
  for (final value in values) {
    if (wire(value) == raw) return value;
  }
  return null;
}

T? _optionalEnum<T>(Object? raw, T? Function(Object?) parse) {
  if (raw == null) return null;
  final value = parse(raw);
  if (value == null) throw FormatException('Invalid enum response.', raw);
  return value;
}

void _requireSchemaVersion(Map<String, dynamic> json) {
  if (json['schema_version'] != 4) {
    throw FormatException('Unsupported supplier schema version.', json);
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _optionalString(json[key]);
  if (value == null) throw FormatException('$key is required.', json[key]);
  return value;
}

String? _optionalString(Object? raw) {
  if (raw == null) return null;
  if (raw is! String || raw.trim().isEmpty) {
    throw FormatException('Expected a nonblank string.', raw);
  }
  return raw.trim();
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = _optionalInt(json[key]);
  if (value == null) throw FormatException('$key is required.', json[key]);
  return value;
}

int? _optionalInt(Object? raw) {
  if (raw == null) return null;
  if (raw is! int || raw < 1) throw FormatException('Invalid integer.', raw);
  return raw;
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('$key must be boolean.', value);
  return value;
}

YorksAccountsDate _requiredDate(Map<String, dynamic> json, String key) {
  final raw = json[key];
  if (raw is! String) throw FormatException('$key must be a date.', raw);
  return YorksAccountsDate.parse(raw);
}

DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
  final value = _optionalDateTime(json[key]);
  if (value == null) throw FormatException('$key is required.', json[key]);
  return value;
}

DateTime? _optionalDateTime(Object? raw) {
  if (raw == null) return null;
  if (raw is! String ||
      !(raw.endsWith('Z') || RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(raw))) {
    throw FormatException('Timestamp must include an offset.', raw);
  }
  return DateTime.tryParse(raw)?.toUtc() ??
      (throw FormatException('Invalid timestamp.', raw));
}

YorksAccountsDecimal _requiredDecimal(Map<String, dynamic> json, String key) =>
    YorksAccountsDecimal.fromRpcValue(json[key], key: key);

YorksAccountsDecimal _requiredMoney(Map<String, dynamic> json, String key) {
  final value = _requiredDecimal(json, key);
  if (value.isNegative || value.fractionDigits > 2) {
    throw FormatException('$key must be non-negative money.', json[key]);
  }
  return value;
}

YorksAccountsDecimal _requiredPercent(Map<String, dynamic> json, String key) {
  final value = _requiredDecimal(json, key);
  if (value.isNegative ||
      value.compareTo(YorksAccountsDecimal.hundred) > 0 ||
      value.fractionDigits > 4) {
    throw FormatException('$key must be a percentage.', json[key]);
  }
  return value;
}

Map<String, dynamic> _requiredMap(Object? raw) {
  if (raw is! Map) throw FormatException('Expected object.', raw);
  return Map<String, dynamic>.from(raw);
}

Map<String, dynamic>? _optionalMap(Object? raw) {
  if (raw == null) return null;
  return _requiredMap(raw);
}

List<Object?> _requiredList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) throw FormatException('$key must be an array.', value);
  return List<Object?>.from(value);
}

import 'accounts_decimal.dart';

/// Calendar-only date used by Accounts RPCs.
///
/// A commercial submission, cheque or payment date must not move when a
/// device changes time zone, so this boundary never accepts a `DateTime` or a
/// locale-formatted string.
final class YorksAccountsDate implements Comparable<YorksAccountsDate> {
  const YorksAccountsDate._(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  static YorksAccountsDate? tryParse(String raw) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw.trim());
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (year < 1) return null;
    final value = DateTime.utc(year, month, day);
    if (value.year != year || value.month != month || value.day != day) {
      return null;
    }
    return YorksAccountsDate._(year, month, day);
  }

  factory YorksAccountsDate.parse(String raw) {
    final value = tryParse(raw);
    if (value == null) throw FormatException('Invalid Accounts date.', raw);
    return value;
  }

  String get postgresText =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  @override
  int compareTo(YorksAccountsDate other) =>
      postgresText.compareTo(other.postgresText);

  @override
  bool operator ==(Object other) =>
      other is YorksAccountsDate && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => postgresText;
}

final class YorksAccountsClaimLineInput {
  YorksAccountsClaimLineInput({
    required this.progressEntryId,
    required this.claimedAmount,
    required this.evidenceReference,
  });

  final String progressEntryId;
  final YorksAccountsDecimal claimedAmount;
  final String? evidenceReference;

  bool get isValid =>
      progressEntryId.trim().isNotEmpty &&
      claimedAmount.isPositive &&
      claimedAmount.fractionDigits <= 2 &&
      (evidenceReference == null || evidenceReference!.trim().isNotEmpty);

  Map<String, Object?> toRpcJson() => {
    'progress_entry_id': progressEntryId.trim(),
    'claimed_amount': claimedAmount.postgresText,
    'evidence_reference': _nullableTrimmed(evidenceReference),
  };
}

final class YorksAccountsClaimDraftInput {
  YorksAccountsClaimDraftInput({
    required this.projectId,
    required this.claimReference,
    required this.periodStart,
    required this.periodEnd,
    required List<YorksAccountsClaimLineInput> lines,
    required this.notes,
    this.adminExceptionReason,
    this.claimId,
    this.expectedVersion,
  }) : lines = List.unmodifiable(lines);

  final String projectId;
  final String? claimId;
  final int? expectedVersion;
  final String claimReference;
  final YorksAccountsDate periodStart;
  final YorksAccountsDate periodEnd;
  final List<YorksAccountsClaimLineInput> lines;
  final String notes;
  final String? adminExceptionReason;

  bool get isUpdate => claimId != null || expectedVersion != null;

  bool get isValid {
    if (projectId.trim().isEmpty || claimReference.trim().isEmpty) return false;
    if (periodEnd.compareTo(periodStart) < 0 || lines.isEmpty) return false;
    if (isUpdate &&
        (claimId == null ||
            claimId!.trim().isEmpty ||
            expectedVersion == null ||
            expectedVersion! < 1)) {
      return false;
    }
    if (!isUpdate && (claimId != null || expectedVersion != null)) return false;
    if (adminExceptionReason != null && adminExceptionReason!.trim().isEmpty) {
      return false;
    }
    if (lines.any((line) => !line.isValid)) return false;
    final progressIds = lines
        .map((line) => line.progressEntryId.trim())
        .toSet();
    return progressIds.length == lines.length;
  }

  Map<String, Object?> idempotencyPayload() => {
    'project_id': projectId.trim(),
    if (claimId != null) 'claim_id': claimId!.trim(),
    if (expectedVersion != null) 'expected_version': expectedVersion,
    'claim_reference': claimReference.trim(),
    'claim_period_start': periodStart.postgresText,
    'claim_period_end': periodEnd.postgresText,
    'lines': lines.map((line) => line.toRpcJson()).toList(growable: false),
    'notes': notes.trim(),
    'admin_exception_reason': _nullableTrimmed(adminExceptionReason),
  };
}

/// Versioned reason-bearing command for a claim or invoice state transition.
final class YorksAccountsEntityActionInput {
  const YorksAccountsEntityActionInput({
    required this.projectId,
    required this.entityId,
    required this.expectedVersion,
    required this.reason,
  });

  final String projectId;
  final String entityId;
  final int expectedVersion;
  final String reason;

  bool get isValid =>
      projectId.trim().isNotEmpty &&
      entityId.trim().isNotEmpty &&
      expectedVersion > 0 &&
      reason.trim().isNotEmpty;

  Map<String, Object?> idempotencyPayload() => {
    'project_id': projectId.trim(),
    'entity_id': entityId.trim(),
    'expected_version': expectedVersion,
    'reason': reason.trim(),
  };
}

final class YorksAccountsInvoiceDraftInput {
  const YorksAccountsInvoiceDraftInput({
    required this.projectId,
    required this.claimId,
    required this.invoiceReference,
    required this.notes,
    this.invoiceId,
    this.expectedVersion,
  });

  final String projectId;
  final String? claimId;
  final String? invoiceId;
  final int? expectedVersion;
  final String invoiceReference;
  final String notes;

  bool get isUpdate => invoiceId != null || expectedVersion != null;

  bool get isValid {
    if (projectId.trim().isEmpty || invoiceReference.trim().isEmpty) {
      return false;
    }
    if (!isUpdate) {
      return claimId != null &&
          claimId!.trim().isNotEmpty &&
          invoiceId == null &&
          expectedVersion == null;
    }
    return invoiceId != null &&
        invoiceId!.trim().isNotEmpty &&
        expectedVersion != null &&
        expectedVersion! > 0 &&
        (claimId == null || claimId!.trim().isNotEmpty);
  }

  Map<String, Object?> idempotencyPayload() => {
    'project_id': projectId.trim(),
    if (claimId != null) 'claim_id': claimId!.trim(),
    if (invoiceId != null) 'invoice_id': invoiceId!.trim(),
    if (expectedVersion != null) 'expected_version': expectedVersion,
    'invoice_reference': invoiceReference.trim(),
    'notes': notes.trim(),
  };
}

final class YorksAccountsInvoiceSubmitInput {
  const YorksAccountsInvoiceSubmitInput({
    required this.projectId,
    required this.invoiceId,
    required this.expectedVersion,
    required this.submissionDate,
    required this.adminExceptionReason,
  });

  final String projectId;
  final String invoiceId;
  final int expectedVersion;
  final YorksAccountsDate submissionDate;
  final String? adminExceptionReason;

  bool get isValid =>
      projectId.trim().isNotEmpty &&
      invoiceId.trim().isNotEmpty &&
      expectedVersion > 0 &&
      adminExceptionReason == null;

  Map<String, Object?> idempotencyPayload() => {
    'project_id': projectId.trim(),
    'invoice_id': invoiceId.trim(),
    'expected_version': expectedVersion,
    'submission_date': submissionDate.postgresText,
    'admin_exception_reason': _nullableTrimmed(adminExceptionReason),
  };
}

final class YorksAccountsCertificationInput {
  const YorksAccountsCertificationInput({
    required this.projectId,
    required this.invoiceId,
    required this.expectedVersion,
    required this.certifiedExVat,
    required this.certificationDate,
    required this.certificationReference,
    required this.differenceReason,
  });

  final String projectId;
  final String invoiceId;
  final int expectedVersion;
  final YorksAccountsDecimal certifiedExVat;
  final YorksAccountsDate certificationDate;
  final String certificationReference;
  final String? differenceReason;

  bool get isStructurallyValid =>
      projectId.trim().isNotEmpty &&
      invoiceId.trim().isNotEmpty &&
      expectedVersion > 0 &&
      !certifiedExVat.isNegative &&
      certifiedExVat.fractionDigits <= 2 &&
      certificationReference.trim().isNotEmpty &&
      (differenceReason == null || differenceReason!.trim().isNotEmpty);

  bool isValidAgainstClaimed(YorksAccountsDecimal claimedExVat) =>
      isStructurallyValid &&
      certifiedExVat.compareTo(claimedExVat) <= 0 &&
      (certifiedExVat == claimedExVat ||
          _nullableTrimmed(differenceReason) != null);

  Map<String, Object?> idempotencyPayload() => {
    'project_id': projectId.trim(),
    'invoice_id': invoiceId.trim(),
    'expected_version': expectedVersion,
    'certified_ex_vat': certifiedExVat.postgresText,
    'certification_date': certificationDate.postgresText,
    'certification_reference': certificationReference.trim(),
    'difference_reason': _nullableTrimmed(differenceReason),
  };
}

final class YorksAccountsPaymentInput {
  const YorksAccountsPaymentInput({
    required this.projectId,
    required this.invoiceId,
    required this.expectedVersion,
    required this.paymentDate,
    required this.amount,
    required this.paymentMethod,
    required this.paymentReference,
    required this.reason,
  });

  final String projectId;
  final String invoiceId;
  final int expectedVersion;
  final YorksAccountsDate paymentDate;
  final YorksAccountsDecimal amount;
  final String paymentMethod;
  final String paymentReference;
  final String? reason;

  bool get isValid =>
      projectId.trim().isNotEmpty &&
      invoiceId.trim().isNotEmpty &&
      expectedVersion > 0 &&
      amount.isPositive &&
      amount.fractionDigits <= 2 &&
      paymentMethod.trim().isNotEmpty &&
      paymentReference.trim().isNotEmpty &&
      (reason == null || reason!.trim().isNotEmpty);

  Map<String, Object?> idempotencyPayload() => {
    'project_id': projectId.trim(),
    'invoice_id': invoiceId.trim(),
    'expected_version': expectedVersion,
    'payment_date': paymentDate.postgresText,
    'amount': amount.postgresText,
    'payment_method': paymentMethod.trim(),
    'payment_reference': paymentReference.trim(),
    'reason': _nullableTrimmed(reason),
  };
}

final class YorksAccountsPaymentReversalInput {
  const YorksAccountsPaymentReversalInput({
    required this.projectId,
    required this.invoiceId,
    required this.expectedVersion,
    required this.originalPaymentId,
    required this.reversalDate,
    required this.reversalReference,
    required this.reason,
    this.chequeOutcome,
  });

  final String projectId;
  final String invoiceId;
  final int expectedVersion;
  final String originalPaymentId;
  final YorksAccountsDate reversalDate;

  /// Blank lets the server pick one from the original reference.
  final String reversalReference;
  final String reason;

  /// Where a cheque's status goes when its payment is reversed: deposited,
  /// returned or bounced. Null means deposited. Ignored for other payments.
  final YorksAccountsPdcStatus? chequeOutcome;

  bool get isValid =>
      projectId.trim().isNotEmpty &&
      invoiceId.trim().isNotEmpty &&
      expectedVersion > 0 &&
      originalPaymentId.trim().isNotEmpty &&
      reason.trim().isNotEmpty;

  Map<String, Object?> idempotencyPayload() => {
    'project_id': projectId.trim(),
    'invoice_id': invoiceId.trim(),
    'expected_version': expectedVersion,
    'original_payment_id': originalPaymentId.trim(),
    'reversal_date': reversalDate.postgresText,
    'reversal_reference': reversalReference.trim(),
    'reason': reason.trim(),
    'cheque_outcome': chequeOutcome?.wireValue,
  };
}

/// Edits a payment in one step: a reversal and a new receipt, together.
final class YorksAccountsPaymentCorrectionInput {
  const YorksAccountsPaymentCorrectionInput({
    required this.projectId,
    required this.invoiceId,
    required this.expectedVersion,
    required this.originalPaymentId,
    required this.paymentDate,
    required this.paymentMethod,
    required this.paymentReference,
    required this.amount,
    required this.reason,
  });

  final String projectId;
  final String invoiceId;
  final int expectedVersion;
  final String originalPaymentId;
  final YorksAccountsDate paymentDate;
  final String paymentMethod;
  final String paymentReference;
  final YorksAccountsDecimal amount;
  final String reason;

  bool get isValid =>
      projectId.trim().isNotEmpty &&
      invoiceId.trim().isNotEmpty &&
      expectedVersion > 0 &&
      originalPaymentId.trim().isNotEmpty &&
      paymentMethod.trim().isNotEmpty &&
      paymentReference.trim().isNotEmpty &&
      amount.isPositive &&
      reason.trim().isNotEmpty;

  Map<String, Object?> idempotencyPayload() => {
    'project_id': projectId.trim(),
    'invoice_id': invoiceId.trim(),
    'expected_version': expectedVersion,
    'original_payment_id': originalPaymentId.trim(),
    'payment_date': paymentDate.postgresText,
    'payment_method': paymentMethod.trim(),
    'payment_reference': paymentReference.trim(),
    'amount': amount.postgresText,
    'reason': reason.trim(),
  };
}

/// Edits the latest certification. Zero undoes it.
final class YorksAccountsCertificationCorrectionInput {
  const YorksAccountsCertificationCorrectionInput({
    required this.projectId,
    required this.invoiceId,
    required this.expectedVersion,
    required this.certificationReference,
    required this.certificationDate,
    required this.certifiedExVat,
    required this.reason,
  });

  final String projectId;
  final String invoiceId;
  final int expectedVersion;
  final String certificationReference;
  final YorksAccountsDate certificationDate;
  final YorksAccountsDecimal certifiedExVat;
  final String reason;

  bool get isValid =>
      projectId.trim().isNotEmpty &&
      invoiceId.trim().isNotEmpty &&
      expectedVersion > 0 &&
      certificationReference.trim().isNotEmpty &&
      !certifiedExVat.isNegative &&
      reason.trim().isNotEmpty;

  Map<String, Object?> idempotencyPayload() => {
    'project_id': projectId.trim(),
    'invoice_id': invoiceId.trim(),
    'expected_version': expectedVersion,
    'certification_reference': certificationReference.trim(),
    'certification_date': certificationDate.postgresText,
    'certified_ex_vat': certifiedExVat.postgresText,
    'reason': reason.trim(),
  };
}

/// Edits a cheque's details without changing where it is in its lifecycle.
final class YorksAccountsPdcEditInput {
  const YorksAccountsPdcEditInput({
    required this.projectId,
    required this.pdcId,
    required this.expectedVersion,
    required this.chequeNumber,
    required this.chequeDate,
    required this.amount,
    required this.bankName,
    required this.reason,
  });

  final String projectId;
  final String pdcId;
  final int expectedVersion;
  final String chequeNumber;
  final YorksAccountsDate chequeDate;
  final YorksAccountsDecimal amount;
  final String? bankName;
  final String reason;

  bool get isValid =>
      projectId.trim().isNotEmpty &&
      pdcId.trim().isNotEmpty &&
      expectedVersion > 0 &&
      chequeNumber.trim().isNotEmpty &&
      amount.isPositive &&
      reason.trim().isNotEmpty;

  Map<String, Object?> idempotencyPayload() => {
    'project_id': projectId.trim(),
    'pdc_id': pdcId.trim(),
    'expected_version': expectedVersion,
    'cheque_number': chequeNumber.trim(),
    'cheque_date': chequeDate.postgresText,
    'amount': amount.postgresText,
    'bank_name': _nullableTrimmed(bankName),
    'reason': reason.trim(),
  };
}

final class YorksAccountsPdcCreateInput {
  const YorksAccountsPdcCreateInput({
    required this.projectId,
    required this.invoiceId,
    required this.expectedVersion,
    required this.chequeNumber,
    required this.chequeDate,
    required this.amount,
    required this.bankName,
  });

  final String projectId;
  final String invoiceId;
  final int expectedVersion;
  final String chequeNumber;
  final YorksAccountsDate chequeDate;
  final YorksAccountsDecimal amount;
  final String? bankName;

  bool get isValid =>
      projectId.trim().isNotEmpty &&
      invoiceId.trim().isNotEmpty &&
      expectedVersion > 0 &&
      chequeNumber.trim().isNotEmpty &&
      amount.isPositive &&
      amount.fractionDigits <= 2 &&
      (bankName == null || bankName!.trim().isNotEmpty);

  Map<String, Object?> idempotencyPayload() => {
    'project_id': projectId.trim(),
    'invoice_id': invoiceId.trim(),
    'expected_invoice_version': expectedVersion,
    'cheque_number': chequeNumber.trim(),
    'cheque_date': chequeDate.postgresText,
    'amount': amount.postgresText,
    'bank_name': _nullableTrimmed(bankName),
  };
}

enum YorksAccountsPdcStatus {
  expected('expected'),
  received('received'),
  deposited('deposited'),
  cleared('cleared'),
  replaced('replaced'),
  returned('returned'),
  bounced('bounced'),
  cancelled('cancelled');

  const YorksAccountsPdcStatus(this.wireValue);
  final String wireValue;
}

final class YorksAccountsPdcTransitionInput {
  const YorksAccountsPdcTransitionInput({
    required this.projectId,
    required this.pdcId,
    required this.expectedVersion,
    required this.targetStatus,
    required this.actionDate,
    required this.clearanceReference,
    required this.reason,
  });

  final String projectId;
  final String pdcId;
  final int expectedVersion;
  final YorksAccountsPdcStatus targetStatus;
  final YorksAccountsDate actionDate;
  final String? clearanceReference;
  final String? reason;

  bool get isValid {
    if (projectId.trim().isEmpty ||
        pdcId.trim().isEmpty ||
        expectedVersion < 1 ||
        targetStatus == YorksAccountsPdcStatus.replaced) {
      return false;
    }
    if (targetStatus == YorksAccountsPdcStatus.cleared &&
        _nullableTrimmed(clearanceReference) == null) {
      return false;
    }
    if ((targetStatus == YorksAccountsPdcStatus.returned ||
            targetStatus == YorksAccountsPdcStatus.bounced ||
            targetStatus == YorksAccountsPdcStatus.cancelled) &&
        _nullableTrimmed(reason) == null) {
      return false;
    }
    return (clearanceReference == null ||
            clearanceReference!.trim().isNotEmpty) &&
        (reason == null || reason!.trim().isNotEmpty);
  }

  Map<String, Object?> idempotencyPayload() => {
    'project_id': projectId.trim(),
    'pdc_id': pdcId.trim(),
    'expected_version': expectedVersion,
    'new_status': targetStatus.wireValue,
    'action_date': actionDate.postgresText,
    'clearance_payment_reference': _nullableTrimmed(clearanceReference),
    'reason': _nullableTrimmed(reason),
  };
}

final class YorksAccountsPdcReplacementInput {
  const YorksAccountsPdcReplacementInput({
    required this.projectId,
    required this.originalPdcId,
    required this.expectedVersion,
    required this.chequeNumber,
    required this.chequeDate,
    required this.amount,
    required this.bankName,
    required this.reason,
  });

  final String projectId;
  final String originalPdcId;
  final int expectedVersion;
  final String chequeNumber;
  final YorksAccountsDate chequeDate;
  final YorksAccountsDecimal amount;
  final String? bankName;
  final String reason;

  bool get isValid =>
      projectId.trim().isNotEmpty &&
      originalPdcId.trim().isNotEmpty &&
      expectedVersion > 0 &&
      chequeNumber.trim().isNotEmpty &&
      amount.isPositive &&
      amount.fractionDigits <= 2 &&
      (bankName == null || bankName!.trim().isNotEmpty) &&
      reason.trim().isNotEmpty;

  Map<String, Object?> idempotencyPayload() => {
    'project_id': projectId.trim(),
    'pdc_id': originalPdcId.trim(),
    'expected_version': expectedVersion,
    'new_cheque_number': chequeNumber.trim(),
    'new_cheque_date': chequeDate.postgresText,
    'new_amount': amount.postgresText,
    'new_bank_name': _nullableTrimmed(bankName),
    'reason': reason.trim(),
  };
}

String? _nullableTrimmed(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

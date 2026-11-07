import 'accounts_decimal.dart';
import 'accounts_receivables_inputs.dart';

enum YorksAccountsClaimStatus {
  draft('draft'),
  readyForAccounts('ready_for_accounts'),
  invoiced('invoiced'),
  cancelled('cancelled');

  const YorksAccountsClaimStatus(this.wireValue);
  final String wireValue;

  static YorksAccountsClaimStatus? tryParse(Object? raw) =>
      _parseEnum(raw, values, (value) => value.wireValue);
}

enum YorksAccountsInvoiceStatus {
  draft('draft'),
  submitted('submitted'),
  underCertification('under_certification'),
  partiallyCertified('partially_certified'),
  certified('certified'),
  partiallyPaid('partially_paid'),
  paid('paid'),
  returned('returned'),
  cancelled('cancelled');

  const YorksAccountsInvoiceStatus(this.wireValue);
  final String wireValue;

  static YorksAccountsInvoiceStatus? tryParse(Object? raw) =>
      _parseEnum(raw, values, (value) => value.wireValue);
}

enum YorksAccountsPaymentEntryKind {
  receipt('receipt'),
  reversal('reversal');

  const YorksAccountsPaymentEntryKind(this.wireValue);
  final String wireValue;

  static YorksAccountsPaymentEntryKind? tryParse(Object? raw) =>
      _parseEnum(raw, values, (value) => value.wireValue);
}

enum YorksAccountsDueState {
  onTrack('on_track'),
  dueSoon('due_soon'),
  dueToday('due_today'),
  overdue('overdue');

  const YorksAccountsDueState(this.wireValue);
  final String wireValue;

  static YorksAccountsDueState? tryParse(Object? raw) =>
      _parseEnum(raw, values, (value) => value.wireValue);
}

extension YorksAccountsPdcStatusParser on YorksAccountsPdcStatus {
  static YorksAccountsPdcStatus? tryParse(Object? raw) => _parseEnum(
    raw,
    YorksAccountsPdcStatus.values,
    (value) => value.wireValue,
  );
}

/// Server-issued command authority for the T03 receivables lifecycle.
///
/// These are the exact R39 capability keys. The Flutter role enum is never
/// consulted to infer a missing permission.
final class YorksAccountsReceivablesCapabilities {
  const YorksAccountsReceivablesCapabilities({
    required this.canViewValues,
    required this.prepareClientClaim,
    required this.manageClientInvoices,
    required this.recordClientCertification,
    required this.recordClientPayment,
    required this.managePdc,
  });

  final bool canViewValues;
  final bool prepareClientClaim;
  final bool manageClientInvoices;
  final bool recordClientCertification;
  final bool recordClientPayment;
  final bool managePdc;

  factory YorksAccountsReceivablesCapabilities.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksAccountsReceivablesCapabilities(
    canViewValues: _requiredBool(json, 'view_project_commercial_values'),
    prepareClientClaim: _requiredBool(json, 'prepare_client_claim'),
    manageClientInvoices: _requiredBool(json, 'manage_client_invoices'),
    recordClientCertification: _requiredBool(
      json,
      'record_client_certification',
    ),
    recordClientPayment: _requiredBool(json, 'record_client_payment'),
    managePdc: _requiredBool(json, 'manage_pdc'),
  );

  static const none = YorksAccountsReceivablesCapabilities(
    canViewValues: false,
    prepareClientClaim: false,
    manageClientInvoices: false,
    recordClientCertification: false,
    recordClientPayment: false,
    managePdc: false,
  );
}

/// Exact server-issued T03 command availability. Unknown or missing authority
/// is never inferred from a role on the client.
final class YorksAccountsReceivablesCommands {
  const YorksAccountsReceivablesCommands({
    required this.createClaimDraft,
    required this.editClaimDraft,
    required this.submitClaimToAccounts,
    required this.cancelClaim,
    required this.createInvoiceDraft,
    required this.submitInvoice,
    required this.returnInvoice,
    required this.cancelInvoice,
    required this.recordCertification,
    required this.recordPayment,
    required this.reversePayment,
    required this.createPdc,
    required this.transitionPdc,
    required this.replacePdc,
    this.editPdc = false,
    this.correctPayment = false,
    this.correctCertification = false,
  });

  final bool createClaimDraft;
  final bool editClaimDraft;
  final bool submitClaimToAccounts;
  final bool cancelClaim;
  final bool createInvoiceDraft;
  final bool submitInvoice;
  final bool returnInvoice;
  final bool cancelInvoice;
  final bool recordCertification;
  final bool recordPayment;
  final bool reversePayment;
  final bool createPdc;
  final bool transitionPdc;
  final bool replacePdc;
  final bool editPdc;
  final bool correctPayment;
  final bool correctCertification;

  factory YorksAccountsReceivablesCommands.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksAccountsReceivablesCommands(
    createClaimDraft: _requiredBool(json, 'create_claim_draft'),
    editClaimDraft: _requiredBool(json, 'edit_claim_draft'),
    submitClaimToAccounts: _requiredBool(json, 'submit_claim_to_accounts'),
    cancelClaim: _requiredBool(json, 'cancel_claim'),
    createInvoiceDraft: _requiredBool(json, 'create_invoice_draft'),
    submitInvoice: _requiredBool(json, 'submit_invoice'),
    returnInvoice: _requiredBool(json, 'return_invoice'),
    cancelInvoice: _requiredBool(json, 'cancel_invoice'),
    recordCertification: _requiredBool(json, 'record_certification'),
    recordPayment: _requiredBool(json, 'record_payment'),
    reversePayment: _requiredBool(json, 'reverse_payment'),
    createPdc: _requiredBool(json, 'create_pdc'),
    transitionPdc: _requiredBool(json, 'transition_pdc'),
    replacePdc: _requiredBool(json, 'replace_pdc'),
    editPdc: json['edit_pdc'] == true,
    correctPayment: json['correct_payment'] == true,
    correctCertification: json['correct_certification'] == true,
  );
}

final class YorksAccountsCompositeCursor {
  const YorksAccountsCompositeCursor({
    required this.timestamp,
    required this.id,
  });

  final DateTime timestamp;
  final String id;

  factory YorksAccountsCompositeCursor.fromRpcJson(
    Map<String, dynamic> json, {
    required String timestampKey,
  }) => YorksAccountsCompositeCursor(
    timestamp: _requiredDateTime(json, timestampKey),
    id: _requiredString(json, 'id'),
  );
}

final class YorksAccountsClientClaimLine {
  YorksAccountsClientClaimLine({
    required this.claimLineId,
    required this.progressEntryId,
    required this.baselineRevisionId,
    required this.progressRevisionId,
    required this.progressRecordVersion,
    required this.projectScopeId,
    required this.buildingName,
    required this.stageKey,
    required this.stageLabel,
    required this.stageValueSnapshot,
    required this.confirmedPercentSnapshot,
    required this.eligibleAmountSnapshot,
    required this.previouslyClaimedAmountSnapshot,
    required this.claimedAmount,
    required this.evidenceReference,
  });

  final String claimLineId;
  final String progressEntryId;
  final String baselineRevisionId;
  final String progressRevisionId;
  final int progressRecordVersion;
  final String projectScopeId;
  final String? buildingName;
  final String stageKey;
  final String? stageLabel;
  final YorksAccountsDecimal? stageValueSnapshot;
  final YorksAccountsDecimal? confirmedPercentSnapshot;
  final YorksAccountsDecimal? eligibleAmountSnapshot;
  final YorksAccountsDecimal? previouslyClaimedAmountSnapshot;
  final YorksAccountsDecimal? claimedAmount;
  final String? evidenceReference;

  factory YorksAccountsClientClaimLine.fromRpcJson(
    Map<String, dynamic> json, {
    required bool canViewValues,
  }) => YorksAccountsClientClaimLine(
    claimLineId: _requiredStringAny(json, const [
      'line_id',
      'claim_line_id',
      'id',
    ]),
    progressEntryId: _requiredString(json, 'progress_entry_id'),
    baselineRevisionId: _requiredString(json, 'baseline_revision_id'),
    progressRevisionId: _requiredString(json, 'progress_revision_id'),
    progressRecordVersion: _requiredInt(json, 'progress_record_version'),
    projectScopeId: _requiredStringAny(json, const [
      'project_scope_id',
      'building_scope_id',
    ]),
    buildingName: _optionalString(json['building_name']),
    stageKey: _requiredString(json, 'stage_key'),
    stageLabel: _optionalString(json['stage_label']),
    stageValueSnapshot: _protectedMoney(
      json,
      'stage_value_snapshot',
      canViewValues,
    ),
    confirmedPercentSnapshot: _protectedPercent(
      json,
      'confirmed_percent_snapshot',
      canViewValues,
    ),
    eligibleAmountSnapshot: _protectedMoney(
      json,
      'eligible_amount_snapshot',
      canViewValues,
    ),
    previouslyClaimedAmountSnapshot: _protectedMoney(
      json,
      'previously_claimed_amount_snapshot',
      canViewValues,
    ),
    claimedAmount: _protectedMoney(json, 'claimed_amount', canViewValues),
    evidenceReference: _optionalString(json['evidence_reference']),
  );

  YorksAccountsClientClaimLine withoutProtectedValues() =>
      YorksAccountsClientClaimLine(
        claimLineId: claimLineId,
        progressEntryId: progressEntryId,
        baselineRevisionId: baselineRevisionId,
        progressRevisionId: progressRevisionId,
        progressRecordVersion: progressRecordVersion,
        projectScopeId: projectScopeId,
        buildingName: buildingName,
        stageKey: stageKey,
        stageLabel: stageLabel,
        stageValueSnapshot: null,
        confirmedPercentSnapshot: null,
        eligibleAmountSnapshot: null,
        previouslyClaimedAmountSnapshot: null,
        claimedAmount: null,
        evidenceReference: evidenceReference,
      );
}

final class YorksAccountsClientClaim {
  YorksAccountsClientClaim({
    required this.claimId,
    required this.projectId,
    required this.baselineRevisionId,
    required this.claimReference,
    required this.periodStart,
    required this.periodEnd,
    required this.status,
    required this.adminExceptionReason,
    required this.notes,
    required this.isStale,
    required this.staleReason,
    required this.recordVersion,
    required this.createdByAuthUserId,
    required this.createdByExactRole,
    required this.readyForAccountsAt,
    required this.cancelledAt,
    required this.cancellationReason,
    required this.claimedExVat,
    required List<YorksAccountsClientClaimLine> lines,
    required this.createdAt,
    required this.updatedAt,
  }) : lines = List.unmodifiable(lines);

  final String claimId;
  final String projectId;
  final String baselineRevisionId;
  final String claimReference;
  final YorksAccountsDate periodStart;
  final YorksAccountsDate periodEnd;
  final YorksAccountsClaimStatus status;
  final String? adminExceptionReason;
  final String? notes;
  final bool isStale;
  final String? staleReason;
  final int recordVersion;
  final String? createdByAuthUserId;
  final String? createdByExactRole;
  final DateTime? readyForAccountsAt;
  final DateTime? cancelledAt;
  final String? cancellationReason;
  final YorksAccountsDecimal? claimedExVat;
  final List<YorksAccountsClientClaimLine> lines;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory YorksAccountsClientClaim.fromRpcJson(
    Map<String, dynamic> json, {
    required bool canViewValues,
  }) {
    final status = YorksAccountsClaimStatus.tryParse(json['status']);
    if (status == null) {
      throw FormatException('Invalid claim status.', json['status']);
    }
    final baselineRevisionId = _requiredString(json, 'baseline_revision_id');
    return YorksAccountsClientClaim(
      claimId: _requiredStringAny(json, const ['claim_id', 'id']),
      projectId: _requiredString(json, 'project_id'),
      baselineRevisionId: baselineRevisionId,
      claimReference: _requiredString(json, 'claim_reference'),
      periodStart: _requiredDate(json, 'claim_period_start'),
      periodEnd: _requiredDate(json, 'claim_period_end'),
      status: status,
      adminExceptionReason: _optionalString(json['admin_exception_reason']),
      notes: _optionalString(json['notes']),
      isStale: _requiredBool(json, 'is_stale'),
      staleReason: _optionalString(json['stale_reason']),
      recordVersion: _requiredInt(json, 'record_version'),
      createdByAuthUserId: _optionalString(json['created_by_auth_user_id']),
      createdByExactRole: _optionalString(json['created_by_exact_role']),
      readyForAccountsAt: _optionalDateTime(json['ready_for_accounts_at']),
      cancelledAt: _optionalDateTime(json['cancelled_at']),
      cancellationReason: _optionalString(json['cancellation_reason']),
      claimedExVat: _protectedMoney(json, 'claimed_ex_vat', canViewValues),
      lines: _mapList(json['lines'])
          .map(
            (line) => YorksAccountsClientClaimLine.fromRpcJson({
              ...line,
              'baseline_revision_id': baselineRevisionId,
            }, canViewValues: canViewValues),
          )
          .toList(growable: false),
      createdAt: _requiredDateTime(json, 'created_at'),
      updatedAt: _requiredDateTime(json, 'updated_at'),
    );
  }

  YorksAccountsClientClaim withoutProtectedValues() => YorksAccountsClientClaim(
    claimId: claimId,
    projectId: projectId,
    baselineRevisionId: baselineRevisionId,
    claimReference: claimReference,
    periodStart: periodStart,
    periodEnd: periodEnd,
    status: status,
    adminExceptionReason: adminExceptionReason,
    notes: notes,
    isStale: isStale,
    staleReason: staleReason,
    recordVersion: recordVersion,
    createdByAuthUserId: createdByAuthUserId,
    createdByExactRole: createdByExactRole,
    readyForAccountsAt: readyForAccountsAt,
    cancelledAt: cancelledAt,
    cancellationReason: cancellationReason,
    claimedExVat: null,
    lines: lines.map((line) => line.withoutProtectedValues()).toList(),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

final class YorksAccountsClientInvoice {
  const YorksAccountsClientInvoice({
    required this.invoiceId,
    required this.projectId,
    required this.claimId,
    required this.invoiceReference,
    required this.status,
    required this.claimedExVat,
    required this.vatRatePercentSnapshot,
    required this.vatAmountSnapshot,
    required this.totalInclVatSnapshot,
    required this.paymentTermsDaysSnapshot,
    required this.reminderLeadDaysSnapshot,
    required this.submissionDate,
    required this.dueDate,
    required this.dueState,
    required this.adminExceptionReason,
    required this.notes,
    required this.recordVersion,
    required this.certifiedExVat,
    required this.certifiedInclVat,
    required this.paidAmount,
    required this.stillDue,
    required this.pdcExposure,
    required this.retentionSnapshot,
    required this.createdByAuthUserId,
    required this.createdByExactRole,
    required this.createdAt,
    required this.updatedAt,
  });

  final String invoiceId;
  final String projectId;
  final String claimId;
  final String invoiceReference;
  final YorksAccountsInvoiceStatus status;
  final YorksAccountsDecimal? claimedExVat;
  final YorksAccountsDecimal? vatRatePercentSnapshot;
  final YorksAccountsDecimal? vatAmountSnapshot;
  final YorksAccountsDecimal? totalInclVatSnapshot;
  final int? paymentTermsDaysSnapshot;
  final int? reminderLeadDaysSnapshot;
  final YorksAccountsDate? submissionDate;
  final YorksAccountsDate? dueDate;
  final YorksAccountsDueState? dueState;
  final String? adminExceptionReason;
  final String? notes;
  final int recordVersion;
  final YorksAccountsDecimal? certifiedExVat;
  final YorksAccountsDecimal? certifiedInclVat;
  final YorksAccountsDecimal? paidAmount;
  final YorksAccountsDecimal? stillDue;
  final YorksAccountsDecimal? pdcExposure;

  /// Retention held back from this invoice's payable (frozen at issue). This is
  /// a commercial figure: never a reduction the actor cannot see. Null when the
  /// actor lacks commercial access; `0` when no retention policy applies.
  final YorksAccountsDecimal? retentionSnapshot;
  final String? createdByAuthUserId;
  final String? createdByExactRole;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory YorksAccountsClientInvoice.fromRpcJson(
    Map<String, dynamic> json, {
    required bool canViewValues,
  }) {
    final status = YorksAccountsInvoiceStatus.tryParse(json['status']);
    if (status == null) {
      throw FormatException('Invalid invoice status.', json['status']);
    }
    final dueStateRaw = json['due_state'];
    final dueState = dueStateRaw == null
        ? null
        : YorksAccountsDueState.tryParse(dueStateRaw);
    if (dueStateRaw != null && dueState == null) {
      throw FormatException('Invalid invoice due state.', dueStateRaw);
    }
    final invoice = YorksAccountsClientInvoice(
      invoiceId: _requiredStringAny(json, const ['invoice_id', 'id']),
      projectId: _requiredString(json, 'project_id'),
      claimId: _requiredString(json, 'claim_id'),
      invoiceReference: _requiredString(json, 'invoice_reference'),
      status: status,
      claimedExVat: _protectedMoney(json, 'claimed_ex_vat', canViewValues),
      vatRatePercentSnapshot: _protectedPercent(
        json,
        'vat_rate_percent_snapshot',
        canViewValues,
      ),
      vatAmountSnapshot: _protectedMoney(
        json,
        'vat_amount_snapshot',
        canViewValues,
      ),
      totalInclVatSnapshot: _protectedMoney(
        json,
        'total_incl_vat_snapshot',
        canViewValues,
      ),
      paymentTermsDaysSnapshot: _protectedInt(
        json,
        'payment_terms_days_snapshot',
        canViewValues,
      ),
      reminderLeadDaysSnapshot: _protectedInt(
        json,
        'reminder_lead_days_snapshot',
        canViewValues,
      ),
      submissionDate: _optionalDate(json['submission_date']),
      dueDate: _optionalDate(json['due_date']),
      dueState: dueState,
      adminExceptionReason: _optionalString(json['admin_exception_reason']),
      notes: _optionalString(json['notes']),
      recordVersion: _requiredInt(json, 'record_version'),
      certifiedExVat: _protectedMoney(json, 'certified_ex_vat', canViewValues),
      certifiedInclVat: _protectedMoney(
        json,
        'certified_incl_vat',
        canViewValues,
      ),
      paidAmount: _protectedMoney(json, 'paid_amount', canViewValues),
      stillDue: _protectedMoney(json, 'still_due', canViewValues),
      pdcExposure: _protectedMoney(json, 'pdc_exposure', canViewValues),
      retentionSnapshot: _protectedMoney(
        json,
        'retention_snapshot',
        canViewValues,
      ),
      createdByAuthUserId: _optionalString(json['created_by_auth_user_id']),
      createdByExactRole: _optionalString(json['created_by_exact_role']),
      createdAt: _requiredDateTime(json, 'created_at'),
      updatedAt: _requiredDateTime(json, 'updated_at'),
    );
    if (invoice.submissionDate == null && invoice.dueDate != null) {
      throw const FormatException(
        'An invoice due date cannot exist without submission.',
      );
    }
    return invoice;
  }

  YorksAccountsClientInvoice withoutProtectedValues() =>
      YorksAccountsClientInvoice(
        invoiceId: invoiceId,
        projectId: projectId,
        claimId: claimId,
        invoiceReference: invoiceReference,
        status: status,
        claimedExVat: null,
        vatRatePercentSnapshot: null,
        vatAmountSnapshot: null,
        totalInclVatSnapshot: null,
        paymentTermsDaysSnapshot: null,
        reminderLeadDaysSnapshot: null,
        submissionDate: submissionDate,
        dueDate: dueDate,
        dueState: dueState,
        adminExceptionReason: adminExceptionReason,
        notes: notes,
        recordVersion: recordVersion,
        certifiedExVat: null,
        certifiedInclVat: null,
        paidAmount: null,
        stillDue: null,
        pdcExposure: null,
        retentionSnapshot: null,
        createdByAuthUserId: createdByAuthUserId,
        createdByExactRole: createdByExactRole,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

final class YorksAccountsClientClaimSummary {
  const YorksAccountsClientClaimSummary({
    required this.claimId,
    required this.claimReference,
    required this.periodStart,
    required this.periodEnd,
    required this.status,
    required this.claimedExVat,
    required this.isStale,
    required this.recordVersion,
    required this.createdByAuthUserId,
    required this.createdByExactRole,
    required this.createdAt,
    required this.updatedAt,
  });

  final String claimId;
  final String claimReference;
  final YorksAccountsDate periodStart;
  final YorksAccountsDate periodEnd;
  final YorksAccountsClaimStatus status;
  final YorksAccountsDecimal claimedExVat;
  final bool isStale;
  final int recordVersion;
  final String? createdByAuthUserId;
  final String? createdByExactRole;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory YorksAccountsClientClaimSummary.fromRpcJson(
    Map<String, dynamic> json,
  ) {
    final status = YorksAccountsClaimStatus.tryParse(json['status']);
    if (status == null) {
      throw FormatException('Invalid claim status.', json['status']);
    }
    return YorksAccountsClientClaimSummary(
      claimId: _requiredString(json, 'claim_id'),
      claimReference: _requiredString(json, 'claim_reference'),
      periodStart: _requiredDate(json, 'claim_period_start'),
      periodEnd: _requiredDate(json, 'claim_period_end'),
      status: status,
      claimedExVat: _requiredMoney(json, 'claimed_ex_vat'),
      isStale: _requiredBool(json, 'is_stale'),
      recordVersion: _requiredInt(json, 'record_version'),
      createdByAuthUserId: _optionalString(json['created_by_auth_user_id']),
      createdByExactRole: _optionalString(json['created_by_exact_role']),
      createdAt: _requiredDateTime(json, 'created_at'),
      updatedAt: _requiredDateTime(json, 'updated_at'),
    );
  }
}

final class YorksAccountsClientInvoiceSummary {
  const YorksAccountsClientInvoiceSummary({
    required this.invoiceId,
    required this.claimId,
    required this.invoiceReference,
    required this.status,
    required this.claimedExVat,
    required this.certifiedExVat,
    required this.totalInclVat,
    required this.amountPaidTillDate,
    required this.stillDue,
    required this.pdcExposure,
    required this.submissionDate,
    required this.dueDate,
    required this.dueState,
    required this.recordVersion,
    required this.updatedAt,
    this.certificationDate,
    this.lastReceiptDate,
    this.replacesReference,
    this.revisionInProgress = false,
  });

  final String invoiceId;
  final String claimId;
  final String invoiceReference;
  final YorksAccountsInvoiceStatus status;
  final YorksAccountsDecimal claimedExVat;
  final YorksAccountsDecimal certifiedExVat;
  final YorksAccountsDecimal totalInclVat;
  final YorksAccountsDecimal amountPaidTillDate;
  final YorksAccountsDecimal stillDue;
  final YorksAccountsDecimal pdcExposure;
  final YorksAccountsDate? submissionDate;
  final YorksAccountsDate? dueDate;
  final YorksAccountsDueState? dueState;
  final int recordVersion;
  final DateTime updatedAt;

  /// The latest certification and the last receipt still standing, for the
  /// tracker's Certified column and "days late / on time".
  final YorksAccountsDate? certificationDate;
  final YorksAccountsDate? lastReceiptDate;

  /// The invoice this revision replaces, if it is one.
  final String? replacesReference;

  /// A revision of this invoice is being prepared.
  final bool revisionInProgress;

  factory YorksAccountsClientInvoiceSummary.fromRpcJson(
    Map<String, dynamic> json,
  ) {
    final status = YorksAccountsInvoiceStatus.tryParse(json['status']);
    if (status == null) {
      throw FormatException('Invalid invoice status.', json['status']);
    }
    final dueStateRaw = json['due_state'];
    final dueState = dueStateRaw == null
        ? null
        : YorksAccountsDueState.tryParse(dueStateRaw);
    if (dueStateRaw != null && dueState == null) {
      throw FormatException('Invalid invoice due state.', dueStateRaw);
    }
    return YorksAccountsClientInvoiceSummary(
      invoiceId: _requiredString(json, 'invoice_id'),
      claimId: _requiredString(json, 'claim_id'),
      invoiceReference: _requiredString(json, 'invoice_reference'),
      status: status,
      claimedExVat: _requiredMoney(json, 'claimed_ex_vat'),
      certifiedExVat: _requiredMoney(json, 'certified_ex_vat'),
      totalInclVat: _requiredMoney(json, 'total_incl_vat'),
      amountPaidTillDate: _requiredMoney(json, 'amount_paid_till_date'),
      stillDue: _requiredMoney(json, 'still_due'),
      pdcExposure: _requiredMoney(json, 'pdc_exposure'),
      submissionDate: _optionalDate(json['submission_date']),
      dueDate: _optionalDate(json['due_date']),
      dueState: dueState,
      recordVersion: _requiredInt(json, 'record_version'),
      updatedAt: _requiredDateTime(json, 'updated_at'),
      certificationDate: _optionalDate(json['certification_date']),
      lastReceiptDate: _optionalDate(json['last_receipt_date']),
      replacesReference: json['replaces_reference'] as String?,
      revisionInProgress: json['revision_in_progress'] == true,
    );
  }
}

final class YorksAccountsClaimsProjection {
  YorksAccountsClaimsProjection({
    required this.schemaVersion,
    required this.projectId,
    required List<YorksAccountsClientClaimSummary> claims,
    required this.nextCursor,
    required this.capabilities,
    required this.commands,
  }) : claims = List.unmodifiable(claims);

  final int schemaVersion;
  final String projectId;
  final List<YorksAccountsClientClaimSummary> claims;
  final YorksAccountsCompositeCursor? nextCursor;
  final YorksAccountsReceivablesCapabilities capabilities;
  final YorksAccountsReceivablesCommands commands;

  factory YorksAccountsClaimsProjection.fromRpcJson(Map<String, dynamic> json) {
    final capabilities = _commercialCapabilities(json);
    return YorksAccountsClaimsProjection(
      schemaVersion: _schemaVersion(json),
      projectId: _requiredString(json, 'project_id'),
      claims: _mapList(json['claims'])
          .map(YorksAccountsClientClaimSummary.fromRpcJson)
          .toList(growable: false),
      nextCursor: _optionalCursor(
        json['next_cursor'],
        timestampKey: 'before_updated_at',
      ),
      capabilities: capabilities,
      commands: _commands(json),
    );
  }
}

final class YorksAccountsClaimDetailProjection {
  const YorksAccountsClaimDetailProjection({
    required this.schemaVersion,
    required this.projectId,
    required this.claim,
    required this.capabilities,
    required this.commands,
  });

  final int schemaVersion;
  final String projectId;
  final YorksAccountsClientClaim claim;
  final YorksAccountsReceivablesCapabilities capabilities;
  final YorksAccountsReceivablesCommands commands;

  factory YorksAccountsClaimDetailProjection.fromRpcJson(
    Map<String, dynamic> json,
  ) {
    final capabilities = _commercialCapabilities(json);
    return YorksAccountsClaimDetailProjection(
      schemaVersion: _schemaVersion(json),
      projectId: _requiredString(json, 'project_id'),
      claim: YorksAccountsClientClaim.fromRpcJson(
        _requiredMap(json, 'claim'),
        canViewValues: capabilities.canViewValues,
      ),
      capabilities: capabilities,
      commands: _commands(json),
    );
  }
}

final class YorksAccountsInvoicesProjection {
  YorksAccountsInvoicesProjection({
    required this.schemaVersion,
    required this.projectId,
    required List<YorksAccountsClientInvoiceSummary> invoices,
    required this.nextCursor,
    required this.capabilities,
    required this.commands,
  }) : invoices = List.unmodifiable(invoices);

  final int schemaVersion;
  final String projectId;
  final List<YorksAccountsClientInvoiceSummary> invoices;
  final YorksAccountsCompositeCursor? nextCursor;
  final YorksAccountsReceivablesCapabilities capabilities;
  final YorksAccountsReceivablesCommands commands;

  factory YorksAccountsInvoicesProjection.fromRpcJson(
    Map<String, dynamic> json,
  ) {
    final capabilities = _commercialCapabilities(json);
    return YorksAccountsInvoicesProjection(
      schemaVersion: _schemaVersion(json),
      projectId: _requiredString(json, 'project_id'),
      invoices: _mapList(json['invoices'])
          .map(YorksAccountsClientInvoiceSummary.fromRpcJson)
          .toList(growable: false),
      nextCursor: _optionalCursor(
        json['next_cursor'],
        timestampKey: 'before_updated_at',
      ),
      capabilities: capabilities,
      commands: _commands(json),
    );
  }
}

final class YorksAccountsInvoiceDetailProjection {
  YorksAccountsInvoiceDetailProjection({
    required this.schemaVersion,
    required this.projectId,
    required this.invoice,
    required this.claim,
    required List<YorksAccountsClientCertification> certifications,
    required List<YorksAccountsClientPayment> payments,
    required List<YorksAccountsClientPdc> pdcs,
    required this.dueState,
    required this.capabilities,
    required this.commands,
  }) : certifications = List.unmodifiable(certifications),
       payments = List.unmodifiable(payments),
       pdcs = List.unmodifiable(pdcs);

  final int schemaVersion;
  final String projectId;
  final YorksAccountsClientInvoice invoice;
  final YorksAccountsClientClaim claim;
  final List<YorksAccountsClientCertification> certifications;
  final List<YorksAccountsClientPayment> payments;
  final List<YorksAccountsClientPdc> pdcs;
  final YorksAccountsDueState? dueState;
  final YorksAccountsReceivablesCapabilities capabilities;
  final YorksAccountsReceivablesCommands commands;

  factory YorksAccountsInvoiceDetailProjection.fromRpcJson(
    Map<String, dynamic> json,
  ) {
    final projectId = _requiredString(json, 'project_id');
    final capabilities = _commercialCapabilities(json);
    final invoiceJson = _requiredMap(json, 'invoice');
    final invoiceId = _requiredString(invoiceJson, 'invoice_id');
    final dueStateRaw = json['due_state'];
    final dueState = dueStateRaw == null
        ? null
        : YorksAccountsDueState.tryParse(dueStateRaw);
    if (dueStateRaw != null && dueState == null) {
      throw FormatException('Invalid invoice due state.', dueStateRaw);
    }
    final invoiceWithDue = Map<String, dynamic>.from(invoiceJson);
    if (dueStateRaw != null) invoiceWithDue['due_state'] = dueStateRaw;
    Map<String, dynamic> contextualChild(Map<String, dynamic> child) => {
      ...child,
      'project_id': projectId,
      'invoice_id': invoiceId,
    };
    return YorksAccountsInvoiceDetailProjection(
      schemaVersion: _schemaVersion(json),
      projectId: projectId,
      invoice: YorksAccountsClientInvoice.fromRpcJson(
        invoiceWithDue,
        canViewValues: capabilities.canViewValues,
      ),
      claim: YorksAccountsClientClaim.fromRpcJson(
        _requiredMap(json, 'claim'),
        canViewValues: capabilities.canViewValues,
      ),
      certifications: _mapList(json['certifications'])
          .map(contextualChild)
          .map(
            (item) => YorksAccountsClientCertification.fromRpcJson(
              item,
              canViewValues: capabilities.canViewValues,
            ),
          )
          .toList(growable: false),
      payments: _mapList(json['payments'])
          .map(contextualChild)
          .map(
            (item) => YorksAccountsClientPayment.fromRpcJson(
              item,
              canViewValues: capabilities.canViewValues,
            ),
          )
          .toList(growable: false),
      pdcs: _mapList(json['pdcs'])
          .map(contextualChild)
          .map(
            (item) => YorksAccountsClientPdc.fromRpcJson(
              item,
              canViewValues: capabilities.canViewValues,
            ),
          )
          .toList(growable: false),
      dueState: dueState,
      capabilities: capabilities,
      commands: _commands(json),
    );
  }
}

final class YorksAccountsClientCertification {
  const YorksAccountsClientCertification({
    required this.certificationId,
    required this.projectId,
    required this.invoiceId,
    required this.revisionNumber,
    required this.certificationReference,
    required this.certificationDate,
    required this.certifiedExVat,
    required this.certifiedVat,
    required this.certifiedInclVat,
    required this.differenceReason,
    required this.actorAuthUserId,
    required this.actorExactRole,
    required this.createdAt,
  });

  final String certificationId;
  final String projectId;
  final String invoiceId;
  final int revisionNumber;
  final String certificationReference;
  final YorksAccountsDate certificationDate;
  final YorksAccountsDecimal? certifiedExVat;
  final YorksAccountsDecimal? certifiedVat;
  final YorksAccountsDecimal? certifiedInclVat;
  final String? differenceReason;
  final String? actorAuthUserId;
  final String? actorExactRole;
  final DateTime createdAt;

  factory YorksAccountsClientCertification.fromRpcJson(
    Map<String, dynamic> json, {
    required bool canViewValues,
  }) => YorksAccountsClientCertification(
    certificationId: _requiredStringAny(json, const ['certification_id', 'id']),
    projectId: _requiredString(json, 'project_id'),
    invoiceId: _requiredString(json, 'invoice_id'),
    revisionNumber: _requiredInt(json, 'revision_number'),
    certificationReference: _requiredString(json, 'certification_reference'),
    certificationDate: _requiredDate(json, 'certification_date'),
    certifiedExVat: _protectedMoney(json, 'certified_ex_vat', canViewValues),
    certifiedVat: _protectedMoney(json, 'certified_vat', canViewValues),
    certifiedInclVat: _protectedMoney(
      json,
      'certified_incl_vat',
      canViewValues,
    ),
    differenceReason: _optionalString(json['difference_reason']),
    actorAuthUserId: _optionalString(json['actor_auth_user_id']),
    actorExactRole: _optionalString(json['actor_exact_role']),
    createdAt: _requiredDateTime(json, 'created_at'),
  );
}

final class YorksAccountsClientPayment {
  const YorksAccountsClientPayment({
    required this.paymentId,
    required this.projectId,
    required this.invoiceId,
    required this.entryKind,
    required this.originalPaymentId,
    required this.pdcId,
    required this.paymentDate,
    required this.paymentMethod,
    required this.paymentReference,
    required this.amount,
    required this.reason,
    required this.actorAuthUserId,
    required this.actorExactRole,
    required this.createdAt,
  });

  final String paymentId;
  final String projectId;
  final String invoiceId;
  final YorksAccountsPaymentEntryKind entryKind;
  final String? originalPaymentId;
  final String? pdcId;
  final YorksAccountsDate paymentDate;
  final String paymentMethod;
  final String paymentReference;
  final YorksAccountsDecimal? amount;
  final String? reason;
  final String? actorAuthUserId;
  final String? actorExactRole;
  final DateTime createdAt;

  factory YorksAccountsClientPayment.fromRpcJson(
    Map<String, dynamic> json, {
    required bool canViewValues,
  }) {
    final entryKind = YorksAccountsPaymentEntryKind.tryParse(
      json['entry_kind'],
    );
    if (entryKind == null) {
      throw FormatException('Invalid payment entry kind.', json['entry_kind']);
    }
    final payment = YorksAccountsClientPayment(
      paymentId: _requiredStringAny(json, const ['payment_id', 'id']),
      projectId: _requiredString(json, 'project_id'),
      invoiceId: _requiredString(json, 'invoice_id'),
      entryKind: entryKind,
      originalPaymentId: _optionalString(json['original_payment_id']),
      pdcId: _optionalString(json['pdc_id']),
      paymentDate: _requiredDate(json, 'payment_date'),
      paymentMethod: _requiredString(json, 'payment_method'),
      paymentReference: _requiredString(json, 'payment_reference'),
      amount: _protectedMoney(json, 'amount', canViewValues),
      reason: _optionalString(json['reason']),
      actorAuthUserId: _optionalString(json['actor_auth_user_id']),
      actorExactRole: _optionalString(json['actor_exact_role']),
      createdAt: _requiredDateTime(json, 'created_at'),
    );
    if (entryKind == YorksAccountsPaymentEntryKind.reversal &&
        (payment.originalPaymentId == null || payment.reason == null)) {
      throw const FormatException(
        'A payment reversal requires its original and reason.',
      );
    }
    return payment;
  }
}

final class YorksAccountsClientPdc {
  const YorksAccountsClientPdc({
    required this.pdcId,
    required this.projectId,
    required this.invoiceId,
    required this.chequeNumber,
    required this.chequeDate,
    required this.amount,
    required this.bankName,
    required this.receivedDate,
    required this.status,
    required this.replacesPdcId,
    required this.replacedByPdcId,
    required this.actionRequired,
    required this.lastActionReason,
    required this.recordVersion,
    required this.createdAt,
    required this.updatedAt,
  });

  final String pdcId;
  final String projectId;
  final String invoiceId;
  final String chequeNumber;
  final YorksAccountsDate chequeDate;
  final YorksAccountsDecimal? amount;
  final String? bankName;
  final YorksAccountsDate? receivedDate;
  final YorksAccountsPdcStatus status;
  final String? replacesPdcId;
  final String? replacedByPdcId;
  final bool actionRequired;
  final String? lastActionReason;
  final int recordVersion;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory YorksAccountsClientPdc.fromRpcJson(
    Map<String, dynamic> json, {
    required bool canViewValues,
  }) {
    final status = YorksAccountsPdcStatusParser.tryParse(json['status']);
    if (status == null) {
      throw FormatException('Invalid PDC status.', json['status']);
    }
    final pdc = YorksAccountsClientPdc(
      pdcId: _requiredStringAny(json, const ['pdc_id', 'id']),
      projectId: _requiredString(json, 'project_id'),
      invoiceId: _requiredString(json, 'invoice_id'),
      chequeNumber: _requiredString(json, 'cheque_number'),
      chequeDate: _requiredDate(json, 'cheque_date'),
      amount: _protectedMoney(json, 'amount', canViewValues),
      bankName: _optionalString(json['bank_name']),
      receivedDate: _optionalDate(json['received_date']),
      status: status,
      replacesPdcId: _optionalString(json['replaces_pdc_id']),
      replacedByPdcId: _optionalString(json['replaced_by_pdc_id']),
      actionRequired: _requiredBool(json, 'action_required'),
      lastActionReason: _optionalString(json['last_action_reason']),
      recordVersion: _requiredInt(json, 'record_version'),
      createdAt: _requiredDateTime(json, 'created_at'),
      updatedAt: _requiredDateTime(json, 'updated_at'),
    );
    if ((status == YorksAccountsPdcStatus.returned ||
            status == YorksAccountsPdcStatus.bounced) &&
        (!pdc.actionRequired || pdc.lastActionReason == null)) {
      throw const FormatException(
        'Returned or bounced PDC requires visible action context.',
      );
    }
    return pdc;
  }
}

final class YorksAccountsClientPdcEvent {
  const YorksAccountsClientPdcEvent({
    required this.eventId,
    required this.projectId,
    required this.invoiceId,
    required this.pdcId,
    required this.sequenceNumber,
    required this.fromStatus,
    required this.toStatus,
    required this.actionDate,
    required this.reason,
    required this.linkedPaymentId,
    required this.actorAuthUserId,
    required this.actorExactRole,
    required this.occurredAt,
  });

  final String eventId;
  final String projectId;
  final String invoiceId;
  final String pdcId;
  final int sequenceNumber;
  final YorksAccountsPdcStatus? fromStatus;
  final YorksAccountsPdcStatus toStatus;
  final YorksAccountsDate actionDate;
  final String? reason;
  final String? linkedPaymentId;
  final String? actorAuthUserId;
  final String? actorExactRole;
  final DateTime occurredAt;

  factory YorksAccountsClientPdcEvent.fromRpcJson(Map<String, dynamic> json) {
    final fromRaw = json['from_status'];
    final fromStatus = fromRaw == null
        ? null
        : YorksAccountsPdcStatusParser.tryParse(fromRaw);
    final toStatus = YorksAccountsPdcStatusParser.tryParse(json['to_status']);
    if ((fromRaw != null && fromStatus == null) || toStatus == null) {
      throw const FormatException('Invalid PDC event status.');
    }
    return YorksAccountsClientPdcEvent(
      eventId: _requiredStringAny(json, const ['event_id', 'id']),
      projectId: _requiredString(json, 'project_id'),
      invoiceId: _requiredString(json, 'invoice_id'),
      pdcId: _requiredString(json, 'pdc_id'),
      sequenceNumber: _requiredInt(json, 'sequence_number'),
      fromStatus: fromStatus,
      toStatus: toStatus,
      actionDate: _requiredDate(json, 'action_date'),
      reason: _optionalString(json['reason']),
      linkedPaymentId: _optionalString(json['linked_payment_id']),
      actorAuthUserId: _optionalString(json['actor_auth_user_id']),
      actorExactRole: _optionalString(json['actor_exact_role']),
      occurredAt: _requiredDateTime(json, 'occurred_at'),
    );
  }
}

enum YorksAccountsReceivablesLedgerEntryType {
  payment('payment'),
  pdcEvent('pdc_event');

  const YorksAccountsReceivablesLedgerEntryType(this.wireValue);
  final String wireValue;

  static YorksAccountsReceivablesLedgerEntryType? tryParse(Object? raw) =>
      _parseEnum(raw, values, (value) => value.wireValue);
}

final class YorksAccountsLedgerPayment {
  const YorksAccountsLedgerPayment({
    required this.paymentId,
    required this.entryKind,
    required this.paymentDate,
    required this.paymentMethod,
    required this.paymentReference,
    required this.amount,
    required this.originalPaymentId,
    required this.pdcId,
    required this.actorAuthUserId,
    required this.actorExactRole,
  });

  final String paymentId;
  final YorksAccountsPaymentEntryKind entryKind;
  final YorksAccountsDate paymentDate;
  final String paymentMethod;
  final String paymentReference;
  final YorksAccountsDecimal amount;
  final String? originalPaymentId;
  final String? pdcId;
  final String? actorAuthUserId;
  final String? actorExactRole;

  factory YorksAccountsLedgerPayment.fromRpcJson(Map<String, dynamic> json) {
    final entryKind = YorksAccountsPaymentEntryKind.tryParse(
      json['entry_kind'],
    );
    if (entryKind == null) {
      throw FormatException('Invalid payment entry kind.', json['entry_kind']);
    }
    final payment = YorksAccountsLedgerPayment(
      paymentId: _requiredString(json, 'payment_id'),
      entryKind: entryKind,
      paymentDate: _requiredDate(json, 'payment_date'),
      paymentMethod: _requiredString(json, 'payment_method'),
      paymentReference: _requiredString(json, 'payment_reference'),
      amount: _requiredMoney(json, 'amount'),
      originalPaymentId: _optionalString(json['original_payment_id']),
      pdcId: _optionalString(json['pdc_id']),
      actorAuthUserId: _optionalString(json['actor_auth_user_id']),
      actorExactRole: _optionalString(json['actor_exact_role']),
    );
    if (entryKind == YorksAccountsPaymentEntryKind.reversal &&
        payment.originalPaymentId == null) {
      throw const FormatException(
        'A reversal ledger entry requires its original payment.',
      );
    }
    return payment;
  }
}

final class YorksAccountsReceivablesLedgerEntry {
  const YorksAccountsReceivablesLedgerEntry({
    required this.ledgerEntryId,
    required this.occurredAt,
    required this.entryType,
    required this.invoiceId,
    required this.payment,
    required this.pdcEvent,
  });

  final String ledgerEntryId;
  final DateTime occurredAt;
  final YorksAccountsReceivablesLedgerEntryType entryType;
  final String invoiceId;
  final YorksAccountsLedgerPayment? payment;
  final YorksAccountsClientPdcEvent? pdcEvent;

  factory YorksAccountsReceivablesLedgerEntry.fromRpcJson(
    Map<String, dynamic> json, {
    required String projectId,
  }) {
    final ledgerEntryId = _requiredString(json, 'ledger_entry_id');
    final occurredAt = _requiredDateTime(json, 'occurred_at');
    final invoiceId = _requiredString(json, 'invoice_id');
    final entryType = YorksAccountsReceivablesLedgerEntryType.tryParse(
      json['entry_type'],
    );
    if (entryType == null) {
      throw FormatException('Invalid ledger entry type.', json['entry_type']);
    }
    final data = _requiredMap(json, 'data');
    return switch (entryType) {
      YorksAccountsReceivablesLedgerEntryType.payment =>
        YorksAccountsReceivablesLedgerEntry(
          ledgerEntryId: ledgerEntryId,
          occurredAt: occurredAt,
          entryType: entryType,
          invoiceId: invoiceId,
          payment: YorksAccountsLedgerPayment.fromRpcJson(data),
          pdcEvent: null,
        ),
      YorksAccountsReceivablesLedgerEntryType.pdcEvent =>
        YorksAccountsReceivablesLedgerEntry(
          ledgerEntryId: ledgerEntryId,
          occurredAt: occurredAt,
          entryType: entryType,
          invoiceId: invoiceId,
          payment: null,
          pdcEvent: YorksAccountsClientPdcEvent.fromRpcJson({
            ...data,
            'event_id': ledgerEntryId,
            'project_id': projectId,
            'invoice_id': invoiceId,
            'occurred_at': occurredAt.toIso8601String(),
          }),
        ),
    };
  }
}

final class YorksAccountsReceivablesLedgerProjection {
  YorksAccountsReceivablesLedgerProjection({
    required this.schemaVersion,
    required this.projectId,
    required this.invoiceId,
    required List<YorksAccountsReceivablesLedgerEntry> entries,
    required this.nextCursor,
    required this.capabilities,
    required this.commands,
  }) : entries = List.unmodifiable(entries);

  final int schemaVersion;
  final String projectId;
  final String? invoiceId;
  final List<YorksAccountsReceivablesLedgerEntry> entries;
  final YorksAccountsCompositeCursor? nextCursor;
  final YorksAccountsReceivablesCapabilities capabilities;
  final YorksAccountsReceivablesCommands commands;

  factory YorksAccountsReceivablesLedgerProjection.fromRpcJson(
    Map<String, dynamic> json,
  ) {
    final projectId = _requiredString(json, 'project_id');
    final capabilities = _commercialCapabilities(json);
    return YorksAccountsReceivablesLedgerProjection(
      schemaVersion: _schemaVersion(json),
      projectId: projectId,
      invoiceId: _optionalString(json['invoice_id']),
      entries: _mapList(json['entries'])
          .map(
            (item) => YorksAccountsReceivablesLedgerEntry.fromRpcJson(
              item,
              projectId: projectId,
            ),
          )
          .toList(growable: false),
      nextCursor: _optionalCursor(
        json['next_cursor'],
        timestampKey: 'before_occurred_at',
      ),
      capabilities: capabilities,
      commands: _commands(json),
    );
  }
}

final class YorksAccountsReceivablesCommandResult {
  const YorksAccountsReceivablesCommandResult({
    required this.replayed,
    required this.projectId,
    required this.entityId,
    required this.recordVersion,
    required this.status,
    required this.claimId,
    required this.invoiceId,
    required this.certificationId,
    required this.paymentId,
    required this.pdcId,
    required this.updatedAt,
  });

  final bool replayed;
  final String projectId;
  final String entityId;
  final int? recordVersion;
  final String status;
  final String? claimId;
  final String? invoiceId;
  final String? certificationId;
  final String? paymentId;
  final String? pdcId;
  final DateTime? updatedAt;

  factory YorksAccountsReceivablesCommandResult.fromRpcJson(
    Map<String, dynamic> json,
  ) {
    _schemaVersion(json);
    final result = YorksAccountsReceivablesCommandResult(
      replayed: _requiredBool(json, 'replayed'),
      projectId: _requiredString(json, 'project_id'),
      entityId: _requiredString(json, 'entity_id'),
      recordVersion: _optionalInt(
        json['record_version'] ?? json['invoice_record_version'],
      ),
      status: _requiredString(json, 'status'),
      claimId: _optionalString(json['claim_id']),
      invoiceId: _optionalString(json['invoice_id']),
      certificationId: _optionalString(json['certification_id']),
      paymentId: _optionalString(json['payment_id']),
      pdcId: _optionalString(json['pdc_id']),
      updatedAt: _optionalDateTime(json['updated_at']),
    );
    final identifiers = [
      result.claimId,
      result.invoiceId,
      result.certificationId,
      result.paymentId,
      result.pdcId,
    ].whereType<String>();
    if (!identifiers.contains(result.entityId)) {
      throw const FormatException(
        'A receivables command entity must match its domain identifier.',
      );
    }
    return result;
  }
}

T? _parseEnum<T>(Object? raw, Iterable<T> values, String Function(T) wire) {
  final normalized = raw?.toString().trim().toLowerCase();
  for (final value in values) {
    if (wire(value) == normalized) return value;
  }
  return null;
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw FormatException('$key must be a boolean.', value);
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _optionalString(json[key]);
  if (value != null) return value;
  throw FormatException('$key must be a non-empty string.', json[key]);
}

String _requiredStringAny(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = _optionalString(json[key]);
    if (value != null) return value;
  }
  throw FormatException('${keys.join('/')} must be a non-empty string.');
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is! String) throw FormatException('Expected a string.', value);
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw FormatException('$key must be an integer.', value);
}

int? _optionalInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  throw FormatException('Expected an integer.', value);
}

YorksAccountsDate _requiredDate(Map<String, dynamic> json, String key) {
  final raw = _requiredString(json, key);
  return YorksAccountsDate.parse(raw);
}

YorksAccountsDate? _optionalDate(Object? value) {
  final raw = _optionalString(value);
  return raw == null ? null : YorksAccountsDate.parse(raw);
}

DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
  final value = _optionalDateTime(json[key]);
  if (value != null) return value;
  throw FormatException('$key must be a timestamp.', json[key]);
}

DateTime? _optionalDateTime(Object? raw) {
  final value = _optionalString(raw);
  if (value == null) return null;
  if (!RegExp(r'(?:Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
    throw FormatException('Timestamp must include a UTC offset.', raw);
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('Invalid timestamp.', raw);
  return parsed.toUtc();
}

YorksAccountsDecimal? _protectedDecimal(
  Map<String, dynamic> json,
  String key,
  bool canViewValues,
) {
  if (!canViewValues) {
    if (json.containsKey(key)) {
      throw FormatException('$key must be omitted for this response shape.');
    }
    return null;
  }
  if (!json.containsKey(key) || json[key] == null) return null;
  return YorksAccountsDecimal.fromRpcValue(json[key], key: key);
}

YorksAccountsDecimal? _protectedMoney(
  Map<String, dynamic> json,
  String key,
  bool canViewValues,
) {
  final value = _protectedDecimal(json, key, canViewValues);
  if (value != null && value.fractionDigits > 2) {
    throw FormatException('$key exceeds the fixed money scale.', json[key]);
  }
  return value;
}

YorksAccountsDecimal _requiredMoney(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) {
    throw FormatException('$key is required.');
  }
  final value = YorksAccountsDecimal.fromRpcValue(json[key], key: key);
  if (value.fractionDigits > 2) {
    throw FormatException('$key exceeds the fixed money scale.', json[key]);
  }
  return value;
}

YorksAccountsDecimal? _protectedPercent(
  Map<String, dynamic> json,
  String key,
  bool canViewValues,
) {
  final value = _protectedDecimal(json, key, canViewValues);
  if (value != null && value.fractionDigits > 4) {
    throw FormatException(
      '$key exceeds the fixed percentage scale.',
      json[key],
    );
  }
  return value;
}

int? _protectedInt(Map<String, dynamic> json, String key, bool canViewValues) {
  if (!canViewValues) {
    if (json.containsKey(key)) {
      throw FormatException('$key must be omitted for this response shape.');
    }
    return null;
  }
  return _optionalInt(json[key]);
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value == null) return const [];
  if (value is! List) throw FormatException('Expected a list.', value);
  return value
      .map((item) {
        if (item is Map) return Map<String, dynamic>.from(item);
        throw FormatException('Expected a list of objects.', item);
      })
      .toList(growable: false);
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is Map) return Map<String, dynamic>.from(value);
  throw FormatException('$key must be an object.', value);
}

int _schemaVersion(Map<String, dynamic> json) {
  final version = _requiredInt(json, 'schema_version');
  if (version != 3) {
    throw FormatException('Unsupported Accounts receivables schema.', version);
  }
  return version;
}

YorksAccountsCompositeCursor? _optionalCursor(
  Object? raw, {
  required String timestampKey,
}) {
  if (raw == null) return null;
  if (raw is! Map) throw FormatException('next_cursor must be an object.', raw);
  return YorksAccountsCompositeCursor.fromRpcJson(
    Map<String, dynamic>.from(raw),
    timestampKey: timestampKey,
  );
}

YorksAccountsReceivablesCapabilities _commercialCapabilities(
  Map<String, dynamic> json,
) {
  final capabilities = YorksAccountsReceivablesCapabilities.fromRpcJson(
    _requiredMap(json, 'capabilities'),
  );
  if (!capabilities.canViewValues) {
    throw const FormatException(
      'T03 projection must not be returned without commercial-value access.',
    );
  }
  return capabilities;
}

YorksAccountsReceivablesCommands _commands(Map<String, dynamic> json) =>
    YorksAccountsReceivablesCommands.fromRpcJson(
      _requiredMap(json, 'commands'),
    );

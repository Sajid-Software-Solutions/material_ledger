import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/yorks_v1_domain_error.dart';
import '../../../shared/models/yorks_v1_feature_flags.dart';
import '../../../shared/sync/connectivity_service.dart';
import '../domain/accounts_receivables_inputs.dart';
import '../domain/accounts_receivables_models.dart';
import 'accounts_repository.dart';

abstract interface class YorksAccountsReceivablesRepository {
  Future<YorksAccountsClaimsProjection> listClaims(
    String projectId, {
    YorksAccountsClaimStatus? status,
    YorksAccountsCompositeCursor? before,
    int limit = 50,
  });

  Future<YorksAccountsClaimDetailProjection> getClaim(
    String projectId,
    String claimId,
  );

  Future<YorksAccountsInvoicesProjection> listInvoices(
    String projectId, {
    YorksAccountsInvoiceStatus? status,
    YorksAccountsDueState? dueState,
    YorksAccountsCompositeCursor? before,
    int limit = 50,
  });

  Future<YorksAccountsInvoiceDetailProjection> getInvoice(
    String projectId,
    String invoiceId,
  );

  Future<YorksAccountsReceivablesLedgerProjection> listReceiptsAndPdc(
    String projectId, {
    String? invoiceId,
    YorksAccountsCompositeCursor? before,
    int limit = 50,
  });

  Future<YorksAccountsReceivablesCommandResult> createClaimDraft(
    YorksAccountsClaimDraftInput input, {
    required String idempotencyKey,
  });

  Future<YorksAccountsReceivablesCommandResult> updateClaimDraft(
    YorksAccountsClaimDraftInput input, {
    required String idempotencyKey,
  });

  Future<YorksAccountsReceivablesCommandResult> deleteClaimDraft(
    YorksAccountsEntityActionInput input, {
    required String idempotencyKey,
  });

  Future<YorksAccountsReceivablesCommandResult> submitClaimToAccounts(
    YorksAccountsEntityActionInput input, {
    required String idempotencyKey,
  });

  Future<YorksAccountsReceivablesCommandResult> cancelClaim(
    YorksAccountsEntityActionInput input, {
    required String idempotencyKey,
  });

  Future<YorksAccountsReceivablesCommandResult> createInvoiceDraft(
    YorksAccountsInvoiceDraftInput input, {
    required String idempotencyKey,
  });

  Future<YorksAccountsReceivablesCommandResult> updateInvoiceDraft(
    YorksAccountsInvoiceDraftInput input, {
    required String idempotencyKey,
  });

  Future<YorksAccountsReceivablesCommandResult> submitInvoice(
    YorksAccountsInvoiceSubmitInput input, {
    required String idempotencyKey,
  });

  Future<YorksAccountsReceivablesCommandResult> markInvoiceUnderCertification(
    YorksAccountsEntityActionInput input, {
    required String idempotencyKey,
  });

  Future<YorksAccountsReceivablesCommandResult> returnInvoice(
    YorksAccountsEntityActionInput input, {
    required String idempotencyKey,
  });

  Future<YorksAccountsReceivablesCommandResult> cancelInvoice(
    YorksAccountsEntityActionInput input, {
    required String idempotencyKey,
  });

  /// Restores a cancelled invoice (and its claim) when nothing since makes it
  /// wrong; the server names the reason otherwise.
  Future<YorksAccountsReceivablesCommandResult> restoreInvoice(
    YorksAccountsEntityActionInput input, {
    required String idempotencyKey,
  });

  /// Restores a deleted claim that never had an invoice.
  Future<YorksAccountsReceivablesCommandResult> restoreClaim(
    YorksAccountsEntityActionInput input, {
    required String idempotencyKey,
  });

  Future<YorksAccountsReceivablesCommandResult> recordCertification(
    YorksAccountsCertificationInput input, {
    required String idempotencyKey,
  });

  Future<YorksAccountsReceivablesCommandResult> recordPayment(
    YorksAccountsPaymentInput input, {
    required String idempotencyKey,
  });

  Future<YorksAccountsReceivablesCommandResult> reversePayment(
    YorksAccountsPaymentReversalInput input, {
    required String idempotencyKey,
  });

  Future<YorksAccountsReceivablesCommandResult> correctPayment(
    YorksAccountsPaymentCorrectionInput input, {
    required String idempotencyKey,
  });

  Future<YorksAccountsReceivablesCommandResult> correctCertification(
    YorksAccountsCertificationCorrectionInput input, {
    required String idempotencyKey,
  });

  Future<YorksAccountsReceivablesCommandResult> updatePdc(
    YorksAccountsPdcEditInput input, {
    required String idempotencyKey,
  });

  Future<YorksAccountsReceivablesCommandResult> createPdc(
    YorksAccountsPdcCreateInput input, {
    required String idempotencyKey,
  });

  Future<YorksAccountsReceivablesCommandResult> transitionPdc(
    YorksAccountsPdcTransitionInput input, {
    required String idempotencyKey,
  });

  Future<YorksAccountsReceivablesCommandResult> replacePdc(
    YorksAccountsPdcReplacementInput input, {
    required String idempotencyKey,
  });
}

enum _ReceivablesEntityKind { claim, invoice, certification, payment, pdc }

final class YorksSupabaseAccountsReceivablesRepository
    implements YorksAccountsReceivablesRepository {
  const YorksSupabaseAccountsReceivablesRepository({
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
  Future<YorksAccountsClaimsProjection> listClaims(
    String projectId, {
    YorksAccountsClaimStatus? status,
    YorksAccountsCompositeCursor? before,
    int limit = 50,
  }) => _projection(
    projectId: projectId,
    limit: limit,
    functionName: 'v1_list_client_claims',
    parameters: {
      'p_status': status?.wireValue,
      'p_before_updated_at': before?.timestamp.toIso8601String(),
      'p_before_id': before?.id,
      'p_limit': limit,
    },
    parse: YorksAccountsClaimsProjection.fromRpcJson,
    projectOf: (projection) => projection.projectId,
  );

  @override
  Future<YorksAccountsClaimDetailProjection> getClaim(
    String projectId,
    String claimId,
  ) async {
    final normalizedProjectId = projectId.trim();
    final normalizedClaimId = claimId.trim();
    if (normalizedProjectId.isEmpty || normalizedClaimId.isEmpty) {
      return _invalidInput();
    }
    final response = await _invoke('v1_get_client_claim', {
      'p_project_id': normalizedProjectId,
      'p_claim_id': normalizedClaimId,
    });
    return _decode(() {
      final projection = YorksAccountsClaimDetailProjection.fromRpcJson(
        response,
      );
      _requireId(projection.projectId, normalizedProjectId);
      _requireId(projection.claim.projectId, normalizedProjectId);
      _requireId(projection.claim.claimId, normalizedClaimId);
      for (final line in projection.claim.lines) {
        _requireId(
          line.baselineRevisionId,
          projection.claim.baselineRevisionId,
        );
      }
      return projection;
    });
  }

  @override
  Future<YorksAccountsInvoicesProjection> listInvoices(
    String projectId, {
    YorksAccountsInvoiceStatus? status,
    YorksAccountsDueState? dueState,
    YorksAccountsCompositeCursor? before,
    int limit = 50,
  }) => _projection(
    projectId: projectId,
    limit: limit,
    functionName: 'v1_list_client_invoices',
    parameters: {
      'p_status': status?.wireValue,
      'p_due_state': dueState?.wireValue,
      'p_before_updated_at': before?.timestamp.toIso8601String(),
      'p_before_id': before?.id,
      'p_limit': limit,
    },
    parse: YorksAccountsInvoicesProjection.fromRpcJson,
    projectOf: (projection) => projection.projectId,
  );

  @override
  Future<YorksAccountsInvoiceDetailProjection> getInvoice(
    String projectId,
    String invoiceId,
  ) async {
    final normalizedProjectId = projectId.trim();
    final normalizedInvoiceId = invoiceId.trim();
    if (normalizedProjectId.isEmpty || normalizedInvoiceId.isEmpty) {
      return _invalidInput();
    }
    final response = await _invoke('v1_get_client_invoice', {
      'p_project_id': normalizedProjectId,
      'p_invoice_id': normalizedInvoiceId,
    });
    return _decode(() {
      final projection = YorksAccountsInvoiceDetailProjection.fromRpcJson(
        response,
      );
      _requireId(projection.projectId, normalizedProjectId);
      _requireId(projection.invoice.projectId, normalizedProjectId);
      _requireId(projection.invoice.invoiceId, normalizedInvoiceId);
      _requireId(projection.claim.projectId, normalizedProjectId);
      _requireId(projection.claim.claimId, projection.invoice.claimId);
      for (final certification in projection.certifications) {
        _requireId(certification.projectId, normalizedProjectId);
        _requireId(certification.invoiceId, normalizedInvoiceId);
      }
      for (final payment in projection.payments) {
        _requireId(payment.projectId, normalizedProjectId);
        _requireId(payment.invoiceId, normalizedInvoiceId);
      }
      for (final pdc in projection.pdcs) {
        _requireId(pdc.projectId, normalizedProjectId);
        _requireId(pdc.invoiceId, normalizedInvoiceId);
      }
      return projection;
    });
  }

  @override
  Future<YorksAccountsReceivablesLedgerProjection> listReceiptsAndPdc(
    String projectId, {
    String? invoiceId,
    YorksAccountsCompositeCursor? before,
    int limit = 50,
  }) async {
    final normalizedProjectId = projectId.trim();
    final normalizedInvoiceId = _nullableTrimmed(invoiceId);
    if (normalizedProjectId.isEmpty ||
        (invoiceId != null && normalizedInvoiceId == null) ||
        !_validPage(limit, before)) {
      return _invalidInput();
    }
    final response = await _invoke('v1_list_client_receipts_pdc', {
      'p_project_id': normalizedProjectId,
      'p_invoice_id': normalizedInvoiceId,
      'p_before_occurred_at': before?.timestamp.toIso8601String(),
      'p_before_id': before?.id,
      'p_limit': limit,
    });
    return _decode(() {
      final projection = YorksAccountsReceivablesLedgerProjection.fromRpcJson(
        response,
      );
      _requireId(projection.projectId, normalizedProjectId);
      if (normalizedInvoiceId != null) {
        _requireId(projection.invoiceId ?? '', normalizedInvoiceId);
      }
      for (final entry in projection.entries) {
        if (normalizedInvoiceId != null) {
          _requireId(entry.invoiceId, normalizedInvoiceId);
        }
      }
      return projection;
    });
  }

  @override
  Future<YorksAccountsReceivablesCommandResult> createClaimDraft(
    YorksAccountsClaimDraftInput input, {
    required String idempotencyKey,
  }) {
    if (input.isUpdate || !input.isValid) return _invalidInput();
    return _command(
      'v1_create_client_claim_draft',
      {
        'p_project_id': input.projectId.trim(),
        'p_claim_reference': input.claimReference.trim(),
        'p_claim_period_start': input.periodStart.postgresText,
        'p_claim_period_end': input.periodEnd.postgresText,
        'p_lines': input.lines
            .map((line) => line.toRpcJson())
            .toList(growable: false),
        'p_notes': input.notes.trim(),
        'p_idempotency_key': idempotencyKey.trim(),
        'p_admin_exception_reason': _nullableTrimmed(
          input.adminExceptionReason,
        ),
      },
      input.projectId,
      idempotencyKey,
      kind: _ReceivablesEntityKind.claim,
    );
  }

  @override
  Future<YorksAccountsReceivablesCommandResult> updateClaimDraft(
    YorksAccountsClaimDraftInput input, {
    required String idempotencyKey,
  }) {
    if (!input.isUpdate || !input.isValid) return _invalidInput();
    return _command(
      'v1_update_client_claim_draft',
      {
        'p_project_id': input.projectId.trim(),
        'p_claim_id': input.claimId!.trim(),
        'p_expected_version': input.expectedVersion,
        'p_claim_reference': input.claimReference.trim(),
        'p_claim_period_start': input.periodStart.postgresText,
        'p_claim_period_end': input.periodEnd.postgresText,
        'p_lines': input.lines
            .map((line) => line.toRpcJson())
            .toList(growable: false),
        'p_notes': input.notes.trim(),
        'p_idempotency_key': idempotencyKey.trim(),
        'p_admin_exception_reason': _nullableTrimmed(
          input.adminExceptionReason,
        ),
      },
      input.projectId,
      idempotencyKey,
      expectedEntityId: input.claimId,
      kind: _ReceivablesEntityKind.claim,
    );
  }

  @override
  Future<YorksAccountsReceivablesCommandResult> deleteClaimDraft(
    YorksAccountsEntityActionInput input, {
    required String idempotencyKey,
  }) => _claimAction('v1_delete_client_claim_draft', input, idempotencyKey);

  @override
  Future<YorksAccountsReceivablesCommandResult> submitClaimToAccounts(
    YorksAccountsEntityActionInput input, {
    required String idempotencyKey,
  }) =>
      _claimAction('v1_submit_client_claim_to_accounts', input, idempotencyKey);

  @override
  Future<YorksAccountsReceivablesCommandResult> cancelClaim(
    YorksAccountsEntityActionInput input, {
    required String idempotencyKey,
  }) => _claimAction('v1_cancel_client_claim', input, idempotencyKey);

  @override
  Future<YorksAccountsReceivablesCommandResult> createInvoiceDraft(
    YorksAccountsInvoiceDraftInput input, {
    required String idempotencyKey,
  }) {
    if (input.isUpdate || !input.isValid) return _invalidInput();
    return _command(
      'v1_create_client_invoice_draft',
      {
        'p_project_id': input.projectId.trim(),
        'p_claim_id': input.claimId!.trim(),
        'p_invoice_reference': input.invoiceReference.trim(),
        'p_notes': input.notes.trim(),
        'p_idempotency_key': idempotencyKey.trim(),
      },
      input.projectId,
      idempotencyKey,
      kind: _ReceivablesEntityKind.invoice,
    );
  }

  @override
  Future<YorksAccountsReceivablesCommandResult> updateInvoiceDraft(
    YorksAccountsInvoiceDraftInput input, {
    required String idempotencyKey,
  }) {
    if (!input.isUpdate || !input.isValid) return _invalidInput();
    return _command(
      'v1_update_client_invoice_draft',
      {
        'p_project_id': input.projectId.trim(),
        'p_invoice_id': input.invoiceId!.trim(),
        'p_expected_version': input.expectedVersion,
        'p_invoice_reference': input.invoiceReference.trim(),
        'p_notes': input.notes.trim(),
        'p_idempotency_key': idempotencyKey.trim(),
      },
      input.projectId,
      idempotencyKey,
      expectedEntityId: input.invoiceId,
      kind: _ReceivablesEntityKind.invoice,
    );
  }

  @override
  Future<YorksAccountsReceivablesCommandResult> submitInvoice(
    YorksAccountsInvoiceSubmitInput input, {
    required String idempotencyKey,
  }) {
    if (!input.isValid) return _invalidInput();
    return _command(
      'v1_submit_client_invoice',
      {
        'p_project_id': input.projectId.trim(),
        'p_invoice_id': input.invoiceId.trim(),
        'p_expected_version': input.expectedVersion,
        'p_submission_date': input.submissionDate.postgresText,
        'p_admin_exception_reason': _nullableTrimmed(
          input.adminExceptionReason,
        ),
        'p_idempotency_key': idempotencyKey.trim(),
      },
      input.projectId,
      idempotencyKey,
      expectedEntityId: input.invoiceId,
      kind: _ReceivablesEntityKind.invoice,
    );
  }

  @override
  Future<YorksAccountsReceivablesCommandResult> markInvoiceUnderCertification(
    YorksAccountsEntityActionInput input, {
    required String idempotencyKey,
  }) => _invoiceAction(
    'v1_mark_client_invoice_under_certification',
    input,
    idempotencyKey,
  );

  @override
  Future<YorksAccountsReceivablesCommandResult> returnInvoice(
    YorksAccountsEntityActionInput input, {
    required String idempotencyKey,
  }) => _invoiceAction('v1_return_client_invoice', input, idempotencyKey);

  @override
  Future<YorksAccountsReceivablesCommandResult> cancelInvoice(
    YorksAccountsEntityActionInput input, {
    required String idempotencyKey,
  }) => _invoiceAction('v1_cancel_client_invoice', input, idempotencyKey);

  @override
  Future<YorksAccountsReceivablesCommandResult> restoreInvoice(
    YorksAccountsEntityActionInput input, {
    required String idempotencyKey,
  }) => _invoiceAction('v1_restore_client_invoice', input, idempotencyKey);

  @override
  Future<YorksAccountsReceivablesCommandResult> restoreClaim(
    YorksAccountsEntityActionInput input, {
    required String idempotencyKey,
  }) => _claimAction('v1_restore_client_claim', input, idempotencyKey);

  @override
  Future<YorksAccountsReceivablesCommandResult> recordCertification(
    YorksAccountsCertificationInput input, {
    required String idempotencyKey,
  }) {
    if (!input.isStructurallyValid) return _invalidInput();
    return _command(
      'v1_record_client_certification',
      {
        'p_project_id': input.projectId.trim(),
        'p_invoice_id': input.invoiceId.trim(),
        'p_expected_version': input.expectedVersion,
        'p_certification_reference': input.certificationReference.trim(),
        'p_certification_date': input.certificationDate.postgresText,
        'p_certified_ex_vat': input.certifiedExVat.postgresText,
        'p_difference_reason': _nullableTrimmed(input.differenceReason),
        'p_idempotency_key': idempotencyKey.trim(),
      },
      input.projectId,
      idempotencyKey,
      kind: _ReceivablesEntityKind.certification,
    );
  }

  @override
  Future<YorksAccountsReceivablesCommandResult> recordPayment(
    YorksAccountsPaymentInput input, {
    required String idempotencyKey,
  }) {
    if (!input.isValid) return _invalidInput();
    return _command(
      'v1_record_client_payment',
      {
        'p_project_id': input.projectId.trim(),
        'p_invoice_id': input.invoiceId.trim(),
        'p_expected_version': input.expectedVersion,
        'p_payment_date': input.paymentDate.postgresText,
        'p_payment_method': input.paymentMethod.trim(),
        'p_payment_reference': input.paymentReference.trim(),
        'p_amount': input.amount.postgresText,
        'p_reason': _nullableTrimmed(input.reason),
        'p_idempotency_key': idempotencyKey.trim(),
      },
      input.projectId,
      idempotencyKey,
      kind: _ReceivablesEntityKind.payment,
    );
  }

  @override
  Future<YorksAccountsReceivablesCommandResult> reversePayment(
    YorksAccountsPaymentReversalInput input, {
    required String idempotencyKey,
  }) {
    if (!input.isValid) return _invalidInput();
    return _command(
      'v1_reverse_client_payment',
      {
        'p_project_id': input.projectId.trim(),
        'p_invoice_id': input.invoiceId.trim(),
        'p_expected_version': input.expectedVersion,
        'p_original_payment_id': input.originalPaymentId.trim(),
        'p_reversal_date': input.reversalDate.postgresText,
        'p_reversal_reference': input.reversalReference.trim(),
        'p_reason': input.reason.trim(),
        'p_idempotency_key': idempotencyKey.trim(),
        if (input.chequeOutcome != null)
          'p_cheque_outcome': input.chequeOutcome!.wireValue,
      },
      input.projectId,
      idempotencyKey,
      kind: _ReceivablesEntityKind.payment,
    );
  }

  @override
  Future<YorksAccountsReceivablesCommandResult> correctPayment(
    YorksAccountsPaymentCorrectionInput input, {
    required String idempotencyKey,
  }) {
    if (!input.isValid) return _invalidInput();
    return _command(
      'v1_correct_client_payment',
      {
        'p_project_id': input.projectId.trim(),
        'p_invoice_id': input.invoiceId.trim(),
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
      idempotencyKey,
      kind: _ReceivablesEntityKind.payment,
    );
  }

  @override
  Future<YorksAccountsReceivablesCommandResult> correctCertification(
    YorksAccountsCertificationCorrectionInput input, {
    required String idempotencyKey,
  }) {
    if (!input.isValid) return _invalidInput();
    return _command(
      'v1_correct_client_certification',
      {
        'p_project_id': input.projectId.trim(),
        'p_invoice_id': input.invoiceId.trim(),
        'p_expected_version': input.expectedVersion,
        'p_certification_reference': input.certificationReference.trim(),
        'p_certification_date': input.certificationDate.postgresText,
        'p_certified_ex_vat': input.certifiedExVat.postgresText,
        'p_reason': input.reason.trim(),
        'p_idempotency_key': idempotencyKey.trim(),
      },
      input.projectId,
      idempotencyKey,
      kind: _ReceivablesEntityKind.certification,
    );
  }

  @override
  Future<YorksAccountsReceivablesCommandResult> updatePdc(
    YorksAccountsPdcEditInput input, {
    required String idempotencyKey,
  }) {
    if (!input.isValid) return _invalidInput();
    return _command(
      'v1_update_client_pdc',
      {
        'p_project_id': input.projectId.trim(),
        'p_pdc_id': input.pdcId.trim(),
        'p_expected_version': input.expectedVersion,
        'p_cheque_number': input.chequeNumber.trim(),
        'p_cheque_date': input.chequeDate.postgresText,
        'p_amount': input.amount.postgresText,
        'p_bank_name': _nullableTrimmed(input.bankName),
        'p_reason': input.reason.trim(),
        'p_idempotency_key': idempotencyKey.trim(),
      },
      input.projectId,
      idempotencyKey,
      kind: _ReceivablesEntityKind.pdc,
    );
  }

  @override
  Future<YorksAccountsReceivablesCommandResult> createPdc(
    YorksAccountsPdcCreateInput input, {
    required String idempotencyKey,
  }) {
    if (!input.isValid) return _invalidInput();
    return _command(
      'v1_create_client_pdc',
      {
        'p_project_id': input.projectId.trim(),
        'p_invoice_id': input.invoiceId.trim(),
        'p_expected_invoice_version': input.expectedVersion,
        'p_cheque_number': input.chequeNumber.trim(),
        'p_cheque_date': input.chequeDate.postgresText,
        'p_amount': input.amount.postgresText,
        'p_bank_name': _nullableTrimmed(input.bankName),
        'p_idempotency_key': idempotencyKey.trim(),
      },
      input.projectId,
      idempotencyKey,
      kind: _ReceivablesEntityKind.pdc,
    );
  }

  @override
  Future<YorksAccountsReceivablesCommandResult> transitionPdc(
    YorksAccountsPdcTransitionInput input, {
    required String idempotencyKey,
  }) {
    if (!input.isValid) return _invalidInput();
    return _command(
      'v1_transition_client_pdc',
      {
        'p_project_id': input.projectId.trim(),
        'p_pdc_id': input.pdcId.trim(),
        'p_expected_version': input.expectedVersion,
        'p_new_status': input.targetStatus.wireValue,
        'p_action_date': input.actionDate.postgresText,
        'p_reason': _nullableTrimmed(input.reason),
        'p_clearance_payment_reference': _nullableTrimmed(
          input.clearanceReference,
        ),
        'p_idempotency_key': idempotencyKey.trim(),
      },
      input.projectId,
      idempotencyKey,
      expectedEntityId: input.pdcId,
      kind: _ReceivablesEntityKind.pdc,
    );
  }

  @override
  Future<YorksAccountsReceivablesCommandResult> replacePdc(
    YorksAccountsPdcReplacementInput input, {
    required String idempotencyKey,
  }) {
    if (!input.isValid) return _invalidInput();
    return _command(
      'v1_replace_client_pdc',
      {
        'p_project_id': input.projectId.trim(),
        'p_pdc_id': input.originalPdcId.trim(),
        'p_expected_version': input.expectedVersion,
        'p_new_cheque_number': input.chequeNumber.trim(),
        'p_new_cheque_date': input.chequeDate.postgresText,
        'p_new_amount': input.amount.postgresText,
        'p_new_bank_name': _nullableTrimmed(input.bankName),
        'p_reason': input.reason.trim(),
        'p_idempotency_key': idempotencyKey.trim(),
      },
      input.projectId,
      idempotencyKey,
      kind: _ReceivablesEntityKind.pdc,
    );
  }

  Future<YorksAccountsReceivablesCommandResult> _claimAction(
    String functionName,
    YorksAccountsEntityActionInput input,
    String idempotencyKey,
  ) {
    if (!input.isValid) return _invalidInput();
    return _command(
      functionName,
      {
        'p_project_id': input.projectId.trim(),
        'p_claim_id': input.entityId.trim(),
        'p_expected_version': input.expectedVersion,
        'p_reason': input.reason.trim(),
        'p_idempotency_key': idempotencyKey.trim(),
      },
      input.projectId,
      idempotencyKey,
      expectedEntityId: input.entityId,
      kind: _ReceivablesEntityKind.claim,
    );
  }

  Future<YorksAccountsReceivablesCommandResult> _invoiceAction(
    String functionName,
    YorksAccountsEntityActionInput input,
    String idempotencyKey,
  ) {
    if (!input.isValid) return _invalidInput();
    return _command(
      functionName,
      {
        'p_project_id': input.projectId.trim(),
        'p_invoice_id': input.entityId.trim(),
        'p_expected_version': input.expectedVersion,
        'p_reason': input.reason.trim(),
        'p_idempotency_key': idempotencyKey.trim(),
      },
      input.projectId,
      idempotencyKey,
      expectedEntityId: input.entityId,
      kind: _ReceivablesEntityKind.invoice,
    );
  }

  Future<T> _projection<T>({
    required String projectId,
    required int limit,
    required String functionName,
    required Map<String, Object?> parameters,
    required T Function(Map<String, dynamic>) parse,
    required String Function(T) projectOf,
  }) async {
    final normalizedProjectId = projectId.trim();
    final beforeId = parameters['p_before_id'];
    final beforeTimestamp = parameters['p_before_updated_at'];
    if (normalizedProjectId.isEmpty ||
        limit < 1 ||
        limit > 100 ||
        ((beforeId == null) != (beforeTimestamp == null)) ||
        (beforeId is String && beforeId.trim().isEmpty)) {
      return _invalidInput();
    }
    final response = await _invoke(functionName, {
      'p_project_id': normalizedProjectId,
      ...parameters,
    });
    return _decode(() {
      final projection = parse(response);
      _requireId(projectOf(projection), normalizedProjectId);
      return projection;
    });
  }

  Future<YorksAccountsReceivablesCommandResult> _command(
    String functionName,
    Map<String, Object?> parameters,
    String expectedProjectId,
    String idempotencyKey, {
    required _ReceivablesEntityKind kind,
    String? expectedEntityId,
  }) async {
    final normalizedProjectId = expectedProjectId.trim();
    if (normalizedProjectId.isEmpty || idempotencyKey.trim().isEmpty) {
      return _invalidInput();
    }
    final response = await _invoke(functionName, parameters);
    return _decode(() {
      final result = YorksAccountsReceivablesCommandResult.fromRpcJson(
        response,
      );
      _requireId(result.projectId, normalizedProjectId);
      if (expectedEntityId != null) {
        _requireId(result.entityId, expectedEntityId.trim());
      }
      final kindId = switch (kind) {
        _ReceivablesEntityKind.claim => result.claimId,
        _ReceivablesEntityKind.invoice => result.invoiceId,
        _ReceivablesEntityKind.certification => result.certificationId,
        _ReceivablesEntityKind.payment => result.paymentId,
        _ReceivablesEntityKind.pdc => result.pdcId,
      };
      if (kindId == null || kindId != result.entityId) {
        throw const FormatException(
          'Receivables command returned the wrong entity kind.',
        );
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
    final code = error.code;
    final mapped = switch (code) {
      'PGRST301' ||
      'PGRST302' ||
      'PGRST303' ||
      '28000' => YorksV1DomainErrorCode.unauthenticated,
      '42501' => YorksV1DomainErrorCode.unauthorized,
      'PGRST002' || 'PGRST003' => YorksV1DomainErrorCode.backendUnavailable,
      '40001' => YorksV1DomainErrorCode.conflict,
      '22023' || '22007' || '22P02' => YorksV1DomainErrorCode.invalidInput,
      _ when message.contains('R39_ACCOUNTS_ACCESS_DENIED') =>
        YorksV1DomainErrorCode.unauthorized,
      _
          when message.contains('VERSION_CONFLICT') ||
              message.contains('IDEMPOTENCY_KEY_REUSED') ||
              message.contains('IDEMPOTENCY_PAYLOAD_MISMATCH') ||
              code == '23505' =>
        YorksV1DomainErrorCode.conflict,
      _ when message.contains('IDEMPOTENCY_IN_PROGRESS') =>
        YorksV1DomainErrorCode.backendUnavailable,
      _
          when message.contains('_CAP_EXCEEDED') ||
              message.contains('_CAP_INVALID') =>
        YorksV1DomainErrorCode.quantityCapExceeded,
      _ when message.contains('APPEND_ONLY') || message.contains('IMMUTABLE') =>
        YorksV1DomainErrorCode.immutableRecord,
      _
          when message.contains('_NOT_EDITABLE') ||
              message.contains('_NOT_SUBMITTABLE') ||
              message.contains('_NOT_CANCELLABLE') ||
              message.contains('_NOT_INVOICEABLE') ||
              message.contains('_NOT_CERTIFIABLE') ||
              message.contains('_NOT_PAYABLE') ||
              message.contains('_NOT_PDC_ELIGIBLE') ||
              message.contains('_NOT_REPLACEABLE') ||
              message.contains('INVALID_INVOICE_TRANSITION') ||
              message.contains('INVALID_PDC_TRANSITION') ||
              code == '55000' ||
              code == 'P0002' =>
        YorksV1DomainErrorCode.invalidTransition,
      _
          when message.contains('INVALID_') ||
              message.contains('_REQUIRED') ||
              code == '23514' =>
        YorksV1DomainErrorCode.invalidInput,
      _ => YorksV1DomainErrorCode.serverRejected,
    };
    return YorksV1DomainException(
      mapped,
      serverCode: code,
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

bool _validPage(int limit, YorksAccountsCompositeCursor? before) =>
    limit >= 1 &&
    limit <= 100 &&
    (before == null || before.id.trim().isNotEmpty);

void _requireId(String actual, String expected) {
  if (expected.isEmpty || actual != expected) {
    throw const FormatException('Accounts response identity mismatch.');
  }
}

String? _nullableTrimmed(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

Future<T> _invalidInput<T>() => Future.error(
  const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput),
);

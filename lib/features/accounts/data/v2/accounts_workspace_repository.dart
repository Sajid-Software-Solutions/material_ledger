/// R39 Accounts Workspace V2 — data layer repository (P5).
///
/// Thin wrapper over the new V2 RPCs, reusing the existing
/// [YorksAccountsRpcClient] (Widget → controller → repository → RPC). Reads
/// return typed projections; commands return the server's result map. Numeric
/// parameters are always sent as decimal strings (never doubles).
library;

import '../../domain/v2/accounts_workspace_models.dart';
import '../../domain/v2/claim_workbench_models.dart';
import '../../domain/v2/client_invoice_document_models.dart';
import '../../domain/v2/commercial_setup_read_models.dart';
import '../../domain/v2/pdc_register_models.dart';
import '../accounts_repository.dart' show YorksAccountsRpcClient;

final class YorksAccountsWorkspaceRepository {
  const YorksAccountsWorkspaceRepository(this._client);

  final YorksAccountsRpcClient _client;

  // ----- Reads -------------------------------------------------------------

  Future<YorksAccountsWorkspace> getWorkspace(String projectId) async {
    final json = await _client.invoke(
      functionName: 'v1_get_project_accounts_workspace',
      parameters: {'p_project_id': projectId},
    );
    return YorksAccountsWorkspace.fromJson(json);
  }

  Future<YorksAccountsCommercialSetupRead> getCommercialSetup(
    String projectId,
  ) async {
    final json = await _client.invoke(
      functionName: 'v1_get_project_commercial_setup',
      parameters: {'p_project_id': projectId},
    );
    return YorksAccountsCommercialSetupRead.fromJson(json);
  }

  Future<YorksAccountsWorkbench> getClaimWorkbench(
    String projectId, {
    String? claimId,
  }) async {
    final json = await _client.invoke(
      functionName: 'v1_get_claim_workbench',
      parameters: {'p_project_id': projectId, 'p_claim_id': claimId},
    );
    return YorksAccountsWorkbench.fromJson(json);
  }

  Future<YorksClientInvoiceDocument> getInvoiceDocument(
    String projectId,
    String invoiceId,
  ) async {
    final json = await _client.invoke(
      functionName: 'v1_get_client_invoice_document',
      parameters: {'p_project_id': projectId, 'p_invoice_id': invoiceId},
    );
    return YorksClientInvoiceDocument.fromJson(json);
  }

  Future<YorksAccountsProjectPdcRegister> getProjectPdcRegister(
    String projectId,
  ) async {
    final json = await _client.invoke(
      functionName: 'v1_list_project_client_pdcs',
      parameters: {'p_project_id': projectId},
    );
    return YorksAccountsProjectPdcRegister.fromJson(json);
  }

  Future<YorksClientInvoiceDocument> previewInvoiceDocument(
    String projectId,
    String claimId,
  ) async {
    final json = await _client.invoke(
      functionName: 'v1_preview_client_invoice_document',
      parameters: {'p_project_id': projectId, 'p_claim_id': claimId},
    );
    return YorksClientInvoiceDocument.fromJson(json);
  }

  // ----- Commands (return the server result map) ---------------------------

  Future<Map<String, dynamic>> saveCommercialSetup({
    required String projectId,
    int? expectedProfileVersion,
    required Map<String, Object?> setup,
    String? note,
    required String idempotencyKey,
  }) {
    return _client.invoke(
      functionName: 'v1_save_project_commercial_setup',
      parameters: {
        'p_project_id': projectId,
        'p_expected_profile_version': expectedProfileVersion,
        'p_setup': setup,
        'p_note': note,
        'p_idempotency_key': idempotencyKey,
      },
    );
  }

  Future<Map<String, dynamic>> saveClaimWorkbench({
    required String projectId,
    String? claimReference,
    required String periodStart,
    required String periodEnd,
    required List<Map<String, Object?>> entries,
    required List<String> evidenceDocumentIds,
    String? reason,
    required String idempotencyKey,
  }) {
    return _client.invoke(
      functionName: 'v1_save_claim_workbench',
      parameters: {
        'p_project_id': projectId,
        'p_claim_reference': claimReference,
        'p_period_start': periodStart,
        'p_period_end': periodEnd,
        'p_entries': entries,
        'p_evidence_document_ids': evidenceDocumentIds,
        'p_reason': reason,
        'p_idempotency_key': idempotencyKey,
      },
    );
  }

  Future<Map<String, dynamic>> reopenClaim({
    required String projectId,
    required String claimId,
    required int expectedVersion,
    required String reason,
    required String idempotencyKey,
  }) {
    return _client.invoke(
      functionName: 'v1_reopen_client_claim',
      parameters: {
        'p_project_id': projectId,
        'p_claim_id': claimId,
        'p_expected_version': expectedVersion,
        'p_reason': reason,
        'p_idempotency_key': idempotencyKey,
      },
    );
  }

  Future<Map<String, dynamic>> saveInvoiceSettings({
    required String projectId,
    required String invoicePrefix,
    String? scopeLine,
    String? billToPartyId,
    String? attentionName,
    int? expectedVersion,
    required String idempotencyKey,
  }) {
    return _client.invoke(
      functionName: 'v1_save_project_invoice_settings',
      parameters: {
        'p_project_id': projectId,
        'p_invoice_prefix': invoicePrefix,
        'p_scope_line': scopeLine,
        'p_bill_to_party_id': billToPartyId,
        'p_attention_name': attentionName,
        'p_expected_version': expectedVersion,
        'p_idempotency_key': idempotencyKey,
      },
    );
  }

  Future<Map<String, dynamic>> issueInvoice({
    required String projectId,
    required String claimId,
    int? expectedClaimVersion,
    String? invoiceReference,
    required String invoiceDate,
    required String submissionDate,
    required String idempotencyKey,
  }) {
    return _client.invoke(
      functionName: 'v1_issue_client_invoice',
      parameters: {
        'p_project_id': projectId,
        'p_claim_id': claimId,
        'p_expected_claim_version': expectedClaimVersion,
        'p_invoice_reference': invoiceReference,
        'p_invoice_date': invoiceDate,
        'p_submission_date': submissionDate,
        'p_idempotency_key': idempotencyKey,
      },
    );
  }

  Future<Map<String, dynamic>> reviseInvoice({
    required String projectId,
    required String invoiceId,
    required int expectedVersion,
    required String reason,
    required String idempotencyKey,
  }) {
    return _client.invoke(
      functionName: 'v1_revise_client_invoice',
      parameters: {
        'p_project_id': projectId,
        'p_invoice_id': invoiceId,
        'p_expected_version': expectedVersion,
        'p_reason': reason,
        'p_idempotency_key': idempotencyKey,
      },
    );
  }
}

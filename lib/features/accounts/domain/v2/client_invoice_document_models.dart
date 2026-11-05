/// R39 Accounts Workspace V2 — client invoice document models (P5).
///
/// Typed parse of the frozen print model returned by
/// `v1_get_client_invoice_document` (issued) and
/// `v1_preview_client_invoice_document` (draft). The builder in P7 renders this
/// model and never recomputes money: all amounts are exact decimal strings.
library;

import '../accounts_decimal.dart';

/// One building × stage line on the invoice breakdown.
final class YorksClientInvoiceLine {
  const YorksClientInvoiceLine({
    required this.buildingScopeId,
    required this.buildingName,
    required this.stageKey,
    required this.stageLabel,
    required this.amount,
  });

  factory YorksClientInvoiceLine.fromJson(Map<String, dynamic> json) {
    return YorksClientInvoiceLine(
      buildingScopeId: json['building_scope_id'] as String,
      buildingName: json['building_name'] as String,
      stageKey: json['stage_key'] as String,
      stageLabel: json['stage_label'] as String?,
      amount: YorksAccountsDecimal.fromRpcValue(json['amount'], key: 'line.amount'),
    );
  }

  final String buildingScopeId;
  final String buildingName;
  final String stageKey;
  final String? stageLabel;
  final YorksAccountsDecimal amount;
}

/// The invoice amounts (exact).
final class YorksClientInvoiceAmounts {
  const YorksClientInvoiceAmounts({
    required this.exVat,
    required this.vatRatePercent,
    required this.vat,
    required this.totalInclVat,
  });

  factory YorksClientInvoiceAmounts.fromJson(Map<String, dynamic> json) {
    return YorksClientInvoiceAmounts(
      exVat: YorksAccountsDecimal.fromRpcValue(json['ex_vat'], key: 'amounts.ex_vat'),
      vatRatePercent: YorksAccountsDecimal.fromRpcValue(
        json['vat_rate_percent'], key: 'amounts.vat_rate_percent'),
      vat: YorksAccountsDecimal.fromRpcValue(json['vat'], key: 'amounts.vat'),
      totalInclVat: YorksAccountsDecimal.fromRpcValue(
        json['total_incl_vat'], key: 'amounts.total_incl_vat'),
    );
  }

  final YorksAccountsDecimal exVat;
  final YorksAccountsDecimal vatRatePercent;
  final YorksAccountsDecimal vat;
  final YorksAccountsDecimal totalInclVat;
}

/// The frozen (or previewed) invoice print model.
final class YorksClientInvoiceDocumentModel {
  const YorksClientInvoiceDocumentModel({
    required this.invoiceReference,
    required this.invoiceDate,
    required this.submissionDate,
    required this.dueDate,
    required this.paymentTermsDays,
    required this.currencyCode,
    required this.company,
    required this.project,
    required this.claim,
    required this.settings,
    required this.amounts,
    required this.lines,
  });

  factory YorksClientInvoiceDocumentModel.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> obj(String key) => json[key] is Map
        ? Map<String, dynamic>.from(json[key] as Map)
        : const <String, dynamic>{};
    return YorksClientInvoiceDocumentModel(
      invoiceReference: json['invoice_reference'] as String,
      invoiceDate: json['invoice_date'] as String?,
      submissionDate: json['submission_date'] as String?,
      dueDate: json['due_date'] as String?,
      paymentTermsDays: (json['payment_terms_days'] as num?)?.toInt(),
      currencyCode: json['currency_code'] as String?,
      company: obj('company'),
      project: obj('project'),
      claim: obj('claim'),
      settings: obj('settings'),
      amounts: YorksClientInvoiceAmounts.fromJson(obj('amounts')),
      lines: ((json['lines'] as List?) ?? const <dynamic>[])
          .map((e) => YorksClientInvoiceLine.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false),
    );
  }

  final String invoiceReference;
  final String? invoiceDate;
  final String? submissionDate;
  final String? dueDate;
  final int? paymentTermsDays;
  final String? currencyCode;

  /// Letterhead / bank block (company.* published settings), snapshotted.
  final Map<String, dynamic> company;
  final Map<String, dynamic> project;
  final Map<String, dynamic> claim;
  final Map<String, dynamic> settings;
  final YorksClientInvoiceAmounts amounts;
  final List<YorksClientInvoiceLine> lines;
}

/// Envelope from get (frozen) or preview (live).
final class YorksClientInvoiceDocument {
  const YorksClientInvoiceDocument({
    required this.projectId,
    required this.invoiceId,
    required this.snapshotSha256,
    required this.controlledDocumentId,
    required this.isPreview,
    required this.document,
  });

  factory YorksClientInvoiceDocument.fromJson(Map<String, dynamic> json) {
    return YorksClientInvoiceDocument(
      projectId: json['project_id'] as String,
      invoiceId: json['invoice_id'] as String?,
      snapshotSha256: json['snapshot_sha256'] as String?,
      controlledDocumentId: json['controlled_document_id'] as String?,
      isPreview: json['preview'] == true,
      document: YorksClientInvoiceDocumentModel.fromJson(
        Map<String, dynamic>.from(json['document'] as Map)),
    );
  }

  final String projectId;

  /// Null for a preview (no invoice yet).
  final String? invoiceId;
  final String? snapshotSha256;
  final String? controlledDocumentId;
  final bool isPreview;
  final YorksClientInvoiceDocumentModel document;
}

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
      amount: YorksAccountsDecimal.fromRpcValue(
        json['amount'],
        key: 'line.amount',
      ),
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
      exVat: YorksAccountsDecimal.fromRpcValue(
        json['ex_vat'],
        key: 'amounts.ex_vat',
      ),
      vatRatePercent: YorksAccountsDecimal.fromRpcValue(
        json['vat_rate_percent'],
        key: 'amounts.vat_rate_percent',
      ),
      vat: YorksAccountsDecimal.fromRpcValue(json['vat'], key: 'amounts.vat'),
      totalInclVat: YorksAccountsDecimal.fromRpcValue(
        json['total_incl_vat'],
        key: 'amounts.total_incl_vat',
      ),
    );
  }

  final YorksAccountsDecimal exVat;
  final YorksAccountsDecimal vatRatePercent;
  final YorksAccountsDecimal vat;
  final YorksAccountsDecimal totalInclVat;
}

/// One stage row of the Main Summary matrix (aggregated across all buildings).
final class YorksClientInvoiceSummaryStage {
  const YorksClientInvoiceSummaryStage({
    required this.stageKey,
    required this.stageLabel,
    required this.contractPercent,
    required this.contractAmount,
    required this.previousAmount,
    required this.thisAmount,
    required this.totalAmount,
  });

  factory YorksClientInvoiceSummaryStage.fromJson(Map<String, dynamic> json) {
    YorksAccountsDecimal d(String k) =>
        YorksAccountsDecimal.fromRpcValue(json[k], key: 'summary.$k');
    return YorksClientInvoiceSummaryStage(
      stageKey: json['stage_key'] as String,
      stageLabel: json['stage_label'] as String?,
      contractPercent: d('contract_percent'),
      contractAmount: d('contract_amount'),
      previousAmount: d('previous_amount'),
      thisAmount: d('this_amount'),
      totalAmount: d('total_amount'),
    );
  }

  final String stageKey;
  final String? stageLabel;
  final YorksAccountsDecimal contractPercent;
  final YorksAccountsDecimal contractAmount;
  final YorksAccountsDecimal previousAmount;
  final YorksAccountsDecimal thisAmount;
  final YorksAccountsDecimal totalAmount;
}

/// The Main Summary matrix: contract / till-previous / this-month / total.
final class YorksClientInvoiceSummary {
  const YorksClientInvoiceSummary({
    required this.contractTotal,
    required this.previousTotal,
    required this.thisTotal,
    required this.totalTotal,
    required this.stages,
    this.contractVat,
    this.contractGrand,
    this.previousVat,
    this.previousGrand,
    this.thisVat,
    this.thisGrand,
    this.totalVat,
    this.totalGrand,
  });

  factory YorksClientInvoiceSummary.fromJson(Map<String, dynamic> json) {
    YorksAccountsDecimal d(String k) =>
        YorksAccountsDecimal.fromRpcValue(json[k], key: 'summary.$k');
    YorksAccountsDecimal? o(String k) => json[k] is String ? d(k) : null;
    return YorksClientInvoiceSummary(
      contractTotal: d('contract_total'),
      previousTotal: d('previous_total'),
      thisTotal: d('this_total'),
      totalTotal: d('total_total'),
      contractVat: o('contract_vat'),
      contractGrand: o('contract_grand'),
      previousVat: o('previous_vat'),
      previousGrand: o('previous_grand'),
      thisVat: o('this_vat'),
      thisGrand: o('this_grand'),
      totalVat: o('total_vat'),
      totalGrand: o('total_grand'),
      stages: ((json['stages'] as List?) ?? const <dynamic>[])
          .map(
            (e) => YorksClientInvoiceSummaryStage.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  final YorksAccountsDecimal contractTotal;
  final YorksAccountsDecimal previousTotal;
  final YorksAccountsDecimal thisTotal;
  final YorksAccountsDecimal totalTotal;
  final List<YorksClientInvoiceSummaryStage> stages;

  /// VAT and grand-total rows per column (schema 3; the Excel rule rounds each
  /// once from the exact amount). Null on older snapshots.
  final YorksAccountsDecimal? contractVat;
  final YorksAccountsDecimal? contractGrand;
  final YorksAccountsDecimal? previousVat;
  final YorksAccountsDecimal? previousGrand;
  final YorksAccountsDecimal? thisVat;
  final YorksAccountsDecimal? thisGrand;
  final YorksAccountsDecimal? totalVat;
  final YorksAccountsDecimal? totalGrand;

  bool get hasVatRows =>
      contractVat != null && previousVat != null && thisVat != null;
}

/// One stage row within a building's breakdown.
final class YorksClientInvoiceBuildingStage {
  const YorksClientInvoiceBuildingStage({
    required this.stageKey,
    required this.stageLabel,
    required this.stageValue,
    required this.previousAmount,
    required this.thisAmount,
    required this.totalAmount,
  });

  factory YorksClientInvoiceBuildingStage.fromJson(Map<String, dynamic> json) {
    YorksAccountsDecimal d(String k) =>
        YorksAccountsDecimal.fromRpcValue(json[k], key: 'building.$k');
    return YorksClientInvoiceBuildingStage(
      stageKey: json['stage_key'] as String,
      stageLabel: json['stage_label'] as String?,
      stageValue: d('stage_value'),
      previousAmount: d('previous_amount'),
      thisAmount: d('this_amount'),
      totalAmount: d('total_amount'),
    );
  }

  final String stageKey;
  final String? stageLabel;
  final YorksAccountsDecimal stageValue;
  final YorksAccountsDecimal previousAmount;
  final YorksAccountsDecimal thisAmount;
  final YorksAccountsDecimal totalAmount;
}

/// One building's breakdown (share, value and its stage rows).
final class YorksClientInvoiceBuilding {
  const YorksClientInvoiceBuilding({
    required this.buildingScopeId,
    required this.name,
    required this.sharePercent,
    required this.buildingValue,
    required this.previousAmount,
    required this.thisAmount,
    required this.totalAmount,
    required this.stages,
  });

  factory YorksClientInvoiceBuilding.fromJson(Map<String, dynamic> json) {
    YorksAccountsDecimal d(String k) =>
        YorksAccountsDecimal.fromRpcValue(json[k], key: 'building.$k');
    return YorksClientInvoiceBuilding(
      buildingScopeId: json['building_scope_id'] as String,
      name: json['name'] as String? ?? '',
      sharePercent: d('share_percent'),
      buildingValue: d('building_value'),
      previousAmount: d('previous_amount'),
      thisAmount: d('this_amount'),
      totalAmount: d('total_amount'),
      stages: ((json['stages'] as List?) ?? const <dynamic>[])
          .map(
            (e) => YorksClientInvoiceBuildingStage.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  final String buildingScopeId;
  final String name;
  final YorksAccountsDecimal sharePercent;
  final YorksAccountsDecimal buildingValue;
  final YorksAccountsDecimal previousAmount;
  final YorksAccountsDecimal thisAmount;
  final YorksAccountsDecimal totalAmount;
  final List<YorksClientInvoiceBuildingStage> stages;
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
    required this.contractValue,
    required this.summary,
    required this.buildings,
    this.billTo = const <String, dynamic>{},
    this.references = const <String, dynamic>{},
  });

  factory YorksClientInvoiceDocumentModel.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> obj(String key) => json[key] is Map
        ? Map<String, dynamic>.from(json[key] as Map)
        : const <String, dynamic>{};
    final summaryJson = json['summary'];
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
          .map(
            (e) => YorksClientInvoiceLine.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(growable: false),
      contractValue: json['contract_value'] is String
          ? YorksAccountsDecimal.fromRpcValue(
              json['contract_value'],
              key: 'contract_value',
            )
          : null,
      // summary / buildings are absent on legacy (schema_version 1) snapshots.
      summary: summaryJson is Map
          ? YorksClientInvoiceSummary.fromJson(
              Map<String, dynamic>.from(summaryJson),
            )
          : null,
      buildings: ((json['buildings'] as List?) ?? const <dynamic>[])
          .map(
            (e) => YorksClientInvoiceBuilding.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(growable: false),
      billTo: obj('bill_to'),
      references: obj('references'),
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

  /// The full contract value (for the summary header). Null on legacy snapshots.
  final YorksAccountsDecimal? contractValue;

  /// The whole contract value every printed percentage is measured against.
  YorksAccountsDecimal? get percentBase =>
      contractValue ?? summary?.contractTotal;

  /// [amount] as a share of the whole contract, the basis Yorks' signed
  /// invoices use for every percentage on the summary and building pages
  /// (YRA-322: DF3W Material Supply 1,549,624.36 of 17,192,000 is 9.01%).
  /// Never divide by a building or stage value: that printed 72.11% where the
  /// client invoice says 9.01%. Presentation only; money stays exact.
  /// Null when there is no contract value to measure against.
  double? percentOfContract(YorksAccountsDecimal amount) {
    final base = double.tryParse(percentBase?.canonicalText ?? '') ?? 0;
    if (base <= 0) return null;
    final value = double.tryParse(amount.canonicalText) ?? 0;
    return value / base * 100;
  }

  /// The stage's share of the contract (10, 50, 30, 5, 5), from the summary.
  YorksAccountsDecimal? stageContractPercent(String stageKey) {
    for (final stage
        in summary?.stages ?? const <YorksClientInvoiceSummaryStage>[]) {
      if (stage.stageKey == stageKey) return stage.contractPercent;
    }
    return null;
  }

  /// Main Summary matrix. Null on legacy (schema_version 1) snapshots, in which
  /// case the builder renders only the tax-invoice page.
  final YorksClientInvoiceSummary? summary;

  /// Per-building breakdown. Empty on legacy snapshots.
  final List<YorksClientInvoiceBuilding> buildings;

  /// Who is billed (name, address), schema 3. Empty on older snapshots.
  final Map<String, dynamic> billTo;

  /// Client TRN, work order number/date and contract number, schema 3.
  final Map<String, dynamic> references;
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
        Map<String, dynamic>.from(json['document'] as Map),
      ),
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

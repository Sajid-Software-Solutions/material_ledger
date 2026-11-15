/// Contract materials — Accounts › Materials (PRODUCT_DECISIONS.md §61).
///
/// Typed parse of `v1_get_accounts_material_register`: per building, every
/// line of the contract's item-measured stages (Material Supply and
/// Installation on YRA-322), with what is confirmed delivered or installed and
/// what has reached site. Money, weights and invoices are present only when the
/// server sends them (`view_project_commercial_values`); a person without that
/// capability gets no such key at all, so every money field here is nullable.
library;

import '../accounts_decimal.dart';

/// Where a line stands in one stage, from its confirmed quantity.
enum YorksAccountsLineProgress {
  /// Nothing confirmed.
  none,

  /// Some, not all, of the line's quantity confirmed.
  part,

  /// All of it confirmed.
  done,
}

/// Where a line's billing stands in one stage, from what is confirmed and what
/// the invoiced claims carried. Only known to someone who may see values.
enum YorksAccountsLineBilling {
  /// Nothing confirmed and nothing invoiced.
  none,

  /// More confirmed than invoiced: the next claim can bill it.
  ready,

  /// Everything confirmed is invoiced.
  invoiced,

  /// More was invoiced than is confirmed today (a lowered confirmation).
  overInvoiced,
}

YorksAccountsDecimal _decimal(Object? raw, String key) =>
    YorksAccountsDecimal.fromRpcValue(raw, key: key);

YorksAccountsDecimal? _optionalDecimal(Object? raw) =>
    raw == null ? null : YorksAccountsDecimal.tryParse('$raw');

/// The invoice that last billed a line.
final class YorksAccountsRegisterInvoice {
  const YorksAccountsRegisterInvoice({
    required this.invoiceId,
    required this.reference,
    required this.status,
  });

  factory YorksAccountsRegisterInvoice.fromJson(Map<String, dynamic> json) =>
      YorksAccountsRegisterInvoice(
        invoiceId: json['invoice_id'] as String,
        reference: json['invoice_reference'] as String? ?? '',
        status: json['status'] as String? ?? '',
      );

  final String invoiceId;
  final String reference;

  /// The invoice's own status (`submitted`, `certified`, `paid` …).
  final String status;
}

/// One line in one item-measured stage.
final class YorksAccountsRegisterLineStage {
  const YorksAccountsRegisterLineStage({
    required this.stageKey,
    required this.stageItemId,
    required this.quantity,
    required this.unitCode,
    required this.confirmedQty,
    required this.needsReview,
    this.weightPercent,
    this.amount,
    this.rate,
    this.doneAmount,
    this.invoicedQty,
    this.lastInvoice,
  });

  factory YorksAccountsRegisterLineStage.fromJson(Map<String, dynamic> json) {
    final invoice = json['last_invoice'];
    return YorksAccountsRegisterLineStage(
      stageKey: json['stage_key'] as String,
      stageItemId: json['stage_item_id'] as String,
      quantity: _decimal(json['quantity'], 'line.quantity'),
      unitCode: json['unit_code'] as String? ?? '',
      confirmedQty: _decimal(json['confirmed_qty'], 'line.confirmed_qty'),
      needsReview: json['needs_review'] == true,
      weightPercent: _optionalDecimal(json['weight_percent']),
      amount: _optionalDecimal(json['amount']),
      rate: _optionalDecimal(json['rate']),
      doneAmount: _optionalDecimal(json['done_amount']),
      invoicedQty: _optionalDecimal(json['invoiced_qty']),
      lastInvoice: invoice is Map
          ? YorksAccountsRegisterInvoice.fromJson(
              Map<String, dynamic>.from(invoice),
            )
          : null,
    );
  }

  final String stageKey;
  final String stageItemId;
  final YorksAccountsDecimal quantity;
  final String unitCode;
  final YorksAccountsDecimal confirmedQty;

  /// A contract revision lowered the quantity below what was confirmed.
  final bool needsReview;

  // ── Only for someone who may see commercial values ─────────────────────────
  final YorksAccountsDecimal? weightPercent;

  /// The line's contract amount in this stage.
  final YorksAccountsDecimal? amount;

  /// [amount] divided by [quantity], rounded to the fil for display.
  final YorksAccountsDecimal? rate;

  /// What the confirmed quantity is worth, rounded to the fil.
  final YorksAccountsDecimal? doneAmount;

  /// The quantity the invoiced claims carried.
  final YorksAccountsDecimal? invoicedQty;
  final YorksAccountsRegisterInvoice? lastInvoice;

  YorksAccountsLineProgress get progress {
    if (!confirmedQty.isPositive) return YorksAccountsLineProgress.none;
    return confirmedQty.compareTo(quantity) >= 0
        ? YorksAccountsLineProgress.done
        : YorksAccountsLineProgress.part;
  }

  /// Null when the caller may not see billing.
  YorksAccountsLineBilling? get billing {
    final invoiced = invoicedQty;
    if (invoiced == null) return null;
    final c = confirmedQty.compareTo(invoiced);
    if (c > 0) return YorksAccountsLineBilling.ready;
    if (c < 0) return YorksAccountsLineBilling.overInvoiced;
    return invoiced.isPositive
        ? YorksAccountsLineBilling.invoiced
        : YorksAccountsLineBilling.none;
  }

  /// A lump-sum line (1 Lot) is measured in parts of one, shown as a
  /// percentage, as the server's unit key reads the usual spellings.
  bool get isLot => const {
    'lot',
    'lots',
    'ls',
    'l.s',
    'lump sum',
    'lumpsum',
    'job',
  }.contains(unitCode.trim().toLowerCase().replaceAll(RegExp(r'\.$'), ''));
}

/// What has reached site for a line, through Material Requests raised from its
/// BOQ row or from a folder linked to it. A guide only.
final class YorksAccountsRegisterSite {
  const YorksAccountsRegisterSite({
    required this.basis,
    required this.deliveredQty,
    required this.deliveries,
    this.lastDeliveryReference,
    this.lastDeliveryDate,
  });

  factory YorksAccountsRegisterSite.fromJson(Map<String, dynamic> json) =>
      YorksAccountsRegisterSite(
        basis: json['basis'] as String? ?? 'quantity',
        deliveredQty: _decimal(json['delivered_qty'], 'site.delivered_qty'),
        deliveries: (json['deliveries'] as num?)?.toInt() ?? 0,
        lastDeliveryReference: json['last_delivery_reference'] as String?,
        lastDeliveryDate: json['last_delivery_date'] as String?,
      );

  /// `quantity` when the rows share the line's unit; `share` otherwise.
  final String basis;
  final YorksAccountsDecimal deliveredQty;
  final int deliveries;
  final String? lastDeliveryReference;
  final String? lastDeliveryDate;
}

/// One contract line of a building, across its item-measured stages.
final class YorksAccountsRegisterLine {
  const YorksAccountsRegisterLine({
    required this.itemKey,
    required this.itemLabel,
    required this.displayOrder,
    required this.stages,
    this.boqRowId,
    this.boqGroupId,
    this.site,
  });

  factory YorksAccountsRegisterLine.fromJson(Map<String, dynamic> json) {
    final site = json['site'];
    return YorksAccountsRegisterLine(
      itemKey: json['item_key'] as String,
      itemLabel: json['item_label'] as String? ?? '',
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
      boqRowId: json['boq_row_id'] as String?,
      boqGroupId: json['boq_group_id'] as String?,
      site: site is Map
          ? YorksAccountsRegisterSite.fromJson(Map<String, dynamic>.from(site))
          : null,
      stages: [
        for (final s in (json['stages'] as List?) ?? const <dynamic>[])
          YorksAccountsRegisterLineStage.fromJson(
            Map<String, dynamic>.from(s as Map),
          ),
      ],
    );
  }

  final String itemKey;
  final String itemLabel;
  final int displayOrder;

  /// The BOQ row (and its folder) that stands for this line, when tied.
  final String? boqRowId;
  final String? boqGroupId;
  final YorksAccountsRegisterSite? site;
  final List<YorksAccountsRegisterLineStage> stages;

  YorksAccountsRegisterLineStage? stage(String stageKey) {
    for (final s in stages) {
      if (s.stageKey == stageKey) return s;
    }
    return null;
  }
}

/// A building's totals in one stage. Money only with values.
final class YorksAccountsRegisterCell {
  const YorksAccountsRegisterCell({
    required this.stageKey,
    required this.stageLabel,
    required this.displayOrder,
    this.stageValue,
    this.doneAmount,
    this.invoicedAmount,
    this.inClaimAmount,
    this.notInvoicedAmount,
    this.overInvoiced = false,
  });

  factory YorksAccountsRegisterCell.fromJson(Map<String, dynamic> json) =>
      YorksAccountsRegisterCell(
        stageKey: json['stage_key'] as String,
        stageLabel: json['stage_label'] as String? ?? '',
        displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
        stageValue: _optionalDecimal(json['stage_value']),
        doneAmount: _optionalDecimal(json['done_amount']),
        invoicedAmount: _optionalDecimal(json['invoiced_amount']),
        inClaimAmount: _optionalDecimal(json['in_claim_amount']),
        notInvoicedAmount: _optionalDecimal(json['not_invoiced_amount']),
        overInvoiced: json['over_invoiced'] == true,
      );

  final String stageKey;
  final String stageLabel;
  final int displayOrder;
  final YorksAccountsDecimal? stageValue;

  /// What the confirmed quantities are worth (the claim's eligible amount).
  final YorksAccountsDecimal? doneAmount;

  /// Billed on issued invoices, as billed.
  final YorksAccountsDecimal? invoicedAmount;

  /// In a claim not yet invoiced.
  final YorksAccountsDecimal? inClaimAmount;

  /// Done but not yet invoiced: the next invoice can bill it, including any
  /// contract value correction on work billed before a revision.
  final YorksAccountsDecimal? notInvoicedAmount;
  final bool overInvoiced;
}

final class YorksAccountsRegisterBuilding {
  const YorksAccountsRegisterBuilding({
    required this.projectScopeId,
    required this.buildingName,
    required this.scopeCode,
    required this.cells,
    required this.lines,
  });

  factory YorksAccountsRegisterBuilding.fromJson(
    Map<String, dynamic> json,
  ) => YorksAccountsRegisterBuilding(
    projectScopeId: json['project_scope_id'] as String,
    buildingName: json['building_name'] as String? ?? '',
    scopeCode: json['scope_code'] as String? ?? '',
    cells: [
      for (final c in (json['stages'] as List?) ?? const <dynamic>[])
        YorksAccountsRegisterCell.fromJson(Map<String, dynamic>.from(c as Map)),
    ],
    lines: [
      for (final l in (json['lines'] as List?) ?? const <dynamic>[])
        YorksAccountsRegisterLine.fromJson(Map<String, dynamic>.from(l as Map)),
    ],
  );

  final String projectScopeId;
  final String buildingName;
  final String scopeCode;
  final List<YorksAccountsRegisterCell> cells;
  final List<YorksAccountsRegisterLine> lines;

  YorksAccountsRegisterCell? cell(String stageKey) {
    for (final c in cells) {
      if (c.stageKey == stageKey) return c;
    }
    return null;
  }

  /// The building's short name: the part before " - " or "- " in names such
  /// as "DF3W- 132/33Kv SUBSTATION BUILDING".
  String get shortName {
    final name = buildingName.trim();
    final dash = name.indexOf('-');
    if (dash > 0) {
      final head = name.substring(0, dash).trim();
      if (head.isNotEmpty && head.length <= 12) return head;
    }
    return name;
  }
}

/// An item-measured stage the register can show.
final class YorksAccountsRegisterStage {
  const YorksAccountsRegisterStage({
    required this.stageKey,
    required this.stageLabel,
    required this.displayOrder,
  });

  factory YorksAccountsRegisterStage.fromJson(Map<String, dynamic> json) =>
      YorksAccountsRegisterStage(
        stageKey: json['stage_key'] as String,
        stageLabel: json['stage_label'] as String? ?? '',
        displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
      );

  final String stageKey;
  final String stageLabel;
  final int displayOrder;
}

/// The whole read.
final class YorksAccountsMaterialRegister {
  const YorksAccountsMaterialRegister({
    required this.projectId,
    required this.canViewValues,
    required this.stages,
    required this.buildings,
    this.baselineRevisionId,
    this.baselineRevisionNumber,
    this.currencyCode,
    this.contractValue,
  });

  factory YorksAccountsMaterialRegister.fromJson(Map<String, dynamic> json) =>
      YorksAccountsMaterialRegister(
        projectId: json['project_id'] as String? ?? '',
        baselineRevisionId: json['baseline_revision_id'] as String?,
        baselineRevisionNumber: (json['baseline_revision_number'] as num?)
            ?.toInt(),
        canViewValues: json['can_view_values'] == true,
        currencyCode: json['currency_code'] as String?,
        contractValue: _optionalDecimal(json['contract_value']),
        stages: [
          for (final s in (json['stages'] as List?) ?? const <dynamic>[])
            YorksAccountsRegisterStage.fromJson(
              Map<String, dynamic>.from(s as Map),
            ),
        ],
        buildings: [
          for (final b in (json['buildings'] as List?) ?? const <dynamic>[])
            YorksAccountsRegisterBuilding.fromJson(
              Map<String, dynamic>.from(b as Map),
            ),
        ],
      );

  final String projectId;
  final String? baselineRevisionId;
  final int? baselineRevisionNumber;

  /// Whether the server sent money. The screen never infers it from a role.
  final bool canViewValues;
  final String? currencyCode;
  final YorksAccountsDecimal? contractValue;
  final List<YorksAccountsRegisterStage> stages;
  final List<YorksAccountsRegisterBuilding> buildings;

  bool get isEmpty => buildings.every((b) => b.lines.isEmpty);
}

/// One numbered row of an invoice-style sheet: either a group heading
/// ("A.10 Ducting") or a line ("A.10.1 Basement Floor").
final class YorksAccountsSheetRow {
  const YorksAccountsSheetRow.heading(this.code, this.label) : line = null;

  const YorksAccountsSheetRow.line(this.code, this.label, this.line);

  final String code;
  final String label;

  /// Null for a group heading.
  final YorksAccountsRegisterLine? line;

  bool get isHeading => line == null;
}

/// Numbers a building's lines as the signed invoices do: one number per line,
/// in contract order, except lines keyed "10-1", "10-2" … which sit under one
/// group number ("A.10") named by the label before " — ", each shown by the
/// rest of its label ("A.10.1 Basement Floor"). [letter] is the building's
/// letter (A for the first building).
List<YorksAccountsSheetRow> yorksAccountsSheetRows(
  String letter,
  List<YorksAccountsRegisterLine> lines,
) {
  final ordered = [...lines]
    ..sort((a, b) {
      final o = a.displayOrder.compareTo(b.displayOrder);
      return o != 0 ? o : a.itemKey.compareTo(b.itemKey);
    });
  final rows = <YorksAccountsSheetRow>[];
  final groupNumber = <String, int>{};
  var number = 0;
  for (final line in ordered) {
    final key = line.itemKey;
    final dash = key.indexOf('-');
    final group = dash > 0 ? key.substring(0, dash) : null;
    final split = line.itemLabel.indexOf(' — ');
    if (group == null) {
      number += 1;
      rows.add(
        YorksAccountsSheetRow.line('$letter.$number', line.itemLabel, line),
      );
      continue;
    }
    if (!groupNumber.containsKey(group)) {
      number += 1;
      groupNumber[group] = number;
      rows.add(
        YorksAccountsSheetRow.heading(
          '$letter.$number',
          split > 0 ? line.itemLabel.substring(0, split) : line.itemLabel,
        ),
      );
    }
    rows.add(
      YorksAccountsSheetRow.line(
        '$letter.${groupNumber[group]}.${key.substring(dash + 1)}',
        split > 0 ? line.itemLabel.substring(split + 3) : line.itemLabel,
        line,
      ),
    );
  }
  return rows;
}

/// The letter the invoices give the building at [index] (A for the first).
String yorksAccountsBuildingLetter(int index) =>
    String.fromCharCode(65 + (index % 26));

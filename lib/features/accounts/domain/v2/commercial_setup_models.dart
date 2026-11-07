/// R39 Accounts Workspace V2 — Contract (commercial setup) form model (P5).
///
/// Client-side mirror of the contract the user edits on the Contract tab, with
/// the additive mirror checks (contract > 0, buildings total 100%, stages total
/// 100%) and a toSetupJson() that builds the exact p_setup payload for
/// v1_save_project_commercial_setup. The server is always final — the
/// per-building item-weight rule and all persistence stay server-enforced; this
/// only gives the SetupCheckPanel instant feedback on the simple totals.
library;

import '../accounts_decimal.dart';

/// Result of one setup mirror check.
final class YorksAccountsSetupCheck {
  const YorksAccountsSetupCheck({
    required this.key,
    required this.ok,
    required this.detail,
  });

  final String key;
  final bool ok;
  final String detail;
}

final class YorksAccountsSetupBuilding {
  const YorksAccountsSetupBuilding({
    required this.buildingScopeId,
    required this.allocationPercent,
  });

  final String buildingScopeId;
  final YorksAccountsDecimal allocationPercent;

  Map<String, Object?> toJson() => {
    'building_scope_id': buildingScopeId,
    'allocation_percent': allocationPercent.postgresText,
  };
}

final class YorksAccountsSetupItem {
  const YorksAccountsSetupItem({
    required this.itemKey,
    required this.itemLabel,
    required this.displayOrder,
    required this.quantity,
    required this.unitCode,
    required this.weightPercentOfContract,
  });

  final String itemKey;
  final String itemLabel;
  final int displayOrder;
  final YorksAccountsDecimal quantity;
  final String unitCode;
  final YorksAccountsDecimal weightPercentOfContract;

  Map<String, Object?> toJson() => {
    'item_key': itemKey,
    'item_label': itemLabel,
    'display_order': displayOrder,
    'quantity': quantity.postgresText,
    'unit_code': unitCode,
    'weight_percent_of_contract': weightPercentOfContract.postgresText,
  };
}

final class YorksAccountsSetupStage {
  const YorksAccountsSetupStage({
    required this.stageKey,
    required this.stageLabel,
    required this.allocationPercent,
    required this.position,
    required this.measurementMode,
    required this.items,
  });

  final String stageKey;
  final String stageLabel;
  final YorksAccountsDecimal allocationPercent;
  final int position;

  /// 'percent' or 'items'.
  final String measurementMode;
  final List<YorksAccountsSetupItem> items;

  bool get isItemsMode => measurementMode == 'items';

  Map<String, Object?> toJson() => {
    'stage_key': stageKey,
    'stage_label': stageLabel,
    'allocation_percent': allocationPercent.postgresText,
    'position': position,
    'measurement_mode': measurementMode,
    if (isItemsMode)
      'items': items.map((e) => e.toJson()).toList(growable: false),
  };
}

final class YorksAccountsCommercialSetup {
  const YorksAccountsCommercialSetup({
    required this.contractValue,
    required this.currencyCode,
    required this.vatRatePercent,
    required this.paymentTermsDays,
    required this.reminderLeadDays,
    required this.buildings,
    required this.stages,
  });

  final YorksAccountsDecimal contractValue;
  final String currencyCode;
  final YorksAccountsDecimal vatRatePercent;
  final int? paymentTermsDays;
  final int? reminderLeadDays;
  final List<YorksAccountsSetupBuilding> buildings;
  final List<YorksAccountsSetupStage> stages;

  static YorksAccountsDecimal _sum(Iterable<YorksAccountsDecimal> xs) =>
      xs.fold(YorksAccountsDecimal.zero, (a, b) => a + b);

  YorksAccountsDecimal get buildingTotal =>
      _sum(buildings.map((b) => b.allocationPercent));
  YorksAccountsDecimal get stageTotal =>
      _sum(stages.map((s) => s.allocationPercent));

  /// Additive mirror checks. The server remains authoritative; the per-building
  /// item-weight rule is not mirrored here (it is server-enforced).
  List<YorksAccountsSetupCheck> validate() {
    final hundred = YorksAccountsDecimal.hundred;
    return [
      YorksAccountsSetupCheck(
        key: 'contract_value',
        ok: contractValue.isPositive,
        detail: contractValue.isPositive
            ? contractValue.displayText(maximumFractionDigits: 2)
            : 'Enter the contract value (excl. VAT)',
      ),
      YorksAccountsSetupCheck(
        key: 'buildings_total',
        ok: buildings.isNotEmpty && buildingTotal == hundred,
        detail:
            'Currently ${buildingTotal.displayText(maximumFractionDigits: 2)}%',
      ),
      YorksAccountsSetupCheck(
        key: 'stages_total',
        ok: stageTotal == hundred,
        detail:
            'Currently ${stageTotal.displayText(maximumFractionDigits: 2)}%',
      ),
    ];
  }

  bool get isValid => validate().every((c) => c.ok);

  /// The p_setup payload for v1_save_project_commercial_setup.
  Map<String, Object?> toSetupJson() => {
    'contract_value': contractValue.postgresText,
    'currency_code': currencyCode,
    'vat_rate_percent': vatRatePercent.postgresText,
    if (paymentTermsDays != null) 'payment_terms_days': paymentTermsDays,
    if (reminderLeadDays != null) 'reminder_lead_days': reminderLeadDays,
    'buildings': buildings.map((b) => b.toJson()).toList(growable: false),
    'stages': stages.map((s) => s.toJson()).toList(growable: false),
  };
}

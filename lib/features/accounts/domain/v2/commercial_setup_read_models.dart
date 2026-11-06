/// R39 Accounts Workspace V2 — Contract (commercial setup) read models (P6).
///
/// Typed parse of `v1_get_project_commercial_setup`, which seeds the Contract
/// tab. Monetary fields (contract value, building/stage/item values) are absent
/// — not null-valued — when the caller lacks view_project_commercial_values, so
/// they parse to `null` here and the whole building/stage/item split is empty.
/// Amounts parse through [YorksAccountsDecimal], which rejects JSON numbers.
library;

import '../accounts_decimal.dart';

final class YorksAccountsSetupReadCapabilities {
  const YorksAccountsSetupReadCapabilities({
    required this.viewProjectAccounts,
    required this.viewProjectCommercialValues,
    required this.configureProjectCommercials,
  });

  factory YorksAccountsSetupReadCapabilities.fromJson(
    Map<String, dynamic> json,
  ) {
    return YorksAccountsSetupReadCapabilities(
      viewProjectAccounts: json['view_project_accounts'] == true,
      viewProjectCommercialValues:
          json['view_project_commercial_values'] == true,
      configureProjectCommercials:
          json['configure_project_commercials'] == true,
    );
  }

  final bool viewProjectAccounts;
  final bool viewProjectCommercialValues;
  final bool configureProjectCommercials;
}

final class YorksAccountsSetupReadBuilding {
  const YorksAccountsSetupReadBuilding({
    required this.projectScopeId,
    required this.name,
    required this.scopeKind,
    required this.allocationPercent,
    required this.value,
  });

  factory YorksAccountsSetupReadBuilding.fromJson(Map<String, dynamic> json) {
    return YorksAccountsSetupReadBuilding(
      projectScopeId: json['project_scope_id'] as String,
      name: json['name'] as String? ?? '',
      scopeKind: json['scope_kind'] as String? ?? 'building',
      allocationPercent: YorksAccountsDecimal.fromRpcValue(
        json['allocation_percent'],
        key: 'building.allocation_percent',
      ),
      value: json.containsKey('value')
          ? YorksAccountsDecimal.fromRpcValue(
              json['value'],
              key: 'building.value',
            )
          : null,
    );
  }

  final String projectScopeId;
  final String name;
  final String scopeKind;
  final YorksAccountsDecimal allocationPercent;
  final YorksAccountsDecimal? value;
}

final class YorksAccountsSetupReadStage {
  const YorksAccountsSetupReadStage({
    required this.stageKey,
    required this.stageName,
    required this.displayOrder,
    required this.measurementMode,
    required this.allocationPercent,
    required this.value,
  });

  factory YorksAccountsSetupReadStage.fromJson(Map<String, dynamic> json) {
    return YorksAccountsSetupReadStage(
      stageKey: json['stage_key'] as String,
      stageName: json['stage_name'] as String? ?? '',
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
      measurementMode: json['measurement_mode'] as String? ?? 'percent',
      allocationPercent: YorksAccountsDecimal.fromRpcValue(
        json['allocation_percent'],
        key: 'stage.allocation_percent',
      ),
      value: json.containsKey('value')
          ? YorksAccountsDecimal.fromRpcValue(json['value'], key: 'stage.value')
          : null,
    );
  }

  final String stageKey;
  final String stageName;
  final int displayOrder;
  final String measurementMode;
  final YorksAccountsDecimal allocationPercent;
  final YorksAccountsDecimal? value;

  bool get isItemsMode => measurementMode == 'items';
}

final class YorksAccountsSetupReadItem {
  const YorksAccountsSetupReadItem({
    required this.projectScopeId,
    required this.buildingName,
    required this.stageKey,
    required this.itemKey,
    required this.itemLabel,
    required this.displayOrder,
    required this.quantity,
    required this.unitCode,
    required this.weightPercentOfContract,
    required this.value,
  });

  factory YorksAccountsSetupReadItem.fromJson(Map<String, dynamic> json) {
    return YorksAccountsSetupReadItem(
      projectScopeId: json['project_scope_id'] as String,
      buildingName: json['building_name'] as String? ?? '',
      stageKey: json['stage_key'] as String,
      itemKey: json['item_key'] as String,
      itemLabel: json['item_label'] as String? ?? '',
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
      quantity: YorksAccountsDecimal.fromRpcValue(
        json['quantity'],
        key: 'item.quantity',
      ),
      unitCode: json['unit_code'] as String? ?? '',
      weightPercentOfContract: YorksAccountsDecimal.fromRpcValue(
        json['weight_percent_of_contract'],
        key: 'item.weight_percent_of_contract',
      ),
      value: json.containsKey('value')
          ? YorksAccountsDecimal.fromRpcValue(json['value'], key: 'item.value')
          : null,
    );
  }

  final String projectScopeId;
  final String buildingName;
  final String stageKey;
  final String itemKey;
  final String itemLabel;
  final int displayOrder;
  final YorksAccountsDecimal quantity;
  final String unitCode;
  final YorksAccountsDecimal weightPercentOfContract;
  final YorksAccountsDecimal? value;
}

final class YorksAccountsSetupReadInvoiceSettings {
  const YorksAccountsSetupReadInvoiceSettings({
    required this.invoicePrefix,
    required this.nextSequence,
    required this.scopeLine,
    required this.attentionName,
    required this.billToPartyId,
    required this.recordVersion,
  });

  factory YorksAccountsSetupReadInvoiceSettings.fromJson(
    Map<String, dynamic> json,
  ) {
    return YorksAccountsSetupReadInvoiceSettings(
      invoicePrefix: json['invoice_prefix'] as String? ?? '',
      nextSequence: (json['next_sequence'] as num?)?.toInt() ?? 1,
      scopeLine: json['scope_line'] as String?,
      attentionName: json['attention_name'] as String?,
      billToPartyId: json['bill_to_party_id'] as String?,
      recordVersion: (json['record_version'] as num?)?.toInt() ?? 1,
    );
  }

  final String invoicePrefix;
  final int nextSequence;
  final String? scopeLine;
  final String? attentionName;
  final String? billToPartyId;
  final int recordVersion;

  /// The next invoice number as it will read, e.g. `YRA322-03`.
  String get nextInvoiceNumber =>
      '$invoicePrefix-${nextSequence.toString().padLeft(2, '0')}';
}

/// A contract party (client or main contractor) read from project setup.
final class YorksAccountsSetupReadParty {
  const YorksAccountsSetupReadParty({
    required this.name,
    required this.address,
    required this.contactName,
    required this.contactPhone,
    required this.contactEmail,
  });

  factory YorksAccountsSetupReadParty.fromJson(Map<String, dynamic> json) {
    return YorksAccountsSetupReadParty(
      name: json['name'] as String?,
      address: json['address'] as String?,
      contactName: json['contact_name'] as String?,
      contactPhone: json['contact_phone'] as String?,
      contactEmail: json['contact_email'] as String?,
    );
  }

  final String? name;
  final String? address;
  final String? contactName;
  final String? contactPhone;
  final String? contactEmail;

  /// A single "Name · Phone" / "Name · Email" contact line, or null.
  String? get contactLine {
    final parts = <String>[
      if (contactName != null && contactName!.isNotEmpty) contactName!,
      if (contactPhone != null && contactPhone!.isNotEmpty)
        contactPhone!
      else if (contactEmail != null && contactEmail!.isNotEmpty)
        contactEmail!,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

final class YorksAccountsCommercialSetupRead {
  const YorksAccountsCommercialSetupRead({
    required this.projectId,
    required this.projectReference,
    required this.projectName,
    required this.hasBaseline,
    required this.canConfigure,
    required this.capabilities,
    required this.profileVersion,
    required this.revisionNumber,
    required this.currencyCode,
    required this.contractValue,
    required this.contractInclVat,
    required this.vatRatePercent,
    required this.paymentTermsDays,
    required this.reminderLeadDays,
    required this.invoiceSettings,
    required this.buildings,
    required this.stages,
    required this.items,
    required this.clientParty,
    required this.mainContractorParty,
    required this.clientTrn,
    required this.workOrderNumber,
    required this.workOrderDate,
    required this.contractNumber,
    required this.retentionPercent,
  });

  factory YorksAccountsCommercialSetupRead.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> list(String key) =>
        ((json[key] as List?) ?? const <dynamic>[])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false);
    YorksAccountsDecimal? money(String key) => json.containsKey(key)
        ? YorksAccountsDecimal.fromRpcValue(json[key], key: key)
        : null;
    final settings = json['invoice_settings'];
    final parties = json['parties'] is Map
        ? Map<String, dynamic>.from(json['parties'] as Map)
        : const <String, dynamic>{};
    YorksAccountsSetupReadParty? party(String kind) => parties[kind] is Map
        ? YorksAccountsSetupReadParty.fromJson(
            Map<String, dynamic>.from(parties[kind] as Map),
          )
        : null;
    final refs = json['references'] is Map
        ? Map<String, dynamic>.from(json['references'] as Map)
        : const <String, dynamic>{};
    return YorksAccountsCommercialSetupRead(
      projectId: json['project_id'] as String,
      projectReference: json['project_reference'] as String?,
      projectName: json['project_name'] as String?,
      hasBaseline: json['has_baseline'] == true,
      canConfigure: json['can_configure'] == true,
      capabilities: YorksAccountsSetupReadCapabilities.fromJson(
        Map<String, dynamic>.from(json['capabilities'] as Map),
      ),
      profileVersion: (json['profile_version'] as num?)?.toInt(),
      revisionNumber: (json['revision_number'] as num?)?.toInt(),
      currencyCode: json['currency_code'] as String?,
      contractValue: money('contract_value'),
      contractInclVat: money('contract_incl_vat'),
      vatRatePercent: money('vat_rate_percent'),
      paymentTermsDays: (json['payment_terms_days'] as num?)?.toInt(),
      reminderLeadDays: (json['reminder_lead_days'] as num?)?.toInt(),
      invoiceSettings: settings is Map
          ? YorksAccountsSetupReadInvoiceSettings.fromJson(
              Map<String, dynamic>.from(settings),
            )
          : null,
      buildings: list(
        'buildings',
      ).map(YorksAccountsSetupReadBuilding.fromJson).toList(growable: false),
      stages: list(
        'stages',
      ).map(YorksAccountsSetupReadStage.fromJson).toList(growable: false),
      items: list(
        'items',
      ).map(YorksAccountsSetupReadItem.fromJson).toList(growable: false),
      clientParty: party('client'),
      mainContractorParty: party('main_contractor'),
      clientTrn: refs['client_trn'] as String?,
      workOrderNumber: refs['work_order_number'] as String?,
      workOrderDate: refs['work_order_date'] as String?,
      contractNumber: refs['contract_number'] as String?,
      retentionPercent: refs['retention_percent'] as String?,
    );
  }

  final String projectId;
  final String? projectReference;
  final String? projectName;
  final bool hasBaseline;
  final bool canConfigure;
  final YorksAccountsSetupReadCapabilities capabilities;
  final int? profileVersion;
  final int? revisionNumber;
  final String? currencyCode;

  /// Present only with view_project_commercial_values.
  final YorksAccountsDecimal? contractValue;
  final YorksAccountsDecimal? contractInclVat;
  final YorksAccountsDecimal? vatRatePercent;
  final int? paymentTermsDays;
  final int? reminderLeadDays;
  final YorksAccountsSetupReadInvoiceSettings? invoiceSettings;
  final List<YorksAccountsSetupReadBuilding> buildings;
  final List<YorksAccountsSetupReadStage> stages;
  final List<YorksAccountsSetupReadItem> items;

  /// Contract parties from project setup (read-only); null when not set.
  final YorksAccountsSetupReadParty? clientParty;
  final YorksAccountsSetupReadParty? mainContractorParty;

  /// Editable contract references (stored on the profile).
  final String? clientTrn;
  final String? workOrderNumber;
  final String? workOrderDate;
  final String? contractNumber;

  /// Retention percent (display only; decimal string) or null.
  final String? retentionPercent;

  bool get hasCommercialValues =>
      capabilities.viewProjectCommercialValues && contractValue != null;

  static YorksAccountsDecimal _sum(Iterable<YorksAccountsDecimal> xs) =>
      xs.fold(YorksAccountsDecimal.zero, (a, b) => a + b);

  YorksAccountsDecimal get buildingTotalPercent =>
      _sum(buildings.map((b) => b.allocationPercent));
  YorksAccountsDecimal get stageTotalPercent =>
      _sum(stages.map((s) => s.allocationPercent));

  bool get buildingsHundred =>
      buildings.isNotEmpty &&
      buildingTotalPercent == YorksAccountsDecimal.hundred;
  bool get stagesHundred =>
      stages.isNotEmpty && stageTotalPercent == YorksAccountsDecimal.hundred;

  /// Items for one items-mode stage, in building then display order.
  List<YorksAccountsSetupReadItem> itemsForStage(String stageKey) =>
      items.where((i) => i.stageKey == stageKey).toList(growable: false);
}

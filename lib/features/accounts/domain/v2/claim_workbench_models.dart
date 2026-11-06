/// R39 Accounts Workspace V2 — claim workbench projection models (P5).
///
/// Typed parse of `v1_get_claim_workbench`: every building × stage cell of the
/// current baseline (with its items for items-mode stages) and the current open
/// claim. Monetary fields (stage value, eligible, claimed, available, item
/// value) arrive as decimal strings and are absent without
/// view_project_commercial_values, so they parse to `null`. Quantities and
/// percentages are exact decimals too.
library;

import '../accounts_decimal.dart';

/// One item row inside an items-mode cell.
final class YorksAccountsWorkbenchItem {
  const YorksAccountsWorkbenchItem({
    required this.stageItemId,
    required this.itemKey,
    required this.itemLabel,
    required this.displayOrder,
    required this.quantity,
    required this.unitCode,
    required this.confirmedQty,
    required this.needsReview,
    required this.itemValue,
  });

  factory YorksAccountsWorkbenchItem.fromJson(Map<String, dynamic> json) {
    return YorksAccountsWorkbenchItem(
      stageItemId: json['stage_item_id'] as String,
      itemKey: json['item_key'] as String,
      itemLabel: json['item_label'] as String,
      displayOrder: (json['display_order'] as num).toInt(),
      quantity: YorksAccountsDecimal.fromRpcValue(json['quantity'], key: 'item.quantity'),
      unitCode: json['unit_code'] as String,
      confirmedQty:
          YorksAccountsDecimal.fromRpcValue(json['confirmed_qty'], key: 'item.confirmed_qty'),
      needsReview: json['needs_review'] == true,
      itemValue: json.containsKey('item_value')
          ? YorksAccountsDecimal.fromRpcValue(json['item_value'], key: 'item.item_value')
          : null,
    );
  }

  final String stageItemId;
  final String itemKey;
  final String itemLabel;
  final int displayOrder;
  final YorksAccountsDecimal quantity;
  final String unitCode;
  final YorksAccountsDecimal confirmedQty;
  final bool needsReview;

  /// Present only with view_project_commercial_values.
  final YorksAccountsDecimal? itemValue;
}

/// One building × stage cell.
final class YorksAccountsWorkbenchCell {
  const YorksAccountsWorkbenchCell({
    required this.progressEntryId,
    required this.buildingScopeId,
    required this.buildingName,
    required this.stageKey,
    required this.stageLabel,
    required this.stagePosition,
    required this.measurementMode,
    required this.confirmedPercent,
    required this.reviewStatus,
    required this.recordVersion,
    required this.stageValue,
    required this.eligible,
    required this.claimed,
    required this.available,
    required this.overClaimed,
    required this.items,
  });

  factory YorksAccountsWorkbenchCell.fromJson(Map<String, dynamic> json) {
    YorksAccountsDecimal? money(String key) => json.containsKey(key)
        ? YorksAccountsDecimal.fromRpcValue(json[key], key: 'cell.$key')
        : null;
    final items = (json['items'] as List?)
        ?.map((e) => YorksAccountsWorkbenchItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false);
    return YorksAccountsWorkbenchCell(
      progressEntryId: json['progress_entry_id'] as String,
      buildingScopeId: json['building_scope_id'] as String,
      buildingName: json['building_name'] as String,
      stageKey: json['stage_key'] as String,
      stageLabel: json['stage_label'] as String?,
      stagePosition: (json['stage_position'] as num).toInt(),
      measurementMode: json['measurement_mode'] as String,
      confirmedPercent: YorksAccountsDecimal.fromRpcValue(
        json['confirmed_percent'], key: 'cell.confirmed_percent'),
      reviewStatus: json['review_status'] as String,
      recordVersion: (json['record_version'] as num).toInt(),
      stageValue: money('stage_value'),
      eligible: money('eligible'),
      claimed: money('claimed'),
      available: money('available'),
      overClaimed: json['over_claimed'] == true,
      items: items ?? const <YorksAccountsWorkbenchItem>[],
    );
  }

  final String progressEntryId;
  final String buildingScopeId;
  final String buildingName;
  final String stageKey;
  final String? stageLabel;
  final int stagePosition;

  /// 'percent' or 'items'.
  final String measurementMode;
  final YorksAccountsDecimal confirmedPercent;
  final String reviewStatus;
  final int recordVersion;

  // Present only with view_project_commercial_values.
  final YorksAccountsDecimal? stageValue;
  final YorksAccountsDecimal? eligible;
  final YorksAccountsDecimal? claimed;
  final YorksAccountsDecimal? available;
  final bool overClaimed;

  final List<YorksAccountsWorkbenchItem> items;

  bool get isItemsMode => measurementMode == 'items';
}

/// The claim workbench projection.
final class YorksAccountsWorkbench {
  const YorksAccountsWorkbench({
    required this.projectId,
    required this.baselineRevisionId,
    required this.baselineRevisionNumber,
    required this.cells,
    required this.claim,
    required this.capabilities,
    required this.commands,
  });

  factory YorksAccountsWorkbench.fromJson(Map<String, dynamic> json) {
    return YorksAccountsWorkbench(
      projectId: json['project_id'] as String,
      baselineRevisionId: json['baseline_revision_id'] as String?,
      baselineRevisionNumber: (json['baseline_revision_number'] as num?)?.toInt(),
      cells: ((json['cells'] as List?) ?? const <dynamic>[])
          .map((e) => YorksAccountsWorkbenchCell.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false),
      claim: json['claim'] is Map ? Map<String, dynamic>.from(json['claim'] as Map) : null,
      capabilities: json['capabilities'] is Map
          ? Map<String, dynamic>.from(json['capabilities'] as Map)
          : const <String, dynamic>{},
      commands: json['commands'] is Map
          ? Map<String, dynamic>.from(json['commands'] as Map)
          : const <String, dynamic>{},
    );
  }

  final String projectId;
  final String? baselineRevisionId;
  final int? baselineRevisionNumber;
  final List<YorksAccountsWorkbenchCell> cells;

  /// The current open claim snapshot, or null when none is open.
  final Map<String, dynamic>? claim;
  final Map<String, dynamic> capabilities;
  final Map<String, dynamic> commands;

  /// `capabilities` is the server's `v1_accounts_capability_envelope`; `commands`
  /// is `v1_accounts_receivables_commands`. Read their keys only through these
  /// getters, so a key name lives in one place.
  bool get canViewValues => capabilities['can_view_values'] == true;
  bool get canConfirmProgress => capabilities['can_confirm'] == true;
  bool get canManageInvoices => commands['submit_invoice'] == true;
  bool get canPrepareClaim => commands['create_claim_draft'] == true;

  String? get openClaimId => claim == null ? null : claim!['claim_id'] as String?;
  String? get openClaimStatus => claim == null ? null : claim!['status'] as String?;
}

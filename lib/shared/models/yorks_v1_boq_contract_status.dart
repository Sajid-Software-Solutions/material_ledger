/// Contract materials — a BOQ folder's contract line status
/// (PRODUCT_DECISIONS.md section 61).
///
/// Typed parse of `v1_get_boq_contract_status`: for each BOQ row tied to a
/// contract line, what Material Requests asked for and what reached site;
/// then, for someone who may read project Accounts, what is confirmed
/// delivered and installed; then, for someone who may see contract values,
/// the line's rate and amount. The server leaves out what the caller may not
/// see, so those fields are nullable. Quantities and money stay exact decimal
/// strings; the screen formats them for display only.
library;

final class YorksV1BoqContractStageStatus {
  const YorksV1BoqContractStageStatus({
    required this.stageKey,
    required this.stageLabel,
    required this.quantity,
    required this.unitCode,
    required this.confirmedQty,
    this.amount,
    this.rate,
  });

  factory YorksV1BoqContractStageStatus.fromJson(Map<String, dynamic> json) =>
      YorksV1BoqContractStageStatus(
        stageKey: json['stage_key'] as String,
        stageLabel: json['stage_label'] as String? ?? '',
        quantity: '${json['quantity'] ?? '0'}',
        unitCode: json['unit_code'] as String? ?? '',
        confirmedQty: '${json['confirmed_qty'] ?? '0'}',
        amount: json['amount'] == null ? null : '${json['amount']}',
        rate: json['rate'] == null ? null : '${json['rate']}',
      );

  final String stageKey;
  final String stageLabel;
  final String quantity;
  final String unitCode;
  final String confirmedQty;

  /// Only for someone who may see contract values.
  final String? amount;
  final String? rate;
}

final class YorksV1BoqContractRowStatus {
  const YorksV1BoqContractRowStatus({
    required this.boqRowId,
    required this.projectScopeId,
    required this.itemKey,
    required this.requestedQty,
    required this.receivedQty,
    required this.deliveries,
    this.lastDeliveryReference,
    this.lastDeliveryDate,
    this.stages,
  });

  factory YorksV1BoqContractRowStatus.fromJson(Map<String, dynamic> json) {
    final stages = json['stages'];
    return YorksV1BoqContractRowStatus(
      boqRowId: json['boq_row_id'] as String,
      projectScopeId: json['project_scope_id'] as String? ?? '',
      itemKey: json['item_key'] as String? ?? '',
      requestedQty: '${json['requested_qty'] ?? '0'}',
      receivedQty: '${json['received_qty'] ?? '0'}',
      deliveries: (json['deliveries'] as num?)?.toInt() ?? 0,
      lastDeliveryReference: json['last_delivery_reference'] as String?,
      lastDeliveryDate: json['last_delivery_date'] as String?,
      stages: stages is List
          ? [
              for (final s in stages)
                YorksV1BoqContractStageStatus.fromJson(
                  Map<String, dynamic>.from(s as Map),
                ),
            ]
          : null,
    );
  }

  final String boqRowId;
  final String projectScopeId;
  final String itemKey;

  /// Submitted, non-cancelled Material Requests raised from the row.
  final String requestedQty;

  /// Good quantity on confirmed receipts, less confirmed returns.
  final String receivedQty;
  final int deliveries;
  final String? lastDeliveryReference;
  final String? lastDeliveryDate;

  /// Null when the caller may not read project Accounts.
  final List<YorksV1BoqContractStageStatus>? stages;

  YorksV1BoqContractStageStatus? stage(String stageKey) {
    for (final s in stages ?? const <YorksV1BoqContractStageStatus>[]) {
      if (s.stageKey == stageKey) return s;
    }
    return null;
  }
}

final class YorksV1BoqContractStatus {
  const YorksV1BoqContractStatus({
    required this.groupId,
    required this.canViewProgress,
    required this.canViewValues,
    required this.rows,
    this.currencyCode,
  });

  factory YorksV1BoqContractStatus.fromJson(Map<String, dynamic> json) =>
      YorksV1BoqContractStatus(
        groupId: json['group_id'] as String? ?? '',
        canViewProgress: json['can_view_progress'] == true,
        canViewValues: json['can_view_values'] == true,
        currencyCode: json['currency_code'] as String?,
        rows: [
          for (final r in (json['rows'] as List?) ?? const <dynamic>[])
            YorksV1BoqContractRowStatus.fromJson(
              Map<String, dynamic>.from(r as Map),
            ),
        ],
      );

  final String groupId;
  final bool canViewProgress;
  final bool canViewValues;
  final String? currencyCode;
  final List<YorksV1BoqContractRowStatus> rows;

  bool get isEmpty => rows.isEmpty;

  YorksV1BoqContractRowStatus? row(String boqRowId) {
    for (final r in rows) {
      if (r.boqRowId == boqRowId) return r;
    }
    return null;
  }
}

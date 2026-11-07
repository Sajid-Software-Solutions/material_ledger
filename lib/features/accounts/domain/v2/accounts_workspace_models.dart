/// R39 Accounts Workspace V2 — Summary projection models (P5).
///
/// Typed parse of `v1_get_project_accounts_workspace`. Monetary and percent
/// fields arrive as decimal strings and are parsed through
/// [YorksAccountsDecimal], which rejects JSON numbers so a binary double can
/// never become a commercial value. Monetary / supplier blocks are absent (not
/// null-valued) when the caller lacks the matching capability, so they parse to
/// `null` here.
library;

import '../accounts_decimal.dart';

/// Capability flags the server resolved for the current actor on this project.
final class YorksAccountsWorkspaceCapabilities {
  const YorksAccountsWorkspaceCapabilities({
    required this.viewProjectAccounts,
    required this.viewProjectCommercialValues,
    required this.viewSupplierCosts,
  });

  factory YorksAccountsWorkspaceCapabilities.fromJson(
    Map<String, dynamic> json,
  ) {
    return YorksAccountsWorkspaceCapabilities(
      viewProjectAccounts: json['view_project_accounts'] == true,
      viewProjectCommercialValues:
          json['view_project_commercial_values'] == true,
      viewSupplierCosts: json['view_supplier_costs'] == true,
    );
  }

  final bool viewProjectAccounts;
  final bool viewProjectCommercialValues;
  final bool viewSupplierCosts;
}

/// One entry in the four-step strip (setup / progress / invoice / paid).
final class YorksAccountsWorkspaceStep {
  const YorksAccountsWorkspaceStep({
    required this.key,
    required this.state,
    this.detail,
  });

  factory YorksAccountsWorkspaceStep.fromJson(Map<String, dynamic> json) {
    return YorksAccountsWorkspaceStep(
      key: json['key'] as String,
      state: (json['state'] as String?) ?? '',
      detail: json['detail'] is Map
          ? YorksAccountsWorkspaceStepDetail.fromJson(
              Map<String, dynamic>.from(json['detail'] as Map),
            )
          : null,
    );
  }

  final String key;

  /// 'done', 'current' or '' (pending).
  final String state;

  /// Status figures under the step label. Present only with
  /// view_project_commercial_values; `null` renders the step label-only.
  final YorksAccountsWorkspaceStepDetail? detail;

  bool get isDone => state == 'done';
  bool get isCurrent => state == 'current';
}

/// The second line of a step tile: figures that differ per step key. Every
/// field is nullable — only the ones relevant to the step (and present in the
/// gated projection) are populated.
final class YorksAccountsWorkspaceStepDetail {
  const YorksAccountsWorkspaceStepDetail({
    this.contractValue,
    this.buildingCount,
    this.stageCount,
    this.claimReference,
    this.claimGross,
    this.issuedCount,
    this.latestReference,
    this.received,
    this.toCome,
  });

  factory YorksAccountsWorkspaceStepDetail.fromJson(Map<String, dynamic> json) {
    YorksAccountsDecimal? dec(String key) => json[key] == null
        ? null
        : YorksAccountsDecimal.fromRpcValue(json[key], key: 'step.detail.$key');
    int? count(String key) => (json[key] as num?)?.toInt();
    return YorksAccountsWorkspaceStepDetail(
      contractValue: dec('contract_value'),
      buildingCount: count('building_count'),
      stageCount: count('stage_count'),
      claimReference: json['claim_reference'] as String?,
      claimGross: dec('claim_gross'),
      issuedCount: count('issued_count'),
      latestReference: json['latest_reference'] as String?,
      received: dec('received'),
      toCome: dec('to_come'),
    );
  }

  final YorksAccountsDecimal? contractValue;
  final int? buildingCount;
  final int? stageCount;
  final String? claimReference;
  final YorksAccountsDecimal? claimGross;
  final int? issuedCount;
  final String? latestReference;
  final YorksAccountsDecimal? received;
  final YorksAccountsDecimal? toCome;
}

/// Small counts/flags the tab bar renders as badges.
final class YorksAccountsWorkspaceBadges {
  const YorksAccountsWorkspaceBadges({
    required this.claimsDraft,
    required this.supplierCount,
  });

  factory YorksAccountsWorkspaceBadges.fromJson(Map<String, dynamic> json) {
    return YorksAccountsWorkspaceBadges(
      claimsDraft: json['claims_draft'] == true,
      supplierCount: (json['supplier_count'] as num?)?.toInt(),
    );
  }

  static const empty = YorksAccountsWorkspaceBadges(
    claimsDraft: false,
    supplierCount: null,
  );

  /// An open draft claim exists → `Draft` badge on Progress & claims.
  final bool claimsDraft;

  /// Overdue supplier-bill count (view_supplier_costs only; `null` otherwise).
  final int? supplierCount;
}

/// A server-derived "needs attention" item with a routable target.
final class YorksAccountsWorkspaceAttention {
  const YorksAccountsWorkspaceAttention({
    required this.severity,
    required this.kind,
    required this.actionKey,
    required this.targetType,
    required this.targetId,
    required this.params,
  });

  factory YorksAccountsWorkspaceAttention.fromJson(Map<String, dynamic> json) {
    return YorksAccountsWorkspaceAttention(
      severity: json['severity'] as String,
      kind: json['kind'] as String,
      actionKey: json['action_key'] as String?,
      targetType: json['target_type'] as String?,
      targetId: json['target_id'] as String?,
      params: json['params'] is Map
          ? Map<String, dynamic>.from(json['params'] as Map)
          : const <String, dynamic>{},
    );
  }

  /// 'bad' | 'warn' | 'pri' | 'ok'.
  final String severity;
  final String kind;
  final String? actionKey;
  final String? targetType;
  final String? targetId;
  final Map<String, dynamic> params;
}

/// Ex-VAT split of the whole contract value for the money-flow bar.
final class YorksAccountsWorkspaceMoneyFlow {
  const YorksAccountsWorkspaceMoneyFlow({
    required this.paid,
    required this.invoicedWaiting,
    required this.doneNotInvoiced,
    required this.remaining,
  });

  factory YorksAccountsWorkspaceMoneyFlow.fromJson(Map<String, dynamic> json) {
    return YorksAccountsWorkspaceMoneyFlow(
      paid: YorksAccountsDecimal.fromRpcValue(
        json['paid'],
        key: 'money_flow.paid',
      ),
      invoicedWaiting: YorksAccountsDecimal.fromRpcValue(
        json['invoiced_waiting'],
        key: 'money_flow.invoiced_waiting',
      ),
      doneNotInvoiced: YorksAccountsDecimal.fromRpcValue(
        json['done_not_invoiced'],
        key: 'money_flow.done_not_invoiced',
      ),
      remaining: YorksAccountsDecimal.fromRpcValue(
        json['remaining'],
        key: 'money_flow.remaining',
      ),
    );
  }

  final YorksAccountsDecimal paid;
  final YorksAccountsDecimal invoicedWaiting;
  final YorksAccountsDecimal doneNotInvoiced;
  final YorksAccountsDecimal remaining;
}

/// Summary KPI tiles (all ex-VAT unless noted; VAT-inclusive contract separate).
final class YorksAccountsWorkspaceKpis {
  const YorksAccountsWorkspaceKpis({
    required this.contractValue,
    required this.contractInclVat,
    required this.invoiced,
    required this.received,
    required this.certified,
    required this.outstanding,
    required this.chequesInHand,
    required this.doneNotInvoiced,
  });

  factory YorksAccountsWorkspaceKpis.fromJson(Map<String, dynamic> json) {
    YorksAccountsDecimal field(String key) =>
        YorksAccountsDecimal.fromRpcValue(json[key], key: 'kpis.$key');
    return YorksAccountsWorkspaceKpis(
      contractValue: field('contract_value'),
      contractInclVat: field('contract_incl_vat'),
      invoiced: field('invoiced'),
      received: field('received'),
      certified: field('certified'),
      outstanding: field('outstanding'),
      chequesInHand: field('cheques_in_hand'),
      doneNotInvoiced: field('done_not_invoiced'),
    );
  }

  final YorksAccountsDecimal contractValue;
  final YorksAccountsDecimal contractInclVat;
  final YorksAccountsDecimal invoiced;
  final YorksAccountsDecimal received;
  final YorksAccountsDecimal certified;
  final YorksAccountsDecimal outstanding;
  final YorksAccountsDecimal chequesInHand;
  final YorksAccountsDecimal doneNotInvoiced;
}

/// One building × stage heatmap cell (invoiced % of the stage value).
final class YorksAccountsWorkspaceHeatmapCell {
  const YorksAccountsWorkspaceHeatmapCell({
    required this.buildingScopeId,
    required this.buildingName,
    required this.stageKey,
    required this.stageLabel,
    required this.stageValue,
    required this.invoicedAmount,
    required this.invoicedPercent,
  });

  factory YorksAccountsWorkspaceHeatmapCell.fromJson(
    Map<String, dynamic> json,
  ) {
    return YorksAccountsWorkspaceHeatmapCell(
      buildingScopeId: json['building_scope_id'] as String,
      buildingName: json['building_name'] as String,
      stageKey: json['stage_key'] as String,
      stageLabel: json['stage_label'] as String?,
      stageValue: YorksAccountsDecimal.fromRpcValue(
        json['stage_value'],
        key: 'heatmap.stage_value',
      ),
      invoicedAmount: YorksAccountsDecimal.fromRpcValue(
        json['invoiced_amount'],
        key: 'heatmap.invoiced_amount',
      ),
      invoicedPercent: YorksAccountsDecimal.fromRpcValue(
        json['invoiced_percent'],
        key: 'heatmap.invoiced_percent',
      ),
    );
  }

  final String buildingScopeId;
  final String buildingName;
  final String stageKey;
  final String? stageLabel;
  final YorksAccountsDecimal stageValue;
  final YorksAccountsDecimal invoicedAmount;
  final YorksAccountsDecimal invoicedPercent;
}

/// Supplier summary tile (gated by view_supplier_costs).
final class YorksAccountsWorkspaceSupplier {
  const YorksAccountsWorkspaceSupplier({
    required this.billed,
    required this.paid,
    required this.unpaid,
    required this.overdueCount,
  });

  factory YorksAccountsWorkspaceSupplier.fromJson(Map<String, dynamic> json) {
    return YorksAccountsWorkspaceSupplier(
      billed: YorksAccountsDecimal.fromRpcValue(
        json['billed'],
        key: 'supplier.billed',
      ),
      paid: YorksAccountsDecimal.fromRpcValue(
        json['paid'],
        key: 'supplier.paid',
      ),
      unpaid: YorksAccountsDecimal.fromRpcValue(
        json['unpaid'],
        key: 'supplier.unpaid',
      ),
      overdueCount: (json['overdue_count'] as num).toInt(),
    );
  }

  final YorksAccountsDecimal billed;
  final YorksAccountsDecimal paid;
  final YorksAccountsDecimal unpaid;
  final int overdueCount;
}

/// Cash position (gated by view_supplier_costs).
final class YorksAccountsWorkspaceCash {
  const YorksAccountsWorkspaceCash({
    required this.received,
    required this.paidToSuppliers,
    required this.net,
  });

  factory YorksAccountsWorkspaceCash.fromJson(Map<String, dynamic> json) {
    return YorksAccountsWorkspaceCash(
      received: YorksAccountsDecimal.fromRpcValue(
        json['received'],
        key: 'cash.received',
      ),
      paidToSuppliers: YorksAccountsDecimal.fromRpcValue(
        json['paid_to_suppliers'],
        key: 'cash.paid_to_suppliers',
      ),
      net: YorksAccountsDecimal.fromRpcValue(json['net'], key: 'cash.net'),
    );
  }

  final YorksAccountsDecimal received;
  final YorksAccountsDecimal paidToSuppliers;
  final YorksAccountsDecimal net;
}

/// The full Summary workspace projection.
final class YorksAccountsWorkspace {
  const YorksAccountsWorkspace({
    required this.projectId,
    required this.projectReference,
    required this.projectName,
    required this.hasBaseline,
    required this.capabilities,
    required this.steps,
    required this.badges,
    required this.attention,
    required this.moneyFlow,
    required this.kpis,
    required this.heatmap,
    required this.supplier,
    required this.cash,
  });

  factory YorksAccountsWorkspace.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> list(String key) =>
        ((json[key] as List?) ?? const <dynamic>[])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false);
    final money = json['money_flow'] is Map
        ? Map<String, dynamic>.from(json['money_flow'] as Map)
        : null;
    final kpis = json['kpis'] is Map
        ? Map<String, dynamic>.from(json['kpis'] as Map)
        : null;
    final supplier = json['supplier'] is Map
        ? Map<String, dynamic>.from(json['supplier'] as Map)
        : null;
    final cash = json['cash'] is Map
        ? Map<String, dynamic>.from(json['cash'] as Map)
        : null;
    return YorksAccountsWorkspace(
      projectId: json['project_id'] as String,
      projectReference: json['project_reference'] as String?,
      projectName: json['project_name'] as String?,
      hasBaseline: json['has_baseline'] == true,
      capabilities: YorksAccountsWorkspaceCapabilities.fromJson(
        Map<String, dynamic>.from(json['capabilities'] as Map),
      ),
      steps: list(
        'steps',
      ).map(YorksAccountsWorkspaceStep.fromJson).toList(growable: false),
      badges: json['badges'] is Map
          ? YorksAccountsWorkspaceBadges.fromJson(
              Map<String, dynamic>.from(json['badges'] as Map),
            )
          : YorksAccountsWorkspaceBadges.empty,
      attention: list(
        'attention',
      ).map(YorksAccountsWorkspaceAttention.fromJson).toList(growable: false),
      moneyFlow: money == null
          ? null
          : YorksAccountsWorkspaceMoneyFlow.fromJson(money),
      kpis: kpis == null ? null : YorksAccountsWorkspaceKpis.fromJson(kpis),
      heatmap: list(
        'heatmap',
      ).map(YorksAccountsWorkspaceHeatmapCell.fromJson).toList(growable: false),
      supplier: supplier == null
          ? null
          : YorksAccountsWorkspaceSupplier.fromJson(supplier),
      cash: cash == null ? null : YorksAccountsWorkspaceCash.fromJson(cash),
    );
  }

  final String projectId;
  final String? projectReference;
  final String? projectName;
  final bool hasBaseline;
  final YorksAccountsWorkspaceCapabilities capabilities;
  final List<YorksAccountsWorkspaceStep> steps;
  final YorksAccountsWorkspaceBadges badges;
  final List<YorksAccountsWorkspaceAttention> attention;

  /// Present only with view_project_commercial_values.
  final YorksAccountsWorkspaceMoneyFlow? moneyFlow;
  final YorksAccountsWorkspaceKpis? kpis;
  final List<YorksAccountsWorkspaceHeatmapCell> heatmap;

  /// Present only with view_supplier_costs.
  final YorksAccountsWorkspaceSupplier? supplier;
  final YorksAccountsWorkspaceCash? cash;
}

/// R39 Accounts Workspace V2 — Material Supply items linked to BOQ folders.
///
/// Typed parse of `v1_get_accounts_material_sources`: each physical
/// building's linkable BOQ folders (never Common / All Buildings, Workshop
/// Materials or an archived folder), the saved links, and per linked item what
/// has been delivered to site. Quantities and delivery references only;
/// nothing commercial. Delivered quantities suggest progress; the engineer
/// still confirms it on the workbench.
library;

import '../accounts_decimal.dart';

/// One BOQ folder of a physical building that an item may stand for.
final class YorksAccountsBoqFolder {
  const YorksAccountsBoqFolder({
    required this.boqGroupId,
    required this.projectScopeId,
    required this.name,
    required this.templateKey,
    required this.rowCount,
    required this.unit,
    required this.quantity,
  });

  factory YorksAccountsBoqFolder.fromJson(Map<String, dynamic> json) {
    return YorksAccountsBoqFolder(
      boqGroupId: json['boq_group_id'] as String,
      projectScopeId: json['project_scope_id'] as String,
      name: json['name'] as String? ?? '',
      templateKey: json['template_key'] as String?,
      rowCount: (json['row_count'] as num?)?.toInt() ?? 0,
      unit: json['unit'] as String?,
      quantity: json['quantity'] == null
          ? null
          : YorksAccountsDecimal.tryParse('${json['quantity']}'),
    );
  }

  final String boqGroupId;
  final String projectScopeId;
  final String name;
  final String? templateKey;
  final int rowCount;

  /// The rows' unit when they all share one, otherwise null.
  final String? unit;

  /// The rows' total when they share a unit, otherwise null.
  final YorksAccountsDecimal? quantity;
}

/// A saved link: [boqGroupId] stands for an item of a stage in a building.
final class YorksAccountsMaterialLink {
  const YorksAccountsMaterialLink({
    required this.projectScopeId,
    required this.stageKey,
    required this.itemKey,
    required this.boqGroupId,
  });

  factory YorksAccountsMaterialLink.fromJson(Map<String, dynamic> json) {
    return YorksAccountsMaterialLink(
      projectScopeId: json['project_scope_id'] as String,
      stageKey: json['stage_key'] as String,
      itemKey: json['item_key'] as String,
      boqGroupId: json['boq_group_id'] as String,
    );
  }

  final String projectScopeId;
  final String stageKey;
  final String itemKey;
  final String boqGroupId;

  Map<String, Object?> toJson() => {
    'project_scope_id': projectScopeId,
    'stage_key': stageKey,
    'item_key': itemKey,
    'boq_group_id': boqGroupId,
  };

  @override
  bool operator ==(Object other) =>
      other is YorksAccountsMaterialLink &&
      other.projectScopeId == projectScopeId &&
      other.stageKey == stageKey &&
      other.itemKey == itemKey &&
      other.boqGroupId == boqGroupId;

  @override
  int get hashCode =>
      Object.hash(projectScopeId, stageKey, itemKey, boqGroupId);
}

/// What has reached site for one linked item of one building.
final class YorksAccountsItemDelivered {
  const YorksAccountsItemDelivered({
    required this.projectScopeId,
    required this.stageKey,
    required this.itemKey,
    required this.basis,
    required this.deliveredQty,
    required this.deliveries,
    required this.lastDeliveryReference,
    required this.lastDeliveryDate,
  });

  factory YorksAccountsItemDelivered.fromJson(Map<String, dynamic> json) {
    return YorksAccountsItemDelivered(
      projectScopeId: json['project_scope_id'] as String,
      stageKey: json['stage_key'] as String,
      itemKey: json['item_key'] as String,
      basis: json['basis'] as String? ?? 'quantity',
      deliveredQty: YorksAccountsDecimal.fromRpcValue(
        json['delivered_qty'],
        key: 'delivered.delivered_qty',
      ),
      deliveries: (json['deliveries'] as num?)?.toInt() ?? 0,
      lastDeliveryReference: json['last_delivery_reference'] as String?,
      lastDeliveryDate: json['last_delivery_date'] as String?,
    );
  }

  final String projectScopeId;
  final String stageKey;
  final String itemKey;

  /// 'quantity' when the BOQ rows share the item's unit and add up;
  /// 'share' when the item gets the share of its BOQ rows delivered.
  final String basis;

  /// In the item's own unit, never more than the server worked out; the
  /// screen still caps it at the item's quantity.
  final YorksAccountsDecimal deliveredQty;
  final int deliveries;
  final String? lastDeliveryReference;
  final String? lastDeliveryDate;

  bool get isShare => basis == 'share';
}

/// The whole read: folders, links and deliveries, plus whether the actor may
/// change the links.
final class YorksAccountsMaterialSources {
  const YorksAccountsMaterialSources({
    required this.canLink,
    required this.folders,
    required this.links,
    required this.delivered,
  });

  factory YorksAccountsMaterialSources.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) parse) {
      final raw = (json[key] as List?) ?? const <dynamic>[];
      return raw
          .map((e) => parse(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
    }

    return YorksAccountsMaterialSources(
      canLink: json['can_link'] == true,
      folders: list('folders', YorksAccountsBoqFolder.fromJson),
      links: list('links', YorksAccountsMaterialLink.fromJson),
      delivered: list('delivered', YorksAccountsItemDelivered.fromJson),
    );
  }

  static const empty = YorksAccountsMaterialSources(
    canLink: false,
    folders: <YorksAccountsBoqFolder>[],
    links: <YorksAccountsMaterialLink>[],
    delivered: <YorksAccountsItemDelivered>[],
  );

  final bool canLink;
  final List<YorksAccountsBoqFolder> folders;
  final List<YorksAccountsMaterialLink> links;
  final List<YorksAccountsItemDelivered> delivered;

  List<YorksAccountsBoqFolder> foldersFor(String projectScopeId) => folders
      .where((f) => f.projectScopeId == projectScopeId)
      .toList(growable: false);

  /// The folders linked to an item in a building.
  List<YorksAccountsBoqFolder> linkedFolders(
    String projectScopeId,
    String stageKey,
    String itemKey,
  ) {
    final ids = links
        .where(
          (l) =>
              l.projectScopeId == projectScopeId &&
              l.stageKey == stageKey &&
              l.itemKey == itemKey,
        )
        .map((l) => l.boqGroupId)
        .toSet();
    return folders
        .where((f) => ids.contains(f.boqGroupId))
        .toList(growable: false);
  }

  YorksAccountsItemDelivered? deliveredFor(
    String projectScopeId,
    String stageKey,
    String itemKey,
  ) {
    for (final d in delivered) {
      if (d.projectScopeId == projectScopeId &&
          d.stageKey == stageKey &&
          d.itemKey == itemKey) {
        return d;
      }
    }
    return null;
  }

  bool get hasFolders => folders.isNotEmpty;
}

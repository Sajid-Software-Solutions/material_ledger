import 'yorks_v1_logistics.dart';

class YorksV1InventoryHistoryQuery {
  const YorksV1InventoryHistoryQuery({
    this.itemId,
    this.search = '',
    this.kind = 'all',
    this.fromAt,
    this.untilAt,
    this.beforeAt,
    this.beforeId,
    this.limit = 50,
  });
  final String? itemId;
  final String search;
  final String kind;
  final DateTime? fromAt;
  final DateTime? untilAt;
  final DateTime? beforeAt;
  final String? beforeId;
  final int limit;

  Map<String, Object?> toRpc() => {
    'p_item_id': itemId,
    'p_search': search,
    'p_kind': kind,
    'p_before_at': beforeAt?.toUtc().toIso8601String(),
    'p_before_id': beforeId,
    'p_limit': limit,
    'p_from_at': fromAt?.toUtc().toIso8601String(),
    'p_until_at': untilAt?.toUtc().toIso8601String(),
  };
  YorksV1InventoryHistoryQuery after(YorksV1InventoryMovement row) =>
      YorksV1InventoryHistoryQuery(
        itemId: itemId,
        search: search,
        kind: kind,
        fromAt: fromAt,
        untilAt: untilAt,
        beforeAt: row.createdAt,
        beforeId: row.id,
        limit: limit,
      );

  @override
  bool operator ==(Object other) =>
      other is YorksV1InventoryHistoryQuery &&
      itemId == other.itemId &&
      search == other.search &&
      kind == other.kind &&
      fromAt == other.fromAt &&
      untilAt == other.untilAt &&
      beforeAt == other.beforeAt &&
      beforeId == other.beforeId &&
      limit == other.limit;
  @override
  int get hashCode => Object.hash(
    itemId,
    search,
    kind,
    fromAt,
    untilAt,
    beforeAt,
    beforeId,
    limit,
  );
}

class YorksV1InventoryHistoryPage {
  const YorksV1InventoryHistoryPage({
    required this.items,
    required this.hasMore,
  });
  final List<YorksV1InventoryMovement> items;
  final bool hasMore;
  factory YorksV1InventoryHistoryPage.fromJson(Map<String, dynamic> json) =>
      YorksV1InventoryHistoryPage(
        items: [
          for (final row in json['items'] as List)
            YorksV1InventoryMovement.fromRpcJson(
              Map<String, dynamic>.from(row as Map),
            ),
        ],
        hasMore: json['has_more'] == true,
      );
}

abstract interface class YorksV1InventoryHistoryRepository {
  Future<YorksV1InventoryHistoryPage> getInventoryHistory(
    YorksV1InventoryHistoryQuery query,
  );
}

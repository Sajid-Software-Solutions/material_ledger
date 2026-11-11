import 'yorks_v1_logistics.dart';

class YorksV1InventoryRegisterQuery {
  const YorksV1InventoryRegisterQuery({
    this.register = 'stock',
    this.search = '',
    this.status = 'all',
    this.unit,
    this.categoryId,
    this.offset = 0,
    this.limit = 50,
  });
  final String register;
  final String search;
  final String status;
  final String? unit;
  final String? categoryId;
  final int offset;
  final int limit;
  Map<String, Object?> toRpc() => {
    'p_register': register,
    'p_search': search,
    'p_status': status,
    'p_unit': unit,
    'p_category_id': categoryId,
    'p_offset': offset,
    'p_limit': limit,
  };
  @override
  bool operator ==(Object other) =>
      other is YorksV1InventoryRegisterQuery &&
      register == other.register &&
      search == other.search &&
      status == other.status &&
      unit == other.unit &&
      categoryId == other.categoryId &&
      offset == other.offset &&
      limit == other.limit;
  @override
  int get hashCode =>
      Object.hash(register, search, status, unit, categoryId, offset, limit);
}

abstract interface class YorksV1InventoryRegisterRepository {
  Future<YorksV1InventoryWorkspace> getInventoryPage(
    YorksV1InventoryRegisterQuery query,
  );
}

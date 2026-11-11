import 'yorks_v1_domain_error.dart';
import 'yorks_v1_quantity.dart';

/// Basis that made a delivery returnable.
///
/// [received]: the site confirmed the delivery; the basis is the good received
/// quantity. [dispatchedUnconfirmed]: dispatched but not yet confirmed by the
/// site; the basis is the dispatched quantity.
enum YorksV1ReturnBasisKind {
  received('received'),
  dispatchedUnconfirmed('dispatched_unconfirmed');

  const YorksV1ReturnBasisKind(this.wireValue);

  final String wireValue;

  static YorksV1ReturnBasisKind? fromWireValue(Object? value) {
    for (final kind in values) {
      if (kind.wireValue == value) return kind;
    }
    return null;
  }
}

/// Query for `v1_material_return_item_candidates`.
class YorksV1MaterialReturnCandidatesQuery {
  const YorksV1MaterialReturnCandidatesQuery({
    required this.projectId,
    this.returnId,
    this.search,
    this.scopeId,
  });

  static const maxSearchLength = 120;

  final String projectId;
  final String? returnId;
  final String? search;
  final String? scopeId;

  String? get normalizedSearch {
    final value = (search ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (value.isEmpty) return null;
    return value.length > maxSearchLength
        ? value.substring(0, maxSearchLength)
        : value;
  }

  Map<String, Object?> toRpcParameters() => {
    'p_project_id': projectId,
    'p_return_id': _trim(returnId),
    'p_search': normalizedSearch,
    'p_scope_id': _trim(scopeId),
  };

  @override
  bool operator ==(Object other) =>
      other is YorksV1MaterialReturnCandidatesQuery &&
      other.projectId == projectId &&
      _trim(other.returnId) == _trim(returnId) &&
      other.normalizedSearch == normalizedSearch &&
      _trim(other.scopeId) == _trim(scopeId);

  @override
  int get hashCode =>
      Object.hash(projectId, _trim(returnId), normalizedSearch, _trim(scopeId));
}

/// One delivery (dispatch line) that can still be returned.
class YorksV1MaterialReturnSource {
  const YorksV1MaterialReturnSource({
    required this.dispatchLineId,
    required this.requestId,
    required this.requestNumber,
    required this.dispatchId,
    required this.dispatchNumber,
    required this.scopeId,
    required this.basisKind,
    required this.dispatchedQuantity,
    required this.basisQuantity,
    required this.onActiveReturnsQuantity,
    required this.returnableQuantity,
    required this.sourceKind,
    this.receiptReviewLineId,
    this.requestLineId,
    this.deliveredAt,
    this.brandOrigin,
    this.model,
    this.equipmentTag,
    this.itemCode,
  });

  final String dispatchLineId;
  final String? receiptReviewLineId;
  final String? requestLineId;
  final String requestId;
  final String requestNumber;
  final String dispatchId;
  final String dispatchNumber;
  final String scopeId;
  final DateTime? deliveredAt;
  final String? brandOrigin;
  final String? model;
  final String? equipmentTag;
  final String? itemCode;
  final String sourceKind;
  final YorksV1ReturnBasisKind basisKind;
  final String dispatchedQuantity;
  final String basisQuantity;
  final String onActiveReturnsQuantity;
  final String returnableQuantity;

  bool get isUnconfirmed =>
      basisKind == YorksV1ReturnBasisKind.dispatchedUnconfirmed;

  factory YorksV1MaterialReturnSource.fromRpcJson(Map<String, dynamic> json) {
    final basis = YorksV1ReturnBasisKind.fromWireValue(json['basis_kind']);
    if (basis == null) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1MaterialReturnSource(
      dispatchLineId: _requiredString(json, 'dispatch_line_id'),
      receiptReviewLineId: _optionalString(json['receipt_review_line_id']),
      requestLineId: _optionalString(json['request_line_id']),
      requestId: _requiredString(json, 'request_id'),
      requestNumber:
          _optionalString(json['request_number']) ??
          _requiredString(json, 'request_id'),
      dispatchId: _requiredString(json, 'dispatch_id'),
      dispatchNumber: _requiredString(json, 'dispatch_number'),
      scopeId: _requiredString(json, 'scope_id'),
      deliveredAt: _optionalDate(json['delivered_at']),
      brandOrigin: _optionalString(json['brand_origin']),
      model: _optionalString(json['model']),
      equipmentTag: _optionalString(json['equipment_tag']),
      itemCode: _optionalString(json['item_code']),
      sourceKind: _requiredString(json, 'source_kind'),
      basisKind: basis,
      dispatchedQuantity: _quantity(json['dispatched_qty']),
      basisQuantity: _quantity(json['basis_qty']),
      onActiveReturnsQuantity: _quantity(json['on_active_returns_qty']),
      returnableQuantity: _quantity(json['returnable_qty']),
    );
  }
}

/// Delivered material grouped per description + size + unit.
class YorksV1MaterialReturnItem {
  YorksV1MaterialReturnItem({
    required this.key,
    required this.description,
    required this.unit,
    required this.deliveredQuantity,
    required this.onActiveReturnsQuantity,
    required this.returnableQuantity,
    required this.unconfirmedReturnableQuantity,
    required List<YorksV1MaterialReturnSource> sources,
    this.size,
    List<String> models = const [],
    List<String> equipmentTags = const [],
    List<String> brandOrigins = const [],
    List<String> itemCodes = const [],
    this.lastDeliveredAt,
  }) : sources = List.unmodifiable(sources),
       models = List.unmodifiable(models),
       equipmentTags = List.unmodifiable(equipmentTags),
       brandOrigins = List.unmodifiable(brandOrigins),
       itemCodes = List.unmodifiable(itemCodes);

  final String key;
  final String description;
  final String? size;
  final String unit;
  final List<String> models;
  final List<String> equipmentTags;
  final List<String> brandOrigins;
  final List<String> itemCodes;
  final String deliveredQuantity;
  final String onActiveReturnsQuantity;
  final String returnableQuantity;
  final String unconfirmedReturnableQuantity;
  final DateTime? lastDeliveredAt;

  /// Newest delivery first, as allocated by [yorksV1AllocateReturnQuantity].
  final List<YorksV1MaterialReturnSource> sources;

  bool get hasUnconfirmed =>
      YorksV1DecimalQuantity.tryParse(
        unconfirmedReturnableQuantity,
      )?.isPositive ==
      true;

  factory YorksV1MaterialReturnItem.fromRpcJson(Map<String, dynamic> json) {
    final sources = json['sources'];
    if (sources is! List) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1MaterialReturnItem(
      key: _requiredString(json, 'key'),
      description: _requiredString(json, 'item_description'),
      size: _optionalString(json['size']),
      unit: _requiredString(json, 'unit'),
      models: _strings(json['models']),
      equipmentTags: _strings(json['equipment_tags']),
      brandOrigins: _strings(json['brand_origins']),
      itemCodes: _strings(json['item_codes']),
      deliveredQuantity: _quantity(json['delivered_qty']),
      onActiveReturnsQuantity: _quantity(json['on_active_returns_qty']),
      returnableQuantity: _quantity(json['returnable_qty']),
      unconfirmedReturnableQuantity: _quantity(
        json['unconfirmed_returnable_qty'],
      ),
      lastDeliveredAt: _optionalDate(json['last_delivered_at']),
      sources: [
        for (final row in sources)
          if (row is Map)
            YorksV1MaterialReturnSource.fromRpcJson(
              Map<String, dynamic>.from(row),
            )
          else
            throw const YorksV1DomainException(
              YorksV1DomainErrorCode.unexpectedResponse,
            ),
      ],
    );
  }
}

class YorksV1MaterialReturnItemCandidates {
  YorksV1MaterialReturnItemCandidates({
    required this.projectId,
    required List<YorksV1MaterialReturnItem> items,
    this.search,
    this.scopeId,
    this.generatedAt,
  }) : items = List.unmodifiable(items);

  final String projectId;
  final String? search;
  final String? scopeId;
  final DateTime? generatedAt;
  final List<YorksV1MaterialReturnItem> items;

  YorksV1MaterialReturnItem? itemForKey(String key) {
    for (final item in items) {
      if (item.key == key) return item;
    }
    return null;
  }

  factory YorksV1MaterialReturnItemCandidates.fromRpcJson(Object? response) {
    if (response is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    final json = Map<String, dynamic>.from(response);
    final items = json['items'];
    if (items is! List) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1MaterialReturnItemCandidates(
      projectId: _requiredString(json, 'project_id'),
      search: _optionalString(json['search']),
      scopeId: _optionalString(json['scope_id']),
      generatedAt: _optionalDate(json['generated_at']),
      items: [
        for (final row in items)
          if (row is Map)
            YorksV1MaterialReturnItem.fromRpcJson(
              Map<String, dynamic>.from(row),
            )
          else
            throw const YorksV1DomainException(
              YorksV1DomainErrorCode.unexpectedResponse,
            ),
      ],
    );
  }
}

/// One allocated slice of a material return: [quantity] from [source].
class YorksV1ReturnAllocation {
  const YorksV1ReturnAllocation({required this.source, required this.quantity});

  final YorksV1MaterialReturnSource source;
  final String quantity;
}

/// Allocates [requested] across [sources] newest delivery first (product
/// owner decision, 4 November 2026). Returns null when [requested] is not a
/// positive quantity or exceeds what the sources can return. The server
/// re-checks every slice under row locks on save and submit.
List<YorksV1ReturnAllocation>? yorksV1AllocateReturnQuantity(
  List<YorksV1MaterialReturnSource> sources,
  String requested,
) {
  final wanted = YorksV1DecimalQuantity.tryParse(requested);
  if (wanted == null || !wanted.isPositive) return null;
  final ordered = [...sources]
    ..sort((a, b) {
      final at = a.deliveredAt;
      final bt = b.deliveredAt;
      if (at != null && bt != null) {
        final byDate = bt.compareTo(at);
        if (byDate != 0) return byDate;
      } else if (at != null || bt != null) {
        return at == null ? 1 : -1;
      }
      return b.dispatchNumber.compareTo(a.dispatchNumber);
    });
  var remaining = wanted;
  final result = <YorksV1ReturnAllocation>[];
  for (final source in ordered) {
    if (!remaining.isPositive) break;
    final available = YorksV1DecimalQuantity.tryParse(
      source.returnableQuantity,
    );
    if (available == null || !available.isPositive) continue;
    final take = available.min(remaining);
    result.add(
      YorksV1ReturnAllocation(source: source, quantity: take.canonicalText),
    );
    remaining = remaining - take;
  }
  return remaining.isPositive ? null : result;
}

/// Client mirror of the server grouping key: normalized description, size and
/// unit separated by U+001F. Different spellings are never merged.
String yorksV1MaterialReturnItemKey({
  required String description,
  required String unit,
  String? size,
}) {
  String collapse(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  return '${collapse(description)}\u001f${collapse(size ?? '')}'
      '\u001f${unit.trim().toLowerCase()}';
}

/// The same material limited to deliveries made to one building.
YorksV1MaterialReturnItem yorksV1MaterialReturnItemForScope(
  YorksV1MaterialReturnItem item,
  String? scopeId,
) {
  if (scopeId == null) return item;
  final sources = item.sources
      .where((source) => source.scopeId == scopeId)
      .toList(growable: false);
  return YorksV1MaterialReturnItem(
    key: item.key,
    description: item.description,
    size: item.size,
    unit: item.unit,
    models: item.models,
    equipmentTags: item.equipmentTags,
    brandOrigins: item.brandOrigins,
    itemCodes: item.itemCodes,
    deliveredQuantity: yorksV1SumQuantities(
      sources.map((source) => source.dispatchedQuantity),
    ),
    onActiveReturnsQuantity: yorksV1SumQuantities(
      sources.map((source) => source.onActiveReturnsQuantity),
    ),
    returnableQuantity: yorksV1SumQuantities(
      sources.map((source) => source.returnableQuantity),
    ),
    unconfirmedReturnableQuantity: yorksV1SumQuantities(
      sources
          .where((source) => source.isUnconfirmed)
          .map((source) => source.returnableQuantity),
    ),
    lastDeliveredAt: item.lastDeliveredAt,
    sources: sources,
  );
}

/// Instant client-side match used while the server trigram search runs: every
/// search word must appear in the material, size, model, tag, brand, code,
/// request or delivery number.
bool yorksV1MaterialReturnItemMatches(
  YorksV1MaterialReturnItem item,
  String search,
) {
  final words = search
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return true;
  final haystack = [
    item.description,
    item.size,
    ...item.models,
    ...item.equipmentTags,
    ...item.brandOrigins,
    ...item.itemCodes,
    for (final source in item.sources) ...[
      source.requestNumber,
      source.dispatchNumber,
    ],
  ].whereType<String>().join(' ').toLowerCase();
  return words.every(haystack.contains);
}

/// Sum of decimal quantity texts; invalid entries count as zero.
String yorksV1SumQuantities(Iterable<String> values) {
  var total = YorksV1DecimalQuantity.zero;
  for (final value in values) {
    total =
        total +
        (YorksV1DecimalQuantity.tryParse(value) ?? YorksV1DecimalQuantity.zero);
  }
  return total.canonicalText;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _optionalString(json[key]);
  if (value == null) {
    throw const YorksV1DomainException(
      YorksV1DomainErrorCode.unexpectedResponse,
    );
  }
  return value;
}

String? _optionalString(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

String _quantity(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return '0';
  if (YorksV1DecimalQuantity.tryParse(text) == null) {
    throw const YorksV1DomainException(
      YorksV1DomainErrorCode.unexpectedResponse,
    );
  }
  return text;
}

List<String> _strings(Object? value) => value is List
    ? value.map(_optionalString).whereType<String>().toList(growable: false)
    : const [];

DateTime? _optionalDate(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());

String? _trim(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

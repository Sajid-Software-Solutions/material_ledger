import 'yorks_v1_logistics.dart';
import 'yorks_v1_quantity.dart';

enum YorksV1DispatchQuantityIssue {
  invalid,
  negative,
  exceedsRemaining,
  unavailable,
  exceedsStock,
}

/// All quantities stay decimal-safe. Availability is a request-wide inventory
/// pool, not a separate allowance for each request line. These checks improve
/// feedback only; the trusted dispatch RPC rechecks the transaction at commit.
abstract final class YorksV1DispatchPreparation {
  static Map<String, YorksV1DecimalQuantity?> _pools(
    List<YorksV1DispatchCandidate> candidates,
  ) {
    final result = <String, YorksV1DecimalQuantity?>{};
    for (final candidate in candidates) {
      if (candidate.source != YorksV1LogisticsSource.warehouse) continue;
      final id = candidate.inventoryItemId ?? candidate.requestLineId;
      final available = YorksV1DecimalQuantity.tryParse(
        candidate.warehouseAvailableQuantity ?? '',
      );
      if (!result.containsKey(id)) {
        result[id] = available;
      } else {
        final previous = result[id];
        result[id] = previous == null || available == null
            ? null
            : previous.min(available);
      }
    }
    return result;
  }

  static Map<String, String> suggest(
    List<YorksV1DispatchCandidate> candidates,
  ) {
    final pools = _pools(candidates);
    final result = <String, String>{};
    for (final candidate in candidates) {
      var quantity =
          YorksV1DecimalQuantity.tryParse(candidate.stillNeededQuantity) ??
          YorksV1DecimalQuantity.zero;
      quantity = quantity.max(YorksV1DecimalQuantity.zero);
      if (candidate.source == YorksV1LogisticsSource.warehouse) {
        final id = candidate.inventoryItemId ?? candidate.requestLineId;
        final available = pools[id] ?? YorksV1DecimalQuantity.zero;
        quantity = quantity.min(available.max(YorksV1DecimalQuantity.zero));
        pools[id] = available - quantity;
      }
      result[candidate.requestLineId] = quantity.isPositive
          ? quantity.canonicalText
          : '';
    }
    return result;
  }

  static Map<String, YorksV1DispatchQuantityIssue> validate(
    List<YorksV1DispatchCandidate> candidates,
    Map<String, String> inputs,
  ) {
    final errors = <String, YorksV1DispatchQuantityIssue>{};
    final pools = _pools(candidates);
    final totals = <String, YorksV1DecimalQuantity>{};
    final lines = <String, List<String>>{};
    for (final candidate in candidates) {
      final id = candidate.requestLineId;
      final text = inputs[id]?.trim() ?? '';
      if (text.isEmpty) continue;
      final quantity = YorksV1DecimalQuantity.tryParse(text);
      if (quantity == null) {
        errors[id] = YorksV1DispatchQuantityIssue.invalid;
        continue;
      }
      if (quantity.isNegative) {
        errors[id] = YorksV1DispatchQuantityIssue.negative;
        continue;
      }
      if (quantity.isZero) continue;
      final remaining = YorksV1DecimalQuantity.tryParse(
        candidate.stillNeededQuantity,
      );
      if (remaining == null || quantity.compareTo(remaining) > 0) {
        errors[id] = YorksV1DispatchQuantityIssue.exceedsRemaining;
      }
      if (candidate.source == YorksV1LogisticsSource.warehouse) {
        final item = candidate.inventoryItemId ?? id;
        (lines[item] ??= []).add(id);
        totals[item] = (totals[item] ?? YorksV1DecimalQuantity.zero) + quantity;
      }
    }
    for (final entry in totals.entries) {
      final available = pools[entry.key];
      final issue = available == null
          ? YorksV1DispatchQuantityIssue.unavailable
          : entry.value.compareTo(available) > 0
          ? YorksV1DispatchQuantityIssue.exceedsStock
          : null;
      if (issue != null) {
        for (final line in lines[entry.key]!) {
          errors.putIfAbsent(line, () => issue);
        }
      }
    }
    return errors;
  }
}

import 'yorks_v1_domain_error.dart';
import 'yorks_v1_quantity.dart';

typedef YorksV1SourcingScope = ({String requestId, String? arrangementId});

class YorksV1SourcingLine {
  const YorksV1SourcingLine({
    required this.requestLineId,
    required this.readyQuantity,
    required this.requestedQuantity,
    required this.sourceKind,
    this.inventoryItemId,
    this.expectedDate,
  });
  final String requestLineId;
  final String readyQuantity;
  final String requestedQuantity;
  final String sourceKind;
  final String? inventoryItemId;
  final String? expectedDate;

  Map<String, Object?> toJson() => {
    'request_line_id': requestLineId,
    'ready_qty': readyQuantity,
    'source_kind': sourceKind,
    'inventory_item_id': inventoryItemId,
    'expected_available_date': expectedDate,
  };

  factory YorksV1SourcingLine.fromJson(Map<String, dynamic> json) {
    final ready = YorksV1DecimalQuantity.tryParse('${json['ready_qty']}');
    final requested = YorksV1DecimalQuantity.tryParse(
      '${json['requested_qty']}',
    );
    if (!_nonempty(json['request_line_id']) ||
        ready == null ||
        requested == null ||
        ready.isNegative ||
        !requested.isPositive ||
        ready.compareTo(requested) > 0 ||
        !{'warehouse', 'external_supplier'}.contains(json['source_kind']) ||
        (json['inventory_item_id'] != null &&
            !_nonempty(json['inventory_item_id'])) ||
        (json['expected_available_date'] != null &&
            !yorksV1SourcingDateIsValid(json['expected_available_date']))) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1SourcingLine(
      requestLineId: json['request_line_id'] as String,
      readyQuantity: ready.canonicalText,
      requestedQuantity: requested.canonicalText,
      sourceKind: json['source_kind'] as String,
      inventoryItemId: json['inventory_item_id'] as String?,
      expectedDate: json['expected_available_date'] as String?,
    );
  }
}

class YorksV1SourcingProgress {
  const YorksV1SourcingProgress({
    required this.requestId,
    required this.arrangementId,
    required this.revision,
    required this.isCurrent,
    required this.updatedAt,
    required this.updatedBy,
    this.updatedByRole,
    required this.lines,
  });
  final String requestId;
  final String arrangementId;
  final int revision;
  final bool isCurrent;
  final DateTime updatedAt;
  final String updatedBy;
  final String? updatedByRole;
  final List<YorksV1SourcingLine> lines;
  int get readyLines => lines
      .where((line) => line.readyQuantity == line.requestedQuantity)
      .length;
  int get waitingLines =>
      lines.where((line) => line.readyQuantity == '0').length;
  int get partialLines => lines.length - readyLines - waitingLines;

  factory YorksV1SourcingProgress.fromJson(Map<String, dynamic> json) {
    final at = DateTime.tryParse('${json['updated_at']}');
    if (!_nonempty(json['request_id']) ||
        !_nonempty(json['arrangement_id']) ||
        json['revision'] is! int ||
        (json['revision'] as int) < 1 ||
        json['is_current'] is! bool ||
        at == null ||
        json['lines'] is! List ||
        (json['updated_by_display_name'] != null &&
            json['updated_by_display_name'] is! String) ||
        (json['updated_by_role'] != null &&
            json['updated_by_role'] is! String)) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    final lines = (json['lines'] as List).map((line) {
      if (line is! Map<String, dynamic>) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.unexpectedResponse,
        );
      }
      return YorksV1SourcingLine.fromJson(line);
    }).toList();
    if (lines.isEmpty ||
        lines.map((line) => line.requestLineId).toSet().length !=
            lines.length) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1SourcingProgress(
      requestId: json['request_id'] as String,
      arrangementId: json['arrangement_id'] as String,
      revision: json['revision'] as int,
      isCurrent: json['is_current'] as bool,
      updatedAt: at,
      updatedBy: json['updated_by_display_name'] as String? ?? '',
      updatedByRole: json['updated_by_role'] as String?,
      lines: List.unmodifiable(lines),
    );
  }
}

bool _nonempty(Object? value) => value is String && value.trim().isNotEmpty;
bool yorksV1SourcingDateIsValid(Object? value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return false;
  }
  final date = DateTime.tryParse(value);
  return date != null && date.toIso8601String().substring(0, 10) == value;
}

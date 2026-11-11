import 'dart:convert';

/// Why stock moved. Every on-hand change is one of these.
enum MovementType {
  receipt('Received', 'وصول'),
  dispatch('Dispatched', 'صرف'),
  returnIn('Returned', 'إرجاع'),
  adjustment('Adjustment', 'تعديل'),
  opening('Opening', 'رصيد افتتاحي');

  const MovementType(this.label, this.ar);
  final String label;
  final String ar;

  static MovementType fromName(String n) => MovementType.values.firstWhere(
    (m) => m.name == n,
    orElse: () => adjustment,
  );
}

/// One append-only entry in the stock ledger: a single change to a material's
/// on-hand quantity, with the resulting balance so the running total is always
/// reconstructable. Records are NEVER edited or deleted — a correction is a new,
/// opposite entry. This is the godown's audit answer to "why is on-hand 84?".
class StockMovement {
  const StockMovement({
    required this.id,
    required this.materialId,
    required this.materialName,
    required this.type,
    required this.delta,
    required this.resultingBalance,
    this.refId,
    this.actor,
    required this.timestamp,
  });

  final String id;
  final String materialId;
  final String materialName;
  final MovementType type;

  /// Signed change to on-hand: positive for in (receipt/return), negative for out.
  final double delta;

  /// On-hand quantity immediately AFTER this movement was applied.
  final double resultingBalance;

  /// The document that caused it (GRN / request / return id), when known.
  final String? refId;

  /// Who recorded it (audit).
  final String? actor;

  final DateTime timestamp;

  String get signedQty =>
      '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(delta.truncateToDouble() == delta ? 0 : 2)}';

  Map<String, dynamic> toJson() => {
    'id': id,
    'materialId': materialId,
    'materialName': materialName,
    'type': type.name,
    'delta': delta,
    'resultingBalance': resultingBalance,
    'refId': refId,
    'actor': actor,
    'timestamp': timestamp.toIso8601String(),
  };

  factory StockMovement.fromJson(Map<String, dynamic> json) => StockMovement(
    id: json['id'] as String? ?? '',
    materialId: json['materialId'] as String? ?? '',
    materialName: json['materialName'] as String? ?? '',
    type: MovementType.fromName(json['type'] as String? ?? 'adjustment'),
    delta: (json['delta'] as num?)?.toDouble() ?? 0,
    resultingBalance: (json['resultingBalance'] as num?)?.toDouble() ?? 0,
    refId: json['refId'] as String?,
    actor: json['actor'] as String?,
    timestamp:
        DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
  );

  static String encodeList(List<StockMovement> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());

  static List<StockMovement> decodeList(String jsonStr) {
    final list = jsonDecode(jsonStr) as List;
    return list
        .map((e) => StockMovement.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

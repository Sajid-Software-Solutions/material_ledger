import 'dart:convert';

/// Settlement state of a single month's rent for a unit (FR-118).
enum RentStatus {
  paid('Paid', 'مدفوع', 'ادا شدہ', 'भुगतान'),
  partial('Partial', 'جزئي', 'جزوی', 'आंशिक'),
  due('Due', 'مستحق', 'واجب', 'देय'),
  overdue('Overdue', 'متأخر', 'زائد المیعاد', 'अतिदेय');

  const RentStatus(this.label, this.ar, this.ur, this.hi);
  final String label;
  final String ar;
  final String ur;
  final String hi;
}

/// A rent payment record for one unit and one billing month (`YYYY-MM`).
/// The settlement [status] is derived from the amounts and the period so it
/// can never drift out of sync with the figures (FR-118/119).
class RentPayment {
  const RentPayment({
    required this.id,
    required this.unitId,
    required this.periodMonth,
    required this.amountDueAED,
    this.amountPaidAED = 0,
    this.paidDate,
    this.method,
    this.note,
    required this.recordedBy,
    required this.recordedAt,
    this.voidedAt,
    this.voidReason = '',
  }) : assert(amountDueAED >= 0, 'amountDueAED cannot be negative'),
       assert(amountPaidAED >= 0, 'amountPaidAED cannot be negative');

  final String id;
  final String unitId;

  /// Billing month in `YYYY-MM` form.
  final String periodMonth;

  final double amountDueAED;
  final double amountPaidAED;
  final DateTime? paidDate;
  final String? method;
  final String? note;
  final String recordedBy;
  final DateTime recordedAt;

  /// Set when the record is voided (a correction). A voided payment is excluded
  /// from all balances/summaries but kept in history for the audit trail.
  final DateTime? voidedAt;
  final String voidReason;

  bool get isVoided => voidedAt != null;

  double get outstandingAED =>
      (amountDueAED - amountPaidAED).clamp(0, double.infinity).toDouble();

  /// Derive the settlement status as of [now] (defaults to the current date).
  RentStatus statusAsOf(DateTime now) {
    // Fully settled (or nothing was owed).
    if (amountDueAED <= 0 || amountPaidAED >= amountDueAED) {
      return RentStatus.paid;
    }
    // A balance remains. Once the billing month has fully passed it is overdue —
    // whether nothing OR only part of it has been paid (a partial old balance is
    // still late money to collect).
    if (_isPastDue(now)) return RentStatus.overdue;
    // Still within the billing window: partial if something's in, else due.
    if (amountPaidAED > 0) return RentStatus.partial;
    return RentStatus.due;
  }

  /// True once the first day of the month AFTER [periodMonth] has arrived, i.e.
  /// the whole billing month has elapsed. A malformed period is treated as
  /// past-due so a real balance SURFACES as overdue rather than being silently
  /// hidden (a corrupted month string must never bury money owed).
  bool _isPastDue(DateTime now) {
    final parts = periodMonth.split('-');
    if (parts.length != 2) return true;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null || month < 1 || month > 12) return true;
    final dueCutoff = month == 12
        ? DateTime(year + 1, 1, 1)
        : DateTime(year, month + 1, 1);
    return now.isAfter(dueCutoff);
  }

  RentPayment copyWith({
    double? amountDueAED,
    double? amountPaidAED,
    DateTime? paidDate,
    String? method,
    String? note,
    DateTime? voidedAt,
    String? voidReason,
  }) => RentPayment(
    id: id,
    unitId: unitId,
    periodMonth: periodMonth,
    amountDueAED: amountDueAED ?? this.amountDueAED,
    amountPaidAED: amountPaidAED ?? this.amountPaidAED,
    paidDate: paidDate ?? this.paidDate,
    method: method ?? this.method,
    note: note ?? this.note,
    recordedBy: recordedBy,
    recordedAt: recordedAt,
    voidedAt: voidedAt ?? this.voidedAt,
    voidReason: voidReason ?? this.voidReason,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'unitId': unitId,
    'periodMonth': periodMonth,
    'amountDueAED': amountDueAED,
    'amountPaidAED': amountPaidAED,
    'paidDate': paidDate?.toIso8601String(),
    'method': method,
    'note': note,
    'recordedBy': recordedBy,
    'recordedAt': recordedAt.toIso8601String(),
    'voidedAt': voidedAt?.toIso8601String(),
    'voidReason': voidReason,
  };

  factory RentPayment.fromJson(Map<String, dynamic> json) => RentPayment(
    id: json['id'] as String? ?? '',
    unitId: json['unitId'] as String? ?? '',
    periodMonth: json['periodMonth'] as String? ?? '',
    amountDueAED: (((json['amountDueAED'] as num?)?.toDouble()) ?? 0)
        .clamp(0, double.infinity)
        .toDouble(),
    // Clamp a corrupted/negative synced paid amount so it can't inflate
    // receivables (a negative "paid" would read as extra outstanding).
    amountPaidAED: (((json['amountPaidAED'] as num?)?.toDouble()) ?? 0)
        .clamp(0, double.infinity)
        .toDouble(),
    paidDate: DateTime.tryParse(json['paidDate'] as String? ?? ''),
    method: json['method'] as String?,
    note: json['note'] as String?,
    recordedBy: json['recordedBy'] as String? ?? 'system',
    recordedAt:
        DateTime.tryParse(json['recordedAt'] as String? ?? '') ??
        DateTime.now(),
    voidedAt: DateTime.tryParse(json['voidedAt'] as String? ?? ''),
    voidReason: json['voidReason'] as String? ?? '',
  );

  static String encodeList(List<RentPayment> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());

  static List<RentPayment> decodeList(String jsonStr) {
    final list = jsonDecode(jsonStr) as List;
    return list
        .map((e) => RentPayment.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

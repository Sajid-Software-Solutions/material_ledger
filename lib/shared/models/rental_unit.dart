import 'dart:convert';

/// What kind of rented space this is.
enum RentalType {
  shop('Shop', 'محل', 'دکان', 'दुकान'),
  workshop('Workshop', 'ورشة', 'ورکشاپ', 'कार्यशाला');

  const RentalType(this.label, this.ar, this.ur, this.hi);
  final String label;
  final String ar;
  final String ur;
  final String hi;

  static RentalType fromName(String n) =>
      RentalType.values.firstWhere((t) => t.name == n, orElse: () => shop);
}

/// Occupancy state of a rental unit.
enum RentalStatus {
  active('Active', 'نشط', 'فعال', 'सक्रिय'),
  vacant('Vacant', 'شاغر', 'خالی', 'खाली');

  const RentalStatus(this.label, this.ar, this.ur, this.hi);
  final String label;
  final String ar;
  final String ur;
  final String hi;

  static RentalStatus fromName(String n) =>
      RentalStatus.values.firstWhere((s) => s.name == n, orElse: () => vacant);
}

/// A shop/workshop the company rents out to a tenant (Rentals module, FR-117).
class RentalUnit {
  const RentalUnit({
    required this.id,
    required this.unitName,
    required this.type,
    required this.location,
    required this.monthlyRentAED,
    this.tenantName,
    this.tenantContact,
    this.leaseStart,
    this.leaseEnd,
    this.status = RentalStatus.vacant,
    this.notes,
    this.securityDepositAED,
    this.vatRatePercent = 5.0,
    required this.createdBy,
    required this.createdAt,
  });

  final String id;
  final String unitName;
  final RentalType type;
  final String location;

  /// Total monthly rent as actually charged/collected (VAT-inclusive, if VAT
  /// applies) — every rent-roll/overdue/collected calculation already uses this
  /// figure unchanged. [vatRatePercent] only derives a NET/VAT breakdown for
  /// display (invoicing transparency); it never alters what's due or collected.
  final double monthlyRentAED;

  final String? tenantName;
  final String? tenantContact;
  final DateTime? leaseStart;
  final DateTime? leaseEnd;
  final RentalStatus status;
  final String? notes;

  /// Security deposit held from the tenant (a liability until refunded/offset
  /// at move-out) — separate from rent, never counted in the rent roll.
  final double? securityDepositAED;

  /// VAT rate applied to this unit's commercial rent (UAE standard 5%). Used
  /// only to derive a net/VAT/gross breakdown for display — see [monthlyRentAED].
  final double vatRatePercent;

  final String createdBy;
  final DateTime createdAt;

  bool get isOccupied => status == RentalStatus.active;

  /// Net (pre-VAT) portion of [monthlyRentAED], back-calculated from the
  /// VAT-inclusive total: net = gross ÷ (1 + rate).
  double get netRentAED => monthlyRentAED / (1 + vatRatePercent / 100);

  /// VAT portion of [monthlyRentAED].
  double get vatAmountAED => monthlyRentAED - netRentAED;

  /// True when the lease end date has passed — a cue to renew or mark vacant.
  bool get leaseExpired =>
      leaseEnd != null && DateTime.now().isAfter(leaseEnd!);

  RentalUnit copyWith({
    String? unitName,
    RentalType? type,
    String? location,
    double? monthlyRentAED,
    String? tenantName,
    String? tenantContact,
    DateTime? leaseStart,
    DateTime? leaseEnd,
    RentalStatus? status,
    String? notes,
    Object? securityDepositAED = _keep,
    double? vatRatePercent,
  }) => RentalUnit(
    id: id,
    unitName: unitName ?? this.unitName,
    type: type ?? this.type,
    location: location ?? this.location,
    monthlyRentAED: monthlyRentAED ?? this.monthlyRentAED,
    tenantName: tenantName ?? this.tenantName,
    tenantContact: tenantContact ?? this.tenantContact,
    leaseStart: leaseStart ?? this.leaseStart,
    leaseEnd: leaseEnd ?? this.leaseEnd,
    status: status ?? this.status,
    notes: notes ?? this.notes,
    securityDepositAED: securityDepositAED == _keep
        ? this.securityDepositAED
        : securityDepositAED as double?,
    vatRatePercent: vatRatePercent ?? this.vatRatePercent,
    createdBy: createdBy,
    createdAt: createdAt,
  );

  static const Object _keep = Object();

  Map<String, dynamic> toJson() => {
    'id': id,
    'unitName': unitName,
    'type': type.name,
    'location': location,
    'monthlyRentAED': monthlyRentAED,
    'tenantName': tenantName,
    'tenantContact': tenantContact,
    'leaseStart': leaseStart?.toIso8601String(),
    'leaseEnd': leaseEnd?.toIso8601String(),
    'status': status.name,
    'notes': notes,
    'securityDepositAED': securityDepositAED,
    'vatRatePercent': vatRatePercent,
    'createdBy': createdBy,
    'createdAt': createdAt.toIso8601String(),
  };

  factory RentalUnit.fromJson(Map<String, dynamic> json) => RentalUnit(
    id: json['id'] as String? ?? '',
    unitName: json['unitName'] as String? ?? '',
    type: RentalType.fromName(json['type'] as String? ?? 'shop'),
    location: json['location'] as String? ?? '',
    monthlyRentAED: (json['monthlyRentAED'] as num?)?.toDouble() ?? 0,
    tenantName: json['tenantName'] as String?,
    tenantContact: json['tenantContact'] as String?,
    leaseStart: DateTime.tryParse(json['leaseStart'] as String? ?? ''),
    leaseEnd: DateTime.tryParse(json['leaseEnd'] as String? ?? ''),
    status: RentalStatus.fromName(json['status'] as String? ?? 'vacant'),
    notes: json['notes'] as String?,
    securityDepositAED: (json['securityDepositAED'] as num?)?.toDouble(),
    vatRatePercent: (json['vatRatePercent'] as num?)?.toDouble() ?? 5.0,
    createdBy: json['createdBy'] as String? ?? 'system',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );

  static String encodeList(List<RentalUnit> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());

  static List<RentalUnit> decodeList(String jsonStr) {
    final list = jsonDecode(jsonStr) as List;
    return list
        .map((e) => RentalUnit.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

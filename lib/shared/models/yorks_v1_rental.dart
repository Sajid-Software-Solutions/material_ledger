enum YorksV1RentalOccupancy {
  occupied,
  vacant,
  unknown;

  static YorksV1RentalOccupancy fromWire(Object? value) =>
      switch (value?.toString()) {
        'occupied' => occupied,
        'vacant' => vacant,
        _ => unknown,
      };

  String get wireValue => name;
}

enum YorksV1RentalPeriodStatus {
  upcoming,
  due,
  partiallyPaid,
  paid,
  overdue;

  static YorksV1RentalPeriodStatus fromWire(Object? value) {
    return switch (value?.toString()) {
      'due' => due,
      'partially_paid' => partiallyPaid,
      'paid' => paid,
      'overdue' => overdue,
      _ => upcoming,
    };
  }
}

enum YorksV1RentalChequeStatus {
  scheduled,
  received,
  deposited,
  cleared,
  returned,
  cancelled;

  static YorksV1RentalChequeStatus fromWire(Object? value) {
    return values.firstWhere(
      (status) => status.name == value?.toString(),
      orElse: () => scheduled,
    );
  }
}

DateTime? _date(Object? value) {
  if (value == null || value.toString().isEmpty) return null;
  return DateTime.tryParse(value.toString());
}

double _number(Object? value) => switch (value) {
  num number => number.toDouble(),
  _ => double.tryParse(value?.toString() ?? '') ?? 0,
};

int _integer(Object? value) => switch (value) {
  int number => number,
  num number => number.toInt(),
  _ => int.tryParse(value?.toString() ?? '') ?? 0,
};

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

List<Map<String, dynamic>> _list(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is Map) Map<String, dynamic>.from(item),
      ]
    : const [];

String _rentalWire(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_|_$'), '');

class YorksV1RentalSummary {
  const YorksV1RentalSummary({
    required this.totalProperties,
    required this.occupied,
    required this.monthlyRentRoll,
    required this.collectedThisMonth,
    required this.outstanding,
    required this.securityDeposits,
    required this.expiringWithin90,
    required this.chequeAttention,
    this.annualRentRoll = 0,
  });

  factory YorksV1RentalSummary.fromJson(Map<String, dynamic> json) {
    return YorksV1RentalSummary(
      totalProperties: _integer(json['total_properties']),
      occupied: _integer(json['occupied']),
      monthlyRentRoll: _number(json['monthly_rent_roll']),
      collectedThisMonth: _number(json['collected_this_month']),
      outstanding: _number(json['outstanding']),
      securityDeposits: _number(json['security_deposits']),
      expiringWithin90: _integer(json['expiring_within_90']),
      chequeAttention: _integer(json['cheque_attention']),
      annualRentRoll: _number(json['annual_rent_roll']),
    );
  }

  final int totalProperties;
  final int occupied;
  final double monthlyRentRoll;
  final double collectedThisMonth;
  final double outstanding;
  final double securityDeposits;
  final int expiringWithin90;
  final int chequeAttention;
  final double annualRentRoll;

  double get occupancyPercent => totalProperties == 0
      ? 0
      : (occupied / totalProperties * 100).clamp(0, 100);
}

class YorksV1RentalProperty {
  const YorksV1RentalProperty({
    required this.id,
    required this.unitCode,
    required this.propertyName,
    required this.propertyType,
    required this.location,
    required this.occupancy,
    required this.isArchived,
    required this.recordVersion,
    this.municipalityNumber,
    this.description,
    this.updatedAt,
    this.leaseId,
    this.contractNumber,
    this.contractType,
    this.contractStatus,
    this.tenantName,
    this.contactNumber,
    this.email,
    this.tradeLicenceNumber,
    this.leaseStart,
    this.leaseEnd,
    this.monthlyRent = 0,
    this.securityDeposit = 0,
    this.monthlyDueDay = 1,
    this.gracePeriodDays = 0,
    this.defaultPaymentMethod,
    this.annualEscalationPercent = 0,
    this.renewalNoticeDays = 90,
    this.outstanding = 0,
    this.currentPaid = 0,
    this.currentDue = 0,
    this.nextChequeDate,
    this.nextChequeNumber,
    this.annualRent,
    this.paymentFrequency = 'monthly',
    this.billingStart,
    this.billingSetupPending = false,
    this.missingFields = const [],
    this.sourceMetadata = const {},
    this.daysToLeaseEnd,
    this.chequeAttention = false,
    this.hasRentAmount = true,
  });

  factory YorksV1RentalProperty.fromJson(Map<String, dynamic> json) {
    return YorksV1RentalProperty(
      id: json['id']?.toString() ?? '',
      unitCode: json['unit_code']?.toString() ?? '',
      propertyName: json['property_name']?.toString() ?? '',
      propertyType: json['property_type']?.toString() ?? '',
      municipalityNumber: json['municipality_number']?.toString(),
      location: json['location']?.toString() ?? '',
      description: json['description']?.toString(),
      occupancy: YorksV1RentalOccupancy.fromWire(json['occupancy_state']),
      isArchived: json['is_archived'] == true,
      recordVersion: _integer(json['record_version']),
      updatedAt: _date(json['updated_at']),
      leaseId: json['lease_id']?.toString(),
      contractNumber: json['contract_number']?.toString(),
      contractType: json['contract_type']?.toString(),
      contractStatus: json['contract_status']?.toString(),
      tenantName: json['tenant_name']?.toString(),
      contactNumber: json['contact_number']?.toString(),
      email: json['email']?.toString(),
      tradeLicenceNumber: json['trade_licence_number']?.toString(),
      leaseStart: _date(json['lease_start']),
      leaseEnd: _date(json['lease_end']),
      monthlyRent: _number(json['monthly_rent']),
      securityDeposit: _number(json['security_deposit']),
      monthlyDueDay: _integer(json['monthly_due_day']),
      gracePeriodDays: _integer(json['grace_period_days']),
      defaultPaymentMethod: json['default_payment_method']?.toString(),
      annualEscalationPercent: _number(json['annual_escalation_percent']),
      renewalNoticeDays: _integer(json['renewal_notice_days']),
      outstanding: _number(json['outstanding']),
      currentPaid: _number(json['current_paid']),
      currentDue: _number(json['current_due']),
      nextChequeDate: _date(json['next_cheque_date']),
      nextChequeNumber: json['next_cheque_number']?.toString(),
      annualRent: json['annual_rent'] == null
          ? null
          : _number(json['annual_rent']),
      paymentFrequency:
          (json['rent_frequency'] ?? json['payment_frequency'])?.toString() ??
          'monthly',
      billingStart: _date(json['billing_start']),
      billingSetupPending: json['billing_setup_pending'] == true,
      missingFields: (json['missing_fields'] is List)
          ? (json['missing_fields'] as List)
                .map((item) => item.toString())
                .toList()
          : const [],
      sourceMetadata: _map(json['source_metadata']),
      daysToLeaseEnd: json['days_to_lease_end'] == null
          ? null
          : _integer(json['days_to_lease_end']),
      chequeAttention: json['cheque_attention'] == true,
      hasRentAmount:
          (json['rent_frequency'] ?? json['payment_frequency']) == 'annual'
          ? json['annual_rent'] != null
          : json['monthly_rent'] != null,
    );
  }

  final String id;
  final String unitCode;
  final String propertyName;
  final String propertyType;
  final String? municipalityNumber;
  final String location;
  final String? description;
  final YorksV1RentalOccupancy occupancy;
  final bool isArchived;
  final int recordVersion;
  final DateTime? updatedAt;
  final String? leaseId;
  final String? contractNumber;
  final String? contractType;
  final String? contractStatus;
  final String? tenantName;
  final String? contactNumber;
  final String? email;
  final String? tradeLicenceNumber;
  final DateTime? leaseStart;
  final DateTime? leaseEnd;
  final double monthlyRent;
  final double securityDeposit;
  final int monthlyDueDay;
  final int gracePeriodDays;
  final String? defaultPaymentMethod;
  final double annualEscalationPercent;
  final int renewalNoticeDays;
  final double outstanding;
  final double currentPaid;
  final double currentDue;
  final DateTime? nextChequeDate;
  final String? nextChequeNumber;
  final double? annualRent;
  final String paymentFrequency;
  final DateTime? billingStart;
  final bool billingSetupPending;
  final List<String> missingFields;
  final Map<String, dynamic> sourceMetadata;
  final int? daysToLeaseEnd;
  final bool chequeAttention;
  final bool hasRentAmount;

  bool get isAnnual => paymentFrequency == 'annual';
  double? get rentAmount =>
      hasRentAmount ? (isAnnual ? annualRent : monthlyRent) : null;
  bool get needsCompletion => missingFields.isNotEmpty;

  bool get isOccupied => occupancy == YorksV1RentalOccupancy.occupied;
}

class YorksV1RentalPayment {
  const YorksV1RentalPayment({
    required this.id,
    required this.propertyId,
    required this.amount,
    required this.paymentDate,
    required this.paymentMethod,
    this.periodId,
    this.periodMonth,
    this.reference,
    this.note,
    this.recordedAt,
    this.recordedBy,
    this.unitCode,
    this.propertyName,
  });

  factory YorksV1RentalPayment.fromJson(Map<String, dynamic> json) {
    return YorksV1RentalPayment(
      id: json['id']?.toString() ?? '',
      propertyId: json['property_id']?.toString() ?? '',
      periodId: json['period_id']?.toString(),
      periodMonth: _date(json['period_month']),
      amount: _number(json['amount_received']),
      paymentDate: _date(json['payment_date']) ?? DateTime(1970),
      paymentMethod: json['payment_method']?.toString() ?? '',
      reference: json['reference']?.toString(),
      note: json['note']?.toString(),
      recordedAt: _date(json['recorded_at']),
      recordedBy: json['recorded_by']?.toString(),
      unitCode: json['unit_code']?.toString(),
      propertyName: json['property_name']?.toString(),
    );
  }

  final String id;
  final String propertyId;
  final String? periodId;
  final DateTime? periodMonth;
  final double amount;
  final DateTime paymentDate;
  final String paymentMethod;
  final String? reference;
  final String? note;
  final DateTime? recordedAt;
  final String? recordedBy;
  final String? unitCode;
  final String? propertyName;
}

class YorksV1RentalCheque {
  const YorksV1RentalCheque({
    required this.id,
    required this.propertyId,
    required this.leaseId,
    required this.chequeNumber,
    required this.chequeType,
    required this.bankName,
    required this.chequeDate,
    required this.amount,
    required this.status,
    required this.recordVersion,
    this.periodId,
    this.note,
    this.unitCode,
    this.propertyName,
    this.tenantName,
  });

  factory YorksV1RentalCheque.fromJson(Map<String, dynamic> json) {
    return YorksV1RentalCheque(
      id: json['id']?.toString() ?? '',
      propertyId: json['property_id']?.toString() ?? '',
      leaseId: json['lease_id']?.toString() ?? '',
      periodId: json['period_id']?.toString(),
      chequeNumber: json['cheque_number']?.toString() ?? '',
      chequeType: json['cheque_type']?.toString() ?? '',
      bankName: json['bank_name']?.toString() ?? '',
      chequeDate: _date(json['cheque_date']) ?? DateTime(1970),
      amount: _number(json['amount']),
      status: YorksV1RentalChequeStatus.fromWire(json['status']),
      note: json['note']?.toString(),
      recordVersion: _integer(json['record_version']),
      unitCode: json['unit_code']?.toString(),
      propertyName: json['property_name']?.toString(),
      tenantName: json['tenant_name']?.toString(),
    );
  }

  final String id;
  final String propertyId;
  final String leaseId;
  final String? periodId;
  final String chequeNumber;
  final String chequeType;
  final String bankName;
  final DateTime chequeDate;
  final double amount;
  final YorksV1RentalChequeStatus status;
  final String? note;
  final int recordVersion;
  final String? unitCode;
  final String? propertyName;
  final String? tenantName;
}

class YorksV1RentalPeriod {
  const YorksV1RentalPeriod({
    required this.id,
    required this.periodMonth,
    required this.dueDate,
    required this.amountDue,
    required this.amountPaid,
    required this.balance,
    required this.status,
  });

  factory YorksV1RentalPeriod.fromJson(Map<String, dynamic> json) {
    return YorksV1RentalPeriod(
      id: json['id']?.toString() ?? '',
      periodMonth: _date(json['period_month']) ?? DateTime(1970),
      dueDate: _date(json['due_date']) ?? DateTime(1970),
      amountDue: _number(json['amount_due']),
      amountPaid: _number(json['amount_paid']),
      balance: _number(json['balance']),
      status: YorksV1RentalPeriodStatus.fromWire(json['status']),
    );
  }

  final String id;
  final DateTime periodMonth;
  final DateTime dueDate;
  final double amountDue;
  final double amountPaid;
  final double balance;
  final YorksV1RentalPeriodStatus status;
}

class YorksV1RentalActivity {
  const YorksV1RentalActivity({
    required this.id,
    required this.eventType,
    required this.actorRole,
    required this.occurredAt,
    required this.actorName,
    this.reason,
    this.afterData = const {},
  });

  factory YorksV1RentalActivity.fromJson(Map<String, dynamic> json) {
    return YorksV1RentalActivity(
      id: json['id']?.toString() ?? '',
      eventType: json['event_type']?.toString() ?? '',
      actorRole: json['actor_role']?.toString() ?? '',
      occurredAt: _date(json['occurred_at']) ?? DateTime(1970),
      actorName: json['actor_name']?.toString() ?? '',
      reason: json['reason']?.toString(),
      afterData: _map(json['after_data']),
    );
  }

  final String id;
  final String eventType;
  final String actorRole;
  final DateTime occurredAt;
  final String actorName;
  final String? reason;
  final Map<String, dynamic> afterData;
}

class YorksV1RentalPortfolio {
  const YorksV1RentalPortfolio({
    required this.asOf,
    required this.summary,
    required this.properties,
    required this.recentPayments,
    required this.cheques,
  });

  factory YorksV1RentalPortfolio.fromJson(Map<String, dynamic> json) {
    return YorksV1RentalPortfolio(
      asOf: _date(json['as_of']) ?? DateTime.now(),
      summary: YorksV1RentalSummary.fromJson(_map(json['summary'])),
      properties: _list(
        json['properties'],
      ).map(YorksV1RentalProperty.fromJson).toList(growable: false),
      recentPayments: _list(
        json['recent_payments'],
      ).map(YorksV1RentalPayment.fromJson).toList(growable: false),
      cheques: _list(
        json['cheques'],
      ).map(YorksV1RentalCheque.fromJson).toList(growable: false),
    );
  }

  final DateTime asOf;
  final YorksV1RentalSummary summary;
  final List<YorksV1RentalProperty> properties;
  final List<YorksV1RentalPayment> recentPayments;
  final List<YorksV1RentalCheque> cheques;
}

class YorksV1RentalPropertyDetail {
  const YorksV1RentalPropertyDetail({
    required this.property,
    required this.periods,
    required this.receipts,
    required this.cheques,
    required this.activity,
    this.lease = const {},
  });

  factory YorksV1RentalPropertyDetail.fromJson(Map<String, dynamic> json) {
    final propertyJson = _map(json['property']);
    final leaseJson = _map(json['lease']);
    return YorksV1RentalPropertyDetail(
      property: YorksV1RentalProperty.fromJson({
        ...propertyJson,
        ...leaseJson,
        'id': propertyJson['id'],
        'record_version': propertyJson['record_version'],
        'updated_at': propertyJson['updated_at'],
        'lease_id': leaseJson['id'],
      }),
      lease: leaseJson,
      periods: _list(
        json['periods'],
      ).map(YorksV1RentalPeriod.fromJson).toList(growable: false),
      receipts: _list(
        json['receipts'],
      ).map(YorksV1RentalPayment.fromJson).toList(growable: false),
      cheques: _list(
        json['cheques'],
      ).map(YorksV1RentalCheque.fromJson).toList(growable: false),
      activity: _list(
        json['activity'],
      ).map(YorksV1RentalActivity.fromJson).toList(growable: false),
    );
  }

  final YorksV1RentalProperty property;
  final Map<String, dynamic> lease;
  final List<YorksV1RentalPeriod> periods;
  final List<YorksV1RentalPayment> receipts;
  final List<YorksV1RentalCheque> cheques;
  final List<YorksV1RentalActivity> activity;
}

class YorksV1RentalPropertyInput {
  const YorksV1RentalPropertyInput({
    required this.unitCode,
    required this.propertyName,
    required this.propertyType,
    required this.location,
    required this.occupancy,
    required this.contractNumber,
    required this.contractType,
    required this.contractStatus,
    required this.monthlyRent,
    required this.securityDeposit,
    required this.monthlyDueDay,
    required this.gracePeriodDays,
    required this.defaultPaymentMethod,
    required this.paymentFrequency,
    required this.contractCheques,
    required this.annualEscalationPercent,
    required this.renewalNoticeDays,
    this.propertyId,
    this.leaseId,
    this.municipalityNumber,
    this.description,
    this.tenantName,
    this.tradeLicenceNumber,
    this.contactNumber,
    this.email,
    this.signedDate,
    this.leaseStart,
    this.leaseEnd,
    this.notes,
    this.annualRent,
    this.billingStart,
    this.sourceMetadata,
  });

  final String? propertyId;
  final String? leaseId;
  final String unitCode;
  final String propertyName;
  final String propertyType;
  final String? municipalityNumber;
  final String location;
  final String? description;
  final YorksV1RentalOccupancy occupancy;
  final String? tenantName;
  final String? tradeLicenceNumber;
  final String? contactNumber;
  final String? email;
  final String contractNumber;
  final String contractType;
  final String contractStatus;
  final DateTime? signedDate;
  final DateTime? leaseStart;
  final DateTime? leaseEnd;
  final double? monthlyRent;
  final double? annualRent;
  final DateTime? billingStart;
  final Map<String, dynamic>? sourceMetadata;
  final double securityDeposit;
  final int monthlyDueDay;
  final int gracePeriodDays;
  final String defaultPaymentMethod;
  final String paymentFrequency;
  final int contractCheques;
  final double annualEscalationPercent;
  final int renewalNoticeDays;
  final String? notes;

  Map<String, Object?> toRpcPayload() => {
    if (propertyId != null) 'property_id': propertyId,
    if (leaseId != null) 'lease_id': leaseId,
    'unit_code': unitCode,
    'property_name': propertyName,
    'property_type': _rentalWire(propertyType),
    'municipality_number': municipalityNumber,
    'location': location,
    'description': description,
    'occupied': occupancy == YorksV1RentalOccupancy.occupied,
    'occupancy_state': occupancy.wireValue,
    'tenant_name': tenantName,
    'trade_licence_number': tradeLicenceNumber,
    'contact_number': contactNumber,
    'email': email,
    'contract_number': contractNumber,
    'contract_type': _rentalWire(contractType),
    'contract_status': _rentalWire(contractStatus),
    'signed_date': signedDate?.toIso8601String().split('T').first,
    'lease_start': leaseStart?.toIso8601String().split('T').first,
    'lease_end': leaseEnd?.toIso8601String().split('T').first,
    'monthly_rent': monthlyRent,
    'annual_rent': annualRent,
    'billing_start': billingStart?.toIso8601String().split('T').first,
    if (sourceMetadata != null) 'source_metadata': sourceMetadata,
    'security_deposit': securityDeposit,
    'monthly_due_day': monthlyDueDay,
    'grace_period_days': gracePeriodDays,
    'default_payment_method': _rentalWire(defaultPaymentMethod),
    'payment_frequency': _rentalWire(paymentFrequency),
    'contract_cheque_count': contractCheques,
    'annual_escalation_percent': annualEscalationPercent,
    'renewal_notice_days': renewalNoticeDays,
    'lease_notes': notes,
  };
}

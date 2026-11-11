import 'yorks_v1_rental.dart';

/// A presentation receipt for one acknowledged command, not a second audit log.
/// Missing fields are deliberately read from the refreshed server projection.
class YorksRentalSaveReceipt {
  const YorksRentalSaveReceipt({
    required this.propertyId,
    required this.input,
    required this.before,
  });

  final String propertyId;
  final YorksV1RentalPropertyInput input;
  final YorksV1RentalPropertyDetail? before;
  bool get created => before == null;

  // A later edit is not evidence of what this command changed.
  bool matchesVersion(YorksV1RentalPropertyDetail after) =>
      after.property.id == propertyId &&
      after.property.recordVersion == (before?.property.recordVersion ?? 0) + 1;

  List<String> updatedFields(YorksV1RentalPropertyDetail after) {
    if (!matchesVersion(after)) return const [];
    final previous = before == null ? <String, Object?>{} : _values(before!);
    final saved = _values(after);
    return [
      for (final key in fieldKeys)
        if (_normal(saved[key]) != _normal(previous[key])) key,
    ];
  }

  List<String> clearedFields(YorksV1RentalPropertyDetail after) {
    final saved = _values(after);
    return [
      for (final key in updatedFields(after))
        if (_normal(saved[key]) == null) key,
    ];
  }

  static const fieldKeys = [
    'unit_code',
    'property_name',
    'property_type',
    'municipality_number',
    'location',
    'description',
    'occupancy_state',
    'tenant_name',
    'trade_licence_number',
    'contact_number',
    'email',
    'contract_number',
    'contract_type',
    'contract_status',
    'signed_date',
    'lease_start',
    'lease_end',
    'monthly_rent',
    'annual_rent',
    'billing_start',
    'security_deposit',
    'monthly_due_day',
    'grace_period_days',
    'default_payment_method',
    'payment_frequency',
    'contract_cheque_count',
    'annual_escalation_percent',
    'renewal_notice_days',
    'lease_notes',
  ];

  static Object? _normal(Object? value) =>
      value is String ? (value.trim().isEmpty ? null : value.trim()) : value;

  static String? _date(DateTime? value) =>
      value?.toIso8601String().split('T').first;

  static Map<String, Object?> _values(YorksV1RentalPropertyDetail detail) {
    final p = detail.property;
    final values = <String, Object?>{
      'unit_code': p.unitCode,
      'property_name': p.propertyName,
      'property_type': p.propertyType,
      'municipality_number': p.municipalityNumber,
      'location': p.location,
      'description': p.description,
      'occupancy_state': p.occupancy.wireValue,
      'tenant_name': p.tenantName,
      'trade_licence_number': p.tradeLicenceNumber,
      'contact_number': p.contactNumber,
      'email': p.email,
      'contract_number': p.contractNumber,
      'contract_type': p.contractType,
      'contract_status': p.contractStatus,
      'signed_date': _date(DateTime.tryParse('${detail.lease['signed_date']}')),
      'lease_start': _date(p.leaseStart),
      'lease_end': _date(p.leaseEnd),
      'monthly_rent': !p.isAnnual && p.hasRentAmount ? p.monthlyRent : null,
      'annual_rent': p.annualRent,
      'billing_start': _date(p.billingStart),
      'security_deposit': p.securityDeposit,
      'monthly_due_day': p.monthlyDueDay,
      'grace_period_days': p.gracePeriodDays,
      'default_payment_method': p.defaultPaymentMethod,
      'payment_frequency': p.paymentFrequency,
      'contract_cheque_count': detail.lease['contract_cheque_count'] ?? 0,
      'annual_escalation_percent': p.annualEscalationPercent,
      'renewal_notice_days': p.renewalNoticeDays,
      'lease_notes': detail.lease['notes'],
    };
    // A vacant unit can be saved without a lease. Its editor defaults are not
    // persisted lease facts and must not be advertised as saved details.
    if (p.leaseId == null) {
      for (final key in fieldKeys.skip(fieldKeys.indexOf('tenant_name'))) {
        values[key] = null;
      }
    }
    return values;
  }
}

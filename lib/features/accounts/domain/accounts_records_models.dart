enum YorksAccountsReportKind {
  portfolio('portfolio'),
  projectSummary('project_summary'),
  commercialBaseline('commercial_baseline'),
  buildingAllocations('building_allocations'),
  stageAllocations('stage_allocations'),
  billingProgress('billing_progress'),
  progressHistory('progress_history'),
  clientClaims('client_claims'),
  claimLines('claim_lines'),
  clientInvoices('client_invoices'),
  certifications('certifications'),
  clientReceipts('client_receipts'),
  pdcRegister('pdc_register'),
  pdcEvents('pdc_events'),
  supplierBills('supplier_bills'),
  supplierPayments('supplier_payments'),
  accountsDocuments('accounts_documents'),
  accountsActivity('accounts_activity');

  const YorksAccountsReportKind(this.wireValue);

  final String wireValue;
}

class YorksAccountsActivityFilters {
  const YorksAccountsActivityFilters({
    this.entityType,
    this.action,
    this.actorAuthUserId,
    this.from,
    this.to,
    this.limit = 50,
    this.offset = 0,
  });

  final String? entityType;
  final String? action;
  final String? actorAuthUserId;
  final DateTime? from;
  final DateTime? to;
  final int limit;
  final int offset;

  bool get isValid =>
      limit >= 1 &&
      limit <= 100 &&
      offset >= 0 &&
      (from == null || to == null || !from!.isAfter(to!));

  Map<String, Object?> toRpcParameters(String projectId) => {
    'p_project_id': projectId.trim(),
    'p_entity_type': _nullable(entityType),
    'p_action': _nullable(action),
    'p_actor_auth_user_id': _nullable(actorAuthUserId),
    'p_from': from?.toUtc().toIso8601String(),
    'p_to': to?.toUtc().toIso8601String(),
    'p_limit': limit,
    'p_offset': offset,
  };
}

class YorksAccountsActivityEntry {
  const YorksAccountsActivityEntry({
    required this.id,
    required this.eventType,
    required this.entityType,
    required this.entityId,
    required this.projectId,
    required this.actorAuthUserId,
    required this.actorDisplayName,
    required this.actorExactRole,
    required this.occurredAt,
    this.reason,
    this.idempotencyKey,
    this.beforeData,
    this.afterData,
    this.businessDate,
    this.context,
  });

  final String id;
  final String eventType;
  final String entityType;
  final String entityId;
  final String projectId;
  final String actorAuthUserId;
  final String actorDisplayName;
  final String actorExactRole;
  final DateTime occurredAt;
  final String? reason;
  final String? idempotencyKey;
  final Map<String, dynamic>? beforeData;
  final Map<String, dynamic>? afterData;

  /// The day it happened (`YYYY-MM-DD`): an invoice's date, a certification
  /// or cheque date, a claim's period end. Null from an older server; then
  /// [occurredAt] (when it was recorded) is the date.
  final String? businessDate;

  /// References that name the entry (invoice, cheque, claim number …), read
  /// from the record it touched. Money only with commercial access.
  final Map<String, dynamic>? context;

  factory YorksAccountsActivityEntry.fromRpcJson(Map<String, dynamic> json) =>
      YorksAccountsActivityEntry(
        id: _requiredString(json, 'id'),
        eventType: _requiredString(json, 'event_type'),
        entityType: _requiredString(json, 'entity_type'),
        entityId: _requiredString(json, 'entity_id'),
        projectId: _requiredString(json, 'project_id'),
        actorAuthUserId: _requiredString(json, 'actor_auth_user_id'),
        actorDisplayName: _requiredString(json, 'actor_display_name'),
        actorExactRole: _requiredString(json, 'actor_exact_role'),
        occurredAt: _requiredDate(json, 'occurred_at'),
        reason: _nullable(json['reason']),
        idempotencyKey: _nullable(json['idempotency_key']),
        beforeData: _nullableMap(json['before_data']),
        afterData: _nullableMap(json['after_data']),
        businessDate: _nullable(json['business_date']),
        context: _nullableMap(json['context']),
      );
}

class YorksAccountsActivityProjection {
  const YorksAccountsActivityProjection({
    required this.projectId,
    required this.total,
    required this.limit,
    required this.offset,
    required this.entries,
  });

  final String projectId;
  final int total;
  final int limit;
  final int offset;
  final List<YorksAccountsActivityEntry> entries;

  bool get hasMore => offset + entries.length < total;

  factory YorksAccountsActivityProjection.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksAccountsActivityProjection(
    projectId: _requiredString(json, 'project_id'),
    total: _nonNegativeInt(json['total']),
    limit: _positiveInt(json['limit']),
    offset: _nonNegativeInt(json['offset']),
    entries: _list(
      json['entries'],
    ).map(YorksAccountsActivityEntry.fromRpcJson).toList(growable: false),
  );
}

class YorksAccountsReportProjection {
  const YorksAccountsReportProjection({
    required this.reportKind,
    required this.currency,
    required this.accessContext,
    required this.generatedAt,
    required this.generatedByAuthUserId,
    required this.generatedByDisplayName,
    required this.columns,
    required this.rows,
    this.projectId,
    this.projectReference,
    this.projectName,
  });

  final String reportKind;
  final String? projectId;
  final String? projectReference;
  final String? projectName;
  final String currency;
  final String accessContext;
  final DateTime generatedAt;
  final String generatedByAuthUserId;
  final String generatedByDisplayName;
  final List<String> columns;
  final List<List<String>> rows;

  factory YorksAccountsReportProjection.fromRpcJson(Map<String, dynamic> json) {
    final columns = _rawList(
      json['columns'],
    ).map((value) => value?.toString() ?? '').toList(growable: false);
    if (columns.isEmpty) throw const FormatException('Report columns missing.');
    final rows = _rawList(json['rows'])
        .map((rawRow) {
          if (rawRow is! List || rawRow.length != columns.length) {
            throw const FormatException('Report row shape mismatch.');
          }
          return rawRow
              .map((value) => value?.toString() ?? '')
              .toList(growable: false);
        })
        .toList(growable: false);
    return YorksAccountsReportProjection(
      reportKind: _requiredString(json, 'report_kind'),
      projectId: _nullable(json['project_id']),
      projectReference: _nullable(json['project_reference']),
      projectName: _nullable(json['project_name']),
      currency: _requiredString(json, 'currency'),
      accessContext: _requiredString(json, 'access_context'),
      generatedAt: _requiredDate(json, 'generated_at'),
      generatedByAuthUserId: _requiredString(json, 'generated_by_auth_user_id'),
      generatedByDisplayName: _requiredString(
        json,
        'generated_by_display_name',
      ),
      columns: columns,
      rows: rows,
    );
  }
}

List<Map<String, dynamic>> _list(Object? value) => _rawList(value)
    .map((item) {
      if (item is! Map) {
        throw const FormatException('Expected response object.');
      }
      return Map<String, dynamic>.from(item);
    })
    .toList(growable: false);

List<dynamic> _rawList(Object? value) {
  if (value is! List) throw const FormatException('Expected response list.');
  return List<dynamic>.from(value);
}

Map<String, dynamic>? _nullableMap(Object? value) {
  if (value == null) return null;
  if (value is! Map) throw const FormatException('Expected response object.');
  return Map<String, dynamic>.from(value);
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _nullable(json[key]);
  if (value == null) throw FormatException('Missing $key.');
  return value;
}

String? _nullable(Object? value) {
  if (value == null) return null;
  final normalized = value.toString().trim();
  return normalized.isEmpty ? null : normalized;
}

DateTime _requiredDate(Map<String, dynamic> json, String key) {
  final value = _requiredString(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('Invalid $key.');
  return parsed;
}

int _positiveInt(Object? value) {
  final result = value is int ? value : int.tryParse(value?.toString() ?? '');
  if (result == null || result <= 0) {
    throw const FormatException('Expected positive integer.');
  }
  return result;
}

int _nonNegativeInt(Object? value) {
  final result = value is int ? value : int.tryParse(value?.toString() ?? '');
  if (result == null || result < 0) {
    throw const FormatException('Expected non-negative integer.');
  }
  return result;
}

/// Worker Records: the protected employment record kept beside a Workforce
/// worker (company, trade licence, passport, salary breakdown, photo).
///
/// Every value comes from the `v1_list_worker_records` / `v1_get_worker_record`
/// projections, which the server returns only to holders of
/// `worker_records.view`. Money stays a validated decimal string end to end;
/// it is never parsed through a binary float.
library;

final RegExp _money = RegExp(r'^\d{1,11}(\.\d{1,2})?$');

String _requiredText(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Worker record field "$key" is missing.');
  }
  return value.trim();
}

String? _optionalText(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('Worker record field "$key" is not text.');
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// A non-negative decimal with at most two places, or null when the server
/// reports the amount as not entered. A missing amount is never read as zero.
String? _optionalMoney(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || !_money.hasMatch(value)) {
    throw FormatException('Worker record amount "$key" is malformed.');
  }
  return value;
}

String _requiredMoney(Map<String, dynamic> json, String key) =>
    _optionalMoney(json, key) ??
    (throw FormatException('Worker record amount "$key" is missing.'));

int _nonNegativeInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num || value < 0 || value != value.roundToDouble()) {
    throw FormatException('Worker record count "$key" is malformed.');
  }
  return value.toInt();
}

/// `1200` → `1,200.00`. Returns an em dash for an amount that was not entered.
String yorksV1FormatWorkerMoney(String? amount) {
  if (amount == null) return '—';
  final parts = amount.split('.');
  final whole = parts.first;
  final fraction = (parts.length > 1 ? parts[1] : '').padRight(2, '0');
  final grouped = StringBuffer();
  for (var index = 0; index < whole.length; index++) {
    if (index > 0 && (whole.length - index) % 3 == 0) grouped.write(',');
    grouped.write(whole[index]);
  }
  return '$grouped.$fraction';
}

enum YorksV1WorkerStatus {
  active('active'),
  inactive('inactive'),
  leftCompany('left_company'),
  suspended('suspended');

  const YorksV1WorkerStatus(this.wireValue);

  final String wireValue;

  static YorksV1WorkerStatus fromWireValue(Object? value) => values.firstWhere(
    (status) => status.wireValue == value,
    orElse: () =>
        throw const FormatException('Worker status is not recognized.'),
  );
}

class YorksV1WorkerRecord {
  const YorksV1WorkerRecord({
    required this.workerId,
    required this.workerNumber,
    required this.fullName,
    required this.designation,
    required this.employerCompany,
    required this.status,
    required this.hasRecord,
    required this.recordVersion,
    this.tradeLicenseNo,
    this.passportNo,
    this.basicSalary,
    this.housingAllowance,
    this.otherAllowance,
    this.totalSalary,
    this.photoObjectPath,
    this.updatedAt,
    this.updatedByName,
    this.updatedByRole,
  });

  final String workerId;
  final String workerNumber;
  final String fullName;
  final String designation;
  final String employerCompany;
  final YorksV1WorkerStatus status;

  /// False when the worker exists only in Workforce and no employment record
  /// has been entered yet.
  final bool hasRecord;
  final int recordVersion;
  final String? tradeLicenseNo;
  final String? passportNo;
  final String? basicSalary;
  final String? housingAllowance;
  final String? otherAllowance;

  /// Null when no employment record exists; otherwise the server-computed sum.
  final String? totalSalary;
  final String? photoObjectPath;
  final DateTime? updatedAt;
  final String? updatedByName;
  final String? updatedByRole;

  factory YorksV1WorkerRecord.fromRpcJson(Map<String, dynamic> json) {
    final hasRecord = json['has_record'];
    if (hasRecord is! bool) {
      throw const FormatException('Worker record state is missing.');
    }
    final updatedAtText = _optionalText(json, 'updated_at');
    final updatedAt = updatedAtText == null
        ? null
        : DateTime.tryParse(updatedAtText);
    if (updatedAtText != null && updatedAt == null) {
      throw const FormatException('Worker record timestamp is malformed.');
    }
    return YorksV1WorkerRecord(
      workerId: _requiredText(json, 'worker_id'),
      workerNumber: _requiredText(json, 'worker_number'),
      fullName: _requiredText(json, 'full_name'),
      designation: _requiredText(json, 'designation'),
      employerCompany: _requiredText(json, 'employer_company'),
      status: YorksV1WorkerStatus.fromWireValue(json['current_status']),
      hasRecord: hasRecord,
      recordVersion: _nonNegativeInt(json, 'record_version'),
      tradeLicenseNo: _optionalText(json, 'trade_license_no'),
      passportNo: _optionalText(json, 'passport_no'),
      basicSalary: _optionalMoney(json, 'basic_salary'),
      housingAllowance: _optionalMoney(json, 'housing_allowance'),
      otherAllowance: _optionalMoney(json, 'other_allowance'),
      totalSalary: hasRecord ? _optionalMoney(json, 'total_salary') : null,
      photoObjectPath: _optionalText(json, 'photo_object_path'),
      updatedAt: updatedAt?.toUtc(),
      updatedByName: _optionalText(json, 'updated_by_name'),
      updatedByRole: _optionalText(json, 'updated_by_role'),
    );
  }
}

class YorksV1WorkerRecordTotals {
  const YorksV1WorkerRecordTotals({
    required this.basicSalary,
    required this.housingAllowance,
    required this.otherAllowance,
    required this.totalSalary,
  });

  final String basicSalary;
  final String housingAllowance;
  final String otherAllowance;
  final String totalSalary;

  factory YorksV1WorkerRecordTotals.fromRpcJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Worker record totals are missing.');
    }
    final json = Map<String, dynamic>.from(raw);
    return YorksV1WorkerRecordTotals(
      basicSalary: _requiredMoney(json, 'basic_salary'),
      housingAllowance: _requiredMoney(json, 'housing_allowance'),
      otherAllowance: _requiredMoney(json, 'other_allowance'),
      totalSalary: _requiredMoney(json, 'total_salary'),
    );
  }
}

/// Filters for one register read. Value equality lets a controller detect a
/// stale response.
class YorksV1WorkerRecordQuery {
  const YorksV1WorkerRecordQuery({
    this.search = '',
    this.company,
    this.status,
    this.limit = 50,
    this.offset = 0,
  });

  final String search;
  final String? company;
  final YorksV1WorkerStatus? status;
  final int limit;
  final int offset;

  YorksV1WorkerRecordQuery copyWith({
    String? search,
    String? company,
    bool clearCompany = false,
    YorksV1WorkerStatus? status,
    bool clearStatus = false,
    int? offset,
  }) => YorksV1WorkerRecordQuery(
    search: search ?? this.search,
    company: clearCompany ? null : company ?? this.company,
    status: clearStatus ? null : status ?? this.status,
    limit: limit,
    offset: offset ?? this.offset,
  );

  Map<String, Object?> toRpcParameters() => {
    'p_search': search.trim().isEmpty ? null : search.trim(),
    'p_company': company,
    'p_status': status?.wireValue,
    'p_limit': limit,
    'p_offset': offset,
  };

  @override
  bool operator ==(Object other) =>
      other is YorksV1WorkerRecordQuery &&
      other.search == search &&
      other.company == company &&
      other.status == status &&
      other.limit == limit &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(search, company, status, limit, offset);
}

class YorksV1WorkerRecordPage {
  const YorksV1WorkerRecordPage({
    required this.totalCount,
    required this.withRecordCount,
    required this.totals,
    required this.companies,
    required this.items,
  });

  /// Workers matching the filters, across every page.
  final int totalCount;
  final int withRecordCount;

  /// Sums over every matching worker, not only the loaded page.
  final YorksV1WorkerRecordTotals totals;
  final List<String> companies;
  final List<YorksV1WorkerRecord> items;

  factory YorksV1WorkerRecordPage.fromRpcJson(Map<String, dynamic> json) {
    if (json['schema_version'] != 1) {
      throw const FormatException('Worker record schema is not supported.');
    }
    final items = json['items'];
    final companies = json['companies'];
    if (items is! List || companies is! List) {
      throw const FormatException('Worker record list is malformed.');
    }
    return YorksV1WorkerRecordPage(
      totalCount: _nonNegativeInt(json, 'total_count'),
      withRecordCount: _nonNegativeInt(json, 'with_record_count'),
      totals: YorksV1WorkerRecordTotals.fromRpcJson(json['totals']),
      companies: List.unmodifiable([
        for (final company in companies)
          if (company is String && company.trim().isNotEmpty) company.trim(),
      ]),
      items: List.unmodifiable([
        for (final item in items)
          if (item is Map)
            YorksV1WorkerRecord.fromRpcJson(Map<String, dynamic>.from(item))
          else
            throw const FormatException('Worker record row is malformed.'),
      ]),
    );
  }
}

/// Whether [text] is an amount the server accepts: digits with at most two
/// decimal places. Blank is valid and means "not entered".
bool yorksV1IsValidWorkerAmount(String text) {
  final trimmed = text.trim();
  return trimmed.isEmpty || RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(trimmed);
}

/// Exact sum of entered amounts, in whole fils, without binary floats.
/// Returns null when no amount is entered or any amount is malformed.
String? yorksV1SumWorkerAmounts(Iterable<String> amounts) {
  var total = BigInt.zero;
  var any = false;
  for (final raw in amounts) {
    final text = raw.trim();
    if (text.isEmpty) continue;
    if (!yorksV1IsValidWorkerAmount(text)) return null;
    final parts = text.split('.');
    final fraction = (parts.length > 1 ? parts[1] : '').padRight(2, '0');
    total +=
        BigInt.parse(parts.first) * BigInt.from(100) + BigInt.parse(fraction);
    any = true;
  }
  if (!any) return null;
  final whole = total ~/ BigInt.from(100);
  final fils = (total % BigInt.from(100)).toString().padLeft(2, '0');
  return '$whole.$fils';
}

/// One create-or-update command. [workerId] null creates a new worker, which
/// then needs [joiningDate]. [expectedVersion] is the employment record
/// version the form was opened with (0 when the worker had no record yet).
class YorksV1SaveWorkerRecordInput {
  const YorksV1SaveWorkerRecordInput({
    required this.fullName,
    required this.designation,
    required this.employerCompany,
    required this.idempotencyKey,
    this.workerId,
    this.expectedVersion,
    this.joiningDate,
    this.tradeLicenseNo = '',
    this.passportNo = '',
    this.basicSalary = '',
    this.housingAllowance = '',
    this.otherAllowance = '',
  });

  final String? workerId;
  final int? expectedVersion;
  final String fullName;
  final String designation;
  final String employerCompany;

  /// `yyyy-MM-dd`; required for a new worker only.
  final String? joiningDate;
  final String tradeLicenseNo;
  final String passportNo;
  final String basicSalary;
  final String housingAllowance;
  final String otherAllowance;
  final String idempotencyKey;

  static String? _blankToNull(String value) =>
      value.trim().isEmpty ? null : value.trim();

  Map<String, Object?> toRpcPayload() => {
    if (workerId != null) 'worker_id': workerId,
    'full_name': fullName.trim(),
    'designation': designation.trim(),
    'employer_company': employerCompany.trim(),
    if (workerId == null) 'joining_date': joiningDate,
    'trade_license_no': _blankToNull(tradeLicenseNo),
    'passport_no': _blankToNull(passportNo),
    'basic_salary': _blankToNull(basicSalary),
    'housing_allowance': _blankToNull(housingAllowance),
    'other_allowance': _blankToNull(otherAllowance),
  };

  /// Stable text of everything the command sends, so a retry of the same
  /// input can reuse its idempotency key and a changed input gets a new one.
  String get signature =>
      '$workerId|$expectedVersion|${toRpcPayload().values.join('|')}';
}

enum YorksV1WorkerImportAction {
  create('create'),
  update('update'),
  unchanged('unchanged'),
  error('error');

  const YorksV1WorkerImportAction(this.wireValue);

  final String wireValue;

  static YorksV1WorkerImportAction fromWireValue(Object? value) =>
      values.firstWhere(
        (action) => action.wireValue == value,
        orElse: () =>
            throw const FormatException('Import action is not recognized.'),
      );
}

/// The server's verdict on one sheet row. [raw] is sent back unchanged with
/// the import so the server can refuse it if the data changed meanwhile.
class YorksV1WorkerImportRowResult {
  const YorksV1WorkerImportRowResult({
    required this.action,
    required this.errors,
    required this.changedFields,
    required this.raw,
  });

  final YorksV1WorkerImportAction action;
  final List<String> errors;
  final List<String> changedFields;
  final Map<String, dynamic> raw;

  factory YorksV1WorkerImportRowResult.fromRpcJson(Map<String, dynamic> json) {
    List<String> strings(Object? value) => value is List
        ? List.unmodifiable(value.whereType<String>())
        : throw const FormatException('Import row lists are malformed.');
    return YorksV1WorkerImportRowResult(
      action: YorksV1WorkerImportAction.fromWireValue(json['action']),
      errors: strings(json['errors']),
      changedFields: strings(json['changed_fields']),
      raw: Map.unmodifiable(json),
    );
  }
}

class YorksV1WorkerImportPreview {
  const YorksV1WorkerImportPreview({
    required this.rows,
    required this.createCount,
    required this.updateCount,
    required this.unchangedCount,
    required this.errorCount,
  });

  final List<YorksV1WorkerImportRowResult> rows;
  final int createCount;
  final int updateCount;
  final int unchangedCount;
  final int errorCount;

  factory YorksV1WorkerImportPreview.fromRpcJson(Map<String, dynamic> json) {
    final rows = json['rows'];
    if (json['schema_version'] != 1 || rows is! List) {
      throw const FormatException('Import preview is malformed.');
    }
    return YorksV1WorkerImportPreview(
      rows: List.unmodifiable([
        for (final row in rows)
          if (row is Map)
            YorksV1WorkerImportRowResult.fromRpcJson(
              Map<String, dynamic>.from(row),
            )
          else
            throw const FormatException('Import preview row is malformed.'),
      ]),
      createCount: _nonNegativeInt(json, 'create_count'),
      updateCount: _nonNegativeInt(json, 'update_count'),
      unchangedCount: _nonNegativeInt(json, 'unchanged_count'),
      errorCount: _nonNegativeInt(json, 'error_count'),
    );
  }
}

class YorksV1WorkerImportResult {
  const YorksV1WorkerImportResult({
    required this.createdCount,
    required this.updatedCount,
    required this.unchangedCount,
  });

  final int createdCount;
  final int updatedCount;
  final int unchangedCount;

  factory YorksV1WorkerImportResult.fromRpcJson(Map<String, dynamic> json) =>
      YorksV1WorkerImportResult(
        createdCount: _nonNegativeInt(json, 'created_count'),
        updatedCount: _nonNegativeInt(json, 'updated_count'),
        unchangedCount: _nonNegativeInt(json, 'unchanged_count'),
      );
}

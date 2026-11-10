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

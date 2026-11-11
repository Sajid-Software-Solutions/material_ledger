import 'yorks_v1_domain_error.dart';

/// Filters for the read-only project Material Summary.
///
/// Dates are calendar dates in Asia/Dubai, inclusive. They are compared with
/// the date each Material Request was submitted, never with dispatch dates.
class YorksV1MaterialSummaryQuery {
  const YorksV1MaterialSummaryQuery({
    required this.projectId,
    this.from,
    this.to,
    this.scopeId,
    this.search,
  });

  final String projectId;
  final DateTime? from;
  final DateTime? to;
  final String? scopeId;
  final String? search;

  /// Normalized search text sent to the server: trimmed, single-spaced and
  /// bounded to the server limit.
  String? get normalizedSearch {
    final text = (search ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return null;
    return text.length > maxSearchLength
        ? text.substring(0, maxSearchLength)
        : text;
  }

  static const maxSearchLength = 120;

  bool get hasFilters =>
      from != null || to != null || scopeId != null || normalizedSearch != null;

  YorksV1MaterialSummaryQuery copyWith({
    DateTime? from,
    DateTime? to,
    String? scopeId,
    String? search,
    bool clearDates = false,
    bool clearScope = false,
  }) => YorksV1MaterialSummaryQuery(
    projectId: projectId,
    from: clearDates ? null : (from ?? this.from),
    to: clearDates ? null : (to ?? this.to),
    scopeId: clearScope ? null : (scopeId ?? this.scopeId),
    search: search ?? this.search,
  );

  Map<String, Object?> toRpcParameters() => {
    'p_project_id': projectId,
    'p_from': from == null ? null : yorksV1MaterialSummaryDateKey(from!),
    'p_to': to == null ? null : yorksV1MaterialSummaryDateKey(to!),
    'p_scope_id': scopeId,
    'p_search': normalizedSearch,
  };

  @override
  bool operator ==(Object other) =>
      other is YorksV1MaterialSummaryQuery &&
      other.projectId == projectId &&
      _sameDay(other.from, from) &&
      _sameDay(other.to, to) &&
      other.scopeId == scopeId &&
      other.normalizedSearch == normalizedSearch;

  @override
  int get hashCode => Object.hash(
    projectId,
    from == null ? null : yorksV1MaterialSummaryDateKey(from!),
    to == null ? null : yorksV1MaterialSummaryDateKey(to!),
    scopeId,
    normalizedSearch,
  );
}

enum YorksV1MaterialSummaryGranularity { month, week }

class YorksV1MaterialSummaryScope {
  const YorksV1MaterialSummaryScope({
    required this.id,
    required this.name,
    required this.isCommon,
    required this.isActive,
  });

  final String id;
  final String name;
  final bool isCommon;
  final bool isActive;

  factory YorksV1MaterialSummaryScope.fromRpcJson(Map<String, dynamic> json) =>
      YorksV1MaterialSummaryScope(
        id: _requiredString(json, 'id'),
        name: _requiredString(json, 'name'),
        isCommon: json['scope_kind'] == 'common',
        isActive: json['is_active'] != false,
      );
}

/// A submitted Material Request that carried at least one summarized item.
class YorksV1MaterialSummaryRequest {
  const YorksV1MaterialSummaryRequest({
    required this.id,
    required this.number,
    required this.requestedOn,
    this.scopeId,
  });

  final String id;
  final String number;

  /// Submission date in Asia/Dubai (date only).
  final DateTime requestedOn;
  final String? scopeId;

  factory YorksV1MaterialSummaryRequest.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksV1MaterialSummaryRequest(
    id: _requiredString(json, 'id'),
    number: _requiredString(json, 'number'),
    requestedOn: _requiredDate(json['requested_on']),
    scopeId: _trimToNull(json['scope_id']),
  );
}

/// Quantities for one item. Values are exact decimal strings from Postgres;
/// doubles are used only for derived display percentages.
class YorksV1MaterialSummaryQuantities {
  const YorksV1MaterialSummaryQuantities({
    required this.requested,
    required this.sent,
    required this.returned,
  });

  final String requested;
  final String sent;
  final String returned;

  double get requestedValue => _number(requested);
  double get sentValue => _number(sent);
  double get returnedValue => _number(returned);

  /// Sent ÷ requested, or null when nothing was requested (for example a
  /// cancelled request whose earlier dispatch is still reported).
  double? get sentOfRequested {
    final base = requestedValue;
    if (base <= 0) return null;
    return sentValue / base;
  }

  bool get fullySent => requestedValue > 0 && sentValue >= requestedValue;

  bool get awaitingDispatch => requestedValue > sentValue;
}

class YorksV1MaterialSummaryItem extends YorksV1MaterialSummaryQuantities {
  const YorksV1MaterialSummaryItem({
    required this.index,
    required this.key,
    required this.description,
    required this.unit,
    required this.brandOrigins,
    required this.itemCodes,
    required super.requested,
    required super.sent,
    required super.returned,
    required this.firstRequestedOn,
    required this.lastRequestedOn,
    required this.requestRefs,
  });

  final int index;
  final String key;
  final String description;
  final String unit;
  final List<String> brandOrigins;
  final List<String> itemCodes;
  final DateTime firstRequestedOn;
  final DateTime lastRequestedOn;

  /// Indexes into [YorksV1ProjectMaterialSummary.requests].
  final List<int> requestRefs;

  factory YorksV1MaterialSummaryItem.fromRpcJson(
    int index,
    Map<String, dynamic> json,
  ) => YorksV1MaterialSummaryItem(
    index: index,
    key: _requiredString(json, 'key'),
    description: _requiredString(json, 'item_description'),
    unit: _requiredString(json, 'unit'),
    brandOrigins: _stringList(json['brand_origins']),
    itemCodes: _stringList(json['item_codes']),
    requested: _quantity(json['requested_qty']),
    sent: _quantity(json['sent_qty']),
    returned: _quantity(json['returned_qty']),
    firstRequestedOn: _requiredDate(json['first_requested_on']),
    lastRequestedOn: _requiredDate(json['last_requested_on']),
    requestRefs: _intList(json['request_refs']),
  );
}

class YorksV1MaterialSummaryPeriodLine
    extends YorksV1MaterialSummaryQuantities {
  const YorksV1MaterialSummaryPeriodLine({
    required this.itemIndex,
    required super.requested,
    required super.sent,
    required super.returned,
    required this.requestRefs,
  });

  final int itemIndex;
  final List<int> requestRefs;
}

class YorksV1MaterialSummaryPeriod {
  const YorksV1MaterialSummaryPeriod({
    required this.granularity,
    required this.start,
    required this.lines,
  });

  final YorksV1MaterialSummaryGranularity granularity;

  /// First day: the 1st of the month, or the Monday of the week.
  final DateTime start;
  final List<YorksV1MaterialSummaryPeriodLine> lines;

  /// Last day, inclusive: month end or the Sunday of the week.
  DateTime get end => switch (granularity) {
    YorksV1MaterialSummaryGranularity.month => DateTime.utc(
      start.year,
      start.month + 1,
      0,
    ),
    YorksV1MaterialSummaryGranularity.week => start.add(
      const Duration(days: 6),
    ),
  };

  Set<int> get requestRefs => {for (final line in lines) ...line.requestRefs};
}

/// Read-only, non-commercial project Material Summary.
class YorksV1ProjectMaterialSummary {
  const YorksV1ProjectMaterialSummary({
    required this.projectId,
    required this.generatedAt,
    required this.scopes,
    required this.requests,
    required this.items,
    required this.months,
    required this.weeks,
  });

  final String projectId;
  final DateTime generatedAt;
  final List<YorksV1MaterialSummaryScope> scopes;
  final List<YorksV1MaterialSummaryRequest> requests;
  final List<YorksV1MaterialSummaryItem> items;

  /// Newest first.
  final List<YorksV1MaterialSummaryPeriod> months;

  /// Newest first. Weeks run Monday to Sunday.
  final List<YorksV1MaterialSummaryPeriod> weeks;

  bool get isEmpty => items.isEmpty;

  int get fullySentCount => items.where((item) => item.fullySent).length;

  int get awaitingDispatchCount =>
      items.where((item) => item.awaitingDispatch).length;

  YorksV1MaterialSummaryRequest? request(int index) =>
      index >= 0 && index < requests.length ? requests[index] : null;

  YorksV1MaterialSummaryItem? item(int index) =>
      index >= 0 && index < items.length ? items[index] : null;

  List<YorksV1MaterialSummaryRequest> requestsFor(Iterable<int> refs) {
    final resolved = <YorksV1MaterialSummaryRequest>[];
    for (final ref in refs.toSet().toList()..sort()) {
      final value = request(ref);
      if (value != null) resolved.add(value);
    }
    return resolved;
  }

  String? scopeName(String? scopeId) {
    if (scopeId == null) return null;
    for (final scope in scopes) {
      if (scope.id == scopeId) return scope.name;
    }
    return null;
  }

  /// Share of an item's total quantity that falls in one period. The base is
  /// requested quantity; when nothing was requested (cancelled requests with
  /// earlier dispatches) the base is sent quantity. Units never mix because
  /// the ratio is always within a single item.
  double? shareOfItem(YorksV1MaterialSummaryPeriodLine line) {
    final total = item(line.itemIndex);
    if (total == null) return null;
    if (total.requestedValue > 0) {
      return line.requestedValue / total.requestedValue;
    }
    if (total.sentValue > 0) return line.sentValue / total.sentValue;
    return null;
  }

  factory YorksV1ProjectMaterialSummary.fromRpcJson(Object? response) {
    if (response is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    final json = Map<String, dynamic>.from(response);
    final items = <YorksV1MaterialSummaryItem>[];
    final rawItems = _list(json['items']);
    for (var index = 0; index < rawItems.length; index++) {
      items.add(
        YorksV1MaterialSummaryItem.fromRpcJson(index, _map(rawItems[index])),
      );
    }
    final requests = [
      for (final row in _list(json['requests']))
        YorksV1MaterialSummaryRequest.fromRpcJson(_map(row)),
    ];
    return YorksV1ProjectMaterialSummary(
      projectId: _requiredString(json, 'project_id'),
      generatedAt:
          DateTime.tryParse('${json['generated_at']}')?.toUtc() ??
          DateTime.now().toUtc(),
      scopes: [
        for (final row in _list(json['scopes']))
          YorksV1MaterialSummaryScope.fromRpcJson(_map(row)),
      ],
      requests: requests,
      items: items,
      months: _periods(
        json['months'],
        YorksV1MaterialSummaryGranularity.month,
        items.length,
      ),
      weeks: _periods(
        json['weeks'],
        YorksV1MaterialSummaryGranularity.week,
        items.length,
      ),
    );
  }

  /// Decodes compact period rows:
  /// `[period_start, item_index, requested, sent, returned, [request_index]]`.
  static List<YorksV1MaterialSummaryPeriod> _periods(
    Object? value,
    YorksV1MaterialSummaryGranularity granularity,
    int itemCount,
  ) {
    final grouped = <String, List<YorksV1MaterialSummaryPeriodLine>>{};
    final order = <String>[];
    for (final row in _list(value)) {
      if (row is! List || row.length < 6) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.unexpectedResponse,
        );
      }
      final start = _trimToNull(row[0]);
      final itemIndex = _int(row[1]);
      if (start == null || itemIndex == null || itemIndex >= itemCount) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.unexpectedResponse,
        );
      }
      final lines = grouped.putIfAbsent(start, () {
        order.add(start);
        return [];
      });
      lines.add(
        YorksV1MaterialSummaryPeriodLine(
          itemIndex: itemIndex,
          requested: _quantity(row[2]),
          sent: _quantity(row[3]),
          returned: _quantity(row[4]),
          requestRefs: _intList(row[5]),
        ),
      );
    }
    final periods = [
      for (final key in order)
        YorksV1MaterialSummaryPeriod(
          granularity: granularity,
          start: _requiredDate(key),
          lines: grouped[key]!..sort((a, b) => a.itemIndex - b.itemIndex),
        ),
    ];
    periods.sort((a, b) => b.start.compareTo(a.start));
    return periods;
  }
}

/// `yyyy-MM-dd` for a calendar date, independent of the device time zone.
String yorksV1MaterialSummaryDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Today's calendar date in Asia/Dubai (UTC+4, no daylight saving).
DateTime yorksV1GulfToday([DateTime? now]) {
  final gulf = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 4));
  return DateTime.utc(gulf.year, gulf.month, gulf.day);
}

/// Monday of the week containing [date].
DateTime yorksV1MaterialSummaryWeekStart(DateTime date) {
  final day = DateTime.utc(date.year, date.month, date.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

bool _sameDay(DateTime? a, DateTime? b) {
  if (a == null || b == null) return a == b;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

double _number(String value) => double.tryParse(value) ?? 0;

String _quantity(Object? value) {
  final text = switch (value) {
    String text => text.trim(),
    num number => number.toString(),
    _ => '',
  };
  if (!RegExp(r'^-?\d+(\.\d+)?$').hasMatch(text)) {
    throw const YorksV1DomainException(
      YorksV1DomainErrorCode.unexpectedResponse,
    );
  }
  return text;
}

List<Object?> _list(Object? value) => value is List ? value : const [];

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) {
    throw const YorksV1DomainException(
      YorksV1DomainErrorCode.unexpectedResponse,
    );
  }
  return Map<String, dynamic>.from(value);
}

List<String> _stringList(Object? value) => [
  for (final entry in _list(value)) ?_trimToNull(entry),
];

List<int> _intList(Object? value) => [
  for (final entry in _list(value))
    if (_int(entry) case final number? when number >= 0) number,
];

int? _int(Object? value) => switch (value) {
  int number => number,
  num number when number == number.roundToDouble() => number.toInt(),
  String text => int.tryParse(text.trim()),
  _ => null,
};

String? _trimToNull(Object? value) {
  final text = switch (value) {
    String text => text,
    num number => number.toString(),
    _ => '',
  }.trim();
  return text.isEmpty ? null : text;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _trimToNull(json[key]);
  if (value == null) {
    throw const YorksV1DomainException(
      YorksV1DomainErrorCode.unexpectedResponse,
    );
  }
  return value;
}

DateTime _requiredDate(Object? value) {
  final text = _trimToNull(value);
  final match = text == null
      ? null
      : RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
  if (match == null) {
    throw const YorksV1DomainException(
      YorksV1DomainErrorCode.unexpectedResponse,
    );
  }
  return DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

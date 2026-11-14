/// Company documents: licences and permits per company and branch,
/// company certificates, vehicles, insurance policies and CICPA passes
/// (docs/yorks-v1/COMPANY_DOCUMENTS.md). Wire shapes of the
/// `v1_company_docs_*` functions.
library;

import 'yorks_v1_people.dart' show PeopleDocumentStatus;

export 'yorks_v1_people.dart' show PeopleDocumentStatus;

String _s(Object? value) => value?.toString() ?? '';
String? _ns(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int? _ni(Object? value) => switch (value) {
  final num number => number.toInt(),
  final String text => int.tryParse(text),
  _ => null,
};

int _i(Object? value) => _ni(value) ?? 0;

DateTime? _dt(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

List<Map<String, dynamic>> _list(Object? value) => [
  for (final item in (value as List? ?? const []))
    if (item is Map) Map<String, dynamic>.from(item),
];

/// What a record is.
enum CompanyRecordKind {
  /// A company or branch holding a trade licence.
  entity('entity'),

  /// A company-wide certificate or permit (ISO, Civil Defence, CMW…).
  item('item'),
  vehicle('vehicle'),
  policy('policy'),
  contract('contract');

  const CompanyRecordKind(this.wire);
  final String wire;

  static CompanyRecordKind from(Object? value) => values.firstWhere(
    (kind) => kind.wire == value,
    orElse: () => CompanyRecordKind.item,
  );
}

/// The documents a record may hold, in the order they are shown.
enum CompanyDocumentKind {
  licence('licence'),
  establishmentCard('establishment_card'),
  labourFile('labour_file'),
  proCard('pro_card'),
  registration('registration'),
  asateelPermit('asateel_permit'),
  cicpaPass('cicpa_pass'),
  insurance('insurance'),
  contract('contract'),
  certificate('certificate'),
  other('other');

  const CompanyDocumentKind(this.wire);
  final String wire;

  static CompanyDocumentKind from(Object? value) => values.firstWhere(
    (kind) => kind.wire == value,
    orElse: () => CompanyDocumentKind.other,
  );

  /// The kinds offered first when adding a document to a record.
  static List<CompanyDocumentKind> suggestedFor(CompanyRecordKind kind) =>
      switch (kind) {
        CompanyRecordKind.entity => const [
          licence,
          establishmentCard,
          labourFile,
          proCard,
          certificate,
          other,
        ],
        CompanyRecordKind.vehicle => const [
          registration,
          asateelPermit,
          cicpaPass,
          insurance,
          other,
        ],
        CompanyRecordKind.policy => const [insurance, other],
        CompanyRecordKind.contract => const [contract, cicpaPass, other],
        CompanyRecordKind.item => const [certificate, licence, other],
      };

  /// The documents a record of this kind is expected to hold; the record
  /// page offers an empty row for each one not yet recorded.
  static List<CompanyDocumentKind> expectedFor(CompanyRecordKind kind) =>
      switch (kind) {
        CompanyRecordKind.entity => const [
          licence,
          establishmentCard,
          labourFile,
        ],
        CompanyRecordKind.vehicle => const [registration, asateelPermit],
        CompanyRecordKind.policy => const [insurance],
        CompanyRecordKind.contract => const [contract],
        CompanyRecordKind.item => const [certificate],
      };

  /// The document a new record of this kind usually starts with.
  static CompanyDocumentKind primaryFor(CompanyRecordKind kind) =>
      suggestedFor(kind).first;
}

final class CompanyDocument {
  const CompanyDocument({
    required this.id,
    required this.recordId,
    required this.kind,
    required this.status,
    required this.recordVersion,
    this.label,
    this.number,
    this.issueDate,
    this.expiryDate,
    this.daysLeft,
    this.sites,
    this.notes,
    this.isCurrent = true,
    this.endedAt,
    this.endedReason,
    this.updatedAt,
    this.updatedBy = '',
  });

  factory CompanyDocument.fromJson(Map<String, dynamic> json) =>
      CompanyDocument(
        id: _s(json['id']),
        recordId: _s(json['record_id']),
        kind: CompanyDocumentKind.from(json['kind']),
        status: PeopleDocumentStatus.from(json['status']),
        recordVersion: _i(json['record_version']),
        label: _ns(json['label']),
        number: _ns(json['number']),
        issueDate: _ns(json['issue_date']),
        expiryDate: _ns(json['expiry_date']),
        daysLeft: _ni(json['days_left']),
        sites: _ns(json['sites']),
        notes: _ns(json['notes']),
        isCurrent: json['is_current'] != false,
        endedAt: _dt(json['ended_at']),
        endedReason: _ns(json['ended_reason']),
        updatedAt: _dt(json['updated_at']),
        updatedBy: _s(json['updated_by']),
      );

  final String id;
  final String recordId;
  final CompanyDocumentKind kind;
  final PeopleDocumentStatus status;
  final int recordVersion;
  final String? label;
  final String? number;

  /// `YYYY-MM-DD`.
  final String? issueDate;
  final String? expiryDate;
  final int? daysLeft;
  final String? sites;
  final String? notes;
  final bool isCurrent;
  final DateTime? endedAt;
  final String? endedReason;
  final DateTime? updatedAt;
  final String updatedBy;
}

/// A CICPA pass record's job and pass counts (from its LOA).
final class CompanyContractDetails {
  const CompanyContractDetails({
    this.job,
    this.people,
    this.vehicles,
    this.appliedPeople,
    this.appliedVehicles,
  });

  factory CompanyContractDetails.fromJson(Map<String, dynamic>? json) =>
      CompanyContractDetails(
        job: _ns(json?['job']),
        people: _ni(json?['people']),
        vehicles: _ni(json?['vehicles']),
        appliedPeople: _ni(json?['applied_people']),
        appliedVehicles: _ni(json?['applied_vehicles']),
      );

  final String? job;
  final int? people;
  final int? vehicles;
  final int? appliedPeople;
  final int? appliedVehicles;

  bool get isEmpty =>
      job == null &&
      people == null &&
      vehicles == null &&
      appliedPeople == null &&
      appliedVehicles == null;

  Map<String, Object?> toJson() => {
    if (job != null && job!.trim().isNotEmpty) 'job': job!.trim(),
    if (people != null) 'people': people,
    if (vehicles != null) 'vehicles': vehicles,
    if (appliedPeople != null) 'applied_people': appliedPeople,
    if (appliedVehicles != null) 'applied_vehicles': appliedVehicles,
  };
}

final class CompanyHistoryEntry {
  const CompanyHistoryEntry({
    required this.entity,
    required this.action,
    required this.actorName,
    required this.actorRole,
    this.kind,
    this.label,
    this.reason,
    this.at,
  });

  factory CompanyHistoryEntry.fromJson(Map<String, dynamic> json) =>
      CompanyHistoryEntry(
        entity: _s(json['entity']),
        action: _s(json['action']),
        actorName: _s(json['actor_name']),
        actorRole: _s(json['actor_role']),
        kind: _ns(json['kind']),
        label: _ns(json['label']),
        reason: _ns(json['reason']),
        at: _dt(json['at']),
      );

  final String entity;
  final String action;
  final String actorName;
  final String actorRole;
  final String? kind;
  final String? label;
  final String? reason;
  final DateTime? at;
}

final class CompanyRecord {
  const CompanyRecord({
    required this.id,
    required this.kind,
    required this.name,
    required this.recordVersion,
    required this.documents,
    required this.attention,
    this.reference,
    this.owner,
    this.details = const CompanyContractDetails(),
    this.notes,
    this.archived = false,
    this.archivedAt,
    this.archivedReason,
    this.sourceNote,
    this.nextExpiry,
    this.previousDocuments = const [],
    this.history = const [],
    this.canManage = false,
    this.updatedAt,
  });

  factory CompanyRecord.fromJson(Map<String, dynamic> json) {
    final next = json['next_expiry'] is Map
        ? Map<String, dynamic>.from(json['next_expiry'] as Map)
        : null;
    return CompanyRecord(
      id: _s(json['id']),
      kind: CompanyRecordKind.from(json['kind']),
      name: _s(json['name']),
      recordVersion: _i(json['record_version']),
      documents: [
        for (final item in _list(json['documents']))
          CompanyDocument.fromJson(item),
      ],
      attention: PeopleDocumentStatus.from(json['attention']),
      reference: _ns(json['reference']),
      owner: _ns(json['owner']),
      details: CompanyContractDetails.fromJson(
        json['details'] is Map
            ? Map<String, dynamic>.from(json['details'] as Map)
            : null,
      ),
      notes: _ns(json['notes']),
      archived: json['status'] == 'archived',
      archivedAt: _dt(json['archived_at']),
      archivedReason: _ns(json['archived_reason']),
      sourceNote: _ns(json['source_note']),
      nextExpiry: next == null
          ? null
          : (
              kind: CompanyDocumentKind.from(next['kind']),
              label: _ns(next['label']),
              expiryDate: _s(next['expiry_date']),
              daysLeft: _i(next['days_left']),
            ),
      previousDocuments: [
        for (final item in _list(json['previous_documents']))
          CompanyDocument.fromJson(item),
      ],
      history: [
        for (final item in _list(json['history']))
          CompanyHistoryEntry.fromJson(item),
      ],
      canManage: json['can_manage'] == true,
      updatedAt: _dt(json['updated_at']),
    );
  }

  final String id;
  final CompanyRecordKind kind;
  final String name;
  final int recordVersion;
  final List<CompanyDocument> documents;
  final PeopleDocumentStatus attention;
  final String? reference;
  final String? owner;
  final CompanyContractDetails details;
  final String? notes;
  final bool archived;
  final DateTime? archivedAt;
  final String? archivedReason;
  final String? sourceNote;
  final ({
    CompanyDocumentKind kind,
    String? label,
    String expiryDate,
    int daysLeft,
  })?
  nextExpiry;
  final List<CompanyDocument> previousDocuments;
  final List<CompanyHistoryEntry> history;
  final bool canManage;
  final DateTime? updatedAt;

  /// The current document of a kind (and label), if held.
  CompanyDocument? current(CompanyDocumentKind kind) {
    for (final document in documents) {
      if (document.kind == kind) return document;
    }
    return null;
  }
}

final class CompanyAttentionItem {
  const CompanyAttentionItem({
    required this.document,
    required this.recordId,
    required this.recordKind,
    required this.recordName,
    this.reference,
    this.owner,
  });

  factory CompanyAttentionItem.fromJson(Map<String, dynamic> json) {
    final record = Map<String, dynamic>.from(json['record'] as Map? ?? {});
    return CompanyAttentionItem(
      document: CompanyDocument.fromJson(
        Map<String, dynamic>.from(json['document'] as Map? ?? {}),
      ),
      recordId: _s(record['id']),
      recordKind: CompanyRecordKind.from(record['kind']),
      recordName: _s(record['name']),
      reference: _ns(record['reference']),
      owner: _ns(record['owner']),
    );
  }

  final CompanyDocument document;
  final String recordId;
  final CompanyRecordKind recordKind;
  final String recordName;
  final String? reference;
  final String? owner;
}

final class CompanyOverview {
  const CompanyOverview({
    required this.today,
    required this.canManage,
    required this.total,
    required this.byKind,
    required this.expired,
    required this.expiring,
    required this.owners,
    required this.attention,
  });

  factory CompanyOverview.fromJson(Map<String, dynamic> json) {
    final counts = Map<String, dynamic>.from(json['counts'] as Map? ?? {});
    return CompanyOverview(
      today: _s(json['today']),
      canManage: json['can_manage'] == true,
      total: _i(counts['total']),
      byKind: {
        for (final kind in CompanyRecordKind.values)
          kind: _i(counts[kind.wire]),
      },
      expired: _i(counts['expired']),
      expiring: _i(counts['expiring']),
      owners: [
        for (final item in _list(json['owners']))
          (name: _s(item['name']), count: _i(item['count'])),
      ],
      attention: [
        for (final item in _list(json['attention']))
          CompanyAttentionItem.fromJson(item),
      ],
    );
  }

  final String today;
  final bool canManage;
  final int total;
  final Map<CompanyRecordKind, int> byKind;

  /// Records with at least one expired / soon-expiring current document.
  final int expired;
  final int expiring;
  final List<({String name, int count})> owners;
  final List<CompanyAttentionItem> attention;
}

/// What the register shows.
enum CompanyStatusFilter {
  attention('attention'),
  expired('expired'),
  expiring('expiring');

  const CompanyStatusFilter(this.wire);
  final String wire;
}

final class CompanyListQuery {
  const CompanyListQuery({
    this.kinds = const [],
    this.owner,
    this.search = '',
    this.status,
    this.includeArchived = false,
    this.sort = 'name',
    this.limit = 25,
    this.offset = 0,
  });

  final List<CompanyRecordKind> kinds;
  final String? owner;
  final String search;
  final CompanyStatusFilter? status;
  final bool includeArchived;
  final String sort;
  final int limit;
  final int offset;

  Map<String, Object?> toJson() => {
    if (kinds.isNotEmpty) 'kinds': [for (final kind in kinds) kind.wire],
    if (owner != null && owner!.isNotEmpty) 'owner': owner,
    if (search.trim().isNotEmpty) 'search': search.trim(),
    if (status != null) 'status': status!.wire,
    if (includeArchived) 'include_archived': true,
    'sort': sort,
    'limit': limit,
    'offset': offset,
  };

  @override
  bool operator ==(Object other) =>
      other is CompanyListQuery &&
      _sameKinds(other.kinds, kinds) &&
      other.owner == owner &&
      other.search == search &&
      other.status == status &&
      other.includeArchived == includeArchived &&
      other.sort == sort &&
      other.limit == limit &&
      other.offset == offset;

  static bool _sameKinds(List<CompanyRecordKind> a, List<CompanyRecordKind> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(kinds),
    owner,
    search,
    status,
    includeArchived,
    sort,
    limit,
    offset,
  );
}

final class CompanyListPage {
  const CompanyListPage({
    required this.today,
    required this.total,
    required this.offset,
    required this.limit,
    required this.rows,
  });

  factory CompanyListPage.fromJson(Map<String, dynamic> json) =>
      CompanyListPage(
        today: _s(json['today']),
        total: _i(json['total']),
        offset: _i(json['offset']),
        limit: _i(json['limit']),
        rows: [
          for (final item in _list(json['rows'])) CompanyRecord.fromJson(item),
        ],
      );

  final String today;
  final int total;
  final int offset;
  final int limit;
  final List<CompanyRecord> rows;
}

final class CompanySaveRecordInput {
  const CompanySaveRecordInput({
    required this.kind,
    required this.name,
    required this.expectedVersion,
    required this.idempotencyKey,
    this.recordId,
    this.reference,
    this.owner,
    this.details = const CompanyContractDetails(),
    this.notes,
  });

  final String? recordId;
  final CompanyRecordKind kind;
  final String name;
  final String? reference;
  final String? owner;
  final CompanyContractDetails details;
  final String? notes;
  final int expectedVersion;
  final String idempotencyKey;

  Map<String, Object?> toPayload() => {
    if (recordId != null) 'record_id': recordId else 'kind': kind.wire,
    'name': name.trim(),
    if (reference != null && reference!.trim().isNotEmpty)
      'reference': reference!.trim(),
    if (owner != null && owner!.trim().isNotEmpty) 'owner': owner!.trim(),
    if (kind == CompanyRecordKind.contract) 'details': details.toJson(),
    if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
  };
}

final class CompanySaveDocumentInput {
  const CompanySaveDocumentInput({
    required this.recordId,
    required this.kind,
    required this.expectedVersion,
    required this.idempotencyKey,
    this.documentId,
    this.renew = false,
    this.label,
    this.number,
    this.issueDate,
    this.expiryDate,
    this.sites,
    this.notes,
  });

  final String recordId;
  final String? documentId;
  final bool renew;
  final CompanyDocumentKind kind;
  final String? label;
  final String? number;
  final String? issueDate;
  final String? expiryDate;
  final String? sites;
  final String? notes;
  final int expectedVersion;
  final String idempotencyKey;

  Map<String, Object?> toPayload() => {
    'record_id': recordId,
    if (documentId != null) 'document_id': documentId,
    if (renew) 'renew': true,
    if (documentId == null) 'kind': kind.wire,
    if (label != null && label!.trim().isNotEmpty) 'label': label!.trim(),
    if (number != null && number!.trim().isNotEmpty) 'number': number!.trim(),
    if (issueDate != null) 'issue_date': issueDate,
    if (expiryDate != null) 'expiry_date': expiryDate,
    if (sites != null && sites!.trim().isNotEmpty) 'sites': sites!.trim(),
    if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
  };
}

final class CompanyImportRow {
  const CompanyImportRow({
    required this.kind,
    required this.name,
    required this.action,
    required this.changes,
    required this.problems,
    this.row,
    this.sheet,
    this.reference,
    this.owner,
    this.recordId,
  });

  factory CompanyImportRow.fromJson(Map<String, dynamic> json) =>
      CompanyImportRow(
        row: _ni(json['row']),
        sheet: _ns(json['sheet']),
        kind: CompanyRecordKind.from(json['kind']),
        name: _s(json['name']),
        reference: _ns(json['reference']),
        owner: _ns(json['owner']),
        action: _s(json['action']),
        recordId: _ns(json['record_id']),
        changes: [
          for (final item in (json['changes'] as List? ?? const []))
            item.toString(),
        ],
        problems: [
          for (final item in (json['problems'] as List? ?? const []))
            item.toString(),
        ],
      );

  final int? row;
  final String? sheet;
  final CompanyRecordKind kind;
  final String name;
  final String? reference;
  final String? owner;

  /// new, update, unchanged or problem.
  final String action;
  final String? recordId;
  final List<String> changes;
  final List<String> problems;
}

final class CompanyImportResult {
  const CompanyImportResult({
    required this.rows,
    required this.newCount,
    required this.updateCount,
    required this.unchangedCount,
    required this.problemCount,
    required this.documentsNew,
    required this.documentsRenewed,
    required this.documentsUpdated,
  });

  factory CompanyImportResult.fromJson(Map<String, dynamic> json) {
    final counts = Map<String, dynamic>.from(json['counts'] as Map? ?? {});
    return CompanyImportResult(
      rows: [
        for (final item in _list(json['rows'])) CompanyImportRow.fromJson(item),
      ],
      newCount: _i(counts['new']),
      updateCount: _i(counts['update']),
      unchangedCount: _i(counts['unchanged']),
      problemCount: _i(counts['problem']),
      documentsNew: _i(counts['documents_new']),
      documentsRenewed: _i(counts['documents_renewed']),
      documentsUpdated: _i(counts['documents_updated']),
    );
  }

  final List<CompanyImportRow> rows;
  final int newCount;
  final int updateCount;
  final int unchangedCount;
  final int problemCount;
  final int documentsNew;
  final int documentsRenewed;
  final int documentsUpdated;

  bool get hasProblems => problemCount > 0;
}

/// People records: staff and labour, their identity documents and site
/// passes (docs/yorks-v1/PEOPLE_RECORDS.md). Wire shapes of the
/// `v1_people_*` functions.
library;

import 'yorks_v1_attachments.dart';

export 'yorks_v1_attachments.dart';

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

/// The documents a person may hold, in the order they are shown.
enum PeopleDocumentKind {
  visa('visa', single: true),
  passport('passport', single: true),
  labourCard('labour_card', single: true),
  iloe('iloe', single: true),
  emiratesId('emirates_id', single: true),
  cicpaPass('cicpa_pass'),
  cmwPass('cmw_pass'),
  other('other');

  const PeopleDocumentKind(this.wire, {this.single = false});

  final String wire;

  /// Only one may be current: a second one is a renewal.
  final bool single;

  bool get isPass => this == cicpaPass || this == cmwPass;

  static PeopleDocumentKind from(Object? value) => values.firstWhere(
    (kind) => kind.wire == value,
    orElse: () => PeopleDocumentKind.other,
  );
}

/// How soon a document ends: expired, within 60 days, fine, or no expiry.
enum PeopleDocumentStatus {
  expired('expired'),
  expiring('expiring'),
  ok('ok'),
  noExpiry('no_expiry');

  const PeopleDocumentStatus(this.wire);
  final String wire;

  static PeopleDocumentStatus from(Object? value) => values.firstWhere(
    (status) => status.wire == value,
    orElse: () => PeopleDocumentStatus.noExpiry,
  );

  bool get needsAttention => this == expired || this == expiring;
}

enum PeopleCategory {
  staff('staff'),
  labour('labour');

  const PeopleCategory(this.wire);
  final String wire;

  static PeopleCategory from(Object? value) =>
      value == 'staff' ? PeopleCategory.staff : PeopleCategory.labour;
}

final class PeopleDocument {
  const PeopleDocument({
    required this.id,
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

  factory PeopleDocument.fromJson(Map<String, dynamic> json) => PeopleDocument(
    id: _s(json['id']),
    kind: PeopleDocumentKind.from(json['kind']),
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
  final PeopleDocumentKind kind;
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

final class PeopleHistoryEntry {
  const PeopleHistoryEntry({
    required this.entity,
    required this.action,
    required this.actorName,
    required this.actorRole,
    required this.changed,
    this.kind,
    this.reason,
    this.at,
  });

  factory PeopleHistoryEntry.fromJson(Map<String, dynamic> json) =>
      PeopleHistoryEntry(
        entity: _s(json['entity']),
        action: _s(json['action']),
        actorName: _s(json['actor_name']),
        actorRole: _s(json['actor_role']),
        changed: [
          for (final key in (json['changed'] as List? ?? const []))
            key.toString(),
        ],
        kind: _ns(json['kind']),
        reason: _ns(json['reason']),
        at: _dt(json['at']),
      );

  final String entity;
  final String action;
  final String actorName;
  final String actorRole;
  final List<String> changed;
  final String? kind;
  final String? reason;
  final DateTime? at;
}

/// A file kept with a person (PRODUCT_DECISIONS section 47).
typedef PeopleAttachment = RecordAttachment;

/// A person's attachments; the owner is the worker id.
typedef PeopleAttachments = RecordAttachments;

final class PeoplePerson {
  const PeoplePerson({
    required this.id,
    required this.number,
    required this.name,
    required this.company,
    required this.position,
    required this.status,
    required this.category,
    required this.recordVersion,
    required this.documents,
    required this.attention,
    this.workerType = '',
    this.joiningDate,
    this.mobile,
    this.hasProfile = false,
    this.arabicName,
    this.dateOfBirth,
    this.unifiedNumber,
    this.idProfession,
    this.sourceNote,
    this.nextExpiry,
    this.crewId,
    this.crewName,
    this.previousDocuments = const [],
    this.history = const [],
    this.canManage = false,
    this.updatedAt,
    this.account,
    this.notes = const [],
    this.canLink = false,
  });

  factory PeoplePerson.fromJson(Map<String, dynamic> json) {
    final crew = json['crew'] is Map
        ? Map<String, dynamic>.from(json['crew'] as Map)
        : null;
    final next = json['next_expiry'] is Map
        ? Map<String, dynamic>.from(json['next_expiry'] as Map)
        : null;
    return PeoplePerson(
      id: _s(json['id']),
      number: _s(json['number']),
      name: _s(json['name']),
      company: _s(json['company']),
      // The Workforce designation: the position held in the company.
      position: _s(json['profession']),
      status: _s(json['status']),
      category: PeopleCategory.from(json['category']),
      recordVersion: _i(json['record_version']),
      documents: [
        for (final item in _list(json['documents']))
          PeopleDocument.fromJson(item),
      ],
      attention: PeopleDocumentStatus.from(json['attention']),
      workerType: _s(json['worker_type']),
      joiningDate: _ns(json['joining_date']),
      mobile: _ns(json['mobile']),
      hasProfile: json['has_profile'] == true,
      arabicName: _ns(json['arabic_name']),
      dateOfBirth: _ns(json['date_of_birth']),
      unifiedNumber: _ns(json['unified_number']),
      idProfession: _ns(json['id_profession']),
      sourceNote: _ns(json['source_note']),
      nextExpiry: next == null
          ? null
          : (
              kind: PeopleDocumentKind.from(next['kind']),
              label: _ns(next['label']),
              expiryDate: _s(next['expiry_date']),
              daysLeft: _i(next['days_left']),
            ),
      crewId: crew == null ? null : _ns(crew['id']),
      crewName: crew == null ? null : _ns(crew['name']),
      previousDocuments: [
        for (final item in _list(json['previous_documents']))
          PeopleDocument.fromJson(item),
      ],
      history: [
        for (final item in _list(json['history']))
          PeopleHistoryEntry.fromJson(item),
      ],
      canManage: json['can_manage'] == true,
      updatedAt: _dt(json['updated_at']),
      account: json['account'] is Map
          ? PeopleAccount.fromJson(
              Map<String, dynamic>.from(json['account'] as Map),
            )
          : null,
      notes: [
        for (final item in _list(json['notes'])) PeopleNote.fromJson(item),
      ],
      canLink: json['can_link'] == true,
    );
  }

  final String id;
  final String number;
  final String name;
  final String company;

  /// The position held in the company (the Workforce designation), e.g.
  /// Project Engineer; "Not recorded" when unknown.
  final String position;

  /// The profession written on the visa and Emirates ID, e.g. Mechanical
  /// Engineer (PRODUCT_DECISIONS section 53).
  final String? idProfession;

  /// The Workforce status: active, inactive, left_company or suspended.
  final String status;
  final PeopleCategory category;

  /// The profile version the edit form opens with (0 when none yet).
  final int recordVersion;
  final List<PeopleDocument> documents;
  final PeopleDocumentStatus attention;
  final String workerType;
  final String? joiningDate;
  final String? mobile;
  final bool hasProfile;
  final String? arabicName;
  final String? dateOfBirth;
  final String? unifiedNumber;
  final String? sourceNote;
  final ({
    PeopleDocumentKind kind,
    String? label,
    String expiryDate,
    int daysLeft,
  })?
  nextExpiry;
  final String? crewId;
  final String? crewName;
  final List<PeopleDocument> previousDocuments;
  final List<PeopleHistoryEntry> history;
  final bool canManage;
  final DateTime? updatedAt;

  /// The app account this person signs in with, when linked.
  final PeopleAccount? account;

  /// Notes the person sent HR/PRO about their record, newest first.
  final List<PeopleNote> notes;

  /// HR/PRO and Admin may link or unlink the account.
  final bool canLink;

  /// The current document of a kind held once (visa, passport, …).
  PeopleDocument? current(PeopleDocumentKind kind) {
    for (final document in documents) {
      if (document.kind == kind) return document;
    }
    return null;
  }

  List<PeopleDocument> passes(PeopleDocumentKind kind) => [
    for (final document in documents)
      if (document.kind == kind) document,
  ];

  bool get isActive => status == 'active';
}

final class PeopleAttentionItem {
  const PeopleAttentionItem({
    required this.document,
    required this.personId,
    required this.personNumber,
    required this.personName,
    required this.company,
    required this.category,
  });

  factory PeopleAttentionItem.fromJson(Map<String, dynamic> json) {
    final person = Map<String, dynamic>.from(json['person'] as Map? ?? {});
    return PeopleAttentionItem(
      document: PeopleDocument.fromJson(
        Map<String, dynamic>.from(json['document'] as Map? ?? {}),
      ),
      personId: _s(person['id']),
      personNumber: _s(person['number']),
      personName: _s(person['name']),
      company: _s(person['company']),
      category: PeopleCategory.from(person['category']),
    );
  }

  final PeopleDocument document;
  final String personId;
  final String personNumber;
  final String personName;
  final String company;
  final PeopleCategory category;
}

final class PeopleOverview {
  const PeopleOverview({
    required this.today,
    required this.canManage,
    required this.total,
    required this.staff,
    required this.labour,
    required this.expired,
    required this.expiring,
    required this.noVisa,
    required this.byKind,
    required this.companies,
    required this.attention,
  });

  factory PeopleOverview.fromJson(Map<String, dynamic> json) {
    final counts = Map<String, dynamic>.from(json['counts'] as Map? ?? {});
    final byKind =
        <PeopleDocumentKind, ({int expired, int expiring, int total})>{};
    final kinds = json['by_kind'];
    if (kinds is Map) {
      kinds.forEach((key, value) {
        if (value is Map) {
          byKind[PeopleDocumentKind.from(key)] = (
            expired: _i(value['expired']),
            expiring: _i(value['expiring']),
            total: _i(value['total']),
          );
        }
      });
    }
    return PeopleOverview(
      today: _s(json['today']),
      canManage: json['can_manage'] == true,
      total: _i(counts['total']),
      staff: _i(counts['staff']),
      labour: _i(counts['labour']),
      expired: _i(counts['expired']),
      expiring: _i(counts['expiring']),
      noVisa: _i(counts['no_visa']),
      byKind: byKind,
      companies: [
        for (final item in _list(json['companies']))
          (name: _s(item['name']), count: _i(item['count'])),
      ],
      attention: [
        for (final item in _list(json['attention']))
          PeopleAttentionItem.fromJson(item),
      ],
    );
  }

  final String today;
  final bool canManage;
  final int total;
  final int staff;
  final int labour;

  /// People with at least one expired / soon-expiring current document.
  final int expired;
  final int expiring;
  final int noVisa;
  final Map<PeopleDocumentKind, ({int expired, int expiring, int total})>
  byKind;
  final List<({String name, int count})> companies;
  final List<PeopleAttentionItem> attention;
}

/// What the register shows.
enum PeopleStatusFilter {
  attention('attention'),
  expired('expired'),
  expiring('expiring'),
  noVisa('no_visa');

  const PeopleStatusFilter(this.wire);
  final String wire;
}

final class PeopleListQuery {
  const PeopleListQuery({
    this.category,
    this.company,
    this.search = '',
    this.status,
    this.sort = 'name',
    this.limit = 25,
    this.offset = 0,
  });

  final PeopleCategory? category;
  final String? company;
  final String search;
  final PeopleStatusFilter? status;
  final String sort;
  final int limit;
  final int offset;

  Map<String, Object?> toJson() => {
    if (category != null) 'category': category!.wire,
    if (company != null && company!.isNotEmpty) 'company': company,
    if (search.trim().isNotEmpty) 'search': search.trim(),
    if (status != null) 'status': status!.wire,
    'sort': sort,
    'limit': limit,
    'offset': offset,
  };

  PeopleListQuery copyWith({
    Object? category = _keep,
    Object? company = _keep,
    String? search,
    Object? status = _keep,
    String? sort,
    int? limit,
    int? offset,
  }) => PeopleListQuery(
    category: identical(category, _keep)
        ? this.category
        : category as PeopleCategory?,
    company: identical(company, _keep) ? this.company : company as String?,
    search: search ?? this.search,
    status: identical(status, _keep)
        ? this.status
        : status as PeopleStatusFilter?,
    sort: sort ?? this.sort,
    limit: limit ?? this.limit,
    offset: offset ?? this.offset,
  );

  @override
  bool operator ==(Object other) =>
      other is PeopleListQuery &&
      other.category == category &&
      other.company == company &&
      other.search == search &&
      other.status == status &&
      other.sort == sort &&
      other.limit == limit &&
      other.offset == offset;

  @override
  int get hashCode =>
      Object.hash(category, company, search, status, sort, limit, offset);
}

const _keep = Object();

final class PeopleListPage {
  const PeopleListPage({
    required this.today,
    required this.total,
    required this.offset,
    required this.limit,
    required this.rows,
  });

  factory PeopleListPage.fromJson(Map<String, dynamic> json) => PeopleListPage(
    today: _s(json['today']),
    total: _i(json['total']),
    offset: _i(json['offset']),
    limit: _i(json['limit']),
    rows: [for (final item in _list(json['rows'])) PeoplePerson.fromJson(item)],
  );

  final String today;
  final int total;
  final int offset;
  final int limit;
  final List<PeoplePerson> rows;
}

/// The person form's input.
final class PeopleSavePersonInput {
  const PeopleSavePersonInput({
    required this.fullName,
    required this.company,
    required this.category,
    required this.expectedVersion,
    required this.idempotencyKey,
    this.workerId,
    this.position,
    this.idProfession,
    this.arabicName,
    this.dateOfBirth,
    this.unifiedNumber,
    this.mobile,
  });

  final String? workerId;
  final String fullName;
  final String company;
  final PeopleCategory category;

  /// The position held in the company (the designation).
  final String? position;

  /// The profession on the visa and ID; an empty text clears it, null
  /// leaves it as it is.
  final String? idProfession;
  final String? arabicName;
  final String? dateOfBirth;
  final String? unifiedNumber;
  final String? mobile;
  final int expectedVersion;
  final String idempotencyKey;

  Map<String, Object?> toPayload() => {
    if (workerId != null) 'worker_id': workerId,
    'full_name': fullName.trim(),
    'employer_company': company.trim(),
    'category': category.wire,
    if (position != null && position!.trim().isNotEmpty)
      'designation': position!.trim(),
    // Editing sends it, so it can be cleared; a new person only when given.
    if (idProfession != null &&
        (workerId != null || idProfession!.trim().isNotEmpty))
      'id_profession': idProfession!.trim(),
    if (arabicName != null && arabicName!.trim().isNotEmpty)
      'arabic_name': arabicName!.trim(),
    if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
    if (unifiedNumber != null && unifiedNumber!.trim().isNotEmpty)
      'unified_number': unifiedNumber!.trim(),
    if (mobile != null && mobile!.trim().isNotEmpty)
      'mobile_number': mobile!.trim(),
  };
}

/// A document to record, correct or renew.
final class PeopleSaveDocumentInput {
  const PeopleSaveDocumentInput({
    required this.workerId,
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

  final String workerId;
  final String? documentId;
  final bool renew;
  final PeopleDocumentKind kind;
  final String? label;
  final String? number;
  final String? issueDate;
  final String? expiryDate;
  final String? sites;
  final String? notes;
  final int expectedVersion;
  final String idempotencyKey;

  Map<String, Object?> toPayload() => {
    'worker_id': workerId,
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

/// One person in an import, as the server classified them.
final class PeopleImportRow {
  const PeopleImportRow({
    required this.name,
    required this.company,
    required this.category,
    required this.action,
    required this.changes,
    required this.problems,
    this.row,
    this.workerId,
  });

  factory PeopleImportRow.fromJson(Map<String, dynamic> json) =>
      PeopleImportRow(
        row: _ni(json['row']),
        name: _s(json['name']),
        company: _s(json['company']),
        category: PeopleCategory.from(json['category']),
        action: _s(json['action']),
        workerId: _ns(json['worker_id']),
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
  final String name;
  final String company;
  final PeopleCategory category;

  /// new, update, unchanged or problem.
  final String action;
  final String? workerId;
  final List<String> changes;
  final List<String> problems;
}

final class PeopleImportResult {
  const PeopleImportResult({
    required this.rows,
    required this.newCount,
    required this.updateCount,
    required this.unchangedCount,
    required this.problemCount,
    required this.documentsNew,
    required this.documentsRenewed,
    required this.documentsUpdated,
  });

  factory PeopleImportResult.fromJson(Map<String, dynamic> json) {
    final counts = Map<String, dynamic>.from(json['counts'] as Map? ?? {});
    return PeopleImportResult(
      rows: [
        for (final item in _list(json['rows'])) PeopleImportRow.fromJson(item),
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

  final List<PeopleImportRow> rows;
  final int newCount;
  final int updateCount;
  final int unchangedCount;
  final int problemCount;
  final int documentsNew;
  final int documentsRenewed;
  final int documentsUpdated;

  bool get hasProblems => problemCount > 0;
}

/// An app account as People shows it (PRODUCT_DECISIONS section 54).
final class PeopleAccount {
  const PeopleAccount({
    required this.authUserId,
    required this.name,
    this.email,
    this.role = '',
    this.active = true,
  });

  factory PeopleAccount.fromJson(Map<String, dynamic> json) => PeopleAccount(
    authUserId: _s(json['auth_user_id']),
    name: _s(json['name']),
    email: _ns(json['email']),
    role: _s(json['role']),
    active: json['active'] != false,
  );

  final String authUserId;
  final String name;
  final String? email;

  /// The exact app role claim, e.g. `site_engineer`.
  final String role;
  final bool active;
}

/// A note a person sent HR/PRO about their own record.
final class PeopleNote {
  const PeopleNote({
    required this.id,
    required this.message,
    this.at,
    this.doneAt,
    this.doneBy,
  });

  factory PeopleNote.fromJson(Map<String, dynamic> json) => PeopleNote(
    id: _s(json['id']),
    message: _s(json['message']),
    at: _dt(json['at']),
    doneAt: _dt(json['done_at']),
    doneBy: _ns(json['done_by']),
  );

  final String id;
  final String message;
  final DateTime? at;
  final DateTime? doneAt;
  final String? doneBy;

  bool get isDone => doneAt != null;
}

/// A People record an account's name matches.
final class PeopleLinkCandidate {
  const PeopleLinkCandidate({
    required this.workerId,
    required this.number,
    required this.name,
    required this.company,
    required this.position,
    required this.category,
  });

  factory PeopleLinkCandidate.fromJson(Map<String, dynamic> json) =>
      PeopleLinkCandidate(
        workerId: _s(json['worker_id']),
        number: _s(json['number']),
        name: _s(json['name']),
        company: _s(json['company']),
        position: _s(json['position']),
        category: PeopleCategory.from(json['category']),
      );

  final String workerId;
  final String number;
  final String name;
  final String company;
  final String position;
  final PeopleCategory category;
}

/// An account not yet linked, with the people its name matches.
final class PeopleLinkAccount {
  const PeopleLinkAccount({required this.account, required this.suggestions});

  factory PeopleLinkAccount.fromJson(Map<String, dynamic> json) =>
      PeopleLinkAccount(
        account: PeopleAccount.fromJson(json),
        suggestions: [
          for (final item in _list(json['suggestions']))
            PeopleLinkCandidate.fromJson(item),
        ],
      );

  final PeopleAccount account;
  final List<PeopleLinkCandidate> suggestions;

  bool suggests(String workerId) =>
      suggestions.any((candidate) => candidate.workerId == workerId);
}

/// An app account and the People record it is linked to, for User
/// Management (PRODUCT_DECISIONS section 56).
final class PeopleAccountPerson {
  const PeopleAccountPerson({
    required this.account,
    required this.person,
    required this.canLink,
  });

  factory PeopleAccountPerson.fromJson(Map<String, dynamic> json) {
    final account = json['account'];
    final person = json['person'];
    return PeopleAccountPerson(
      account: account is Map
          ? PeopleAccount.fromJson(Map<String, dynamic>.from(account))
          : null,
      person: person is Map
          ? PeoplePerson.fromJson(Map<String, dynamic>.from(person))
          : null,
      canLink: json['can_link'] == true,
    );
  }

  final PeopleAccount? account;

  /// Null until HR/PRO links the account to a person.
  final PeoplePerson? person;

  /// HR/PRO and Admin link and unlink; anyone else only reads.
  final bool canLink;
}

/// Every account not yet linked to a person (HR/PRO and Admin).
final class PeopleLinkSuggestions {
  const PeopleLinkSuggestions({
    required this.linkedCount,
    required this.accounts,
  });

  factory PeopleLinkSuggestions.fromJson(Map<String, dynamic> json) =>
      PeopleLinkSuggestions(
        linkedCount: _i(json['linked_count']),
        accounts: [
          for (final item in _list(json['accounts']))
            PeopleLinkAccount.fromJson(item),
        ],
      );

  final int linkedCount;
  final List<PeopleLinkAccount> accounts;

  int get withSuggestions =>
      accounts.where((account) => account.suggestions.isNotEmpty).length;
}

/// One of the caller's own documents: never a whole number.
final class PeopleMineDocument {
  const PeopleMineDocument({
    required this.kind,
    required this.status,
    this.label,
    this.numberLast4,
    this.expiryDate,
    this.daysLeft,
    this.sites,
  });

  factory PeopleMineDocument.fromJson(Map<String, dynamic> json) =>
      PeopleMineDocument(
        kind: PeopleDocumentKind.from(json['kind']),
        status: PeopleDocumentStatus.from(json['status']),
        label: _ns(json['label']),
        numberLast4: _ns(json['number_last4']),
        expiryDate: _ns(json['expiry_date']),
        daysLeft: _ni(json['days_left']),
        sites: _ns(json['sites']),
      );

  final PeopleDocumentKind kind;
  final PeopleDocumentStatus status;
  final String? label;

  /// The last four letters or digits; null when the number is short.
  final String? numberLast4;
  final String? expiryDate;
  final int? daysLeft;
  final String? sites;
}

/// This month so far, from the crew day sheets.
final class PeopleMineAttendance {
  const PeopleMineAttendance({
    required this.month,
    required this.recordedDays,
    required this.presentDays,
    required this.absentDays,
    required this.leaveDays,
    required this.offDays,
    required this.workedMinutes,
    required this.overtimeMinutes,
  });

  factory PeopleMineAttendance.fromJson(Map<String, dynamic> json) =>
      PeopleMineAttendance(
        month: _s(json['month']),
        recordedDays: _i(json['recorded_days']),
        presentDays: _i(json['present_days']),
        absentDays: _i(json['absent_days']),
        leaveDays: _i(json['leave_days']),
        offDays: _i(json['off_days']),
        workedMinutes: _i(json['worked_minutes']),
        overtimeMinutes: _i(json['overtime_minutes']),
      );

  /// `YYYY-MM`.
  final String month;
  final int recordedDays;
  final int presentDays;
  final int absentDays;
  final int leaveDays;
  final int offDays;
  final int workedMinutes;
  final int overtimeMinutes;
}

/// The caller's own People record, as they may see it.
final class PeopleMinePerson {
  const PeopleMinePerson({
    required this.id,
    required this.number,
    required this.name,
    required this.company,
    required this.position,
    required this.category,
    required this.status,
    required this.documents,
    required this.attention,
    required this.notes,
    this.arabicName,
    this.idProfession,
    this.joiningDate,
    this.crewName,
    this.attendance,
  });

  factory PeopleMinePerson.fromJson(Map<String, dynamic> json) {
    final crew = json['crew'] is Map
        ? Map<String, dynamic>.from(json['crew'] as Map)
        : null;
    return PeopleMinePerson(
      id: _s(json['id']),
      number: _s(json['number']),
      name: _s(json['name']),
      company: _s(json['company']),
      position: _s(json['position']),
      category: PeopleCategory.from(json['category']),
      status: _s(json['status']),
      documents: [
        for (final item in _list(json['documents']))
          PeopleMineDocument.fromJson(item),
      ],
      attention: PeopleDocumentStatus.from(json['attention']),
      notes: [
        for (final item in _list(json['notes'])) PeopleNote.fromJson(item),
      ],
      arabicName: _ns(json['arabic_name']),
      idProfession: _ns(json['id_profession']),
      joiningDate: _ns(json['joining_date']),
      crewName: crew == null ? null : _ns(crew['name']),
      attendance: json['attendance'] is Map
          ? PeopleMineAttendance.fromJson(
              Map<String, dynamic>.from(json['attendance'] as Map),
            )
          : null,
    );
  }

  final String id;
  final String number;
  final String name;
  final String company;

  /// The position in the company; "Not recorded" when unknown.
  final String position;
  final PeopleCategory category;
  final String status;
  final List<PeopleMineDocument> documents;

  /// The worst current document: expired, expiring or ok.
  final PeopleDocumentStatus attention;
  final List<PeopleNote> notes;
  final String? arabicName;
  final String? idProfession;
  final String? joiningDate;
  final String? crewName;
  final PeopleMineAttendance? attendance;

  int get needingAttention =>
      documents.where((document) => document.status.needsAttention).length;
}

/// A project the caller is a dated member of today.
final class PeopleMineProject {
  const PeopleMineProject({
    required this.id,
    required this.ref,
    required this.name,
    required this.state,
    required this.role,
  });

  factory PeopleMineProject.fromJson(Map<String, dynamic> json) =>
      PeopleMineProject(
        id: _s(json['id']),
        ref: _s(json['ref']),
        name: _s(json['name']),
        state: _s(json['state']),
        role: _s(json['role']),
      );

  final String id;
  final String ref;
  final String name;
  final String state;

  /// `project_engineer` or `site_engineer`.
  final String role;
}

/// `v1_people_get_mine`: the caller's own record and work.
final class PeopleMine {
  const PeopleMine({required this.person, required this.projects});

  factory PeopleMine.fromJson(Map<String, dynamic> json) => PeopleMine(
    person: json['state'] == 'linked' && json['person'] is Map
        ? PeopleMinePerson.fromJson(
            Map<String, dynamic>.from(json['person'] as Map),
          )
        : null,
    projects: [
      for (final item in _list(json['projects']))
        PeopleMineProject.fromJson(item),
    ],
  );

  /// Null until HR/PRO links the account to a People record.
  final PeopleMinePerson? person;
  final List<PeopleMineProject> projects;

  bool get isLinked => person != null;
}

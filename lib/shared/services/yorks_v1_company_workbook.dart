/// Company documents — reading the company sheets of the Staff Documents &
/// Passes tracker, and writing the register back out.
///
/// Reading works on the safe scalar view of any workbook
/// ([YorksV1BoqParsedWorkbook]):
///
/// * **Company Licenses & Permits**: the LICENSES row names each company or
///   branch (with its licence number) and the rows below give each one's
///   commercial licence, establishment card, labour file and PRO cards by
///   column. Rows with only one or two values are company-wide certificates
///   and permits. The car registration sections list vehicles with their
///   registration and Asateel permit; Personal cars are kept as Personal.
/// * **CICPA Contracts** sheet: one CICPA pass record per LOA under each
///   company heading, with its job, people and vehicle counts, passes applied
///   for and expiry.
///
/// The company's postal address (P.O. Box) is never read as a document.
/// * **Staff Documents**: the insurance lines between the people are the
///   company's policies, for the company block they sit in.
/// * **Gate Passes**: a pass whose name carries a plate is the vehicle's
///   CICPA pass, joined to the vehicle by its plate.
///
/// The app's own export (one flat Company Documents sheet) reads back the
/// same way. Nothing is sent anywhere here.
library;

import '../models/yorks_v1_boq_workbook.dart';
import '../models/yorks_v1_company_documents.dart';
import '../models/yorks_v1_people.dart' show PeopleDocumentKind;
import 'yorks_v1_people_workbook.dart'
    show
        PeopleCell,
        PeopleSheet,
        peopleNameKey,
        peopleNumberText,
        peopleParseDate,
        peopleReadTracker;

/// One document read from the sheet.
final class CompanyTrackerDocument {
  const CompanyTrackerDocument({
    required this.kind,
    this.label,
    this.number,
    this.expiryDate,
    this.sites,
  });

  final CompanyDocumentKind kind;
  final String? label;
  final String? number;
  final String? expiryDate;
  final String? sites;

  Map<String, Object?> toJson() => {
    'kind': kind.wire,
    if (label != null) 'label': label,
    if (number != null) 'number': number,
    if (expiryDate != null) 'expiry_date': expiryDate,
    if (sites != null) 'sites': sites,
  };
}

/// One record read from the workbook.
final class CompanyTrackerRecord {
  CompanyTrackerRecord({
    required this.sheet,
    required this.row,
    required this.kind,
    required this.name,
    this.reference,
    this.owner,
    this.details = const CompanyContractDetails(),
    this.sourceNote,
    List<CompanyTrackerDocument>? documents,
    List<String>? issues,
  }) : documents = documents ?? [],
       issues = issues ?? [];

  final String sheet;

  /// Excel row number (1-based).
  final int row;
  final CompanyRecordKind kind;
  final String name;
  String? reference;
  String? owner;
  CompanyContractDetails details;
  final String? sourceNote;
  final List<CompanyTrackerDocument> documents;

  /// Cells that could not be read (the server is told nothing about them).
  final List<String> issues;

  Map<String, Object?> toJson() => {
    'row': row,
    'sheet': sheet,
    'kind': kind.wire,
    'name': name,
    if (reference != null) 'reference': reference,
    if (owner != null) 'owner': owner,
    if (kind == CompanyRecordKind.contract && !details.isEmpty)
      'details': details.toJson(),
    if (sourceNote != null) 'source_note': sourceNote,
    'documents': [for (final document in documents) document.toJson()],
  };
}

final class CompanyTrackerRead {
  const CompanyTrackerRead({
    required this.records,
    required this.skippedRows,
    required this.sheetsFound,
  });

  final List<CompanyTrackerRecord> records;

  /// Rows that hold no record (notes such as "(COURT) 3 spas").
  final List<({String sheet, int row, String text})> skippedRows;

  /// The sheets recognised, by name.
  final List<String> sheetsFound;

  int get issueCount =>
      records.fold(0, (sum, record) => sum + record.issues.length);

  int count(CompanyRecordKind kind) =>
      records.where((record) => record.kind == kind).length;

  int get documentCount =>
      records.fold(0, (sum, record) => sum + record.documents.length);

  Map<String, Object?> toPayload({required String sourceName}) => {
    'source_name': sourceName,
    'records': [for (final record in records) record.toJson()],
  };
}

const companyImportMaxRecords = 1000;

String _key(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

String _clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

String _cell(List<String> row, int column) =>
    column < 0 || column >= row.length ? '' : _clean(row[column]);

/// The plate or other number at the end of a name: `H1 HYUNDAI 29641`.
String? companyPlate(String name) =>
    RegExp(r'(\d{3,})\s*$').firstMatch(_clean(name))?.group(1);

/// A date cell read as `YYYY-MM-DD` when it is a plausible document date.
String? _date(String raw) {
  final value = peopleParseDate(raw);
  if (value == null || value.isEmpty) return null;
  final year = int.tryParse(value.substring(0, 4)) ?? 0;
  return year >= 2000 && year <= 2100 ? value : null;
}

const _vehicleWords = [
  'TOYOTA',
  'HONDA',
  'NISSAN',
  'HYUNDAI',
  'MITSUBISHI',
  'LEXUS',
  'VOLKSWAGEN',
  'MAZDA',
  'KIA',
  'FORD',
  'ISUZU',
  'CHEVROLET',
  'STAREX',
  'PICKUP',
  'BUS',
  'VAN',
  'TRUCK',
  'H1',
];

bool _looksLikeVehicle(String name) {
  final upper = name.toUpperCase();
  if (upper.contains('INSURANCE')) return false;
  final words = upper.split(RegExp(r'[^A-Z0-9]+'));
  return _vehicleWords.any(words.contains) || companyPlate(name) != null;
}

/// What a per-company licence row records.
({CompanyDocumentKind kind, String? label}) _licenceRow(String title) {
  final key = _key(title);
  if (key.contains('commerciallicen')) {
    return (kind: CompanyDocumentKind.licence, label: null);
  }
  if (key.contains('establishment')) {
    return (kind: CompanyDocumentKind.establishmentCard, label: null);
  }
  if (key.contains('labourfile') || key.contains('laborfile')) {
    return (kind: CompanyDocumentKind.labourFile, label: null);
  }
  if (key.startsWith('procard')) {
    return (kind: CompanyDocumentKind.proCard, label: _clean(title));
  }
  return (kind: CompanyDocumentKind.other, label: _clean(title));
}

CompanyTrackerRead companyReadTracker(YorksV1BoqParsedWorkbook workbook) {
  final records = <CompanyTrackerRecord>[];
  final skipped = <({String sheet, int row, String text})>[];
  final found = <String>[];

  for (final sheet in workbook.sheets) {
    if (sheet.isHidden) continue;
    if (_readExport(sheet, records)) {
      found.add(sheet.name);
      continue;
    }
    if (_readLicences(sheet, records, skipped)) {
      found.add(sheet.name);
      continue;
    }
    if (_readContracts(sheet, records)) {
      found.add(sheet.name);
      continue;
    }
    if (_readInsurance(sheet, records)) found.add(sheet.name);
  }

  // Vehicle passes from the gate pass sheet, joined by plate.
  final passes = peopleReadTracker(workbook).vehicles;
  for (final pass in passes) {
    final plate = companyPlate(pass.name);
    CompanyTrackerRecord? vehicle;
    for (final record in records) {
      if (record.kind == CompanyRecordKind.vehicle &&
          plate != null &&
          (record.reference == plate || companyPlate(record.name) == plate)) {
        vehicle = record;
        break;
      }
    }
    if (vehicle == null) {
      vehicle = CompanyTrackerRecord(
        sheet: 'Gate Passes',
        row: pass.row,
        kind: CompanyRecordKind.vehicle,
        name: _clean(pass.name),
        reference: plate,
        owner: pass.section.isEmpty ? null : pass.section,
        sourceNote: 'Added from the gate pass list',
      );
      records.add(vehicle);
    }
    final held = vehicle.documents
        .where((document) => document.kind == CompanyDocumentKind.cicpaPass)
        .length;
    if (pass.number == null && pass.expiry == null && pass.sites == null) {
      continue;
    }
    vehicle.documents.add(
      CompanyTrackerDocument(
        kind: CompanyDocumentKind.cicpaPass,
        label: held == 0
            ? (pass.kind == PeopleDocumentKind.cmwPass ? 'CMW' : null)
            : pass.number,
        number: pass.number,
        expiryDate: pass.expiry,
        sites: pass.sites,
      ),
    );
  }

  // The company's postal address ("P.O. BOX 4757") sits among the permits
  // but is not a document: leave it out, and say so in the preview.
  records.removeWhere((record) {
    if (!companyIsPostalAddress(record.name)) return false;
    skipped.add((sheet: record.sheet, row: record.row, text: record.name));
    return true;
  });

  return CompanyTrackerRead(
    records: records,
    skippedRows: skipped,
    sheetsFound: found,
  );
}

/// "P.O. BOX 4757", "PO Box 12", "Post Box 9": an address, not a document.
bool companyIsPostalAddress(String name) {
  final key = _key(name);
  return key.startsWith('pobox') || key.startsWith('postbox');
}

/// Company Licenses & Permits: `Item | Value 1 | Value 2 …`.
bool _readLicences(
  YorksV1BoqWorkbookSheet sheet,
  List<CompanyTrackerRecord> records,
  List<({String sheet, int row, String text})> skipped,
) {
  var header = -1;
  for (var r = 0; r < sheet.rows.length && r < 20; r++) {
    final row = sheet.rows[r];
    if (_key(_cell(row, 0)) == 'item' && _key(_cell(row, 1)) == 'value1') {
      header = r;
      break;
    }
  }
  if (header < 0) return false;

  // Columns 1… are the companies named on the LICENSES row.
  final entities = <int, CompanyTrackerRecord>{};
  String? vehicleOwner;
  var asateelColumn = -1;

  for (var r = header + 1; r < sheet.rows.length; r++) {
    final row = sheet.rows[r];
    final excelRow = r + 1;
    final title = _cell(row, 0);
    if (title.isEmpty) continue;
    final values = <int, String>{
      for (var c = 1; c < row.length; c++)
        if (_cell(row, c).isNotEmpty) c: _cell(row, c),
    };
    final key = _key(title);

    if (key == 'licenses' || key == 'licences') {
      for (final MapEntry(key: column, value: text) in values.entries) {
        final match = RegExp(
          r'^(.*?)\s*((?:CN-)?\d{5,})$',
          caseSensitive: false,
        ).firstMatch(text);
        final record = CompanyTrackerRecord(
          sheet: sheet.name,
          row: excelRow,
          kind: CompanyRecordKind.entity,
          name: _clean(match?.group(1) ?? text),
          reference: match?.group(2),
        );
        entities[column] = record;
        records.add(record);
      }
      continue;
    }

    // Vehicle sections.
    if (key.contains('carregistration') || key == 'personalcars') {
      vehicleOwner = key == 'personalcars'
          ? 'Personal'
          : _clean(title.toUpperCase().split('CAR REGISTRATION').first);
      if (vehicleOwner.isEmpty) vehicleOwner = null;
      asateelColumn = -1;
      for (final MapEntry(key: column, value: text) in values.entries) {
        if (_key(text).contains('asateel')) asateelColumn = column;
      }
      continue;
    }
    if (vehicleOwner != null) {
      if (_looksLikeVehicle(title)) {
        final record = CompanyTrackerRecord(
          sheet: sheet.name,
          row: excelRow,
          kind: CompanyRecordKind.vehicle,
          name: title,
          reference: companyPlate(title),
          owner: vehicleOwner,
        );
        final registration = _date(values[1] ?? '');
        if (values[1] != null && registration == null) {
          record.issues.add('registration');
        }
        if (registration != null) {
          record.documents.add(
            CompanyTrackerDocument(
              kind: CompanyDocumentKind.registration,
              expiryDate: registration,
            ),
          );
        }
        final permitColumn = asateelColumn > 0 ? asateelColumn : 2;
        final permit = _date(values[permitColumn] ?? '');
        if (values[permitColumn] != null && permit == null) {
          record.issues.add('asateel_permit');
        }
        if (permit != null) {
          record.documents.add(
            CompanyTrackerDocument(
              kind: CompanyDocumentKind.asateelPermit,
              expiryDate: permit,
            ),
          );
        }
        records.add(record);
        continue;
      }
      // Lines after the cars that are not cars: a policy, or a permit.
    }

    // A note under the row above, e.g. "(COURT)  3 spas".
    if (title.startsWith('(')) {
      skipped.add((
        sheet: sheet.name,
        row: excelRow,
        text: [title, ...values.values].join(' '),
      ));
      continue;
    }

    // A licence, establishment card, labour file or PRO card row, or any
    // row with values for three or more companies, is per company.
    final perCompany =
        entities.isNotEmpty &&
        values.keys.every(entities.containsKey) &&
        (_licenceRow(title).kind != CompanyDocumentKind.other ||
            values.length >= 3 ||
            values.keys.any((column) => column > 2));
    if (perCompany) {
      final what = _licenceRow(title);
      for (final MapEntry(key: column, value: text) in values.entries) {
        final entity = entities[column]!;
        if (what.kind == CompanyDocumentKind.labourFile) {
          entity.documents.add(
            CompanyTrackerDocument(
              kind: what.kind,
              label: what.label,
              number: peopleNumberText(text),
            ),
          );
          continue;
        }
        final expiry = _date(text);
        if (expiry == null) {
          entity.issues.add(_clean(title));
          continue;
        }
        entity.documents.add(
          CompanyTrackerDocument(
            kind: what.kind,
            label: what.label,
            expiryDate: expiry,
          ),
        );
      }
      continue;
    }

    // A company-wide certificate, permit or policy, with one or two dates.
    final policy = title.toUpperCase().contains('INSURANCE');
    final record = CompanyTrackerRecord(
      sheet: sheet.name,
      row: excelRow,
      kind: policy ? CompanyRecordKind.policy : CompanyRecordKind.item,
      name: title,
    );
    var order = 0;
    for (final MapEntry(key: column, value: text) in values.entries) {
      order++;
      final expiry = _date(text);
      final kind = policy
          ? CompanyDocumentKind.insurance
          : CompanyDocumentKind.certificate;
      final label = order == 1 ? null : 'Value $column';
      if (expiry != null) {
        record.documents.add(
          CompanyTrackerDocument(kind: kind, label: label, expiryDate: expiry),
        );
      } else {
        final number = peopleNumberText(text);
        if (number == null) continue;
        record.documents.add(
          CompanyTrackerDocument(kind: kind, label: label, number: number),
        );
      }
    }
    records.add(record);
  }
  return true;
}

/// CICPA Contracts: `LOA # | JOB | PEOPLE | VEHICLE | APPLIED … | EXPIRY`
/// under "CONTRACTS FOR company" headings.
bool _readContracts(
  YorksV1BoqWorkbookSheet sheet,
  List<CompanyTrackerRecord> records,
) {
  var loa = -1, job = -1, people = -1, vehicles = -1;
  var appliedPeople = -1, appliedVehicles = -1, expiry = -1;
  var seen = false;
  String? owner;
  for (var r = 0; r < sheet.rows.length; r++) {
    final row = sheet.rows[r];
    final keys = [for (var c = 0; c < row.length; c++) _key(_cell(row, c))];
    final heading = keys.indexWhere((key) => key.startsWith('contractsfor'));
    if (heading >= 0) {
      owner = _clean(
        _cell(
          row,
          heading,
        ).replaceFirst(RegExp(r'contracts\s+for', caseSensitive: false), ''),
      );
      continue;
    }
    final loaColumn = keys.indexWhere((key) => key == 'loa');
    if (loaColumn >= 0) {
      seen = true;
      loa = loaColumn;
      int at(bool Function(String key) test, int fallback) {
        final index = keys.indexWhere(test);
        return index >= 0 ? index : fallback;
      }

      job = at((key) => key == 'job', loa + 1);
      people = at((key) => key == 'people', people < 0 ? loa + 2 : people);
      vehicles = at(
        (key) => key == 'vehicle' || key == 'vehicles',
        vehicles < 0 ? loa + 3 : vehicles,
      );
      appliedPeople = at(
        (key) => key.startsWith('appliedpeople'),
        appliedPeople < 0 ? loa + 4 : appliedPeople,
      );
      appliedVehicles = at(
        (key) => key.startsWith('appliedvehicle'),
        appliedVehicles < 0 ? loa + 5 : appliedVehicles,
      );
      expiry = at((key) => key.startsWith('expiry'), loa + 6);
      continue;
    }
    if (!seen || loa < 0) continue;
    final number = peopleNumberText(_cell(row, loa));
    if (number == null || !RegExp(r'^\d{3,}$').hasMatch(number)) continue;
    final jobText = _cell(row, job);
    int? count(int column) {
      final text = peopleNumberText(_cell(row, column));
      return text == null ? null : int.tryParse(text);
    }

    final record = CompanyTrackerRecord(
      sheet: sheet.name,
      row: r + 1,
      kind: CompanyRecordKind.contract,
      name: jobText.isEmpty ? 'LOA $number' : 'LOA $number · $jobText',
      reference: number,
      owner: owner == null || owner.isEmpty ? null : owner,
      details: CompanyContractDetails(
        job: jobText.isEmpty ? null : jobText,
        people: count(people),
        vehicles: count(vehicles),
        appliedPeople: count(appliedPeople),
        appliedVehicles: count(appliedVehicles),
      ),
    );
    final raw = _cell(row, expiry);
    final date = _date(raw);
    if (raw.isNotEmpty && date == null) record.issues.add('expiry');
    record.documents.add(
      CompanyTrackerDocument(
        kind: CompanyDocumentKind.contract,
        number: number,
        expiryDate: date,
      ),
    );
    records.add(record);
  }
  return seen;
}

/// Staff Documents: the insurance lines between the people.
bool _readInsurance(
  YorksV1BoqWorkbookSheet sheet,
  List<CompanyTrackerRecord> records,
) {
  var header = -1;
  var nameColumn = -1, companyColumn = -1, expiryColumn = -1;
  for (var r = 0; r < sheet.rows.length && r < 20; r++) {
    final keys = [
      for (var c = 0; c < sheet.rows[r].length; c++)
        _key(_cell(sheet.rows[r], c)),
    ];
    final name = keys.indexWhere(
      (key) => key == 'employeename' || key == 'name' || key == 'fullname',
    );
    final company = keys.indexWhere((key) => key == 'company');
    final expiry = keys.indexWhere((key) => key.startsWith('visaexpiry'));
    if (name >= 0 && company >= 0 && expiry >= 0) {
      header = r;
      nameColumn = name;
      companyColumn = company;
      expiryColumn = expiry;
      break;
    }
  }
  if (header < 0) return false;
  String? company;
  var any = false;
  for (var r = header + 1; r < sheet.rows.length; r++) {
    final row = sheet.rows[r];
    final rowCompany = _cell(row, companyColumn);
    if (rowCompany.isNotEmpty) company = rowCompany;
    final name = _cell(row, nameColumn);
    if (!name.toUpperCase().contains('INSURANCE')) continue;
    any = true;
    final record = CompanyTrackerRecord(
      sheet: sheet.name,
      row: r + 1,
      kind: CompanyRecordKind.policy,
      name: name,
      owner: company,
    );
    final raw = _cell(row, expiryColumn);
    final date = _date(raw);
    if (raw.isNotEmpty && date == null) record.issues.add('expiry');
    if (date != null) {
      record.documents.add(
        CompanyTrackerDocument(
          kind: CompanyDocumentKind.insurance,
          expiryDate: date,
        ),
      );
    }
    records.add(record);
  }
  return any;
}

// ─── The app's own export ──────────────────────────────────────────────────

const _groupHeading = 'Group';
const _exportHeadings = [
  _groupHeading,
  'Name',
  'Reference',
  'Company',
  'Document',
  'Name of document',
  'Number',
  'Expiry',
  'Sites',
  'Job',
  'People',
  'Vehicles',
  'Applied people passes',
  'Applied vehicle passes',
];

String companyExportGroupName(CompanyRecordKind kind) => switch (kind) {
  CompanyRecordKind.entity => 'Company or branch',
  CompanyRecordKind.item => 'Certificate or permit',
  CompanyRecordKind.vehicle => 'Vehicle',
  CompanyRecordKind.policy => 'Insurance',
  CompanyRecordKind.contract => 'CICPA pass',
};

/// Group names written by earlier exports, still read back.
const _legacyGroupNames = {'cicpacontract': CompanyRecordKind.contract};

String companyExportDocumentName(CompanyDocumentKind kind) => switch (kind) {
  CompanyDocumentKind.licence => 'Trade licence',
  CompanyDocumentKind.establishmentCard => 'Establishment card',
  CompanyDocumentKind.labourFile => 'Labour file',
  CompanyDocumentKind.proCard => 'PRO card',
  CompanyDocumentKind.registration => 'Registration',
  CompanyDocumentKind.asateelPermit => 'Asateel permit',
  CompanyDocumentKind.cicpaPass => 'CICPA pass',
  CompanyDocumentKind.insurance => 'Insurance',
  CompanyDocumentKind.contract => 'LOA',
  CompanyDocumentKind.certificate => 'Certificate or permit',
  CompanyDocumentKind.other => 'Other',
};

CompanyRecordKind? _groupFrom(String text) {
  final key = _key(text);
  for (final kind in CompanyRecordKind.values) {
    if (key == _key(companyExportGroupName(kind)) || key == kind.wire) {
      return kind;
    }
  }
  return _legacyGroupNames[key];
}

CompanyDocumentKind? _documentFrom(String text) {
  final key = _key(text);
  if (key.isEmpty) return null;
  for (final kind in CompanyDocumentKind.values) {
    if (key == _key(companyExportDocumentName(kind)) ||
        key == _key(kind.wire) ||
        key == _key(kind.name)) {
      return kind;
    }
  }
  return CompanyDocumentKind.other;
}

bool _readExport(
  YorksV1BoqWorkbookSheet sheet,
  List<CompanyTrackerRecord> records,
) {
  var header = -1;
  late List<String> keys;
  for (var r = 0; r < sheet.rows.length && r < 10; r++) {
    keys = [
      for (var c = 0; c < sheet.rows[r].length; c++)
        _key(_cell(sheet.rows[r], c)),
    ];
    if (keys.contains('group') &&
        keys.contains('document') &&
        keys.contains('nameofdocument')) {
      header = r;
      break;
    }
  }
  if (header < 0) return false;
  int col(String heading) => keys.indexOf(_key(heading));
  final byIdentity = <String, CompanyTrackerRecord>{};
  for (var r = header + 1; r < sheet.rows.length; r++) {
    final row = sheet.rows[r];
    final kind = _groupFrom(_cell(row, col('Group')));
    final name = _cell(row, col('Name'));
    if (kind == null || name.isEmpty) continue;
    final reference = _cell(row, col('Reference'));
    final owner = _cell(row, col('Company'));
    final identity = [
      kind.wire,
      peopleNameKey(name),
      reference,
      owner,
    ].join('|');
    int? count(String heading) {
      final text = peopleNumberText(_cell(row, col(heading)));
      return text == null ? null : int.tryParse(text);
    }

    final record = byIdentity.putIfAbsent(identity, () {
      final created = CompanyTrackerRecord(
        sheet: sheet.name,
        row: r + 1,
        kind: kind,
        name: name,
        reference: reference.isEmpty ? null : reference,
        owner: owner.isEmpty ? null : owner,
        details: kind == CompanyRecordKind.contract
            ? CompanyContractDetails(
                job: _cell(row, col('Job')).isEmpty
                    ? null
                    : _cell(row, col('Job')),
                people: count('People'),
                vehicles: count('Vehicles'),
                appliedPeople: count('Applied people passes'),
                appliedVehicles: count('Applied vehicle passes'),
              )
            : const CompanyContractDetails(),
      );
      records.add(created);
      return created;
    });
    final documentKind = _documentFrom(_cell(row, col('Document')));
    if (documentKind == null) continue;
    final label = _cell(row, col('Name of document'));
    final number = peopleNumberText(_cell(row, col('Number')));
    final rawExpiry = _cell(row, col('Expiry'));
    final expiry = _date(rawExpiry);
    if (rawExpiry.isNotEmpty && expiry == null) {
      record.issues.add('expiry');
      continue;
    }
    final sites = _cell(row, col('Sites'));
    record.documents.add(
      CompanyTrackerDocument(
        kind: documentKind,
        label: label.isEmpty ? null : label,
        number: number,
        expiryDate: expiry,
        sites: sites.isEmpty ? null : sites,
      ),
    );
  }
  return true;
}

/// The register as a workbook: every record and document on one sheet (the
/// layout imports again), and what needs attention.
List<PeopleSheet> companyExportSheets(
  List<CompanyRecord> records, {
  required String today,
}) {
  PeopleCell date(String? value, {PeopleDocumentStatus? tone}) =>
      value == null || value.isEmpty
      ? const PeopleCell.text('')
      : PeopleCell.date(value, tone: tone);
  PeopleCell count(int? value) => PeopleCell.text(value?.toString() ?? '');

  final sorted = [...records]
    ..sort((a, b) {
      final kind = a.kind.index.compareTo(b.kind.index);
      if (kind != 0) return kind;
      final owner = (a.owner ?? '').toLowerCase().compareTo(
        (b.owner ?? '').toLowerCase(),
      );
      if (owner != 0) return owner;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

  List<PeopleCell> recordCells(CompanyRecord record) => [
    PeopleCell.text(companyExportGroupName(record.kind)),
    PeopleCell.text(record.name),
    PeopleCell.text(record.reference ?? ''),
    PeopleCell.text(record.owner ?? ''),
  ];
  List<PeopleCell> contractCells(CompanyRecord record) =>
      record.kind == CompanyRecordKind.contract
      ? [
          PeopleCell.text(record.details.job ?? ''),
          count(record.details.people),
          count(record.details.vehicles),
          count(record.details.appliedPeople),
          count(record.details.appliedVehicles),
        ]
      : const [
          PeopleCell.text(''),
          PeopleCell.text(''),
          PeopleCell.text(''),
          PeopleCell.text(''),
          PeopleCell.text(''),
        ];

  final register = PeopleSheet(
    name: 'Company Documents',
    title: 'Company Documents — exported $today',
    headings: _exportHeadings,
    widths: const [20, 36, 16, 24, 22, 26, 18, 14, 28, 22, 9, 10, 14, 14],
    rows: [
      for (final record in sorted)
        if (record.documents.isEmpty)
          [
            ...recordCells(record),
            for (var i = 0; i < 5; i++) const PeopleCell.text(''),
            ...contractCells(record),
          ]
        else
          for (final document in record.documents)
            [
              ...recordCells(record),
              PeopleCell.text(companyExportDocumentName(document.kind)),
              PeopleCell.text(document.label ?? ''),
              PeopleCell.text(document.number ?? ''),
              date(document.expiryDate, tone: document.status),
              PeopleCell.text(document.sites ?? ''),
              ...contractCells(record),
            ],
    ],
  );

  final attention = [
    for (final record in sorted)
      for (final document in record.documents)
        if (document.status.needsAttention) (record, document),
  ]..sort((a, b) => (a.$2.expiryDate ?? '').compareTo(b.$2.expiryDate ?? ''));

  final needs = PeopleSheet(
    name: 'Needs Attention',
    title: 'Expired, or expiring within 60 days — $today',
    headings: const [
      'Group',
      'Name',
      'Company',
      'Document',
      'Number',
      'Expiry',
      'Days left',
    ],
    widths: const [20, 36, 24, 24, 18, 14, 11],
    rows: [
      for (final (record, document) in attention)
        [
          PeopleCell.text(companyExportGroupName(record.kind)),
          PeopleCell.text(record.name),
          PeopleCell.text(record.owner ?? ''),
          PeopleCell.text(
            document.label ?? companyExportDocumentName(document.kind),
          ),
          PeopleCell.text(document.number ?? ''),
          date(document.expiryDate, tone: document.status),
          PeopleCell.text(document.daysLeft?.toString() ?? ''),
        ],
    ],
  );
  return [register, needs];
}

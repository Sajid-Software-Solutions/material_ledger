/// People records — reading the Staff Documents & Passes tracker, and
/// writing the register back out in the same layout.
///
/// Reading works on the safe scalar view of any workbook
/// ([YorksV1BoqParsedWorkbook]). It finds the staff sheet and the gate pass
/// sheet by their headings, turns Excel dates (serial numbers, and the
/// `YYYYMMDD` numbers the pass sheet uses) into ISO dates, keeps long
/// numbers such as Emirates ID exact, sorts each person into Staff or
/// Labour from their profession, and joins every gate pass to the person it
/// belongs to. Nothing is sent anywhere here.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/yorks_v1_boq_workbook.dart';
import '../models/yorks_v1_people.dart';

/// One document read from the sheet.
final class PeopleTrackerDocument {
  const PeopleTrackerDocument({
    required this.kind,
    this.number,
    this.expiryDate,
    this.sites,
  });

  final PeopleDocumentKind kind;
  final String? number;
  final String? expiryDate;
  final String? sites;

  Map<String, Object?> toJson() => {
    'kind': kind.wire,
    if (number != null) 'number': number,
    if (expiryDate != null) 'expiry_date': expiryDate,
    if (sites != null) 'sites': sites,
  };
}

/// Where a person came from in the workbook.
enum PeopleTrackerOrigin { staffSheet, passSheet }

final class PeopleTrackerPerson {
  PeopleTrackerPerson({
    required this.origin,
    required this.row,
    required this.fullName,
    required this.company,
    required this.category,
    this.profession,
    this.arabicName,
    this.dateOfBirth,
    this.unifiedNumber,
    this.sourceNote,
    List<PeopleTrackerDocument>? documents,
    List<String>? issues,
  }) : documents = documents ?? [],
       issues = issues ?? [];

  final PeopleTrackerOrigin origin;

  /// The row number as Excel shows it.
  final int row;
  final String fullName;
  final String company;
  final PeopleCategory category;
  final String? profession;
  final String? arabicName;
  final String? dateOfBirth;
  final String? unifiedNumber;
  final String? sourceNote;
  final List<PeopleTrackerDocument> documents;

  /// Cells that could not be read, e.g. a date that is not a date.
  final List<String> issues;

  Map<String, Object?> toJson() => {
    'row': row,
    'full_name': fullName,
    'employer_company': company,
    'category': category.wire,
    if (profession != null) 'designation': profession,
    if (arabicName != null) 'arabic_name': arabicName,
    if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
    if (unifiedNumber != null) 'unified_number': unifiedNumber,
    if (sourceNote != null) 'source_note': sourceNote,
    'documents': [for (final document in documents) document.toJson()],
  };
}

/// A gate pass name and what it was joined to.
final class PeopleTrackerPassMatch {
  const PeopleTrackerPassMatch({
    required this.row,
    required this.name,
    required this.section,
    required this.matchedName,
    required this.added,
  });

  final int row;
  final String name;
  final String section;

  /// The person it was joined to; null when it could not be recorded.
  final String? matchedName;

  /// True when no one in the staff sheet matched and a person was added.
  final bool added;
}

/// A gate pass held by a vehicle (a name with a plate number); Company
/// documents records it against the vehicle.
typedef PeopleTrackerVehiclePass = ({
  int row,
  String name,
  String section,
  PeopleDocumentKind kind,
  String? number,
  String? expiry,
  String? sites,
});

final class PeopleTrackerRead {
  const PeopleTrackerRead({
    required this.people,
    required this.passMatches,
    required this.skippedRows,
    required this.vehicles,
    required this.staffSheetFound,
    required this.passSheetFound,
  });

  final List<PeopleTrackerPerson> people;
  final List<PeopleTrackerPassMatch> passMatches;

  /// Rows that are not people, e.g. company insurance lines.
  final List<({int row, String text})> skippedRows;

  /// Vehicle passes, kept for company documents.
  final List<PeopleTrackerVehiclePass> vehicles;
  final bool staffSheetFound;
  final bool passSheetFound;

  bool get readable => people.isNotEmpty;
  int get issueCount =>
      people.fold(0, (sum, person) => sum + person.issues.length);

  Map<String, Object?> toPayload({
    required String sourceName,
    required String joiningDate,
  }) => {
    'source_name': sourceName,
    'joining_date': joiningDate,
    'people': [for (final person in people) person.toJson()],
  };
}

const peopleImportMaxPeople = 1000;

String _key(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

String _clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Comparable name: upper case, letters and digits only, single spaces.
String peopleNameKey(String value) =>
    _clean(value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9؀-ۿ ]'), ' '));

/// Excel stores dates as day serials since 1899-12-30. The pass sheet uses
/// `YYYYMMDD` numbers. Text dates such as `31/01/2027`, `31-Jan-2027` and
/// `2027-01-31` are accepted too. Returns `YYYY-MM-DD`, '' for a blank cell,
/// or null when the cell is not a date.
String? peopleParseDate(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return '';
  final number = double.tryParse(text);
  if (number != null) {
    if (number == number.roundToDouble() &&
        number >= 19000101 &&
        number <= 21001231) {
      final value = number.toInt();
      return _iso(value ~/ 10000, (value ~/ 100) % 100, value % 100);
    }
    if (number >= 1 && number < 80000) {
      final date = DateTime.utc(
        1899,
        12,
        30,
      ).add(Duration(days: number.floor()));
      return _iso(date.year, date.month, date.day);
    }
    return null;
  }
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(text);
  if (iso != null) {
    return _iso(
      int.parse(iso.group(1)!),
      int.parse(iso.group(2)!),
      int.parse(iso.group(3)!),
    );
  }
  final numeric = RegExp(
    r'^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})$',
  ).firstMatch(text);
  if (numeric != null) {
    var year = int.parse(numeric.group(3)!);
    if (year < 100) year += 2000;
    return _iso(
      year,
      int.parse(numeric.group(2)!),
      int.parse(numeric.group(1)!),
    );
  }
  final named = RegExp(
    r'^(\d{1,2})[ \-]([A-Za-z]{3,})[ \-,]*(\d{2,4})$',
  ).firstMatch(text);
  if (named != null) {
    final month = _months[named.group(2)!.substring(0, 3).toLowerCase()];
    if (month != null) {
      var year = int.parse(named.group(3)!);
      if (year < 100) year += 2000;
      return _iso(year, month, int.parse(named.group(1)!));
    }
  }
  return null;
}

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

String? _iso(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime.utc(year, month, day);
  if (date.month != month || date.day != day) return null;
  return '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}

/// A number held as text, exactly: `784199012345678.0` and
/// `7.84199012345678E14` both read `784199012345678`. Other text is kept,
/// with spacing tidied.
String? peopleNumberText(String raw) {
  final text = _clean(raw);
  if (text.isEmpty) return null;
  final scientific = RegExp(
    r'^(\d+)(?:\.(\d+))?[Ee]\+?(\d+)$',
  ).firstMatch(text);
  if (scientific != null) {
    final whole = scientific.group(1)!;
    final fraction = scientific.group(2) ?? '';
    final exponent = int.parse(scientific.group(3)!);
    if (exponent >= fraction.length) {
      final digits =
          whole + fraction + ''.padRight(exponent - fraction.length, '0');
      return digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    }
    return text;
  }
  final decimal = RegExp(r'^(\d+)\.0+$').firstMatch(text);
  if (decimal != null) return decimal.group(1);
  return text;
}

const _staffWords = [
  'director',
  'manager',
  'engineer',
  'officer',
  'clerk',
  'account',
  'sales',
  'secretary',
  'messenger',
  'relations',
  'admin',
  'coordinator',
  'printer',
  'follow up',
];

/// Office roles are Staff; site trades, assistants, drivers and everyone
/// with no profession are Labour. Each person can be changed afterwards.
PeopleCategory peopleCategoryFor(String? profession) {
  final text = (profession ?? '').toLowerCase();
  if (text.isEmpty) return PeopleCategory.labour;
  return _staffWords.any(text.contains)
      ? PeopleCategory.staff
      : PeopleCategory.labour;
}

enum _Column {
  company,
  name,
  arabicName,
  profession,
  category,
  visaExpiry,
  visaNumber,
  passportNumber,
  passportExpiry,
  labourCardExpiry,
  iloeExpiry,
  emiratesIdNumber,
  emiratesIdExpiry,
  dateOfBirth,
  unifiedNumber,
}

const _aliases = <_Column, List<String>>{
  _Column.company: ['company', 'companyname', 'employer'],
  _Column.name: ['employeename', 'name', 'fullname', 'names', 'workername'],
  _Column.arabicName: ['arabicname', 'nameinarabic'],
  _Column.profession: [
    'profession',
    'designation',
    'jobtitle',
    'occupation',
    'position',
  ],
  _Column.category: ['category', 'stafforlabour', 'type'],
  _Column.visaExpiry: ['visaexpiry', 'residencevisaexpiry', 'visaexpirydate'],
  _Column.visaNumber: [
    'residencevisanumber',
    'residencevisano',
    'visanumber',
    'visano',
  ],
  _Column.passportNumber: ['passportnumber', 'passportno', 'passport'],
  _Column.passportExpiry: ['passportexpiry', 'passportexpirydate'],
  _Column.labourCardExpiry: [
    'labourcardexpiry',
    'laborcardexpiry',
    'workpermitexpiry',
    'labourcardexpirydate',
  ],
  _Column.iloeExpiry: ['iloeexpiry', 'iloeexpirydate'],
  _Column.emiratesIdNumber: [
    'emiratesidnumber',
    'emiratesid',
    'emiratesidno',
    'eidnumber',
    'eid',
  ],
  _Column.emiratesIdExpiry: ['emiratesidexpiry', 'eidexpiry'],
  _Column.dateOfBirth: ['dateofbirth', 'dob', 'birthdate'],
  _Column.unifiedNumber: ['unifiednumber', 'unifiedno', 'uid'],
};

PeopleTrackerRead peopleReadTracker(YorksV1BoqParsedWorkbook workbook) {
  final people = <PeopleTrackerPerson>[];
  final skipped = <({int row, String text})>[];
  var staffFound = false;

  // ── Staff Documents ──────────────────────────────────────────────────────
  for (final sheet in workbook.sheets) {
    if (sheet.isHidden) continue;
    var headerIndex = -1;
    var columns = <_Column, int>{};
    for (var index = 0; index < sheet.rows.length && index < 20; index++) {
      final found = <_Column, int>{};
      final row = sheet.rows[index];
      for (var cell = 0; cell < row.length; cell++) {
        final heading = _key(row[cell]);
        if (heading.isEmpty) continue;
        for (final entry in _aliases.entries) {
          if (!found.containsKey(entry.key) && entry.value.contains(heading)) {
            found[entry.key] = cell;
            break;
          }
        }
      }
      // A staff sheet names the person and at least one identity date.
      if (found.containsKey(_Column.name) &&
          found.containsKey(_Column.company) &&
          (found.containsKey(_Column.visaExpiry) ||
              found.containsKey(_Column.passportExpiry) ||
              found.containsKey(_Column.labourCardExpiry))) {
        headerIndex = index;
        columns = found;
        break;
      }
    }
    if (headerIndex < 0) continue;
    staffFound = true;
    String cell(List<String> row, _Column column) {
      final index = columns[column];
      if (index == null || index >= row.length) return '';
      return _clean(row[index]);
    }

    for (var index = headerIndex + 1; index < sheet.rows.length; index++) {
      final row = sheet.rows[index];
      final excelRow = index + 1;
      final name = cell(row, _Column.name);
      if (name.isEmpty) continue;
      // Company insurance policies sit among the people; they are company
      // documents, not people.
      if (name.toUpperCase().contains('INSURANCE')) {
        skipped.add((row: excelRow, text: name));
        continue;
      }
      final issues = <String>[];
      String? date(_Column column, String label) {
        final value = peopleParseDate(cell(row, column));
        if (value == null) {
          issues.add(label);
          return null;
        }
        return value.isEmpty ? null : value;
      }

      final profession = cell(row, _Column.profession);
      final categoryCell = cell(row, _Column.category).toLowerCase();
      final category = categoryCell.startsWith('staff')
          ? PeopleCategory.staff
          : categoryCell.startsWith('lab')
          ? PeopleCategory.labour
          : peopleCategoryFor(profession);
      final documents = <PeopleTrackerDocument>[];
      void add(PeopleDocumentKind kind, String? number, String? expiry) {
        if (number == null && expiry == null) return;
        documents.add(
          PeopleTrackerDocument(kind: kind, number: number, expiryDate: expiry),
        );
      }

      add(
        PeopleDocumentKind.visa,
        peopleNumberText(cell(row, _Column.visaNumber)),
        date(_Column.visaExpiry, 'visa_expiry'),
      );
      add(
        PeopleDocumentKind.passport,
        peopleNumberText(cell(row, _Column.passportNumber)),
        date(_Column.passportExpiry, 'passport_expiry'),
      );
      add(
        PeopleDocumentKind.labourCard,
        null,
        date(_Column.labourCardExpiry, 'labour_card_expiry'),
      );
      add(
        PeopleDocumentKind.iloe,
        null,
        date(_Column.iloeExpiry, 'iloe_expiry'),
      );
      add(
        PeopleDocumentKind.emiratesId,
        peopleNumberText(cell(row, _Column.emiratesIdNumber)),
        date(_Column.emiratesIdExpiry, 'emirates_id_expiry'),
      );
      final company = cell(row, _Column.company);
      final arabic = cell(row, _Column.arabicName);
      people.add(
        PeopleTrackerPerson(
          origin: PeopleTrackerOrigin.staffSheet,
          row: excelRow,
          fullName: name,
          company: company,
          category: category,
          profession: profession.isEmpty ? null : profession,
          arabicName: arabic.isEmpty ? null : arabic,
          dateOfBirth: date(_Column.dateOfBirth, 'date_of_birth'),
          unifiedNumber: peopleNumberText(cell(row, _Column.unifiedNumber)),
          documents: documents,
          issues: [if (company.isEmpty) 'company', ...issues],
        ),
      );
    }
    break;
  }

  // ── Gate passes ──────────────────────────────────────────────────────────
  final matches = <PeopleTrackerPassMatch>[];
  final vehicles = <PeopleTrackerVehiclePass>[];
  var passFound = false;
  for (final sheet in workbook.sheets) {
    if (sheet.isHidden) continue;
    final read = _readPasses(sheet);
    if (read == null) continue;
    passFound = true;
    for (final pass in read) {
      if (RegExp(r'\d').hasMatch(pass.name)) {
        vehicles.add((
          row: pass.row,
          name: pass.name,
          section: pass.section,
          kind: pass.kind,
          number: pass.number,
          expiry: pass.expiry,
          sites: pass.sites,
        ));
        continue;
      }
      final person = _matchPerson(people, pass.name, pass.section);
      if (person == null) {
        if (pass.number == null && pass.expiry == null && pass.sites == null) {
          matches.add(
            PeopleTrackerPassMatch(
              row: pass.row,
              name: pass.name,
              section: pass.section,
              matchedName: null,
              added: false,
            ),
          );
          continue;
        }
        final added = PeopleTrackerPerson(
          origin: PeopleTrackerOrigin.passSheet,
          row: pass.row,
          fullName: pass.name,
          company: _sectionCompany(people, pass.section),
          category: PeopleCategory.labour,
          sourceNote: 'Added from the gate pass list',
          issues: [if (pass.badExpiry) 'pass_expiry'],
        );
        _addPass(added, pass);
        people.add(added);
        matches.add(
          PeopleTrackerPassMatch(
            row: pass.row,
            name: pass.name,
            section: pass.section,
            matchedName: added.fullName,
            added: true,
          ),
        );
        continue;
      }
      if (pass.badExpiry) person.issues.add('pass_expiry');
      final recorded = _addPass(person, pass);
      matches.add(
        PeopleTrackerPassMatch(
          row: pass.row,
          name: pass.name,
          section: pass.section,
          matchedName: recorded ? person.fullName : null,
          added: false,
        ),
      );
    }
    break;
  }

  return PeopleTrackerRead(
    people: people,
    passMatches: matches,
    skippedRows: skipped,
    vehicles: vehicles,
    staffSheetFound: staffFound,
    passSheetFound: passFound,
  );
}

final class _Pass {
  const _Pass({
    required this.row,
    required this.section,
    required this.kind,
    required this.name,
    this.number,
    this.expiry,
    this.sites,
    this.badExpiry = false,
  });

  final int row;
  final String section;
  final PeopleDocumentKind kind;
  final String name;
  final String? number;
  final String? expiry;
  final String? sites;
  final bool badExpiry;
}

/// Both layouts: the tracker's two blocks (CNI card | CMW pass, each with
/// expiry, name, number and jobs, under company section rows) and the
/// exported one-pass-per-row sheet (Name, Company, Pass, Number, Expiry,
/// Sites).
List<_Pass>? _readPasses(YorksV1BoqWorkbookSheet sheet) {
  for (var index = 0; index < sheet.rows.length && index < 20; index++) {
    final headings = [for (final cell in sheet.rows[index]) _key(cell)];
    // Exported layout.
    final passColumn = headings.indexOf('pass');
    if (passColumn >= 0 && headings.contains('name')) {
      final name = headings.indexOf('name');
      final company = headings.indexOf('company');
      final number = headings.indexOf('number');
      final expiry = headings.indexOf('expiry');
      final sites = headings.indexOf('sites');
      String at(List<String> row, int column) =>
          column < 0 || column >= row.length ? '' : _clean(row[column]);
      return [
        for (var r = index + 1; r < sheet.rows.length; r++)
          if (at(sheet.rows[r], name).isNotEmpty)
            _pass(
              row: r + 1,
              section: at(sheet.rows[r], company),
              kind: at(sheet.rows[r], passColumn).toLowerCase().contains('cmw')
                  ? PeopleDocumentKind.cmwPass
                  : PeopleDocumentKind.cicpaPass,
              name: at(sheet.rows[r], name),
              number: at(sheet.rows[r], number),
              expiry: at(sheet.rows[r], expiry),
              sites: at(sheet.rows[r], sites),
            ),
      ];
    }
    // Tracker layout: two NAME headings, each followed by a pass number.
    final names = [
      for (var c = 0; c < headings.length; c++)
        if (headings[c] == 'name') c,
    ];
    if (names.isEmpty ||
        !headings.any(
          (heading) => heading.contains('cni') || heading.contains('cmw'),
        )) {
      continue;
    }
    final blocks = [
      for (final name in names)
        if (name + 1 < headings.length)
          (
            expiry: name - 1,
            name: name,
            number: name + 1,
            sites: name + 2,
            kind: headings[name + 1].contains('cmw')
                ? PeopleDocumentKind.cmwPass
                : PeopleDocumentKind.cicpaPass,
          ),
    ];
    final passes = <_Pass>[];
    var section = 'YORKS';
    for (var r = index + 1; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      String at(int column) =>
          column < 0 || column >= row.length ? '' : _clean(row[column]);
      final filled = [
        for (var c = 0; c < row.length; c++)
          if (_clean(row[c]).isNotEmpty) c,
      ];
      // A company section heading: one text cell, no pass data.
      if (filled.length == 1 &&
          double.tryParse(at(filled.single)) == null &&
          blocks.every((block) => filled.single != block.number)) {
        section = at(filled.single).toUpperCase();
        continue;
      }
      for (final block in blocks) {
        final name = at(block.name);
        if (name.isEmpty) continue;
        passes.add(
          _pass(
            row: r + 1,
            section: section,
            kind: block.kind,
            name: name,
            number: at(block.number),
            expiry: at(block.expiry),
            sites: at(block.sites),
          ),
        );
      }
    }
    return passes;
  }
  return null;
}

_Pass _pass({
  required int row,
  required String section,
  required PeopleDocumentKind kind,
  required String name,
  required String number,
  required String expiry,
  required String sites,
}) {
  final date = peopleParseDate(expiry);
  return _Pass(
    row: row,
    section: section,
    kind: kind,
    name: name,
    number: peopleNumberText(number),
    expiry: date == null || date.isEmpty ? null : date,
    sites: sites.isEmpty ? null : sites,
    badExpiry: date == null,
  );
}

/// A pass is recorded when it has a number, an expiry or the sites it
/// covers; a row with only a name has nothing to record.
bool _addPass(PeopleTrackerPerson person, _Pass pass) {
  if (pass.number == null && pass.expiry == null && pass.sites == null) {
    return false;
  }
  person.documents.add(
    PeopleTrackerDocument(
      kind: pass.kind,
      number: pass.number,
      expiryDate: pass.expiry,
      sites: pass.sites,
    ),
  );
  return true;
}

bool _sectionFits(String section, String company) {
  final s = section.toUpperCase();
  final c = company.toUpperCase();
  if (s.contains('BADAWI')) return c.contains('BADAWI');
  if (s.contains('BRANCH')) return c.contains('BRANCH');
  return !c.contains('BADAWI') && !c.contains('BRANCH');
}

/// The staff person a pass belongs to: the same name, or the one person
/// whose name contains every word of it; the pass section decides between
/// people of the same name in different companies.
PeopleTrackerPerson? _matchPerson(
  List<PeopleTrackerPerson> people,
  String name,
  String section,
) {
  final key = peopleNameKey(name);
  if (key.isEmpty) return null;
  final words = key.split(' ');
  List<PeopleTrackerPerson> pick(List<PeopleTrackerPerson> candidates) {
    if (candidates.length <= 1) return candidates;
    final fitting = [
      for (final person in candidates)
        if (_sectionFits(section, person.company)) person,
    ];
    return fitting.isEmpty ? candidates : fitting;
  }

  final exact = pick([
    for (final person in people)
      if (peopleNameKey(person.fullName) == key) person,
  ]);
  if (exact.length == 1) return exact.single;
  if (exact.length > 1) return null;
  final containing = pick([
    for (final person in people)
      if (words.every(peopleNameKey(person.fullName).split(' ').contains))
        person,
  ]);
  return containing.length == 1 ? containing.single : null;
}

/// The company a person added from a pass section belongs to: the most
/// common staff company that fits the section, or the section's own name.
String _sectionCompany(List<PeopleTrackerPerson> people, String section) {
  final counts = <String, int>{};
  for (final person in people) {
    if (person.origin != PeopleTrackerOrigin.staffSheet) continue;
    if (!_sectionFits(section, person.company)) continue;
    counts[person.company] = (counts[person.company] ?? 0) + 1;
  }
  if (counts.isEmpty) {
    return section
        .toLowerCase()
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
  return (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
      .first
      .key;
}

// ─── Export ────────────────────────────────────────────────────────────────

/// A cell of an exported sheet.
final class PeopleCell {
  const PeopleCell.text(this.text, {this.tone}) : date = null;
  const PeopleCell.date(this.date, {this.tone}) : text = null;

  final String? text;

  /// `YYYY-MM-DD`; written as a real Excel date.
  final String? date;
  final PeopleDocumentStatus? tone;
}

final class PeopleSheet {
  const PeopleSheet({
    required this.name,
    required this.title,
    required this.headings,
    required this.rows,
    required this.widths,
  });

  final String name;
  final String title;
  final List<String> headings;
  final List<List<PeopleCell>> rows;
  final List<double> widths;
}

/// The register as a workbook: Staff Documents (the tracker's layout, so it
/// can be imported again), Gate Passes, and what needs attention.
List<PeopleSheet> peopleExportSheets(
  List<PeoplePerson> people, {
  required String today,
}) {
  PeopleCell date(String? value, {PeopleDocumentStatus? tone}) =>
      value == null || value.isEmpty
      ? const PeopleCell.text('')
      : PeopleCell.date(value, tone: tone);
  String number(PeopleDocument? document) => document?.number ?? '';

  final sorted = [...people]
    ..sort((a, b) {
      final category = a.category.index.compareTo(b.category.index);
      if (category != 0) return category;
      final company = a.company.toLowerCase().compareTo(
        b.company.toLowerCase(),
      );
      if (company != 0) return company;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

  final staff = PeopleSheet(
    name: 'Staff Documents',
    title: 'Staff Documents — exported $today',
    headings: const [
      'No.',
      'Category',
      'Company',
      'Employee Name',
      'Arabic Name',
      'Profession',
      'Visa Expiry',
      'Residence Visa Number',
      'Passport Number',
      'Passport Expiry',
      'Labour Card Expiry',
      'ILOE Expiry',
      'Emirates ID Number',
      'Emirates ID Expiry',
      'Date of Birth',
      'Unified Number',
    ],
    widths: const [
      12,
      10,
      24,
      30,
      26,
      26,
      14,
      20,
      16,
      14,
      16,
      14,
      20,
      16,
      14,
      16,
    ],
    rows: [
      for (final person in sorted)
        () {
          final visa = person.current(PeopleDocumentKind.visa);
          final passport = person.current(PeopleDocumentKind.passport);
          final labour = person.current(PeopleDocumentKind.labourCard);
          final iloe = person.current(PeopleDocumentKind.iloe);
          final eid = person.current(PeopleDocumentKind.emiratesId);
          return [
            PeopleCell.text(person.number),
            PeopleCell.text(
              person.category == PeopleCategory.staff ? 'Staff' : 'Labour',
            ),
            PeopleCell.text(person.company),
            PeopleCell.text(person.name),
            PeopleCell.text(person.arabicName ?? ''),
            PeopleCell.text(
              person.profession == 'Not recorded' ? '' : person.profession,
            ),
            date(visa?.expiryDate, tone: visa?.status),
            PeopleCell.text(number(visa)),
            PeopleCell.text(number(passport)),
            date(passport?.expiryDate, tone: passport?.status),
            date(labour?.expiryDate, tone: labour?.status),
            date(iloe?.expiryDate, tone: iloe?.status),
            PeopleCell.text(number(eid)),
            date(eid?.expiryDate, tone: eid?.status),
            date(person.dateOfBirth),
            PeopleCell.text(person.unifiedNumber ?? ''),
          ];
        }(),
    ],
  );

  final passes = PeopleSheet(
    name: 'Gate Passes',
    title: 'Gate Passes — exported $today',
    headings: const ['Name', 'Company', 'Pass', 'Number', 'Expiry', 'Sites'],
    widths: const [30, 24, 10, 20, 14, 48],
    rows: [
      for (final person in sorted)
        for (final document in person.documents)
          if (document.kind.isPass)
            [
              PeopleCell.text(person.name),
              PeopleCell.text(person.company),
              PeopleCell.text(
                document.kind == PeopleDocumentKind.cicpaPass ? 'CICPA' : 'CMW',
              ),
              PeopleCell.text(document.number ?? ''),
              date(document.expiryDate, tone: document.status),
              PeopleCell.text(document.sites ?? ''),
            ],
    ],
  );

  final attentionRows = [
    for (final person in sorted)
      for (final document in person.documents)
        if (document.status.needsAttention) (person, document),
  ]..sort((a, b) => (a.$2.expiryDate ?? '').compareTo(b.$2.expiryDate ?? ''));
  final attention = PeopleSheet(
    name: 'Needs Attention',
    title: 'Expired and expiring within 60 days — $today',
    headings: const [
      'Name',
      'Company',
      'Category',
      'Document',
      'Number',
      'Expiry',
      'Days Left',
      'Status',
    ],
    widths: const [30, 24, 10, 16, 20, 14, 10, 14],
    rows: [
      for (final (person, document) in attentionRows)
        [
          PeopleCell.text(person.name),
          PeopleCell.text(person.company),
          PeopleCell.text(
            person.category == PeopleCategory.staff ? 'Staff' : 'Labour',
          ),
          PeopleCell.text(_kindLabel(document)),
          PeopleCell.text(document.number ?? ''),
          date(document.expiryDate, tone: document.status),
          PeopleCell.text('${document.daysLeft ?? ''}'),
          PeopleCell.text(
            document.status == PeopleDocumentStatus.expired
                ? 'Expired'
                : 'Expiring',
            tone: document.status,
          ),
        ],
    ],
  );
  return [staff, passes, attention];
}

String _kindLabel(PeopleDocument document) => switch (document.kind) {
  PeopleDocumentKind.visa => 'Visa',
  PeopleDocumentKind.passport => 'Passport',
  PeopleDocumentKind.labourCard => 'Labour card',
  PeopleDocumentKind.iloe => 'ILOE',
  PeopleDocumentKind.emiratesId => 'Emirates ID',
  PeopleDocumentKind.cicpaPass => 'CICPA pass',
  PeopleDocumentKind.cmwPass => 'CMW pass',
  PeopleDocumentKind.other => document.label ?? 'Document',
};

/// A styled `.xlsx`: a title row, a bold frozen heading row, borders, real
/// dates, and red / amber / green for expired, expiring and fine.
Uint8List peopleEncodeWorkbook(List<PeopleSheet> sheets) {
  final archive = Archive()
    ..addFile(ArchiveFile.string('[Content_Types].xml', _contentTypes(sheets)))
    ..addFile(ArchiveFile.string('_rels/.rels', _rootRels))
    ..addFile(ArchiveFile.string('xl/workbook.xml', _workbook(sheets)))
    ..addFile(
      ArchiveFile.string('xl/_rels/workbook.xml.rels', _workbookRels(sheets)),
    )
    ..addFile(ArchiveFile.string('xl/styles.xml', _styles));
  for (var index = 0; index < sheets.length; index++) {
    archive.addFile(
      ArchiveFile.string(
        'xl/worksheets/sheet${index + 1}.xml',
        _sheetXml(sheets[index]),
      ),
    );
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _column(int index) {
  var value = index + 1;
  final out = StringBuffer();
  while (value > 0) {
    final remainder = (value - 1) % 26;
    out.write(String.fromCharCode(65 + remainder));
    value = (value - 1) ~/ 26;
  }
  return out.toString().split('').reversed.join();
}

String _escape(String value) => const HtmlEscape(
  HtmlEscapeMode.element,
).convert(value).replaceAll('"', '&quot;');

int _serial(String iso) {
  final date = DateTime.utc(
    int.parse(iso.substring(0, 4)),
    int.parse(iso.substring(5, 7)),
    int.parse(iso.substring(8, 10)),
  );
  return date.difference(DateTime.utc(1899, 12, 30)).inDays;
}

// Styles: 0 default, 1 title, 2 heading, 3 text, 4 date, 5 expired text,
// 6 expiring text, 7 fine text, 8 expired date, 9 expiring date, 10 fine
// date.
int _style(PeopleCell cell) {
  final tone = cell.tone;
  final base = cell.date != null ? 4 : 3;
  return switch (tone) {
    PeopleDocumentStatus.expired => base == 4 ? 8 : 5,
    PeopleDocumentStatus.expiring => base == 4 ? 9 : 6,
    PeopleDocumentStatus.ok => base == 4 ? 10 : 7,
    _ => base,
  };
}

String _sheetXml(PeopleSheet sheet) {
  final lastColumn = _column(sheet.headings.length - 1);
  final out = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<sheetViews><sheetView workbookViewId="0">'
    '<pane ySplit="3" topLeftCell="A4" activePane="bottomLeft" state="frozen"/>'
    '</sheetView></sheetViews>'
    '<sheetFormatPr defaultRowHeight="18"/><cols>',
  );
  for (var index = 0; index < sheet.widths.length; index++) {
    out.write(
      '<col min="${index + 1}" max="${index + 1}" '
      'width="${sheet.widths[index]}" customWidth="1"/>',
    );
  }
  out
    ..write('</cols><sheetData>')
    ..write('<row r="1" ht="26" customHeight="1">')
    ..write(
      '<c r="A1" t="inlineStr" s="1"><is><t>${_escape(sheet.title)}</t></is></c>',
    )
    ..write('</row><row r="3">');
  for (var index = 0; index < sheet.headings.length; index++) {
    out.write(
      '<c r="${_column(index)}3" t="inlineStr" s="2"><is><t>'
      '${_escape(sheet.headings[index])}</t></is></c>',
    );
  }
  out.write('</row>');
  for (var r = 0; r < sheet.rows.length; r++) {
    final rowNumber = r + 4;
    out.write('<row r="$rowNumber">');
    final row = sheet.rows[r];
    for (var c = 0; c < row.length; c++) {
      final cell = row[c];
      final reference = '${_column(c)}$rowNumber';
      final style = _style(cell);
      if (cell.date != null) {
        out.write(
          '<c r="$reference" s="$style"><v>${_serial(cell.date!)}</v></c>',
        );
      } else {
        final text = cell.text ?? '';
        out.write(
          '<c r="$reference" t="inlineStr" s="$style"><is><t xml:space="preserve">'
          '${_escape(text)}</t></is></c>',
        );
      }
    }
    out.write('</row>');
  }
  out.write('</sheetData>');
  if (sheet.rows.isNotEmpty) {
    out.write('<autoFilter ref="A3:$lastColumn${sheet.rows.length + 3}"/>');
  }
  out.write(
    '<pageSetup orientation="landscape" fitToWidth="1" fitToHeight="0"/>'
    '</worksheet>',
  );
  return out.toString();
}

String _contentTypes(List<PeopleSheet> sheets) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
    '${[for (var i = 1; i <= sheets.length; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
    '</Types>';

const _rootRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
    '</Relationships>';

String _workbook(List<PeopleSheet> sheets) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
    '<sheets>'
    '${[for (var i = 0; i < sheets.length; i++) '<sheet name="${_escape(sheets[i].name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
    '</sheets></workbook>';

String _workbookRels(List<PeopleSheet> sheets) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '${[for (var i = 1; i <= sheets.length; i++) '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>'].join()}'
    '<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
    '</Relationships>';

const _styles =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<numFmts count="1"><numFmt numFmtId="164" formatCode="dd-mmm-yyyy"/></numFmts>'
    '<fonts count="5">'
    '<font><sz val="11"/><name val="Calibri"/></font>'
    '<font><b/><sz val="14"/><color rgb="FF12365E"/><name val="Calibri"/></font>'
    '<font><b/><sz val="11"/><color rgb="FF10233F"/><name val="Calibri"/></font>'
    '<font><sz val="11"/><color rgb="FFB42318"/><name val="Calibri"/></font>'
    '<font><sz val="11"/><color rgb="FF8A5A00"/><name val="Calibri"/></font>'
    '</fonts>'
    '<fills count="6">'
    '<fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFEAF0F7"/></patternFill></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFFDECEA"/></patternFill></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFFFF4DB"/></patternFill></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFE8F6EE"/></patternFill></fill>'
    '</fills>'
    '<borders count="2">'
    '<border><left/><right/><top/><bottom/><diagonal/></border>'
    '<border><left style="thin"><color rgb="FFD7E0EB"/></left>'
    '<right style="thin"><color rgb="FFD7E0EB"/></right>'
    '<top style="thin"><color rgb="FFD7E0EB"/></top>'
    '<bottom style="thin"><color rgb="FFD7E0EB"/></bottom><diagonal/></border>'
    '</borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="11">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    '<xf numFmtId="0" fontId="2" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/>'
    '<xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>'
    '<xf numFmtId="0" fontId="3" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>'
    '<xf numFmtId="0" fontId="4" fillId="4" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>'
    '<xf numFmtId="0" fontId="0" fillId="5" borderId="1" xfId="0" applyFill="1" applyBorder="1"/>'
    '<xf numFmtId="164" fontId="3" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"/>'
    '<xf numFmtId="164" fontId="4" fillId="4" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"/>'
    '<xf numFmtId="164" fontId="0" fillId="5" borderId="1" xfId="0" applyNumberFormat="1" applyFill="1" applyBorder="1"/>'
    '</cellXfs>'
    '</styleSheet>';

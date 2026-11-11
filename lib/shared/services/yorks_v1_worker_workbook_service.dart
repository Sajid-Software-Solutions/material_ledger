import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';

import '../models/yorks_v1_boq_workbook.dart';
import '../models/yorks_v1_domain_error.dart';
import '../models/yorks_v1_worker_record.dart';
import 'yorks_v1_boq_workbook_service.dart';

/// The workforce sheet's columns, in the order of the template.
enum YorksV1WorkerSheetColumn {
  number('Nos'),
  name('Names'),
  company('Company'),
  tradeLicense('Trade License No.'),
  passport('Passport No.'),
  basic('Basic Salary'),
  housing('Housing'),
  others('Others'),
  total('Total Salary');

  const YorksV1WorkerSheetColumn(this.templateHeading);

  final String templateHeading;
}

const _headingAliases = <YorksV1WorkerSheetColumn, List<String>>{
  YorksV1WorkerSheetColumn.number: ['nos', 'no', 'srno', 'sno', 'serial'],
  YorksV1WorkerSheetColumn.name: [
    'names',
    'name',
    'fullname',
    'workername',
    'employeename',
  ],
  YorksV1WorkerSheetColumn.company: ['company', 'companyname', 'employer'],
  YorksV1WorkerSheetColumn.tradeLicense: [
    'tradelicenseno',
    'tradelicenceno',
    'tradelicense',
    'tradelicence',
    'licenseno',
    'licenceno',
    'tlno',
  ],
  YorksV1WorkerSheetColumn.passport: [
    'passportno',
    'passportnumber',
    'passport',
  ],
  YorksV1WorkerSheetColumn.basic: ['basicsalary', 'basic'],
  YorksV1WorkerSheetColumn.housing: [
    'housing',
    'housingallowance',
    'accommodation',
  ],
  YorksV1WorkerSheetColumn.others: [
    'others',
    'other',
    'otherallowance',
    'otherallowances',
  ],
  YorksV1WorkerSheetColumn.total: ['totalsalary', 'total'],
};

String _normalizedHeading(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Problems found in the sheet itself, before the server is asked.
enum YorksV1WorkerSheetIssue { amountInvalid, totalMismatch }

/// One data row read from the sheet. Amounts are normalized decimal text
/// (`1200.00` → `1200.00`, `AED 1,200` → `1200`), or empty when blank.
class YorksV1WorkerSheetRow {
  const YorksV1WorkerSheetRow({
    required this.rowNumber,
    required this.fullName,
    required this.company,
    required this.tradeLicenseNo,
    required this.passportNo,
    required this.basicSalary,
    required this.housingAllowance,
    required this.otherAllowance,
    required this.issues,
  });

  /// The row number as Excel shows it (1-based).
  final int rowNumber;
  final String fullName;
  final String company;
  final String tradeLicenseNo;
  final String passportNo;
  final String basicSalary;
  final String housingAllowance;
  final String otherAllowance;
  final List<YorksV1WorkerSheetIssue> issues;

  Map<String, Object?> toRpcJson() => {
    'row_number': rowNumber,
    'full_name': fullName,
    'employer_company': company,
    'trade_license_no': tradeLicenseNo,
    'passport_no': passportNo,
    'basic_salary': basicSalary,
    'housing_allowance': housingAllowance,
    'other_allowance': otherAllowance,
  };
}

class YorksV1WorkerSheet {
  const YorksV1WorkerSheet({
    required this.rows,
    required this.missingColumns,
    required this.tooManyRows,
  });

  final List<YorksV1WorkerSheetRow> rows;

  /// Required headings not found: name and company.
  final List<YorksV1WorkerSheetColumn> missingColumns;
  final bool tooManyRows;

  bool get readable =>
      missingColumns.isEmpty && !tooManyRows && rows.isNotEmpty;
}

const yorksV1WorkerImportMaxRows = 500;

/// Reads an amount cell. Excel stores numbers as binary floats, so a value
/// such as `1199.9999999999998` is accepted as `1200.00` when it is within a
/// millionth of two decimal places. Anything else with more decimals, a
/// negative number or text is invalid.
String? yorksV1ParseWorkerAmount(String raw) {
  var text = raw.trim().toUpperCase();
  if (text.isEmpty) return '';
  text = text
      .replaceAll('AED', '')
      .replaceAll('DHS', '')
      .replaceAll(',', '')
      .replaceAll(' ', '');
  if (text.isEmpty) return '';
  if (RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(text)) return text;
  if (!RegExp(r'^\d{1,10}\.\d+$').hasMatch(text) &&
      !RegExp(r'^\d+(\.\d+)?[Ee][+-]?\d+$').hasMatch(text)) {
    return null;
  }
  final value = double.tryParse(text);
  if (value == null || value < 0 || value >= 1e10) return null;
  final fils = (value * 100).round();
  if ((value * 100 - fils).abs() > 1e-4) return null;
  final whole = fils ~/ 100;
  final cents = (fils % 100).toString().padLeft(2, '0');
  return '$whole.$cents';
}

YorksV1WorkerSheet yorksV1ReadWorkerSheet(YorksV1BoqWorkbookSheet sheet) {
  // The heading row is the first of the top 20 that names both the worker
  // and the company columns.
  var headerIndex = -1;
  var columns = <YorksV1WorkerSheetColumn, int>{};
  for (var index = 0; index < sheet.rows.length && index < 20; index++) {
    final found = <YorksV1WorkerSheetColumn, int>{};
    final row = sheet.rows[index];
    for (var cell = 0; cell < row.length; cell++) {
      final heading = _normalizedHeading(row[cell]);
      if (heading.isEmpty) continue;
      for (final entry in _headingAliases.entries) {
        if (!found.containsKey(entry.key) && entry.value.contains(heading)) {
          found[entry.key] = cell;
          break;
        }
      }
    }
    if (found.containsKey(YorksV1WorkerSheetColumn.name) &&
        found.containsKey(YorksV1WorkerSheetColumn.company)) {
      headerIndex = index;
      columns = found;
      break;
    }
  }
  if (headerIndex < 0) {
    return const YorksV1WorkerSheet(
      rows: [],
      missingColumns: [
        YorksV1WorkerSheetColumn.name,
        YorksV1WorkerSheetColumn.company,
      ],
      tooManyRows: false,
    );
  }

  String cell(List<String> row, YorksV1WorkerSheetColumn column) {
    final index = columns[column];
    if (index == null || index >= row.length) return '';
    return row[index].replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  final rows = <YorksV1WorkerSheetRow>[];
  var dataRows = 0;
  for (var index = headerIndex + 1; index < sheet.rows.length; index++) {
    final row = sheet.rows[index];
    final name = cell(row, YorksV1WorkerSheetColumn.name);
    final company = cell(row, YorksV1WorkerSheetColumn.company);
    final values = [
      name,
      company,
      cell(row, YorksV1WorkerSheetColumn.tradeLicense),
      cell(row, YorksV1WorkerSheetColumn.passport),
      cell(row, YorksV1WorkerSheetColumn.basic),
      cell(row, YorksV1WorkerSheetColumn.housing),
      cell(row, YorksV1WorkerSheetColumn.others),
    ];
    if (values.every((value) => value.isEmpty)) continue;
    // A totals line at the foot of the sheet is not a worker.
    if (company.isEmpty &&
        const {'total', 'totals', 'grandtotal'}.contains(
          _normalizedHeading(
            name.isEmpty ? cell(row, YorksV1WorkerSheetColumn.number) : name,
          ),
        )) {
      continue;
    }
    dataRows++;
    if (dataRows > yorksV1WorkerImportMaxRows) {
      return YorksV1WorkerSheet(
        rows: List.unmodifiable(rows),
        missingColumns: const [],
        tooManyRows: true,
      );
    }
    final issues = <YorksV1WorkerSheetIssue>[];
    String amount(YorksV1WorkerSheetColumn column) {
      final parsed = yorksV1ParseWorkerAmount(cell(row, column));
      if (parsed == null) {
        if (!issues.contains(YorksV1WorkerSheetIssue.amountInvalid)) {
          issues.add(YorksV1WorkerSheetIssue.amountInvalid);
        }
        return cell(row, column);
      }
      return parsed;
    }

    final basic = amount(YorksV1WorkerSheetColumn.basic);
    final housing = amount(YorksV1WorkerSheetColumn.housing);
    final others = amount(YorksV1WorkerSheetColumn.others);
    final total = yorksV1ParseWorkerAmount(
      cell(row, YorksV1WorkerSheetColumn.total),
    );
    if (!issues.contains(YorksV1WorkerSheetIssue.amountInvalid) &&
        total != null &&
        total.isNotEmpty) {
      final sum = yorksV1SumWorkerAmounts([basic, housing, others]);
      final expected = yorksV1SumWorkerAmounts([total]);
      if (sum != expected) issues.add(YorksV1WorkerSheetIssue.totalMismatch);
    } else if (total == null) {
      if (!issues.contains(YorksV1WorkerSheetIssue.amountInvalid)) {
        issues.add(YorksV1WorkerSheetIssue.amountInvalid);
      }
    }
    rows.add(
      YorksV1WorkerSheetRow(
        rowNumber: index + 1,
        fullName: name,
        company: company,
        tradeLicenseNo: cell(row, YorksV1WorkerSheetColumn.tradeLicense),
        passportNo: cell(row, YorksV1WorkerSheetColumn.passport),
        basicSalary: basic,
        housingAllowance: housing,
        otherAllowance: others,
        issues: List.unmodifiable(issues),
      ),
    );
  }
  return YorksV1WorkerSheet(
    rows: List.unmodifiable(rows),
    missingColumns: const [],
    tooManyRows: false,
  );
}

/// A picked workbook: its visible worksheets, already decoded.
class YorksV1PickedWorkerWorkbook {
  const YorksV1PickedWorkerWorkbook({
    required this.fileName,
    required this.sheets,
  });

  final String fileName;
  final List<YorksV1BoqWorkbookSheet> sheets;
}

abstract interface class YorksV1WorkerWorkbookFiles {
  /// Null when the user cancels. Throws `invalidInput` for a file that is not
  /// a readable `.xlsx` workbook.
  Future<YorksV1PickedWorkerWorkbook?> pickWorkbook();

  /// Saves the empty import template; false when the user cancels.
  Future<bool> saveTemplate();
}

class YorksV1PlatformWorkerWorkbookFiles implements YorksV1WorkerWorkbookFiles {
  const YorksV1PlatformWorkerWorkbookFiles();

  static const _xlsxMime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  static const _xlsx = XTypeGroup(
    label: 'Excel workbook',
    extensions: ['xlsx'],
    mimeTypes: [_xlsxMime],
  );

  @override
  Future<YorksV1PickedWorkerWorkbook?> pickWorkbook() async {
    final file = await openFile(acceptedTypeGroups: const [_xlsx]);
    if (file == null) return null;
    final name = file.name.replaceAll('\\', '/').split('/').last;
    if (!name.toLowerCase().endsWith('.xlsx')) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    final workbook = const YorksV1BoqWorkbookCodec().decode(
      bytes: await file.readAsBytes(),
      fileName: name,
    );
    return YorksV1PickedWorkerWorkbook(
      fileName: name,
      sheets: [
        for (final sheet in workbook.sheets)
          if (!sheet.isHidden) sheet,
      ],
    );
  }

  @override
  Future<bool> saveTemplate() async {
    const name = 'Yorks_Worker_Records_Import_Template.xlsx';
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const [_xlsx],
    );
    if (location == null) return false;
    await XFile.fromData(
      yorksV1WorkerImportTemplate(),
      name: name,
      mimeType: _xlsxMime,
    ).saveTo(location.path);
    return true;
  }
}

/// A one-sheet workbook holding only the template headings.
Uint8List yorksV1WorkerImportTemplate() {
  String escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  String column(int index) => String.fromCharCode(65 + index);
  final headings = YorksV1WorkerSheetColumn.values;
  final cells = [
    for (var index = 0; index < headings.length; index++)
      '<c r="${column(index)}1" t="inlineStr"><is><t>'
          '${escape(headings[index].templateHeading)}</t></is></c>',
  ].join();
  final widths = [6, 32, 40, 20, 16, 14, 12, 12, 14];
  final cols = [
    for (var index = 0; index < widths.length; index++)
      '<col min="${index + 1}" max="${index + 1}" width="${widths[index]}" '
          'customWidth="1"/>',
  ].join();
  const ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  const rel =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  ArchiveFile text(String path, String content) {
    final bytes = utf8.encode(content);
    return ArchiveFile(path, bytes.length, bytes);
  }

  final archive = Archive()
    ..addFile(
      text(
        '[Content_Types].xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml" ContentType="application/xml"/>'
            '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
            '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
            '</Types>',
      ),
    )
    ..addFile(
      text(
        '_rels/.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="$rel/officeDocument" Target="xl/workbook.xml"/>'
            '</Relationships>',
      ),
    )
    ..addFile(
      text(
        'xl/workbook.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<workbook xmlns="$ns" xmlns:r="$rel">'
            '<sheets><sheet name="Workers" sheetId="1" r:id="rId1"/></sheets>'
            '</workbook>',
      ),
    )
    ..addFile(
      text(
        'xl/_rels/workbook.xml.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="$rel/worksheet" Target="worksheets/sheet1.xml"/>'
            '</Relationships>',
      ),
    )
    ..addFile(
      text(
        'xl/worksheets/sheet1.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<worksheet xmlns="$ns"><cols>$cols</cols>'
            '<sheetData><row r="1">$cells</row></sheetData></worksheet>',
      ),
    );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

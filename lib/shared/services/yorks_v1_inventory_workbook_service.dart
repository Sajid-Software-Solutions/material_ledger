import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/yorks_v1_boq_workbook.dart';
import '../models/yorks_v1_domain_error.dart';
import '../models/yorks_v1_inventory_supplier.dart';
import '../models/yorks_v1_inventory_workbook.dart';
import '../models/yorks_v1_logistics.dart';
import 'yorks_v1_boq_workbook_service.dart';
import 'yorks_v1_inventory_workbook_template.dart';

class YorksV1InventorySelectedWorkbook {
  const YorksV1InventorySelectedWorkbook({
    required this.fileName,
    required this.bytes,
    this.worksheetName,
  });

  final String fileName;
  final Uint8List bytes;
  final String? worksheetName;

  YorksV1InventorySelectedWorkbook selectWorksheet(String name) =>
      YorksV1InventorySelectedWorkbook(
        fileName: fileName,
        bytes: bytes,
        worksheetName: name,
      );
}

class YorksV1InventoryWorksheetOption {
  const YorksV1InventoryWorksheetOption({
    required this.name,
    required this.isHidden,
  });

  final String name;
  final bool isHidden;
}

abstract interface class YorksV1InventoryWorkbookFileService {
  Future<YorksV1InventorySelectedWorkbook?> selectWorkbook();

  Future<bool> saveImportTemplate();

  Future<bool> saveStockRegister({
    required YorksV1InventoryWorkspace workspace,
    required String suggestedName,
  });
}

abstract interface class YorksV1InventoryMovementPrintService {
  Future<bool> printMovementRegister(
    List<YorksV1InventoryMovement> movements, {
    bool Function()? canPrint,
  });
}

abstract interface class YorksV1InventoryMovementFileService {
  Future<bool> saveMovementRegister(List<YorksV1InventoryMovement> movements);
}

abstract interface class YorksV1InventorySupplierRegisterFileService {
  Future<bool> saveSupplierRegister({
    required List<YorksV1InventorySupplierDirectoryEntry> suppliers,
    required List<YorksV1InventorySupplierUnitTotal> unitTotals,
    DateTime? generatedAt,
  });
}

abstract interface class YorksV1InventoryImportEvidenceFileService {
  Future<bool> saveImportIssues({
    required YorksV1InventoryImportPreview preview,
  });

  Future<bool> saveCleanedImportPreview({
    required YorksV1InventoryImportPreview preview,
  });

  Future<bool> saveImportResult({
    required YorksV1InventoryImportPreview preview,
    required YorksV1InventoryImportResult result,
  });
}

class YorksV1PlatformInventoryWorkbookFileService
    implements
        YorksV1InventoryWorkbookFileService,
        YorksV1InventoryMovementFileService,
        YorksV1InventoryMovementPrintService,
        YorksV1InventorySupplierRegisterFileService,
        YorksV1InventoryImportEvidenceFileService {
  const YorksV1PlatformInventoryWorkbookFileService();

  static const _xlsxMime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  static const _xlsx = XTypeGroup(
    label: 'Excel workbook',
    extensions: ['xlsx'],
    mimeTypes: [_xlsxMime],
  );
  static const _csv = XTypeGroup(
    label: 'CSV data',
    extensions: ['csv'],
    mimeTypes: ['text/csv'],
  );
  @override
  Future<YorksV1InventorySelectedWorkbook?> selectWorkbook() async {
    final file = await openFile(acceptedTypeGroups: const [_xlsx, _csv]);
    if (file == null) return null;
    final name = _fileName(file.name);
    final extension = name.toLowerCase().split('.').last;
    if (extension != 'xlsx' && extension != 'csv') {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.lengthInBytes > 25 * 1024 * 1024) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    return YorksV1InventorySelectedWorkbook(fileName: name, bytes: bytes);
  }

  @override
  Future<bool> saveImportTemplate() => _save(
    bytes: base64Decode(yorksV1InventoryWorkbookTemplateBase64),
    name: 'Yorks_Warehouse_Inventory_Import_Template.xlsx',
    type: _xlsx,
    mimeType: _xlsxMime,
  );

  @override
  Future<bool> saveStockRegister({
    required YorksV1InventoryWorkspace workspace,
    required String suggestedName,
  }) => _save(
    bytes: buildStockRegisterWorkbook(workspace: workspace),
    name: suggestedName,
    type: _xlsx,
    mimeType: _xlsxMime,
  );

  @override
  Future<bool> saveMovementRegister(List<YorksV1InventoryMovement> movements) =>
      _save(
        bytes: buildMovementRegisterWorkbook(movements),
        name:
            'Yorks_Stock_Movements_${_dateStamp(DateTime.now().toUtc())}.xlsx',
        type: _xlsx,
        mimeType: _xlsxMime,
      );

  static const movementHeadings = [
    'Date (UTC)',
    'Item Code',
    'Item Description',
    'Unit',
    'Movement',
    'Quantity Change',
    'On Hand After',
    'Reason',
    'Actor',
    'Reference',
  ];

  static List<List<String>> movementRows(
    List<YorksV1InventoryMovement> movements,
  ) => [
    for (final m in movements)
      [
        m.createdAt.toUtc().toIso8601String(),
        m.itemCode ?? '',
        m.itemDescription ?? '',
        m.unit ?? '',
        m.movementType,
        m.quantityDelta,
        m.onHandAfterQuantity,
        m.reason,
        m.actorDisplayName,
        m.sourceEntityId ?? '',
      ],
  ];

  static Uint8List buildMovementRegisterWorkbook(
    List<YorksV1InventoryMovement> movements,
  ) => _encodeStyledStockRegister(
    title: 'Yorks Stock Movements',
    headings: movementHeadings,
    rows: movementRows(movements),
  );

  static Future<Uint8List> buildMovementPdf(
    List<YorksV1InventoryMovement> movements,
  ) async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
    final arabic = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
    );
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        fontFallback: [arabic],
      ),
    );
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        maxPages: 10000,
        margin: const pw.EdgeInsets.all(24),
        header: (_) => pw.Text(
          'Yorks Stock Movements',
          style: pw.TextStyle(font: bold, fontSize: 14),
        ),
        footer: (context) => pw.Text(
          '${context.pageNumber} / ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8),
        ),
        build: (_) => [
          pw.TableHelper.fromTextArray(
            headers: movementHeadings,
            data: movementRows(movements),
            cellStyle: const pw.TextStyle(fontSize: 7),
            headerStyle: pw.TextStyle(font: bold, fontSize: 7),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignment: pw.Alignment.centerLeft,
          ),
        ],
      ),
    );
    return pdf.save();
  }

  @override
  Future<bool> printMovementRegister(
    List<YorksV1InventoryMovement> movements, {
    bool Function()? canPrint,
  }) async {
    final bytes = await buildMovementPdf(movements);
    if (canPrint != null && !canPrint()) return false;
    return Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  @override
  Future<bool> saveSupplierRegister({
    required List<YorksV1InventorySupplierDirectoryEntry> suppliers,
    required List<YorksV1InventorySupplierUnitTotal> unitTotals,
    DateTime? generatedAt,
  }) {
    final generated = (generatedAt ?? DateTime.now()).toUtc();
    return _save(
      bytes: buildSupplierRegisterWorkbook(
        suppliers: suppliers,
        unitTotals: unitTotals,
        generatedAt: generated,
      ),
      name: supplierRegisterSuggestedName(generated),
      type: _xlsx,
      mimeType: _xlsxMime,
    );
  }

  @override
  Future<bool> saveImportIssues({
    required YorksV1InventoryImportPreview preview,
  }) => _save(
    bytes: buildImportIssuesWorkbook(preview: preview),
    name: importIssuesSuggestedName(preview.fileName),
    type: _xlsx,
    mimeType: _xlsxMime,
  );

  @override
  Future<bool> saveCleanedImportPreview({
    required YorksV1InventoryImportPreview preview,
  }) => _save(
    bytes: buildCleanedImportPreviewWorkbook(preview: preview),
    name: cleanedImportPreviewSuggestedName(preview.fileName),
    type: _xlsx,
    mimeType: _xlsxMime,
  );

  @override
  Future<bool> saveImportResult({
    required YorksV1InventoryImportPreview preview,
    required YorksV1InventoryImportResult result,
  }) => _save(
    bytes: buildImportResultWorkbook(preview: preview, result: result),
    name: importResultSuggestedName(preview.fileName, result.importBatchId),
    type: _xlsx,
    mimeType: _xlsxMime,
  );

  /// The stock register is a read-only operational snapshot. It deliberately
  /// contains neither costs nor valuation and cannot be re-imported as a
  /// quantity-changing command.
  static Uint8List buildStockRegisterWorkbook({
    required YorksV1InventoryWorkspace workspace,
    DateTime? generatedAt,
  }) {
    final generated = (generatedAt ?? DateTime.now()).toUtc();
    final title = 'Yorks Warehouse Stock Register — ${_dateStamp(generated)}';
    const headings = [
      'Item Code',
      'Item Description',
      'Category',
      'Brand / Origin',
      'Unit',
      'On Hand',
      'Reserved',
      'Available',
      'Minimum Stock',
      'Location / Bin',
      'Status',
      'Last Updated',
    ];
    final rows = [
      for (final item in workspace.items) _stockRegisterValues(item, generated),
    ];
    return _encodeStyledStockRegister(
      title: title,
      headings: headings,
      rows: rows,
    );
  }

  static String stockRegisterSuggestedName(DateTime generatedAt) =>
      'Yorks_Warehouse_Stock_Register_${_dateStamp(generatedAt.toUtc())}.xlsx';

  static String supplierRegisterSuggestedName(DateTime generatedAt) =>
      'Yorks_Inventory_Supplier_Register_${_dateStamp(generatedAt.toUtc())}.xlsx';

  static Uint8List buildSupplierRegisterWorkbook({
    required List<YorksV1InventorySupplierDirectoryEntry> suppliers,
    required List<YorksV1InventorySupplierUnitTotal> unitTotals,
    DateTime? generatedAt,
  }) {
    final generated = (generatedAt ?? DateTime.now()).toUtc();
    final orderedSuppliers =
        List<YorksV1InventorySupplierDirectoryEntry>.from(suppliers)
          ..sort((left, right) {
            if (left.isSystemUnknown != right.isSystemUnknown) {
              return left.isSystemUnknown ? -1 : 1;
            }
            return left.name.toLowerCase().compareTo(right.name.toLowerCase());
          });
    final groupedUnits = _groupSupplierUnitTotals(unitTotals);
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          '[Content_Types].xml',
          _supplierRegisterContentTypesXml,
        ),
      )
      ..addFile(
        ArchiveFile.string('_rels/.rels', _stockRegisterRootRelationshipsXml),
      )
      ..addFile(
        ArchiveFile.string('xl/workbook.xml', _supplierRegisterWorkbookXml),
      )
      ..addFile(
        ArchiveFile.string(
          'xl/_rels/workbook.xml.rels',
          _supplierRegisterWorkbookRelationshipsXml,
        ),
      )
      ..addFile(ArchiveFile.string('xl/styles.xml', _supplierRegisterStylesXml))
      ..addFile(
        ArchiveFile.string(
          'xl/worksheets/sheet1.xml',
          _supplierRegisterDirectorySheetXml(
            suppliers: orderedSuppliers,
            generatedAt: generated,
          ),
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'xl/worksheets/sheet2.xml',
          _supplierRegisterUnitSheetXml(
            totals: groupedUnits,
            generatedAt: generated,
          ),
        ),
      );
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static String importIssuesSuggestedName(String sourceFileName) =>
      '${_safeImportBaseName(sourceFileName)}_Issues.xlsx';

  static String cleanedImportPreviewSuggestedName(String sourceFileName) =>
      '${_safeImportBaseName(sourceFileName)}_Cleaned_Preview.xlsx';

  static String importResultSuggestedName(
    String sourceFileName,
    String importBatchId,
  ) =>
      '${_safeImportBaseName(sourceFileName)}_Result_${_safeFileToken(importBatchId)}.xlsx';

  static Uint8List buildImportIssuesWorkbook({
    required YorksV1InventoryImportPreview preview,
  }) {
    const headings = [
      'Source Row',
      'Severity',
      'Issue Code',
      'Detail',
      'Item Code',
      'Item Description',
      'Supplier Source Text',
      'Supplier Reference',
      'Received Date',
      'Unit',
      'Stock Action',
    ];
    final rows = <List<String>>[];
    for (final row in preview.rows) {
      for (final issue in row.issues) {
        rows.add([
          row.sourceRowNumber.toString(),
          issue.isWarning ? 'Warning' : 'Error',
          issue.code.name,
          issue.detail ?? '',
          row.itemCode,
          row.description,
          row.supplierSourceText,
          row.supplierReference,
          row.receivedDate,
          row.unit,
          row.stockAction?.displayName ?? '',
        ]);
      }
    }
    return _encodeImportEvidenceWorkbook([
      _InventoryImportExportSheet(
        name: 'Issues',
        title: 'Yorks Inventory Import Issues',
        subtitle:
            '${preview.fileName} • ${preview.errorCount} error rows • ${preview.warningCount} warning rows • current reviewed draft',
        headings: headings,
        rows: rows,
        emptyMessage: 'The current reviewed draft has no warnings or errors.',
      ),
    ]);
  }

  static Uint8List buildCleanedImportPreviewWorkbook({
    required YorksV1InventoryImportPreview preview,
  }) => _encodeImportEvidenceWorkbook([
    _InventoryImportExportSheet(
      name: 'Cleaned Preview',
      title: 'Yorks Inventory Cleaned Preview',
      subtitle:
          '${preview.fileName} • ${preview.rowCount} rows • strict validation draft • source file remains unchanged',
      headings: _cleanedImportHeadings,
      rows: [
        for (final row in preview.rows) _cleanedImportValues(row, preview),
      ],
      emptyMessage: 'No reviewed rows are available.',
    ),
  ]);

  static Uint8List buildImportResultWorkbook({
    required YorksV1InventoryImportPreview preview,
    required YorksV1InventoryImportResult result,
  }) {
    if (!preview.strictImport ||
        result.excludedCount != 0 ||
        result.rowCount != preview.rowCount) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    final summary = <List<String>>[
      ['Import Batch ID', result.importBatchId],
      ['Source File', preview.fileName],
      ['File SHA-256', preview.fileSha256 ?? ''],
      ['Import Mode', 'Strict'],
      ['Committed Rows', result.rowCount.toString()],
      ['Created Items', result.createdItems.toString()],
      ['Updated Items', result.updatedItems.toString()],
      ['Created Categories', result.createdCategories.toString()],
      ['Created Suppliers', result.createdSuppliers.toString()],
      ['Receipt Batches', result.receiptBatches.toString()],
      ['Stock Movements', result.movements.toString()],
      ['Warnings', result.warningCount.toString()],
      ['Excluded Rows', result.excludedCount.toString()],
      ['Unknown Supplier Rows', result.unknownSupplierRows.toString()],
    ];
    return _encodeImportEvidenceWorkbook([
      _InventoryImportExportSheet(
        name: 'Import Summary',
        title: 'Yorks Inventory Import Result',
        subtitle:
            'Authoritative server result • batch ${result.importBatchId} • strict atomic commit',
        headings: const ['Metric', 'Authoritative Result'],
        rows: summary,
        emptyMessage: 'No authoritative result was supplied.',
      ),
      _InventoryImportExportSheet(
        name: 'Committed Rows',
        title: 'Committed Row Evidence',
        subtitle:
            '${result.rowCount} rows committed atomically • no valid-rows-only exclusions',
        headings: [..._cleanedImportHeadings, 'Outcome', 'Import Batch ID'],
        rows: [
          for (final row in preview.rows)
            [
              ..._cleanedImportValues(row, preview),
              'Committed',
              result.importBatchId,
            ],
        ],
        emptyMessage: 'No committed rows were returned.',
      ),
      _InventoryImportExportSheet(
        name: 'Unit Totals',
        title: 'Committed Quantities by Unit',
        subtitle:
            'Accepted, damaged and rejected quantities remain separated by unit; no mixed-unit aggregate',
        headings: const ['Unit', 'Accepted', 'Damaged', 'Rejected'],
        rows: [
          for (final total in result.unitTotals)
            [
              total.unit,
              total.acceptedQuantity,
              total.damagedQuantity,
              total.rejectedQuantity,
            ],
        ],
        emptyMessage: 'No authoritative unit totals were returned.',
      ),
    ]);
  }

  static const _cleanedImportHeadings = <String>[
    'S:No',
    'Item Code *',
    'Category *',
    'Item Description *',
    'Size (If Any)',
    'Model / Tag',
    'Serial No',
    'Brand / Origin',
    'RAL Colour',
    'Stock Action *',
    'Quantity *',
    'Unit *',
    'Minimum Stock',
    'Location / Shelf',
    'External Supplier Name',
    'Supplier Reference / Delivery Note',
    'Received Date',
    'Notes',
    'Unit Price',
    'Total Price',
    'Accepted Quantity',
    'Damaged Quantity',
    'Rejected Quantity',
    'Validation Status',
    'Validation Notes',
  ];

  static List<String> _cleanedImportValues(
    YorksV1InventoryImportRow row,
    YorksV1InventoryImportPreview preview,
  ) => [
    _sourceSequenceValue(row, preview),
    row.itemCode,
    row.newCategoryName ?? row.sourceCategory,
    row.description,
    row.sizeText,
    row.modelTag,
    row.serialNumber,
    row.brandOrigin,
    row.ralColour,
    row.stockAction?.displayName ?? '',
    row.quantity,
    row.unit,
    row.minimumStock,
    row.locationBin,
    row.canonicalSupplierName ?? row.newSupplierName ?? row.supplierSourceText,
    row.supplierReference,
    row.receivedDate,
    row.notes,
    row.unitPrice,
    row.calculatedTotalPrice ?? '',
    row.acceptedQuantity ?? row.quantity,
    row.damagedQuantity,
    row.rejectedQuantity,
    row.hasErrors
        ? 'Error'
        : row.hasWarnings
        ? 'Warning'
        : 'Ready',
    row.issues
        .map(
          (issue) => issue.detail == null
              ? issue.code.name
              : '${issue.code.name}: ${issue.detail}',
        )
        .join('; '),
  ];

  static String _sourceSequenceValue(
    YorksV1InventoryImportRow row,
    YorksV1InventoryImportPreview preview,
  ) {
    final index = preview.mapping?.sourceIndex(
      YorksV1InventoryControlledField.sequence,
    );
    if (index != null && index < row.rawSourceValues.length) {
      return row.rawSourceValues[index];
    }
    return row.sourceRowNumber.toString();
  }

  static String _safeImportBaseName(String value) {
    final fileName = _fileName(value);
    final dot = fileName.lastIndexOf('.');
    final base = dot > 0 ? fileName.substring(0, dot) : fileName;
    final safe = _safeFileToken(base);
    return safe.isEmpty ? 'Yorks_Inventory_Import' : safe;
  }

  static String _safeFileToken(String value) {
    final safe = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return safe.length <= 72 ? safe : safe.substring(0, 72);
  }

  static Uint8List _encodeImportEvidenceWorkbook(
    List<_InventoryImportExportSheet> sheets,
  ) {
    if (sheets.isEmpty) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    final overrides = StringBuffer();
    final sheetNodes = StringBuffer();
    final relationships = StringBuffer();
    for (var index = 0; index < sheets.length; index++) {
      final number = index + 1;
      overrides.write(
        '<Override PartName="/xl/worksheets/sheet$number.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
      );
      sheetNodes.write(
        '<sheet name="${_xmlEscape(sheets[index].name)}" sheetId="$number" r:id="rId$number"/>',
      );
      relationships.write(
        '<Relationship Id="rId$number" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$number.xml"/>',
      );
    }
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          '[Content_Types].xml',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
              '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
              '<Default Extension="xml" ContentType="application/xml"/>'
              '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
              '${overrides.toString()}'
              '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
              '</Types>',
        ),
      )
      ..addFile(
        ArchiveFile.string('_rels/.rels', _stockRegisterRootRelationshipsXml),
      )
      ..addFile(
        ArchiveFile.string(
          'xl/workbook.xml',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
              '<sheets>${sheetNodes.toString()}</sheets></workbook>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'xl/_rels/workbook.xml.rels',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
              '${relationships.toString()}'
              '<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
              '</Relationships>',
        ),
      )
      ..addFile(
        ArchiveFile.string('xl/styles.xml', _supplierRegisterStylesXml),
      );
    for (var index = 0; index < sheets.length; index++) {
      archive.addFile(
        ArchiveFile.string(
          'xl/worksheets/sheet${index + 1}.xml',
          _importEvidenceSheetXml(sheets[index]),
        ),
      );
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static String _importEvidenceSheetXml(_InventoryImportExportSheet sheet) {
    final lastColumn = _excelColumnName(sheet.headings.length - 1);
    final output = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetViews><sheetView workbookViewId="0"><pane ySplit="3" topLeftCell="A4" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols>',
    );
    for (var index = 0; index < sheet.headings.length; index++) {
      final width = math.max(
        12,
        math.min(38, sheet.headings[index].length + 4),
      );
      output.write(
        '<col min="${index + 1}" max="${index + 1}" width="$width" customWidth="1"/>',
      );
    }
    output.write('</cols><sheetData>');
    output.write(
      '<row r="1" ht="27" customHeight="1">${_supplierRegisterCell('A1', sheet.title, 1)}</row>',
    );
    output.write(
      '<row r="2">${_supplierRegisterCell('A2', sheet.subtitle, 4)}</row>',
    );
    output.write('<row r="3" ht="23" customHeight="1">');
    for (var index = 0; index < sheet.headings.length; index++) {
      output.write(
        _supplierRegisterCell(
          '${_excelColumnName(index)}3',
          sheet.headings[index],
          2,
        ),
      );
    }
    output.write('</row>');
    if (sheet.rows.isEmpty) {
      output.write(
        '<row r="4">${_supplierRegisterCell('A4', sheet.emptyMessage, 4)}</row>',
      );
    } else {
      for (var rowIndex = 0; rowIndex < sheet.rows.length; rowIndex++) {
        final rowNumber = rowIndex + 4;
        output.write('<row r="$rowNumber">');
        for (var column = 0; column < sheet.headings.length; column++) {
          final value = column < sheet.rows[rowIndex].length
              ? sheet.rows[rowIndex][column]
              : '';
          output.write(
            _supplierRegisterCell(
              '${_excelColumnName(column)}$rowNumber',
              yorksV1InventorySafeSpreadsheetText(value),
              column == 0 ? 3 : 4,
            ),
          );
        }
        output.write('</row>');
      }
    }
    final lastRow = sheet.rows.isEmpty ? 4 : sheet.rows.length + 3;
    output.write(
      '</sheetData><autoFilter ref="A3:$lastColumn$lastRow"/>'
      '<mergeCells count="2"><mergeCell ref="A1:${lastColumn}1"/>'
      '<mergeCell ref="A2:${lastColumn}2"/></mergeCells></worksheet>',
    );
    return output.toString();
  }

  static List<String> _stockRegisterValues(
    YorksV1LogisticsInventoryItem item,
    DateTime generatedAt,
  ) => [
    item.itemCode ?? '',
    item.description,
    _parentCategoryName(item.categoryPath, item.categoryName),
    item.brandOrigin ?? '',
    item.unit,
    _displayQuantity(item.onHandQuantity),
    _displayQuantity(item.reservedQuantity),
    _displayQuantity(item.availableQuantity),
    item.minimumStock == null ? '' : _displayQuantity(item.minimumStock!),
    item.locationBin ?? '',
    item.isActive
        ? item.isOutOfStock
              ? 'Out of Stock'
              : item.isLowStock
              ? 'Low Stock'
              : 'In Stock'
        : 'Inactive',
    DateFormat(
      'dd MMM yyyy, hh:mm a',
    ).format((item.updatedAt ?? generatedAt).toLocal()),
  ];

  static String _parentCategoryName(String? path, String? fallback) {
    final index = path?.indexOf(' › ') ?? -1;
    if (index > 0) return path!.substring(0, index).trim();
    return fallback?.trim().isNotEmpty == true
        ? fallback!.trim()
        : 'Uncategorized';
  }

  static String _displayQuantity(String value) {
    final normalized = value.trim();
    if (!RegExp(r'^-?\d+(?:\.\d+)?$').hasMatch(normalized)) {
      return normalized;
    }
    return normalized
        .replaceFirstMapped(RegExp(r'(\.\d*?)0+$'), (match) => match.group(1)!)
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static List<YorksV1InventorySupplierUnitTotal> _groupSupplierUnitTotals(
    List<YorksV1InventorySupplierUnitTotal> totals,
  ) {
    final grouped =
        <
          String,
          ({
            String unit,
            List<String> accepted,
            List<String> damaged,
            List<String> rejected,
          })
        >{};
    for (final total in totals) {
      final key = yorksV1InventorySearchKey(total.unit);
      if (key.isEmpty) continue;
      final current = grouped[key];
      grouped[key] = (
        unit: current?.unit ?? total.unit.trim(),
        accepted: [...?current?.accepted, total.acceptedQuantity],
        damaged: [...?current?.damaged, total.damagedQuantity],
        rejected: [...?current?.rejected, total.rejectedQuantity],
      );
    }
    return [
      for (final group in grouped.values)
        YorksV1InventorySupplierUnitTotal(
          unit: group.unit,
          acceptedQuantity: _sumDecimalText(group.accepted),
          damagedQuantity: _sumDecimalText(group.damaged),
          rejectedQuantity: _sumDecimalText(group.rejected),
        ),
    ]..sort((left, right) => left.unit.compareTo(right.unit));
  }

  static String _sumDecimalText(List<String> values) {
    var scale = 0;
    for (final value in values) {
      final normalized = value.trim();
      if (!RegExp(r'^\d+(?:\.\d+)?$').hasMatch(normalized)) {
        throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
      }
      final dot = normalized.indexOf('.');
      if (dot >= 0) scale = math.max(scale, normalized.length - dot - 1);
    }
    var total = BigInt.zero;
    for (final value in values) {
      final pieces = value.trim().split('.');
      final fraction = pieces.length == 1 ? '' : pieces[1];
      total += BigInt.parse('${pieces[0]}${fraction.padRight(scale, '0')}');
    }
    if (scale == 0) return total.toString();
    final digits = total.toString().padLeft(scale + 1, '0');
    final whole = digits.substring(0, digits.length - scale);
    final fraction = digits
        .substring(digits.length - scale)
        .replaceFirst(RegExp(r'0+$'), '');
    return fraction.isEmpty ? whole : '$whole.$fraction';
  }

  static String _dateStamp(DateTime value) =>
      DateFormat('yyyy-MM-dd').format(value);

  static String _supplierRegisterDirectorySheetXml({
    required List<YorksV1InventorySupplierDirectoryEntry> suppliers,
    required DateTime generatedAt,
  }) {
    const headings = [
      'Supplier Code',
      'Supplier Name',
      'Status',
      'Aliases',
      'Description',
      'Receipt Batches',
      'Distinct Items',
      'Missing Documents',
      'Reconciliation Items',
      'Last Receipt',
      'System Folder',
    ];
    const widths = [15, 34, 18, 34, 38, 16, 15, 18, 20, 22, 16];
    final output = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetViews><sheetView workbookViewId="0"><pane ySplit="3" topLeftCell="A4" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols>',
    );
    for (var index = 0; index < widths.length; index++) {
      output.write(
        '<col min="${index + 1}" max="${index + 1}" width="${widths[index]}" customWidth="1"/>',
      );
    }
    output.write('</cols><sheetData>');
    output.write(
      '<row r="1" ht="27" customHeight="1">${_supplierRegisterCell('A1', 'Yorks Inventory Supplier Register', 1)}</row>',
    );
    output.write(
      '<row r="2">${_supplierRegisterCell('A2', 'Authorized directory snapshot • ${suppliers.length} supplier folders • Generated ${DateFormat('dd MMM yyyy, hh:mm a').format(generatedAt.toLocal())}', 4)}</row>',
    );
    output.write('<row r="3" ht="23" customHeight="1">');
    for (var index = 0; index < headings.length; index++) {
      output.write(
        _supplierRegisterCell(
          '${_excelColumnName(index)}3',
          headings[index],
          2,
        ),
      );
    }
    output.write('</row>');
    for (var index = 0; index < suppliers.length; index++) {
      final row = index + 4;
      final supplier = suppliers[index];
      final values = [
        supplier.code,
        supplier.name,
        supplier.status.wireValue.replaceAll('_', ' '),
        supplier.aliases.join('; '),
        supplier.description ?? '',
        supplier.receiptBatchCount.toString(),
        supplier.distinctItemCount.toString(),
        supplier.missingDocumentCount.toString(),
        supplier.reconciliationCount.toString(),
        supplier.lastReceiptAt == null
            ? ''
            : DateFormat(
                'dd MMM yyyy, hh:mm a',
              ).format(supplier.lastReceiptAt!.toLocal()),
        supplier.isSystemUnknown ? 'Yes — pinned system folder' : 'No',
      ];
      output.write('<row r="$row">');
      for (var column = 0; column < values.length; column++) {
        final style = supplier.isSystemUnknown
            ? 6
            : column >= 5 && column <= 8
            ? 5
            : column == 0
            ? 3
            : 4;
        output.write(
          _supplierRegisterCell(
            '${_excelColumnName(column)}$row',
            values[column],
            style,
          ),
        );
      }
      output.write('</row>');
    }
    if (suppliers.isEmpty) {
      output.write(
        '<row r="4">${_supplierRegisterCell('A4', 'No authorized supplier folders were available for this export.', 4)}</row>',
      );
    }
    final lastRow = suppliers.isEmpty ? 4 : suppliers.length + 3;
    output.write(
      '</sheetData><autoFilter ref="A3:K$lastRow"/><mergeCells count="2"><mergeCell ref="A1:K1"/><mergeCell ref="A2:K2"/></mergeCells></worksheet>',
    );
    return output.toString();
  }

  static String _supplierRegisterUnitSheetXml({
    required List<YorksV1InventorySupplierUnitTotal> totals,
    required DateTime generatedAt,
  }) {
    const headings = ['Unit', 'Accepted', 'Damaged', 'Rejected'];
    const widths = [22, 18, 18, 18];
    final output = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetViews><sheetView workbookViewId="0"><pane ySplit="3" topLeftCell="A4" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols>',
    );
    for (var index = 0; index < widths.length; index++) {
      output.write(
        '<col min="${index + 1}" max="${index + 1}" width="${widths[index]}" customWidth="1"/>',
      );
    }
    output.write('</cols><sheetData>');
    output.write(
      '<row r="1" ht="27" customHeight="1">${_supplierRegisterCell('A1', 'Receipt Quantities by Unit', 1)}</row>',
    );
    output.write(
      '<row r="2">${_supplierRegisterCell('A2', 'Units remain separate; no mixed-unit grand quantity is calculated • ${DateFormat('dd MMM yyyy').format(generatedAt.toLocal())}', 4)}</row>',
    );
    output.write('<row r="3" ht="23" customHeight="1">');
    for (var index = 0; index < headings.length; index++) {
      output.write(
        _supplierRegisterCell(
          '${_excelColumnName(index)}3',
          headings[index],
          2,
        ),
      );
    }
    output.write('</row>');
    for (var index = 0; index < totals.length; index++) {
      final row = index + 4;
      final total = totals[index];
      final values = [
        total.unit,
        _displayQuantity(total.acceptedQuantity),
        _displayQuantity(total.damagedQuantity),
        _displayQuantity(total.rejectedQuantity),
      ];
      output.write('<row r="$row">');
      for (var column = 0; column < values.length; column++) {
        output.write(
          _supplierRegisterCell(
            '${_excelColumnName(column)}$row',
            values[column],
            column == 0 ? 3 : 5,
          ),
        );
      }
      output.write('</row>');
    }
    if (totals.isEmpty) {
      output.write(
        '<row r="4">${_supplierRegisterCell('A4', 'No authorized unit totals were supplied for this export.', 4)}</row>',
      );
    }
    final lastRow = totals.isEmpty ? 4 : totals.length + 3;
    output.write(
      '</sheetData><autoFilter ref="A3:D$lastRow"/><mergeCells count="2"><mergeCell ref="A1:D1"/><mergeCell ref="A2:D2"/></mergeCells></worksheet>',
    );
    return output.toString();
  }

  static String _supplierRegisterCell(String ref, String value, int style) {
    final safe = yorksV1InventorySafeSpreadsheetText(value);
    final preserve = safe.trim() != safe ? ' xml:space="preserve"' : '';
    return '<c r="$ref" s="$style" t="inlineStr"><is><t$preserve>${_xmlEscape(safe)}</t></is></c>';
  }

  /// Uses only the small, documented subset of XLSX that the application also
  /// decodes: inline text cells, one sheet and explicit styles. This keeps the
  /// register visually usable in Excel/Numbers without introducing a mutable
  /// spreadsheet dependency or a second export data path.
  static Uint8List _encodeStyledStockRegister({
    required String title,
    required List<String> headings,
    required List<List<String>> rows,
  }) {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          '[Content_Types].xml',
          _stockRegisterContentTypesXml,
        ),
      )
      ..addFile(
        ArchiveFile.string('_rels/.rels', _stockRegisterRootRelationshipsXml),
      )
      ..addFile(
        ArchiveFile.string('xl/workbook.xml', _stockRegisterWorkbookXml),
      )
      ..addFile(
        ArchiveFile.string(
          'xl/_rels/workbook.xml.rels',
          _stockRegisterWorkbookRelationshipsXml,
        ),
      )
      ..addFile(ArchiveFile.string('xl/styles.xml', _stockRegisterStylesXml))
      ..addFile(
        ArchiveFile.string(
          'xl/worksheets/sheet1.xml',
          _stockRegisterSheetXml(title: title, headings: headings, rows: rows),
        ),
      );
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static String _stockRegisterSheetXml({
    required String title,
    required List<String> headings,
    required List<List<String>> rows,
  }) {
    const widths = [18, 36, 28, 24, 12, 12, 12, 12, 15, 18, 16, 24];
    final output = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetViews><sheetView workbookViewId="0"><pane ySplit="2" topLeftCell="A3" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>'
      '<cols>',
    );
    for (var index = 0; index < widths.length; index++) {
      output.write(
        '<col min="${index + 1}" max="${index + 1}" width="${widths[index]}" customWidth="1"/>',
      );
    }
    output.write('</cols><sheetData>');
    output.write(
      '<row r="1" ht="26" customHeight="1">${_stockRegisterCell('A1', title, 1)}</row>',
    );
    output.write('<row r="2" ht="23" customHeight="1">');
    for (var index = 0; index < headings.length; index++) {
      output.write(
        _stockRegisterCell('${_excelColumnName(index)}2', headings[index], 2),
      );
    }
    output.write('</row>');
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final excelRow = rowIndex + 3;
      output.write('<row r="$excelRow">');
      for (
        var columnIndex = 0;
        columnIndex < rows[rowIndex].length;
        columnIndex++
      ) {
        final style = columnIndex == 0
            ? 3
            : columnIndex >= 5 && columnIndex <= 8
            ? 5
            : 4;
        output.write(
          _stockRegisterCell(
            '${_excelColumnName(columnIndex)}$excelRow',
            rows[rowIndex][columnIndex],
            style,
          ),
        );
      }
      output.write('</row>');
    }
    final lastRow = rows.length + 2;
    output.write(
      '</sheetData><autoFilter ref="A2:L$lastRow"/><mergeCells count="1"><mergeCell ref="A1:L1"/></mergeCells></worksheet>',
    );
    return output.toString();
  }

  static String _stockRegisterCell(String ref, String value, int style) {
    final safe = yorksV1InventorySafeSpreadsheetText(value);
    final preserve = safe.trim() != safe ? ' xml:space="preserve"' : '';
    return '<c r="$ref" s="$style" t="inlineStr"><is><t$preserve>${_xmlEscape(safe)}</t></is></c>';
  }

  static String _excelColumnName(int index) {
    var value = index + 1;
    final output = StringBuffer();
    while (value > 0) {
      value--;
      output.writeCharCode(65 + (value % 26));
      value ~/= 26;
    }
    return output.toString().split('').reversed.join();
  }

  static String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static const _stockRegisterContentTypesXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
      '</Types>';
  static const _stockRegisterRootRelationshipsXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>';
  static const _stockRegisterWorkbookXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets><sheet name="Stock Register" sheetId="1" r:id="rId1"/></sheets></workbook>';
  static const _stockRegisterWorkbookRelationshipsXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '</Relationships>';
  static const _stockRegisterStylesXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<fonts count="2"><font><sz val="11"/><color theme="1"/><name val="Arial"/><family val="2"/></font><font><b/><sz val="11"/><color rgb="FF132033"/><name val="Arial"/><family val="2"/></font></fonts>'
      '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFD9E0E5"/><bgColor indexed="64"/></patternFill></fill></fills>'
      '<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"><color rgb="FFBFC7D1"/></left><right style="thin"><color rgb="FFBFC7D1"/></right><top style="thin"><color rgb="FFBFC7D1"/></top><bottom style="thin"><color rgb="FFBFC7D1"/></bottom><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="6"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" applyAlignment="1" xfId="0"><alignment horizontal="center" vertical="center"/></xf><xf numFmtId="0" fontId="1" fillId="2" borderId="1" applyAlignment="1" xfId="0"><alignment horizontal="center" vertical="center"/></xf><xf numFmtId="0" fontId="1" fillId="0" borderId="1" applyAlignment="1" xfId="0"><alignment vertical="center"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="1" applyAlignment="1" xfId="0"><alignment vertical="center"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="1" applyAlignment="1" xfId="0"><alignment horizontal="right" vertical="center"/></xf></cellXfs>'
      '</styleSheet>';
  static const _supplierRegisterContentTypesXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      '<Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
      '</Types>';
  static const _supplierRegisterWorkbookXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets><sheet name="Supplier Register" sheetId="1" r:id="rId1"/><sheet name="Unit Totals" sheetId="2" r:id="rId2"/></sheets></workbook>';
  static const _supplierRegisterWorkbookRelationshipsXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>'
      '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '</Relationships>';
  static const _supplierRegisterStylesXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<fonts count="2"><font><sz val="11"/><color theme="1"/><name val="Arial"/><family val="2"/></font><font><b/><sz val="11"/><color rgb="FF132033"/><name val="Arial"/><family val="2"/></font></fonts>'
      '<fills count="4"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFD9E0E5"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFFFF3D6"/><bgColor indexed="64"/></patternFill></fill></fills>'
      '<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"><color rgb="FFBFC7D1"/></left><right style="thin"><color rgb="FFBFC7D1"/></right><top style="thin"><color rgb="FFBFC7D1"/></top><bottom style="thin"><color rgb="FFBFC7D1"/></bottom><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="7"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" applyAlignment="1" xfId="0"><alignment horizontal="center" vertical="center"/></xf><xf numFmtId="0" fontId="1" fillId="2" borderId="1" applyAlignment="1" xfId="0"><alignment horizontal="center" vertical="center"/></xf><xf numFmtId="0" fontId="1" fillId="0" borderId="1" applyAlignment="1" xfId="0"><alignment vertical="center"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="1" applyAlignment="1" xfId="0"><alignment vertical="center" wrapText="1"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="1" applyAlignment="1" xfId="0"><alignment horizontal="right" vertical="center"/></xf><xf numFmtId="0" fontId="1" fillId="3" borderId="1" applyAlignment="1" xfId="0"><alignment vertical="center" wrapText="1"/></xf></cellXfs>'
      '</styleSheet>';

  static Future<bool> _save({
    required Uint8List bytes,
    required String name,
    required XTypeGroup type,
    required String mimeType,
  }) async {
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: [type],
    );
    if (location == null) return false;
    await XFile.fromData(
      bytes,
      name: name,
      mimeType: mimeType,
    ).saveTo(location.path);
    return true;
  }

  static String _fileName(String pathOrName) {
    final normalized = pathOrName.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    return slash < 0 ? normalized : normalized.substring(slash + 1);
  }
}

class YorksV1InventoryCategoryMatcher {
  const YorksV1InventoryCategoryMatcher();

  YorksV1InventoryCategory? exact(
    String value,
    List<YorksV1InventoryCategory> categories,
  ) {
    final key = yorksV1InventorySearchKey(value);
    if (key.isEmpty) return null;
    for (final category in categories) {
      if (yorksV1InventorySearchKey(category.name) == key ||
          yorksV1InventorySearchKey(category.displayPath) == key ||
          category.aliases.any(
            (alias) => yorksV1InventorySearchKey(alias) == key,
          )) {
        return category;
      }
    }
    return null;
  }

  List<YorksV1InventoryCategorySuggestion> rank(
    String value,
    List<YorksV1InventoryCategory> categories,
  ) {
    final result =
        <YorksV1InventoryCategorySuggestion>[
          for (final category in categories)
            YorksV1InventoryCategorySuggestion(
              category: category,
              score: math.max(
                _similarity(value, category.displayPath),
                math.max(
                  _similarity(value, category.name),
                  category.aliases.fold<double>(
                    0,
                    (best, alias) => math.max(best, _similarity(value, alias)),
                  ),
                ),
              ),
            ),
        ]..sort((a, b) {
          final score = b.score.compareTo(a.score);
          return score != 0
              ? score
              : a.category.name.compareTo(b.category.name);
        });
    return result.take(5).toList(growable: false);
  }

  static double _similarity(String left, String right) {
    final leftKey = yorksV1InventorySearchKey(left);
    final rightKey = yorksV1InventorySearchKey(right);
    if (leftKey.isEmpty || rightKey.isEmpty) return 0;
    if (leftKey == rightKey) return 1;
    final direct = _normalizedLevenshtein(leftKey, rightKey);
    final sortedLeft = _tokenKey(left);
    final sortedRight = _tokenKey(right);
    return math.max(direct, _normalizedLevenshtein(sortedLeft, sortedRight));
  }

  static String _tokenKey(String value) {
    final tokens =
        value
            .toLowerCase()
            .split(RegExp(r'[^a-z0-9]+'))
            .where((token) => token.isNotEmpty)
            .map(
              (token) => token.length > 3 && token.endsWith('s')
                  ? token.substring(0, token.length - 1)
                  : token,
            )
            .toList()
          ..sort();
    return tokens.join();
  }

  static double _normalizedLevenshtein(String left, String right) {
    final longest = math.max(left.length, right.length);
    if (longest == 0) return 1;
    final previous = List<int>.generate(right.length + 1, (index) => index);
    final current = List<int>.filled(right.length + 1, 0);
    for (var leftIndex = 1; leftIndex <= left.length; leftIndex++) {
      current[0] = leftIndex;
      for (var rightIndex = 1; rightIndex <= right.length; rightIndex++) {
        final substitution =
            previous[rightIndex - 1] +
            (left.codeUnitAt(leftIndex - 1) == right.codeUnitAt(rightIndex - 1)
                ? 0
                : 1);
        current[rightIndex] = math.min(
          math.min(previous[rightIndex] + 1, current[rightIndex - 1] + 1),
          substitution,
        );
      }
      for (var index = 0; index < previous.length; index++) {
        previous[index] = current[index];
      }
    }
    return 1 - (previous[right.length] / longest);
  }
}

class YorksV1InventorySupplierMatcher {
  const YorksV1InventorySupplierMatcher();

  List<YorksV1InventorySupplierMaster> exactMatches(
    String value,
    List<YorksV1InventorySupplierMaster> suppliers,
  ) {
    final key = yorksV1InventorySearchKey(value);
    if (key.isEmpty) return const [];
    return [
      for (final supplier in suppliers)
        if (yorksV1InventorySearchKey(supplier.name) == key ||
            supplier.aliases.any(
              (alias) => yorksV1InventorySearchKey(alias) == key,
            ))
          supplier,
    ];
  }

  List<YorksV1InventorySupplierSuggestion> rank(
    String value,
    List<YorksV1InventorySupplierMaster> suppliers,
  ) {
    final result =
        <YorksV1InventorySupplierSuggestion>[
          for (final supplier in suppliers)
            if (supplier.isActive && !supplier.isUnknownSupplier)
              YorksV1InventorySupplierSuggestion(
                supplier: supplier,
                score: math.max(
                  YorksV1InventoryCategoryMatcher._similarity(
                    value,
                    supplier.name,
                  ),
                  supplier.aliases.fold<double>(
                    0,
                    (best, alias) => math.max(
                      best,
                      YorksV1InventoryCategoryMatcher._similarity(value, alias),
                    ),
                  ),
                ),
              ),
        ]..sort((a, b) {
          final byScore = b.score.compareTo(a.score);
          return byScore != 0
              ? byScore
              : a.supplier.name.compareTo(b.supplier.name);
        });
    return result
        .where((suggestion) => suggestion.score >= 0.20)
        .take(5)
        .toList(growable: false);
  }
}

class YorksV1InventoryWorkbookCodec {
  const YorksV1InventoryWorkbookCodec({
    this.matcher = const YorksV1InventoryCategoryMatcher(),
    this.supplierMatcher = const YorksV1InventorySupplierMatcher(),
  });

  final YorksV1InventoryCategoryMatcher matcher;
  final YorksV1InventorySupplierMatcher supplierMatcher;

  YorksV1InventoryImportPreview decode({
    required YorksV1InventorySelectedWorkbook workbook,
    required List<YorksV1InventoryCategory> categories,
    required List<YorksV1LogisticsInventoryItem> inventoryItems,
    List<YorksV1InventorySupplierMaster> suppliers = const [],
    bool requireR38_9Columns = false,
  }) {
    final source = read(workbook);
    final mapping = proposeMapping(
      source,
      requireR38_9Fields: requireR38_9Columns,
    );
    if (!mapping.canContinue) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    return previewFromSource(
      mapping: mapping,
      categories: categories,
      inventoryItems: inventoryItems,
      suppliers: suppliers,
    );
  }

  YorksV1InventoryWorkbookSource read(
    YorksV1InventorySelectedWorkbook workbook,
  ) {
    _validateSelectedWorkbook(workbook);
    final lowerName = workbook.fileName.toLowerCase();
    final decoded = lowerName.endsWith('.csv')
        ? (
            matrix: _decodeCsv(workbook.bytes),
            worksheetName: null as String?,
            worksheetNames: const <String>[],
          )
        : _decodeXlsx(workbook);
    return sourceFromMatrix(
      fileName: workbook.fileName,
      matrix: decoded.matrix,
      fileSha256: sha256.convert(workbook.bytes).toString(),
      worksheetName: decoded.worksheetName,
      availableWorksheetNames: decoded.worksheetNames,
    );
  }

  /// Returns every worksheet name without selecting one. CSV files have no
  /// worksheet choice. The same file-size and type boundary as [read] applies.
  List<String> availableWorksheetNames(
    YorksV1InventorySelectedWorkbook workbook,
  ) => [for (final option in availableWorksheets(workbook)) option.name];

  /// Hidden and very-hidden worksheets remain selectable, but the UI must
  /// identify them clearly so an operator never commits one by accident.
  List<YorksV1InventoryWorksheetOption> availableWorksheets(
    YorksV1InventorySelectedWorkbook workbook,
  ) {
    _validateSelectedWorkbook(workbook);
    if (workbook.fileName.toLowerCase().endsWith('.csv')) return const [];
    return [
      for (final sheet in _decodeInventoryXlsx(workbook).sheets)
        YorksV1InventoryWorksheetOption(
          name: sheet.name,
          isHidden: sheet.isHidden,
        ),
    ];
  }

  YorksV1InventoryWorkbookSource sourceFromMatrix({
    required String fileName,
    required List<List<String>> matrix,
    String? fileSha256,
    String? worksheetName,
    List<String> availableWorksheetNames = const [],
  }) {
    if (matrix.isEmpty) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    final headerRowIndex = _findHeaderRow(matrix);
    final headers = matrix[headerRowIndex];
    final rawRows = <List<String>>[];
    final sourceRowNumbers = <int>[];
    for (var index = headerRowIndex + 1; index < matrix.length; index++) {
      final row = matrix[index];
      if (row.every((value) => value.trim().isEmpty)) continue;
      rawRows.add(List<String>.from(row));
      sourceRowNumbers.add(index + 1);
    }
    if (rawRows.isEmpty || rawRows.length > 20000) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    final columns = <YorksV1InventorySourceColumn>[];
    for (var column = 0; column < headers.length; column++) {
      final samples = <String>[];
      for (final row in rawRows) {
        if (column >= row.length) continue;
        final value = row[column].trim();
        if (value.isEmpty || samples.contains(value)) continue;
        samples.add(value);
        if (samples.length == 3) break;
      }
      columns.add(
        YorksV1InventorySourceColumn(
          index: column,
          header: headers[column].trim(),
          sampleValues: samples,
        ),
      );
    }
    return YorksV1InventoryWorkbookSource(
      fileName: fileName,
      fileSha256:
          fileSha256 ??
          sha256.convert(utf8.encode(jsonEncode(matrix))).toString(),
      worksheetName: worksheetName,
      availableWorksheetNames: availableWorksheetNames,
      headerRowIndex: headerRowIndex,
      columns: columns,
      dataRows: rawRows,
      sourceRowNumbers: sourceRowNumbers,
    );
  }

  YorksV1InventoryColumnMapping proposeMapping(
    YorksV1InventoryWorkbookSource source, {
    bool requireR38_9Fields = true,
  }) {
    final indexes = <YorksV1InventoryControlledField, int>{};
    final issues = <YorksV1InventoryColumnMappingIssue>[];
    for (final field in YorksV1InventoryControlledField.values) {
      final matches = [
        for (final column in source.columns)
          if (field.recognizesHeader(column.header)) column.index,
      ];
      if (matches.isNotEmpty) indexes[field] = matches.first;
      if (matches.length > 1) {
        issues.add(
          YorksV1InventoryColumnMappingIssue(
            code: YorksV1InventoryColumnMappingIssueCode.ambiguousSourceHeader,
            field: field,
            sourceColumnIndex: matches.first,
          ),
        );
      }
    }
    return _validatedMapping(
      source: source,
      indexes: indexes,
      requireR38_9Fields: requireR38_9Fields,
      priorIssues: issues,
    );
  }

  YorksV1InventoryColumnMapping updateMapping({
    required YorksV1InventoryColumnMapping mapping,
    required YorksV1InventoryControlledField field,
    required int? sourceColumnIndex,
    bool? requireR38_9Fields,
  }) {
    final indexes = Map<YorksV1InventoryControlledField, int>.from(
      mapping.indexes,
    );
    if (sourceColumnIndex == null) {
      indexes.remove(field);
    } else if (sourceColumnIndex < 0 ||
        sourceColumnIndex >= mapping.source.columns.length) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    } else {
      indexes[field] = sourceColumnIndex;
    }
    return _validatedMapping(
      source: mapping.source,
      indexes: indexes,
      requireR38_9Fields: requireR38_9Fields ?? mapping.requiresR38_9Fields,
      treatWorkbookAsOpeningBalance:
          field == YorksV1InventoryControlledField.sourceType &&
              sourceColumnIndex != null
          ? false
          : mapping.treatWorkbookAsOpeningBalance,
      unitMappings: mapping.unitMappings,
      cellEdits: mapping.cellEdits,
    );
  }

  YorksV1InventoryColumnMapping applyOpeningBalanceDefault({
    required YorksV1InventoryColumnMapping mapping,
    required bool enabled,
    bool? requireR38_9Fields,
  }) {
    if (enabled &&
        mapping.indexes.containsKey(
          YorksV1InventoryControlledField.sourceType,
        )) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    return _validatedMapping(
      source: mapping.source,
      indexes: mapping.indexes,
      requireR38_9Fields:
          requireR38_9Fields ?? (mapping.requiresR38_9Fields || enabled),
      treatWorkbookAsOpeningBalance: enabled,
      unitMappings: mapping.unitMappings,
      cellEdits: mapping.cellEdits,
    );
  }

  YorksV1InventoryColumnMapping applyUnitMapping({
    required YorksV1InventoryColumnMapping mapping,
    required String sourceUnitText,
    required String controlledUnit,
  }) {
    final sourceKey = yorksV1InventorySearchKey(sourceUnitText);
    final canonicalUnit = yorksV1InventoryCanonicalUnit(controlledUnit);
    if (sourceKey.isEmpty || canonicalUnit == null) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    return _validatedMapping(
      source: mapping.source,
      indexes: mapping.indexes,
      requireR38_9Fields: mapping.requiresR38_9Fields,
      treatWorkbookAsOpeningBalance: mapping.treatWorkbookAsOpeningBalance,
      unitMappings: [
        for (final decision in mapping.unitMappings)
          if (decision.sourceKey != sourceKey) decision,
        YorksV1InventoryUnitMappingDecision(
          sourceUnitText: sourceUnitText.trim(),
          controlledUnit: canonicalUnit,
        ),
      ],
      cellEdits: mapping.cellEdits,
    );
  }

  YorksV1InventoryColumnMapping clearUnitMapping({
    required YorksV1InventoryColumnMapping mapping,
    required String sourceUnitText,
  }) {
    final sourceKey = yorksV1InventorySearchKey(sourceUnitText);
    return _validatedMapping(
      source: mapping.source,
      indexes: mapping.indexes,
      requireR38_9Fields: mapping.requiresR38_9Fields,
      treatWorkbookAsOpeningBalance: mapping.treatWorkbookAsOpeningBalance,
      unitMappings: [
        for (final decision in mapping.unitMappings)
          if (decision.sourceKey != sourceKey) decision,
      ],
      cellEdits: mapping.cellEdits,
    );
  }

  YorksV1InventoryColumnMapping applyCellEdit({
    required YorksV1InventoryColumnMapping mapping,
    required int sourceRowNumber,
    required YorksV1InventoryControlledField field,
    required String value,
    YorksV1InventoryCellEditOrigin origin =
        YorksV1InventoryCellEditOrigin.directEdit,
  }) {
    if (!yorksV1InventorySafeEditableFields.contains(field)) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    final rowIndex = mapping.source.sourceRowNumbers.indexOf(sourceRowNumber);
    if (rowIndex < 0) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    final originalValue = _sourceCellValue(mapping, rowIndex, field);
    final nextEdits = [
      for (final edit in mapping.cellEdits)
        if (edit.sourceRowNumber != sourceRowNumber || edit.field != field)
          edit,
      if (value != originalValue)
        YorksV1InventoryCellEdit(
          sourceRowNumber: sourceRowNumber,
          field: field,
          originalValue: originalValue,
          value: value,
          origin: origin,
        ),
    ];
    return _validatedMapping(
      source: mapping.source,
      indexes: mapping.indexes,
      requireR38_9Fields: mapping.requiresR38_9Fields,
      treatWorkbookAsOpeningBalance: mapping.treatWorkbookAsOpeningBalance,
      unitMappings: mapping.unitMappings,
      cellEdits: nextEdits,
    );
  }

  /// Applies an exact-value replacement only to the reviewed, quantity-neutral
  /// fields. This is intentionally not a substring rewrite: technical model
  /// punctuation and item identifiers must never be changed incidentally.
  YorksV1InventoryBulkEditResult applyExactSearchAndReplace({
    required YorksV1InventoryColumnMapping mapping,
    required YorksV1InventoryControlledField field,
    required String sourceText,
    required String replacementText,
  }) {
    if (!yorksV1InventorySafeEditableFields.contains(field) ||
        sourceText == replacementText) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    var next = mapping;
    var affected = 0;
    for (var index = 0; index < mapping.source.dataRows.length; index++) {
      final sourceRowNumber = mapping.source.sourceRowNumbers[index];
      if (_effectiveCellValue(mapping, index, field) != sourceText) continue;
      next = applyCellEdit(
        mapping: next,
        sourceRowNumber: sourceRowNumber,
        field: field,
        value: replacementText,
        origin: YorksV1InventoryCellEditOrigin.searchAndReplace,
      );
      affected++;
    }
    return YorksV1InventoryBulkEditResult(
      mapping: next,
      affectedRows: affected,
    );
  }

  /// Removes control characters and normalizes whitespace in review-editable
  /// text only. It is idempotent and never changes quantity, stock action,
  /// source type, unit, price or total.
  YorksV1InventoryBulkEditResult applySafeFixes(
    YorksV1InventoryColumnMapping mapping,
  ) {
    var next = mapping;
    final affectedRows = <int>{};
    for (var index = 0; index < mapping.source.dataRows.length; index++) {
      final sourceRowNumber = mapping.source.sourceRowNumbers[index];
      for (final field in yorksV1InventorySafeEditableFields) {
        final current = _effectiveCellValue(mapping, index, field);
        final normalized = _normalizeSafeReviewText(current, field);
        if (normalized == current) continue;
        next = applyCellEdit(
          mapping: next,
          sourceRowNumber: sourceRowNumber,
          field: field,
          value: normalized,
          origin: YorksV1InventoryCellEditOrigin.safeFix,
        );
        affectedRows.add(sourceRowNumber);
      }
    }
    return YorksV1InventoryBulkEditResult(
      mapping: next,
      affectedRows: affectedRows.length,
    );
  }

  static String _sourceCellValue(
    YorksV1InventoryColumnMapping mapping,
    int rowIndex,
    YorksV1InventoryControlledField field,
  ) {
    final sourceIndex = mapping.indexes[field];
    final row = mapping.source.dataRows[rowIndex];
    return sourceIndex == null || sourceIndex >= row.length
        ? ''
        : row[sourceIndex];
  }

  static String _effectiveCellValue(
    YorksV1InventoryColumnMapping mapping,
    int rowIndex,
    YorksV1InventoryControlledField field,
  ) {
    final sourceRowNumber = mapping.source.sourceRowNumbers[rowIndex];
    return mapping.cellEditFor(sourceRowNumber, field)?.value ??
        _sourceCellValue(mapping, rowIndex, field);
  }

  static String _normalizeSafeReviewText(
    String value,
    YorksV1InventoryControlledField field,
  ) {
    final withoutControls = value.replaceAll(
      RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]'),
      '',
    );
    if (field == YorksV1InventoryControlledField.notes) {
      return withoutControls
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim().replaceAll(RegExp(r'[ \t]+'), ' '))
          .join('\n')
          .trim();
    }
    return withoutControls.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  YorksV1InventoryColumnMapping _validatedMapping({
    required YorksV1InventoryWorkbookSource source,
    required Map<YorksV1InventoryControlledField, int> indexes,
    required bool requireR38_9Fields,
    bool treatWorkbookAsOpeningBalance = false,
    List<YorksV1InventoryUnitMappingDecision> unitMappings = const [],
    List<YorksV1InventoryCellEdit> cellEdits = const [],
    List<YorksV1InventoryColumnMappingIssue> priorIssues = const [],
  }) {
    final issues = [...priorIssues];
    for (final field in YorksV1InventoryControlledField.values) {
      final required =
          field.isRequired &&
          (requireR38_9Fields ||
              field != YorksV1InventoryControlledField.sourceType) &&
          !(field == YorksV1InventoryControlledField.sourceType &&
              treatWorkbookAsOpeningBalance);
      if (required && !indexes.containsKey(field)) {
        issues.add(
          YorksV1InventoryColumnMappingIssue(
            code: YorksV1InventoryColumnMappingIssueCode.missingRequiredField,
            field: field,
          ),
        );
      }
    }
    final bySource = <int, List<YorksV1InventoryControlledField>>{};
    for (final entry in indexes.entries) {
      bySource.putIfAbsent(entry.value, () => []).add(entry.key);
    }
    for (final entry in bySource.entries) {
      if (entry.value.length < 2) continue;
      issues.add(
        YorksV1InventoryColumnMappingIssue(
          code: YorksV1InventoryColumnMappingIssueCode.duplicateSourceColumn,
          field: entry.value.first,
          sourceColumnIndex: entry.key,
        ),
      );
    }
    return YorksV1InventoryColumnMapping(
      source: source,
      indexes: indexes,
      issues: issues,
      requiresR38_9Fields: requireR38_9Fields,
      treatWorkbookAsOpeningBalance: treatWorkbookAsOpeningBalance,
      unitMappings: unitMappings,
      cellEdits: cellEdits,
    );
  }

  YorksV1InventoryImportPreview previewFromMatrix({
    required String fileName,
    required List<List<String>> matrix,
    required List<YorksV1InventoryCategory> categories,
    required List<YorksV1LogisticsInventoryItem> inventoryItems,
    List<YorksV1InventorySupplierMaster> suppliers = const [],
    bool requireR38_9Columns = false,
  }) {
    final source = sourceFromMatrix(fileName: fileName, matrix: matrix);
    final mapping = proposeMapping(
      source,
      requireR38_9Fields: requireR38_9Columns,
    );
    if (!mapping.canContinue) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    return previewFromSource(
      mapping: mapping,
      categories: categories,
      inventoryItems: inventoryItems,
      suppliers: suppliers,
    );
  }

  YorksV1InventoryImportPreview previewFromSource({
    required YorksV1InventoryColumnMapping mapping,
    required List<YorksV1InventoryCategory> categories,
    required List<YorksV1LogisticsInventoryItem> inventoryItems,
    List<YorksV1InventorySupplierMaster> suppliers = const [],
  }) {
    if (!mapping.canContinue) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    final rows = <_RawInventoryRow>[];
    for (var index = 0; index < mapping.source.dataRows.length; index++) {
      final source = mapping.source.dataRows[index];
      final sourceRowNumber = mapping.source.sourceRowNumbers[index];
      String raw(YorksV1InventoryControlledField field) {
        final sourceIndex = mapping.indexes[field];
        return sourceIndex == null || sourceIndex >= source.length
            ? ''
            : source[sourceIndex];
      }

      String effective(YorksV1InventoryControlledField field) =>
          mapping.cellEditFor(sourceRowNumber, field)?.value ?? raw(field);

      final rawUnit = raw(YorksV1InventoryControlledField.unit).trim();
      final mappedUnit = mapping.controlledUnitFor(rawUnit);
      final rawAction = raw(YorksV1InventoryControlledField.stockAction).trim();
      final normalizeOpeningAction =
          mapping.treatWorkbookAsOpeningBalance &&
          YorksV1InventoryStockAction.parse(rawAction) ==
              YorksV1InventoryStockAction.addStock;
      final effectiveAction = normalizeOpeningAction
          ? 'Opening Balance'
          : rawAction;
      final declaredSourceType = raw(
        YorksV1InventoryControlledField.sourceType,
      ).trim();
      final inferredSourceType = _sourceTypeForStockAction(
        YorksV1InventoryStockAction.parse(effectiveAction),
      );
      final action = YorksV1InventoryStockAction.parse(effectiveAction);
      final suppliedReason = effective(
        YorksV1InventoryControlledField.reason,
      ).trim();
      final notes = effective(YorksV1InventoryControlledField.notes).trim();
      final controlledReason = switch (action) {
        YorksV1InventoryStockAction.openingBalance =>
          'Inventory import: Opening Balance',
        YorksV1InventoryStockAction.addStock => 'Inventory import: Add Stock',
        YorksV1InventoryStockAction.noStockChange =>
          'Inventory import: No Stock Change',
        _ => '',
      };

      rows.add(
        _RawInventoryRow(
          sourceRowNumber: sourceRowNumber,
          itemCode: effective(YorksV1InventoryControlledField.itemCode).trim(),
          description: effective(
            YorksV1InventoryControlledField.description,
          ).trim(),
          sourceCategory: effective(
            YorksV1InventoryControlledField.category,
          ).trim(),
          brandOrigin: effective(
            YorksV1InventoryControlledField.brandOrigin,
          ).trim(),
          unit: mappedUnit ?? rawUnit,
          rawUnit: rawUnit,
          unitWasMapped: mappedUnit != null,
          action: effectiveAction,
          stockActionWasNormalized: normalizeOpeningAction,
          quantity: raw(YorksV1InventoryControlledField.quantity).trim(),
          reason: suppliedReason.isNotEmpty
              ? suppliedReason
              : notes.isNotEmpty
              ? notes
              : controlledReason,
          minimumStock: effective(
            YorksV1InventoryControlledField.minimumStock,
          ).trim(),
          locationBin: effective(
            YorksV1InventoryControlledField.locationShelf,
          ).trim(),
          notes: notes,
          sizeText: effective(YorksV1InventoryControlledField.sizeText).trim(),
          modelTag: effective(YorksV1InventoryControlledField.modelTag).trim(),
          serialNumber: yorksV1InventoryNormalizeOptionalSerial(
            effective(YorksV1InventoryControlledField.serialNumber),
          ),
          ralColour: effective(
            YorksV1InventoryControlledField.ralColour,
          ).trim(),
          sourceType: declaredSourceType.isNotEmpty
              ? declaredSourceType
              : inferredSourceType?.displayName ?? '',
          sourceTypeWasDefaulted: mapping.treatWorkbookAsOpeningBalance,
          supplierName: effective(
            YorksV1InventoryControlledField.externalSupplierName,
          ),
          rawSupplierName: raw(
            YorksV1InventoryControlledField.externalSupplierName,
          ),
          supplierReference: effective(
            YorksV1InventoryControlledField.supplierReference,
          ),
          rawSupplierReference: raw(
            YorksV1InventoryControlledField.supplierReference,
          ),
          receivedDate: _canonicalInventoryDate(
            effective(YorksV1InventoryControlledField.receivedDate),
          ),
          rawReceivedDate: raw(YorksV1InventoryControlledField.receivedDate),
          unitPrice: raw(YorksV1InventoryControlledField.unitPrice).trim(),
          totalPrice: raw(YorksV1InventoryControlledField.totalPrice).trim(),
          rawSourceHeaders: [
            for (final column in mapping.source.columns) column.header,
          ],
          rawSourceWorksheetName: mapping.source.worksheetName,
          rawSourceValues: source,
          appliedCellEdits: [
            for (final edit in mapping.cellEdits)
              if (edit.sourceRowNumber == sourceRowNumber) edit,
          ],
        ),
      );
    }
    if (rows.isEmpty || rows.length > 20000) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    final itemByCode = <String, YorksV1LogisticsInventoryItem>{};
    final itemByIdentity = <String, YorksV1LogisticsInventoryItem>{};
    for (final item in inventoryItems) {
      final code = yorksV1InventorySearchKey(item.itemCode ?? '');
      if (code.isNotEmpty) itemByCode.putIfAbsent(code, () => item);
      itemByIdentity.putIfAbsent(
        _identity(item.description, item.brandOrigin ?? '', item.unit),
        () => item,
      );
    }
    final categoryByKey = <String, YorksV1InventoryCategory>{};
    for (final category in categories) {
      for (final value in [
        category.name,
        category.displayPath,
        ...category.aliases,
      ]) {
        final key = yorksV1InventorySearchKey(value);
        if (key.isNotEmpty) categoryByKey.putIfAbsent(key, () => category);
      }
    }
    final suppliersByKey = <String, List<YorksV1InventorySupplierMaster>>{};
    for (final supplier in suppliers) {
      for (final value in [supplier.name, ...supplier.aliases]) {
        final key = yorksV1InventorySearchKey(value);
        if (key.isEmpty) continue;
        final matches = suppliersByKey.putIfAbsent(key, () => []);
        if (!matches.any((candidate) => candidate.id == supplier.id)) {
          matches.add(supplier);
        }
      }
    }
    final categorySuggestionCache =
        <String, List<YorksV1InventoryCategorySuggestion>>{};
    final supplierSuggestionCache =
        <String, List<YorksV1InventorySupplierSuggestion>>{};
    final identityCounts = <String, int>{};
    final serialCounts = <String, int>{};
    final receiptLineCounts = <String, int>{};
    for (final row in rows) {
      final identity = _identity(row.description, row.brandOrigin, row.unit);
      identityCounts[identity] = (identityCounts[identity] ?? 0) + 1;
      final serial = yorksV1InventorySearchKey(row.serialNumber);
      if (serial.isNotEmpty) {
        serialCounts[serial] = (serialCounts[serial] ?? 0) + 1;
      }
      final receiptLine = _receiptLineIdentity(row);
      receiptLineCounts[receiptLine] =
          (receiptLineCounts[receiptLine] ?? 0) + 1;
    }
    return YorksV1InventoryImportPreview(
      fileName: mapping.source.fileName,
      fileSha256: mapping.source.fileSha256,
      mapping: mapping,
      rows: [
        for (final row in rows)
          _validate(
            row,
            categories: categories,
            itemByCode: itemByCode,
            itemByIdentity: itemByIdentity,
            categoryByKey: categoryByKey,
            categorySuggestionCache: categorySuggestionCache,
            suppliers: suppliers,
            suppliersByKey: suppliersByKey,
            supplierSuggestionCache: supplierSuggestionCache,
            hasR38_9SourceType:
                mapping.requiresR38_9Fields ||
                mapping.treatWorkbookAsOpeningBalance ||
                mapping.indexes.containsKey(
                  YorksV1InventoryControlledField.sourceType,
                ),
            duplicateSerial:
                (serialCounts[yorksV1InventorySearchKey(row.serialNumber)] ??
                    0) >
                1,
            duplicateReceiptLine:
                (receiptLineCounts[_receiptLineIdentity(row)] ?? 0) > 1,
            duplicateIdentity:
                (identityCounts[_identity(
                      row.description,
                      row.brandOrigin,
                      row.unit,
                    )] ??
                    0) >
                1,
          ),
      ],
    );
  }

  YorksV1InventoryImportPreview applyCategoryDecision({
    required YorksV1InventoryImportPreview preview,
    required String sourceCategory,
    String? categoryId,
    bool createNew = false,
  }) {
    final key = yorksV1InventorySearchKey(sourceCategory);
    final selectedName = createNew
        ? yorksV1InventoryCategoryDisplayName(sourceCategory)
        : null;
    return preview.copyWithRows([
      for (final row in preview.rows)
        if (row.categorySourceKey != key)
          row
        else
          row.copyWith(
            categoryId: categoryId,
            newCategoryName: selectedName,
            clearCategoryId: createNew,
            clearNewCategoryName: !createNew,
            issues: [
              for (final issue in row.issues)
                if (issue.code !=
                        YorksV1InventoryImportIssueCode
                            .categoryDecisionRequired &&
                    issue.code != YorksV1InventoryImportIssueCode.newCategory &&
                    issue.code != YorksV1InventoryImportIssueCode.aliasMapping)
                  issue,
              if (createNew)
                YorksV1InventoryImportIssue(
                  code: YorksV1InventoryImportIssueCode.newCategory,
                  detail: selectedName,
                  isWarning: true,
                )
              else
                const YorksV1InventoryImportIssue(
                  code: YorksV1InventoryImportIssueCode.aliasMapping,
                  isWarning: true,
                ),
            ],
          ),
    ]);
  }

  YorksV1InventoryImportPreview applySupplierDecision({
    required YorksV1InventoryImportPreview preview,
    required String sourceSupplierText,
    String? supplierId,
    String? canonicalSupplierName,
    bool createNew = false,
    bool useUnknownSupplier = false,
  }) {
    final key = yorksV1InventorySearchKey(sourceSupplierText);
    if (key.isEmpty && !useUnknownSupplier) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    final existingSelected =
        !createNew &&
        !useUnknownSupplier &&
        supplierId?.trim().isNotEmpty == true &&
        canonicalSupplierName?.trim().isNotEmpty == true;
    if (!existingSelected && !createNew && !useUnknownSupplier) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    final resolvedName = useUnknownSupplier
        ? yorksV1UnknownSupplierName
        : createNew
        ? sourceSupplierText.trim()
        : canonicalSupplierName!.trim();
    return preview.copyWithRows([
      for (final row in preview.rows)
        if (row.supplierSourceKey != key)
          row
        else
          row.copyWith(
            supplierId: useUnknownSupplier
                ? yorksV1UnknownSupplierId
                : supplierId,
            canonicalSupplierName: createNew ? null : resolvedName,
            newSupplierName: createNew ? resolvedName : null,
            clearSupplierId: createNew,
            clearCanonicalSupplierName: createNew,
            clearNewSupplierName: !createNew,
            supplierResolution: useUnknownSupplier
                ? YorksV1InventorySupplierResolution.unknownSupplier
                : createNew
                ? YorksV1InventorySupplierResolution.createNew
                : YorksV1InventorySupplierResolution.existing,
            requiresSupplierDecision: false,
            issues: [
              for (final issue in row.issues)
                if (!_supplierDecisionIssueCodes.contains(issue.code)) issue,
              YorksV1InventoryImportIssue(
                code: useUnknownSupplier
                    ? YorksV1InventoryImportIssueCode.supplierMissingUsesUnknown
                    : createNew
                    ? YorksV1InventoryImportIssueCode.newSupplier
                    : YorksV1InventoryImportIssueCode.supplierAliasMapping,
                detail: resolvedName,
                isWarning: true,
              ),
            ],
          ),
    ]);
  }

  YorksV1InventoryImportPreview applyReceiptQuantities({
    required YorksV1InventoryImportPreview preview,
    required int sourceRowNumber,
    required String accepted,
    required String damaged,
    required String rejected,
  }) {
    return preview.copyWithRows([
      for (final row in preview.rows)
        if (row.sourceRowNumber != sourceRowNumber)
          row
        else
          _withReceiptQuantities(
            row,
            accepted: accepted,
            damaged: damaged,
            rejected: rejected,
          ),
    ]);
  }

  YorksV1InventoryImportRow _withReceiptQuantities(
    YorksV1InventoryImportRow row, {
    required String accepted,
    required String damaged,
    required String rejected,
  }) {
    final issues = [
      for (final issue in row.issues)
        if (issue.code !=
                YorksV1InventoryImportIssueCode.receiptQuantityInvalid &&
            issue.code !=
                YorksV1InventoryImportIssueCode.receiptQuantityMismatch)
          issue,
    ];
    final acceptedValue = _parseDecimal(accepted);
    final damagedValue = _parseDecimal(damaged);
    final rejectedValue = _parseDecimal(rejected);
    final deliveredValue = _parseDecimal(row.quantity);
    final isReceipt =
        row.stockAction == YorksV1InventoryStockAction.openingBalance ||
        row.stockAction == YorksV1InventoryStockAction.addStock;
    if (acceptedValue == null ||
        damagedValue == null ||
        rejectedValue == null ||
        acceptedValue < 0 ||
        damagedValue < 0 ||
        rejectedValue < 0) {
      issues.add(
        const YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.receiptQuantityInvalid,
        ),
      );
    } else if (!isReceipt &&
        (acceptedValue != 0 || damagedValue != 0 || rejectedValue != 0)) {
      issues.add(
        const YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.receiptQuantityInvalid,
        ),
      );
    } else if (isReceipt &&
        (deliveredValue == null ||
            ((acceptedValue + damagedValue + rejectedValue) - deliveredValue)
                    .abs() >
                0.000001)) {
      issues.add(
        YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.receiptQuantityMismatch,
          detail: row.quantity,
        ),
      );
    }
    return row.copyWith(
      acceptedQuantity: accepted.trim(),
      damagedQuantity: damaged.trim(),
      rejectedQuantity: rejected.trim(),
      issues: issues,
    );
  }

  static const _supplierDecisionIssueCodes = {
    YorksV1InventoryImportIssueCode.supplierDecisionRequired,
    YorksV1InventoryImportIssueCode.supplierIntegrityConflict,
    YorksV1InventoryImportIssueCode.supplierInactive,
    YorksV1InventoryImportIssueCode.supplierAliasMapping,
    YorksV1InventoryImportIssueCode.newSupplier,
  };

  YorksV1InventoryImportRow _validate(
    _RawInventoryRow row, {
    required List<YorksV1InventoryCategory> categories,
    required Map<String, YorksV1LogisticsInventoryItem> itemByCode,
    required Map<String, YorksV1LogisticsInventoryItem> itemByIdentity,
    required Map<String, YorksV1InventoryCategory> categoryByKey,
    required Map<String, List<YorksV1InventoryCategorySuggestion>>
    categorySuggestionCache,
    required List<YorksV1InventorySupplierMaster> suppliers,
    required Map<String, List<YorksV1InventorySupplierMaster>> suppliersByKey,
    required Map<String, List<YorksV1InventorySupplierSuggestion>>
    supplierSuggestionCache,
    required bool hasR38_9SourceType,
    required bool duplicateSerial,
    required bool duplicateReceiptLine,
    required bool duplicateIdentity,
  }) {
    final issues = <YorksV1InventoryImportIssue>[];
    final action = YorksV1InventoryStockAction.parse(row.action);
    final quantity = _parseDecimal(row.quantity);
    final minimum = row.minimumStock.isEmpty
        ? null
        : _parseDecimal(row.minimumStock);
    final sourceType = YorksV1InventorySourceType.parse(row.sourceType);
    final unitPrice = row.unitPrice.isEmpty
        ? null
        : _parseDecimal(row.unitPrice);
    final importedTotal = row.totalPrice.isEmpty
        ? null
        : _parseDecimal(row.totalPrice);
    final calculatedTotal = unitPrice == null || quantity == null
        ? null
        : unitPrice * quantity;
    final unit = _canonicalUnit(row.unit);
    final itemCodeKey = yorksV1InventorySearchKey(row.itemCode);
    final item = itemCodeKey.isNotEmpty
        ? itemByCode[itemCodeKey]
        : itemByIdentity[_identity(row.description, row.brandOrigin, row.unit)];
    if (row.sourceTypeWasDefaulted) {
      issues.add(
        const YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode
              .sourceTypeDefaultedToOpeningBalance,
          isWarning: true,
        ),
      );
    }
    if (row.stockActionWasNormalized) {
      issues.add(
        const YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode
              .stockActionNormalizedToOpeningBalance,
          isWarning: true,
        ),
      );
    }
    if (row.unitWasMapped) {
      issues.add(
        YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.unitMapped,
          detail: '${row.rawUnit} -> ${row.unit}',
          isWarning: true,
        ),
      );
    }
    if (row.appliedCellEdits.isNotEmpty) {
      issues.add(
        YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.reviewEditApplied,
          detail: row.appliedCellEdits
              .map((edit) => edit.field.name)
              .join(', '),
          isWarning: true,
        ),
      );
    }
    final expectedSourceType = _sourceTypeForStockAction(action);
    if (hasR38_9SourceType &&
        (sourceType == null || sourceType != expectedSourceType)) {
      issues.add(
        const YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.sourceTypeInvalid,
        ),
      );
    }
    if (hasR38_9SourceType &&
        expectedSourceType != null &&
        sourceType != expectedSourceType) {
      issues.add(
        const YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.sourceActionMismatch,
        ),
      );
    }
    if (row.description.isEmpty) {
      issues.add(
        const YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.descriptionRequired,
        ),
      );
    }
    if (row.unit.isEmpty) {
      issues.add(
        const YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.unitRequired,
        ),
      );
    } else if (unit == null) {
      issues.add(
        const YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.unitNotAllowed,
        ),
      );
    }
    if (action == null) {
      issues.add(
        const YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.stockActionInvalid,
        ),
      );
    }
    if (quantity == null || quantity < 0) {
      issues.add(
        const YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.quantityInvalid,
        ),
      );
    } else if (action != null &&
        action != YorksV1InventoryStockAction.noStockChange &&
        quantity <= 0) {
      issues.add(
        const YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.quantityMustBePositive,
        ),
      );
    } else if (action == YorksV1InventoryStockAction.noStockChange &&
        quantity != 0) {
      issues.add(
        const YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.noStockChangeQuantityIgnored,
          isWarning: true,
        ),
      );
    }
    final requiresUserReason =
        action == YorksV1InventoryStockAction.removeStock ||
        action == YorksV1InventoryStockAction.correctionIncrease ||
        action == YorksV1InventoryStockAction.correctionDecrease;
    if (requiresUserReason && row.reason.isEmpty) {
      issues.add(
        const YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.reasonRequired,
        ),
      );
    }
    if (row.minimumStock.isNotEmpty && (minimum == null || minimum < 0)) {
      issues.add(
        const YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.minimumStockInvalid,
        ),
      );
    }
    if (duplicateSerial && row.serialNumber.isNotEmpty) {
      issues.add(
        const YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.duplicateSerialNumber,
        ),
      );
    }
    if (duplicateReceiptLine) {
      issues.add(
        const YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.duplicateReceiptLine,
        ),
      );
    }
    if (duplicateIdentity && row.itemCode.isEmpty) {
      issues.add(
        const YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.duplicateIdentity,
          isWarning: true,
        ),
      );
    }
    if ((action == YorksV1InventoryStockAction.removeStock ||
            action == YorksV1InventoryStockAction.correctionIncrease ||
            action == YorksV1InventoryStockAction.correctionDecrease) &&
        item == null) {
      issues.add(
        const YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.removeRequiresExistingItem,
        ),
      );
    }
    if ((action == YorksV1InventoryStockAction.removeStock ||
            action == YorksV1InventoryStockAction.correctionDecrease) &&
        item != null &&
        quantity != null &&
        quantity > (double.tryParse(item.availableQuantity) ?? 0)) {
      issues.add(
        YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.removeExceedsAvailable,
          detail: item.availableQuantity,
        ),
      );
    }
    if (action == YorksV1InventoryStockAction.openingBalance &&
        item != null &&
        (double.tryParse(item.onHandQuantity) ?? 0) > 0) {
      issues.add(
        const YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.openingBalanceConflict,
        ),
      );
    }
    if (item != null &&
        unit != null &&
        yorksV1InventorySearchKey(item.unit) !=
            yorksV1InventorySearchKey(unit)) {
      issues.add(
        YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.unitMismatch,
          detail: item.unit,
        ),
      );
    }

    if (row.unitPrice.isNotEmpty && (unitPrice == null || unitPrice < 0)) {
      issues.add(
        const YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.unitPriceInvalid,
        ),
      );
    }
    if (row.totalPrice.isNotEmpty && importedTotal == null) {
      issues.add(
        const YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.totalPriceMismatch,
          isWarning: true,
        ),
      );
    } else if (importedTotal != null &&
        calculatedTotal != null &&
        (importedTotal - calculatedTotal).abs() > 0.005) {
      issues.add(
        YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.totalPriceMismatch,
          detail: _decimalText(calculatedTotal),
          isWarning: true,
        ),
      );
    }
    final trackingMode = row.serialNumber.trim().isEmpty
        ? 'bulk'
        : 'serialized';
    if (trackingMode == 'serialized' &&
        (quantity == null ||
            quantity != 1 ||
            (action != YorksV1InventoryStockAction.openingBalance &&
                action != YorksV1InventoryStockAction.addStock))) {
      issues.add(
        const YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.trackingModeInvalid,
        ),
      );
    }

    String? supplierId;
    String? canonicalSupplierName;
    String? newSupplierName;
    YorksV1InventorySupplierResolution? supplierResolution;
    var requiresSupplierDecision = false;
    List<YorksV1InventorySupplierSuggestion> supplierSuggestions = const [];
    if (hasR38_9SourceType &&
        (action == YorksV1InventoryStockAction.openingBalance ||
            action == YorksV1InventoryStockAction.addStock)) {
      final sourceSupplier = row.supplierName.trim();
      if (yorksV1InventoryIsUnknownSupplierText(sourceSupplier)) {
        supplierId = yorksV1UnknownSupplierId;
        canonicalSupplierName = yorksV1UnknownSupplierName;
        supplierResolution = YorksV1InventorySupplierResolution.unknownSupplier;
        issues.add(
          const YorksV1InventoryImportIssue(
            code: YorksV1InventoryImportIssueCode.supplierMissingUsesUnknown,
            detail: yorksV1UnknownSupplierName,
            isWarning: true,
          ),
        );
      } else if (sourceType == YorksV1InventorySourceType.externalSupplier) {
        final supplierKey = yorksV1InventorySearchKey(sourceSupplier);
        final exact = suppliersByKey[supplierKey] ?? const [];
        if (exact.length > 1) {
          issues.add(
            const YorksV1InventoryImportIssue(
              code: YorksV1InventoryImportIssueCode.supplierIntegrityConflict,
            ),
          );
        } else if (exact.length == 1) {
          final supplier = exact.single;
          supplierId = supplier.id;
          canonicalSupplierName = supplier.name;
          supplierResolution = YorksV1InventorySupplierResolution.existing;
          if (!supplier.isActive) {
            issues.add(
              const YorksV1InventoryImportIssue(
                code: YorksV1InventoryImportIssueCode.supplierInactive,
              ),
            );
          } else if (yorksV1InventorySearchKey(sourceSupplier) !=
              yorksV1InventorySearchKey(supplier.name)) {
            issues.add(
              YorksV1InventoryImportIssue(
                code: YorksV1InventoryImportIssueCode.supplierAliasMapping,
                detail: supplier.name,
                isWarning: true,
              ),
            );
          }
        } else {
          requiresSupplierDecision = true;
          supplierSuggestions = supplierSuggestionCache.putIfAbsent(
            supplierKey,
            () => supplierMatcher.rank(sourceSupplier, suppliers),
          );
          issues.add(
            const YorksV1InventoryImportIssue(
              code: YorksV1InventoryImportIssueCode.supplierDecisionRequired,
            ),
          );
        }
      } else {
        issues.add(
          const YorksV1InventoryImportIssue(
            code: YorksV1InventoryImportIssueCode.supplierUnexpectedForSource,
            isWarning: true,
          ),
        );
      }

      if (sourceType == YorksV1InventorySourceType.externalSupplier) {
        if (row.supplierReference.trim().isEmpty) {
          issues.add(
            const YorksV1InventoryImportIssue(
              code: YorksV1InventoryImportIssueCode.supplierReferenceRequired,
            ),
          );
        }
        if (row.receivedDate.trim().isEmpty) {
          issues.add(
            const YorksV1InventoryImportIssue(
              code: YorksV1InventoryImportIssueCode.receivedDateRequired,
            ),
          );
        } else if (!_isUnambiguousDate(row.receivedDate.trim())) {
          issues.add(
            const YorksV1InventoryImportIssue(
              code: YorksV1InventoryImportIssueCode.receivedDateInvalid,
            ),
          );
        }
      } else if (row.receivedDate.trim().isNotEmpty &&
          !_isUnambiguousDate(row.receivedDate.trim())) {
        issues.add(
          const YorksV1InventoryImportIssue(
            code: YorksV1InventoryImportIssueCode.receivedDateInvalid,
          ),
        );
      }
    }

    String? categoryId;
    String? newCategoryName;
    var requiresCategoryDecision = false;
    List<YorksV1InventoryCategorySuggestion> suggestions = const [];
    if (row.sourceCategory.isEmpty) {
      categoryId = item?.categoryId;
      if (categoryId == null) {
        issues.add(
          const YorksV1InventoryImportIssue(
            code: YorksV1InventoryImportIssueCode.categoryRequired,
          ),
        );
      }
    } else if (categoryByKey[yorksV1InventorySearchKey(row.sourceCategory)]
        case final exact?) {
      categoryId = exact.id;
      if (yorksV1InventorySearchKey(row.sourceCategory) !=
          yorksV1InventorySearchKey(exact.name)) {
        issues.add(
          YorksV1InventoryImportIssue(
            code: YorksV1InventoryImportIssueCode.aliasMapping,
            detail: exact.name,
            isWarning: true,
          ),
        );
      }
    } else {
      requiresCategoryDecision = true;
      final categoryKey = yorksV1InventorySearchKey(row.sourceCategory);
      suggestions = categorySuggestionCache.putIfAbsent(
        categoryKey,
        () => matcher.rank(row.sourceCategory, categories),
      );
      // A non-exact category must never be silently promoted to a master.
      // Show both the existing-category and new-parent choices even when no
      // fuzzy suggestion was found; Procurement must explicitly choose one.
      issues.add(
        const YorksV1InventoryImportIssue(
          code: YorksV1InventoryImportIssueCode.categoryDecisionRequired,
        ),
      );
    }
    return YorksV1InventoryImportRow(
      sourceRowNumber: row.sourceRowNumber,
      itemCode: row.itemCode,
      description: row.description,
      sourceCategory: row.sourceCategory,
      brandOrigin: row.brandOrigin,
      unit: unit ?? row.unit,
      stockAction: action,
      quantity: row.quantity,
      reason: row.reason,
      minimumStock: row.minimumStock,
      locationBin: row.locationBin,
      notes: row.notes,
      sizeText: row.sizeText,
      modelTag: row.modelTag,
      serialNumber: row.serialNumber,
      ralColour: row.ralColour,
      rawSourceType: row.sourceType,
      sourceTypeWasDefaulted: row.sourceTypeWasDefaulted,
      stockActionWasNormalized: row.stockActionWasNormalized,
      sourceType: sourceType,
      rawUnit: row.rawUnit,
      unitWasMapped: row.unitWasMapped,
      rawSupplierName: row.rawSupplierName,
      rawSupplierReference: row.rawSupplierReference,
      rawReceivedDate: row.rawReceivedDate,
      editedSupplierName: row.supplierName == row.rawSupplierName
          ? null
          : row.supplierName,
      editedSupplierReference: row.supplierReference == row.rawSupplierReference
          ? null
          : row.supplierReference,
      editedReceivedDate: row.receivedDate == row.rawReceivedDate
          ? null
          : row.receivedDate,
      supplierId: supplierId,
      canonicalSupplierName: canonicalSupplierName,
      newSupplierName: newSupplierName,
      supplierResolution: supplierResolution,
      requiresSupplierDecision: requiresSupplierDecision,
      supplierSuggestions: supplierSuggestions,
      unitPrice: row.unitPrice,
      importedTotalPrice: row.totalPrice,
      calculatedTotalPrice: _decimalText(calculatedTotal),
      acceptedQuantity:
          action == YorksV1InventoryStockAction.openingBalance ||
              action == YorksV1InventoryStockAction.addStock
          ? row.quantity
          : '0',
      damagedQuantity: '0',
      rejectedQuantity: '0',
      trackingMode: trackingMode,
      rawSourceWorksheetName: row.rawSourceWorksheetName,
      rawSourceHeaders: row.rawSourceHeaders,
      rawSourceValues: row.rawSourceValues,
      appliedCellEdits: row.appliedCellEdits,
      inventoryItemId: item?.id,
      categoryId: categoryId,
      newCategoryName: newCategoryName,
      requiresCategoryDecision: requiresCategoryDecision,
      suggestions: suggestions,
      issues: issues,
    );
  }

  static String _identity(String description, String brand, String unit) =>
      '${yorksV1InventorySearchKey(description)}|'
      '${yorksV1InventorySearchKey(brand)}|'
      '${yorksV1InventorySearchKey(unit)}';

  static YorksV1InventorySourceType? _sourceTypeForStockAction(
    YorksV1InventoryStockAction? action,
  ) => switch (action) {
    YorksV1InventoryStockAction.openingBalance =>
      YorksV1InventorySourceType.openingBalance,
    YorksV1InventoryStockAction.addStock =>
      YorksV1InventorySourceType.externalSupplier,
    YorksV1InventoryStockAction.removeStock ||
    YorksV1InventoryStockAction.correctionIncrease ||
    YorksV1InventoryStockAction.correctionDecrease =>
      YorksV1InventorySourceType.correction,
    YorksV1InventoryStockAction.noStockChange =>
      YorksV1InventorySourceType.noStockChange,
    null => null,
  };

  static String _receiptLineIdentity(_RawInventoryRow row) => [
    yorksV1InventorySearchKey(row.itemCode).isNotEmpty
        ? yorksV1InventorySearchKey(row.itemCode)
        : _identity(row.description, row.brandOrigin, row.unit),
    yorksV1InventorySearchKey(row.sourceType),
    yorksV1InventorySearchKey(row.action),
    yorksV1InventorySearchKey(row.supplierName),
    yorksV1InventorySearchKey(row.supplierReference),
    row.receivedDate.trim(),
    yorksV1InventorySearchKey(row.locationBin),
    yorksV1InventorySearchKey(row.serialNumber),
    row.quantity.trim(),
    yorksV1InventorySearchKey(row.unit),
  ].join('|');

  static double? _parseDecimal(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final normalized =
        RegExp(r'^-?\d{1,3}(?:,\d{3})+(?:\.\d+)?$').hasMatch(trimmed)
        ? trimmed.replaceAll(',', '')
        : trimmed;
    if (!RegExp(r'^-?\d+(?:\.\d+)?$').hasMatch(normalized)) return null;
    return double.tryParse(normalized);
  }

  static String? _decimalText(double? value) {
    if (value == null || !value.isFinite) return null;
    return value.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static bool _isUnambiguousDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}(?:[T ]|$)').hasMatch(value)) {
      return false;
    }
    return DateTime.tryParse(value) != null;
  }

  static String _canonicalInventoryDate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || _isUnambiguousDate(trimmed)) return trimmed;
    final serial = _parseDecimal(trimmed);
    if (serial == null || serial < 1 || serial >= 2958466) return trimmed;
    final wholeDays = serial.floor();
    final date = DateTime.utc(1899, 12, 30).add(Duration(days: wholeDays));
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static String? _canonicalUnit(String value) =>
      yorksV1InventoryCanonicalUnit(value);

  static int _findHeaderRow(List<List<String>> matrix) {
    var bestIndex = -1;
    var bestScore = 0;
    final scanCount = math.min(30, matrix.length);
    for (var rowIndex = 0; rowIndex < scanCount; rowIndex++) {
      final recognized = <YorksV1InventoryControlledField>{};
      for (final header in matrix[rowIndex]) {
        for (final field in YorksV1InventoryControlledField.values) {
          if (field.recognizesHeader(header)) recognized.add(field);
        }
      }
      if (recognized.length > bestScore) {
        bestScore = recognized.length;
        bestIndex = rowIndex;
      }
    }
    if (bestIndex < 0 || bestScore < 4) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    return bestIndex;
  }

  static ({
    List<List<String>> matrix,
    String? worksheetName,
    List<String> worksheetNames,
  })
  _decodeXlsx(YorksV1InventorySelectedWorkbook workbook) {
    final parsed = _decodeInventoryXlsx(workbook);
    final names = [for (final sheet in parsed.sheets) sheet.name];
    final selectedName = workbook.worksheetName?.trim();
    if (selectedName != null && selectedName.isNotEmpty) {
      for (final sheet in parsed.sheets) {
        if (sheet.name == selectedName) {
          return (
            matrix: sheet.rows,
            worksheetName: sheet.name,
            worksheetNames: names,
          );
        }
      }
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    for (final sheet in parsed.sheets) {
      if (yorksV1InventorySearchKey(sheet.name) == 'inventoryimport') {
        return (
          matrix: sheet.rows,
          worksheetName: sheet.name,
          worksheetNames: names,
        );
      }
    }
    if (parsed.sheets.length == 1) {
      final sheet = parsed.sheets.single;
      return (
        matrix: sheet.rows,
        worksheetName: sheet.name,
        worksheetNames: names,
      );
    }
    // Never silently select the first sheet of an ambiguous workbook. The
    // controlled pack uses the explicit "Inventory Import" worksheet.
    throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
  }

  static YorksV1BoqParsedWorkbook _decodeInventoryXlsx(
    YorksV1InventorySelectedWorkbook workbook,
  ) => const YorksV1BoqWorkbookCodec().decode(
    bytes: workbook.bytes,
    fileName: workbook.fileName,
    maxWorkbookBytes: 25 * 1024 * 1024,
    // The controlled limit applies to data rows. Preserve space for a title,
    // instructions and the scanned header without weakening BOQ limits.
    maxRowsPerSheet: 20032,
  );

  static void _validateSelectedWorkbook(
    YorksV1InventorySelectedWorkbook workbook,
  ) {
    if (workbook.bytes.isEmpty ||
        workbook.bytes.lengthInBytes > 25 * 1024 * 1024) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    final lowerName = workbook.fileName.toLowerCase();
    if (!lowerName.endsWith('.csv') && !lowerName.endsWith('.xlsx')) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
  }

  static List<List<String>> _decodeCsv(Uint8List bytes) {
    final text = utf8
        .decode(bytes, allowMalformed: false)
        .replaceFirst('\ufeff', '');
    final rows = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var quoted = false;
    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if (quoted) {
        if (char == '"') {
          if (index + 1 < text.length && text[index + 1] == '"') {
            field.write('"');
            index++;
          } else {
            quoted = false;
          }
        } else {
          field.write(char);
        }
      } else if (char == '"' && field.isEmpty) {
        quoted = true;
      } else if (char == ',') {
        row.add(field.toString());
        field = StringBuffer();
      } else if (char == '\n' || char == '\r') {
        if (char == '\r' &&
            index + 1 < text.length &&
            text[index + 1] == '\n') {
          index++;
        }
        row.add(field.toString());
        field = StringBuffer();
        rows.add(row);
        row = <String>[];
      } else {
        field.write(char);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows;
  }
}

class _RawInventoryRow {
  const _RawInventoryRow({
    required this.sourceRowNumber,
    required this.itemCode,
    required this.description,
    required this.sourceCategory,
    required this.brandOrigin,
    required this.unit,
    required this.rawUnit,
    required this.unitWasMapped,
    required this.action,
    required this.stockActionWasNormalized,
    required this.quantity,
    required this.reason,
    required this.minimumStock,
    required this.locationBin,
    required this.notes,
    required this.sizeText,
    required this.modelTag,
    required this.serialNumber,
    required this.ralColour,
    required this.sourceType,
    required this.sourceTypeWasDefaulted,
    required this.supplierName,
    required this.rawSupplierName,
    required this.supplierReference,
    required this.rawSupplierReference,
    required this.receivedDate,
    required this.rawReceivedDate,
    required this.unitPrice,
    required this.totalPrice,
    required this.rawSourceWorksheetName,
    required this.rawSourceHeaders,
    required this.rawSourceValues,
    required this.appliedCellEdits,
  });

  final int sourceRowNumber;
  final String itemCode;
  final String description;
  final String sourceCategory;
  final String brandOrigin;
  final String unit;
  final String rawUnit;
  final bool unitWasMapped;
  final String action;
  final bool stockActionWasNormalized;
  final String quantity;
  final String reason;
  final String minimumStock;
  final String locationBin;
  final String notes;
  final String sizeText;
  final String modelTag;
  final String serialNumber;
  final String ralColour;
  final String sourceType;
  final bool sourceTypeWasDefaulted;
  final String supplierName;
  final String rawSupplierName;
  final String supplierReference;
  final String rawSupplierReference;
  final String receivedDate;
  final String rawReceivedDate;
  final String unitPrice;
  final String totalPrice;
  final String? rawSourceWorksheetName;
  final List<String> rawSourceHeaders;
  final List<String> rawSourceValues;
  final List<YorksV1InventoryCellEdit> appliedCellEdits;
}

class _InventoryImportExportSheet {
  const _InventoryImportExportSheet({
    required this.name,
    required this.title,
    required this.subtitle,
    required this.headings,
    required this.rows,
    required this.emptyMessage,
  });

  final String name;
  final String title;
  final String subtitle;
  final List<String> headings;
  final List<List<String>> rows;
  final String emptyMessage;
}

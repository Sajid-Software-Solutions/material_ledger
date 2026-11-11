import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/yorks_v1_material_summary_strings.dart';
import '../models/yorks_v1_project_material_summary.dart';
import '../models/yorks_v1_quantity.dart';
import 'yorks_v1_logistics_document_service.dart';

/// Context printed on every Material Summary export so a saved file always
/// says which project and which filters produced it.
class YorksV1MaterialSummaryExportContext {
  const YorksV1MaterialSummaryExportContext({
    required this.projectReference,
    required this.projectName,
    required this.buildingLabel,
    required this.periodLabel,
    required this.generatedAt,
    this.search,
  });

  final String projectReference;
  final String projectName;
  final String buildingLabel;
  final String periodLabel;
  final String? search;
  final DateTime generatedAt;

  String get filterLine => [
    '${YorksV1MaterialSummaryStrings.building.primary}: $buildingLabel',
    '${YorksV1MaterialSummaryStrings.period.primary}: $periodLabel',
    if (search != null && search!.trim().isNotEmpty)
      '${YorksV1MaterialSummaryStrings.search.primary}: "${search!.trim()}"',
  ].join('   ·   ');
}

/// `November 2026` or `Mon 26 Oct – Sun 1 Nov 2026`.
String yorksV1MaterialSummaryPeriodLabel(YorksV1MaterialSummaryPeriod period) {
  switch (period.granularity) {
    case YorksV1MaterialSummaryGranularity.month:
      return DateFormat('MMMM yyyy').format(period.start);
    case YorksV1MaterialSummaryGranularity.week:
      final end = period.end;
      final startFormat = period.start.year == end.year
          ? DateFormat('EEE d MMM')
          : DateFormat('EEE d MMM yyyy');
      return '${startFormat.format(period.start)} – '
          '${DateFormat('EEE d MMM yyyy').format(end)}';
  }
}

String yorksV1MaterialSummaryDate(DateTime date) =>
    DateFormat('dd/MM/yyyy').format(date);

/// Whole-number percentage, or an em dash when the ratio is undefined.
String yorksV1MaterialSummaryPercent(double? ratio) {
  if (ratio == null || ratio.isNaN || ratio.isInfinite) return '—';
  final percent = ratio * 100;
  if (percent > 0 && percent < 1) return '<1%';
  return '${percent.round()}%';
}

String yorksV1MaterialSummaryQuantity(String value) =>
    yorksV1DisplayQuantity(value);

/// Builds operational-only Excel and PDF exports of the filtered Material
/// Summary. The typed summary contains no commercial field, so none can leak.
class YorksV1MaterialSummaryDocumentService {
  const YorksV1MaterialSummaryDocumentService();

  static const _xlsxMime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  String get excelMimeType => _xlsxMime;

  String suggestedFileName(
    YorksV1MaterialSummaryExportContext context,
    String extension,
  ) {
    final stamp = DateFormat('yyyyMMdd').format(context.generatedAt.toLocal());
    final reference = context.projectReference.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]+'),
      '_',
    );
    return '${reference.isEmpty ? 'project' : reference}'
        '_material_summary_$stamp.$extension';
  }

  // ─── Excel ────────────────────────────────────────────────────────────

  Uint8List buildExcel(
    YorksV1ProjectMaterialSummary summary,
    YorksV1MaterialSummaryExportContext context,
  ) {
    final sheets = [
      _overallSheet(summary, context),
      _periodSheet(
        summary,
        context,
        YorksV1MaterialSummaryStrings.monthly.primary,
        YorksV1MaterialSummaryStrings.month.primary,
        summary.months,
      ),
      _periodSheet(
        summary,
        context,
        YorksV1MaterialSummaryStrings.weekly.primary,
        '${YorksV1MaterialSummaryStrings.week.primary} (Mon–Sun)',
        summary.weeks,
      ),
    ];
    return _XlsxWriter(sheets).encode();
  }

  _Sheet _overallSheet(
    YorksV1ProjectMaterialSummary summary,
    YorksV1MaterialSummaryExportContext context,
  ) => _Sheet(
    name: YorksV1MaterialSummaryStrings.overall.primary,
    preamble: _preamble(context),
    columns: [
      _Column('No.', 6),
      _Column(YorksV1MaterialSummaryStrings.material.primary, 42),
      _Column(YorksV1MaterialSummaryStrings.itemCode.primary, 16),
      _Column(YorksV1MaterialSummaryStrings.brandOrigin.primary, 20),
      _Column(YorksV1MaterialSummaryStrings.unit.primary, 9),
      _Column(YorksV1MaterialSummaryStrings.requested.primary, 12),
      _Column(YorksV1MaterialSummaryStrings.sent.primary, 12),
      _Column(YorksV1MaterialSummaryStrings.returned.primary, 12),
      _Column(YorksV1MaterialSummaryStrings.sentOfRequested.primary, 14),
      _Column(YorksV1MaterialSummaryStrings.materialRequests.primary, 40),
      _Column(YorksV1MaterialSummaryStrings.firstRequested.primary, 14),
      _Column(YorksV1MaterialSummaryStrings.lastRequested.primary, 14),
    ],
    rows: [
      for (final item in summary.items)
        [
          _Cell.number('${item.index + 1}'),
          _Cell.text(item.description),
          _Cell.text(item.itemCodes.join(', ')),
          _Cell.text(item.brandOrigins.join(', ')),
          _Cell.text(item.unit),
          _Cell.number(item.requested),
          _Cell.number(item.sent),
          _Cell.number(item.returned),
          _Cell.percent(item.sentOfRequested),
          _Cell.text(_requestNumbers(summary, item.requestRefs)),
          _Cell.text(yorksV1MaterialSummaryDate(item.firstRequestedOn)),
          _Cell.text(yorksV1MaterialSummaryDate(item.lastRequestedOn)),
        ],
    ],
  );

  _Sheet _periodSheet(
    YorksV1ProjectMaterialSummary summary,
    YorksV1MaterialSummaryExportContext context,
    String name,
    String periodHeading,
    List<YorksV1MaterialSummaryPeriod> periods,
  ) => _Sheet(
    name: name,
    preamble: _preamble(context),
    columns: [
      _Column(periodHeading, 30),
      _Column(YorksV1MaterialSummaryStrings.material.primary, 42),
      _Column(YorksV1MaterialSummaryStrings.itemCode.primary, 16),
      _Column(YorksV1MaterialSummaryStrings.unit.primary, 9),
      _Column(YorksV1MaterialSummaryStrings.requested.primary, 12),
      _Column(YorksV1MaterialSummaryStrings.sent.primary, 12),
      _Column(YorksV1MaterialSummaryStrings.returned.primary, 12),
      _Column(YorksV1MaterialSummaryStrings.shareOfItem.primary, 16),
      _Column(YorksV1MaterialSummaryStrings.sentOfRequested.primary, 14),
      _Column(YorksV1MaterialSummaryStrings.materialRequests.primary, 40),
    ],
    rows: [
      for (final period in periods)
        for (final line in period.lines)
          if (summary.item(line.itemIndex) case final item?)
            [
              _Cell.text(yorksV1MaterialSummaryPeriodLabel(period)),
              _Cell.text(item.description),
              _Cell.text(item.itemCodes.join(', ')),
              _Cell.text(item.unit),
              _Cell.number(line.requested),
              _Cell.number(line.sent),
              _Cell.number(line.returned),
              _Cell.percent(summary.shareOfItem(line)),
              _Cell.percent(line.sentOfRequested),
              _Cell.text(_requestNumbers(summary, line.requestRefs)),
            ],
    ],
  );

  List<String> _preamble(YorksV1MaterialSummaryExportContext context) => [
    '${YorksV1MaterialSummaryStrings.title.primary} — '
        '${context.projectReference} · ${context.projectName}',
    context.filterLine,
    '${YorksV1MaterialSummaryStrings.dateBasis.primary} '
        '${YorksV1MaterialSummaryStrings.generated.primary}: '
        '${DateFormat('dd/MM/yyyy HH:mm').format(context.generatedAt.toLocal())}',
  ];

  static String _requestNumbers(
    YorksV1ProjectMaterialSummary summary,
    Iterable<int> refs,
  ) => summary.requestsFor(refs).map((request) => request.number).join(', ');

  // ─── PDF ──────────────────────────────────────────────────────────────

  Future<Uint8List> buildPdf(
    YorksV1ProjectMaterialSummary summary,
    YorksV1MaterialSummaryExportContext context, {
    PdfPageFormat? format,
  }) async {
    final theme =
        await YorksV1LogisticsDocumentService.controlledDocumentTheme();
    final logo = await YorksV1LogisticsDocumentService.controlledDocumentLogo();
    final pageFormat = format ?? PdfPageFormat.a4.landscape;
    final document = pw.Document(
      theme: theme,
      title:
          '${context.projectReference} - ${YorksV1MaterialSummaryStrings.title.primary}',
      author: 'Yorks Project Management',
      creator: 'Yorks Project Management',
    );
    final generated = DateFormat(
      'dd/MM/yyyy HH:mm',
    ).format(context.generatedAt.toLocal());

    document.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        maxPages: 1000,
        margin: pw.EdgeInsets.fromLTRB(
          10 * PdfPageFormat.mm,
          9 * PdfPageFormat.mm,
          10 * PdfPageFormat.mm,
          8 * PdfPageFormat.mm,
        ),
        header: (pageContext) => pageContext.pageNumber == 1
            ? pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  YorksV1LogisticsDocumentService.controlledDocumentCompanyHeader(
                    logo,
                  ),
                  pw.SizedBox(height: 3 * PdfPageFormat.mm),
                  pw.Center(
                    child: pw.Text(
                      YorksV1MaterialSummaryStrings.title.primary.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 2.5 * PdfPageFormat.mm),
                  _pdfMeta(
                    YorksV1MaterialSummaryStrings.project.primary,
                    '${context.projectReference} · ${context.projectName}',
                  ),
                  _pdfMeta(
                    YorksV1MaterialSummaryStrings.building.primary,
                    context.buildingLabel,
                  ),
                  _pdfMeta(
                    YorksV1MaterialSummaryStrings.period.primary,
                    context.periodLabel,
                  ),
                  if (context.search != null &&
                      context.search!.trim().isNotEmpty)
                    _pdfMeta(
                      YorksV1MaterialSummaryStrings.search.primary,
                      '"${context.search!.trim()}"',
                    ),
                  _pdfMeta(
                    YorksV1MaterialSummaryStrings.generated.primary,
                    generated,
                  ),
                  pw.SizedBox(height: 1.5 * PdfPageFormat.mm),
                  pw.Text(
                    '${YorksV1MaterialSummaryStrings.dateBasis.primary} '
                    '${YorksV1MaterialSummaryStrings.percentagesNote.primary}',
                    style: pw.TextStyle(fontSize: 6.8, color: _muted),
                  ),
                  pw.SizedBox(height: 3 * PdfPageFormat.mm),
                ],
              )
            : pw.Padding(
                padding: pw.EdgeInsets.only(bottom: 2 * PdfPageFormat.mm),
                child: pw.Text(
                  '${context.projectReference} · '
                  '${YorksV1MaterialSummaryStrings.title.primary}',
                  style: pw.TextStyle(fontSize: 7.5, color: _muted),
                ),
              ),
        footer: (pageContext) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              '${YorksV1MaterialSummaryStrings.generated.primary} $generated',
              style: pw.TextStyle(fontSize: 6.2, color: _muted),
            ),
            pw.Text(
              'Page ${pageContext.pageNumber} of ${pageContext.pagesCount}',
              style: pw.TextStyle(fontSize: 6.2, color: _muted),
            ),
          ],
        ),
        build: (_) => [
          _sectionTitle(
            '${YorksV1MaterialSummaryStrings.overall.primary} · '
            '${summary.items.length} ${YorksV1MaterialSummaryStrings.materials.primary}',
          ),
          if (summary.items.isEmpty)
            _emptyLine()
          else
            _pdfTable(
              headers: [
                'No.',
                YorksV1MaterialSummaryStrings.material.primary,
                YorksV1MaterialSummaryStrings.itemCode.primary,
                YorksV1MaterialSummaryStrings.unit.primary,
                YorksV1MaterialSummaryStrings.requested.primary,
                YorksV1MaterialSummaryStrings.sent.primary,
                YorksV1MaterialSummaryStrings.returned.primary,
                YorksV1MaterialSummaryStrings.sentOfRequested.primary,
                YorksV1MaterialSummaryStrings.materialRequests.primary,
              ],
              widths: const [5, 30, 10, 6, 8, 8, 8, 8, 27],
              numericColumns: const {0, 4, 5, 6, 7},
              rows: [
                for (final item in summary.items)
                  [
                    '${item.index + 1}',
                    [
                      item.description,
                      if (item.brandOrigins.isNotEmpty)
                        item.brandOrigins.join(', '),
                    ].join('\n'),
                    item.itemCodes.join(', '),
                    item.unit,
                    yorksV1MaterialSummaryQuantity(item.requested),
                    yorksV1MaterialSummaryQuantity(item.sent),
                    yorksV1MaterialSummaryQuantity(item.returned),
                    yorksV1MaterialSummaryPercent(item.sentOfRequested),
                    _requestNumbers(summary, item.requestRefs),
                  ],
              ],
            ),
          ..._pdfPeriods(
            summary,
            YorksV1MaterialSummaryStrings.monthly.primary,
            summary.months,
          ),
          ..._pdfPeriods(
            summary,
            '${YorksV1MaterialSummaryStrings.weekly.primary} (Mon–Sun)',
            summary.weeks,
          ),
        ],
      ),
    );
    return document.save(enableEventLoopBalancing: true);
  }

  List<pw.Widget> _pdfPeriods(
    YorksV1ProjectMaterialSummary summary,
    String title,
    List<YorksV1MaterialSummaryPeriod> periods,
  ) => [
    pw.SizedBox(height: 5 * PdfPageFormat.mm),
    _sectionTitle(title),
    if (periods.isEmpty)
      _emptyLine()
    else
      _pdfTable(
        headers: [
          YorksV1MaterialSummaryStrings.period.primary,
          YorksV1MaterialSummaryStrings.material.primary,
          YorksV1MaterialSummaryStrings.unit.primary,
          YorksV1MaterialSummaryStrings.requested.primary,
          YorksV1MaterialSummaryStrings.sent.primary,
          YorksV1MaterialSummaryStrings.returned.primary,
          YorksV1MaterialSummaryStrings.shareOfItem.primary,
          YorksV1MaterialSummaryStrings.sentOfRequested.primary,
          YorksV1MaterialSummaryStrings.materialRequests.primary,
        ],
        widths: const [15, 26, 6, 8, 8, 8, 8, 8, 22],
        numericColumns: const {3, 4, 5, 6, 7},
        rows: [
          for (final period in periods)
            for (var index = 0; index < period.lines.length; index++)
              if (summary.item(period.lines[index].itemIndex) case final item?)
                [
                  index == 0 ? yorksV1MaterialSummaryPeriodLabel(period) : '',
                  item.description,
                  item.unit,
                  yorksV1MaterialSummaryQuantity(period.lines[index].requested),
                  yorksV1MaterialSummaryQuantity(period.lines[index].sent),
                  yorksV1MaterialSummaryQuantity(period.lines[index].returned),
                  yorksV1MaterialSummaryPercent(
                    summary.shareOfItem(period.lines[index]),
                  ),
                  yorksV1MaterialSummaryPercent(
                    period.lines[index].sentOfRequested,
                  ),
                  _requestNumbers(summary, period.lines[index].requestRefs),
                ],
        ],
      ),
  ];

  static final PdfColor _muted = PdfColor.fromHex('#5C6673');
  static final PdfColor _grid = PdfColor.fromHex('#9AA3AE');

  static pw.Widget _sectionTitle(String text) => pw.Padding(
    padding: pw.EdgeInsets.only(bottom: 1.8 * PdfPageFormat.mm),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
    ),
  );

  static pw.Widget _emptyLine() => pw.Text(
    YorksV1MaterialSummaryStrings.emptyFiltered.primary,
    style: pw.TextStyle(fontSize: 8, color: _muted),
  );

  static pw.Widget _pdfMeta(String label, String value) => pw.Padding(
    padding: pw.EdgeInsets.only(bottom: 1 * PdfPageFormat.mm),
    child: pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$label: ',
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          ),
          pw.TextSpan(text: value, style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    ),
  );

  static pw.Widget _pdfTable({
    required List<String> headers,
    required List<List<String>> rows,
    required List<double> widths,
    required Set<int> numericColumns,
  }) => pw.TableHelper.fromTextArray(
    border: pw.TableBorder.all(color: _grid, width: .4),
    headerStyle: pw.TextStyle(fontSize: 7.2, fontWeight: pw.FontWeight.bold),
    headerDecoration: const pw.BoxDecoration(
      color: PdfColor.fromInt(0xFFE7EEF9),
    ),
    headerAlignments: {
      for (final column in numericColumns) column: pw.Alignment.centerRight,
    },
    cellStyle: const pw.TextStyle(fontSize: 7),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2.2),
    cellAlignments: {
      for (var column = 0; column < headers.length; column++)
        column: numericColumns.contains(column)
            ? pw.Alignment.topRight
            : pw.Alignment.topLeft,
    },
    oddRowDecoration: const pw.BoxDecoration(
      color: PdfColor.fromInt(0xFFF7F9FC),
    ),
    columnWidths: {
      for (var column = 0; column < widths.length; column++)
        column: pw.FlexColumnWidth(widths[column]),
    },
    headers: headers,
    data: rows,
  );
}

// ─── Minimal styled XLSX writer ──────────────────────────────────────────
//
// The shared BOQ codec writes every value as text, which prevents engineers
// from summing quantities. This writer emits numeric and percentage cells,
// a bold frozen header row, filters and column widths.

class _Column {
  const _Column(this.heading, this.width);
  final String heading;
  final double width;
}

enum _CellKind { text, number, percent }

class _Cell {
  const _Cell._(this.kind, this.value);

  factory _Cell.text(String value) => _Cell._(_CellKind.text, value);

  factory _Cell.number(String value) => _Cell._(
    double.tryParse(value) == null ? _CellKind.text : _CellKind.number,
    value,
  );

  factory _Cell.percent(double? ratio) =>
      ratio == null || ratio.isNaN || ratio.isInfinite
      ? const _Cell._(_CellKind.text, '—')
      : _Cell._(_CellKind.percent, ratio.toStringAsFixed(6));

  final _CellKind kind;
  final String value;
}

class _Sheet {
  const _Sheet({
    required this.name,
    required this.preamble,
    required this.columns,
    required this.rows,
  });

  final String name;
  final List<String> preamble;
  final List<_Column> columns;
  final List<List<_Cell>> rows;
}

class _XlsxWriter {
  _XlsxWriter(this.sheets);

  final List<_Sheet> sheets;

  // Style indexes in styles.xml cellXfs.
  static const _styleTitle = 1;
  static const _styleNote = 2;
  static const _styleHeader = 3;
  static const _styleNumber = 4;
  static const _stylePercent = 5;
  static const _styleText = 6;

  Uint8List encode() {
    final archive = Archive();
    void add(String path, String content) =>
        archive.addFile(ArchiveFile.string(path, content));

    add('[Content_Types].xml', _contentTypes());
    add('_rels/.rels', _rootRels);
    add('xl/workbook.xml', _workbook());
    add('xl/_rels/workbook.xml.rels', _workbookRels());
    add('xl/styles.xml', _styles);
    for (var index = 0; index < sheets.length; index++) {
      add('xl/worksheets/sheet${index + 1}.xml', _sheetXml(sheets[index]));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  String _sheetXml(_Sheet sheet) {
    final headerRow = sheet.preamble.length + 2;
    final lastRow = headerRow + sheet.rows.length;
    final lastColumn = _columnName(sheet.columns.length - 1);
    final out = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheetViews><sheetView workbookViewId="0">'
      '<pane ySplit="$headerRow" topLeftCell="A${headerRow + 1}" '
      'activePane="bottomLeft" state="frozen"/>'
      '</sheetView></sheetViews>'
      '<sheetFormatPr defaultRowHeight="15"/><cols>',
    );
    for (var index = 0; index < sheet.columns.length; index++) {
      out.write(
        '<col min="${index + 1}" max="${index + 1}" '
        'width="${sheet.columns[index].width}" customWidth="1"/>',
      );
    }
    out.write('</cols><sheetData>');
    var row = 1;
    for (var index = 0; index < sheet.preamble.length; index++) {
      out.write('<row r="$row">');
      _textCell(
        out,
        'A$row',
        sheet.preamble[index],
        index == 0 ? _styleTitle : _styleNote,
      );
      out.write('</row>');
      row++;
    }
    row++; // blank spacer row
    out.write('<row r="$row">');
    for (var index = 0; index < sheet.columns.length; index++) {
      _textCell(
        out,
        '${_columnName(index)}$row',
        sheet.columns[index].heading,
        _styleHeader,
      );
    }
    out.write('</row>');
    for (final cells in sheet.rows) {
      row++;
      out.write('<row r="$row">');
      for (var index = 0; index < cells.length; index++) {
        final cell = cells[index];
        final reference = '${_columnName(index)}$row';
        switch (cell.kind) {
          case _CellKind.number:
            out.write(
              '<c r="$reference" s="$_styleNumber"><v>${cell.value}</v></c>',
            );
          case _CellKind.percent:
            out.write(
              '<c r="$reference" s="$_stylePercent"><v>${cell.value}</v></c>',
            );
          case _CellKind.text:
            if (cell.value.isNotEmpty) {
              _textCell(out, reference, cell.value, _styleText);
            }
        }
      }
      out.write('</row>');
    }
    out.write('</sheetData>');
    if (sheet.rows.isNotEmpty) {
      out.write('<autoFilter ref="A$headerRow:$lastColumn$lastRow"/>');
    }
    out.write(
      '<pageMargins left="0.4" right="0.4" top="0.5" bottom="0.5" '
      'header="0.3" footer="0.3"/>'
      '<pageSetup orientation="landscape" fitToWidth="1" fitToHeight="0"/>'
      '</worksheet>',
    );
    return out.toString();
  }

  static void _textCell(
    StringBuffer out,
    String reference,
    String value,
    int style,
  ) {
    final clean = value.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
    final preserve = clean.trim() != clean ? ' xml:space="preserve"' : '';
    out.write(
      '<c r="$reference" s="$style" t="inlineStr"><is><t$preserve>'
      '${_escape(clean)}</t></is></c>',
    );
  }

  String _workbook() {
    final out = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets>',
    );
    for (var index = 0; index < sheets.length; index++) {
      out.write(
        '<sheet name="${_escape(_sheetName(sheets[index].name, index))}" '
        'sheetId="${index + 1}" r:id="rId${index + 1}"/>',
      );
    }
    out.write('</sheets><definedNames>');
    for (var index = 0; index < sheets.length; index++) {
      final sheet = sheets[index];
      if (sheet.rows.isEmpty) continue;
      final headerRow = sheet.preamble.length + 2;
      final lastRow = headerRow + sheet.rows.length;
      final lastColumn = _columnName(sheet.columns.length - 1);
      out.write(
        '<definedName name="_xlnm._FilterDatabase" localSheetId="$index" '
        'hidden="1">\'${_escape(_sheetName(sheet.name, index))}\'!'
        '\$A\$$headerRow:\$$lastColumn\$$lastRow</definedName>',
      );
    }
    out.write('</definedNames></workbook>');
    return out.toString();
  }

  String _workbookRels() {
    final out = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
    );
    for (var index = 0; index < sheets.length; index++) {
      out.write(
        '<Relationship Id="rId${index + 1}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
        'Target="worksheets/sheet${index + 1}.xml"/>',
      );
    }
    out.write(
      '<Relationship Id="rId${sheets.length + 1}" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
      'Target="styles.xml"/></Relationships>',
    );
    return out.toString();
  }

  String _contentTypes() {
    final out = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>',
    );
    for (var index = 0; index < sheets.length; index++) {
      out.write(
        '<Override PartName="/xl/worksheets/sheet${index + 1}.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
      );
    }
    out.write('</Types>');
    return out.toString();
  }

  static const _rootRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
      'Target="xl/workbook.xml"/></Relationships>';

  // 0 default · 1 title · 2 note · 3 header · 4 number · 5 percent · 6 text
  static const _styles =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<fonts count="4">'
      '<font><sz val="11"/><name val="Calibri"/></font>'
      '<font><b/><sz val="14"/><name val="Calibri"/></font>'
      '<font><sz val="9"/><color rgb="FF5C6673"/><name val="Calibri"/></font>'
      '<font><b/><sz val="11"/><name val="Calibri"/></font>'
      '</fonts>'
      '<fills count="3">'
      '<fill><patternFill patternType="none"/></fill>'
      '<fill><patternFill patternType="gray125"/></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FFE7EEF9"/><bgColor indexed="64"/></patternFill></fill>'
      '</fills>'
      '<borders count="2">'
      '<border><left/><right/><top/><bottom/><diagonal/></border>'
      '<border><left/><right/><top/><bottom style="thin"><color rgb="FF9AA3AE"/></bottom><diagonal/></border>'
      '</borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="7">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      '<xf numFmtId="0" fontId="3" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top"/></xf>'
      '<xf numFmtId="9" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>'
      '</cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
      '</styleSheet>';

  static String _sheetName(String source, int index) {
    final cleaned = source.replaceAll(RegExp(r'[\[\]\*\?/\\:]'), ' ').trim();
    final name = cleaned.isEmpty ? 'Sheet${index + 1}' : cleaned;
    return name.length > 31 ? name.substring(0, 31) : name;
  }

  static String _columnName(int index) {
    var value = index + 1;
    final buffer = StringBuffer();
    while (value > 0) {
      final remainder = (value - 1) % 26;
      buffer.write(String.fromCharCode(65 + remainder));
      value = (value - 1) ~/ 26;
    }
    return buffer.toString().split('').reversed.join();
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

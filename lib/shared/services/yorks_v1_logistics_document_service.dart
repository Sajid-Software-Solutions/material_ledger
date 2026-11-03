import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/yorks_v1_boq.dart';
import '../models/yorks_v1_company_document_strings.dart';
import '../models/yorks_v1_logistics.dart';
import '../models/yorks_v1_logistics_strings.dart';
import '../models/yorks_v1_material_return_workflow.dart';
import '../models/yorks_v1_project_strings.dart';
import '../models/yorks_v1_quantity.dart';
import 'yorks_v1_boq_workbook_service.dart';
import 'yorks_v1_pdf_arabic.dart';

/// Generates operational-only exports from server-derived Delivery Order and
/// return snapshots. No cost or supplier-commercial fields can enter either
/// document because the typed inputs do not contain them.
class YorksV1LogisticsDocumentService {
  const YorksV1LogisticsDocumentService({
    this.workbookCodec = const YorksV1BoqWorkbookCodec(),
  });

  final YorksV1BoqWorkbookCodec workbookCodec;

  Uint8List buildDeliveryOrderExcel({
    required YorksV1ReturnsDocumentsWorkspace workspace,
    required YorksV1DeliveryOrderDispatch dispatch,
    required YorksV1DeliveryOrderRevision revision,
  }) => _buildWorkbook(
    projectId: workspace.projectId,
    sourceId: revision.id,
    title: '${dispatch.deliveryOrder!.reference} R${revision.revisionNumber}',
    headings: [
      YorksV1LogisticsStrings.serialNumber.primary,
      YorksV1LogisticsStrings.itemDescription.primary,
      YorksV1LogisticsStrings.deliveryQuantity.primary,
      YorksV1LogisticsStrings.unit.primary,
    ],
    rows: [
      for (final line in revision.lines)
        [
          line.serialNumber.toString(),
          yorksV1DeliveryOrderLineDescription(line),
          yorksV1DisplayQuantity(line.quantity),
          line.unit,
        ],
    ],
  );

  Uint8List buildMaterialReturnExcel({
    required YorksV1ReturnsDocumentsWorkspace workspace,
    required YorksV1MaterialReturn materialReturn,
  }) => _buildWorkbook(
    projectId: workspace.projectId,
    sourceId: materialReturn.id,
    title:
        materialReturn.number ??
        YorksV1LogisticsStrings.materialReturns.primary,
    headings: [
      YorksV1LogisticsStrings.serialNumber.primary,
      YorksV1LogisticsStrings.itemDescription.primary,
      YorksV1LogisticsStrings.deliveryQuantity.primary,
      YorksV1LogisticsStrings.unit.primary,
    ],
    rows: [
      for (final line in materialReturn.lines)
        [
          line.displayOrder.toString(),
          line.description,
          yorksV1DisplayQuantity(line.returnQuantity),
          line.unit,
        ],
    ],
  );

  Uint8List buildProjectMaterialReturnExcel(
    YorksV1ProjectMaterialReturn materialReturn,
  ) => _buildWorkbook(
    projectId: materialReturn.projectId,
    sourceId: materialReturn.id,
    title: materialReturn.number ?? 'Material Return Draft',
    headings: const [
      'No.',
      'Item Description',
      'Brand / Origin',
      'Qty.',
      'Unit',
      'Source trace',
      'Note',
    ],
    rows: [
      for (final line in materialReturn.lines)
        [
          line.displayOrder.toString(),
          line.description,
          line.brandOrigin ?? '',
          yorksV1DisplayQuantity(line.returnQuantity),
          line.unit,
          line.origin == YorksV1ReturnLineOrigin.custom
              ? 'Custom / unmatched'
              : [
                  line.sourceRequestNumber,
                  line.sourceDispatchNumber,
                ].whereType<String>().join(' · '),
          line.lineNote ?? '',
        ],
    ],
  );

  /// Printing receives the exact immutable A4 bytes used by the PDF download
  /// and stored controlled-document snapshot.  Never rebuild a second printer
  /// layout from mutable dispatch rows.
  Future<void> printDeliveryOrder({
    required YorksV1ReturnsDocumentsWorkspace workspace,
    required YorksV1DeliveryOrderDispatch dispatch,
    required YorksV1DeliveryOrderRevision revision,
  }) async {
    final bytes = await buildDeliveryOrderPdf(
      workspace: workspace,
      dispatch: dispatch,
      revision: revision,
      format: PdfPageFormat.a4,
    );
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> shareDeliveryOrderPdf({
    required YorksV1ReturnsDocumentsWorkspace workspace,
    required YorksV1DeliveryOrderDispatch dispatch,
    required YorksV1DeliveryOrderRevision revision,
  }) async {
    final bytes = await buildDeliveryOrderPdf(
      workspace: workspace,
      dispatch: dispatch,
      revision: revision,
      format: PdfPageFormat.a4,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: suggestedDeliveryOrderPdfName(
        dispatch.deliveryOrder!,
        revision,
      ),
    );
  }

  Future<void> printMaterialReturn({
    required YorksV1ReturnsDocumentsWorkspace workspace,
    required YorksV1MaterialReturn materialReturn,
  }) => Printing.layoutPdf(
    onLayout: (format) => buildMaterialReturnPdf(
      workspace: workspace,
      materialReturn: materialReturn,
      format: format,
    ),
  );

  Future<void> printProjectMaterialReturn(
    YorksV1ProjectMaterialReturn materialReturn,
  ) => Printing.layoutPdf(
    onLayout: (format) =>
        buildProjectMaterialReturnPdf(materialReturn, format: format),
  );

  Future<void> shareProjectMaterialReturnPdf(
    YorksV1ProjectMaterialReturn materialReturn,
  ) async {
    final bytes = await buildProjectMaterialReturnPdf(
      materialReturn,
      format: PdfPageFormat.a4,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: suggestedProjectMaterialReturnPdfName(materialReturn),
    );
  }

  Future<Uint8List> buildProjectMaterialReturnPdf(
    YorksV1ProjectMaterialReturn materialReturn, {
    required PdfPageFormat format,
  }) async {
    final logo = await _loadLogo();
    final theme = await _buildTheme();
    final document = pw.Document(
      theme: theme,
      title: '${materialReturn.number ?? 'Draft'} - RETURN MATERIALS',
      author: YorksV1CompanyDocumentStrings.legalName.primary,
      creator: 'Yorks Project Management',
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        maxPages: 200,
        margin: pw.EdgeInsets.fromLTRB(
          12 * PdfPageFormat.mm,
          9 * PdfPageFormat.mm,
          12 * PdfPageFormat.mm,
          7 * PdfPageFormat.mm,
        ),
        header: (context) => context.pageNumber == 1
            ? pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  _companyHeader(logo),
                  pw.SizedBox(height: 2.5 * PdfPageFormat.mm),
                  pw.Center(
                    child: pw.Text(
                      'RETURN MATERIALS',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 3 * PdfPageFormat.mm),
                  _deliveryLabelValue(
                    'Reference',
                    materialReturn.number ?? 'Draft',
                    valueBold: true,
                  ),
                  pw.SizedBox(height: 1.8 * PdfPageFormat.mm),
                  _deliveryLabelValue(
                    'Project',
                    '${materialReturn.projectReference} - ${materialReturn.projectName}',
                    valueBold: true,
                  ),
                  pw.SizedBox(height: 1.8 * PdfPageFormat.mm),
                  _deliveryLabelValue(
                    'Building / Scope',
                    materialReturn.scopeName,
                  ),
                  pw.SizedBox(height: 1.8 * PdfPageFormat.mm),
                  _deliveryLabelValue(
                    'Date',
                    DateFormat('dd/MM/yyyy').format(
                      (materialReturn.requestedReturnDate ??
                              materialReturn.draftedAt)
                          .toLocal(),
                    ),
                  ),
                  pw.SizedBox(height: 1.8 * PdfPageFormat.mm),
                  _deliveryLabelValue('Purpose', materialReturn.purpose ?? '—'),
                  if (materialReturn.deliveryNoteReference != null) ...[
                    pw.SizedBox(height: 1.8 * PdfPageFormat.mm),
                    _deliveryLabelValue(
                      'Delivery note',
                      materialReturn.deliveryNoteReference!,
                    ),
                  ],
                  if (materialReturn.driverName != null) ...[
                    pw.SizedBox(height: 1.8 * PdfPageFormat.mm),
                    _deliveryLabelValue(
                      'Driver / Vehicle',
                      [
                        materialReturn.driverName,
                        materialReturn.vehicleReference,
                      ].whereType<String>().join(' · '),
                    ),
                  ],
                  pw.SizedBox(height: 4 * PdfPageFormat.mm),
                ],
              )
            : pw.SizedBox(),
        footer: _materialReturnFooter,
        build: (_) => [
          _table(
            headers: const ['No.', 'Item Description', 'Qty.', 'Unit', 'Note'],
            rows: [
              for (final line in materialReturn.lines)
                [
                  line.displayOrder.toString(),
                  [
                    line.description,
                    if (line.brandOrigin != null) line.brandOrigin!,
                    if (line.sourceRequestNumber != null)
                      'Source: ${line.sourceRequestNumber}'
                    else if (line.origin == YorksV1ReturnLineOrigin.custom)
                      'Source: Custom / unmatched',
                  ].join('\n'),
                  yorksV1DisplayQuantity(line.returnQuantity),
                  line.unit,
                  line.lineNote ?? '',
                ],
            ],
          ),
        ],
      ),
    );
    return document.save(enableEventLoopBalancing: true);
  }

  String suggestedProjectMaterialReturnExcelName(
    YorksV1ProjectMaterialReturn materialReturn,
  ) => '${_safeName(materialReturn.number ?? 'material_return_draft')}.xlsx';

  String suggestedProjectMaterialReturnPdfName(
    YorksV1ProjectMaterialReturn materialReturn,
  ) => '${_safeName(materialReturn.number ?? 'material_return_draft')}.pdf';

  Future<Uint8List> buildDeliveryOrderPdf({
    required YorksV1ReturnsDocumentsWorkspace workspace,
    required YorksV1DeliveryOrderDispatch dispatch,
    required YorksV1DeliveryOrderRevision revision,
    required PdfPageFormat format,
  }) async {
    final logo = await _loadLogo();
    final theme = await _buildTheme();
    final deliveryOrder = dispatch.deliveryOrder!;
    final isReceiptReviewed =
        revision.snapshotKind == YorksV1DeliveryOrderSnapshotKind.receiptReview;
    final documentTitle =
        (isReceiptReviewed
                ? YorksV1LogisticsStrings.deliveryReportTitle
                : YorksV1LogisticsStrings.deliveryOrderTitle)
            .primary;
    _validateDeliveryOrder(revision);
    final document = pw.Document(
      theme: theme,
      title: '${deliveryOrder.reference} - $documentTitle',
      author: YorksV1CompanyDocumentStrings.legalName.primary,
      creator: 'Yorks Project Management',
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        maxPages: 200,
        margin: pw.EdgeInsets.fromLTRB(
          12 * PdfPageFormat.mm,
          9 * PdfPageFormat.mm,
          12 * PdfPageFormat.mm,
          7 * PdfPageFormat.mm,
        ),
        // The company/title/metadata block is a first-page form header. The
        // delivery table continues with its own repeated column heading.
        header: (context) => context.pageNumber == 1
            ? _deliveryOrderHeader(
                logo: logo,
                workspace: workspace,
                dispatch: dispatch,
                deliveryOrder: deliveryOrder,
                revision: revision,
                documentTitle: documentTitle,
              )
            : pw.SizedBox(),
        // Every page reserves an equal footer band so pagination is stable.
        // Only the final page paints the receipt/signature form in that band,
        // immediately above the legal company footer.
        footer: _deliveryOrderFooter,
        build: (_) => [_deliveryOrderTable(revision.lines)],
      ),
    );
    return document.save(enableEventLoopBalancing: true);
  }

  Future<Uint8List> buildMaterialReturnPdf({
    required YorksV1ReturnsDocumentsWorkspace workspace,
    required YorksV1MaterialReturn materialReturn,
    required PdfPageFormat format,
  }) async {
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => _pdfHeader(
          YorksV1LogisticsStrings.materialReturns.primary,
          materialReturn.number ??
              YorksV1LogisticsStrings.materialReturns.primary,
        ),
        build: (_) => [
          _metadata([
            _PdfMeta(
              YorksV1LogisticsStrings.project.primary,
              workspace.projectName,
            ),
            _PdfMeta(
              YorksV1LogisticsStrings.scope.primary,
              workspace.scopeName,
            ),
            _PdfMeta(
              YorksV1LogisticsStrings.state.primary,
              yorksV1MaterialReturnStateCopy(materialReturn.state).primary,
            ),
            _PdfMeta(
              YorksV1LogisticsStrings.draftedBy.primary,
              materialReturn.draftedByDisplayName,
            ),
          ]),
          if (materialReturn.note != null) ...[
            pw.SizedBox(height: 10),
            pw.Text(
              materialReturn.note!,
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
          pw.SizedBox(height: 16),
          _table(
            headers: [
              YorksV1LogisticsStrings.serialNumber.primary,
              YorksV1LogisticsStrings.itemDescription.primary,
              YorksV1LogisticsStrings.deliveryQuantity.primary,
              YorksV1LogisticsStrings.unit.primary,
            ],
            rows: [
              for (final line in materialReturn.lines)
                [
                  line.displayOrder.toString(),
                  line.description,
                  yorksV1DisplayQuantity(line.returnQuantity),
                  line.unit,
                ],
            ],
          ),
        ],
      ),
    );
    return document.save();
  }

  String suggestedDeliveryOrderExcelName(
    YorksV1DeliveryOrder deliveryOrder,
    YorksV1DeliveryOrderRevision revision,
  ) => '${_safeName(deliveryOrder.reference)}_r${revision.revisionNumber}.xlsx';

  String suggestedDeliveryOrderPdfName(
    YorksV1DeliveryOrder deliveryOrder,
    YorksV1DeliveryOrderRevision revision,
  ) => '${_safeName(deliveryOrder.reference)}_r${revision.revisionNumber}.pdf';

  String suggestedMaterialReturnExcelName(
    YorksV1MaterialReturn materialReturn,
  ) => '${_safeName(materialReturn.number ?? 'material_return')}.xlsx';

  Uint8List _buildWorkbook({
    required String projectId,
    required String sourceId,
    required String title,
    required List<String> headings,
    required List<List<String>> rows,
  }) {
    final columns = [
      for (var index = 0; index < headings.length; index++)
        YorksV1BoqColumn(
          id: 'logistics_column_$index',
          heading: headings[index],
          displayOrder: index + 1,
        ),
    ];
    return workbookCodec.encodeWorksheet(
      YorksV1BoqWorksheet(
        group: YorksV1BoqGroup(
          id: sourceId,
          projectId: projectId,
          name: title,
          worksheetTitle: title,
          displayOrder: 1,
          isCustom: false,
          isArchived: false,
          version: 1,
          rowCount: rows.length,
          columnCount: columns.length,
          updatedAt: DateTime.now().toUtc(),
        ),
        columns: columns,
        rows: [
          for (var rowIndex = 0; rowIndex < rows.length; rowIndex++)
            YorksV1BoqRow(
              id: '$sourceId-$rowIndex',
              displayOrder: rowIndex + 1,
              values: {
                for (var column = 0; column < rows[rowIndex].length; column++)
                  'logistics_column_$column': rows[rowIndex][column],
              },
              canonicalValues: const {},
            ),
        ],
      ),
    );
  }

  static pw.Widget _pdfHeader(String title, String reference) => pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(
        YorksV1LogisticsStrings.companyName.primary,
        style: pw.TextStyle(
          color: PdfColor.fromInt(0xFF003FB1),
          fontSize: 14,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      pw.Text(reference, style: const pw.TextStyle(fontSize: 9)),
      pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
    ],
  );

  /// Shared controlled-document fonts (Noto Sans with Arabic fallback) for
  /// other operational exports, so every Yorks PDF uses one letterhead.
  static Future<pw.ThemeData> controlledDocumentTheme() => _buildTheme();

  static Future<pw.MemoryImage> controlledDocumentLogo() => _loadLogo();

  static pw.Widget controlledDocumentCompanyHeader(pw.MemoryImage? logo) =>
      _companyHeader(logo);

  static Future<pw.MemoryImage>? _logoFuture;
  static Future<pw.ThemeData>? _themeFuture;

  static Future<pw.MemoryImage> _loadLogo() =>
      _logoFuture ??= _loadLogoUncached();

  static Future<pw.MemoryImage> _loadLogoUncached() async {
    final data = await rootBundle.load('assets/logo.png');
    return pw.MemoryImage(data.buffer.asUint8List());
  }

  static Future<pw.ThemeData> _buildTheme() =>
      _themeFuture ??= _buildThemeUncached();

  static Future<pw.ThemeData> _buildThemeUncached() async {
    final base = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
    final arabic = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
    );
    return pw.ThemeData.withFont(
      base: base,
      bold: bold,
      fontFallback: [arabic],
    );
  }

  static final PdfColor _documentInk = PdfColor.fromHex('#111111');
  static final PdfColor _documentGrid = PdfColor.fromHex('#222222');
  static final PdfColor _headerFill = PdfColor.fromHex('#D0D0D0');
  static final PdfColor _documentMuted = PdfColor.fromHex('#5C6673');

  static pw.Widget _deliveryOrderHeader({
    required pw.MemoryImage? logo,
    required YorksV1ReturnsDocumentsWorkspace workspace,
    required YorksV1DeliveryOrderDispatch dispatch,
    required YorksV1DeliveryOrder deliveryOrder,
    required YorksV1DeliveryOrderRevision revision,
    required String documentTitle,
  }) {
    final identity = revision.documentIdentity;
    final projectName = identity?.projectName ?? workspace.projectName;
    final jobReference =
        identity?.jobContractReference ?? workspace.jobContractReference;
    final contractor =
        identity?.mainContractorName ??
        workspace.mainContractorName ??
        projectName;
    final dispatchDate = identity?.dispatchDate ?? dispatch.dispatchDate;
    final scope =
        identity?.scopeCode ??
        identity?.scopeName ??
        workspace.scopeCode ??
        workspace.scopeName;
    final materialContext =
        identity?.materialContext ??
        workspace.materialContext ??
        'Material delivery';
    final dispatchRole = identity?.dispatchedByExactRole;
    final dispatchedBy = [
      identity?.dispatchedByDisplayName,
      if (dispatchRole != null)
        YorksV1ProjectStrings.roleLabel(dispatchRole).primary,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · ');
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _companyHeader(logo),
        pw.SizedBox(height: 2.5 * PdfPageFormat.mm),
        pw.Center(
          child: pw.Text(
            documentTitle,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: _documentInk,
            ),
          ),
        ),
        pw.SizedBox(height: 2.6 * PdfPageFormat.mm),
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(4.2),
            1: pw.FlexColumnWidth(1.8),
          },
          children: [
            pw.TableRow(
              children: [
                _deliveryTopText(contractor, bold: true),
                _deliveryTopText('Ref: ${deliveryOrder.reference}', bold: true),
              ],
            ),
            pw.TableRow(
              children: [
                _deliveryTopText(''),
                _deliveryTopText(
                  'Date: ${DateFormat('dd/MM/yyyy').format(dispatchDate.toLocal())}',
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 3 * PdfPageFormat.mm),
        _deliveryLabelValue(
          'Project',
          YorksV1CompanyDocumentStrings.qualifiedProjectName(
            projectName: projectName,
            jobContractReference: jobReference,
          ),
          valueBold: true,
        ),
        pw.SizedBox(height: 2.5 * PdfPageFormat.mm),
        _deliveryLabelValue('Building No.', scope, valueBold: true),
        pw.SizedBox(height: 2.5 * PdfPageFormat.mm),
        _deliveryLabelValue('Materials', materialContext, valueBold: true),
        if (dispatchedBy.isNotEmpty) ...[
          pw.SizedBox(height: 2.5 * PdfPageFormat.mm),
          _deliveryLabelValue('Dispatched by', dispatchedBy, valueBold: true),
        ],
        pw.SizedBox(height: 4 * PdfPageFormat.mm),
      ],
    );
  }

  static pw.Widget _companyHeader(pw.MemoryImage? logo) => pw.Container(
    width: double.infinity,
    padding: pw.EdgeInsets.symmetric(
      horizontal: 4.5 * PdfPageFormat.mm,
      vertical: 3 * PdfPageFormat.mm,
    ),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _documentGrid, width: .8),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Expanded(
          flex: 10,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text(
                YorksV1CompanyDocumentStrings.legalName.primary,
                style: pw.TextStyle(
                  fontSize: 10.2,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 3 * PdfPageFormat.mm),
        pw.SizedBox(
          width: 20 * PdfPageFormat.mm,
          height: 20 * PdfPageFormat.mm,
          child: logo == null
              ? pw.SizedBox()
              : pw.Image(logo, fit: pw.BoxFit.contain),
        ),
        pw.SizedBox(width: 3 * PdfPageFormat.mm),
        pw.Expanded(
          flex: 10,
          child: pw.Text(
            yorksV1ShapeArabicForPdf(
              YorksV1CompanyDocumentStrings.legalName.ar,
            ),
            textDirection: pw.TextDirection.ltr,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(fontSize: 10.2, fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],
    ),
  );

  static pw.Widget _deliveryTopText(String text, {bool bold = false}) =>
      pw.Padding(
        padding: pw.EdgeInsets.only(
          right: 2 * PdfPageFormat.mm,
          bottom: 1.2 * PdfPageFormat.mm,
        ),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: bold ? 8.4 : 7.5,
            fontWeight: bold ? pw.FontWeight.bold : null,
          ),
        ),
      );

  static pw.Widget _deliveryLabelValue(
    String label,
    String value, {
    bool valueBold = false,
  }) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(
        width: 23 * PdfPageFormat.mm,
        child: pw.Text(
          '$label:',
          style: pw.TextStyle(fontSize: 8.7, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.Expanded(
        child: pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 8.2,
            fontWeight: valueBold ? pw.FontWeight.bold : null,
          ),
        ),
      ),
    ],
  );

  static pw.Widget _deliveryOrderTable(
    List<YorksV1DeliveryOrderLine> lines, {
    bool includeHeader = true,
  }) => pw.Table(
    border: pw.TableBorder.all(color: _documentGrid, width: .7),
    columnWidths: const {
      0: pw.FlexColumnWidth(.7),
      1: pw.FlexColumnWidth(5.1),
      2: pw.FlexColumnWidth(1.05),
      3: pw.FlexColumnWidth(1.15),
    },
    defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
    children: [
      if (includeHeader)
        pw.TableRow(
          repeat: true,
          decoration: pw.BoxDecoration(color: _headerFill),
          children: [
            _deliveryTableHeader('S. No.'),
            _deliveryTableHeader('Description'),
            _deliveryTableHeader('Qty.'),
            _deliveryTableHeader('Unit'),
          ],
        ),
      for (var index = 0; index < lines.length; index++)
        pw.TableRow(
          children: [
            _deliveryCell(
              '${lines[index].serialNumber}',
              alignment: pw.Alignment.center,
            ),
            _deliveryDescriptionCell(lines[index]),
            _deliveryCell(
              yorksV1DisplayQuantity(lines[index].quantity),
              alignment: pw.Alignment.center,
            ),
            _deliveryCell(lines[index].unit, alignment: pw.Alignment.center),
          ],
        ),
    ],
  );

  static pw.Widget _deliveryTableHeader(String text) => pw.Padding(
    padding: pw.EdgeInsets.symmetric(
      horizontal: 1.5 * PdfPageFormat.mm,
      vertical: 2.6 * PdfPageFormat.mm,
    ),
    child: pw.Center(
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 8.2, fontWeight: pw.FontWeight.bold),
      ),
    ),
  );

  static pw.Widget _deliveryCell(
    String text, {
    pw.Alignment alignment = pw.Alignment.centerLeft,
  }) => pw.Container(
    alignment: alignment,
    padding: pw.EdgeInsets.symmetric(
      horizontal: 2.2 * PdfPageFormat.mm,
      vertical: 2.4 * PdfPageFormat.mm,
    ),
    child: pw.Text(text, style: const pw.TextStyle(fontSize: 8.1)),
  );

  static pw.Widget _deliveryDescriptionCell(YorksV1DeliveryOrderLine line) =>
      pw.Container(
        alignment: pw.Alignment.centerLeft,
        padding: pw.EdgeInsets.symmetric(
          horizontal: 2.2 * PdfPageFormat.mm,
          vertical: 2.4 * PdfPageFormat.mm,
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text(line.description, style: const pw.TextStyle(fontSize: 8.1)),
            pw.SizedBox(height: .9 * PdfPageFormat.mm),
            pw.Text(
              yorksV1DeliveryOrderLineMetadata(line),
              style: pw.TextStyle(fontSize: 7.2, color: PdfColors.blueGrey700),
            ),
          ],
        ),
      );

  static pw.Widget _deliveryOrderSignatureBlock() => pw.Column(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      _writingLine('Delivery Address', ''),
      pw.SizedBox(height: 4 * PdfPageFormat.mm),
      pw.Row(
        children: [
          pw.Expanded(
            child: _writingLine(
              YorksV1LogisticsStrings.inspectedAndChecked.primary,
              '',
            ),
          ),
          pw.SizedBox(width: 8 * PdfPageFormat.mm),
          pw.Expanded(
            child: _writingLine(
              YorksV1LogisticsStrings.receiverName.primary,
              '',
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 4.5 * PdfPageFormat.mm),
      pw.Row(
        children: [
          pw.Expanded(child: _writingLine('Signature', '')),
          pw.SizedBox(width: 8 * PdfPageFormat.mm),
          pw.Expanded(child: _writingLine('Signature', '')),
        ],
      ),
      pw.SizedBox(height: 4.5 * PdfPageFormat.mm),
      pw.Row(
        children: [
          pw.Expanded(child: _writingLine('Date', '')),
          pw.SizedBox(width: 8 * PdfPageFormat.mm),
          pw.Expanded(child: _writingLine('Date', '')),
        ],
      ),
      pw.SizedBox(height: 6 * PdfPageFormat.mm),
      pw.Center(
        child: pw.Text(
          YorksV1LogisticsStrings.goodsReceivedInGoodCondition.primary,
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
      ),
    ],
  );

  static pw.Widget _writingLine(String label, String value) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [
      pw.Text(
        '$label:',
        style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(width: 2 * PdfPageFormat.mm),
      pw.Expanded(
        child: pw.Container(
          constraints: pw.BoxConstraints(minHeight: 4.8 * PdfPageFormat.mm),
          padding: pw.EdgeInsets.only(
            left: 1 * PdfPageFormat.mm,
            bottom: .8 * PdfPageFormat.mm,
          ),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: _documentGrid, width: .65),
            ),
          ),
          child: value.trim().isEmpty
              ? pw.SizedBox()
              : pw.Text(value.trim(), style: const pw.TextStyle(fontSize: 7.2)),
        ),
      ),
    ],
  );

  static pw.Widget _companyContact() => pw.Container(
    width: double.infinity,
    padding: pw.EdgeInsets.symmetric(
      horizontal: 2 * PdfPageFormat.mm,
      vertical: 1.5 * PdfPageFormat.mm,
    ),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _documentInk, width: .65),
    ),
    child: pw.Column(
      children: [
        pw.Text(
          yorksV1ShapeArabicForPdf(
            YorksV1CompanyDocumentStrings.contactLine.ar,
          ),
          textDirection: pw.TextDirection.ltr,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 6.8,
            lineSpacing: 1.8,
            color: _documentInk,
          ),
        ),
        pw.SizedBox(height: 1.2 * PdfPageFormat.mm),
        pw.Text(
          YorksV1CompanyDocumentStrings.contactLine.en,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 6.8,
            lineSpacing: 1.8,
            color: _documentInk,
          ),
        ),
        pw.SizedBox(height: 1.2 * PdfPageFormat.mm),
        pw.Text(
          'E-mail: ${YorksV1CompanyDocumentStrings.email}',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 6.8, color: _documentInk),
        ),
      ],
    ),
  );

  static pw.Widget _deliveryOrderFooter(pw.Context context) => pw.Column(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.SizedBox(
        height: 50 * PdfPageFormat.mm,
        child: context.pageNumber == context.pagesCount
            ? pw.Align(
                alignment: pw.Alignment.bottomCenter,
                child: _deliveryOrderSignatureBlock(),
              )
            : pw.SizedBox(),
      ),
      pw.SizedBox(height: 4 * PdfPageFormat.mm),
      _companyContact(),
      pw.SizedBox(height: 1.5 * PdfPageFormat.mm),
      _pageNumber(context),
    ],
  );

  static pw.Widget _materialReturnFooter(pw.Context context) => pw.Column(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.SizedBox(
        height: 43 * PdfPageFormat.mm,
        child: context.pageNumber == context.pagesCount
            ? pw.Align(
                alignment: pw.Alignment.bottomCenter,
                child: pw.Table(
                  border: pw.TableBorder.all(color: _documentGrid, width: .65),
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        color: PdfColor.fromInt(0xFFE7EEF9),
                      ),
                      children: [
                        for (final heading in const [
                          'Send by',
                          'Driver',
                          'Engineer',
                          'Receive by',
                        ])
                          pw.Padding(
                            padding: pw.EdgeInsets.all(1.8 * PdfPageFormat.mm),
                            child: pw.Text(
                              heading,
                              style: pw.TextStyle(
                                fontSize: 7.2,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    for (final label in const ['Name', 'Signature', 'Date'])
                      pw.TableRow(
                        children: [
                          for (var index = 0; index < 4; index++)
                            pw.Container(
                              height: 8 * PdfPageFormat.mm,
                              padding: pw.EdgeInsets.all(
                                1.6 * PdfPageFormat.mm,
                              ),
                              child: pw.Text(
                                '$label:',
                                style: const pw.TextStyle(fontSize: 6.7),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              )
            : pw.SizedBox(),
      ),
      pw.SizedBox(height: 4 * PdfPageFormat.mm),
      _companyContact(),
      pw.SizedBox(height: 1.5 * PdfPageFormat.mm),
      _pageNumber(context),
    ],
  );

  static pw.Widget _pageNumber(pw.Context context) => pw.Align(
    alignment: pw.Alignment.centerRight,
    child: pw.Text(
      'Page ${context.pageNumber} of ${context.pagesCount}',
      style: pw.TextStyle(fontSize: 6.2, color: _documentMuted),
    ),
  );

  static void _validateDeliveryOrder(YorksV1DeliveryOrderRevision revision) {
    if (revision.lines.isEmpty) {
      throw StateError('The Delivery Order has no dispatched material lines.');
    }
    for (var index = 0; index < revision.lines.length; index++) {
      final line = revision.lines[index];
      if (line.description.trim().isEmpty ||
          line.unit.trim().isEmpty ||
          double.tryParse(line.quantity.trim()) == null ||
          double.parse(line.quantity.trim()) < 0 ||
          (revision.snapshotKind == YorksV1DeliveryOrderSnapshotKind.dispatch &&
              double.parse(line.quantity.trim()) <= 0)) {
        throw StateError(
          'Delivery Order row ${index + 1} has incomplete snapshot values.',
        );
      }
    }
  }

  static pw.Widget _metadata(List<_PdfMeta> values) => pw.Wrap(
    spacing: 18,
    runSpacing: 6,
    children: [
      for (final value in values)
        pw.RichText(
          text: pw.TextSpan(
            children: [
              pw.TextSpan(
                text: '${value.label}: ',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 8,
                ),
              ),
              pw.TextSpan(
                text: value.value,
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          ),
        ),
    ],
  );

  static pw.Widget _table({
    required List<String> headers,
    required List<List<String>> rows,
  }) => pw.TableHelper.fromTextArray(
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
    headerDecoration: const pw.BoxDecoration(
      color: PdfColor.fromInt(0xFFE7EEF9),
    ),
    cellStyle: const pw.TextStyle(fontSize: 8.5),
    headers: headers,
    data: rows,
  );

  static String _safeName(String source) {
    final safe = source.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return safe.isEmpty ? 'logistics_document' : safe;
  }
}

class _PdfMeta {
  const _PdfMeta(this.label, this.value);
  final String label;
  final String value;
}

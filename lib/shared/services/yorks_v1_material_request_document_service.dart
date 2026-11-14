import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/yorks_v1_boq.dart';
import '../models/yorks_v1_company_document_strings.dart';
import '../models/yorks_v1_material_request.dart';
import '../models/yorks_v1_material_request_document.dart';
import '../models/yorks_v1_material_request_strings.dart';
import '../models/yorks_v1_project_strings.dart';
import '../models/yorks_v1_quantity.dart';
import 'yorks_v1_boq_workbook_service.dart';
import 'yorks_v1_pdf_letterhead.dart';

/// Produces a controlled MR export from the role-safe projection already held
/// by the caller. Commercial fields are included only when the server supplied
/// them; the service never looks up or reconstructs cost data locally.
class YorksV1MaterialRequestDocumentService {
  const YorksV1MaterialRequestDocumentService({
    this.workbookCodec = const YorksV1BoqWorkbookCodec(),
  });

  final YorksV1BoqWorkbookCodec workbookCodec;

  Uint8List buildExcel(YorksV1MaterialRequest request) => _buildExcel(
    id: request.id,
    projectId: request.projectId,
    title: request.requestNumber ?? request.projectReference,
    worksheetTitle: 'Material Request',
    version: request.recordVersion,
    updatedAt: request.updatedAt,
    lines: request.lines,
    includeCommercial: request.lines.any((line) => line.unitCost != null),
  );

  /// Exports the same controlled operational table while a request is still
  /// private and editable. Technical planning context is carried in the
  /// Item Description cell so the controlled workbook never grows BOQ-only
  /// columns, and commercial values are never added to a draft export.
  Uint8List buildDraftExcel(YorksV1MaterialRequestDraft draft) => _buildExcel(
    id: draft.id,
    projectId: draft.projectId ?? 'draft',
    title: 'Material Request',
    worksheetTitle: 'Material Request',
    version: draft.serverRecordVersion,
    updatedAt: draft.updatedAt,
    lines: draft.lines,
    includeCommercial: false,
  );

  /// Produces an import-ready engineering workbook for reuse while composing
  /// another request. Unlike the controlled submitted form, this private
  /// draft workbook keeps Size and Model / Tag in explicit editable columns.
  /// It contains no commercial or warehouse availability data.
  Uint8List buildDraftImportExcel(YorksV1MaterialRequestDraft draft) {
    final headings = <String>[
      YorksV1MaterialRequestStrings.rowNumber.primary,
      YorksV1MaterialRequestStrings.itemDescription.primary,
      YorksV1MaterialRequestStrings.size.primary,
      YorksV1MaterialRequestStrings.planningModelTag.primary,
      YorksV1MaterialRequestStrings.brandOrigin.primary,
      YorksV1MaterialRequestStrings.quantity.primary,
      YorksV1MaterialRequestStrings.unit.primary,
    ];
    final columns = [
      for (var index = 0; index < headings.length; index++)
        YorksV1BoqColumn(
          id: 'mr_import_column_$index',
          heading: headings[index],
          displayOrder: index + 1,
        ),
    ];
    final worksheet = YorksV1BoqWorksheet(
      group: YorksV1BoqGroup(
        id: draft.id,
        projectId: draft.projectId ?? 'draft',
        name: 'Material Request Import',
        worksheetTitle: 'MR Import',
        displayOrder: 1,
        isCustom: false,
        isArchived: false,
        version: draft.serverRecordVersion,
        rowCount: draft.lines.length,
        columnCount: columns.length,
        updatedAt: draft.updatedAt,
      ),
      columns: columns,
      rows: [
        for (var index = 0; index < draft.lines.length; index++)
          YorksV1BoqRow(
            id: draft.lines[index].id,
            displayOrder: index + 1,
            values: {
              'mr_import_column_0': (index + 1).toString(),
              'mr_import_column_1': draft.lines[index].description,
              'mr_import_column_2': draft.lines[index].size ?? '',
              'mr_import_column_3':
                  draft.lines[index].model ??
                  draft.lines[index].planningModelTag ??
                  '',
              'mr_import_column_4': draft.lines[index].brandOrigin ?? '',
              'mr_import_column_5': draft.lines[index].quantity,
              'mr_import_column_6': draft.lines[index].unit,
            },
            canonicalValues: const {},
          ),
      ],
    );
    return workbookCodec.encodeWorksheet(worksheet);
  }

  Uint8List _buildExcel({
    required String id,
    required String projectId,
    required String title,
    required String worksheetTitle,
    required int version,
    required DateTime updatedAt,
    required List<YorksV1MaterialRequestLine> lines,
    required bool includeCommercial,
  }) {
    // Engineer projections intentionally omit commercial columns. When a
    // server-authorized commercial projection is supplied, the controlled
    // order is exactly: R No, Item Description, Brand/Origin, Qty, Unit,
    // Unit Cost, Total Cost.
    final headings = <String>[
      YorksV1MaterialRequestStrings.rowNumber.primary,
      YorksV1MaterialRequestStrings.itemDescription.primary,
      YorksV1MaterialRequestStrings.brandOrigin.primary,
      YorksV1MaterialRequestStrings.quantity.primary,
      YorksV1MaterialRequestStrings.unit.primary,
      if (includeCommercial) YorksV1MaterialRequestStrings.unitCost.primary,
      if (includeCommercial) YorksV1MaterialRequestStrings.totalCost.primary,
    ];
    final columns = [
      for (var index = 0; index < headings.length; index++)
        YorksV1BoqColumn(
          id: 'mr_column_$index',
          heading: headings[index],
          displayOrder: index + 1,
        ),
    ];
    final worksheet = YorksV1BoqWorksheet(
      group: YorksV1BoqGroup(
        id: id,
        projectId: projectId,
        name: title,
        worksheetTitle: worksheetTitle,
        displayOrder: 1,
        isCustom: false,
        isArchived: false,
        version: version,
        rowCount: lines.length,
        columnCount: columns.length,
        updatedAt: updatedAt,
      ),
      columns: columns,
      rows: [
        for (var index = 0; index < lines.length; index++)
          // R No is a presentation sequence, never an internal identifier.
          // Re-numbering here keeps exports consecutive after line deletes or
          // server-side ordering changes.
          YorksV1BoqRow(
            id: lines[index].id,
            displayOrder: index + 1,
            values: {
              'mr_column_0': (index + 1).toString(),
              'mr_column_1': _displayDescription(lines[index]),
              'mr_column_2': lines[index].brandOrigin ?? '',
              'mr_column_3': lines[index].quantity,
              'mr_column_4': lines[index].unit,
              if (includeCommercial) 'mr_column_5': lines[index].unitCost ?? '',
              if (includeCommercial)
                'mr_column_6': lines[index].totalCost ?? '',
            },
            canonicalValues: const {},
          ),
      ],
    );
    return workbookCodec.encodeWorksheet(worksheet);
  }

  String suggestedExcelName(YorksV1MaterialRequest request) =>
      '${_safeName(request.requestNumber ?? request.projectReference)}_Material_Request.xlsx';

  String suggestedDraftExcelName(YorksV1MaterialRequestDraft draft) =>
      'Material_Request_Draft_${_safeName(draft.id)}.xlsx';

  String suggestedDraftImportExcelName(
    YorksV1MaterialRequestDraft draft, {
    String? projectReference,
  }) {
    final reference = projectReference?.trim();
    final prefix = reference == null || reference.isEmpty
        ? 'Material_Request'
        : '${_safeName(reference)}_Material_Request';
    return '${prefix}_Import_Ready.xlsx';
  }

  static const double _mm = PdfPageFormat.mm;
  static final PdfColor _documentInk = PdfColor.fromHex('#111111');
  static final PdfColor _documentGrid = PdfColor.fromHex('#222222');
  static final PdfColor _documentMuted = PdfColor.fromHex('#5C6673');

  /// Print and PDF sharing intentionally use exactly the same A4 bytes.  This
  /// avoids a browser/printer layout drift and preserves the controlled
  /// snapshot supplied by the server-authorized request projection.
  Future<void> printPdf(YorksV1MaterialRequest request) async {
    final bytes = await buildPdf(request, PdfPageFormat.a4);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> printDocumentPdf(
    YorksV1MaterialRequestDocumentModel model,
  ) async {
    final bytes = await buildDocumentPdf(model, PdfPageFormat.a4);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> sharePdf(YorksV1MaterialRequest request) async {
    final bytes = await buildPdf(request, PdfPageFormat.a4);
    await Printing.sharePdf(bytes: bytes, filename: suggestedPdfName(request));
  }

  Future<void> shareDocumentPdf(
    YorksV1MaterialRequestDocumentModel model,
  ) async {
    final bytes = await buildDocumentPdf(model, PdfPageFormat.a4);
    await Printing.sharePdf(
      bytes: bytes,
      filename: suggestedPdfName(model.request),
    );
  }

  String suggestedPdfName(YorksV1MaterialRequest request) =>
      '${_safeName(request.requestNumber ?? request.projectReference)}_Material_Request.pdf';

  Future<Uint8List> buildPdf(
    YorksV1MaterialRequest request,
    PdfPageFormat format,
  ) => buildDocumentPdf(
    YorksV1MaterialRequestDocumentModel.fromRequest(request),
    format,
  );

  Future<Uint8List> buildDocumentPdf(
    YorksV1MaterialRequestDocumentModel model,
    PdfPageFormat format,
  ) async {
    final request = model.request;
    _validatePdfRequest(request);
    final commercial = request.lines.any((line) => line.unitCost != null);
    final theme = await _buildTheme();
    final logo = await _loadLogo();
    final document = pw.Document(
      theme: theme,
      title:
          '${request.requestNumber ?? request.projectReference} - Material Request',
      author: YorksV1MaterialRequestStrings.companyLegalName.primary,
      creator: 'Yorks Project Management',
    );
    document.addPage(
      pw.MultiPage(
        // The controlled document is A4 portrait regardless of the printer's
        // previously selected paper size. [format] remains in the public
        // signature for backwards-compatible callers.
        pageFormat: PdfPageFormat.a4,
        maxPages: 200,
        margin: pw.EdgeInsets.fromLTRB(7 * _mm, 7 * _mm, 7 * _mm, 7 * _mm),
        // The controlled form identity block belongs to page one only. The
        // table's own repeated heading still identifies continuation pages.
        header: (context) => context.pageNumber == 1
            ? _formalHeader(logo, model)
            : pw.SizedBox(),
        build: (_) => [
          _materialTable(model, commercial: commercial),
          // Keep all three approval areas together near the bottom of the
          // final page without reserving their space on every preceding page.
          pw.NewPage(freeSpace: 52 * _mm),
          pw.Spacer(),
          _approvalClosingBlock(model),
        ],
      ),
    );
    return document.save(enableEventLoopBalancing: true);
  }

  // The logo and fonts are shared with every Yorks print
  // (yorks_v1_pdf_letterhead.dart).
  static Future<pw.MemoryImage> _loadLogo() => yorksV1PdfLogo();

  static Future<pw.ThemeData> _buildTheme() => yorksV1PdfTheme();

  static pw.Widget _formalHeader(
    pw.MemoryImage? logo,
    YorksV1MaterialRequestDocumentModel model,
  ) {
    final request = model.request;
    final requestedBy = [
      request.requesterDisplayName?.trim(),
      requesterRoleLabel(request),
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    final scheduledDate = request.scheduledDate == null
        ? '—'
        : DateFormat('dd MMM yyyy').format(request.scheduledDate!.toLocal());
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _companyHeader(logo),
        pw.SizedBox(height: 2.5 * _mm),
        pw.Center(
          child: pw.Text(
            YorksV1MaterialRequestStrings.materialRequestForm.primary,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: _documentInk,
            ),
          ),
        ),
        pw.SizedBox(height: 2.6 * _mm),
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(1.05),
            1: pw.FlexColumnWidth(2.35),
            2: pw.FlexColumnWidth(1.05),
            3: pw.FlexColumnWidth(2.35),
          },
          children: [
            _metaRow(
              'Project Name',
              YorksV1CompanyDocumentStrings.qualifiedProjectName(
                projectName: request.projectName,
                jobContractReference: request.jobContractReference,
              ),
              'Request No.',
              request.requestNumber ?? request.id,
            ),
            _metaRow(
              'Project Ref. No.',
              request.projectReference,
              'Requested By',
              requestedBy.isEmpty ? '—' : requestedBy,
            ),
            _metaRow(
              'Delivery Type',
              yorksV1MaterialRequestTimingCopy(request.timing).primary,
              'Scheduled Date',
              scheduledDate,
            ),
            _metaRow(
              'Building / Other',
              request.scopeName,
              'Project Engineers',
              model.projectEngineerNames.isEmpty
                  ? '—'
                  : model.projectEngineerNames.join(', '),
            ),
          ],
        ),
        pw.SizedBox(height: 3 * _mm),
      ],
    );
  }

  static pw.Widget _companyHeader(pw.MemoryImage? logo) =>
      yorksV1PdfLetterhead(logo);

  static pw.TableRow _metaRow(
    String leftLabel,
    String leftValue,
    String rightLabel,
    String rightValue,
  ) => pw.TableRow(
    verticalAlignment: pw.TableCellVerticalAlignment.top,
    children: [
      _metaLabel(leftLabel),
      _metaValue(leftValue),
      _metaLabel(rightLabel),
      _metaValue(rightValue),
    ],
  );

  static pw.Widget _metaLabel(String value) => pw.Padding(
    padding: pw.EdgeInsets.only(right: 1.5 * _mm, bottom: 1.8 * _mm),
    child: pw.Text(
      '$value:',
      style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
    ),
  );

  static pw.Widget _metaValue(String value) => pw.Padding(
    padding: pw.EdgeInsets.only(right: 3 * _mm, bottom: 1.8 * _mm),
    child: pw.Text(
      value.trim().isEmpty ? '—' : value.trim(),
      style: const pw.TextStyle(fontSize: 7.4),
    ),
  );

  static pw.Widget _materialTable(
    YorksV1MaterialRequestDocumentModel model, {
    required bool commercial,
  }) {
    final request = model.request;
    final showStatus = model.showLineStatus;
    final headers = [
      'R No',
      'Item Description',
      'Brand/Origin',
      'Qty.',
      'Unit',
      if (commercial) 'Unit Cost',
      if (commercial) 'Total Cost',
      if (showStatus) 'Status',
    ];
    final widths = commercial
        ? <int, pw.TableColumnWidth>{
            0: pw.FlexColumnWidth(.65),
            1: pw.FlexColumnWidth(3.45),
            2: pw.FlexColumnWidth(1.8),
            3: pw.FlexColumnWidth(.8),
            4: pw.FlexColumnWidth(.9),
            5: pw.FlexColumnWidth(1.25),
            6: pw.FlexColumnWidth(1.25),
            if (showStatus) 7: const pw.FlexColumnWidth(1.45),
          }
        : <int, pw.TableColumnWidth>{
            0: pw.FlexColumnWidth(.65),
            1: pw.FlexColumnWidth(4.25),
            2: pw.FlexColumnWidth(2.05),
            3: pw.FlexColumnWidth(.85),
            4: pw.FlexColumnWidth(.95),
            if (showStatus) 5: const pw.FlexColumnWidth(1.45),
          };
    return pw.Table(
      border: pw.TableBorder.all(color: _documentGrid, width: .8),
      columnWidths: widths,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
      children: [
        pw.TableRow(
          repeat: true,
          verticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [for (final header in headers) _tableHeader(header)],
        ),
        for (var index = 0; index < request.lines.length; index++)
          _materialRow(
            request.lines[index],
            index + 1,
            commercial: commercial,
            status: showStatus
                ? model.receiptStatuses[request.lines[index].id]
                : null,
          ),
        for (var index = request.lines.length; index < 6; index++)
          _emptyMaterialRow(commercial: commercial, showStatus: showStatus),
      ],
    );
  }

  static pw.TableRow _materialRow(
    YorksV1MaterialRequestLine line,
    int number, {
    required bool commercial,
    String? status,
  }) => pw.TableRow(
    children: [
      _tableCell('$number', bold: true, alignment: pw.Alignment.topCenter),
      _descriptionCell(line),
      _tableCell(line.brandOrigin ?? ''),
      _tableCell(
        yorksV1DisplayQuantity(line.quantity),
        alignment: pw.Alignment.topCenter,
      ),
      _tableCell(line.unit),
      if (commercial)
        _tableCell(
          _dashWhenEmpty(line.unitCost),
          alignment: pw.Alignment.topRight,
        ),
      if (commercial)
        _tableCell(
          _dashWhenEmpty(line.totalCost),
          alignment: pw.Alignment.topRight,
        ),
      if (status != null) _tableCell(status),
    ],
  );

  static pw.TableRow _emptyMaterialRow({
    required bool commercial,
    required bool showStatus,
  }) => pw.TableRow(
    children: [
      for (
        var index = 0;
        index < (commercial ? 7 : 5) + (showStatus ? 1 : 0);
        index++
      )
        pw.SizedBox(height: 8.2 * _mm),
    ],
  );

  static pw.Widget _tableHeader(String value) => pw.Padding(
    padding: pw.EdgeInsets.symmetric(
      horizontal: 1.2 * _mm,
      vertical: 2.2 * _mm,
    ),
    child: pw.Center(
      child: pw.Text(
        value,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(fontSize: 7.3, fontWeight: pw.FontWeight.bold),
      ),
    ),
  );

  static pw.Widget _tableCell(
    String value, {
    bool bold = false,
    pw.Alignment alignment = pw.Alignment.topLeft,
  }) => pw.Container(
    alignment: alignment,
    padding: pw.EdgeInsets.symmetric(
      horizontal: 1.2 * _mm,
      vertical: 2.5 * _mm,
    ),
    child: pw.Text(
      value,
      style: pw.TextStyle(
        fontSize: 7.2,
        fontWeight: bold ? pw.FontWeight.bold : null,
      ),
    ),
  );

  static pw.Widget _descriptionCell(YorksV1MaterialRequestLine line) {
    final details = <String>[
      if (line.size?.trim().isNotEmpty ?? false) 'Size: ${line.size!.trim()}',
      if (line.model?.trim().isNotEmpty ?? false)
        'Model: ${line.model!.trim()}',
      if (line.equipmentTag?.trim().isNotEmpty ?? false)
        'Tag: ${line.equipmentTag!.trim()}',
      if (line.planningModelTag?.trim().isNotEmpty ?? false)
        'Model / Tag: ${line.planningModelTag!.trim()}',
    ];
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(
        horizontal: 1.2 * _mm,
        vertical: 2.5 * _mm,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(line.description, style: const pw.TextStyle(fontSize: 7.4)),
          if (details.isNotEmpty) ...[
            pw.SizedBox(height: .5 * _mm),
            pw.Text(
              details.join(' · '),
              style: pw.TextStyle(fontSize: 6.5, color: _documentMuted),
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _approvalClosingBlock(
    YorksV1MaterialRequestDocumentModel model,
  ) {
    final request = model.request;
    final arrangement = model.arrangement;
    final approval = model.approval;
    final dispatch = model.dispatch;
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Table(
          border: pw.TableBorder.all(color: _documentGrid, width: .65),
          children: [
            pw.TableRow(
              children: [
                _approvalCell(
                  YorksV1MaterialRequestStrings.requestedBy.primary,
                  request.requesterDisplayName ?? '',
                  requesterRoleLabel(request),
                  request.submittedAt ?? request.createdAt,
                ),
                _approvalCell(
                  YorksV1MaterialRequestStrings.procurement.primary,
                  arrangement?.displayName ?? '',
                  _actorRoleLabel(arrangement),
                  arrangement?.actedAt,
                ),
                _approvalCell(
                  YorksV1MaterialRequestStrings.approvedBy.primary,
                  approval?.displayName ?? '',
                  _actorRoleLabel(approval),
                  approval?.actedAt,
                ),
                _approvalCell(
                  YorksV1MaterialRequestStrings.orderedDispatched.primary,
                  dispatch?.displayName ?? '',
                  _actorRoleLabel(dispatch),
                  dispatch?.actedAt,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  static String requesterRoleLabel(YorksV1MaterialRequest request) {
    final role = request.requesterExactRole ?? request.requesterProjectRole;
    final normalized = role?.trim();
    if (normalized == null || normalized.isEmpty) return '';
    return switch (normalized) {
      'project_engineer' ||
      'site_engineer' ||
      'senior_mechanical_engineer' ||
      'project_manager' ||
      'workshop_in_charge' ||
      'document_controller' ||
      'procurement' ||
      'admin' => YorksV1ProjectStrings.roleLabel(normalized).primary,
      _ => normalized,
    };
  }

  static pw.Widget _approvalCell(
    String title,
    String name,
    String detail,
    DateTime? date,
  ) => pw.Container(
    height: 35 * _mm,
    padding: pw.EdgeInsets.all(2.5 * _mm),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 3.7 * _mm),
        _approvalText('Name', name),
        pw.SizedBox(height: 2.4 * _mm),
        _approvalText('Role', detail),
        pw.SizedBox(height: 2.4 * _mm),
        _approvalText(
          'Date',
          date == null
              ? ''
              : DateFormat('dd MMM yyyy, hh:mm a').format(date.toLocal()),
        ),
      ],
    ),
  );

  static pw.Widget _approvalText(String label, String value) =>
      pw.Text('$label: $value', style: const pw.TextStyle(fontSize: 6.6));

  static void _validatePdfRequest(YorksV1MaterialRequest request) {
    if (request.lines.isEmpty) {
      throw StateError('The Material Request has no material lines.');
    }
    for (var index = 0; index < request.lines.length; index++) {
      final line = request.lines[index];
      if (line.description.trim().isEmpty ||
          line.unit.trim().isEmpty ||
          YorksV1DecimalQuantity.tryParse(line.quantity)?.isPositive != true) {
        throw StateError(
          'Material Request row ${index + 1} has incomplete controlled values.',
        );
      }
    }
  }

  static String _displayDescription(YorksV1MaterialRequestLine line) {
    final details = <String>[
      if (line.size?.trim().isNotEmpty ?? false) 'Size: ${line.size!.trim()}',
      if (line.model?.trim().isNotEmpty ?? false)
        'Model / Tag: ${line.model!.trim()}',
      if (line.planningModelTag?.trim().isNotEmpty ?? false)
        'Model / Tag: ${line.planningModelTag!.trim()}',
    ];
    if (details.isEmpty) return line.description;
    return '${line.description.trim()}\n${details.join('\n')}';
  }

  static String _actorRoleLabel(YorksV1MaterialRequestDocumentActor? actor) {
    final role = actor?.role.trim() ?? '';
    return role.isEmpty ? '' : YorksV1ProjectStrings.roleLabel(role).primary;
  }

  static String _dashWhenEmpty(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? '—' : normalized;
  }

  static String _safeName(String source) {
    final safe = source.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return safe.isEmpty ? 'material_request' : safe;
  }
}

/// The company letterhead on Yorks printed documents: the English legal name,
/// the logo and the Arabic legal name in one ruled box, as on the Material
/// Request form. Shared so every print carries the same header.
library;

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/yorks_v1_company_document_strings.dart';
import '../models/yorks_v1_material_request_strings.dart';
import 'yorks_v1_pdf_arabic.dart';

const double _mm = PdfPageFormat.mm;
final PdfColor _documentGrid = PdfColor.fromHex('#222222');

Future<pw.MemoryImage>? _logoFuture;
Future<pw.ThemeData>? _themeFuture;

/// The company logo (`assets/logo.png`), loaded once.
Future<pw.MemoryImage> yorksV1PdfLogo() => _logoFuture ??= _loadLogo();

Future<pw.MemoryImage> _loadLogo() async {
  final data = await rootBundle.load('assets/logo.png');
  return pw.MemoryImage(data.buffer.asUint8List());
}

/// Noto Sans with an Arabic fallback, loaded once, so the Arabic legal name
/// and any Arabic text print.
Future<pw.ThemeData> yorksV1PdfTheme() => _themeFuture ??= _loadTheme();

Future<pw.ThemeData> _loadTheme() async {
  final base = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
  );
  final arabic = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
  );
  return pw.ThemeData.withFont(base: base, bold: bold, fontFallback: [arabic]);
}

/// The ruled letterhead box: legal name, logo, Arabic legal name.
pw.Widget yorksV1PdfLetterhead(pw.MemoryImage? logo) => pw.Container(
  width: double.infinity,
  padding: pw.EdgeInsets.symmetric(horizontal: 4.5 * _mm, vertical: 3 * _mm),
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
              YorksV1MaterialRequestStrings.companyLegalName.primary,
              style: pw.TextStyle(
                fontSize: 10.2,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      pw.SizedBox(width: 3 * _mm),
      pw.SizedBox(
        width: 20 * _mm,
        height: 20 * _mm,
        child: logo == null
            ? pw.SizedBox()
            : pw.Image(logo, fit: pw.BoxFit.contain),
      ),
      pw.SizedBox(width: 3 * _mm),
      pw.Expanded(
        flex: 10,
        child: pw.Text(
          yorksV1ShapeArabicForPdf(YorksV1CompanyDocumentStrings.legalName.ar),
          textDirection: pw.TextDirection.ltr,
          textAlign: pw.TextAlign.right,
          style: const pw.TextStyle(fontSize: 7.4),
        ),
      ),
    ],
  ),
);

/// R39 Accounts Workspace V2 — tax-invoice PDF builder (P7).
///
/// Renders the server-frozen invoice document model to an A4 portrait PDF. It
/// prints only the snapshot's values and never recomputes money; the only
/// render-time derivation is the amount-in-words line, which is display text
/// (not a stored or transmitted value). Fonts match the register export
/// (bundled Noto Sans + Noto Naskh Arabic).
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/accounts_decimal.dart';
import '../../domain/v2/client_invoice_document_models.dart';

abstract final class YorksClientInvoiceDocumentBuilder {
  /// Builds the printable tax invoice from the frozen (or previewed) model.
  static Future<Uint8List> build(YorksClientInvoiceDocumentModel doc) async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
    final arabic = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
    );

    final currency = doc.currencyCode ?? 'AED';
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        fontFallback: [arabic],
      ),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 36),
        footer: (context) => _footer(doc, context),
        build: (context) => [
          _header(doc),
          pw.SizedBox(height: 14),
          _meta(doc, currency),
          pw.SizedBox(height: 14),
          _linesTable(doc, currency),
          pw.SizedBox(height: 12),
          _totals(doc, currency),
          pw.SizedBox(height: 10),
          _amountInWordsLine(doc.amounts.totalInclVat, currency),
          pw.SizedBox(height: 18),
          _bankBlock(doc),
        ],
      ),
    );

    return pdf.save();
  }

  // ─── Sections ──────────────────────────────────────────────────────────

  static pw.Widget _header(YorksClientInvoiceDocumentModel doc) {
    final company = doc.company;
    final contact = <String>[
      if (_s(company['address']) != null) _s(company['address'])!,
      if (_s(company['phone']) != null) 'Tel ${_s(company['phone'])}',
      if (_s(company['fax']) != null) 'Fax ${_s(company['fax'])}',
      if (_s(company['email']) != null) _s(company['email'])!,
    ].join('  ·  ');
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'TAX INVOICE',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 20,
                    color: PdfColor.fromInt(0xFF0D2F57),
                  ),
                ),
                if (_s(company['trn']) != null)
                  pw.Text(
                    'TRN ${_s(company['trn'])}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
              ],
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF0D2F57),
                borderRadius: pw.BorderRadius.circular(7),
              ),
              child: pw.Text(
                doc.invoiceReference,
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        if (contact.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            contact,
            style: pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
          ),
        ],
        pw.SizedBox(height: 10),
        pw.Divider(height: 1, color: PdfColors.grey400),
      ],
    );
  }

  static pw.Widget _meta(YorksClientInvoiceDocumentModel doc, String currency) {
    final project = doc.project;
    final settings = doc.settings;
    final left = <List<String>>[
      [
        'Project',
        '${_s(project['name']) ?? ''} (${_s(project['project_ref']) ?? ''})',
      ],
      if (_s(settings['scope_line']) != null)
        ['Scope', _s(settings['scope_line'])!],
      if (_s(settings['attention_name']) != null)
        ['Attn', _s(settings['attention_name'])!],
    ];
    final right = <List<String>>[
      if (doc.invoiceDate != null) ['Invoice date', doc.invoiceDate!],
      if (doc.submissionDate != null) ['Submitted', doc.submissionDate!],
      if (doc.dueDate != null) ['Due', doc.dueDate!],
    ];
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: _metaColumn(left)),
        pw.SizedBox(width: 16),
        pw.Expanded(child: _metaColumn(right)),
      ],
    );
  }

  static pw.Widget _metaColumn(List<List<String>> rows) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      for (final row in rows)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.RichText(
            text: pw.TextSpan(
              children: [
                pw.TextSpan(
                  text: '${row[0]}:  ',
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.TextSpan(
                  text: row[1],
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  static pw.Widget _linesTable(
    YorksClientInvoiceDocumentModel doc,
    String currency,
  ) {
    return pw.TableHelper.fromTextArray(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        fontSize: 9,
        color: PdfColors.white,
      ),
      headerDecoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFF0D2F57)),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerRight,
      },
      headers: ['Building', 'Stage', 'Amount ($currency)'],
      data: [
        for (final line in doc.lines)
          [
            line.buildingName,
            line.stageLabel ?? line.stageKey,
            _money(line.amount),
          ],
      ],
    );
  }

  static pw.Widget _totals(
    YorksClientInvoiceDocumentModel doc,
    String currency,
  ) {
    final a = doc.amounts;
    pw.Widget row(
      String label,
      YorksAccountsDecimal value, {
      bool strong = false,
    }) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 9.5,
            fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
        pw.SizedBox(width: 16),
        pw.SizedBox(
          width: 140,
          child: pw.Text(
            '$currency ${_money(value)}',
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              fontSize: 9.5,
              fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
      ],
    );
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        row('Total excl. VAT', a.exVat),
        pw.SizedBox(height: 3),
        row(
          'VAT (${a.vatRatePercent.displayText(maximumFractionDigits: 2)}%)',
          a.vat,
        ),
        pw.SizedBox(height: 3),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: row('Total incl. VAT', a.totalInclVat, strong: true),
        ),
      ],
    );
  }

  static pw.Widget _amountInWordsLine(
    YorksAccountsDecimal total,
    String currency,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Text(
        _amountInWords(total, currency),
        style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic),
      ),
    );
  }

  static pw.Widget _bankBlock(YorksClientInvoiceDocumentModel doc) {
    final c = doc.company;
    final rows = <List<String>>[
      if (_s(c['bank_name']) != null) ['Bank', _s(c['bank_name'])!],
      if (_s(c['bank_account_name']) != null)
        ['Account name', _s(c['bank_account_name'])!],
      if (_s(c['bank_iban']) != null) ['IBAN', _s(c['bank_iban'])!],
    ];
    if (rows.isEmpty) return pw.SizedBox();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Bank details',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5),
        ),
        pw.SizedBox(height: 4),
        _metaColumn(rows),
      ],
    );
  }

  static pw.Widget _footer(
    YorksClientInvoiceDocumentModel doc,
    pw.Context context,
  ) {
    final c = doc.company;
    final parts = <String>[
      if (_s(c['phone']) != null) 'Tel ${_s(c['phone'])}',
      if (_s(c['fax']) != null) 'Fax ${_s(c['fax'])}',
      if (_s(c['address']) != null) _s(c['address'])!,
      if (_s(c['email']) != null) _s(c['email'])!,
    ];
    return pw.Column(
      children: [
        pw.Divider(height: 1, color: PdfColors.grey300),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(
                parts.join('  ·  '),
                style: pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
              ),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
            ),
          ],
        ),
      ],
    );
  }

  // ─── Formatting helpers ──────────────────────────────────────────────────

  static String? _s(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static String _money(YorksAccountsDecimal value) {
    final raw = value.canonicalText;
    final negative = raw.startsWith('-');
    final parts = (negative ? raw.substring(1) : raw).split('.');
    final whole = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final fraction = parts.length == 1 ? '00' : parts[1].padRight(2, '0');
    return '${negative ? '-' : ''}$whole.$fraction';
  }

  static String _amountInWords(YorksAccountsDecimal total, String currency) {
    final raw = total.canonicalText;
    final parts = raw.split('.');
    final whole = BigInt.tryParse(parts.first) ?? BigInt.zero;
    final cents = parts.length == 1
        ? '00'
        : parts[1].padRight(2, '0').substring(0, 2);
    final words = _wholeToWords(whole);
    return '$currency $words and $cents/100 only';
  }

  static String _wholeToWords(BigInt value) {
    if (value == BigInt.zero) return 'Zero';
    const ones = [
      '',
      'One',
      'Two',
      'Three',
      'Four',
      'Five',
      'Six',
      'Seven',
      'Eight',
      'Nine',
      'Ten',
      'Eleven',
      'Twelve',
      'Thirteen',
      'Fourteen',
      'Fifteen',
      'Sixteen',
      'Seventeen',
      'Eighteen',
      'Nineteen',
    ];
    const tens = [
      '',
      '',
      'Twenty',
      'Thirty',
      'Forty',
      'Fifty',
      'Sixty',
      'Seventy',
      'Eighty',
      'Ninety',
    ];
    String threeDigits(int n) {
      final buf = <String>[];
      if (n >= 100) {
        buf.add('${ones[n ~/ 100]} Hundred');
        n %= 100;
      }
      if (n >= 20) {
        buf.add(tens[n ~/ 10]);
        n %= 10;
      }
      if (n > 0) buf.add(ones[n]);
      return buf.join(' ');
    }

    const scales = ['', ' Thousand', ' Million', ' Billion', ' Trillion'];
    final groups = <int>[];
    var v = value;
    final thousand = BigInt.from(1000);
    while (v > BigInt.zero) {
      groups.add((v % thousand).toInt());
      v = v ~/ thousand;
    }
    final out = <String>[];
    for (var i = groups.length - 1; i >= 0; i--) {
      if (groups[i] == 0) continue;
      final scale = i < scales.length ? scales[i] : '';
      out.add('${threeDigits(groups[i])}$scale');
    }
    return out.join(' ');
  }
}

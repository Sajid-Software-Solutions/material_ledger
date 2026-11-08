/// R39 Accounts Workspace V2 — tax-invoice PDF builder.
///
/// Renders the server-frozen invoice document model to A4 portrait pages laid
/// out as the signed Yorks invoices (and the approved prototype): letterhead,
/// TAX INVOICE, bill-to / invoice / project boxes, stage rows a–e, amount in
/// words, notes, totals and signatures; then the Main Summary (with VAT and
/// grand-total rows), the summary by building and the per-building breakdown.
///
/// It prints only the snapshot's values and never recomputes money. The only
/// render-time derivations are display text: the amount in words and
/// percentages of the contract. Fonts match the register export (bundled Noto
/// Sans + Noto Sans Arabic).
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/accounts_decimal.dart';
import '../../domain/v2/client_invoice_document_models.dart';

abstract final class YorksClientInvoiceDocumentBuilder {
  static const _navy = 0xFF0F1E3A;
  static const _ink = 0xFF16202F;
  static const _muted = 0xFF45526A;
  static const _faint = 0xFF6B778C;
  static const _line = 0xFFC9D1DD;
  static const _band = 0xFFF1F4F7;

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
    pw.MemoryImage? emblem;
    try {
      final bytes = await rootBundle.load(
        'assets/branding/yorks_emblem_web.png',
      );
      emblem = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {
      emblem = null;
    }

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        fontFallback: [arabic],
      ),
    );
    final hasSummary = doc.summary != null && doc.buildings.isNotEmpty;
    final pages = !hasSummary ? 1 : (doc.buildings.length > 1 ? 3 : 2);
    final ctx = _Ctx(doc, emblem, arabic, pages);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
        footer: ctx.footer,
        build: (context) => [
          ...ctx.pageOne(),
          if (hasSummary) ...[
            pw.NewPage(),
            ...ctx.pageTwo(),
            if (pages > 2) ...[pw.NewPage(), ...ctx.pageThree()],
          ],
        ],
      ),
    );
    return pdf.save();
  }

  // ─── Formatting (display only) ──────────────────────────────────────────

  static String money(YorksAccountsDecimal? value) {
    if (value == null) return '—';
    final raw = value.canonicalText;
    final negative = raw.startsWith('-');
    final parts = (negative ? raw.substring(1) : raw).split('.');
    final whole = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    var fraction = parts.length == 1 ? '00' : parts[1].padRight(2, '0');
    if (fraction.length > 2) fraction = fraction.substring(0, 2);
    return '${negative ? '-' : ''}$whole.$fraction';
  }

  static double number(YorksAccountsDecimal? value) =>
      value == null ? 0 : double.tryParse(value.canonicalText) ?? 0;

  static String pct(double value, [int digits = 2]) =>
      '${value.toStringAsFixed(digits)}%';

  /// `19.01.2026`, as on the signed invoices.
  static String dotDate(String? iso) {
    if (iso == null || iso.length < 10) return '—';
    return '${iso.substring(8, 10)}.${iso.substring(5, 7)}.${iso.substring(0, 4)}';
  }

  static String? text(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// "UAE Dirham Six Million … Seventy Seven & 33/100 Only".
  static String amountInWords(YorksAccountsDecimal total) {
    final raw = total.canonicalText;
    final parts = raw.split('.');
    final whole = BigInt.tryParse(parts.first) ?? BigInt.zero;
    final cents = parts.length == 1
        ? 0
        : int.parse(parts[1].padRight(2, '0').substring(0, 2));
    final words = whole == BigInt.zero ? 'Zero' : _words(whole);
    final fils = cents == 0 ? '' : ' & ${cents.toString().padLeft(2, '0')}/100';
    return 'UAE Dirham $words$fils Only';
  }

  static String _words(BigInt value) {
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
    String three(int n) {
      final buf = <String>[];
      if (n >= 100) {
        buf.add('${ones[n ~/ 100]} Hundred');
        n %= 100;
      }
      if (n >= 20) {
        buf.add(tens[n ~/ 10] + (n % 10 > 0 ? ' ${ones[n % 10]}' : ''));
      } else if (n > 0) {
        buf.add(ones[n]);
      }
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
      out.add('${three(groups[i])}${i < scales.length ? scales[i] : ''}');
    }
    return out.join(' ');
  }
}

/// One rendering pass over a document.
final class _Ctx {
  _Ctx(this.doc, this.emblem, this.arabic, this.pages);

  final YorksClientInvoiceDocumentModel doc;
  final pw.MemoryImage? emblem;
  final pw.Font arabic;
  final int pages;

  static const _letters = 'abcdefghijklmnopqrstuvwxyz';

  String get _currency => doc.currencyCode ?? 'AED';
  Map<String, dynamic> get _c => doc.company;
  String? _s(Object? v) => YorksClientInvoiceDocumentBuilder.text(v);
  String _m(YorksAccountsDecimal? v) =>
      YorksClientInvoiceDocumentBuilder.money(v);
  double _n(YorksAccountsDecimal? v) =>
      YorksClientInvoiceDocumentBuilder.number(v);

  double get _contract => _n(doc.contractValue ?? doc.summary?.contractTotal);

  String _ofContract(YorksAccountsDecimal? v) => _contract > 0
      ? YorksClientInvoiceDocumentBuilder.pct(_n(v) / _contract * 100)
      : '—';

  String get _legalName =>
      _s(_c['legal_name']) ?? 'Yorks Air Conditioning & Refrigeration LLC-SPC';

  String get _contractNo =>
      _s(doc.references['contract_number']) ??
      _s(doc.project['contract_reference']) ??
      '';

  String get _projectRef => _s(doc.project['project_ref']) ?? '';
  String get _woNo => _s(doc.references['work_order_number']) ?? '—';

  pw.TextStyle _st(
    double size, {
    bool bold = false,
    int color = YorksClientInvoiceDocumentBuilder._ink,
    double? spacing,
  }) => pw.TextStyle(
    fontSize: size,
    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    color: PdfColor.fromInt(color),
    letterSpacing: spacing,
  );

  // ─── Page 1: the tax invoice ─────────────────────────────────────────────

  List<pw.Widget> pageOne() => [
    _letterhead(),
    pw.SizedBox(height: 10),
    _title(),
    pw.SizedBox(height: 10),
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: _billToBox()),
        pw.SizedBox(width: 10),
        pw.Expanded(child: _invoiceBox()),
      ],
    ),
    pw.SizedBox(height: 8),
    _projectBox(),
    pw.SizedBox(height: 10),
    _itemsTable(),
    pw.SizedBox(height: 10),
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(flex: 3, child: _wordsAndNotes()),
        pw.SizedBox(width: 14),
        pw.Expanded(flex: 2, child: _totalsBox()),
      ],
    ),
    pw.SizedBox(height: 26),
    _signatures(),
  ];

  pw.Widget _letterhead() {
    final arabicName = _s(_c['arabic_name']);
    return pw.Column(
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('YORKS', style: _st(20, bold: true, spacing: 2)),
                  pw.Text(
                    'Airconditioning & Refrigeration LLC-SPC',
                    style: _st(
                      9,
                      color: YorksClientInvoiceDocumentBuilder._muted,
                    ),
                  ),
                ],
              ),
            ),
            if (emblem != null)
              pw.SizedBox(width: 54, height: 54, child: pw.Image(emblem!)),
            pw.Expanded(
              child: arabicName == null
                  ? pw.SizedBox()
                  : pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text(
                        arabicName,
                        textDirection: pw.TextDirection.rtl,
                        style: pw.TextStyle(font: arabic, fontSize: 12),
                      ),
                    ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Container(
          height: 1.4,
          color: PdfColor.fromInt(YorksClientInvoiceDocumentBuilder._navy),
        ),
      ],
    );
  }

  pw.Widget _title() => pw.Column(
    children: [
      pw.Text('TAX INVOICE', style: _st(16, bold: true, spacing: 3)),
      pw.Text(
        'فاتورة ضريبية',
        textDirection: pw.TextDirection.rtl,
        style: pw.TextStyle(
          font: arabic,
          fontSize: 9,
          color: PdfColor.fromInt(YorksClientInvoiceDocumentBuilder._muted),
        ),
      ),
    ],
  );

  pw.Widget _box(String heading, pw.Widget body) => pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border.all(
        color: PdfColor.fromInt(YorksClientInvoiceDocumentBuilder._line),
        width: 0.6,
      ),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          color: PdfColor.fromInt(YorksClientInvoiceDocumentBuilder._band),
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: pw.Text(
            heading.toUpperCase(),
            style: _st(
              7.5,
              bold: true,
              color: YorksClientInvoiceDocumentBuilder._muted,
              spacing: 0.8,
            ),
          ),
        ),
        pw.Padding(padding: const pw.EdgeInsets.all(8), child: body),
      ],
    ),
  );

  pw.Widget _kv(List<(String, String)> rows, {double labelWidth = 62}) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final (k, v) in rows)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: labelWidth,
                    child: pw.Text(
                      k,
                      style: _st(
                        8,
                        color: YorksClientInvoiceDocumentBuilder._faint,
                      ),
                    ),
                  ),
                  pw.Expanded(child: pw.Text(v, style: _st(8.5, bold: true))),
                ],
              ),
            ),
        ],
      );

  pw.Widget _billToBox() {
    final name = _s(doc.billTo['name']) ?? '—';
    final address = _s(doc.billTo['address']);
    return _box(
      'Bill to',
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(name, style: _st(10, bold: true)),
          if (address != null)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 1, bottom: 4),
              child: pw.Text(
                address,
                style: _st(
                  8.5,
                  color: YorksClientInvoiceDocumentBuilder._muted,
                ),
              ),
            )
          else
            pw.SizedBox(height: 4),
          _kv([
            ('TRN', _s(doc.references['client_trn']) ?? '—'),
            ('Attention', _s(doc.settings['attention_name']) ?? '—'),
          ]),
        ],
      ),
    );
  }

  pw.Widget _invoiceBox() {
    final terms = doc.paymentTermsDays;
    return _box(
      'Invoice',
      _kv([
        ('Invoice no.', doc.invoiceReference),
        (
          'Invoice date',
          YorksClientInvoiceDocumentBuilder.dotDate(doc.invoiceDate),
        ),
        (
          'Due date',
          '${YorksClientInvoiceDocumentBuilder.dotDate(doc.dueDate)}'
              '${terms == null ? '' : ' ($terms days)'}',
        ),
        ('Yorks TRN', _s(_c['trn']) ?? '—'),
      ], labelWidth: 70),
    );
  }

  pw.Widget _projectBox() {
    final name = _s(doc.project['name']) ?? '';
    final project = _contractNo.isEmpty || name.startsWith(_contractNo)
        ? name
        : '$_contractNo — $name';
    return _box(
      'Project',
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 3,
            child: _kv([('Project', project), ('Yorks ref.', _projectRef)]),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            flex: 2,
            child: _kv([
              ('Work order', _woNo),
              (
                'WO date',
                YorksClientInvoiceDocumentBuilder.dotDate(
                  _s(doc.references['work_order_date']),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  pw.Widget _cell(
    String value, {
    bool right = false,
    bool bold = false,
    double size = 8.5,
    int color = YorksClientInvoiceDocumentBuilder._ink,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
    child: pw.Text(
      value,
      textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
      style: _st(size, bold: bold, color: color),
    ),
  );

  pw.TableRow _head(List<String> labels, Set<int> numeric) => pw.TableRow(
    decoration: pw.BoxDecoration(
      color: PdfColor.fromInt(YorksClientInvoiceDocumentBuilder._navy),
    ),
    children: [
      for (final (i, l) in labels.indexed)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: pw.Text(
            l,
            textAlign: numeric.contains(i)
                ? pw.TextAlign.right
                : pw.TextAlign.left,
            style: _st(7.5, bold: true, color: 0xFFFFFFFF),
          ),
        ),
    ],
  );

  pw.TableBorder get _border => pw.TableBorder(
    horizontalInside: pw.BorderSide(
      color: PdfColor.fromInt(YorksClientInvoiceDocumentBuilder._line),
      width: 0.5,
    ),
    bottom: pw.BorderSide(
      color: PdfColor.fromInt(YorksClientInvoiceDocumentBuilder._line),
      width: 0.5,
    ),
  );

  pw.BoxDecoration get _sumBand => pw.BoxDecoration(
    color: PdfColor.fromInt(YorksClientInvoiceDocumentBuilder._band),
  );

  pw.Widget _itemsTable() {
    final stages =
        doc.summary?.stages ?? const <YorksClientInvoiceSummaryStage>[];
    final zero = YorksClientInvoiceDocumentBuilder._faint;
    final scope = _s(doc.settings['scope_line']);
    return pw.Table(
      border: _border,
      columnWidths: const {
        0: pw.FixedColumnWidth(32),
        1: pw.FlexColumnWidth(),
        2: pw.FixedColumnWidth(58),
        3: pw.FixedColumnWidth(82),
        4: pw.FixedColumnWidth(58),
        5: pw.FixedColumnWidth(86),
      },
      children: [
        _head(
          const [
            'Item',
            'Description',
            'Contract %',
            'Contract (AED)',
            'This inv. %',
            'This invoice (AED)',
          ],
          const {2, 3, 4, 5},
        ),
        if (scope != null)
          pw.TableRow(
            children: [
              _cell(''),
              _cell(scope, bold: true),
              _cell(''),
              _cell(''),
              _cell(''),
              _cell(''),
            ],
          ),
        if (stages.isEmpty)
          for (final line in doc.lines)
            pw.TableRow(
              children: [
                _cell(''),
                _cell(
                  '${line.buildingName} — ${line.stageLabel ?? line.stageKey}',
                ),
                _cell(''),
                _cell(''),
                _cell(_ofContract(line.amount), right: true),
                _cell(_m(line.amount), right: true),
              ],
            )
        else
          for (final (i, s) in stages.indexed)
            pw.TableRow(
              children: [
                _cell('${_letters[i % _letters.length]}.'),
                _cell(s.stageLabel ?? s.stageKey),
                _cell(
                  YorksClientInvoiceDocumentBuilder.pct(
                    _n(s.contractPercent),
                    0,
                  ),
                  right: true,
                ),
                _cell(_m(s.contractAmount), right: true),
                _cell(
                  _n(s.thisAmount) > 0.004 ? _ofContract(s.thisAmount) : '—',
                  right: true,
                  color: _n(s.thisAmount) > 0.004
                      ? YorksClientInvoiceDocumentBuilder._ink
                      : zero,
                ),
                _cell(
                  _n(s.thisAmount) > 0.004 ? _m(s.thisAmount) : '—',
                  right: true,
                  color: _n(s.thisAmount) > 0.004
                      ? YorksClientInvoiceDocumentBuilder._ink
                      : zero,
                ),
              ],
            ),
        pw.TableRow(
          decoration: _sumBand,
          children: [
            _cell(''),
            _cell('TOTAL', bold: true),
            _cell(stages.isEmpty ? '' : '100%', right: true, bold: true),
            _cell(
              doc.contractValue == null ? '' : _m(doc.contractValue),
              right: true,
              bold: true,
            ),
            _cell(_ofContract(doc.amounts.exVat), right: true, bold: true),
            _cell(_m(doc.amounts.exVat), right: true, bold: true),
          ],
        ),
      ],
    );
  }

  pw.Widget _wordsAndNotes() {
    final bank = _s(_c['bank_name']);
    final iban = _s(_c['bank_iban']);
    final account = _s(_c['bank_account_name']);
    final terms = doc.paymentTermsDays;
    final payTo = [
      ?bank,
      if (iban != null) 'IBAN $iban',
      if (account != null) 'Account name: $account',
    ].join(', ');
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(7),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromInt(YorksClientInvoiceDocumentBuilder._band),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'AMOUNT IN WORDS',
                style: _st(
                  6.5,
                  bold: true,
                  color: YorksClientInvoiceDocumentBuilder._faint,
                  spacing: 0.8,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                YorksClientInvoiceDocumentBuilder.amountInWords(
                  doc.amounts.totalInclVat,
                ),
                style: _st(8.5, bold: true),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Text('Notes', style: _st(8.5, bold: true)),
        pw.SizedBox(height: 2),
        for (final (i, note) in [
          'We certify that the contents are true and correct.',
          if (payTo.isNotEmpty)
            'Payment to be transferred to our account: $payTo.',
          if (terms != null) 'Terms of payment: $terms days by bank transfer.',
        ].indexed)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 1.5),
            child: pw.Text(
              '${i + 1}. $note',
              style: _st(8, color: YorksClientInvoiceDocumentBuilder._muted),
            ),
          ),
      ],
    );
  }

  pw.Widget _totalsBox() {
    final a = doc.amounts;
    final rate = a.vatRatePercent.displayText(maximumFractionDigits: 2);
    pw.Widget row(String l, String v, {bool strong = false}) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: strong
          ? pw.BoxDecoration(
              color: PdfColor.fromInt(YorksClientInvoiceDocumentBuilder._navy),
            )
          : null,
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              l,
              style: _st(
                8.5,
                bold: strong,
                color: strong
                    ? 0xFFFFFFFF
                    : YorksClientInvoiceDocumentBuilder._ink,
              ),
            ),
          ),
          pw.Text(
            v,
            style: _st(
              strong ? 10 : 8.5,
              bold: true,
              color: strong
                  ? 0xFFFFFFFF
                  : YorksClientInvoiceDocumentBuilder._ink,
            ),
          ),
        ],
      ),
    );
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: PdfColor.fromInt(YorksClientInvoiceDocumentBuilder._line),
          width: 0.6,
        ),
      ),
      child: pw.Column(
        children: [
          row('Gross total', _m(a.exVat)),
          row('Add: VAT $rate%', _m(a.vat)),
          row('Net payable ($_currency)', _m(a.totalInclVat), strong: true),
        ],
      ),
    );
  }

  pw.Widget _signatures() {
    pw.Widget area(String who, String what) => pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 30),
          pw.Container(
            height: 0.6,
            color: PdfColor.fromInt(YorksClientInvoiceDocumentBuilder._muted),
          ),
          pw.SizedBox(height: 3),
          pw.Text(who, style: _st(8, bold: true)),
          pw.Text(
            what,
            style: _st(7.5, color: YorksClientInvoiceDocumentBuilder._muted),
          ),
        ],
      ),
    );
    final client = _s(doc.billTo['name']) ?? 'Client';
    return pw.Row(
      children: [
        area('Received by — $client', 'Name, signature, stamp & date'),
        pw.SizedBox(width: 40),
        area('For, $_legalName', 'Authorised signatory & stamp'),
      ],
    );
  }

  // ─── Page header for summary pages ───────────────────────────────────────

  pw.Widget _miniHeader(String title) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (emblem != null)
            pw.Padding(
              padding: const pw.EdgeInsets.only(right: 6),
              child: pw.SizedBox(
                width: 22,
                height: 22,
                child: pw.Image(emblem!),
              ),
            ),
          pw.Text('YORKS ', style: _st(10, bold: true)),
          pw.Text(
            'Airconditioning & Refrigeration LLC-SPC',
            style: _st(7.5, color: YorksClientInvoiceDocumentBuilder._muted),
          ),
          pw.Spacer(),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(doc.invoiceReference, style: _st(9, bold: true)),
              pw.Text(
                YorksClientInvoiceDocumentBuilder.dotDate(doc.invoiceDate),
                style: _st(
                  7.5,
                  color: YorksClientInvoiceDocumentBuilder._muted,
                ),
              ),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Container(
        height: 0.8,
        color: PdfColor.fromInt(YorksClientInvoiceDocumentBuilder._navy),
      ),
      pw.SizedBox(height: 8),
      _sectionTitle(
        title,
        [
          if (_contractNo.isNotEmpty) _contractNo,
          if (_projectRef.isNotEmpty) 'Yorks Ref. $_projectRef',
          if (_woNo != '—') 'WO $_woNo',
        ].join(' · '),
      ),
      pw.SizedBox(height: 6),
    ],
  );

  pw.Widget _sectionTitle(String title, String side) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [
      pw.Text(title, style: _st(10.5, bold: true, spacing: 1)),
      pw.Spacer(),
      pw.Text(
        side,
        style: _st(7.5, color: YorksClientInvoiceDocumentBuilder._muted),
      ),
    ],
  );

  // ─── Page 2: main summary and summary by building ────────────────────────

  List<pw.Widget> pageTwo() {
    final s = doc.summary!;
    final rate = doc.amounts.vatRatePercent.displayText(
      maximumFractionDigits: 2,
    );
    String amt(YorksAccountsDecimal? v) =>
        v == null ? '' : (_n(v).abs() > 0.004 ? _m(v) : '0.00');
    String ofc(YorksAccountsDecimal v) =>
        _n(v).abs() > 0.004 ? _ofContract(v) : '0.00%';
    final numeric = {1, 2, 3, 4, 5, 6, 7, 8};
    return [
      _miniHeader('MAIN SUMMARY — ALL BUILDINGS'),
      pw.Table(
        border: _border,
        columnWidths: const {
          0: pw.FlexColumnWidth(),
          1: pw.FixedColumnWidth(32),
          2: pw.FixedColumnWidth(62),
          3: pw.FixedColumnWidth(40),
          4: pw.FixedColumnWidth(58),
          5: pw.FixedColumnWidth(40),
          6: pw.FixedColumnWidth(58),
          7: pw.FixedColumnWidth(40),
          8: pw.FixedColumnWidth(60),
        },
        children: [
          // Each % sits before its amount, as the workbook's paired columns.
          _head(const [
            'Description',
            '%',
            'Contract',
            '%',
            'Till previous',
            '%',
            'This month',
            '%',
            'Total completion',
          ], numeric),
          for (final (i, st) in s.stages.indexed)
            pw.TableRow(
              children: [
                _cell(
                  '${_letters[i % _letters.length]}. ${st.stageLabel ?? st.stageKey}',
                  size: 8,
                ),
                _cell(
                  YorksClientInvoiceDocumentBuilder.pct(
                    _n(st.contractPercent),
                    0,
                  ),
                  right: true,
                  size: 8,
                ),
                _cell(_m(st.contractAmount), right: true, size: 8),
                _cell(ofc(st.previousAmount), right: true, size: 8),
                _cell(amt(st.previousAmount), right: true, size: 8),
                _cell(ofc(st.thisAmount), right: true, size: 8),
                _cell(amt(st.thisAmount), right: true, size: 8),
                _cell(ofc(st.totalAmount), right: true, size: 8),
                _cell(amt(st.totalAmount), right: true, size: 8),
              ],
            ),
          pw.TableRow(
            decoration: _sumBand,
            children: [
              _cell('Sub total', bold: true, size: 8),
              _cell('100%', right: true, bold: true, size: 8),
              _cell(_m(s.contractTotal), right: true, bold: true, size: 8),
              _cell(ofc(s.previousTotal), right: true, bold: true, size: 8),
              _cell(amt(s.previousTotal), right: true, bold: true, size: 8),
              _cell(ofc(s.thisTotal), right: true, bold: true, size: 8),
              _cell(amt(s.thisTotal), right: true, bold: true, size: 8),
              _cell(ofc(s.totalTotal), right: true, bold: true, size: 8),
              _cell(amt(s.totalTotal), right: true, bold: true, size: 8),
            ],
          ),
          if (s.hasVatRows) ...[
            pw.TableRow(
              children: [
                _cell('VAT $rate%', size: 8),
                _cell('', size: 8),
                _cell(amt(s.contractVat), right: true, size: 8),
                _cell('', size: 8),
                _cell(amt(s.previousVat), right: true, size: 8),
                _cell('', size: 8),
                _cell(amt(s.thisVat), right: true, size: 8),
                _cell('', size: 8),
                _cell(amt(s.totalVat), right: true, size: 8),
              ],
            ),
            pw.TableRow(
              decoration: _sumBand,
              children: [
                _cell('Grand total', bold: true, size: 8),
                _cell('', size: 8),
                _cell(amt(s.contractGrand), right: true, bold: true, size: 8),
                _cell('', size: 8),
                _cell(amt(s.previousGrand), right: true, bold: true, size: 8),
                _cell('', size: 8),
                _cell(amt(s.thisGrand), right: true, bold: true, size: 8),
                _cell('', size: 8),
                _cell(amt(s.totalGrand), right: true, bold: true, size: 8),
              ],
            ),
          ],
        ],
      ),
      pw.SizedBox(height: 16),
      _sectionTitle('SUMMARY BY BUILDING', 'Amounts excl. VAT'),
      pw.SizedBox(height: 6),
      pw.Table(
        border: _border,
        columnWidths: const {
          0: pw.FlexColumnWidth(),
          1: pw.FixedColumnWidth(40),
          2: pw.FixedColumnWidth(74),
          3: pw.FixedColumnWidth(74),
          4: pw.FixedColumnWidth(74),
          5: pw.FixedColumnWidth(74),
          6: pw.FixedColumnWidth(46),
        },
        children: [
          _head(
            const [
              'Building',
              'Share',
              'Building value',
              'Till previous',
              'This month',
              'Total',
              'Done',
            ],
            const {1, 2, 3, 4, 5, 6},
          ),
          for (final b in doc.buildings)
            pw.TableRow(
              children: [
                _cell(b.name, bold: true),
                _cell(
                  YorksClientInvoiceDocumentBuilder.pct(_n(b.sharePercent), 0),
                  right: true,
                ),
                _cell(_m(b.buildingValue), right: true),
                _cell(_m(b.previousAmount), right: true),
                _cell(_m(b.thisAmount), right: true),
                _cell(_m(b.totalAmount), right: true),
                _cell(
                  YorksClientInvoiceDocumentBuilder.pct(b.donePercent),
                  right: true,
                ),
              ],
            ),
          pw.TableRow(
            decoration: _sumBand,
            children: [
              _cell('Total', bold: true),
              _cell('100%', right: true, bold: true),
              _cell(_m(s.contractTotal), right: true, bold: true),
              _cell(_m(s.previousTotal), right: true, bold: true),
              _cell(_m(s.thisTotal), right: true, bold: true),
              _cell(_m(s.totalTotal), right: true, bold: true),
              _cell(_ofContract(s.totalTotal), right: true, bold: true),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 14),
      pw.Row(
        children: [
          pw.Expanded(
            child: _figureBox('THIS INVOICE (EXCL. VAT)', _m(s.thisTotal)),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: _figureBox(
              'CUMULATIVE INVOICED TO DATE (EXCL. VAT)',
              '${_m(s.totalTotal)} · ${_ofContract(s.totalTotal)}',
            ),
          ),
        ],
      ),
    ];
  }

  pw.Widget _figureBox(String label, String value) => pw.Container(
    padding: const pw.EdgeInsets.all(7),
    decoration: pw.BoxDecoration(
      color: PdfColor.fromInt(YorksClientInvoiceDocumentBuilder._band),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: _st(
            6.5,
            bold: true,
            color: YorksClientInvoiceDocumentBuilder._faint,
            spacing: 0.8,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(value, style: _st(10, bold: true)),
      ],
    ),
  );

  // ─── Page 3: breakdown per building ──────────────────────────────────────

  List<pw.Widget> pageThree() {
    final out = <pw.Widget>[_miniHeader('BREAKDOWN PER BUILDING')];
    for (final (bi, b) in doc.buildings.indexed) {
      final letter = String.fromCharCode(65 + (bi % 26));
      String done(YorksAccountsDecimal total, YorksAccountsDecimal value) =>
          _n(value) > 0
          ? YorksClientInvoiceDocumentBuilder.pct(
              _n(total) / _n(value) * 100,
              1,
            )
          : '—';
      out
        ..add(
          pw.Table(
            border: _border,
            columnWidths: const {
              0: pw.FlexColumnWidth(),
              1: pw.FixedColumnWidth(74),
              2: pw.FixedColumnWidth(74),
              3: pw.FixedColumnWidth(74),
              4: pw.FixedColumnWidth(74),
              5: pw.FixedColumnWidth(42),
            },
            children: [
              _head(
                [
                  '$letter · ${b.name} — '
                      '${YorksClientInvoiceDocumentBuilder.pct(_n(b.sharePercent), 0)} of contract',
                  'Contract',
                  'Till previous',
                  'This month',
                  'Total',
                  'Done',
                ],
                const {1, 2, 3, 4, 5},
              ),
              for (final (i, st) in b.stages.indexed)
                pw.TableRow(
                  children: [
                    _cell('$letter.${i + 1}  ${st.stageLabel ?? st.stageKey}'),
                    _cell(_m(st.stageValue), right: true),
                    _cell(_m(st.previousAmount), right: true),
                    _cell(_m(st.thisAmount), right: true),
                    _cell(_m(st.totalAmount), right: true),
                    _cell(done(st.totalAmount, st.stageValue), right: true),
                  ],
                ),
              pw.TableRow(
                decoration: _sumBand,
                children: [
                  _cell('Total ${b.name}', bold: true),
                  _cell(_m(b.buildingValue), right: true, bold: true),
                  _cell(_m(b.previousAmount), right: true, bold: true),
                  _cell(_m(b.thisAmount), right: true, bold: true),
                  _cell(_m(b.totalAmount), right: true, bold: true),
                  _cell(
                    done(b.totalAmount, b.buildingValue),
                    right: true,
                    bold: true,
                  ),
                ],
              ),
            ],
          ),
        )
        ..add(pw.SizedBox(height: 10));
    }
    return out;
  }

  // ─── Footer on every page ────────────────────────────────────────────────

  pw.Widget footer(pw.Context context) {
    final parts = <String>[
      if (_s(_c['phone']) != null) 'Tel ${_s(_c['phone'])}',
      if (_s(_c['fax']) != null) 'Fax ${_s(_c['fax'])}',
      if (_s(_c['address']) != null) _s(_c['address'])!,
      if (_s(_c['email']) != null) _s(_c['email'])!,
    ];
    final style = _st(7, color: YorksClientInvoiceDocumentBuilder._faint);
    return pw.Column(
      children: [
        pw.Container(
          height: 0.5,
          color: PdfColor.fromInt(YorksClientInvoiceDocumentBuilder._line),
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          children: [
            pw.Text(doc.invoiceReference, style: style),
            pw.Expanded(
              child: pw.Text(
                parts.join(' · '),
                textAlign: pw.TextAlign.center,
                style: style,
              ),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: style,
            ),
          ],
        ),
      ],
    );
  }
}

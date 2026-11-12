/// Workforce attendance V2 — the monthly DAILY TIME SHEET as PDF/print (one
/// page per worker, the paper layout) and as an Excel register (one row per
/// worker per entered day). Built only from the server's month sheet.
library;

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../domain/attendance_models.dart';
import '../domain/attendance_time.dart';

class YorksAttendanceSheetService {
  const YorksAttendanceSheetService();

  static const xlsxMimeType =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  static const pdfMimeType = 'application/pdf';

  String fileStem(AttendanceMonthSheet sheet) {
    final crew = sheet.crew.name
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+$'), '');
    final month = DateFormat(
      'MMMM-y',
    ).format(attendanceDate(sheet.month.month));
    return 'Yorks-time-sheet-$crew-$month';
  }

  static String _status(AttendanceRow row) => switch (row.status) {
    AttendanceStatus.present => 'Present',
    AttendanceStatus.absent => 'Absent',
    AttendanceStatus.rest => 'Rest day',
    AttendanceStatus.annualLeave => 'Annual leave',
    AttendanceStatus.sickLeave => 'Sick leave',
    AttendanceStatus.officialLeave => 'Official leave',
    AttendanceStatus.unpaidLeave => 'Unpaid leave',
    null => '',
  };

  static bool _holiday(AttendanceMonthSheet sheet, String date) =>
      sheet.month.days.where((d) => d.date == date).firstOrNull?.holiday ??
      false;

  // ─── Excel ────────────────────────────────────────────────────────────────

  Uint8List buildExcel(AttendanceMonthSheet sheet) {
    const headings = [
      'Worker',
      'Emp ID',
      'Designation',
      'Crew',
      'Date',
      'Day',
      'Status',
      'In',
      'Break',
      'Back',
      'Out',
      'Hours',
      'OT normal',
      'OT holiday',
      'Project',
      'Entered by',
      'Month confirmed',
    ];
    final confirmed = switch (sheet.month.state) {
      AttendanceMonthState.notNeeded => 'Not needed',
      AttendanceMonthState.confirmed => 'Yes',
      _ => 'Not yet',
    };
    final rows = <List<Object>>[];
    for (final worker in sheet.workers) {
      for (final day in worker.days) {
        final minutes = day.row.minutes(holiday: _holiday(sheet, day.date));
        rows.add([
          worker.worker.name,
          worker.worker.number,
          worker.worker.designation,
          sheet.crew.name,
          day.date,
          DateFormat('EEEE').format(attendanceDate(day.date)),
          _status(day.row),
          formatAttendanceTime(day.row.start),
          formatAttendanceTime(day.row.breakStart),
          formatAttendanceTime(day.row.breakFinish),
          formatAttendanceTime(day.row.finish),
          minutes.worked / 60,
          minutes.normalOvertime / 60,
          minutes.holidayOvertime / 60,
          day.row.workLabel ?? sheet.crew.workLabel,
          sheet.enteredBy[day.date]?.by ?? '',
          confirmed,
        ]);
      }
    }
    return _xlsx('Time sheet', headings, rows);
  }

  static Uint8List _xlsx(
    String sheetName,
    List<String> headings,
    List<List<Object>> rows,
  ) {
    String escape(String value) => value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
    String column(int index) {
      var n = index;
      var name = '';
      do {
        name = String.fromCharCode(65 + n % 26) + name;
        n = n ~/ 26 - 1;
      } while (n >= 0);
      return name;
    }

    String cell(int col, int row, Object value) {
      final ref = '${column(col)}$row';
      if (value is num) {
        final rounded = (value * 100).round() / 100;
        return '<c r="$ref"><v>$rounded</v></c>';
      }
      return '<c r="$ref" t="inlineStr"><is><t xml:space="preserve">'
          '${escape(value.toString())}</t></is></c>';
    }

    final buffer = StringBuffer()
      ..write('<row r="1">')
      ..writeAll([
        for (var c = 0; c < headings.length; c++) cell(c, 1, headings[c]),
      ])
      ..write('</row>');
    for (var r = 0; r < rows.length; r++) {
      buffer
        ..write('<row r="${r + 2}">')
        ..writeAll([
          for (var c = 0; c < rows[r].length; c++) cell(c, r + 2, rows[r][c]),
        ])
        ..write('</row>');
    }
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
              '<sheets><sheet name="${escape(sheetName)}" sheetId="1" r:id="rId1"/></sheets>'
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
              '<worksheet xmlns="$ns"><sheetViews><sheetView workbookViewId="0">'
              '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
              '</sheetView></sheetViews>'
              '<sheetData>$buffer</sheetData></worksheet>',
        ),
      );
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  // ─── PDF ──────────────────────────────────────────────────────────────────

  Future<Uint8List> buildPdf(
    AttendanceMonthSheet sheet, {
    List<AttendanceSheetWorker>? workers,
  }) async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
    final document = pw.Document(
      title: fileStem(sheet),
      subject: 'Yorks DAILY TIME SHEET',
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    for (final worker in workers ?? sheet.workers) {
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(24, 26, 24, 22),
          build: (_) => _paper(sheet, worker),
        ),
      );
    }
    return document.save();
  }

  Future<void> printPdf(
    AttendanceMonthSheet sheet, {
    List<AttendanceSheetWorker>? workers,
  }) async {
    final bytes = await buildPdf(sheet, workers: workers);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: fileStem(sheet),
    );
  }

  static pw.Widget _paper(
    AttendanceMonthSheet sheet,
    AttendanceSheetWorker worker,
  ) {
    final monthStart = attendanceDate(sheet.month.month);
    final last = attendanceDate(sheet.month.lastDay);
    final byDate = {for (final day in worker.days) day.date: day.row};
    const small = pw.TextStyle(fontSize: 7.5);
    final boldSmall = pw.TextStyle(
      fontSize: 7.5,
      fontWeight: pw.FontWeight.bold,
    );
    pw.Widget c(String text, {bool bold = false, pw.Alignment? align}) =>
        pw.Container(
          alignment: align ?? pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2.2),
          child: pw.Text(text, style: bold ? boldSmall : small),
        );

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          c('Date', bold: true),
          c('Day', bold: true),
          c('In', bold: true),
          c('Brk', bold: true),
          c('In', bold: true),
          c('Out', bold: true),
          c('Nor.', bold: true, align: pw.Alignment.centerRight),
          c('Hol.', bold: true, align: pw.Alignment.centerRight),
          c('Project name', bold: true),
          c('Status', bold: true),
        ],
      ),
    ];
    var presentDays = 0;
    var regular = 0;
    var normalOt = 0;
    var holidayOt = 0;
    final weekTakers = <String>{};
    for (
      var date = monthStart;
      !date.isAfter(last);
      date = date.add(const Duration(days: 1))
    ) {
      final iso = attendanceIso(date);
      final row = byDate[iso];
      final holiday = _holiday(sheet, iso);
      final minutes = row?.minutes(holiday: holiday);
      if (row?.status == AttendanceStatus.present) presentDays++;
      regular += minutes?.regular ?? 0;
      normalOt += minutes?.normalOvertime ?? 0;
      holidayOt += minutes?.holidayOvertime ?? 0;
      final entry = sheet.enteredBy[iso];
      if (entry != null) weekTakers.add(entry.by);
      final status = row == null
          ? (holiday ? '' : 'Not entered')
          : sheet.month.isConfirmed
          ? 'Confirmed'
          : (entry?.changed ?? false)
          ? 'Entered · changed'
          : 'Entered';
      final firstIn = row == null
          ? ''
          : row.status == AttendanceStatus.present
          ? formatAttendanceTime(row.start)
          : row.status == AttendanceStatus.rest
          ? ''
          : _status(row);
      rows.add(
        pw.TableRow(
          decoration: holiday
              ? const pw.BoxDecoration(color: PdfColors.grey100)
              : null,
          children: [
            c(DateFormat('d MMM').format(date)),
            c(DateFormat('EEEE').format(date)),
            c(
              firstIn,
              bold: row != null && row.status != AttendanceStatus.present,
            ),
            c(formatAttendanceTime(row?.breakStart)),
            c(formatAttendanceTime(row?.breakFinish)),
            c(formatAttendanceTime(row?.finish)),
            c(
              formatAttendanceHours(minutes?.normalOvertime ?? 0),
              align: pw.Alignment.centerRight,
            ),
            c(
              formatAttendanceHours(minutes?.holidayOvertime ?? 0),
              align: pw.Alignment.centerRight,
            ),
            c(row == null ? '' : (row.workLabel ?? sheet.crew.workLabel)),
            c(status),
          ],
        ),
      );
      if (date.weekday == DateTime.saturday || date == last) {
        rows.add(
          pw.TableRow(
            children: [
              pw.Container(),
              pw.Container(),
              pw.Container(),
              pw.Container(),
              pw.Container(),
              pw.Container(),
              pw.Container(),
              pw.Container(),
              c(
                'Site in-charge: ${weekTakers.isEmpty ? '—' : weekTakers.join(', ')}',
                bold: true,
              ),
              pw.Container(),
            ],
          ),
        );
        weekTakers.clear();
      }
    }
    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          c('Total', bold: true),
          c('$presentDays days present', bold: true),
          c(''),
          c(''),
          c(''),
          c(
            '${formatAttendanceHours(regular, zeroAsDash: true)} h',
            bold: true,
          ),
          c(
            formatAttendanceHours(normalOt, zeroAsDash: true),
            bold: true,
            align: pw.Alignment.centerRight,
          ),
          c(
            formatAttendanceHours(holidayOt, zeroAsDash: true),
            bold: true,
            align: pw.Alignment.centerRight,
          ),
          c(''),
          c(''),
        ],
      ),
    );

    pw.Widget field(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Center(
          child: pw.Text(
            'DAILY TIME SHEET',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Center(
          child: pw.Text(
            'Yorks Air Conditioning & Refrigeration',
            style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
          ),
        ),
        pw.SizedBox(height: 10),
        field('Name:', worker.worker.name),
        field('Log for the month of:', DateFormat('MMMM y').format(monthStart)),
        field('Emp. ID No.:', worker.worker.number),
        field('Designation:', worker.worker.designation),
        field(
          'Crew / project:',
          '${sheet.crew.name} · ${sheet.crew.workLabel}',
        ),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
          columnWidths: const {
            0: pw.FixedColumnWidth(38),
            1: pw.FixedColumnWidth(52),
            2: pw.FixedColumnWidth(48),
            3: pw.FixedColumnWidth(40),
            4: pw.FixedColumnWidth(40),
            5: pw.FixedColumnWidth(40),
            6: pw.FixedColumnWidth(28),
            7: pw.FixedColumnWidth(28),
            8: pw.FlexColumnWidth(),
            9: pw.FixedColumnWidth(58),
          },
          children: rows,
        ),
        pw.Spacer(),
        pw.Text(
          sheet.month.isConfirmed
              ? 'Month confirmed by ${sheet.month.confirmedBy ?? ''}.'
              : sheet.month.state == AttendanceMonthState.notNeeded
              ? 'No month confirmation needed for this crew.'
              : 'Not yet confirmed: figures can still change.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ],
    );
  }
}

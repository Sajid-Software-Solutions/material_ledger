/// Workforce attendance — one place's day on paper (owner request, 15
/// November 2026, PRODUCT_DECISIONS section 59): the day as saved, under the
/// company letterhead of every Yorks print, for anyone who may see the day.
/// Built only from the server's day; unsaved changes are never printed.
library;

import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../shared/services/yorks_v1_pdf_letterhead.dart';
import '../domain/attendance_models.dart';
import '../domain/attendance_time.dart';
import 'attendance_sheet_service.dart';

/// One labourer's line on the printed day.
typedef AttendanceDayPrintLine = ({
  String name,
  String number,
  String designation,
  String where,
  String status,
  String start,
  String breakStart,
  String breakFinish,
  String finish,
  int worked,
  int normalOvertime,
  int holidayOvertime,
  String savedBy,
});

class YorksAttendanceDayPrint {
  const YorksAttendanceDayPrint();

  /// `Yorks-attendance-YRA-322-DF3W-2026-11-12`.
  String fileStem(AttendanceDay day) {
    final place = day.crew.label
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'(^-+|-+$)'), '');
    return 'Yorks-attendance-$place-${day.date}';
  }

  /// A working day, a rest day (Sunday) or a named public holiday.
  static String dayType(AttendanceDay day) {
    if (!day.holiday) return 'Working day';
    final name = day.holidayName;
    return name == null ? 'Rest day' : 'Public holiday · $name';
  }

  /// The column for where each line was worked: the building at a
  /// project's place, else the project typed on the line.
  static String whereHeading(AttendanceCrew crew) =>
      crew.placeKind == 'project' ? 'Building' : 'Project';

  static String _where(AttendanceCrew crew, AttendanceRow row) {
    if (crew.placeKind != 'project') {
      return row.workLabel ?? (crew.isPlace ? '' : crew.workLabel);
    }
    return switch (row.workScopeName) {
      null => '',
      'Common / All Buildings' => 'Common',
      final building => building,
    };
  }

  /// The saved lines, in the order the day shows them.
  static List<AttendanceDayPrintLine> lines(AttendanceDay day) {
    final lines = <AttendanceDayPrintLine>[];
    for (final row in day.rows) {
      final status = row.status;
      if (status == null) continue;
      final minutes = row.minutes(holiday: day.holiday);
      final present = status == AttendanceStatus.present;
      String time(int? minute) => present ? formatAttendanceTime(minute) : '';
      lines.add((
        name: row.worker.name,
        number: row.worker.number,
        designation: row.worker.designation,
        where: _where(day.crew, row),
        status: attendancePrintStatus(status),
        start: time(row.start),
        breakStart: time(row.breakStart),
        breakFinish: time(row.breakFinish),
        finish: time(row.finish),
        worked: minutes.worked,
        normalOvertime: minutes.normalOvertime,
        holidayOvertime: minutes.holidayOvertime,
        savedBy: row.updatedBy ?? day.enteredBy ?? '',
      ));
    }
    return lines;
  }

  /// "2 present · 1 absent · 1 on leave", with rest days when any.
  static String summary(AttendanceDay day) {
    var present = 0;
    var absent = 0;
    var leave = 0;
    var rest = 0;
    for (final row in day.rows) {
      switch (row.status) {
        case AttendanceStatus.present:
          present++;
        case AttendanceStatus.absent:
          absent++;
        case AttendanceStatus.rest:
          rest++;
        case final status? when status.isLeave:
          leave++;
        default:
      }
    }
    return [
      '$present present',
      '$absent absent',
      '$leave on leave',
      if (rest > 0) rest == 1 ? '1 rest day' : '$rest rest days',
    ].join(' · ');
  }

  static String _stamp(DateTime? at) =>
      at == null ? '' : DateFormat('d MMM y, HH:mm').format(at.toLocal());

  /// What a change after entry did to a line: "from 6:30 AM–2:30 PM to
  /// Absent" (the print's font has no arrow).
  static String change(AttendanceChange change) {
    String describe(Map<String, dynamic>? data) {
      if (data == null) return 'Removed from the day';
      final status = AttendanceStatus.fromCode(data['status']);
      if (status == AttendanceStatus.present) {
        return '${formatAttendanceTime(data['start_minute'] as int?)}–'
            '${formatAttendanceTime(data['finish_minute'] as int?)}';
      }
      return attendancePrintStatus(status);
    }

    return '${change.by} · ${_stamp(change.at)}: ${change.workerName} from '
        '${describe(change.before)} to ${describe(change.after)} — '
        '${change.reason}';
  }

  Future<Uint8List> buildPdf(AttendanceDay day) async {
    final logo = await yorksV1PdfLogo();
    final document = pw.Document(
      title: fileStem(day),
      subject: 'Yorks DAILY ATTENDANCE',
      theme: await yorksV1PdfTheme(),
    );
    final printed = lines(day);
    const small = pw.TextStyle(fontSize: 7.5);
    final boldSmall = pw.TextStyle(
      fontSize: 7.5,
      fontWeight: pw.FontWeight.bold,
    );
    const muted = pw.TextStyle(fontSize: 6.8, color: PdfColors.grey700);
    pw.Widget c(String text, {bool bold = false, bool end = false}) =>
        pw.Container(
          alignment: end ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2.6),
          child: pw.Text(text, style: bold ? boldSmall : small),
        );
    String hours(int minutes) =>
        minutes == 0 ? '' : formatAttendanceHours(minutes);

    final rows = <pw.TableRow>[
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          c('No.', bold: true),
          c('Labourer', bold: true),
          c(whereHeading(day.crew), bold: true),
          c('Status', bold: true),
          c('In', bold: true),
          c('Brk', bold: true),
          c('In', bold: true),
          c('Out', bold: true),
          c('Hrs', bold: true, end: true),
          c('Nor.', bold: true, end: true),
          c('Hol.', bold: true, end: true),
          c('Saved by', bold: true),
        ],
      ),
      for (var i = 0; i < printed.length; i++)
        pw.TableRow(
          verticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [
            c('${i + 1}'),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 3,
                vertical: 2,
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(printed[i].name, style: boldSmall),
                  pw.Text(
                    [
                      printed[i].number,
                      printed[i].designation,
                    ].where((part) => part.isNotEmpty).join(' · '),
                    style: muted,
                  ),
                ],
              ),
            ),
            c(printed[i].where),
            c(printed[i].status, bold: printed[i].status != 'Present'),
            c(printed[i].start),
            c(printed[i].breakStart),
            c(printed[i].breakFinish),
            c(printed[i].finish),
            c(hours(printed[i].worked), end: true),
            c(hours(printed[i].normalOvertime), end: true),
            c(hours(printed[i].holidayOvertime), end: true),
            c(printed[i].savedBy),
          ],
        ),
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          c(''),
          c(
            printed.length == 1
                ? 'Total · 1 labourer'
                : 'Total · ${printed.length} labourers',
            bold: true,
          ),
          for (var i = 0; i < 6; i++) c(''),
          c(
            formatAttendanceHours(
              printed.fold(0, (sum, line) => sum + line.worked),
              zeroAsDash: true,
            ),
            bold: true,
            end: true,
          ),
          c(
            formatAttendanceHours(
              printed.fold(0, (sum, line) => sum + line.normalOvertime),
              zeroAsDash: true,
            ),
            bold: true,
            end: true,
          ),
          c(
            formatAttendanceHours(
              printed.fold(0, (sum, line) => sum + line.holidayOvertime),
              zeroAsDash: true,
            ),
            bold: true,
            end: true,
          ),
          c(''),
        ],
      ),
    ];

    pw.Widget field(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
          ),
          pw.Expanded(
            child: pw.Text(
              value.isEmpty ? '—' : value,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    final date = DateFormat('EEEE d MMMM y').format(attendanceDate(day.date));
    final entered = day.enteredBy == null
        ? ''
        : '${day.enteredBy} · ${_stamp(day.enteredAt)}';
    final lastSaved =
        day.lastSavedBy == null ||
            (day.lastSavedBy == day.enteredBy &&
                day.lastSavedAt == day.enteredAt)
        ? null
        : '${day.lastSavedBy} · ${_stamp(day.lastSavedAt)}';

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 22, 24, 20),
        maxPages: 40,
        header: (context) => context.pageNumber == 1
            ? pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  yorksV1PdfLetterhead(logo),
                  pw.SizedBox(height: 8),
                  pw.Center(
                    child: pw.Text(
                      'DAILY ATTENDANCE',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  field('Place / project:', attendancePrintPlace(day.crew)),
                  field('Date:', date),
                  field('Day:', dayType(day)),
                  field('Entered by:', entered),
                  if (lastSaved != null) field('Last saved by:', lastSaved),
                  field('Recorded:', summary(day)),
                  pw.SizedBox(height: 8),
                ],
              )
            : pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Text(
                  'DAILY ATTENDANCE · ${day.crew.label} · $date',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
              ),
        footer: (context) => pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                attendancePrintMonthNote(day.month),
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey700,
                ),
              ),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          ],
        ),
        build: (_) => [
          if (printed.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 12),
              child: pw.Text(
                'Nobody was recorded at this place on this day.',
                style: const pw.TextStyle(fontSize: 9),
              ),
            )
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
              columnWidths: const {
                0: pw.FixedColumnWidth(22),
                1: pw.FlexColumnWidth(),
                2: pw.FixedColumnWidth(72),
                3: pw.FixedColumnWidth(52),
                4: pw.FixedColumnWidth(36),
                5: pw.FixedColumnWidth(32),
                6: pw.FixedColumnWidth(32),
                7: pw.FixedColumnWidth(36),
                8: pw.FixedColumnWidth(24),
                9: pw.FixedColumnWidth(24),
                10: pw.FixedColumnWidth(24),
                11: pw.FixedColumnWidth(66),
              },
              children: rows,
            ),
          if (day.changes.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text('Changed after entry', style: boldSmall),
            pw.SizedBox(height: 3),
            for (final item in day.changes)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.Text(change(item), style: small),
              ),
          ],
        ],
      ),
    );
    return document.save();
  }

  Future<void> printDay(AttendanceDay day) async {
    final bytes = await buildPdf(day);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: fileStem(day));
  }
}

/// Workforce attendance V2 — time entry and hours, exactly as the approved
/// prototype and the paper DAILY TIME SHEET define them.
///
/// The server (`v1_wf_compute_minutes`) is the authority for saved hours; the
/// client uses the same rules only to show a live total while typing.
library;

/// A normal working day: 8 hours.
const int attendanceStandardMinutes = 480;

/// Result of reading a typed time.
final class AttendanceParsedTime {
  const AttendanceParsedTime._(this.minutes, this.ok);

  /// Minutes from midnight, or null when the field is empty or invalid.
  final int? minutes;

  /// False when the text is not a time ("Not a time").
  final bool ok;

  static const empty = AttendanceParsedTime._(null, true);
  static const invalid = AttendanceParsedTime._(null, false);
}

final _pmSuffix = RegExp(r'p\.?m?\.?$');
final _amSuffix = RegExp(r'a\.?m?\.?$');
final _hourMinute = RegExp(r'^\d{1,2}:\d{1,2}$');
final _compact = RegExp(r'^\d{3,4}$');
final _hourOnly = RegExp(r'^\d{1,2}$');

/// Reads "630" (6:30 AM), "1230", "5", "17:30", "5p", "5.30pm".
///
/// Without an AM/PM suffix, an hour before 12 that would fall at or before
/// [after] (the previous field) is read as the afternoon: "5" after a 1 PM
/// start is 5 PM.
AttendanceParsedTime parseAttendanceTime(String? input, {int? after}) {
  var text = (input ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  if (text.isEmpty) return AttendanceParsedTime.empty;
  String? suffix;
  if (_pmSuffix.hasMatch(text)) {
    suffix = 'p';
    text = text.replaceFirst(_pmSuffix, '');
  } else if (_amSuffix.hasMatch(text)) {
    suffix = 'a';
    text = text.replaceFirst(_amSuffix, '');
  }
  text = text.replaceAll(RegExp(r'[.\-h;]'), ':');
  int hour;
  var minute = 0;
  if (_hourMinute.hasMatch(text)) {
    final parts = text.split(':');
    hour = int.parse(parts[0]);
    minute = int.parse(parts[1]);
  } else if (_compact.hasMatch(text)) {
    hour = int.parse(text.substring(0, text.length - 2));
    minute = int.parse(text.substring(text.length - 2));
  } else if (_hourOnly.hasMatch(text)) {
    hour = int.parse(text);
  } else {
    return AttendanceParsedTime.invalid;
  }
  if (minute > 59 || hour > 23) return AttendanceParsedTime.invalid;
  if (suffix == 'p' && hour < 12) hour += 12;
  if (suffix == 'a' && hour == 12) hour = 0;
  var value = hour * 60 + minute;
  if (suffix == null &&
      hour < 12 &&
      after != null &&
      value <= after &&
      value + 720 > after) {
    value += 720;
  }
  return AttendanceParsedTime._(value, true);
}

/// "6:30 AM", or "5 PM" on the hour.
String formatAttendanceTime(int? minutes) {
  if (minutes == null) return '';
  final hour = minutes ~/ 60;
  final minute = minutes % 60;
  final period = hour >= 12 ? 'PM' : 'AM';
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  return minute == 0
      ? '$h12 $period'
      : '$h12:${minute.toString().padLeft(2, '0')} $period';
}

/// The compact form used inside time fields: "6:30a", "5p".
String formatAttendanceTimeInput(int? minutes) {
  if (minutes == null) return '';
  return formatAttendanceTime(
    minutes,
  ).replaceAll(' AM', 'a').replaceAll(' PM', 'p');
}

/// Hours to one decimal place, blank for zero ("8", "3.5", "").
String formatAttendanceHours(int minutes, {bool zeroAsDash = false}) {
  if (minutes == 0) return zeroAsDash ? '0' : '';
  final tenths = (minutes / 6).round();
  final whole = tenths ~/ 10;
  final fraction = tenths % 10;
  return fraction == 0 ? '$whole' : '$whole.$fraction';
}

/// Worked, regular, normal-overtime and holiday-overtime minutes for a row.
final class AttendanceMinutes {
  const AttendanceMinutes({
    this.worked = 0,
    this.regular = 0,
    this.normalOvertime = 0,
    this.holidayOvertime = 0,
    this.timeMissing = false,
  });

  final int worked;
  final int regular;
  final int normalOvertime;
  final int holidayOvertime;

  /// Present without a valid In and Out.
  final bool timeMissing;

  int get overtime => normalOvertime + holidayOvertime;
}

/// Mirrors `v1_wf_compute_minutes`: only Present counts; a working day pays
/// up to 8 hours as normal time and the rest as normal overtime; every hour on
/// a Sunday or public holiday is holiday overtime.
AttendanceMinutes computeAttendanceMinutes({
  required bool present,
  required bool holiday,
  int? start,
  int? breakStart,
  int? breakFinish,
  int? finish,
}) {
  if (!present) return const AttendanceMinutes();
  if (start == null || finish == null || finish <= start) {
    return const AttendanceMinutes(timeMissing: true);
  }
  final breakMinutes =
      breakStart != null && breakFinish != null && breakFinish > breakStart
      ? breakFinish - breakStart
      : 0;
  final worked = (finish - start - breakMinutes).clamp(0, 24 * 60);
  if (holiday) {
    return AttendanceMinutes(worked: worked, holidayOvertime: worked);
  }
  return AttendanceMinutes(
    worked: worked,
    regular: worked < attendanceStandardMinutes
        ? worked
        : attendanceStandardMinutes,
    normalOvertime: worked > attendanceStandardMinutes
        ? worked - attendanceStandardMinutes
        : 0,
  );
}

/// Weekly off days (Sunday unless Configuration says otherwise, as
/// `DateTime.weekday` numbers) and the server's public holidays.
bool attendanceIsRestDay(
  DateTime date, {
  Set<String> holidays = const {},
  Set<int> offDays = const {DateTime.sunday},
}) => offDays.contains(date.weekday) || holidays.contains(attendanceIso(date));

/// `YYYY-MM-DD` for a calendar date.
String attendanceIso(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Parses `YYYY-MM-DD` as a local calendar date.
DateTime attendanceDate(String iso) {
  final parts = iso.split('-').map(int.parse).toList(growable: false);
  return DateTime(parts[0], parts[1], parts[2]);
}

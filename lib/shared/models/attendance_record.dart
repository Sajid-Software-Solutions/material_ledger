import 'dart:convert';

/// Daily attendance state for an employee (FR-125).
enum AttendanceStatus {
  present('Present', 'حاضر', 'حاضر', 'उपस्थित'),
  absent('Absent', 'غائب', 'غیر حاضر', 'अनुपस्थित'),
  onLeave('On Leave', 'في إجازة', 'چھٹی پر', 'अवकाश'),
  halfDay('Half Day', 'نصف يوم', 'آدھا دن', 'आधा दिन');

  const AttendanceStatus(this.label, this.ar, this.ur, this.hi);
  final String label;
  final String ar;
  final String ur;
  final String hi;

  static AttendanceStatus fromName(String n) => AttendanceStatus.values
      .firstWhere((s) => s.name == n, orElse: () => present);
}

/// One attendance entry for an employee on a date.
class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.employeeId,
    required this.date,
    required this.status,
    this.note,
    required this.recordedBy,
  });

  final String id;
  final String employeeId;
  final DateTime date;
  final AttendanceStatus status;
  final String? note;
  final String recordedBy;

  /// `YYYY-MM-DD` day key (one record per employee per day).
  String get dayKey =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
    'id': id,
    'employeeId': employeeId,
    'date': date.toIso8601String(),
    'status': status.name,
    'note': note,
    'recordedBy': recordedBy,
  };

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) =>
      AttendanceRecord(
        id: json['id'] as String,
        employeeId: json['employeeId'] as String,
        date: DateTime.parse(json['date'] as String),
        status: AttendanceStatus.fromName(
          json['status'] as String? ?? 'present',
        ),
        note: json['note'] as String?,
        recordedBy: json['recordedBy'] as String? ?? 'system',
      );

  static String encodeList(List<AttendanceRecord> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());

  static List<AttendanceRecord> decodeList(String jsonStr) {
    final list = jsonDecode(jsonStr) as List;
    return list
        .map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

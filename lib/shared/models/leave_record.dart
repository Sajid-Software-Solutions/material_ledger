import 'dart:convert';

/// Annual leave entitlement per calendar year (FR-127).
const int kAnnualLeaveEntitlement = 30;

enum LeaveType {
  annual('Annual', 'سنوية', 'سالانہ', 'वार्षिक'),
  sick('Sick', 'مرضية', 'بیماری', 'बीमारी'),
  unpaid('Unpaid', 'غير مدفوعة', 'بلا معاوضہ', 'अवैतनिक'),
  emergency('Emergency', 'طارئة', 'ہنگامی', 'आपातकालीन');

  const LeaveType(this.label, this.ar, this.ur, this.hi);
  final String label;
  final String ar;
  final String ur;
  final String hi;

  static LeaveType fromName(String n) =>
      LeaveType.values.firstWhere((t) => t.name == n, orElse: () => annual);
}

enum LeaveRecordStatus {
  pending('Pending', 'معلق', 'زیر التواء', 'लंबित'),
  approved('Approved', 'موافق عليه', 'منظور', 'स्वीकृत'),
  rejected('Rejected', 'مرفوض', 'مسترد', 'अस्वीकृत'),
  cancelled('Cancelled', 'ملغاة', 'منسوخ', 'रद्द');

  const LeaveRecordStatus(this.label, this.ar, this.ur, this.hi);
  final String label;
  final String ar;
  final String ur;
  final String hi;

  static LeaveRecordStatus fromName(String n) => LeaveRecordStatus.values
      .firstWhere((s) => s.name == n, orElse: () => pending);
}

/// A leave request/record for an employee (FR-126).
///
/// Created two ways: an engineer self-service **request** (status `pending`,
/// carries [reason] + [requestedByUserId]/[requestedByName]/[requestedAt]) which
/// an approver then decides; or an admin **retroactive record** (status
/// `approved` straight away). The decision audit (`approvedBy` = decider name,
/// [decidedAt], [decisionNote]) is filled in when an approver acts.
class LeaveRecord {
  const LeaveRecord({
    required this.id,
    required this.employeeId,
    required this.type,
    required this.startDate,
    required this.endDate,
    required this.days,
    this.status = LeaveRecordStatus.pending,
    this.approvedBy,
    this.note,
    this.reason,
    this.requestedByUserId,
    this.requestedByName,
    this.requestedAt,
    this.decidedAt,
    this.decisionNote,
  });

  final String id;
  final String employeeId;
  final LeaveType type;
  final DateTime startDate;
  final DateTime endDate;
  final int days;
  final LeaveRecordStatus status;

  /// Name of the approver who decided (admin/procurement). Null while pending.
  final String? approvedBy;
  final String? note;

  /// The engineer's justification supplied when requesting.
  final String? reason;

  /// The requesting login (AppUser) — used to notify them of the decision.
  final String? requestedByUserId;
  final String? requestedByName;
  final DateTime? requestedAt;

  /// When the approver decided, and their reason (esp. on rejection).
  final DateTime? decidedAt;
  final String? decisionNote;

  /// A request still awaiting a decision.
  bool get isPending => status == LeaveRecordStatus.pending;

  /// Self-service request (vs. an admin retroactive record).
  bool get isRequest => requestedByUserId != null;

  LeaveRecord copyWith({
    LeaveRecordStatus? status,
    String? approvedBy,
    DateTime? decidedAt,
    String? decisionNote,
  }) => LeaveRecord(
    id: id,
    employeeId: employeeId,
    type: type,
    startDate: startDate,
    endDate: endDate,
    days: days,
    status: status ?? this.status,
    approvedBy: approvedBy ?? this.approvedBy,
    note: note,
    reason: reason,
    requestedByUserId: requestedByUserId,
    requestedByName: requestedByName,
    requestedAt: requestedAt,
    decidedAt: decidedAt ?? this.decidedAt,
    decisionNote: decisionNote ?? this.decisionNote,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'employeeId': employeeId,
    'type': type.name,
    'startDate': startDate.toIso8601String(),
    'endDate': endDate.toIso8601String(),
    'days': days,
    'status': status.name,
    'approvedBy': approvedBy,
    'note': note,
    'reason': reason,
    'requestedByUserId': requestedByUserId,
    'requestedByName': requestedByName,
    'requestedAt': requestedAt?.toIso8601String(),
    'decidedAt': decidedAt?.toIso8601String(),
    'decisionNote': decisionNote,
  };

  factory LeaveRecord.fromJson(Map<String, dynamic> json) => LeaveRecord(
    id: json['id'] as String? ?? '',
    employeeId: json['employeeId'] as String? ?? '',
    type: LeaveType.fromName(json['type'] as String? ?? 'annual'),
    startDate:
        DateTime.tryParse(json['startDate'] as String? ?? '') ?? DateTime.now(),
    endDate:
        DateTime.tryParse(json['endDate'] as String? ?? '') ?? DateTime.now(),
    days: (json['days'] as num?)?.toInt() ?? 0,
    status: LeaveRecordStatus.fromName(json['status'] as String? ?? 'pending'),
    approvedBy: json['approvedBy'] as String?,
    note: json['note'] as String?,
    reason: json['reason'] as String?,
    requestedByUserId: json['requestedByUserId'] as String?,
    requestedByName: json['requestedByName'] as String?,
    requestedAt: DateTime.tryParse(json['requestedAt'] as String? ?? ''),
    decidedAt: DateTime.tryParse(json['decidedAt'] as String? ?? ''),
    decisionNote: json['decisionNote'] as String?,
  );

  static String encodeList(List<LeaveRecord> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());

  static List<LeaveRecord> decodeList(String jsonStr) {
    final list = jsonDecode(jsonStr) as List;
    return list
        .map((e) => LeaveRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

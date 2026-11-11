import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/attendance_record.dart';
import '../models/employee.dart';
import '../models/leave_record.dart';
import 'hr_provider.dart';
import 'session_provider.dart';

String _dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The signed-in user's HR self-profile, derived live from their login, their
/// linked employee record, the attendance ledger and their leave balance.
///
/// This is deliberately NOT a seeded constant: every field is the real value for
/// whoever is signed in. An unlinked login (owner/admin has no employee record
/// by design) resolves to a [EmployeeProfile.linked] == false profile carrying
/// real identity but honest placeholders for the HR-specific figures.
final employeeProvider = Provider<EmployeeProfile>((ref) {
  final user = ref.watch(currentUserProvider);
  final emp = ref.watch(currentUserEmployeeProvider);

  final name = (emp != null && emp.fullName.trim().isNotEmpty)
      ? emp.fullName
      : (user?.fullName ?? '—');
  final email = (user?.email.trim().isNotEmpty ?? false) ? user!.email : '—';

  if (emp == null) {
    // Unlinked login — real identity, honest placeholders for HR fields.
    return EmployeeProfile(
      name: name,
      title: user?.role.label ?? '—',
      employeeId: '—',
      email: email,
      phone: '—',
      department: '—',
      nationality: '—',
      linked: false,
      today: SelfAttendance.notMarked,
      annualUsed: 0,
      annualEntitlement: 0,
      pendingRequests: 0,
    );
  }

  // Today's real attendance status from the ledger (notMarked when absent).
  final todayKey = _dayKey(DateTime.now());
  var today = SelfAttendance.notMarked;
  for (final a in ref.watch(attendanceProvider)) {
    if (a.employeeId == emp.id && a.dayKey == todayKey) {
      today = switch (a.status) {
        AttendanceStatus.present => SelfAttendance.present,
        AttendanceStatus.absent => SelfAttendance.absent,
        AttendanceStatus.onLeave => SelfAttendance.onLeave,
        AttendanceStatus.halfDay => SelfAttendance.halfDay,
      };
      break;
    }
  }

  final bal = ref.watch(leaveBalanceProvider(emp.id));

  var pending = 0;
  for (final l in ref.watch(leaveRecordsProvider)) {
    if (l.employeeId == emp.id && l.status == LeaveRecordStatus.pending) {
      pending++;
    }
  }

  return EmployeeProfile(
    name: name,
    title: emp.jobRole.trim().isNotEmpty
        ? emp.jobRole
        : (user?.role.label ?? '—'),
    employeeId: emp.id,
    email: email,
    phone: (emp.contact?.trim().isNotEmpty ?? false)
        ? emp.contact!.trim()
        : '—',
    department: emp.department.trim().isNotEmpty ? emp.department : '—',
    nationality: emp.nationality.trim().isNotEmpty ? emp.nationality : '—',
    linked: true,
    today: today,
    annualUsed: bal.usedAnnual,
    annualEntitlement: bal.entitlement,
    pendingRequests: pending,
    joinDate: emp.joinDate,
  );
});

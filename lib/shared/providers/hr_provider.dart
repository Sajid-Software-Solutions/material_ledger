import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/attendance_record.dart';
import '../models/employee_record.dart';
import '../models/gratuity.dart';
import '../models/leave_record.dart';
import '../models/sick_leave_tiers.dart';
import '../repositories/collection_store.dart';
import '../repositories/storage.dart';
import '../sync/sync_engine.dart';
import 'session_provider.dart';

// Bumped to v2 to re-seed the roster with names aligned to the login accounts
// (emp-001 Imran Khan, emp-002 Al Asad).
const _kEmployeesKey = 'employees_v3';
const _kAttendanceKey = 'attendance_v2';
const _kLeaveKey = 'leave_records_v2';
const _uuid = Uuid();

String _dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ─── Employees ───────────────────────────────────────────────────

final employeesProvider =
    StateNotifierProvider<EmployeesNotifier, List<Employee>>((ref) {
      return EmployeesNotifier(
        ref,
        ref
            .watch(storageProvider)
            .collection<Employee>(
              _kEmployeesKey,
              toJson: (e) => e.toJson(),
              fromJson: Employee.fromJson,
            ),
      );
    });

class EmployeesNotifier extends StateNotifier<List<Employee>> {
  EmployeesNotifier(this._ref, this._store) : super([]) {
    state = _store.isSeeded ? _store.readAll() : _seed();
    if (!_store.isSeeded) _store.writeAll(state);
  }

  final Ref _ref;
  final CollectionStore<Employee> _store;

  Employee? byId(String id) {
    for (final e in state) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<Employee> addEmployee({
    required String fullName,
    required String jobRole,
    required String department,
    required String nationality,
    String? contact,
    double? salaryAED,
    double? basicWageAED,
  }) async {
    final e = Employee(
      id: 'emp-${_uuid.v4().substring(0, 8)}',
      fullName: fullName,
      jobRole: jobRole,
      department: department,
      nationality: nationality,
      contact: contact,
      salaryAED: salaryAED,
      basicWageAED: basicWageAED,
      joinDate: DateTime.now(),
    );
    state = [e, ...state];
    await _store.writeAll(state);
    await _syncEmployee(e, kind: 'employee.create');
    return e;
  }

  Future<void> updateEmployee(Employee updated) async {
    state = [
      for (final e in state)
        if (e.id == updated.id) updated else e,
    ];
    await _store.writeAll(state);
    await _syncEmployee(updated, kind: 'employee.update');
  }

  Future<void> _syncEmployee(Employee e, {required String kind}) {
    // Salary/basic-wage are admin-only (canSeeSalary). The employees table is
    // readable by anyone with the 'people' cap (procurement included), so
    // compensation figures must NEVER ride in the shared payload — strip them
    // before they leave the device. They stay in the local store for authorised
    // (admin) use; cross-admin sync would need a dedicated salary-capped table
    // (see PRODUCTION_STATUS).
    final payload = e.toJson()
      ..remove('salaryAED')
      ..remove('basicWageAED');
    return _ref.enqueueSync(
      collection: 'employees',
      docId: e.id,
      kind: kind,
      label: 'Employee',
      payload: payload,
    );
  }

  // Trimmed to just the two logins that link to an employee record
  // (owner/admin has none by design). Real hires are added via addEmployee().
  static List<Employee> _seed() {
    final now = DateTime.now();
    return [
      Employee(
        id: 'emp-001',
        fullName: 'Imran Khan',
        jobRole: 'Site Engineer',
        department: 'Projects',
        nationality: 'Pakistan',
        contact: '+971 50 111 2222',
        emiratesId: '784-1990-1234567-1',
        passportNo: 'AB1234567',
        visaExpiry: DateTime(now.year + 1, 4, 15),
        joinDate: DateTime(now.year - 3, 2, 1),
        salaryAED: 6500,
        status: EmployeeStatus.active,
      ),
      Employee(
        id: 'emp-002',
        fullName: 'Al Asad',
        jobRole: 'Procurement Officer',
        department: 'Procurement',
        nationality: 'Pakistan',
        contact: '+971 55 333 4444',
        emiratesId: '784-1988-7654321-2',
        joinDate: DateTime(now.year - 2, 7, 10),
        salaryAED: 7200,
        status: EmployeeStatus.active,
      ),
    ];
  }
}

// ─── Attendance ──────────────────────────────────────────────────

final attendanceProvider =
    StateNotifierProvider<AttendanceNotifier, List<AttendanceRecord>>((ref) {
      return AttendanceNotifier(
        ref,
        ref
            .watch(storageProvider)
            .collection<AttendanceRecord>(
              _kAttendanceKey,
              toJson: (a) => a.toJson(),
              fromJson: AttendanceRecord.fromJson,
            ),
      );
    });

class AttendanceNotifier extends StateNotifier<List<AttendanceRecord>> {
  AttendanceNotifier(this._ref, this._store) : super([]) {
    state = _store.isSeeded ? _store.readAll() : _seed();
    if (!_store.isSeeded) _store.writeAll(state);
  }

  final Ref _ref;
  final CollectionStore<AttendanceRecord> _store;

  /// Set today's attendance for an employee (one record per day — upsert).
  Future<void> markToday({
    required String employeeId,
    required AttendanceStatus status,
    String? note,
    required String recordedBy,
  }) async {
    final today = _dayKey(DateTime.now());
    final idx = state.indexWhere(
      (a) => a.employeeId == employeeId && a.dayKey == today,
    );
    final record = AttendanceRecord(
      id: idx >= 0 ? state[idx].id : 'att-${_uuid.v4().substring(0, 8)}',
      employeeId: employeeId,
      date: DateTime.now(),
      status: status,
      note: note,
      recordedBy: recordedBy,
    );
    state = idx >= 0
        ? [
            for (var i = 0; i < state.length; i++)
              if (i == idx) record else state[i],
          ]
        : [record, ...state];
    await _store.writeAll(state);
    await _ref.enqueueSync(
      collection: 'attendance',
      docId: record.id,
      kind: 'attendance.mark',
      label: 'Attendance',
      payload: record.toJson(),
    );
  }

  AttendanceRecord? todayFor(String employeeId) {
    final today = _dayKey(DateTime.now());
    for (final a in state) {
      if (a.employeeId == employeeId && a.dayKey == today) return a;
    }
    return null;
  }

  // No pre-seeded demo attendance — marked fresh via the attendance sheet.
  static List<AttendanceRecord> _seed() => [];
}

// ─── Leave records ───────────────────────────────────────────────

final leaveRecordsProvider =
    StateNotifierProvider<LeaveNotifier, List<LeaveRecord>>((ref) {
      return LeaveNotifier(
        ref,
        ref
            .watch(storageProvider)
            .collection<LeaveRecord>(
              _kLeaveKey,
              toJson: (l) => l.toJson(),
              fromJson: LeaveRecord.fromJson,
            ),
      );
    });

class LeaveNotifier extends StateNotifier<List<LeaveRecord>> {
  LeaveNotifier(this._ref, this._store) : super([]) {
    state = _store.isSeeded ? _store.readAll() : _seed();
    if (!_store.isSeeded) _store.writeAll(state);
  }

  final Ref _ref;
  final CollectionStore<LeaveRecord> _store;

  List<LeaveRecord> forEmployee(String employeeId) =>
      state.where((l) => l.employeeId == employeeId).toList()
        ..sort((a, b) => b.startDate.compareTo(a.startDate));

  Future<LeaveRecord> addLeave({
    required String employeeId,
    required LeaveType type,
    required DateTime startDate,
    required DateTime endDate,
    LeaveRecordStatus status = LeaveRecordStatus.approved,
    String? approvedBy,
    String? note,
  }) async {
    final days = endDate.difference(startDate).inDays + 1;
    final record = LeaveRecord(
      id: 'leave-${_uuid.v4().substring(0, 8)}',
      employeeId: employeeId,
      type: type,
      startDate: startDate,
      endDate: endDate,
      days: days < 1 ? 1 : days,
      status: status,
      approvedBy: approvedBy,
      note: note,
    );
    state = [record, ...state];
    await _store.writeAll(state);
    await _syncLeave(record, kind: 'leave.create');
    return record;
  }

  Future<void> setStatus(
    String id,
    LeaveRecordStatus status, {
    String? approvedBy,
  }) async {
    state = [
      for (final l in state)
        if (l.id == id)
          l.copyWith(status: status, approvedBy: approvedBy)
        else
          l,
    ];
    await _store.writeAll(state);
    for (final l in state) {
      if (l.id == id) {
        await _syncLeave(l, kind: 'leave.status');
        break;
      }
    }
  }

  /// Engineer self-service: file a leave request (status `pending`) for the
  /// employee linked to their login. An approver then [decide]s it.
  Future<LeaveRecord> submitRequest({
    required String employeeId,
    required String requestedByUserId,
    required String requestedByName,
    required LeaveType type,
    required DateTime startDate,
    required DateTime endDate,
    String? reason,
  }) async {
    // Hard-block an overlapping request: two overlapping active leaves would each
    // subtract from the balance and double-count the same days.
    if (leaveOverlaps(employeeId, startDate, endDate)) {
      throw StateError(
        'This overlaps an existing leave request for these dates.',
      );
    }
    final days = endDate.difference(startDate).inDays + 1;
    final record = LeaveRecord(
      id: 'leave-${_uuid.v4().substring(0, 8)}',
      employeeId: employeeId,
      type: type,
      startDate: startDate,
      endDate: endDate,
      days: days < 1 ? 1 : days,
      status: LeaveRecordStatus.pending,
      reason: reason,
      requestedByUserId: requestedByUserId,
      requestedByName: requestedByName,
      requestedAt: DateTime.now(),
    );
    state = [record, ...state];
    await _store.writeAll(state);
    await _syncLeave(record, kind: 'leave.request');
    return record;
  }

  /// Approver action on a pending request → approved/rejected, stamping the
  /// decider, time, and (optional) reason. A user can never decide their own
  /// request. Returns the updated record (or null if it wasn't actionable).
  Future<LeaveRecord?> decide(
    String id, {
    required bool approve,
    required String decidedBy,
    String? decidedByUserId,
    String? decisionNote,
  }) async {
    // Guard: don't approve a request that would overlap an already-approved leave
    // for the same employee (a belt-and-suspenders check for edited/imported
    // records — submit already blocks new overlaps).
    if (approve) {
      LeaveRecord? target;
      for (final l in state) {
        if (l.id == id) {
          target = l;
          break;
        }
      }
      if (target != null) {
        for (final l in state) {
          if (l.id == id || l.employeeId != target.employeeId) continue;
          if (l.status != LeaveRecordStatus.approved) continue;
          if (!target.startDate.isAfter(l.endDate) &&
              !l.startDate.isAfter(target.endDate)) {
            return null; // would overlap an approved leave → refuse
          }
        }
      }
    }
    LeaveRecord? updated;
    state = [
      for (final l in state)
        if (l.id == id && l.isPending && l.requestedByUserId != decidedByUserId)
          updated = l.copyWith(
            status: approve
                ? LeaveRecordStatus.approved
                : LeaveRecordStatus.rejected,
            approvedBy: decidedBy,
            decidedAt: DateTime.now(),
            decisionNote: decisionNote,
          )
        else
          l,
    ];
    if (updated == null) return null;
    await _store.writeAll(state);
    await _syncLeave(updated, kind: 'leave.decision');
    return updated;
  }

  /// Engineer withdraws their own still-pending request.
  Future<void> withdraw(String id) async {
    LeaveRecord? updated;
    state = [
      for (final l in state)
        if (l.id == id && l.isPending)
          updated = l.copyWith(status: LeaveRecordStatus.cancelled)
        else
          l,
    ];
    if (updated == null) return;
    await _store.writeAll(state);
    await _syncLeave(updated, kind: 'leave.withdraw');
  }

  /// True if [start]–[end] overlaps an existing active (pending/approved) leave
  /// for the employee — drives the "overlaps another leave" warning.
  bool leaveOverlaps(
    String employeeId,
    DateTime start,
    DateTime end, {
    String? excludeId,
  }) {
    for (final l in state) {
      if (l.employeeId != employeeId || l.id == excludeId) continue;
      if (l.status == LeaveRecordStatus.rejected ||
          l.status == LeaveRecordStatus.cancelled) {
        continue;
      }
      if (!start.isAfter(l.endDate) && !l.startDate.isAfter(end)) return true;
    }
    return false;
  }

  Future<void> _syncLeave(LeaveRecord l, {required String kind}) {
    return _ref.enqueueSync(
      collection: 'leaveRecords',
      docId: l.id,
      kind: kind,
      label: 'Leave',
      payload: l.toJson(),
    );
  }

  // No pre-seeded demo leave — requested/recorded fresh during testing.
  static List<LeaveRecord> _seed() => [];
}

// ─── Derived: leave balance ──────────────────────────────────────

class LeaveBalance {
  const LeaveBalance({required this.entitlement, required this.usedAnnual});
  final int entitlement;
  final int usedAnnual;
  int get remaining => (entitlement - usedAnnual).clamp(0, entitlement);
}

/// Days of an [l]eave that fall inside calendar [year] — so a leave spanning a
/// year boundary (e.g. 28 Dec–6 Jan) charges each year only for its own days
/// instead of dumping the whole span onto the start year.
int _annualDaysInYear(LeaveRecord l, int year) {
  DateTime dateOnly(DateTime x) => DateTime(x.year, x.month, x.day);
  final yStart = DateTime(year, 1, 1);
  final yEnd = DateTime(year, 12, 31);
  final s = dateOnly(l.startDate).isAfter(yStart)
      ? dateOnly(l.startDate)
      : yStart;
  final e = dateOnly(l.endDate).isBefore(yEnd) ? dateOnly(l.endDate) : yEnd;
  if (e.isBefore(s)) return 0;
  return e.difference(s).inDays + 1;
}

/// Annual-leave entitlement by length of service, per UAE Labour Law
/// (Federal Decree-Law 33/2021, Art. 29): none in the first 6 months, ~2 days a
/// month while 6–12 months in, then the full 30 days from one year of service.
/// A null join date (unknown tenure) falls back to the full entitlement.
int _annualEntitlement(DateTime? joinDate) {
  if (joinDate == null) return kAnnualLeaveEntitlement;
  final now = DateTime.now();
  var months = (now.year - joinDate.year) * 12 + (now.month - joinDate.month);
  if (now.day < joinDate.day) months -= 1;
  if (months < 6) return 0;
  if (months < 12) return (months * 2).clamp(0, kAnnualLeaveEntitlement);
  return kAnnualLeaveEntitlement;
}

/// Annual-leave balance for an employee: the tenure-based entitlement minus the
/// approved annual days taken THIS calendar year (year-boundary-aware). Watches
/// the employee roster so a change to the person's join date reprices the
/// entitlement (FR-127).
final leaveBalanceProvider = Provider.family<LeaveBalance, String>((
  ref,
  employeeId,
) {
  final records = ref.watch(leaveRecordsProvider);
  Employee? employee;
  for (final e in ref.watch(employeesProvider)) {
    if (e.id == employeeId) {
      employee = e;
      break;
    }
  }
  final year = DateTime.now().year;
  var used = 0;
  for (final l in records) {
    if (l.employeeId != employeeId) continue;
    if (l.type != LeaveType.annual) continue;
    if (l.status != LeaveRecordStatus.approved) continue;
    used += _annualDaysInYear(l, year);
  }
  return LeaveBalance(
    entitlement: _annualEntitlement(employee?.joinDate),
    usedAnnual: used,
  );
});

/// Sick-leave days already taken (any status other than rejected/cancelled;
/// pending counts so the tier preview reacts before approval) for [employeeId]
/// in the current calendar year — feeds [sickLeaveTierProvider].
int _sickDaysUsedThisYear(List<LeaveRecord> records, String employeeId) {
  final year = DateTime.now().year;
  var used = 0;
  for (final l in records) {
    if (l.employeeId != employeeId || l.type != LeaveType.sick) continue;
    if (l.status == LeaveRecordStatus.rejected ||
        l.status == LeaveRecordStatus.cancelled) {
      continue;
    }
    used += _annualDaysInYear(l, year);
  }
  return used;
}

/// How a [days]-day sick-leave request for [employeeId] would split across the
/// UAE statutory pay tiers (full/half/unpaid), given what they've already used
/// this year. `(employeeId, days)` as the family key.
final sickLeaveTierProvider =
    Provider.family<SickLeaveTierSplit, (String employeeId, int days)>((
      ref,
      arg,
    ) {
      final records = ref.watch(leaveRecordsProvider);
      final used = _sickDaysUsedThisYear(records, arg.$1);
      return splitSickLeaveTiers(alreadyUsedDays: used, requestedDays: arg.$2);
    });

/// End-of-service gratuity ESTIMATE for [employeeId] as of today — an HR
/// planning figure, not a certified payout (see gratuity.dart). Null when the
/// employee has no join date or no basic-wage figure to compute from.
final gratuityEstimateProvider = Provider.family<GratuityEstimate?, String>((
  ref,
  employeeId,
) {
  Employee? emp;
  for (final e in ref.watch(employeesProvider)) {
    if (e.id == employeeId) {
      emp = e;
      break;
    }
  }
  final wage = emp?.effectiveBasicWageAED;
  final joinDate = emp?.joinDate;
  if (emp == null || wage == null || wage <= 0 || joinDate == null) return null;
  return calculateGratuity(
    joinDate: joinDate,
    asOf: DateTime.now(),
    basicWageAED: wage,
  );
});

/// Company-wide accrued gratuity liability across the whole active roster —
/// the roll-up figure management needs for financial planning.
final totalGratuityLiabilityProvider = Provider<double>((ref) {
  final employees = ref.watch(employeesProvider);
  var total = 0.0;
  for (final e in employees) {
    if (e.status == EmployeeStatus.inactive) continue;
    final est = ref.watch(gratuityEstimateProvider(e.id));
    if (est != null && est.entitled) total += est.amountAED;
  }
  return total;
});

// ─── Derived: leave-request queues + identity link ───────────────

/// All pending leave requests — the admin/procurement approvals queue, newest
/// request first.
final pendingLeaveRequestsProvider = Provider<List<LeaveRecord>>((ref) {
  final records = ref.watch(leaveRecordsProvider);
  return records.where((l) => l.isPending).toList()..sort(
    (a, b) =>
        (b.requestedAt ?? b.startDate).compareTo(a.requestedAt ?? a.startDate),
  );
});

/// The HR [Employee] linked to the signed-in login, or null when unlinked.
final currentUserEmployeeProvider = Provider<Employee?>((ref) {
  final empId = ref.watch(currentUserProvider)?.employeeId;
  if (empId == null) return null;
  for (final e in ref.watch(employeesProvider)) {
    if (e.id == empId) return e;
  }
  return null;
});

/// The signed-in user's own leave records (newest first); empty when unlinked.
final myLeaveRecordsProvider = Provider<List<LeaveRecord>>((ref) {
  final emp = ref.watch(currentUserEmployeeProvider);
  if (emp == null) return const [];
  return ref
      .watch(leaveRecordsProvider)
      .where((l) => l.employeeId == emp.id)
      .toList()
    ..sort((a, b) => b.startDate.compareTo(a.startDate));
});

// ─── Derived: HR dashboard summary ───────────────────────────────

class HrSummary {
  const HrSummary({
    required this.total,
    required this.presentToday,
    required this.onLeaveToday,
    required this.absentToday,
  });
  final int total;
  final int presentToday;
  final int onLeaveToday;
  final int absentToday;
}

final hrSummaryProvider = Provider<HrSummary>((ref) {
  final employees = ref.watch(employeesProvider);
  final attendance = ref.watch(attendanceProvider);
  final today = _dayKey(DateTime.now());

  var present = 0, onLeave = 0, absent = 0;
  for (final e in employees) {
    AttendanceRecord? rec;
    for (final a in attendance) {
      if (a.employeeId == e.id && a.dayKey == today) {
        rec = a;
        break;
      }
    }
    switch (rec?.status) {
      case AttendanceStatus.present:
      case AttendanceStatus.halfDay:
        present++;
      case AttendanceStatus.onLeave:
        onLeave++;
      case AttendanceStatus.absent:
        absent++;
      case null:
        break;
    }
  }

  return HrSummary(
    total: employees.length,
    presentToday: present,
    onLeaveToday: onLeave,
    absentToday: absent,
  );
});

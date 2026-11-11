import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/rent_payment.dart';
import '../models/rental_unit.dart';
import '../repositories/collection_store.dart';
import '../repositories/storage.dart';
import '../sync/sync_engine.dart';

const _kRentalUnitsKey = 'rental_units_v2';
const _kRentPaymentsKey = 'rent_payments_v2';
const _uuid = Uuid();

String _monthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// Billing-month keys from [start] to [end] inclusive (month granularity).
List<String> _monthsBetween(DateTime start, DateTime end) {
  final out = <String>[];
  var y = start.year;
  var m = start.month;
  while (y < end.year || (y == end.year && m <= end.month)) {
    out.add('$y-${m.toString().padLeft(2, '0')}');
    if (++m > 12) {
      m = 1;
      y++;
    }
  }
  return out;
}

/// Rent arrears for an occupied [unit] as of [now], derived from OCCUPANCY —
/// not just from entered payment records. Every elapsed month since the lease
/// began that still has an unpaid balance is overdue; the current month's unpaid
/// balance is "due". This is what makes rent-roll, collected, and overdue tie
/// out: an occupied month nobody entered a record for is still money owed.
/// Bounded to the last 24 months so a very old lease can't blow up the scan.
({double overdue, double currentDue}) unitRentArrears(
  RentalUnit unit,
  List<RentPayment> payments,
  DateTime now,
) {
  if (!unit.isOccupied) return (overdue: 0, currentDue: 0);
  final leaseStart = unit.leaseStart ?? unit.createdAt;
  final windowStart = DateTime(now.year - 2, now.month);
  final start = leaseStart.isAfter(windowStart) ? leaseStart : windowStart;
  final endCap = (unit.leaseEnd != null && unit.leaseEnd!.isBefore(now))
      ? unit.leaseEnd!
      : now;
  if (endCap.isBefore(start)) return (overdue: 0, currentDue: 0);
  final thisMonth = _monthKey(now);
  var overdue = 0.0;
  var currentDue = 0.0;
  for (final key in _monthsBetween(start, endCap)) {
    var paid = 0.0;
    for (final p in payments) {
      if (p.unitId != unit.id || p.isVoided || p.periodMonth != key) continue;
      paid += p.amountPaidAED.clamp(0, unit.monthlyRentAED).toDouble();
    }
    final outstanding = (unit.monthlyRentAED - paid)
        .clamp(0, double.infinity)
        .toDouble();
    if (outstanding <= 0) continue;
    if (key == thisMonth) {
      currentDue += outstanding;
    } else {
      overdue += outstanding;
    }
  }
  return (overdue: overdue, currentDue: currentDue);
}

// ─── Rental Units ────────────────────────────────────────────────

final rentalUnitsProvider =
    StateNotifierProvider<RentalUnitsNotifier, List<RentalUnit>>((ref) {
      return RentalUnitsNotifier(
        ref,
        ref
            .watch(storageProvider)
            .collection<RentalUnit>(
              _kRentalUnitsKey,
              toJson: (u) => u.toJson(),
              fromJson: RentalUnit.fromJson,
            ),
      );
    });

class RentalUnitsNotifier extends StateNotifier<List<RentalUnit>> {
  RentalUnitsNotifier(this._ref, this._store) : super([]) {
    state = _store.isSeeded ? _store.readAll() : _seedUnits();
    if (!_store.isSeeded) _store.writeAll(state);
  }

  final Ref _ref;
  final CollectionStore<RentalUnit> _store;

  RentalUnit? byId(String id) {
    for (final u in state) {
      if (u.id == id) return u;
    }
    return null;
  }

  Future<RentalUnit> addUnit({
    required String unitName,
    required RentalType type,
    required String location,
    required double monthlyRentAED,
    String? tenantName,
    String? tenantContact,
    DateTime? leaseStart,
    DateTime? leaseEnd,
    String? notes,
    double? securityDepositAED,
    double vatRatePercent = 5.0,
    required String createdBy,
  }) async {
    final occupied = (tenantName ?? '').trim().isNotEmpty;
    final unit = RentalUnit(
      id: 'unit-${_uuid.v4().substring(0, 8)}',
      unitName: unitName,
      type: type,
      location: location,
      monthlyRentAED: monthlyRentAED,
      tenantName: tenantName,
      tenantContact: tenantContact,
      leaseStart: leaseStart,
      leaseEnd: leaseEnd,
      status: occupied ? RentalStatus.active : RentalStatus.vacant,
      notes: notes,
      securityDepositAED: securityDepositAED,
      vatRatePercent: vatRatePercent,
      createdBy: createdBy,
      createdAt: DateTime.now(),
    );
    state = [unit, ...state];
    await _store.writeAll(state);
    await _syncUnit(unit, kind: 'rentalUnit.create');
    return unit;
  }

  Future<void> updateUnit(RentalUnit updated) async {
    state = [
      for (final u in state)
        if (u.id == updated.id) updated else u,
    ];
    await _store.writeAll(state);
    await _syncUnit(updated, kind: 'rentalUnit.update');
  }

  Future<void> _syncUnit(RentalUnit u, {required String kind}) {
    return _ref.enqueueSync(
      collection: 'rentalUnits',
      docId: u.id,
      kind: kind,
      label: 'Rental unit',
      payload: u.toJson(),
    );
  }

  // No pre-seeded demo units — the office adds real rental units as
  // testing/production use begins.
  static List<RentalUnit> _seedUnits() => [];
}

// ─── Rent Payments ───────────────────────────────────────────────

final rentPaymentsProvider =
    StateNotifierProvider<RentPaymentsNotifier, List<RentPayment>>((ref) {
      return RentPaymentsNotifier(
        ref,
        ref
            .watch(storageProvider)
            .collection<RentPayment>(
              _kRentPaymentsKey,
              toJson: (p) => p.toJson(),
              fromJson: RentPayment.fromJson,
            ),
      );
    });

class RentPaymentsNotifier extends StateNotifier<List<RentPayment>> {
  RentPaymentsNotifier(this._ref, this._store) : super([]) {
    state = _store.isSeeded ? _store.readAll() : _seedPayments();
    if (!_store.isSeeded) _store.writeAll(state);
  }

  final Ref _ref;
  final CollectionStore<RentPayment> _store;

  List<RentPayment> forUnit(String unitId) =>
      state.where((p) => p.unitId == unitId).toList()
        ..sort((a, b) => b.periodMonth.compareTo(a.periodMonth));

  /// Record (or top up) a payment for a unit + billing month. If a record for
  /// that period exists, the paid amount is increased; otherwise a new record
  /// is created. Returns the resulting payment.
  Future<RentPayment> recordPayment({
    required String unitId,
    required String periodMonth,
    required double amountDueAED,
    required double amountPaidAED,
    String? method,
    String? note,
    required String recordedBy,
  }) async {
    final idx = state.indexWhere(
      (p) => p.unitId == unitId && p.periodMonth == periodMonth && !p.isVoided,
    );
    late RentPayment result;
    if (idx >= 0) {
      // Top up: accumulate the paid amount but PRESERVE the period's original
      // total due — re-recording must never reset/double the charge. The new
      // [amountDueAED] only matters when creating a fresh period record below.
      // Cap the running total at the period's due so a month's rent can never be
      // over-collected (overpayment would inflate the cash-received roll).
      final original = state[idx];
      final cappedPaid = (original.amountPaidAED + amountPaidAED)
          .clamp(0, original.amountDueAED)
          .toDouble();
      result = original.copyWith(
        amountPaidAED: cappedPaid,
        paidDate: DateTime.now(),
        method: method,
        note: note,
      );
      state = [
        for (var i = 0; i < state.length; i++)
          if (i == idx) result else state[i],
      ];
    } else {
      result = RentPayment(
        id: 'rent-${_uuid.v4().substring(0, 8)}',
        unitId: unitId,
        periodMonth: periodMonth,
        amountDueAED: amountDueAED,
        // Never record more than the month's due (no over-collection).
        amountPaidAED: amountPaidAED.clamp(0, amountDueAED).toDouble(),
        paidDate: DateTime.now(),
        method: method,
        note: note,
        recordedBy: recordedBy,
        recordedAt: DateTime.now(),
      );
      state = [result, ...state];
    }
    await _store.writeAll(state);
    // Money movement / balance change → transactional (atomic on the server).
    await _ref.enqueueSync(
      collection: 'rentPayments',
      docId: result.id,
      kind: 'rentPayment.record',
      label: 'Rent payment',
      payload: result.toJson(),
      transactional: true,
    );
    return result;
  }

  /// Void a payment record (a correction). It's kept in history for the audit
  /// trail but excluded from all balances; recording again for the same period
  /// then creates a fresh record.
  Future<void> voidPayment(String id, {required String reason}) async {
    final now = DateTime.now();
    RentPayment? voided;
    state = [
      for (final p in state)
        if (p.id == id && !p.isVoided)
          voided = p.copyWith(voidedAt: now, voidReason: reason.trim())
        else
          p,
    ];
    if (voided == null) return;
    await _store.writeAll(state);
    await _ref.enqueueSync(
      collection: 'rentPayments',
      docId: voided.id,
      kind: 'rentPayment.void',
      label: 'Rent payment',
      payload: voided.toJson(),
      transactional: true,
    );
  }

  // No pre-seeded demo payments — recorded fresh as testing/production use begins.
  static List<RentPayment> _seedPayments() => [];
}

// ─── Derived: per-unit current status ────────────────────────────

/// The current rent status for a unit (Paid/Due/Overdue/Partial), derived from
/// occupancy-based arrears so an unbilled elapsed month still reads as overdue.
final unitRentStatusProvider = Provider.family<RentStatus, String>((
  ref,
  unitId,
) {
  final units = ref.watch(rentalUnitsProvider);
  final payments = ref.watch(rentPaymentsProvider);
  final now = DateTime.now();
  RentalUnit? unit;
  for (final u in units) {
    if (u.id == unitId) {
      unit = u;
      break;
    }
  }
  if (unit == null || !unit.isOccupied) return RentStatus.paid; // nothing owed

  final a = unitRentArrears(unit, payments, now);
  if (a.overdue > 0) return RentStatus.overdue;
  if (a.currentDue <= 0) return RentStatus.paid;
  // Current month has a balance: partial if something's in this month, else due.
  final thisMonth = _monthKey(now);
  final paidThis = payments
      .where(
        (p) => p.unitId == unitId && !p.isVoided && p.periodMonth == thisMonth,
      )
      .fold(0.0, (s, p) => s + p.amountPaidAED);
  return paidThis > 0 ? RentStatus.partial : RentStatus.due;
});

// ─── Derived: dashboard summary ──────────────────────────────────

class RentalsSummary {
  const RentalsSummary({
    required this.totalUnits,
    required this.occupied,
    required this.vacant,
    required this.monthlyRentRoll,
    required this.collectedThisMonth,
    required this.overdueTotal,
    required this.currentMonthDue,
  });

  final int totalUnits;
  final int occupied;
  final int vacant;
  final double monthlyRentRoll;
  final double collectedThisMonth;
  final double overdueTotal;

  /// This month's rent still outstanding on occupied units (derived from
  /// occupancy, not just entered records). Holds the invariant
  /// `collectedThisMonth + currentMonthDue == monthlyRentRoll`.
  final double currentMonthDue;
}

final rentalsSummaryProvider = Provider<RentalsSummary>((ref) {
  final units = ref.watch(rentalUnitsProvider);
  final payments = ref.watch(rentPaymentsProvider);
  final now = DateTime.now();
  final thisMonth = _monthKey(now);

  final rentRoll = units
      .where((u) => u.isOccupied)
      .fold(0.0, (s, u) => s + u.monthlyRentAED);

  // Collected = this month's non-void receipts (clamped so a legacy over-record
  // can't push it above the roll).
  var collected = 0.0;
  for (final p in payments) {
    if (p.isVoided || p.periodMonth != thisMonth) continue;
    collected += p.amountPaidAED.clamp(0, p.amountDueAED).toDouble();
  }

  // Overdue + current-due are derived from OCCUPANCY (accrual), so an occupied
  // month with no record is no longer invisible.
  var overdue = 0.0;
  var currentDue = 0.0;
  for (final u in units) {
    final a = unitRentArrears(u, payments, now);
    overdue += a.overdue;
    currentDue += a.currentDue;
  }

  return RentalsSummary(
    totalUnits: units.length,
    occupied: units.where((u) => u.isOccupied).length,
    vacant: units.where((u) => !u.isOccupied).length,
    monthlyRentRoll: rentRoll,
    collectedThisMonth: collected,
    overdueTotal: overdue,
    currentMonthDue: currentDue,
  );
});

/// Current billing month key (`YYYY-MM`) for record-payment defaults.
String currentRentMonthKey() => _monthKey(DateTime.now());

/// Total security deposits currently held across all units — a liability until
/// refunded/offset at move-out, kept separate from the rent roll.
final totalSecurityDepositsHeldProvider = Provider<double>((ref) {
  return ref
      .watch(rentalUnitsProvider)
      .fold(0.0, (s, u) => s + (u.securityDepositAED ?? 0));
});

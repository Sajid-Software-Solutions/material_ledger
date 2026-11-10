/// End-of-service gratuity (UAE Federal Decree-Law No. 33/2021, Art. 51) — an
/// ESTIMATE for HR planning, not a certified payroll figure. Actual settlement
/// should be confirmed with a qualified HR/legal advisor, especially for
/// unlimited vs limited contracts, unpaid-leave deductions, and any
/// company-specific policy.
///
/// Standard formula (private sector, on basic wage — not gross salary):
///   < 1 year of service        → not entitled (0)
///   1–5 years                  → 21 days' basic wage per year of service
///   > 5 years                  → 21 days/year for the first 5 years,
///                                 30 days/year for each year beyond
///   Total is capped at 2 years' total wage (Art. 51(5)).
library;

/// One resulting breakdown of a gratuity estimate.
class GratuityEstimate {
  const GratuityEstimate({
    required this.yearsOfService,
    required this.entitled,
    required this.amountAED,
  });

  /// Full + partial years of service (fractional), e.g. 3.5.
  final double yearsOfService;

  /// False when service is under 1 year (no statutory entitlement).
  final bool entitled;

  final double amountAED;
}

/// Pure calculation — no I/O, no `DateTime.now()` default (the caller supplies
/// "as of" so this stays deterministic/testable). [basicWageAED] is the monthly
/// BASIC wage (not gross salary — allowances are excluded per Art. 51).
GratuityEstimate calculateGratuity({
  required DateTime joinDate,
  required DateTime asOf,
  required double basicWageAED,
}) {
  final serviceDays = asOf.difference(joinDate).inDays;
  final years = serviceDays / 365.25;

  if (years < 1 || basicWageAED <= 0) {
    return GratuityEstimate(
      yearsOfService: years,
      entitled: false,
      amountAED: 0,
    );
  }

  final dailyWage = basicWageAED / 30;
  double amount;
  if (years <= 5) {
    amount = years * 21 * dailyWage;
  } else {
    amount = 5 * 21 * dailyWage + (years - 5) * 30 * dailyWage;
  }

  // Statutory cap: total gratuity may never exceed 2 years' total wage.
  final cap = basicWageAED * 24;
  if (amount > cap) amount = cap;

  return GratuityEstimate(
    yearsOfService: years,
    entitled: true,
    amountAED: amount,
  );
}

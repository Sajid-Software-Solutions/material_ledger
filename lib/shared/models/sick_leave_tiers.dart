/// UAE statutory sick-leave pay tiers (Federal Decree-Law No. 33/2021, Art. 31)
/// — after probation, up to 90 days of sick leave per year (not necessarily
/// consecutive): the first 15 days full pay, the next 30 half pay, the
/// remaining 45 unpaid. This is a planning aid for payroll, not a certified
/// figure — confirm with HR/legal for edge cases (probation, non-consecutive
/// spells crossing the cap).
library;

const int kSickFullPayDays = 15;
const int kSickHalfPayDays = 30;
const int kSickAnnualCap = 90; // full + half + unpaid

/// How [requestedDays] of NEW sick leave split across the pay tiers, given
/// [alreadyUsedDays] of sick leave already taken (and approved) this year.
class SickLeaveTierSplit {
  const SickLeaveTierSplit({
    required this.fullPayDays,
    required this.halfPayDays,
    required this.unpaidDays,
    required this.exceedsAnnualCap,
  });

  final int fullPayDays;
  final int halfPayDays;
  final int unpaidDays;

  /// True when this request would push cumulative sick leave past the 90-day
  /// annual cap — the excess is folded into [unpaidDays] rather than dropped.
  final bool exceedsAnnualCap;

  int get totalDays => fullPayDays + halfPayDays + unpaidDays;
}

SickLeaveTierSplit splitSickLeaveTiers({
  required int alreadyUsedDays,
  required int requestedDays,
}) {
  if (requestedDays <= 0) {
    return const SickLeaveTierSplit(
      fullPayDays: 0,
      halfPayDays: 0,
      unpaidDays: 0,
      exceedsAnnualCap: false,
    );
  }
  final usedBefore = alreadyUsedDays.clamp(0, kSickAnnualCap);
  final cappedRequested =
      (usedBefore + requestedDays).clamp(0, kSickAnnualCap) - usedBefore;
  final overCap = requestedDays - cappedRequested; // days beyond the 90-day cap

  int daysInTier(int tierStart, int tierEnd) {
    final start = usedBefore.clamp(tierStart, tierEnd);
    final end = (usedBefore + cappedRequested).clamp(tierStart, tierEnd);
    return (end - start).clamp(0, tierEnd - tierStart);
  }

  final full = daysInTier(0, kSickFullPayDays);
  final half = daysInTier(
    kSickFullPayDays,
    kSickFullPayDays + kSickHalfPayDays,
  );
  final unpaid =
      daysInTier(kSickFullPayDays + kSickHalfPayDays, kSickAnnualCap) + overCap;

  return SickLeaveTierSplit(
    fullPayDays: full,
    halfPayDays: half,
    unpaidDays: unpaid,
    exceedsAnnualCap: overCap > 0,
  );
}

import 'yorks_v1_rental.dart';

/// Presentation guidance from the authorized rental projection. These are
/// review destinations, never permission grants or automatic commands.
enum YorksRentalAction {
  rent,
  cheque,
  expiredLease,
  lease,
  billing,
  details;

  static YorksRentalAction? fromName(String? name) {
    for (final action in values) {
      if (action.name == name) return action;
    }
    return null;
  }
}

List<YorksRentalAction> rentalActions(YorksV1RentalProperty property) {
  final days = property.daysToLeaseEnd;
  return [
    if (!property.billingSetupPending && property.outstanding > 0)
      YorksRentalAction.rent,
    if (!property.isArchived) ...[
      if (property.chequeAttention) YorksRentalAction.cheque,
      if (property.leaseEnd != null && days != null)
        if (days < 0)
          YorksRentalAction.expiredLease
        else if (days <= property.renewalNoticeDays)
          YorksRentalAction.lease,
      if (property.billingSetupPending) YorksRentalAction.billing,
      if (property.missingFields.any((field) => field != 'billing_start'))
        YorksRentalAction.details,
    ],
  ];
}

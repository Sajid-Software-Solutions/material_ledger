/// R39 Accounts Workspace V2 — claims-list models.
///
/// Typed parse of `v1_list_client_claims` for the Progress & claims tab's
/// claim-cards row. The RPC is commercial-gated (it requires
/// view_project_commercial_values, or manage_client_invoices), so a caller
/// without access gets an error the controller treats as "no cards row" rather
/// than a value here. Monetary fields are decimal strings parsed through
/// [YorksAccountsDecimal].
library;

import '../accounts_decimal.dart';

/// One claim as shown on a claim card (reference, period, status, gross).
final class YorksAccountsClaimSummary {
  const YorksAccountsClaimSummary({
    required this.claimId,
    required this.reference,
    required this.status,
    required this.periodStart,
    required this.periodEnd,
    required this.grossExVat,
    required this.isStale,
    required this.recordVersion,
  });

  factory YorksAccountsClaimSummary.fromJson(Map<String, dynamic> json) {
    return YorksAccountsClaimSummary(
      claimId: json['claim_id'] as String,
      reference: json['claim_reference'] as String? ?? '',
      status: json['status'] as String? ?? 'draft',
      periodStart: json['claim_period_start'] as String?,
      periodEnd: json['claim_period_end'] as String?,
      grossExVat: json['claimed_ex_vat'] == null
          ? null
          : YorksAccountsDecimal.fromRpcValue(
              json['claimed_ex_vat'],
              key: 'claim.claimed_ex_vat',
            ),
      isStale: json['is_stale'] == true,
      recordVersion: (json['record_version'] as num?)?.toInt() ?? 1,
    );
  }

  final String claimId;
  final String reference;

  /// 'draft' | 'ready_for_accounts' | 'invoiced' | 'cancelled'.
  final String status;
  final String? periodStart;
  final String? periodEnd;
  final YorksAccountsDecimal? grossExVat;
  final bool isStale;
  final int recordVersion;
}

/// The project's claims, newest first, for the claim-cards row.
final class YorksAccountsClaimsList {
  const YorksAccountsClaimsList({required this.claims});

  factory YorksAccountsClaimsList.fromJson(Map<String, dynamic> json) {
    final list = (json['claims'] as List?) ?? const <dynamic>[];
    return YorksAccountsClaimsList(
      claims: list
          .map(
            (e) => YorksAccountsClaimSummary.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  static const empty = YorksAccountsClaimsList(
    claims: <YorksAccountsClaimSummary>[],
  );

  final List<YorksAccountsClaimSummary> claims;
}

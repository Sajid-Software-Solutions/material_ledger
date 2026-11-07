/// R39 Accounts Workspace V2 — contract variations (VO register) models.
///
/// Typed parse of `v1_list_accounts_variations`. The register is display/track
/// only: approved variations do not change the contract value. Amounts are
/// decimal strings parsed through [YorksAccountsDecimal].
library;

import '../accounts_decimal.dart';

/// One variation order (VO) in the register.
final class YorksAccountsVariation {
  const YorksAccountsVariation({
    required this.variationId,
    required this.voNumber,
    required this.description,
    required this.amount,
    required this.status,
    required this.recordVersion,
  });

  factory YorksAccountsVariation.fromJson(Map<String, dynamic> json) {
    return YorksAccountsVariation(
      variationId: json['variation_id'] as String,
      voNumber: json['vo_number'] as String? ?? '',
      description: json['description'] as String?,
      amount: json['amount'] == null
          ? null
          : YorksAccountsDecimal.fromRpcValue(
              json['amount'],
              key: 'variation.amount',
            ),
      status: json['status'] as String? ?? 'pending',
      recordVersion: (json['record_version'] as num?)?.toInt() ?? 1,
    );
  }

  final String variationId;
  final String voNumber;
  final String? description;
  final YorksAccountsDecimal? amount;

  /// 'pending' | 'approved' | 'rejected'.
  final String status;
  final int recordVersion;
}

/// The project's variations plus whether the actor may edit them.
final class YorksAccountsVariationsList {
  const YorksAccountsVariationsList({
    required this.variations,
    required this.canConfigure,
  });

  factory YorksAccountsVariationsList.fromJson(Map<String, dynamic> json) {
    final list = (json['variations'] as List?) ?? const <dynamic>[];
    return YorksAccountsVariationsList(
      variations: list
          .map(
            (e) => YorksAccountsVariation.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(growable: false),
      canConfigure: json['can_configure'] == true,
    );
  }

  static const empty = YorksAccountsVariationsList(
    variations: <YorksAccountsVariation>[],
    canConfigure: false,
  );

  final List<YorksAccountsVariation> variations;
  final bool canConfigure;
}

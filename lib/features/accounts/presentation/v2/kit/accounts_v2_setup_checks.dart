/// R39 Accounts Workspace V2 — the Contract setup checks, as the prototype
/// lists them: contract value, buildings to 100%, stages to 100%, and one line
/// per item-measured stage whose item weights must make up that stage.
///
/// These mirror rules the server enforces on save; they only tell the person
/// what is left to fix. Figures go through doubles for display only.
library;

import '../../../domain/v2/commercial_setup_read_models.dart';

enum AccountsV2SetupCheckKind { contractValue, buildings, stages, items }

/// One check and the figures its line is written from.
final class AccountsV2SetupCheck {
  const AccountsV2SetupCheck({
    required this.kind,
    required this.ok,
    this.current = 0,
    this.needed = 0,
    this.stageKey,
    this.stageName,
    this.shortfallAmount = 0,
  });

  final AccountsV2SetupCheckKind kind;
  final bool ok;

  /// Contract value, or the current percent total.
  final double current;

  /// For an item stage: the percent of contract one building needs.
  final double needed;
  final String? stageKey;
  final String? stageName;

  /// For an item stage: the money the items are short (+) or over (−) by.
  final double shortfallAmount;
}

double _d(Object? decimal) => double.tryParse('$decimal') ?? 0;

/// One stage as the checks need it.
typedef AccountsV2CheckStage = ({
  String key,
  String name,
  double percent,
  bool byItems,

  /// Item weights (percent of contract) per building id. A null key is one
  /// list every building shares, as the contract editor saves it.
  Map<String?, List<double>> weights,
});

/// The checks for a contract being edited or as stored, in the prototype's
/// order: value, buildings, stages, then one per item-measured stage.
List<AccountsV2SetupCheck> accountsV2SetupChecksFrom({
  required double contract,
  required List<({String id, double share})> buildings,
  required List<AccountsV2CheckStage> stages,
}) {
  const epsilon = 0.005;
  final buildingTotal = buildings.fold<double>(0, (a, b) => a + b.share);
  final stageTotal = stages.fold<double>(0, (a, s) => a + s.percent);
  final checks = <AccountsV2SetupCheck>[
    AccountsV2SetupCheck(
      kind: AccountsV2SetupCheckKind.contractValue,
      ok: contract > 0,
      current: contract,
    ),
    AccountsV2SetupCheck(
      kind: AccountsV2SetupCheckKind.buildings,
      ok: buildings.isNotEmpty && (buildingTotal - 100).abs() < epsilon,
      current: buildingTotal,
    ),
    AccountsV2SetupCheck(
      kind: AccountsV2SetupCheckKind.stages,
      ok: (stageTotal - 100).abs() < epsilon,
      current: stageTotal,
    ),
  ];
  for (final stage in stages) {
    if (!stage.byItems) continue;
    // Each building's items must make up that building's share of the stage.
    // The line reports the first building that does not, else the first one.
    AccountsV2SetupCheck? first;
    AccountsV2SetupCheck? failing;
    for (final building in buildings) {
      final need = building.share * stage.percent / 100;
      final list =
          stage.weights[building.id] ?? stage.weights[null] ?? const [];
      final have = list.fold<double>(0, (a, w) => a + w);
      final check = AccountsV2SetupCheck(
        kind: AccountsV2SetupCheckKind.items,
        ok: list.isNotEmpty && (have - need).abs() < 0.0005,
        current: have,
        needed: need,
        stageKey: stage.key,
        stageName: stage.name,
        shortfallAmount: (need - have) * contract / 100,
      );
      first ??= check;
      if (!check.ok) {
        failing = check;
        break;
      }
    }
    checks.add(
      failing ??
          first ??
          AccountsV2SetupCheck(
            kind: AccountsV2SetupCheckKind.items,
            ok: false,
            stageKey: stage.key,
            stageName: stage.name,
          ),
    );
  }
  return checks;
}

/// The checks for a stored contract.
List<AccountsV2SetupCheck> accountsV2SetupChecks(
  YorksAccountsCommercialSetupRead setup,
) {
  return accountsV2SetupChecksFrom(
    contract: _d(setup.contractValue?.canonicalText),
    buildings: [
      for (final b in setup.buildings)
        (id: b.projectScopeId, share: _d(b.allocationPercent.canonicalText)),
    ],
    stages: [
      for (final s in setup.stages)
        (
          key: s.stageKey,
          name: s.stageName,
          percent: _d(s.allocationPercent.canonicalText),
          byItems: s.measurementMode == 'items',
          weights: {
            for (final b in setup.buildings)
              b.projectScopeId: [
                for (final i in setup.items)
                  if (i.stageKey == s.stageKey &&
                      i.projectScopeId == b.projectScopeId)
                    _d(i.weightPercentOfContract.canonicalText),
              ],
          },
        ),
    ],
  );
}

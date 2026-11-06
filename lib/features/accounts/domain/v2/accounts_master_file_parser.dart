/// R39 Accounts Workspace V2 — Project Master File parser (Import, S1).
///
/// Pure-Dart mapping from a decoded Project Master File workbook to an editable
/// [YorksAccountsMasterFileDraft] for the Contract-tab import preview. The parser
/// takes already-decoded sheet grids (sheet name → rows of cells) so it is
/// independent of any spreadsheet library; wiring the real `.xlsx` decode into
/// these grids, and the preview/confirm UI, are the next increment (S2).
///
/// Layout (confirmed 7 Nov 2026 against "Project Master File - Nexus 4 Station",
/// Yorks Ref YRA-322) and the authoritative-value decision are documented in
/// `docs/yorks-v1/ACCOUNTS_V2_IMPORT_MASTER_FILE_SCOPE.md` §5. Percentages in the
/// workbook are fractions (0.1 = 10%) and are kept as fractions here; the
/// fraction→percent conversion happens when the confirmed draft is turned into a
/// `v1_save_project_commercial_setup` payload (S2/S4). Item quantities, building
/// shares and weights are base-independent, so only the top-line contract value
/// differs between the master file (18,085,468) and the authoritative signed
/// invoice (17,192,000); the draft uses the authoritative value and records the
/// discrepancy rather than silently picking one (AGENTS: never reinterpret or
/// silently omit).
library;

import '../accounts_decimal.dart';

/// A decoded worksheet: rows of cells, each cell a String, num, DateTime or null.
typedef YorksAccountsMasterSheet = List<List<Object?>>;

enum YorksAccountsMasterIssueSeverity { warning, info }

/// A reconciliation note surfaced to the preview (never a silent drop).
final class YorksAccountsMasterFileIssue {
  const YorksAccountsMasterFileIssue({
    required this.severity,
    required this.code,
    required this.message,
  });

  final YorksAccountsMasterIssueSeverity severity;
  final String code;
  final String message;
}

/// One building from the Summery (Option) per-building blocks.
final class YorksAccountsMasterBuilding {
  const YorksAccountsMasterBuilding({
    required this.blockLetter,
    required this.name,
    required this.code,
    required this.fraction,
    this.statedContractValue,
  });

  final String blockLetter;
  final String name;

  /// The substation code parsed from the name, e.g. `DF3W`; null if absent.
  final String? code;

  /// Building share of the contract as a fraction (0.25 = 25%).
  final YorksAccountsDecimal fraction;

  /// The contract value this block stated (used to flag an internal mismatch).
  final YorksAccountsDecimal? statedContractValue;
}

/// One stage from the ALL PROJECT SUMMARY block.
final class YorksAccountsMasterStage {
  const YorksAccountsMasterStage({
    required this.key,
    required this.label,
    required this.fraction,
    required this.mode,
  });

  final String key;
  final String label;

  /// Stage share of the contract as a fraction (0.1 = 10%).
  final YorksAccountsDecimal fraction;

  /// 'percent' or 'items' (Material Supply and Installation are items-mode, D3).
  final String mode;
}

/// One item from a Material / Installation per-building block.
final class YorksAccountsMasterItem {
  const YorksAccountsMasterItem({
    required this.buildingCode,
    required this.stageKey,
    required this.itemNo,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.weightFraction,
  });

  final String? buildingCode;
  final String stageKey;
  final String itemNo;
  final String name;
  final YorksAccountsDecimal quantity;

  /// The workbook has no unit column; null means the preview must set one.
  final String? unit;

  /// Weight as a fraction of the total contract (0.045 = 4.5%).
  final YorksAccountsDecimal weightFraction;
}

/// The parsed, editable master-file draft.
final class YorksAccountsMasterFileDraft {
  const YorksAccountsMasterFileDraft({
    required this.contractValue,
    required this.fileContractValue,
    required this.currencyCode,
    required this.buildings,
    required this.stages,
    required this.items,
    required this.issues,
  });

  /// The value the baseline will use — the authoritative one supplied to the
  /// parser (the signed invoice), not necessarily the file's.
  final YorksAccountsDecimal contractValue;

  /// The total the workbook itself stated (may differ — see [issues]).
  final YorksAccountsDecimal? fileContractValue;
  final String currencyCode;
  final List<YorksAccountsMasterBuilding> buildings;
  final List<YorksAccountsMasterStage> stages;
  final List<YorksAccountsMasterItem> items;
  final List<YorksAccountsMasterFileIssue> issues;

  bool get hasWarnings =>
      issues.any((i) => i.severity == YorksAccountsMasterIssueSeverity.warning);
}

/// Maps a decoded Project Master File workbook to a [YorksAccountsMasterFileDraft].
final class YorksAccountsMasterFileParser {
  const YorksAccountsMasterFileParser();

  /// Canonical stage keys for Material Supply and Installation (items-mode, D3).
  static const _itemsStageKeys = {'material_supply', 'installation'};

  /// Parses [sheets] (keys matched case-insensitively, trimmed) against the
  /// [expectedContractValue] the owner declared authoritative.
  YorksAccountsMasterFileDraft parse({
    required Map<String, YorksAccountsMasterSheet> sheets,
    required YorksAccountsDecimal expectedContractValue,
    String currencyCode = 'AED',
  }) {
    final issues = <YorksAccountsMasterFileIssue>[];
    final byName = <String, YorksAccountsMasterSheet>{
      for (final e in sheets.entries) e.key.trim().toLowerCase(): e.value,
    };

    final summery = _find(byName, const [
      'summery (option)',
      'summary',
      'summery',
    ]);
    final material = _find(byName, const ['material', 'material supply']);
    final installation = _find(byName, const ['installation']);

    YorksAccountsDecimal? fileContractValue;
    final buildings = <YorksAccountsMasterBuilding>[];
    final stages = <YorksAccountsMasterStage>[];

    if (summery == null) {
      issues.add(
        const YorksAccountsMasterFileIssue(
          severity: YorksAccountsMasterIssueSeverity.warning,
          code: 'summery_missing',
          message:
              'No Summery (Option) sheet found; buildings and stages '
              'could not be read.',
        ),
      );
    } else {
      for (var i = 0; i < summery.length; i++) {
        final row = summery[i];
        final label = _str(row, 3);
        // Per-building block header: col D == 'Contract Value' (title case).
        if (label == 'Contract Value') {
          final name = _str(row, 2) ?? '';
          final stated = _dec(row, 5);
          final next = (i + 1 < summery.length) ? summery[i + 1] : const [];
          final fraction = _dec(next, 4) ?? YorksAccountsDecimal.zero;
          buildings.add(
            YorksAccountsMasterBuilding(
              blockLetter: _str(row, 1) ?? '',
              name: name,
              code: _code(name),
              fraction: fraction,
              statedContractValue: stated,
            ),
          );
        }
        // ALL PROJECT SUMMARY total: col D == 'CONTRACT VALUE' (upper case).
        if (label == 'CONTRACT VALUE') {
          fileContractValue = _dec(row, 5);
          for (var j = i + 1; j < summery.length; j++) {
            final c = _str(summery[j], 2);
            if (c == null) continue;
            if (c.toUpperCase() == 'TOTAL') break;
            final key = _stageKey(c);
            if (key == null) {
              issues.add(
                YorksAccountsMasterFileIssue(
                  severity: YorksAccountsMasterIssueSeverity.info,
                  code: 'stage_unmapped',
                  message: 'Unrecognised stage "$c" was not mapped.',
                ),
              );
              continue;
            }
            if (stages.any((s) => s.key == key)) continue;
            stages.add(
              YorksAccountsMasterStage(
                key: key,
                label: c,
                fraction: _dec(summery[j], 3) ?? YorksAccountsDecimal.zero,
                mode: _itemsStageKeys.contains(key) ? 'items' : 'percent',
              ),
            );
          }
        }
      }
    }

    final items = <YorksAccountsMasterItem>[
      ..._items(material, 'material_supply'),
      ..._items(installation, 'installation'),
    ];

    // Reconciliation notes.
    if (fileContractValue != null &&
        fileContractValue.compareTo(expectedContractValue) != 0) {
      issues.add(
        YorksAccountsMasterFileIssue(
          severity: YorksAccountsMasterIssueSeverity.warning,
          code: 'contract_value_mismatch',
          message:
              'The workbook total ${fileContractValue.canonicalText} '
              'differs from the authoritative '
              '${expectedContractValue.canonicalText}; the authoritative value '
              'is used.',
        ),
      );
    }
    for (final b in buildings) {
      final stated = b.statedContractValue;
      if (stated != null &&
          fileContractValue != null &&
          stated.compareTo(fileContractValue) != 0) {
        issues.add(
          YorksAccountsMasterFileIssue(
            severity: YorksAccountsMasterIssueSeverity.warning,
            code: 'building_value_inconsistent',
            message:
                'Block ${b.blockLetter} states '
                '${stated.canonicalText}, which differs from the workbook '
                'total ${fileContractValue.canonicalText}.',
          ),
        );
      }
    }
    if (items.any((it) => it.unit == null)) {
      issues.add(
        const YorksAccountsMasterFileIssue(
          severity: YorksAccountsMasterIssueSeverity.info,
          code: 'item_units_missing',
          message:
              'The workbook has no unit column; set item units in the '
              'preview before confirming.',
        ),
      );
    }

    return YorksAccountsMasterFileDraft(
      contractValue: expectedContractValue,
      fileContractValue: fileContractValue,
      currencyCode: currencyCode,
      buildings: buildings,
      stages: stages,
      items: items,
      issues: issues,
    );
  }

  List<YorksAccountsMasterItem> _items(
    YorksAccountsMasterSheet? sheet,
    String stageKey,
  ) {
    if (sheet == null) return const [];
    final out = <YorksAccountsMasterItem>[];
    String? building;
    for (final row in sheet) {
      final b = _str(row, 1);
      if (b == null) continue;
      if (b.toUpperCase().contains('SUMMARY') ||
          b.toUpperCase().contains('DELIVERD') ||
          b.toUpperCase().contains('DELIVERED')) {
        building = _code(b);
        continue;
      }
      if (!_itemNo.hasMatch(b)) continue;
      final weight = _dec(row, 5);
      if (weight == null) continue; // sub-rows / totals carry no weight
      final name = _str(row, 3);
      if (name == null) continue;
      out.add(
        YorksAccountsMasterItem(
          buildingCode: building,
          stageKey: stageKey,
          itemNo: b,
          name: name,
          quantity: _dec(row, 4) ?? YorksAccountsDecimal.zero,
          unit: null,
          weightFraction: weight,
        ),
      );
    }
    return out;
  }

  static final _itemNo = RegExp(r'^[A-Za-z]\.\d+$');
  static final _codePattern = RegExp(r'\(([A-Za-z0-9]+)\)');

  static YorksAccountsMasterSheet? _find(
    Map<String, YorksAccountsMasterSheet> byName,
    List<String> candidates,
  ) {
    for (final c in candidates) {
      final hit = byName[c];
      if (hit != null) return hit;
    }
    // Fall back to a prefix match (handles trailing spaces / suffixes).
    for (final entry in byName.entries) {
      if (candidates.any((c) => entry.key.startsWith(c))) return entry.value;
    }
    return null;
  }

  static String? _code(String text) => _codePattern.firstMatch(text)?.group(1);

  static String? _str(List<Object?> row, int col) {
    if (col >= row.length) return null;
    final v = row[col];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static YorksAccountsDecimal? _dec(List<Object?> row, int col) {
    final s = _str(row, col);
    return s == null ? null : YorksAccountsDecimal.tryParse(s);
  }

  static String? _stageKey(String raw) {
    final v = raw.toLowerCase();
    if (v.contains('cooling load') || v.contains('design')) return 'design';
    if (v.contains('material supply') || v.contains('material')) {
      return 'material_supply';
    }
    if (v.contains('installation')) return 'installation';
    if (v.contains('comission') ||
        v.contains('commission') ||
        v.contains('handover')) {
      return 'commissioning_handover';
    }
    if (v.contains('energi')) return 'energizing';
    return null;
  }
}

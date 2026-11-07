/// R39 Accounts Workspace V2 — Project Master File parser.
///
/// Pure-Dart mapping from a decoded workbook (sheet name → rows of cells) to a
/// reviewable [YorksAccountsMasterFileDraft]. It reads both real layouts:
/// the Project Master File (`Summery (Option)`, no units column) and the invoice
/// workbook (`Summary`, with a `Units` column), locating item columns from the
/// `Item` header row rather than fixed positions.
///
/// Workbook numbers arrive as Excel's raw 17-digit text (for example
/// `4.4999999999999998E-2`). They are normalized to Excel's own 15 significant
/// digits with exact string arithmetic — never through a double — so a weight
/// reads as `0.045`.
///
/// Nothing is dropped silently: a row that cannot be read becomes a blocking
/// issue, so the import cannot be confirmed with part of the contract missing.
/// The contract value is never assumed. The caller passes the project's current
/// value, a difference is reported, and a person confirms the figure in review.
/// See `docs/yorks-v1/ACCOUNTS_V2_IMPORT_MASTER_FILE_SCOPE.md`.
library;

import '../accounts_decimal.dart';
import 'commercial_setup_models.dart';

/// A decoded worksheet: rows of cells, each usually a String.
typedef YorksAccountsMasterSheet = List<List<Object?>>;

/// `blocking` prevents confirming; the others are shown for review.
enum YorksAccountsMasterIssueSeverity { blocking, warning, info }

/// A reconciliation note. Its text is localized from [code] and [args] by the
/// presentation layer (key `v2_import_issue_<code>`).
final class YorksAccountsMasterFileIssue {
  const YorksAccountsMasterFileIssue({
    required this.severity,
    required this.code,
    this.args = const {},
  });

  final YorksAccountsMasterIssueSeverity severity;
  final String code;
  final Map<String, String> args;
}

/// One building from the summary's per-building blocks.
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

  /// The building code parsed from the name, for example `DF3W`.
  final String? code;

  /// Building share of the contract as a fraction (0.25 = 25%).
  final YorksAccountsDecimal fraction;

  /// The contract value this block stated (used to flag an internal mismatch).
  final YorksAccountsDecimal? statedContractValue;
}

/// One billing stage.
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

  /// 'percent' or 'items' (Material Supply and Installation are items-mode).
  final String mode;
}

/// One weighted item from a Material / Installation per-building block.
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

  /// Workbook number, for example `A.10.1`.
  final String itemNo;
  final String name;
  final YorksAccountsDecimal quantity;

  /// Null when the workbook has no unit column; review supplies a default.
  final String? unit;

  /// Weight as a fraction of the total contract (0.045 = 4.5%).
  final YorksAccountsDecimal weightFraction;

  /// Stable across buildings and revisions: `A.10.1` and `B.10.1` both give
  /// `10-1`, so progress carries forward by item.
  String get itemKey => itemNo.split('.').skip(1).join('-');
}

/// The parsed master-file draft, ready for review.
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

  /// The proposed value: the project's current value when it has one, otherwise
  /// the workbook's. Review may change it.
  final YorksAccountsDecimal contractValue;

  /// The total the workbook itself stated (may differ — see [issues]).
  final YorksAccountsDecimal? fileContractValue;
  final String currencyCode;
  final List<YorksAccountsMasterBuilding> buildings;
  final List<YorksAccountsMasterStage> stages;
  final List<YorksAccountsMasterItem> items;
  final List<YorksAccountsMasterFileIssue> issues;

  bool get hasBlockers => issues.any(
    (i) => i.severity == YorksAccountsMasterIssueSeverity.blocking,
  );

  bool get hasWarnings =>
      issues.any((i) => i.severity == YorksAccountsMasterIssueSeverity.warning);

  /// The item list for a stage. The server applies one list to every building,
  /// and the parser blocks a workbook whose buildings differ, so the first
  /// building's list represents them all.
  List<YorksAccountsMasterItem> itemsForStage(String stageKey) {
    final forStage = items.where((i) => i.stageKey == stageKey);
    if (forStage.isEmpty) return const [];
    final first = forStage.first.buildingCode;
    return forStage
        .where((i) => i.buildingCode == first)
        .toList(growable: false);
  }

  /// The `v1_save_project_commercial_setup` model. [scopeIdByCode] maps building
  /// codes to the project's scope ids; review blocks an unmatched building.
  YorksAccountsCommercialSetup toCommercialSetup({
    required YorksAccountsDecimal contractValue,
    required YorksAccountsDecimal vatRatePercent,
    required Map<String, String> scopeIdByCode,
    required String defaultUnit,
    int? paymentTermsDays,
    int? reminderLeadDays,
  }) {
    return YorksAccountsCommercialSetup(
      contractValue: contractValue,
      currencyCode: currencyCode,
      vatRatePercent: vatRatePercent,
      paymentTermsDays: paymentTermsDays,
      reminderLeadDays: reminderLeadDays,
      buildings: [
        for (final b in buildings)
          YorksAccountsSetupBuilding(
            buildingScopeId: scopeIdByCode[b.code]!,
            allocationPercent: yorksAccountsFractionToPercent(b.fraction),
          ),
      ],
      stages: [
        for (final (index, s) in stages.indexed)
          YorksAccountsSetupStage(
            stageKey: s.key,
            stageLabel: s.label,
            allocationPercent: yorksAccountsFractionToPercent(s.fraction),
            position: index + 1,
            measurementMode: s.mode,
            items: [
              for (final (order, item) in itemsForStage(s.key).indexed)
                YorksAccountsSetupItem(
                  itemKey: item.itemKey,
                  itemLabel: item.name,
                  displayOrder: order + 1,
                  quantity: item.quantity,
                  unitCode: item.unit ?? defaultUnit,
                  weightPercentOfContract: yorksAccountsFractionToPercent(
                    item.weightFraction,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// Exactly converts a fraction to a percent (0.045 → 4.5) by moving the decimal
/// point, without floating-point arithmetic.
YorksAccountsDecimal yorksAccountsFractionToPercent(
  YorksAccountsDecimal fraction,
) {
  final shifted = _normalizeNumber('${fraction.canonicalText}E2');
  return YorksAccountsDecimal.parse(shifted!);
}

final _numberPattern = RegExp(r'^([+-]?)(\d*)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$');

/// Normalizes Excel's raw numeric text to plain decimal text at 15 significant
/// digits and at most 8 fraction digits (a fraction of 8 digits is a percent of
/// 6, the precision the server stores). Returns null when [raw] is not a number.
String? _normalizeNumber(String raw) {
  final match = _numberPattern.firstMatch(raw.trim());
  if (match == null) return null;
  final whole = match.group(2) ?? '';
  final fraction = match.group(3) ?? '';
  if (whole.isEmpty && fraction.isEmpty) return null;
  final negative = match.group(1) == '-';
  var digits = '$whole$fraction';
  var point = whole.length + int.parse(match.group(4) ?? '0');

  final leading =
      digits.length - digits.replaceFirst(RegExp(r'^0+'), '').length;
  digits = digits.substring(leading);
  point -= leading;
  if (digits.isEmpty) return '0';

  (String, int) round(String value, int pointAt, int keep) {
    if (keep < 0) return ('', pointAt);
    if (value.length <= keep) return (value, pointAt);
    var kept = keep == 0 ? BigInt.zero : BigInt.parse(value.substring(0, keep));
    if (value.codeUnitAt(keep) >= 0x35) kept += BigInt.one;
    if (kept == BigInt.zero) return ('', pointAt);
    final text = kept.toString();
    return (text, pointAt + (text.length - keep));
  }

  (digits, point) = round(digits, point, 15);
  // At most 8 fraction digits means keeping (point + 8) significant digits.
  (digits, point) = round(digits, point, point + 8);
  if (digits.isEmpty) return '0';

  final String body;
  if (point <= 0) {
    body = '0.${'0' * -point}$digits';
  } else if (point >= digits.length) {
    body = '$digits${'0' * (point - digits.length)}';
  } else {
    body = '${digits.substring(0, point)}.${digits.substring(point)}';
  }
  final trimmed = body.contains('.')
      ? body.replaceFirst(RegExp(r'\.?0+$'), '')
      : body;
  return negative ? '-$trimmed' : trimmed;
}

/// Maps a decoded workbook to a [YorksAccountsMasterFileDraft].
final class YorksAccountsMasterFileParser {
  const YorksAccountsMasterFileParser();

  static const _itemsStageKeys = {'material_supply', 'installation'};
  static final _itemNo = RegExp(r'^[A-Za-z]\.\d+(\.\d+)*$');
  static final _codePattern = RegExp(r'\(([A-Za-z0-9]+)\)\s*$');

  /// Parses [sheets] (names matched case-insensitively, trimmed). Pass the
  /// project's current contract value as [expectedContractValue] so a differing
  /// workbook total is reported; pass null for a project with no contract yet.
  YorksAccountsMasterFileDraft parse({
    required Map<String, YorksAccountsMasterSheet> sheets,
    YorksAccountsDecimal? expectedContractValue,
    String currencyCode = 'AED',
  }) {
    final issues = <YorksAccountsMasterFileIssue>[];
    final byName = <String, YorksAccountsMasterSheet>{
      for (final e in sheets.entries) e.key.trim().toLowerCase(): e.value,
    };

    final summary = _find(byName, const [
      'summery (option)',
      'summary',
      'summery',
    ]);
    final material = _find(byName, const ['material', 'material supply']);
    final installation = _find(byName, const ['installation']);

    YorksAccountsDecimal? fileContractValue;
    final buildings = <YorksAccountsMasterBuilding>[];
    final stages = <YorksAccountsMasterStage>[];

    void readStages(
      YorksAccountsMasterSheet sheet,
      int from,
      List<YorksAccountsMasterStage> into,
    ) {
      for (var j = from; j < sheet.length; j++) {
        if (_str(sheet[j], 3) == 'Contract Value') break;
        final label = _str(sheet[j], 2);
        if (label == null) continue;
        // TOTAL, or the invoice workbook's SUB TOTAL / GRAND TOTAL, ends the stages.
        if (label.toUpperCase().contains('TOTAL')) break;
        final key = _stageKey(label);
        if (key == null) {
          issues.add(
            YorksAccountsMasterFileIssue(
              severity: YorksAccountsMasterIssueSeverity.blocking,
              code: 'stage_unmapped',
              args: {'stage': label},
            ),
          );
          continue;
        }
        if (into.any((s) => s.key == key)) continue;
        into.add(
          YorksAccountsMasterStage(
            key: key,
            label: label,
            fraction: _dec(sheet[j], 3) ?? YorksAccountsDecimal.zero,
            mode: _itemsStageKeys.contains(key) ? 'items' : 'percent',
          ),
        );
      }
    }

    if (summary == null) {
      issues.add(
        const YorksAccountsMasterFileIssue(
          severity: YorksAccountsMasterIssueSeverity.blocking,
          code: 'summary_missing',
        ),
      );
    } else {
      var totalRow = -1;
      int? firstBlockRow;
      for (var i = 0; i < summary.length; i++) {
        final row = summary[i];
        final label = _str(row, 3);
        if (label == 'Contract Value') {
          final name = _str(row, 2) ?? '';
          final next = i + 1 < summary.length ? summary[i + 1] : const [];
          firstBlockRow ??= i + 2;
          buildings.add(
            YorksAccountsMasterBuilding(
              blockLetter: _str(row, 1) ?? '',
              name: name,
              code: _code(name),
              fraction: _dec(next, 4) ?? YorksAccountsDecimal.zero,
              statedContractValue: _dec(row, 5),
            ),
          );
        } else if (label == 'CONTRACT VALUE') {
          fileContractValue = _dec(row, 5);
          totalRow = i;
        }
      }
      if (totalRow >= 0) {
        readStages(summary, totalRow + 1, stages);
      }
      // A summary with no all-project block: the first building's rows list them.
      if (stages.isEmpty && firstBlockRow != null) {
        readStages(summary, firstBlockRow, stages);
      }
      fileContractValue ??= buildings.isEmpty
          ? null
          : buildings.first.statedContractValue;
      if (buildings.isEmpty || stages.isEmpty) {
        issues.add(
          const YorksAccountsMasterFileIssue(
            severity: YorksAccountsMasterIssueSeverity.blocking,
            code: 'summary_unreadable',
          ),
        );
      }
      for (final b in buildings.where((b) => b.code == null)) {
        issues.add(
          YorksAccountsMasterFileIssue(
            severity: YorksAccountsMasterIssueSeverity.blocking,
            code: 'building_code_missing',
            args: {'building': b.name},
          ),
        );
      }
    }

    final items = <YorksAccountsMasterItem>[
      ..._items(material, 'material_supply', issues),
      ..._items(installation, 'installation', issues),
    ];
    for (final s in stages.where((s) => s.mode == 'items')) {
      if (!items.any((i) => i.stageKey == s.key)) {
        issues.add(
          YorksAccountsMasterFileIssue(
            severity: YorksAccountsMasterIssueSeverity.blocking,
            code: 'stage_items_missing',
            args: {'stage': s.label},
          ),
        );
      }
    }
    _checkBuildings(buildings, items, issues);

    if (expectedContractValue != null &&
        fileContractValue != null &&
        fileContractValue.compareTo(expectedContractValue) != 0) {
      issues.add(
        YorksAccountsMasterFileIssue(
          severity: YorksAccountsMasterIssueSeverity.warning,
          code: 'contract_value_mismatch',
          args: {
            'file': fileContractValue.canonicalText,
            'current': expectedContractValue.canonicalText,
          },
        ),
      );
    }
    final total = fileContractValue;
    if (total != null) {
      for (final b in buildings) {
        final stated = b.statedContractValue;
        if (stated != null && stated.compareTo(total) != 0) {
          issues.add(
            YorksAccountsMasterFileIssue(
              severity: YorksAccountsMasterIssueSeverity.warning,
              code: 'building_value_inconsistent',
              args: {
                'building': b.code ?? b.blockLetter,
                'stated': stated.canonicalText,
                'total': total.canonicalText,
              },
            ),
          );
        }
      }
    }
    if (items.any((i) => i.unit == null)) {
      issues.add(
        const YorksAccountsMasterFileIssue(
          severity: YorksAccountsMasterIssueSeverity.info,
          code: 'item_units_missing',
        ),
      );
    }

    return YorksAccountsMasterFileDraft(
      contractValue:
          expectedContractValue ??
          fileContractValue ??
          YorksAccountsDecimal.zero,
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
    List<YorksAccountsMasterFileIssue> issues,
  ) {
    if (sheet == null) return const [];
    final out = <YorksAccountsMasterItem>[];
    String? building;
    int? qtyCol;
    int? unitCol;
    int? weightCol;
    YorksAccountsDecimal? target;
    var sum = YorksAccountsDecimal.zero;
    var seen = false;
    String? parentNo;
    String? parentName;
    final unweighted = <String, String>{};

    void closeBlock() {
      if (!seen) return;
      unweighted.forEach((no, name) {
        issues.add(
          YorksAccountsMasterFileIssue(
            severity: YorksAccountsMasterIssueSeverity.blocking,
            code: 'item_without_weight',
            args: {'item': '$no $name', 'building': building ?? ''},
          ),
        );
      });
      if (target != null && sum.compareTo(target!) != 0) {
        issues.add(
          YorksAccountsMasterFileIssue(
            severity: YorksAccountsMasterIssueSeverity.blocking,
            code: 'item_weights_mismatch',
            args: {
              'building': building ?? '',
              'stage': stageKey,
              'have': sum.canonicalText,
              'need': target!.canonicalText,
            },
          ),
        );
      }
      unweighted.clear();
      target = null;
      sum = YorksAccountsDecimal.zero;
      seen = false;
      parentNo = null;
      parentName = null;
    }

    for (final row in sheet) {
      final b = _str(row, 1);
      final c = _str(row, 2);
      if (b != null && b.toUpperCase().contains('SUMMARY')) {
        closeBlock();
        building = _code(b);
        continue;
      }
      if (b == 'Item') {
        qtyCol = unitCol = weightCol = null;
        for (var col = 0; col < row.length; col++) {
          final head = _str(row, col)?.toLowerCase();
          if (head == null) continue;
          if (head.contains('qty')) qtyCol = col;
          if (head == 'unit' || head == 'units') unitCol = col;
          if (head == 'weight') weightCol = col;
        }
        continue;
      }
      if (b != null && b.toUpperCase() == 'TOTAL') continue;
      if (weightCol == null || qtyCol == null) continue;

      final no = (b != null && _itemNo.hasMatch(b))
          ? b
          : (c != null && _itemNo.hasMatch(c) ? c : null);
      if (no == null) {
        // The stage row above the items states the block's expected weight.
        final stated = _dec(row, weightCol);
        if (c != null && stated != null) target ??= stated;
        continue;
      }

      seen = true;
      final name = _str(row, 3) ?? '';
      final weightText = _str(row, weightCol);
      final depth = no.split('.').length;
      final isChild = parentNo != null && no.startsWith('$parentNo.');

      if (weightText == null) {
        // A top-level row with no weight groups weighted children (A.10 Ducting
        // works). A child with no weight only breaks down a weighted parent's
        // quantity (A.1.1 System-01), so it is not an item.
        if (depth == 2) {
          parentNo = no;
          parentName = name;
          unweighted[no] = name;
        }
        continue;
      }

      if (depth == 2) {
        parentNo = no;
        parentName = name;
      }
      if (isChild) unweighted.remove(parentNo);

      final weight = _dec(row, weightCol);
      final quantity = _dec(row, qtyCol);
      if (weight == null || quantity == null || name.isEmpty) {
        issues.add(
          YorksAccountsMasterFileIssue(
            severity: YorksAccountsMasterIssueSeverity.blocking,
            code: 'item_unreadable',
            args: {'item': '$no $name', 'building': building ?? ''},
          ),
        );
        continue;
      }
      sum += weight;
      out.add(
        YorksAccountsMasterItem(
          buildingCode: building,
          stageKey: stageKey,
          itemNo: no,
          name: isChild ? '$parentName — $name' : name,
          quantity: quantity,
          unit: unitCol == null ? null : _str(row, unitCol),
          weightFraction: weight,
        ),
      );
    }
    closeBlock();
    return out;
  }

  /// The server applies one item list to every building, so items must exist
  /// for known buildings and every building's list must match.
  void _checkBuildings(
    List<YorksAccountsMasterBuilding> buildings,
    List<YorksAccountsMasterItem> items,
    List<YorksAccountsMasterFileIssue> issues,
  ) {
    final known = buildings.map((b) => b.code).toSet();
    final unknown = items.map((i) => i.buildingCode).toSet().difference(known);
    for (final code in unknown) {
      issues.add(
        YorksAccountsMasterFileIssue(
          severity: YorksAccountsMasterIssueSeverity.blocking,
          code: 'item_building_unknown',
          args: {'building': code ?? ''},
        ),
      );
    }
    for (final stageKey in _itemsStageKeys) {
      final forStage = items.where((i) => i.stageKey == stageKey);
      if (forStage.isEmpty) continue;
      // Compared by content, not number: the real master file repeats one number
      // in three Installation blocks, which shifts the later numbers by one.
      String signature(String? code) => forStage
          .where((i) => i.buildingCode == code)
          .map(
            (i) =>
                '${i.name.toLowerCase()}|${i.quantity.canonicalText}|'
                '${i.weightFraction.canonicalText}',
          )
          .join(';');
      final first = buildings.isEmpty ? null : buildings.first.code;
      final keys = forStage
          .where((i) => i.buildingCode == first)
          .map((i) => i.itemKey)
          .toList();
      if (keys.toSet().length != keys.length) {
        issues.add(
          YorksAccountsMasterFileIssue(
            severity: YorksAccountsMasterIssueSeverity.blocking,
            code: 'item_number_duplicate',
            args: {'building': first ?? '', 'stage': stageKey},
          ),
        );
      }
      final reference = signature(
        buildings.isEmpty ? null : buildings.first.code,
      );
      for (final b in buildings.skip(1)) {
        if (signature(b.code) != reference) {
          issues.add(
            YorksAccountsMasterFileIssue(
              severity: YorksAccountsMasterIssueSeverity.blocking,
              code: 'item_sets_differ',
              args: {'building': b.code ?? b.blockLetter, 'stage': stageKey},
            ),
          );
        }
      }
    }
  }

  static YorksAccountsMasterSheet? _find(
    Map<String, YorksAccountsMasterSheet> byName,
    List<String> candidates,
  ) {
    for (final c in candidates) {
      final hit = byName[c];
      if (hit != null) return hit;
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
    if (s == null) return null;
    final normalized = _normalizeNumber(s);
    return normalized == null
        ? null
        : YorksAccountsDecimal.tryParse(normalized);
  }

  static String? _stageKey(String raw) {
    final v = raw.toLowerCase();
    if (v.contains('cooling load') || v.contains('design')) return 'design';
    if (v.contains('material')) return 'material_supply';
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

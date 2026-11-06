import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/accounts/domain/accounts_decimal.dart';
import 'package:material_ledger/features/accounts/domain/v2/accounts_master_file_parser.dart';

/// The fixtures below use the raw cell text the XLSX codec really returns for the
/// YRA-322 workbooks, including Excel's 17-digit exponents, weighted sub-rows,
/// the `Lot ` grouping row and the `(A) ...` header prefix. Clean hand-typed
/// values hid a bug that dropped most items, so keep these raw.
List<Object?> _row(Map<int, Object?> cells, {int width = 9}) {
  final row = List<Object?>.filled(width, '');
  cells.forEach((c, v) => row[c] = v);
  return row;
}

const _letters = {'DF3W': 'A', 'DF4W': 'B', 'DF6W': 'C', 'DF7W': 'D'};

YorksAccountsMasterSheet _summary({
  String total = '18085468',
  String df7wStated = '17192000',
}) {
  List<List<Object?>> block(String code) {
    final letter = _letters[code]!;
    return [
      _row({
        1: letter,
        2: '132/22Kv Substation- ($code)',
        3: 'Contract Value',
        5: code == 'DF7W' ? df7wStated : total,
      }),
      _row({3: '1', 4: '0.25', 5: '4521367'}),
      _row({
        1: '$letter.1',
        2: 'Cooling Load Design',
        3: '0.1',
        4: '2.5000000000000001E-2',
      }),
      _row({2: 'TOTAL', 3: '1', 4: '0.25'}),
    ];
  }

  return [
    for (final code in _letters.keys) ...block(code),
    _row({1: 'ALL PROJECT SUMMARY  (DF3W,DF4W,DF6W,DF7W)'}),
    _row({3: 'CONTRACT VALUE', 5: total}),
    _row({1: '1.1', 2: 'Cooling Load Design', 3: '0.1', 4: '0.1'}),
    _row({1: '1.2', 2: 'Material Supply', 3: '0.5', 4: '0.5'}),
    _row({1: '1.3', 2: 'Progress Installation', 3: '0.3', 4: '0.3'}),
    _row({1: '1.4', 2: 'Comissioning & Handover', 3: '0.05', 4: '0.05'}),
    _row({1: '1.5', 2: 'Energizing Substation', 3: '0.05', 4: '0.05'}),
    _row({2: 'TOTAL', 3: '1', 4: '1'}),
    _row({2: 'SUB TOTAL', 3: '1'}),
  ];
}

/// One real-shaped item block (master layout: no Units column).
List<List<Object?>> _materialBlock(
  String code, {
  String acWeight = '4.4999999999999998E-2',
}) {
  final l = _letters[code]!;
  return [
    _row({1: 'DELIVERD MATERIAL SUMMARY  ($code)'}),
    _row({
      1: 'Item',
      2: 'Description',
      4: 'Total Qty.',
      5: 'WEIGHT',
      6: 'Contract',
      7: '46289',
    }),
    _row({1: l, 2: 'Total Contract Value', 6: '18085468'}),
    _row({2: 'Material Supply', 5: '0.125', 6: '2260683.5'}),
    _row({
      1: '$l.1',
      3: 'AC Units (Package Unit)',
      4: '6',
      5: acWeight,
      6: '813846.05999999994',
      7: '6',
    }),
    _row({2: '$l.1.1', 3: 'System-01', 4: '3'}),
    _row({2: '$l.1.2', 3: 'System-02', 4: '3'}),
    _row({
      1: '$l.2',
      3: 'Ventilation Fans ',
      4: '30',
      5: '0.01',
      6: '180854.68',
    }),
    _row({1: '$l.3', 3: 'Ducting works ', 4: 'Lot '}),
    _row({
      2: '$l.3.1',
      3: 'Basement Floor',
      4: '1',
      5: '5.0000000000000001E-3',
    }),
    _row({2: '$l.3.2', 3: 'Roof', 4: '1', 5: '6.5000000000000002E-2'}),
    _row({1: 'TOTAL', 5: '0.12500000000000003', 6: '2260683.5000000009'}),
  ];
}

List<List<Object?>> _installationBlock(
  String code, {
  bool shiftNumbers = false,
}) {
  final l = _letters[code]!;
  return [
    _row({1: '(${_letters[code]}) MATERIAL INSTALLATION SUMMARY  ($code)'}),
    _row({
      1: 'Item',
      2: 'Description',
      4: 'Total Qty.',
      5: 'WEIGHT',
      6: 'Contract',
    }),
    _row({2: 'Material Supply', 5: '7.4999999999999997E-2', 6: '1356410.1'}),
    _row({1: '$l.1', 3: 'AC Units (Package Unit)', 4: '6', 5: '0.02'}),
    // The real DF4W/DF6W/DF7W blocks repeat a number here.
    _row({
      1: shiftNumbers ? '$l.1' : '$l.2',
      3: 'Fire Dampers',
      4: '55',
      5: '5.5E-2',
    }),
  ];
}

Map<String, YorksAccountsMasterSheet> _master({
  YorksAccountsMasterSheet? summary,
  String df6wAcWeight = '4.4999999999999998E-2',
}) => {
  'Summery (Option)': summary ?? _summary(),
  'Material': [
    for (final code in _letters.keys)
      ..._materialBlock(
        code,
        acWeight: code == 'DF6W' ? df6wAcWeight : '4.4999999999999998E-2',
      ),
  ],
  'Material submittal': [
    _row({1: 'Item', 5: 'WEIGHT'}),
  ],
  'Installation': [
    for (final code in _letters.keys)
      ..._installationBlock(code, shiftNumbers: code != 'DF3W'),
  ],
};

void main() {
  const parser = YorksAccountsMasterFileParser();
  final current = YorksAccountsDecimal.parse('17192000');

  YorksAccountsMasterFileDraft parse([
    Map<String, YorksAccountsMasterSheet>? s,
  ]) => parser.parse(sheets: s ?? _master(), expectedContractValue: current);

  Set<String> codes(YorksAccountsMasterFileDraft d) =>
      d.issues.map((i) => i.code).toSet();

  group('contract value', () {
    test('proposes the current value and reports the workbook total', () {
      final d = parse();
      expect(d.contractValue.canonicalText, '17192000');
      expect(d.fileContractValue?.canonicalText, '18085468');
      expect(codes(d), contains('contract_value_mismatch'));
    });

    test('flags only the block that disagrees with the workbook total', () {
      final d = parse();
      final stray = d.issues.where(
        (i) => i.code == 'building_value_inconsistent',
      );
      expect(stray.single.args['building'], 'DF7W');
    });

    test('a project with no contract yet uses the workbook total', () {
      final d = parser.parse(sheets: _master());
      expect(d.contractValue.canonicalText, '18085468');
      expect(codes(d), isNot(contains('contract_value_mismatch')));
    });
  });

  group('structure', () {
    test('reads buildings by code and stops stages at any total row', () {
      final d = parse();
      expect(d.buildings.map((b) => b.code), ['DF3W', 'DF4W', 'DF6W', 'DF7W']);
      expect(d.stages.map((s) => s.key), [
        'design',
        'material_supply',
        'installation',
        'commissioning_handover',
        'energizing',
      ]);
      expect(codes(d), isNot(contains('stage_unmapped')));
    });

    test('does not mistake the Material submittal sheet for Material', () {
      expect(
        parse().items.where((i) => i.stageKey == 'material_supply').length,
        16,
      );
    });
  });

  group('items', () {
    test('reads Excel exponent weights exactly', () {
      final ac = parse().itemsForStage('material_supply').first;
      expect(ac.name, 'AC Units (Package Unit)');
      expect(ac.weightFraction.canonicalText, '0.045');
      expect(ac.quantity.canonicalText, '6');
    });

    test('keeps weighted sub-rows, skips quantity-only breakdowns', () {
      final names = parse().itemsForStage('material_supply').map((i) => i.name);
      expect(names, [
        'AC Units (Package Unit)',
        'Ventilation Fans',
        'Ducting works — Basement Floor',
        'Ducting works — Roof',
      ]);
    });

    test('item keys are stable across buildings', () {
      final d = parse();
      final keys = d.itemsForStage('material_supply').map((i) => i.itemKey);
      expect(keys, ['1', '2', '3-1', '3-2']);
    });

    test('tags Installation items with the code, not the (A) prefix', () {
      final d = parse();
      final buildings = d.items
          .where((i) => i.stageKey == 'installation')
          .map((i) => i.buildingCode)
          .toSet();
      expect(buildings, {'DF3W', 'DF4W', 'DF6W', 'DF7W'});
    });

    test('compares buildings by content, tolerating the shifted numbering', () {
      expect(codes(parse()), isNot(contains('item_sets_differ')));
      expect(parse().hasBlockers, isFalse);
    });

    test('blocks when a building really has different items', () {
      final d = parse(_master(df6wAcWeight: '0.05'));
      expect(codes(d), contains('item_sets_differ'));
      expect(d.hasBlockers, isTrue);
    });

    test('blocks when weights do not reach the stage total', () {
      final sheets = _master();
      sheets['Material'] = _materialBlock('DF3W', acWeight: '0.04');
      expect(codes(parse(sheets)), contains('item_weights_mismatch'));
    });

    test('blocks an unreadable weight rather than dropping the row', () {
      final sheets = _master();
      sheets['Material'] = _materialBlock('DF3W', acWeight: 'n/a');
      final d = parse(sheets);
      expect(codes(d), contains('item_unreadable'));
      expect(d.hasBlockers, isTrue);
    });

    test('blocks a repeated number in the template building', () {
      final sheets = _master();
      sheets['Installation'] = [
        ..._installationBlock('DF3W', shiftNumbers: true),
      ];
      expect(codes(parse(sheets)), contains('item_number_duplicate'));
    });

    test('blocks a missing summary', () {
      final d = parse({'Other': const []});
      expect(codes(d), contains('summary_missing'));
      expect(d.hasBlockers, isTrue);
    });
  });

  group('invoice workbook layout', () {
    test('reads the Units column wherever the header puts it', () {
      final sheets = _master();
      sheets['Material'] = [
        _row({1: '(A) DELIVERD MATERIAL SUMMARY (DF3W)'}),
        _row({
          1: 'Item',
          2: 'Description',
          4: 'Total Qty.',
          5: 'Units',
          6: 'WEIGHT',
          7: 'Contract',
        }),
        _row({
          2: 'Total Breakdown of Delivered Materials',
          6: '0.125',
          7: '2149000',
        }),
        _row({
          1: 'A.1',
          3: 'AC Units',
          4: '6',
          5: 'Nos',
          6: '0.125',
          7: '2149000',
        }),
      ];
      final item = parse(sheets).items.firstWhere((i) => i.name == 'AC Units');
      expect(item.unit, 'Nos');
      expect(item.weightFraction.canonicalText, '0.125');
    });
  });

  group('setup conversion', () {
    test('converts fractions to percents exactly, per the server contract', () {
      final d = parse();
      final setup = d.toCommercialSetup(
        contractValue: current,
        vatRatePercent: YorksAccountsDecimal.parse('5'),
        scopeIdByCode: {for (final c in _letters.keys) c: 'scope-$c'},
        defaultUnit: 'Nos',
      );
      expect(setup.contractValue.canonicalText, '17192000');
      expect(setup.isValid, isTrue);
      expect(setup.buildings.first.allocationPercent.canonicalText, '25');
      expect(setup.buildings.first.buildingScopeId, 'scope-DF3W');
      final supply = setup.stages.firstWhere(
        (s) => s.stageKey == 'material_supply',
      );
      expect(supply.measurementMode, 'items');
      expect(supply.items.first.weightPercentOfContract.canonicalText, '4.5');
      expect(supply.items.first.unitCode, 'Nos');
      // Per-building item weights sum to building% x stage% (the server's rule).
      final sum = supply.items.fold(
        YorksAccountsDecimal.zero,
        (a, i) => a + i.weightPercentOfContract,
      );
      expect(sum.canonicalText, '12.5');
    });

    test('fraction to percent handles tiny and whole values', () {
      String pct(String f) => yorksAccountsFractionToPercent(
        YorksAccountsDecimal.parse(f),
      ).canonicalText;
      expect(pct('0.003'), '0.3');
      expect(pct('0.0125'), '1.25');
      expect(pct('1'), '100');
      expect(pct('0'), '0');
    });
  });
}

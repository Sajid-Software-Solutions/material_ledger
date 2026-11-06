import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/accounts/domain/accounts_decimal.dart';
import 'package:material_ledger/features/accounts/domain/v2/accounts_master_file_parser.dart';

/// Builds a sparse row of width 8 (cols A..H) from {colIndex: value}.
List<Object?> _row(Map<int, Object?> cells) {
  final row = List<Object?>.filled(8, null);
  cells.forEach((c, v) => row[c] = v);
  return row;
}

/// Synthetic grids mirroring the real "Project Master File - Nexus 4 Station"
/// (YRA-322): total 18,085,468 everywhere except the DF7W block header, which
/// carries the stray 17,192,000. Percentages are fractions.
Map<String, YorksAccountsMasterSheet> _sheets() {
  List<List<Object?>> block(String letter, String code, String stated) => [
    _row({
      1: letter,
      2: '132/22Kv Substation- ($code)',
      3: 'Contract Value',
      5: stated,
    }),
    _row({3: '1', 4: '0.25', 5: '4521367'}),
  ];
  return {
    'Summery (Option)': [
      _row({1: 'NO', 2: 'DESCRIPTION', 3: 'Contract & Building Value'}),
      ...block('A', 'DF3W', '18085468'),
      ...block('B', 'DF4W', '18085468'),
      ...block('C', 'DF6W', '18085468'),
      ...block('D', 'DF7W', '17192000'), // stray, != the 18,085,468 total
      _row({1: 'ALL PROJECT SUMMARY'}),
      _row({3: 'CONTRACT VALUE', 5: '18085468'}),
      _row({1: '1.1', 2: 'Cooling Load Design', 3: '0.1', 4: '0.1'}),
      _row({1: '1.2', 2: 'Material Supply', 3: '0.5', 4: '0.5'}),
      _row({1: '1.3', 2: 'Progress Installation', 3: '0.3', 4: '0.3'}),
      _row({1: '1.4', 2: 'Comissioning & Handover', 3: '0.05', 4: '0.05'}),
      _row({1: '1.5', 2: 'Energizing Substation', 3: '0.05', 4: '0.05'}),
      _row({2: 'TOTAL', 3: '1'}),
    ],
    'Material  ': [
      _row({1: 'DELIVERD MATERIAL SUMMARY  (DF3W)'}),
      _row({
        1: 'Item',
        2: 'Description',
        4: 'Total Qty.',
        5: 'WEIGHT',
        6: 'Contract',
      }),
      _row({1: 'A', 2: 'Total Contract Value', 6: '18085468'}),
      _row({2: 'Material Supply', 5: '0.125', 6: '2260683.5'}),
      _row({
        1: 'A.1',
        3: 'AC Units (Package Unit)',
        4: '6',
        5: '0.045',
        6: '813846.06',
      }),
      _row({
        2: 'A.1.1',
        3: 'System-01',
        4: '3',
      }), // sub-row: no weight -> skipped
      _row({2: 'A.1.2', 3: 'System-02', 4: '3'}),
      _row({
        1: 'A.2',
        3: 'Ventilation Fans',
        4: '30',
        5: '0.01',
        6: '180854.68',
      }),
    ],
    'Installation': [
      _row({1: 'DELIVERD INSTALLATION SUMMARY  (DF3W)'}),
      _row({1: 'A.1', 3: 'Duct Fixing', 4: '100', 5: '0.02', 6: '361709.36'}),
    ],
  };
}

void main() {
  const parser = YorksAccountsMasterFileParser();
  final expected = YorksAccountsDecimal.parse('17192000');

  group('YorksAccountsMasterFileParser', () {
    test('uses the authoritative contract value, keeps the file value', () {
      final draft = parser.parse(
        sheets: _sheets(),
        expectedContractValue: expected,
      );
      expect(draft.contractValue.canonicalText, '17192000');
      expect(draft.fileContractValue?.canonicalText, '18085468');
      expect(draft.currencyCode, 'AED');
    });

    test('reads the four buildings at 25% with their codes', () {
      final draft = parser.parse(
        sheets: _sheets(),
        expectedContractValue: expected,
      );
      expect(draft.buildings.map((b) => b.code).toList(), [
        'DF3W',
        'DF4W',
        'DF6W',
        'DF7W',
      ]);
      expect(
        draft.buildings.every((b) => b.fraction.canonicalText == '0.25'),
        isTrue,
      );
    });

    test('reads the five stages with items mode on supply + installation', () {
      final draft = parser.parse(
        sheets: _sheets(),
        expectedContractValue: expected,
      );
      expect(draft.stages.map((s) => s.key).toList(), [
        'design',
        'material_supply',
        'installation',
        'commissioning_handover',
        'energizing',
      ]);
      final supply = draft.stages.firstWhere((s) => s.key == 'material_supply');
      expect(supply.fraction.canonicalText, '0.5');
      expect(supply.mode, 'items');
      final design = draft.stages.firstWhere((s) => s.key == 'design');
      expect(design.fraction.canonicalText, '0.1');
      expect(design.mode, 'percent');
    });

    test('reads items (qty + weight), skips sub-rows, tags the stage', () {
      final draft = parser.parse(
        sheets: _sheets(),
        expectedContractValue: expected,
      );
      final ac = draft.items.firstWhere((i) => i.name.startsWith('AC Units'));
      expect(ac.quantity.canonicalText, '6');
      expect(ac.weightFraction.canonicalText, '0.045');
      expect(ac.unit, isNull);
      expect(ac.buildingCode, 'DF3W');
      expect(ac.stageKey, 'material_supply');
      // Sub-rows (System-01/02) have no weight and are not items.
      expect(draft.items.any((i) => i.name == 'System-01'), isFalse);
      // The Installation sheet contributes an installation-stage item.
      expect(
        draft.items.any(
          (i) => i.stageKey == 'installation' && i.name == 'Duct Fixing',
        ),
        isTrue,
      );
    });

    test('flags the contract-value mismatch and the DF7W internal stray', () {
      final draft = parser.parse(
        sheets: _sheets(),
        expectedContractValue: expected,
      );
      expect(draft.hasWarnings, isTrue);
      final codes = draft.issues.map((i) => i.code).toSet();
      expect(
        codes,
        containsAll(<String>{
          'contract_value_mismatch',
          'building_value_inconsistent',
          'item_units_missing',
        }),
      );
      // Exactly one block (DF7W) is internally inconsistent with the total.
      expect(
        draft.issues
            .where((i) => i.code == 'building_value_inconsistent')
            .length,
        1,
      );
    });

    test(
      'a workbook already on the authoritative total raises no mismatch',
      () {
        // Replace every 18,085,468 with 17,192,000 so file == authoritative.
        final sheets = <String, YorksAccountsMasterSheet>{
          for (final e in _sheets().entries)
            e.key: [
              for (final row in e.value)
                [for (final c in row) c == '18085468' ? '17192000' : c],
            ],
        };
        final draft = parser.parse(
          sheets: sheets,
          expectedContractValue: expected,
        );
        final codes = draft.issues.map((i) => i.code).toSet();
        expect(codes.contains('contract_value_mismatch'), isFalse);
        expect(codes.contains('building_value_inconsistent'), isFalse);
      },
    );
  });
}

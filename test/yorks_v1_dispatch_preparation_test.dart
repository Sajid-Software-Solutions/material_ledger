import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/models/yorks_v1_dispatch_preparation.dart';
import 'package:material_ledger/shared/models/yorks_v1_logistics.dart';

void main() {
  test('shared inventory is allocated once across suggested lines', () {
    expect(YorksV1DispatchPreparation.suggest([_line('a'), _line('b')]), {
      'a': '2',
      'b': '',
    });
  });
  test('shared stock shortage marks every contributing row', () {
    expect(
      YorksV1DispatchPreparation.validate(
        [_line('a'), _line('b')],
        {'a': '2', 'b': '2'},
      ),
      {
        'a': YorksV1DispatchQuantityIssue.exceedsStock,
        'b': YorksV1DispatchQuantityIssue.exceedsStock,
      },
    );
  });
  test('negative values are rejected alongside a valid positive line', () {
    expect(
      YorksV1DispatchPreparation.validate(
        [_line('a'), _line('b')],
        {'a': '-1', 'b': '1'},
      ),
      {'a': YorksV1DispatchQuantityIssue.negative},
    );
  });
  test('zero and blank omit lines, malformed and excess values do not', () {
    expect(
      YorksV1DispatchPreparation.validate(
        [_line('a'), _line('b')],
        {'a': '0', 'b': ''},
      ),
      isEmpty,
    );
    expect(
      YorksV1DispatchPreparation.validate(
        [_line('a'), _line('b')],
        {'a': 'invalid', 'b': '5'},
      ),
      {
        'a': YorksV1DispatchQuantityIssue.invalid,
        'b': YorksV1DispatchQuantityIssue.exceedsRemaining,
      },
    );
  });
  test('decimal totals at the stock boundary remain exact', () {
    expect(
      YorksV1DispatchPreparation.validate(
        [_line('a', available: '0.3'), _line('b', available: '0.3')],
        {'a': '0.1', 'b': '0.2'},
      ),
      isEmpty,
    );
  });
  test(
    'unknown stock does not produce a positive suggestion or pass review',
    () {
      expect(
        YorksV1DispatchPreparation.suggest([_line('a', available: null)]),
        {'a': ''},
      );
      expect(
        YorksV1DispatchPreparation.validate(
          [_line('a', available: null)],
          {'a': '1'},
        ),
        {'a': YorksV1DispatchQuantityIssue.unavailable},
      );
    },
  );
}

YorksV1DispatchCandidate _line(String id, {String? available = '2'}) =>
    YorksV1DispatchCandidate(
      requestLineId: id,
      displayOrder: 1,
      description: 'Damper',
      unit: 'Nos',
      approvedQuantity: '4',
      goodReceivedQuantity: '0',
      inTransitQuantity: '0',
      stillNeededQuantity: '4',
      source: YorksV1LogisticsSource.warehouse,
      inventoryItemId: 'stock',
      warehouseAvailableQuantity: available,
    );

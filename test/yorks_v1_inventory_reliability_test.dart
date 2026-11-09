import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_ledger/shared/controllers/yorks_v1_inventory_import_recovery.dart';
import 'package:material_ledger/shared/models/yorks_v1_inventory_history.dart';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:material_ledger/shared/services/yorks_v1_inventory_workbook_service.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/controllers/yorks_v1_inventory_stock_command.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_logistics.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_logistics_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('import recovery survives recreation and isolates owners', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final first = YorksV1InventoryImportRecovery(prefs, 'owner-a');
    final record = <String, Object?>{
      'key': 'original',
      'supplier': true,
      'payload': {'rows': [], 'file_name': 'witness.xlsx'},
    };
    await first.persist(record);
    final restored = YorksV1InventoryImportRecovery(prefs, 'owner-a');
    final other = YorksV1InventoryImportRecovery(prefs, 'owner-b');
    expect(restored.read(), record);
    expect(other.exists, isFalse);
    await expectLater(
      restored.persist({...record, 'key': 'replacement'}),
      throwsStateError,
    );
    expect(restored.read()['key'], 'original');
    restored.active = false;
    await expectLater(restored.persist(record), throwsStateError);
    await first.persist(null);
    expect(restored.exists, isFalse);
  });

  test('large import recovery is compressed and restores every row', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final recovery = YorksV1InventoryImportRecovery(
      preferences,
      'large-import',
    );
    final rows = [
      for (var i = 0; i < 20000; i++)
        {
          'item_code': 'ITEM-$i',
          'item_description': 'Galvanized duct sheet',
          'unit': 'Nos',
          'quantity': '10',
          'reason': 'External supplier receipt',
          'supplier_name': 'Test Supplier',
          'reference': 'DELIVERY-2026',
        },
    ];
    await recovery.persist({
      'key': 'large-key',
      'supplier': true,
      'payload': {'rows': rows},
    });
    expect(preferences.getString('large-import')!.startsWith('gz1:'), isTrue);
    expect(preferences.getString('large-import')!.length, lessThan(1000000));
    final restored = recovery.read()['payload']['rows'] as List;
    expect(restored.length, 20000);
    expect(restored.last['item_code'], 'ITEM-19999');
  });

  test('history dates persist across cursor pages and export queries', () {
    final query = YorksV1InventoryHistoryQuery(
      fromAt: DateTime.utc(2026, 10, 1),
      untilAt: DateTime.utc(2026, 10, 2),
    );
    expect(query.toRpc()['p_until_at'], '2026-10-02T00:00:00.000Z');
    expect(query, isNot(const YorksV1InventoryHistoryQuery()));
  });

  test('print PDF builds from the same row values as the workbook', () async {
    final rows = <YorksV1InventoryMovement>[];
    final bytes =
        await YorksV1PlatformInventoryWorkbookFileService.buildMovementPdf(
          rows,
        );
    expect(ascii.decode(bytes.take(4).toList()), '%PDF');
    expect(
      YorksV1PlatformInventoryWorkbookFileService.movementHeadings,
      contains('Quantity Change'),
    );
  });

  YorksV1InventoryAdjustmentInput input(String key, [String quantity = '1']) =>
      YorksV1InventoryAdjustmentInput(
        quantityDelta: quantity,
        reason: 'Count',
        idempotencyKey: key,
        inventoryItemId: 'item',
        expectedVersion: 3,
      );

  test('movement workbook exports signed facts without formula execution', () {
    final rows = [
      YorksV1InventoryMovement(
        id: 'movement',
        movementType: 'correction',
        quantityDelta: '-1.25',
        onHandAfterQuantity: '8.75',
        reason: 'Counted',
        actorDisplayName: 'Warehouse',
        createdAt: DateTime.utc(2026, 10, 8),
        itemDescription: '=not a formula',
        unit: 'Kg',
        sourceEntityId: 'reference',
      ),
    ];
    final bytes =
        YorksV1PlatformInventoryWorkbookFileService.buildMovementRegisterWorkbook(
          rows,
        );
    final archive = ZipDecoder().decodeBytes(bytes);
    final xml = utf8.decode(
      archive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
    );
    expect(xml, contains('Quantity Change'));
    expect(xml, contains('-1.25'));
    expect(xml, contains('Counted'));
    expect(xml, contains('reference'));
    expect(xml, isNot(contains('<f>')));
    expect(xml, isNot(contains('Minimum Stock')));
  });

  test(
    'uncertain retry preserves original payload and identity, including offline retry',
    () async {
      final repo = _Repository();
      final command = YorksV1InventoryStockCommand();
      repo.failure = StateError('response lost');
      await expectLater(
        command.save(repo, () => input('original')),
        throwsStateError,
      );
      expect(command.unresolved, isTrue);
      repo.failure = const YorksV1DomainException(
        YorksV1DomainErrorCode.offline,
      );
      await expectLater(
        command.save(repo, () => input('changed', '99')),
        throwsA(isA<YorksV1DomainException>()),
      );
      expect(command.unresolved, isTrue);
      repo.failure = null;
      await command.save(repo, () => input('third', '22'));
      expect(
        repo.inputs.map((e) => e.idempotencyKey),
        everyElement('original'),
      );
      expect(repo.inputs.map((e) => e.quantityDelta), everyElement('1'));
      expect(command.unresolved, isFalse);
    },
  );

  test(
    'confirmed rejection releases command so corrected input uses a new key',
    () async {
      final repo = _Repository()
        ..failure = const YorksV1DomainException(
          YorksV1DomainErrorCode.invalidInput,
        );
      final command = YorksV1InventoryStockCommand();
      await expectLater(
        command.save(repo, () => input('bad')),
        throwsA(isA<YorksV1DomainException>()),
      );
      expect(command.unresolved, isFalse);
      repo.failure = null;
      await command.save(repo, () => input('corrected', '-1'));
      expect(repo.inputs.last.idempotencyKey, 'corrected');
      expect(repo.inputs.last.quantityDelta, '-1');
    },
  );

  test(
    'reload replays serialized command and clears only after confirmation',
    () async {
      String? stored;
      Future<void> persist(YorksV1InventoryAdjustmentInput? input) async {
        stored = input == null ? null : jsonEncode(input.toRecoveryJson());
      }

      final repo = _Repository()..failure = StateError('lost response');
      final first = YorksV1InventoryStockCommand(persist: persist);
      await expectLater(
        first.save(repo, () => input('durable', '-2')),
        throwsStateError,
      );
      expect(stored, isNotNull);
      final restored = YorksV1InventoryStockCommand(
        recovered: YorksV1InventoryAdjustmentInput.fromRecoveryJson(
          jsonDecode(stored!),
        ),
        persist: persist,
      );
      repo.failure = null;
      await restored.save(repo, () => input('must-not-use'));
      expect(repo.inputs.last.idempotencyKey, 'durable');
      expect(repo.inputs.last.quantityDelta, '-2');
      expect(repo.inputs.last.expectedVersion, 3);
      expect(stored, isNull);
    },
  );

  test(
    'failed persistence and changed authority prevent a stock write',
    () async {
      final repo = _Repository();
      final blocked = YorksV1InventoryStockCommand(
        persist: (_) async => throw StateError('storage unavailable'),
      );
      await expectLater(
        blocked.save(repo, () => input('key')),
        throwsStateError,
      );
      expect(repo.inputs, isEmpty);
      final changed = YorksV1InventoryStockCommand(canExecute: () => false);
      await expectLater(
        changed.save(repo, () => input('key')),
        throwsStateError,
      );
      expect(repo.inputs, isEmpty);
      expect(changed.unresolved, isTrue);
    },
  );

  test(
    'unknown recovery fields are preserved for review, not replayed incompletely',
    () {
      expect(
        () => YorksV1InventoryAdjustmentInput.fromRecoveryJson({
          ...input('key').toRecoveryJson(),
          'futureField': 'retain me',
        }),
        throwsFormatException,
      );
    },
  );

  test('double submit makes only one repository call', () async {
    final repo = _Repository()..completion = Completer<void>();
    final command = YorksV1InventoryStockCommand();
    final first = command.save(repo, () => input('first'));
    await command.save(repo, () => input('second'));
    expect(repo.inputs, hasLength(1));
    repo.completion!.complete();
    await first;
    expect(command.busy, isFalse);
  });
}

class _Repository implements YorksV1LogisticsRepository {
  final inputs = <YorksV1InventoryAdjustmentInput>[];
  Object? failure;
  Completer<void>? completion;
  @override
  Future<YorksV1LogisticsInventoryItem> adjustInventory(
    YorksV1InventoryAdjustmentInput input,
  ) async {
    inputs.add(input);
    if (completion != null) await completion!.future;
    if (failure != null) throw failure!;
    return const YorksV1LogisticsInventoryItem(
      id: 'item',
      isActive: true,
      description: 'Item',
      unit: 'Nos',
      onHandQuantity: '2',
      reservedQuantity: '0',
      availableQuantity: '2',
      recordVersion: 4,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

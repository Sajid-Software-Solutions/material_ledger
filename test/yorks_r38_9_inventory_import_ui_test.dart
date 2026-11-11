import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/materials/presentation/screens/yorks_v1_inventory_import_screen.dart';
import 'package:material_ledger/shared/controllers/yorks_v1_inventory_import_controller.dart';
import 'package:material_ledger/shared/models/yorks_v1_inventory_workbook.dart';
import 'package:material_ledger/shared/models/yorks_v1_logistics.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_configuration_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_inventory_workbook_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_logistics_repository.dart';
import 'package:material_ledger/shared/services/yorks_v1_inventory_workbook_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadGoldenFonts);

  testWidgets('import fails closed when controlled units cannot load', (
    tester,
  ) async {
    await _setViewport(tester, const Size(820, 900));
    final controller = _controller();
    await _pump(tester, controller: controller, failControlledUnits: true);

    expect(
      find.textContaining('Controlled units are unavailable.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('inventory-import-controlled-units-retry')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('inventory-import-choose-file')),
      findsNothing,
    );
    expect(controller.state.stage, YorksV1InventoryImportStage.uploadFile);
  });

  for (final width in [360.0, 390.0, 820.0, 1440.0]) {
    testWidgets('upload stage is overflow-free at ${width.toInt()}px', (
      tester,
    ) async {
      await _setViewport(tester, Size(width, 900));
      final controller = _controller();
      await _pump(tester, controller: controller);

      expect(find.text('Inventory Import'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('inventory-import-choose-file')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('import-stage-horizontal-scroll')),
        width < 720 ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('import primary action meets touch and keyboard access', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1440, 900));
    final controller = _controller();
    await _pump(tester, controller: controller);

    final primary = find.byKey(const ValueKey('inventory-import-choose-file'));
    final size = tester.getSize(primary);
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));

    expect(await _tabToFinder(tester, primary), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.state.stage, YorksV1InventoryImportStage.mapColumns);
  });

  testWidgets(
    '390px ambiguous workbook requires explicit sheet and cancel is safe',
    (tester) async {
      await _setViewport(tester, const Size(390, 844));
      const fileService = _AmbiguousWorkbookFileService();
      final controller = _WorksheetChoiceController(
        fileService: fileService,
        options: const [
          YorksV1InventoryWorksheetOption(
            name: 'Current Stock',
            isHidden: false,
          ),
          YorksV1InventoryWorksheetOption(
            name: 'Archived Stock',
            isHidden: true,
          ),
        ],
      );
      await _pump(tester, controller: controller, fileService: fileService);

      await tester.tap(
        find.byKey(const ValueKey('inventory-import-choose-file')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey('inventory-import-worksheet-list')),
        findsOneWidget,
      );
      expect(find.text('Hidden worksheet'), findsNWidgets(2));

      await tester.tap(
        find.byKey(const ValueKey('inventory-import-worksheet-cancel')),
      );
      await tester.pumpAndSettle();
      expect(controller.state.stage, YorksV1InventoryImportStage.uploadFile);
      expect(controller.state.errorCode, isNull);

      await tester.tap(
        find.byKey(const ValueKey('inventory-import-choose-file')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.byKey(const ValueKey('inventory-import-worksheet-Archived Stock')),
      );
      await tester.pumpAndSettle();

      expect(controller.preparedWorksheet, 'Archived Stock');
      expect(controller.state.stage, YorksV1InventoryImportStage.mapColumns);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('normalized Inventory Import sheet remains automatic', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    const fileService = _AmbiguousWorkbookFileService();
    final controller = _WorksheetChoiceController(
      fileService: fileService,
      options: const [
        YorksV1InventoryWorksheetOption(name: 'Instructions', isHidden: false),
        YorksV1InventoryWorksheetOption(
          name: ' Inventory-Import ',
          isHidden: false,
        ),
      ],
    );
    await _pump(tester, controller: controller, fileService: fileService);

    await tester.tap(
      find.byKey(const ValueKey('inventory-import-choose-file')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('inventory-import-worksheet-list')),
      findsNothing,
    );
    expect(controller.preparedWorksheet, ' Inventory-Import ');
    expect(controller.state.stage, YorksV1InventoryImportStage.mapColumns);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all five authoritative stages remain operable on tablet', (
    tester,
  ) async {
    await _setViewport(tester, const Size(820, 1050));
    final controller = _controller();
    await _pump(tester, controller: controller);

    await tester.tap(
      find.byKey(const ValueKey('inventory-import-choose-file')),
    );
    await tester.pumpAndSettle();
    expect(controller.state.stage, YorksV1InventoryImportStage.mapColumns);
    expect(
      find.byKey(const ValueKey('inventory-import-mapping-list')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    expect(controller.confirmMapping(), isTrue);
    await tester.pumpAndSettle();
    expect(controller.state.stage, YorksV1InventoryImportStage.reviewValidate);
    expect(
      find.byKey(const ValueKey('inventory-import-review-list')),
      findsOneWidget,
    );

    expect(controller.continueToSupplierReceipt(), isTrue);
    await tester.pumpAndSettle();
    expect(controller.state.stage, YorksV1InventoryImportStage.supplierReceipt);
    expect(
      find.byKey(const ValueKey('inventory-import-receipt-list')),
      findsOneWidget,
    );

    controller.confirmSupplierAndReceipt();
    await tester.pump();
    expect(controller.state.canCommit, isTrue);
    await controller.commit();
    await tester.pumpAndSettle();

    expect(controller.state.stage, YorksV1InventoryImportStage.importSummary);
    expect(find.text('Inventory import committed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('import persists exact receipt command before failed commit', () async {
    Map<String, Object?>? stored;
    final controller = _controller(
      failCommit: true,
      persistPending: (record) async {
        stored = record;
      },
    );
    await controller.chooseFile(_workspace, suppliers: _suppliers);
    expect(controller.confirmMapping(), isTrue);
    expect(controller.continueToSupplierReceipt(), isTrue);
    controller.confirmSupplierAndReceipt();
    await controller.commit();
    expect(stored?['key'], '93000000-0000-4000-8000-000000000091');
    expect(stored?['supplier'], isTrue);
    expect((stored?['payload'] as Map)['rows'], isNotEmpty);
    final original = jsonEncode(stored);
    await controller.commit();
    expect(jsonEncode(stored), original);
    controller.dispose();
  });

  testWidgets('commit failure is identified as an inventory import failure', (
    tester,
  ) async {
    await _setViewport(tester, const Size(820, 1050));
    final controller = _controller(failCommit: true);
    await controller.chooseFile(_workspace, suppliers: _suppliers);
    expect(controller.confirmMapping(), isTrue);
    expect(controller.continueToSupplierReceipt(), isTrue);
    controller.confirmSupplierAndReceipt();
    await controller.commit();
    await _pump(tester, controller: controller);

    expect(
      find.text('Inventory import could not be confirmed.'),
      findsOneWidget,
    );
    expect(find.text('Supplier workspace could not be loaded.'), findsNothing);
    expect(controller.state.hasUnconfirmedCommit, isTrue);
    expect(controller.state.canCommit, isTrue);
    final commit = tester.widget<FilledButton>(
      find.byKey(const ValueKey('inventory-import-commit')),
    );
    expect(commit.onPressed, isNotNull);
    expect(tester.widget<PopScope>(find.byType(PopScope).last).canPop, isFalse);
    final source = controller.state.source;
    controller.previousStage();
    controller.reset();
    expect(controller.state.stage, YorksV1InventoryImportStage.supplierReceipt);
    expect(controller.state.source, same(source));

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'legacy workbook requires explicit Opening Balance and date review',
    (tester) async {
      await _setViewport(tester, const Size(390, 900));
      const fileService = _LegacyOpeningBalanceFileService();
      final controller = _controller(fileService: fileService);
      await _pump(tester, controller: controller, fileService: fileService);

      await tester.tap(
        find.byKey(const ValueKey('inventory-import-choose-file')),
      );
      await tester.pumpAndSettle();
      expect(controller.state.canTreatWorkbookAsOpeningBalance, isTrue);
      expect(controller.state.treatsWorkbookAsOpeningBalance, isFalse);
      expect(
        find.byKey(const ValueKey('inventory-import-opening-balance-default')),
        findsOneWidget,
      );

      controller.setTreatWorkbookAsOpeningBalance(true);
      expect(controller.state.treatsWorkbookAsOpeningBalance, isTrue);
      expect(controller.confirmMapping(), isTrue);
      await tester.pumpAndSettle();

      expect(controller.state.requiresOpeningBalanceAsOfDate, isTrue);
      expect(controller.state.unresolvedUnitGroups, isEmpty);
      expect(
        find.byKey(const ValueKey('inventory-import-opening-balance-date')),
        findsOneWidget,
      );
      controller.setOpeningBalanceAsOfDate('2026-08-20');
      await tester.pumpAndSettle();
      expect(controller.state.unresolvedUnitGroups, isEmpty);
      expect(controller.state.canContinueReview, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('non-stock role fails closed before workbook data renders', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 800));
    final controller = _controller();
    await _pump(
      tester,
      controller: controller,
      role: YorksV1Role.projectEngineer,
    );

    expect(find.text('Restricted'), findsOneWidget);
    expect(find.text('Choose File'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review correction and evidence actions use the controller', (
    tester,
  ) async {
    await _setViewport(tester, const Size(820, 1100));
    final fileService = _EvidenceImportFileService();
    final controller = _controller(fileService: fileService);
    await controller.chooseFile(_workspace, suppliers: _suppliers);
    expect(controller.confirmMapping(), isTrue);
    await _pump(tester, controller: controller);

    await tester.tap(find.byKey(const ValueKey('inventory-import-edit-row-2')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('inventory-import-edit-value')),
      'Edited grille',
    );
    await tester.tap(
      find.byKey(const ValueKey('inventory-import-save-cell-edit')),
    );
    await tester.pumpAndSettle();
    expect(controller.state.preview!.rows.single.description, 'Edited grille');

    await tester.tap(
      find.byKey(const ValueKey('inventory-import-search-replace')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('inventory-import-replace-source')),
      'Edited grille',
    );
    await tester.enterText(
      find.byKey(const ValueKey('inventory-import-replace-value')),
      'Reviewed  grille',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('inventory-import-apply-replace')),
    );
    await tester.pumpAndSettle();
    expect(
      controller.state.preview!.rows.single.description,
      'Reviewed  grille',
    );

    await tester.tap(find.byKey(const ValueKey('inventory-import-safe-fixes')));
    await tester.pumpAndSettle();
    expect(controller.canUndoSafeFixes, isTrue);
    expect(
      controller.state.preview!.rows.single.description,
      'Reviewed grille',
    );
    await tester.tap(
      find.byKey(const ValueKey('inventory-import-undo-safe-fixes')),
    );
    await tester.pumpAndSettle();
    expect(
      controller.state.preview!.rows.single.description,
      'Reviewed  grille',
    );

    await tester.tap(
      find.byKey(const ValueKey('inventory-import-export-issues')),
    );
    await tester.pump();
    expect(fileService.issuesExports, 1);
    await tester.pump(const Duration(seconds: 6));
    await tester.tap(
      find.byKey(const ValueKey('inventory-import-export-cleaned')),
    );
    await tester.pump();
    expect(fileService.cleanedExports, 1);
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('summary result workbook requires the committed strict result', (
    tester,
  ) async {
    await _setViewport(tester, const Size(820, 1000));
    final fileService = _EvidenceImportFileService();
    final controller = _controller(fileService: fileService);
    await controller.chooseFile(_workspace, suppliers: _suppliers);
    expect(controller.confirmMapping(), isTrue);
    expect(controller.continueToSupplierReceipt(), isTrue);
    controller.confirmSupplierAndReceipt();
    await controller.commit();
    await _pump(tester, controller: controller);

    await tester.tap(
      find.byKey(const ValueKey('inventory-import-export-result')),
    );
    await tester.pump();
    expect(fileService.resultExports, 1);
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });

  for (final visual in <({String name, Size size})>[
    (name: 'desktop_1440', size: const Size(1440, 1000)),
    (name: 'mobile_360', size: const Size(360, 1000)),
  ]) {
    testWidgets('import upload visual ${visual.name}', (tester) async {
      await _setViewport(tester, visual.size);
      final controller = _controller();
      await _pump(tester, controller: controller);
      if (visual.name == 'mobile_360') {
        await tester.drag(
          find.byKey(const ValueKey('inventory-import-scroll-view')),
          const Offset(0, -900),
        );
        await tester.pumpAndSettle();
      }

      await expectLater(
        find.byType(YorksV1InventoryImportScreen),
        matchesGoldenFile('goldens/r38_9/import_upload_${visual.name}.png'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('import mapping visual ${visual.name}', (tester) async {
      await _setViewport(tester, visual.size);
      final controller = _controller();
      await controller.chooseFile(_workspace, suppliers: _suppliers);
      await _pump(tester, controller: controller);

      await expectLater(
        find.byType(YorksV1InventoryImportScreen),
        matchesGoldenFile('goldens/r38_9/import_mapping_${visual.name}.png'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('import summary visual ${visual.name}', (tester) async {
      await _setViewport(tester, visual.size);
      final controller = _controller();
      await controller.chooseFile(_workspace, suppliers: _suppliers);
      expect(controller.confirmMapping(), isTrue);
      expect(controller.continueToSupplierReceipt(), isTrue);
      controller.confirmSupplierAndReceipt();
      await controller.commit();
      await _pump(tester, controller: controller);

      await expectLater(
        find.byType(YorksV1InventoryImportScreen),
        matchesGoldenFile('goldens/r38_9/import_summary_${visual.name}.png'),
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final visual in <({String name, Size size})>[
    (name: 'desktop_1440', size: const Size(1440, 1000)),
    (name: 'tablet_820', size: const Size(820, 1000)),
    (name: 'mobile_360', size: const Size(360, 900)),
  ]) {
    testWidgets('import review visual ${visual.name}', (tester) async {
      await _setViewport(tester, visual.size);
      final controller = _controller();
      await controller.chooseFile(_workspace, suppliers: _suppliers);
      expect(controller.confirmMapping(), isTrue);

      await _pump(tester, controller: controller);

      expect(
        find.byKey(const ValueKey('inventory-import-review-list')),
        findsOneWidget,
      );
      await expectLater(
        find.byType(YorksV1InventoryImportScreen),
        matchesGoldenFile('goldens/r38_9/import_review_${visual.name}.png'),
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final visual in <({String name, Size size})>[
    (name: 'desktop_1440', size: const Size(1440, 1000)),
    (name: 'mobile_360', size: const Size(360, 900)),
  ]) {
    testWidgets('import receipt visual ${visual.name}', (tester) async {
      await _setViewport(tester, visual.size);
      final controller = _controller();
      await controller.chooseFile(_workspace, suppliers: _suppliers);
      expect(controller.confirmMapping(), isTrue);
      expect(controller.continueToSupplierReceipt(), isTrue);

      await _pump(tester, controller: controller);

      expect(
        find.byKey(const ValueKey('inventory-import-receipt-list')),
        findsOneWidget,
      );
      await expectLater(
        find.byType(YorksV1InventoryImportScreen),
        matchesGoldenFile('goldens/r38_9/import_receipt_${visual.name}.png'),
      );
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _loadGoldenFonts() async {
  final nexus = FontLoader('NexusSans')
    ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
  final arabic = FontLoader('NotoSansArabic')
    ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
  final cache = _flutterCacheDirectory();
  final icons = await File(
    '${cache.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ).readAsBytes();
  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(icons)));
  await Future.wait([nexus.load(), arabic.load(), materialIcons.load()]);
}

Directory _flutterCacheDirectory() {
  var directory = File(Platform.resolvedExecutable).parent;
  for (var level = 0; level < 8; level++) {
    if (directory.path.endsWith('${Platform.pathSeparator}cache')) {
      return directory;
    }
    directory = directory.parent;
  }
  throw StateError('Could not locate the Flutter cache from the test runner');
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<bool> _tabToFinder(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    if (_primaryFocusIsWithin(finder)) return true;
  }
  return false;
}

bool _primaryFocusIsWithin(Finder finder) {
  final target = finder.evaluate().single;
  Element? current = FocusManager.instance.primaryFocus?.context as Element?;
  while (current != null) {
    if (identical(current, target)) return true;
    Element? parent;
    current.visitAncestorElements((ancestor) {
      parent = ancestor;
      return false;
    });
    current = parent;
  }
  return false;
}

Future<void> _pump(
  WidgetTester tester, {
  required YorksV1InventoryImportController controller,
  YorksV1InventoryWorkbookFileService fileService = const _ImportFileService(),
  YorksV1Role role = YorksV1Role.admin,
  bool failControlledUnits = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksV1CurrentRoleProvider.overrideWithValue(role),
        yorksV1ConfigurationUnitCodesProvider.overrideWith((ref) async {
          if (failControlledUnits) {
            throw StateError('Controlled unit register unavailable');
          }
          return yorksV1InventoryControlledUnits;
        }),
        yorksV1InventoryImportControllerProvider.overrideWith(
          (ref) => controller,
        ),
        yorksV1InventoryWorkbookFileServiceProvider.overrideWithValue(
          fileService,
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: YorksV1InventoryImportScreen(
          workspace: _workspace,
          suppliers: _suppliers,
          onCancel: () {},
          onReturnToSuppliers: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

YorksV1InventoryImportController _controller({
  YorksV1InventoryWorkbookFileService fileService = const _ImportFileService(),
  bool failCommit = false,
  Future<void> Function(Map<String, Object?>?)? persistPending,
}) => YorksV1InventoryImportController(
  persistPending: persistPending,
  repository: _ImportRepository(),
  fileService: fileService,
  // Widget tests run in a fake-async zone; keep the explicit codec local so
  // production's compute-isolate path remains covered by the controller test.
  codec: const YorksV1InventoryWorkbookCodec(),
  uuidFactory: () => '93000000-0000-4000-8000-000000000091',
  r38_9Commit: ({required payload, required idempotencyKey}) async {
    expect(payload['rows'], isA<List<Object?>>());
    if (failCommit) {
      throw StateError('Forced inventory import failure');
    }
    return const YorksV1InventoryImportResult(
      importBatchId: 'batch-r38-9-ui',
      rowCount: 1,
      createdItems: 1,
      updatedItems: 0,
      createdCategories: 0,
    );
  },
);

class _WorksheetChoiceController extends YorksV1InventoryImportController {
  _WorksheetChoiceController({
    required super.fileService,
    required this.options,
  }) : super(
         repository: _ImportRepository(),
         codec: const YorksV1InventoryWorkbookCodec(),
         uuidFactory: () => '93000000-0000-4000-8000-000000000092',
         r38_9Commit: ({required payload, required idempotencyKey}) async =>
             const YorksV1InventoryImportResult(
               importBatchId: 'batch-r38-9-sheet-ui',
               rowCount: 1,
               createdItems: 1,
               updatedItems: 0,
               createdCategories: 0,
             ),
       );

  final List<YorksV1InventoryWorksheetOption> options;
  String? preparedWorksheet;

  @override
  Future<List<YorksV1InventoryWorksheetOption>> availableWorksheets(
    YorksV1InventorySelectedWorkbook selected,
  ) async => options;

  @override
  Future<bool> prepareSelectedAsync(
    YorksV1InventorySelectedWorkbook selected,
    YorksV1InventoryWorkspace workspace, {
    List<YorksV1InventorySupplierMaster> suppliers = const [],
  }) async {
    preparedWorksheet = selected.worksheetName;
    final csv = await const _ImportFileService().selectWorkbook();
    return super.prepareSelectedAsync(csv!, workspace, suppliers: suppliers);
  }
}

class _ImportRepository implements YorksV1LogisticsRepository {
  @override
  Future<YorksV1InventoryImportResult> importInventory(
    YorksV1InventoryImportInput input,
  ) async => const YorksV1InventoryImportResult(
    importBatchId: 'legacy-batch',
    rowCount: 1,
    createdItems: 1,
    updatedItems: 0,
    createdCategories: 0,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImportFileService implements YorksV1InventoryWorkbookFileService {
  const _ImportFileService();

  @override
  Future<YorksV1InventorySelectedWorkbook?> selectWorkbook() async =>
      YorksV1InventorySelectedWorkbook(
        fileName: 'supplier-receipt.csv',
        bytes: Uint8List.fromList(
          utf8.encode('${_headers.join(',')}\r\n${_row.join(',')}'),
        ),
      );

  @override
  Future<bool> saveImportTemplate() async => true;

  @override
  Future<bool> saveStockRegister({
    required YorksV1InventoryWorkspace workspace,
    required String suggestedName,
  }) async => true;
}

class _AmbiguousWorkbookFileService
    implements YorksV1InventoryWorkbookFileService {
  const _AmbiguousWorkbookFileService();

  @override
  Future<YorksV1InventorySelectedWorkbook?> selectWorkbook() async =>
      YorksV1InventorySelectedWorkbook(
        fileName: 'multi-sheet.xlsx',
        bytes: Uint8List.fromList([1, 2, 3]),
      );

  @override
  Future<bool> saveImportTemplate() async => true;

  @override
  Future<bool> saveStockRegister({
    required YorksV1InventoryWorkspace workspace,
    required String suggestedName,
  }) async => true;
}

class _EvidenceImportFileService extends _ImportFileService
    implements YorksV1InventoryImportEvidenceFileService {
  int issuesExports = 0;
  int cleanedExports = 0;
  int resultExports = 0;

  @override
  Future<bool> saveImportIssues({
    required YorksV1InventoryImportPreview preview,
  }) async {
    issuesExports += 1;
    return true;
  }

  @override
  Future<bool> saveCleanedImportPreview({
    required YorksV1InventoryImportPreview preview,
  }) async {
    cleanedExports += 1;
    return true;
  }

  @override
  Future<bool> saveImportResult({
    required YorksV1InventoryImportPreview preview,
    required YorksV1InventoryImportResult result,
  }) async {
    resultExports += 1;
    return true;
  }
}

class _LegacyOpeningBalanceFileService
    implements YorksV1InventoryWorkbookFileService {
  const _LegacyOpeningBalanceFileService();

  @override
  Future<YorksV1InventorySelectedWorkbook?> selectWorkbook() async =>
      YorksV1InventorySelectedWorkbook(
        fileName: 'legacy-opening-balance.csv',
        bytes: Uint8List.fromList(
          utf8.encode('${_legacyHeaders.join(',')}\r\n${_legacyRow.join(',')}'),
        ),
      );

  @override
  Future<bool> saveImportTemplate() async => true;

  @override
  Future<bool> saveStockRegister({
    required YorksV1InventoryWorkspace workspace,
    required String suggestedName,
  }) async => true;
}

final _workspace = YorksV1InventoryWorkspace(
  items: const [],
  categories: [
    YorksV1InventoryCategory(
      id: 'category-air',
      name: 'Air Terminals',
      isSystem: true,
      isActive: true,
      recordVersion: 1,
      itemCount: 0,
      aliases: const [],
      createdByDisplayName: 'Yorks standard',
      createdAt: DateTime.utc(2026, 8, 20),
    ),
  ],
);

final _suppliers = [
  YorksV1InventorySupplierMaster(
    id: 'supplier-trox',
    name: 'TROX Middle East LLC',
    aliases: const ['TROX'],
  ),
  YorksV1InventorySupplierMaster(
    id: yorksV1UnknownSupplierId,
    name: yorksV1UnknownSupplierName,
    isUnknownSupplier: true,
  ),
];

const _headers = <String>[
  'S:No',
  'Item Code *',
  'Category *',
  'Item Description *',
  'Size (If Any)',
  'Model / Tag',
  'Serial No',
  'Brand / Origin',
  'RAL Colour',
  'Source Type *',
  'Stock Action *',
  'Quantity *',
  'Unit *',
  'Reason *',
  'Minimum Stock',
  'Location / Shelf',
  'External Supplier Name',
  'Supplier Reference / Delivery Note',
  'Received Date',
  'Notes',
  'Unit Price',
  'Total Price',
];

const _row = <String>[
  '1',
  'AIR-LIGR-001',
  'Air Terminals',
  'Linear Supply Air Grille',
  '600 x 600 mm',
  '',
  '',
  'TROX / UAE',
  'RAL 9010',
  'External Supplier',
  'Add Stock',
  '10',
  'Nos',
  'Supplier receipt',
  '2',
  'Main Warehouse / A-01',
  'TROX Middle East LLC',
  'DN-001',
  '2026-08-20',
  'Checked',
  '45',
  '450',
];

const _legacyHeaders = <String>[
  'S:No',
  'Item Code *',
  'Category *',
  'Item Description *',
  'Size (If Any)',
  'Model / Tag',
  'Serial No',
  'Brand / Origin',
  'RAL Colour',
  'Stock Action *',
  'Quantity *',
  'Unit *',
  'Reason *',
  'Minimum Stock',
  'Location / Shelf',
  'External Supplier Name',
  'Supplier Reference / Delivery Note',
  'Received Date',
  'Notes',
  'Unit Price',
  'Total Price',
];

const _legacyRow = <String>[
  '1',
  'AIR-PACK-001',
  'Air Terminals',
  'Legacy grille pack',
  '',
  '',
  '',
  'Yorks',
  '',
  'Add Stock',
  '4',
  'Pack',
  'Opening stock',
  '1',
  'A-02',
  '',
  '',
  '',
  '',
  '',
  '',
];

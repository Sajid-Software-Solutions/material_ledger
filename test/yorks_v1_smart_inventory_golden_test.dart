import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:material_ledger/shared/models/yorks_v1_inventory_register_query.dart';
import 'package:material_ledger/shared/models/yorks_v1_inventory_history.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/materials/presentation/screens/yorks_v1_inventory_screen.dart';
import 'package:material_ledger/shared/controllers/yorks_v1_inventory_import_controller.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_logistics.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_configuration_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_inventory_workbook_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_logistics_repository_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_logistics_repository.dart';
import 'package:material_ledger/shared/services/yorks_v1_inventory_workbook_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
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
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final size in [const Size(360, 800), const Size(1366, 768)]) {
    testWidgets('Arabic inventory remains readable at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('selected_language', 'ar');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.procurement,
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1LogisticsRepositoryProvider.overrideWithValue(
              const _GoldenInventoryRepository(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const YorksV1InventoryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(YorksV1InventoryScreen),
        matchesGoldenFile(
          'goldens/r38_3/warehouse_items_arabic_${size.width.toInt()}.png',
        ),
      );
      expect(tester.takeException(), isNull);
      if (size.width > 1000) {
        final name = find.text('WH-DCT-001 · GI duct sheet 24 gauge');
        final before = tester.getTopLeft(name);
        final scroll = find
            .byWidgetPredicate(
              (w) =>
                  w is SingleChildScrollView &&
                  w.scrollDirection == Axis.horizontal,
            )
            .last;
        await tester.drag(scroll, const Offset(200, 0));
        await tester.pumpAndSettle();
        expect(
          tester.widget<SingleChildScrollView>(scroll).controller!.offset,
          greaterThan(0),
        );
        expect(tester.getTopLeft(name).dx, closeTo(before.dx, 1));
      }
    });
  }

  testWidgets(
    'stock pages preserve search and exports include the complete match set',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final preferences = await SharedPreferences.getInstance();
      final repo = _PagedInventoryRepository();
      final files = _RecordingInventoryWorkbookFileService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.procurement,
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1LogisticsRepositoryProvider.overrideWithValue(repo),
            yorksV1InventoryWorkbookFileServiceProvider.overrideWithValue(
              files,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const YorksV1InventoryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.fullReads, 0);
      expect(find.text('1–50 / 120'), findsOneWidget);
      await tester.tap(find.text('Export stock'));
      await tester.pumpAndSettle();
      expect(files.lastItemCount, 120);
      await tester.ensureVisible(find.text('Next').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next').last);
      await tester.pumpAndSettle();
      expect(find.text('51–100 / 120'), findsOneWidget);
      final search = find.byType(TextField).first;
      await tester.ensureVisible(search);
      await tester.enterText(search, 'Page item 119');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(repo.queries.last.offset, 0);
      expect(repo.queries.last.search, 'Page item 119');
      expect(
        tester.widget<TextField>(search).controller!.text,
        'Page item 119',
      );
      expect(find.text('1–1 / 1'), findsOneWidget);
      expect(repo.fullReads, 0);
      await tester.pump(const Duration(seconds: 6));
      expect(tester.takeException(), isNull);
    },
  );

  for (final owner in ['owner-a', 'owner-b']) {
    testWidgets('reloaded stock recovery is scoped to $owner', (tester) async {
      final preferences = await SharedPreferences.getInstance();
      const key = 'yorks.inventory.pending.v1.owner-a.procurement';
      final input = YorksV1InventoryAdjustmentInput(
        quantityDelta: '-1',
        reason: 'Witness',
        idempotencyKey: 'original',
        inventoryItemId: _workspace.items.first.id,
        expectedVersion: 1,
        action: 'correction',
      );
      await preferences.setString(key, jsonEncode(input.toRecoveryJson()));
      final repo = _RetryStockRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1AuthUserIdProvider.overrideWithValue(owner),
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.procurement,
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1LogisticsRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const YorksV1InventoryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (owner == 'owner-a') {
        expect(find.text('Retry save'), findsOneWidget);
        await tester.tap(find.text('Retry save'));
        await tester.pumpAndSettle();
        expect(preferences.containsKey(key), isTrue);
        await tester.tap(find.text('Retry save'));
        await tester.pumpAndSettle();
        expect(
          repo.inputs.map((input) => input.idempotencyKey),
          everyElement('original'),
        );
        expect(preferences.containsKey(key), isFalse);
        expect(find.text('Warehouse Inventory'), findsOneWidget);
      } else {
        expect(find.text('Retry save'), findsNothing);
        expect(repo.inputs, isEmpty);
        expect(preferences.containsKey(key), isTrue);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final evidence in <({String name, Size size})>[
    (name: 'smart_inventory_desktop.png', size: const Size(1366, 768)),
    (name: 'smart_inventory_tablet.png', size: const Size(900, 1024)),
    (name: 'smart_inventory_mobile.png', size: const Size(360, 800)),
  ]) {
    testWidgets('R38.3 smart warehouse — ${evidence.size}', (tester) async {
      tester.view.physicalSize = evidence.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.procurement,
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1ConfigurationUnitCodesProvider.overrideWith(
              (ref) async => const [
                'Nos',
                'Meter',
                'Set',
                'Kg',
                'Ton',
                'Boxes',
              ],
            ),
            yorksV1LogisticsRepositoryProvider.overrideWithValue(
              const _GoldenInventoryRepository(),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const YorksV1InventoryScreen(initialTab: 'overview'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Warehouse Inventory'), findsOneWidget);
      expect(find.text('Stock quantity remains controlled'), findsOneWidget);
      expect(find.text('4.0000'), findsNothing);
      expect(find.text('Incoming stock'), findsNothing);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/r35/${evidence.name}'),
      );
    });
  }

  for (final evidence in <({String suffix, Size size})>[
    (suffix: 'desktop_1440', size: const Size(1440, 900)),
    (suffix: 'mobile_360', size: const Size(360, 800)),
  ]) {
    testWidgets('R38.9 supplier-aware inventory overview — ${evidence.size}', (
      tester,
    ) async {
      tester.view.physicalSize = evidence.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.procurement,
            ),
            yorksV1FeatureFlagsProvider.overrideWithValue(
              const YorksV1FeatureFlags(
                foundation: true,
                projects: true,
                boq: true,
                excel: true,
                requests: true,
                arrangement: true,
                logistics: true,
                returnsDocuments: true,
                documents: true,
                inventorySuppliers: true,
              ),
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1ConfigurationUnitCodesProvider.overrideWith(
              (ref) async => const [
                'Nos',
                'Meter',
                'Set',
                'Kg',
                'Ton',
                'Boxes',
              ],
            ),
            yorksV1LogisticsRepositoryProvider.overrideWithValue(
              const _GoldenInventoryRepository(),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const YorksV1InventoryScreen(initialTab: 'overview'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      if (evidence.size.width <= 720) {
        await tester.tap(
          find.byKey(const ValueKey('inventory-section-selector')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Suppliers'), findsWidgets);
        await tester.tap(find.text('Overview').last);
        await tester.pumpAndSettle();
      } else {
        expect(find.text('Suppliers'), findsWidgets);
      }
      expect(find.text('Import Inventory'), findsWidgets);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/r38_9/inventory_overview_${evidence.suffix}.png',
        ),
      );
    });
  }

  for (final evidence in <({String suffix, Size size, double scroll})>[
    (suffix: 'desktop', size: const Size(1366, 768), scroll: 520),
    (suffix: 'mobile', size: const Size(360, 800), scroll: 1420),
  ]) {
    testWidgets('R38.3 bounded overview lists — ${evidence.size}', (
      tester,
    ) async {
      tester.view.physicalSize = evidence.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.procurement,
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1LogisticsRepositoryProvider.overrideWithValue(
              const _GoldenInventoryRepository(),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const YorksV1InventoryScreen(initialTab: 'overview'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(CustomScrollView).first,
        Offset(0, -evidence.scroll),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('inventory-category-list')), findsOne);
      expect(
        find.byKey(const ValueKey('inventory-recent-movement-list')),
        findsOne,
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/r35/smart_inventory_lists_${evidence.suffix}.png',
        ),
      );
    });
  }

  testWidgets(
    'warehouse overview keeps large operational lists bounded and aligned',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.procurement,
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1LogisticsRepositoryProvider.overrideWithValue(
              const _LargeInventoryRepository(),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const YorksV1InventoryScreen(initialTab: 'overview'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final attentionPanel = find.byKey(
        const ValueKey('inventory-attention-panel'),
      );
      final quickToolsPanel = find.byKey(
        const ValueKey('inventory-quick-tools-panel'),
      );
      final categoryPanel = find.byKey(
        const ValueKey('inventory-category-panel'),
      );
      final movementPanel = find.byKey(
        const ValueKey('inventory-recent-movements-panel'),
      );
      expect(
        tester.getSize(attentionPanel).height,
        tester.getSize(quickToolsPanel).height,
      );
      expect(
        tester.getSize(categoryPanel).height,
        tester.getSize(movementPanel).height,
      );

      for (final key in const [
        'inventory-attention-list',
        'inventory-category-list',
        'inventory-recent-movement-list',
      ]) {
        final scrollable = find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Scrollable),
        );
        expect(scrollable, findsOneWidget);
        expect(
          tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
          greaterThan(0),
        );
      }

      final lastTool = find.byKey(const ValueKey('inventory-quick-tool-4'));
      expect(
        tester.getCenter(lastTool).dx,
        closeTo(tester.getCenter(quickToolsPanel).dx, 1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final evidence in <({String suffix, Size size})>[
    (suffix: 'desktop', size: const Size(1366, 768)),
    (suffix: 'mobile', size: const Size(360, 800)),
  ]) {
    testWidgets('R38.3 stock chooser and category create — ${evidence.size}', (
      tester,
    ) async {
      tester.view.physicalSize = evidence.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.procurement,
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1ConfigurationUnitCodesProvider.overrideWith(
              (ref) async => const [
                'Nos',
                'Meter',
                'Set',
                'Kg',
                'Ton',
                'Boxes',
              ],
            ),
            yorksV1LogisticsRepositoryProvider.overrideWithValue(
              const _GoldenInventoryRepository(),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const YorksV1InventoryScreen(initialTab: 'overview'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add / Receive Stock').first);
      await tester.pumpAndSettle();
      expect(find.text('Create inventory item'), findsOneWidget);
      expect(find.text('Receive or adjust existing stock'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/r35/smart_inventory_chooser_${evidence.suffix}.png',
        ),
      );

      await tester.tap(find.text('Create inventory item'));
      await tester.pumpAndSettle();
      expect(find.text('Item identity'), findsOneWidget);
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.hintText == 'Start typing a category',
        ),
        'round ac terminal',
      );
      await tester.pumpAndSettle();
      expect(find.text('Air Terminals › Round'), findsOneWidget);
      expect(find.textContaining('Create “Round AC Terminal”'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/r35/smart_inventory_create_${evidence.suffix}.png',
        ),
      );
    });
  }

  for (final evidence in <({String suffix, Size size})>[
    (suffix: 'desktop', size: const Size(1366, 768)),
    (suffix: 'mobile', size: const Size(360, 800)),
  ]) {
    testWidgets('R38.3 controlled Ton and Boxes units — ${evidence.size}', (
      tester,
    ) async {
      tester.view.physicalSize = evidence.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.procurement,
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1ConfigurationUnitCodesProvider.overrideWith(
              (ref) async => const [
                'Nos',
                'Meter',
                'Set',
                'Kg',
                'Ton',
                'Boxes',
              ],
            ),
            yorksV1LogisticsRepositoryProvider.overrideWithValue(
              const _GoldenInventoryRepository(),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const YorksV1InventoryScreen(initialTab: 'overview'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add / Receive Stock').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create inventory item'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();

      expect(find.text('Ton'), findsOneWidget);
      expect(find.text('Boxes'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/r35/smart_inventory_controlled_units_${evidence.suffix}.png',
        ),
      );
    });
  }

  for (final evidence in <({String suffix, Size size})>[
    (suffix: 'desktop', size: const Size(1366, 768)),
    (suffix: 'mobile', size: const Size(360, 800)),
  ]) {
    testWidgets('R38.3 warehouse item detail — ${evidence.size}', (
      tester,
    ) async {
      tester.view.physicalSize = evidence.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.procurement,
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1LogisticsRepositoryProvider.overrideWithValue(
              const _GoldenInventoryRepository(),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const YorksV1InventoryScreen(initialTab: 'overview'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _selectSection(tester, 'Items');
      await tester.pumpAndSettle();
      final item = find.textContaining('GI duct sheet 24 gauge').first;
      if (evidence.size.width < 500) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -720));
        await tester.pumpAndSettle();
      }
      await tester.tap(item);
      await tester.pumpAndSettle();

      expect(find.text('Active Reservations'), findsOneWidget);
      expect(find.text('Receive / Adjust'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/r38_3/warehouse_item_detail_${evidence.suffix}.png',
        ),
      );
    });
  }

  for (final evidence in <({String suffix, Size size})>[
    (suffix: 'desktop', size: const Size(1366, 768)),
    (suffix: 'mobile', size: const Size(360, 800)),
  ]) {
    testWidgets('R38.3 warehouse categories — ${evidence.size}', (
      tester,
    ) async {
      tester.view.physicalSize = evidence.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.procurement,
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1LogisticsRepositoryProvider.overrideWithValue(
              const _GoldenInventoryRepository(),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const YorksV1InventoryScreen(initialTab: 'overview'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _selectSection(tester, 'Items');
      await tester.pumpAndSettle();
      await _openCategories(tester);
      await tester.pumpAndSettle();

      expect(find.text('Warehouse Categories'), findsOneWidget);
      expect(find.text('New Parent Category'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/r38_3/warehouse_categories_${evidence.suffix}.png',
        ),
      );
    });
  }

  testWidgets('Warehouse category management creates a top-level category', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repository = _CategoryCreationRepository();
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          yorksV1CurrentRoleProvider.overrideWithValue(YorksV1Role.procurement),
          sharedPreferencesProvider.overrideWithValue(preferences),
          yorksV1LogisticsRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: const YorksV1InventoryScreen(initialTab: 'overview'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _selectSection(tester, 'Items');
    await tester.pumpAndSettle();
    await _openCategories(tester);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'e.g. Air Terminals',
      ),
      'fresh air systems',
    );
    await tester.tap(find.text('Add Category'));
    await tester.pumpAndSettle();

    expect(repository.creation, isNotNull);
    expect(repository.creation!.name, 'fresh air systems');
    expect(repository.creation!.parentCategoryId, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final evidence
      in <({String tab, String surface, String name, Size size})>[
        (
          tab: 'Items',
          surface: 'Warehouse Items',
          name: 'items_desktop',
          size: const Size(1366, 768),
        ),
        (
          tab: 'Items',
          surface: 'Warehouse Items',
          name: 'items_mobile',
          size: const Size(360, 800),
        ),
        (
          tab: 'Stock Movements',
          surface: 'Stock Movement History',
          name: 'movements_desktop',
          size: const Size(1366, 768),
        ),
        (
          tab: 'Stock Movements',
          surface: 'Stock Movement History',
          name: 'movements_mobile',
          size: const Size(360, 800),
        ),
        (
          tab: 'Reservations',
          surface: 'Active Reservations',
          name: 'reservations_desktop',
          size: const Size(1366, 768),
        ),
        (
          tab: 'Reservations',
          surface: 'Active Reservations',
          name: 'reservations_mobile',
          size: const Size(360, 800),
        ),
      ]) {
    testWidgets('R38.3 warehouse ${evidence.tab} — ${evidence.size}', (
      tester,
    ) async {
      tester.view.physicalSize = evidence.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.procurement,
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1LogisticsRepositoryProvider.overrideWithValue(
              const _GoldenInventoryRepository(),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const YorksV1InventoryScreen(initialTab: 'overview'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _selectSection(tester, evidence.tab);
      await tester.pumpAndSettle();

      expect(find.text(evidence.surface), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/r38_3/warehouse_${evidence.name}.png'),
      );
      if (evidence.name == 'items_desktop') {
        final name = find.text('WH-DCT-001 · GI duct sheet 24 gauge');
        expect(name, findsOneWidget);
        final before = tester.getTopLeft(name);
        final horizontal = find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        );
        await tester.drag(horizontal.last, const Offset(-200, 0));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<SingleChildScrollView>(horizontal.last)
              .controller!
              .offset,
          greaterThan(0),
        );
        expect(tester.getTopLeft(name).dx, closeTo(before.dx, 1));
        expect(tester.takeException(), isNull);
      }
    });
  }

  for (final evidence in <({String suffix, Size size})>[
    (suffix: 'desktop', size: const Size(1366, 768)),
    (suffix: 'mobile', size: const Size(360, 800)),
  ]) {
    testWidgets('R38.3 warehouse import preview — ${evidence.size}', (
      tester,
    ) async {
      tester.view.physicalSize = evidence.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.procurement,
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1LogisticsRepositoryProvider.overrideWithValue(
              const _GoldenInventoryRepository(),
            ),
            yorksV1InventoryWorkbookFileServiceProvider.overrideWithValue(
              const _GoldenInventoryWorkbookFileService(),
            ),
            yorksV1InventoryImportControllerProvider.overrideWith((ref) {
              return YorksV1InventoryImportController(
                repository: const _GoldenInventoryRepository(),
                fileService: const _GoldenInventoryWorkbookFileService(),
                codec: const YorksV1InventoryWorkbookCodec(),
              );
            }),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const YorksV1InventoryScreen(initialTab: 'overview'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import Inventory').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select Excel or CSV file'));
      await tester.pumpAndSettle();

      expect(find.text('Preview Inventory Import'), findsOneWidget);
      expect(find.text('Smart category mapping is active'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/r38_3/warehouse_import_${evidence.suffix}.png',
        ),
      );
    });
  }

  testWidgets(
    'warehouse import exposes explicit existing-or-new category choices',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.procurement,
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1LogisticsRepositoryProvider.overrideWithValue(
              const _GoldenInventoryRepository(),
            ),
            yorksV1InventoryWorkbookFileServiceProvider.overrideWithValue(
              const _GoldenInventoryWorkbookFileService(),
            ),
            yorksV1InventoryImportControllerProvider.overrideWith((ref) {
              return YorksV1InventoryImportController(
                repository: const _GoldenInventoryRepository(),
                fileService: const _GoldenInventoryWorkbookFileService(),
                codec: const YorksV1InventoryWorkbookCodec(),
              );
            }),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const YorksV1InventoryScreen(initialTab: 'overview'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import Inventory').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select Excel or CSV file'));
      await tester.pumpAndSettle();

      final firstChoice = find.byKey(
        const ValueKey('inventory-category-2-null-null'),
      );
      expect(firstChoice, findsOneWidget);
      await tester.tap(firstChoice);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create “Air Grille Fittings”').last);
      await tester.pumpAndSettle();

      final confirm = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Confirm Import (3)'),
      );
      expect(confirm.onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Warehouse item search includes the item brand', (tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          yorksV1CurrentRoleProvider.overrideWithValue(YorksV1Role.procurement),
          sharedPreferencesProvider.overrideWithValue(preferences),
          yorksV1LogisticsRepositoryProvider.overrideWithValue(
            const _GoldenInventoryRepository(),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: const YorksV1InventoryScreen(initialTab: 'overview'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _selectSection(tester, 'Items');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Yorks');
    await tester.pumpAndSettle();

    expect(find.textContaining('Round air diffuser 300 mm'), findsOneWidget);
    expect(find.textContaining('GI duct sheet 24 gauge'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'inventory file actions download the format and export the register',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final preferences = await SharedPreferences.getInstance();
      final files = _RecordingInventoryWorkbookFileService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.procurement,
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1LogisticsRepositoryProvider.overrideWithValue(
              const _GoldenInventoryRepository(),
            ),
            yorksV1InventoryWorkbookFileServiceProvider.overrideWithValue(
              files,
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const YorksV1InventoryScreen(initialTab: 'overview'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Download Format').first);
      await tester.pump();
      expect(files.templateDownloads, 1);
      expect(
        find.text('The controlled import format was downloaded.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Export register').first);
      await tester.pump();
      expect(files.registerExports, 1);
      expect(
        find.text('The current stock register was exported.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 6));
    },
  );
  for (final correction in [false, true]) {
    testWidgets(
      'stock retry retains confirmed command; signed correction=$correction',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final repository = _RetryStockRepository();
        final preferences = await SharedPreferences.getInstance();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              yorksV1CurrentRoleProvider.overrideWithValue(
                YorksV1Role.procurement,
              ),
              sharedPreferencesProvider.overrideWithValue(preferences),
              yorksV1ConfigurationUnitCodesProvider.overrideWith(
                (ref) async => const ['Nos'],
              ),
              yorksV1LogisticsRepositoryProvider.overrideWithValue(repository),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: const YorksV1InventoryScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('GI duct sheet 24 gauge').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Receive / Adjust'));
        await tester.pumpAndSettle();
        if (correction) {
          await tester.tap(find.text('Correction'));
          await tester.pumpAndSettle();
        }
        await tester.enterText(
          find.widgetWithText(TextField, 'Stock quantity'),
          correction ? '-1' : '1',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Reason'),
          'Verified count',
        );
        await tester.tap(
          find
              .widgetWithText(
                FilledButton,
                correction ? 'Correction' : 'Add stock',
              )
              .last,
        );
        await tester.pumpAndSettle();
        expect(repository.inputs, hasLength(1));
        expect(repository.inputs.single.quantityDelta, correction ? '-1' : '1');
        expect(
          find.textContaining('The result is not confirmed.'),
          findsWidgets,
        );
        await tester.tap(find.text('Retry save'));
        await tester.pumpAndSettle();
        expect(repository.inputs, hasLength(2));
        expect(
          repository.inputs[0].idempotencyKey,
          repository.inputs[1].idempotencyKey,
        );
        expect(find.text('Retry save'), findsNothing);
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

Future<void> _openCategories(WidgetTester tester) async {
  final menu = find.byTooltip('Manage categories');
  if (menu.evaluate().isNotEmpty) {
    await tester.ensureVisible(menu);
    await tester.tap(menu);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('Manage categories').last);
  await tester.pumpAndSettle();
}

Future<void> _selectSection(WidgetTester tester, String label) async {
  final selector = find.byKey(const ValueKey('inventory-section-selector'));
  if (selector.evaluate().isNotEmpty) {
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
  } else {
    await tester.tap(find.text(label).first);
  }
  await tester.pumpAndSettle();
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

class _GoldenInventoryRepository
    implements YorksV1LogisticsRepository, YorksV1InventoryHistoryRepository {
  @override
  Future<YorksV1InventoryHistoryPage> getInventoryHistory(
    YorksV1InventoryHistoryQuery query,
  ) async => YorksV1InventoryHistoryPage(
    items: _workspace.recentMovements
        .where((m) => query.itemId == null || m.inventoryItemId == query.itemId)
        .toList(),
    hasMore: false,
  );

  const _GoldenInventoryRepository();

  @override
  Future<YorksV1InventoryWorkspace> getInventory({String? search}) async =>
      _workspace;

  @override
  Future<YorksV1InventoryItemDetail> getInventoryItem(
    String inventoryItemId,
  ) async {
    final item = _workspace.items.singleWhere(
      (item) => item.id == inventoryItemId,
    );
    return YorksV1InventoryItemDetail(
      item: item,
      movements: _workspace.recentMovements
          .where((movement) => movement.inventoryItemId == inventoryItemId)
          .toList(growable: false),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LargeInventoryRepository implements YorksV1LogisticsRepository {
  const _LargeInventoryRepository();

  @override
  Future<YorksV1InventoryWorkspace> getInventory({String? search}) async {
    final items = List.generate(
      100,
      (index) => YorksV1LogisticsInventoryItem(
        id: 'large-item-$index',
        itemCode: 'WH-LARGE-$index',
        description: 'Attention item $index',
        unit: 'Nos',
        minimumStock: '2',
        isActive: true,
        onHandQuantity: '0',
        reservedQuantity: '0',
        availableQuantity: '0',
        recordVersion: 1,
        metadataRecordVersion: 1,
      ),
    );
    return YorksV1InventoryWorkspace(
      items: items,
      categories: List.generate(
        100,
        (index) => _category(
          'large-category-$index',
          'Catalogue category ${index + 1}',
          index % 8,
        ),
      ),
      recentMovements: List.generate(
        100,
        (index) => YorksV1InventoryMovement(
          id: 'large-movement-$index',
          inventoryItemId: items[index].id,
          itemCode: items[index].itemCode,
          itemDescription: items[index].description,
          unit: items[index].unit,
          movementType: index.isEven ? 'opening_balance' : 'adjustment',
          quantityDelta: index.isEven ? '1' : '-1',
          onHandAfterQuantity: '0',
          reason: index.isEven ? 'Received stock' : 'Issued stock',
          actorDisplayName: 'Warehouse Controller',
          createdAt: DateTime.utc(
            2026,
            8,
            14,
            12,
          ).subtract(Duration(minutes: index)),
        ),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CategoryCreationRepository implements YorksV1LogisticsRepository {
  YorksV1InventoryCategoryCreationInput? creation;

  @override
  Future<YorksV1InventoryWorkspace> getInventory({String? search}) async =>
      _workspace;

  @override
  Future<YorksV1InventoryCategory> createInventoryCategory(
    YorksV1InventoryCategoryCreationInput input,
  ) async {
    creation = input;
    return YorksV1InventoryCategory(
      id: 'category-created',
      name: input.name,
      isSystem: false,
      isActive: true,
      recordVersion: 1,
      itemCount: 0,
      aliases: const [],
      createdByDisplayName: 'Ali Raza',
      createdAt: DateTime.utc(2026, 8, 10),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GoldenInventoryWorkbookFileService
    implements YorksV1InventoryWorkbookFileService {
  const _GoldenInventoryWorkbookFileService();

  @override
  Future<YorksV1InventorySelectedWorkbook?>
  selectWorkbook() async => YorksV1InventorySelectedWorkbook(
    fileName: 'Yorks_Warehouse_Inventory_Import_Template.csv',
    bytes: Uint8List.fromList(
      utf8.encode(
        '''Item Code,Item Description,Category,Brand / Origin,Unit,Stock Action,Quantity,Reason,Minimum Stock,Location / Bin,Notes
WH-NEW-001,Ceiling supply grille,Air Grille Fittings,Yorks,NOS,Opening Balance,10,Opening count,2,A-01,Receiving
WH-NEW-002,Wall return grille,Air Grille Fittings,Yorks,NOS,Opening Balance,8,Opening count,2,A-02,Receiving
WH-NEW-003,Weather louvre,Air Grille Fittings,Yorks,NOS,Opening Balance,6,Opening count,1,A-03,Receiving''',
      ),
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

class _RecordingInventoryWorkbookFileService
    implements YorksV1InventoryWorkbookFileService {
  int templateDownloads = 0;
  int registerExports = 0;
  int? lastItemCount;

  @override
  Future<YorksV1InventorySelectedWorkbook?> selectWorkbook() async => null;

  @override
  Future<bool> saveImportTemplate() async {
    templateDownloads += 1;
    return true;
  }

  @override
  Future<bool> saveStockRegister({
    required YorksV1InventoryWorkspace workspace,
    required String suggestedName,
  }) async {
    registerExports += 1;
    lastItemCount = workspace.items.length;
    expect(workspace.items, isNotEmpty);
    expect(suggestedName, endsWith('.xlsx'));
    return true;
  }
}

final _workspace = YorksV1InventoryWorkspace(
  items: [
    YorksV1LogisticsInventoryItem(
      id: 'item-1',
      itemCode: 'WH-DCT-001',
      description: 'GI duct sheet 24 gauge',
      categoryId: 'category-duct',
      categoryName: 'Ductwork & Accessories',
      brandOrigin: 'UAE',
      unit: 'Nos',
      minimumStock: '4.0000',
      locationBin: 'A-01',
      isActive: true,
      onHandQuantity: '12',
      reservedQuantity: '3',
      availableQuantity: '9',
      recordVersion: 3,
      metadataRecordVersion: 1,
      updatedAt: DateTime.utc(2026, 8, 9, 10, 30),
    ),
    YorksV1LogisticsInventoryItem(
      id: 'item-2',
      itemCode: 'WH-AT-001',
      description: 'Round air diffuser 300 mm',
      categoryId: 'category-round',
      categoryName: 'Air Terminals - Round',
      categoryPath: 'Air Terminals › Round',
      brandOrigin: 'Yorks',
      unit: 'Nos',
      minimumStock: '3',
      locationBin: 'B-03',
      isActive: true,
      onHandQuantity: '4',
      reservedQuantity: '2',
      availableQuantity: '2',
      recordVersion: 2,
      metadataRecordVersion: 1,
    ),
    YorksV1LogisticsInventoryItem(
      id: 'item-3',
      itemCode: 'WH-FAN-001',
      description: 'Inline ventilation fan 250 mm',
      categoryId: 'category-fan',
      categoryName: 'Fans & Equipment',
      brandOrigin: 'Systemair',
      unit: 'Nos',
      minimumStock: '1',
      locationBin: 'C-07',
      isActive: true,
      onHandQuantity: '0',
      reservedQuantity: '0',
      availableQuantity: '0',
      recordVersion: 1,
      metadataRecordVersion: 1,
    ),
  ],
  categories: [
    _category(
      'category-round',
      'Round',
      1,
      parentCategoryId: 'category-air-terminals',
      parentName: 'Air Terminals',
      aliases: const ['Round AC Terminal'],
    ),
    _category('category-air-terminals', 'Air Terminals', 0),
    _category('category-duct', 'Ductwork & Accessories', 1),
    _category('category-fan', 'Fans & Equipment', 1),
    _category('category-general', 'General & Custom', 0),
  ],
  recentMovements: [
    YorksV1InventoryMovement(
      id: 'movement-1',
      inventoryItemId: 'item-1',
      itemCode: 'WH-DCT-001',
      itemDescription: 'GI duct sheet 24 gauge',
      unit: 'Nos',
      movementType: 'opening_balance',
      quantityDelta: '12',
      onHandAfterQuantity: '12',
      reason: 'Verified opening balance',
      actorDisplayName: 'Ali Raza',
      createdAt: DateTime.utc(2026, 8, 9, 10, 30),
    ),
    YorksV1InventoryMovement(
      id: 'movement-2',
      inventoryItemId: 'item-2',
      itemCode: 'WH-AT-001',
      itemDescription: 'Round air diffuser 300 mm',
      unit: 'Nos',
      movementType: 'adjustment',
      quantityDelta: '-2',
      onHandAfterQuantity: '4',
      reason: 'Issued to approved dispatch',
      actorDisplayName: 'Ali Raza',
      createdAt: DateTime.utc(2026, 8, 9, 9, 10),
    ),
  ],
  reservations: [
    YorksV1InventoryReservation(
      id: 'reservation-1',
      inventoryItemId: 'item-1',
      itemCode: 'WH-DCT-001',
      itemDescription: 'GI duct sheet 24 gauge',
      unit: 'Nos',
      requestId: 'request-1',
      requestNumber: 'YRA322-MR101',
      projectName: 'Al Dhafra Grid Substation HVAC Works',
      scopeName: 'Common / All Buildings',
      reservedQuantity: '3',
      remainingQuantity: '3',
      state: 'active',
      createdAt: DateTime.utc(2026, 8, 9, 8),
    ),
  ],
  summary: const YorksV1InventorySummary(
    totalActiveItems: 3,
    lowStockCount: 1,
    outOfStockCount: 1,
    reservedCount: 2,
    incomingCount: 0,
  ),
);

YorksV1InventoryCategory _category(
  String id,
  String name,
  int itemCount, {
  String? parentCategoryId,
  String? parentName,
  List<String> aliases = const [],
}) => YorksV1InventoryCategory(
  id: id,
  name: name,
  isSystem: true,
  isActive: true,
  recordVersion: 1,
  itemCount: itemCount,
  parentCategoryId: parentCategoryId,
  parentName: parentName,
  aliases: aliases,
  createdByDisplayName: 'Yorks standard',
  createdAt: DateTime.utc(2026, 8, 9),
);

class _RetryStockRepository extends _GoldenInventoryRepository {
  final inputs = <YorksV1InventoryAdjustmentInput>[];
  @override
  Future<YorksV1LogisticsInventoryItem> adjustInventory(
    YorksV1InventoryAdjustmentInput input,
  ) async {
    inputs.add(input);
    if (inputs.length == 1) throw StateError('Lost response');
    return _workspace.items.first;
  }
}

class _PagedInventoryRepository extends _GoldenInventoryRepository
    implements YorksV1InventoryRegisterRepository {
  int fullReads = 0;
  final queries = <YorksV1InventoryRegisterQuery>[];
  final all = List.generate(
    120,
    (i) => YorksV1LogisticsInventoryItem(
      id: 'page-$i',
      description: 'Page item ${i.toString().padLeft(3, '0')}',
      unit: 'Nos',
      isActive: true,
      onHandQuantity: '10',
      reservedQuantity: '0',
      availableQuantity: '10',
      recordVersion: 1,
    ),
  );
  @override
  Future<YorksV1InventoryWorkspace> getInventory({String? search}) async {
    fullReads++;
    return YorksV1InventoryWorkspace(items: all);
  }

  @override
  Future<YorksV1InventoryWorkspace> getInventoryPage(
    YorksV1InventoryRegisterQuery query,
  ) async {
    queries.add(query);
    final matches = all
        .where((item) => item.description.contains(query.search))
        .toList();
    return YorksV1InventoryWorkspace(
      items: matches.skip(query.offset).take(query.limit).toList(),
      totalMatches: matches.length,
      pageOffset: query.offset,
      hasMore: query.offset + query.limit < matches.length,
      availableUnits: const ['Nos'],
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/widgets/widgets.dart';
import 'package:material_ledger/features/materials/presentation/screens/yorks_v1_arrangement_screen.dart';
import 'package:material_ledger/shared/models/yorks_v1_arrangement.dart';
import 'package:material_ledger/shared/models/yorks_v1_logistics.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/permissions_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_arrangement_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_arrangement_repository_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_logistics_repository_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_material_request_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_arrangement_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_logistics_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_procurement_progress_provider.dart';
import 'yorks_v1_procurement_progress_test.dart' show FakeRepository;
import 'support/yorks_v1_permission_test_support.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('NexusSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    var directory = File(Platform.resolvedExecutable).parent;
    while (!directory.path.endsWith('${Platform.pathSeparator}cache') &&
        directory.path != directory.parent.path) {
      directory = directory.parent;
    }
    final bytes = await File(
      '${directory.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await Future.wait([font.load(), icons.load()]);
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final entry in [
    (
      name:
          'fresh unmatched custom item selects external despite stocked catalogue',
      description: 'Custom pump',
      source: YorksV1ArrangementSource.warehouse,
      quantity: null,
      expectedSource: YorksV1ArrangementSource.externalSupplier,
    ),
    (
      name: 'fresh exact match selects warehouse and requested quantity',
      description: 'Motorized smoke damper',
      source: YorksV1ArrangementSource.warehouse,
      quantity: null,
      expectedSource: YorksV1ArrangementSource.warehouse,
    ),
    (
      name: 'explicit warehouse selection survives absent match',
      description: 'Custom pump',
      source: YorksV1ArrangementSource.warehouse,
      quantity: '2',
      expectedSource: YorksV1ArrangementSource.warehouse,
    ),
    (
      name: 'explicit external selection survives a warehouse match',
      description: 'Motorized smoke damper',
      source: YorksV1ArrangementSource.externalSupplier,
      quantity: '2',
      expectedSource: YorksV1ArrangementSource.externalSupplier,
    ),
    (
      name: 'fresh matched item without shelf reports its missing location',
      description: 'Motorized smoke damper alternate',
      source: YorksV1ArrangementSource.warehouse,
      quantity: null,
      expectedSource: YorksV1ArrangementSource.warehouse,
    ),
    (
      name: 'saved blank quantity remains blank and editable',
      description: 'Motorized smoke damper',
      source: YorksV1ArrangementSource.warehouse,
      quantity: '',
      expectedSource: YorksV1ArrangementSource.warehouse,
    ),
    (
      name: 'saved zero quantity remains zero and editable',
      description: 'Motorized smoke damper',
      source: YorksV1ArrangementSource.warehouse,
      quantity: '0',
      expectedSource: YorksV1ArrangementSource.warehouse,
    ),
  ]) {
    testWidgets(entry.name, (tester) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final preferences = await SharedPreferences.getInstance();
      final workspace = YorksV1ArrangementWorkspace(
        requestId: 'request-1',
        requestState: 'arranging',
        requestRecordVersion: 2,
        canBegin: false,
        canSave: true,
        canDecide: false,
        arrangements: [
          YorksV1ProcurementArrangement(
            id: 'arrangement-1',
            version: 1,
            status: YorksV1ArrangementStatus.working,
            isCurrent: true,
            recordVersion: 1,
            startedByDisplayName: 'Procurement',
            startedAt: DateTime.utc(2026, 10, 9),
            lines: [
              YorksV1ArrangementLine(
                id: 'arrangement-line-1',
                requestLineId: 'request-line-1',
                displayOrder: 1,
                description: entry.description,
                requestedQuantity: '11',
                unit: 'Nos',
                source: entry.source,
                arrangedQuantity: entry.quantity,
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1AuthUserIdProvider.overrideWithValue(
              'procurement-test-user',
            ),
            yorksV1ProcurementProgressRepositoryProvider.overrideWithValue(
              FakeRepository(),
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1CurrentPermissionSnapshotProvider.overrideWith(
              (ref) => YorksV1TestPermissionController(
                yorksV1TrustedFeaturePermissionState(),
              ),
            ),
            yorksV1MaterialRequestDetailProvider(
              'request-1',
            ).overrideWith((ref) async => _request),
            yorksV1ArrangementRepositoryProvider.overrideWithValue(
              _ArrangementRepository(),
            ),
            yorksV1ArrangementWorkspaceProvider(
              'request-1',
            ).overrideWith((ref) async => workspace),
            yorksV1ArrangementInventoryProvider.overrideWith(
              (ref) async => _inventoryItems,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const YorksV1ArrangementScreen(
              requestId: 'request-1',
              embedded: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (entry.quantity != '0') {
        expect(
          tester
              .widget<ChoiceChip>(
                find.byKey(
                  ValueKey(
                    'source-arrangement-line-1-${entry.expectedSource.wireValue}',
                  ),
                ),
              )
              .selected,
          isTrue,
        );
      }
      final quantityField = find.byKey(
        const ValueKey('arranged-arrangement-line-1'),
      );
      expect(
        tester.widget<TextFormField>(quantityField).controller!.text,
        entry.quantity ?? '11',
      );
      expect(tester.widget<TextFormField>(quantityField).enabled, isTrue);
      if (entry.quantity == '') {
        expect(find.text('Enter quantity'), findsOneWidget);
      }
      if (entry.description == 'Motorized smoke damper' &&
          entry.quantity == null &&
          entry.expectedSource == YorksV1ArrangementSource.warehouse) {
        expect(
          find.text('Shelf / bin: Rack B / Shelf 3').hitTestable(),
          findsOneWidget,
        );
        final search = find.byKey(
          const ValueKey('warehouse-search-arrangement-line-1'),
        );
        await tester.enterText(search, 'Motorized');
        await tester.pumpAndSettle();
        // Every option supplies location context. A missing shelf is explicit,
        // never copied from another inventory item or invented from its code.
        expect(
          find.textContaining('Shelf / bin: Rack B / Shelf 3'),
          findsNWidgets(2),
        );
        expect(find.textContaining('Shelf / bin not set'), findsOneWidget);
        await tester.tap(
          find.text('MSD-ALT · Motorized smoke damper alternate'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Shelf / bin not set').hitTestable(), findsOneWidget);
        expect(find.textContaining('Rack B / Shelf 3'), findsNothing);
      }
      if (entry.description == 'Motorized smoke damper alternate') {
        expect(find.text('Shelf / bin not set').hitTestable(), findsOneWidget);
        expect(find.textContaining('Rack B / Shelf 3'), findsNothing);
      }
      if (entry.quantity == '' || entry.quantity == '0') {
        await tester.enterText(quantityField, '3');
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextFormField>(quantityField).controller!.text,
          '3',
        );
        expect(tester.widget<TextFormField>(quantityField).enabled, isTrue);
        await tester.enterText(quantityField, '0');
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextFormField>(quantityField).controller!.text,
          '0',
        );
        expect(tester.widget<TextFormField>(quantityField).enabled, isTrue);
        await tester.enterText(quantityField, '');
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextFormField>(quantityField).controller!.text,
          '',
        );
        expect(tester.widget<TextFormField>(quantityField).enabled, isTrue);
        expect(find.text('Enter quantity'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'desktop scroll keeps item pinned and blocks source input beneath it',
    (tester) async {
      tester.view.physicalSize = const Size(1040, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1AuthUserIdProvider.overrideWithValue(
              'procurement-test-user',
            ),
            yorksV1ProcurementProgressRepositoryProvider.overrideWithValue(
              FakeRepository(),
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1CurrentPermissionSnapshotProvider.overrideWith(
              (ref) => YorksV1TestPermissionController(
                yorksV1TrustedFeaturePermissionState(),
              ),
            ),
            yorksV1MaterialRequestDetailProvider(
              'request-1',
            ).overrideWith((ref) async => _request),
            canManageCommercialsProvider.overrideWithValue(true),
            canViewCommercialsProvider.overrideWithValue(true),
            yorksV1ArrangementRepositoryProvider.overrideWithValue(
              _ArrangementRepository(),
            ),
            yorksV1ArrangementWorkspaceProvider(
              'request-1',
            ).overrideWith((ref) async => _externalSupplierWorkspace),
            yorksV1ArrangementInventoryProvider.overrideWith(
              (ref) async => _inventoryItems,
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const YorksV1ArrangementScreen(
              requestId: 'request-1',
              embedded: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Availability details (optional)'));
      await tester.pumpAndSettle();

      final identity = find.text('Cable tray hanging clamp').hitTestable();
      final identityHeader = find.text('Requested item').hitTestable();
      final quantity = find.byKey(
        const ValueKey('arranged-arrangement-line-2'),
      );
      final quantityHeader = find.text('ARRANGED');
      final source = find.byKey(
        const ValueKey('source-arrangement-line-2-warehouse'),
      );
      final sourceHeader = find.text('SUPPLIER / SOURCE');
      expect(
        tester.getTopLeft(quantity).dx,
        closeTo(tester.getTopLeft(quantityHeader).dx, 1),
      );
      expect(
        tester.getTopLeft(source).dx,
        closeTo(tester.getTopLeft(sourceHeader).dx, 1),
      );
      final identityBefore = tester.getTopLeft(identity);
      final identityHeaderBefore = tester.getTopLeft(identityHeader);
      final quantityBefore = tester.getTopLeft(quantity);
      final horizontal = tester
          .widget<SingleChildScrollView>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is SingleChildScrollView &&
                  widget.scrollDirection == Axis.horizontal,
            ),
          )
          .controller!;
      expect(horizontal.position.maxScrollExtent, greaterThan(0));
      horizontal.jumpTo(horizontal.position.maxScrollExtent);
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(identity).dx, closeTo(identityBefore.dx, 1));
      expect(
        tester.getTopLeft(identityHeader).dx,
        closeTo(identityHeaderBefore.dx, 1),
      );
      expect(
        tester.getTopLeft(quantity).dx,
        closeTo(quantityBefore.dx - horizontal.offset, 1),
      );
      expect(
        tester.getTopLeft(quantity).dx,
        closeTo(tester.getTopLeft(quantityHeader).dx, 1),
      );

      // A tall source editor must neither show through nor accept pointer input
      // beneath the pinned item, even below its short title and edit action.
      final expectedDate = find.byKey(
        const ValueKey('external-expected-arrangement-line-2'),
      );
      final sourceBox = tester.renderObject<RenderBox>(expectedDate);
      final sourceBounds = tester.getRect(expectedDate);
      final pinnedBackground = find
          .ancestor(
            of: identity,
            matching: find.byWidgetPredicate(
              (widget) => widget is Container && widget.color != null,
            ),
          )
          .first;
      final pinnedBounds = tester.getRect(pinnedBackground);
      expect(sourceBounds.top, greaterThan(tester.getBottomLeft(identity).dy));
      expect(pinnedBounds.bottom, greaterThanOrEqualTo(sourceBounds.bottom));
      final coveredPoint = Offset(
        sourceBounds.left + 2,
        sourceBounds.center.dy,
      );
      expect(pinnedBounds.contains(coveredPoint), isTrue);
      expect(
        tester
            .hitTestOnBinding(coveredPoint)
            .path
            .any((entry) => entry.target == sourceBox),
        isFalse,
      );
      expect(
        tester
            .hitTestOnBinding(
              Offset(sourceBounds.right - 2, sourceBounds.center.dy),
            )
            .path
            .any((entry) => entry.target == sourceBox),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'procurement can edit item details in the unsaved arrangement editor',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = _ArrangementRepository();
      final preferences = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1AuthUserIdProvider.overrideWithValue(
              'procurement-test-user',
            ),
            yorksV1ProcurementProgressRepositoryProvider.overrideWithValue(
              FakeRepository(),
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1CurrentPermissionSnapshotProvider.overrideWith(
              (ref) => YorksV1TestPermissionController(
                yorksV1TrustedFeaturePermissionState(),
              ),
            ),
            yorksV1MaterialRequestDetailProvider(
              'request-1',
            ).overrideWith((ref) async => _request),
            yorksV1ArrangementRepositoryProvider.overrideWithValue(repository),
            yorksV1ArrangementWorkspaceProvider(
              'request-1',
            ).overrideWith((ref) async => _workingWorkspace),
            yorksV1ArrangementInventoryProvider.overrideWith(
              (ref) async => _inventoryItems,
            ),
            yorksV1MaterialRequestInventorySearchProvider(
              const YorksV1MaterialRequestInventorySearchKey(
                projectId: 'project-1',
                scopeId: 'scope-1',
                query: 'damper',
              ),
            ).overrideWith(
              (ref) async => const [
                YorksV1MaterialRequestInventorySuggestion(
                  id: 'known-damper',
                  description: 'Known fire damper',
                  model: 'KFD-500',
                  unit: 'Nos',
                ),
              ],
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: YorksV1ArrangementScreen(
              requestId: 'request-1',
              embedded: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit item details').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('Originally requested'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('procurement-item-description')),
        findsOneWidget,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/r35/arrange_clarify_item_desktop_1366x900.png',
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('procurement-item-search')),
        'damper',
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Known fire damper'), findsNothing);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Known fire damper'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('procurement-item-description')),
            )
            .controller
            ?.text,
        'Known fire damper',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('procurement-item-model')),
            )
            .controller
            ?.text,
        'KFD-500',
      );
      await tester.enterText(
        find.byKey(const ValueKey('procurement-item-description')),
        'Motorized smoke damper MSD-600',
      );
      await tester.enterText(
        find.byKey(const ValueKey('procurement-item-model')),
        'MSD-600',
      );
      await tester.tap(
        find.byKey(const ValueKey('save-procurement-item-clarification')),
      );
      await tester.pumpAndSettle();

      expect(repository.clarificationInputs, hasLength(1));
      expect(
        repository.clarificationInputs.single.itemDescription,
        'Motorized smoke damper MSD-600',
      );
      expect(repository.clarificationInputs.single.modelReference, 'MSD-600');
      await tester.pump(const Duration(seconds: 6));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('item detail editing uses a focused mobile sheet at 360px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          yorksV1AuthUserIdProvider.overrideWithValue('procurement-test-user'),
          yorksV1ProcurementProgressRepositoryProvider.overrideWithValue(
            FakeRepository(),
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
          yorksV1CurrentPermissionSnapshotProvider.overrideWith(
            (ref) => YorksV1TestPermissionController(
              yorksV1TrustedFeaturePermissionState(),
            ),
          ),
          yorksV1MaterialRequestDetailProvider(
            'request-1',
          ).overrideWith((ref) async => _request),
          yorksV1ArrangementRepositoryProvider.overrideWithValue(
            _ArrangementRepository(),
          ),
          yorksV1ArrangementWorkspaceProvider(
            'request-1',
          ).overrideWith((ref) async => _workingWorkspace),
          yorksV1ArrangementInventoryProvider.overrideWith(
            (ref) async => _inventoryItems,
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: YorksV1ArrangementScreen(
            requestId: 'request-1',
            embedded: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit item details').hitTestable());
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('procurement-item-description')),
      findsOneWidget,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/r35/arrange_clarify_item_mobile_360x800.png'),
    );
  });

  testWidgets('failed clarification keeps the entered details for retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repository = _ArrangementRepository()..failNextClarification = true;
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          yorksV1AuthUserIdProvider.overrideWithValue('procurement-test-user'),
          yorksV1ProcurementProgressRepositoryProvider.overrideWithValue(
            FakeRepository(),
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
          yorksV1CurrentPermissionSnapshotProvider.overrideWith(
            (ref) => YorksV1TestPermissionController(
              yorksV1TrustedFeaturePermissionState(),
            ),
          ),
          yorksV1MaterialRequestDetailProvider(
            'request-1',
          ).overrideWith((ref) async => _request),
          yorksV1ArrangementRepositoryProvider.overrideWithValue(repository),
          yorksV1ArrangementWorkspaceProvider(
            'request-1',
          ).overrideWith((ref) async => _workingWorkspace),
          yorksV1ArrangementInventoryProvider.overrideWith(
            (ref) async => _inventoryItems,
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: YorksV1ArrangementScreen(
            requestId: 'request-1',
            embedded: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit item details').hitTestable());
    await tester.pumpAndSettle();
    final description = find.byKey(
      const ValueKey('procurement-item-description'),
    );
    await tester.enterText(description, 'Retry-safe damper');
    await tester.tap(
      find.byKey(const ValueKey('save-procurement-item-clarification')),
    );
    await tester.pumpAndSettle();

    expect(description, findsOneWidget);
    expect(find.text('Retry-safe damper'), findsOneWidget);
    expect(
      find.textContaining('Item details could not be updated'),
      findsOneWidget,
    );
    expect(repository.clarificationInputs, hasLength(1));
  });

  testWidgets(
    'pending Procurement clarification locks arrangement and stays correctable',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final preferences = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1AuthUserIdProvider.overrideWithValue(
              'procurement-test-user',
            ),
            yorksV1ProcurementProgressRepositoryProvider.overrideWithValue(
              FakeRepository(),
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1CurrentPermissionSnapshotProvider.overrideWith(
              (ref) => YorksV1TestPermissionController(
                yorksV1TrustedFeaturePermissionState(),
              ),
            ),
            yorksV1MaterialRequestDetailProvider(
              'request-1',
            ).overrideWith((ref) async => _request),
            yorksV1ArrangementRepositoryProvider.overrideWithValue(
              _ArrangementRepository(),
            ),
            yorksV1ArrangementWorkspaceProvider(
              'request-1',
            ).overrideWith((ref) async => _pendingClarificationWorkspace),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: YorksV1ArrangementScreen(
              requestId: 'request-1',
              embedded: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('procurement-clarification-review-required')),
        findsOneWidget,
      );
      expect(find.text('Engineering approval required'), findsOneWidget);
      final saveLabel = find.text('Review arrangement');
      expect(saveLabel, findsOneWidget);
      expect(
        tester
            .widget<InkWell>(
              find.ancestor(of: saveLabel, matching: find.byType(InkWell)),
            )
            .onTap,
        isNull,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/r35/arrange_clarification_review_desktop_1366x900.png',
        ),
      );

      await tester.tap(find.text('Edit item details').hitTestable());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('procurement-item-description')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'pending Procurement clarification remains clear and usable at 360px',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final preferences = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1AuthUserIdProvider.overrideWithValue(
              'procurement-test-user',
            ),
            yorksV1ProcurementProgressRepositoryProvider.overrideWithValue(
              FakeRepository(),
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1CurrentPermissionSnapshotProvider.overrideWith(
              (ref) => YorksV1TestPermissionController(
                yorksV1TrustedFeaturePermissionState(),
              ),
            ),
            yorksV1MaterialRequestDetailProvider(
              'request-1',
            ).overrideWith((ref) async => _request),
            yorksV1ArrangementRepositoryProvider.overrideWithValue(
              _ArrangementRepository(),
            ),
            yorksV1ArrangementWorkspaceProvider(
              'request-1',
            ).overrideWith((ref) async => _pendingClarificationWorkspace),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: YorksV1ArrangementScreen(requestId: 'request-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('procurement-clarification-review-required')),
        findsOneWidget,
      );
      final reviewAction = tester.widget<PrimaryButton>(
        find.byKey(const ValueKey('mobile-arrangement-review-action')),
      );
      expect(reviewAction.onPressed, isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/r35/arrange_clarification_review_mobile_360x800.png',
        ),
      );

      await tester.tap(find.text('Motorized smoke damper'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('mobile-clarify-item-action')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('procurement-item-description')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'embedded arrangement opens the direct editor and closes after a saved hand-off',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = _ArrangementRepository();
      final preferences = await SharedPreferences.getInstance();
      var completed = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1AuthUserIdProvider.overrideWithValue(
              'procurement-test-user',
            ),
            yorksV1ProcurementProgressRepositoryProvider.overrideWithValue(
              FakeRepository(),
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1CurrentPermissionSnapshotProvider.overrideWith(
              (ref) => YorksV1TestPermissionController(
                yorksV1TrustedFeaturePermissionState(),
              ),
            ),
            yorksV1MaterialRequestDetailProvider(
              'request-1',
            ).overrideWith((ref) async => _request),
            canManageCommercialsProvider.overrideWithValue(true),
            canViewCommercialsProvider.overrideWithValue(true),
            yorksV1ArrangementRepositoryProvider.overrideWithValue(repository),
            yorksV1ArrangementWorkspaceProvider(
              'request-1',
            ).overrideWith((ref) async => _workingWorkspace),
            yorksV1ArrangementInventoryProvider.overrideWith(
              (ref) async => const [
                YorksV1InventoryItem(
                  id: 'inventory-1',
                  description: 'Motorized smoke damper',
                  unit: 'Nos',
                  onHandQuantity: '12',
                  reservedQuantity: '0',
                  availableQuantity: '12',
                  recordVersion: 1,
                ),
              ],
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: SizedBox(
              width: 1320,
              height: 760,
              child: YorksV1ArrangementScreen(
                requestId: 'request-1',
                embedded: true,
                onCompleted: () => completed = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Arrange Material Request'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('material-request-information-action')),
        findsOneWidget,
      );
      expect(find.text('Start arrangement'), findsNothing);
      expect(find.text('REQUESTED ITEM'), findsOneWidget);
      expect(
        find
            .text('Linked to BOQ · Building A · Dampers & Fire Control')
            .hitTestable(),
        findsOneWidget,
      );
      expect(find.text('Review arrangement'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/r35/arrange_material_request_desktop.png'),
      );

      await _tapReviewAndSave(tester, find.text('Review arrangement'));
      await tester.pumpAndSettle();

      expect(repository.saveInputs, hasLength(1));
      expect(completed, isTrue);
      expect(find.text('Arrangement saved and confirmed'), findsOneWidget);
      expect(
        find.textContaining('1 full · 0 partial · 0 unavailable'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 6));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'revoked commercial capability hides cost and omits protected writes',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = _ArrangementRepository();
      final preferences = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1AuthUserIdProvider.overrideWithValue(
              'procurement-test-user',
            ),
            yorksV1ProcurementProgressRepositoryProvider.overrideWithValue(
              FakeRepository(),
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1CurrentPermissionSnapshotProvider.overrideWith(
              (ref) => YorksV1TestPermissionController(
                yorksV1TrustedFeaturePermissionState(),
              ),
            ),
            yorksV1MaterialRequestDetailProvider(
              'request-1',
            ).overrideWith((ref) async => _request),
            canManageCommercialsProvider.overrideWithValue(false),
            canViewCommercialsProvider.overrideWithValue(false),
            yorksV1ArrangementRepositoryProvider.overrideWithValue(repository),
            yorksV1ArrangementWorkspaceProvider(
              'request-1',
            ).overrideWith((ref) async => _workingWorkspace),
            yorksV1ArrangementInventoryProvider.overrideWith(
              (ref) async => _inventoryItems,
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: YorksV1ArrangementScreen(
              requestId: 'request-1',
              embedded: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Unit Cost'), findsNothing);
      expect(find.text('110.29'), findsNothing);
      await _tapReviewAndSave(tester, find.text('Review arrangement'));
      await tester.pumpAndSettle();

      expect(repository.saveInputs, hasLength(1));
      expect(repository.saveInputs.single.lines.single.unitCost, isNull);
      await tester.pump(const Duration(seconds: 6));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'required external readiness stays visible and duplicate save is blocked',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = _ArrangementRepository();
      final preferences = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1AuthUserIdProvider.overrideWithValue(
              'procurement-test-user',
            ),
            yorksV1ProcurementProgressRepositoryProvider.overrideWithValue(
              FakeRepository(),
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1CurrentPermissionSnapshotProvider.overrideWith(
              (ref) => YorksV1TestPermissionController(
                yorksV1TrustedFeaturePermissionState(),
              ),
            ),
            yorksV1MaterialRequestDetailProvider(
              'request-1',
            ).overrideWith((ref) async => _request),
            canManageCommercialsProvider.overrideWithValue(false),
            canViewCommercialsProvider.overrideWithValue(false),
            yorksV1ArrangementRepositoryProvider.overrideWithValue(repository),
            yorksV1ArrangementWorkspaceProvider('request-1').overrideWith(
              (ref) async => YorksV1ArrangementWorkspace(
                requestId: 'request-1',
                requestState: 'arranging',
                requestRecordVersion: 1,
                canBegin: false,
                canSave: true,
                canDecide: false,
                externalSourceReadinessRequired: true,
                arrangements: _externalSupplierWorkspace.arrangements,
              ),
            ),
            yorksV1ArrangementInventoryProvider.overrideWith(
              (ref) async => const [],
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: YorksV1ArrangementScreen(
              requestId: 'request-1',
              embedded: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ready = find.byKey(
        const ValueKey('external-ready-arrangement-line-2'),
      );
      expect(ready, findsOneWidget);
      final save = find.text('Review arrangement');
      await tester.ensureVisible(save);
      await _tapReviewAndSave(tester, save);
      await tester.pumpAndSettle();
      expect(repository.saveInputs, isEmpty);
      await tester.ensureVisible(ready);
      await tester.tap(ready);
      await tester.pumpAndSettle();
      await tester.ensureVisible(save);
      repository.pendingSave = Completer<void>();
      // Two taps before the next frame must still execute just one command.
      final reviewAction = tester
          .widget<PrimaryButton>(
            find.ancestor(of: save, matching: find.byType(PrimaryButton)),
          )
          .onPressed!;
      reviewAction();
      reviewAction();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      final confirm = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save arrangement'),
          )
          .onPressed!;
      confirm();
      confirm();
      await tester.pump();
      expect(repository.saveInputs, hasLength(1));
      expect(
        repository.saveInputs.single.lines.single.externalSourceReady,
        isTrue,
      );
      repository.pendingSave!.complete();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 6));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Full external supplier saves without supplier name or reason', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repository = _ArrangementRepository();
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          yorksV1AuthUserIdProvider.overrideWithValue('procurement-test-user'),
          yorksV1ProcurementProgressRepositoryProvider.overrideWithValue(
            FakeRepository(),
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
          yorksV1CurrentPermissionSnapshotProvider.overrideWith(
            (ref) => YorksV1TestPermissionController(
              yorksV1TrustedFeaturePermissionState(),
            ),
          ),
          yorksV1MaterialRequestDetailProvider(
            'request-1',
          ).overrideWith((ref) async => _request),
          canManageCommercialsProvider.overrideWithValue(false),
          canViewCommercialsProvider.overrideWithValue(false),
          yorksV1ArrangementRepositoryProvider.overrideWithValue(repository),
          yorksV1ArrangementWorkspaceProvider(
            'request-1',
          ).overrideWith((ref) async => _externalSupplierWorkspace),
          yorksV1ArrangementInventoryProvider.overrideWith(
            (ref) async => const [],
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: YorksV1ArrangementScreen(
            requestId: 'request-1',
            embedded: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final external = find.byKey(
      const ValueKey('source-arrangement-line-2-external_supplier'),
    );
    await tester.tap(
      find.byKey(const ValueKey('source-arrangement-line-2-warehouse')),
    );
    await tester.pumpAndSettle();
    await tester.tap(external);
    await tester.pumpAndSettle();
    expect(repository.saveInputs, isEmpty);
    expect(tester.widget<ChoiceChip>(external).selected, isTrue);
    expect(
      find.byKey(const ValueKey('external-ready-arrangement-line-2')),
      findsNothing,
    );
    expect(find.text('Add supplier details (optional)'), findsOneWidget);
    expect(find.text('Supplier name optional'), findsNothing);
    expect(
      find.byKey(const ValueKey('reason-arrangement-line-2-full')),
      findsNothing,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        'goldens/r35/arrange_external_supplier_optional_desktop.png',
      ),
    );
    for (final width in [1920.0, 1024.0, 768.0, 360.0, 1366.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      await tester.ensureVisible(external);
      expect(tester.widget<ChoiceChip>(external).selected, isTrue);
      expect(tester.takeException(), isNull);
      if (width == 768 || width == 360) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/r35/arrange_external_quick_${width.toInt()}.png',
          ),
        );
      }
    }
    await tester.ensureVisible(find.text('Review arrangement'));
    await _tapReviewAndSave(tester, find.text('Review arrangement'));
    await tester.pumpAndSettle();

    expect(repository.saveInputs, hasLength(1));
    final line = repository.saveInputs.single.lines.single;
    expect(line.source, YorksV1ArrangementSource.externalSupplier);
    expect(line.decision, YorksV1ArrangementDecision.full);
    expect(line.externalSupplier, isNull);
    expect(line.reason, isNull);
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('external readiness remains complete and usable at 360px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repository = _ArrangementRepository();
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          yorksV1AuthUserIdProvider.overrideWithValue('procurement-test-user'),
          yorksV1ProcurementProgressRepositoryProvider.overrideWithValue(
            FakeRepository(),
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
          yorksV1CurrentPermissionSnapshotProvider.overrideWith(
            (ref) => YorksV1TestPermissionController(
              yorksV1TrustedFeaturePermissionState(),
            ),
          ),
          yorksV1MaterialRequestDetailProvider(
            'request-1',
          ).overrideWith((ref) async => _request),
          canManageCommercialsProvider.overrideWithValue(false),
          canViewCommercialsProvider.overrideWithValue(false),
          yorksV1ArrangementRepositoryProvider.overrideWithValue(repository),
          yorksV1ArrangementWorkspaceProvider(
            'request-1',
          ).overrideWith((ref) async => _externalSupplierWorkspace),
          yorksV1ArrangementInventoryProvider.overrideWith(
            (ref) async => const [],
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: YorksV1ArrangementScreen(
            requestId: 'request-1',
            embedded: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await Scrollable.ensureVisible(
      tester.element(find.text('Availability details (optional)')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Availability details (optional)'));
    await tester.pumpAndSettle();

    final ready = find.byKey(
      const ValueKey('external-ready-arrangement-line-2'),
    );
    final expectedDate = find.byKey(
      const ValueKey('external-expected-arrangement-line-2'),
    );
    final reference = find.byKey(
      const ValueKey('external-reference-arrangement-line-2'),
    );
    expect(ready, findsOneWidget);
    expect(expectedDate, findsOneWidget);
    expect(reference, findsOneWidget);

    await tester.ensureVisible(ready);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        'goldens/r35/arrange_external_readiness_mobile_360.png',
      ),
    );
    await tester.tap(ready);
    await tester.ensureVisible(expectedDate);
    await tester.enterText(expectedDate, '2026-09-01');
    await tester.ensureVisible(reference);
    await tester.enterText(reference, 'QUOTE-2026-91');
    await Scrollable.ensureVisible(
      tester.element(find.text('Availability details (optional)')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Availability details (optional)'));
    await tester.pumpAndSettle();
    expect(reference, findsNothing);
    tester.view.physicalSize = const Size(1024, 900);
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.text('Availability details (optional)')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Availability details (optional)'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(reference);
    expect(
      tester.widget<TextFormField>(reference).initialValue,
      'QUOTE-2026-91',
    );
    final save = find.text('Review arrangement');
    await tester.ensureVisible(save);
    await _tapReviewAndSave(tester, save);
    await tester.pumpAndSettle();

    expect(repository.saveInputs, hasLength(1));
    final line = repository.saveInputs.single.lines.single;
    expect(line.externalSourceReady, isTrue);
    expect(line.externalExpectedDate, '2026-09-01');
    expect(line.externalReference, 'QUOTE-2026-91');
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('direct arrangement editor remains usable at 360px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          yorksV1AuthUserIdProvider.overrideWithValue('procurement-test-user'),
          yorksV1ProcurementProgressRepositoryProvider.overrideWithValue(
            FakeRepository(),
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
          yorksV1CurrentPermissionSnapshotProvider.overrideWith(
            (ref) => YorksV1TestPermissionController(
              yorksV1TrustedFeaturePermissionState(),
            ),
          ),
          yorksV1MaterialRequestDetailProvider(
            'request-1',
          ).overrideWith((ref) async => _request),
          canManageCommercialsProvider.overrideWithValue(true),
          canViewCommercialsProvider.overrideWithValue(true),
          yorksV1ArrangementRepositoryProvider.overrideWithValue(
            _ArrangementRepository(),
          ),
          yorksV1ArrangementWorkspaceProvider(
            'request-1',
          ).overrideWith((ref) async => _workingWorkspace),
          yorksV1ArrangementInventoryProvider.overrideWith(
            (ref) async => const [
              YorksV1InventoryItem(
                id: 'inventory-1',
                description: 'Motorized smoke damper',
                unit: 'Nos',
                onHandQuantity: '12',
                reservedQuantity: '0',
                availableQuantity: '12',
                recordVersion: 1,
              ),
            ],
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: YorksV1ArrangementScreen(requestId: 'request-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Arrange requested items'), findsOneWidget);
    expect(find.text('Start arrangement'), findsNothing);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/r35/arrange_material_request_mobile.png'),
    );
  });

  testWidgets(
    'warehouse source ranks inventory matches and retains the selected item',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = _ArrangementRepository();
      final preferences = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1AuthUserIdProvider.overrideWithValue(
              'procurement-test-user',
            ),
            yorksV1ProcurementProgressRepositoryProvider.overrideWithValue(
              FakeRepository(),
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1CurrentPermissionSnapshotProvider.overrideWith(
              (ref) => YorksV1TestPermissionController(
                yorksV1TrustedFeaturePermissionState(),
              ),
            ),
            yorksV1MaterialRequestDetailProvider(
              'request-1',
            ).overrideWith((ref) async => _request),
            canManageCommercialsProvider.overrideWithValue(true),
            canViewCommercialsProvider.overrideWithValue(true),
            yorksV1ArrangementRepositoryProvider.overrideWithValue(repository),
            yorksV1ArrangementWorkspaceProvider(
              'request-1',
            ).overrideWith((ref) async => _workingWorkspace),
            yorksV1ArrangementInventoryProvider.overrideWith(
              (ref) async => _inventoryItems,
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: YorksV1ArrangementScreen(
              requestId: 'request-1',
              embedded: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final search = find.byKey(
        const ValueKey('warehouse-search-arrangement-line-1'),
      );
      expect(search, findsOneWidget);
      expect(find.text('Create inventory item'), findsOneWidget);

      await tester.tap(search);
      await tester.enterText(search, 'MSD-ALT');
      await tester.pumpAndSettle();
      await tester.tap(find.text('MSD-ALT · Motorized smoke damper alternate'));
      await tester.pumpAndSettle();
      await _tapReviewAndSave(tester, find.text('Review arrangement'));
      await tester.pumpAndSettle();

      expect(repository.saveInputs, hasLength(1));
      expect(
        repository.saveInputs.single.lines.single.inventoryItemId,
        'inventory-2',
      );
      await tester.pump(const Duration(seconds: 6));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'zero warehouse availability blocks save with an actionable message',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = _ArrangementRepository();
      final preferences = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1AuthUserIdProvider.overrideWithValue(
              'procurement-test-user',
            ),
            yorksV1ProcurementProgressRepositoryProvider.overrideWithValue(
              FakeRepository(),
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1CurrentPermissionSnapshotProvider.overrideWith(
              (ref) => YorksV1TestPermissionController(
                yorksV1TrustedFeaturePermissionState(),
              ),
            ),
            yorksV1MaterialRequestDetailProvider(
              'request-1',
            ).overrideWith((ref) async => _request),
            canManageCommercialsProvider.overrideWithValue(true),
            canViewCommercialsProvider.overrideWithValue(true),
            yorksV1ArrangementRepositoryProvider.overrideWithValue(repository),
            yorksV1ArrangementWorkspaceProvider(
              'request-1',
            ).overrideWith((ref) async => _workingWorkspace),
            yorksV1ArrangementInventoryProvider.overrideWith(
              (ref) async => const [
                YorksV1InventoryItem(
                  id: 'inventory-1',
                  itemCode: 'MSD-600',
                  description: 'Motorized smoke damper',
                  unit: 'Nos',
                  onHandQuantity: '0',
                  reservedQuantity: '0',
                  availableQuantity: '0',
                  recordVersion: 2,
                ),
              ],
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: YorksV1ArrangementScreen(
              requestId: 'request-1',
              embedded: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
      await _tapReviewAndSave(tester, find.text('Review arrangement'));
      await tester.pumpAndSettle();

      expect(repository.saveInputs, isEmpty);
      expect(
        find.byKey(const ValueKey('arrangement-validation-summary')),
        findsOneWidget,
      );
      expect(find.text('1 row needs attention before saving.'), findsOneWidget);
      expect(find.text('Item 1'), findsOneWidget);
      expect(
        find.textContaining('11 Nos is arranged but only 0 Nos is available'),
        findsOneWidget,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/r35/arrange_inline_validation_desktop.png'),
      );
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a retained request reservation remains available to its replacement',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = _ArrangementRepository();
      final preferences = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1AuthUserIdProvider.overrideWithValue(
              'procurement-test-user',
            ),
            yorksV1ProcurementProgressRepositoryProvider.overrideWithValue(
              FakeRepository(),
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1CurrentPermissionSnapshotProvider.overrideWith(
              (ref) => YorksV1TestPermissionController(
                yorksV1TrustedFeaturePermissionState(),
              ),
            ),
            yorksV1MaterialRequestDetailProvider(
              'request-1',
            ).overrideWith((ref) async => _request),
            yorksV1ArrangementRepositoryProvider.overrideWithValue(repository),
            yorksV1ArrangementWorkspaceProvider(
              'request-1',
            ).overrideWith((ref) async => _replacementWorkspace),
            yorksV1ArrangementInventoryProvider.overrideWith(
              (ref) async => const [
                YorksV1InventoryItem(
                  id: 'inventory-1',
                  description: 'Motorized smoke damper',
                  unit: 'Nos',
                  onHandQuantity: '11',
                  reservedQuantity: '11',
                  availableQuantity: '0',
                  recordVersion: 2,
                ),
              ],
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: YorksV1ArrangementScreen(
              requestId: 'request-1',
              embedded: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tapReviewAndSave(tester, find.text('Review arrangement'));
      await tester.pumpAndSettle();

      expect(repository.saveInputs, hasLength(1));
      await tester.pump(const Duration(seconds: 6));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Procurement can create a zero-stock item from a request line without inventing a reservation',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final preferences = await SharedPreferences.getInstance();
      final inventory = _ArrangementCreationInventoryRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1AuthUserIdProvider.overrideWithValue(
              'procurement-test-user',
            ),
            yorksV1ProcurementProgressRepositoryProvider.overrideWithValue(
              FakeRepository(),
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1CurrentPermissionSnapshotProvider.overrideWith(
              (ref) => YorksV1TestPermissionController(
                yorksV1TrustedFeaturePermissionState(),
              ),
            ),
            yorksV1MaterialRequestDetailProvider(
              'request-1',
            ).overrideWith((ref) async => _request),
            canManageCommercialsProvider.overrideWithValue(true),
            canViewCommercialsProvider.overrideWithValue(true),
            yorksV1ArrangementRepositoryProvider.overrideWithValue(
              _ArrangementRepository(),
            ),
            yorksV1LogisticsRepositoryProvider.overrideWithValue(inventory),
            yorksV1ArrangementWorkspaceProvider(
              'request-1',
            ).overrideWith((ref) async => _workingWorkspace),
            yorksV1ArrangementInventoryProvider.overrideWith(
              (ref) async => _inventoryItems,
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: YorksV1ArrangementScreen(
              requestId: 'request-1',
              embedded: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          const ValueKey('arrangement-create-inventory-arrangement-line-1'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('arrangement-new-inventory-description')),
        findsOneWidget,
      );

      final category = find.byKey(
        const ValueKey('arrangement-new-inventory-category'),
      );
      await tester.tap(category);
      await tester.enterText(category, 'Custom dampers');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create as a new parent category'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('arrangement-create-inventory-confirm')),
      );
      await tester.pumpAndSettle();

      expect(inventory.createInput, isNotNull);
      expect(inventory.createInput!.createsItem, isTrue);
      expect(inventory.createInput!.unit, 'Nos');
      expect(inventory.createInput!.newCategoryName, 'Custom Dampers');
      expect(inventory.createInput!.quantityDelta, '0');
      expect(find.text('Inventory item created'), findsOneWidget);
      expect(
        find.text(
          'The new item has no available stock. Receive physical stock before using it from Warehouse, or choose External supplier.',
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Procurement may leave category empty during catalogue reconciliation',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final preferences = await SharedPreferences.getInstance();
      final inventory = _ArrangementCreationInventoryRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1AuthUserIdProvider.overrideWithValue(
              'procurement-test-user',
            ),
            yorksV1ProcurementProgressRepositoryProvider.overrideWithValue(
              FakeRepository(),
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1CurrentPermissionSnapshotProvider.overrideWith(
              (ref) => YorksV1TestPermissionController(
                yorksV1TrustedFeaturePermissionState(),
              ),
            ),
            yorksV1MaterialRequestDetailProvider(
              'request-1',
            ).overrideWith((ref) async => _request),
            yorksV1ArrangementRepositoryProvider.overrideWithValue(
              _ArrangementRepository(),
            ),
            yorksV1LogisticsRepositoryProvider.overrideWithValue(inventory),
            yorksV1ArrangementWorkspaceProvider(
              'request-1',
            ).overrideWith((ref) async => _workingWorkspace),
            yorksV1ArrangementInventoryProvider.overrideWith(
              (ref) async => _inventoryItems,
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: YorksV1ArrangementScreen(
              requestId: 'request-1',
              embedded: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          const ValueKey('arrangement-create-inventory-arrangement-line-1'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('arrangement-create-inventory-confirm')),
      );
      await tester.pumpAndSettle();

      expect(inventory.createInput, isNotNull);
      expect(inventory.createInput!.categoryId, isNull);
      expect(inventory.createInput!.newCategoryName, isNull);
      expect(inventory.createInput!.quantityDelta, '0');
      expect(find.text('Inventory item created'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mobile arrangement line keeps warehouse search usable at 360px',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final preferences = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1AuthUserIdProvider.overrideWithValue(
              'procurement-test-user',
            ),
            yorksV1ProcurementProgressRepositoryProvider.overrideWithValue(
              FakeRepository(),
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1CurrentPermissionSnapshotProvider.overrideWith(
              (ref) => YorksV1TestPermissionController(
                yorksV1TrustedFeaturePermissionState(),
              ),
            ),
            yorksV1MaterialRequestDetailProvider(
              'request-1',
            ).overrideWith((ref) async => _request),
            canManageCommercialsProvider.overrideWithValue(true),
            canViewCommercialsProvider.overrideWithValue(true),
            yorksV1ArrangementRepositoryProvider.overrideWithValue(
              _ArrangementRepository(),
            ),
            yorksV1ArrangementWorkspaceProvider(
              'request-1',
            ).overrideWith((ref) async => _workingWorkspace),
            yorksV1ArrangementInventoryProvider.overrideWith(
              (ref) async => _inventoryItems,
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: YorksV1ArrangementScreen(requestId: 'request-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Motorized smoke damper'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('warehouse-search-arrangement-line-1')),
        findsOneWidget,
      );
      expect(find.text('Create inventory item'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/r35/arrange_material_request_mobile_line.png',
        ),
      );
    },
  );
}

const _inventoryItems = [
  YorksV1InventoryItem(
    id: 'inventory-1',
    itemCode: 'MSD-600',
    locationBin: 'Rack B / Shelf 3',
    description: 'Motorized smoke damper',
    unit: 'Nos',
    onHandQuantity: '12',
    reservedQuantity: '0',
    availableQuantity: '12',
    recordVersion: 1,
  ),
  YorksV1InventoryItem(
    id: 'inventory-2',
    itemCode: 'MSD-ALT',
    description: 'Motorized smoke damper alternate',
    unit: 'Nos',
    onHandQuantity: '20',
    reservedQuantity: '0',
    availableQuantity: '20',
    recordVersion: 1,
  ),
];

final _request = YorksV1MaterialRequest(
  id: 'request-1',
  projectId: 'project-1',
  projectReference: 'YRA-313',
  projectName: 'Riyadh Substation',
  scopeId: 'scope-1',
  scopeName: 'Building A',
  state: YorksV1MaterialRequestState.arranging,
  recordVersion: 2,
  createdAt: DateTime.utc(2026, 8, 8),
  updatedAt: DateTime.utc(2026, 8, 8),
  timing: YorksV1MaterialRequestTiming.normal,
  requestNumber: 'YRAASDF12-MR101',
  title: 'Arrangement test request',
  requesterDisplayName: 'Project Engineer',
  requesterProjectRole: 'Project Engineer',
  lines: const [
    YorksV1MaterialRequestLine(
      id: 'request-line-1',
      displayOrder: 1,
      source: YorksV1MaterialRequestLineSource.custom,
      description: 'Motorized smoke damper',
      quantity: '11',
      unit: 'Nos',
    ),
  ],
);

final _workingWorkspace = YorksV1ArrangementWorkspace(
  requestId: 'request-1',
  requestNumber: 'YRAASDF12-MR101',
  requestState: 'arranging',
  requestRecordVersion: 2,
  canBegin: false,
  canSave: true,
  canClarify: true,
  canDecide: false,
  arrangements: [
    YorksV1ProcurementArrangement(
      id: 'arrangement-1',
      version: 1,
      status: YorksV1ArrangementStatus.working,
      isCurrent: true,
      recordVersion: 1,
      startedByDisplayName: 'Procurement User',
      startedAt: DateTime.utc(2026, 8, 8),
      lines: const [
        YorksV1ArrangementLine(
          id: 'arrangement-line-1',
          requestLineId: 'request-line-1',
          displayOrder: 1,
          description: 'Motorized smoke damper',
          requestedQuantity: '11.0000',
          unit: 'Nos',
          requestSourceKind: 'boq',
          sourceBoqGroupId: 'boq-group-1',
          sourceBoqRowId: 'boq-row-1',
          sourceBoqGroupName: 'Dampers & Fire Control',
          sourceScopeName: 'Building A',
          source: YorksV1ArrangementSource.warehouse,
          inventoryItemId: 'inventory-1',
          decision: YorksV1ArrangementDecision.full,
          arrangedQuantity: '11.0000',
          unitCost: '110.29',
        ),
      ],
    ),
  ],
);

final _externalSupplierWorkspace = YorksV1ArrangementWorkspace(
  requestId: 'request-1',
  requestNumber: 'YRAASDF12-MR102',
  requestState: 'arranging',
  requestRecordVersion: 2,
  canBegin: false,
  canSave: true,
  canClarify: true,
  canDecide: false,
  arrangements: [
    YorksV1ProcurementArrangement(
      id: 'arrangement-2',
      version: 1,
      status: YorksV1ArrangementStatus.working,
      isCurrent: true,
      recordVersion: 1,
      startedByDisplayName: 'Procurement User',
      startedAt: DateTime.utc(2026, 8, 12),
      lines: const [
        YorksV1ArrangementLine(
          id: 'arrangement-line-2',
          requestLineId: 'request-line-2',
          displayOrder: 1,
          description: 'Cable tray hanging clamp',
          requestedQuantity: '50.0000',
          unit: 'Nos',
          source: YorksV1ArrangementSource.externalSupplier,
          decision: YorksV1ArrangementDecision.full,
          arrangedQuantity: '50.0000',
        ),
      ],
    ),
  ],
);

final _pendingClarificationWorkspace = YorksV1ArrangementWorkspace(
  requestId: 'request-1',
  requestNumber: 'YRAASDF12-MR101',
  requestState: 'awaiting_request_approval',
  requestRecordVersion: 3,
  canBegin: false,
  canSave: false,
  canClarify: true,
  canDecide: false,
  clarificationReviewRequired: true,
  procurementClarificationRevision: 1,
  approvedProcurementClarificationRevision: 0,
  arrangements: _workingWorkspace.arrangements,
);

final _replacementWorkspace = YorksV1ArrangementWorkspace(
  requestId: 'request-1',
  requestNumber: 'YRAASDF12-MR103',
  requestState: 'arranging',
  requestRecordVersion: 4,
  canBegin: false,
  canSave: true,
  canClarify: true,
  canDecide: false,
  arrangements: [
    YorksV1ProcurementArrangement(
      id: 'arrangement-3',
      version: 2,
      status: YorksV1ArrangementStatus.working,
      isCurrent: false,
      recordVersion: 1,
      startedByDisplayName: 'Procurement User',
      startedAt: DateTime.utc(2026, 8, 13),
      lines: const [
        YorksV1ArrangementLine(
          id: 'arrangement-line-3',
          requestLineId: 'request-line-1',
          displayOrder: 1,
          description: 'Motorized smoke damper',
          requestedQuantity: '11',
          unit: 'Nos',
          source: YorksV1ArrangementSource.warehouse,
          inventoryItemId: 'inventory-1',
          decision: YorksV1ArrangementDecision.full,
          arrangedQuantity: '11',
        ),
      ],
    ),
    YorksV1ProcurementArrangement(
      id: 'arrangement-1',
      version: 1,
      status: YorksV1ArrangementStatus.returned,
      isCurrent: true,
      recordVersion: 2,
      startedByDisplayName: 'Procurement User',
      startedAt: DateTime.utc(2026, 8, 12),
      lines: const [
        YorksV1ArrangementLine(
          id: 'arrangement-line-1',
          requestLineId: 'request-line-1',
          displayOrder: 1,
          description: 'Motorized smoke damper',
          requestedQuantity: '11',
          unit: 'Nos',
          source: YorksV1ArrangementSource.warehouse,
          inventoryItemId: 'inventory-1',
          decision: YorksV1ArrangementDecision.full,
          arrangedQuantity: '11',
          reservationState: 'active',
          reservedQuantity: '11',
        ),
      ],
    ),
  ],
);

class _ArrangementRepository implements YorksV1ArrangementRepository {
  final List<YorksV1SaveArrangementInput> saveInputs = [];
  final List<YorksV1UpdateProcurementMaterialItemInput> clarificationInputs =
      [];
  bool failNextClarification = false;
  Completer<void>? pendingSave;

  @override
  Future<YorksV1ArrangementWorkspace> begin(
    YorksV1BeginArrangementInput input,
  ) async => _workingWorkspace;

  @override
  Future<YorksV1ArrangementWorkspace> decide(
    YorksV1DecideArrangementInput input,
  ) async => _workingWorkspace;

  @override
  Future<YorksV1ArrangementWorkspace> getWorkspace(String requestId) async =>
      _workingWorkspace;

  @override
  Future<List<YorksV1InventoryItem>> listInventoryItems() async => const [
    YorksV1InventoryItem(
      id: 'inventory-1',
      itemCode: 'MSD-600',
      description: 'Motorized smoke damper',
      unit: 'Nos',
      onHandQuantity: '12',
      reservedQuantity: '0',
      availableQuantity: '12',
      recordVersion: 1,
    ),
  ];

  @override
  Future<YorksV1ArrangementWorkspace> save(
    YorksV1SaveArrangementInput input,
  ) async {
    saveInputs.add(input);
    await pendingSave?.future;
    return _workingWorkspace;
  }

  @override
  Future<YorksV1ArrangementWorkspace> updateProcurementItem(
    YorksV1UpdateProcurementMaterialItemInput input,
  ) async {
    clarificationInputs.add(input);
    if (failNextClarification) {
      failNextClarification = false;
      throw StateError('simulated clarification failure');
    }
    return _workingWorkspace;
  }
}

class _ArrangementCreationInventoryRepository
    implements YorksV1LogisticsRepository {
  YorksV1InventoryAdjustmentInput? createInput;

  @override
  Future<List<YorksV1ProjectMaterialMovement>> getProjectMaterialMovements(
    String projectId,
  ) async => const [];

  @override
  Future<YorksV1InventoryWorkspace> getInventory({String? search}) async =>
      YorksV1InventoryWorkspace(
        items: const [],
        categories: [
          YorksV1InventoryCategory(
            id: 'category-1',
            name: 'Dampers & Fire Control',
            isSystem: true,
            isActive: true,
            recordVersion: 1,
            itemCount: 2,
            aliases: const [],
            createdByDisplayName: 'System',
            createdAt: DateTime.utc(2026, 8, 10),
          ),
        ],
      );

  @override
  Future<YorksV1LogisticsInventoryItem> adjustInventory(
    YorksV1InventoryAdjustmentInput input,
  ) async {
    createInput = input;
    return YorksV1LogisticsInventoryItem(
      id: 'created-item-1',
      itemCode: 'INV-001',
      description: input.description ?? '',
      unit: input.unit ?? 'Nos',
      isActive: true,
      onHandQuantity: '0',
      reservedQuantity: '0',
      availableQuantity: '0',
      recordVersion: 1,
    );
  }

  @override
  Future<YorksV1InventoryItemDetail> getInventoryItem(String inventoryItemId) =>
      throw UnimplementedError();

  @override
  Future<YorksV1InventoryCategory> createInventoryCategory(
    YorksV1InventoryCategoryCreationInput input,
  ) => throw UnimplementedError();

  @override
  Future<YorksV1InventoryImportResult> importInventory(
    YorksV1InventoryImportInput input,
  ) => throw UnimplementedError();

  @override
  Future<YorksV1LogisticsInventoryItem> setInventoryItemActive(
    YorksV1InventoryItemStateInput input,
  ) => throw UnimplementedError();

  @override
  Future<YorksV1LogisticsWorkspace> getWorkspace(String requestId) =>
      throw UnimplementedError();

  @override
  Future<YorksV1LogisticsWorkspace> dispatch(YorksV1DispatchInput input) =>
      throw UnimplementedError();

  @override
  Future<YorksV1LogisticsWorkspace> confirmReceipt(
    YorksV1ReceiptConfirmationInput input,
  ) => throw UnimplementedError();

  @override
  Future<YorksV1ReturnsDocumentsWorkspace> getReturnsDocumentsWorkspace(
    String requestId,
  ) => throw UnimplementedError();

  @override
  Future<YorksV1ReturnsDocumentsWorkspace> generateDeliveryOrder(
    YorksV1DeliveryOrderGenerationInput input,
  ) => throw UnimplementedError();

  @override
  Future<YorksV1ReturnsDocumentsWorkspace> saveMaterialReturnDraft(
    YorksV1MaterialReturnDraftInput input,
  ) => throw UnimplementedError();

  @override
  Future<YorksV1ReturnsDocumentsWorkspace> submitMaterialReturn(
    YorksV1MaterialReturnSubmissionInput input,
  ) => throw UnimplementedError();

  @override
  Future<YorksV1ReturnsDocumentsWorkspace> confirmMaterialReturn(
    YorksV1MaterialReturnConfirmationInput input,
  ) => throw UnimplementedError();

  @override
  Future<YorksV1ReturnsDocumentsWorkspace> rejectMaterialReturn(
    YorksV1MaterialReturnRejectionInput input,
  ) => throw UnimplementedError();
}

Future<void> _tapReviewAndSave(WidgetTester tester, Finder review) async {
  if (review.evaluate().isEmpty) return;
  await tester.tap(review.first);
  await tester.pumpAndSettle();
  final save = find.widgetWithText(FilledButton, 'Save arrangement');
  if (save.evaluate().isNotEmpty) {
    await tester.tap(save);
    await tester.pump();
  }
}

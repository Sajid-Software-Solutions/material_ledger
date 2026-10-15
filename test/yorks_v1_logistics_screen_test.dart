import 'dart:io';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:flutter/services.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/shared/models/yorks_v1_inventory_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/materials/presentation/screens/yorks_v1_inventory_screen.dart';
import 'package:material_ledger/features/materials/presentation/screens/yorks_v1_logistics_screen.dart';
import 'package:material_ledger/features/materials/presentation/screens/yorks_v1_returns_documents_screen.dart';
import 'package:material_ledger/shared/models/yorks_v1_logistics.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_configuration_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_logistics_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_logistics_repository_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_material_request_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_logistics_repository.dart';
import 'package:material_ledger/shared/services/yorks_v1_logistics_document_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_ledger/shared/providers/yorks_v1_procurement_progress_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_procurement_progress_repository.dart';

import 'support/yorks_v1_permission_test_support.dart';

void main() {
  setUpAll(_loadDispatchFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in [const Size(1366, 800), const Size(360, 800)]) {
    testWidgets(
      'lost dispatch response confirms exact receipt at ${size.width}',
      (tester) async {
        final preferences = await SharedPreferences.getInstance();
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = _FakeLogisticsRepository()
          ..dispatchErrorAfterCommit = const YorksV1DomainException(
            YorksV1DomainErrorCode.backendUnavailable,
          );
        final progress = _FakeProgressRepository()
          ..resolvedOutcome = const YorksV1ProcurementCommandOutcome(
            status: 'confirmed',
            effectId: 'dispatch-exact-42',
            effectReference: 'DN-EXACT-42',
            committedVersion: 6,
          );
        await tester.pumpWidget(
          _testApp(
            preferences: preferences,
            repository: repository,
            progressRepository: progress,
            request: _informationRequest,
            useAppTheme: true,
            child: const YorksV1LogisticsScreen(requestId: 'request-1'),
          ),
        );
        await tester.pumpAndSettle();
        final quantity = find.byKey(
          const ValueKey('dispatch-quantity-request-line-1'),
        );
        if (quantity.evaluate().isNotEmpty) {
          await tester.enterText(quantity, '2');
        } else {
          await tester.enterText(find.byType(TextField).last, '2');
        }
        await tester.ensureVisible(find.text('Review dispatch').last);
        await tester.tap(find.text('Review dispatch').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('confirm-dispatch')));
        await tester.pumpAndSettle();
        expect(repository.dispatchCalls, 1);
        expect(progress.outcomeCalls, 1);
        expect(find.text('Dispatch confirmed — DN-EXACT-42.'), findsWidgets);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/r35/procurement_dispatch_reconciled_${size.width.toInt()}.png',
          ),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('logistics editor remains usable at a 360px mobile width', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _testApp(
        preferences: preferences,
        child: const YorksV1LogisticsScreen(requestId: 'request-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Review dispatch'), findsWidgets);
    expect(find.text('VAV Damper'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'negative dispatch quantity is shown on the row and cannot be reviewed',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      await tester.binding.setSurfaceSize(const Size(1366, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _FakeLogisticsRepository();
      await tester.pumpWidget(
        _testApp(
          preferences: preferences,
          repository: repository,
          child: const YorksV1LogisticsScreen(requestId: 'request-1'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'DN-NEGATIVE');
      await tester.enterText(find.byType(TextField).last, '-1');
      await tester.tap(find.text('Review dispatch'));
      await tester.pumpAndSettle();
      expect(find.text('Enter zero or a positive quantity.'), findsOneWidget);
      expect(find.byKey(const ValueKey('confirm-dispatch')), findsNothing);
      expect(repository._dispatchCommitted, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('saved dispatch preparation resumes without moving stock', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(1366, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeLogisticsRepository();
    final progress = _FakeProgressRepository();
    Widget app() => _testApp(
      preferences: preferences,
      repository: repository,
      progressRepository: progress,
      child: const YorksV1LogisticsScreen(requestId: 'request-1'),
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'DN-PREPARED');
    await tester.enterText(find.byType(TextField).last, '1.');
    await tester.tap(find.text('Save progress').last);
    await tester.pumpAndSettle();
    expect(repository._dispatchCommitted, isFalse);
    expect(find.text('Progress saved to your account'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('DN-PREPARED'), findsOneWidget);
    expect(find.text('1.'), findsOneWidget);
    expect(repository._dispatchCommitted, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'request information is available in dispatch and returns workspaces',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final child in <Widget>[
        const YorksV1LogisticsScreen(requestId: 'request-1'),
        const YorksV1ReturnsDocumentsScreen(requestId: 'request-1'),
      ]) {
        await tester.pumpWidget(
          _testApp(
            preferences: preferences,
            request: _informationRequest,
            child: child,
          ),
        );
        await tester.pumpAndSettle();

        final action = find.byKey(
          const ValueKey('material-request-information-action'),
        );
        expect(action, findsOneWidget);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(find.text('Y-001-MR001'), findsWidgets);
        expect(find.text('Yorks Project'), findsWidgets);
        await tester.tap(find.byIcon(Icons.close_rounded).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'dispatch history uses a spreadsheet table on desktop and cards on phone',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        _testApp(
          preferences: preferences,
          child: const YorksV1LogisticsScreen(requestId: 'receipt-focus'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('dispatch-lines-table')),
        findsOneWidget,
      );
      expect(find.text('Focus damper'), findsOneWidget);
      expect(find.text('Print Material Request'), findsOneWidget);
      expect(find.text('Print Delivery Report'), findsOneWidget);
      expect(find.text('Receipt review'), findsWidgets);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(YorksV1LogisticsScreen),
        matchesGoldenFile('goldens/r35/dispatch_detail_register_1366x900.png'),
      );

      tester.view.physicalSize = const Size(360, 800);
      await tester.pumpWidget(
        _testApp(
          preferences: preferences,
          child: const YorksV1LogisticsScreen(requestId: 'receipt-focus'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('dispatch-lines-table')), findsNothing);
      expect(find.text('Focus damper'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dispatch needs no supplier reference and refreshes Delivery Order before receipt review',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      final repository = _FakeLogisticsRepository();
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _testApp(
          preferences: preferences,
          repository: repository,
          child: const _DispatchDeliveryOrderRefreshHarness(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Delivery Order pending'), findsOneWidget);
      expect(repository.returnsWorkspaceCalls, 1);

      expect(
        find.text('Supplier delivery reference (optional)'),
        findsOneWidget,
      );
      final dispatchButton = find.text('Review dispatch').last;
      await tester.ensureVisible(dispatchButton);
      await tester.tap(dispatchButton);
      await tester.pumpAndSettle();
      expect(repository._dispatchCommitted, isFalse);
      await tester.tap(find.byKey(const ValueKey('confirm-dispatch')));
      await tester.pumpAndSettle();

      expect(find.text('Delivery Order ready'), findsOneWidget);
      expect(repository.returnsWorkspaceCalls, greaterThanOrEqualTo(2));
      expect(find.text('Dispatch committed'), findsOneWidget);
      expect(
        repository.lastDispatchInput?.toRpcPayload()['delivery_reference'],
        isNull,
      );
      expect(
        find.textContaining('Y-001-DSP001 · 1 line committed'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 6));
    },
  );

  testWidgets('inventory detail renders the protected movement ledger', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(1366, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _testApp(preferences: preferences, child: const YorksV1InventoryScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Items'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('VAV Damper'));
    await tester.pumpAndSettle();

    expect(find.text('Stock Movements'), findsWidgets);
    expect(find.text('Opening balance'), findsOneWidget);
  });

  testWidgets(
    'Senior Mechanical Engineer inventory workspace is visibly read-only',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      await tester.binding.setSurfaceSize(const Size(1366, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _testApp(
          preferences: preferences,
          exactRole: YorksV1Role.seniorMechanicalEngineer,
          child: const YorksV1InventoryScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add / Receive Stock'), findsNothing);
      expect(find.text('Import Inventory'), findsNothing);
      expect(find.text('Export stock'), findsOneWidget);

      await tester.tap(find.text('Items'));
      await tester.pumpAndSettle();
      expect(find.text('Stock'), findsNothing);
      await tester.tap(find.textContaining('VAV Damper'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Details'), findsNothing);
      expect(find.text('Receive / Adjust'), findsNothing);
      expect(find.text('Close'), findsOneWidget);
    },
  );

  testWidgets('inventory detail edits metadata through its separate command', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final repository = _FakeLogisticsRepository();
    await tester.binding.setSurfaceSize(const Size(1366, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _testApp(
        preferences: preferences,
        repository: repository,
        child: const YorksV1InventoryScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Items'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('VAV Damper'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit Details'));
    await tester.pumpAndSettle();
    final descriptionField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.controller?.text == 'VAV Damper',
      description: 'the inventory item description field',
    );
    await tester.enterText(descriptionField, 'VAV Damper revised');
    await tester.tap(find.text('Save Item Details'));
    await tester.pumpAndSettle();

    expect(repository.metadataInput, isNotNull);
    expect(repository.metadataInput!.description, 'VAV Damper revised');
    expect(
      repository.metadataInput!.toRpcPayload().containsKey('quantity'),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('return quantity uses a focused editor on a 360px mobile width', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _testApp(
        preferences: preferences,
        child: const YorksV1ReturnsDocumentsScreen(requestId: 'request-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Copper pipe'), findsOneWidget);
    await tester.tap(find.text('Copper pipe'));
    await tester.pumpAndSettle();

    expect(find.text('Return quantity'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
  });

  testWidgets(
    'stale focused receipt route fails closed without opening another dispatch',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _testApp(
          preferences: preferences,
          child: const YorksV1LogisticsScreen(
            requestId: 'receipt-focus',
            focusReceiptReview: true,
            // A stale deep link must never silently select a different
            // committed dispatch.
            focusedDispatchId: 'stale-dispatch',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('This record changed. Refresh it before trying again.'),
        findsOneWidget,
      );
      expect(find.text('Review delivered materials'), findsNothing);
      await tester.pump(const Duration(seconds: 6));
    },
  );

  testWidgets(
    'server-confirmed receipt reports line and exception counts before closing',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      final repository = _FakeLogisticsRepository();

      await tester.pumpWidget(
        _testApp(
          preferences: preferences,
          repository: repository,
          exactRole: YorksV1Role.projectEngineer,
          child: const YorksV1LogisticsScreen(
            requestId: 'receipt-focus',
            focusReceiptReview: true,
            focusedDispatchId: 'dispatch-focus',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Save receipt review'), findsOneWidget);
      await tester.tap(find.text('All dispatch lines have been reviewed.'));
      await tester.pump();
      await tester.tap(find.text('Save receipt review'));
      await tester.pumpAndSettle();

      expect(find.text('Receipt confirmed'), findsOneWidget);
      expect(
        find.text('1 line confirmed · 0 exceptions recorded.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 6));
    },
  );

  testWidgets(
    'stale focused Delivery Order route fails closed without another dispatch',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _testApp(
          preferences: preferences,
          child: const YorksV1ReturnsDocumentsScreen(
            requestId: 'delivery-focus',
            focusDeliveryOrder: true,
            // Likewise, a stale focus must not open a different committed
            // dispatch's controlled document.
            focusedDispatchId: 'stale-dispatch',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('This record changed. Refresh it before trying again.'),
        findsOneWidget,
      );
      expect(find.text('Delivery Order reference'), findsNothing);
      expect(find.text('Material returns'), findsNothing);
      await tester.pump(const Duration(seconds: 6));
    },
  );

  testWidgets(
    'document revision selection prints the selected immutable snapshot',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final documents = _SelectedRevisionDocuments();
      final workspace = _revisionChoiceWorkspace;
      await tester.pumpWidget(
        _testApp(
          preferences: preferences,
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showYorksV1DeliveryOrderGenerationDialog(
                  context,
                  workspace: workspace,
                  dispatch: workspace.deliveryOrderDispatches.single,
                  documents: documents,
                  canGenerate: false,
                ),
                child: const Text('Open revision preview'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open revision preview'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Delivery report'), findsWidgets);
      await tester.tap(find.text('Print / PDF'));
      await tester.pumpAndSettle();
      expect(documents.printed, ['received-revision']);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Delivery note').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Print / PDF'));
      await tester.pumpAndSettle();
      expect(documents.printed, ['received-revision', 'original-revision']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Delivery Order output retry reuses the server-confirmed revision',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      final repository = _DeliveryOrderRetryRepository();
      final documents = _LostOutputDocuments();
      final initial = _postDispatchDeliveryWorkspace('delivery-output-retry');
      final dispatch = initial.deliveryOrderDispatches.single;

      await tester.pumpWidget(
        _testApp(
          preferences: preferences,
          repository: repository,
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showYorksV1DeliveryOrderGenerationDialog(
                    context,
                    workspace: initial,
                    dispatch: dispatch,
                    documents: documents,
                    canGenerate: true,
                  ),
                  child: const Text('Open Delivery Order'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open Delivery Order'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(
        find.text('Delivery number assigned automatically'),
        findsOneWidget,
      );

      await tester.tap(find.text('Download PDF'));
      await tester.pumpAndSettle();
      expect(repository.generationCalls, 1);
      expect(documents.shareAttempts, 1);
      expect(find.text('DO-RETRY-001'), findsOneWidget);
      expect(repository.lastInput?.deliveryOrderReference, isEmpty);
      await tester.pump(const Duration(seconds: 6));

      await tester.tap(find.text('Download PDF'));
      await tester.pumpAndSettle();
      expect(repository.generationCalls, 1);
      expect(documents.shareAttempts, 2);
      expect(find.text('Delivery number assigned automatically'), findsNothing);
    },
  );
  testWidgets('a new Delivery Order revision keeps its confirmed number', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final repository = _DeliveryOrderRetryRepository();
    final documents = _SelectedRevisionDocuments();
    final workspace = _confirmedDeliveryOrderWorkspace('delivery-revision');
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      _testApp(
        preferences: preferences,
        repository: repository,
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showYorksV1DeliveryOrderGenerationDialog(
                context,
                workspace: workspace,
                dispatch: workspace.deliveryOrderDispatches.single,
                documents: documents,
                canGenerate: true,
              ),
              child: const Text('Open revision'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open revision'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create new revision'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('DO-RETRY-001'), findsOneWidget);
    await tester.tap(find.text('Print / PDF'));
    await tester.pumpAndSettle();
    expect(repository.lastInput?.deliveryOrderReference, 'DO-RETRY-001');
    expect(repository.generationCalls, 1);
    expect(documents.printed, ['revision-1']);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(1366, 900), const Size(360, 800)]) {
    testWidgets('automatic delivery number ${size.width.toInt()} visual', (
      tester,
    ) async {
      final preferences = await SharedPreferences.getInstance();
      final workspace = _postDispatchDeliveryWorkspace('delivery-auto');
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        _testApp(
          preferences: preferences,
          useAppTheme: true,
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showYorksV1DeliveryOrderGenerationDialog(
                  context,
                  workspace: workspace,
                  dispatch: workspace.deliveryOrderDispatches.single,
                  documents: _SelectedRevisionDocuments(),
                  canGenerate: true,
                ),
                child: const Text('Open delivery'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open delivery'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(
        find.text('Delivery number assigned automatically'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/r35/procurement_automatic_delivery_${size.width.toInt()}.png',
        ),
      );
    });
  }
  for (final size in [const Size(1366, 900), const Size(360, 800)]) {
    testWidgets('dispatch preparation workspace ${size.width.toInt()} visual', (
      tester,
    ) async {
      final preferences = await SharedPreferences.getInstance();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        _testApp(
          preferences: preferences,
          useAppTheme: true,
          child: YorksV1LogisticsScreen(
            requestId: 'request-1',
            initialDispatchDate: DateTime(2026, 10, 8),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(YorksV1LogisticsScreen),
        matchesGoldenFile(
          'goldens/r35/procurement_dispatch_${size.width.toInt()}.png',
        ),
      );
    });
  }
}

Widget _testApp({
  required SharedPreferences preferences,
  required Widget child,
  YorksV1LogisticsRepository? repository,
  YorksV1Role exactRole = YorksV1Role.procurement,
  YorksV1MaterialRequest? request,
  _FakeProgressRepository? progressRepository,
  bool useAppTheme = false,
}) => ProviderScope(
  overrides: [
    yorksV1AuthUserIdProvider.overrideWithValue('procurement-test'),
    yorksV1ProcurementProgressRepositoryProvider.overrideWithValue(
      progressRepository ?? _FakeProgressRepository(),
    ),
    yorksV1CurrentRoleProvider.overrideWithValue(exactRole),
    yorksV1CurrentPermissionSnapshotProvider.overrideWith(
      (ref) => YorksV1TestPermissionController(
        yorksV1TrustedFeaturePermissionState(role: exactRole),
      ),
    ),
    sharedPreferencesProvider.overrideWithValue(preferences),
    yorksV1ConfigurationUnitCodesProvider.overrideWith(
      (ref) async => const ['Nos', 'Meter', 'Set', 'Kg', 'Ton', 'Boxes'],
    ),
    yorksV1LogisticsRepositoryProvider.overrideWithValue(
      repository ?? _FakeLogisticsRepository(),
    ),
    if (request != null)
      yorksV1MaterialRequestDetailProvider(
        request.id,
      ).overrideWith((ref) async => request),
  ],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: useAppTheme ? AppTheme.light : null,
    home: child,
  ),
);

final _informationRequest = YorksV1MaterialRequest(
  id: 'request-1',
  projectId: 'project-1',
  projectReference: 'Y-001',
  projectName: 'Yorks Project',
  scopeId: 'scope-building-a',
  scopeName: 'Building A',
  state: YorksV1MaterialRequestState.approved,
  recordVersion: 1,
  createdAt: DateTime.utc(2026, 8, 10),
  updatedAt: DateTime.utc(2026, 8, 10),
  timing: YorksV1MaterialRequestTiming.normal,
  requestNumber: 'Y-001-MR001',
  requesterDisplayName: 'Project Engineer',
  requesterProjectRole: 'project_engineer',
  currentActionOwnerRole: 'procurement',
  lines: const [],
);

class _DispatchDeliveryOrderRefreshHarness extends ConsumerWidget {
  const _DispatchDeliveryOrderRefreshHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(
      yorksV1ReturnsDocumentsWorkspaceProvider('request-1'),
    );
    final deliveryOrderReady =
        workspace.valueOrNull?.deliveryOrderDispatches.any(
          (dispatch) => dispatch.canGenerate,
        ) ??
        false;
    return Scaffold(
      body: Column(
        children: [
          Text(
            deliveryOrderReady
                ? 'Delivery Order ready'
                : 'Delivery Order pending',
          ),
          Expanded(child: YorksV1LogisticsScreen(requestId: 'request-1')),
        ],
      ),
    );
  }
}

class _FakeProgressRepository implements YorksV1ProcurementProgressRepository {
  YorksV1ProcurementCommandOutcome? resolvedOutcome;
  int outcomeCalls = 0;
  YorksV1ProcurementProgressRead read = const YorksV1ProcurementProgressRead();
  @override
  Future<YorksV1ProcurementProgressRead> get(
    YorksV1ProcurementProgressScope scope,
  ) async => read;
  @override
  Future<YorksV1ProcurementProgressCheckpoint> save({
    required YorksV1ProcurementProgressDraft draft,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    final checkpoint = YorksV1ProcurementProgressCheckpoint(
      draft: draft,
      revision: expectedRevision + 1,
      savedAt: DateTime.utc(2026, 10, 8),
    );
    read = YorksV1ProcurementProgressRead(
      checkpoint: checkpoint,
      revision: checkpoint.revision,
    );
    return checkpoint;
  }

  @override
  Future<int> discard({
    required YorksV1ProcurementProgressScope scope,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    read = YorksV1ProcurementProgressRead(
      revision: expectedRevision + 1,
      discarded: true,
    );
    return read.revision;
  }

  @override
  Future<YorksV1ProcurementPendingCommand> prepare({
    required YorksV1ProcurementProgressScope scope,
    required int checkpointRevision,
    required String commandName,
    required String commandKey,
    required Map<String, Object?> commandPayload,
    required String idempotencyKey,
  }) async => YorksV1ProcurementPendingCommand(
    attemptId: 'attempt',
    commandName: commandName,
    commandKey: commandKey,
  );
  @override
  Future<YorksV1ProcurementCommandOutcome> outcome({
    required String requestId,
    required String commandName,
    required String commandKey,
    bool automatic = false,
  }) async {
    outcomeCalls++;
    return resolvedOutcome ??
        const YorksV1ProcurementCommandOutcome(status: 'not_found');
  }

  @override
  Future<String> abandon({
    required String requestId,
    required String commandName,
    required String commandKey,
  }) async => 'abandoned';
}

class _FakeLogisticsRepository
    implements
        YorksV1LogisticsRepository,
        YorksV1InventoryItemMetadataRepository,
        YorksV1InventoryHistoryRepository {
  @override
  Future<YorksV1InventoryHistoryPage> getInventoryHistory(
    YorksV1InventoryHistoryQuery query,
  ) async => YorksV1InventoryHistoryPage(
    items: (await getInventoryItem(query.itemId ?? 'item')).movements,
    hasMore: false,
  );

  YorksV1InventoryItemMetadataInput? metadataInput;
  bool _dispatchCommitted = false;
  Object? dispatchErrorAfterCommit;
  int dispatchCalls = 0;
  YorksV1DispatchInput? lastDispatchInput;
  int returnsWorkspaceCalls = 0;

  @override
  Future<List<YorksV1ProjectMaterialMovement>> getProjectMaterialMovements(
    String projectId,
  ) async => const [];

  @override
  Future<YorksV1InventoryWorkspace> getInventory({String? search}) async =>
      YorksV1InventoryWorkspace(
        items: [_item],
        categories: [
          YorksV1InventoryCategory(
            id: 'category-1',
            name: 'Dampers & Fire Control',
            isSystem: true,
            isActive: true,
            recordVersion: 1,
            itemCount: 1,
            aliases: [],
            createdByDisplayName: 'System',
            createdAt: DateTime.utc(2026, 8, 10),
          ),
        ],
      );

  @override
  Future<YorksV1InventoryItemDetail> getInventoryItem(
    String inventoryItemId,
  ) async => YorksV1InventoryItemDetail(
    item: _item,
    movements: [
      YorksV1InventoryMovement(
        id: 'movement-1',
        movementType: 'opening_balance',
        quantityDelta: '5',
        onHandAfterQuantity: '5',
        reason: 'Opening balance',
        actorDisplayName: 'Procurement User',
        createdAt: DateTime.utc(2026, 8, 2),
      ),
    ],
  );

  @override
  Future<YorksV1LogisticsInventoryItem> adjustInventory(
    YorksV1InventoryAdjustmentInput input,
  ) async => _item;

  @override
  Future<YorksV1LogisticsInventoryItem> updateInventoryItemMetadata(
    YorksV1InventoryItemMetadataInput input,
  ) async {
    metadataInput = input;
    return _item;
  }

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
  ) async => _item;

  @override
  Future<YorksV1LogisticsWorkspace> getWorkspace(String requestId) async {
    if (requestId == 'receipt-focus') return _receiptFocusWorkspace;
    if (_dispatchCommitted) return _postDispatchLogisticsWorkspace(requestId);
    return YorksV1LogisticsWorkspace(
      requestId: requestId,
      projectId: 'project-1',
      requestNumber: 'Y-001-MR001',
      requestState: 'approved',
      requestRecordVersion: 5,
      projectName: 'Yorks Project',
      scopeName: 'Building A',
      canDispatch: true,
      canConfirmReceipt: false,
      dispatchCandidates: const [
        YorksV1DispatchCandidate(
          requestLineId: 'request-line-1',
          displayOrder: 1,
          description: 'VAV Damper',
          unit: 'Nos',
          approvedQuantity: '4',
          goodReceivedQuantity: '0',
          inTransitQuantity: '0',
          stillNeededQuantity: '4',
          source: YorksV1LogisticsSource.warehouse,
          inventoryItemId: 'inventory-1',
          reservedRemainingQuantity: '4',
          warehouseAvailableQuantity: '4',
        ),
      ],
      dispatches: const [],
    );
  }

  @override
  Future<YorksV1LogisticsWorkspace> dispatch(YorksV1DispatchInput input) async {
    dispatchCalls++;
    _dispatchCommitted = true;
    lastDispatchInput = input;
    if (dispatchErrorAfterCommit != null) throw dispatchErrorAfterCommit!;
    return getWorkspace(input.requestId);
  }

  @override
  Future<YorksV1LogisticsWorkspace> confirmReceipt(
    YorksV1ReceiptConfirmationInput input,
  ) => getWorkspace(input.requestId);

  @override
  Future<YorksV1ReturnsDocumentsWorkspace> getReturnsDocumentsWorkspace(
    String requestId,
  ) async {
    returnsWorkspaceCalls++;
    if (requestId == 'delivery-focus') return _deliveryFocusWorkspace;
    if (requestId == 'receipt-focus') return _receiptFocusDocumentsWorkspace;
    return _dispatchCommitted
        ? _postDispatchDeliveryWorkspace(requestId)
        : _returnsWorkspace(requestId);
  }

  @override
  Future<YorksV1ReturnsDocumentsWorkspace> generateDeliveryOrder(
    YorksV1DeliveryOrderGenerationInput input,
  ) async => input.requestId == 'delivery-focus'
      ? _deliveryFocusWorkspace
      : _returnsWorkspace(input.requestId);

  @override
  Future<YorksV1ReturnsDocumentsWorkspace> saveMaterialReturnDraft(
    YorksV1MaterialReturnDraftInput input,
  ) async => _returnsWorkspace(input.requestId);

  @override
  Future<YorksV1ReturnsDocumentsWorkspace> submitMaterialReturn(
    YorksV1MaterialReturnSubmissionInput input,
  ) async => _returnsWorkspace('request-1');

  @override
  Future<YorksV1ReturnsDocumentsWorkspace> confirmMaterialReturn(
    YorksV1MaterialReturnConfirmationInput input,
  ) async => _returnsWorkspace('request-1');

  @override
  Future<YorksV1ReturnsDocumentsWorkspace> rejectMaterialReturn(
    YorksV1MaterialReturnRejectionInput input,
  ) async => _returnsWorkspace('request-1');
}

class _DeliveryOrderRetryRepository extends _FakeLogisticsRepository {
  int generationCalls = 0;
  YorksV1DeliveryOrderGenerationInput? lastInput;

  @override
  Future<YorksV1ReturnsDocumentsWorkspace> generateDeliveryOrder(
    YorksV1DeliveryOrderGenerationInput input,
  ) async {
    generationCalls++;
    lastInput = input;
    return _confirmedDeliveryOrderWorkspace(input.requestId);
  }
}

class _SelectedRevisionDocuments extends YorksV1LogisticsDocumentService {
  final printed = <String>[];
  @override
  Future<void> printDeliveryOrder({
    required YorksV1ReturnsDocumentsWorkspace workspace,
    required YorksV1DeliveryOrderDispatch dispatch,
    required YorksV1DeliveryOrderRevision revision,
  }) async {
    printed.add(revision.id);
  }
}

final _revisionChoiceWorkspace = YorksV1ReturnsDocumentsWorkspace(
  requestId: 'request-1',
  projectId: 'project-1',
  requestNumber: 'MR-001',
  requestState: 'partially_received',
  requestRecordVersion: 7,
  projectName: 'Yorks Project',
  projectReference: 'Y-001',
  scopeName: 'Building A',
  canGenerateDeliveryOrder: false,
  canSubmitMaterialReturn: false,
  canConfirmMaterialReturn: false,
  deliveryOrderDispatches: [
    YorksV1DeliveryOrderDispatch(
      dispatchId: 'dispatch',
      dispatchNumber: 'DSP-001',
      dispatchDate: DateTime.utc(2026, 10, 8),
      dispatchRecordVersion: 2,
      canGenerate: false,
      deliveryOrder: YorksV1DeliveryOrder(
        id: 'order',
        dispatchId: 'dispatch',
        reference: 'DO-001',
        recordVersion: 2,
        currentRevisionId: 'received-revision',
        revisions: [
          YorksV1DeliveryOrderRevision(
            id: 'received-revision',
            revisionNumber: 2,
            isCurrent: true,
            generatedAt: DateTime.utc(2026, 10, 8),
            generatedByDisplayName: 'Site Engineer',
            snapshotKind: YorksV1DeliveryOrderSnapshotKind.receiptReview,
            lines: const [
              YorksV1DeliveryOrderLine(
                serialNumber: 1,
                description: 'VAV Damper',
                quantity: '1',
                unit: 'Nos',
              ),
            ],
          ),
          YorksV1DeliveryOrderRevision(
            id: 'original-revision',
            revisionNumber: 1,
            isCurrent: false,
            generatedAt: DateTime.utc(2026, 10, 7),
            generatedByDisplayName: 'Procurement',
            lines: const [
              YorksV1DeliveryOrderLine(
                serialNumber: 1,
                description: 'VAV Damper',
                quantity: '4',
                unit: 'Nos',
              ),
            ],
          ),
        ],
      ),
    ),
  ],
  returnCandidates: const [],
  materialReturns: const [],
  returnInventoryItems: const [],
);

class _LostOutputDocuments extends YorksV1LogisticsDocumentService {
  int shareAttempts = 0;

  @override
  Future<void> shareDeliveryOrderPdf({
    required YorksV1ReturnsDocumentsWorkspace workspace,
    required YorksV1DeliveryOrderDispatch dispatch,
    required YorksV1DeliveryOrderRevision revision,
  }) async {
    shareAttempts++;
    if (shareAttempts == 1) {
      throw StateError('Local output channel unavailable.');
    }
  }
}

YorksV1ReturnsDocumentsWorkspace _returnsWorkspace(String requestId) =>
    YorksV1ReturnsDocumentsWorkspace(
      requestId: requestId,
      projectId: 'project-1',
      requestNumber: 'Y-001-MR001',
      requestState: 'received',
      requestRecordVersion: 1,
      projectName: 'Yorks Project',
      projectReference: 'Y-001',
      scopeName: 'Building A',
      canGenerateDeliveryOrder: false,
      canSubmitMaterialReturn: true,
      canConfirmMaterialReturn: false,
      deliveryOrderDispatches: const [],
      returnCandidates: const [
        YorksV1ReturnCandidate(
          receiptReviewLineId: 'receipt-line-1',
          dispatchNumber: 'Y-001-DSP001',
          displayOrder: 1,
          description: 'Copper pipe',
          unit: 'Mtr',
          source: YorksV1LogisticsSource.warehouse,
          goodReceivedQuantity: '3',
          confirmedReturnQuantity: '0',
          eligibleReturnQuantity: '3',
        ),
      ],
      materialReturns: const [],
      returnInventoryItems: const [],
    );

YorksV1LogisticsWorkspace _postDispatchLogisticsWorkspace(String requestId) =>
    YorksV1LogisticsWorkspace(
      requestId: requestId,
      projectId: 'project-1',
      requestNumber: 'Y-001-MR001',
      requestState: 'dispatched',
      requestRecordVersion: 6,
      projectName: 'Yorks Project',
      scopeName: 'Building A',
      canDispatch: false,
      canConfirmReceipt: true,
      dispatchCandidates: const [],
      dispatches: [
        YorksV1MaterialDispatch(
          id: 'dispatch-after-commit',
          number: 'Y-001-DSP001',
          dispatchDate: DateTime.utc(2026, 8, 10),
          state: YorksV1DispatchState.receiptPending,
          recordVersion: 1,
          dispatchedByDisplayName: 'Procurement User',
          dispatchedAt: DateTime.utc(2026, 8, 10),
          canConfirmReceipt: true,
          lines: const [],
        ),
      ],
    );

YorksV1ReturnsDocumentsWorkspace _postDispatchDeliveryWorkspace(
  String requestId,
) => YorksV1ReturnsDocumentsWorkspace(
  requestId: requestId,
  projectId: 'project-1',
  requestNumber: 'Y-001-MR001',
  requestState: 'dispatched',
  requestRecordVersion: 6,
  projectName: 'Yorks Project',
  projectReference: 'Y-001',
  scopeName: 'Building A',
  canGenerateDeliveryOrder: true,
  canSubmitMaterialReturn: false,
  canConfirmMaterialReturn: false,
  deliveryOrderDispatches: [
    YorksV1DeliveryOrderDispatch(
      dispatchId: 'dispatch-after-commit',
      dispatchNumber: 'Y-001-DSP001',
      dispatchDate: DateTime.utc(2026, 8, 10),
      dispatchRecordVersion: 1,
      canGenerate: true,
    ),
  ],
  returnCandidates: const [],
  materialReturns: const [],
  returnInventoryItems: const [],
);

YorksV1ReturnsDocumentsWorkspace _confirmedDeliveryOrderWorkspace(
  String requestId,
) => YorksV1ReturnsDocumentsWorkspace(
  requestId: requestId,
  projectId: 'project-1',
  requestNumber: 'Y-001-MR001',
  requestState: 'dispatched',
  requestRecordVersion: 6,
  projectName: 'Yorks Project',
  projectReference: 'Y-001',
  scopeName: 'Building A',
  canGenerateDeliveryOrder: true,
  canSubmitMaterialReturn: false,
  canConfirmMaterialReturn: false,
  deliveryOrderDispatches: [
    YorksV1DeliveryOrderDispatch(
      dispatchId: 'dispatch-after-commit',
      dispatchNumber: 'Y-001-DSP001',
      dispatchDate: DateTime.utc(2026, 8, 10),
      dispatchRecordVersion: 1,
      canGenerate: true,
      deliveryOrder: YorksV1DeliveryOrder(
        id: 'delivery-order-1',
        dispatchId: 'dispatch-after-commit',
        reference: 'DO-RETRY-001',
        recordVersion: 1,
        currentRevisionId: 'revision-1',
        revisions: [
          YorksV1DeliveryOrderRevision(
            id: 'revision-1',
            revisionNumber: 1,
            isCurrent: true,
            generatedAt: DateTime.utc(2026, 8, 10),
            generatedByDisplayName: 'Project Engineer',
            lines: const [
              YorksV1DeliveryOrderLine(
                serialNumber: 1,
                description: 'VAV Damper',
                quantity: '4',
                unit: 'Nos',
              ),
            ],
          ),
        ],
      ),
    ),
  ],
  returnCandidates: const [],
  materialReturns: const [],
  returnInventoryItems: const [],
);

const _item = YorksV1LogisticsInventoryItem(
  id: 'inventory-1',
  itemCode: 'VAV-001',
  description: 'VAV Damper',
  categoryId: 'category-1',
  categoryName: 'Dampers & Fire Control',
  brandOrigin: 'UAE',
  unit: 'Nos',
  isActive: true,
  onHandQuantity: '5',
  reservedQuantity: '1',
  availableQuantity: '4',
  recordVersion: 2,
  metadataRecordVersion: 1,
  movementCount: 1,
);

final _receiptFocusWorkspace = YorksV1LogisticsWorkspace(
  requestId: 'receipt-focus',
  projectId: 'project-1',
  requestNumber: 'Y-001-MR001',
  requestState: 'dispatched',
  requestRecordVersion: 5,
  projectName: 'Yorks Project',
  scopeName: 'Building A',
  canDispatch: false,
  canConfirmReceipt: true,
  dispatchCandidates: const [],
  dispatches: [
    YorksV1MaterialDispatch(
      id: 'dispatch-focus',
      number: 'Y-001-DSP001',
      dispatchDate: DateTime.utc(2026, 8, 5),
      state: YorksV1DispatchState.receiptPending,
      recordVersion: 3,
      dispatchedByDisplayName: 'Procurement User',
      dispatchedAt: DateTime.utc(2026, 8, 5),
      canConfirmReceipt: true,
      deliveryReference: 'DN-001',
      lines: const [
        YorksV1DispatchLine(
          id: 'dispatch-line-focus',
          requestLineId: 'request-line-focus',
          description: 'Focus damper',
          unit: 'Nos',
          source: YorksV1LogisticsSource.warehouse,
          dispatchedQuantity: '1',
          approvedQuantity: '1',
        ),
      ],
    ),
  ],
);

final _deliveryFocusWorkspace = YorksV1ReturnsDocumentsWorkspace(
  requestId: 'delivery-focus',
  projectId: 'project-1',
  requestNumber: 'Y-001-MR001',
  requestState: 'received',
  requestRecordVersion: 2,
  projectName: 'Yorks Project',
  projectReference: 'Y-001',
  scopeName: 'Building A',
  canGenerateDeliveryOrder: true,
  canSubmitMaterialReturn: false,
  canConfirmMaterialReturn: false,
  deliveryOrderDispatches: [
    YorksV1DeliveryOrderDispatch(
      dispatchId: 'dispatch-delivery',
      dispatchNumber: 'Y-001-DSP001',
      dispatchDate: DateTime.utc(2026, 8, 5),
      dispatchRecordVersion: 3,
      canGenerate: true,
      receiptReviewedAt: DateTime.utc(2026, 8, 5),
    ),
  ],
  returnCandidates: const [],
  materialReturns: const [],
  returnInventoryItems: const [],
);

final _receiptFocusDocumentsWorkspace = YorksV1ReturnsDocumentsWorkspace(
  requestId: 'receipt-focus',
  projectId: 'project-1',
  requestNumber: 'Y-001-MR001',
  requestState: 'dispatched',
  requestRecordVersion: 5,
  projectName: 'Yorks Project',
  projectReference: 'Y-001',
  scopeName: 'Building A',
  canGenerateDeliveryOrder: true,
  canSubmitMaterialReturn: false,
  canConfirmMaterialReturn: false,
  deliveryOrderDispatches: [
    YorksV1DeliveryOrderDispatch(
      dispatchId: 'dispatch-focus',
      dispatchNumber: 'Y-001-DSP001',
      dispatchDate: DateTime.utc(2026, 8, 5),
      dispatchRecordVersion: 3,
      canGenerate: true,
      receiptReviewedAt: DateTime.utc(2026, 8, 5),
      deliveryOrder: YorksV1DeliveryOrder(
        id: 'delivery-order-focus',
        dispatchId: 'dispatch-focus',
        reference: 'YRA/DN/001/2026',
        recordVersion: 1,
        currentRevisionId: 'delivery-revision-focus',
        revisions: [
          YorksV1DeliveryOrderRevision(
            id: 'delivery-revision-focus',
            revisionNumber: 1,
            isCurrent: true,
            generatedAt: DateTime.utc(2026, 8, 5),
            generatedByDisplayName: 'Project Engineer',
            snapshotKind: YorksV1DeliveryOrderSnapshotKind.receiptReview,
            lines: const [
              YorksV1DeliveryOrderLine(
                serialNumber: 1,
                description: 'Focus damper',
                quantity: '1',
                unit: 'Nos',
              ),
            ],
          ),
        ],
      ),
    ),
  ],
  returnCandidates: const [],
  materialReturns: const [],
  returnInventoryItems: const [],
);

Future<void> _loadDispatchFonts() async {
  final font = FontLoader('NexusSans')
    ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
  final arabic = FontLoader('NotoSansArabic')
    ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
  var directory = File(Platform.resolvedExecutable).parent;
  for (var level = 0; level < 8; level++) {
    if (directory.path.endsWith('${Platform.pathSeparator}cache')) break;
    directory = directory.parent;
  }
  final bytes = await File(
    '${directory.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ).readAsBytes();
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await Future.wait([font.load(), arabic.load(), icons.load()]);
}

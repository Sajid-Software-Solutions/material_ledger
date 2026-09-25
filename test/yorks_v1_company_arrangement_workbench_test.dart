import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/materials/presentation/screens/yorks_v1_company_arrangement_workbench.dart';
import 'package:material_ledger/features/materials/presentation/screens/yorks_v1_company_material_request_operations.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_arrangement.dart';
import 'package:material_ledger/shared/models/yorks_v1_company_material_request.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request.dart';

void main() {
  const person = YorksV1CompanyMaterialRequestPerson(
    authUserId: 'person',
    displayName: 'Engineer',
  );
  const request = YorksV1CompanyMaterialRequest(
    id: 'request',
    recordVersion: 3,
    state: 'approved_for_procurement',
    categoryName: 'Workshop',
    responsibleUnitName: 'Operations',
    purpose: 'Safety material',
    timing: YorksV1MaterialRequestTiming.normal,
    deliveryCollectionPoint: 'Office',
    beneficiary: person,
    authorizedReceiver: person,
    requesterDisplayName: 'Engineer',
    requesterExactRole: 'site_engineer',
    lines: [
      YorksV1CompanyMaterialRequestLine(
        id: 'line',
        displayOrder: 1,
        description: 'Workshop helmet',
        quantity: '3',
        withdrawableQuantity: '3',
        unit: 'pcs',
      ),
    ],
  );

  for (final width in [360.0, 390.0, 600.0, 768.0, 1024.0, 1366.0, 1920.0]) {
    testWidgets(
      'Company arrangement workbench saves external source at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, width <= 390 ? 800 : 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        List<CompanySupplyPlanChoice>? saved;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => YorksV1CompanyArrangementWorkbench(
                      request: request,
                      inventory: const <YorksV1InventoryItem>[],
                      language: AppLanguage.english,
                      onSave: (choices) async => saved = choices,
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            width <= 720 ? 'Arrange items' : 'Arrange Material Request',
          ),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('company-arrangement-save')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('company-arrangement-validation')),
          findsOneWidget,
        );
        expect(saved, isNull);

        if (width <= 720) {
          await tester.tap(
            find.byKey(const ValueKey('company-arrangement-mobile-line-line')),
          );
          await tester.pumpAndSettle();
        }

        await tester.tap(
          find.byKey(const ValueKey('company-arrangement-source-line')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('External supplier').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('company-arrangement-supplier-line')),
          'Supplier A',
        );
        if (width <= 720) {
          await tester.tap(find.text('Previous'));
          await tester.pumpAndSettle();
        }
        await tester.tap(
          find.byKey(const ValueKey('company-arrangement-save')),
        );
        await tester.pumpAndSettle();
        expect(saved, isNull);
        expect(find.text('Arrangement Summary'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('company-arrangement-save')),
        );
        await tester.pumpAndSettle();
        expect(saved, hasLength(1));
        expect(saved!.single.decision, 'full');
        expect(saved!.single.externalSupplier, 'Supplier A');
        expect(saved!.single.quantity, '3');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('stock search, dirty close, and failed save preserve the plan', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var attempts = 0;
    List<CompanySupplyPlanChoice>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => YorksV1CompanyArrangementWorkbench(
                  request: request,
                  inventory: const [
                    YorksV1InventoryItem(
                      id: 'stock',
                      itemCode: 'PPE-001',
                      description: 'Workshop helmet stock',
                      unit: 'pcs',
                      onHandQuantity: '8',
                      reservedQuantity: '0',
                      availableQuantity: '8',
                      recordVersion: 1,
                    ),
                  ],
                  language: AppLanguage.english,
                  onSave: (choices) async {
                    attempts++;
                    if (attempts == 1) throw StateError('temporary failure');
                    saved = choices;
                  },
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('company-arrangement-stock-line')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Workshop helmet stock').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();
    expect(find.textContaining('unsaved arrangement changes'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Arrange Material Request'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('company-arrangement-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('company-arrangement-save')));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(saved, isNull);
    expect(find.text('Arrange Material Request'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('company-arrangement-save')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(saved!.single.inventoryItemId, 'stock');
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/materials/presentation/widgets/yorks_v1_material_request_recovery_changes.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request.dart';

void main() {
  const line = YorksV1MaterialRequestLine(
    id: 'line',
    displayOrder: 1,
    source: YorksV1MaterialRequestLineSource.custom,
    description: 'Duct',
    quantity: '1',
    unit: 'Nos',
    model: 'Model B',
    size: '500 mm',
    equipmentTag: 'AHU-2',
    planningModelTag: 'Legacy B',
    brandOrigin: 'UAE',
    unitCost: '998877',
    totalCost: '998877',
    currencyCode: 'SECRET-CURRENCY',
  );
  final date = DateTime.utc(2026, 10, 7);
  final saved = YorksV1MaterialRequest(
    id: 'request',
    projectId: 'project',
    scopeId: 'scope',
    projectReference: 'P1',
    projectName: 'Project',
    scopeName: 'Common',
    state: YorksV1MaterialRequestState.draft,
    recordVersion: 4,
    createdAt: date,
    updatedAt: date,
    title: 'Identical title',
    timing: YorksV1MaterialRequestTiming.scheduled,
    scheduledDate: date,
    deliveryNote: 'Gate B',
    lines: [line],
  );
  final draft = YorksV1MaterialRequestDraft(
    id: 'request',
    ownerAuthUserId: 'owner',
    submissionIdempotencyKey: 'key',
    projectId: saved.projectId,
    scopeId: saved.scopeId,
    title: saved.title,
    timing: saved.timing,
    scheduledDate: date,
    deliveryNote: saved.deliveryNote,
    updatedAt: date,
    lines: [line],
  );

  Future<void> pump(
    WidgetTester tester,
    YorksV1MaterialRequestDraft recovered,
  ) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: YorksV1MaterialRequestRecoveryChanges(
            draft: recovered,
            saved: saved,
            language: AppLanguage.english,
          ),
        ),
      ),
    ),
  );

  testWidgets('delivery note only difference displays both values', (
    tester,
  ) async {
    await pump(tester, draft.copyWith(deliveryNote: 'Gate A'));
    expect(find.text('Delivery note'), findsOneWidget);
    expect(find.text('Saved value: Gate B'), findsOneWidget);
    expect(find.text('Recovered input: Gate A'), findsOneWidget);
    expect(find.textContaining('998877'), findsNothing);
    expect(find.textContaining('SECRET-CURRENCY'), findsNothing);
  });

  for (final field in [
    'model',
    'size',
    'equipmentTag',
    'planningModelTag',
    'brandOrigin',
  ]) {
    testWidgets('technical only change including cleared $field is visible', (
      tester,
    ) async {
      final changed = switch (field) {
        'model' => line.copyWith(model: null),
        'size' => line.copyWith(size: null),
        'equipmentTag' => line.copyWith(equipmentTag: null),
        'planningModelTag' => line.copyWith(planningModelTag: null),
        _ => line.copyWith(brandOrigin: null),
      };
      await pump(tester, draft.copyWith(lines: [changed]));
      expect(find.text('Recovered input: Not set / cleared'), findsOneWidget);
      expect(find.textContaining('Saved value:'), findsOneWidget);
      expect(find.textContaining('998877'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('timing and cleared date are shown before adopting recovery', (
    tester,
  ) async {
    await pump(
      tester,
      draft.copyWith(
        timing: YorksV1MaterialRequestTiming.normal,
        scheduledDate: null,
      ),
    );
    expect(find.text('Saved value: Scheduled'), findsOneWidget);
    expect(find.text('Recovered input: Normal'), findsOneWidget);
    expect(find.text('Saved value: 2026-10-07'), findsOneWidget);
    expect(find.text('Recovered input: Not set / cleared'), findsOneWidget);
  });
}

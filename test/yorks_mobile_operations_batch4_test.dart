import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/constants/app_spacing.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/materials/presentation/screens/yorks_v1_arrangement_screen.dart';
import 'package:material_ledger/features/materials/presentation/screens/yorks_v1_logistics_screen.dart';
import 'package:material_ledger/features/materials/presentation/screens/yorks_v1_returns_documents_screen.dart';
import 'package:material_ledger/shared/models/yorks_v1_arrangement.dart';
import 'package:material_ledger/shared/models/yorks_v1_logistics.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/permissions_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_arrangement_repository_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_logistics_repository_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_material_request_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_material_request_repository_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_arrangement_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_logistics_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_material_request_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/yorks_v1_permission_test_support.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_procurement_progress_provider.dart';
import 'yorks_v1_procurement_progress_test.dart' show FakeRepository;

late SharedPreferences _preferences;

void main() {
  setUpAll(() async {
    final nexusFontLoader = FontLoader('NexusSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final arabicFontLoader = FontLoader('NotoSansArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
    final flutterCache = _flutterCacheDirectory();
    final iconBytes = await File(
      '${flutterCache.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    final iconFontLoader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(iconBytes)));
    await Future.wait([
      nexusFontLoader.load(),
      arabicFontLoader.load(),
      iconFontLoader.load(),
    ]);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _preferences = await SharedPreferences.getInstance();
  });

  for (final size in [const Size(390, 844), const Size(360, 800)]) {
    final suffix = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('ref29 arrangement list $suffix', (tester) async {
      await _setViewport(tester, size);
      await _pumpArrangement(tester, _workingArrangementWorkspace);
      expect(
        find.byKey(const ValueKey('mobile-arrangement-list')),
        findsOneWidget,
      );
      expect(find.text('Review arrangement'), findsOneWidget);
      expect(find.text('Save arrangement'), findsNothing);
      await _golden(tester, '29_arrangement_list_$suffix');
    });

    testWidgets('ref30 arrangement line editor $suffix', (tester) async {
      await _setViewport(tester, size);
      await _pumpArrangement(tester, _workingArrangementWorkspace);
      await tester.tap(find.text('Motorized smoke damper'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mobile-arrangement-line')),
        findsOneWidget,
      );
      expect(find.text('Full'), findsOneWidget);
      expect(find.text('Cannot Provide Now'), findsNothing);
      expect(
        find.byType(DropdownButtonFormField<YorksV1ArrangementDecision>),
        findsNothing,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('arranged-arrangement-line-1')))
            .height,
        greaterThanOrEqualTo(AppSpacing.minTapTarget),
      );
      await _golden(tester, '30_arrangement_line_$suffix');
    });

    testWidgets('ref31 arrangement review $suffix', (tester) async {
      await _setViewport(tester, size);
      await _pumpArrangement(tester, _workingArrangementWorkspace);
      await tester.tap(
        find.byKey(const ValueKey('mobile-arrangement-review-action')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mobile-arrangement-review')),
        findsOneWidget,
      );
      await _golden(tester, '31_arrangement_review_$suffix');
    });

    testWidgets('legacy arrangement review is read-only $suffix', (
      tester,
    ) async {
      await _setViewport(tester, size);
      await _pumpArrangement(tester, _approvalArrangementWorkspace);
      expect(
        find.byKey(const ValueKey('mobile-arrangement-read-only')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mobile-arrangement-approval')),
        findsNothing,
      );
      expect(find.text('Approve arrangement'), findsNothing);
      expect(find.text('Return'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ref34 create dispatch $suffix', (tester) async {
      await _setViewport(tester, size);
      await _pumpLogistics(tester, requestId: 'dispatch');
      expect(
        find.byKey(const ValueKey('mobile-dispatch-create')),
        findsOneWidget,
      );
      await _golden(tester, '34_dispatch_create_$suffix');
    });

    testWidgets('ref35 receipt review $suffix', (tester) async {
      await _setViewport(tester, size);
      await _pumpLogistics(tester, requestId: 'receipt', focusReceipt: true);
      expect(
        find.byKey(const ValueKey('mobile-receipt-review')),
        findsOneWidget,
      );
      expect(find.text('0 / 2 lines reviewed'), findsOneWidget);
      await _golden(tester, '35_receipt_review_$suffix');
    });

    testWidgets('ref36 delivery exception $suffix', (tester) async {
      await _setViewport(tester, size);
      await _pumpLogistics(tester, requestId: 'receipt', focusReceipt: true);
      await tester.tap(find.text('Missing').first);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mobile-receipt-exception')),
        findsOneWidget,
      );
      await _golden(tester, '36_receipt_exception_$suffix');
    });

    testWidgets('ref37 delivery order $suffix', (tester) async {
      await _setViewport(tester, size);
      await _pumpReturns(
        tester,
        requestId: 'delivery',
        focusDeliveryOrder: true,
      );
      expect(
        find.byKey(const ValueKey('mobile-delivery-order-preview')),
        findsOneWidget,
      );
      expect(find.text('Print / PDF'), findsWidgets);
      expect(find.text('Download PDF'), findsWidgets);
      await _golden(tester, '37_delivery_order_$suffix');
    });

    testWidgets('ref38 return material selection $suffix', (tester) async {
      await _setViewport(tester, size);
      await _pumpReturns(tester, requestId: 'returns');
      expect(
        find.byKey(const ValueKey('mobile-return-select')),
        findsOneWidget,
      );
      expect(find.textContaining('10.0000'), findsNothing);
      await _golden(tester, '38_return_select_$suffix');
    });

    testWidgets('ref39 return material review $suffix', (tester) async {
      await _setViewport(tester, size);
      await _pumpReturns(tester, requestId: 'returns');
      await tester.tap(find.text('Copper pipe'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '2');
      await tester.tap(find.text('Save Review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next · 1 Items'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mobile-return-review')),
        findsOneWidget,
      );
      await _golden(tester, '39_return_review_$suffix');
    });
  }

  testWidgets(
    'mobile arrangement saves incomplete progress from the line editor',
    (tester) async {
      await _setViewport(tester, const Size(360, 800));
      final progress = await _pumpArrangement(
        tester,
        _workingArrangementWorkspace,
      );
      expect(find.text('Save progress'), findsOneWidget);
      await tester.tap(find.text('Motorized smoke damper'));
      await tester.pumpAndSettle();
      final quantity = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Arranged',
      );
      await tester.enterText(quantity, '1.');
      final save = find.text('Save progress');
      await Scrollable.ensureVisible(tester.element(save), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(progress.saved, isNotNull);
      final lines = progress.saved!.inputs['lines'] as List;
      expect((lines.first as Map)['arranged_qty'], '1.');
      expect(find.text('Progress saved to your account'), findsOneWidget);
      expect(find.text('Save arrangement'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'quantity drives status without losing focus or source selection',
    (tester) async {
      await _setViewport(tester, const Size(360, 800));
      final progress = await _pumpArrangement(
        tester,
        _workingArrangementWorkspace,
      );
      await tester.tap(find.text('Motorized smoke damper'));
      await tester.pumpAndSettle();
      final quantity = find.byKey(
        const ValueKey('arranged-arrangement-line-1'),
      );
      await tester.enterText(quantity, '4');
      await tester.pumpAndSettle();
      expect(find.text('Partial'), findsOneWidget);
      final editable = tester.widget<EditableText>(
        find.descendant(of: quantity, matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isTrue);
      await tester.enterText(quantity, '0');
      await tester.pumpAndSettle();
      expect(find.text('Cannot Provide Now'), findsOneWidget);
      expect(tester.widget<TextFormField>(quantity).enabled, isTrue);
      await tester.enterText(quantity, '');
      await tester.pumpAndSettle();
      expect(find.text('Cannot Provide Now'), findsNothing);
      expect(find.text('Enter quantity'), findsOneWidget);
      await tester.enterText(quantity, '1.');
      await tester.pumpAndSettle();
      expect(find.text('Partial'), findsNothing);
      expect(find.text('Enter quantity'), findsOneWidget);
      await tester.enterText(quantity, '11');
      await tester.pumpAndSettle();
      expect(find.text('Full'), findsOneWidget);
      final save = find.text('Save progress');
      await Scrollable.ensureVisible(tester.element(save), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      final line = (progress.saved!.inputs['lines'] as List).first as Map;
      expect(line['decision'], 'full');
      expect(line['inventory_item_id'], 'inventory-1');
      expect(line['source_kind'], 'warehouse');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('receipt requires an explicit outcome for every line', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    final repository = await _pumpLogistics(
      tester,
      requestId: 'receipt',
      focusReceipt: true,
    );
    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirm receipt review'),
    );
    expect(confirm.onPressed, isNull);
    expect(repository.receipts, isEmpty);

    await tester.tap(find.text('Receive all as dispatched'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Confirm receipt review'),
    );
    await tester.pumpAndSettle();

    expect(repository.receipts, hasLength(1));
    expect(
      repository.receipts.single.lines.every(
        (line) => line.outcome == YorksV1ReceiptOutcome.received,
      ),
      isTrue,
    );
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('mixed receipt remains exact and usable at 360px', (
    tester,
  ) async {
    await _setViewport(tester, const Size(360, 800));
    final repository = await _pumpLogistics(
      tester,
      requestId: 'receipt',
      focusReceipt: true,
    );

    await tester.tap(find.text('Mixed').first);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile-receipt-exception')),
      findsOneWidget,
    );
    expect(find.text('Missing quantity'), findsOneWidget);
    expect(find.text('Damaged quantity'), findsOneWidget);

    Finder field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
      description: '$label field',
    );
    await tester.enterText(field('Good quantity'), '2');
    await tester.enterText(field('Missing quantity'), '1');
    await tester.enterText(field('Damaged quantity'), '1');
    await tester.enterText(field('Explanation'), 'One missing, one damaged');
    await tester.tap(find.text('Save Review'));
    await tester.pumpAndSettle();

    expect(find.text('1 / 2 lines reviewed'), findsOneWidget);
    await tester.tap(find.text('Received').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Confirm receipt review'),
    );
    await tester.pumpAndSettle();

    expect(repository.receipts, hasLength(1));
    final mixed = repository.receipts.single.lines.first;
    expect(mixed.outcome, YorksV1ReceiptOutcome.mixed);
    expect(mixed.goodQuantity, '2');
    expect(mixed.missingQuantity, '1');
    expect(mixed.damagedQuantity, '1');
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dispatch retry reuses one command identity', (tester) async {
    await _setViewport(tester, const Size(390, 844));
    final repository = _OperationsRepository()..dispatchFailures = 1;
    await _pumpLogistics(tester, requestId: 'dispatch', repository: repository);
    await tester.enterText(find.byType(TextField).first, 'DN-100');
    await tester.tap(find.text('Review dispatch'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-dispatch')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry saved submission'));
    await tester.pumpAndSettle();

    expect(repository.dispatches, hasLength(2));
    expect(
      repository.dispatches.first.idempotencyKey,
      repository.dispatches.last.idempotencyKey,
    );
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('pending receipt checks preserve review and never resend mutation', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    final repository = _OperationsRepository()..receiptFailures = 1;
    final outcomes = _ReceiptOutcomeRpcClient();
    await _pumpLogistics(
      tester,
      requestId: 'receipt',
      focusReceipt: true,
      repository: repository,
      outcomeRpc: outcomes,
    );
    await tester.tap(find.text('Receive all as dispatched'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Confirm receipt review'),
    );
    await tester.pumpAndSettle();
    // Finish the bounded automatic status reads without resending the receipt.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2 lines reviewed'), findsOneWidget);
    expect(find.text('Confirm receipt review'), findsNothing);
    expect(repository.receipts, hasLength(1));
    expect(outcomes.keys, hasLength(3));

    final receiveAll = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Receive all as dispatched'),
    );
    expect(receiveAll.onPressed, isNull);
    final statusReads = outcomes.keys.length;
    await tester.tap(
      find.widgetWithText(FilledButton, 'Check submission status'),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 / 2 lines reviewed'), findsOneWidget);
    expect(outcomes.keys, hasLength(statusReads + 1));
    expect(repository.receipts, hasLength(1));
    expect(outcomes.keys.toSet(), {repository.receipts.single.idempotencyKey});

    // A committed command stays successful even if its optional view is absent.
    outcomes.confirmed = true;
    await tester.tap(
      find.widgetWithText(FilledButton, 'Check submission status'),
    );
    await tester.pumpAndSettle();
    expect(repository.receipts, hasLength(1));
    expect(outcomes.keys, hasLength(statusReads + 2));
    expect(find.byKey(const ValueKey('mobile-receipt-review')), findsNothing);
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('return draft retry reuses the same command identity', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    final repository = _OperationsRepository()..returnFailures = 1;
    await _pumpReturns(tester, requestId: 'returns', repository: repository);
    await tester.tap(find.text('Copper pipe'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '2');
    await tester.tap(find.text('Save Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next · 1 Items'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save return draft'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save return draft'));
    await tester.pumpAndSettle();

    expect(repository.returnDrafts, hasLength(2));
    expect(
      repository.returnDrafts.first.idempotencyKey,
      repository.returnDrafts.last.idempotencyKey,
    );
  });

  testWidgets('return quantities never expose database numeric scale', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1366, 768));
    await _pumpReturns(
      tester,
      requestId: 'returns',
      repository: _OperationsRepository(
        returnsWorkspace: _returnsWorkspaceWithScaledDraft,
      ),
    );

    expect(find.textContaining('10.0000'), findsNothing);
    expect(find.textContaining('50.0000'), findsNothing);
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .map((field) => field.controller?.text),
      contains('10'),
    );
  });

  testWidgets('desktop arrangement stays on the existing office surface', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1366, 768), topInset: 0);
    await _pumpArrangement(tester, _workingArrangementWorkspace);
    expect(find.byKey(const ValueKey('mobile-arrangement-list')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop delivery order uses the controlled printable surface', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1366, 768), topInset: 0);
    await _pumpReturns(tester, requestId: 'delivery', focusDeliveryOrder: true);

    expect(
      find.byKey(const ValueKey('yorks-v1-controlled-delivery-order-preview')),
      findsOneWidget,
    );
    expect(find.text('Print / PDF'), findsWidgets);
    expect(find.text('Download PDF'), findsWidgets);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/r35/controlled_delivery_order_desktop.png'),
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _golden(WidgetTester tester, String name) async {
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/mobile_batch4/$name.png'),
  );
  expect(tester.takeException(), isNull);
}

Future<FakeRepository> _pumpArrangement(
  WidgetTester tester,
  YorksV1ArrangementWorkspace workspace,
) async {
  final repository = _ArrangementRepository(workspace);
  final progress = FakeRepository();
  await tester.pumpWidget(
    _app(
      progressRepository: progress,
      overrides: [
        canManageCommercialsProvider.overrideWithValue(true),
        canViewCommercialsProvider.overrideWithValue(true),
        yorksV1MaterialRequestDetailProvider(
          'request-1',
        ).overrideWith((ref) async => _arrangementRequest),
        yorksV1ArrangementRepositoryProvider.overrideWithValue(repository),
      ],
      child: const YorksV1ArrangementScreen(requestId: 'request-1'),
    ),
  );
  await tester.pumpAndSettle();
  return progress;
}

Future<_OperationsRepository> _pumpLogistics(
  WidgetTester tester, {
  required String requestId,
  bool focusReceipt = false,
  _OperationsRepository? repository,
  YorksV1MaterialRequestRpcClient? outcomeRpc,
}) async {
  final fixture = repository ?? _OperationsRepository();
  await tester.pumpWidget(
    _app(
      overrides: [
        yorksV1LogisticsRepositoryProvider.overrideWithValue(fixture),
        if (outcomeRpc != null)
          yorksV1MaterialRequestRpcClientProvider.overrideWithValue(outcomeRpc),
      ],
      child: YorksV1LogisticsScreen(
        requestId: requestId,
        focusReceiptReview: focusReceipt,
        focusedDispatchId: focusReceipt ? 'dispatch-1' : null,
        initialDispatchDate: DateTime.utc(2026, 8, 9),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fixture;
}

Future<_OperationsRepository> _pumpReturns(
  WidgetTester tester, {
  required String requestId,
  bool focusDeliveryOrder = false,
  _OperationsRepository? repository,
}) async {
  final fixture = repository ?? _OperationsRepository();
  if (focusDeliveryOrder) {
    await tester.pumpWidget(
      _app(
        overrides: const [],
        child: Center(
          child: Image.asset(
            'assets/branding/yorks_emblem_mobile.png',
            width: 42,
            height: 42,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }
  await tester.pumpWidget(
    _app(
      overrides: [
        yorksV1LogisticsRepositoryProvider.overrideWithValue(fixture),
      ],
      child: YorksV1ReturnsDocumentsScreen(
        requestId: requestId,
        focusDeliveryOrder: focusDeliveryOrder,
        focusedDispatchId: focusDeliveryOrder ? 'dispatch-1' : null,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fixture;
}

Widget _app({
  required List<Override> overrides,
  required Widget child,
  FakeRepository? progressRepository,
}) => ProviderScope(
  overrides: [
    sharedPreferencesProvider.overrideWithValue(_preferences),
    yorksV1AuthUserIdProvider.overrideWithValue('procurement-test-user'),
    yorksV1ProcurementProgressRepositoryProvider.overrideWithValue(
      progressRepository ?? FakeRepository(),
    ),
    yorksV1CurrentPermissionSnapshotProvider.overrideWith(
      (ref) => YorksV1TestPermissionController(
        yorksV1TrustedFeaturePermissionState(),
      ),
    ),
    ...overrides,
  ],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: child,
  ),
);

Future<void> _setViewport(
  WidgetTester tester,
  Size size, {
  double topInset = 26,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(top: topInset);
  tester.view.viewPadding = FakeViewPadding(top: topInset);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });
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

final _workingArrangementWorkspace = YorksV1ArrangementWorkspace(
  requestId: 'request-1',
  requestNumber: 'YRA-322-MR101',
  requestState: 'Procurement arrangement',
  requestRecordVersion: 4,
  canBegin: false,
  canSave: true,
  canDecide: false,
  arrangements: [_workingArrangement],
);

final _arrangementRequest = YorksV1MaterialRequest(
  id: 'request-1',
  projectId: 'project-1',
  projectReference: 'YRA-322',
  projectName: 'Al Dhafra Grid Substation HVAC Works',
  scopeId: 'common',
  scopeName: 'Common / All Buildings',
  state: YorksV1MaterialRequestState.arranging,
  recordVersion: 4,
  createdAt: DateTime.utc(2026, 8, 8),
  updatedAt: DateTime.utc(2026, 8, 9),
  timing: YorksV1MaterialRequestTiming.normal,
  requestNumber: 'YRA-322-MR101',
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

final _approvalArrangementWorkspace = YorksV1ArrangementWorkspace(
  requestId: 'request-1',
  requestNumber: 'YRA-322-MR101',
  requestState: 'Project Engineer review',
  requestRecordVersion: 5,
  canBegin: false,
  canSave: false,
  canDecide: true,
  arrangements: [_approvalArrangement],
);

final _workingArrangement = YorksV1ProcurementArrangement(
  id: 'arrangement-1',
  version: 1,
  status: YorksV1ArrangementStatus.working,
  isCurrent: true,
  recordVersion: 2,
  startedByDisplayName: 'Ali Raza',
  startedAt: DateTime.utc(2026, 8, 9),
  lines: const [
    YorksV1ArrangementLine(
      id: 'arrangement-line-1',
      requestLineId: 'request-line-1',
      displayOrder: 1,
      description: 'Motorized smoke damper',
      brandOrigin: 'Beteccad UAE',
      requestedQuantity: '11',
      unit: 'Nos',
      source: YorksV1ArrangementSource.warehouse,
      inventoryItemId: 'inventory-1',
      decision: YorksV1ArrangementDecision.full,
      arrangedQuantity: '11',
      unitCost: '110.29',
    ),
    YorksV1ArrangementLine(
      id: 'arrangement-line-2',
      requestLineId: 'request-line-2',
      displayOrder: 2,
      description: 'Flexible duct connector',
      brandOrigin: 'Yorks',
      requestedQuantity: '6',
      unit: 'Nos',
      source: YorksV1ArrangementSource.externalSupplier,
      externalSupplier: 'Local supplier',
      decision: YorksV1ArrangementDecision.partial,
      arrangedQuantity: '4',
      reason: 'Two units are pending supplier confirmation.',
      unitCost: '35',
    ),
    YorksV1ArrangementLine(
      id: 'arrangement-line-3',
      requestLineId: 'request-line-3',
      displayOrder: 3,
      description: 'Spring mounts',
      requestedQuantity: '2',
      unit: 'Set',
      source: YorksV1ArrangementSource.externalSupplier,
      decision: YorksV1ArrangementDecision.unavailable,
      arrangedQuantity: '0',
      reason: 'Not currently available.',
    ),
  ],
);

final _approvalArrangement = YorksV1ProcurementArrangement(
  id: _workingArrangement.id,
  version: _workingArrangement.version,
  status: YorksV1ArrangementStatus.awaitingApproval,
  isCurrent: true,
  recordVersion: 3,
  startedByDisplayName: _workingArrangement.startedByDisplayName,
  startedAt: _workingArrangement.startedAt,
  savedAt: DateTime.utc(2026, 8, 9, 10),
  savedByDisplayName: 'Ali Raza',
  procurementNote: 'Partial supply is clearly marked for review.',
  lines: _workingArrangement.lines,
);

class _ArrangementRepository implements YorksV1ArrangementRepository {
  _ArrangementRepository(this.workspace);

  final YorksV1ArrangementWorkspace workspace;

  @override
  Future<YorksV1ArrangementWorkspace> begin(
    YorksV1BeginArrangementInput input,
  ) async => workspace;

  @override
  Future<YorksV1ArrangementWorkspace> decide(
    YorksV1DecideArrangementInput input,
  ) async => workspace;

  @override
  Future<YorksV1ArrangementWorkspace> getWorkspace(String requestId) async =>
      workspace;

  @override
  Future<List<YorksV1InventoryItem>> listInventoryItems() async => const [
    YorksV1InventoryItem(
      id: 'inventory-1',
      description: 'Motorized smoke damper',
      unit: 'Nos',
      onHandQuantity: '12',
      reservedQuantity: '1',
      availableQuantity: '11',
      recordVersion: 2,
    ),
  ];

  @override
  Future<YorksV1ArrangementWorkspace> save(
    YorksV1SaveArrangementInput input,
  ) async => workspace;

  @override
  Future<YorksV1ArrangementWorkspace> updateProcurementItem(
    YorksV1UpdateProcurementMaterialItemInput input,
  ) async => workspace;
}

class _OperationsRepository implements YorksV1LogisticsRepository {
  _OperationsRepository({this.returnsWorkspace});

  final YorksV1ReturnsDocumentsWorkspace? returnsWorkspace;
  int dispatchFailures = 0;
  int receiptFailures = 0;
  int returnFailures = 0;
  final List<YorksV1DispatchInput> dispatches = [];
  final List<YorksV1ReceiptConfirmationInput> receipts = [];
  final List<YorksV1MaterialReturnDraftInput> returnDrafts = [];

  @override
  Future<List<YorksV1ProjectMaterialMovement>> getProjectMaterialMovements(
    String projectId,
  ) async => const [];

  @override
  Future<YorksV1LogisticsWorkspace> getWorkspace(String requestId) async =>
      requestId == 'receipt' ? _receiptWorkspace : _dispatchWorkspace;

  @override
  Future<YorksV1LogisticsWorkspace> dispatch(YorksV1DispatchInput input) async {
    dispatches.add(input);
    if (dispatchFailures-- > 0) throw StateError('temporary failure');
    return _dispatchWorkspace;
  }

  @override
  Future<YorksV1LogisticsWorkspace> confirmReceipt(
    YorksV1ReceiptConfirmationInput input,
  ) async {
    receipts.add(input);
    if (receiptFailures-- > 0) throw StateError('temporary failure');
    return _receiptWorkspace;
  }

  @override
  Future<YorksV1ReturnsDocumentsWorkspace> getReturnsDocumentsWorkspace(
    String requestId,
  ) async =>
      returnsWorkspace ??
      (requestId == 'delivery' ? _deliveryWorkspace : _returnsWorkspace);

  @override
  Future<YorksV1ReturnsDocumentsWorkspace> generateDeliveryOrder(
    YorksV1DeliveryOrderGenerationInput input,
  ) async => _deliveryWorkspace;

  @override
  Future<YorksV1ReturnsDocumentsWorkspace> saveMaterialReturnDraft(
    YorksV1MaterialReturnDraftInput input,
  ) async {
    returnDrafts.add(input);
    if (returnFailures-- > 0) throw StateError('temporary failure');
    return _returnsWorkspace;
  }

  @override
  Future<YorksV1ReturnsDocumentsWorkspace> submitMaterialReturn(
    YorksV1MaterialReturnSubmissionInput input,
  ) async => _returnsWorkspace;

  @override
  Future<YorksV1ReturnsDocumentsWorkspace> confirmMaterialReturn(
    YorksV1MaterialReturnConfirmationInput input,
  ) async => _returnsWorkspace;

  @override
  Future<YorksV1ReturnsDocumentsWorkspace> rejectMaterialReturn(
    YorksV1MaterialReturnRejectionInput input,
  ) async => _returnsWorkspace;

  @override
  Future<YorksV1InventoryWorkspace> getInventory({String? search}) async =>
      YorksV1InventoryWorkspace(items: const []);

  @override
  Future<YorksV1InventoryItemDetail> getInventoryItem(String inventoryItemId) =>
      throw UnimplementedError();

  @override
  Future<YorksV1LogisticsInventoryItem> adjustInventory(
    YorksV1InventoryAdjustmentInput input,
  ) => throw UnimplementedError();

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
}

final _dispatchWorkspace = YorksV1LogisticsWorkspace(
  requestId: 'dispatch',
  projectId: 'project-1',
  requestNumber: 'YRA-322-MR101',
  requestState: 'approved',
  requestRecordVersion: 7,
  projectName: 'Al Dhafra Grid Substation HVAC Works',
  scopeName: 'Common / All Buildings',
  canDispatch: true,
  canConfirmReceipt: false,
  dispatchCandidates: const [
    YorksV1DispatchCandidate(
      requestLineId: 'request-line-1',
      displayOrder: 1,
      description: 'Motorized smoke damper',
      brandOrigin: 'Beteccad UAE',
      unit: 'Nos',
      approvedQuantity: '4',
      goodReceivedQuantity: '0',
      inTransitQuantity: '0',
      stillNeededQuantity: '4',
      source: YorksV1LogisticsSource.warehouse,
      inventoryItemId: 'inventory-1',
      reservedRemainingQuantity: '4',
      warehouseAvailableQuantity: '7',
    ),
  ],
  dispatches: const [],
);

final _receiptDispatch = YorksV1MaterialDispatch(
  id: 'dispatch-1',
  number: 'YRA-322-DSP001',
  dispatchDate: DateTime.utc(2026, 8, 9),
  state: YorksV1DispatchState.receiptPending,
  recordVersion: 2,
  dispatchedByDisplayName: 'Ali Raza',
  dispatchedAt: DateTime.utc(2026, 8, 9, 9),
  canConfirmReceipt: true,
  deliveryReference: 'DN-100',
  driverName: 'Ahmed',
  vehicleReference: 'AD-20451',
  lines: const [
    YorksV1DispatchLine(
      id: 'dispatch-line-1',
      requestLineId: 'request-line-1',
      description: 'Motorized smoke damper',
      brandOrigin: 'Beteccad UAE',
      unit: 'Nos',
      source: YorksV1LogisticsSource.warehouse,
      dispatchedQuantity: '4',
      approvedQuantity: '4',
    ),
    YorksV1DispatchLine(
      id: 'dispatch-line-2',
      requestLineId: 'request-line-2',
      description: 'Flexible duct connector',
      brandOrigin: 'Yorks',
      unit: 'Nos',
      source: YorksV1LogisticsSource.externalSupplier,
      dispatchedQuantity: '2',
      approvedQuantity: '2',
    ),
  ],
);

final _receiptWorkspace = YorksV1LogisticsWorkspace(
  requestId: 'receipt',
  projectId: 'project-1',
  requestNumber: 'YRA-322-MR101',
  requestState: 'dispatched',
  requestRecordVersion: 8,
  projectName: 'Al Dhafra Grid Substation HVAC Works',
  scopeName: 'Common / All Buildings',
  canDispatch: false,
  canConfirmReceipt: true,
  dispatchCandidates: const [],
  dispatches: [_receiptDispatch],
);

final _deliveryOrder = YorksV1DeliveryOrder(
  id: 'delivery-order-1',
  dispatchId: 'dispatch-1',
  reference: 'DO-2026-0101',
  recordVersion: 1,
  currentRevisionId: 'delivery-revision-1',
  revisions: [
    YorksV1DeliveryOrderRevision(
      id: 'delivery-revision-1',
      revisionNumber: 1,
      isCurrent: true,
      generatedAt: DateTime.utc(2026, 8, 9, 10),
      generatedByDisplayName: 'Omar Farooq',
      lines: const [
        YorksV1DeliveryOrderLine(
          serialNumber: 1,
          description: 'Motorized smoke damper',
          size: '500x300mm',
          model: 'MSD-500',
          quantity: '4',
          unit: 'Nos',
        ),
        YorksV1DeliveryOrderLine(
          serialNumber: 2,
          description: 'Flexible duct connector',
          size: '300mm',
          model: 'FDC-300',
          quantity: '2',
          unit: 'Nos',
        ),
      ],
    ),
  ],
);

final _deliveryWorkspace = YorksV1ReturnsDocumentsWorkspace(
  requestId: 'delivery',
  projectId: 'project-1',
  requestNumber: 'YRA-322-MR101',
  requestState: 'dispatched',
  requestRecordVersion: 8,
  projectName: 'Al Dhafra Grid Substation HVAC Works',
  projectReference: 'YRA-322',
  scopeName: 'Common / All Buildings',
  canGenerateDeliveryOrder: true,
  canSubmitMaterialReturn: false,
  canConfirmMaterialReturn: false,
  deliveryOrderDispatches: [
    YorksV1DeliveryOrderDispatch(
      dispatchId: 'dispatch-1',
      dispatchNumber: 'YRA-322-DSP001',
      dispatchDate: DateTime.utc(2026, 8, 9),
      dispatchRecordVersion: 2,
      canGenerate: true,
      deliveryOrder: _deliveryOrder,
    ),
  ],
  returnCandidates: const [],
  materialReturns: const [],
  returnInventoryItems: const [],
);

final _returnsWorkspace = YorksV1ReturnsDocumentsWorkspace(
  requestId: 'returns',
  projectId: 'project-1',
  requestNumber: 'YRA-322-MR101',
  requestState: 'received',
  requestRecordVersion: 9,
  projectName: 'Al Dhafra Grid Substation HVAC Works',
  projectReference: 'YRA-322',
  scopeName: 'Common / All Buildings',
  canGenerateDeliveryOrder: false,
  canSubmitMaterialReturn: true,
  canConfirmMaterialReturn: false,
  deliveryOrderDispatches: const [],
  returnCandidates: const [
    YorksV1ReturnCandidate(
      receiptReviewLineId: 'receipt-line-1',
      dispatchNumber: 'YRA-322-DSP001',
      displayOrder: 1,
      description: 'Copper pipe',
      brandOrigin: 'Mueller',
      unit: 'Mtr',
      source: YorksV1LogisticsSource.warehouse,
      goodReceivedQuantity: '12.0000',
      confirmedReturnQuantity: '2.0000',
      eligibleReturnQuantity: '10.0000',
      sourceInventoryItemId: 'inventory-copper',
    ),
    YorksV1ReturnCandidate(
      receiptReviewLineId: 'receipt-line-2',
      dispatchNumber: 'YRA-322-DSP001',
      displayOrder: 2,
      description: 'Flexible duct connector',
      brandOrigin: 'Yorks',
      unit: 'Nos',
      source: YorksV1LogisticsSource.externalSupplier,
      goodReceivedQuantity: '4',
      confirmedReturnQuantity: '0',
      eligibleReturnQuantity: '4',
    ),
  ],
  materialReturns: const [],
  returnInventoryItems: const [],
);

final _returnsWorkspaceWithScaledDraft = YorksV1ReturnsDocumentsWorkspace(
  requestId: 'returns',
  projectId: 'project-1',
  requestNumber: 'YRA-322-MR101',
  requestState: 'received',
  requestRecordVersion: 9,
  projectName: 'Al Dhafra Grid Substation HVAC Works',
  projectReference: 'YRA-322',
  scopeName: 'Common / All Buildings',
  canGenerateDeliveryOrder: false,
  canSubmitMaterialReturn: true,
  canConfirmMaterialReturn: false,
  deliveryOrderDispatches: const [],
  returnCandidates: const [
    YorksV1ReturnCandidate(
      receiptReviewLineId: 'receipt-line-scaled',
      dispatchNumber: 'YRA-322-DSP001',
      displayOrder: 1,
      description: 'Cable tray hanging clamp',
      unit: 'Nos',
      source: YorksV1LogisticsSource.warehouse,
      goodReceivedQuantity: '50.0000',
      confirmedReturnQuantity: '0.0000',
      eligibleReturnQuantity: '50.0000',
      sourceInventoryItemId: 'inventory-clamp',
    ),
  ],
  materialReturns: [
    YorksV1MaterialReturn(
      id: 'return-scaled',
      state: YorksV1MaterialReturnState.draft,
      recordVersion: 1,
      draftedAt: DateTime.utc(2026, 8, 12),
      draftedByDisplayName: 'Project Engineer',
      canEditDraft: true,
      canSubmit: true,
      canConfirm: false,
      canReject: false,
      lines: const [
        YorksV1MaterialReturnLine(
          id: 'return-line-scaled',
          receiptReviewLineId: 'receipt-line-scaled',
          dispatchNumber: 'YRA-322-DSP001',
          displayOrder: 1,
          description: 'Cable tray hanging clamp',
          unit: 'Nos',
          source: YorksV1LogisticsSource.warehouse,
          goodQuantitySnapshot: '50.0000',
          returnQuantity: '10.0000',
        ),
      ],
    ),
  ],
  returnInventoryItems: const [],
);

class _ReceiptOutcomeRpcClient implements YorksV1MaterialRequestRpcClient {
  final List<String> keys = [];
  bool confirmed = false;

  @override
  Future<Object?> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async {
    expect(functionName, 'v1_get_material_workflow_command_outcome');
    expect(parameters['p_command_name'], 'v1_confirm_receipt');
    final key = parameters['p_idempotency_key']! as String;
    keys.add(key);
    return {
      'status': confirmed ? 'confirmed' : 'unknown',
      'command_name': 'v1_confirm_receipt',
      'command_key': key,
      if (confirmed) 'entity_id': 'receipt',
      if (confirmed) 'record_version': 9,
      'response': null,
    };
  }
}

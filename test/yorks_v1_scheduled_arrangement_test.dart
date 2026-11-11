import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/materials/presentation/screens/yorks_v1_arrangement_screen.dart';
import 'package:material_ledger/shared/models/yorks_v1_arrangement.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/permissions_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_arrangement_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_arrangement_repository_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_material_request_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_procurement_progress_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_sourcing_progress_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_arrangement_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_sourcing_progress_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/yorks_v1_permission_test_support.dart';
import 'yorks_v1_procurement_progress_test.dart' show FakeRepository;

void main() {
  setUpAll(() async {
    final fonts = FontLoader('NexusSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    var directory = File(Platform.resolvedExecutable).parent;
    while (!directory.path.endsWith('${Platform.pathSeparator}cache') &&
        directory.path != directory.parent.path) {
      directory = directory.parent;
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            await File(
              '${directory.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes(),
          ),
        ),
      );
    await Future.wait([fonts.load(), icons.load()]);
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in [const Size(1366, 900), const Size(360, 800)]) {
    final suffix = '${size.width.toInt()}x${size.height.toInt()}';
    testWidgets(
      'scheduled update shares ready facts without committing arrangement $suffix',
      (tester) async {
        final fixture = await _pump(tester, size: size);
        expect(find.textContaining('Scheduled'), findsOneWidget);
        expect(find.textContaining('Oct 15'), findsOneWidget);
        expect(find.text('No preparation update yet'), findsOneWidget);
        if (size.width < 600) {
          expect(find.text('3 / 3 quantities entered'), findsOneWidget);
        }
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/r35/scheduled_arrangement_$suffix.png'),
        );
        await _tapUpdate(tester);
        expect(find.text('Share preparation update?'), findsOneWidget);
        expect(find.text('Ready now 2 / 5 Nos'), findsOneWidget);
        expect(
          find.text('Ready now 0 / 10 m · Expected 2026-10-14'),
          findsOneWidget,
        );
        expect(find.text('Ready now 0 / 3 Set'), findsOneWidget);
        expect(fixture.sourcing.payloads, isEmpty);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/r35/scheduled_arrangement_preview_$suffix.png',
          ),
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Update team'));
        await tester.pumpAndSettle();
        expect(fixture.sourcing.payloads, hasLength(1));
        final payload = fixture.sourcing.payloads.single;
        final lines = payload['lines'] as List;
        expect(lines.map((line) => (line as Map)['ready_qty']), [
          '2',
          '0',
          '0',
        ]);
        expect((lines[1] as Map)['expected_available_date'], '2026-10-14');
        expect(payload['expected_request_version'], 3);
        expect(payload['expected_arrangement_version'], 1);
        expect(payload['expected_revision'], 0);
        expect(payload.toString(), isNot(contains('unit_cost')));
        expect(
          find.text('0 ready · 1 partly ready · 2 waiting'),
          findsOneWidget,
        );
        expect(fixture.arrangement.commands, isEmpty);
        expect(fixture.privateProgress.saved, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'external quantity becomes ready only after an explicit available confirmation',
    (tester) async {
      final fixture = await _pump(tester, size: const Size(360, 800));
      final external = find.text('Flexible duct');
      await Scrollable.ensureVisible(tester.element(external), alignment: .3);
      await tester.pumpAndSettle();
      await tester.tap(external);
      await tester.pumpAndSettle();
      final ready = find.byKey(
        const ValueKey('external-ready-arrangement-line-2'),
      );
      await Scrollable.ensureVisible(tester.element(ready), alignment: .3);
      await tester.pumpAndSettle();
      await tester.tap(ready);
      await tester.pumpAndSettle();
      await _tapUpdate(tester);
      expect(
        find.text('Ready now 8 / 10 m · Expected 2026-10-14'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Update team'));
      await tester.pumpAndSettle();
      expect(
        ((fixture.sourcing.payloads.single['lines'] as List)[1]
            as Map)['ready_qty'],
        '8',
      );
      expect(fixture.arrangement.commands, isEmpty);
      expect(fixture.privateProgress.saved, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'incomplete quantity stays private and cannot publish a misleading team update',
    (tester) async {
      final fixture = await _pump(tester, size: const Size(360, 800));
      final item = find.text('Access door');
      await Scrollable.ensureVisible(tester.element(item), alignment: .3);
      await tester.pumpAndSettle();
      await tester.tap(item);
      await tester.pumpAndSettle();
      final quantity = find.byKey(
        const ValueKey('arranged-arrangement-line-1'),
      );
      await tester.enterText(quantity, '1.');
      await _tapUpdate(tester);
      expect(find.text('Share preparation update?'), findsNothing);
      expect(
        find.textContaining('Check the quantities and expected dates'),
        findsOneWidget,
      );
      expect(tester.widget<TextFormField>(quantity).controller!.text, '1.');
      expect(fixture.sourcing.payloads, isEmpty);
      expect(fixture.arrangement.commands, isEmpty);
      expect(fixture.privateProgress.saved, isNull);
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rejected team update preserves confirmed quantities and private edits',
    (tester) async {
      final sourcing = _SourcingRepository()
        ..confirmed = _confirmed(warehouse: '1')
        ..saveError = const YorksV1DomainException(
          YorksV1DomainErrorCode.conflict,
        );
      final fixture = await _pump(
        tester,
        size: const Size(1366, 900),
        sourcing: sourcing,
      );
      final quantity = find.byKey(
        const ValueKey('arranged-arrangement-line-1'),
      );
      await tester.enterText(quantity, '4');
      await _tapUpdate(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Update team'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Team progress could not be updated'),
        findsOneWidget,
      );
      expect(tester.widget<TextFormField>(quantity).controller!.text, '4');
      expect(sourcing.confirmed!.lines.first.readyQuantity, '1');
      expect(find.text('0 ready · 1 partly ready · 2 waiting'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Update team'))
            .onPressed,
        isNull,
      );
      expect(fixture.arrangement.commands, isEmpty);
      expect(fixture.privateProgress.saved, isNull);
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rapid update and confirmation taps produce one shared update', (
    tester,
  ) async {
    final sourcing = _SourcingRepository()
      ..pending = Completer<YorksV1SourcingProgress>();
    final fixture = await _pump(
      tester,
      size: const Size(1366, 900),
      sourcing: sourcing,
    );
    final update = find.widgetWithText(TextButton, 'Update team');
    await tester.tap(update);
    await tester.tap(update, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    final confirm = find.widgetWithText(FilledButton, 'Update team');
    await tester.tap(confirm);
    await tester.tap(confirm, warnIfMissed: false);
    await tester.pump();
    expect(sourcing.payloads, hasLength(1));
    sourcing.pending!.complete(_confirmed());
    await tester.pumpAndSettle();
    expect(find.byType(YorksV1ArrangementScreen), findsOneWidget);
    expect(fixture.arrangement.commands, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _tapUpdate(WidgetTester tester) async {
  final button = find.widgetWithText(TextButton, 'Update team');
  await Scrollable.ensureVisible(tester.element(button), alignment: .3);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<
  ({
    _SourcingRepository sourcing,
    _ArrangementRepository arrangement,
    FakeRepository privateProgress,
  })
>
_pump(
  WidgetTester tester, {
  required Size size,
  _SourcingRepository? sourcing,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final preferences = await SharedPreferences.getInstance();
  final shared = sourcing ?? _SourcingRepository();
  final arrangement = _ArrangementRepository();
  final progress = FakeRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksV1AuthUserIdProvider.overrideWithValue('procurement-test-user'),
        yorksV1CurrentRoleProvider.overrideWithValue(YorksV1Role.procurement),
        yorksV1CurrentPermissionSnapshotProvider.overrideWith(
          (ref) => YorksV1TestPermissionController(
            yorksV1TrustedFeaturePermissionState(),
          ),
        ),
        canManageCommercialsProvider.overrideWithValue(false),
        canViewCommercialsProvider.overrideWithValue(false),
        yorksV1ProcurementProgressRepositoryProvider.overrideWithValue(
          progress,
        ),
        yorksV1SourcingProgressRepositoryProvider.overrideWithValue(shared),
        yorksV1ArrangementRepositoryProvider.overrideWithValue(arrangement),
        yorksV1ArrangementWorkspaceProvider(
          'request-1',
        ).overrideWith((ref) async => _workspace),
        yorksV1MaterialRequestDetailProvider(
          'request-1',
        ).overrideWith((ref) async => _request),
        yorksV1ArrangementInventoryProvider.overrideWith(
          (ref) async => _inventory,
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: YorksV1ArrangementScreen(
          requestId: 'request-1',
          embedded: size.width >= 600,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (
    sourcing: shared,
    arrangement: arrangement,
    privateProgress: progress,
  );
}

final _workspace = YorksV1ArrangementWorkspace(
  requestId: 'request-1',
  requestNumber: 'YRA-322-MR015',
  requestState: 'arranging',
  requestRecordVersion: 3,
  canBegin: false,
  canSave: true,
  canDecide: false,
  timing: YorksV1MaterialRequestTiming.scheduled,
  scheduledDate: DateTime.utc(2026, 10, 15),
  arrangements: [
    YorksV1ProcurementArrangement(
      id: 'arrangement-1',
      version: 1,
      status: YorksV1ArrangementStatus.working,
      isCurrent: true,
      recordVersion: 1,
      startedByDisplayName: 'Procurement user',
      startedAt: DateTime.utc(2026, 10, 9),
      lines: [
        const YorksV1ArrangementLine(
          id: 'arrangement-line-1',
          requestLineId: 'line-1',
          displayOrder: 1,
          description: 'Access door',
          requestedQuantity: '5',
          unit: 'Nos',
          source: YorksV1ArrangementSource.warehouse,
          inventoryItemId: 'inventory-1',
          arrangedQuantity: '2',
        ),
        YorksV1ArrangementLine(
          id: 'arrangement-line-2',
          requestLineId: 'line-2',
          displayOrder: 2,
          description: 'Flexible duct',
          requestedQuantity: '10',
          unit: 'm',
          source: YorksV1ArrangementSource.externalSupplier,
          arrangedQuantity: '8',
          externalSupplier: 'Supplier A',
          externalExpectedDate: DateTime.utc(2026, 10, 14),
        ),
        const YorksV1ArrangementLine(
          id: 'arrangement-line-3',
          requestLineId: 'line-3',
          displayOrder: 3,
          description: 'Mounting kit',
          requestedQuantity: '3',
          unit: 'Set',
          source: YorksV1ArrangementSource.externalSupplier,
        ),
      ],
    ),
  ],
);
final _request = YorksV1MaterialRequest(
  id: 'request-1',
  projectId: 'project-1',
  projectReference: 'YRA-322',
  projectName: 'Substation',
  scopeId: 'scope-1',
  scopeName: 'Building A',
  state: YorksV1MaterialRequestState.arranging,
  recordVersion: 3,
  createdAt: DateTime.utc(2026, 10, 9),
  updatedAt: DateTime.utc(2026, 10, 9),
  timing: YorksV1MaterialRequestTiming.scheduled,
  scheduledDate: DateTime.utc(2026, 10, 15),
  requestNumber: 'YRA-322-MR015',
  lines: const [],
);
const _inventory = [
  YorksV1InventoryItem(
    id: 'inventory-1',
    description: 'Access door',
    unit: 'Nos',
    onHandQuantity: '10',
    reservedQuantity: '0',
    availableQuantity: '10',
    recordVersion: 1,
    locationBin: 'Rack B / Shelf 3',
  ),
];

YorksV1SourcingProgress _confirmed({
  String warehouse = '2',
  int revision = 1,
  List? lines,
}) => YorksV1SourcingProgress.fromJson({
  'request_id': 'request-1',
  'arrangement_id': 'arrangement-1',
  'revision': revision,
  'is_current': true,
  'updated_at': '2026-10-09T10:30:00Z',
  'updated_by_display_name': 'Procurement user',
  'lines':
      lines ??
      [
        {
          'request_line_id': 'line-1',
          'ready_qty': warehouse,
          'requested_qty': '5',
          'source_kind': 'warehouse',
          'inventory_item_id': 'inventory-1',
        },
        {
          'request_line_id': 'line-2',
          'ready_qty': '0',
          'requested_qty': '10',
          'source_kind': 'external_supplier',
          'expected_available_date': '2026-10-14',
        },
        {
          'request_line_id': 'line-3',
          'ready_qty': '0',
          'requested_qty': '3',
          'source_kind': 'external_supplier',
        },
      ],
});

class _SourcingRepository implements YorksV1SourcingProgressRepository {
  final payloads = <Map<String, Object?>>[];
  YorksV1SourcingProgress? confirmed;
  Object? saveError;
  Completer<YorksV1SourcingProgress>? pending;
  @override
  Future<YorksV1SourcingProgress?> read(YorksV1SourcingScope scope) async =>
      confirmed;
  @override
  Future<YorksV1SourcingProgress> save(
    Map<String, Object?> payload,
    String key,
  ) async {
    payloads.add(payload);
    if (saveError != null) throw saveError!;
    if (pending != null) return pending!.future;
    final requested = {'line-1': '5', 'line-2': '10', 'line-3': '3'};
    confirmed = _confirmed(
      revision: (confirmed?.revision ?? 0) + 1,
      lines: [
        for (final raw in payload['lines'] as List)
          {
            ...raw as Map<String, Object?>,
            'requested_qty': requested[raw['request_line_id']],
          },
      ],
    );
    return confirmed!;
  }
}

class _ArrangementRepository implements YorksV1ArrangementRepository {
  final commands = <Invocation>[];
  @override
  Future<YorksV1ArrangementWorkspace> getWorkspace(String id) async =>
      _workspace;
  @override
  Future<List<YorksV1InventoryItem>> listInventoryItems() async => _inventory;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    commands.add(invocation);
    throw StateError('Unexpected arrangement mutation');
  }
}

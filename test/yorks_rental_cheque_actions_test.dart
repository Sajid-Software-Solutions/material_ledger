import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/core/widgets/widgets.dart';
import 'package:material_ledger/features/rentals/presentation/screens/yorks_v1_rental_screens.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_rental.dart';
import 'package:material_ledger/shared/providers/yorks_v1_rental_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_rental_repository.dart';

void main() {
  setUpAll(() async {
    final sans = FontLoader('NexusSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    var directory = File(Platform.resolvedExecutable).parent;
    while (!directory.path.endsWith('${Platform.pathSeparator}cache')) {
      if (directory.parent.path == directory.path) {
        throw StateError('Flutter cache unavailable');
      }
      directory = directory.parent;
    }
    final icons = await File(
      '${directory.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    final material = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(icons)));
    await Future.wait([sans.load(), material.load()]);
  });

  const matrix = {
    YorksV1RentalChequeStatus.scheduled: ['Mark received', 'Mark cancelled'],
    YorksV1RentalChequeStatus.received: [
      'Mark deposited',
      'Mark returned',
      'Mark cancelled',
    ],
    YorksV1RentalChequeStatus.deposited: ['Mark cleared', 'Mark returned'],
    YorksV1RentalChequeStatus.returned: ['Mark received', 'Mark cancelled'],
    YorksV1RentalChequeStatus.cleared: <String>[],
    YorksV1RentalChequeStatus.cancelled: <String>[],
  };
  for (final entry in matrix.entries) {
    testWidgets(
      '${entry.key.name} cheque exposes only server-permitted transitions',
      (tester) async {
        await _openCheques(tester, _ChequeRepository(entry.key));
        if (entry.value.isEmpty) {
          expect(find.byTooltip('Cheque actions'), findsNothing);
        } else {
          await tester.tap(find.byTooltip('Cheque actions'));
          await tester.pumpAndSettle();
          for (final label in [
            'Mark received',
            'Mark deposited',
            'Mark cleared',
            'Mark returned',
            'Mark cancelled',
          ]) {
            expect(
              find.text(label),
              entry.value.contains(label) ? findsOneWidget : findsNothing,
            );
          }
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'return requires a reason and retains it while an uncertain result is retried',
    (tester) async {
      final repository = _ChequeRepository(YorksV1RentalChequeStatus.received)
        ..loseNextResponse = true;
      await _openCheques(tester, repository);
      await _choose(tester, 'Mark returned');
      final confirm = find.widgetWithText(TextButton, 'Mark returned');
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.text('A reason is required.'), findsOneWidget);
      expect(repository.calls, isEmpty);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Change reason'),
        'Bank returned the cheque',
      );
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.text('Confirm status change'), findsOneWidget);
      expect(find.text('Bank returned the cheque'), findsOneWidget);
      expect(repository.calls, hasLength(1));
      await tester.tap(find.text('Confirm status change'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(repository.calls, hasLength(2));
      expect(repository.calls[0]['key'], repository.calls[1]['key']);
      expect(repository.calls[1]['reason'], 'Bank returned the cheque');
      expect(repository.committedKeys, hasLength(1));
      expect(repository.status, YorksV1RentalChequeStatus.returned);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancel reason dialog can be dismissed without writing, then confirmed',
    (tester) async {
      final repository = _ChequeRepository(YorksV1RentalChequeStatus.scheduled);
      await _openCheques(tester, repository);
      await _choose(tester, 'Mark cancelled');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(repository.calls, isEmpty);
      await _choose(tester, 'Mark cancelled');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Change reason'),
        'Replaced by bank transfer',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Mark cancelled'));
      await tester.pumpAndSettle();
      expect(repository.status, YorksV1RentalChequeStatus.cancelled);
      expect(repository.calls.single['reason'], 'Replaced by bank transfer');
      expect(find.byTooltip('Cheque actions'), findsNothing);
    },
  );

  testWidgets(
    'returned cheque can be received again and busy commands disable actions',
    (tester) async {
      final repository = _ChequeRepository(YorksV1RentalChequeStatus.returned)
        ..pending = Completer<void>();
      await _openCheques(tester, repository);
      await _choose(tester, 'Mark received', settle: false);
      await tester.pump();
      expect(repository.calls, hasLength(1));
      final menu = tester.widget<PopupMenuButton<YorksV1RentalChequeStatus>>(
        find.byType(PopupMenuButton<YorksV1RentalChequeStatus>),
      );
      expect(menu.enabled, isFalse);
      expect(
        tester
            .widget<PrimaryButton>(
              find.widgetWithText(PrimaryButton, 'Add cheque'),
            )
            .onPressed,
        isNull,
      );
      repository.pending!.complete();
      await tester.pumpAndSettle();
      expect(repository.status, YorksV1RentalChequeStatus.received);
      expect(repository.calls.single['reason'], isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('archived property cheque history is read-only', (tester) async {
    final repository = _ChequeRepository(YorksV1RentalChequeStatus.received)
      ..archived = true;
    await _openCheques(tester, repository);
    expect(find.byTooltip('Cheque actions'), findsNothing);
    expect(
      tester
          .widget<PrimaryButton>(
            find.widgetWithText(PrimaryButton, 'Add cheque'),
          )
          .onPressed,
      isNull,
    );
    expect(repository.calls, isEmpty);
  });

  for (final size in [const Size(1366, 768), const Size(360, 800)]) {
    testWidgets('cheque actions and reason fit $size', (tester) async {
      await _openCheques(
        tester,
        _ChequeRepository(YorksV1RentalChequeStatus.received),
        size: size,
      );
      await _choose(tester, 'Mark returned');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Change reason'),
        'Bank returned the cheque',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/r38_4/rental_cheque_reason_${size.width.toInt()}.png',
        ),
      );
    });
  }
}

Future<void> _openCheques(
  WidgetTester tester,
  _ChequeRepository repository, {
  Size size = const Size(1366, 768),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        yorksV1RentalRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const YorksV1RentalPropertyScreen(propertyId: 'property-1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (size.width < 720) {
    await tester.tap(
      find.byWidgetPredicate((widget) => widget is DropdownButtonFormField),
    );
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('CDC / PDC'));
  await tester.pumpAndSettle();
}

Future<void> _choose(
  WidgetTester tester,
  String label, {
  bool settle = true,
}) async {
  await tester.tap(find.byTooltip('Cheque actions'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  if (settle) await tester.pumpAndSettle();
}

class _ChequeRepository implements YorksV1RentalRepository {
  _ChequeRepository(this.status);
  YorksV1RentalChequeStatus status;
  bool archived = false;
  bool loseNextResponse = false;
  Completer<void>? pending;
  final calls = <Map<String, Object?>>[];
  final committedKeys = <String>{};
  int version = 1;

  @override
  Future<YorksV1RentalPropertyDetail> getProperty(String propertyId) async =>
      YorksV1RentalPropertyDetail.fromJson({
        'property': {
          'id': 'property-1',
          'unit_code': 'SHOP-1',
          'property_name': 'Example shop',
          'property_type': 'shop',
          'location': 'Example location',
          'occupancy_state': 'occupied',
          'record_version': 1,
          'is_archived': archived,
        },
        'lease': {
          'id': 'lease-1',
          'tenant_name': 'Example tenant',
          'contract_number': 'TC-1',
          'lease_start': '2026-01-01',
          'lease_end': '2026-12-31',
          'monthly_rent': 1000,
        },
        'periods': [],
        'receipts': [],
        'activity': [],
        'cheques': [
          {
            'id': 'cheque-1',
            'property_id': 'property-1',
            'lease_id': 'lease-1',
            'cheque_number': 'PDC-001',
            'cheque_type': 'PDC',
            'bank_name': 'Example Bank',
            'cheque_date': '2026-11-01',
            'amount': 1000,
            'status': status.name,
            'record_version': version,
          },
        ],
      });

  @override
  Future<void> transitionCheque({
    required String chequeId,
    required int expectedVersion,
    required YorksV1RentalChequeStatus nextStatus,
    required String? reason,
    required String idempotencyKey,
  }) async {
    calls.add({
      'status': nextStatus.name,
      'reason': reason,
      'key': idempotencyKey,
    });
    if (pending != null) await pending!.future;
    if (committedKeys.add(idempotencyKey)) {
      status = nextStatus;
      version++;
    }
    if (loseNextResponse) {
      loseNextResponse = false;
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected repository call: ${invocation.memberName}',
  );
}

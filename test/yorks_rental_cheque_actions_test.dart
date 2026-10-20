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
    'new cheque stays open and locked until the exact uncertain request is confirmed',
    (tester) async {
      final repository = _ChequeRepository(YorksV1RentalChequeStatus.scheduled)
        ..pending = Completer<void>()
        ..loseNextSaveResponse = true;
      await _openCheques(tester, repository);
      await _newCheque(tester);
      await tester.tap(find.widgetWithText(PrimaryButton, 'Add cheque').last);
      await tester.pump();
      expect(repository.saves, hasLength(1));
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == 'Close',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Add CDC / PDC Cheque'), findsOneWidget);
      repository.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Confirm cheque'), findsOneWidget);
      expect(find.text('NEW-002'), findsOneWidget);
      final frozen = find.ancestor(
        of: find.widgetWithText(TextFormField, 'Cheque No.'),
        matching: find.byWidgetPredicate(
          (widget) => widget is AbsorbPointer && widget.absorbing,
        ),
      );
      expect(tester.widget<AbsorbPointer>(frozen).absorbing, isTrue);
      repository.saveFailure = const YorksV1DomainException(
        YorksV1DomainErrorCode.offline,
      );
      await tester.tap(find.text('Confirm cheque'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm cheque'), findsOneWidget);
      expect(tester.widget<AbsorbPointer>(frozen).absorbing, isTrue);
      repository.saveFailure = null;
      await tester.tap(find.text('Confirm cheque'));
      await tester.pumpAndSettle();
      expect(find.text('Add CDC / PDC Cheque'), findsNothing);
      expect(repository.saves, hasLength(3));
      expect(repository.saves.map((save) => save['key']).toSet(), hasLength(1));
      expect(
        repository.saves.first['payload'],
        repository.saves.last['payload'],
      );
      expect(repository.savedKeys, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rejected cheque keeps entries and allows a corrected attempt', (
    tester,
  ) async {
    final repository = _ChequeRepository(YorksV1RentalChequeStatus.scheduled)
      ..saveFailure = const YorksV1DomainException(
        YorksV1DomainErrorCode.invalidInput,
      );
    await _openCheques(tester, repository);
    await _newCheque(tester);
    await tester.tap(find.widgetWithText(PrimaryButton, 'Add cheque').last);
    await tester.pumpAndSettle();
    expect(find.text('NEW-002'), findsOneWidget);
    expect(find.textContaining('The cheque was rejected.'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Cheque No.'),
      'CORRECTED-003',
    );
    repository.saveFailure = null;
    await tester.tap(find.widgetWithText(PrimaryButton, 'Add cheque').last);
    await tester.pumpAndSettle();
    expect(repository.saves.last['key'], isNot(repository.saves.first['key']));
    expect(
      (repository.saves.last['payload'] as Map)['cheque_number'],
      'CORRECTED-003',
    );
    expect(repository.savedKeys, hasLength(1));
  });

  testWidgets('nonfinite cheque amounts never reach the repository', (
    tester,
  ) async {
    final repository = _ChequeRepository(YorksV1RentalChequeStatus.scheduled);
    await _openCheques(tester, repository);
    await _newCheque(tester);
    for (final invalid in ['NaN', 'Infinity', '1e999']) {
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount (AED)'),
        invalid,
      );
      await tester.tap(find.widgetWithText(PrimaryButton, 'Add cheque').last);
      await tester.pumpAndSettle();
      expect(repository.saves, isEmpty, reason: invalid);
      expect(find.text('Add CDC / PDC Cheque'), findsOneWidget);
    }
  });

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
      repository.transitionFailure = const YorksV1DomainException(
        YorksV1DomainErrorCode.offline,
      );
      await tester.tap(find.text('Confirm status change'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm status change'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Change reason'),
            )
            .enabled,
        isFalse,
      );
      repository.transitionFailure = null;
      await tester.tap(find.text('Confirm status change'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(repository.calls, hasLength(3));
      expect(repository.calls.map((call) => call['key']).toSet(), hasLength(1));
      expect(repository.calls.last['reason'], 'Bank returned the cheque');
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

Future<void> _newCheque(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(PrimaryButton, 'Add cheque'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Cheque No.'),
    'NEW-002',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Bank'),
    'Example Bank',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Amount (AED)'),
    '250',
  );
}

class _ChequeRepository implements YorksV1RentalRepository {
  _ChequeRepository(this.status);
  YorksV1RentalChequeStatus status;
  bool archived = false;
  bool loseNextResponse = false;
  bool loseNextSaveResponse = false;
  Object? saveFailure;
  Object? transitionFailure;
  Completer<void>? pending;
  final calls = <Map<String, Object?>>[];
  final saves = <Map<String, Object?>>[];
  final savedKeys = <String>{};
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
    if (transitionFailure != null) throw transitionFailure!;
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
  Future<void> saveCheque({
    required Map<String, Object?> payload,
    required int? expectedVersion,
    required String idempotencyKey,
  }) async {
    saves.add({'payload': payload, 'key': idempotencyKey});
    if (pending != null) await pending!.future;
    if (saveFailure != null) throw saveFailure!;
    savedKeys.add(idempotencyKey);
    if (loseNextSaveResponse) {
      loseNextSaveResponse = false;
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/widgets/widgets.dart';
import 'package:material_ledger/features/rentals/presentation/screens/yorks_v1_rental_screens.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_rental.dart';
import 'package:material_ledger/shared/providers/yorks_v1_rental_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_rental_repository.dart';

void main() {
  Future<void> openPayment(
    WidgetTester tester,
    _PaymentRepository repository,
  ) async {
    tester.view.physicalSize = const Size(1366, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          yorksV1RentalRepositoryProvider.overrideWithValue(repository),
          yorksV1RentalCommandActorProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(
          home: YorksV1RentalPropertyScreen(propertyId: 'payment-property'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rent Schedule'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record payment'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Amount Received (AED)'), '25.50');
    await tester.enterText(
      field('Receipt / Bank / Cheque Reference'),
      'BANK-25',
    );
    await tester.enterText(field('Payment Note'), 'Part receipt');
  }

  Future<void> submit(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label).last);
    await tester.tap(find.text(label).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
  }

  testWidgets('payment dialog closes only after the server confirms receipt', (
    tester,
  ) async {
    final repository = _PaymentRepository(1);
    await openPayment(tester, repository);
    await submit(tester, 'Record payment');

    expect(repository.calls, hasLength(1));
    expect(repository.calls.single.amount, 25.50);
    expect(repository.calls.single.method, 'bank_transfer');
    expect(find.text('Record Rent Payment'), findsOneWidget);
    expect(find.text('Rent payment recorded.'), findsNothing);

    repository.responses.single.complete();
    await tester.pumpAndSettle();
    expect(find.text('Record Rent Payment'), findsNothing);
    expect(find.text('Rent payment recorded.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'lost response then offline keeps frozen input and retries the same payment key',
    (tester) async {
      final repository = _PaymentRepository(3);
      await openPayment(tester, repository);
      await submit(tester, 'Record payment');
      final original = repository.calls.single;
      repository.responses[0].completeError(
        YorksV1DomainException(
          YorksV1DomainErrorCode.backendUnavailable,
          cause: TimeoutException('Response lost after possible commit'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Confirm payment'), findsOneWidget);
      expect(find.textContaining('could not be confirmed'), findsOneWidget);
      expect(_text(tester, 'Amount Received (AED)'), '25.50');
      expect(_text(tester, 'Receipt / Bank / Cheque Reference'), 'BANK-25');
      expect(_text(tester, 'Payment Note'), 'Part receipt');
      expect(_frozen(tester), isTrue);
      expect(find.text('Rent payment recorded.'), findsNothing);

      await submit(tester, 'Confirm payment');
      expect(repository.calls, hasLength(2));
      expect(repository.calls[1].key, original.key);
      expect(repository.calls[1].payload, original.payload);
      repository.responses[1].completeError(
        const YorksV1DomainException(YorksV1DomainErrorCode.offline),
      );
      await tester.pumpAndSettle();

      expect(find.text('Confirm payment'), findsOneWidget);
      expect(_frozen(tester), isTrue);
      expect(_text(tester, 'Amount Received (AED)'), '25.50');
      expect(find.text('Record Rent Payment'), findsOneWidget);
      expect(find.text('Rent payment recorded.'), findsNothing);

      await submit(tester, 'Confirm payment');
      expect(repository.calls, hasLength(3));
      expect(repository.calls[2].key, original.key);
      expect(repository.calls[2].payload, original.payload);
      repository.responses[2].complete();
      await tester.pumpAndSettle();
      expect(find.text('Record Rent Payment'), findsNothing);
      expect(find.text('Rent payment recorded.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'busy payment blocks another submission, close, cancel and Back',
    (tester) async {
      final repository = _PaymentRepository(1);
      await openPayment(tester, repository);
      await submit(tester, 'Record payment');

      final primary = tester.widget<PrimaryButton>(
        find.widgetWithText(PrimaryButton, 'Saving…'),
      );
      final cancel = tester.widget<SecondaryButton>(
        find.widgetWithText(SecondaryButton, 'Cancel'),
      );
      final close = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Close',
        ),
      );
      expect(primary.onPressed, isNull);
      expect(cancel.onPressed, isNull);
      expect(close.onPressed, isNull);
      expect(_frozen(tester), isTrue);
      await tester.tap(find.text('Saving…'), warnIfMissed: false);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(repository.calls, hasLength(1));
      expect(find.text('Record Rent Payment'), findsOneWidget);

      repository.responses.single.complete();
      await tester.pumpAndSettle();
      expect(find.text('Record Rent Payment'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

String _text(WidgetTester tester, String label) =>
    tester.widget<TextField>(field(label)).controller!.text;

bool _frozen(WidgetTester tester) => tester
    .widgetList<AbsorbPointer>(
      find.ancestor(
        of: field('Amount Received (AED)'),
        matching: find.byType(AbsorbPointer),
      ),
    )
    .any((widget) => widget.absorbing);

final _detail = YorksV1RentalPropertyDetail.fromJson({
  'property': {
    'id': 'payment-property',
    'unit_code': 'PAY-01',
    'property_name': 'Payment fixture',
    'property_type': 'shop',
    'location': 'Dubai',
    'occupancy_state': 'occupied',
    'record_version': 1,
  },
  'lease': {
    'id': 'payment-lease',
    'tenant_name': 'Fixture tenant',
    'contract_number': 'PAY-CONTRACT',
    'contract_status': 'active',
    'payment_frequency': 'monthly',
    'monthly_rent': 100,
  },
  'periods': [
    {
      'id': 'payment-period',
      'period_month': '2026-10-01',
      'due_date': '2026-10-01',
      'amount_due': 100,
      'amount_paid': 0,
      'balance': 100,
      'status': 'due',
    },
  ],
});

class _PaymentCall {
  const _PaymentCall(this.key, this.payload);
  final String key;
  final Map<String, Object?> payload;
  double get amount => payload['amount']! as double;
  String get method => payload['method']! as String;
}

class _PaymentRepository implements YorksV1RentalRepository {
  _PaymentRepository(int attempts)
    : responses = List.generate(attempts, (_) => Completer<void>());
  final List<Completer<void>> responses;
  final calls = <_PaymentCall>[];

  @override
  Future<YorksV1RentalPropertyDetail> getProperty(String propertyId) async =>
      _detail;

  @override
  Future<void> recordPayment({
    required String periodId,
    required double amount,
    required DateTime paymentDate,
    required String paymentMethod,
    required String? reference,
    required String? note,
    required String idempotencyKey,
  }) {
    calls.add(
      _PaymentCall(idempotencyKey, {
        'period': periodId,
        'amount': amount,
        'date': paymentDate,
        'method': paymentMethod,
        'reference': reference,
        'note': note,
      }),
    );
    return responses[calls.length - 1].future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

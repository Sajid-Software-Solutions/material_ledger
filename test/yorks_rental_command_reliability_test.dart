import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_rental.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_rental_workbook.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_rental_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_material_request_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_rental_repository.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets(
    'visible rental reads refresh and stop when the screen unmounts',
    (tester) async {
      final repository = _CommandRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1RentalRepositoryProvider.overrideWithValue(repository),
          ],
          child: Consumer(
            builder: (context, ref, child) {
              ref.watch(yorksV1RentalPortfolioProvider);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pump();
      expect(repository.portfolioReads, 1);
      await tester.pump(const Duration(minutes: 1));
      await tester.pump();
      expect(repository.portfolioReads, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 1));
      expect(repository.portfolioReads, 2);
    },
  );

  ProviderContainer containerFor(
    _CommandRepository repository, {
    String actor = 'actor-a',
  }) {
    final container = ProviderContainer(
      overrides: [
        yorksV1RentalRepositoryProvider.overrideWithValue(repository),
        yorksV1RentalCommandActorProvider.overrideWithValue(actor),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    container.listen(yorksV1RentalCommandProvider, (_, _) {});
    return container;
  }

  Future<bool> pay(
    ProviderContainer container, {
    double amount = 40,
    String method = 'Cash',
    String? note,
  }) => container
      .read(yorksV1RentalCommandProvider.notifier)
      .recordPayment(
        propertyId: 'property',
        periodId: 'period',
        amount: amount,
        paymentDate: DateTime(2026, 10, 20),
        paymentMethod: method,
        note: note,
      );

  test(
    'UI payment labels and cheque choices produce accepted RPC tokens',
    () async {
      final rpc = _RecordingRpc();
      final connectivity = DefaultConnectivity();
      addTearDown(connectivity.dispose);
      final repository = YorksV1SupabaseRentalRepository(
        featureFlags: const YorksV1FeatureFlags(foundation: true),
        connectivity: connectivity,
        rpcClient: rpc,
      );
      for (final entry in {
        'Cash': 'cash',
        'Bank Transfer': 'bank_transfer',
        'PDC': 'pdc',
        'CDC': 'cdc',
        'Cheque': 'other',
        'Other': 'other',
      }.entries) {
        await repository.recordPayment(
          periodId: 'period',
          amount: 10,
          paymentDate: DateTime(2026, 10, 20),
          paymentMethod: entry.key,
          reference: 'reference',
          note: null,
          idempotencyKey: 'key',
        );
        expect(rpc.parameters.last['p_payment_method'], entry.value);
      }
      await repository.saveCheque(
        payload: {'cheque_type': 'PDC'},
        expectedVersion: null,
        idempotencyKey: 'cheque-key',
      );
      expect((rpc.parameters.last['p_payload'] as Map)['cheque_type'], 'pdc');
      final before = rpc.parameters.length;
      await expectLater(
        repository.saveCheque(
          payload: {'cheque_type': 'unknown'},
          expectedVersion: null,
          idempotencyKey: 'bad',
        ),
        throwsA(isA<YorksV1DomainException>()),
      );
      expect(rpc.parameters.length, before);
      for (final resolution in YorksV1RentalIntentResolution.values) {
        rpc.response = {'state': resolution.name};
        expect(
          await repository.settleCommandIntent(
            commandName: 'v1_record_rent_payment',
            idempotencyKey: 'pending-key',
          ),
          resolution,
        );
        expect(rpc.parameters.last, {
          'p_command_name': 'v1_record_rent_payment',
          'p_idempotency_key': 'pending-key',
        });
      }
      rpc.response = {'state': 'unconfirmed'};
      await expectLater(
        repository.settleCommandIntent(
          commandName: 'v1_record_rent_payment',
          idempotencyKey: 'pending-key',
        ),
        throwsA(
          isA<YorksV1DomainException>().having(
            (error) => error.code,
            'code',
            YorksV1DomainErrorCode.unexpectedResponse,
          ),
        ),
      );
    },
  );

  test(
    'uncertain exact retries retain one key across normalized UI labels',
    () async {
      final repository = _CommandRepository()..failure = _uncertain;
      final container = containerFor(repository);
      addTearDown(container.dispose);
      expect(await pay(container), false);
      expect(prefs.getKeys(), hasLength(1));
      repository.failure = null;
      expect(await pay(container, method: 'cash'), true);
      expect(repository.keys, hasLength(2));
      expect(repository.keys.first, repository.keys.last);
      expect(repository.methods, ['cash', 'cash']);
      expect(prefs.getKeys(), isEmpty);
    },
  );

  test(
    'changed payment data cannot bypass an unresolved per-period intent',
    () async {
      final repository = _CommandRepository()..failure = _uncertain;
      final container = containerFor(repository);
      addTearDown(container.dispose);
      expect(await pay(container), false);
      expect(await pay(container, note: 'changed note'), false);
      expect(repository.keys, hasLength(1));
      final error = container.read(yorksV1RentalCommandProvider).error;
      expect(
        error,
        isA<YorksV1DomainException>().having(
          (e) => e.code,
          'code',
          YorksV1DomainErrorCode.conflict,
        ),
      );
      expect(prefs.getKeys(), hasLength(1));
    },
  );

  test(
    'the persisted fence survives controller disposal and exact retry',
    () async {
      final repository = _CommandRepository()..failure = _uncertain;
      final first = containerFor(repository);
      expect(await pay(first), false);
      first.dispose();
      final restored = containerFor(repository);
      addTearDown(restored.dispose);
      expect(await pay(restored, amount: 25), false);
      expect(repository.keys, hasLength(1));
      repository.failure = null;
      expect(await pay(restored), true);
      expect(repository.keys.first, repository.keys.last);
    },
  );

  test(
    'confirmed recovery stops before a changed payment can become an additional charge',
    () async {
      final repository = _CommandRepository()..failure = _uncertain;
      final container = containerFor(repository);
      addTearDown(container.dispose);
      expect(await pay(container), false);
      final original = repository.keys.single;
      repository
        ..failure = null
        ..confirmed = true;
      expect(await pay(container, amount: 25), false);
      expect(repository.keys, [original]);
      final controller = container.read(yorksV1RentalCommandProvider.notifier);
      expect(
        await controller.settlePendingCommand(
          controller.pendingCommands.single,
        ),
        YorksV1RentalIntentResolution.confirmed,
      );
      expect(repository.keys, [original]);
      expect(prefs.getKeys(), isEmpty);
      expect(await pay(container, amount: 25), true);
      expect(repository.keys.last, isNot(original));
      expect(prefs.getKeys(), isEmpty);
    },
  );

  test(
    'a restarted client can explicitly abandon an uncommitted request without its lost payload',
    () async {
      final repository = _CommandRepository()..failure = _uncertain;
      final first = containerFor(repository);
      expect(await pay(first, amount: 71, note: 'private tenant note'), false);
      final oldKey = repository.keys.single;
      expect(
        prefs.getString(prefs.getKeys().single),
        isNot(contains('private tenant note')),
      );
      first.dispose();
      final restarted = containerFor(repository);
      addTearDown(restarted.dispose);
      final controller = restarted.read(yorksV1RentalCommandProvider.notifier);
      expect(controller.pendingCommands.single.idempotencyKey, oldKey);
      expect(await pay(restarted, amount: 25), false);
      repository.failure = null;
      expect(
        await controller.settlePendingCommand(
          controller.pendingCommands.single,
        ),
        YorksV1RentalIntentResolution.abandoned,
      );
      expect(repository.keys, [oldKey]);
      expect(prefs.getKeys(), isEmpty);
      expect(await pay(restarted, amount: 25), true);
      expect(repository.keys.last, isNot(oldKey));
    },
  );

  test(
    'another actor cannot settle the previous actor pending action',
    () async {
      final repository = _CommandRepository()..failure = _uncertain;
      final first = containerFor(repository);
      addTearDown(first.dispose);
      expect(await pay(first), false);
      final pending = first
          .read(yorksV1RentalCommandProvider.notifier)
          .pendingCommands
          .single;
      final second = containerFor(repository, actor: 'actor-b');
      addTearDown(second.dispose);
      final controller = second.read(yorksV1RentalCommandProvider.notifier);
      expect(controller.pendingCommands, isEmpty);
      expect(await controller.settlePendingCommand(pending), isNull);
      expect(repository.settledKeys, isEmpty);
      expect(prefs.getKeys(), hasLength(1));
    },
  );

  test(
    'property save and workbook import retain the first command key after restart',
    () async {
      final repository = _CommandRepository()..failure = _uncertain;
      final first = containerFor(repository);
      expect(
        await first
            .read(yorksV1RentalCommandProvider.notifier)
            .saveProperty(
              _propertyInput,
              expectedVersion: null,
              idempotencyKey: 'initial-property-key',
            ),
        isNull,
      );
      expect(
        await first
            .read(yorksV1RentalCommandProvider.notifier)
            .importWorkbook(_preview('initial-import-key')),
        false,
      );
      first.dispose();
      final restarted = containerFor(repository);
      addTearDown(restarted.dispose);
      repository.failure = null;
      final controller = restarted.read(yorksV1RentalCommandProvider.notifier);
      expect(controller.pendingCommands, hasLength(2));
      expect(
        await controller.saveProperty(
          _propertyInput,
          expectedVersion: null,
          idempotencyKey: 'new-dialog-key',
        ),
        'property',
      );
      expect(
        await controller.importWorkbook(_preview('new-preview-key')),
        true,
      );
      expect(repository.propertyKeys, [
        'initial-property-key',
        'initial-property-key',
      ]);
      expect(repository.importKeys, [
        'initial-import-key',
        'initial-import-key',
      ]);
      expect(prefs.getKeys(), isEmpty);
    },
  );

  test(
    'disposed controllers preserve uncertain references without late state writes',
    () async {
      final repository = _CommandRepository()
        ..pendingPayment = Completer<void>();
      final container = containerFor(repository);
      final payment = pay(container);
      await Future<void>.delayed(Duration.zero);
      container.dispose();
      repository.pendingPayment!.complete();
      expect(await payment, false);
      expect(prefs.getKeys(), hasLength(1));
    },
  );

  test(
    'changing actor while intent persistence is pending prevents the request',
    () async {
      final actorState = StateProvider<String>((ref) => 'actor-a');
      final repository = _CommandRepository();
      final container = ProviderContainer(
        overrides: [
          yorksV1RentalRepositoryProvider.overrideWithValue(repository),
          yorksV1RentalCommandActorProvider.overrideWith(
            (ref) => ref.watch(actorState),
          ),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);
      container.listen(yorksV1RentalCommandProvider, (_, _) {});
      final payment = pay(container);
      container.read(actorState.notifier).state = 'actor-b';
      expect(await payment, false);
      expect(repository.keys, isEmpty);
      expect(prefs.getKeys(), isEmpty);
    },
  );

  test(
    'changing actor during a request preserves the original actor fence',
    () async {
      final actorState = StateProvider<String>((ref) => 'actor-a');
      final repository = _CommandRepository()
        ..pendingPayment = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          yorksV1RentalRepositoryProvider.overrideWithValue(repository),
          yorksV1RentalCommandActorProvider.overrideWith(
            (ref) => ref.watch(actorState),
          ),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);
      container.listen(yorksV1RentalCommandProvider, (_, _) {});
      final payment = pay(container);
      await Future<void>.delayed(Duration.zero);
      expect(repository.keys, hasLength(1));
      container.read(actorState.notifier).state = 'actor-b';
      repository.pendingPayment!.complete();
      expect(await payment, false);
      expect(prefs.getKeys().single, contains('actor-a'));
      expect(
        container.read(yorksV1RentalCommandProvider.notifier).pendingCommands,
        isEmpty,
      );
      container.read(actorState.notifier).state = 'actor-a';
      expect(
        container
            .read(yorksV1RentalCommandProvider.notifier)
            .pendingCommands
            .single
            .idempotencyKey,
        repository.keys.single,
      );
    },
  );

  test(
    'settlement responses from a changed session cannot clear the original actor fence',
    () async {
      final actorState = StateProvider<String>((ref) => 'actor-a');
      final repository = _CommandRepository()..failure = _uncertain;
      final container = ProviderContainer(
        overrides: [
          yorksV1RentalRepositoryProvider.overrideWithValue(repository),
          yorksV1RentalCommandActorProvider.overrideWith(
            (ref) => ref.watch(actorState),
          ),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);
      container.listen(yorksV1RentalCommandProvider, (_, _) {});
      expect(await pay(container), false);
      repository
        ..failure = null
        ..pendingSettlement = Completer<void>();
      final controller = container.read(yorksV1RentalCommandProvider.notifier);
      final settlement = controller.settlePendingCommand(
        controller.pendingCommands.single,
      );
      await Future<void>.delayed(Duration.zero);
      container.read(actorState.notifier).state = 'actor-b';
      repository.pendingSettlement!.complete();
      expect(await settlement, isNull);
      expect(prefs.getKeys().single, contains('actor-a'));
    },
  );

  test(
    'a definitive transaction rejection permits a corrected new attempt',
    () async {
      final repository = _CommandRepository()
        ..failure = const YorksV1DomainException(
          YorksV1DomainErrorCode.invalidInput,
        );
      final container = containerFor(repository);
      addTearDown(container.dispose);
      expect(await pay(container), false);
      expect(prefs.getKeys(), isEmpty);
      repository.failure = null;
      expect(await pay(container, amount: 25), true);
      expect(repository.keys.first, isNot(repository.keys.last));
    },
  );

  test('another actor never reuses or clears the first actor intent', () async {
    final repository = _CommandRepository()..failure = _uncertain;
    final first = containerFor(repository);
    addTearDown(first.dispose);
    expect(await pay(first), false);
    final original = repository.keys.single;
    repository.failure = null;
    final second = containerFor(repository, actor: 'actor-b');
    addTearDown(second.dispose);
    expect(await pay(second), true);
    expect(repository.keys.last, isNot(original));
    expect(prefs.getKeys(), hasLength(1));
    expect(prefs.getKeys().single, contains('actor-a'));
  });

  test(
    'loss of access during exact recovery retains the prior uncertain fence',
    () async {
      final repository = _CommandRepository()..failure = _uncertain;
      final container = containerFor(repository);
      addTearDown(container.dispose);
      expect(await pay(container), false);
      repository.failure = const YorksV1DomainException(
        YorksV1DomainErrorCode.unauthorized,
      );
      expect(await pay(container), false);
      expect(prefs.getKeys(), hasLength(1));
      expect(repository.keys.first, repository.keys.last);
    },
  );

  test(
    'a rejected retry cannot release an earlier request that may still be running',
    () async {
      final repository = _CommandRepository()..failure = _uncertain;
      final container = containerFor(repository);
      addTearDown(container.dispose);
      expect(await pay(container), false);
      final key = repository.keys.single;
      repository.failure = const YorksV1DomainException(
        YorksV1DomainErrorCode.conflict,
        serverCode: '55P03',
      );
      expect(await pay(container), false);
      expect(prefs.getKeys(), hasLength(1));
      repository.failure = null;
      expect(await pay(container, amount: 25), false);
      expect(repository.keys, [key, key]);
      final controller = container.read(yorksV1RentalCommandProvider.notifier);
      expect(
        await controller.settlePendingCommand(
          controller.pendingCommands.single,
        ),
        YorksV1RentalIntentResolution.abandoned,
      );
      expect(await pay(container, amount: 25), true);
      expect(repository.keys.last, isNot(key));
    },
  );
}

const _uncertain = YorksV1DomainException(
  YorksV1DomainErrorCode.backendUnavailable,
);

class _CommandRepository
    implements
        YorksV1RentalRepository,
        YorksV1RentalCommandOutcomeRepository,
        YorksV1RentalCommandRecoveryRepository {
  Object? failure;
  int portfolioReads = 0;
  @override
  Future<YorksV1RentalPortfolio> getPortfolio() async {
    portfolioReads++;
    return YorksV1RentalPortfolio.fromJson(const {
      'summary': {},
      'properties': [],
      'recent_payments': [],
      'cheques': [],
    });
  }

  bool confirmed = false;
  final keys = <String>[];
  final methods = <String>[];
  final outcomeKeys = <String>[];
  final settledKeys = <String>[];
  final propertyKeys = <String>[];
  final importKeys = <String>[];
  Completer<void>? pendingPayment;
  Completer<void>? pendingSettlement;
  @override
  Future<void> recordPayment({
    required String periodId,
    required double amount,
    required DateTime paymentDate,
    required String paymentMethod,
    required String? reference,
    required String? note,
    required String idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    methods.add(paymentMethod);
    if (pendingPayment != null) await pendingPayment!.future;
    final error = failure;
    if (error != null) throw error;
  }

  @override
  Future<String> saveProperty(
    YorksV1RentalPropertyInput input, {
    required int? expectedVersion,
    required String idempotencyKey,
  }) async {
    propertyKeys.add(idempotencyKey);
    if (failure != null) throw failure!;
    return 'property';
  }

  @override
  Future<void> importWorkbook({
    required Map<String, Object?> payload,
    required String idempotencyKey,
  }) async {
    importKeys.add(idempotencyKey);
    if (failure != null) throw failure!;
  }

  @override
  Future<YorksV1RentalIntentResolution> settleCommandIntent({
    required String commandName,
    required String idempotencyKey,
  }) async {
    settledKeys.add(idempotencyKey);
    if (pendingSettlement != null) await pendingSettlement!.future;
    if (failure != null) throw failure!;
    return confirmed
        ? YorksV1RentalIntentResolution.confirmed
        : YorksV1RentalIntentResolution.abandoned;
  }

  @override
  Future<bool> wasCommandConfirmed({
    required String commandName,
    required String idempotencyKey,
  }) async {
    outcomeKeys.add(idempotencyKey);
    return confirmed;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

YorksV1RentalImportPreview _preview(String key) => YorksV1RentalImportPreview(
  fileName: 'source.xlsx',
  commandId: key,
  properties: const [
    YorksV1RentalImportRow(
      sheet: 'Rental Properties',
      rowNumber: 4,
      action: 'create',
      label: 'SHOP-1',
      payload: {'unit_code': 'SHOP-1'},
    ),
  ],
  payments: const [],
  cheques: const [],
  issues: const [],
);

const _propertyInput = YorksV1RentalPropertyInput(
  unitCode: 'SHOP-1',
  propertyName: 'Example Shop',
  propertyType: 'shop',
  location: '',
  occupancy: YorksV1RentalOccupancy.unknown,
  contractNumber: '',
  contractType: 'tenancy_contract',
  contractStatus: 'draft',
  monthlyRent: null,
  annualRent: 12000,
  securityDeposit: 0,
  monthlyDueDay: 1,
  gracePeriodDays: 5,
  defaultPaymentMethod: 'bank_transfer',
  paymentFrequency: 'annual',
  contractCheques: 0,
  annualEscalationPercent: 0,
  renewalNoticeDays: 90,
);

class _RecordingRpc implements YorksV1MaterialRequestRpcClient {
  final parameters = <Map<String, Object?>>[];
  Object? response = <String, Object?>{};
  @override
  Future<Object?> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async {
    this.parameters.add(parameters);
    return response;
  }
}

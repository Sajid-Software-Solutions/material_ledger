import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_rental.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
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
    'actor-scoped confirmed outcome releases a prior uncertain fence safely',
    () async {
      final repository = _CommandRepository()..failure = _uncertain;
      final container = containerFor(repository);
      addTearDown(container.dispose);
      expect(await pay(container), false);
      final original = repository.keys.single;
      repository
        ..failure = null
        ..confirmed = true;
      expect(await pay(container, amount: 25), true);
      expect(repository.outcomeKeys, [original]);
      expect(repository.keys.last, isNot(original));
      expect(prefs.getKeys(), isEmpty);
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
}

const _uncertain = YorksV1DomainException(
  YorksV1DomainErrorCode.backendUnavailable,
);

class _CommandRepository
    implements YorksV1RentalRepository, YorksV1RentalCommandOutcomeRepository {
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
    final error = failure;
    if (error != null) throw error;
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

class _RecordingRpc implements YorksV1MaterialRequestRpcClient {
  final parameters = <Map<String, Object?>>[];
  @override
  Future<Object?> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async {
    this.parameters.add(parameters);
    return <String, Object?>{};
  }
}

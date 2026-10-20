import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/yorks_v1_rental.dart';
import '../models/yorks_v1_domain_error.dart';
import '../models/yorks_v1_rental_workbook.dart';
import '../repositories/yorks_v1_material_request_repository.dart';
import '../repositories/yorks_v1_rental_repository.dart';
import '../services/yorks_v1_rental_workbook_service.dart';
import '../sync/connectivity_service.dart';
import 'language_provider.dart';
import 'session_provider.dart';
import 'yorks_v1_feature_flags_provider.dart';

final yorksV1RentalRpcClientProvider =
    Provider<YorksV1MaterialRequestRpcClient?>((ref) {
      final client = ref.watch(supabaseClientProvider);
      return client == null
          ? null
          : SupabaseYorksV1MaterialRequestRpcClient(client);
    });

final yorksV1RentalRepositoryProvider = Provider<YorksV1RentalRepository>((
  ref,
) {
  return YorksV1SupabaseRentalRepository(
    featureFlags: ref.watch(yorksV1FeatureFlagsProvider),
    connectivity: ref.watch(connectivityProvider),
    rpcClient: ref.watch(yorksV1RentalRpcClientProvider),
  );
});

final yorksV1RentalWorkbookFileServiceProvider =
    Provider<YorksV1RentalWorkbookFileService>(
      (ref) => const YorksV1PlatformRentalWorkbookFileService(),
    );

final yorksV1RentalWorkbookCodecProvider = Provider<YorksV1RentalWorkbookCodec>(
  (ref) => const YorksV1RentalWorkbookCodec(),
);

final yorksV1RentalPortfolioProvider =
    FutureProvider.autoDispose<YorksV1RentalPortfolio>((ref) {
      ref.watch(authSessionRevisionProvider);
      final repository = ref.watch(yorksV1RentalRepositoryProvider);
      return _readRentalWithRefresh(ref, repository.getPortfolio);
    });

final yorksV1RentalPropertyProvider = FutureProvider.autoDispose
    .family<YorksV1RentalPropertyDetail, String>((ref, propertyId) {
      ref.watch(authSessionRevisionProvider);
      final repository = ref.watch(yorksV1RentalRepositoryProvider);
      return _readRentalWithRefresh(
        ref,
        () => repository.getProperty(propertyId),
      );
    });

Future<T> _readRentalWithRefresh<T>(Ref ref, Future<T> Function() read) {
  Timer? refresh;
  var active = true;
  var disposed = false;
  var loaded = false;
  void schedule() {
    refresh?.cancel();
    if (active && loaded && !disposed) {
      refresh = Timer(const Duration(minutes: 1), ref.invalidateSelf);
    }
  }

  ref.onCancel(() {
    active = false;
    refresh?.cancel();
  });
  ref.onResume(() {
    active = true;
    schedule();
  });
  ref.onDispose(() {
    disposed = true;
    refresh?.cancel();
  });
  return read().then((value) {
    loaded = true;
    schedule();
    return value;
  });
}

final yorksV1RentalCommandActorProvider = Provider<String?>((ref) {
  ref.watch(authSessionRevisionProvider);
  return ref.watch(supabaseClientProvider)?.auth.currentUser?.id;
});

final yorksV1RentalCommandProvider =
    StateNotifierProvider.autoDispose<
      YorksV1RentalCommandController,
      AsyncValue<void>
    >((ref) => YorksV1RentalCommandController(ref));

class YorksV1RentalCommandController extends StateNotifier<AsyncValue<void>> {
  YorksV1RentalCommandController(this._ref)
    : super(const AsyncValue.data(null));

  final Ref _ref;
  static const _uuid = Uuid();
  final Map<String, _RentalCommandIntent> _pendingIntents = {};

  Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  Future<_RentalCommandIntent> _commandIntent(
    YorksV1RentalRepository repository,
    String command,
    String entity,
    Map<String, Object?> payload,
  ) async {
    final actor = _ref.read(yorksV1RentalCommandActorProvider);
    final fingerprint = sha256
        .convert(utf8.encode(jsonEncode(_canonical(payload))))
        .toString();
    final slot = 'yorks.rental.pending.${actor ?? 'local'}.$command.$entity';
    final prefs = actor == null ? null : _ref.read(sharedPreferencesProvider);
    _RentalCommandIntent? previous = _pendingIntents[slot];
    final stored = prefs?.getString(slot);
    if (stored != null) {
      final decoded = jsonDecode(stored);
      if (decoded is! Map ||
          decoded['key'] is! String ||
          decoded['fingerprint'] is! String) {
        throw const YorksV1DomainException(YorksV1DomainErrorCode.conflict);
      }
      previous = _RentalCommandIntent(
        slot,
        decoded['key'] as String,
        decoded['fingerprint'] as String,
        actor != null,
        true,
      );
    }
    if (previous != null && previous.fingerprint != fingerprint) {
      if (repository is YorksV1RentalCommandOutcomeRepository &&
          await (repository as YorksV1RentalCommandOutcomeRepository)
              .wasCommandConfirmed(
                commandName: command,
                idempotencyKey: previous.key,
              )) {
        await _confirmedIntent(previous);
        previous = null;
      } else {
        throw const YorksV1DomainException(YorksV1DomainErrorCode.conflict);
      }
    }
    final intent = _RentalCommandIntent(
      slot,
      previous?.key ?? _uuid.v4(),
      fingerprint,
      actor != null,
      previous != null,
    );
    _pendingIntents[slot] = intent;
    if (prefs != null &&
        !await prefs.setString(
          slot,
          jsonEncode({'key': intent.key, 'fingerprint': fingerprint}),
        )) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
    return intent;
  }

  Future<void> _confirmedIntent(_RentalCommandIntent intent) async {
    if (intent.persistent) {
      final prefs = _ref.read(sharedPreferencesProvider);
      if (!await prefs.remove(intent.slot)) return;
    }
    _pendingIntents.remove(intent.slot);
  }

  bool _definitiveFailure(Object error, _RentalCommandIntent intent) {
    if (error is! YorksV1DomainException) return false;
    if (error.code == YorksV1DomainErrorCode.backendUnavailable ||
        error.code == YorksV1DomainErrorCode.unexpectedResponse) {
      return false;
    }
    // Losing access/connectivity on a retry does not prove the earlier attempt
    // failed. Keep its fence until the original actor can confirm the outcome.
    if (intent.wasExisting &&
        (error.code == YorksV1DomainErrorCode.offline ||
            error.code == YorksV1DomainErrorCode.unauthorized ||
            error.code == YorksV1DomainErrorCode.unauthenticated ||
            error.code == YorksV1DomainErrorCode.featureDisabled)) {
      return false;
    }
    return error.code != YorksV1DomainErrorCode.serverRejected ||
        error.serverCode != null;
  }

  Future<void> _withIntent(
    YorksV1RentalRepository repository,
    String command,
    String entity,
    Map<String, Object?> payload,
    Future<void> Function(String key) operation,
  ) async {
    final intent = await _commandIntent(repository, command, entity, payload);
    try {
      await operation(intent.key);
    } catch (error) {
      if (_definitiveFailure(error, intent)) await _confirmedIntent(intent);
      rethrow;
    }
    await _confirmedIntent(intent);
  }

  Future<String?> saveProperty(
    YorksV1RentalPropertyInput input, {
    required int? expectedVersion,
    required String idempotencyKey,
  }) async {
    if (state.isLoading) return null;
    state = const AsyncValue.loading();
    try {
      final propertyId = await _ref
          .read(yorksV1RentalRepositoryProvider)
          .saveProperty(
            input,
            expectedVersion: expectedVersion,
            idempotencyKey: idempotencyKey,
          );
      _invalidate(propertyId);
      state = const AsyncValue.data(null);
      return propertyId;
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
      return null;
    }
  }

  Future<bool> recordPayment({
    required String propertyId,
    required String periodId,
    required double amount,
    required DateTime paymentDate,
    required String paymentMethod,
    String? reference,
    String? note,
  }) => _run(propertyId, (repository) async {
    final method = yorksV1RentalPaymentMethodWire(paymentMethod);
    await _withIntent(
      repository,
      'v1_record_rent_payment',
      periodId,
      {
        'property': propertyId,
        'period': periodId,
        'amount': amount,
        'date': paymentDate.toIso8601String().split('T').first,
        'method': method,
        'reference': reference,
        'note': note,
      },
      (key) => repository.recordPayment(
        periodId: periodId,
        amount: amount,
        paymentDate: paymentDate,
        paymentMethod: method,
        reference: reference,
        note: note,
        idempotencyKey: key,
      ),
    );
  });

  Future<bool> saveCheque({
    required String propertyId,
    required Map<String, Object?> payload,
    required int? expectedVersion,
  }) => _run(propertyId, (repository) async {
    final wire = yorksV1RentalChequePayloadWire(payload);
    await _withIntent(
      repository,
      'v1_save_rental_cheque',
      payload['cheque_id']?.toString() ?? propertyId,
      {'property': propertyId, 'payload': wire, 'version': expectedVersion},
      (key) => repository.saveCheque(
        payload: wire,
        expectedVersion: expectedVersion,
        idempotencyKey: key,
      ),
    );
  });

  Future<bool> transitionCheque({
    required String propertyId,
    required YorksV1RentalCheque cheque,
    required YorksV1RentalChequeStatus nextStatus,
    String? reason,
  }) => _run(propertyId, (repository) async {
    await _withIntent(
      repository,
      'v1_transition_rental_cheque',
      cheque.id,
      {
        'property': propertyId,
        'cheque': cheque.id,
        'version': cheque.recordVersion,
        'status': nextStatus.name,
        'reason': reason,
      },
      (key) => repository.transitionCheque(
        chequeId: cheque.id,
        expectedVersion: cheque.recordVersion,
        nextStatus: nextStatus,
        reason: reason,
        idempotencyKey: key,
      ),
    );
  });

  Future<bool> archiveProperty({
    required YorksV1RentalProperty property,
    required String reason,
  }) => _run(property.id, (repository) async {
    await _withIntent(
      repository,
      'v1_archive_rental_property',
      property.id,
      {
        'property': property.id,
        'version': property.recordVersion,
        'reason': reason,
      },
      (key) => repository.archiveProperty(
        propertyId: property.id,
        expectedVersion: property.recordVersion,
        reason: reason,
        idempotencyKey: key,
      ),
    );
  });

  Future<bool> importWorkbook(YorksV1RentalImportPreview preview) async {
    if (state.isLoading || !preview.canConfirm) return false;
    state = const AsyncValue.loading();
    try {
      await _ref
          .read(yorksV1RentalRepositoryProvider)
          .importWorkbook(
            payload: preview.toRpcPayload(),
            idempotencyKey: preview.commandId,
          );
      _ref.invalidate(yorksV1RentalPortfolioProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
      return false;
    }
  }

  Future<bool> _run(
    String propertyId,
    Future<void> Function(YorksV1RentalRepository repository) operation,
  ) async {
    if (state.isLoading) return false;
    state = const AsyncValue.loading();
    try {
      await operation(_ref.read(yorksV1RentalRepositoryProvider));
      _invalidate(propertyId);
      state = const AsyncValue.data(null);
      return true;
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
      return false;
    }
  }

  void _invalidate(String propertyId) {
    _ref.invalidate(yorksV1RentalPortfolioProvider);
    _ref.invalidate(yorksV1RentalPropertyProvider(propertyId));
  }
}

class _RentalCommandIntent {
  const _RentalCommandIntent(
    this.slot,
    this.key,
    this.fingerprint,
    this.persistent,
    this.wasExisting,
  );
  final String slot;
  final String key;
  final String fingerprint;
  final bool persistent;
  final bool wasExisting;
}

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

  List<YorksV1RentalPendingCommand> get pendingCommands {
    final actor = _ref.read(yorksV1RentalCommandActorProvider);
    if (actor == null) return const [];
    final prefs = _ref.read(sharedPreferencesProvider);
    final prefix = 'yorks.rental.pending.$actor.';
    final slots = {
      ...prefs.getKeys(),
      ..._pendingIntents.keys,
    }.where((slot) => slot.startsWith(prefix));
    final commands = <YorksV1RentalPendingCommand>[];
    for (final slot in slots) {
      final parts = slot.substring(prefix.length).split('.');
      if (parts.length != 2 ||
          !const {
            'v1_save_rental_property',
            'v1_record_rent_payment',
            'v1_save_rental_cheque',
            'v1_transition_rental_cheque',
            'v1_archive_rental_property',
            'v1_import_rental_workbook',
          }.contains(parts.first)) {
        continue;
      }
      try {
        final stored = prefs.getString(slot);
        final decoded = stored == null ? null : jsonDecode(stored);
        final key = decoded is Map
            ? decoded['key']
            : _pendingIntents[slot]?.key;
        if (key is! String || key.isEmpty) continue;
        commands.add(
          YorksV1RentalPendingCommand(actor, parts[0], parts[1], key),
        );
      } on FormatException {
        /* Invalid local metadata is never submitted as a command. */
      }
    }
    return commands;
  }

  Future<YorksV1RentalIntentResolution?> settlePendingCommand(
    YorksV1RentalPendingCommand pending,
  ) async {
    if (state.isLoading) return null;
    state = const AsyncValue.loading();
    try {
      if (!pendingCommands.any(
        (command) =>
            command.actor == pending.actor &&
            command.commandName == pending.commandName &&
            command.entity == pending.entity &&
            command.idempotencyKey == pending.idempotencyKey,
      )) {
        throw const YorksV1DomainException(YorksV1DomainErrorCode.conflict);
      }
      final repository = _ref.read(yorksV1RentalRepositoryProvider);
      if (repository is! YorksV1RentalCommandRecoveryRepository) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.backendUnavailable,
        );
      }
      final resolution =
          await (repository as YorksV1RentalCommandRecoveryRepository)
              .settleCommandIntent(
                commandName: pending.commandName,
                idempotencyKey: pending.idempotencyKey,
              );
      if (_ref.read(yorksV1RentalCommandActorProvider) != pending.actor) {
        throw const YorksV1DomainException(YorksV1DomainErrorCode.unauthorized);
      }
      await _confirmedIntent(
        _RentalCommandIntent(
          pending.slot,
          pending.idempotencyKey,
          '',
          true,
          true,
        ),
      );
      _ref.invalidate(yorksV1RentalPortfolioProvider);
      _ref.invalidate(yorksV1RentalPropertyProvider);
      if (mounted) state = const AsyncValue.data(null);
      return resolution;
    } catch (error, stack) {
      if (mounted) state = AsyncValue.error(error, stack);
      return null;
    }
  }

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
    Map<String, Object?> payload, {
    String? preferredKey,
  }) async {
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
      // Changed input is not permission to create an additional transaction
      // after a lost response. Explicit recovery must settle the old request,
      // refresh its result and stop before the user submits a new action.
      throw const YorksV1DomainException(YorksV1DomainErrorCode.conflict);
    }
    final intent = _RentalCommandIntent(
      slot,
      previous?.key ?? preferredKey ?? _uuid.v4(),
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
    // A rejected retry (including a lock timeout/conflict) does not establish
    // that the earlier request failed. Only explicit server settlement can
    // safely release an already uncertain command.
    if (intent.wasExisting) return false;
    return error.code != YorksV1DomainErrorCode.serverRejected ||
        error.serverCode != null;
  }

  Future<T> _withIntent<T>(
    YorksV1RentalRepository repository,
    String command,
    String entity,
    Map<String, Object?> payload,
    Future<T> Function(String key) operation, {
    String? preferredKey,
  }) async {
    final actor = _ref.read(yorksV1RentalCommandActorProvider);
    final intent = await _commandIntent(
      repository,
      command,
      entity,
      payload,
      preferredKey: preferredKey,
    );
    late T result;
    try {
      if (_ref.read(yorksV1RentalCommandActorProvider) != actor) {
        throw const YorksV1DomainException(YorksV1DomainErrorCode.unauthorized);
      }
      result = await operation(intent.key);
      if (_ref.read(yorksV1RentalCommandActorProvider) != actor) {
        // The result belongs to the actor that started the request. Preserve
        // its reference for that actor's later review, even if it committed.
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.backendUnavailable,
        );
      }
    } catch (error) {
      if (_definitiveFailure(error, intent)) await _confirmedIntent(intent);
      rethrow;
    }
    await _confirmedIntent(intent);
    return result;
  }

  Future<String?> saveProperty(
    YorksV1RentalPropertyInput input, {
    required int? expectedVersion,
    required String idempotencyKey,
  }) async {
    if (state.isLoading) return null;
    state = const AsyncValue.loading();
    try {
      final repository = _ref.read(yorksV1RentalRepositoryProvider);
      final propertyId = await _withIntent(
        repository,
        'v1_save_rental_property',
        input.propertyId ?? 'new',
        {'payload': input.toRpcPayload(), 'version': expectedVersion},
        (key) => repository.saveProperty(
          input,
          expectedVersion: expectedVersion,
          idempotencyKey: key,
        ),
        preferredKey: idempotencyKey,
      );
      _invalidate(propertyId);
      if (mounted) state = const AsyncValue.data(null);
      return propertyId;
    } catch (error, stack) {
      if (mounted) state = AsyncValue.error(error, stack);
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
      final repository = _ref.read(yorksV1RentalRepositoryProvider);
      final payload = preview.toRpcPayload();
      await _withIntent(
        repository,
        'v1_import_rental_workbook',
        'workbook',
        payload,
        (key) =>
            repository.importWorkbook(payload: payload, idempotencyKey: key),
        preferredKey: preview.commandId,
      );
      _ref.invalidate(yorksV1RentalPortfolioProvider);
      if (mounted) state = const AsyncValue.data(null);
      return true;
    } catch (error, stack) {
      if (mounted) state = AsyncValue.error(error, stack);
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
      if (mounted) state = const AsyncValue.data(null);
      return true;
    } catch (error, stack) {
      if (mounted) state = AsyncValue.error(error, stack);
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

class YorksV1RentalPendingCommand {
  const YorksV1RentalPendingCommand(
    this.actor,
    this.commandName,
    this.entity,
    this.idempotencyKey,
  );
  final String actor;
  final String commandName;
  final String entity;
  final String idempotencyKey;
  String get slot => 'yorks.rental.pending.$actor.$commandName.$entity';
}

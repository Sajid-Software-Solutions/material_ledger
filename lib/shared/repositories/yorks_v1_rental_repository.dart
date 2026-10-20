import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/yorks_v1_domain_error.dart';
import '../models/yorks_v1_feature_flags.dart';
import '../models/yorks_v1_rental.dart';
import '../sync/connectivity_service.dart';
import 'yorks_v1_material_request_repository.dart';

abstract interface class YorksV1RentalRepository {
  Future<YorksV1RentalPortfolio> getPortfolio();

  Future<YorksV1RentalPropertyDetail> getProperty(String propertyId);

  Future<String> saveProperty(
    YorksV1RentalPropertyInput input, {
    required int? expectedVersion,
    required String idempotencyKey,
  });

  Future<void> recordPayment({
    required String periodId,
    required double amount,
    required DateTime paymentDate,
    required String paymentMethod,
    required String? reference,
    required String? note,
    required String idempotencyKey,
  });

  Future<void> saveCheque({
    required Map<String, Object?> payload,
    required int? expectedVersion,
    required String idempotencyKey,
  });

  Future<void> transitionCheque({
    required String chequeId,
    required int expectedVersion,
    required YorksV1RentalChequeStatus nextStatus,
    required String? reason,
    required String idempotencyKey,
  });

  Future<void> archiveProperty({
    required String propertyId,
    required int expectedVersion,
    required String reason,
    required String idempotencyKey,
  });

  Future<Map<String, dynamic>> getExportData();

  Future<void> importWorkbook({
    required Map<String, Object?> payload,
    required String idempotencyKey,
  });
}

/// Optional recovery seam; existing repository test doubles need not expose it.
abstract interface class YorksV1RentalCommandOutcomeRepository {
  Future<bool> wasCommandConfirmed({
    required String commandName,
    required String idempotencyKey,
  });
}

String yorksV1RentalPaymentMethodWire(String value) {
  final normalized = value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
  return switch (normalized) {
    'bank_transfer' || 'cash' || 'pdc' || 'cdc' || 'other' => normalized,
    'cheque' => 'other',
    _ => throw const YorksV1DomainException(
      YorksV1DomainErrorCode.invalidInput,
    ),
  };
}

Map<String, Object?> yorksV1RentalChequePayloadWire(
  Map<String, Object?> payload,
) {
  final type = payload['cheque_type']?.toString().trim().toLowerCase();
  if (type != 'pdc' && type != 'cdc') {
    throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
  }
  return {...payload, 'cheque_type': type};
}

class YorksV1SupabaseRentalRepository
    implements YorksV1RentalRepository, YorksV1RentalCommandOutcomeRepository {
  const YorksV1SupabaseRentalRepository({
    required YorksV1FeatureFlags featureFlags,
    required ConnectivityService connectivity,
    YorksV1MaterialRequestRpcClient? rpcClient,
    Duration rpcTimeout = const Duration(seconds: 25),
  }) : _featureFlags = featureFlags,
       _connectivity = connectivity,
       _rpcClient = rpcClient,
       _rpcTimeout = rpcTimeout;

  final YorksV1FeatureFlags _featureFlags;
  final ConnectivityService _connectivity;
  final YorksV1MaterialRequestRpcClient? _rpcClient;
  final Duration _rpcTimeout;

  @override
  Future<YorksV1RentalPortfolio> getPortfolio() async {
    final response = await _invoke(
      functionName: 'v1_get_rental_portfolio',
      parameters: const {},
    );
    return YorksV1RentalPortfolio.fromJson(_object(response));
  }

  @override
  Future<YorksV1RentalPropertyDetail> getProperty(String propertyId) async {
    final response = await _invoke(
      functionName: 'v1_get_rental_property',
      parameters: {'p_property_id': propertyId},
    );
    return YorksV1RentalPropertyDetail.fromJson(_object(response));
  }

  @override
  Future<String> saveProperty(
    YorksV1RentalPropertyInput input, {
    required int? expectedVersion,
    required String idempotencyKey,
  }) async {
    final response = _object(
      await _invoke(
        functionName: 'v1_save_rental_property',
        parameters: {
          'p_payload': input.toRpcPayload(),
          'p_expected_version': expectedVersion,
          'p_idempotency_key': idempotencyKey,
        },
      ),
    );
    final propertyId = response['property_id']?.toString();
    if (propertyId == null || propertyId.isEmpty) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    // The command response confirms the write. Detail loading has its own
    // error/retry state and must never turn a committed save into a failure.
    return propertyId;
  }

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
    await _invoke(
      functionName: 'v1_record_rent_payment',
      parameters: {
        'p_period_id': periodId,
        'p_amount': amount,
        'p_payment_date': _wireDate(paymentDate),
        'p_payment_method': yorksV1RentalPaymentMethodWire(paymentMethod),
        'p_reference': reference,
        'p_note': note,
        'p_idempotency_key': idempotencyKey,
      },
    );
  }

  @override
  Future<void> saveCheque({
    required Map<String, Object?> payload,
    required int? expectedVersion,
    required String idempotencyKey,
  }) async {
    await _invoke(
      functionName: 'v1_save_rental_cheque',
      parameters: {
        'p_payload': yorksV1RentalChequePayloadWire(payload),
        'p_expected_version': expectedVersion,
        'p_idempotency_key': idempotencyKey,
      },
    );
  }

  @override
  Future<void> transitionCheque({
    required String chequeId,
    required int expectedVersion,
    required YorksV1RentalChequeStatus nextStatus,
    required String? reason,
    required String idempotencyKey,
  }) async {
    await _invoke(
      functionName: 'v1_transition_rental_cheque',
      parameters: {
        'p_cheque_id': chequeId,
        'p_expected_version': expectedVersion,
        'p_next_status': nextStatus.name,
        'p_reason': reason,
        'p_idempotency_key': idempotencyKey,
      },
    );
  }

  @override
  Future<void> archiveProperty({
    required String propertyId,
    required int expectedVersion,
    required String reason,
    required String idempotencyKey,
  }) async {
    await _invoke(
      functionName: 'v1_archive_rental_property',
      parameters: {
        'p_property_id': propertyId,
        'p_expected_version': expectedVersion,
        'p_reason': reason,
        'p_idempotency_key': idempotencyKey,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> getExportData() async {
    return _object(
      await _invoke(
        functionName: 'v1_get_rental_export_data',
        parameters: const {},
      ),
    );
  }

  @override
  Future<void> importWorkbook({
    required Map<String, Object?> payload,
    required String idempotencyKey,
  }) async {
    await _invoke(
      functionName: 'v1_import_rental_workbook',
      parameters: {'p_payload': payload, 'p_idempotency_key': idempotencyKey},
    );
  }

  @override
  Future<bool> wasCommandConfirmed({
    required String commandName,
    required String idempotencyKey,
  }) async {
    final response = _object(
      await _invoke(
        functionName: 'v1_get_rental_command_outcome',
        parameters: {
          'p_command_name': commandName,
          'p_idempotency_key': idempotencyKey,
        },
      ),
    );
    return response['state'] == 'confirmed';
  }

  Future<Object?> _invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async {
    if (!_featureFlags.foundation) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.featureDisabled,
      );
    }
    if (!_connectivity.isOnline) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.offline);
    }
    final rpc = _rpcClient;
    if (rpc == null) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
    try {
      return await rpc
          .invoke(functionName: functionName, parameters: parameters)
          .timeout(_rpcTimeout);
    } on YorksV1DomainException {
      rethrow;
    } on PostgrestException catch (error) {
      throw _mapPostgrest(error);
    } on TimeoutException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
        cause: error,
      );
    } catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
        cause: error,
      );
    }
  }

  static Map<String, dynamic> _object(Object? response) {
    if (response is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return Map<String, dynamic>.from(response);
  }

  static String _wireDate(DateTime value) =>
      value.toIso8601String().split('T').first;

  static YorksV1DomainException _mapPostgrest(PostgrestException error) {
    final message = error.message;
    final code = switch (error.code) {
      '42501' || '28000' => YorksV1DomainErrorCode.unauthorized,
      '40001' || '23505' || '55P03' => YorksV1DomainErrorCode.conflict,
      'P0002' => YorksV1DomainErrorCode.invalidInput,
      'PGRST002' || 'PGRST003' => YorksV1DomainErrorCode.backendUnavailable,
      '22023' || '22007' || '22P02' => YorksV1DomainErrorCode.invalidInput,
      '23514' when message.contains('TRANSITION') =>
        YorksV1DomainErrorCode.invalidTransition,
      '23514' => YorksV1DomainErrorCode.invalidInput,
      _ => YorksV1DomainErrorCode.serverRejected,
    };
    return YorksV1DomainException(code, serverCode: error.code, cause: error);
  }
}

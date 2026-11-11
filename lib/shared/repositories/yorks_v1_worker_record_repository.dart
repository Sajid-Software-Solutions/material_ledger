import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/analytics_event.dart';
import '../models/yorks_v1_domain_error.dart';
import '../models/yorks_v1_feature_flags.dart';
import '../models/yorks_v1_worker_record.dart';
import '../services/analytics_service.dart';
import '../sync/connectivity_service.dart';

const yorksV1WorkerPhotoBucket = 'yorks-worker-photos';

/// Seam over Supabase so the repository is testable without a client.
abstract interface class YorksV1WorkerRecordDataClient {
  Future<Object?> rpc(String functionName, Map<String, Object?> parameters);

  Future<String> signedPhotoUrl(String objectPath, {required int seconds});

  Future<void> uploadPhoto(String objectPath, Uint8List jpegBytes);
}

final class SupabaseYorksV1WorkerRecordDataClient
    implements YorksV1WorkerRecordDataClient {
  const SupabaseYorksV1WorkerRecordDataClient(this._client);

  final SupabaseClient _client;

  @override
  Future<Object?> rpc(String functionName, Map<String, Object?> parameters) =>
      _client.rpc(functionName, params: parameters);

  @override
  Future<String> signedPhotoUrl(String objectPath, {required int seconds}) =>
      _client.storage
          .from(yorksV1WorkerPhotoBucket)
          .createSignedUrl(objectPath, seconds);

  @override
  Future<void> uploadPhoto(String objectPath, Uint8List jpegBytes) => _client
      .storage
      .from(yorksV1WorkerPhotoBucket)
      .uploadBinary(
        objectPath,
        jpegBytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg'),
      );
}

abstract interface class YorksV1WorkerRecordRepository {
  Future<YorksV1WorkerRecordPage> listRecords(YorksV1WorkerRecordQuery query);

  Future<YorksV1WorkerRecord> getRecord(String workerId);

  /// A short-lived link to a stored photo. Storage re-checks
  /// `worker_records.view`; knowing a path grants nothing.
  Future<String> photoUrl(String objectPath);

  /// Creates or updates a record. Requires `worker_records.manage`; the
  /// server rechecks it, the record version and the idempotency key.
  Future<YorksV1WorkerRecord> saveRecord(YorksV1SaveWorkerRecordInput input);

  /// Stores a prepared JPEG and attaches it to the worker's record.
  Future<YorksV1WorkerRecord> setPhoto({
    required String workerId,
    required Uint8List jpegBytes,
    required int expectedVersion,
    required String idempotencyKey,
  });

  /// Classifies sheet rows on the server. Writes nothing.
  Future<YorksV1WorkerImportPreview> previewImport(
    List<Map<String, Object?>> rows,
  );

  /// Imports every row or none. [expected] is the preview's rows, unchanged.
  Future<YorksV1WorkerImportResult> importRecords({
    required List<Map<String, Object?>> rows,
    required List<Map<String, dynamic>> expected,
    String? newWorkerDesignation,
    String? newWorkerJoiningDate,
    required String idempotencyKey,
  });
}

final class YorksV1SupabaseWorkerRecordRepository
    implements YorksV1WorkerRecordRepository {
  const YorksV1SupabaseWorkerRecordRepository({
    required YorksV1FeatureFlags featureFlags,
    required ConnectivityService connectivity,
    YorksV1WorkerRecordDataClient? dataClient,
    AnalyticsService analytics = const NoopAnalyticsService(),
  }) : _featureFlags = featureFlags,
       _connectivity = connectivity,
       _dataClient = dataClient,
       _analytics = analytics;

  final YorksV1FeatureFlags _featureFlags;
  final ConnectivityService _connectivity;
  final YorksV1WorkerRecordDataClient? _dataClient;
  final AnalyticsService _analytics;

  @override
  Future<YorksV1WorkerRecordPage> listRecords(
    YorksV1WorkerRecordQuery query,
  ) async {
    // No search text, name or amount is sent to analytics.
    final operation = _analytics.beginOperation(
      'worker_records_load',
      properties: const {AnalyticsProperty.workflow: 'worker_records'},
    );
    try {
      final response = await _invoke(
        (client) =>
            client.rpc('v1_list_worker_records', query.toRpcParameters()),
      );
      final page = YorksV1WorkerRecordPage.fromRpcJson(_map(response));
      operation.complete(resultCount: page.items.length);
      return page;
    } on FormatException catch (error) {
      final mapped = YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
      operation.fail(mapped);
      throw mapped;
    } catch (error) {
      operation.fail(error);
      rethrow;
    }
  }

  @override
  Future<YorksV1WorkerRecord> getRecord(String workerId) async {
    final normalized = workerId.trim();
    if (normalized.isEmpty) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    final response = await _invoke(
      (client) =>
          client.rpc('v1_get_worker_record', {'p_worker_id': normalized}),
    );
    try {
      final record = YorksV1WorkerRecord.fromRpcJson(_map(response));
      if (record.workerId != normalized) {
        throw const FormatException('Worker record identity mismatch.');
      }
      return record;
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<String> photoUrl(String objectPath) async {
    final url = await _invoke(
      (client) => client.signedPhotoUrl(objectPath, seconds: 3600),
    );
    if (url is! String || url.isEmpty) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return url;
  }

  @override
  Future<YorksV1WorkerRecord> saveRecord(
    YorksV1SaveWorkerRecordInput input,
  ) async {
    final operation = _analytics.beginOperation(
      'worker_record_save',
      properties: const {AnalyticsProperty.workflow: 'worker_records'},
    );
    try {
      final response = await _invoke(
        (client) => client.rpc('v1_save_worker_record', {
          'p_payload': input.toRpcPayload(),
          'p_expected_version': input.expectedVersion,
          'p_idempotency_key': input.idempotencyKey,
        }),
      );
      final record = _record(response);
      operation.complete();
      return record;
    } catch (error) {
      operation.fail(error);
      rethrow;
    }
  }

  @override
  Future<YorksV1WorkerRecord> setPhoto({
    required String workerId,
    required Uint8List jpegBytes,
    required int expectedVersion,
    required String idempotencyKey,
  }) async {
    // The object name derives from the idempotency key, so a retry reuses
    // the same stored object instead of leaving an orphan.
    final objectPath = 'workers/$workerId/$idempotencyKey.jpg';
    final operation = _analytics.beginOperation(
      'worker_record_photo_set',
      properties: const {AnalyticsProperty.workflow: 'worker_records'},
    );
    try {
      try {
        await _invoke((client) async {
          await client.uploadPhoto(objectPath, jpegBytes);
          return null;
        });
      } on YorksV1DomainException catch (error) {
        // A retry finds the object already stored; continue to attach it.
        final cause = error.cause;
        final alreadyStored =
            cause is StorageException &&
            (cause.statusCode == '409' ||
                cause.message.toLowerCase().contains('already exists'));
        if (!alreadyStored) rethrow;
      }
      final response = await _invoke(
        (client) => client.rpc('v1_set_worker_photo', {
          'p_worker_id': workerId,
          'p_object_path': objectPath,
          'p_expected_version': expectedVersion,
          'p_idempotency_key': idempotencyKey,
        }),
      );
      final record = _record(response);
      operation.complete();
      return record;
    } catch (error) {
      operation.fail(error);
      rethrow;
    }
  }

  @override
  Future<YorksV1WorkerImportPreview> previewImport(
    List<Map<String, Object?>> rows,
  ) async {
    final response = await _invoke(
      (client) =>
          client.rpc('v1_preview_worker_records_import', {'p_rows': rows}),
    );
    try {
      return YorksV1WorkerImportPreview.fromRpcJson(_map(response));
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<YorksV1WorkerImportResult> importRecords({
    required List<Map<String, Object?>> rows,
    required List<Map<String, dynamic>> expected,
    String? newWorkerDesignation,
    String? newWorkerJoiningDate,
    required String idempotencyKey,
  }) async {
    final operation = _analytics.beginOperation(
      'worker_records_import',
      properties: {
        AnalyticsProperty.workflow: 'worker_records',
        AnalyticsProperty.itemCount: rows.length,
      },
    );
    try {
      final response = await _invoke(
        (client) => client.rpc('v1_import_worker_records', {
          'p_payload': {
            'rows': rows,
            'expected': expected,
            'new_worker_designation': ?newWorkerDesignation,
            'new_worker_joining_date': ?newWorkerJoiningDate,
          },
          'p_idempotency_key': idempotencyKey,
        }),
      );
      final YorksV1WorkerImportResult result;
      try {
        result = YorksV1WorkerImportResult.fromRpcJson(_map(response));
      } on FormatException catch (error) {
        throw YorksV1DomainException(
          YorksV1DomainErrorCode.unexpectedResponse,
          cause: error,
        );
      }
      operation.complete(
        resultCount: result.createdCount + result.updatedCount,
      );
      return result;
    } catch (error) {
      operation.fail(error);
      rethrow;
    }
  }

  static YorksV1WorkerRecord _record(Object? response) {
    try {
      return YorksV1WorkerRecord.fromRpcJson(_map(response));
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  static Map<String, dynamic> _map(Object? response) {
    if (response is! Map) {
      throw const FormatException('Worker record response is not an object.');
    }
    return Map<String, dynamic>.from(response);
  }

  Future<Object?> _invoke(
    Future<Object?> Function(YorksV1WorkerRecordDataClient client) call,
  ) async {
    if (!_featureFlags.workerRecords) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.featureDisabled,
      );
    }
    if (!_connectivity.isOnline) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.offline);
    }
    final client = _dataClient;
    if (client == null) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
    try {
      return await call(client);
    } on YorksV1DomainException {
      rethrow;
    } on PostgrestException catch (error) {
      throw YorksV1DomainException(
        switch (error.code) {
          'PGRST301' ||
          'PGRST302' ||
          'PGRST303' ||
          '28000' => YorksV1DomainErrorCode.unauthenticated,
          '42501' => YorksV1DomainErrorCode.unauthorized,
          '22023' || '22P02' => YorksV1DomainErrorCode.invalidInput,
          '40001' => YorksV1DomainErrorCode.conflict,
          // Only the passport-uniqueness rule raises this for these commands.
          '23505' => YorksV1DomainErrorCode.invalidInput,
          'P0002' => YorksV1DomainErrorCode.conflict,
          'PGRST002' || 'PGRST003' => YorksV1DomainErrorCode.backendUnavailable,
          _ => YorksV1DomainErrorCode.serverRejected,
        },
        serverCode: error.code,
        serverMessage: error.message,
        cause: error,
      );
    } on StorageException catch (error) {
      throw YorksV1DomainException(
        error.statusCode == '403' || error.statusCode == '401'
            ? YorksV1DomainErrorCode.unauthorized
            : YorksV1DomainErrorCode.backendUnavailable,
        cause: error,
      );
    } catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
        cause: error,
      );
    }
  }
}

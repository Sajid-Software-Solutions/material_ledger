import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/yorks_v1_company_documents.dart';
import '../models/yorks_v1_domain_error.dart';
import '../models/yorks_v1_feature_flags.dart';
import '../sync/connectivity_service.dart';
import 'yorks_v1_record_files.dart';

export 'yorks_v1_record_files.dart';

const yorksV1CompanyFilesBucket = 'yorks-company-files';

/// Seam over Supabase so the repository is testable without a client.
abstract interface class YorksV1CompanyDocumentsRpcClient {
  Future<Object?> rpc(String functionName, Map<String, Object?> parameters);
}

final class SupabaseYorksV1CompanyDocumentsRpcClient
    implements YorksV1CompanyDocumentsRpcClient {
  const SupabaseYorksV1CompanyDocumentsRpcClient(this._client);

  final SupabaseClient _client;

  @override
  Future<Object?> rpc(String functionName, Map<String, Object?> parameters) =>
      _client.rpc(functionName, params: parameters);
}

/// Company documents: licences, permits, certificates, vehicles, insurance
/// and CICPA passes. Every command is rechecked on the server
/// (`company_documents.*`, record versions, idempotency keys); nothing is
/// shown as saved before the server confirms it.
final class YorksV1CompanyDocumentsRepository {
  const YorksV1CompanyDocumentsRepository({
    required YorksV1FeatureFlags featureFlags,
    required ConnectivityService connectivity,
    YorksV1CompanyDocumentsRpcClient? client,
    YorksV1RecordFileClient? files,
  }) : _featureFlags = featureFlags,
       _connectivity = connectivity,
       _client = client,
       _files = files;

  final YorksV1FeatureFlags _featureFlags;
  final ConnectivityService _connectivity;
  final YorksV1CompanyDocumentsRpcClient? _client;
  final YorksV1RecordFileClient? _files;

  /// A record's attachments (company_documents.view).
  Future<CompanyAttachments> attachments(String recordId) async =>
      CompanyAttachments.fromJson(
        _map(
          await _invoke('v1_company_docs_list_attachments', {
            'p_record_id': recordId,
          }),
        ),
        ownerKey: 'record_id',
      );

  /// How many attachments each record has, by record id.
  Future<Map<String, int>> attachmentCounts() async {
    final counts = _map(
      await _invoke('v1_company_docs_attachment_counts', const {}),
    )['counts'];
    return {
      if (counts is Map)
        for (final MapEntry(:key, :value) in counts.entries)
          key.toString(): value is num ? value.toInt() : 0,
    };
  }

  /// Stores the file, then records it; a retry reuses the same stored file
  /// and the server reads size and type from storage.
  Future<CompanyAttachments> addAttachment({
    required String recordId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    required String idempotencyKey,
    String? documentId,
    String? title,
  }) async {
    final objectPath = yorksV1RecordFilePath(
      folder: 'company',
      ownerId: recordId,
      idempotencyKey: idempotencyKey,
      contentType: contentType,
      sizeBytes: bytes.lengthInBytes,
    );
    _ready();
    await yorksV1StoreRecordFile(_files, objectPath, bytes, contentType);
    return CompanyAttachments.fromJson(
      _map(
        await _invoke('v1_company_docs_add_attachment', {
          'p_record_id': recordId,
          'p_payload': {
            'object_path': objectPath,
            'file_name': fileName,
            'document_id': documentId,
            'title': title,
          },
          'p_idempotency_key': idempotencyKey,
        }),
      ),
      ownerKey: 'record_id',
    );
  }

  /// Hides an attachment with a reason; the file and history are kept.
  Future<CompanyAttachments> removeAttachment({
    required String attachmentId,
    required String reason,
    required String idempotencyKey,
  }) async => CompanyAttachments.fromJson(
    _map(
      await _invoke('v1_company_docs_remove_attachment', {
        'p_attachment_id': attachmentId,
        'p_reason': reason,
        'p_idempotency_key': idempotencyKey,
      }),
    ),
    ownerKey: 'record_id',
  );

  /// A five-minute link to open a file. Storage rechecks who is asking.
  Future<String> attachmentUrl(String objectPath) async {
    _ready();
    return yorksV1RecordFileUrl(_files, objectPath);
  }

  Future<CompanyOverview> overview() async => CompanyOverview.fromJson(
    _map(await _invoke('v1_company_docs_overview', {})),
  );

  Future<CompanyListPage> list(CompanyListQuery query) async =>
      CompanyListPage.fromJson(
        _map(
          await _invoke('v1_company_docs_list', {'p_query': query.toJson()}),
        ),
      );

  Future<CompanyRecord> get(String recordId) async => CompanyRecord.fromJson(
    _map(await _invoke('v1_company_docs_get', {'p_record_id': recordId})),
  );

  Future<CompanyRecord> saveRecord(CompanySaveRecordInput input) async =>
      CompanyRecord.fromJson(
        _map(
          await _invoke('v1_company_docs_save_record', {
            'p_payload': input.toPayload(),
            'p_expected_version': input.expectedVersion,
            'p_idempotency_key': input.idempotencyKey,
          }),
        ),
      );

  Future<CompanyRecord> setArchived({
    required String recordId,
    required bool archived,
    required String reason,
    required int expectedVersion,
    required String idempotencyKey,
  }) async => CompanyRecord.fromJson(
    _map(
      await _invoke('v1_company_docs_set_archived', {
        'p_record_id': recordId,
        'p_archived': archived,
        'p_reason': reason,
        'p_expected_version': expectedVersion,
        'p_idempotency_key': idempotencyKey,
      }),
    ),
  );

  Future<CompanyRecord> saveDocument(CompanySaveDocumentInput input) async =>
      CompanyRecord.fromJson(
        _map(
          await _invoke('v1_company_docs_save_document', {
            'p_payload': input.toPayload(),
            'p_expected_version': input.expectedVersion,
            'p_idempotency_key': input.idempotencyKey,
          }),
        ),
      );

  Future<CompanyRecord> endDocument({
    required String documentId,
    required String reason,
    required int expectedVersion,
    required String idempotencyKey,
  }) async => CompanyRecord.fromJson(
    _map(
      await _invoke('v1_company_docs_end_document', {
        'p_document_id': documentId,
        'p_reason': reason,
        'p_expected_version': expectedVersion,
        'p_idempotency_key': idempotencyKey,
      }),
    ),
  );

  /// Classifies each record on the server. Writes nothing.
  Future<CompanyImportResult> previewImport(
    Map<String, Object?> payload,
  ) async => CompanyImportResult.fromJson(
    _map(
      await _invoke('v1_company_docs_preview_import', {'p_payload': payload}),
    ),
  );

  /// Imports every record or none.
  Future<CompanyImportResult> import(
    Map<String, Object?> payload, {
    required String idempotencyKey,
  }) async => CompanyImportResult.fromJson(
    _map(
      await _invoke('v1_company_docs_import', {
        'p_payload': payload,
        'p_idempotency_key': idempotencyKey,
      }),
    ),
  );

  void _ready() {
    if (!_featureFlags.companyDocuments) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.featureDisabled,
      );
    }
    if (!_connectivity.isOnline) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.offline);
    }
  }

  Future<Object?> _invoke(
    String functionName,
    Map<String, Object?> parameters,
  ) async {
    _ready();
    final client = _client;
    if (client == null) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
    try {
      return await client.rpc(functionName, parameters);
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
          '22023' ||
          '22P02' ||
          '22007' ||
          '22008' => YorksV1DomainErrorCode.invalidInput,
          '40001' || 'P0002' => YorksV1DomainErrorCode.conflict,
          'PGRST002' || 'PGRST003' => YorksV1DomainErrorCode.backendUnavailable,
          _ => YorksV1DomainErrorCode.serverRejected,
        },
        serverCode: error.code,
        serverMessage: error.message,
        cause: error,
      );
    }
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const YorksV1DomainException(
      YorksV1DomainErrorCode.unexpectedResponse,
    );
  }
}

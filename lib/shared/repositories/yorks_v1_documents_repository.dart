import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/yorks_v1_document.dart';
import '../models/analytics_event.dart';
import '../models/yorks_v1_domain_error.dart';
import '../models/yorks_v1_feature_flags.dart';
import '../sync/connectivity_service.dart';
import '../services/analytics_service.dart';
import 'yorks_v1_material_request_repository.dart';

/// A narrow Storage/Edge/RPC boundary. Widgets never receive a Supabase client,
/// unrestricted Storage path, or a chance to forge document finalization.
abstract interface class YorksV1DocumentStorageClient {
  Future<void> upload({
    required String bucketId,
    required String objectPath,
    required Uint8List bytes,
    required String mimeType,
  });

  Future<Uint8List> download({
    required String bucketId,
    required String objectPath,
  });
}

abstract interface class YorksV1DocumentFinalizerClient {
  Future<Object?> finalize(String uploadIntentId);
}

class SupabaseYorksV1DocumentStorageClient
    implements YorksV1DocumentStorageClient {
  const SupabaseYorksV1DocumentStorageClient(this._client);

  final SupabaseClient _client;

  @override
  Future<void> upload({
    required String bucketId,
    required String objectPath,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    await _client.storage
        .from(bucketId)
        .uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
  }

  @override
  Future<Uint8List> download({
    required String bucketId,
    required String objectPath,
  }) => _client.storage.from(bucketId).download(objectPath);
}

class SupabaseYorksV1DocumentFinalizerClient
    implements YorksV1DocumentFinalizerClient {
  const SupabaseYorksV1DocumentFinalizerClient(this._client);

  final SupabaseClient _client;

  @override
  Future<Object?> finalize(String uploadIntentId) async {
    final response = await _client.functions.invoke(
      'finalize-document-upload',
      body: {'upload_intent_id': uploadIntentId},
    );
    return response.data;
  }
}

abstract interface class YorksV1DocumentsRepository {
  Future<YorksV1DocumentWorkspace> getWorkspace(String projectId);

  Future<YorksV1DocumentWorkspace> upload(YorksV1DocumentUploadInput input);

  Future<void> linkDocument(YorksV1DocumentLinkInput input);

  Future<void> removeDocumentLink(YorksV1DocumentLinkRemovalInput input);

  Future<Uint8List> downloadDocument({
    required String bucketId,
    required String objectPath,
  });
}

/// Rental documents share the controlled Yorks document store, but use an
/// Admin-only server projection so a property identifier is never mistaken for
/// a project membership boundary.
abstract interface class YorksV1RentalDocumentsRepository {
  Future<YorksV1DocumentWorkspace> getRentalWorkspace(String propertyId);

  Future<YorksV1DocumentWorkspace> uploadRental(
    YorksV1DocumentUploadInput input,
  );

  Future<Uint8List> downloadDocument({
    required String bucketId,
    required String objectPath,
  });
}

/// Supplier receipt evidence reuses the immutable Yorks document/version
/// pipeline while keeping its non-project authorization in a dedicated RPC.
abstract interface class YorksV1SupplierDocumentsRepository {
  Future<YorksV1DocumentWorkspace> getSupplierWorkspace(String supplierId);

  Future<YorksV1DocumentWorkspace> uploadSupplier(
    YorksV1DocumentUploadInput input,
  );

  Future<Uint8List> downloadDocument({
    required String bucketId,
    required String objectPath,
  });
}

/// Accounts documents reuse the same immutable object/version pipeline while
/// receiving a strictly role-shaped commercial projection.
abstract interface class YorksV1AccountsDocumentsRepository {
  Future<YorksV1AccountsDocumentWorkspace> getAccountsWorkspace(
    String projectId, {
    String? search,
    YorksV1AccountsDocumentType? documentType,
    bool includeArchived = false,
  });

  Future<YorksV1AccountsDocumentWorkspace> uploadAccounts(
    YorksV1DocumentUploadInput input,
  );

  Future<Uint8List> downloadDocument({
    required String bucketId,
    required String objectPath,
  });
}

class YorksV1SupabaseDocumentsRepository
    implements
        YorksV1DocumentsRepository,
        YorksV1RentalDocumentsRepository,
        YorksV1SupplierDocumentsRepository,
        YorksV1AccountsDocumentsRepository {
  const YorksV1SupabaseDocumentsRepository({
    required YorksV1FeatureFlags featureFlags,
    required ConnectivityService connectivity,
    YorksV1MaterialRequestRpcClient? rpcClient,
    YorksV1DocumentStorageClient? storageClient,
    YorksV1DocumentFinalizerClient? finalizerClient,
    AnalyticsService analytics = const NoopAnalyticsService(),
  }) : _featureFlags = featureFlags,
       _connectivity = connectivity,
       _rpcClient = rpcClient,
       _storageClient = storageClient,
       _finalizerClient = finalizerClient,
       _analytics = analytics;

  final YorksV1FeatureFlags _featureFlags;
  final ConnectivityService _connectivity;
  final YorksV1MaterialRequestRpcClient? _rpcClient;
  final YorksV1DocumentStorageClient? _storageClient;
  final YorksV1DocumentFinalizerClient? _finalizerClient;
  final AnalyticsService _analytics;

  @override
  Future<YorksV1DocumentWorkspace> getWorkspace(String projectId) async {
    final response = await _invoke(
      functionName: 'v1_document_workspace_projection',
      parameters: {'p_project_id': projectId},
    );
    return _workspace(response);
  }

  @override
  Future<YorksV1DocumentWorkspace> getRentalWorkspace(String propertyId) async {
    final response = await _invoke(
      functionName: 'v1_rental_document_workspace_projection',
      parameters: {'p_property_id': propertyId},
    );
    return _workspace(response);
  }

  @override
  Future<YorksV1DocumentWorkspace> getSupplierWorkspace(
    String supplierId,
  ) async {
    _requireSupplierReady();
    final response = await _invoke(
      functionName: 'v1_supplier_document_workspace_projection',
      parameters: {'p_supplier_id': supplierId},
    );
    return _workspace(response);
  }

  @override
  Future<YorksV1AccountsDocumentWorkspace> getAccountsWorkspace(
    String projectId, {
    String? search,
    YorksV1AccountsDocumentType? documentType,
    bool includeArchived = false,
  }) async {
    final normalizedProjectId = projectId.trim();
    if (normalizedProjectId.isEmpty) _unexpected();
    _requireAccountsReady();
    final response = await _invoke(
      functionName: 'v1_get_accounts_documents',
      parameters: {
        'p_project_id': normalizedProjectId,
        'p_search': _nullableTrimmed(search),
        'p_document_type': documentType?.wireValue,
        'p_include_archived': includeArchived,
      },
    );
    if (response is! Map) _unexpected();
    final workspace = YorksV1AccountsDocumentWorkspace.fromRpcJson(
      Map<String, dynamic>.from(response),
    );
    if (workspace.projectId != normalizedProjectId) _unexpected();
    return workspace;
  }

  @override
  Future<YorksV1DocumentWorkspace> upload(YorksV1DocumentUploadInput input) =>
      _upload(
        input,
        prepareFunction: 'v1_prepare_document_upload',
        reload: () => getWorkspace(input.projectId),
      );

  @override
  Future<YorksV1DocumentWorkspace> uploadRental(
    YorksV1DocumentUploadInput input,
  ) => _upload(
    input,
    prepareFunction: 'v1_prepare_rental_document_upload',
    reload: () => getRentalWorkspace(input.projectId),
  );

  @override
  Future<YorksV1DocumentWorkspace> uploadSupplier(
    YorksV1DocumentUploadInput input,
  ) {
    _requireSupplierReady();
    _validateSupplierUpload(input);
    return _upload(
      input,
      prepareFunction: 'v1_prepare_supplier_document_upload',
      reload: () => getSupplierWorkspace(input.projectId),
      includeSupplierMetadata: true,
    );
  }

  @override
  Future<YorksV1AccountsDocumentWorkspace> uploadAccounts(
    YorksV1DocumentUploadInput input,
  ) {
    _requireAccountsReady();
    _validateAccountsUpload(input);
    return _upload(
      input,
      prepareFunction: 'v1_prepare_accounts_document_upload',
      reload: () => getAccountsWorkspace(input.projectId),
      includeAccountsMetadata: true,
    );
  }

  Future<T> _upload<T>(
    YorksV1DocumentUploadInput input, {
    required String prepareFunction,
    required Future<T> Function() reload,
    bool includeSupplierMetadata = false,
    bool includeAccountsMetadata = false,
  }) async {
    final properties = <AnalyticsProperty, Object?>{
      AnalyticsProperty.objectType: input.entityType,
      AnalyticsProperty.fileType: _fileType(input.mimeType),
      AnalyticsProperty.fileSizeBucket: _fileSizeBucket(input.bytes.length),
      AnalyticsProperty.attachmentCount: 1,
    };
    _uploadAnalyticsSafely(
      () => _analytics.capture(
        AnalyticsEvent.documentUploadAttempted,
        properties: properties,
      ),
    );
    AnalyticsOperation? operation;
    _uploadAnalyticsSafely(
      () => operation = _analytics.beginOperation(
        'document_upload',
        properties: properties,
      ),
    );
    try {
      final result = await _uploadAuthorized(
        input,
        prepareFunction: prepareFunction,
        reload: reload,
        includeSupplierMetadata: includeSupplierMetadata,
        includeAccountsMetadata: includeAccountsMetadata,
      );
      _uploadAnalyticsSafely(() => operation?.complete());
      _uploadAnalyticsSafely(
        () => _analytics.capture(
          AnalyticsEvent.documentUploadSucceeded,
          properties: properties,
        ),
      );
      return result;
    } catch (error) {
      _uploadAnalyticsSafely(() => operation?.fail(error));
      _uploadAnalyticsSafely(
        () => _analytics.capture(
          AnalyticsEvent.documentUploadFailed,
          properties: {
            ...properties,
            AnalyticsProperty.errorCategory: analyticsErrorCategory(error),
          },
        ),
      );
      rethrow;
    }
  }

  static void _uploadAnalyticsSafely(void Function() emit) {
    try {
      emit();
    } catch (_) {
      // Instrumentation cannot block an authorized file attempt, erase a
      // finalized success, or replace the original business failure.
    }
  }

  Future<T> _uploadAuthorized<T>(
    YorksV1DocumentUploadInput input, {
    required String prepareFunction,
    required Future<T> Function() reload,
    bool includeSupplierMetadata = false,
    bool includeAccountsMetadata = false,
  }) async {
    _requireReady();
    final rpc = _rpcClient!;
    final storage = _storageClient;
    final finalizer = _finalizerClient;
    if (storage == null || finalizer == null) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
    final hash = sha256.convert(input.bytes).toString();
    final intent = _intent(
      await _rpc(
        rpc,
        functionName: prepareFunction,
        parameters: {
          'p_payload': includeSupplierMetadata
              ? input.toSupplierRpcPayload(hash)
              : includeAccountsMetadata
              ? input.toAccountsRpcPayload(hash)
              : input.toRpcPayload(hash),
          'p_idempotency_key': input.idempotencyKey,
        },
      ),
    );
    if ((intent.finalizedDocumentId == null) !=
        (intent.finalizedVersionId == null)) {
      _unexpected();
    }
    final replacementDocumentId = _nullableTrimmed(input.documentId);
    if (intent.finalizedDocumentId != null &&
        replacementDocumentId != null &&
        intent.finalizedDocumentId != replacementDocumentId) {
      _unexpected();
    }
    if (intent.finalizedDocumentId == null) {
      try {
        await storage.upload(
          bucketId: intent.bucketId,
          objectPath: intent.objectPath,
          bytes: input.bytes,
          mimeType: intent.mimeType,
        );
      } on StorageException catch (error) {
        // A retry after an ambiguous transport failure may encounter the same
        // immutable object. The server finalizer remains the authority.
        if (!error.message.toLowerCase().contains('already exists')) rethrow;
      } catch (error) {
        throw YorksV1DomainException(
          YorksV1DomainErrorCode.backendUnavailable,
          cause: error,
        );
      }
      try {
        final response = await finalizer.finalize(intent.id);
        // HTTP success alone is not proof of document finalization. Require
        // the protected RPC's exact identity/revision projection before the
        // coordinator may label this immutable file intent Ready.
        if (response is! Map ||
            response['document_id'] is! String ||
            (response['document_id'] as String).trim().isEmpty ||
            response['document_version_id'] is! String ||
            (response['document_version_id'] as String).trim().isEmpty ||
            response['revision_number'] is! int ||
            response['revision_number'] != intent.plannedRevisionNumber ||
            (replacementDocumentId != null &&
                response['document_id'] != replacementDocumentId)) {
          _unexpected();
        }
      } on FunctionException catch (error) {
        throw YorksV1DomainException(
          error.status == 401 || error.status == 403
              ? YorksV1DomainErrorCode.unauthorized
              : YorksV1DomainErrorCode.conflict,
          cause: error,
        );
      } on YorksV1DomainException {
        rethrow;
      } catch (error) {
        throw YorksV1DomainException(
          YorksV1DomainErrorCode.backendUnavailable,
          cause: error,
        );
      }
    }
    return reload();
  }

  static String _fileType(String mimeType) {
    final normalized = mimeType.trim().toLowerCase();
    if (normalized == 'application/pdf') return 'pdf';
    if (normalized.startsWith('image/')) return 'image';
    if (normalized.contains('spreadsheet') || normalized.contains('excel')) {
      return 'spreadsheet';
    }
    if (normalized.contains('word') || normalized.contains('document')) {
      return 'document';
    }
    return 'other';
  }

  static String _fileSizeBucket(int bytes) => switch (bytes) {
    < 100000 => 'under_100kb',
    < 1000000 => '100kb_to_1mb',
    < 10000000 => '1mb_to_10mb',
    _ => 'over_10mb',
  };

  @override
  Future<void> linkDocument(YorksV1DocumentLinkInput input) async {
    await _invoke(
      functionName: 'v1_link_document',
      parameters: {
        'p_payload': input.toRpcPayload(),
        'p_idempotency_key': input.idempotencyKey,
      },
    );
  }

  @override
  Future<void> removeDocumentLink(YorksV1DocumentLinkRemovalInput input) async {
    await _invoke(
      functionName: 'v1_remove_document_link',
      parameters: {
        'p_payload': input.toRpcPayload(),
        'p_idempotency_key': input.idempotencyKey,
      },
    );
  }

  @override
  Future<Uint8List> downloadDocument({
    required String bucketId,
    required String objectPath,
  }) async {
    _requireReady();
    final storage = _storageClient;
    if (storage == null) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
    try {
      return await storage.download(bucketId: bucketId, objectPath: objectPath);
    } on StorageException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unauthorized,
        cause: error,
      );
    } catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
        cause: error,
      );
    }
  }

  Future<Object?> _invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async {
    _requireReady();
    return _rpc(
      _rpcClient!,
      functionName: functionName,
      parameters: parameters,
    );
  }

  Future<Object?> _rpc(
    YorksV1MaterialRequestRpcClient rpc, {
    required String functionName,
    required Map<String, Object?> parameters,
  }) async {
    try {
      return await rpc.invoke(
        functionName: functionName,
        parameters: parameters,
      );
    } on YorksV1DomainException {
      rethrow;
    } on PostgrestException catch (error) {
      final code = switch (error.code) {
        '42501' || '28000' => YorksV1DomainErrorCode.unauthorized,
        '40001' || '23505' || '55P03' => YorksV1DomainErrorCode.conflict,
        '22023' || '22P02' => YorksV1DomainErrorCode.invalidInput,
        _ => YorksV1DomainErrorCode.backendUnavailable,
      };
      throw YorksV1DomainException(code, cause: error);
    } catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
        cause: error,
      );
    }
  }

  void _requireReady() {
    if (!_featureFlags.documents) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.featureDisabled,
      );
    }
    if (!_connectivity.isOnline) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.offline);
    }
    if (_rpcClient == null) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
  }

  void _requireSupplierReady() {
    if (!_featureFlags.inventorySuppliers) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.featureDisabled,
      );
    }
    _requireReady();
  }

  void _requireAccountsReady() {
    if (!_featureFlags.accounts) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.featureDisabled,
      );
    }
    _requireReady();
  }

  static void _validateSupplierUpload(YorksV1DocumentUploadInput input) {
    final type = input.supplierDocumentType;
    final reference = input.businessReference?.trim();
    final notes = input.supplierDocumentNotes?.trim();
    final referenceMissing = reference == null || reference.isEmpty;
    final invalid =
        type == null ||
        (input.entityType != YorksV1DocumentEntityType.supplier &&
            input.entityType !=
                YorksV1DocumentEntityType.supplierReceiptBatch) ||
        (type.requiresBusinessReference && referenceMissing) ||
        (!referenceMissing && reference.length > 180) ||
        (notes != null && notes.length > 1000) ||
        (type == YorksV1SupplierDocumentType.invoice &&
            input.classification != YorksV1DocumentClassification.commercial);
    if (invalid) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
  }

  static void _validateAccountsUpload(YorksV1DocumentUploadInput input) {
    final type = input.accountsDocumentType;
    final accountsTarget = input.entityType.wireValue.startsWith('accounts_');
    final operationalAllowed =
        type == YorksV1AccountsDocumentType.progressEvidence;
    final classificationValid = operationalAllowed
        ? input.classification == YorksV1DocumentClassification.operational ||
              input.classification == YorksV1DocumentClassification.commercial
        : input.classification == YorksV1DocumentClassification.commercial;
    if (type == null || !accountsTarget || !classificationValid) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
  }

  static YorksV1DocumentWorkspace _workspace(Object? response) {
    if (response is! Map) _unexpected();
    return YorksV1DocumentWorkspace.fromRpcJson(
      Map<String, dynamic>.from(response),
    );
  }

  static YorksV1DocumentUploadIntent _intent(Object? response) {
    if (response is! Map) _unexpected();
    return YorksV1DocumentUploadIntent.fromRpcJson(
      Map<String, dynamic>.from(response),
    );
  }

  static Never _unexpected() => throw const YorksV1DomainException(
    YorksV1DomainErrorCode.unexpectedResponse,
  );
}

String? _nullableTrimmed(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

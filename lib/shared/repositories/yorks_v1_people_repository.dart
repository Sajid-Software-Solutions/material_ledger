import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/yorks_v1_domain_error.dart';
import '../models/yorks_v1_feature_flags.dart';
import '../models/yorks_v1_people.dart';
import '../sync/connectivity_service.dart';

/// Seam over Supabase so the repository is testable without a client.
abstract interface class YorksV1PeopleRpcClient {
  Future<Object?> rpc(String functionName, Map<String, Object?> parameters);
}

const yorksV1PeopleFilesBucket = 'yorks-people-files';

/// Seam over Supabase Storage for people's attachments.
abstract interface class YorksV1PeopleFileClient {
  Future<void> upload(String objectPath, Uint8List bytes, String contentType);

  Future<String> signedUrl(String objectPath, {required int seconds});
}

final class SupabaseYorksV1PeopleFileClient implements YorksV1PeopleFileClient {
  const SupabaseYorksV1PeopleFileClient(this._client);

  final SupabaseClient _client;

  @override
  Future<void> upload(String objectPath, Uint8List bytes, String contentType) =>
      _client.storage
          .from(yorksV1PeopleFilesBucket)
          .uploadBinary(
            objectPath,
            bytes,
            fileOptions: FileOptions(contentType: contentType),
          );

  @override
  Future<String> signedUrl(String objectPath, {required int seconds}) => _client
      .storage
      .from(yorksV1PeopleFilesBucket)
      .createSignedUrl(objectPath, seconds);
}

final class SupabaseYorksV1PeopleRpcClient implements YorksV1PeopleRpcClient {
  const SupabaseYorksV1PeopleRpcClient(this._client);

  final SupabaseClient _client;

  @override
  Future<Object?> rpc(String functionName, Map<String, Object?> parameters) =>
      _client.rpc(functionName, params: parameters);
}

/// People records: staff and labour, their documents and the tracker
/// import. Every command is rechecked on the server (`people_records.*`,
/// record versions, idempotency keys); nothing is shown as saved before the
/// server confirms it.
final class YorksV1PeopleRepository {
  const YorksV1PeopleRepository({
    required YorksV1FeatureFlags featureFlags,
    required ConnectivityService connectivity,
    YorksV1PeopleRpcClient? client,
    YorksV1PeopleFileClient? files,
  }) : _featureFlags = featureFlags,
       _connectivity = connectivity,
       _client = client,
       _files = files;

  final YorksV1FeatureFlags _featureFlags;
  final ConnectivityService _connectivity;
  final YorksV1PeopleRpcClient? _client;
  final YorksV1PeopleFileClient? _files;

  Future<PeopleOverview> overview() async =>
      PeopleOverview.fromJson(_map(await _invoke('v1_people_overview', {})));

  Future<PeopleListPage> list(PeopleListQuery query) async =>
      PeopleListPage.fromJson(
        _map(await _invoke('v1_people_list', {'p_query': query.toJson()})),
      );

  Future<PeoplePerson> get(String workerId) async => PeoplePerson.fromJson(
    _map(await _invoke('v1_people_get', {'p_worker_id': workerId})),
  );

  Future<PeoplePerson> savePerson(PeopleSavePersonInput input) async =>
      PeoplePerson.fromJson(
        _map(
          await _invoke('v1_people_save_person', {
            'p_payload': input.toPayload(),
            'p_expected_version': input.expectedVersion,
            'p_idempotency_key': input.idempotencyKey,
          }),
        ),
      );

  Future<PeoplePerson> saveDocument(PeopleSaveDocumentInput input) async =>
      PeoplePerson.fromJson(
        _map(
          await _invoke('v1_people_save_document', {
            'p_payload': input.toPayload(),
            'p_expected_version': input.expectedVersion,
            'p_idempotency_key': input.idempotencyKey,
          }),
        ),
      );

  Future<PeoplePerson> endDocument({
    required String documentId,
    required String reason,
    required int expectedVersion,
    required String idempotencyKey,
  }) async => PeoplePerson.fromJson(
    _map(
      await _invoke('v1_people_end_document', {
        'p_document_id': documentId,
        'p_reason': reason,
        'p_expected_version': expectedVersion,
        'p_idempotency_key': idempotencyKey,
      }),
    ),
  );

  /// A person's attachments (people_records.view).
  Future<PeopleAttachments> attachments(String workerId) async =>
      PeopleAttachments.fromJson(
        _map(
          await _invoke('v1_people_list_attachments', {
            'p_worker_id': workerId,
          }),
        ),
      );

  /// How many attachments each person has, by worker id.
  Future<Map<String, int>> attachmentCounts() async {
    final counts = _map(
      await _invoke('v1_people_attachment_counts', const {}),
    )['counts'];
    return {
      if (counts is Map)
        for (final MapEntry(:key, :value) in counts.entries)
          key.toString(): value is num ? value.toInt() : 0,
    };
  }

  /// Stores the file, then records it. The stored name derives from the
  /// idempotency key, so a retry reuses the same file instead of leaving an
  /// orphan; the server reads size and type from storage.
  Future<PeopleAttachments> addAttachment({
    required String workerId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    required String idempotencyKey,
    String? documentId,
    String? title,
  }) async {
    final extension = peopleAttachmentTypes[contentType];
    if (extension == null ||
        bytes.isEmpty ||
        bytes.lengthInBytes > peopleAttachmentMaxBytes) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    final objectPath = 'people/$workerId/$idempotencyKey.$extension';
    _ready();
    final files = _files;
    if (files == null) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
    try {
      await files.upload(objectPath, bytes, contentType);
    } on StorageException catch (error) {
      final alreadyStored =
          error.statusCode == '409' ||
          error.message.toLowerCase().contains('already exists');
      if (!alreadyStored) {
        throw YorksV1DomainException(
          error.statusCode == '403'
              ? YorksV1DomainErrorCode.unauthorized
              : YorksV1DomainErrorCode.serverRejected,
          serverMessage: error.message,
          cause: error,
        );
      }
    }
    return PeopleAttachments.fromJson(
      _map(
        await _invoke('v1_people_add_attachment', {
          'p_worker_id': workerId,
          'p_payload': {
            'object_path': objectPath,
            'file_name': fileName,
            'document_id': documentId,
            'title': title,
          },
          'p_idempotency_key': idempotencyKey,
        }),
      ),
    );
  }

  /// Hides an attachment with a reason; the file and history are kept.
  Future<PeopleAttachments> removeAttachment({
    required String attachmentId,
    required String reason,
    required String idempotencyKey,
  }) async => PeopleAttachments.fromJson(
    _map(
      await _invoke('v1_people_remove_attachment', {
        'p_attachment_id': attachmentId,
        'p_reason': reason,
        'p_idempotency_key': idempotencyKey,
      }),
    ),
  );

  /// A five-minute link to open a file. Storage rechecks who is asking.
  Future<String> attachmentUrl(String objectPath) async {
    _ready();
    final files = _files;
    if (files == null) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
    try {
      return await files.signedUrl(objectPath, seconds: 300);
    } on StorageException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unauthorized,
        serverMessage: error.message,
        cause: error,
      );
    }
  }

  /// Classifies each person on the server. Writes nothing.
  Future<PeopleImportResult> previewImport(
    Map<String, Object?> payload,
  ) async => PeopleImportResult.fromJson(
    _map(await _invoke('v1_people_preview_import', {'p_payload': payload})),
  );

  /// Imports every person or none.
  Future<PeopleImportResult> import(
    Map<String, Object?> payload, {
    required String idempotencyKey,
  }) async => PeopleImportResult.fromJson(
    _map(
      await _invoke('v1_people_import', {
        'p_payload': payload,
        'p_idempotency_key': idempotencyKey,
      }),
    ),
  );

  void _ready() {
    if (!_featureFlags.peopleRecords) {
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
          '23505' => YorksV1DomainErrorCode.conflict,
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

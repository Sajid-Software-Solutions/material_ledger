import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/yorks_v1_attachments.dart';
import '../models/yorks_v1_domain_error.dart';

/// Seam over Supabase Storage for one private bucket of record attachments
/// (`yorks-people-files`, `yorks-company-files`).
abstract interface class YorksV1RecordFileClient {
  Future<void> upload(String objectPath, Uint8List bytes, String contentType);

  Future<String> signedUrl(String objectPath, {required int seconds});
}

final class SupabaseYorksV1RecordFileClient implements YorksV1RecordFileClient {
  const SupabaseYorksV1RecordFileClient(this._client, this.bucket);

  final SupabaseClient _client;
  final String bucket;

  @override
  Future<void> upload(String objectPath, Uint8List bytes, String contentType) =>
      _client.storage
          .from(bucket)
          .uploadBinary(
            objectPath,
            bytes,
            fileOptions: FileOptions(contentType: contentType),
          );

  @override
  Future<String> signedUrl(String objectPath, {required int seconds}) =>
      _client.storage.from(bucket).createSignedUrl(objectPath, seconds);
}

/// The stored name of a new attachment: `<folder>/<owner>/<key>.<ext>`. The
/// key is the command's idempotency key, so a retry reuses the same file.
/// Throws invalid input for an unsupported type, an empty or a too large
/// file.
String yorksV1RecordFilePath({
  required String folder,
  required String ownerId,
  required String idempotencyKey,
  required String contentType,
  required int sizeBytes,
}) {
  final extension = recordAttachmentTypes[contentType];
  if (extension == null ||
      sizeBytes <= 0 ||
      sizeBytes > recordAttachmentMaxBytes) {
    throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
  }
  return '$folder/$ownerId/$idempotencyKey.$extension';
}

/// Stores a file. A retry that finds the file already stored carries on.
Future<void> yorksV1StoreRecordFile(
  YorksV1RecordFileClient? files,
  String objectPath,
  Uint8List bytes,
  String contentType,
) async {
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
}

/// A five-minute link to open a stored file. Storage rechecks who asks.
Future<String> yorksV1RecordFileUrl(
  YorksV1RecordFileClient? files,
  String objectPath,
) async {
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

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../models/yorks_v1_attachments.dart';

/// A file chosen for bulk upload. Its bytes are read only when it is
/// uploaded, so choosing a large folder does not fill the browser's memory.
final class YorksV1PickedFile {
  const YorksV1PickedFile({
    required this.name,
    required this.size,
    required this.read,
  });

  final String name;
  final int size;
  final Future<Uint8List> Function() read;

  /// The stored type for this file, or null when it cannot be attached
  /// (not a PDF, Word, Excel, JPG or PNG file).
  String? get contentType => yorksV1AttachmentTypeFor(name);

  /// Attachable: a known type, not empty, at most 20 MB.
  bool get attachable =>
      contentType != null && size > 0 && size <= recordAttachmentMaxBytes;
}

/// The stored type for a file name, by its extension.
String? yorksV1AttachmentTypeFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0) return null;
  return switch (fileName.substring(dot + 1).toLowerCase()) {
    'pdf' => 'application/pdf',
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    _ => null,
  };
}

/// Chooses several files at once (a folder's worth of scans).
abstract interface class YorksV1MultiFileService {
  Future<List<YorksV1PickedFile>> selectFiles();
}

class YorksV1PlatformMultiFileService implements YorksV1MultiFileService {
  const YorksV1PlatformMultiFileService();

  static const _types = XTypeGroup(
    label: 'Scans and documents',
    extensions: ['pdf', 'jpg', 'jpeg', 'png', 'docx', 'xlsx'],
    mimeTypes: [
      'application/pdf',
      'image/jpeg',
      'image/png',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ],
  );

  @override
  Future<List<YorksV1PickedFile>> selectFiles() async {
    final files = await openFiles(acceptedTypeGroups: const [_types]);
    return [
      for (final file in files)
        YorksV1PickedFile(
          name: file.name,
          size: await file.length(),
          read: file.readAsBytes,
        ),
    ];
  }
}

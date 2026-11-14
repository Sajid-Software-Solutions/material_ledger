/// Files kept with a record — a person (People records) or a company record
/// (Company documents): copies of its documents and any other paper
/// (PRODUCT_DECISIONS sections 47 and 48). Wire shape of the
/// `v1_people_*attachment*` and `v1_company_docs_*attachment*` functions.
library;

String _s(Object? value) => value?.toString() ?? '';
String? _ns(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int _i(Object? value) => switch (value) {
  final num number => number.toInt(),
  final String text => int.tryParse(text) ?? 0,
  _ => 0,
};

DateTime? _dt(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

/// One file kept with a record.
final class RecordAttachment {
  const RecordAttachment({
    required this.id,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.objectPath,
    this.documentId,
    this.documentKind,
    this.documentLabel,
    this.documentNumber,
    this.documentCurrent = false,
    this.title,
    this.uploadedBy = '',
    this.uploadedByRole = '',
    this.uploadedAt,
  });

  factory RecordAttachment.fromJson(Map<String, dynamic> json) =>
      RecordAttachment(
        id: _s(json['id']),
        fileName: _s(json['file_name']),
        contentType: _s(json['content_type']),
        sizeBytes: _i(json['size_bytes']),
        objectPath: _s(json['object_path']),
        documentId: _ns(json['document_id']),
        documentKind: _ns(json['document_kind']),
        documentLabel: _ns(json['document_label']),
        documentNumber: _ns(json['document_number']),
        documentCurrent: json['document_current'] == true,
        title: _ns(json['title']),
        uploadedBy: _s(json['uploaded_by']),
        uploadedByRole: _s(json['uploaded_by_role']),
        uploadedAt: _dt(json['uploaded_at']),
      );

  final String id;
  final String fileName;
  final String contentType;
  final int sizeBytes;

  /// Opened through a short-lived link; storage rechecks the reader.
  final String objectPath;

  /// The record's document this file copies, if any (its kind is the wire
  /// value of that record's document kinds).
  final String? documentId;
  final String? documentKind;
  final String? documentLabel;
  final String? documentNumber;
  final bool documentCurrent;
  final String? title;
  final String uploadedBy;
  final String uploadedByRole;
  final DateTime? uploadedAt;

  bool get isImage => contentType.startsWith('image/');
  bool get isPdf => contentType == 'application/pdf';
  bool get isSheet => contentType.contains('spreadsheet');

  /// "1.2 MB", "340 KB".
  String get sizeText => recordAttachmentSize(sizeBytes);
}

/// "1.2 MB", "340 KB".
String recordAttachmentSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024).ceil()} KB';
}

/// A record's attachments and whether the reader may add or remove them.
final class RecordAttachments {
  const RecordAttachments({
    required this.ownerId,
    required this.items,
    this.canManage = false,
  });

  /// [ownerKey] is `worker_id` for a person, `record_id` for a company
  /// record.
  factory RecordAttachments.fromJson(
    Map<String, dynamic> json, {
    required String ownerKey,
  }) => RecordAttachments(
    ownerId: _s(json[ownerKey]),
    canManage: json['can_manage'] == true,
    items: [
      for (final item in (json['attachments'] as List? ?? const []))
        if (item is Map) RecordAttachment.fromJson(Map.from(item)),
    ],
  );

  final String ownerId;
  final bool canManage;
  final List<RecordAttachment> items;

  /// How many files copy each document, by document id.
  Map<String, int> get byDocument {
    final counts = <String, int>{};
    for (final item in items) {
      final document = item.documentId;
      if (document != null) counts[document] = (counts[document] ?? 0) + 1;
    }
    return counts;
  }
}

/// Attachment types accepted (and checked again by storage and the server),
/// with the file extension each is stored under.
const recordAttachmentTypes = {
  'application/pdf': 'pdf',
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
      'docx',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
};

/// The largest attachment, as the storage buckets enforce.
const recordAttachmentMaxBytes = 20 * 1024 * 1024;

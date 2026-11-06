/// A bounded, authorized current-document projection for progress evidence.
/// Progress commands store document IDs, not immutable version IDs.
final class YorksAccountsEvidenceDocument {
  const YorksAccountsEvidenceDocument({
    required this.id,
    required this.fileName,
    required this.currentVersionId,
    required this.revisionNumber,
    required this.mimeType,
    required this.bucketId,
    required this.objectPath,
    this.reference,
  });

  final String id;
  final String fileName;
  final String? reference;
  final String currentVersionId;
  final int revisionNumber;
  final String mimeType;
  final String bucketId;
  final String objectPath;

  factory YorksAccountsEvidenceDocument.fromRpcJson(Map<String, dynamic> json) {
    String requiredString(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Invalid evidence $key.');
      }
      return value;
    }

    final revision = json['revision_number'];
    if (revision is! int || revision < 1) {
      throw const FormatException('Invalid evidence revision.');
    }
    final reference = json['reference'];
    if (reference != null && reference is! String) {
      throw const FormatException('Invalid evidence reference.');
    }
    return YorksAccountsEvidenceDocument(
      id: requiredString('id'),
      fileName: requiredString('file_name'),
      reference: reference as String?,
      currentVersionId: requiredString('current_version_id'),
      revisionNumber: revision,
      mimeType: requiredString('mime_type'),
      bucketId: requiredString('bucket_id'),
      objectPath: requiredString('object_path'),
    );
  }
}

final class YorksAccountsEvidenceSearch {
  const YorksAccountsEvidenceSearch({
    required this.projectId,
    required this.documents,
    required this.selected,
    required this.hasMore,
  });

  final String projectId;
  final List<YorksAccountsEvidenceDocument> documents;
  final List<YorksAccountsEvidenceDocument> selected;
  final bool hasMore;

  factory YorksAccountsEvidenceSearch.fromRpcJson(Map<String, dynamic> json) {
    List<YorksAccountsEvidenceDocument> documents(String key) {
      final raw = json[key];
      if (raw is! List) throw FormatException('Invalid evidence $key.');
      return List.unmodifiable(
        raw.map((item) {
          if (item is! Map) {
            throw FormatException('Invalid evidence $key item.');
          }
          return YorksAccountsEvidenceDocument.fromRpcJson(
            Map<String, dynamic>.from(item),
          );
        }),
      );
    }

    final projectId = json['project_id'];
    final hasMore = json['has_more'];
    if (projectId is! String || projectId.isEmpty || hasMore is! bool) {
      throw const FormatException('Invalid evidence search response.');
    }
    return YorksAccountsEvidenceSearch(
      projectId: projectId,
      documents: documents('documents'),
      selected: documents('selected'),
      hasMore: hasMore,
    );
  }
}

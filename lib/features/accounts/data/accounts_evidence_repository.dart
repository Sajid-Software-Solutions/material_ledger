import 'dart:typed_data';

import '../../../shared/models/yorks_v1_domain_error.dart';
import '../../../shared/repositories/yorks_v1_documents_repository.dart';
import 'accounts_repository.dart';
import '../domain/accounts_evidence_models.dart';

abstract interface class YorksAccountsEvidenceRepository {
  Future<YorksAccountsEvidenceSearch> search({
    required String projectId,
    String? query,
    List<String> selectedDocumentIds = const [],
  });

  Future<Uint8List> preview({
    required String projectId,
    required YorksAccountsEvidenceDocument document,
  });
}

final class YorksSupabaseAccountsEvidenceRepository
    implements YorksAccountsEvidenceRepository {
  const YorksSupabaseAccountsEvidenceRepository({
    required YorksAccountsRpcClient rpcClient,
    required YorksV1DocumentsRepository documentsRepository,
  }) : _rpcClient = rpcClient,
       _documentsRepository = documentsRepository;

  final YorksAccountsRpcClient _rpcClient;
  final YorksV1DocumentsRepository _documentsRepository;

  @override
  Future<YorksAccountsEvidenceSearch> search({
    required String projectId,
    String? query,
    List<String> selectedDocumentIds = const [],
  }) async {
    if (projectId.trim().isEmpty ||
        (query?.length ?? 0) > 120 ||
        selectedDocumentIds.length > 256) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    final response = await _rpcClient.invoke(
      functionName: 'v1_accounts_search_progress_evidence',
      parameters: {
        'p_project_id': projectId,
        'p_query': query,
        'p_selected_document_ids': selectedDocumentIds,
        'p_limit': 20,
      },
    );
    try {
      final result = YorksAccountsEvidenceSearch.fromRpcJson(response);
      if (result.projectId != projectId ||
          result.documents.length > 20 ||
          result.selected.length > 256 ||
          result.selected.any(
            (item) => !selectedDocumentIds.contains(item.id),
          )) {
        throw const FormatException('Evidence search scope mismatch.');
      }
      return result;
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }

  @override
  Future<Uint8List> preview({
    required String projectId,
    required YorksAccountsEvidenceDocument document,
  }) async {
    // Re-read current authorization and revision immediately before Storage.
    // Storage still enforces the current actor's own read policy.
    final fresh = await search(
      projectId: projectId,
      selectedDocumentIds: [document.id],
    );
    if (fresh.selected.length != 1 ||
        fresh.selected.single.currentVersionId != document.currentVersionId) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.conflict);
    }
    final current = fresh.selected.single;
    return _documentsRepository.downloadDocument(
      bucketId: current.bucketId,
      objectPath: current.objectPath,
    );
  }
}

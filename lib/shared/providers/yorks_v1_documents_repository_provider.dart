import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/yorks_v1_documents_repository.dart';
import '../sync/connectivity_service.dart';
import '../services/analytics_service.dart';
import '../services/yorks_v1_document_upload_journal.dart';
import 'language_provider.dart';
import 'yorks_v1_feature_flags_provider.dart';
import 'yorks_v1_material_request_repository_provider.dart';
import 'yorks_v1_identity_provider.dart';
import 'yorks_v1_project_creation_draft_provider.dart';

final yorksV1DocumentUploadJournalProvider =
    Provider<YorksV1DocumentUploadJournal>(
      (ref) => YorksV1DocumentUploadJournal(
        storage: ref.watch(yorksV1ProjectDraftAtomicStorageProvider),
        backend: ref.watch(yorksV1ProjectDraftBackendIdentityProvider),
        owner: ref.watch(yorksV1AuthUserIdProvider) ?? '',
      ),
    );

final yorksV1DocumentsRepositoryProvider = Provider<YorksV1DocumentsRepository>(
  (ref) {
    final client = ref.watch(supabaseClientProvider);
    return YorksV1SupabaseDocumentsRepository(
      featureFlags: ref.watch(yorksV1FeatureFlagsProvider),
      connectivity: ref.watch(connectivityProvider),
      rpcClient: ref.watch(yorksV1MaterialRequestRpcClientProvider),
      storageClient: client == null
          ? null
          : SupabaseYorksV1DocumentStorageClient(client),
      finalizerClient: client == null
          ? null
          : SupabaseYorksV1DocumentFinalizerClient(client),
      analytics: ref.watch(analyticsServiceProvider),
      uploadJournal: ref.watch(yorksV1DocumentUploadJournalProvider),
    );
  },
);

final yorksV1RentalDocumentsRepositoryProvider =
    Provider<YorksV1RentalDocumentsRepository>((ref) {
      final repository = ref.watch(yorksV1DocumentsRepositoryProvider);
      if (repository is! YorksV1RentalDocumentsRepository) {
        throw StateError('Rental document repository is unavailable.');
      }
      return repository as YorksV1RentalDocumentsRepository;
    });

final yorksV1SupplierDocumentsRepositoryProvider =
    Provider<YorksV1SupplierDocumentsRepository>((ref) {
      final repository = ref.watch(yorksV1DocumentsRepositoryProvider);
      if (repository is! YorksV1SupplierDocumentsRepository) {
        throw StateError('Supplier document repository is unavailable.');
      }
      return repository as YorksV1SupplierDocumentsRepository;
    });

final yorksV1AccountsDocumentsRepositoryProvider =
    Provider<YorksV1AccountsDocumentsRepository>((ref) {
      final repository = ref.watch(yorksV1DocumentsRepositoryProvider);
      if (repository is! YorksV1AccountsDocumentsRepository) {
        throw StateError('Accounts document repository is unavailable.');
      }
      return repository as YorksV1AccountsDocumentsRepository;
    });

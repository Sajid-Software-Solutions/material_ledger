import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/yorks_v1_company_documents.dart';
import '../repositories/yorks_v1_company_documents_repository.dart';
import '../sync/connectivity_service.dart';
import 'language_provider.dart' show supabaseClientProvider;
import 'yorks_v1_feature_flags_provider.dart';
import 'yorks_v1_identity_provider.dart';

final yorksV1CompanyDocumentsRepositoryProvider =
    Provider<YorksV1CompanyDocumentsRepository>((ref) {
      final client = ref.watch(supabaseClientProvider);
      return YorksV1CompanyDocumentsRepository(
        featureFlags: ref.watch(yorksV1FeatureFlagsProvider),
        connectivity: ref.watch(connectivityProvider),
        client: client == null
            ? null
            : SupabaseYorksV1CompanyDocumentsRpcClient(client),
      );
    });

/// The Company documents home: counts, owners and what needs attention.
final yorksV1CompanyOverviewProvider =
    FutureProvider.autoDispose<CompanyOverview>((ref) {
      ref.watch(yorksV1AuthUserIdProvider);
      return ref.watch(yorksV1CompanyDocumentsRepositoryProvider).overview();
    });

/// One register page.
final yorksV1CompanyListProvider = FutureProvider.autoDispose
    .family<CompanyListPage, CompanyListQuery>((ref, query) {
      ref.watch(yorksV1AuthUserIdProvider);
      return ref.watch(yorksV1CompanyDocumentsRepositoryProvider).list(query);
    });

/// One record, its documents and history.
final yorksV1CompanyRecordProvider = FutureProvider.autoDispose
    .family<CompanyRecord, String>((ref, recordId) {
      ref.watch(yorksV1AuthUserIdProvider);
      return ref.watch(yorksV1CompanyDocumentsRepositoryProvider).get(recordId);
    });

/// After any write: the home, every register page and the record reload.
void yorksV1RefreshCompanyDocuments(WidgetRef ref, {String? recordId}) {
  ref.invalidate(yorksV1CompanyOverviewProvider);
  ref.invalidate(yorksV1CompanyListProvider);
  if (recordId != null) ref.invalidate(yorksV1CompanyRecordProvider(recordId));
}

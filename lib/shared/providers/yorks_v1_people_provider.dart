import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/yorks_v1_people.dart';
import '../repositories/yorks_v1_people_repository.dart';
import '../sync/connectivity_service.dart';
import 'language_provider.dart' show supabaseClientProvider;
import 'yorks_v1_feature_flags_provider.dart';
import 'yorks_v1_identity_provider.dart';

final yorksV1PeopleRepositoryProvider = Provider<YorksV1PeopleRepository>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);
  return YorksV1PeopleRepository(
    featureFlags: ref.watch(yorksV1FeatureFlagsProvider),
    connectivity: ref.watch(connectivityProvider),
    client: client == null ? null : SupabaseYorksV1PeopleRpcClient(client),
    files: client == null
        ? null
        : SupabaseYorksV1RecordFileClient(client, yorksV1PeopleFilesBucket),
  );
});

/// The People home: counts, companies and what needs attention.
final yorksV1PeopleOverviewProvider =
    FutureProvider.autoDispose<PeopleOverview>((ref) {
      ref.watch(yorksV1AuthUserIdProvider);
      return ref.watch(yorksV1PeopleRepositoryProvider).overview();
    });

/// One register page.
final yorksV1PeopleListProvider = FutureProvider.autoDispose
    .family<PeopleListPage, PeopleListQuery>((ref, query) {
      ref.watch(yorksV1AuthUserIdProvider);
      return ref.watch(yorksV1PeopleRepositoryProvider).list(query);
    });

/// One person's record, documents and history.
final yorksV1PeoplePersonProvider = FutureProvider.autoDispose
    .family<PeoplePerson, String>((ref, workerId) {
      ref.watch(yorksV1AuthUserIdProvider);
      return ref.watch(yorksV1PeopleRepositoryProvider).get(workerId);
    });

/// One person's attachments.
final yorksV1PeopleAttachmentsProvider = FutureProvider.autoDispose
    .family<PeopleAttachments, String>((ref, workerId) {
      ref.watch(yorksV1AuthUserIdProvider);
      return ref.watch(yorksV1PeopleRepositoryProvider).attachments(workerId);
    });

/// How many attachments each person has, for the register.
final yorksV1PeopleAttachmentCountsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) {
      ref.watch(yorksV1AuthUserIdProvider);
      return ref.watch(yorksV1PeopleRepositoryProvider).attachmentCounts();
    });

/// After any write: the home, every register page and the record reload.
void yorksV1RefreshPeople(WidgetRef ref, {String? workerId}) {
  ref.invalidate(yorksV1PeopleOverviewProvider);
  ref.invalidate(yorksV1PeopleListProvider);
  ref.invalidate(yorksV1PeopleAttachmentCountsProvider);
  if (workerId != null) {
    ref.invalidate(yorksV1PeoplePersonProvider(workerId));
    ref.invalidate(yorksV1PeopleAttachmentsProvider(workerId));
  }
}

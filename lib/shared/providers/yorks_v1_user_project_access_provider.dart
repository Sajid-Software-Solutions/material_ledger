import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/yorks_v1_user_project_access.dart';
import '../repositories/yorks_v1_user_project_access_repository.dart';
import 'language_provider.dart';
import 'users_provider.dart';

/// Null when the app is not connected to the Yorks V1 backend (local mode and
/// widget tests). User Management then shows no project figures rather than
/// invented ones.
final yorksV1UserProjectAccessRepositoryProvider =
    Provider<YorksV1UserProjectAccessRepository?>((ref) {
      final client = ref.watch(supabaseClientProvider);
      if (client == null ||
          !ref.watch(yorksV1UserProvisioningEnabledProvider)) {
        return null;
      }
      return YorksV1SupabaseUserProjectAccessRepository(client);
    });

final yorksV1UserProjectAccessProvider =
    FutureProvider.autoDispose<YorksV1UserProjectAccessDirectory?>((ref) {
      final repository = ref.watch(yorksV1UserProjectAccessRepositoryProvider);
      return repository?.load();
    });

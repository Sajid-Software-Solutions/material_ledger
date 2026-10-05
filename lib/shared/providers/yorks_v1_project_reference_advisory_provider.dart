import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/yorks_v1_project_reference_advisory_repository.dart';
import 'language_provider.dart';
import 'yorks_v1_identity_provider.dart';
import 'yorks_v1_permission_provider.dart';

export '../repositories/yorks_v1_project_reference_advisory_repository.dart'
    show YorksV1ProjectReferenceAdvisory;

typedef YorksV1ProjectReferenceAdvisoryQuery = ({
  String reference,
  String? projectId,
});

final yorksV1ProjectReferenceAdvisoryDataClientProvider =
    Provider<YorksV1ProjectReferenceAdvisoryDataClient?>((ref) {
      final client = ref.watch(supabaseClientProvider);
      return client == null
          ? null
          : SupabaseYorksV1ProjectReferenceAdvisoryDataClient(client);
    });

final yorksV1ProjectReferenceAdvisoryRepositoryProvider =
    Provider<YorksV1ProjectReferenceAdvisoryRepository>((ref) {
      return YorksV1ProjectReferenceAdvisoryRepository(
        dataClient: ref.watch(
          yorksV1ProjectReferenceAdvisoryDataClientProvider,
        ),
      );
    });

/// Debounced advisory only. Each reference/edit target and authority context
/// has its own disposable request; a retired response cannot replace the
/// current field's status. No result is persisted or shared as authorization.
final yorksV1ProjectReferenceAdvisoryProvider = FutureProvider.autoDispose
    .family<
      YorksV1ProjectReferenceAdvisory,
      YorksV1ProjectReferenceAdvisoryQuery
    >((ref, query) async {
      final owner = ref.watch(yorksV1AuthUserIdProvider);
      final role = ref.watch(yorksV1CurrentRoleProvider);
      final permission = ref.watch(
        yorksV1CurrentPermissionSnapshotProvider.select(
          (state) => (
            revision: state.snapshot?.revision,
            active: state.snapshot?.user.isActive,
          ),
        ),
      );
      final repository = ref.watch(
        yorksV1ProjectReferenceAdvisoryRepositoryProvider,
      );
      if (owner == null ||
          owner.trim().isEmpty ||
          role == null ||
          !role.canCreateProject ||
          permission.active == false ||
          query.reference.trim().isEmpty) {
        return YorksV1ProjectReferenceAdvisory.unavailable;
      }

      final debounced = Completer<bool>();
      final disposed = Completer<YorksV1ProjectReferenceAdvisory>();
      final timer = Timer(const Duration(milliseconds: 350), () {
        debounced.complete(true);
      });
      ref.onDispose(() {
        timer.cancel();
        if (!debounced.isCompleted) debounced.complete(false);
        if (!disposed.isCompleted) {
          disposed.complete(YorksV1ProjectReferenceAdvisory.unavailable);
        }
      });
      if (!await debounced.future) {
        return YorksV1ProjectReferenceAdvisory.unavailable;
      }
      // The installed PostgREST client has no per-request abort signal. Stop
      // waiting on disposal and ignore the detached request's late response.
      return Future.any([
        repository.check(
          reference: query.reference,
          projectId: query.projectId,
        ),
        disposed.future,
      ]);
    });

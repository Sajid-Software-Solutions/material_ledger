import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/yorks_v1_project_creation_draft.dart';
import '../models/yorks_v1_project_local_creation_draft.dart';
import '../models/yorks_v1_permission_management.dart';
import '../repositories/yorks_v1_project_draft_store.dart';
import '../repositories/yorks_v1_project_local_creation_draft_repository.dart';
import 'language_provider.dart';
import 'yorks_v1_feature_flags_provider.dart';
import 'yorks_v1_identity_provider.dart';
import 'yorks_v1_permission_provider.dart';
import 'yorks_v1_project_creation_draft_provider.dart';

export '../models/yorks_v1_project_local_creation_draft.dart';

/// Does not watch any draft controller/notifier. The portfolio can read this
/// projection while another tab owns the proposal without changing its lease.
final yorksV1ProjectLocalCreationDraftProvider =
    Provider.autoDispose<YorksV1ProjectLocalCreationDraftState>((ref) {
      if (!ref.watch(yorksV1FeatureFlagsProvider).projectSetup) {
        return const YorksV1ProjectLocalCreationDraftState();
      }
      final owner = ref.watch(yorksV1AuthUserIdProvider);
      if (owner == null || owner.trim().isEmpty) {
        return const YorksV1ProjectLocalCreationDraftState();
      }
      final role = ref.watch(yorksV1CurrentRoleProvider);
      if (role?.canCreateProject != true ||
          !ref
              .watch(yorksV1CurrentPermissionSnapshotProvider)
              .hybridAllows(
                YorksV1CapabilityKeys.projectsCreate,
                legacyAllowed: true,
                requireWrite: true,
              )) {
        return const YorksV1ProjectLocalCreationDraftState();
      }
      final backend = ref.watch(yorksV1ProjectDraftBackendIdentityProvider);
      final storage = ref.watch(yorksV1ProjectDraftAtomicStorageProvider);
      final key = yorksV1ProjectDraftStorageKey(
        backendIdentity: backend,
        ownerAuthUserId: owner,
        mode: YorksV1ProjectDraftMode.create,
      );
      if (storage is ProjectDraftStorageChanges) {
        var disposed = false;
        var refreshScheduled = false;
        void scheduleRefresh() {
          if (disposed || refreshScheduled) return;
          refreshScheduled = true;
          scheduleMicrotask(() {
            if (!disposed) ref.invalidateSelf();
          });
        }

        final subscription = (storage as ProjectDraftStorageChanges).changes
            .listen((keys) {
              if (keys.isEmpty ||
                  keys.any(
                    (changed) =>
                        changed == key ||
                        changed == '$key:catalogue' ||
                        changed.startsWith('$key:draft:') ||
                        changed == '$key:latest_operation' ||
                        changed.startsWith('$key:journal:') ||
                        changed == '$key:quarantine' ||
                        changed.startsWith('$key:quarantine:'),
                  )) {
                scheduleRefresh();
              }
            }, onError: (Object _) => scheduleRefresh());
        ref.onDispose(() {
          disposed = true;
          unawaited(subscription.cancel());
        });
      }
      try {
        return YorksV1ProjectLocalCreationDraftRepository(
          storage,
        ).readCatalogue(
          storageKey: key,
          ownerAuthUserId: owner,
          backendIdentity: backend,
          legacyRaw: ref
              .watch(sharedPreferencesProvider)
              .getString('yorks_v1_project_creation_draft_v1_$owner'),
        );
      } catch (_) {
        return const YorksV1ProjectLocalCreationDraftState(
          status: YorksV1ProjectLocalCreationDraftStatus.unavailable,
        );
      }
    });

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import '../controllers/yorks_v1_sourcing_progress_controller.dart';
import '../models/yorks_v1_sourcing_progress.dart';
import '../repositories/yorks_v1_sourcing_progress_repository.dart';
import '../repositories/yorks_v1_material_request_repository.dart';
import '../sync/connectivity_service.dart';
import 'language_provider.dart';
import 'yorks_v1_material_request_provider.dart';
import 'yorks_v1_identity_provider.dart';
import 'yorks_v1_permission_provider.dart';

export '../models/yorks_v1_sourcing_progress.dart';

final yorksV1SourcingProgressRepositoryProvider =
    Provider<YorksV1SourcingProgressRepository>((ref) {
      final client = ref.watch(supabaseClientProvider);
      return YorksV1SupabaseSourcingProgressRepository(
        connectivity: ref.watch(connectivityProvider),
        rpc: client == null
            ? null
            : SupabaseYorksV1MaterialRequestRpcClient(client),
      );
    });

final yorksV1SourcingProgressProvider = StateNotifierProvider.autoDispose
    .family<
      YorksV1SourcingProgressController,
      YorksV1SourcingProgressState,
      YorksV1SourcingScope
    >((ref, scope) {
      final actor = ref.watch(yorksV1AuthUserIdProvider);
      ref.watch(yorksV1CurrentRoleProvider);
      ref.watch(
        yorksV1CurrentPermissionSnapshotProvider.select(
          (value) => (value.snapshot?.revision, value.snapshot?.user.isActive),
        ),
      );
      final controller = YorksV1SourcingProgressController(
        ref.watch(yorksV1SourcingProgressRepositoryProvider),
        scope,
      );
      if (actor == null || actor.isEmpty) {
        controller.deny();
      } else {
        unawaited(controller.load());
      }
      if (scope.arrangementId == null && actor != null && actor.isNotEmpty) {
        // Shared preparation updates deliberately do not create notifications.
        // Refresh only the mounted reader while foregrounded; the editing scope
        // keeps its revision until an explicit refresh to prevent lost updates.
        final refresh = Timer.periodic(const Duration(minutes: 1), (_) {
          if (WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed &&
              ref.read(connectivityProvider).isOnline &&
              controller.canRefresh) {
            unawaited(controller.load(refresh: true));
          }
        });
        ref.onDispose(refresh.cancel);
        ref.listen<int>(yorksV1MaterialRequestRealtimeRevisionProvider, (
          previous,
          next,
        ) {
          if (previous != null && previous != next) ref.invalidateSelf();
        });
      }
      return controller;
    });

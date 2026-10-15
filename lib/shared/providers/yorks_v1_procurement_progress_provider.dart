import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/yorks_v1_procurement_progress_controller.dart';
import '../models/yorks_v1_procurement_progress.dart';
import '../repositories/yorks_v1_material_request_repository.dart';
import '../repositories/yorks_v1_procurement_progress_repository.dart';
import '../services/yorks_v1_procurement_recovery_store.dart';
import '../sync/connectivity_service.dart';
import '../services/analytics_service.dart';
import 'language_provider.dart';
import 'permissions_provider.dart';
import 'session_provider.dart' show authSessionRevisionProvider;
import 'yorks_v1_identity_provider.dart';
import 'yorks_v1_permission_provider.dart';

export '../controllers/yorks_v1_procurement_progress_controller.dart';
export '../models/yorks_v1_procurement_progress.dart';
export '../models/yorks_v1_procurement_progress_strings.dart';

final yorksV1ProcurementProgressRepositoryProvider =
    Provider<YorksV1ProcurementProgressRepository>((ref) {
      final client = ref.watch(supabaseClientProvider);
      return YorksV1SupabaseProcurementProgressRepository(
        connectivity: ref.watch(connectivityProvider),
        rpcClient: client == null
            ? null
            : SupabaseYorksV1MaterialRequestRpcClient(client),
      );
    });

/// Backend URL is part of recovery identity even on same-origin deployments.
final yorksV1ProcurementProgressBackendProvider = Provider<String>(
  (ref) => const String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'unconfigured',
  ),
);

final yorksV1ProcurementProgressControllerProvider = Provider.autoDispose
    .family<
      YorksV1ProcurementProgressController,
      YorksV1ProcurementProgressScope
    >((ref, scope) {
      final actor = ref.read(yorksV1AuthUserIdProvider);
      if (actor == null || actor.isEmpty) {
        throw StateError('Authenticated progress owner required');
      }
      final controller = YorksV1ProcurementProgressController(
        analytics: ref.watch(analyticsServiceProvider),
        repository: ref.watch(yorksV1ProcurementProgressRepositoryProvider),
        recoveryStore: YorksV1ProcurementRecoveryStore(
          preferences: ref.watch(sharedPreferencesProvider),
          backendIdentity: ref.watch(yorksV1ProcurementProgressBackendProvider),
          actorAuthUserId: actor,
        ),
        scope: scope,
        isOnline: () => ref.read(connectivityProvider).isOnline,
      );
      final connection = ref.read(connectivityProvider).onChange.listen((
        online,
      ) {
        if (online) unawaited(controller.recoverPendingCommand());
      });
      ref.onDispose(connection.cancel);
      final resumeObserver = _ProcurementResumeObserver(() {
        unawaited(controller.recoverPendingCommand());
      });
      WidgetsBinding.instance.addObserver(resumeObserver);
      ref.onDispose(
        () => WidgetsBinding.instance.removeObserver(resumeObserver),
      );
      ref.listen(yorksV1AuthUserIdProvider, (previous, next) {
        if (next != actor) {
          unawaited(controller.revoke());
          ref.invalidateSelf();
        }
      });
      ref.listen(authSessionRevisionProvider, (previous, next) {
        if (previous != next && ref.read(yorksV1AuthUserIdProvider) == actor) {
          unawaited(
            controller.revalidateAuthority().then(
              (_) => controller.recoverPendingCommand(),
            ),
          );
        }
      });
      ref.listen(yorksV1CurrentRoleProvider, (previous, next) {
        if (previous != next) {
          unawaited(
            controller.revalidateAuthority().then(
              (_) => controller.recoverPendingCommand(),
            ),
          );
        }
      });
      ref.listen(yorksV1CurrentPermissionSnapshotProvider, (previous, next) {
        if (next.snapshot?.user.isActive == false) {
          unawaited(controller.revoke());
        } else if (previous?.snapshot?.revision != next.snapshot?.revision) {
          unawaited(
            controller.revalidateAuthority().then(
              (_) => controller.recoverPendingCommand(),
            ),
          );
        }
      });
      ref.listen(canViewCommercialsProvider, (previous, next) {
        if (previous == true && !next) controller.clearCommercialInputs();
      });
      ref.onDispose(controller.dispose);
      return controller;
    });

/// The active editor supplies one guard shared by shell and local navigation.
class YorksV1ProcurementExitGuard {
  Future<bool> Function()? check;
  Future<bool> Function()? beforeNavigation;
}

final yorksV1ProcurementExitGuardProvider =
    Provider<YorksV1ProcurementExitGuard>(
      (ref) => YorksV1ProcurementExitGuard(),
    );

class _ProcurementResumeObserver with WidgetsBindingObserver {
  _ProcurementResumeObserver(this.onResume);
  final VoidCallback onResume;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

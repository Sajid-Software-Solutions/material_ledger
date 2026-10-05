import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/analytics_event.dart';
import '../models/yorks_v1_arrangement.dart';
import '../models/yorks_v1_role.dart';
import '../services/analytics_service.dart';
import '../sync/yorks_v1_protected_read_coordinator.dart';
import 'yorks_v1_arrangement_repository_provider.dart';
import 'yorks_v1_identity_provider.dart';
import 'yorks_v1_permission_provider.dart';

final yorksV1ArrangementWorkspaceReadCoordinatorProvider =
    Provider<YorksV1ProtectedReadCoordinator<YorksV1ArrangementWorkspace>>((
      ref,
    ) {
      ref.watch(yorksV1AuthUserIdProvider);
      ref.watch(yorksV1CurrentRoleProvider);
      ref.watch(
        yorksV1CurrentPermissionSnapshotProvider.select(
          (state) => (
            revision: state.snapshot?.revision,
            active: state.snapshot?.user.isActive,
          ),
        ),
      );
      ref.watch(yorksV1ArrangementRepositoryProvider);
      final analytics = ref.watch(analyticsServiceProvider);
      return YorksV1ProtectedReadCoordinator<YorksV1ArrangementWorkspace>(
        onObservation: (observation) => analytics.capture(
          AnalyticsEvent.protectedReadCoordinated,
          properties: {
            AnalyticsProperty.operation: 'procurement_workspace_load',
            AnalyticsProperty.workflow: 'procurement',
            AnalyticsProperty.outcome: observation.outcome,
            AnalyticsProperty.loadTrigger: observation.trigger,
            AnalyticsProperty.coalesced: observation.coalesced,
            AnalyticsProperty.cacheState: observation.cacheState,
            AnalyticsProperty.requestGeneration: observation.generation,
            AnalyticsProperty.visibilityState: observation.visibilityState,
          },
        ),
      );
    });

/// Ordinary engineering readers use the already-authorized controlled
/// document projection for arrangement history. Only transactional
/// Procurement/Admin actors and the retained legacy review surface need the
/// heavier arrangement workspace during MR detail startup.
bool yorksV1ShouldLoadArrangementWorkspaceForDetail({
  required YorksV1Role? role,
  required bool legacyArrangementReview,
}) {
  return legacyArrangementReview ||
      role == YorksV1Role.procurement ||
      role == YorksV1Role.admin;
}

final yorksV1ArrangementWorkspaceProvider = FutureProvider.autoDispose
    .family<YorksV1ArrangementWorkspace, String>((ref, requestId) {
      // An active arrangement is a transactional editor with an expected
      // server version. Rebuilding it on every Realtime/fallback revision can
      // dispose text controllers and inventory state while Procurement is
      // typing. Lists and record details still refresh from Realtime; this
      // editor refreshes only on an explicit user action or confirmed command.
      // A competing write is rejected safely by v1_save_arrangement's version
      // check instead of being merged into the in-progress form.
      yorksV1RefreshProtectedProjectionOnPermissionRevision(ref);
      final repository = ref.watch(yorksV1ArrangementRepositoryProvider);
      return ref
          .watch(yorksV1ArrangementWorkspaceReadCoordinatorProvider)
          .load(key: requestId, read: () => repository.getWorkspace(requestId));
    });

void yorksV1InvalidateArrangementWorkspace(
  WidgetRef ref,
  String requestId, {
  YorksV1ProtectedReadTrigger trigger =
      YorksV1ProtectedReadTrigger.confirmedCommand,
}) {
  ref
      .read(yorksV1ArrangementWorkspaceReadCoordinatorProvider)
      .markStale(requestId, trigger: trigger);
  ref.invalidate(yorksV1ArrangementWorkspaceProvider(requestId));
}

final yorksV1ArrangementInventoryProvider =
    FutureProvider.autoDispose<List<YorksV1InventoryItem>>((ref) {
      return ref
          .watch(yorksV1ArrangementRepositoryProvider)
          .listInventoryItems();
    });

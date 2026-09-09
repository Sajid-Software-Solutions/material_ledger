import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/yorks_v1_project_portfolio.dart';
import '../models/yorks_v1_permission_management.dart';
import '../repositories/yorks_v1_project_portfolio_repository.dart';
import 'language_provider.dart';
import 'yorks_v1_permission_provider.dart';
import 'yorks_v1_feature_flags_provider.dart';
import 'yorks_v1_material_request_provider.dart';
import '../services/analytics_service.dart';

final yorksV1ProjectPortfolioDataClientProvider =
    Provider<YorksV1ProjectPortfolioDataClient?>((ref) {
      final client = ref.watch(supabaseClientProvider);
      return client == null
          ? null
          : SupabaseYorksV1ProjectPortfolioDataClient(client);
    });

final yorksV1ProjectOverviewDataClientProvider =
    Provider<YorksV1ProjectOverviewDataClient?>((ref) {
      final client = ref.watch(supabaseClientProvider);
      return client == null
          ? null
          : SupabaseYorksV1ProjectOverviewDataClient(client);
    });

final yorksV1ProjectPortfolioRepositoryProvider =
    Provider<YorksV1ProjectPortfolioRepository>((ref) {
      return YorksV1SupabaseProjectPortfolioRepository(
        featureFlags: ref.watch(yorksV1FeatureFlagsProvider),
        dataClient: ref.watch(yorksV1ProjectPortfolioDataClientProvider),
        analytics: ref.watch(analyticsServiceProvider),
      );
    });

/// Authorized project-only rows for the R35 portfolio. Invalidating this
/// provider re-runs the same RLS-protected read; it never falls back to a
/// legacy local project register.
final yorksV1ProjectPortfolioProvider =
    FutureProvider.autoDispose<List<YorksV1ProjectPortfolioItem>>((ref) {
      yorksV1RefreshProtectedProjectionOnPermissionRevision(ref);
      // Recent-request counts and action cues are server projections. Refresh
      // them when the recipient receives a V1 workflow notification rather
      // than attempting to patch portfolio state in the browser.
      ref.listen<int>(yorksV1MaterialRequestRealtimeRevisionProvider, (
        previous,
        next,
      ) {
        if (previous != null && previous != next) ref.invalidateSelf();
      });
      return ref
          .watch(yorksV1ProjectPortfolioRepositoryProvider)
          .listPortfolio();
    });

/// Bounded startup projection. Connected builds use one protected RPC;
/// disconnected test/demo builds derive the same shape from the retained
/// portfolio provider so there is no second source of truth.
final yorksV1ProjectOverviewProvider =
    FutureProvider.autoDispose<YorksV1ProjectOverview>((ref) async {
      yorksV1RefreshProtectedProjectionOnPermissionRevision(ref);
      ref.listen<int>(yorksV1MaterialRequestRealtimeRevisionProvider, (
        previous,
        next,
      ) {
        if (previous != null && previous != next) ref.invalidateSelf();
      });
      final client = ref.watch(yorksV1ProjectOverviewDataClientProvider);
      if (client == null) {
        return YorksV1ProjectOverview.fromItems(
          await ref.watch(yorksV1ProjectPortfolioProvider.future),
        );
      }
      return YorksV1ProjectOverviewRepository(
        featureFlags: ref.watch(yorksV1FeatureFlagsProvider),
        dataClient: client,
        analytics: ref.watch(analyticsServiceProvider),
      ).getOverview();
    });

/// Immediately removes projects denied by the latest confirmed permission
/// snapshot, even while the protected portfolio is being re-fetched. Shadow
/// capabilities retain the RLS-filtered legacy result; candidates never grant.
final yorksV1AuthorizedProjectPortfolioProvider =
    Provider.autoDispose<AsyncValue<List<YorksV1ProjectPortfolioItem>>>((ref) {
      final permissionState = ref.watch(
        yorksV1CurrentPermissionSnapshotProvider,
      );
      return ref.watch(yorksV1ProjectPortfolioProvider).whenData((projects) {
        final snapshot = permissionState.snapshot;
        final capability = snapshot?.capability(
          YorksV1CapabilityKeys.projectsView,
        );
        if (snapshot == null || capability == null || !snapshot.user.isActive) {
          return const <YorksV1ProjectPortfolioItem>[];
        }
        if (capability.authorizationMode ==
            YorksV1PermissionCapabilityAuthorizationMode.shadow) {
          return projects;
        }
        return projects
            .where(
              (project) => snapshot.allows(
                YorksV1CapabilityKeys.projectsView,
                projectId: project.project.id,
              ),
            )
            .toList(growable: false);
      });
    });

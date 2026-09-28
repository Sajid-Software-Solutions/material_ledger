import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/yorks_v1_project_portfolio.dart';
import '../models/yorks_v1_permission_management.dart';
import '../repositories/yorks_v1_project_portfolio_repository.dart';
import '../services/analytics_service.dart';
import 'language_provider.dart';
import 'yorks_v1_feature_flags_provider.dart';
import 'yorks_v1_identity_provider.dart';
import 'yorks_v1_permission_provider.dart';

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

/// Shares only an active portfolio read, never a completed authorization
/// result. The coordinator itself is recreated whenever the authenticated
/// identity, exact server role, or confirmed permission revision changes, so
/// an old-authority request cannot satisfy a new-authority projection.
final yorksV1ProjectPortfolioLoadCoordinatorProvider =
    Provider<YorksV1ProjectPortfolioLoadCoordinator>((ref) {
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
      return YorksV1ProjectPortfolioLoadCoordinator(
        ref.watch(yorksV1ProjectPortfolioRepositoryProvider),
      );
    });

class YorksV1ProjectPortfolioLoadCoordinator {
  YorksV1ProjectPortfolioLoadCoordinator(this._repository);

  final YorksV1ProjectPortfolioRepository _repository;
  Future<List<YorksV1ProjectPortfolioItem>>? _inFlight;
  Object? _inFlightToken;

  Future<List<YorksV1ProjectPortfolioItem>> load() {
    final active = _inFlight;
    if (active != null) return active;

    final token = Object();
    _inFlightToken = token;
    final next = _run(token);
    _inFlight = next;
    return next;
  }

  Future<List<YorksV1ProjectPortfolioItem>> _run(Object token) async {
    try {
      return await _repository.listPortfolio();
    } finally {
      if (identical(_inFlightToken, token)) {
        _inFlight = null;
        _inFlightToken = null;
      }
    }
  }
}

/// Authorized project-only rows for the R35 portfolio. Invalidating this
/// provider re-runs the same RLS-protected read; it never falls back to a
/// legacy local project register.
final yorksV1ProjectPortfolioProvider =
    FutureProvider.autoDispose<List<YorksV1ProjectPortfolioItem>>((ref) {
      // Project context is shared by Projects, project Accounts, and company
      // Accounts. Preserve it across short route gaps; explicit project,
      // identity, role, and permission invalidations still recreate it.
      ref.keepAlive();
      yorksV1RefreshProtectedProjectionOnPermissionRevision(ref);
      return ref.watch(yorksV1ProjectPortfolioLoadCoordinatorProvider).load();
    });

/// Bounded startup projection. Connected builds use one protected RPC;
/// disconnected test/demo builds derive the same shape from the retained
/// portfolio provider so there is no second source of truth.
final yorksV1ProjectOverviewProvider =
    FutureProvider.autoDispose<YorksV1ProjectOverview>((ref) async {
      yorksV1RefreshProtectedProjectionOnPermissionRevision(ref);
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

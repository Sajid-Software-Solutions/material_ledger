import '../../../shared/services/analytics_service.dart';
import '../data/company_analytics_project_options.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/yorks_v1_permission_management.dart';
import '../../../shared/models/yorks_v1_domain_error.dart';
import '../../../shared/providers/language_provider.dart';
import '../../../shared/providers/yorks_v1_feature_flags_provider.dart';
import '../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../../shared/providers/yorks_v1_permission_provider.dart';
import '../../../shared/sync/connectivity_service.dart';
import '../data/company_analytics_repository.dart';
import '../domain/company_analytics_models.dart';

final companyAnalyticsRpcClientProvider = Provider<CompanyAnalyticsRpcClient?>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseCompanyAnalyticsRpcClient(client);
});

final companyAnalyticsRepositoryProvider = Provider<CompanyAnalyticsRepository>(
  (ref) {
    return SupabaseCompanyAnalyticsRepository(
      featureFlags: ref.watch(yorksV1FeatureFlagsProvider),
      connectivity: ref.watch(connectivityProvider),
      analytics: ref.watch(analyticsServiceProvider),
      rpcClient: ref.watch(companyAnalyticsRpcClientProvider),
    );
  },
);

typedef CompanyAnalyticsAuthorityEpoch = ({
  String? actorAuthUserId,
  int? permissionRevision,
  bool active,
  bool enabled,
  bool canView,
});

final companyAnalyticsAuthorityEpochProvider =
    Provider<CompanyAnalyticsAuthorityEpoch>((ref) {
      final permission = ref.watch(yorksV1CurrentPermissionSnapshotProvider);
      return (
        actorAuthUserId: ref.watch(yorksV1AuthUserIdProvider),
        permissionRevision: permission.snapshot?.revision,
        active: permission.snapshot?.user.isActive == true,
        enabled: ref.watch(yorksV1FeatureFlagsProvider).analytics,
        canView: permission.hybridAllows(
          YorksV1CapabilityKeys.analyticsView,
          legacyAllowed: false,
          organizationSummary: true,
        ),
      );
    });

final companyAnalyticsProjectionProvider = FutureProvider.autoDispose
    .family<CompanyAnalyticsProjection, CompanyAnalyticsFilters>((
      ref,
      filters,
    ) async {
      yorksV1RefreshProtectedProjectionOnPermissionRevision(ref);
      final authority = ref.watch(companyAnalyticsAuthorityEpochProvider);
      if (!authority.enabled ||
          !authority.active ||
          authority.actorAuthUserId == null ||
          !authority.canView) {
        throw const YorksV1DomainException(YorksV1DomainErrorCode.unauthorized);
      }
      return ref
          .watch(companyAnalyticsRepositoryProvider)
          .getProjection(filters);
    });

final companyAnalyticsProjectOptionsProvider =
    FutureProvider.autoDispose<List<CompanyAnalyticsProjectOption>>((
      ref,
    ) async {
      final authority = ref.watch(companyAnalyticsAuthorityEpochProvider);
      if (!authority.enabled ||
          !authority.active ||
          authority.actorAuthUserId == null ||
          !authority.canView) {
        throw const YorksV1DomainException(YorksV1DomainErrorCode.unauthorized);
      }
      if (!ref.watch(connectivityProvider).isOnline) {
        throw const YorksV1DomainException(YorksV1DomainErrorCode.offline);
      }
      final client = ref.watch(supabaseClientProvider);
      if (client == null) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.backendUnavailable,
        );
      }
      return CompanyAnalyticsProjectOptionsRepository(client).load();
    });

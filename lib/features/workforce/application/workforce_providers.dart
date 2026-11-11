import 'workforce_team_workers_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/yorks_v1_permission_management.dart';
import '../../../shared/models/yorks_v1_role.dart';
import '../../../shared/providers/language_provider.dart';
import '../../../shared/providers/yorks_v1_feature_flags_provider.dart';
import '../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../../shared/providers/yorks_v1_permission_provider.dart';
import '../../../shared/repositories/yorks_v1_documents_repository.dart';
import '../../../shared/services/yorks_v1_critical_command_key_store.dart';
import '../../../shared/sync/connectivity_service.dart';
import '../data/workforce_repository.dart';
import '../data/workforce_report_service.dart';
import '../domain/workforce_dashboard_models.dart';
import 'workforce_administration_controller.dart';
import 'workforce_daily_roster_controller.dart';
import 'workforce_dashboard_controller.dart';
import 'workforce_collaboration_controller.dart';
import 'workforce_monthly_period_controller.dart';
import 'workforce_review_controller.dart';
import 'workforce_report_controller.dart';

final yorksWorkforceRpcClientProvider = Provider<YorksWorkforceRpcClient?>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseYorksWorkforceRpcClient(client);
});

final yorksWorkforceRepositoryProvider = Provider<YorksWorkforceRepository>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);
  return YorksSupabaseWorkforceRepository(
    featureFlags: ref.watch(yorksV1FeatureFlagsProvider),
    connectivity: ref.watch(connectivityProvider),
    rpcClient: ref.watch(yorksWorkforceRpcClientProvider),
    documentStorageClient: client == null
        ? null
        : SupabaseYorksV1DocumentStorageClient(client),
    documentFinalizerClient: client == null
        ? null
        : SupabaseYorksV1DocumentFinalizerClient(client),
  );
});

final yorksWorkforceReviewRepositoryProvider =
    Provider<YorksWorkforceReviewRepository>((ref) {
      final repository = ref.watch(yorksWorkforceRepositoryProvider);
      if (repository is! YorksWorkforceReviewRepository) {
        throw StateError('Workforce review repository is unavailable');
      }
      return repository as YorksWorkforceReviewRepository;
    });

final yorksWorkforceCollaborationRepositoryProvider =
    Provider<YorksWorkforceCollaborationRepository>((ref) {
      final repository = ref.watch(yorksWorkforceRepositoryProvider);
      if (repository is! YorksWorkforceCollaborationRepository) {
        throw StateError('Workforce collaboration repository is unavailable');
      }
      return repository as YorksWorkforceCollaborationRepository;
    });

final yorksWorkforceReportRepositoryProvider =
    Provider<YorksWorkforceReportRepository>((ref) {
      final repository = ref.watch(yorksWorkforceRepositoryProvider);
      if (repository is! YorksWorkforceReportRepository) {
        throw StateError('Workforce report repository is unavailable');
      }
      return repository as YorksWorkforceReportRepository;
    });

final yorksWorkforceDashboardRepositoryProvider =
    Provider<YorksWorkforceDashboardRepository>((ref) {
      final repository = ref.watch(yorksWorkforceRepositoryProvider);
      if (repository is! YorksWorkforceDashboardRepository) {
        throw StateError('Workforce dashboard repository is unavailable');
      }
      return repository as YorksWorkforceDashboardRepository;
    });

final yorksWorkforceReportBinaryServiceProvider =
    Provider<YorksWorkforceReportBinaryService>(
      (_) => const YorksWorkforceReportService(),
    );

typedef YorksWorkforceAuthorityEpoch = ({
  String? actorAuthUserId,
  Object? exactRole,
  int? revision,
  bool featureEnabled,
  bool active,
  bool canView,
  bool canMaintainAttendance,
  bool canMaintainTimesheets,
  bool canReviewTimesheets,
  bool canCorrectDuringReview,
  bool canVerifyTimesheets,
  bool canFinalApproveTimesheets,
  bool canReopenPeriods,
  bool canExportReports,
  bool canManageWorkers,
  bool canManageTeams,
  bool canManageConfiguration,
  bool trustedForWrites,
});

/// Carries authorization identity/revision only; it contains no roster values.
/// Any field change disposes the protected T05 controller and its local edits.
final yorksWorkforceAuthorityEpochProvider =
    Provider<YorksWorkforceAuthorityEpoch>((ref) {
      final permission = ref.watch(yorksV1CurrentPermissionSnapshotProvider);
      final snapshot = permission.snapshot;
      return (
        actorAuthUserId: ref.watch(yorksV1AuthUserIdProvider),
        exactRole: ref.watch(yorksV1CurrentRoleProvider),
        revision: snapshot?.revision,
        featureEnabled: ref.watch(yorksV1FeatureFlagsProvider).workforce,
        active: snapshot?.user.isActive == true,
        canView: permission.allowsWorkforceSummary(
          YorksV1CapabilityKeys.workforceView,
        ),
        canMaintainAttendance:
            snapshot?.allows(
              YorksV1CapabilityKeys.workforceAttendanceMaintain,
            ) ==
            true,
        canMaintainTimesheets:
            snapshot?.allows(
              YorksV1CapabilityKeys.workforceTimesheetsMaintain,
            ) ==
            true,
        canReviewTimesheets:
            snapshot?.allows(YorksV1CapabilityKeys.workforceTimesheetsReview) ==
            true,
        canCorrectDuringReview:
            snapshot?.allows(
              YorksV1CapabilityKeys.workforceTimesheetsCorrectDuringReview,
            ) ==
            true,
        canVerifyTimesheets:
            snapshot?.allows(YorksV1CapabilityKeys.workforceTimesheetsVerify) ==
            true,
        canFinalApproveTimesheets:
            snapshot?.allows(
              YorksV1CapabilityKeys.workforceTimesheetsFinalApprove,
            ) ==
            true,
        canReopenPeriods:
            snapshot?.allows(YorksV1CapabilityKeys.workforcePeriodsReopen) ==
            true,
        canExportReports:
            snapshot?.allows(YorksV1CapabilityKeys.workforceReportsExport) ==
            true,
        canManageWorkers:
            snapshot?.allows(YorksV1CapabilityKeys.workforceWorkersManage) ==
            true,
        canManageTeams:
            snapshot?.allows(YorksV1CapabilityKeys.workforceTeamsManage) ==
            true,
        canManageConfiguration:
            snapshot?.allows(
              YorksV1CapabilityKeys.workforceConfigurationManage,
            ) ==
            true,
        trustedForWrites: permission.isTrustedForWrites,
      );
    });

final yorksWorkforceAdministrationControllerProvider =
    StateNotifierProvider.autoDispose<
      YorksWorkforceAdministrationController,
      YorksWorkforceAdministrationState
    >((ref) {
      ref.keepAlive();
      final epoch = ref.watch(yorksWorkforceAuthorityEpochProvider);
      final controller = YorksWorkforceAdministrationController(
        repository: ref.watch(yorksWorkforceRepositoryProvider),
        commandKeys: YorksV1CriticalCommandKeyStore(
          preferences: ref.watch(sharedPreferencesProvider),
          actorAuthUserId: epoch.actorAuthUserId ?? 'inactive',
        ),
        connectivity: ref.watch(connectivityProvider),
        canManageWorkers: epoch.canManageWorkers,
        canManageTeams: epoch.canManageTeams,
        canManageConfiguration: epoch.canManageConfiguration,
      );
      if (!epoch.featureEnabled ||
          epoch.actorAuthUserId == null ||
          !epoch.active ||
          !epoch.canView ||
          !epoch.trustedForWrites ||
          (!epoch.canManageWorkers &&
              !epoch.canManageTeams &&
              !epoch.canManageConfiguration)) {
        controller.purgeProtectedState(unavailable: !epoch.featureEnabled);
      }
      return controller;
    });

final yorksWorkforceDailyRosterControllerProvider =
    StateNotifierProvider.autoDispose<
      YorksWorkforceDailyRosterController,
      YorksWorkforceDailyRosterState
    >((ref) {
      ref.keepAlive();
      final epoch = ref.watch(yorksWorkforceAuthorityEpochProvider);
      final controller = YorksWorkforceDailyRosterController(
        repository: ref.watch(yorksWorkforceRepositoryProvider),
        commandKeys: YorksV1CriticalCommandKeyStore(
          preferences: ref.watch(sharedPreferencesProvider),
          actorAuthUserId: epoch.actorAuthUserId ?? 'inactive',
        ),
        connectivity: ref.watch(connectivityProvider),
      );
      if (!epoch.featureEnabled ||
          epoch.actorAuthUserId == null ||
          !epoch.active ||
          !epoch.canView) {
        controller.purgeProtectedState(unavailable: !epoch.featureEnabled);
      }
      return controller;
    });

final yorksWorkforceDashboardControllerProvider =
    StateNotifierProvider.autoDispose<
      YorksWorkforceDashboardController,
      YorksWorkforceOverviewState
    >((ref) {
      ref.keepAlive();
      final epoch = ref.watch(yorksWorkforceAuthorityEpochProvider);
      final role = ref.watch(yorksV1CurrentRoleProvider);
      final kind = switch (role) {
        YorksV1Role.admin => YorksWorkforceOverviewKind.admin,
        YorksV1Role.projectManager || YorksV1Role.seniorMechanicalEngineer =>
          YorksWorkforceOverviewKind.management,
        _ => YorksWorkforceOverviewKind.supervisor,
      };
      final controller = YorksWorkforceDashboardController(
        repository: ref.watch(yorksWorkforceDashboardRepositoryProvider),
        connectivity: ref.watch(connectivityProvider),
        kind: kind,
      );
      if (!epoch.featureEnabled ||
          epoch.actorAuthUserId == null ||
          !epoch.active ||
          !epoch.canView) {
        controller.purgeProtectedState(unavailable: !epoch.featureEnabled);
      }
      return controller;
    });

final yorksWorkforceMonthlyControllerProvider =
    StateNotifierProvider.autoDispose<
      YorksWorkforceMonthlyController,
      YorksWorkforceMonthlyState
    >((ref) {
      ref.keepAlive();
      final epoch = ref.watch(yorksWorkforceAuthorityEpochProvider);
      final controller = YorksWorkforceMonthlyController(
        repository: ref.watch(yorksWorkforceRepositoryProvider),
        commandKeys: YorksV1CriticalCommandKeyStore(
          preferences: ref.watch(sharedPreferencesProvider),
          actorAuthUserId: epoch.actorAuthUserId ?? 'inactive',
        ),
        connectivity: ref.watch(connectivityProvider),
      );
      if (!epoch.featureEnabled ||
          epoch.actorAuthUserId == null ||
          !epoch.active ||
          !epoch.canView) {
        controller.purgeProtectedState(unavailable: !epoch.featureEnabled);
      }
      return controller;
    });

final yorksWorkforceReviewControllerProvider =
    StateNotifierProvider.autoDispose<
      YorksWorkforceReviewController,
      YorksWorkforceReviewState
    >((ref) {
      ref.keepAlive();
      final epoch = ref.watch(yorksWorkforceAuthorityEpochProvider);
      final controller = YorksWorkforceReviewController(
        repository: ref.watch(yorksWorkforceReviewRepositoryProvider),
        commandKeys: YorksV1CriticalCommandKeyStore(
          preferences: ref.watch(sharedPreferencesProvider),
          actorAuthUserId: epoch.actorAuthUserId ?? 'inactive',
        ),
        connectivity: ref.watch(connectivityProvider),
      );
      if (!epoch.featureEnabled ||
          epoch.actorAuthUserId == null ||
          !epoch.active ||
          !epoch.canView) {
        controller.purgeProtectedState(unavailable: !epoch.featureEnabled);
      }
      return controller;
    });

final yorksWorkforceCollaborationControllerProvider =
    StateNotifierProvider.autoDispose<
      YorksWorkforceCollaborationController,
      YorksWorkforceCollaborationState
    >((ref) {
      ref.keepAlive();
      final epoch = ref.watch(yorksWorkforceAuthorityEpochProvider);
      final controller = YorksWorkforceCollaborationController(
        repository: ref.watch(yorksWorkforceCollaborationRepositoryProvider),
        commandKeys: YorksV1CriticalCommandKeyStore(
          preferences: ref.watch(sharedPreferencesProvider),
          actorAuthUserId: epoch.actorAuthUserId ?? 'inactive',
        ),
        connectivity: ref.watch(connectivityProvider),
      );
      if (!epoch.featureEnabled ||
          epoch.actorAuthUserId == null ||
          !epoch.active ||
          !epoch.canView) {
        controller.purgeProtectedState(unavailable: !epoch.featureEnabled);
      }
      return controller;
    });

final yorksWorkforceReportControllerProvider =
    StateNotifierProvider.autoDispose<
      YorksWorkforceReportController,
      YorksWorkforceReportState
    >((ref) {
      ref.keepAlive();
      final epoch = ref.watch(yorksWorkforceAuthorityEpochProvider);
      final controller = YorksWorkforceReportController(
        repository: ref.watch(yorksWorkforceReportRepositoryProvider),
        binaryService: ref.watch(yorksWorkforceReportBinaryServiceProvider),
        commandKeys: YorksV1CriticalCommandKeyStore(
          preferences: ref.watch(sharedPreferencesProvider),
          actorAuthUserId: epoch.actorAuthUserId ?? 'inactive',
        ),
        connectivity: ref.watch(connectivityProvider),
      );
      if (!epoch.featureEnabled ||
          epoch.actorAuthUserId == null ||
          !epoch.active ||
          !epoch.canView ||
          !epoch.canExportReports) {
        controller.purgeProtectedState(unavailable: !epoch.featureEnabled);
      }
      return controller;
    });

final yorksWorkforceTeamWorkersProvider =
    StateNotifierProvider.autoDispose<
      WorkforceTeamWorkersController,
      AsyncValue<Map<String, dynamic>>
    >((ref) {
      final epoch = ref.watch(yorksWorkforceAuthorityEpochProvider);
      final repository =
          ref.watch(yorksWorkforceRepositoryProvider)
              as YorksWorkforceTeamWorkerRepository;
      return WorkforceTeamWorkersController(
        repository,
        YorksV1CriticalCommandKeyStore(
          preferences: ref.watch(sharedPreferencesProvider),
          actorAuthUserId: epoch.actorAuthUserId ?? 'inactive',
        ),
      );
    });

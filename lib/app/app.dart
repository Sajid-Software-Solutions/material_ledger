import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/hardware/hardware_action_service.dart';
import '../core/security/session_lock.dart';
import '../core/scroll/yorks_scroll_behavior.dart';
import '../core/theme/app_theme.dart';
import '../features/system/presentation/screens/lock_screen.dart';
import '../features/accounts/application/accounts_portfolio_providers.dart';
import '../features/accounts/application/accounts_providers.dart';
import '../features/accounts/application/accounts_receivables_providers.dart';
import '../features/accounts/application/accounts_supplier_providers.dart';
import '../features/company_overview/application/company_analytics_providers.dart';
import '../features/workforce/application/workforce_providers.dart';
import '../shared/providers/language_provider.dart';
import '../shared/providers/analytics_identity_provider.dart';
import '../shared/providers/role_permissions_provider.dart';
import '../shared/providers/session_provider.dart';
import '../shared/providers/yorks_v1_arrangement_provider.dart';
import '../shared/providers/yorks_v1_boq_provider.dart';
import '../shared/providers/yorks_v1_documents_provider.dart';
import '../shared/providers/yorks_v1_feature_flags_provider.dart';
import '../shared/providers/yorks_v1_identity_provider.dart';
import '../shared/providers/yorks_v1_logistics_provider.dart';
import '../shared/providers/yorks_v1_material_request_provider.dart';
import '../shared/providers/yorks_v1_permission_provider.dart';
import '../shared/providers/yorks_v1_project_portfolio_provider.dart';
import '../shared/providers/yorks_v1_project_setup_navigation_provider.dart';
import '../shared/services/app_config_service.dart';
import '../shared/services/analytics_route_mapper.dart';
import '../shared/services/analytics_service.dart';
import '../shared/widgets/notification_alert_host.dart';
import '../shared/widgets/notification_attention_host.dart';
import 'router.dart';
import 'startup/app_startup_coordinator.dart';
import 'yorks_localizations.dart';

/// Bridges [rolePermissionsProvider] changes to the router's refreshListenable.
class _RouterRefresh extends ChangeNotifier {
  void ping() => notifyListeners();
}

void _invalidateYorksV1ProtectedProjectionCaches(Ref ref) {
  // A permission revision is a refresh signal, never a row-level transaction.
  // Destroy each protected cache so a revoked project/request cannot remain in
  // memory while the same actor retains access to other projects.
  ref.invalidate(yorksV1ProjectPortfolioProvider);
  ref.invalidate(yorksV1ProjectOverviewProvider);
  ref.invalidate(yorksV1BoqGroupsProvider);
  ref.invalidate(yorksV1ScopedBoqGroupsProvider);
  ref.invalidate(yorksV1BoqWorksheetControllerProvider);
  ref.invalidate(yorksV1DocumentWorkspaceProvider);
  ref.invalidate(yorksV1MaterialRequestSummaryPageProvider);
  ref.invalidate(yorksV1MaterialRequestCommentPageProvider);
  ref.invalidate(yorksV1MaterialRequestWorkAssignmentProvider);
  ref.invalidate(yorksV1MaterialRequestChangeSummaryProvider);
  ref.invalidate(yorksV1MaterialRequestListProvider);
  ref.invalidate(yorksV1MaterialRequestDraftProjectsProvider);
  ref.invalidate(yorksV1MaterialRequestScopesProvider);
  ref.invalidate(yorksV1MaterialRequestMentionCandidatesProvider);
  ref.invalidate(yorksV1MaterialRequestInventorySearchProvider);
  ref.invalidate(yorksV1MaterialRequestDetailProvider);
  ref.invalidate(yorksV1MaterialRequestPhase3PolicyProvider);
  ref.invalidate(yorksV1MaterialRequestDocumentProvider);
  ref.invalidate(yorksV1ArrangementWorkspaceProvider);
  ref.invalidate(yorksV1ArrangementInventoryProvider);
  ref.invalidate(yorksV1LogisticsWorkspaceProvider);
  ref.invalidate(yorksV1ProjectMaterialMovementsProvider);
  ref.invalidate(yorksV1ReturnsDocumentsWorkspaceProvider);
  ref.invalidate(yorksV1MaterialReturnRegisterProvider);
  ref.invalidate(yorksV1MaterialReturnProjectsProvider);
  ref.invalidate(yorksV1ProjectMaterialReturnProvider);
  ref.invalidate(yorksV1MaterialReturnCreationWorkspaceProvider);
  ref.invalidate(yorksAccountsPortfolioControllerProvider);
  ref.invalidate(yorksAccountsProjectOverviewControllerProvider);
  ref.invalidate(yorksAccountsProjectControllerProvider);
  ref.invalidate(yorksAccountsReceivablesControllerProvider);
  ref.invalidate(yorksAccountsSupplierControllerProvider);
  ref.invalidate(yorksWorkforceDailyRosterControllerProvider);
  ref.invalidate(yorksWorkforceMonthlyControllerProvider);
  ref.invalidate(companyAnalyticsProjectionProvider);
}

/// Provider for the app router — lives here so the incremental
/// compiler always sees it in the same unit as [MaterialLedgerApp].
class _RouterLocationMemory {
  _RouterLocationMemory(this.location);
  String? location;
}

String? captureAppLaunchLocation() => initialAppLocation(
  browserUri: kIsWeb ? Uri.base : null,
  platformLocation: WidgetsBinding.instance.platformDispatcher.defaultRouteName,
);

/// main() overrides this with the location captured before its temporary
/// startup MaterialApp renders. Direct app mounts retain the platform fallback.
final appLaunchLocationProvider = Provider<String?>(
  (ref) => captureAppLaunchLocation(),
);

final _routerLocationMemoryProvider = Provider(
  (ref) => _RouterLocationMemory(ref.read(appLaunchLocationProvider)),
);
final appRouterProvider = Provider<GoRouter>((ref) {
  final memory = ref.read(_routerLocationMemoryProvider);
  final isOnboarded = ref.watch(onboardingCompleteProvider);
  final isLoggedIn = ref.watch(isLoggedInProvider);
  final role = ref.watch(currentRoleProvider);
  // The Admin directory is presentation data. A roster refresh may replace
  // names, emails or other users, but must not reconstruct GoRouter and throw
  // away the current location. Observe only fields that route guards actually
  // consume, then read the matching user snapshot when one of those fields
  // changes.
  ref.watch(
    currentUserProvider.select(
      (user) => user == null
          ? null
          : (
              id: user.id,
              role: user.role,
              active: user.active,
              mustChangePassword: user.mustChangePassword,
              canSeeCost: user.canSeeCostOverride,
              canViewFinance: user.canViewFinanceOverride,
              canSeeSalary: user.canSeeSalaryOverride,
              canAccessRentals: user.canAccessRentalsOverride,
              canAccessPeople: user.canAccessPeopleOverride,
              canReceiveGoods: user.canReceiveGoodsOverride,
            ),
    ),
  );
  final user = ref.read(currentUserProvider);
  final gate = ref.watch(appGateProvider);
  final yorksV1ProjectsEnabled = ref
      .watch(yorksV1FeatureFlagsProvider)
      .projects;
  final yorksV1BoqEnabled = ref.watch(yorksV1FeatureFlagsProvider).boq;
  final yorksV1RequestsEnabled = ref
      .watch(yorksV1FeatureFlagsProvider)
      .requests;
  final yorksV1ArrangementEnabled = ref
      .watch(yorksV1FeatureFlagsProvider)
      .arrangement;
  final yorksV1LogisticsEnabled = ref
      .watch(yorksV1FeatureFlagsProvider)
      .logistics;
  final yorksV1ReturnsDocumentsEnabled = ref
      .watch(yorksV1FeatureFlagsProvider)
      .returnsDocuments;
  final yorksV1DocumentsEnabled = ref
      .watch(yorksV1FeatureFlagsProvider)
      .documents;
  final yorksV1TeamChatEnabled = ref
      .watch(yorksV1FeatureFlagsProvider)
      .teamChat;
  final yorksV1InventorySuppliersEnabled = ref
      .watch(yorksV1FeatureFlagsProvider)
      .inventorySuppliers;
  final yorksV1CompanyMaterialRequestsEnabled = ref
      .watch(yorksV1FeatureFlagsProvider)
      .companyMaterialRequests;
  final yorksV1AccountsEnabled = ref
      .watch(yorksV1FeatureFlagsProvider)
      .accounts;
  final yorksV1WorkforceEnabled = ref
      .watch(yorksV1FeatureFlagsProvider)
      .workforce;
  final yorksV1AnalyticsEnabled = ref
      .watch(yorksV1FeatureFlagsProvider)
      .analytics;
  final yorksV1Role = ref.watch(yorksV1CurrentRoleProvider);
  final connectedV1Permissions =
      yorksV1ProjectsEnabled && ref.watch(supabaseClientProvider) != null;

  // Re-run route guards when an Admin edits role permissions — WITHOUT
  // rebuilding the router (which would reset navigation). We bridge the provider
  // to a Listenable and read it live in the redirect.
  final refresh = _RouterRefresh();
  ref.listen(rolePermissionsProvider, (_, _) => refresh.ping());
  ref.listen(yorksV1CurrentPermissionSnapshotProvider, (previous, next) {
    refresh.ping();
    final previousSnapshot = previous?.snapshot;
    if (previousSnapshot == null) return;
    final nextSnapshot = next.snapshot;
    if (nextSnapshot == null ||
        nextSnapshot.revision != previousSnapshot.revision) {
      _invalidateYorksV1ProtectedProjectionCaches(ref);
    }
  });
  ref.onDispose(refresh.dispose);

  final router = createAppRouter(
    restoredLocation: memory.location,
    isOnboarded: isOnboarded,
    isLoggedIn: isLoggedIn,
    role: role,
    user: user,
    gate: gate,
    yorksV1ProjectsEnabled: yorksV1ProjectsEnabled,
    yorksV1ProjectSetupEnabled:
        ref.watch(yorksV1FeatureFlagsProvider).projectSetup && kIsWeb,
    onLeaveYorksProjectSetup: () =>
        ref.read(yorksV1ProjectSetupNavigationGuardProvider).canLeave(),
    onSelectYorksProjectSetup: (draftId, legacyRecovery) => ref
        .read(yorksV1ProjectSetupNavigationGuardProvider)
        .canSelectCreation(draftId, legacyRecovery: legacyRecovery),
    yorksV1BoqEnabled: yorksV1BoqEnabled,
    yorksV1RequestsEnabled: yorksV1RequestsEnabled,
    yorksV1ArrangementEnabled: yorksV1ArrangementEnabled,
    yorksV1LogisticsEnabled: yorksV1LogisticsEnabled,
    yorksV1ReturnsDocumentsEnabled: yorksV1ReturnsDocumentsEnabled,
    yorksV1DocumentsEnabled: yorksV1DocumentsEnabled,
    yorksV1TeamChatEnabled: yorksV1TeamChatEnabled,
    yorksV1InventorySuppliersEnabled: yorksV1InventorySuppliersEnabled,
    yorksV1CompanyMaterialRequestsEnabled:
        yorksV1CompanyMaterialRequestsEnabled,
    yorksV1AccountsEnabled: yorksV1AccountsEnabled,
    yorksV1WorkforceEnabled: yorksV1WorkforceEnabled,
    yorksV1AnalyticsEnabled: yorksV1AnalyticsEnabled,
    yorksV1Role: yorksV1Role,
    yorksV1PermissionResolver: connectedV1Permissions
        ? (
            capabilityKey, {
            required legacyAllowed,
            requireWrite = false,
            organizationSummary = false,
            projectId,
          }) => ref
              .read(yorksV1CurrentPermissionSnapshotProvider)
              .hybridRouteAllows(
                capabilityKey,
                legacyAllowed: legacyAllowed,
                requireWrite: requireWrite,
                organizationSummary: organizationSummary,
                projectId: projectId,
              )
        : null,
    rolePermissions: () => ref.read(rolePermissionsProvider),
    refreshListenable: refresh,
  );
  void rememberLocation() {
    memory.location = router.routeInformationProvider.value.uri.toString();
  }

  router.routeInformationProvider.addListener(rememberLocation);
  ref.onDispose(() {
    rememberLocation();
    router.routeInformationProvider.removeListener(rememberLocation);
    router.dispose();
  });
  return router;
});

/// Maps a rugged device's physical action button (and the F5 demo key) to the
/// current role's primary action: engineers raise a New Request, office roles
/// jump to the Materials hub. Read once at launch.
final hardwareActionProvider = Provider<HardwareActionService>((ref) {
  final service = HardwareActionService(() {
    final role = ref.read(currentRoleProvider);
    final router = ref.read(appRouterProvider);
    router.go(
      role.usesAdminPanel
          ? RoutePaths.materials
          : RoutePaths.engineerNewRequest,
    );
  });
  ref.onDispose(service.dispose);
  return service;
});

/// Root application widget.
///
/// Uses [ConsumerWidget] to read the router from Riverpod,
/// which rebuilds when onboarding state changes (redirect logic).
class MaterialLedgerApp extends ConsumerStatefulWidget {
  const MaterialLedgerApp({super.key});

  @override
  ConsumerState<MaterialLedgerApp> createState() => _MaterialLedgerAppState();
}

class _MaterialLedgerAppState extends ConsumerState<MaterialLedgerApp> {
  Timer? _notificationChromeTimer;
  bool _notificationChromeReady = false;
  GoRouter? _analyticsRouter;
  AnalyticsService? _analyticsService;
  VoidCallback? _analyticsRouterListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notificationChromeTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _notificationChromeReady = true);
      });
    });
  }

  @override
  void dispose() {
    _notificationChromeTimer?.cancel();
    final listener = _analyticsRouterListener;
    if (listener != null) {
      _analyticsRouter?.routeInformationProvider.removeListener(listener);
    }
    super.dispose();
  }

  void _trackRouter(GoRouter router, AnalyticsService analytics) {
    if (identical(_analyticsRouter, router) &&
        identical(_analyticsService, analytics)) {
      return;
    }
    final oldListener = _analyticsRouterListener;
    if (oldListener != null) {
      _analyticsRouter?.routeInformationProvider.removeListener(oldListener);
    }
    final tracker = AnalyticsRouteTracker(analytics);
    void listener() {
      tracker.track(router.routeInformationProvider.value.uri);
    }

    _analyticsRouter = router;
    _analyticsService = analytics;
    _analyticsRouterListener = listener;
    router.routeInformationProvider.addListener(listener);
    listener();
  }

  @override
  Widget build(BuildContext context) {
    // The coordinator starts auth immediately, then mounts independent global
    // services after the first route has had an uncontested render window.
    ref.watch(appStartupCoordinatorProvider);
    ref.watch(analyticsIdentityLifecycleProvider);
    if (_notificationChromeReady) ref.watch(hardwareActionProvider);
    final router = ref.watch(appRouterProvider);
    _trackRouter(router, ref.watch(analyticsServiceProvider));
    final language = ref.watch(languageProvider);

    return MaterialApp.router(
      title: 'Yorks AC. & Ref.',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: Locale(language.code),
      supportedLocales: yorksSupportedLocales,
      localizationsDelegates: yorksLocalizationDelegates,
      routerConfig: router,
      scrollBehavior: const YorksScrollBehavior(),
      // Overlay the lock screen above whatever is on screen (preserves
      // navigation), and reset the idle timer on any interaction.
      builder: (context, child) {
        final content = _AppChrome(child: child ?? const SizedBox.shrink());
        if (!_notificationChromeReady) return content;
        return NotificationAttentionHost(
          child: NotificationAlertHost(child: content),
        );
      },
    );
  }
}

/// Overlays the session-lock screen above the app content. Kept as its own
/// ConsumerWidget so it watches lock state in its own build, independent of the
/// router rebuild. The lock only ever appears on a cold start (see
/// [SessionLockController]); it never triggers on resume from background.
class _AppChrome extends ConsumerWidget {
  const _AppChrome({required this.child});
  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(sessionLockedProvider);
    final enabled = ref.watch(appLockEnabledProvider);
    final loggedIn = ref.watch(isLoggedInProvider);
    final showLock = locked && enabled && loggedIn;

    return Stack(
      children: [
        child ?? const SizedBox.shrink(),
        if (showLock) const Positioned.fill(child: LockScreen()),
      ],
    );
  }
}

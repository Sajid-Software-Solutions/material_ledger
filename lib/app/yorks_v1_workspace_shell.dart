import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/constants.dart';
import '../core/fullscreen/yorks_workspace_fullscreen.dart';
import '../core/zoom/yorks_workspace_zoom.dart';
import '../core/widgets/brand_logo.dart';
import '../core/widgets/yorks_mobile_ui.dart';
import '../core/widgets/yorks_panel_toggle_icon.dart';
import '../shared/models/app_language.dart';
import '../shared/models/app_strings.dart';
import '../shared/models/yorks_v1_permission_management.dart';
import '../shared/models/yorks_v1_permission_strings.dart';
import '../shared/models/yorks_v1_project_strings.dart';
import '../shared/models/yorks_v1_role.dart';
import '../shared/models/yorks_v1_shell_strings.dart';
import '../shared/models/yorks_v1_team_chat_strings.dart';
import '../shared/models/yorks_v1_workspace_status.dart';
import '../shared/models/yorks_v1_zoom_strings.dart';
import '../shared/providers/language_provider.dart';
import '../shared/providers/notification_provider.dart';
import '../shared/providers/session_provider.dart';
import '../shared/providers/yorks_v1_my_profile_provider.dart';
import '../shared/providers/yorks_v1_permission_provider.dart';
import '../shared/providers/yorks_v1_identity_provider.dart';
import '../shared/providers/yorks_v1_feature_flags_provider.dart';
import '../shared/providers/yorks_v1_team_chat_provider.dart';
import '../shared/providers/yorks_v1_workspace_status_provider.dart';
import '../shared/providers/yorks_v1_workspace_presentation_provider.dart';
import '../shared/widgets/notification_bell.dart';
import '../shared/widgets/yorks_sign_out_action.dart';
import 'router.dart';
import 'yorks_navigation_history.dart';
import 'yorks_v1_workspace_search_launcher.dart';
import 'yorks_v1_workspace_status_label.dart';

/// Desktop-only shell preference. It lives above individual route widgets so
/// navigating between Yorks screens does not reopen the panel unexpectedly.
final yorksV1SidebarExpandedProvider = yorksV1WorkspaceSidebarExpandedProvider;

/// R35 workspace chrome for every connected Yorks V1 operational route.
///
/// This widget is intentionally presentation-only. It does not widen routes,
/// client permissions or server data; individual feature screens continue to
/// request their own safe projections and call their existing controllers.
class YorksV1WorkspaceShell extends ConsumerWidget {
  const YorksV1WorkspaceShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final role = ref.watch(yorksV1CurrentRoleProvider);
    final user = ref.watch(currentUserProvider);
    final routeUri = GoRouterState.of(context).uri;
    final location = routeUri.path;
    final currentLocation = routeUri.toString();
    final navigationHistory = ref.watch(yorksNavigationHistoryProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      ref.read(yorksNavigationHistoryProvider.notifier).record(currentLocation);
    });
    final isAccountant = role == YorksV1Role.accountant;
    final featureFlags = ref.watch(yorksV1FeatureFlagsProvider);
    final companyRequestsEnabled = featureFlags.companyMaterialRequests;
    final accountsEnabled = featureFlags.accounts;
    final workforceEnabled = featureFlags.workforce;
    final analyticsEnabled = featureFlags.analytics;
    final teamChatEnabled = !isAccountant && featureFlags.teamChat;
    // Protected Accounts and Workforce routes are explicit runtime consumers.
    // Accountant remains isolated from legacy operational navigation, while
    // either accepted feature still waits for the same confirmed permission
    // snapshot as every other authorized identity.
    final connectedV1Permissions =
        (!isAccountant ||
            accountsEnabled ||
            workforceEnabled ||
            analyticsEnabled) &&
        ref.watch(supabaseClientProvider) != null;
    final permissionState = connectedV1Permissions
        ? ref.watch(yorksV1CurrentPermissionSnapshotProvider)
        : null;
    if (connectedV1Permissions && permissionState?.snapshot == null) {
      return _YorksPermissionVerificationShell(
        language: language,
        loading: permissionState?.isInitialLoading ?? true,
        onRetry: permissionState?.isInitialLoading ?? true
            ? null
            : () => ref
                  .read(yorksV1CurrentPermissionSnapshotProvider.notifier)
                  .refresh(),
      );
    }
    final chatUnread = teamChatEnabled
        ? ref.watch(yorksV1TeamChatUnreadProvider)
        : 0;
    final destinations = _destinationsFor(
      role,
      teamChatEnabled: teamChatEnabled,
      chatUnread: chatUnread,
      permissionState: permissionState,
      companyRequestsEnabled: companyRequestsEnabled,
      accountsEnabled: accountsEnabled,
      workforceEnabled: workforceEnabled,
      analyticsEnabled: analyticsEnabled,
    );
    final current = _currentDestination(destinations, location);
    final desktop =
        MediaQuery.sizeOf(context).width >=
        AppSpacing.yorksV1ShellDesktopBreakpoint;
    final fullscreen = desktop
        ? ref.watch(yorksWorkspaceFullscreenControllerProvider)
        : null;
    final sidebarExpanded = desktop
        ? ref.watch(yorksV1SidebarExpandedProvider)
        : true;
    final breadcrumbs = _breadcrumbsFor(location, current);
    final focusedMobileRoute = location == RoutePaths.engineerCreateProject;
    final featureOwnsMobileTopBar = _featureOwnsMobileTopBar(location);

    void openSearch() {
      showYorksV1WorkspaceSearch(
        context,
        targets: [
          for (final destination in destinations)
            if (destination.path != null)
              YorksV1SearchNavigationTarget(
                label: destination.label,
                icon: destination.icon,
                path: destination.path!,
              ),
          if (destinations.any(
            (destination) => destination.path == RoutePaths.yorksV1Workforce,
          ))
            const YorksV1SearchNavigationTarget(
              label: YorksV1ShellStrings.workforceTimesheets,
              icon: Icons.calendar_month_outlined,
              path: RoutePaths.yorksV1WorkforceTimesheets,
            ),
        ],
        language: language,
        role: role,
      );
    }

    final sidebar = _YorksDesktopSidebar(
      destinations: destinations,
      activePath: current?.path,
      language: language,
      role: role,
      userName: user?.fullName,
      expanded: sidebarExpanded,
    );
    final canPopNatively = Navigator.maybeOf(context)?.canPop() ?? false;
    final canUseWorkspaceHistory = navigationHistory.canGoBack(currentLocation);

    return YorksWorkspaceZoomHost(
      key: ValueKey(user?.id),
      routeKey: location,
      child: PopScope(
        // Root destinations in StatefulShellRoute have no Navigator page to pop.
        // Intercept system/gesture Back there and consume the shared workspace
        // history. Native nested routes keep their normal pop semantics.
        canPop: canPopNatively || !canUseWorkspaceHistory,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop || !canUseWorkspaceHistory) return;
          yorksNavigateBack(
            context,
            ref,
            currentLocation,
            fallback: current?.path ?? RoutePaths.engineerHome,
          );
        },
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
                openSearch,
            const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                openSearch,
            if (fullscreen?.shouldHideWorkspaceChrome ?? false)
              const SingleActivator(LogicalKeyboardKey.escape): () {
                fullscreen!.toggle();
              },
          },
          child: Scaffold(
            backgroundColor: AppColors.surface,
            drawer: desktop
                ? null
                : Drawer(
                    width: 246,
                    shape: const RoundedRectangleBorder(),
                    child: _YorksDesktopSidebar(
                      destinations: destinations,
                      activePath: current?.path,
                      language: language,
                      role: role,
                      userName: user?.fullName,
                      expanded: true,
                    ),
                  ),
            body: Builder(
              builder: (scaffoldContext) {
                if (!desktop) {
                  final unread = ref.watch(unreadNotificationCountProvider);
                  return ColoredBox(
                    color: AppColors.mobileSurface,
                    child: Column(
                      children: [
                        if (!(YorksMobileUi.isActive(context) &&
                            featureOwnsMobileTopBar))
                          _YorksWorkspaceMobileTopBar(
                            breadcrumbs: breadcrumbs,
                            language: language,
                            location: location,
                            showBack: yorksCanNavigateBack(
                              context,
                              ref,
                              currentLocation,
                            ),
                            unreadNotifications: unread,
                            teamChatEnabled: teamChatEnabled,
                            unreadChat: chatUnread,
                            onMenu: () =>
                                context.go(RoutePaths.yorksV1MobileMore),
                            onBack: () => yorksNavigateBack(
                              context,
                              ref,
                              currentLocation,
                              fallback:
                                  current?.path ?? RoutePaths.engineerHome,
                            ),
                          ),
                        Expanded(
                          child: YorksWorkspaceZoomViewport(
                            routeKey: location,
                            language: language,
                            child: child,
                          ),
                        ),
                        if (!focusedMobileRoute)
                          _YorksMobileNavigation(
                            destinations: _mobileDestinationsFor(
                              role,
                              nativeMobile: YorksMobileUi.isActive(context),
                              teamChatEnabled: teamChatEnabled,
                              chatUnread: chatUnread,
                              permissionState: permissionState,
                              companyRequestsEnabled: companyRequestsEnabled,
                              accountsEnabled: accountsEnabled,
                              workforceEnabled: workforceEnabled,
                              analyticsEnabled: analyticsEnabled,
                            ),
                            activePath: location,
                            language: language,
                          ),
                      ],
                    ),
                  );
                }
                if (fullscreen?.shouldHideWorkspaceChrome ?? false) {
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: YorksWorkspaceZoomViewport(
                          routeKey: location,
                          language: language,
                          child: child,
                        ),
                      ),
                      SafeArea(
                        child: Align(
                          alignment: AlignmentDirectional.topEnd,
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Material(
                              key: const ValueKey(
                                'yorks-workspace-fullscreen-exit-surface',
                              ),
                              color: AppColors.workspaceChrome,
                              elevation: 3,
                              shape: const CircleBorder(
                                side: BorderSide(color: AppColors.line),
                              ),
                              child: _YorksWorkspaceFullscreenButton(
                                language: language,
                                controller: fullscreen!,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    sidebar,
                    Expanded(
                      child: Column(
                        children: [
                          _YorksWorkspaceTopBar(
                            breadcrumbs: breadcrumbs,
                            language: language,
                            role: role,
                            destinations: destinations,
                            teamChatEnabled: teamChatEnabled,
                            unreadChat: chatUnread,
                            sidebarExpanded: sidebarExpanded,
                            showBack:
                                yorksCanNavigateBack(
                                  context,
                                  ref,
                                  currentLocation,
                                ) ||
                                (current?.path != null &&
                                    location != current!.path),
                            onToggleSidebar: () async {
                              final focused =
                                  FocusManager.instance.primaryFocus;
                              if (focused?.context
                                      ?.findAncestorStateOfType<
                                        EditableTextState
                                      >() !=
                                  null) {
                                focused?.unfocus();
                              }
                              await Future<void>.delayed(Duration.zero);
                              if (!context.mounted) return;
                              ref
                                  .read(yorksV1SidebarExpandedProvider.notifier)
                                  .state = !ref.read(
                                yorksV1SidebarExpandedProvider,
                              );
                            },
                            onBack: () => yorksNavigateBack(
                              context,
                              ref,
                              currentLocation,
                              fallback:
                                  current?.path ?? RoutePaths.engineerHome,
                            ),
                          ),
                          Expanded(
                            child: YorksWorkspaceZoomViewport(
                              routeKey: location,
                              language: language,
                              child: child,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Record-oriented Project and Material Request screens have titles and
  /// actions that only their own controller-backed projections can supply.
  /// They own the compact phone header while the shell retains its bottom
  /// navigation. This avoids stacking a generic workspace toolbar above a
  /// focused record toolbar on the native mobile breakpoint.
  bool _featureOwnsMobileTopBar(String location) {
    // The retained engineering calculators use a focused, controller-backed
    // phone header just like record routes. Keep the shared bottom navigation,
    // but do not stack the generic workspace toolbar above their own actions.
    if (location == RoutePaths.yorksV1DuctSizer ||
        location == RoutePaths.yorksV1EspCalculator ||
        location == RoutePaths.engineerProfile ||
        location == RoutePaths.notificationPreferences ||
        location.startsWith(RoutePaths.yorksV1TeamChat)) {
      return true;
    }
    final segments = Uri(path: location).pathSegments;
    if (segments.length < 2 || segments[0] != 'yorks') {
      return false;
    }
    if (segments[1] == 'material-requests') return true;
    if (segments[1] != 'projects' || segments.length < 3) return false;
    return segments.last != 'edit';
  }

  List<_YorksDestination> _mobileDestinationsFor(
    YorksV1Role? role, {
    required bool nativeMobile,
    bool teamChatEnabled = true,
    int chatUnread = 0,
    YorksV1CurrentPermissionSnapshotState? permissionState,
    bool companyRequestsEnabled = false,
    bool accountsEnabled = false,
    bool workforceEnabled = false,
    bool analyticsEnabled = false,
  }) {
    final all = _destinationsFor(
      role,
      teamChatEnabled: teamChatEnabled,
      chatUnread: chatUnread,
      permissionState: permissionState,
      companyRequestsEnabled: companyRequestsEnabled,
      accountsEnabled: accountsEnabled,
      workforceEnabled: workforceEnabled,
      analyticsEnabled: analyticsEnabled,
    );
    _YorksDestination? path(String route) {
      for (final destination in all) {
        if (destination.path == route) return destination;
      }
      return null;
    }

    final home = path(RoutePaths.engineerHome);
    if (role == YorksV1Role.accountant) {
      final accounts = path(RoutePaths.yorksV1Accounts);
      final projects = path(RoutePaths.yorksV1AccountsProjects);
      final claims = path(RoutePaths.yorksV1AccountsClaims);
      final payments = path(RoutePaths.yorksV1AccountsClientPayments);
      final more = _YorksDestination(
        label: AppStrings.more,
        icon: nativeMobile ? Icons.menu_rounded : Icons.grid_view_outlined,
        selectedIcon: nativeMobile
            ? Icons.menu_rounded
            : Icons.grid_view_rounded,
        path: RoutePaths.yorksV1MobileMore,
      );
      return [?accounts, ?projects, ?claims, ?payments, more];
    }
    final requiredHome = home!;
    if (!nativeMobile) {
      final more = _YorksDestination(
        label: AppStrings.more,
        icon: Icons.grid_view_outlined,
        selectedIcon: Icons.grid_view_rounded,
        path: RoutePaths.yorksV1MobileMore,
      );
      final preferred = role == YorksV1Role.procurement
          ? <_YorksDestination?>[
              requiredHome,
              path(RoutePaths.yorksV1MaterialRequests),
              path(RoutePaths.yorksV1Inventory),
              teamChatEnabled
                  ? path(RoutePaths.yorksV1TeamChat)
                  : path(RoutePaths.yorksV1Dispatches),
            ]
          : <_YorksDestination?>[
              requiredHome,
              path(RoutePaths.yorksV1Projects),
              if (teamChatEnabled) path(RoutePaths.yorksV1TeamChat),
              path(RoutePaths.yorksV1MaterialRequests),
            ];
      return [...preferred.whereType<_YorksDestination>(), more];
    }
    _YorksDestination mobilePath(
      _YorksDestination source,
      IconData icon,
      IconData selectedIcon, {
      TranslatableString? mobileLabel,
    }) {
      return _YorksDestination(
        label: mobileLabel ?? source.label,
        compactLabel: mobileLabel ?? source.compactLabel,
        icon: icon,
        selectedIcon: selectedIcon,
        path: source.path,
      );
    }

    final mobileHome = mobilePath(
      requiredHome,
      Icons.home_outlined,
      Icons.home_rounded,
      mobileLabel: AppStrings.home,
    );
    final projectSource = path(RoutePaths.yorksV1Projects);
    final projects = projectSource == null
        ? null
        : mobilePath(
            projectSource,
            Icons.folder_outlined,
            Icons.folder_rounded,
          );
    final requestSource = path(RoutePaths.yorksV1MaterialRequests);
    final requests = requestSource == null
        ? null
        : mobilePath(
            requestSource,
            Icons.receipt_long_outlined,
            Icons.receipt_long_rounded,
          );
    final chatSource = path(RoutePaths.yorksV1TeamChat);
    final chat = teamChatEnabled && chatSource != null
        ? mobilePath(
            chatSource,
            Icons.chat_bubble_outline_rounded,
            Icons.chat_bubble_rounded,
          )
        : null;
    final more = _YorksDestination(
      label: AppStrings.more,
      icon: Icons.menu_rounded,
      selectedIcon: Icons.menu_rounded,
      path: RoutePaths.yorksV1MobileMore,
    );
    if (role == YorksV1Role.procurement) {
      return [
        mobileHome,
        ?requests,
        ?path(RoutePaths.yorksV1Inventory),
        ?(chat ?? path(RoutePaths.yorksV1Dispatches)),
        more,
      ];
    }
    return [mobileHome, ?projects, ?chat, ?requests, more];
  }

  List<_YorksDestination> _destinationsFor(
    YorksV1Role? role, {
    bool teamChatEnabled = true,
    int chatUnread = 0,
    YorksV1CurrentPermissionSnapshotState? permissionState,
    bool companyRequestsEnabled = false,
    bool accountsEnabled = false,
    bool workforceEnabled = false,
    bool analyticsEnabled = false,
  }) {
    final accountantOffice = accountsEnabled && role == YorksV1Role.accountant
        ? <_YorksDestination>[
            _YorksDestination(
              label: YorksV1ShellStrings.accounts,
              icon: Icons.dashboard_outlined,
              selectedIcon: Icons.dashboard_rounded,
              path: RoutePaths.yorksV1Accounts,
              group: YorksV1ShellStrings.accountantWorkspace,
            ),
            _YorksDestination(
              label: YorksV1ShellStrings.projectAccounts,
              icon: Icons.folder_outlined,
              selectedIcon: Icons.folder_rounded,
              path: RoutePaths.yorksV1AccountsProjects,
            ),
            _YorksDestination(
              label: YorksV1ShellStrings.billingProgress,
              icon: Icons.stacked_bar_chart_outlined,
              selectedIcon: Icons.stacked_bar_chart_rounded,
              path: RoutePaths.yorksV1AccountsBillingProgress,
            ),
            _YorksDestination(
              label: YorksV1ShellStrings.accountsClaims,
              icon: Icons.request_page_outlined,
              selectedIcon: Icons.request_page_rounded,
              path: RoutePaths.yorksV1AccountsClaims,
            ),
            _YorksDestination(
              label: YorksV1ShellStrings.receiptsPdc,
              icon: Icons.account_balance_wallet_outlined,
              selectedIcon: Icons.account_balance_wallet_rounded,
              path: RoutePaths.yorksV1AccountsClientPayments,
            ),
            _YorksDestination(
              label: YorksV1ShellStrings.supplierBills,
              icon: Icons.receipt_long_outlined,
              selectedIcon: Icons.receipt_long_rounded,
              path: RoutePaths.yorksV1AccountsSupplierBills,
            ),
            _YorksDestination(
              label: YorksV1ShellStrings.dueSchedule,
              icon: Icons.calendar_month_outlined,
              selectedIcon: Icons.calendar_month_rounded,
              path: RoutePaths.yorksV1AccountsDueSchedule,
            ),
            _YorksDestination(
              label: YorksV1ShellStrings.accountsDocuments,
              icon: Icons.folder_copy_outlined,
              selectedIcon: Icons.folder_copy_rounded,
              path: RoutePaths.yorksV1AccountsDocuments,
            ),
            _YorksDestination(
              label: YorksV1ShellStrings.accountsReports,
              icon: Icons.analytics_outlined,
              selectedIcon: Icons.analytics_rounded,
              path: RoutePaths.yorksV1AccountsReports,
            ),
            _YorksDestination(
              label: YorksV1ShellStrings.accountsAuditTrail,
              icon: Icons.policy_outlined,
              selectedIcon: Icons.policy_rounded,
              path: RoutePaths.yorksV1AccountsActivity,
            ),
          ]
        : const <_YorksDestination>[];
    final candidates = <_YorksDestination>[
      if (!(accountsEnabled && role == YorksV1Role.accountant))
        ..._legacyDestinationsFor(
          role,
          teamChatEnabled: teamChatEnabled,
          chatUnread: chatUnread,
        ),
      ...accountantOffice,
      if (analyticsEnabled)
        _YorksDestination(
          label: YorksV1ShellStrings.analytics,
          icon: Icons.insights_outlined,
          selectedIcon: Icons.insights_rounded,
          path: RoutePaths.yorksV1Analytics,
        ),
      if (accountsEnabled && role != YorksV1Role.accountant)
        _YorksDestination(
          label: YorksV1ShellStrings.accounts,
          icon: Icons.account_balance_wallet_outlined,
          selectedIcon: Icons.account_balance_wallet_rounded,
          path: RoutePaths.yorksV1Accounts,
        ),
      if (workforceEnabled)
        _YorksDestination(
          label: YorksV1ShellStrings.workforce,
          icon: Icons.groups_2_outlined,
          selectedIcon: Icons.groups_2_rounded,
          path: RoutePaths.yorksV1Workforce,
        ),
      if (workforceEnabled)
        _YorksDestination(
          label: YorksV1ShellStrings.workforceAdministration,
          icon: Icons.badge_outlined,
          selectedIcon: Icons.badge_rounded,
          path: RoutePaths.yorksV1WorkforceAdministration,
          group: YorksV1ShellStrings.administration,
        ),
      ..._legacyDestinationsFor(
        YorksV1Role.admin,
        teamChatEnabled: teamChatEnabled,
        chatUnread: chatUnread,
      ),
      ..._legacyDestinationsFor(
        YorksV1Role.procurement,
        teamChatEnabled: teamChatEnabled,
        chatUnread: chatUnread,
      ),
      ..._legacyDestinationsFor(
        YorksV1Role.seniorMechanicalEngineer,
        teamChatEnabled: teamChatEnabled,
        chatUnread: chatUnread,
      ),
    ];
    final unique = <String, _YorksDestination>{};
    for (final destination in candidates) {
      final path = destination.path;
      if (path != null) unique.putIfAbsent(path, () => destination);
    }

    bool allows(String capabilityKey, bool legacyAllowed) {
      return permissionState?.hybridAllows(
            capabilityKey,
            legacyAllowed: legacyAllowed,
            organizationSummary: true,
          ) ??
          legacyAllowed;
    }

    bool destinationAllowed(_YorksDestination destination) {
      final path = destination.path;
      if (path == RoutePaths.engineerHome) return true;
      if (role == YorksV1Role.accountant &&
          path != RoutePaths.yorksV1Accounts &&
          path != RoutePaths.yorksV1Workforce &&
          (path == null ||
              !path.startsWith('${RoutePaths.yorksV1Accounts}/'))) {
        return false;
      }
      if (path == RoutePaths.yorksV1Accounts ||
          (path?.startsWith('${RoutePaths.yorksV1Accounts}/') ?? false)) {
        final structurallyEligible =
            role == YorksV1Role.admin ||
            role == YorksV1Role.accountant ||
            role == YorksV1Role.projectManager ||
            role == YorksV1Role.seniorMechanicalEngineer;
        final canViewAccounts = allows(
          YorksV1CapabilityKeys.viewProjectAccounts,
          false,
        );
        final canViewDestination =
            path != RoutePaths.yorksV1AccountsSupplierBills ||
            allows(YorksV1CapabilityKeys.viewSupplierCosts, false);
        return accountsEnabled &&
            structurallyEligible &&
            canViewAccounts &&
            canViewDestination;
      }
      if (path == RoutePaths.yorksV1Workforce) {
        return workforceEnabled &&
            allows(YorksV1CapabilityKeys.workforceView, false);
      }
      if (path == RoutePaths.yorksV1WorkforceAdministration) {
        return workforceEnabled &&
            allows(YorksV1CapabilityKeys.workforceView, false) &&
            (allows(YorksV1CapabilityKeys.workforceWorkersManage, false) ||
                allows(YorksV1CapabilityKeys.workforceTeamsManage, false) ||
                allows(
                  YorksV1CapabilityKeys.workforceConfigurationManage,
                  false,
                ));
      }
      if (path == RoutePaths.yorksV1Analytics) {
        return analyticsEnabled &&
            allows(YorksV1CapabilityKeys.analyticsView, false);
      }
      if (path == RoutePaths.yorksV1Projects) {
        return allows(YorksV1CapabilityKeys.projectsView, role != null);
      }
      if (path == RoutePaths.yorksV1MaterialRequests) {
        return (companyRequestsEnabled &&
                role != null &&
                role != YorksV1Role.accountant) ||
            allows(YorksV1CapabilityKeys.materialRequestsView, role != null);
      }
      if (path == RoutePaths.yorksV1TeamChat) {
        return allows(YorksV1CapabilityKeys.chatView, role != null);
      }
      if (path == RoutePaths.yorksV1Inventory) {
        return allows(
          YorksV1CapabilityKeys.inventoryView,
          role?.canBrowseInventory ?? false,
        );
      }
      if (path == RoutePaths.yorksV1Returns) {
        return allows(YorksV1CapabilityKeys.returnsView, role != null);
      }
      if (path == RoutePaths.yorksV1Dispatches) {
        return allows(
          YorksV1CapabilityKeys.dispatchView,
          role == YorksV1Role.procurement || role == YorksV1Role.admin,
        );
      }
      if (path == RoutePaths.yorksV1Configuration) {
        return allows(
          YorksV1CapabilityKeys.configurationView,
          role == YorksV1Role.admin,
        );
      }
      if (path == RoutePaths.rentals) {
        return allows(
          YorksV1CapabilityKeys.rentalsView,
          role == YorksV1Role.admin,
        );
      }
      if (path == RoutePaths.users) {
        return allows(
          YorksV1CapabilityKeys.usersView,
          role?.canConfigureUsers ?? false,
        );
      }
      if (path == RoutePaths.activityLog) {
        return allows(
          YorksV1CapabilityKeys.auditView,
          role == YorksV1Role.admin,
        );
      }
      if (path == RoutePaths.yorksV1DuctSizer ||
          path == RoutePaths.yorksV1EspCalculator) {
        return role?.isEngineering ?? false;
      }
      return false;
    }

    final visible = <_YorksDestination>[
      for (final destination in unique.values)
        if (destinationAllowed(destination)) destination,
    ];
    final accountsIndex = visible.indexWhere(
      (destination) => destination.path == RoutePaths.yorksV1Accounts,
    );
    final requestsIndex = visible.indexWhere(
      (destination) => destination.path == RoutePaths.yorksV1MaterialRequests,
    );
    if (accountsIndex >= 0 && requestsIndex >= 0) {
      final accounts = visible.removeAt(accountsIndex);
      final updatedRequestsIndex = visible.indexWhere(
        (destination) => destination.path == RoutePaths.yorksV1MaterialRequests,
      );
      visible.insert(updatedRequestsIndex + 1, accounts);
    }
    final workforceIndex = visible.indexWhere(
      (destination) => destination.path == RoutePaths.yorksV1Workforce,
    );
    if (workforceIndex >= 0) {
      final workforce = visible.removeAt(workforceIndex);
      final accountsOrRequestsIndex = visible.indexWhere(
        (destination) => destination.path == RoutePaths.yorksV1Accounts,
      );
      final updatedRequestsIndex = visible.indexWhere(
        (destination) => destination.path == RoutePaths.yorksV1MaterialRequests,
      );
      final anchor = accountsOrRequestsIndex >= 0
          ? accountsOrRequestsIndex
          : updatedRequestsIndex;
      visible.insert(anchor >= 0 ? anchor + 1 : visible.length, workforce);
    }
    final analyticsIndex = visible.indexWhere(
      (destination) => destination.path == RoutePaths.yorksV1Analytics,
    );
    if (analyticsIndex >= 0) {
      final analytics = visible.removeAt(analyticsIndex);
      final overviewIndex = visible.indexWhere(
        (destination) => destination.path == RoutePaths.engineerHome,
      );
      visible.insert(overviewIndex >= 0 ? overviewIndex + 1 : 0, analytics);
    }
    return visible;
  }

  List<_YorksDestination> _legacyDestinationsFor(
    YorksV1Role? role, {
    bool teamChatEnabled = true,
    int chatUnread = 0,
  }) {
    final workspace = _workspaceCopy(role);
    final shared = <_YorksDestination>[
      _YorksDestination(
        label: YorksV1ShellStrings.overview,
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard_rounded,
        path: RoutePaths.engineerHome,
        group: workspace,
      ),
      _YorksDestination(
        label: YorksV1ShellStrings.projects,
        icon: Icons.account_tree_outlined,
        selectedIcon: Icons.account_tree_rounded,
        path: RoutePaths.yorksV1Projects,
      ),
      _YorksDestination(
        label: YorksV1ShellStrings.materialRequests,
        compactLabel: YorksV1ShellStrings.requestsCompact,
        icon: Icons.assignment_outlined,
        selectedIcon: Icons.assignment_rounded,
        path: RoutePaths.yorksV1MaterialRequests,
      ),
      if (teamChatEnabled)
        _YorksDestination(
          label: YorksV1TeamChatStrings.teamChat,
          icon: Icons.chat_bubble_outline_rounded,
          selectedIcon: Icons.chat_bubble_rounded,
          path: RoutePaths.yorksV1TeamChat,
          badgeCount: chatUnread,
          group: YorksV1ShellStrings.collaboration,
        ),
    ];

    return switch (role) {
      YorksV1Role.projectEngineer ||
      YorksV1Role.siteEngineer ||
      YorksV1Role.seniorMechanicalEngineer ||
      YorksV1Role.projectManager ||
      YorksV1Role.workshopInCharge ||
      YorksV1Role.documentController => [
        ...shared,
        if (role?.canBrowseInventory ?? false)
          _YorksDestination(
            label: YorksV1ShellStrings.browseInventory,
            icon: Icons.inventory_2_outlined,
            selectedIcon: Icons.inventory_2_rounded,
            path: RoutePaths.yorksV1Inventory,
            suffix: YorksV1ShellStrings.viewOnly,
          ),
        _YorksDestination(
          label: YorksV1ShellStrings.materialReturns,
          compactLabel: YorksV1ShellStrings.returnsCompact,
          icon: Icons.assignment_return_outlined,
          selectedIcon: Icons.assignment_return_rounded,
          path: RoutePaths.yorksV1Returns,
        ),
        _YorksDestination(
          label: YorksV1ShellStrings.ductSizer,
          compactLabel: YorksV1ShellStrings.ductCompact,
          icon: Icons.straighten_outlined,
          selectedIcon: Icons.straighten_rounded,
          path: RoutePaths.yorksV1DuctSizer,
          group: YorksV1ShellStrings.engineeringTools,
        ),
        _YorksDestination(
          label: YorksV1ShellStrings.espCalculator,
          compactLabel: YorksV1ShellStrings.espCompact,
          icon: Icons.speed_outlined,
          selectedIcon: Icons.speed_rounded,
          path: RoutePaths.yorksV1EspCalculator,
          group: YorksV1ShellStrings.engineeringTools,
        ),
        if (role?.canConfigureUsers ?? false)
          _YorksDestination(
            label: YorksV1ShellStrings.userManagement,
            icon: Icons.manage_accounts_outlined,
            selectedIcon: Icons.manage_accounts_rounded,
            path: RoutePaths.users,
            group: YorksV1ShellStrings.administration,
          ),
      ],
      YorksV1Role.accountant => [shared.first],
      YorksV1Role.procurement => [
        shared.first,
        shared[2],
        if (teamChatEnabled) shared.last,
        _YorksDestination(
          label: YorksV1ShellStrings.browseInventory,
          icon: Icons.inventory_2_outlined,
          selectedIcon: Icons.inventory_2_rounded,
          path: RoutePaths.yorksV1Inventory,
        ),
        _YorksDestination(
          label: YorksV1ShellStrings.dispatches,
          icon: Icons.local_shipping_outlined,
          selectedIcon: Icons.local_shipping_rounded,
          path: RoutePaths.yorksV1Dispatches,
        ),
        _YorksDestination(
          label: YorksV1ShellStrings.materialReturns,
          icon: Icons.assignment_return_outlined,
          selectedIcon: Icons.assignment_return_rounded,
          path: RoutePaths.yorksV1Returns,
        ),
        _YorksDestination(
          label: YorksV1ShellStrings.projects,
          icon: Icons.account_tree_outlined,
          selectedIcon: Icons.account_tree_rounded,
          path: RoutePaths.yorksV1Projects,
          suffix: YorksV1ShellStrings.viewOnly,
        ),
      ],
      YorksV1Role.admin => [
        ...shared,
        _YorksDestination(
          label: YorksV1ShellStrings.browseInventory,
          icon: Icons.inventory_2_outlined,
          selectedIcon: Icons.inventory_2_rounded,
          path: RoutePaths.yorksV1Inventory,
        ),
        _YorksDestination(
          label: YorksV1ShellStrings.materialReturns,
          icon: Icons.assignment_return_outlined,
          selectedIcon: Icons.assignment_return_rounded,
          path: RoutePaths.yorksV1Returns,
        ),
        _YorksDestination(
          label: YorksV1ShellStrings.dispatches,
          icon: Icons.local_shipping_outlined,
          selectedIcon: Icons.local_shipping_rounded,
          path: RoutePaths.yorksV1Dispatches,
        ),
        _YorksDestination(
          label: YorksV1ShellStrings.configuration,
          icon: Icons.tune_outlined,
          selectedIcon: Icons.tune_rounded,
          path: RoutePaths.yorksV1Configuration,
          group: YorksV1ShellStrings.administration,
        ),
        _YorksDestination(
          label: YorksV1ShellStrings.rentalProperties,
          icon: Icons.apartment_outlined,
          selectedIcon: Icons.apartment_rounded,
          path: RoutePaths.rentals,
          group: YorksV1ShellStrings.administration,
        ),
        _YorksDestination(
          label: YorksV1ShellStrings.userManagement,
          icon: Icons.manage_accounts_outlined,
          selectedIcon: Icons.manage_accounts_rounded,
          path: RoutePaths.users,
          group: YorksV1ShellStrings.administration,
        ),
        _YorksDestination(
          label: YorksV1ShellStrings.auditTrail,
          icon: Icons.history_outlined,
          selectedIcon: Icons.history_rounded,
          path: RoutePaths.activityLog,
          group: YorksV1ShellStrings.administration,
        ),
      ],
      null => shared,
    };
  }

  _YorksDestination? _currentDestination(
    List<_YorksDestination> destinations,
    String location,
  ) {
    if (location.startsWith('${RoutePaths.yorksV1Accounts}/')) {
      for (final destination in destinations) {
        if (destination.path == location) return destination;
      }
    }
    if (location == RoutePaths.yorksV1Accounts ||
        (location.startsWith('/yorks/projects/') &&
            location.contains('/accounts'))) {
      for (final destination in destinations) {
        if (destination.path == RoutePaths.yorksV1Accounts) return destination;
      }
    }
    for (final destination in destinations) {
      final path = destination.path;
      if (path == null) continue;
      if (location == path ||
          (path == RoutePaths.yorksV1Accounts &&
              (location == RoutePaths.yorksV1Accounts ||
                  location.contains('/accounts'))) ||
          (path == RoutePaths.yorksV1Projects &&
              location == RoutePaths.engineerCreateProject) ||
          (path == RoutePaths.yorksV1MaterialRequests &&
              location.startsWith('/yorks/material-requests')) ||
          (path == RoutePaths.yorksV1TeamChat &&
              location.startsWith(RoutePaths.yorksV1TeamChat)) ||
          (path == RoutePaths.yorksV1Workforce &&
              location.startsWith(RoutePaths.yorksV1Workforce)) ||
          (path == RoutePaths.yorksV1Projects &&
              location.startsWith('/yorks/projects'))) {
        return destination;
      }
      if (path == RoutePaths.yorksV1Dispatches &&
          location == RoutePaths.yorksV1Dispatches) {
        return destination;
      }
      if (path == RoutePaths.yorksV1Returns &&
          location == RoutePaths.yorksV1Returns) {
        return destination;
      }
    }
    return null;
  }

  List<TranslatableString> _breadcrumbsFor(
    String location,
    _YorksDestination? current,
  ) {
    if (location == RoutePaths.engineerCreateProject) {
      return const [
        YorksV1ProjectStrings.projects,
        YorksV1ProjectStrings.createProject,
      ];
    }
    if (location == RoutePaths.yorksV1WorkforceTimesheets) {
      return const [
        YorksV1ShellStrings.workforce,
        YorksV1ShellStrings.workforceTimesheets,
      ];
    }
    return [current?.label ?? YorksV1ShellStrings.overview];
  }
}

/// Prevents protected feature widgets, navigation and actions from building
/// before the first server-confirmed permission projection is available. The
/// browser URL remains unchanged so a valid deep link resumes after the
/// router's permission refresh signal, without a deny/redirect flash.
class _YorksPermissionVerificationShell extends StatelessWidget {
  const _YorksPermissionVerificationShell({
    required this.language,
    required this.loading,
    required this.onRetry,
  });

  final AppLanguage language;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('yorks-permission-verification-shell'),
    backgroundColor: AppColors.surface,
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  const SizedBox.square(
                    dimension: AppSpacing.minTapTarget,
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  )
                else
                  const Icon(
                    Icons.security_update_warning_outlined,
                    size: 48,
                    color: AppColors.muted,
                  ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  YorksV1PermissionStrings.text(
                    language,
                    loading ? 'loading_title' : 'load_failed_title',
                  ),
                  textAlign: TextAlign.center,
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  YorksV1PermissionStrings.text(
                    language,
                    loading ? 'loading_body' : 'load_failed_body',
                  ),
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.muted,
                  ),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  OutlinedButton.icon(
                    key: const ValueKey('retry-permission-verification'),
                    onPressed: onRetry,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(
                        AppSpacing.minTapTarget,
                        AppSpacing.minTapTarget,
                      ),
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(
                      YorksV1PermissionStrings.text(language, 'retry'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Full mobile destination used by the fixed bottom navigation. It exposes
/// only routes already available to the authenticated role.
class YorksV1MobileMoreScreen extends ConsumerWidget {
  const YorksV1MobileMoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final role = ref.watch(yorksV1CurrentRoleProvider);
    final user = ref.watch(currentUserProvider);
    final featureFlags = ref.watch(yorksV1FeatureFlagsProvider);
    final companyRequestsEnabled = featureFlags.companyMaterialRequests;
    final accountsEnabled = featureFlags.accounts;
    final workforceEnabled = featureFlags.workforce;
    final analyticsEnabled = featureFlags.analytics;
    final teamChatEnabled =
        role != YorksV1Role.accountant && featureFlags.teamChat;
    final connectedV1Permissions =
        (role != YorksV1Role.accountant ||
            accountsEnabled ||
            workforceEnabled ||
            analyticsEnabled) &&
        ref.watch(supabaseClientProvider) != null;
    final permissionState = connectedV1Permissions
        ? ref.watch(yorksV1CurrentPermissionSnapshotProvider)
        : null;
    final chatUnread = teamChatEnabled
        ? ref.watch(yorksV1TeamChatUnreadProvider)
        : 0;
    final shell = YorksV1WorkspaceShell(child: const SizedBox.shrink());
    final all = shell._destinationsFor(
      role,
      teamChatEnabled: teamChatEnabled,
      chatUnread: chatUnread,
      permissionState: permissionState,
      companyRequestsEnabled: companyRequestsEnabled,
      accountsEnabled: accountsEnabled,
      workforceEnabled: workforceEnabled,
      analyticsEnabled: analyticsEnabled,
    );
    final primaryRoutes = shell
        ._mobileDestinationsFor(
          role,
          nativeMobile: YorksMobileUi.isActive(context),
          teamChatEnabled: teamChatEnabled,
          chatUnread: chatUnread,
          permissionState: permissionState,
          companyRequestsEnabled: companyRequestsEnabled,
          accountsEnabled: accountsEnabled,
          workforceEnabled: workforceEnabled,
          analyticsEnabled: analyticsEnabled,
        )
        .map((destination) => destination.path)
        .whereType<String>()
        .toSet();
    final moreDestinations = all
        .where(
          (destination) =>
              destination.path != null &&
              !primaryRoutes.contains(destination.path),
        )
        .toList();

    return ColoredBox(
      color: AppColors.mobileSurface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          Semantics(
            button: true,
            label: AppStrings.profile.active(language),
            child: YorksMobileCard(
              key: const ValueKey('mobile-profile-entry'),
              onTap: () => context.push(RoutePaths.engineerProfile),
              child: Row(
                children: [
                  _Avatar(name: user?.fullName ?? '', size: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.fullName ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _roleCopy(role).active(language),
                          style: AppTypography.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.muted,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _workspaceCopy(role).active(language),
            style: AppTypography.labelMedium.copyWith(
              letterSpacing: .8,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          YorksMobileCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (
                  var index = 0;
                  index < moreDestinations.length;
                  index++
                ) ...[
                  _MoreDestinationRow(
                    destination: moreDestinations[index],
                    language: language,
                  ),
                  if (index != moreDestinations.length - 1)
                    const Divider(height: 1),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            AppStrings.settings.active(language),
            style: AppTypography.labelMedium.copyWith(
              letterSpacing: .8,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          YorksMobileCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _MoreDestinationRow(
                  destination: _YorksDestination(
                    label: AppStrings.notifications,
                    icon: Icons.notifications_outlined,
                    selectedIcon: Icons.notifications_rounded,
                    path: RoutePaths.notifications,
                  ),
                  language: language,
                ),
                const Divider(height: 1),
                _MoreDestinationRow(
                  destination: _YorksDestination(
                    label: AppStrings.profile,
                    icon: Icons.person_outline_rounded,
                    selectedIcon: Icons.person_rounded,
                    path: RoutePaths.engineerProfile,
                  ),
                  language: language,
                ),
                const Divider(height: 1),
                Semantics(
                  button: true,
                  child: InkWell(
                    onTap: () => showYorksSignOut(context, ref),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 52),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.logout_rounded,
                              size: 21,
                              color: AppColors.error,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              AppStrings.signOut.active(language),
                              style: AppTypography.bodyMedium.copyWith(
                                color: AppColors.error,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreDestinationRow extends StatelessWidget {
  const _MoreDestinationRow({
    required this.destination,
    required this.language,
  });

  final _YorksDestination destination;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: destination.label.active(language),
    child: InkWell(
      onTap: () => context.go(destination.path!),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(destination.icon, size: 21, color: AppColors.inkSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  destination.label.active(language),
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _YorksWorkspaceTopBar extends ConsumerWidget {
  const _YorksWorkspaceTopBar({
    required this.breadcrumbs,
    required this.language,
    required this.role,
    required this.destinations,
    required this.teamChatEnabled,
    required this.unreadChat,
    required this.sidebarExpanded,
    required this.showBack,
    required this.onToggleSidebar,
    required this.onBack,
  });

  final List<TranslatableString> breadcrumbs;
  final AppLanguage language;
  final YorksV1Role? role;
  final List<_YorksDestination> destinations;
  final bool teamChatEnabled;
  final int unreadChat;
  final bool sidebarExpanded;
  final bool showBack;
  final VoidCallback onToggleSidebar;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaceStatus = ref.watch(yorksV1WorkspaceStatusProvider);
    final fullscreen = ref.watch(yorksWorkspaceFullscreenControllerProvider);
    return Material(
      color: AppColors.workspaceChrome,
      child: Container(
        height: AppSpacing.topBarHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            Semantics(
              expanded: sidebarExpanded,
              child: IconButton(
                key: const ValueKey('yorks-workspace-sidebar-toggle'),
                tooltip:
                    (sidebarExpanded
                            ? YorksV1ShellStrings.collapsePanel
                            : YorksV1ShellStrings.expandPanel)
                        .active(language),
                onPressed: onToggleSidebar,
                style: IconButton.styleFrom(
                  foregroundColor: sidebarExpanded
                      ? AppColors.blue
                      : AppColors.muted,
                  backgroundColor: sidebarExpanded
                      ? AppColors.blueContainer
                      : null,
                ),
                icon: YorksPanelToggleIcon(expanded: sidebarExpanded),
              ),
            ),
            const SizedBox(width: AppSpacing.xxs),
            IconButton(
              key: const ValueKey('yorks-workspace-back'),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: showBack ? onBack : null,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      YorksV1ShellStrings.companyName.active(language),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  for (final breadcrumb in breadcrumbs) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      child: Text(
                        '/',
                        style: TextStyle(color: AppColors.lineStrong),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        breadcrumb.active(language),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            SizedBox(
              width: 300,
              child: _YorksQuickNavigationButton(
                destinations: destinations
                    .where((destination) => destination.path != null)
                    .toList(growable: false),
                language: language,
                role: role,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            if (fullscreen.isSupported) ...[
              _YorksWorkspaceFullscreenButton(
                language: language,
                controller: fullscreen,
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            if (teamChatEnabled) ...[
              IconButton(
                tooltip: YorksV1TeamChatStrings.teamChat.active(language),
                onPressed: () => context.go(RoutePaths.yorksV1TeamChat),
                icon: Badge(
                  isLabelVisible: unreadChat > 0,
                  label: Text(unreadChat > 99 ? '99+' : '$unreadChat'),
                  child: const Icon(Icons.chat_bubble_outline_rounded),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            const NotificationBell(),
            const SizedBox(width: AppSpacing.lg),
            YorksV1WorkspaceStatusLabel(status: workspaceStatus),
          ],
        ),
      ),
    );
  }
}

class _YorksWorkspaceFullscreenButton extends StatelessWidget {
  const _YorksWorkspaceFullscreenButton({
    required this.language,
    required this.controller,
  });

  final AppLanguage language;
  final YorksWorkspaceFullscreenController controller;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('yorks-workspace-fullscreen-toggle'),
    tooltip:
        (controller.isFullscreen
                ? YorksV1ZoomStrings.exitFullscreen
                : YorksV1ZoomStrings.enterFullscreen)
            .active(language),
    onPressed: controller.toggle,
    icon: Icon(
      controller.isFullscreen
          ? Icons.fullscreen_exit_rounded
          : Icons.fullscreen_rounded,
    ),
  );
}

class _YorksWorkspaceMobileTopBar extends StatelessWidget {
  const _YorksWorkspaceMobileTopBar({
    required this.breadcrumbs,
    required this.language,
    required this.location,
    required this.showBack,
    required this.unreadNotifications,
    required this.teamChatEnabled,
    required this.unreadChat,
    required this.onMenu,
    required this.onBack,
  });

  final List<TranslatableString> breadcrumbs;
  final AppLanguage language;
  final String location;
  final bool showBack;
  final int unreadNotifications;
  final bool teamChatEnabled;
  final int unreadChat;
  final VoidCallback onMenu;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final focused = location == RoutePaths.engineerCreateProject;
    final home = location == RoutePaths.engineerHome;
    final title = home
        ? YorksV1ShellStrings.companyName.active(language)
        : breadcrumbs.last.active(language);
    return YorksMobileAppBar(
      title: title,
      brand: home,
      leading: home
          ? null
          : YorksMobileIconButton(
              icon: focused || showBack
                  ? Icons.arrow_back_rounded
                  : Icons.menu_rounded,
              tooltip: focused || showBack
                  ? MaterialLocalizations.of(context).backButtonTooltip
                  : MaterialLocalizations.of(context).openAppDrawerTooltip,
              onPressed: focused || showBack ? onBack : onMenu,
            ),
      trailing: home
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (teamChatEnabled)
                  YorksMobileIconButton(
                    icon: Icons.chat_bubble_outline_rounded,
                    tooltip: YorksV1TeamChatStrings.teamChat.active(language),
                    badge: unreadChat > 0,
                    onPressed: () => context.go(RoutePaths.yorksV1TeamChat),
                  ),
                YorksMobileIconButton(
                  icon: Icons.notifications_none_rounded,
                  tooltip: AppStrings.notifications.active(language),
                  badge: unreadNotifications > 0,
                  onPressed: () => context.push(RoutePaths.notifications),
                ),
              ],
            )
          : null,
    );
  }
}

class _YorksDesktopSidebar extends ConsumerWidget {
  const _YorksDesktopSidebar({
    required this.destinations,
    required this.activePath,
    required this.language,
    required this.role,
    required this.userName,
    required this.expanded,
  });

  final List<_YorksDestination> destinations;
  final String? activePath;
  final AppLanguage language;
  final YorksV1Role? role;
  final String? userName;
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaceStatus = ref.watch(yorksV1WorkspaceStatusProvider);
    TranslatableString? previousGroup;
    final displayName = (userName ?? '').trim();
    return Container(
      width: expanded
          ? AppSpacing.sidebarWidth
          : AppSpacing.sidebarCollapsedWidth,
      decoration: const BoxDecoration(
        color: AppColors.workspaceChrome,
        border: Border(right: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                expanded ? 22 : AppSpacing.xs,
                expanded ? 24 : AppSpacing.lg,
                expanded ? 14 : AppSpacing.xs,
                expanded ? 24 : AppSpacing.lg,
              ),
              child: Row(
                mainAxisAlignment: expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  if (expanded) ...[
                    const BrandLogo(size: 48, shadow: true),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            YorksV1ShellStrings.companyName.active(language),
                            style: AppTypography.titleSmall.copyWith(
                              color: AppColors.navy,
                              fontSize: 14,
                              height: 1.15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            YorksV1ShellStrings.companyLegalName.active(
                              language,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else
                    const BrandLogo(size: 36),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.line),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  expanded ? AppSpacing.md : AppSpacing.xs,
                  AppSpacing.sm,
                  expanded ? AppSpacing.md : AppSpacing.xs,
                  AppSpacing.sm,
                ),
                children: [
                  for (final destination in destinations) ...[
                    if (destination.group != null &&
                        destination.group != previousGroup) ...[
                      if (previousGroup != null)
                        const SizedBox(height: AppSpacing.md),
                      if (expanded)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.sm,
                            AppSpacing.sm,
                            AppSpacing.sm,
                            AppSpacing.sm,
                          ),
                          child: Text(
                            destination.group!.active(language).toUpperCase(),
                            style: AppTypography.labelSmall.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                    ],
                    _YorksNavigationTile(
                      destination: destination,
                      selected:
                          destination.path != null &&
                          destination.path == activePath,
                      language: language,
                      compact: !expanded,
                    ),
                    () {
                      previousGroup = destination.group;
                      return const SizedBox.shrink();
                    }(),
                  ],
                ],
              ),
            ),
            YorksAccountEntry(
              displayName: displayName,
              role: role,
              language: language,
              workspaceStatus: workspaceStatus,
              expanded: expanded,
            ),
            const Divider(height: 1, color: AppColors.line),
            if (expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    YorksV1WorkspaceStatusLabel(
                      status: workspaceStatus,
                      compact: true,
                      language: language,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      YorksV1ShellStrings.connectedProjectControl.active(
                        language,
                      ),
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class YorksAccountEntry extends ConsumerStatefulWidget {
  const YorksAccountEntry({
    super.key,
    required this.displayName,
    required this.role,
    required this.language,
    required this.workspaceStatus,
    required this.expanded,
  });

  final String displayName;
  final YorksV1Role? role;
  final AppLanguage language;
  final YorksV1WorkspaceStatus workspaceStatus;
  final bool expanded;

  @override
  ConsumerState<YorksAccountEntry> createState() => _YorksAccountEntryState();
}

class _YorksAccountEntryState extends ConsumerState<YorksAccountEntry> {
  final MenuController _menu = MenuController();

  void _closeThenGo(String location) {
    _menu.close();
    // MenuAnchor owns an overlay route. Replacing the location cannot become
    // that overlay's pop target; the shared workspace history still provides
    // the expected Back destination after this root-level navigation.
    context.go(location);
  }

  @override
  Widget build(BuildContext context) {
    final fallbackName = widget.displayName.isEmpty
        ? YorksV1ShellStrings.account.active(widget.language)
        : widget.displayName;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.expanded ? AppSpacing.md : AppSpacing.xs,
        AppSpacing.sm,
        widget.expanded ? AppSpacing.md : AppSpacing.xs,
        AppSpacing.md,
      ),
      child: MenuAnchor(
        key: const ValueKey('yorks-account-popover-anchor'),
        controller: _menu,
        alignmentOffset: const Offset(8, -8),
        style: MenuStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          backgroundColor: const WidgetStatePropertyAll(
            AppColors.surfaceContainerLowest,
          ),
          elevation: const WidgetStatePropertyAll(12),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              side: const BorderSide(color: AppColors.line),
            ),
          ),
        ),
        menuChildren: [
          YorksAccountPopover(
            fallbackName: fallbackName,
            fallbackRole: widget.role,
            language: widget.language,
            workspaceStatus: widget.workspaceStatus,
            onOpenProfile: () => _closeThenGo(RoutePaths.engineerProfile),
            onNotifications: () => _closeThenGo(RoutePaths.notifications),
            onHelp: () => _closeThenGo(RoutePaths.about),
            onSignOut: () async {
              _menu.close();
              await showYorksSignOut(context, ref);
            },
          ),
        ],
        builder: (context, controller, child) => Semantics(
          button: true,
          expanded: controller.isOpen,
          label: AppStrings.profile.active(widget.language),
          child: Material(
            color: AppColors.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              side: const BorderSide(color: AppColors.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('yorks-account-entry'),
              onTap: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 7,
                  ),
                  child: Row(
                    mainAxisAlignment: widget.expanded
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _Avatar(name: fallbackName, size: 36),
                          Positioned(
                            right: -1,
                            bottom: -1,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: YorksV1WorkspaceStatusLabel.colorFor(
                                  widget.workspaceStatus.state,
                                ),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.surfaceContainerLowest,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (widget.expanded) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                fallbackName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.labelLarge.copyWith(
                                  color: AppColors.ink,
                                ),
                              ),
                              Text(
                                _roleCopy(widget.role).active(widget.language),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.labelSmall,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          controller.isOpen
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 18,
                          color: AppColors.muted,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class YorksAccountPopover extends ConsumerWidget {
  const YorksAccountPopover({
    super.key,
    required this.fallbackName,
    required this.fallbackRole,
    required this.language,
    required this.workspaceStatus,
    required this.onOpenProfile,
    required this.onNotifications,
    required this.onHelp,
    required this.onSignOut,
  });

  final String fallbackName;
  final YorksV1Role? fallbackRole;
  final AppLanguage language;
  final YorksV1WorkspaceStatus workspaceStatus;
  final VoidCallback onOpenProfile;
  final VoidCallback onNotifications;
  final VoidCallback onHelp;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileState = ref.watch(yorksV1MyProfileProvider);
    final profile = profileState.valueOrNull;
    final protectedName = profile?.displayName.trim();
    final name = protectedName == null || protectedName.isEmpty
        ? fallbackName
        : protectedName;
    final role = profile?.exactRole ?? fallbackRole;
    final accountStatus = profileState.when(
      data: (_) => (
        AppStrings.accountActive.active(language),
        Icons.verified_user_outlined,
        AppColors.success,
      ),
      loading: () => (
        AppStrings.verifyingAccount.active(language),
        Icons.sync_rounded,
        AppColors.blue,
      ),
      error: (_, _) => (
        AppStrings.accountUnavailable.active(language),
        Icons.error_outline_rounded,
        AppColors.error,
      ),
    );
    return SizedBox(
      key: const ValueKey('yorks-account-popover'),
      width: 352,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: const BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppSpacing.radiusLg),
              ),
            ),
            child: Row(
              children: [
                _Avatar(name: name, size: 50),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.titleMedium.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _roleCopy(role).active(language),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall.copyWith(
                          color: const Color(0xFFD7E7F7),
                        ),
                      ),
                      if (profile?.email?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            profile!.email!.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelSmall.copyWith(
                              color: const Color(0xFFBFD7F4),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _YorksAccountStatusRow(
                  key: const ValueKey('yorks-account-authority-status'),
                  icon: accountStatus.$2,
                  label: accountStatus.$1,
                  color: accountStatus.$3,
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.cloud_done_outlined,
                        size: 18,
                        color: AppColors.inkSecondary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          AppStrings.workspaceSync.active(language),
                          style: AppTypography.labelMedium,
                        ),
                      ),
                      YorksV1WorkspaceStatusLabel(
                        status: workspaceStatus,
                        compact: true,
                        language: language,
                      ),
                    ],
                  ),
                ),
                const Divider(height: AppSpacing.xl),
                FilledButton.icon(
                  key: const ValueKey('open-my-yorks'),
                  onPressed: onOpenProfile,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.person_outline_rounded),
                  label: Text(AppStrings.openMyYorks.active(language)),
                ),
                const SizedBox(height: AppSpacing.xs),
                _YorksAccountPopoverAction(
                  icon: Icons.notifications_outlined,
                  label: AppStrings.notifications.active(language),
                  onTap: onNotifications,
                ),
                _YorksAccountPopoverAction(
                  icon: Icons.help_outline_rounded,
                  label: AppStrings.about.active(language),
                  onTap: onHelp,
                ),
                YorksWorkspaceZoomMenu(language: language),
                const Divider(height: AppSpacing.sm),
                _YorksAccountPopoverAction(
                  icon: Icons.logout_rounded,
                  label: AppStrings.signOut.active(language),
                  color: AppColors.error,
                  onTap: onSignOut,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _YorksAccountStatusRow extends StatelessWidget {
  const _YorksAccountStatusRow({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: AppTypography.labelMedium.copyWith(color: color),
            ),
          ),
        ],
      ),
    ),
  );
}

class _YorksAccountPopoverAction extends StatelessWidget {
  const _YorksAccountPopoverAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.ink,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.bodyMedium.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: color.withValues(alpha: 0.65),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _YorksMobileNavigation extends StatelessWidget {
  const _YorksMobileNavigation({
    required this.destinations,
    required this.activePath,
    required this.language,
  });

  final List<_YorksDestination> destinations;
  final String? activePath;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    if (!YorksMobileUi.isActive(context)) {
      return SafeArea(
        top: false,
        minimum: EdgeInsets.zero,
        child: DecoratedBox(
          key: const ValueKey('yorks-compact-navigation-legacy'),
          decoration: const BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: SizedBox(
            height: YorksMobileUi.navigationHeight,
            child: _navigationRow(),
          ),
        ),
      );
    }
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Container(
        key: const ValueKey('yorks-mobile-navigation'),
        height: YorksMobileUi.navigationHeight,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: AppColors.navy.withValues(alpha: .97),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x24142F50),
              blurRadius: 22,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: _navigationRow(),
      ),
    );
  }

  Widget _navigationRow() => Row(
    children: [
      for (final destination in destinations)
        Expanded(
          child: _YorksMobileItem(
            destination: destination,
            selected:
                destination.path == activePath ||
                (destination.path == RoutePaths.yorksV1Projects &&
                    activePath?.startsWith('/yorks/projects') == true) ||
                (destination.path == RoutePaths.yorksV1MaterialRequests &&
                    activePath?.startsWith('/yorks/material-requests') ==
                        true) ||
                (destination.path == RoutePaths.yorksV1TeamChat &&
                    activePath?.startsWith(RoutePaths.yorksV1TeamChat) == true),
            language: language,
          ),
        ),
    ],
  );
}

class _YorksNavigationTile extends StatelessWidget {
  const _YorksNavigationTile({
    required this.destination,
    required this.selected,
    required this.language,
    this.compact = false,
  });

  final _YorksDestination destination;
  final bool selected;
  final AppLanguage language;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final disabled = destination.path == null;
    return Semantics(
      button: !disabled,
      selected: selected,
      enabled: !disabled,
      label: destination.label.active(language),
      child: Tooltip(
        message: destination.label.active(language),
        child: Material(
          color: selected ? AppColors.blueContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            onTap: disabled ? null : () => context.go(destination.path!),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppSpacing.minTapTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Row(
                  mainAxisAlignment: compact
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    _DestinationIcon(
                      destination: destination,
                      selected: selected,
                      color: disabled
                          ? AppColors.mutedLight
                          : selected
                          ? AppColors.blue
                          : AppColors.inkSecondary,
                    ),
                    if (!compact) ...[
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          destination.label.active(language),
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodyMedium.copyWith(
                            color: disabled
                                ? AppColors.mutedLight
                                : selected
                                ? AppColors.navy
                                : AppColors.inkSecondary,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (destination.suffix != null)
                        Text(
                          destination.suffix!.active(language),
                          style: AppTypography.labelSmall,
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _YorksMobileItem extends StatelessWidget {
  const _YorksMobileItem({
    required this.destination,
    required this.selected,
    required this.language,
  });

  final _YorksDestination destination;
  final bool selected;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    if (!YorksMobileUi.isActive(context)) {
      return Semantics(
        button: true,
        selected: selected,
        label: destination.label.active(language),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => context.go(destination.path!),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: AppSpacing.minTapTarget,
              minHeight: AppSpacing.minTapTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DestinationIcon(
                    destination: destination,
                    selected: selected,
                    color: selected ? AppColors.blue : AppColors.muted,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    (destination.compactLabel ?? destination.label).active(
                      language,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelSmall.copyWith(
                      color: selected ? AppColors.blue : AppColors.muted,
                      fontSize: 9,
                      height: 1,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label.active(language),
      child: Material(
        color: selected
            ? AppColors.onPrimary.withValues(alpha: .12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () => context.go(destination.path!),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: AppSpacing.minTapTarget,
              minHeight: AppSpacing.minTapTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DestinationIcon(
                    destination: destination,
                    selected: selected,
                    color: selected
                        ? AppColors.onPrimary
                        : AppColors.lineStrong,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    (destination.compactLabel ?? destination.label).active(
                      language,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelSmall.copyWith(
                      color: selected
                          ? AppColors.onPrimary
                          : AppColors.lineStrong,
                      fontSize: 9,
                      height: 1,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _YorksQuickNavigationButton extends StatelessWidget {
  const _YorksQuickNavigationButton({
    required this.destinations,
    required this.language,
    required this.role,
  });

  final List<_YorksDestination> destinations;
  final AppLanguage language;
  final YorksV1Role? role;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: YorksV1ShellStrings.quickNavigation.active(language),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showYorksV1WorkspaceSearch(
          context,
          targets: [
            for (final destination in destinations)
              if (destination.path != null)
                YorksV1SearchNavigationTarget(
                  label: destination.label,
                  icon: destination.icon,
                  path: destination.path!,
                ),
            if (destinations.any(
              (destination) => destination.path == RoutePaths.yorksV1Workforce,
            ))
              const YorksV1SearchNavigationTarget(
                label: YorksV1ShellStrings.workforceTimesheets,
                icon: Icons.calendar_month_outlined,
                path: RoutePaths.yorksV1WorkforceTimesheets,
              ),
          ],
          language: language,
          role: role,
        ),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.search_rounded,
                size: 19,
                color: AppColors.muted,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  YorksV1ShellStrings.searchOrJump.active(language),
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text('⌘K', style: AppTypography.labelSmall),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.size = 32});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty);
    final initials = words.take(2).map((word) => word.characters.first).join();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.blueContainer,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials.isEmpty ? 'Y' : initials.toUpperCase(),
        style: AppTypography.labelLarge.copyWith(color: AppColors.navy),
      ),
    );
  }
}

class _YorksDestination {
  const _YorksDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.compactLabel,
    this.path,
    this.group,
    this.suffix,
    this.badgeCount = 0,
  });

  final TranslatableString label;
  final IconData icon;
  final IconData selectedIcon;
  final TranslatableString? compactLabel;
  final String? path;
  final TranslatableString? group;
  final TranslatableString? suffix;
  final int badgeCount;
}

class _DestinationIcon extends StatelessWidget {
  const _DestinationIcon({
    required this.destination,
    required this.selected,
    required this.color,
  });

  final _YorksDestination destination;
  final bool selected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      selected ? destination.selectedIcon : destination.icon,
      size: 20,
      color: color,
    );
    // Preserve the established shell geometry exactly when no badge is
    // visible. Wrapping every destination in the wider badge canvas shifts
    // unrelated navigation icons and creates needless visual churn.
    if (destination.badgeCount <= 0) return icon;
    return SizedBox(
      width: 25,
      height: 24,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 1, top: 2, child: icon),
          Positioned(
            right: -2,
            top: -3,
            child: Container(
              constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
              padding: const EdgeInsets.symmetric(horizontal: 3),
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              child: Text(
                destination.badgeCount > 99
                    ? '99+'
                    : '${destination.badgeCount}',
                style: AppTypography.labelSmall.copyWith(
                  color: Colors.white,
                  fontSize: 8,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

TranslatableString _roleCopy(YorksV1Role? role) => switch (role) {
  YorksV1Role.projectEngineer => AppStrings.projectEngineerRole,
  YorksV1Role.siteEngineer => AppStrings.siteEngineerRole,
  YorksV1Role.seniorMechanicalEngineer =>
    AppStrings.seniorMechanicalEngineerRole,
  YorksV1Role.projectManager => AppStrings.projectManagerRole,
  YorksV1Role.workshopInCharge => AppStrings.workshopInChargeRole,
  YorksV1Role.documentController => AppStrings.documentControllerRole,
  YorksV1Role.accountant => AppStrings.accountantRole,
  YorksV1Role.procurement => AppStrings.procurementRole,
  YorksV1Role.admin => AppStrings.adminRole,
  null => YorksV1ShellStrings.account,
};

TranslatableString _workspaceCopy(YorksV1Role? role) => switch (role) {
  YorksV1Role.projectEngineer ||
  YorksV1Role.siteEngineer ||
  YorksV1Role.seniorMechanicalEngineer ||
  YorksV1Role.projectManager ||
  YorksV1Role.workshopInCharge ||
  YorksV1Role.documentController => YorksV1ShellStrings.engineerWorkspace,
  YorksV1Role.accountant => YorksV1ShellStrings.accountantWorkspace,
  YorksV1Role.procurement => YorksV1ShellStrings.procurementWorkspace,
  YorksV1Role.admin => YorksV1ShellStrings.managementWorkspace,
  null => YorksV1ShellStrings.operationalWorkspace,
};

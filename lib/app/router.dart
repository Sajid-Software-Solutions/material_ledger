import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/constants.dart';

import '../features/admin/presentation/screens/access_roles_screen.dart';
import '../features/leave/presentation/screens/leave_requests_screen.dart';
import '../features/leave/presentation/screens/my_leave_screen.dart';
import '../features/admin/presentation/screens/admin_projects_screen.dart';
import '../features/admin/presentation/screens/admin_requests_screen.dart';
import '../features/admin/presentation/screens/data_sync_screen.dart';
import '../features/admin/presentation/screens/more_hub_screen.dart';
import '../features/admin/presentation/screens/material_masters_screen.dart';
import '../features/admin/presentation/screens/user_management_screen.dart';
import '../features/admin/presentation/screens/yorks_v1_user_access_screen.dart';
import '../features/admin/presentation/screens/yorks_v1_configuration_screen.dart';
import '../features/accounts/presentation/screens/yorks_accounts_screens.dart';
import '../features/accounts/presentation/screens/yorks_accounts_office_screen.dart';
import '../features/accounts/domain/accounts_office_models.dart';
import '../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../features/engineer/presentation/screens/engineer_browse_screen.dart';
import '../features/engineering_tools/presentation/screens/yorks_v1_engineering_calculator_screens.dart';
import '../features/engineer/presentation/screens/engineer_create_project_screen.dart';
import '../features/engineer/presentation/screens/engineer_home_screen.dart';
import '../features/engineer/presentation/screens/engineer_new_request_screen.dart';
import '../features/engineer/presentation/screens/engineer_projects_screen.dart';
import '../features/engineer/presentation/screens/engineer_profile_screen.dart'
    deferred as engineer_profile;
import '../features/engineer/presentation/screens/notification_preferences_screen.dart';
import '../features/engineer/presentation/screens/material_picker_screen.dart';
import '../features/engineer/presentation/screens/confirm_receipt_screen.dart';
import '../features/engineer/presentation/screens/employee_detail_screen.dart';
import '../features/engineer/presentation/screens/plan_build_screen.dart';
import '../features/engineer/presentation/screens/plan_diff_screen.dart';
import '../features/engineer/presentation/screens/plan_review_screen.dart';
import '../features/engineer/presentation/screens/request_detail_screen.dart';
import '../features/engineer/presentation/screens/requests_list_screen.dart';
import '../features/engineer/presentation/screens/return_screen.dart';
import '../features/login/presentation/screens/change_password_screen.dart';
import '../features/login/presentation/screens/login_screen.dart';
import '../features/system/presentation/screens/gate_screens.dart';
import '../features/finance/presentation/screens/finance_screen.dart';
import '../features/inventory/presentation/screens/goods_receipt_screen.dart';
import '../features/inventory/presentation/screens/inventory_screen.dart';
import '../features/inventory/presentation/screens/stock_history_screen.dart';
import '../features/materials/presentation/screens/materials_hub_screen.dart';
import '../features/materials/presentation/screens/material_line_grid_demo_screen.dart';
import '../features/materials/presentation/screens/yorks_v1_arrangement_screen.dart';
import '../features/materials/presentation/screens/yorks_v1_inventory_import_screen.dart';
import '../features/materials/presentation/screens/yorks_v1_inventory_screen.dart';
import '../features/materials/presentation/screens/yorks_v1_inventory_supplier_screens.dart';
import '../features/materials/presentation/screens/yorks_v1_logistics_screen.dart';
import '../features/materials/presentation/screens/yorks_v1_material_request_screens.dart';
import '../features/materials/presentation/screens/yorks_v1_company_material_request_screen.dart'
    deferred as company_material_request;
import '../features/materials/presentation/screens/yorks_v1_material_returns_screen.dart';
import '../features/materials/presentation/screens/yorks_v1_returns_documents_screen.dart';
import '../features/onboarding/presentation/screens/language_selection_screen.dart';
import '../features/onboarding/presentation/screens/splash_screen.dart';
import '../features/people/presentation/screens/employee_profile_screen.dart';
import '../features/people/presentation/screens/people_dashboard_screen.dart';
import '../features/procurement/presentation/screens/procurement_dispatch_screen.dart';
import '../features/procurement/presentation/screens/procurement_plan_review_screen.dart';
import '../features/procurement/presentation/screens/procurement_workspace_screen.dart';
import '../features/projects/presentation/screens/project_workspace_screen.dart';
import '../features/projects/presentation/screens/yorks_v1_boq_screens.dart';
import '../features/projects/presentation/screens/yorks_v1_project_create_flow_screen.dart';
import '../features/projects/presentation/screens/yorks_v1_documents_screen.dart';
import '../features/projects/presentation/screens/yorks_v1_projects_screen.dart';
import '../features/rentals/presentation/screens/rental_unit_detail_screen.dart';
import '../features/rentals/presentation/screens/rentals_dashboard_screen.dart';
import '../features/chat/presentation/screens/yorks_v1_team_chat_screen.dart';
import '../features/company_overview/presentation/company_analytics_screen.dart';
import '../features/transactions/presentation/screens/transactions_screen.dart';
import '../features/workforce/presentation/screens/yorks_workforce_daily_attendance_screen.dart';
import '../features/workforce/presentation/screens/yorks_workforce_administration_screen.dart';
import '../features/workforce/presentation/screens/yorks_workforce_overview_screen.dart';
import '../features/workforce/presentation/screens/yorks_workforce_timesheets_screen.dart';
import '../shared/models/app_config.dart';
import '../shared/models/app_user.dart';
import '../shared/models/role_permissions.dart';
import '../shared/models/user_role.dart';
import '../shared/models/yorks_v1_permission_management.dart';
import '../shared/models/yorks_v1_material_request.dart';
import '../shared/models/yorks_v1_role.dart';
import '../shared/providers/yorks_v1_permission_provider.dart';
import '../shared/screens/about_screen.dart';
import '../shared/screens/activity_log_screen.dart';
import '../shared/screens/notifications_screen.dart';
import '../shared/screens/privacy_policy_screen.dart';
import '../shared/screens/terms_of_service_screen.dart';
import 'app_shell.dart';
import 'engineer_shell.dart';
import 'yorks_v1_workspace_shell.dart';

/// Route path constants
abstract final class RoutePaths {
  // ─── Onboarding & Auth ─────────────────────────────────────
  static const String splash = '/splash';
  static const String languageSelection = '/language-selection';
  static const String login = '/login';
  static const String changePassword = '/change-password';
  static const String updateRequired = '/update-required';
  static const String maintenance = '/maintenance';

  // ─── Tab roots (StatefulShellRoute branches) ───────────────
  static const String engineerHome = '/'; // Home (role-aware dashboard)
  static const String materials = '/materials'; // Materials hub
  static const String rentals = '/rentals'; // Rentals hub
  static const String people = '/people'; // People hub
  static const String more = '/more'; // Admin · settings hub
  /// Office home alias (kept for older call sites; Home is unified at root).
  static const String dashboard = '/';

  // ─── Materials flows (full-screen, reached from the hub/Home) ─
  static const String engineerBrowse = '/browse';
  static const String engineerProjects = '/projects';
  static const String engineerCreateProject = '/projects/new';
  static const String projectWorkspace = '/projects/:id';
  static const String yorksV1Projects = '/yorks/projects';
  static const String yorksV1Analytics = '/yorks/analytics';
  static const String yorksV1Project = '/yorks/projects/:projectId';
  static const String yorksV1ProjectEdit = '/yorks/projects/:projectId/edit';
  static const String yorksV1BoqGroups = '/yorks/projects/:projectId/boq';
  static const String yorksV1BoqWorksheet =
      '/yorks/projects/:projectId/boq/:groupId';
  static const String yorksV1ProjectDocuments =
      '/yorks/projects/:projectId/documents';
  static const String yorksV1Accounts = '/yorks/accounts';
  static const String yorksV1AccountsProjects = '/yorks/accounts/projects';
  static const String yorksV1AccountsBillingProgress =
      '/yorks/accounts/billing-progress';
  static const String yorksV1AccountsClaims = '/yorks/accounts/claims';
  static const String yorksV1AccountsClientPayments =
      '/yorks/accounts/client-payments';
  static const String yorksV1AccountsSupplierBills =
      '/yorks/accounts/supplier-bills';
  static const String yorksV1AccountsDueSchedule =
      '/yorks/accounts/due-schedule';
  static const String yorksV1AccountsDocuments = '/yorks/accounts/documents';
  static const String yorksV1AccountsReports = '/yorks/accounts/reports';
  static const String yorksV1AccountsActivity = '/yorks/accounts/activity';
  static const String yorksV1ProjectAccounts =
      '/yorks/projects/:projectId/accounts';
  static const String yorksV1ProjectAccountsOverview =
      '/yorks/projects/:projectId/accounts/overview';
  static const String yorksV1ProjectAccountsBilling =
      '/yorks/projects/:projectId/accounts/billing';
  static const String yorksV1ProjectAccountsInvoices =
      '/yorks/projects/:projectId/accounts/client-invoices';
  static const String yorksV1ProjectAccountsReceiptsPdc =
      '/yorks/projects/:projectId/accounts/receipts-pdc';
  static const String yorksV1ProjectAccountsSupplierBills =
      '/yorks/projects/:projectId/accounts/supplier-bills';
  static const String yorksV1ProjectAccountsDocuments =
      '/yorks/projects/:projectId/accounts/documents';
  static const String yorksV1ProjectAccountsActivity =
      '/yorks/projects/:projectId/accounts/activity';
  static const String yorksV1MaterialRequests = '/yorks/material-requests';
  static const String yorksV1MaterialRequestDraft =
      '/yorks/material-requests/draft/:draftId';
  static const String yorksV1CompanyMaterialRequests =
      '/yorks/material-requests/company';
  static const String yorksV1CompanyMaterialRequestNew =
      '/yorks/material-requests/company/new';
  static const String yorksV1CompanyMaterialRequest =
      '/yorks/material-requests/company/:requestId';
  static const String yorksV1MaterialRequest =
      '/yorks/material-requests/:requestId';
  static const String yorksV1MaterialRequestArrangement =
      '/yorks/material-requests/:requestId/arrangement';
  static const String yorksV1MaterialRequestLogistics =
      '/yorks/material-requests/:requestId/logistics';
  static const String yorksV1MaterialRequestReturnsDocuments =
      '/yorks/material-requests/:requestId/returns';
  static const String yorksV1Inventory = '/yorks/inventory';
  static const String yorksV1InventorySuppliers = '/yorks/inventory/suppliers';
  static const String yorksV1InventorySupplier =
      '/yorks/inventory/suppliers/:supplierId';
  static const String yorksV1InventoryImport = '/yorks/inventory/import';
  static const String yorksV1Dispatches = '/yorks/dispatches';
  static const String yorksV1Returns = '/yorks/returns';
  static const String yorksV1MaterialReturnNew = '/yorks/returns/new';
  static const String yorksV1MaterialReturn = '/yorks/returns/:returnId';
  static const String yorksV1Configuration = '/yorks/configuration';
  static const String yorksV1Workforce = '/yorks/workforce';
  static const String yorksV1WorkforceAdministration =
      '/yorks/workforce/administration';
  static const String yorksV1WorkforceAttendance =
      '/yorks/workforce/attendance';
  static const String yorksV1WorkforceTimesheets =
      '/yorks/workforce/timesheets';
  static const String yorksV1TeamChat = '/yorks/team-chat';
  static const String yorksV1TeamChatConversation =
      '/yorks/team-chat/:conversationId';
  static const String engineerProjectsView = '/my-projects';
  static const String engineerNewRequest = '/new-request';
  static const String engineerPickMaterials = '/pick-materials';
  static const String engineerProfile = '/profile';
  static const String requestDetail = '/request/:id';
  static const String requests = '/requests';
  static const String employeeDetail = '/me';
  static const String planReview = '/plan/:id';
  static const String planBuild = '/plan-build/:id';
  static const String planDiff = '/plan-diff/:id';
  static const String confirmReceipt = '/receipt/:id';
  static const String returnStore = '/return';
  static const String yorksV1DuctSizer = '/tools/duct-sizer';
  static const String yorksV1EspCalculator = '/tools/esp-calculator';

  /// Engineer self-service leave (reached from the Profile tab).
  static const String myLeave = '/my-leave';

  /// Admin/procurement leave approvals queue (reached from the People hub).
  static const String leaveRequests = '/people/leave-requests';

  static String planReviewPath(String projectId) => '/plan/$projectId';
  static String projectWorkspacePath(String projectId) =>
      '/projects/$projectId';
  static String yorksV1ProjectPath(String projectId) =>
      '/yorks/projects/$projectId';
  static String yorksV1ProjectEditPath(String projectId) =>
      '/yorks/projects/$projectId/edit';
  static String yorksV1BoqGroupsPath(String projectId) =>
      '/yorks/projects/$projectId/boq';
  static String yorksV1BoqWorksheetPath(String projectId, String groupId) =>
      '/yorks/projects/$projectId/boq/$groupId';
  static String yorksV1ProjectDocumentsPath(
    String projectId, {
    String? entityType,
    String? entityId,
  }) {
    final queryParameters = <String, String>{};
    if (entityType != null) queryParameters['entity_type'] = entityType;
    if (entityId != null) queryParameters['entity_id'] = entityId;
    return Uri(
      path: '/yorks/projects/$projectId/documents',
      queryParameters: queryParameters,
    ).toString();
  }

  static String yorksV1ProjectAccountsPath(String projectId) =>
      '/yorks/projects/$projectId/accounts';
  static String yorksV1ProjectAccountsOverviewPath(String projectId) =>
      '/yorks/projects/$projectId/accounts/overview';
  static String yorksV1ProjectAccountsBillingPath(String projectId) =>
      '/yorks/projects/$projectId/accounts/billing';
  static String yorksV1ProjectAccountsInvoicesPath(String projectId) =>
      '/yorks/projects/$projectId/accounts/client-invoices';
  static String yorksV1ProjectAccountsReceiptsPdcPath(String projectId) =>
      '/yorks/projects/$projectId/accounts/receipts-pdc';
  static String yorksV1ProjectAccountsSupplierBillsPath(String projectId) =>
      '/yorks/projects/$projectId/accounts/supplier-bills';
  static String yorksV1ProjectAccountsDocumentsPath(String projectId) =>
      '/yorks/projects/$projectId/accounts/documents';
  static String yorksV1ProjectAccountsActivityPath(String projectId) =>
      '/yorks/projects/$projectId/accounts/activity';

  static String yorksV1MaterialRequestDraftPath(
    String draftId, {
    String? boqGroupId,
    String? projectId,
    int? boqVersion,
    YorksV1MaterialRequestDraftEntryMode? entryMode,
  }) {
    if ((boqGroupId == null || boqGroupId.trim().isEmpty) &&
        (projectId == null || projectId.trim().isEmpty) &&
        entryMode == null) {
      return '/yorks/material-requests/draft/$draftId';
    }
    final query = <String, String>{};
    if (boqGroupId != null && boqGroupId.trim().isNotEmpty) {
      query['boq_group_id'] = boqGroupId;
    }
    if (projectId != null && projectId.trim().isNotEmpty) {
      query['project_id'] = projectId;
    }
    if (boqVersion != null) query['boq_version'] = '$boqVersion';
    if (entryMode != null) query['entry_mode'] = entryMode.wireValue;
    return Uri(
      path: '/yorks/material-requests/draft/$draftId',
      queryParameters: query,
    ).toString();
  }

  static String yorksV1MaterialRequestPath(
    String requestId, {
    String? commentId,
  }) => Uri(
    path: '/yorks/material-requests/$requestId',
    queryParameters: commentId == null || commentId.trim().isEmpty
        ? null
        : {'comment': commentId.trim()},
  ).toString();

  static String yorksV1CompanyMaterialRequestPath(String requestId) =>
      '/yorks/material-requests/company/$requestId';

  static String yorksV1TeamChatPath([String? conversationId]) {
    final id = conversationId?.trim() ?? '';
    return id.isEmpty ? yorksV1TeamChat : '/yorks/team-chat/$id';
  }

  static String yorksV1InventorySupplierPath(String supplierId) =>
      '/yorks/inventory/suppliers/$supplierId';

  static String yorksV1MaterialReturnPath(String returnId) =>
      '/yorks/returns/$returnId';

  static String yorksV1MaterialReturnEditPath(
    String projectId,
    String returnId,
  ) => Uri(
    path: yorksV1MaterialReturnNew,
    queryParameters: {'project_id': projectId, 'return_id': returnId},
  ).toString();

  static String yorksV1MaterialRequestsPath({String? projectId}) {
    final trimmed = projectId?.trim();
    if (trimmed == null || trimmed.isEmpty) return yorksV1MaterialRequests;
    return Uri(
      path: yorksV1MaterialRequests,
      queryParameters: {'project_id': trimmed},
    ).toString();
  }

  static String yorksV1MaterialRequestArrangementPath(String requestId) =>
      '/yorks/material-requests/$requestId/arrangement';

  /// Opens the protected dispatch/receipt workspace. A receipt focus simply
  /// selects a server-authorized delivery for the review dialog; it does not
  /// carry or mutate any receipt state through the URL.
  static String yorksV1MaterialRequestLogisticsPath(
    String requestId, {
    bool focusReceiptReview = false,
    String? dispatchId,
  }) {
    if (!focusReceiptReview && (dispatchId == null || dispatchId.isEmpty)) {
      return '/yorks/material-requests/$requestId/logistics';
    }
    return Uri(
      path: '/yorks/material-requests/$requestId/logistics',
      queryParameters: {
        if (focusReceiptReview) 'focus': 'receipt_review',
        if (dispatchId != null && dispatchId.isNotEmpty)
          'dispatch_id': dispatchId,
      },
    ).toString();
  }

  /// Opens the Delivery Order command from a committed dispatch without
  /// making the operator navigate through the Material Returns workspace.
  /// The route still performs its normal server-authorized workspace fetch;
  /// query parameters only select the already-authorized presentation focus.
  static String yorksV1MaterialRequestReturnsDocumentsPath(
    String requestId, {
    bool focusDeliveryOrder = false,
    String? dispatchId,
  }) {
    if (!focusDeliveryOrder && (dispatchId == null || dispatchId.isEmpty)) {
      return '/yorks/material-requests/$requestId/returns';
    }
    return Uri(
      path: '/yorks/material-requests/$requestId/returns',
      queryParameters: {
        if (focusDeliveryOrder) 'focus': 'delivery_order',
        if (dispatchId != null && dispatchId.isNotEmpty)
          'dispatch_id': dispatchId,
      },
    ).toString();
  }

  static String planBuildPath(String projectId) => '/plan-build/$projectId';
  static String planDiffPath(String projectId) => '/plan-diff/$projectId';
  static String confirmReceiptPath(String requestId) => '/receipt/$requestId';
  static String requestDetailPath(String requestId) => '/request/$requestId';

  // ─── Office / admin screens (full-screen, reached from hubs) ─
  static const String inventory = '/admin/inventory';
  static const String materialMasters = '/admin/material-masters';
  static const String materialLineGridDemo = '/debug/material-line-grid';
  static const String stockHistory = '/admin/inventory/history';
  static const String transactions = '/admin/transactions';
  static const String goodsReceipt = '/admin/goods-receipt';
  static const String finance = '/admin/finance';
  static const String adminPanel =
      '/admin/panel'; // legacy → redirects to /more
  static const String adminProjects = '/admin/projects';
  static const String adminRequests = '/admin/requests';
  static const String users = '/admin/users';
  static const String yorksV1UserAccess = '/admin/users/:appUserId/access';
  static const String accessRoles = '/access-roles';
  static const String dataSync = '/data-sync';
  static const String procurement = '/admin/procurement';
  static const String planReviewProcurement = '/admin/plan-review/:id';
  static const String dispatch = '/admin/dispatch/:id';

  static String planReviewProcurementPath(String projectId) =>
      '/admin/plan-review/$projectId';
  static String dispatchPath(String requestId) => '/admin/dispatch/$requestId';

  static String yorksV1UserAccessPath(String appUserId) =>
      '/admin/users/${appUserId.trim()}/access';

  // ─── Rentals / People details ───────────────────────────────
  static const String rentalUnit = '/rentals/:id';
  static String rentalUnitPath(String unitId) => '/rentals/$unitId';
  static const String employeeProfile = '/people/:id';
  static String employeeProfilePath(String employeeId) => '/people/$employeeId';

  // ─── Shared ─────────────────────────────────────────────────
  static const String about = '/about';
  static const String activityLog = '/activity';
  static const String notifications = '/notifications';
  static const String notificationPreferences = '/notification-preferences';
  static const String yorksV1MobileMore = '/yorks/more';
  static const String privacyPolicy = '/privacy-policy';
  static const String termsOfService = '/terms-of-service';
}

// ─── Page transition helpers (keep route definitions terse) ──────────
Page<void> _fade(LocalKey key, Widget child, {int ms = 0}) =>
    NoTransitionPage<void>(key: key, child: child);

Page<void> _slide(
  LocalKey key,
  Widget child, {
  Offset begin = const Offset(1, 0),
}) => NoTransitionPage<void>(key: key, child: child);

/// V1 record routes retain their feature-local scaffold and controllers while
/// sharing the approved R35 Yorks navigation chrome. The wrapper is deliberately
/// absent from retained legacy routes so the V1 rollout cannot restyle or alter
/// their behavior by accident.
Page<void> _yorksV1Slide(LocalKey key, Widget child) =>
    _slide(key, YorksV1WorkspaceShell(child: child));

/// Slide-in page for screens that were originally office-shell *tabs* and so
/// have no `Scaffold`/`Material` of their own. When reached as a full-screen
/// route from a hub we wrap them in a slim Scaffold so they get a Material
/// ancestor and an automatic back button.
Page<void> _framed(LocalKey key, Widget child) => _slide(
  key,
  Scaffold(
    backgroundColor: AppColors.surface,
    appBar: AppBar(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      toolbarHeight: 48,
    ),
    body: child,
  ),
);

/// Routes open to a [UserRole]. The in-app half of role-based access control
/// (the Firestore Security Rules enforce the same server-side).
bool? _isAllowedForRole(
  String path,
  UserRole role,
  AppUser? user,
  RolePermissions perms,
  YorksV1Role? yorksV1Role,
  YorksV1HybridPermissionResolver? permissionResolver,
) {
  // Grantable boundaries resolve through: per-user override → editable role
  // default (Access & Roles matrix) → built-in baseline.
  final canReceiveGoods = resolveCapability(
    user,
    role,
    perms,
    RoleCapability.goods,
  );
  final canViewFinance = resolveCapability(
    user,
    role,
    perms,
    RoleCapability.finance,
  );
  final canViewCommercials = resolveCapability(
    user,
    role,
    perms,
    RoleCapability.viewCommercials,
  );
  final canAccessPeople = resolveCapability(
    user,
    role,
    perms,
    RoleCapability.people,
  );

  // Reached from the profile menu / shared across every role.
  const sharedAll = {
    RoutePaths.engineerHome,
    RoutePaths.about,
    RoutePaths.notifications,
    RoutePaths.notificationPreferences,
    RoutePaths.yorksV1MobileMore,
    RoutePaths.privacyPolicy,
    RoutePaths.termsOfService,
    RoutePaths.employeeDetail,
    RoutePaths.engineerProfile,
  };
  if (sharedAll.contains(path)) return true;

  if (_isYorksV1AccountsPath(path)) return true;
  if (_isYorksV1WorkforcePath(path)) return true;
  if (_isYorksV1AnalyticsPath(path)) return true;

  // Accountant is an Accounts-only identity. Normalized Accounts paths are
  // accepted above and then resolved through the protected capability guard.
  if (role == UserRole.accountant) return false;

  // Materials hub is an office tab; engineers use their own Browse instead.
  if (path == RoutePaths.materials) return role.usesAdminPanel;

  // Admin-only: the More hub + administration screens + admin oversight.
  // The connected project register is shared by office roles; destructive
  // controls remain Admin-only inside the screen.
  if (path == RoutePaths.adminProjects) return role.usesAdminPanel;
  if (path == RoutePaths.more ||
      path == RoutePaths.accessRoles ||
      path == RoutePaths.dataSync ||
      path == RoutePaths.materialMasters ||
      path == RoutePaths.adminRequests) {
    return role.isAdmin;
  }
  if (path == RoutePaths.users || path.startsWith('${RoutePaths.users}/')) {
    final legacy = yorksV1Role?.canConfigureUsers ?? role.isAdmin;
    return _hybridRouteAllows(
      permissionResolver,
      YorksV1CapabilityKeys.usersView,
      legacyAllowed: legacy,
    );
  }
  if (path == RoutePaths.activityLog) {
    return _hybridRouteAllows(
      permissionResolver,
      YorksV1CapabilityKeys.auditView,
      legacyAllowed: yorksV1Role == YorksV1Role.admin,
    );
  }
  if (path == RoutePaths.goodsReceipt) return canReceiveGoods;
  if (path == RoutePaths.finance) {
    return canViewFinance && canViewCommercials;
  }

  // Leave approvals — gated by its own (editable) capability, checked before
  // the generic /people rule since the path lives under /people.
  if (path == RoutePaths.leaveRequests) {
    return resolveCapability(user, role, perms, RoleCapability.approveLeave);
  }

  // Modules with their own tab + detail screens.
  // The normalized R38.4 rental workspace is deliberately Admin-only for the
  // first rollout. The client guard follows the same exact, server-controlled
  // Yorks role claim as the rental RPCs; legacy capability overrides cannot
  // expose commercial tenant, rent, receipt or cheque data.
  if (path.startsWith('/rentals')) {
    return _hybridRouteAllows(
      permissionResolver,
      YorksV1CapabilityKeys.rentalsView,
      legacyAllowed: yorksV1Role == YorksV1Role.admin,
    );
  }
  if (path.startsWith('/people')) return canAccessPeople;

  // Remaining office screens (inventory, transactions, procurement, dispatch,
  // plan-review) — non-engineer roles only.
  if (path == RoutePaths.inventory ||
      path == RoutePaths.transactions ||
      path == RoutePaths.procurement ||
      path.startsWith('/admin/')) {
    return role.usesAdminPanel;
  }

  // Leave self-service is for staff who request leave — engineers and
  // procurement — not the owner/admin, who approves it in the office panel.
  if (path == RoutePaths.myLeave) return !role.isAdmin;

  // Engineer materials flows (browse, projects, new-request, request/:id,
  // requests, receipt/:id, return, plan*) + anything else → all roles.
  return true;
}

/// Exact V1 experience guard for routes whose workspace visibility is narrower
/// than the shared project/request read surface. Trusted RPCs and RLS remain
/// authoritative; this prevents a stale link from building an inappropriate
/// editor or organization-wide queue before the server rejects it.
bool? _isYorksV1RouteAllowedForRole(
  Uri uri,
  YorksV1Role? role,
  YorksV1HybridPermissionResolver? permissionResolver,
) {
  final path = uri.path;
  // Engineering calculators deliberately live outside the `/yorks/` prefix,
  // so evaluate their exact role boundary before the generic V1-path fast
  // path below. Otherwise a Procurement deep link reaches an Engineer-only
  // tool simply because its URL has a historical top-level prefix.
  if (path == RoutePaths.yorksV1DuctSizer ||
      path == RoutePaths.yorksV1EspCalculator) {
    return role?.isEngineering ?? false;
  }

  if (!path.startsWith('/yorks/')) return true;
  if (role == null) return false;

  if (_isYorksV1AnalyticsPath(path)) {
    return _hybridRouteAllows(
      permissionResolver,
      YorksV1CapabilityKeys.analyticsView,
      legacyAllowed: false,
      organizationSummary: true,
    );
  }

  if (_isYorksV1AccountsPath(path)) {
    final projectId = _yorksV1ProjectIdFromPath(path);
    if (projectId == null) {
      if (!_canOpenAccountsPortfolio(role)) return false;
      final canViewAccounts = _hybridRouteAllows(
        permissionResolver,
        YorksV1CapabilityKeys.viewProjectAccounts,
        legacyAllowed: false,
        organizationSummary: true,
      );
      if (path != RoutePaths.yorksV1AccountsSupplierBills) {
        return canViewAccounts;
      }
      final canViewSupplierCosts = _hybridRouteAllows(
        permissionResolver,
        YorksV1CapabilityKeys.viewSupplierCosts,
        legacyAllowed: false,
        organizationSummary: true,
      );
      if (canViewAccounts == false || canViewSupplierCosts == false) {
        return false;
      }
      if (canViewAccounts == null || canViewSupplierCosts == null) return null;
      return true;
    }
    final supplierOnly = path.endsWith('/supplier-bills');
    final capability = supplierOnly
        ? YorksV1CapabilityKeys.viewSupplierCosts
        : YorksV1CapabilityKeys.viewProjectAccounts;
    return _hybridRouteAllows(
      permissionResolver,
      capability,
      legacyAllowed: false,
      projectId: projectId,
      organizationSummary: false,
    );
  }

  if (_isYorksV1WorkforcePath(path)) {
    if (path == RoutePaths.yorksV1WorkforceAdministration) {
      final canView = _hybridRouteAllows(
        permissionResolver,
        YorksV1CapabilityKeys.workforceView,
        legacyAllowed: false,
        organizationSummary: true,
      );
      if (canView != true) return canView;
      return _hybridRouteAllowsAny(permissionResolver, const [
        YorksV1CapabilityKeys.workforceWorkersManage,
        YorksV1CapabilityKeys.workforceTeamsManage,
        YorksV1CapabilityKeys.workforceConfigurationManage,
      ]);
    }
    return _hybridRouteAllows(
      permissionResolver,
      YorksV1CapabilityKeys.workforceView,
      legacyAllowed: false,
      organizationSummary: true,
    );
  }

  // Accountant inherits no non-Accounts project, BOQ, MR, Inventory or
  // administration route merely because it is a recognized platform role.
  if (role == YorksV1Role.accountant) return false;

  if (path == RoutePaths.yorksV1Projects ||
      path.startsWith('${RoutePaths.yorksV1Projects}/')) {
    final projectId = _yorksV1ProjectIdFromPath(path);
    final decision = _hybridRouteAllows(
      permissionResolver,
      YorksV1CapabilityKeys.projectsView,
      legacyAllowed: true,
      projectId: projectId,
      organizationSummary: projectId == null,
    );
    if (decision != true) return decision;

    // BOQ is a separate protected read surface. A person may retain access to
    // the project workspace while an explicit BOQ deny removes workbook data.
    // Check both the folder route and individual worksheet deep links here;
    // RPC/RLS repeats the same project-scoped decision.
    final projectSegments = uri.pathSegments;
    final isBoqRoute =
        projectSegments.length >= 4 &&
        projectSegments[0] == 'yorks' &&
        projectSegments[1] == 'projects' &&
        projectSegments[3] == 'boq';
    if (isBoqRoute) {
      final boqDecision = _hybridRouteAllows(
        permissionResolver,
        YorksV1CapabilityKeys.boqView,
        legacyAllowed: true,
        projectId: projectId,
        organizationSummary: false,
      );
      if (boqDecision != true) return boqDecision;
    }
  }

  if (path == RoutePaths.yorksV1MaterialRequests ||
      path.startsWith('${RoutePaths.yorksV1MaterialRequests}/')) {
    // Company-use requests have their own server-authoritative, effective
    // category/unit authorization. Do not make the project-register capability
    // a client-side substitute for that independent boundary.
    if (path == RoutePaths.yorksV1CompanyMaterialRequests ||
        path.startsWith('${RoutePaths.yorksV1CompanyMaterialRequests}/')) {
      return true;
    }
    final projectId = uri.queryParameters['project_id']?.trim();
    final decision = _hybridRouteAllows(
      permissionResolver,
      YorksV1CapabilityKeys.materialRequestsView,
      legacyAllowed: true,
      projectId: projectId == null || projectId.isEmpty ? null : projectId,
      organizationSummary: projectId == null || projectId.isEmpty,
    );
    if (decision != true) return decision;
  }

  if (path == RoutePaths.yorksV1TeamChat ||
      path.startsWith('${RoutePaths.yorksV1TeamChat}/')) {
    return _hybridRouteAllows(
      permissionResolver,
      YorksV1CapabilityKeys.chatView,
      legacyAllowed: true,
    );
  }

  if (path == RoutePaths.yorksV1Inventory ||
      path == RoutePaths.yorksV1Dispatches) {
    if (path == RoutePaths.yorksV1Inventory) {
      return _hybridRouteAllows(
        permissionResolver,
        YorksV1CapabilityKeys.inventoryView,
        legacyAllowed: role.canBrowseInventory,
      );
    }
    return _hybridRouteAllows(
      permissionResolver,
      YorksV1CapabilityKeys.dispatchView,
      legacyAllowed:
          role == YorksV1Role.procurement || role == YorksV1Role.admin,
    );
  }

  if (path == RoutePaths.yorksV1InventorySuppliers ||
      path == RoutePaths.yorksV1InventoryImport ||
      path.startsWith('${RoutePaths.yorksV1InventorySuppliers}/')) {
    final structurallyEligible =
        role == YorksV1Role.procurement || role == YorksV1Role.admin;
    if (!structurallyEligible) return false;
    return _hybridRouteAllows(
      permissionResolver,
      YorksV1CapabilityKeys.inventoryView,
      legacyAllowed: role.canBrowseInventory,
    );
  }

  if (path == RoutePaths.yorksV1Configuration) {
    return _hybridRouteAllows(
      permissionResolver,
      YorksV1CapabilityKeys.configurationView,
      legacyAllowed: role == YorksV1Role.admin,
    );
  }

  if (path == RoutePaths.yorksV1Returns ||
      path.startsWith('${RoutePaths.yorksV1Returns}/')) {
    return _hybridRouteAllows(
      permissionResolver,
      YorksV1CapabilityKeys.returnsView,
      legacyAllowed: true,
    );
  }

  if (path.startsWith('/yorks/projects/') && path.endsWith('/edit')) {
    final structurallyEligible =
        role.isEngineering || role == YorksV1Role.admin;
    if (!structurallyEligible) return false;
    return _hybridRouteAllows(
      permissionResolver,
      YorksV1CapabilityKeys.projectsEdit,
      legacyAllowed: structurallyEligible,
      projectId: _yorksV1ProjectIdFromPath(path),
      organizationSummary: false,
    );
  }

  return true;
}

bool? _hybridRouteAllows(
  YorksV1HybridPermissionResolver? resolver,
  String capabilityKey, {
  required bool legacyAllowed,
  String? projectId,
  bool organizationSummary = true,
}) {
  if (resolver == null) return legacyAllowed;
  return resolver(
    capabilityKey,
    legacyAllowed: legacyAllowed,
    organizationSummary: organizationSummary,
    projectId: projectId,
  );
}

bool? _hybridRouteAllowsAny(
  YorksV1HybridPermissionResolver? resolver,
  Iterable<String> capabilityKeys,
) {
  if (resolver == null) return false;
  var unresolved = false;
  for (final capabilityKey in capabilityKeys) {
    final decision = resolver(
      capabilityKey,
      legacyAllowed: false,
      organizationSummary: true,
    );
    if (decision == true) return true;
    if (decision == null) unresolved = true;
  }
  return unresolved ? null : false;
}

String? _yorksV1ProjectIdFromPath(String path) {
  final segments = Uri(path: path).pathSegments;
  if (segments.length < 3 ||
      segments[0] != 'yorks' ||
      segments[1] != 'projects') {
    return null;
  }
  final projectId = segments[2].trim();
  return projectId.isEmpty ? null : projectId;
}

bool _isYorksV1AccountsPath(String path) =>
    path == RoutePaths.yorksV1Accounts ||
    path.startsWith('${RoutePaths.yorksV1Accounts}/') ||
    (path.startsWith('/yorks/projects/') && path.contains('/accounts'));

bool _isYorksV1WorkforcePath(String path) =>
    path == RoutePaths.yorksV1Workforce ||
    path.startsWith('${RoutePaths.yorksV1Workforce}/');

bool _isYorksV1AnalyticsPath(String path) =>
    path == RoutePaths.yorksV1Analytics ||
    path.startsWith('${RoutePaths.yorksV1Analytics}/');

bool _canOpenAccountsPortfolio(YorksV1Role role) =>
    role == YorksV1Role.admin ||
    role == YorksV1Role.accountant ||
    role == YorksV1Role.projectManager ||
    role == YorksV1Role.seniorMechanicalEngineer;

/// Creates the app [GoRouter].
/// [isOnboarded], [isLoggedIn], [role] and [user] drive redirect / access logic.
GoRouter createAppRouter({
  required bool isOnboarded,
  required bool isLoggedIn,
  required UserRole role,
  AppUser? user,
  AppGate gate = AppGate.none,

  /// Exact V1 authority is deliberately supplied separately from [role]. The
  /// legacy shell role is a compatibility presentation value only and must not
  /// turn a legacy Engineer into a Project Engineer.
  bool yorksV1ProjectsEnabled = false,
  bool yorksV1BoqEnabled = false,
  bool yorksV1RequestsEnabled = false,
  bool yorksV1CompanyMaterialRequestsEnabled = false,
  bool yorksV1ArrangementEnabled = false,
  bool yorksV1LogisticsEnabled = false,
  bool yorksV1ReturnsDocumentsEnabled = false,
  bool yorksV1DocumentsEnabled = false,
  bool yorksV1TeamChatEnabled = false,
  bool yorksV1InventorySuppliersEnabled = false,
  bool yorksV1AccountsEnabled = false,
  bool yorksV1WorkforceEnabled = false,
  bool yorksV1AnalyticsEnabled = false,
  YorksV1Role? yorksV1Role,
  YorksV1HybridPermissionResolver? yorksV1PermissionResolver,
  // Live editable role-permission defaults. A getter (not a snapshot) + the
  // [refreshListenable] let route guards re-evaluate the moment an Admin edits
  // the matrix, WITHOUT rebuilding the router (no nav reset).
  RolePermissions Function()? rolePermissions,
  Listenable? refreshListenable,
}) {
  // Retained engineers keep their original shell. Once the normalized Yorks
  // rollout is active, engineers use the same R35 workspace shell as the
  // connected project routes so the desktop rail does not disappear at Home.
  final useEngineerShell = !role.usesAdminPanel;
  final initialLocation = !isOnboarded
      ? RoutePaths.splash
      : !isLoggedIn
      ? RoutePaths.login
      : yorksV1AccountsEnabled && yorksV1Role == YorksV1Role.accountant
      ? RoutePaths.yorksV1Accounts
      : RoutePaths.engineerHome;
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final path = state.uri.path;

      // Splash is only a one-frame first-run compatibility handoff. Returning
      // users and signed-out users start directly at their useful destination.
      if (path == RoutePaths.splash && !isOnboarded) return null;

      // Hard global gates block everything (incl. login) until cleared.
      if (gate == AppGate.updateRequired) {
        return path == RoutePaths.updateRequired
            ? null
            : RoutePaths.updateRequired;
      }
      if (gate == AppGate.maintenance) {
        return path == RoutePaths.maintenance ? null : RoutePaths.maintenance;
      }
      // Gate cleared but still sitting on a gate screen → move on.
      if (path == RoutePaths.updateRequired || path == RoutePaths.maintenance) {
        return RoutePaths.engineerHome;
      }

      // Force onboarding first (language selection).
      if (!isOnboarded) {
        return path == RoutePaths.languageSelection ? null : RoutePaths.splash;
      }

      // Onboarded but not logged in -> login only.
      if (!isLoggedIn) {
        return path == RoutePaths.login ? null : RoutePaths.login;
      }

      // Evicted mid-session: the account was deactivated, demoted-then-removed,
      // or a re-seed dropped the id → straight back to login (no stale session).
      if (user == null || !user.active) {
        return path == RoutePaths.login ? null : RoutePaths.login;
      }

      // Logged-in users shouldn't sit on onboarding/login. Accountant lands
      // directly in the normalized, capability-guarded Accounts workspace.
      if (path == RoutePaths.languageSelection || path == RoutePaths.login) {
        if (yorksV1AccountsEnabled && yorksV1Role == YorksV1Role.accountant) {
          return RoutePaths.yorksV1Accounts;
        }
        return RoutePaths.engineerHome;
      }

      // Force a password change for admin-created / reset accounts before they
      // can use anything else. (user is non-null + active past the guard above.)
      if (user.mustChangePassword) {
        return path == RoutePaths.changePassword
            ? null
            : RoutePaths.changePassword;
      }
      if (path == RoutePaths.changePassword) {
        return RoutePaths.engineerHome; // nothing to change → leave
      }

      // An already-authenticated Accountant may revisit the root route from a
      // bookmark or a pre-rollout browser session. Once Accounts is enabled,
      // send that stale landing route through the same protected portfolio
      // guard instead of leaving it on the historical rollout-locked page.
      if (path == RoutePaths.engineerHome &&
          yorksV1AccountsEnabled &&
          yorksV1Role == YorksV1Role.accountant) {
        final allowed = _hybridRouteAllows(
          yorksV1PermissionResolver,
          YorksV1CapabilityKeys.viewProjectAccounts,
          legacyAllowed: false,
          organizationSummary: true,
        );
        if (allowed == true) return RoutePaths.yorksV1Accounts;
      }

      // This is an experience-level guard only; the normalized V1 RPC/RLS
      // remains authoritative. It ensures a Procurement deep-link never
      // builds the project-creation form once the Rev 2.0/R35 route is on.
      if (yorksV1ProjectsEnabled && path == RoutePaths.engineerCreateProject) {
        final structurallyEligible = yorksV1Role?.canCreateProject ?? false;
        if (!structurallyEligible) return _yorksV1ProjectFallbackPath();
        final capabilityAllowed = _hybridRouteAllows(
          yorksV1PermissionResolver,
          YorksV1CapabilityKeys.projectsCreate,
          legacyAllowed: structurallyEligible,
        );
        if (capabilityAllowed == false) {
          return _yorksV1ProjectFallbackPath();
        }
        if (capabilityAllowed == null) return null;
      }

      if (_isYorksV1AccountsPath(path) && !yorksV1AccountsEnabled) {
        return _yorksV1ProjectFallbackPath();
      }
      if (_isYorksV1WorkforcePath(path) && !yorksV1WorkforceEnabled) {
        return _yorksV1ProjectFallbackPath();
      }
      if (_isYorksV1AnalyticsPath(path) && !yorksV1AnalyticsEnabled) {
        return _yorksV1ProjectFallbackPath();
      }
      if (path == RoutePaths.finance && yorksV1AccountsEnabled) {
        return yorksV1Role != null && _canOpenAccountsPortfolio(yorksV1Role)
            ? RoutePaths.yorksV1Accounts
            : _yorksV1ProjectFallbackPath();
      }
      if (yorksV1AccountsEnabled &&
          yorksV1Role == YorksV1Role.procurement &&
          path.endsWith('/accounts')) {
        final projectId = _yorksV1ProjectIdFromPath(path);
        if (projectId != null) {
          return RoutePaths.yorksV1ProjectAccountsSupplierBillsPath(projectId);
        }
      }
      if (path.startsWith('/yorks/projects/') &&
          !_isYorksV1AccountsPath(path) &&
          !yorksV1BoqEnabled) {
        return _yorksV1ProjectFallbackPath();
      }
      if (path.startsWith('/yorks/projects/') &&
          path.endsWith('/documents') &&
          !yorksV1DocumentsEnabled) {
        return _yorksV1ProjectFallbackPath();
      }

      if (path.startsWith('/yorks/material-requests') &&
          !yorksV1RequestsEnabled) {
        return _yorksV1ProjectFallbackPath();
      }
      if ((path == RoutePaths.yorksV1CompanyMaterialRequests ||
              path.startsWith(
                '${RoutePaths.yorksV1CompanyMaterialRequests}/',
              )) &&
          !yorksV1CompanyMaterialRequestsEnabled) {
        return RoutePaths.yorksV1MaterialRequests;
      }
      if (path.startsWith(RoutePaths.yorksV1TeamChat) &&
          !yorksV1TeamChatEnabled) {
        return _yorksV1ProjectFallbackPath();
      }
      if (path.startsWith('/yorks/material-requests/') &&
          path.endsWith('/arrangement') &&
          !yorksV1ArrangementEnabled) {
        return _yorksV1ProjectFallbackPath();
      }
      if ((path == RoutePaths.yorksV1Inventory ||
              path == RoutePaths.yorksV1Dispatches ||
              (path.startsWith('/yorks/material-requests/') &&
                  path.endsWith('/logistics'))) &&
          !yorksV1LogisticsEnabled) {
        return _yorksV1ProjectFallbackPath();
      }
      if ((path == RoutePaths.yorksV1Returns ||
              (path.startsWith('/yorks/material-requests/') &&
                  path.endsWith('/returns'))) &&
          !yorksV1ReturnsDocumentsEnabled) {
        return _yorksV1ProjectFallbackPath();
      }
      if (path.startsWith('/yorks/material-requests/draft/')) {
        final structurallyEligible =
            yorksV1Role?.canCreateMaterialRequest ?? false;
        if (!structurallyEligible) return _yorksV1ProjectFallbackPath();
        final capabilityAllowed = _hybridRouteAllows(
          yorksV1PermissionResolver,
          YorksV1CapabilityKeys.materialRequestsCreate,
          legacyAllowed: structurallyEligible,
          projectId: state.uri.queryParameters['project_id'],
          organizationSummary: (state.uri.queryParameters['project_id'] ?? '')
              .trim()
              .isEmpty,
        );
        if (capabilityAllowed == false) {
          return _yorksV1ProjectFallbackPath();
        }
        if (capabilityAllowed == null) return null;
      }
      // The retained local Access & Roles matrix is not a V1 authority. Keep
      // its route available only to the explicit legacy rollout lane.
      if (yorksV1ProjectsEnabled && path == RoutePaths.accessRoles) {
        return RoutePaths.users;
      }
      // Scoped-access deep links fail closed until a current protected
      // snapshot authoritatively grants permission inspection. The target
      // workspace RPC/RLS repeats this check; this guard prevents the page
      // from painting while that confirmation is absent or stale.
      if (path.startsWith('${RoutePaths.users}/')) {
        final capabilityAllowed = _hybridRouteAllows(
          yorksV1PermissionResolver,
          YorksV1CapabilityKeys.permissionsView,
          legacyAllowed: yorksV1Role?.canConfigureUsers ?? role.isAdmin,
        );
        if (capabilityAllowed == false) return RoutePaths.users;
        if (capabilityAllowed == null) return null;
      }
      final yorksV1RouteAllowed = _isYorksV1RouteAllowedForRole(
        state.uri,
        yorksV1Role,
        yorksV1PermissionResolver,
      );
      if (yorksV1RouteAllowed == false) {
        return _yorksV1ProjectFallbackPath();
      }
      if (yorksV1RouteAllowed == null) return null;

      // Batch 2 has the normalized creation flow but not the V1 portfolio,
      // workspace, BOQ/plan or request projection. Once V1 Projects is
      // enabled, no role may reach the retained generic Project/Request store
      // through an old route. This prevents V1 records from being handled by
      // a parallel legacy authority.
      if (yorksV1ProjectsEnabled && _isLegacyProjectOrRequestRoute(path)) {
        return _yorksV1ProjectFallbackPath();
      }

      // Retire the old hub locations.
      if (path == '/admin') return RoutePaths.engineerHome;
      if (path == RoutePaths.adminPanel) {
        return role.isAdmin ? RoutePaths.more : RoutePaths.engineerHome;
      }

      // Role-based access guard for module routes → Home if not allowed.
      final perms =
          rolePermissions?.call() ?? RolePermissions.fromRoleDefaults();
      final roleAllowed = _isAllowedForRole(
        path,
        role,
        user,
        perms,
        yorksV1Role,
        yorksV1PermissionResolver,
      );
      if (roleAllowed == false) {
        return RoutePaths.engineerHome;
      }
      if (roleAllowed == null) return null;

      return null;
    },
    routes: [
      // ─── Onboarding & Auth (outside the shell) ────────────
      GoRoute(
        path: RoutePaths.splash,
        pageBuilder: (context, state) =>
            _fade(state.pageKey, const SplashScreen(), ms: 400),
      ),
      GoRoute(
        path: RoutePaths.languageSelection,
        pageBuilder: (context, state) =>
            _fade(state.pageKey, const LanguageSelectionScreen(), ms: 500),
      ),
      GoRoute(
        path: RoutePaths.changePassword,
        pageBuilder: (context, state) =>
            _fade(state.pageKey, const ChangePasswordScreen(), ms: 300),
      ),
      GoRoute(
        path: RoutePaths.updateRequired,
        pageBuilder: (context, state) =>
            _fade(state.pageKey, const UpdateRequiredScreen(), ms: 300),
      ),
      GoRoute(
        path: RoutePaths.maintenance,
        pageBuilder: (context, state) =>
            _fade(state.pageKey, const MaintenanceScreen(), ms: 300),
      ),
      GoRoute(
        path: RoutePaths.login,
        pageBuilder: (context, state) =>
            _fade(state.pageKey, const LoginScreen(), ms: 350),
      ),

      // ─── Role shell ───────────────────────────────────────
      // Engineers keep their original 4-tab mobile shell (Home · Browse ·
      // Projects · Profile + New Request); office roles get the role-aware
      // hub shell (Home · Materials · Rentals · People · More).
      if (useEngineerShell)
        // Engineer: 4 state-preserving branches. Non-tab flows (New Request,
        // Create Project) are nested so the bottom bar stays visible AND their
        // typed input survives tab switches (IndexedStack keeps branches alive).
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              yorksV1ProjectsEnabled && yorksV1Role != null
              ? YorksV1WorkspaceShell(child: navigationShell)
              : EngineerShellScreen(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: RoutePaths.engineerHome,
                  pageBuilder: (context, state) =>
                      const NoTransitionPage(child: EngineerHomeScreen()),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: RoutePaths.engineerBrowse,
                  pageBuilder: (context, state) =>
                      const NoTransitionPage(child: EngineerBrowseScreen()),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: RoutePaths.engineerProjects,
                  pageBuilder: (context, state) =>
                      const NoTransitionPage(child: EngineerProjectsScreen()),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: RoutePaths.engineerProfile,
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: _DeferredEngineerProfileScreen(),
                  ),
                ),
              ],
            ),
            // 5th branch (no visible tab) — New Request lives INSIDE the shell so
            // the bottom bar stays visible and the in-progress draft survives tab
            // switches (IndexedStack keeps it mounted). Reached via the centre
            // "+" FAB / rail button (goBranch), not a tab.
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: RoutePaths.engineerNewRequest,
                  pageBuilder: (context, state) =>
                      const NoTransitionPage(child: EngineerNewRequestScreen()),
                ),
              ],
            ),
          ],
        )
      else
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              AppShell(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: RoutePaths.engineerHome,
                  pageBuilder: (context, state) =>
                      const NoTransitionPage(child: DashboardScreen()),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: RoutePaths.materials,
                  pageBuilder: (context, state) =>
                      const NoTransitionPage(child: MaterialsHubScreen()),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: RoutePaths.rentals,
                  pageBuilder: (context, state) =>
                      const NoTransitionPage(child: RentalsDashboardScreen()),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: RoutePaths.people,
                  pageBuilder: (context, state) =>
                      const NoTransitionPage(child: PeopleDashboardScreen()),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: RoutePaths.more,
                  pageBuilder: (context, state) =>
                      const NoTransitionPage(child: MoreHubScreen()),
                ),
              ],
            ),
          ],
        ),

      // Office roles reach the account/settings screen via the Home avatar menu
      // (engineers have it as their Profile tab). Same screen for consistency.
      if (!useEngineerShell)
        GoRoute(
          path: RoutePaths.engineerProfile,
          pageBuilder: (context, state) =>
              yorksV1ProjectsEnabled && yorksV1Role != null
              ? _yorksV1Slide(
                  state.pageKey,
                  const _DeferredEngineerProfileScreen(),
                )
              : _framed(state.pageKey, const _DeferredEngineerProfileScreen()),
        ),
      if (!useEngineerShell)
        GoRoute(
          path: RoutePaths.engineerBrowse,
          pageBuilder: (context, state) =>
              _framed(state.pageKey, const EngineerBrowseScreen()),
        ),

      // ─── Engineer create-flows (full-screen over the shell) ─────────
      // Create Project overlays the shell with its own back; New Request now
      // lives INSIDE the shell as a branch (see above), so it's not here.
      GoRoute(
        path: RoutePaths.engineerCreateProject,
        pageBuilder: (context, state) => yorksV1ProjectsEnabled
            ? _yorksV1Slide(state.pageKey, const EngineerCreateProjectScreen())
            : _slide(state.pageKey, const EngineerCreateProjectScreen()),
      ),
      GoRoute(
        path: RoutePaths.projectWorkspace,
        pageBuilder: (context, state) => _slide(
          state.pageKey,
          ProjectWorkspaceScreen(projectId: state.pathParameters['id'] ?? ''),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1Projects,
        pageBuilder: (context, state) =>
            _yorksV1Slide(state.pageKey, const YorksV1ProjectsScreen()),
      ),
      if (yorksV1AnalyticsEnabled)
        GoRoute(
          path: RoutePaths.yorksV1Analytics,
          pageBuilder: (context, state) =>
              _yorksV1Slide(state.pageKey, const CompanyAnalyticsScreen()),
        ),
      GoRoute(
        path: RoutePaths.yorksV1Accounts,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          const YorksAccountsPortfolioScreen(controlCentre: true),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1AccountsProjects,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          const YorksAccountsPortfolioScreen(controlCentre: false),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1AccountsBillingProgress,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          const YorksAccountsPortfolioScreen(billingProgress: true),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1AccountsClaims,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          const YorksAccountsOfficeScreen(
            section: YorksAccountsOfficeSection.claims,
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1AccountsClientPayments,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          const YorksAccountsOfficeScreen(
            section: YorksAccountsOfficeSection.clientPayments,
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1AccountsSupplierBills,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          const YorksAccountsOfficeScreen(
            section: YorksAccountsOfficeSection.supplierBills,
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1AccountsDueSchedule,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          const YorksAccountsOfficeScreen(
            section: YorksAccountsOfficeSection.dueSchedule,
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1AccountsDocuments,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          const YorksAccountsOfficeScreen(
            section: YorksAccountsOfficeSection.documents,
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1AccountsReports,
        pageBuilder: (context, state) =>
            _yorksV1Slide(state.pageKey, const YorksAccountsReportsScreen()),
      ),
      GoRoute(
        path: RoutePaths.yorksV1AccountsActivity,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          const YorksAccountsOfficeScreen(
            section: YorksAccountsOfficeSection.activity,
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1ProjectAccounts,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          YorksProjectAccountsScreen(
            projectId: state.pathParameters['projectId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1ProjectAccountsOverview,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          YorksProjectAccountsScreen(
            projectId: state.pathParameters['projectId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1ProjectAccountsBilling,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          YorksProjectAccountsScreen(
            projectId: state.pathParameters['projectId'] ?? '',
            initialTab: YorksProjectAccountsTab.billing,
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1ProjectAccountsInvoices,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          YorksProjectAccountsScreen(
            projectId: state.pathParameters['projectId'] ?? '',
            initialTab: YorksProjectAccountsTab.invoices,
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1ProjectAccountsReceiptsPdc,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          YorksProjectAccountsScreen(
            projectId: state.pathParameters['projectId'] ?? '',
            initialTab: YorksProjectAccountsTab.receiptsPdc,
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1ProjectAccountsSupplierBills,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          YorksProjectAccountsScreen(
            projectId: state.pathParameters['projectId'] ?? '',
            initialTab: YorksProjectAccountsTab.supplierBills,
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1ProjectAccountsDocuments,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          YorksProjectAccountsScreen(
            projectId: state.pathParameters['projectId'] ?? '',
            initialTab: YorksProjectAccountsTab.documents,
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1ProjectAccountsActivity,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          YorksProjectAccountsScreen(
            projectId: state.pathParameters['projectId'] ?? '',
            initialTab: YorksProjectAccountsTab.activity,
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1BoqGroups,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          YorksV1ProjectWorkspaceScreen(
            projectId: state.pathParameters['projectId'] ?? '',
            initialTab: YorksV1ProjectWorkspaceTab.boq,
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1ProjectEdit,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          YorksV1ProjectEditFlowScreen(
            projectId: state.pathParameters['projectId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1Project,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          YorksV1ProjectWorkspaceScreen(
            projectId: state.pathParameters['projectId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1BoqWorksheet,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          YorksV1BoqWorksheetScreen(
            projectId: state.pathParameters['projectId'] ?? '',
            groupId: state.pathParameters['groupId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1ProjectDocuments,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          YorksV1DocumentsScreen(
            projectId: state.pathParameters['projectId'] ?? '',
            focusEntityType: state.uri.queryParameters['entity_type'],
            focusEntityId: state.uri.queryParameters['entity_id'],
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1MaterialRequests,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          YorksV1MaterialRequestsScreen(
            projectId: state.uri.queryParameters['project_id'],
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1MaterialRequestDraft,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          YorksV1MaterialRequestDraftScreen(
            draftId: state.pathParameters['draftId'] ?? '',
            entryMode: YorksV1MaterialRequestDraftEntryMode.fromWireValue(
              state.uri.queryParameters['entry_mode'],
            ),
            boqGroupId: state.uri.queryParameters['boq_group_id'],
            projectId: state.uri.queryParameters['project_id'],
            boqVersion: int.tryParse(
              state.uri.queryParameters['boq_version'] ?? '',
            ),
          ),
        ),
      ),
      if (yorksV1CompanyMaterialRequestsEnabled)
        GoRoute(
          path: RoutePaths.yorksV1CompanyMaterialRequests,
          pageBuilder: (context, state) => _yorksV1Slide(
            state.pageKey,
            const _DeferredCompanyMaterialRequestScreen(inbox: true),
          ),
        ),
      if (yorksV1CompanyMaterialRequestsEnabled)
        GoRoute(
          path: RoutePaths.yorksV1CompanyMaterialRequestNew,
          pageBuilder: (context, state) => _yorksV1Slide(
            state.pageKey,
            const _DeferredCompanyMaterialRequestScreen(),
          ),
        ),
      if (yorksV1CompanyMaterialRequestsEnabled)
        GoRoute(
          path: RoutePaths.yorksV1CompanyMaterialRequest,
          pageBuilder: (context, state) => _yorksV1Slide(
            state.pageKey,
            _DeferredCompanyMaterialRequestScreen(
              requestId: state.pathParameters['requestId'] ?? '',
            ),
          ),
        ),
      GoRoute(
        path: RoutePaths.yorksV1MaterialRequestArrangement,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          YorksV1ArrangementScreen(
            requestId: state.pathParameters['requestId'] ?? '',
            onCompleted: () => context.pop(),
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1MaterialRequestLogistics,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          YorksV1LogisticsScreen(
            requestId: state.pathParameters['requestId'] ?? '',
            focusReceiptReview:
                state.uri.queryParameters['focus'] == 'receipt_review',
            focusedDispatchId: state.uri.queryParameters['dispatch_id'],
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1MaterialRequestReturnsDocuments,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          YorksV1ReturnsDocumentsScreen(
            requestId: state.pathParameters['requestId'] ?? '',
            focusDeliveryOrder:
                state.uri.queryParameters['focus'] == 'delivery_order',
            focusedDispatchId: state.uri.queryParameters['dispatch_id'],
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1Inventory,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          YorksV1InventoryScreen(initialTab: state.uri.queryParameters['tab']),
        ),
      ),
      if (yorksV1InventorySuppliersEnabled)
        GoRoute(
          path: RoutePaths.yorksV1InventorySuppliers,
          pageBuilder: (context, state) => _yorksV1Slide(
            state.pageKey,
            const YorksV1InventorySupplierDirectoryScreen(),
          ),
        ),
      if (yorksV1InventorySuppliersEnabled)
        GoRoute(
          path: RoutePaths.yorksV1InventorySupplier,
          pageBuilder: (context, state) => _yorksV1Slide(
            state.pageKey,
            YorksV1InventorySupplierFolderScreen(
              supplierId: state.pathParameters['supplierId'] ?? '',
            ),
          ),
        ),
      if (yorksV1InventorySuppliersEnabled)
        GoRoute(
          path: RoutePaths.yorksV1InventoryImport,
          pageBuilder: (context, state) => _yorksV1Slide(
            state.pageKey,
            YorksV1InventoryImportScreen(
              preselectedSupplierId: state.uri.queryParameters['supplierId'],
              onCancel: () {
                if (context.canPop()) {
                  context.pop();
                  return;
                }
                context.go(RoutePaths.yorksV1InventorySuppliers);
              },
              onReturnToSuppliers: () =>
                  context.go(RoutePaths.yorksV1InventorySuppliers),
              onOpenSupplier: (supplierId) => context.go(
                RoutePaths.yorksV1InventorySupplierPath(supplierId),
              ),
            ),
          ),
        ),
      GoRoute(
        path: RoutePaths.yorksV1Configuration,
        pageBuilder: (context, state) =>
            _yorksV1Slide(state.pageKey, const YorksV1ConfigurationScreen()),
      ),
      if (yorksV1WorkforceEnabled)
        GoRoute(
          path: RoutePaths.yorksV1Workforce,
          pageBuilder: (context, state) => _yorksV1Slide(
            state.pageKey,
            const YorksWorkforceOverviewScreen(),
          ),
        ),
      if (yorksV1WorkforceEnabled)
        GoRoute(
          path: RoutePaths.yorksV1WorkforceAdministration,
          pageBuilder: (context, state) => _yorksV1Slide(
            state.pageKey,
            const YorksWorkforceAdministrationScreen(),
          ),
        ),
      if (yorksV1WorkforceEnabled)
        GoRoute(
          path: RoutePaths.yorksV1WorkforceAttendance,
          pageBuilder: (context, state) => _yorksV1Slide(
            state.pageKey,
            const YorksWorkforceDailyAttendanceScreen(),
          ),
        ),
      if (yorksV1WorkforceEnabled)
        GoRoute(
          path: RoutePaths.yorksV1WorkforceTimesheets,
          pageBuilder: (context, state) => _yorksV1Slide(
            state.pageKey,
            const YorksWorkforceTimesheetsScreen(),
          ),
        ),
      GoRoute(
        path: RoutePaths.yorksV1TeamChat,
        pageBuilder: (context, state) =>
            _yorksV1Slide(state.pageKey, const YorksV1TeamChatScreen()),
      ),
      GoRoute(
        path: RoutePaths.yorksV1TeamChatConversation,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          YorksV1TeamChatScreen(
            initialConversationId: state.pathParameters['conversationId'],
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1Dispatches,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          const YorksV1WorkflowQueueScreen(
            kind: YorksV1WorkflowQueueKind.dispatches,
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1Returns,
        pageBuilder: (context, state) =>
            _yorksV1Slide(state.pageKey, const YorksV1MaterialReturnsScreen()),
      ),
      GoRoute(
        path: RoutePaths.yorksV1MaterialReturnNew,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          YorksV1MaterialReturnEditorScreen(
            initialProjectId: state.uri.queryParameters['project_id'],
            returnId: state.uri.queryParameters['return_id'],
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1MaterialReturn,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          YorksV1MaterialReturnDetailScreen(
            returnId: state.pathParameters['returnId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1DuctSizer,
        pageBuilder: (context, state) =>
            _yorksV1Slide(state.pageKey, const YorksV1DuctSizerScreen()),
      ),
      GoRoute(
        path: RoutePaths.yorksV1EspCalculator,
        pageBuilder: (context, state) =>
            _yorksV1Slide(state.pageKey, const YorksV1EspCalculatorScreen()),
      ),
      GoRoute(
        path: RoutePaths.yorksV1MaterialRequest,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          YorksV1MaterialRequestDetailScreen(
            requestId: state.pathParameters['requestId'] ?? '',
            commentId: state.uri.queryParameters['comment'],
          ),
        ),
      ),
      // Standalone projects view (reached from the profile quick links) — the
      // tab screen has no Scaffold of its own, so frame it for a back button.
      GoRoute(
        path: RoutePaths.engineerProjectsView,
        pageBuilder: (context, state) =>
            _framed(state.pageKey, const EngineerProjectsScreen()),
      ),

      // ─── Shared detail/workflow screens (full-screen, all roles) ─────
      // Material picker — pushed ON TOP of the New Request screen so the
      // engineer adds inventory + custom items, then returns to the request.
      GoRoute(
        path: RoutePaths.engineerPickMaterials,
        pageBuilder: (context, state) =>
            _slide(state.pageKey, const MaterialPickerScreen()),
      ),
      GoRoute(
        path: RoutePaths.requestDetail,
        pageBuilder: (context, state) => _slide(
          state.pageKey,
          RequestDetailScreen(requestId: state.pathParameters['id'] ?? ''),
        ),
      ),
      GoRoute(
        path: RoutePaths.requests,
        pageBuilder: (context, state) => _slide(
          state.pageKey,
          RequestsListScreen(projectName: state.extra as String?),
        ),
      ),
      GoRoute(
        path: RoutePaths.planReview,
        pageBuilder: (context, state) => _slide(
          state.pageKey,
          PlanReviewScreen(projectId: state.pathParameters['id'] ?? ''),
        ),
      ),
      GoRoute(
        path: RoutePaths.planBuild,
        pageBuilder: (context, state) => _slide(
          state.pageKey,
          PlanBuildScreen(projectId: state.pathParameters['id'] ?? ''),
        ),
      ),
      GoRoute(
        path: RoutePaths.planDiff,
        pageBuilder: (context, state) => _slide(
          state.pageKey,
          PlanDiffScreen(projectId: state.pathParameters['id'] ?? ''),
        ),
      ),
      GoRoute(
        path: RoutePaths.confirmReceipt,
        pageBuilder: (context, state) => _slide(
          state.pageKey,
          ConfirmReceiptScreen(requestId: state.pathParameters['id'] ?? ''),
        ),
      ),
      GoRoute(
        path: RoutePaths.returnStore,
        pageBuilder: (context, state) => _slide(
          state.pageKey,
          ReturnScreen(initialProjectName: state.extra as String?),
        ),
      ),
      GoRoute(
        path: RoutePaths.employeeDetail,
        pageBuilder: (context, state) =>
            _slide(state.pageKey, const EmployeeDetailScreen()),
      ),

      // ─── Office / admin screens (full-screen over the shell) ─
      GoRoute(
        path: RoutePaths.inventory,
        pageBuilder: (context, state) =>
            _framed(state.pageKey, const InventoryScreen()),
      ),
      GoRoute(
        path: RoutePaths.materialMasters,
        pageBuilder: (context, state) =>
            _slide(state.pageKey, const MaterialMastersScreen()),
      ),
      GoRoute(
        path: RoutePaths.stockHistory,
        pageBuilder: (context, state) =>
            _slide(state.pageKey, const StockHistoryScreen()),
      ),
      GoRoute(
        path: RoutePaths.transactions,
        pageBuilder: (context, state) =>
            _framed(state.pageKey, const TransactionsScreen()),
      ),
      GoRoute(
        path: RoutePaths.goodsReceipt,
        pageBuilder: (context, state) =>
            _slide(state.pageKey, const GoodsReceiptScreen()),
      ),
      GoRoute(
        path: RoutePaths.finance,
        pageBuilder: (context, state) =>
            _slide(state.pageKey, const FinanceScreen()),
      ),
      GoRoute(
        path: RoutePaths.adminProjects,
        pageBuilder: (context, state) =>
            _slide(state.pageKey, const AdminProjectsScreen()),
      ),
      GoRoute(
        path: RoutePaths.adminRequests,
        pageBuilder: (context, state) =>
            _slide(state.pageKey, const AdminRequestsScreen()),
      ),
      GoRoute(
        path: RoutePaths.users,
        pageBuilder: (context, state) =>
            _yorksV1Slide(state.pageKey, const UserManagementScreen()),
      ),
      GoRoute(
        path: RoutePaths.yorksV1UserAccess,
        pageBuilder: (context, state) => _yorksV1Slide(
          state.pageKey,
          YorksV1UserAccessScreen(
            targetAppUserId: state.pathParameters['appUserId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.accessRoles,
        pageBuilder: (context, state) =>
            _slide(state.pageKey, const AccessRolesScreen()),
      ),
      GoRoute(
        path: RoutePaths.dataSync,
        pageBuilder: (context, state) =>
            _slide(state.pageKey, const DataSyncScreen()),
      ),
      // ─── Leave management ───────────────────────────────────────
      GoRoute(
        path: RoutePaths.myLeave,
        pageBuilder: (context, state) =>
            _slide(state.pageKey, const MyLeaveScreen()),
      ),
      GoRoute(
        path: RoutePaths.leaveRequests,
        pageBuilder: (context, state) =>
            _slide(state.pageKey, const LeaveRequestsScreen()),
      ),
      GoRoute(
        path: RoutePaths.procurement,
        pageBuilder: (context, state) =>
            _slide(state.pageKey, const ProcurementWorkspaceScreen()),
      ),
      GoRoute(
        path: RoutePaths.planReviewProcurement,
        pageBuilder: (context, state) => _slide(
          state.pageKey,
          ProcurementPlanReviewScreen(
            projectId: state.pathParameters['id'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.dispatch,
        pageBuilder: (context, state) => _slide(
          state.pageKey,
          ProcurementDispatchScreen(
            requestId: state.pathParameters['id'] ?? '',
          ),
        ),
      ),

      // ─── Rentals / People details (full-screen) ───────────
      GoRoute(
        path: RoutePaths.rentalUnit,
        pageBuilder: (context, state) => _slide(
          state.pageKey,
          RentalUnitDetailScreen(unitId: state.pathParameters['id'] ?? ''),
        ),
      ),
      GoRoute(
        path: RoutePaths.employeeProfile,
        pageBuilder: (context, state) => _slide(
          state.pageKey,
          EmployeeProfileScreen(employeeId: state.pathParameters['id'] ?? ''),
        ),
      ),

      // ─── Shared (full-screen) ─────────────────────────────
      GoRoute(
        path: RoutePaths.about,
        pageBuilder: (context, state) =>
            _slide(state.pageKey, const AboutScreen()),
      ),
      GoRoute(
        path: RoutePaths.activityLog,
        pageBuilder: (context, state) =>
            _yorksV1Slide(state.pageKey, const ActivityLogScreen()),
      ),
      GoRoute(
        path: RoutePaths.yorksV1MobileMore,
        pageBuilder: (context, state) =>
            _yorksV1Slide(state.pageKey, const YorksV1MobileMoreScreen()),
      ),
      GoRoute(
        path: RoutePaths.notifications,
        pageBuilder: (context, state) => _slide(
          state.pageKey,
          const NotificationsScreen(),
          begin: const Offset(0, 1),
        ),
      ),
      GoRoute(
        path: RoutePaths.notificationPreferences,
        pageBuilder: (context, state) =>
            yorksV1ProjectsEnabled && yorksV1Role != null
            ? _yorksV1Slide(
                state.pageKey,
                const NotificationPreferencesScreen(),
              )
            : _slide(state.pageKey, const NotificationPreferencesScreen()),
      ),
      GoRoute(
        path: RoutePaths.privacyPolicy,
        pageBuilder: (context, state) =>
            _slide(state.pageKey, const PrivacyPolicyScreen()),
      ),
      GoRoute(
        path: RoutePaths.termsOfService,
        pageBuilder: (context, state) =>
            _slide(state.pageKey, const TermsOfServiceScreen()),
      ),
      if (kDebugMode)
        GoRoute(
          path: RoutePaths.materialLineGridDemo,
          pageBuilder: (context, state) =>
              _slide(state.pageKey, const MaterialLineGridDemoScreen()),
        ),
    ],
  );
}

/// Keeps the rich My Yorks workspace out of the initial web download. Native
/// builds resolve this deferred library immediately; web loads the same
/// reviewed screen only when the person opens Profile.
class _DeferredEngineerProfileScreen extends StatefulWidget {
  const _DeferredEngineerProfileScreen();

  @override
  State<_DeferredEngineerProfileScreen> createState() =>
      _DeferredEngineerProfileScreenState();
}

class _DeferredEngineerProfileScreenState
    extends State<_DeferredEngineerProfileScreen> {
  static Future<void>? _sharedLoad;
  late Future<void> _load;

  @override
  void initState() {
    super.initState();
    _load = _sharedLoad ??= engineer_profile.loadLibrary();
  }

  void _retry() {
    setState(() {
      _load = _sharedLoad = engineer_profile.loadLibrary();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError) {
          return engineer_profile.EngineerProfileScreen();
        }
        if (snapshot.hasError) {
          return Center(
            child: IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: MaterialLocalizations.of(
                context,
              ).refreshIndicatorSemanticLabel,
              onPressed: _retry,
            ),
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}

/// Loads the Company Request editor only after its feature-gated route is
/// opened. The feature remains server-authorized; this keeps a disabled or
/// unopened workflow out of the initial web download without changing its
/// route or lifecycle behavior.
class _DeferredCompanyMaterialRequestScreen extends StatefulWidget {
  const _DeferredCompanyMaterialRequestScreen({
    this.requestId,
    this.inbox = false,
  });

  final String? requestId;
  final bool inbox;

  @override
  State<_DeferredCompanyMaterialRequestScreen> createState() =>
      _DeferredCompanyMaterialRequestScreenState();
}

class _DeferredCompanyMaterialRequestScreenState
    extends State<_DeferredCompanyMaterialRequestScreen> {
  static Future<void>? _sharedLoad;
  late Future<void> _load;

  @override
  void initState() {
    super.initState();
    _load = _sharedLoad ??= company_material_request.loadLibrary();
  }

  void _retry() {
    setState(() {
      _load = _sharedLoad = company_material_request.loadLibrary();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError) {
          if (widget.inbox) {
            return company_material_request.YorksV1CompanyMaterialRequestApprovalInboxScreen();
          }
          if (widget.requestId != null) {
            return company_material_request.YorksV1CompanyMaterialRequestApprovalScreen(
              requestId: widget.requestId!,
            );
          }
          return company_material_request.YorksV1CompanyMaterialRequestScreen();
        }
        if (snapshot.hasError) {
          return Center(
            child: IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: MaterialLocalizations.of(
                context,
              ).refreshIndicatorSemanticLabel,
              onPressed: _retry,
            ),
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}

/// The only Batch 2 V1 project landing that is registered for the current
/// shell. A normalized office portfolio arrives with the later workspace/read
/// slice; returning Home now is safer than invoking an incompatible legacy
/// project route or producing an unmatched GoRouter location.
String _yorksV1ProjectFallbackPath() => RoutePaths.engineerHome;

/// Legacy project/plan/request routes that have no normalized V1 projection
/// in Batch 2. `/projects/new` is deliberately excluded because it resolves
/// to the new five-stage creation flow before this predicate is reached.
bool _isLegacyProjectOrRequestRoute(String path) {
  if (path == RoutePaths.engineerCreateProject) return false;

  if (path == RoutePaths.engineerProjects ||
      path == RoutePaths.engineerProjectsView ||
      path == RoutePaths.adminProjects ||
      path == RoutePaths.procurement ||
      path == RoutePaths.finance ||
      path == RoutePaths.engineerNewRequest ||
      path == RoutePaths.engineerPickMaterials ||
      path == RoutePaths.requests ||
      path == RoutePaths.adminRequests ||
      path == RoutePaths.returnStore) {
    return true;
  }

  return path.startsWith('${RoutePaths.engineerProjects}/') ||
      path.startsWith('/plan/') ||
      path.startsWith('/plan-build/') ||
      path.startsWith('/plan-diff/') ||
      path.startsWith('/admin/plan-review/') ||
      path.startsWith('/request/') ||
      path.startsWith('/receipt/') ||
      path.startsWith('/admin/dispatch/');
}

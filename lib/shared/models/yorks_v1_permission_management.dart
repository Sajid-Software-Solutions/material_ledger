import 'yorks_v1_role.dart';

abstract final class YorksV1PermissionSchema {
  static const current = 1;
}

/// Target-aware controls for protected User Management commands.
///
/// The server computes the actor's exact role ceiling and independently checks
/// each target action. The client deliberately has no hierarchy fallback: a
/// missing, malformed or failed projection leaves every connected control
/// unavailable.
class YorksV1UserAdminOptions {
  YorksV1UserAdminOptions({
    required this.schemaVersion,
    required this.targetAppUserId,
    required Iterable<YorksV1Role> assignableExactRoles,
    required this.canAssignRole,
    required this.canResetPassword,
    required this.canManageActivation,
  }) : assignableExactRoles = List.unmodifiable(assignableExactRoles) {
    if (schemaVersion != YorksV1PermissionSchema.current) {
      throw const FormatException('Unsupported user admin options schema');
    }
    if (this.assignableExactRoles.toSet().length !=
        this.assignableExactRoles.length) {
      throw const FormatException('Duplicate assignable exact role');
    }
    if (canAssignRole != this.assignableExactRoles.isNotEmpty) {
      throw const FormatException('Inconsistent role assignment options');
    }
  }

  final int schemaVersion;
  final String? targetAppUserId;
  final List<YorksV1Role> assignableExactRoles;
  final bool canAssignRole;
  final bool canResetPassword;
  final bool canManageActivation;

  bool allowsRole(YorksV1Role role) =>
      canAssignRole && assignableExactRoles.contains(role);

  factory YorksV1UserAdminOptions.fromRpcJson(Map<String, dynamic> json) {
    final rawRoles = json['assignable_exact_roles'];
    if (rawRoles is! List) {
      throw const FormatException('Missing assignable exact roles');
    }
    final roles = <YorksV1Role>[];
    for (final rawRole in rawRoles) {
      final role = YorksV1Role.fromServerClaim(rawRole);
      if (role == null) {
        throw const FormatException('Invalid assignable exact role');
      }
      roles.add(role);
    }
    return YorksV1UserAdminOptions(
      schemaVersion: _integer(json['schema_version']),
      targetAppUserId: _nullableText(json['target_app_user_id']),
      assignableExactRoles: roles,
      canAssignRole: _boolean(json['can_assign_role']),
      canResetPassword: _boolean(json['can_reset_password']),
      canManageActivation: _boolean(json['can_manage_activation']),
    );
  }
}

/// Client-recognized capability keys seeded by the protected catalogue.
///
/// Server responses may include a syntactically valid future key so an older
/// client can continue showing the rest of a snapshot. Such a key is retained
/// as read-only metadata but [YorksV1PermissionCatalogEntry.isOperational]
/// remains false until this list and its localized presentation are updated.
abstract final class YorksV1CapabilityKeys {
  static const projectsView = 'projects.view';
  static const projectsViewAll = 'projects.view_all';
  static const projectsCreate = 'projects.create';
  static const projectsEdit = 'projects.edit';
  static const projectsChangeState = 'projects.change_state';
  static const projectsArchive = 'projects.archive';
  static const projectsManageTeam = 'projects.manage_team';
  static const boqView = 'boq.view';
  static const boqEdit = 'boq.edit';
  static const boqImport = 'boq.import';
  static const boqExport = 'boq.export';
  static const boqManageFolders = 'boq.manage_folders';
  static const materialRequestsView = 'material_requests.view';
  static const materialRequestsCreate = 'material_requests.create';
  static const materialRequestsEdit = 'material_requests.edit';
  static const materialRequestsSubmit = 'material_requests.submit';
  static const materialRequestsApprove = 'material_requests.approve';
  static const materialRequestsReturnForChanges =
      'material_requests.return_for_changes';
  static const materialRequestsCancel = 'material_requests.cancel';
  static const materialRequestsClose = 'material_requests.close';
  static const materialRequestsPrint = 'material_requests.print';
  static const procurementView = 'procurement.view';
  static const procurementArrange = 'procurement.arrange';
  static const procurementExternalReadinessManage =
      'procurement.external_readiness.manage';
  static const dispatchView = 'dispatch.view';
  static const dispatchCreate = 'dispatch.create';
  static const deliveryOrdersGenerate = 'delivery_orders.generate';
  static const deliveryReportsPrint = 'delivery_reports.print';
  static const receiptsView = 'receipts.view';
  static const receiptsConfirm = 'receipts.confirm';
  static const receiptsAttachEvidence = 'receipts.attach_evidence';
  static const returnsView = 'returns.view';
  static const returnsCreate = 'returns.create';
  static const returnsApprove = 'returns.approve';
  static const returnsDispatch = 'returns.dispatch';
  static const returnsConfirm = 'returns.confirm';
  static const inventoryView = 'inventory.view';
  static const inventoryItemsManage = 'inventory.items.manage';
  static const inventoryStockAdjust = 'inventory.stock.adjust';
  static const inventoryImport = 'inventory.import';
  static const inventoryCategoriesManage = 'inventory.categories.manage';
  static const inventorySuppliersManage = 'inventory.suppliers.manage';
  static const inventoryExport = 'inventory.export';
  static const commercialsView = 'commercials.view';
  static const commercialsManage = 'commercials.manage';
  static const documentsView = 'documents.view';
  static const documentsUpload = 'documents.upload';
  static const documentsVersionsManage = 'documents.versions.manage';
  static const documentsCommercialView = 'documents.commercial.view';
  static const documentsAdminRestrictedView = 'documents.admin_restricted.view';
  static const chatView = 'chat.view';
  static const chatSend = 'chat.send';
  static const chatGroupsCreate = 'chat.groups.create';
  static const chatGroupsManage = 'chat.groups.manage';
  static const chatAnnouncementsCreate = 'chat.announcements.create';
  static const chatAnnouncementsSend = 'chat.announcements.send';
  static const rentalsView = 'rentals.view';
  static const rentalsManage = 'rentals.manage';
  static const rentalsImportExport = 'rentals.import_export';
  static const rentalsDocumentsManage = 'rentals.documents.manage';
  static const peopleView = 'people.view';
  static const peopleManage = 'people.manage';
  static const peopleSalaryView = 'people.salary.view';
  static const leaveViewOwn = 'leave.view_own';
  static const leaveRequest = 'leave.request';
  static const leaveViewAll = 'leave.view_all';
  static const leaveManage = 'leave.manage';
  static const configurationView = 'configuration.view';
  static const configurationStage = 'configuration.stage';
  static const configurationPublish = 'configuration.publish';
  static const usersView = 'users.view';
  static const usersCreate = 'users.create';
  static const usersProfileEdit = 'users.profile.edit';
  static const usersRolesAssign = 'users.roles.assign';
  static const usersPasswordReset = 'users.password.reset';
  static const usersActivationManage = 'users.activation.manage';
  static const usersDelete = 'users.delete';
  static const permissionsView = 'permissions.view';
  static const permissionsManage = 'permissions.manage';
  static const permissionsDelegate = 'permissions.delegate';
  static const permissionsRoleTemplatesManage =
      'permissions.role_templates.manage';
  static const auditView = 'audit.view';
  static const auditExport = 'audit.export';
  static const auditReviewNoteAppend = 'audit.review_note.append';
  static const analyticsView = 'analytics.view';
  static const analyticsExport = 'analytics.export';
  static const accountsView = 'accounts.view';
  static const accountsEdit = 'accounts.edit';
  static const accountsApprove = 'accounts.approve';
  static const accountsExport = 'accounts.export';
  static const viewProjectAccounts = 'view_project_accounts';
  static const viewProjectCommercialValues = 'view_project_commercial_values';
  static const suggestBillingProgress = 'suggest_billing_progress';
  static const confirmBillingProgress = 'confirm_billing_progress';
  static const prepareClientClaim = 'prepare_client_claim';
  static const manageClientInvoices = 'manage_client_invoices';
  static const recordClientCertification = 'record_client_certification';
  static const recordClientPayment = 'record_client_payment';
  static const managePdc = 'manage_pdc';
  static const manageSupplierBills = 'manage_supplier_bills';
  static const approveSupplierBillPayment = 'approve_supplier_bill_payment';
  static const configureProjectCommercials = 'configure_project_commercials';
  static const viewSupplierCosts = 'view_supplier_costs';
  static const exportAccountsRegisters = 'export_accounts_registers';
  static const reviewCommercialProgress = 'review_commercial_progress';
  static const workforceView = 'workforce.view';
  static const workforceAttendanceMaintain = 'workforce.attendance.maintain';
  static const workforceTimesheetsMaintain = 'workforce.timesheets.maintain';
  static const workforceTimesheetsReview = 'workforce.timesheets.review';
  static const workforceTimesheetsCorrectDuringReview =
      'workforce.timesheets.correct_during_review';
  static const workforceTimesheetsVerify = 'workforce.timesheets.verify';
  static const workforceTimesheetsFinalApprove =
      'workforce.timesheets.final_approve';
  static const workforcePeriodsReopen = 'workforce.periods.reopen';
  static const workforceReportsExport = 'workforce.reports.export';
  static const workforceWorkersManage = 'workforce.workers.manage';
  static const workforceTeamsManage = 'workforce.teams.manage';
  static const workforceConfigurationManage = 'workforce.configuration.manage';

  static const workforce = <String>{
    workforceView,
    workforceAttendanceMaintain,
    workforceTimesheetsMaintain,
    workforceTimesheetsReview,
    workforceTimesheetsCorrectDuringReview,
    workforceTimesheetsVerify,
    workforceTimesheetsFinalApprove,
    workforcePeriodsReopen,
    workforceReportsExport,
    workforceWorkersManage,
    workforceTeamsManage,
    workforceConfigurationManage,
  };

  /// The R39 Accounts contract is the only authority allowed to use bare
  /// snake_case capability keys. Retained operational capabilities remain
  /// dotted. Keeping this set closed prevents a malformed or future bare key
  /// from silently becoming client-recognized authority.
  static const r39Accounts = <String>{
    viewProjectAccounts,
    viewProjectCommercialValues,
    suggestBillingProgress,
    confirmBillingProgress,
    prepareClientClaim,
    manageClientInvoices,
    recordClientCertification,
    recordClientPayment,
    managePdc,
    manageSupplierBills,
    approveSupplierBillPayment,
    configureProjectCommercials,
    viewSupplierCosts,
    exportAccountsRegisters,
    reviewCommercialProgress,
  };

  static bool isValidWireKey(String value) =>
      RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$').hasMatch(value) ||
      r39Accounts.contains(value);

  static const all = <String>{
    projectsView,
    projectsViewAll,
    projectsCreate,
    projectsEdit,
    projectsChangeState,
    projectsArchive,
    projectsManageTeam,
    boqView,
    boqEdit,
    boqImport,
    boqExport,
    boqManageFolders,
    materialRequestsView,
    materialRequestsCreate,
    materialRequestsEdit,
    materialRequestsSubmit,
    materialRequestsApprove,
    materialRequestsReturnForChanges,
    materialRequestsCancel,
    materialRequestsClose,
    materialRequestsPrint,
    procurementView,
    procurementArrange,
    procurementExternalReadinessManage,
    dispatchView,
    dispatchCreate,
    deliveryOrdersGenerate,
    deliveryReportsPrint,
    receiptsView,
    receiptsConfirm,
    receiptsAttachEvidence,
    returnsView,
    returnsCreate,
    returnsApprove,
    returnsDispatch,
    returnsConfirm,
    inventoryView,
    inventoryItemsManage,
    inventoryStockAdjust,
    inventoryImport,
    inventoryCategoriesManage,
    inventorySuppliersManage,
    inventoryExport,
    commercialsView,
    commercialsManage,
    documentsView,
    documentsUpload,
    documentsVersionsManage,
    documentsCommercialView,
    documentsAdminRestrictedView,
    chatView,
    chatSend,
    chatGroupsCreate,
    chatGroupsManage,
    chatAnnouncementsCreate,
    chatAnnouncementsSend,
    rentalsView,
    rentalsManage,
    rentalsImportExport,
    rentalsDocumentsManage,
    peopleView,
    peopleManage,
    peopleSalaryView,
    leaveViewOwn,
    leaveRequest,
    leaveViewAll,
    leaveManage,
    configurationView,
    configurationStage,
    configurationPublish,
    usersView,
    usersCreate,
    usersProfileEdit,
    usersRolesAssign,
    usersPasswordReset,
    usersActivationManage,
    usersDelete,
    permissionsView,
    permissionsManage,
    permissionsDelegate,
    permissionsRoleTemplatesManage,
    auditView,
    auditExport,
    auditReviewNoteAppend,
    analyticsView,
    analyticsExport,
    accountsView,
    accountsEdit,
    accountsApprove,
    accountsExport,
    ...r39Accounts,
    ...workforce,
  };
}

enum YorksV1PermissionAuthorizationMode {
  shadow('shadow'),
  mixed('mixed'),
  enforced('enforced');

  const YorksV1PermissionAuthorizationMode(this.wireValue);

  final String wireValue;

  static YorksV1PermissionAuthorizationMode fromWire(Object? value) =>
      values.firstWhere(
        (mode) => mode.wireValue == value,
        orElse: () => throw const FormatException(
          'Invalid permission authorization mode',
        ),
      );
}

enum YorksV1PermissionCapabilityAuthorizationMode {
  shadow('shadow'),
  enforced('enforced');

  const YorksV1PermissionCapabilityAuthorizationMode(this.wireValue);

  final String wireValue;

  static YorksV1PermissionCapabilityAuthorizationMode fromWire(Object? value) =>
      values.firstWhere(
        (mode) => mode.wireValue == value,
        orElse: () => throw const FormatException(
          'Invalid capability authorization mode',
        ),
      );
}

enum YorksV1PermissionRiskLevel {
  low('low'),
  medium('medium'),
  high('high'),
  critical('critical');

  const YorksV1PermissionRiskLevel(this.wireValue);

  final String wireValue;

  static YorksV1PermissionRiskLevel fromWire(Object? value) =>
      values.firstWhere(
        (level) => level.wireValue == value,
        orElse: () =>
            throw const FormatException('Invalid permission risk level'),
      );
}

enum YorksV1PermissionRuntimeStatus {
  operational('operational'),
  planned('planned');

  const YorksV1PermissionRuntimeStatus(this.wireValue);

  final String wireValue;

  static YorksV1PermissionRuntimeStatus fromWire(Object? value) =>
      values.firstWhere(
        (status) => status.wireValue == value,
        orElse: () =>
            throw const FormatException('Invalid permission runtime status'),
      );
}

/// Assignment scopes are deliberately narrow. Record ownership (`self`) is a
/// protected runtime predicate and cannot be granted by an administrator.
enum YorksV1PermissionScopeKind {
  organization('organization'),
  project('project');

  const YorksV1PermissionScopeKind(this.wireValue);

  final String wireValue;

  static YorksV1PermissionScopeKind fromWire(Object? value) =>
      values.firstWhere(
        (scope) => scope.wireValue == value,
        orElse: () =>
            throw const FormatException('Invalid permission scope kind'),
      );
}

/// `inherit` is a client selection meaning that the explicit assignment must
/// be cleared. Persisted assignment rows and the set RPC accept only grant or
/// deny.
enum YorksV1PermissionAssignmentEffect {
  inherit('inherit'),
  grant('grant'),
  deny('deny');

  const YorksV1PermissionAssignmentEffect(this.wireValue);

  final String wireValue;

  bool get isExplicit => this != inherit;

  static YorksV1PermissionAssignmentEffect fromWire(
    Object? value, {
    bool allowInherit = false,
  }) {
    final effect = values.firstWhere(
      (candidate) => candidate.wireValue == value,
      orElse: () =>
          throw const FormatException('Invalid permission assignment effect'),
    );
    if (!allowInherit && !effect.isExplicit) {
      throw const FormatException('Persisted permission cannot inherit');
    }
    return effect;
  }
}

enum YorksV1PermissionChangeOperation {
  set('set'),
  clear('clear');

  const YorksV1PermissionChangeOperation(this.wireValue);

  final String wireValue;
}

/// One reviewed member of an atomic permission-change batch.
class YorksV1PermissionChange {
  YorksV1PermissionChange._({
    required this.operation,
    this.capabilityKey,
    this.effect,
    this.scope,
    this.effectiveFrom,
    this.effectiveUntil,
    this.assignmentId,
  }) {
    switch (operation) {
      case YorksV1PermissionChangeOperation.set:
        if (capabilityKey == null ||
            capabilityKey!.trim().isEmpty ||
            effect?.isExplicit != true ||
            scope == null ||
            assignmentId != null) {
          throw const FormatException('Invalid permission set change');
        }
        if (effectiveFrom != null &&
            effectiveUntil != null &&
            !effectiveUntil!.isAfter(effectiveFrom!)) {
          throw const FormatException('Invalid permission validity window');
        }
        break;
      case YorksV1PermissionChangeOperation.clear:
        if (assignmentId == null ||
            assignmentId!.trim().isEmpty ||
            capabilityKey != null ||
            effect != null ||
            scope != null ||
            effectiveFrom != null ||
            effectiveUntil != null) {
          throw const FormatException('Invalid permission clear change');
        }
        break;
    }
  }

  factory YorksV1PermissionChange.set({
    required String capabilityKey,
    required YorksV1PermissionAssignmentEffect effect,
    required YorksV1PermissionScope scope,
    DateTime? effectiveFrom,
    DateTime? effectiveUntil,
  }) => YorksV1PermissionChange._(
    operation: YorksV1PermissionChangeOperation.set,
    capabilityKey: capabilityKey.trim(),
    effect: effect,
    scope: scope,
    effectiveFrom: effectiveFrom?.toUtc(),
    effectiveUntil: effectiveUntil?.toUtc(),
  );

  factory YorksV1PermissionChange.clear({required String assignmentId}) =>
      YorksV1PermissionChange._(
        operation: YorksV1PermissionChangeOperation.clear,
        assignmentId: assignmentId.trim(),
      );

  final YorksV1PermissionChangeOperation operation;
  final String? capabilityKey;
  final YorksV1PermissionAssignmentEffect? effect;
  final YorksV1PermissionScope? scope;
  final DateTime? effectiveFrom;
  final DateTime? effectiveUntil;
  final String? assignmentId;

  Map<String, Object?> toRpcJson() => switch (operation) {
    YorksV1PermissionChangeOperation.set => {
      'operation': operation.wireValue,
      'capability_key': capabilityKey,
      'effect': effect!.wireValue,
      'scope_kind': scope!.kind.wireValue,
      'project_ids': scope!.projectIds,
      'effective_from': effectiveFrom?.toIso8601String(),
      'effective_until': effectiveUntil?.toIso8601String(),
    },
    YorksV1PermissionChangeOperation.clear => {
      'operation': operation.wireValue,
      'assignment_id': assignmentId,
    },
  };

  String get identity => switch (operation) {
    YorksV1PermissionChangeOperation.set => [
      operation.wireValue,
      capabilityKey,
      scope!.kind.wireValue,
    ].join(':'),
    YorksV1PermissionChangeOperation.clear =>
      '${operation.wireValue}:$assignmentId',
  };
}

enum YorksV1PermissionEffectiveSource {
  explicitDeny('explicit_deny'),
  explicitGrant('explicit_grant'),
  legacyOverride('legacy_override'),
  roleDefault('role_default'),
  hardInvariant('hard_invariant'),
  inactive('inactive'),
  plannedDisabled('planned_disabled'),
  none('none'),
  unknown('unknown');

  const YorksV1PermissionEffectiveSource(this.wireValue);

  final String wireValue;

  static YorksV1PermissionEffectiveSource fromWire(Object? value) =>
      values.firstWhere(
        (source) => source.wireValue == value,
        orElse: () =>
            throw const FormatException('Invalid effective permission source'),
      );
}

enum YorksV1PermissionAssignmentOrigin {
  permissionManagement('permission_management'),
  legacyCommercial('legacy_commercial'),
  legacyAppUser('legacy_app_user');

  const YorksV1PermissionAssignmentOrigin(this.wireValue);

  final String wireValue;

  static YorksV1PermissionAssignmentOrigin fromWire(Object? value) =>
      values.firstWhere(
        (origin) => origin.wireValue == value,
        orElse: () =>
            throw const FormatException('Invalid permission assignment origin'),
      );
}

class YorksV1PermissionScope {
  YorksV1PermissionScope({
    required this.kind,
    Iterable<String> projectIds = const [],
  }) : projectIds = List.unmodifiable(
         projectIds.map((id) => id.trim()).where((id) => id.isNotEmpty),
       ) {
    final distinct = this.projectIds.toSet();
    if (distinct.length != this.projectIds.length) {
      throw const FormatException('Permission project scope contains repeats');
    }
    if (kind == YorksV1PermissionScopeKind.organization &&
        this.projectIds.isNotEmpty) {
      throw const FormatException(
        'Organization permission cannot contain projects',
      );
    }
    if (kind == YorksV1PermissionScopeKind.project && this.projectIds.isEmpty) {
      throw const FormatException('Project permission requires a project');
    }
  }

  final YorksV1PermissionScopeKind kind;
  final List<String> projectIds;

  factory YorksV1PermissionScope.fromJson(Map<String, dynamic> json) =>
      YorksV1PermissionScope(
        kind: YorksV1PermissionScopeKind.fromWire(json['scope_kind']),
        projectIds: _stringList(json['project_ids']),
      );

  Map<String, Object?> toRpcJson() => {
    'scope_kind': kind.wireValue,
    'project_ids': projectIds,
  };

  bool containsProject(String projectId) =>
      kind == YorksV1PermissionScopeKind.project &&
      projectIds.contains(projectId.trim());
}

class YorksV1PermissionActor {
  const YorksV1PermissionActor._({
    required this.isSystem,
    this.appUserId,
    this.displayName,
    this.exactRole,
  });

  const YorksV1PermissionActor.user({
    required String appUserId,
    required String displayName,
    required YorksV1Role exactRole,
  }) : this._(
         isSystem: false,
         appUserId: appUserId,
         displayName: displayName,
         exactRole: exactRole,
       );

  const YorksV1PermissionActor.system({required String displayName})
    : this._(isSystem: true, displayName: displayName);

  final bool isSystem;
  final String? appUserId;
  final String? displayName;
  final YorksV1Role? exactRole;

  factory YorksV1PermissionActor.fromJson(Map<String, dynamic> json) {
    final kind = json['actor_kind'];
    if (kind == 'system') {
      if (json['app_user_id'] != null || json['exact_role'] != 'system') {
        throw const FormatException('System actor cannot have an app user id');
      }
      return YorksV1PermissionActor.system(
        displayName: _text(json['display_name']),
      );
    }
    if (kind != 'user') throw const FormatException('Invalid actor kind');
    return YorksV1PermissionActor.user(
      appUserId: _text(json['app_user_id']),
      displayName: _text(json['display_name']),
      exactRole: _role(json['exact_role']),
    );
  }
}

class YorksV1PermissionUser {
  YorksV1PermissionUser({
    required this.appUserId,
    required this.displayName,
    required this.exactRole,
    required this.isActive,
  }) {
    if (isActive && exactRole == null) {
      throw const FormatException('Active permission user requires a role');
    }
  }

  final String appUserId;
  final String displayName;
  final YorksV1Role? exactRole;
  final bool isActive;

  factory YorksV1PermissionUser.fromJson(Map<String, dynamic> json) =>
      YorksV1PermissionUser(
        appUserId: _text(json['app_user_id']),
        displayName: _text(json['display_name']),
        exactRole: _nullableRole(json['exact_role']),
        isActive: _boolean(json['is_active']),
      );
}

class YorksV1PermissionCatalogEntry {
  YorksV1PermissionCatalogEntry({
    required this.key,
    required this.module,
    required this.action,
    required this.label,
    required this.description,
    required this.riskLevel,
    required Iterable<YorksV1PermissionScopeKind> allowedScopes,
    required this.requiresProjectAccess,
    required Iterable<String> dependencies,
    required this.runtimeStatus,
    required this.isAssignable,
    required this.displayOrder,
  }) : allowedScopes = Set.unmodifiable(allowedScopes),
       dependencies = List.unmodifiable(dependencies) {
    if (!YorksV1CapabilityKeys.isValidWireKey(key) ||
        !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(module) ||
        !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(action)) {
      throw const FormatException('Incomplete permission catalog entry');
    }
    if (this.allowedScopes.isEmpty) {
      throw const FormatException('Permission must declare an allowed scope');
    }
    if (this.dependencies.toSet().length != this.dependencies.length ||
        this.dependencies.any(
          (dependency) => !YorksV1CapabilityKeys.isValidWireKey(dependency),
        )) {
      throw const FormatException('Invalid permission dependencies');
    }
    if (runtimeStatus != YorksV1PermissionRuntimeStatus.operational &&
        isAssignable) {
      throw const FormatException('Planned permission cannot be assignable');
    }
    if (displayOrder < 0) {
      throw const FormatException('Invalid permission display order');
    }
  }

  final String key;
  final String module;
  final String action;
  final String label;
  final String description;
  final YorksV1PermissionRiskLevel riskLevel;
  final Set<YorksV1PermissionScopeKind> allowedScopes;
  final bool requiresProjectAccess;
  final List<String> dependencies;
  final YorksV1PermissionRuntimeStatus runtimeStatus;
  final bool isAssignable;
  final int displayOrder;

  bool get isClientRecognized => YorksV1CapabilityKeys.all.contains(key);

  bool get isOperational =>
      isClientRecognized &&
      runtimeStatus == YorksV1PermissionRuntimeStatus.operational;

  bool get canAssignFromThisClient => isOperational && isAssignable;

  factory YorksV1PermissionCatalogEntry.fromJson(Map<String, dynamic> json) {
    final rawScopes = json['allowed_scope_kinds'];
    if (rawScopes is! List) {
      throw const FormatException('Missing permission scope catalogue');
    }
    return YorksV1PermissionCatalogEntry(
      key: _text(json['capability_key']),
      module: _text(json['module_key']),
      action: _text(json['action_key']),
      label: _text(json['label']),
      description: _text(json['description']),
      riskLevel: YorksV1PermissionRiskLevel.fromWire(json['risk_level']),
      allowedScopes: rawScopes.map(YorksV1PermissionScopeKind.fromWire),
      requiresProjectAccess: _boolean(json['requires_project_access']),
      dependencies: _stringList(json['dependencies']),
      runtimeStatus: YorksV1PermissionRuntimeStatus.fromWire(
        json['runtime_status'],
      ),
      isAssignable: _boolean(json['is_assignable']),
      displayOrder: _integer(json['display_order']),
    );
  }
}

class YorksV1PermissionRoleDefault {
  const YorksV1PermissionRoleDefault({
    required this.capabilityKey,
    required this.role,
    required this.isGranted,
  });

  final String capabilityKey;
  final YorksV1Role? role;
  final bool isGranted;
}

class YorksV1PermissionProjectEffectiveAccess {
  const YorksV1PermissionProjectEffectiveAccess({
    required this.projectId,
    required this.projectRef,
    required this.projectName,
    required this.effect,
    required this.hasProjectAccess,
    required this.authoritativeEffective,
    required this.authoritativeSource,
    required this.candidateEffective,
    required this.candidateSource,
    required this.hasParity,
    required this.effectiveFrom,
    this.effectiveUntil,
    required this.assignmentId,
  });

  final String projectId;
  final String projectRef;
  final String projectName;

  /// Null for a resolution-only project row with no direct assignment.
  final YorksV1PermissionAssignmentEffect? effect;
  final bool hasProjectAccess;
  final bool authoritativeEffective;
  final YorksV1PermissionEffectiveSource authoritativeSource;
  final bool candidateEffective;
  final YorksV1PermissionEffectiveSource candidateSource;
  final bool hasParity;
  final DateTime? effectiveFrom;
  final DateTime? effectiveUntil;
  final String? assignmentId;

  bool get hasDirectAssignment =>
      assignmentId != null && effect != null && effectiveFrom != null;

  bool get isAllowed => authoritativeEffective;

  factory YorksV1PermissionProjectEffectiveAccess.fromJson(
    Map<String, dynamic> json,
  ) {
    final effect = json['effect'] == null
        ? null
        : YorksV1PermissionAssignmentEffect.fromWire(json['effect']);
    final effectiveFrom = _nullableDateTime(json['effective_from']);
    final assignmentId = _nullableText(json['assignment_id']);
    final populated = [
      effect,
      effectiveFrom,
      assignmentId,
    ].where((value) => value != null).length;
    if (populated != 0 && populated != 3) {
      throw const FormatException('Incomplete project assignment projection');
    }
    return YorksV1PermissionProjectEffectiveAccess(
      projectId: _text(json['project_id']),
      projectRef: _text(json['project_ref']),
      projectName: _text(json['project_name']),
      effect: effect,
      hasProjectAccess: _boolean(json['has_project_access']),
      authoritativeEffective: _boolean(json['authoritative_effective']),
      authoritativeSource: YorksV1PermissionEffectiveSource.fromWire(
        json['authoritative_source'],
      ),
      candidateEffective: _boolean(json['candidate_effective']),
      candidateSource: YorksV1PermissionEffectiveSource.fromWire(
        json['candidate_source'],
      ),
      hasParity: _boolean(json['parity']),
      effectiveFrom: effectiveFrom,
      effectiveUntil: _nullableDateTime(json['effective_until']),
      assignmentId: assignmentId,
    );
  }
}

class YorksV1PermissionCapabilityAccess {
  YorksV1PermissionCapabilityAccess({
    required this.catalog,
    required this.authorizationMode,
    required this.roleDefault,
    required this.organizationSummaryVisible,
    required this.authoritativeEffective,
    required this.authoritativeSource,
    required this.candidateEffective,
    required this.candidateSource,
    required this.hasParity,
    required this.actorCanDelegate,
    required Iterable<YorksV1PermissionScopeKind> actorDelegableScopes,
    required Iterable<YorksV1PermissionProjectEffectiveAccess> projectOverrides,
  }) : actorDelegableScopes = Set.unmodifiable(actorDelegableScopes),
       projectOverrides = List.unmodifiable(projectOverrides) {
    if (!catalog.allowedScopes.containsAll(this.actorDelegableScopes)) {
      throw const FormatException(
        'Delegable permission scope is outside the catalogue',
      );
    }
    if (this.projectOverrides.map((item) => item.projectId).toSet().length !=
        this.projectOverrides.length) {
      throw const FormatException('Duplicate project permission override');
    }
  }

  final YorksV1PermissionCatalogEntry catalog;
  final YorksV1PermissionCapabilityAuthorizationMode authorizationMode;
  final YorksV1PermissionRoleDefault roleDefault;
  final bool organizationSummaryVisible;
  final bool? authoritativeEffective;
  final YorksV1PermissionEffectiveSource? authoritativeSource;
  final bool? candidateEffective;
  final YorksV1PermissionEffectiveSource? candidateSource;
  final bool? hasParity;

  /// Server-projected delegation authority for this exact actor, target and
  /// capability. Missing or malformed values fail decoding rather than
  /// painting an assignment control the server must reject.
  final bool actorCanDelegate;

  /// Server-projected scope ceiling for this actor, target and capability.
  /// An absent or empty projection is intentionally read-only; the client
  /// never infers organization authority from a role label.
  final Set<YorksV1PermissionScopeKind> actorDelegableScopes;
  final List<YorksV1PermissionProjectEffectiveAccess> projectOverrides;

  bool get canEdit =>
      actorCanDelegate &&
      actorDelegableScopes.isNotEmpty &&
      catalog.canAssignFromThisClient &&
      authorizationMode ==
          YorksV1PermissionCapabilityAuthorizationMode.enforced;

  /// Safe convenience alias. Never substitutes the shadow candidate decision.
  bool? get organizationEffective => authoritativeEffective;

  YorksV1PermissionEffectiveSource? get organizationSource =>
      authoritativeSource;

  bool? get candidateOrganizationEffective => candidateEffective;

  YorksV1PermissionEffectiveSource? get candidateOrganizationSource =>
      candidateSource;

  factory YorksV1PermissionCapabilityAccess.fromJson(
    Map<String, dynamic> json, {
    required YorksV1Role? targetRole,
  }) {
    final projectOverrides = json['project_overrides'];
    if (projectOverrides is! List) {
      throw const FormatException('Missing project permission overrides');
    }
    final rawDelegableScopes = json['actor_delegable_scope_kinds'];
    if (rawDelegableScopes != null && rawDelegableScopes is! List) {
      throw const FormatException('Invalid delegable permission scopes');
    }
    final catalog = YorksV1PermissionCatalogEntry.fromJson(json);
    final organizationSummaryVisible = _boolean(
      json['organization_summary_visible'],
    );
    final authoritativeEffective = json['authoritative_effective'] == null
        ? null
        : _boolean(json['authoritative_effective']);
    final authoritativeSource = json['authoritative_source'] == null
        ? null
        : YorksV1PermissionEffectiveSource.fromWire(
            json['authoritative_source'],
          );
    final candidateEffective = json['candidate_effective'] == null
        ? null
        : _boolean(json['candidate_effective']);
    final candidateSource = json['candidate_source'] == null
        ? null
        : YorksV1PermissionEffectiveSource.fromWire(json['candidate_source']);
    final hasParity = json['parity'] == null ? null : _boolean(json['parity']);
    if (organizationSummaryVisible &&
        (authoritativeEffective == null ||
            authoritativeSource == null ||
            candidateEffective == null ||
            candidateSource == null ||
            hasParity == null)) {
      throw const FormatException(
        'Visible organization permission summary is incomplete',
      );
    }
    if (!organizationSummaryVisible &&
        (authoritativeEffective != null ||
            authoritativeSource != null ||
            candidateEffective != null ||
            candidateSource != null ||
            hasParity != null)) {
      throw const FormatException(
        'Hidden organization permission summary was not redacted',
      );
    }
    return YorksV1PermissionCapabilityAccess(
      catalog: catalog,
      authorizationMode: YorksV1PermissionCapabilityAuthorizationMode.fromWire(
        json['authorization_mode'],
      ),
      roleDefault: YorksV1PermissionRoleDefault(
        capabilityKey: catalog.key,
        role: targetRole,
        isGranted: _boolean(json['role_default']),
      ),
      organizationSummaryVisible: organizationSummaryVisible,
      authoritativeEffective: authoritativeEffective,
      authoritativeSource: authoritativeSource,
      candidateEffective: candidateEffective,
      candidateSource: candidateSource,
      hasParity: hasParity,
      actorCanDelegate: _boolean(json['actor_can_delegate']),
      actorDelegableScopes: rawDelegableScopes == null
          ? const <YorksV1PermissionScopeKind>[]
          : rawDelegableScopes.map<YorksV1PermissionScopeKind>(
              YorksV1PermissionScopeKind.fromWire,
            ),
      projectOverrides: projectOverrides.map(
        (item) =>
            YorksV1PermissionProjectEffectiveAccess.fromJson(_object(item)),
      ),
    );
  }

  bool authoritativeEffectiveForProject(String projectId) {
    final normalized = projectId.trim();
    for (final override in projectOverrides) {
      if (override.projectId == normalized) {
        return override.authoritativeEffective;
      }
    }
    return false;
  }

  bool candidateEffectiveForProject(String projectId) {
    final normalized = projectId.trim();
    for (final override in projectOverrides) {
      if (override.projectId == normalized) return override.candidateEffective;
    }
    return false;
  }
}

class YorksV1PermissionProjectAccess {
  const YorksV1PermissionProjectAccess({
    required this.projectId,
    required this.projectRef,
    required this.projectName,
    required this.state,
    required this.hasAccess,
  });

  final String projectId;
  final String projectRef;
  final String projectName;
  final String state;
  final bool hasAccess;

  factory YorksV1PermissionProjectAccess.fromJson(Map<String, dynamic> json) =>
      YorksV1PermissionProjectAccess(
        projectId: _text(json['project_id']),
        projectRef: _text(json['project_ref']),
        projectName: _text(json['project_name']),
        state: _text(json['state']),
        // The protected projection contains only projects for which the target
        // has record access. A future explicit flag may narrow that further.
        hasAccess: _boolean(json['has_access']),
      );
}

class YorksV1CurrentPermissionSnapshot {
  YorksV1CurrentPermissionSnapshot({
    required this.schemaVersion,
    required this.authorizationMode,
    required this.generatedAt,
    this.nextTransitionAt,
    required this.user,
    required this.revision,
    required Iterable<YorksV1PermissionCapabilityAccess> capabilities,
    required Iterable<YorksV1PermissionProjectAccess> projectAccess,
  }) : capabilities = List.unmodifiable(capabilities),
       projectAccess = List.unmodifiable(projectAccess) {
    if (schemaVersion != YorksV1PermissionSchema.current) {
      throw const FormatException('Unsupported permission snapshot schema');
    }
    if (revision < 0) {
      throw const FormatException('Invalid permission snapshot revision');
    }
    if (this.capabilities.map((item) => item.catalog.key).toSet().length !=
        this.capabilities.length) {
      throw const FormatException('Duplicate permission capability');
    }
    if (this.projectAccess.map((item) => item.projectId).toSet().length !=
        this.projectAccess.length) {
      throw const FormatException('Duplicate permission project access');
    }
  }

  final int schemaVersion;
  final YorksV1PermissionAuthorizationMode authorizationMode;
  final DateTime generatedAt;

  /// Earliest future server-time boundary at which an assignment starts or
  /// expires. Realtime cannot emit an event for the passage of time itself, so
  /// the controller schedules a protected refresh at this instant.
  final DateTime? nextTransitionAt;
  final YorksV1PermissionUser user;
  final int revision;
  final List<YorksV1PermissionCapabilityAccess> capabilities;
  final List<YorksV1PermissionProjectAccess> projectAccess;

  factory YorksV1CurrentPermissionSnapshot.fromRpcJson(
    Map<String, dynamic> json,
  ) {
    final user = YorksV1PermissionUser.fromJson(_object(json['user']));
    return YorksV1CurrentPermissionSnapshot(
      schemaVersion: _integer(json['schema_version']),
      authorizationMode: YorksV1PermissionAuthorizationMode.fromWire(
        json['authorization_mode'],
      ),
      generatedAt: _dateTime(json['generated_at']),
      nextTransitionAt: _nullableDateTime(json['next_transition_at']),
      user: user,
      revision: _integer(json['revision']),
      capabilities: _objectList(json['capabilities']).map(
        (item) => YorksV1PermissionCapabilityAccess.fromJson(
          item,
          targetRole: user.exactRole,
        ),
      ),
      projectAccess: _objectList(
        json['project_access'],
      ).map(YorksV1PermissionProjectAccess.fromJson),
    );
  }

  YorksV1PermissionCapabilityAccess? capability(String capabilityKey) {
    final normalized = capabilityKey.trim();
    for (final access in capabilities) {
      if (access.catalog.key == normalized) return access;
    }
    return null;
  }

  /// A fail-closed presentation helper. Trusted reads and commands must still
  /// repeat the authorization check in Postgres.
  /// An Accountant is never a technical project member, so [projectAccess] is
  /// empty by design and the server grants their Accounts capabilities from the
  /// role default instead. Limited to the Accounts module: this gives them no
  /// project, BOQ or other technical access. A per-project denial still wins, and
  /// the server re-checks every Accounts RPC.
  bool accountantHoldsAccountsCapability(
    YorksV1PermissionCapabilityAccess access,
  ) =>
      user.exactRole == YorksV1Role.accountant &&
      access.catalog.module == 'accounts' &&
      access.roleDefault.isGranted;

  bool allows(String capabilityKey, {String? projectId}) {
    if (!user.isActive) return false;
    final access = capability(capabilityKey);
    if (access == null || !access.catalog.isOperational) return false;
    // Organization-scoped capabilities do not receive per-project rows from
    // the server. Passing project context to a shared action helper must not
    // accidentally turn a confirmed organization grant into a deny.
    if (!access.catalog.requiresProjectAccess) {
      return access.authoritativeEffective == true;
    }
    if (projectId == null) {
      return false;
    }
    final normalizedProjectId = projectId.trim();
    if (normalizedProjectId.isEmpty) return false;
    if (accountantHoldsAccountsCapability(access)) {
      for (final override in access.projectOverrides) {
        if (override.projectId == normalizedProjectId) {
          return override.authoritativeEffective;
        }
      }
      return true;
    }
    if (!projectAccess.any(
      (project) =>
          project.projectId == normalizedProjectId && project.hasAccess,
    )) {
      return false;
    }
    return access.authoritativeEffectiveForProject(normalizedProjectId);
  }
}

class YorksV1PermissionAssignmentValue {
  YorksV1PermissionAssignmentValue({
    required this.capabilityKey,
    required this.effect,
    required this.scope,
    required this.effectiveFrom,
    this.effectiveUntil,
  }) {
    if (!effect.isExplicit) {
      throw const FormatException('Assignment value must be explicit');
    }
    if (effectiveUntil != null && !effectiveUntil!.isAfter(effectiveFrom)) {
      throw const FormatException('Invalid permission validity window');
    }
  }

  final String capabilityKey;
  final YorksV1PermissionAssignmentEffect effect;
  final YorksV1PermissionScope scope;
  final DateTime effectiveFrom;
  final DateTime? effectiveUntil;

  factory YorksV1PermissionAssignmentValue.fromJson(
    Map<String, dynamic> json,
  ) => YorksV1PermissionAssignmentValue(
    capabilityKey: _text(json['capability_key']),
    effect: YorksV1PermissionAssignmentEffect.fromWire(json['effect']),
    scope: YorksV1PermissionScope.fromJson(json),
    effectiveFrom: _dateTime(json['effective_from']),
    effectiveUntil: _nullableDateTime(json['effective_until']),
  );
}

class YorksV1PermissionAssignment extends YorksV1PermissionAssignmentValue {
  YorksV1PermissionAssignment({
    required this.id,
    required super.capabilityKey,
    required super.effect,
    required super.scope,
    required this.origin,
    required super.effectiveFrom,
    super.effectiveUntil,
    required this.reason,
    required this.version,
    required this.changedBy,
    required this.createdAt,
    required this.updatedAt,
  }) {
    if (id.isEmpty || reason.trim().isEmpty || version < 1) {
      throw const FormatException('Incomplete permission assignment');
    }
  }

  final String id;
  final YorksV1PermissionAssignmentOrigin origin;
  final String reason;
  final int version;
  final YorksV1PermissionActor? changedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory YorksV1PermissionAssignment.fromJson(Map<String, dynamic> json) =>
      YorksV1PermissionAssignment(
        id: _text(json['id']),
        capabilityKey: _text(json['capability_key']),
        effect: YorksV1PermissionAssignmentEffect.fromWire(json['effect']),
        scope: YorksV1PermissionScope.fromJson(json),
        origin: YorksV1PermissionAssignmentOrigin.fromWire(json['origin']),
        effectiveFrom: _dateTime(json['effective_from']),
        effectiveUntil: _nullableDateTime(json['effective_until']),
        reason: _text(json['reason']),
        version: _integer(json['version']),
        changedBy: json['changed_by'] == null
            ? null
            : YorksV1PermissionActor.fromJson(_object(json['changed_by'])),
        createdAt: _dateTime(json['created_at']),
        updatedAt: _dateTime(json['updated_at']),
      );
}

enum YorksV1PermissionHistoryEventKind {
  set('set'),
  clear('clear'),
  migration('migration'),
  legacySync('legacy_sync');

  const YorksV1PermissionHistoryEventKind(this.wireValue);

  final String wireValue;

  static YorksV1PermissionHistoryEventKind fromWire(Object? value) =>
      values.firstWhere(
        (kind) => kind.wireValue == value,
        orElse: () =>
            throw const FormatException('Invalid permission history event'),
      );
}

class YorksV1PermissionHistoryEvent {
  YorksV1PermissionHistoryEvent({
    required this.id,
    required this.kind,
    required this.capabilityKey,
    required this.effect,
    required this.scope,
    required Iterable<YorksV1PermissionAssignmentValue> before,
    required Iterable<YorksV1PermissionAssignmentValue> after,
    required this.reason,
    required this.actor,
    required this.occurredAt,
    required this.idempotencyKey,
    required this.eventOrdinal,
    required this.revision,
  }) : before = List.unmodifiable(before),
       after = List.unmodifiable(after);

  final String id;
  final YorksV1PermissionHistoryEventKind kind;
  final String capabilityKey;
  final YorksV1PermissionAssignmentEffect? effect;
  final YorksV1PermissionScope scope;
  final List<YorksV1PermissionAssignmentValue> before;
  final List<YorksV1PermissionAssignmentValue> after;
  final String reason;
  final YorksV1PermissionActor actor;
  final DateTime occurredAt;
  final String? idempotencyKey;
  final int eventOrdinal;
  final int revision;

  factory YorksV1PermissionHistoryEvent.fromJson(Map<String, dynamic> json) {
    final effect = json['effect'];
    return YorksV1PermissionHistoryEvent(
      id: _text(json['id']),
      kind: YorksV1PermissionHistoryEventKind.fromWire(json['event_kind']),
      capabilityKey: _text(json['capability_key']),
      effect: effect == null
          ? null
          : YorksV1PermissionAssignmentEffect.fromWire(effect),
      scope: YorksV1PermissionScope.fromJson(json),
      before: _permissionAssignmentValueList(json['before']),
      after: _permissionAssignmentValueList(json['after']),
      reason: _text(json['reason']),
      actor: YorksV1PermissionActor.fromJson(_object(json['actor'])),
      occurredAt: _dateTime(json['occurred_at']),
      idempotencyKey: _nullableText(json['idempotency_key']),
      eventOrdinal: _integer(json['event_ordinal']),
      revision: _integer(json['revision']),
    );
  }
}

List<YorksV1PermissionAssignmentValue> _permissionAssignmentValueList(
  Object? value,
) {
  if (value == null) return const [];
  return _objectList(
    value,
  ).map(YorksV1PermissionAssignmentValue.fromJson).toList(growable: false);
}

class YorksV1PermissionHistoryPage {
  YorksV1PermissionHistoryPage({
    required this.schemaVersion,
    required this.targetAppUserId,
    required Iterable<YorksV1PermissionHistoryEvent> items,
    this.nextOccurredAt,
    this.nextId,
  }) : items = List.unmodifiable(items) {
    if (schemaVersion != YorksV1PermissionSchema.current) {
      throw const FormatException('Unsupported permission history schema');
    }
    if ((nextOccurredAt == null) != (nextId == null)) {
      throw const FormatException('Incomplete permission history cursor');
    }
  }

  final int schemaVersion;
  final String targetAppUserId;
  final List<YorksV1PermissionHistoryEvent> items;
  final DateTime? nextOccurredAt;
  final String? nextId;

  factory YorksV1PermissionHistoryPage.fromRpcJson(Map<String, dynamic> json) {
    final cursor = json['next_cursor'];
    final cursorObject = cursor == null ? null : _object(cursor);
    return YorksV1PermissionHistoryPage(
      schemaVersion: _integer(json['schema_version']),
      targetAppUserId: _text(json['target_app_user_id']),
      items: _objectList(
        json['items'],
      ).map(YorksV1PermissionHistoryEvent.fromJson),
      nextOccurredAt: cursorObject == null
          ? null
          : _dateTime(cursorObject['occurred_at']),
      nextId: cursorObject == null ? null : _text(cursorObject['id']),
    );
  }
}

class YorksV1UserPermissionWorkspace {
  YorksV1UserPermissionWorkspace({
    required this.schemaVersion,
    required this.authorizationMode,
    required this.generatedAt,
    required this.actor,
    required this.target,
    required this.revision,
    required Iterable<YorksV1PermissionCapabilityAccess> catalog,
    required Iterable<YorksV1PermissionAssignment> assignments,
    required Iterable<YorksV1PermissionProjectAccess> projects,
    required Iterable<YorksV1PermissionHistoryEvent> recentHistory,
    this.workforceAccess,
  }) : catalog = List.unmodifiable(catalog),
       assignments = List.unmodifiable(assignments),
       projects = List.unmodifiable(projects),
       recentHistory = List.unmodifiable(recentHistory) {
    if (schemaVersion != YorksV1PermissionSchema.current) {
      throw const FormatException('Unsupported permission workspace schema');
    }
    if (revision < 0) {
      throw const FormatException('Invalid permission workspace revision');
    }
    if (this.catalog.map((item) => item.catalog.key).toSet().length !=
        this.catalog.length) {
      throw const FormatException('Duplicate workspace capability');
    }
    if (this.assignments.map((item) => item.id).toSet().length !=
        this.assignments.length) {
      throw const FormatException('Duplicate permission assignment');
    }
  }

  final int schemaVersion;
  final YorksV1PermissionAuthorizationMode authorizationMode;
  final DateTime generatedAt;
  final YorksV1PermissionActor actor;
  final YorksV1PermissionUser target;
  final int revision;
  final List<YorksV1PermissionCapabilityAccess> catalog;
  final List<YorksV1PermissionAssignment> assignments;
  final List<YorksV1PermissionProjectAccess> projects;
  final List<YorksV1PermissionHistoryEvent> recentHistory;
  final YorksV1WorkforceAccessStatus? workforceAccess;

  List<YorksV1PermissionRoleDefault> get roleDefaults =>
      List.unmodifiable(catalog.map((entry) => entry.roleDefault));

  factory YorksV1UserPermissionWorkspace.fromRpcJson(
    Map<String, dynamic> json,
  ) {
    final target = YorksV1PermissionUser.fromJson(_object(json['target']));
    return YorksV1UserPermissionWorkspace(
      schemaVersion: _integer(json['schema_version']),
      authorizationMode: YorksV1PermissionAuthorizationMode.fromWire(
        json['authorization_mode'],
      ),
      generatedAt: _dateTime(json['generated_at']),
      actor: YorksV1PermissionActor.fromJson(_object(json['actor'])),
      target: target,
      revision: _integer(json['revision']),
      catalog: _objectList(json['catalog']).map(
        (item) => YorksV1PermissionCapabilityAccess.fromJson(
          item,
          targetRole: target.exactRole,
        ),
      ),
      assignments: _objectList(
        json['assignments'],
      ).map(YorksV1PermissionAssignment.fromJson),
      projects: _objectList(
        json['projects'],
      ).map(YorksV1PermissionProjectAccess.fromJson),
      recentHistory: _objectList(
        json['recent_history'],
      ).map(YorksV1PermissionHistoryEvent.fromJson),
      workforceAccess: json['workforce_access'] == null
          ? null
          : YorksV1WorkforceAccessStatus.fromJson(
              _object(json['workforce_access']),
            ),
    );
  }
}

class YorksV1WorkforceAccessStatus {
  YorksV1WorkforceAccessStatus({
    required this.referenceDate,
    required this.hasOperationalAccess,
    required this.canAssignOrganizationResponsibility,
    required this.activeWorkerCount,
    required this.activeTeamCount,
    required this.scheduledTeamCount,
    this.organizationResponsibilityId,
    this.organizationResponsibilityValidFrom,
    this.organizationResponsibilityValidTo,
    this.organizationResponsibilityRecordVersion,
  }) {
    final responsibilityValues = <Object?>[
      organizationResponsibilityId,
      organizationResponsibilityValidFrom,
      organizationResponsibilityRecordVersion,
    ];
    if (responsibilityValues.any((value) => value == null) &&
        responsibilityValues.any((value) => value != null)) {
      throw const FormatException(
        'Incomplete Workforce organization responsibility',
      );
    }
    if (activeWorkerCount < 0 ||
        activeTeamCount < 0 ||
        scheduledTeamCount < 0 ||
        scheduledTeamCount > activeTeamCount) {
      throw const FormatException('Invalid Workforce access counts');
    }
  }

  final DateTime referenceDate;
  final bool hasOperationalAccess;
  final bool canAssignOrganizationResponsibility;
  final int activeWorkerCount;
  final int activeTeamCount;
  final int scheduledTeamCount;
  final String? organizationResponsibilityId;
  final DateTime? organizationResponsibilityValidFrom;
  final DateTime? organizationResponsibilityValidTo;
  final int? organizationResponsibilityRecordVersion;

  bool get hasOrganizationResponsibility =>
      organizationResponsibilityId != null;

  bool get isConfigurationEmpty =>
      activeWorkerCount == 0 && activeTeamCount == 0;

  factory YorksV1WorkforceAccessStatus.fromJson(Map<String, dynamic> json) {
    final responsibility = json['organization_responsibility'] == null
        ? null
        : _object(json['organization_responsibility']);
    return YorksV1WorkforceAccessStatus(
      referenceDate: _dateOnly(json['reference_date']),
      hasOperationalAccess: _boolean(json['has_operational_access']),
      canAssignOrganizationResponsibility: _boolean(
        json['can_assign_organization_responsibility'],
      ),
      activeWorkerCount: _integer(json['active_worker_count']),
      activeTeamCount: _integer(json['active_team_count']),
      scheduledTeamCount: _integer(json['scheduled_team_count']),
      organizationResponsibilityId: responsibility == null
          ? null
          : _text(responsibility['responsibility_assignment_id']),
      organizationResponsibilityValidFrom: responsibility == null
          ? null
          : _dateOnly(responsibility['valid_from']),
      organizationResponsibilityValidTo:
          responsibility == null || responsibility['valid_to'] == null
          ? null
          : _dateOnly(responsibility['valid_to']),
      organizationResponsibilityRecordVersion: responsibility == null
          ? null
          : _integer(responsibility['record_version']),
    );
  }
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map) throw const FormatException('Expected JSON object');
  return Map<String, dynamic>.from(value);
}

List<Map<String, dynamic>> _objectList(Object? value) {
  if (value is! List) throw const FormatException('Expected JSON array');
  return value.map(_object).toList(growable: false);
}

List<String> _stringList(Object? value) {
  if (value is! List || value.any((item) => item is! String)) {
    throw const FormatException('Expected string array');
  }
  return value
      .cast<String>()
      .map((item) => item.trim())
      .toList(growable: false);
}

String _text(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Expected non-empty text');
  }
  return value.trim();
}

String? _nullableText(Object? value) {
  if (value == null) return null;
  return _text(value);
}

bool _boolean(Object? value) {
  if (value is! bool) throw const FormatException('Expected boolean');
  return value;
}

int _integer(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw const FormatException('Expected integer');
}

DateTime _dateTime(Object? value) {
  if (value is! String) throw const FormatException('Expected timestamp');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw const FormatException('Invalid timestamp');
  return parsed.toUtc();
}

DateTime? _nullableDateTime(Object? value) {
  if (value == null) return null;
  return _dateTime(value);
}

DateTime _dateOnly(Object? value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const FormatException('Expected date');
  }
  final parsed = DateTime.tryParse('${value}T00:00:00Z');
  if (parsed == null) throw const FormatException('Invalid date');
  return parsed;
}

YorksV1Role _role(Object? value) {
  final role = YorksV1Role.fromServerClaim(value);
  if (role == null) throw const FormatException('Invalid exact V1 role');
  return role;
}

YorksV1Role? _nullableRole(Object? value) {
  if (value == null || value == '') return null;
  return _role(value);
}

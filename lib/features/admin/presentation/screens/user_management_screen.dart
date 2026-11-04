import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:uuid/uuid.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/constants.dart';
import '../../../../core/feedback/feedback_service.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/app_user.dart';
import '../../../../shared/models/audit_log.dart';
import '../../../../shared/models/effective_permissions.dart';
import '../../../../shared/models/user_role.dart';
import '../../../../shared/models/yorks_v1_commercial_capability.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/models/yorks_v1_permission_management.dart';
import '../../../../shared/models/yorks_v1_project_strings.dart';
import '../../../../shared/models/yorks_v1_permission_strings.dart';
import '../../../../shared/models/yorks_v1_role.dart';
import '../../../../shared/models/yorks_v1_user_management_strings.dart';
import '../../../../shared/models/yorks_v1_user_project_access.dart';
import '../../../../shared/providers/audit_log_provider.dart';
import '../../../../shared/providers/hr_provider.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/session_provider.dart';
import '../../../../shared/providers/users_provider.dart';
import '../../../../shared/providers/yorks_v1_commercial_capability_provider.dart';
import '../../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../../../shared/providers/yorks_v1_permission_provider.dart';
import '../../../../shared/providers/yorks_v1_user_project_access_provider.dart';
import '../widgets/yorks_v1_user_management_views.dart';

/// Strips the `Exception: ` prefix so remote-provisioning errors read cleanly in
/// a snackbar.
String _friendlyErr(Object e) {
  final s = e.toString();
  const p = 'Exception: ';
  return s.startsWith(p) ? s.substring(p.length) : s;
}

String _permissionCopy(AppLanguage language, String key, {String? name}) =>
    YorksV1PermissionStrings.text(
      language,
      key,
    ).replaceAll('{name}', name ?? '');

List<YorksV1Role> _displayYorksV1Roles(AppUser user) =>
    user.yorksV1RoleCache == null
    ? const <YorksV1Role>[]
    : <YorksV1Role>[user.yorksV1RoleCache!];

/// Display-only role text for the retained roster. V1 authorization never uses
/// this cache; server commands and route guards read the current exact claim.
String _roleLabel(AppUser user, {required bool yorksV1Provisioning}) {
  if (!yorksV1Provisioning) return user.role.label;
  final roles = _displayYorksV1Roles(user);
  return roles.isEmpty
      ? AppStrings.yorksV1RoleMappingRequired.primary
      : roles.map((role) => _yorksV1RoleText(role).primary).join(' · ');
}

String _roleFamilyLabel(
  AppUser user, {
  required bool yorksV1Provisioning,
  required AppLanguage language,
}) {
  if (!yorksV1Provisioning) return user.role.label;
  final roles = _displayYorksV1Roles(user);
  if (roles.any((role) => role.isEngineering)) {
    return _permissionCopy(language, 'role_family.engineering');
  }
  if (roles.contains(YorksV1Role.procurement)) {
    return _permissionCopy(language, 'role_family.procurement');
  }
  if (roles.contains(YorksV1Role.admin)) {
    return _permissionCopy(language, 'role_family.admin');
  }
  return _permissionCopy(language, 'unassigned');
}

String _roleTitleLabel(
  AppUser user, {
  required bool yorksV1Provisioning,
  required AppLanguage language,
}) {
  if (!yorksV1Provisioning) return user.role.label;
  final roles = _displayYorksV1Roles(user);
  if (roles.isEmpty) return _permissionCopy(language, 'unassigned');
  return roles
      .map((role) => _yorksV1RoleText(role).active(language))
      .join(' · ');
}

TranslatableString _yorksV1RoleText(YorksV1Role role) => switch (role) {
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
};

/// The per-user capabilities an Admin can grant/revoke, with display labels.
const _managedPermissions = <(PermissionKey, String)>[
  (PermissionKey.viewCommercials, 'View commercials'),
  (PermissionKey.finance, 'Financial reports'),
  (PermissionKey.salary, 'Salary & HR documents'),
  (PermissionKey.rentals, 'Rentals module'),
  (PermissionKey.people, 'People / HR module'),
  (PermissionKey.goods, 'Receive goods (stock-in)'),
];

typedef _UserManagementBusyCommand =
    Future<void> Function(Future<void> Function() command);

@visibleForTesting
bool yorksV1IsProtectedSelfTarget({
  required bool connectedV1,
  required String? currentAppUserId,
  required String targetAppUserId,
}) =>
    connectedV1 &&
    currentAppUserId != null &&
    currentAppUserId.trim().isNotEmpty &&
    currentAppUserId == targetAppUserId;

@visibleForTesting
class YorksV1UserManagementAccess {
  const YorksV1UserManagementAccess({
    required this.canView,
    required this.canCreate,
    required this.canEditProfile,
    required this.canAssignRoles,
    required this.canResetPassword,
    required this.canManageActivation,
    required this.canViewPermissions,
    required this.canManagePermissions,
    required this.canViewAudit,
    required this.isConfigurationActor,
    required this.connectedV1,
  });

  factory YorksV1UserManagementAccess.resolve({
    required bool connectedV1,
    required YorksV1Role? role,
    required YorksV1CurrentPermissionSnapshotState permissionState,
  }) {
    if (!connectedV1) {
      return const YorksV1UserManagementAccess(
        canView: true,
        canCreate: true,
        canEditProfile: true,
        canAssignRoles: true,
        canResetPassword: true,
        canManageActivation: true,
        canViewPermissions: false,
        canManagePermissions: false,
        canViewAudit: true,
        isConfigurationActor: false,
        connectedV1: false,
      );
    }
    final legacy = role?.canConfigureUsers ?? false;
    bool read(String key) => permissionState.hybridAllows(
      key,
      legacyAllowed: legacy,
      organizationSummary: true,
    );
    bool write(String key) => permissionState.hybridAllows(
      key,
      legacyAllowed: legacy,
      requireWrite: true,
      organizationSummary: true,
    );
    return YorksV1UserManagementAccess(
      canView: read(YorksV1CapabilityKeys.usersView),
      canCreate: write(YorksV1CapabilityKeys.usersCreate),
      canEditProfile: write(YorksV1CapabilityKeys.usersProfileEdit),
      canAssignRoles: write(YorksV1CapabilityKeys.usersRolesAssign),
      canResetPassword: write(YorksV1CapabilityKeys.usersPasswordReset),
      canManageActivation: write(YorksV1CapabilityKeys.usersActivationManage),
      canViewPermissions: read(YorksV1CapabilityKeys.permissionsView),
      canManagePermissions: write(YorksV1CapabilityKeys.permissionsManage),
      canViewAudit: read(YorksV1CapabilityKeys.auditView),
      // The retained commercial-capability RPC has not been delegated yet.
      // It still requires the established Admin/SME configuration actor in
      // addition to the scoped permission decision.
      isConfigurationActor: role?.canConfigureUsers ?? false,
      connectedV1: true,
    );
  }

  final bool canView;
  final bool canCreate;
  final bool canEditProfile;
  final bool canAssignRoles;
  final bool canResetPassword;
  final bool canManageActivation;
  final bool canViewPermissions;
  final bool canManagePermissions;
  final bool canViewAudit;
  final bool isConfigurationActor;
  final bool connectedV1;

  bool get canManageUser =>
      canEditProfile ||
      canAssignRoles ||
      canResetPassword ||
      canManageActivation;

  bool get canViewCommercialAccess =>
      isConfigurationActor && canViewPermissions;

  bool get canManageCommercialAccess =>
      isConfigurationActor && canManagePermissions;
}

/// Admin user management & access control (SRS §4.7). Create, edit,
/// deactivate and restore accounts, assign roles and project teams, reset
/// passwords and open detailed permissions. No self-signup: management creates
/// every account.
class UserManagementScreen extends ConsumerStatefulWidget {
  const UserManagementScreen({super.key});

  @override
  ConsumerState<UserManagementScreen> createState() =>
      _UserManagementScreenState();
}

const _metricAll = 'all';
const _metricActive = 'active';
const _metricEngineers = 'engineers';
const _metricUnassigned = 'unassigned';
const _metricProjects = 'projects';
const _metricDeactivated = 'deactivated';

class _UserManagementScreenState extends ConsumerState<UserManagementScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  YorksV1UserManagementTab _tab = YorksV1UserManagementTab.users;
  String _metric = _metricAll;
  YorksV1Role? _roleFilter;
  int? _lastDirectoryRefreshRevision;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(
    AppUser user, {
    required bool yorksV1Provisioning,
    required YorksV1UserProjectAccess? projectAccess,
  }) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final searchable = [
      user.fullName,
      user.email,
      _roleLabel(user, yorksV1Provisioning: yorksV1Provisioning),
      for (final membership
          in projectAccess?.memberships ??
              const <YorksV1UserProjectMembership>[]) ...[
        membership.projectRef,
        membership.projectName,
      ],
    ].join(' ').toLowerCase();
    return searchable.contains(q);
  }

  bool _matchesMetric(
    AppUser user,
    YorksV1UserProjectAccessDirectory? directory,
  ) => switch (_metric) {
    _metricActive => user.active,
    _metricDeactivated => !user.active,
    _metricEngineers => _displayYorksV1Roles(
      user,
    ).any((role) => role.isEngineering),
    _metricUnassigned =>
      directory?.userFor(user.id)?.isUnassignedEngineer ?? false,
    _ => true,
  };

  Future<void> _refresh(YorksV1UserManagementAccess access) async {
    ref.invalidate(yorksV1UserProjectAccessProvider);
    try {
      await ref
          .read(usersProvider.notifier)
          .refreshFromServer(permissionConfirmed: access.canView);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyErr(error))));
      }
    }
  }

  void _openUser(String appUserId, YorksV1UserManagementAccess access) {
    final user = ref
        .read(usersProvider)
        .where((candidate) => candidate.id == appUserId)
        .firstOrNull;
    if (user == null || !access.canManageUser) return;
    _ManageUserSheet.show(context, user, access);
  }

  Future<void> _removeUserAccess(AppUser user) async {
    final connectedV1 =
        ref.read(yorksV1UserProvisioningEnabledProvider) &&
        ref.read(supabaseClientProvider) != null;
    final language = ref.read(languageProvider);
    if (yorksV1IsProtectedSelfTarget(
      connectedV1: connectedV1,
      currentAppUserId:
          ref
              .read(yorksV1CurrentPermissionSnapshotProvider)
              .snapshot
              ?.user
              .appUserId ??
          ref.read(currentUserProvider)?.id,
      targetAppUserId: user.id,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _permissionCopy(language, 'self_account_protected_body'),
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (connectedV1) {
      try {
        final options = await ref.read(
          yorksV1UserAdminOptionsProvider(user.id).future,
        );
        if (!options.canManageActivation) {
          throw StateError(
            _permissionCopy(language, 'admin_options_unavailable'),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_friendlyErr(error)),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: Text(
          _permissionCopy(
            language,
            connectedV1
                ? 'deactivate_account_title'
                : 'delete_local_user_title',
          ),
        ),
        content: Text(
          _permissionCopy(
            language,
            connectedV1 ? 'deactivate_account_body' : 'delete_local_user_body',
            name: user.fullName,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppStrings.cancel.active(language)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              _permissionCopy(
                language,
                connectedV1 ? 'deactivate_account' : 'delete_local_user',
              ),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final changed = connectedV1
          ? await ref
                .read(usersProvider.notifier)
                .setActive(user.id, false, idempotencyKey: const Uuid().v4())
          : await ref
                .read(usersProvider.notifier)
                .deleteUser(user.id, idempotencyKey: const Uuid().v4());
      if (!changed) {
        throw StateError(
          _permissionCopy(language, 'last_admin_deactivation_error'),
        );
      }
      await ref.logAudit(
        action: connectedV1 ? 'User deactivated' : 'Local user deleted',
        module: AuditModule.platform,
        refId: user.id,
        detail: connectedV1
            ? '${user.fullName} · account access removed; history retained'
            : '${user.fullName} · local development roster only',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _permissionCopy(
                language,
                connectedV1
                    ? 'deactivate_account_success'
                    : 'delete_local_user_success',
                name: user.fullName,
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyErr(error)),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final yorksV1Provisioning = ref.watch(
      yorksV1UserProvisioningEnabledProvider,
    );
    final connectedV1 =
        yorksV1Provisioning && ref.watch(supabaseClientProvider) != null;
    final permissionState = ref.watch(yorksV1CurrentPermissionSnapshotProvider);
    final access = YorksV1UserManagementAccess.resolve(
      connectedV1: connectedV1,
      role: ref.watch(yorksV1CurrentRoleProvider),
      permissionState: permissionState,
    );
    if (!access.canView) {
      return _UserDirectoryAccessGate(
        loading: permissionState.isInitialLoading,
        onRetry: () => ref
            .read(yorksV1CurrentPermissionSnapshotProvider.notifier)
            .refresh(),
      );
    }

    final revision = permissionState.snapshot?.revision;
    if (connectedV1 &&
        revision != null &&
        _lastDirectoryRefreshRevision != revision) {
      _lastDirectoryRefreshRevision = revision;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        try {
          await ref
              .read(usersProvider.notifier)
              .refreshFromServer(permissionConfirmed: access.canView);
        } catch (_) {
          // Keep the last confirmed directory. The explicit Refresh action
          // remains available for a transient protected-directory failure.
        }
      });
    }

    final all = ref.watch(usersProvider);
    final projectAccessState = ref.watch(yorksV1UserProjectAccessProvider);
    final directory = projectAccessState.valueOrNull;
    final projectAccessLoading = projectAccessState.isLoading;
    final names = {for (final user in all) user.id: user.fullName};
    final roleLabels = {
      for (final user in all)
        user.id: _roleTitleLabel(
          user,
          yorksV1Provisioning: yorksV1Provisioning,
          language: language,
        ),
    };
    final currentAppUserId =
        permissionState.snapshot?.user.appUserId ??
        ref.watch(currentUserProvider)?.id;

    final users =
        all
            .where(
              (user) =>
                  _matchesMetric(user, directory) &&
                  (_roleFilter == null ||
                      _displayYorksV1Roles(user).contains(_roleFilter)) &&
                  _matches(
                    user,
                    yorksV1Provisioning: yorksV1Provisioning,
                    projectAccess: directory?.userFor(user.id),
                  ),
            )
            .toList()
          ..sort((left, right) {
            if (left.active != right.active) return left.active ? -1 : 1;
            return left.fullName.toLowerCase().compareTo(
              right.fullName.toLowerCase(),
            );
          });

    final activeUsers = all.where((user) => user.active).length;
    final engineers = all
        .where(
          (user) =>
              _displayYorksV1Roles(user).any((role) => role.isEngineering),
        )
        .length;
    final unassigned = directory == null
        ? null
        : all
              .where(
                (user) =>
                    directory.userFor(user.id)?.isUnassignedEngineer ?? false,
              )
              .length;
    final deactivated = all.length - activeUsers;
    final metrics = [
      YorksV1UserMetric(
        id: _metricAll,
        label: YorksV1UserManagementStrings.totalAccounts,
        hint: YorksV1UserManagementStrings.allRolesHint,
        value: '${all.length}',
        icon: Icons.people_alt_outlined,
        foreground: AppColors.blue,
        background: AppColors.blueContainer,
      ),
      YorksV1UserMetric(
        id: _metricActive,
        label: YorksV1UserManagementStrings.activeMetric,
        hint: YorksV1UserManagementStrings.canSignIn,
        value: '$activeUsers',
        icon: Icons.verified_user_outlined,
        foreground: AppColors.success,
        background: AppColors.successContainer,
      ),
      YorksV1UserMetric(
        id: _metricEngineers,
        label: YorksV1UserManagementStrings.engineersMetric,
        hint: YorksV1UserManagementStrings.engineersHint,
        value: '$engineers',
        icon: Icons.engineering_outlined,
        foreground: AppColors.purple,
        background: AppColors.purpleContainer,
      ),
      YorksV1UserMetric(
        id: _metricUnassigned,
        label: YorksV1UserManagementStrings.notOnProjectMetric,
        hint: YorksV1UserManagementStrings.notOnProjectHint,
        value: unassigned == null ? '—' : '$unassigned',
        icon: Icons.person_search_outlined,
        foreground: AppColors.warning,
        background: AppColors.warningContainer,
      ),
      YorksV1UserMetric(
        id: _metricProjects,
        label: YorksV1UserManagementStrings.projectsStaffedMetric,
        hint: YorksV1UserManagementStrings.projectsStaffedHint,
        value: directory == null
            ? '—'
            : '${directory.staffedOpenProjectCount}/${directory.openProjectCount}',
        icon: Icons.account_tree_outlined,
        foreground: AppColors.blue,
        background: AppColors.blueContainer,
      ),
      YorksV1UserMetric(
        id: _metricDeactivated,
        label: YorksV1UserManagementStrings.deactivatedMetric,
        hint: YorksV1UserManagementStrings.historyRetained,
        value: '$deactivated',
        icon: Icons.person_off_outlined,
        foreground: AppColors.neutralText,
        background: AppColors.neutralContainer,
      ),
    ];
    final tab =
        _tab == YorksV1UserManagementTab.accessHistory && !access.canViewAudit
        ? YorksV1UserManagementTab.users
        : _tab;
    final compact =
        MediaQuery.sizeOf(context).width < AppSpacing.compactBreakpoint;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Directionality(
          textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: RefreshIndicator(
            onRefresh: () => _refresh(access),
            child: ListView(
              key: const ValueKey('user-management'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                compact ? AppSpacing.md : AppSpacing.xl,
                compact ? AppSpacing.md : AppSpacing.lg,
                compact ? AppSpacing.md : AppSpacing.xxl,
                AppSpacing.xxxl,
              ),
              children: [
                YorksV1UserManagementHeader(
                  language: language,
                  onCreate: access.canCreate
                      ? () => _AddUserSheet.show(context)
                      : null,
                  onRefresh: () => _refresh(access),
                ),
                const SizedBox(height: AppSpacing.lg),
                YorksV1UserMetricsGrid(
                  metrics: metrics,
                  language: language,
                  selectedId: tab == YorksV1UserManagementTab.projectAccess
                      ? _metricProjects
                      : _metric,
                  onSelected: (id) => setState(() {
                    if (id == _metricProjects) {
                      _tab = YorksV1UserManagementTab.projectAccess;
                      return;
                    }
                    _tab = YorksV1UserManagementTab.users;
                    _metric = _metric == id ? _metricAll : id;
                  }),
                ),
                const SizedBox(height: AppSpacing.lg),
                YorksV1UserManagementTabs(
                  language: language,
                  selected: tab,
                  showAccessHistory: access.canViewAudit,
                  onChanged: (value) => setState(() => _tab = value),
                ),
                const SizedBox(height: AppSpacing.md),
                switch (tab) {
                  YorksV1UserManagementTab.users => _UsersPanel(
                    users: users,
                    allUsersEmpty: all.isEmpty,
                    directory: directory,
                    projectAccessLoading: projectAccessLoading,
                    projectAccessFailed: projectAccessState.hasError,
                    onRetryProjectAccess: () =>
                        ref.invalidate(yorksV1UserProjectAccessProvider),
                    language: language,
                    yorksV1Provisioning: yorksV1Provisioning,
                    access: access,
                    currentAppUserId: currentAppUserId,
                    queryController: _searchController,
                    onQueryChanged: (query) => setState(() => _query = query),
                    roleFilter: _roleFilter,
                    onRoleFilterChanged: (role) =>
                        setState(() => _roleFilter = role),
                    onOpen: (user) =>
                        _ManageUserSheet.show(context, user, access),
                    onDelete: _removeUserAccess,
                  ),
                  YorksV1UserManagementTab.projectAccess =>
                    YorksV1ProjectTeamsPanel(
                      language: language,
                      names: names,
                      roleLabels: roleLabels,
                      onOpenUser: (appUserId) => _openUser(appUserId, access),
                    ),
                  YorksV1UserManagementTab.accessHistory => _AccessHistoryPanel(
                    entries: ref.watch(auditLogProvider),
                    language: language,
                  ),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The user directory: search, role filter, then a table on desktop and
/// cards on narrow screens.
class _UsersPanel extends StatelessWidget {
  const _UsersPanel({
    required this.users,
    required this.allUsersEmpty,
    required this.directory,
    required this.projectAccessLoading,
    required this.projectAccessFailed,
    required this.onRetryProjectAccess,
    required this.language,
    required this.yorksV1Provisioning,
    required this.access,
    required this.currentAppUserId,
    required this.queryController,
    required this.onQueryChanged,
    required this.roleFilter,
    required this.onRoleFilterChanged,
    required this.onOpen,
    required this.onDelete,
  });

  final List<AppUser> users;
  final bool allUsersEmpty;
  final YorksV1UserProjectAccessDirectory? directory;
  final bool projectAccessLoading;
  final bool projectAccessFailed;
  final VoidCallback onRetryProjectAccess;
  final AppLanguage language;
  final bool yorksV1Provisioning;
  final YorksV1UserManagementAccess access;
  final String? currentAppUserId;
  final TextEditingController queryController;
  final ValueChanged<String> onQueryChanged;
  final YorksV1Role? roleFilter;
  final ValueChanged<YorksV1Role?> onRoleFilterChanged;
  final ValueChanged<AppUser> onOpen;
  final ValueChanged<AppUser> onDelete;

  @override
  Widget build(BuildContext context) {
    final showCommercial = directory?.commercialVisible ?? false;
    return LedgerCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final search = TextField(
                  key: const ValueKey('user-management-search'),
                  controller: queryController,
                  onChanged: onQueryChanged,
                  decoration: InputDecoration(
                    hintText: YorksV1UserManagementStrings.searchUsers.active(
                      language,
                    ),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: queryController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: YorksV1UserManagementStrings.clearSearch
                                .active(language),
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              queryController.clear();
                              onQueryChanged('');
                            },
                          ),
                  ),
                );
                final roleField = DropdownButtonFormField<YorksV1Role?>(
                  key: ValueKey('user-management-role-${roleFilter?.name}'),
                  initialValue: roleFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  items: [
                    DropdownMenuItem<YorksV1Role?>(
                      value: null,
                      child: Text(
                        YorksV1UserManagementStrings.allRoles.active(language),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    for (final role in YorksV1Role.values)
                      DropdownMenuItem<YorksV1Role?>(
                        value: role,
                        child: Text(
                          _yorksV1RoleText(role).active(language),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: onRoleFilterChanged,
                );
                if (constraints.maxWidth < 720) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      search,
                      if (yorksV1Provisioning) ...[
                        const SizedBox(height: AppSpacing.sm),
                        roleField,
                      ],
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: search),
                    if (yorksV1Provisioning) ...[
                      const SizedBox(width: AppSpacing.md),
                      SizedBox(width: 260, child: roleField),
                    ],
                  ],
                );
              },
            ),
          ),
          if (projectAccessFailed)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.cloud_off_outlined,
                    color: AppColors.muted,
                    size: 18,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: YorksV1ActiveText(
                      copy:
                          YorksV1UserManagementStrings.projectAccessUnavailable,
                      language: language,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onRetryProjectAccess,
                    child: YorksV1ActiveText(
                      copy: YorksV1UserManagementStrings.retry,
                      language: language,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1, color: AppColors.line),
          if (users.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
              child: Column(
                children: [
                  Icon(
                    allUsersEmpty
                        ? Icons.person_add_alt_outlined
                        : Icons.search_off_rounded,
                    size: 36,
                    color: AppColors.muted,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  YorksV1ActiveText(
                    copy: allUsersEmpty
                        ? YorksV1UserManagementStrings.noUsersYet
                        : YorksV1UserManagementStrings.noMatchingUsers,
                    language: language,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final table = constraints.maxWidth >= 960;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (table)
                      _UserTableHeader(
                        language: language,
                        showCommercial: showCommercial,
                      ),
                    for (var i = 0; i < users.length; i++)
                      table
                          ? _UserTableRow(
                              user: users[i],
                              projectAccess: directory?.userFor(users[i].id),
                              projectAccessLoading: projectAccessLoading,
                              showCommercial: showCommercial,
                              isCurrentUser: _isSelf(users[i]),
                              language: language,
                              yorksV1Provisioning: yorksV1Provisioning,
                              access: access,
                              onOpen: onOpen,
                              onDelete: onDelete,
                            )
                          : Padding(
                              padding: EdgeInsets.fromLTRB(
                                AppSpacing.md,
                                i == 0 ? AppSpacing.md : 0,
                                AppSpacing.md,
                                AppSpacing.sm,
                              ),
                              child: _UserCard(
                                user: users[i],
                                projectAccess: directory?.userFor(users[i].id),
                                projectAccessLoading: projectAccessLoading,
                                showCommercial: showCommercial,
                                isCurrentUser: _isSelf(users[i]),
                                language: language,
                                yorksV1Provisioning: yorksV1Provisioning,
                                access: access,
                                onOpen: onOpen,
                                onDelete: onDelete,
                              ),
                            ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  bool _isSelf(AppUser user) => yorksV1IsProtectedSelfTarget(
    connectedV1: access.connectedV1,
    currentAppUserId: currentAppUserId,
    targetAppUserId: user.id,
  );
}

class _UserTableHeader extends StatelessWidget {
  const _UserTableHeader({
    required this.language,
    required this.showCommercial,
  });

  final AppLanguage language;
  final bool showCommercial;

  @override
  Widget build(BuildContext context) {
    Widget label(TranslatableString copy) => Text(
      copy.active(language).toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.labelSmall.copyWith(
        color: AppColors.muted,
        fontWeight: FontWeight.w800,
        letterSpacing: .6,
      ),
    );
    return Container(
      color: AppColors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: label(YorksV1UserManagementStrings.userColumn),
          ),
          Expanded(
            flex: 3,
            child: label(YorksV1UserManagementStrings.roleColumn),
          ),
          Expanded(
            flex: 4,
            child: label(YorksV1UserManagementStrings.projectAccessColumn),
          ),
          if (showCommercial)
            Expanded(
              flex: 2,
              child: label(YorksV1UserManagementStrings.commercialColumn),
            ),
          Expanded(
            flex: 2,
            child: label(YorksV1UserManagementStrings.lastActiveColumn),
          ),
          Expanded(
            flex: 2,
            child: label(YorksV1UserManagementStrings.statusColumn),
          ),
          const SizedBox(width: _actionsWidth),
        ],
      ),
    );
  }
}

const double _actionsWidth = 112;

class _UserTableRow extends StatelessWidget {
  const _UserTableRow({
    required this.user,
    required this.projectAccess,
    required this.projectAccessLoading,
    required this.showCommercial,
    required this.isCurrentUser,
    required this.language,
    required this.yorksV1Provisioning,
    required this.access,
    required this.onOpen,
    required this.onDelete,
  });

  final AppUser user;
  final YorksV1UserProjectAccess? projectAccess;
  final bool projectAccessLoading;
  final bool showCommercial;
  final bool isCurrentUser;
  final AppLanguage language;
  final bool yorksV1Provisioning;
  final YorksV1UserManagementAccess access;
  final ValueChanged<AppUser> onOpen;
  final ValueChanged<AppUser> onDelete;

  @override
  Widget build(BuildContext context) => Material(
    color: user.active
        ? AppColors.surfaceContainerLowest
        : AppColors.surfaceContainerLow.withValues(alpha: .6),
    child: InkWell(
      key: Key('user-row-${user.id}'),
      onTap: access.canManageUser ? () => onOpen(user) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: _UserIdentity(
                user: user,
                isCurrentUser: isCurrentUser,
                language: language,
              ),
            ),
            Expanded(
              flex: 3,
              child: _RoleCell(
                user: user,
                yorksV1Provisioning: yorksV1Provisioning,
                language: language,
              ),
            ),
            Expanded(
              flex: 4,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: YorksV1ProjectAccessSummary(
                  access: projectAccess,
                  loading: projectAccessLoading,
                  language: language,
                ),
              ),
            ),
            if (showCommercial)
              Expanded(
                flex: 2,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: YorksV1CommercialSummaryPill(
                    summary: projectAccess?.commercial,
                    language: language,
                  ),
                ),
              ),
            Expanded(
              flex: 2,
              child: Text(
                projectAccess == null
                    ? '—'
                    : yorksV1LastSignInLabel(
                        projectAccess!.lastSignInAt,
                        language,
                      ),
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.inkSecondary,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: _StatusPill(active: user.active, language: language),
              ),
            ),
            SizedBox(
              width: _actionsWidth,
              child: _RowActions(
                user: user,
                isCurrentUser: isCurrentUser,
                language: language,
                yorksV1Provisioning: yorksV1Provisioning,
                access: access,
                onOpen: onOpen,
                onDelete: onDelete,
                iconOnly: true,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.projectAccess,
    required this.projectAccessLoading,
    required this.showCommercial,
    required this.isCurrentUser,
    required this.language,
    required this.yorksV1Provisioning,
    required this.access,
    required this.onOpen,
    required this.onDelete,
  });

  final AppUser user;
  final YorksV1UserProjectAccess? projectAccess;
  final bool projectAccessLoading;
  final bool showCommercial;
  final bool isCurrentUser;
  final AppLanguage language;
  final bool yorksV1Provisioning;
  final YorksV1UserManagementAccess access;
  final ValueChanged<AppUser> onOpen;
  final ValueChanged<AppUser> onDelete;

  @override
  Widget build(BuildContext context) => Semantics(
    button: access.canManageUser,
    label:
        '${user.fullName}, ${_roleLabel(user, yorksV1Provisioning: yorksV1Provisioning)}',
    child: Material(
      color: AppColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: InkWell(
        key: Key('user-card-${user.id}'),
        onTap: access.canManageUser ? () => onOpen(user) : null,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _UserIdentity(
                      user: user,
                      isCurrentUser: isCurrentUser,
                      language: language,
                    ),
                  ),
                  if (access.canManageUser)
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.muted,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 52),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RoleCell(
                      user: user,
                      yorksV1Provisioning: yorksV1Provisioning,
                      language: language,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _StatusPill(active: user.active, language: language),
                        if (showCommercial)
                          YorksV1CommercialSummaryPill(
                            summary: projectAccess?.commercial,
                            language: language,
                          ),
                        if (projectAccess != null)
                          Text(
                            '${YorksV1UserManagementStrings.lastActiveColumn.active(language)}: ${yorksV1LastSignInLabel(projectAccess!.lastSignInAt, language)}',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    YorksV1ProjectAccessSummary(
                      access: projectAccess,
                      loading: projectAccessLoading,
                      language: language,
                      maxChips: 4,
                    ),
                  ],
                ),
              ),
              if ((yorksV1Provisioning && access.canViewPermissions) ||
                  (!access.connectedV1 &&
                      user.active &&
                      access.canManageActivation &&
                      !isCurrentUser)) ...[
                const SizedBox(height: AppSpacing.sm),
                const Divider(height: 1, color: AppColors.line),
                const SizedBox(height: AppSpacing.xs),
                _RowActions(
                  user: user,
                  isCurrentUser: isCurrentUser,
                  language: language,
                  yorksV1Provisioning: yorksV1Provisioning,
                  access: access,
                  onOpen: onOpen,
                  onDelete: onDelete,
                  showEdit: false,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _UserIdentity extends StatelessWidget {
  const _UserIdentity({
    required this.user,
    required this.isCurrentUser,
    required this.language,
  });

  final AppUser user;
  final bool isCurrentUser;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      YorksV1UserInitials(name: user.fullName, muted: !user.active),
      const SizedBox(width: AppSpacing.md),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    user.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      color: user.active ? AppColors.ink : AppColors.muted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (isCurrentUser) ...[
                  const SizedBox(width: AppSpacing.xs),
                  YorksV1Pill(
                    label: YorksV1UserManagementStrings.youLabel.active(
                      language,
                    ),
                    tone: YorksV1PillTone.info,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              user.email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
            ),
          ],
        ),
      ),
    ],
  );
}

class _RoleCell extends StatelessWidget {
  const _RoleCell({
    required this.user,
    required this.yorksV1Provisioning,
    required this.language,
  });

  final AppUser user;
  final bool yorksV1Provisioning;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        _roleTitleLabel(
          user,
          yorksV1Provisioning: yorksV1Provisioning,
          language: language,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelLarge.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
        ),
      ),
      Text(
        _roleFamilyLabel(
          user,
          yorksV1Provisioning: yorksV1Provisioning,
          language: language,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
      ),
    ],
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active, required this.language});

  final bool active;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => YorksV1Pill(
    label:
        (active
                ? YorksV1UserManagementStrings.active
                : YorksV1UserManagementStrings.deactivated)
            .active(language),
    tone: active ? YorksV1PillTone.success : YorksV1PillTone.neutral,
    icon: active ? Icons.check_circle_outline_rounded : Icons.block_rounded,
  );
}

class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.user,
    required this.isCurrentUser,
    required this.language,
    required this.yorksV1Provisioning,
    required this.access,
    required this.onOpen,
    required this.onDelete,
    this.showEdit = true,
    this.iconOnly = false,
  });

  final AppUser user;
  final bool isCurrentUser;
  final AppLanguage language;
  final bool yorksV1Provisioning;
  final YorksV1UserManagementAccess access;
  final ValueChanged<AppUser> onOpen;
  final ValueChanged<AppUser> onDelete;
  final bool showEdit;

  /// The desktop table uses compact icon buttons; the whole row also opens
  /// the edit panel.
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final manageAccessLabel = YorksV1PermissionStrings.text(
      language,
      'manage_access',
    );
    final editLabel = YorksV1UserManagementStrings.edit.active(language);
    void openAccess() => context.go(RoutePaths.yorksV1UserAccessPath(user.id));
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        if (yorksV1Provisioning && access.canViewPermissions)
          iconOnly
              ? IconButton.outlined(
                  key: Key('manage-access-${user.id}'),
                  tooltip: manageAccessLabel,
                  onPressed: openAccess,
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                )
              : OutlinedButton.icon(
                  key: Key('manage-access-${user.id}'),
                  onPressed: openAccess,
                  icon: const Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 17,
                  ),
                  label: Text(manageAccessLabel),
                ),
        if (showEdit && access.canManageUser)
          iconOnly
              ? IconButton.outlined(
                  key: Key('manage-user-${user.id}'),
                  tooltip: editLabel,
                  onPressed: () => onOpen(user),
                  icon: const Icon(Icons.edit_outlined),
                )
              : OutlinedButton.icon(
                  key: Key('manage-user-${user.id}'),
                  onPressed: () => onOpen(user),
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: Text(editLabel),
                ),
        if (!access.connectedV1 &&
            user.active &&
            access.canManageActivation &&
            !isCurrentUser)
          iconOnly
              ? IconButton(
                  key: Key('deactivate-user-${user.id}'),
                  tooltip: YorksV1PermissionStrings.text(
                    language,
                    'delete_local_user',
                  ),
                  onPressed: () => onDelete(user),
                  icon: const Icon(
                    Icons.person_remove_outlined,
                    color: AppColors.error,
                  ),
                )
              : TextButton(
                  key: Key('deactivate-user-${user.id}'),
                  onPressed: () => onDelete(user),
                  child: Text(
                    YorksV1PermissionStrings.text(
                      language,
                      'delete_local_user',
                    ),
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
      ],
    );
  }
}

class _AccessHistoryPanel extends StatelessWidget {
  const _AccessHistoryPanel({required this.entries, required this.language});

  final List<AuditEntry> entries;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final relevant = entries
        .where(
          (entry) =>
              entry.module == AuditModule.platform ||
              entry.action.toLowerCase().contains('access'),
        )
        .take(50)
        .toList();
    return LedgerCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                YorksV1ActiveText(
                  copy: YorksV1UserManagementStrings.accessHistory,
                  language: language,
                  style: AppTypography.titleLarge.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                YorksV1ActiveText(
                  copy: YorksV1UserManagementStrings.accessHistoryDescription,
                  language: language,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.line),
          if (relevant.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
              child: Column(
                children: [
                  const Icon(
                    Icons.history_rounded,
                    size: 36,
                    color: AppColors.muted,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  YorksV1ActiveText(
                    copy: YorksV1UserManagementStrings.noAccessHistory,
                    language: language,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            )
          else
            for (final entry in relevant)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.line)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.blueContainer,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusSm,
                        ),
                      ),
                      child: const Icon(
                        Icons.manage_accounts_outlined,
                        size: 19,
                        color: AppColors.blue,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.action,
                            style: AppTypography.labelLarge.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if ((entry.detail ?? '').isNotEmpty)
                            Text(
                              entry.detail!,
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.inkSecondary,
                              ),
                            ),
                          Text(
                            '${entry.actorName} · ${DateFormat('d MMM yyyy, HH:mm').format(entry.timestamp.toLocal())}',
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
        ],
      ),
    );
  }
}

class _UserDirectoryAccessGate extends ConsumerWidget {
  const _UserDirectoryAccessGate({
    required this.loading,
    required this.onRetry,
  });

  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    return Scaffold(
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
                    const CircularProgressIndicator()
                  else
                    const Icon(
                      Icons.admin_panel_settings_outlined,
                      size: 48,
                      color: AppColors.muted,
                    ),
                  const Gap(AppSpacing.lg),
                  Text(
                    YorksV1PermissionStrings.text(
                      language,
                      loading
                          ? 'directory_loading_title'
                          : 'directory_unavailable_title',
                    ),
                    key: const ValueKey('user-directory-access-state'),
                    textAlign: TextAlign.center,
                    style: AppTypography.titleMedium,
                  ),
                  if (!loading) ...[
                    const Gap(AppSpacing.sm),
                    Text(
                      YorksV1PermissionStrings.text(
                        language,
                        'directory_unavailable_body',
                      ),
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                    const Gap(AppSpacing.lg),
                    OutlinedButton.icon(
                      onPressed: onRetry,
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
}

@visibleForTesting
class YorksV1RoleAssignmentEditor extends StatelessWidget {
  const YorksV1RoleAssignmentEditor({
    required this.language,
    required this.primary,
    required this.availableRoles,
    required this.onPrimaryChanged,
    this.statusText,
  });

  final AppLanguage language;
  final YorksV1Role? primary;
  final List<YorksV1Role> availableRoles;
  final ValueChanged<YorksV1Role>? onPrimaryChanged;
  final String? statusText;

  @override
  Widget build(BuildContext context) {
    final selected = availableRoles.contains(primary) ? primary : null;
    final onChanged = availableRoles.isEmpty || onPrimaryChanged == null
        ? null
        : (YorksV1Role? role) {
            if (role != null) onPrimaryChanged!(role);
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          YorksV1PermissionStrings.text(language, 'role'),
          style: AppTypography.titleSmall,
        ),
        const Gap(AppSpacing.sm),
        DropdownButtonFormField<YorksV1Role>(
          key: const ValueKey('server-assignable-role-field'),
          initialValue: selected,
          isExpanded: true,
          decoration: InputDecoration(helperText: statusText),
          hint: Text(AppStrings.yorksV1RoleMappingRequired.active(language)),
          items: [
            for (final role in availableRoles)
              DropdownMenuItem(
                value: role,
                child: Text(_yorksV1RoleText(role).active(language)),
              ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ─── Add user ────────────────────────────────────────────────────
class _AddUserSheet extends ConsumerStatefulWidget {
  const _AddUserSheet();

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: AppColors.scrim.withValues(alpha: .38),
      builder: (dialogContext) {
        final viewport = MediaQuery.sizeOf(dialogContext);
        final phone = YorksMobileUi.isActive(dialogContext);
        return Dialog(
          alignment: phone ? Alignment.bottomCenter : Alignment.center,
          backgroundColor: AppColors.surfaceContainerLowest,
          insetPadding: phone
              ? const EdgeInsets.fromLTRB(8, 48, 8, 0)
              : const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          shape: RoundedRectangleBorder(
            borderRadius: phone
                ? const BorderRadius.vertical(
                    top: Radius.circular(AppSpacing.radiusXl),
                  )
                : BorderRadius.circular(AppSpacing.radiusXl),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 704,
              maxHeight: viewport.height * .92,
            ),
            child: const _AddUserSheet(),
          ),
        );
      },
    );
  }

  @override
  ConsumerState<_AddUserSheet> createState() => _AddUserSheetState();
}

class _AddUserSheetState extends ConsumerState<_AddUserSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  UserRole _legacyRole = UserRole.engineer;
  YorksV1Role _yorksV1Role = YorksV1Role.siteEngineer;
  bool _busy = false;
  String? _createCommandFingerprint;
  String? _createIdempotencyKey;
  String? _createAppUserId;

  ({String idempotencyKey, String appUserId}) _createCommandFor(
    String fingerprint,
  ) {
    if (_createCommandFingerprint != fingerprint) {
      _createCommandFingerprint = fingerprint;
      _createIdempotencyKey = const Uuid().v4();
      _createAppUserId = 'usr-${const Uuid().v4().substring(0, 8)}';
    }
    return (
      idempotencyKey: _createIdempotencyKey!,
      appUserId: _createAppUserId!,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final yorksV1Provisioning = ref.read(
      yorksV1UserProvisioningEnabledProvider,
    );
    final connectedV1 =
        yorksV1Provisioning && ref.read(supabaseClientProvider) != null;
    if (connectedV1) {
      final options = ref
          .read(yorksV1UserAdminOptionsProvider(null))
          .asData
          ?.value;
      if (options == null || !options.allowsRole(_yorksV1Role)) {
        final language = ref.read(languageProvider);
        AppFeedback.warning();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _permissionCopy(language, 'admin_options_unavailable'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    }
    setState(() => _busy = true);
    try {
      final fullName = _nameController.text.trim();
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      final command = _createCommandFor(
        [
          yorksV1Provisioning,
          fullName,
          email,
          password,
          yorksV1Provisioning ? _yorksV1Role.name : _legacyRole.name,
        ].join('\u0000'),
      );
      // When Supabase is configured this provisions the account in the identity
      // provider (via the admin-users function) before storing it locally; a
      // failure (e.g. duplicate email) throws and nothing is written.
      final users = ref.read(usersProvider.notifier);
      final user = yorksV1Provisioning
          ? await users.createYorksV1User(
              fullName: fullName,
              email: email,
              role: _yorksV1Role,
              password: password,
              idempotencyKey: command.idempotencyKey,
              appUserId: command.appUserId,
            )
          : await users.createUser(
              fullName: fullName,
              email: email,
              role: _legacyRole,
              password: password,
              idempotencyKey: command.idempotencyKey,
              appUserId: command.appUserId,
            );
      await ref.logAudit(
        action: 'User created',
        module: AuditModule.platform,
        refId: user.id,
        detail:
            '${user.fullName} · ${_roleLabel(user, yorksV1Provisioning: yorksV1Provisioning)}',
      );
      if (!mounted) return;
      // The app-level messenger outlives this sheet, so the success toast still
      // shows after we pop.
      final messenger = ScaffoldMessenger.of(context);
      AppFeedback.confirm();
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text('${user.fullName} added')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppFeedback.warning();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyErr(e)),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final language = ref.watch(languageProvider);
    final yorksV1Provisioning = ref.watch(
      yorksV1UserProvisioningEnabledProvider,
    );
    final connectedV1 =
        yorksV1Provisioning && ref.watch(supabaseClientProvider) != null;
    final adminOptionsState = connectedV1
        ? ref.watch(yorksV1UserAdminOptionsProvider(null))
        : null;
    final adminOptions = adminOptionsState?.asData?.value;
    final assignableRoles = connectedV1
        ? adminOptions?.assignableExactRoles ?? const <YorksV1Role>[]
        : YorksV1Role.values;
    final roleOptionsStatus = !connectedV1
        ? null
        : adminOptionsState!.isLoading
        ? _permissionCopy(language, 'admin_options_loading')
        : adminOptions == null
        ? _permissionCopy(language, 'admin_options_unavailable')
        : assignableRoles.isEmpty
        ? _permissionCopy(language, 'no_assignable_roles')
        : _permissionCopy(language, 'role_options_help');
    final canCreateWithRole =
        !yorksV1Provisioning ||
        !connectedV1 ||
        (adminOptions?.allowsRole(_yorksV1Role) ?? false);
    final access = YorksV1UserManagementAccess.resolve(
      connectedV1: connectedV1,
      role: ref.watch(yorksV1CurrentRoleProvider),
      permissionState: ref.watch(yorksV1CurrentPermissionSnapshotProvider),
    );
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            YorksV1ActiveText(
                              copy: YorksV1UserManagementStrings.createUser,
                              language: language,
                              style: AppTypography.headlineSmall.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Gap(AppSpacing.xxs),
                            YorksV1ActiveText(
                              copy: YorksV1UserManagementStrings
                                  .createUserDescription,
                              language: language,
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMd,
                          ),
                        ),
                        child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: AppSpacing.xxl),
                  const Gap(AppSpacing.lg),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stacked = constraints.maxWidth < 560;
                      final fields = [
                        LedgerTextField(
                          controller: _nameController,
                          label: 'Full Name',
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? AppStrings.fieldRequired.primary
                              : null,
                        ),
                        LedgerTextField(
                          controller: _emailController,
                          label: 'Email Address',
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) {
                            final t = (v ?? '').trim();
                            if (t.isEmpty) {
                              return AppStrings.fieldRequired.primary;
                            }
                            if (!t.contains('@')) {
                              return AppStrings.emailAddress.primary;
                            }
                            return null;
                          },
                        ),
                      ];
                      return stacked
                          ? Column(
                              children: [
                                fields[0],
                                const Gap(AppSpacing.lg),
                                fields[1],
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(child: fields[0]),
                                const Gap(AppSpacing.lg),
                                Expanded(child: fields[1]),
                              ],
                            );
                    },
                  ),
                  const Gap(AppSpacing.lg),
                  if (yorksV1Provisioning)
                    YorksV1RoleAssignmentEditor(
                      language: language,
                      primary: _yorksV1Role,
                      availableRoles: assignableRoles,
                      statusText: roleOptionsStatus,
                      onPrimaryChanged:
                          connectedV1 && adminOptions?.canAssignRole != true
                          ? null
                          : (role) => setState(() {
                              _yorksV1Role = role;
                            }),
                    )
                  else ...[
                    Text('Role', style: AppTypography.titleSmall),
                    const Gap(AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      children: [
                        for (final role in UserRole.values)
                          _RoleChip(
                            label: role.label,
                            selected: _legacyRole == role,
                            onTap: () => setState(() => _legacyRole = role),
                          ),
                      ],
                    ),
                  ],
                  const Gap(AppSpacing.lg),
                  LedgerTextField(
                    controller: _passwordController,
                    label: AppStrings.initialPassword.primary,
                    obscureText: true,
                    validator: (v) => (v ?? '').trim().length < 6
                        ? AppStrings.passwordTooShort.primary
                        : null,
                  ),
                  const Gap(AppSpacing.xxl),
                  PrimaryButton(
                    label: AppStrings.createUser.primary,
                    icon: Icons.check_rounded,
                    isLoading: _busy,
                    isExpanded: true,
                    onPressed: _busy || !access.canCreate || !canCreateWithRole
                        ? null
                        : _save,
                  ),
                  const Gap(AppSpacing.md),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Manage user ─────────────────────────────────────────────────
class _ManageUserSheet extends ConsumerStatefulWidget {
  const _ManageUserSheet({required this.userId, required this.access});
  final String userId;
  final YorksV1UserManagementAccess access;

  static Future<void> show(
    BuildContext context,
    AppUser user,
    YorksV1UserManagementAccess access,
  ) {
    return showDialog<void>(
      context: context,
      barrierColor: AppColors.scrim.withValues(alpha: .38),
      builder: (dialogContext) {
        final viewport = MediaQuery.sizeOf(dialogContext);
        // Desktop: a full-height side panel next to the directory. Narrow
        // screens: a tall bottom sheet.
        final side = viewport.width >= 900;
        return Dialog(
          alignment: side
              ? AlignmentDirectional.centerEnd
              : Alignment.bottomCenter,
          backgroundColor: AppColors.surface,
          insetPadding: side
              ? const EdgeInsets.all(AppSpacing.md)
              : const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.huge,
                  AppSpacing.sm,
                  0,
                ),
          shape: RoundedRectangleBorder(
            borderRadius: side
                ? BorderRadius.circular(AppSpacing.radiusXl)
                : const BorderRadius.vertical(
                    top: Radius.circular(AppSpacing.radiusXl),
                  ),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: side ? 620 : viewport.width,
            height: side
                ? viewport.height - AppSpacing.md * 2
                : viewport.height * .92,
            child: _ManageUserSheet(userId: user.id, access: access),
          ),
        );
      },
    );
  }

  @override
  ConsumerState<_ManageUserSheet> createState() => _ManageUserSheetState();
}

class _ManageUserSheetState extends ConsumerState<_ManageUserSheet> {
  /// True while a remote (Edge-Function-backed) action is in flight. Disables
  /// the sheet's controls and shows a progress line so the admin gets clear
  /// system-status feedback and can't fire a second action mid-flight.
  bool _busy = false;
  final Map<String, String> _idempotencyKeys = {};
  String? _pendingResetPassword;

  String _idempotencyKeyFor(String command) =>
      _idempotencyKeys.putIfAbsent(command, () => const Uuid().v4());

  void _completeCommand(String command) {
    _idempotencyKeys.remove(command);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref
        .watch(usersProvider)
        .where((u) => u.id == widget.userId)
        .firstOrNull;
    if (user == null) return const SizedBox.shrink();
    final language = ref.watch(languageProvider);
    final yorksV1Provisioning = ref.watch(
      yorksV1UserProvisioningEnabledProvider,
    );
    final connectedV1 =
        yorksV1Provisioning && ref.watch(supabaseClientProvider) != null;
    final isCurrentUser = yorksV1IsProtectedSelfTarget(
      connectedV1: connectedV1,
      currentAppUserId:
          ref
              .watch(yorksV1CurrentPermissionSnapshotProvider)
              .snapshot
              ?.user
              .appUserId ??
          ref.watch(currentUserProvider)?.id,
      targetAppUserId: user.id,
    );
    final access = YorksV1UserManagementAccess.resolve(
      connectedV1: connectedV1,
      role: ref.watch(yorksV1CurrentRoleProvider),
      permissionState: ref.watch(yorksV1CurrentPermissionSnapshotProvider),
    );
    final adminOptionsState = connectedV1
        ? ref.watch(yorksV1UserAdminOptionsProvider(user.id))
        : null;
    final adminOptions = adminOptionsState?.asData?.value;
    final assignableRoles = connectedV1
        ? adminOptions?.assignableExactRoles ?? const <YorksV1Role>[]
        : YorksV1Role.values;
    final roleOptionsStatus = !connectedV1
        ? null
        : adminOptionsState!.isLoading
        ? _permissionCopy(language, 'admin_options_loading')
        : adminOptions == null
        ? _permissionCopy(language, 'admin_options_unavailable')
        : assignableRoles.isEmpty
        ? _permissionCopy(language, 'no_assignable_roles')
        : _permissionCopy(language, 'role_options_help');
    final canManageActivationForTarget =
        access.canManageActivation &&
        !isCurrentUser &&
        (!connectedV1 || adminOptions?.canManageActivation == true);
    final canAssignRolesForTarget =
        access.canAssignRoles &&
        !isCurrentUser &&
        (!connectedV1 || adminOptions?.canAssignRole == true);
    final canResetPasswordForTarget =
        access.canResetPassword &&
        !isCurrentUser &&
        (!connectedV1 || adminOptions?.canResetPassword == true);
    // The app-level messenger outlives this sheet, so success toasts shown after
    // Navigator.pop still appear.
    final messenger = ScaffoldMessenger.of(context);

    void warn(String msg) {
      AppFeedback.warning();
      messenger.showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.error),
      );
    }

    void success(String msg) {
      AppFeedback.confirm();
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    }

    /// Runs [body] under the busy guard: disables controls + shows the progress
    /// line while the remote call is in flight, and blocks concurrent actions.
    Future<void> run(Future<void> Function() body) async {
      if (_busy) return;
      setState(() => _busy = true);
      try {
        await body();
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    Future<void> toggleActive() => run(() async {
      if (!canManageActivationForTarget) {
        return warn(
          _permissionCopy(
            language,
            isCurrentUser
                ? 'self_account_protected_body'
                : 'admin_options_unavailable',
          ),
        );
      }
      final willActivate = !user.active;
      final command = 'set-active:${user.id}:$willActivate';
      try {
        final allowed = await ref
            .read(usersProvider.notifier)
            .setActive(
              user.id,
              willActivate,
              idempotencyKey: _idempotencyKeyFor(command),
            );
        if (!allowed) {
          return warn(
            _permissionCopy(language, 'last_admin_deactivation_error'),
          );
        }
        _completeCommand(command);
        if (connectedV1) {
          ref.invalidate(yorksV1UserAdminOptionsProvider(user.id));
        }
        await ref.logAudit(
          action: willActivate ? 'User reactivated' : 'User deactivated',
          module: AuditModule.platform,
          refId: user.id,
          detail: user.fullName,
        );
        success(
          _permissionCopy(
            language,
            willActivate ? 'account_reactivated' : 'account_deactivated',
          ),
        );
      } catch (e) {
        warn(_friendlyErr(e));
      }
    });

    Future<void> toggleAccess() => run(() async {
      final grant = !user.inventoryAccess;
      try {
        await ref
            .read(usersProvider.notifier)
            .setInventoryAccess(user.id, grant);
        await ref.logAudit(
          action: grant
              ? 'Inventory access granted'
              : 'Inventory access revoked',
          module: AuditModule.platform,
          refId: user.id,
          detail: user.fullName,
        );
        success(
          grant ? 'Inventory access granted' : 'Inventory access revoked',
        );
      } catch (e) {
        warn(_friendlyErr(e));
      }
    });

    Future<void> resetPassword() => run(() async {
      if (!canResetPasswordForTarget) {
        return warn(
          _permissionCopy(
            language,
            isCurrentUser
                ? 'self_account_protected_body'
                : 'admin_options_unavailable',
          ),
        );
      }
      // Capture the navigator up-front (before any await) — the sheet's own
      // context is about to be popped, so we drive the result dialog off the
      // (stable) navigator's context instead.
      final navigator = Navigator.of(context);
      // Set a temporary password the admin can share; the user must change it on
      // first sign-in. When Supabase is configured this resets the real Auth
      // credential via the admin-users function.
      final temp = _pendingResetPassword ??=
          'Temp${1000 + Random().nextInt(9000)}';
      final command = 'set-password:${user.id}:$temp';
      try {
        await ref
            .read(usersProvider.notifier)
            .setPassword(
              user.id,
              temp,
              temporary: true,
              idempotencyKey: _idempotencyKeyFor(command),
            );
      } catch (e) {
        return warn(_friendlyErr(e));
      }
      _pendingResetPassword = null;
      _completeCommand(command);
      await ref.logAudit(
        action: 'Password reset',
        module: AuditModule.platform,
        refId: user.id,
        detail: user.fullName,
      );
      if (!mounted) return;
      navigator.pop();
      showDialog<void>(
        context: navigator.context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          ),
          title: const Text('Temporary password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Share this with ${user.fullName}. They must change it on first '
                'sign-in:',
                style: AppTypography.bodyMedium,
              ),
              const Gap(AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        temp,
                        style: AppTypography.titleMedium.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy',
                      icon: const Icon(Icons.copy_rounded, size: 20),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: temp));
                        AppFeedback.confirm();
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Password copied')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppStrings.done.primary),
            ),
          ],
        ),
      );
    });

    Future<void> setLegacyRole(UserRole role) => run(() async {
      if (role == user.role) return;
      final command = 'set-role:${user.id}:${role.name}';
      try {
        final allowed = await ref
            .read(usersProvider.notifier)
            .setRole(
              user.id,
              role,
              idempotencyKey: _idempotencyKeyFor(command),
            );
        if (!allowed) return warn("Can't change the only active admin's role.");
        _completeCommand(command);
        await ref.logAudit(
          action: 'User role changed',
          module: AuditModule.platform,
          refId: user.id,
          detail: '${user.fullName} → ${role.label}',
        );
        success('Role changed to ${role.label}');
      } catch (e) {
        warn(_friendlyErr(e));
      }
    });

    Future<void> setYorksV1Role(YorksV1Role role) => run(() async {
      if (role == user.yorksV1RoleCache) return;
      if (!canAssignRolesForTarget ||
          (connectedV1 && adminOptions?.allowsRole(role) != true)) {
        return warn(_permissionCopy(language, 'admin_options_unavailable'));
      }
      final command = 'set-v1-role:${user.id}:${role.claimValue}';
      try {
        final allowed = await ref
            .read(usersProvider.notifier)
            .setYorksV1Role(
              user.id,
              role,
              idempotencyKey: _idempotencyKeyFor(command),
            );
        if (!allowed) return warn("Can't change the only active admin's role.");
        _completeCommand(command);
        if (connectedV1) {
          ref.invalidate(yorksV1UserAdminOptionsProvider(user.id));
        }
        final label = _yorksV1RoleText(role).primary;
        await ref.logAudit(
          action: 'User role changed',
          module: AuditModule.platform,
          refId: user.id,
          detail: '${user.fullName} → $label',
        );
        success('Role changed to $label');
      } catch (e) {
        warn(_friendlyErr(e));
      }
    });

    Future<void> setOverride(PermissionKey key, bool value) => run(() async {
      // Toggling back to the role default clears the override entirely.
      final next = value == user.roleDefaultFor(key) ? null : value;
      final command = 'set-override:${user.id}:${key.name}:$next';
      try {
        await ref
            .read(usersProvider.notifier)
            .setPermissionOverride(
              user.id,
              key,
              next,
              idempotencyKey: _idempotencyKeyFor(command),
            );
        _completeCommand(command);
        await ref.logAudit(
          action: 'Permission updated',
          module: AuditModule.platform,
          refId: user.id,
          detail: '${user.fullName} · $key = ${next ?? 'role default'}',
        );
        success('Permission updated');
      } catch (e) {
        warn(_friendlyErr(e));
      }
    });

    Future<void> setEmployee(String? employeeId) => run(() async {
      final allowed = await ref
          .read(usersProvider.notifier)
          .setEmployeeLink(user.id, employeeId);
      if (!allowed) {
        return warn('That employee is already linked to another user.');
      }
      await ref.logAudit(
        action: employeeId == null
            ? 'Employee link cleared'
            : 'Linked to employee',
        module: AuditModule.platform,
        refId: user.id,
        detail: '${user.fullName} → ${employeeId ?? 'none'}',
      );
      success(
        employeeId == null ? 'Employee link cleared' : 'Linked to employee',
      );
    });

    Future<void> pickEmployee() async {
      if (_busy) return;
      final employees = ref.read(employeesProvider);
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppSpacing.radiusXl),
            ),
          ),
          child: SafeArea(
            top: false,
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              children: [
                ListTile(
                  leading: const Icon(Icons.link_off_rounded),
                  title: const Text('Not linked'),
                  trailing: user.employeeId == null
                      ? const Icon(
                          Icons.check_rounded,
                          color: AppColors.primary,
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    setEmployee(null);
                  },
                ),
                for (final e in employees)
                  ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: Text(e.fullName),
                    subtitle: Text('${e.jobRole} · ${e.id}'),
                    trailing: user.employeeId == e.id
                        ? const Icon(
                            Icons.check_rounded,
                            color: AppColors.primary,
                          )
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      setEmployee(e.id);
                    },
                  ),
              ],
            ),
          ),
        ),
      );
    }

    Future<void> removeUserAccess() async {
      if (_busy) return;
      if (!canManageActivationForTarget) {
        warn(
          _permissionCopy(
            language,
            isCurrentUser
                ? 'self_account_protected_body'
                : 'admin_options_unavailable',
          ),
        );
        return;
      }
      final connectedV1 = access.connectedV1;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          ),
          title: Text(
            _permissionCopy(
              language,
              connectedV1
                  ? 'deactivate_account_title'
                  : 'delete_local_user_title',
            ),
          ),
          content: Text(
            _permissionCopy(
              language,
              connectedV1
                  ? 'deactivate_account_body'
                  : 'delete_local_user_body',
              name: user.fullName,
            ),
            style: AppTypography.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppStrings.cancel.primary),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                _permissionCopy(
                  language,
                  connectedV1 ? 'deactivate_account' : 'delete_local_user',
                ),
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await run(() async {
        final navigator = Navigator.of(context); // capture before await
        final bool changed;
        const active = false;
        final command = 'set-active:${user.id}:$active';
        try {
          changed = connectedV1
              ? await ref
                    .read(usersProvider.notifier)
                    .setActive(
                      user.id,
                      false,
                      idempotencyKey: _idempotencyKeyFor(command),
                    )
              : await ref
                    .read(usersProvider.notifier)
                    .deleteUser(
                      user.id,
                      idempotencyKey: _idempotencyKeyFor(command),
                    );
        } catch (e) {
          return warn(_friendlyErr(e));
        }
        if (!changed) {
          return warn(
            _permissionCopy(language, 'last_admin_deactivation_error'),
          );
        }
        _completeCommand(command);
        await ref.logAudit(
          action: connectedV1 ? 'User deactivated' : 'Local user deleted',
          module: AuditModule.platform,
          refId: user.id,
          detail: connectedV1
              ? '${user.fullName} · account access removed; history retained'
              : '${user.fullName} · local development roster only',
        );
        if (!mounted) return;
        navigator.pop();
        success(
          _permissionCopy(
            language,
            connectedV1
                ? 'deactivate_account_success'
                : 'delete_local_user_success',
            name: user.fullName,
          ),
        );
      });
    }

    final roleLabel = _roleTitleLabel(
      user,
      yorksV1Provisioning: yorksV1Provisioning,
      language: language,
    );
    final canOpenPermissions = yorksV1Provisioning && access.canViewPermissions;

    void navigateAway(String location) {
      final router = GoRouter.of(context);
      Navigator.pop(context);
      router.go(location);
    }

    final sections = <Widget>[
      YorksV1EditPanelSection(
        icon: Icons.badge_outlined,
        title: YorksV1UserManagementStrings.accountSection,
        subtitle: YorksV1UserManagementStrings.accountSectionHint,
        language: language,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile.adaptive(
              key: const ValueKey('manage-sheet-active'),
              contentPadding: EdgeInsets.zero,
              value: user.active,
              onChanged: _busy || !canManageActivationForTarget
                  ? null
                  : (_) => toggleActive(),
              title: YorksV1ActiveText(
                copy: YorksV1UserManagementStrings.accountActive,
                language: language,
                style: AppTypography.labelLarge.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                isCurrentUser
                    ? _permissionCopy(language, 'self_account_protected_body')
                    : YorksV1UserManagementStrings.accountActiveHint.active(
                        language,
                      ),
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ),
            if (!yorksV1Provisioning && user.role == UserRole.engineer)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: user.inventoryAccess,
                onChanged: _busy ? null : (_) => toggleAccess(),
                title: Text(
                  AppStrings.inventoryAccess.active(language),
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  AppStrings.inventoryAccessHint.active(language),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ),
            const Divider(height: AppSpacing.lg, color: AppColors.line),
            if (canAssignRolesForTarget && yorksV1Provisioning)
              YorksV1RoleAssignmentEditor(
                language: language,
                primary: user.yorksV1RoleCache,
                availableRoles: assignableRoles,
                statusText: roleOptionsStatus,
                onPrimaryChanged: _busy ? (_) {} : setYorksV1Role,
              )
            else if (canAssignRolesForTarget)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  YorksV1ActiveText(
                    copy: YorksV1UserManagementStrings.roleColumn,
                    language: language,
                    style: AppTypography.titleSmall,
                  ),
                  const Gap(AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final role in UserRole.values)
                        _RoleChip(
                          label: role.label,
                          selected: role == user.role,
                          onTap: _busy ? null : () => setLegacyRole(role),
                        ),
                    ],
                  ),
                ],
              )
            else
              Row(
                children: [
                  YorksV1ActiveText(
                    copy: YorksV1UserManagementStrings.roleColumn,
                    language: language,
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                  const Gap(AppSpacing.md),
                  Flexible(
                    child: YorksV1Pill(
                      label: roleLabel,
                      tone: YorksV1PillTone.info,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
      if (yorksV1Provisioning)
        YorksV1EditPanelSection(
          icon: Icons.account_tree_outlined,
          title: YorksV1UserManagementStrings.projectAccessSection,
          language: language,
          child: YorksV1UserProjectAccessSection(
            appUserId: user.id,
            roleLabel: roleLabel,
            language: language,
            onOpenProject: (projectId) =>
                navigateAway(RoutePaths.yorksV1ProjectPath(projectId)),
          ),
        ),
      // V1 commercial authority is deliberately not backed by the retained
      // local permission overrides. The child fetches a live, Admin-only
      // server projection and the Edge/DB command remains authoritative even
      // if this display cache is stale.
      if (access.canViewCommercialAccess &&
          yorksV1Provisioning &&
          user.yorksV1RoleCache != null)
        YorksV1EditPanelSection(
          icon: Icons.payments_outlined,
          title: YorksV1UserManagementStrings.commercialSection,
          subtitle: YorksV1ProjectStrings.commercialAccessDescription,
          language: language,
          child: _YorksV1CommercialAccessSection(
            appUserId: user.id,
            targetRole: user.yorksV1RoleCache!,
            canManage: access.canManageCommercialAccess,
            busy: _busy,
            runBusyCommand: run,
            onFailure: warn,
            onSuccess: success,
          ),
        ),
      if (access.canEditProfile)
        YorksV1EditPanelSection(
          icon: Icons.assignment_ind_outlined,
          title: YorksV1UserManagementStrings.hrSection,
          language: language,
          child: Builder(
            builder: (_) {
              final linked = ref
                  .watch(employeesProvider)
                  .where((e) => e.id == user.employeeId)
                  .firstOrNull;
              return Row(
                children: [
                  Icon(
                    linked == null
                        ? Icons.link_off_rounded
                        : Icons.badge_outlined,
                    color: linked == null ? AppColors.muted : AppColors.blue,
                  ),
                  const Gap(AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          linked?.fullName ??
                              YorksV1UserManagementStrings.hrNotLinked.active(
                                language,
                              ),
                          style: AppTypography.labelLarge.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          linked == null
                              ? YorksV1UserManagementStrings.hrNotLinkedHint
                                    .active(language)
                              : '${linked.jobRole} · ${linked.id}',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Gap(AppSpacing.sm),
                  OutlinedButton(
                    onPressed: _busy ? null : pickEmployee,
                    child: YorksV1ActiveText(
                      copy: linked == null
                          ? YorksV1UserManagementStrings.link
                          : YorksV1UserManagementStrings.change,
                      language: language,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      if (!yorksV1Provisioning && user.role != UserRole.admin)
        YorksV1EditPanelSection(
          icon: Icons.tune_rounded,
          title: YorksV1UserManagementStrings.legacyPermissionsSection,
          subtitle: YorksV1UserManagementStrings.legacyPermissionsHint,
          language: language,
          child: Column(
            children: [
              for (final (key, label) in _managedPermissions)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: user.effectiveFor(key),
                  onChanged: _busy ? null : (v) => setOverride(key, v),
                  title: Text(label, style: AppTypography.labelLarge),
                  subtitle: YorksV1ActiveText(
                    copy: user.overrideFor(key) == null
                        ? YorksV1UserManagementStrings.roleDefault
                        : YorksV1UserManagementStrings.customForUser,
                    language: language,
                    style: AppTypography.bodySmall.copyWith(
                      color: user.overrideFor(key) == null
                          ? AppColors.muted
                          : AppColors.blue,
                    ),
                  ),
                ),
            ],
          ),
        ),
      if (canResetPasswordForTarget || canOpenPermissions)
        YorksV1EditPanelSection(
          icon: Icons.lock_outline_rounded,
          title: YorksV1UserManagementStrings.securitySection,
          language: language,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (canResetPasswordForTarget)
                _PanelActionRow(
                  key: const ValueKey('manage-sheet-reset-password'),
                  icon: Icons.lock_reset_rounded,
                  title: AppStrings.resetPassword.active(language),
                  subtitle: YorksV1UserManagementStrings.resetPasswordHint
                      .active(language),
                  onTap: _busy ? null : resetPassword,
                ),
              if (canResetPasswordForTarget && canOpenPermissions)
                const Divider(height: AppSpacing.md, color: AppColors.line),
              if (canOpenPermissions)
                _PanelActionRow(
                  key: const ValueKey('manage-sheet-detailed-permissions'),
                  icon: Icons.admin_panel_settings_outlined,
                  title: YorksV1UserManagementStrings.detailedPermissions
                      .active(language),
                  subtitle: YorksV1UserManagementStrings.detailedPermissionsHint
                      .active(language),
                  onTap: () =>
                      navigateAway(RoutePaths.yorksV1UserAccessPath(user.id)),
                ),
            ],
          ),
        ),
      if (canManageActivationForTarget && user.active)
        YorksV1EditPanelSection(
          icon: Icons.person_off_outlined,
          title: YorksV1UserManagementStrings.accountRemovalSection,
          subtitle: YorksV1UserManagementStrings.accountRemovalHint,
          language: language,
          danger: true,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              key: const ValueKey('manage-sheet-deactivate-account'),
              onPressed: _busy ? null : removeUserAccess,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: BorderSide(color: AppColors.error.withValues(alpha: .5)),
              ),
              icon: const Icon(Icons.person_off_outlined),
              label: Text(
                _permissionCopy(
                  language,
                  access.connectedV1
                      ? 'deactivate_account'
                      : 'delete_local_user',
                ),
              ),
            ),
          ),
        ),
    ];

    return Material(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.surfaceContainerLowest,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                YorksV1UserInitials(
                  name: user.fullName,
                  size: 52,
                  muted: !user.active,
                ),
                const Gap(AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      YorksV1ActiveText(
                        copy: YorksV1UserManagementStrings.editUser,
                        language: language,
                        style: AppTypography.labelMedium.copyWith(
                          color: AppColors.blue,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        user.fullName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.titleLarge.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        user.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                      const Gap(AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          _StatusPill(active: user.active, language: language),
                          YorksV1Pill(
                            label: roleLabel,
                            tone: YorksV1PillTone.info,
                          ),
                          if (isCurrentUser)
                            YorksV1Pill(
                              label: YorksV1UserManagementStrings.youLabel
                                  .active(language),
                              tone: YorksV1PillTone.accent,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: YorksV1UserManagementStrings.close.active(language),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 2,
            child: _busy ? const LinearProgressIndicator(minHeight: 2) : null,
          ),
          const Divider(height: 1, color: AppColors.line),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: sections.length,
              separatorBuilder: (_, _) => const Gap(AppSpacing.md),
              itemBuilder: (_, index) => sections[index],
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelActionRow extends StatelessWidget {
  const _PanelActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, color: onTap == null ? AppColors.muted : AppColors.blue),
          const Gap(AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ],
      ),
    ),
  );
}

/// Connected, Admin-only V1 commercial capability controls.
///
/// This section renders only a small authorization projection. It never loads
/// a commercial material, cost, quotation or other protected business value.
class _YorksV1CommercialAccessSection extends ConsumerWidget {
  const _YorksV1CommercialAccessSection({
    required this.appUserId,
    required this.targetRole,
    required this.canManage,
    required this.busy,
    required this.runBusyCommand,
    required this.onFailure,
    required this.onSuccess,
  });

  final String appUserId;
  final YorksV1Role targetRole;
  final bool canManage;
  final bool busy;
  final _UserManagementBusyCommand runBusyCommand;
  final ValueChanged<String> onFailure;
  final ValueChanged<String> onSuccess;

  /// Product Decisions permit a reasoned Admin override for an Engineer's
  /// protected commercial *view*. `manage_commercials` remains unavailable to
  /// both engineering roles and is also enforced by the server command.
  bool _mayChange(YorksV1CommercialCapability capability) =>
      switch (capability) {
        YorksV1CommercialCapability.viewCommercials => true,
        YorksV1CommercialCapability.manageCommercials =>
          targetRole == YorksV1Role.procurement ||
              targetRole == YorksV1Role.admin,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final access = ref.watch(yorksV1CommercialCapabilitiesProvider(appUserId));

    return access.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: LinearProgressIndicator(minHeight: 2),
      ),
      error: (_, _) => Row(
        children: [
          Expanded(
            child: Text(
              YorksV1ProjectStrings.commercialAccessUnavailable.active(
                language,
              ),
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
          ),
          TextButton.icon(
            onPressed: busy
                ? null
                : () => ref.invalidate(
                    yorksV1CommercialCapabilitiesProvider(appUserId),
                  ),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(YorksV1ProjectStrings.retry.active(language)),
          ),
        ],
      ),
      data: (capabilities) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final capability in YorksV1CommercialCapability.values)
            _CommercialCapabilitySwitch(
              capability: capability,
              access: capabilities[capability],
              enabled: !busy && canManage && _mayChange(capability),
              onChanged: (granted) => _changeCapability(
                context,
                ref,
                capability: capability,
                granted: granted,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _changeCapability(
    BuildContext context,
    WidgetRef ref, {
    required YorksV1CommercialCapability capability,
    required bool granted,
  }) async {
    if (!canManage) return;
    final reason = await _askCommercialCapabilityReason(context);
    if (reason == null) return;

    await runBusyCommand(() async {
      try {
        await ref
            .read(yorksV1CommercialCapabilityRepositoryProvider)
            .setForAppUser(
              appUserId: appUserId,
              capability: capability,
              granted: granted,
              reason: reason,
              idempotencyKey: const Uuid().v4(),
            );
        ref.invalidate(yorksV1CommercialCapabilitiesProvider(appUserId));
        onSuccess(YorksV1ProjectStrings.accessUpdated.primary);
      } on YorksV1DomainException catch (error) {
        onFailure(YorksV1ProjectStrings.errorFor(error.code).primary);
      } catch (_) {
        onFailure(YorksV1ProjectStrings.commercialAccessUnavailable.primary);
      }
    });
  }

  Future<String?> _askCommercialCapabilityReason(BuildContext context) async {
    final controller = TextEditingController();
    String? validationError;
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: AppColors.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
            ),
            title: Text(
              YorksV1ProjectStrings.commercialAccessChangeReason.primary,
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                hintText:
                    YorksV1ProjectStrings.commercialAccessReasonHint.primary,
                errorText: validationError,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(YorksV1ProjectStrings.cancel.primary),
              ),
              FilledButton(
                onPressed: () {
                  final reason = controller.text.trim();
                  if (reason.isEmpty) {
                    setDialogState(
                      () => validationError = YorksV1ProjectStrings
                          .commercialAccessChangeReason
                          .primary,
                    );
                    return;
                  }
                  Navigator.pop(dialogContext, reason);
                },
                child: Text(YorksV1ProjectStrings.saveAccessChange.primary),
              ),
            ],
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }
}

class _CommercialCapabilitySwitch extends ConsumerWidget {
  const _CommercialCapabilitySwitch({
    required this.capability,
    required this.access,
    required this.enabled,
    required this.onChanged,
  });

  final YorksV1CommercialCapability capability;
  final YorksV1CommercialCapabilityAccess access;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final label = switch (capability) {
      YorksV1CommercialCapability.viewCommercials =>
        YorksV1ProjectStrings.viewCommercials,
      YorksV1CommercialCapability.manageCommercials =>
        YorksV1ProjectStrings.manageCommercials,
    };
    final source = access.usesRoleDefault
        ? YorksV1ProjectStrings.roleDefault
        : YorksV1ProjectStrings.customForUser;

    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: access.effective,
      onChanged: enabled ? onChanged : null,
      title: Text(
        label.active(language),
        style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        source.active(language),
        style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
      ),
      activeThumbColor: AppColors.primary,
    );
  }
}

// ─── Role chip ───────────────────────────────────────────────────
class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;

  /// Null → disabled (e.g. while a remote action is in flight).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null && !selected ? 0.5 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        child: AnimatedContainer(
          duration: Duration.zero,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary
                : AppColors.primaryContainer.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          ),
          child: Text(
            label,
            style: AppTypography.labelLarge.copyWith(
              color: selected ? AppColors.onPrimary : AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

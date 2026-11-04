import 'yorks_v1_domain_error.dart';
import 'yorks_v1_project.dart';
import 'yorks_v1_role.dart';

/// How an account reaches projects. Mirrors `v1_user_project_access_basis`.
enum YorksV1ProjectAccessBasis {
  /// Admin and the organisation-wide engineering roles read every project.
  allProjects('all_projects'),

  /// Procurement reads active and on-hold projects.
  activeProjects('active_projects'),

  /// Project and Site Engineers read only the projects they are assigned to.
  assigned('assigned'),

  /// The role has no structural project access (for example Accountant).
  none('none');

  const YorksV1ProjectAccessBasis(this.wireValue);

  final String wireValue;

  static YorksV1ProjectAccessBasis fromWireValue(Object? value) {
    for (final basis in values) {
      if (basis.wireValue == value) return basis;
    }
    return none;
  }
}

/// One dated project membership of one account.
class YorksV1UserProjectMembership {
  const YorksV1UserProjectMembership({
    required this.projectId,
    required this.projectRef,
    required this.projectName,
    required this.projectState,
    required this.role,
    required this.effectiveFrom,
  });

  final String projectId;
  final String projectRef;
  final String projectName;
  final YorksV1ProjectLifecycle? projectState;
  final YorksV1ProjectMembershipRole role;
  final DateTime effectiveFrom;

  factory YorksV1UserProjectMembership.fromRpcJson(Map<String, dynamic> json) {
    final role = YorksV1ProjectMembershipRole.fromWireValue(
      json['project_role'],
    );
    if (role == null) throw const FormatException('Unknown project role');
    return YorksV1UserProjectMembership(
      projectId: _required(json, 'project_id'),
      projectRef: _required(json, 'project_ref'),
      projectName: _text(json['project_name']),
      projectState: YorksV1ProjectLifecycle.fromWireValue(
        json['project_state'],
      ),
      role: role,
      effectiveFrom: _date(json['effective_from']),
    );
  }
}

/// Effective commercial access, visible to Admin only.
class YorksV1UserCommercialSummary {
  const YorksV1UserCommercialSummary({
    required this.canView,
    required this.canManage,
  });

  final bool canView;
  final bool canManage;
}

/// The project access projection for one account in User Management.
class YorksV1UserProjectAccess {
  const YorksV1UserProjectAccess({
    required this.appUserId,
    required this.exactRole,
    required this.basis,
    required this.isActive,
    required this.teamEligible,
    required this.projectCount,
    required this.memberships,
    this.lastSignInAt,
    this.commercial,
  });

  final String appUserId;
  final YorksV1Role? exactRole;
  final YorksV1ProjectAccessBasis basis;
  final bool isActive;

  /// True for active Project and Site Engineers, who join project teams.
  final bool teamEligible;

  /// Number of readable projects this account reaches, from the server.
  final int projectCount;
  final List<YorksV1UserProjectMembership> memberships;
  final DateTime? lastSignInAt;
  final YorksV1UserCommercialSummary? commercial;

  /// An engineer on no project at all: a staffing gap worth surfacing.
  bool get isUnassignedEngineer =>
      isActive &&
      basis == YorksV1ProjectAccessBasis.assigned &&
      memberships.isEmpty;

  YorksV1UserProjectMembership? membershipFor(String projectId) {
    for (final membership in memberships) {
      if (membership.projectId == projectId) return membership;
    }
    return null;
  }

  factory YorksV1UserProjectAccess.fromRpcJson(Map<String, dynamic> json) {
    final commercial = json['commercial'];
    return YorksV1UserProjectAccess(
      appUserId: _required(json, 'app_user_id'),
      exactRole: YorksV1Role.fromServerClaim(json['exact_role']),
      basis: YorksV1ProjectAccessBasis.fromWireValue(json['access_basis']),
      isActive: json['is_active'] == true,
      teamEligible: json['team_eligible'] == true,
      projectCount: _int(json['project_count']),
      memberships: [
        for (final item in _list(json['memberships']))
          YorksV1UserProjectMembership.fromRpcJson(item),
      ],
      lastSignInAt: _optionalDate(json['last_sign_in_at']),
      commercial: commercial is Map
          ? YorksV1UserCommercialSummary(
              canView: commercial['view'] == true,
              canManage: commercial['manage'] == true,
            )
          : null,
    );
  }
}

/// One member of a project team as shown in User Management.
class YorksV1ProjectTeamAccessMember {
  const YorksV1ProjectTeamAccessMember({
    required this.appUserId,
    required this.displayName,
    required this.role,
    required this.effectiveFrom,
    required this.isActive,
  });

  /// Null only for an identity the directory cannot map to an account.
  final String? appUserId;
  final String displayName;
  final YorksV1ProjectMembershipRole role;
  final DateTime effectiveFrom;
  final bool isActive;

  factory YorksV1ProjectTeamAccessMember.fromRpcJson(
    Map<String, dynamic> json,
  ) {
    final role = YorksV1ProjectMembershipRole.fromWireValue(
      json['project_role'],
    );
    if (role == null) throw const FormatException('Unknown project role');
    final appUserId = _text(json['app_user_id']);
    return YorksV1ProjectTeamAccessMember(
      appUserId: appUserId.isEmpty ? null : appUserId,
      displayName: _text(json['display_name']),
      role: role,
      effectiveFrom: _date(json['effective_from']),
      isActive: json['is_active'] == true,
    );
  }
}

/// One readable project and its current team.
class YorksV1ProjectTeamAccess {
  const YorksV1ProjectTeamAccess({
    required this.projectId,
    required this.projectRef,
    required this.projectName,
    required this.state,
    required this.recordVersion,
    required this.canManageTeam,
    required this.members,
  });

  final String projectId;
  final String projectRef;
  final String projectName;
  final YorksV1ProjectLifecycle? state;
  final int recordVersion;

  /// The caller may change this team now (authority and project state).
  final bool canManageTeam;
  final List<YorksV1ProjectTeamAccessMember> members;

  Iterable<YorksV1ProjectTeamAccessMember> get projectEngineers =>
      members.where(
        (member) => member.role == YorksV1ProjectMembershipRole.projectEngineer,
      );

  Iterable<YorksV1ProjectTeamAccessMember> get siteEngineers => members.where(
    (member) => member.role == YorksV1ProjectMembershipRole.siteEngineer,
  );

  /// Open projects are expected to have a Project Engineer.
  bool get isOpen =>
      state == YorksV1ProjectLifecycle.draft ||
      state == YorksV1ProjectLifecycle.active ||
      state == YorksV1ProjectLifecycle.onHold;

  bool get needsProjectEngineer => isOpen && projectEngineers.isEmpty;

  factory YorksV1ProjectTeamAccess.fromRpcJson(Map<String, dynamic> json) =>
      YorksV1ProjectTeamAccess(
        projectId: _required(json, 'project_id'),
        projectRef: _required(json, 'project_ref'),
        projectName: _text(json['project_name']),
        state: YorksV1ProjectLifecycle.fromWireValue(json['state']),
        recordVersion: _int(json['record_version']),
        canManageTeam: json['can_manage_team'] == true,
        members: [
          for (final item in _list(json['members']))
            YorksV1ProjectTeamAccessMember.fromRpcJson(item),
        ],
      );
}

/// The whole User Management project-access read.
class YorksV1UserProjectAccessDirectory {
  YorksV1UserProjectAccessDirectory({
    required this.generatedAt,
    required this.commercialVisible,
    required Iterable<YorksV1UserProjectAccess> users,
    required Iterable<YorksV1ProjectTeamAccess> projects,
  }) : users = {for (final user in users) user.appUserId: user},
       projects = List.unmodifiable(projects);

  final DateTime generatedAt;
  final bool commercialVisible;
  final Map<String, YorksV1UserProjectAccess> users;
  final List<YorksV1ProjectTeamAccess> projects;

  YorksV1UserProjectAccess? userFor(String appUserId) => users[appUserId];

  YorksV1ProjectTeamAccess? projectFor(String projectId) {
    for (final project in projects) {
      if (project.projectId == projectId) return project;
    }
    return null;
  }

  int get openProjectCount =>
      projects.where((project) => project.isOpen).length;

  int get staffedOpenProjectCount => projects
      .where((project) => project.isOpen && !project.needsProjectEngineer)
      .length;

  factory YorksV1UserProjectAccessDirectory.fromRpcJson(
    Map<String, dynamic> json,
  ) {
    try {
      return YorksV1UserProjectAccessDirectory(
        generatedAt: _date(json['generated_at']),
        commercialVisible: json['commercial_visible'] == true,
        users: [
          for (final item in _list(json['users']))
            YorksV1UserProjectAccess.fromRpcJson(item),
        ],
        projects: [
          for (final item in _list(json['projects']))
            YorksV1ProjectTeamAccess.fromRpcJson(item),
        ],
      );
    } on FormatException catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }
}

String _required(Map<String, dynamic> json, String key) {
  final value = _text(json[key]);
  if (value.isEmpty) throw FormatException('Missing $key');
  return value;
}

String _text(Object? value) => value is String ? value.trim() : '';

int _int(Object? value) => switch (value) {
  final int number => number,
  final num number => number.toInt(),
  final String text => int.tryParse(text) ?? 0,
  _ => 0,
};

DateTime _date(Object? value) {
  final parsed = _optionalDate(value);
  if (parsed == null) throw const FormatException('Invalid date');
  return parsed;
}

DateTime? _optionalDate(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;

List<Map<String, dynamic>> _list(Object? value) {
  if (value == null) return const [];
  if (value is! List) throw const FormatException('Expected a list');
  final rows = <Map<String, dynamic>>[];
  for (final item in value) {
    if (item is! Map) throw const FormatException('Expected an object');
    rows.add(Map<String, dynamic>.from(item));
  }
  return rows;
}

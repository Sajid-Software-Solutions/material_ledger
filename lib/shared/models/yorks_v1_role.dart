/// Exact, server-controlled Yorks V1 role claims.
///
/// This type deliberately does not convert from the legacy [UserRole] model.
/// A legacy `engineer` is not evidence of either V1 engineering role; V1
/// authority begins only after the server supplies one of these exact claims.
enum YorksV1Role {
  projectEngineer('project_engineer'),
  siteEngineer('site_engineer'),
  seniorMechanicalEngineer('senior_mechanical_engineer'),
  projectManager('project_manager'),
  workshopInCharge('workshop_in_charge'),
  documentController('document_controller'),
  accountant('accountant'),

  /// People and HR: users, worker records, Workforce and Rentals, with
  /// read-only Projects and Accounts. Never a technical project member.
  pr('pr'),
  procurement('procurement'),
  admin('admin');

  const YorksV1Role(this.claimValue);

  /// The exact value accepted from `auth.jwt() -> app_metadata.role`.
  final String claimValue;

  /// Parses only an exact server claim. In particular, this does not lowercase,
  /// normalize, or reinterpret legacy labels such as `engineer`.
  static YorksV1Role? fromServerClaim(Object? value) {
    if (value is! String) return null;
    for (final role in YorksV1Role.values) {
      if (role.claimValue == value) return role;
    }
    return null;
  }

  bool get canCreateProject => isEngineering || this == admin;

  /// V1 Material Request draft creation follows the same base-role boundary.
  /// The server additionally checks active project membership and project state
  /// for every save and submit command.
  bool get canCreateMaterialRequest => isEngineering || this == admin;

  /// Project material returns are raised by project stakeholders and remain
  /// server-scoped to active membership. Completed projects intentionally stay
  /// eligible so surplus can be reconciled during close-out.
  bool get canCreateMaterialReturn => isEngineering || this == admin;

  /// A base Site Engineer can hold a dated, project-specific Project Engineer
  /// membership. The client has no authoritative membership projection at this
  /// command boundary, so it must not reject that person before the trusted
  /// RPC checks their active project role. Procurement remains denied early.
  ///
  /// This is not a grant: `v1_can_manage_project` re-checks the exact role and
  /// active Project Engineer membership (or Admin override) under its lock.
  bool get canManageProjectMembers => isEngineering || this == admin;

  /// See [canManageProjectMembers]. Project-state authority likewise belongs
  /// to the server-side intersection of base role and dated membership.
  bool get canSetProjectState => isEngineering || this == admin;

  /// Roles that reach Workforce attendance and crew requests by role and
  /// project membership (PRODUCT_DECISIONS 37), as the server's
  /// `v1_wf_allowed` does. Admin and PR hold the Workforce keys instead.
  bool get reachesWorkforceByRole =>
      this == siteEngineer ||
      this == projectEngineer ||
      this == seniorMechanicalEngineer ||
      this == projectManager ||
      this == workshopInCharge ||
      this == documentController ||
      this == accountant;

  /// User Configuration is a separately approved organization-level control.
  /// It does not imply access to unrelated Admin screens or commercial data.
  bool get canConfigureUsers =>
      this == admin || this == seniorMechanicalEngineer || this == pr;

  /// These organization-wide roles share Project Engineer workflow authority.
  /// The trusted database maps each exact claim to
  /// Project Engineer workflow authority and grants project access without a
  /// dated per-project membership row.
  bool get isGlobalProjectEngineer =>
      this == seniorMechanicalEngineer ||
      this == projectManager ||
      this == workshopInCharge ||
      this == documentController;

  /// Stock mutations remain Procurement/Admin-only. The approved Senior
  /// Mechanical Engineer exception is a read-only warehouse workspace grant.
  bool get canBrowseInventory =>
      this == seniorMechanicalEngineer || this == procurement || this == admin;

  bool get canManageInventory => this == procurement || this == admin;

  bool get isEngineering =>
      this == projectEngineer ||
      this == siteEngineer ||
      isGlobalProjectEngineer;
}

/// Compatibility-shell roles retained while normalized Yorks modules are
/// rolled out. Exact Yorks authorization always uses `YorksV1Role` and the
/// protected server capability projection instead of these presentation
/// buckets.
///
/// Accountant is deliberately explicit and least-privilege. It is not folded
/// into Admin, Procurement or Engineer because doing so would grant unrelated
/// legacy module authority before the normalized Accounts feature is enabled.
enum UserRole {
  engineer('Engineer', 'انجینئر', 'इंजीनियर'),
  procurement('Procurement', 'پروکیورمنٹ', 'खरीद'),
  accountant('Accountant', 'اکاؤنٹنٹ', 'लेखाकार'),

  /// People and HR. Users, worker records, Workforce, People, leave and
  /// Rentals; read-only Projects and Accounts through exact capabilities.
  pr('PR', 'پی آر', 'पीआर'),
  admin('Admin', 'ایڈمن', 'एडमिन');

  const UserRole(this.label, this.labelUr, this.labelHi);

  final String label;
  final String labelUr;
  final String labelHi;

  static UserRole fromName(String name) => UserRole.values.firstWhere(
    (r) => r.name == name,
    orElse: () => UserRole.engineer,
  );

  // ─── Capabilities (mirror Security-Rules matrix, Appendix F/I) ───
  /// Commercial records are visible to Admin/Procurement by default.
  bool get canViewCommercials => this == admin || this == procurement;

  /// Transitional alias for existing presentation code.
  bool get canSeeCost => canViewCommercials;

  /// Employee salary & documents are visible to Admin only. (Procurement runs
  /// HR operations but not compensation — widen here if that changes.)
  bool get canSeeSalary => this == admin || this == pr;

  /// Admin has read-all across every module (and the owner signs in here).
  bool get isAdmin => this == admin;

  // Module access -------------------------------------------------------
  bool get canAccessMaterials => this != accountant && this != pr;
  bool get canAccessRentals =>
      this == procurement || this == admin || this == pr;
  bool get canAccessPeople =>
      this == procurement || this == admin || this == pr;

  // Write access --------------------------------------------------------
  bool get canWriteRentals =>
      this == procurement || this == admin || this == pr;
  bool get canWritePeople => this == procurement || this == admin || this == pr;

  /// Record goods receipts into the store (procurement & admin).
  bool get canReceiveGoods => this == procurement || this == admin;

  /// Approve/reject engineer leave requests (procurement & admin). Engineers
  /// request their own leave; they never approve.
  bool get canApproveLeave =>
      this == procurement || this == admin || this == pr;

  /// View the retired legacy finance/cost roll-up screen. Normalized Accounts
  /// uses exact server capabilities and never derives access from this getter.
  bool get canViewFinance => this == admin;

  /// True for the office/web roles that use the multi-module admin panel.
  bool get usesAdminPanel => this != engineer;
}

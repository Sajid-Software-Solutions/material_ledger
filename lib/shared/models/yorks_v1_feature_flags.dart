/// Compile-time rollout controls for the Yorks V1 R35 experience.
///
/// Constructor values represent requested deployment settings. Public getters
/// expose only effective settings: every downstream feature also requires all
/// preceding features in the approved dependency chain. This keeps a partial
/// or inconsistent deployment fail-closed.
///
/// These flags are intentionally separate from `NexusFeatureFlags`. Legacy V7
/// deployment settings do not enable Yorks V1 behavior.
class YorksV1FeatureFlags {
  const YorksV1FeatureFlags({
    bool foundation = false,
    bool projects = false,
    bool projectSetup = false,
    bool boq = false,
    bool excel = false,
    bool requests = false,
    bool arrangement = false,
    bool legacyArrangementReview = false,
    bool logistics = false,
    bool returnsDocuments = false,
    bool documents = false,
    bool accounts = false,
    bool accountsWorkspaceV2 = false,
    bool workforce = false,
    // Retired: accepted for compatibility and ignored. See [analytics].
    // ignore: avoid_unused_constructor_parameters
    bool analytics = false,
    bool teamChat = false,
    bool inventorySuppliers = false,
    bool companyMaterialRequests = false,
    bool roleOverviewV2 = false,
    bool workerRecords = false,
    bool workforceAttendanceV2 = false,
  }) : _foundation = foundation,
       _projects = projects,
       _projectSetup = projectSetup,
       _boq = boq,
       _excel = excel,
       _requests = requests,
       _arrangement = arrangement,
       _legacyArrangementReview = legacyArrangementReview,
       _logistics = logistics,
       _returnsDocuments = returnsDocuments,
       _documents = documents,
       _accounts = accounts,
       _accountsWorkspaceV2 = accountsWorkspaceV2,
       _workforce = workforce,
       _teamChat = teamChat,
       _inventorySuppliers = inventorySuppliers,
       _companyMaterialRequests = companyMaterialRequests,
       _roleOverviewV2 = roleOverviewV2,
       _workerRecords = workerRecords,
       _workforceAttendanceV2 = workforceAttendanceV2;

  const YorksV1FeatureFlags.fromEnvironment()
    : _foundation = const bool.fromEnvironment(
        'YORKS_V1_FOUNDATION',
        defaultValue: true,
      ),
      _projects = const bool.fromEnvironment(
        'YORKS_V1_PROJECTS',
        defaultValue: true,
      ),
      _projectSetup = const bool.fromEnvironment(
        'YORKS_V1_PROJECT_SETUP',
        defaultValue: false,
      ),
      _boq = const bool.fromEnvironment('YORKS_V1_BOQ', defaultValue: true),
      _excel = const bool.fromEnvironment('YORKS_V1_EXCEL', defaultValue: true),
      _requests = const bool.fromEnvironment(
        'YORKS_V1_REQUESTS',
        defaultValue: true,
      ),
      _arrangement = const bool.fromEnvironment(
        'YORKS_V1_ARRANGEMENT',
        defaultValue: true,
      ),
      _legacyArrangementReview = const bool.fromEnvironment(
        'YORKS_V1_LEGACY_ARRANGEMENT_REVIEW',
        defaultValue: false,
      ),
      _logistics = const bool.fromEnvironment(
        'YORKS_V1_LOGISTICS',
        defaultValue: true,
      ),
      _returnsDocuments = const bool.fromEnvironment(
        'YORKS_V1_RETURNS_DOCUMENTS',
        defaultValue: true,
      ),
      _documents = const bool.fromEnvironment(
        'YORKS_V1_DOCUMENTS',
        defaultValue: true,
      ),
      _accounts = const bool.fromEnvironment(
        'YORKS_V1_ACCOUNTS',
        defaultValue: false,
      ),
      _accountsWorkspaceV2 = const bool.fromEnvironment(
        'YORKS_V1_ACCOUNTS_WORKSPACE_V2',
        defaultValue: false,
      ),
      _workforce = const bool.fromEnvironment(
        'YORKS_V1_WORKFORCE',
        defaultValue: false,
      ),
      _teamChat = const bool.fromEnvironment(
        'YORKS_R38_TEAM_CHAT',
        defaultValue: false,
      ),
      _inventorySuppliers = const bool.fromEnvironment(
        'YORKS_R38_9_INVENTORY_SUPPLIERS',
        defaultValue: false,
      ),
      _companyMaterialRequests = const bool.fromEnvironment(
        'YORKS_V1_COMPANY_MATERIAL_REQUESTS',
        defaultValue: false,
      ),
      _roleOverviewV2 = const bool.fromEnvironment(
        'YORKS_V1_ROLE_OVERVIEW_V2',
        defaultValue: false,
      ),
      _workerRecords = const bool.fromEnvironment(
        'YORKS_V1_WORKER_RECORDS',
        defaultValue: false,
      ),
      _workforceAttendanceV2 = const bool.fromEnvironment(
        'YORKS_V1_WORKFORCE_ATTENDANCE_V2',
        defaultValue: false,
      );

  final bool _foundation;
  final bool _projects;
  final bool _projectSetup;
  final bool _boq;
  final bool _excel;
  final bool _requests;
  final bool _arrangement;
  final bool _legacyArrangementReview;
  final bool _logistics;
  final bool _returnsDocuments;
  final bool _documents;
  final bool _accounts;
  final bool _accountsWorkspaceV2;
  final bool _workforce;
  final bool _teamChat;
  final bool _inventorySuppliers;
  final bool _companyMaterialRequests;
  final bool _roleOverviewV2;
  final bool _workerRecords;
  final bool _workforceAttendanceV2;

  bool get foundation => _foundation;
  bool get projects => foundation && _projects;

  /// The project setup redesign stays off until recovery and UI acceptance.
  bool get projectSetup => projects && _projectSetup;

  bool get boq => projects && _boq;
  bool get excel => boq && _excel;
  bool get requests => excel && _requests;
  bool get arrangement => requests && _arrangement;

  /// Compatibility-only controls for arrangements saved before request-first
  /// approval was introduced. New arrangements are dispatch-ready immediately
  /// after Procurement saves them, so production keeps this surface disabled.
  bool get legacyArrangementReview => arrangement && _legacyArrangementReview;

  bool get logistics => arrangement && _logistics;
  bool get returnsDocuments => logistics && _returnsDocuments;
  bool get documents => returnsDocuments && _documents;

  /// Accounts remains a separately controlled R39 rollout. It depends on the
  /// protected document chain and defaults off until its database, permission
  /// and UI acceptance gates have all passed.
  bool get accounts => documents && _accounts;

  /// The rebuilt six-tab Accounts Workspace V2 experience. It is a phased,
  /// default-off rollout layered on top of the accepted Accounts chain: when it
  /// is enabled the per-project Accounts surface renders the new workspace,
  /// otherwise the existing V1 Accounts screen stays in place. It never relaxes
  /// any server authority — the new RPCs enforce the same capabilities.
  bool get accountsWorkspaceV2 => accounts && _accountsWorkspaceV2;

  /// Workforce is an independently controlled, default-off rollout. Accepted
  /// routes are exposed only when the release operator explicitly enables it.
  bool get workforce => documents && _workforce;

  /// Operational Analytics is retired (owner decision, 9 November 2026;
  /// `PRODUCT_DECISIONS.md` section 31). Its company view duplicated the
  /// role-based Overview and waited on a slow projection, so no build can
  /// enable it: the route, sidebar entry, search target and profile link
  /// all stay hidden. `YORKS_V1_ANALYTICS` and the `analytics` constructor
  /// argument are accepted and ignored for compatibility. The protected
  /// server projection and its data are left untouched.
  bool get analytics => false;

  bool get teamChat => documents && _teamChat;

  /// Supplier folders include controlled receipt evidence, so the feature
  /// cannot be enabled with only the stock kernel. Keeping the secure document
  /// dependency in the effective getter prevents a partially functional
  /// supplier workspace from reaching users.
  bool get inventorySuppliers => documents && _inventorySuppliers;

  /// Company-use requests are a separately gated, additive lane. A project
  /// request remains available even while the company routing matrix is being
  /// configured and reviewed.
  bool get companyMaterialRequests => requests && _companyMaterialRequests;

  /// The role-based Overview: one home screen per exact role, built from the
  /// existing protected request, project and inventory projections. It is a
  /// read-only navigation surface and defaults off until its UI acceptance;
  /// when off, the retained R35 overview stays in place.
  bool get roleOverviewV2 => requests && _roleOverviewV2;

  /// Worker Records: the protected employment record (company, trade licence,
  /// passport, salary, photo) shown in User Management. Default off until the
  /// database bundle is applied and the release gate passes. The server
  /// enforces `worker_records.*` regardless of this flag.
  bool get workerRecords => foundation && _workerRecords;

  /// Workforce attendance from the approved prototype (crew days, month
  /// confirmation, monthly sheets; PRODUCT_DECISIONS.md section 37). Replaces
  /// the T03-T10 attendance and timesheet screens when on. Default off until
  /// `supabase/release/workforce_attendance_v2_bundle.sql` is applied.
  bool get workforceAttendanceV2 => workforce && _workforceAttendanceV2;

  /// The one supported Yorks V1 R35 operational chain. Release builds must
  /// fail closed if a caller explicitly disables any dependency in this chain.
  bool get isCompleteR35 => documents;
}

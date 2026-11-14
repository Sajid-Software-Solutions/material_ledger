/// Workforce attendance by role (PRODUCT_DECISIONS section 58): which
/// Workforce screens each exact role is shown, and where it lands.
///
/// This is presentation only. What anyone may see or change is decided on
/// the server for every call (`v1_wf_crew_access`); a hidden tab never grants
/// or removes a right.
library;

import '../../../shared/models/yorks_v1_role.dart';

/// The Workforce tabs a role is shown.
enum AttendanceTab {
  /// `/yorks/workforce`: My sites, Sites or Overview, by layout.
  overview,

  /// `/yorks/workforce/attendance`: taking attendance; the Workshop for the
  /// Workshop In-Charge.
  attendance,

  /// `/yorks/workforce/month`: the month by labourer, each labourer's time
  /// sheet and the year (Employees for the office).
  month,

  /// `/yorks/workforce/sheets`: the paper DAILY TIME SHEET per place.
  sheets,

  /// `/yorks/workforce/confirm`: month confirmation.
  confirm,
}

enum AttendanceRoleLayout {
  /// Site Engineer: one attendance screen, no tabs.
  siteEngineer([]),

  /// Project Engineer, Senior Mechanical Engineer, Project Manager: My sites,
  /// Take attendance, Month, Confirm.
  engineer([
    AttendanceTab.overview,
    AttendanceTab.attendance,
    AttendanceTab.month,
    AttendanceTab.confirm,
  ]),

  /// Document Controller: Sites and Month, read only.
  reader([AttendanceTab.overview, AttendanceTab.month]),

  /// Workshop In-Charge: the Workshop (attendance), Month and Time sheet.
  workshop([
    AttendanceTab.attendance,
    AttendanceTab.month,
    AttendanceTab.sheets,
  ]),

  /// Accountant: Overview, Employees, Time sheets and Attendance.
  accounts([
    AttendanceTab.overview,
    AttendanceTab.month,
    AttendanceTab.sheets,
    AttendanceTab.attendance,
  ]),

  /// HR/PRO and Admin: the Accountant's tabs plus Confirm.
  office([
    AttendanceTab.overview,
    AttendanceTab.month,
    AttendanceTab.sheets,
    AttendanceTab.attendance,
    AttendanceTab.confirm,
  ]);

  const AttendanceRoleLayout(this.tabs);

  /// Tabs in the order shown. Empty: the role's one screen has no tab row.
  final List<AttendanceTab> tabs;

  /// The layout for an exact role. With no role yet (still loading, or a
  /// local test) every screen stays reachable: the server decides.
  static AttendanceRoleLayout of(YorksV1Role? role) => switch (role) {
    YorksV1Role.siteEngineer => siteEngineer,
    YorksV1Role.projectEngineer ||
    YorksV1Role.seniorMechanicalEngineer ||
    YorksV1Role.projectManager => engineer,
    YorksV1Role.documentController => reader,
    YorksV1Role.workshopInCharge => workshop,
    YorksV1Role.accountant => accounts,
    YorksV1Role.pr || YorksV1Role.admin || null => office,
    // Procurement has no Workforce; the server refuses every call.
    YorksV1Role.procurement => reader,
  };

  /// The first screen: Workforce opens here.
  AttendanceTab get landing =>
      tabs.isEmpty ? AttendanceTab.attendance : tabs.first;

  /// The office reads every place as Overview, Employees and Time sheets.
  bool get isOffice => this == office || this == accounts;

  /// A Workforce page this layout has no tab for, other than one that is
  /// reached from a row (a place's day or sheet) or a reminder (Confirm),
  /// opens the layout's first screen instead. Null keeps the page.
  AttendanceTab? redirectFrom(AttendanceTab tab) {
    if (tabs.isEmpty) {
      // Site Engineer: attendance, and Confirm when a month waits for them
      // as a project's Project Engineer.
      return tab == AttendanceTab.attendance || tab == AttendanceTab.confirm
          ? null
          : AttendanceTab.attendance;
    }
    if (tab == AttendanceTab.overview && !tabs.contains(tab)) return landing;
    return null;
  }
}

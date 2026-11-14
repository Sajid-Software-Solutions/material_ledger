// Attendance by role (PRODUCT_DECISIONS section 58): where each exact role
// lands and which old links move. The tabs each role sees are checked in
// yorks_v1_workspace_shell_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/app/router.dart';
import 'package:material_ledger/features/workforce/application/attendance_role_layout.dart';
import 'package:material_ledger/features/workforce/domain/attendance_models.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';

void main() {
  group('layout', () {
    test('each role lands on its own first screen', () {
      expect(
        AttendanceRoleLayout.of(YorksV1Role.siteEngineer).landing,
        AttendanceTab.attendance,
      );
      expect(
        AttendanceRoleLayout.of(YorksV1Role.workshopInCharge).landing,
        AttendanceTab.attendance,
      );
      for (final role in [
        YorksV1Role.projectEngineer,
        YorksV1Role.documentController,
        YorksV1Role.accountant,
        YorksV1Role.pr,
        YorksV1Role.admin,
      ]) {
        expect(
          AttendanceRoleLayout.of(role).landing,
          AttendanceTab.overview,
          reason: role.name,
        );
      }
    });

    test('with no role yet every screen stays reachable', () {
      expect(AttendanceRoleLayout.of(null), AttendanceRoleLayout.office);
      for (final tab in AttendanceTab.values) {
        expect(AttendanceRoleLayout.of(null).redirectFrom(tab), isNull);
      }
    });

    test('a Site Engineer keeps attendance and a waiting confirmation', () {
      final layout = AttendanceRoleLayout.of(YorksV1Role.siteEngineer);
      expect(layout.tabs, isEmpty);
      expect(layout.redirectFrom(AttendanceTab.attendance), isNull);
      // A Site Engineer who is a project's Project Engineer confirms it.
      expect(layout.redirectFrom(AttendanceTab.confirm), isNull);
      for (final tab in [
        AttendanceTab.overview,
        AttendanceTab.month,
        AttendanceTab.sheets,
      ]) {
        expect(
          layout.redirectFrom(tab),
          AttendanceTab.attendance,
          reason: tab.name,
        );
      }
    });

    test('the Workshop In-Charge opens the Workshop for Workforce', () {
      final layout = AttendanceRoleLayout.of(YorksV1Role.workshopInCharge);
      expect(
        layout.redirectFrom(AttendanceTab.overview),
        AttendanceTab.attendance,
      );
      expect(layout.redirectFrom(AttendanceTab.month), isNull);
      expect(layout.redirectFrom(AttendanceTab.sheets), isNull);
    });

    test(
      'with the Workforce Center on, the Workshop In-Charge gets its tab',
      () {
        expect(
          AttendanceRoleLayout.of(
            YorksV1Role.workshopInCharge,
          ).tabsFor(center: true),
          [
            AttendanceTab.attendance,
            AttendanceTab.overview,
            AttendanceTab.month,
            AttendanceTab.sheets,
          ],
        );
        expect(AttendanceRoleLayout.workshop.centerAdded(center: true), isTrue);
        expect(
          AttendanceRoleLayout.workshop.centerAdded(center: false),
          isFalse,
        );
        // The Site Engineer keeps one screen; everyone else already has it.
        for (final layout in AttendanceRoleLayout.values) {
          if (layout == AttendanceRoleLayout.workshop) continue;
          expect(
            layout.tabsFor(center: true),
            layout.tabs,
            reason: layout.name,
          );
          expect(
            layout.centerAdded(center: true),
            isFalse,
            reason: layout.name,
          );
        }
        expect(
          AttendanceRoleLayout.workshop.tabsFor(center: false),
          AttendanceRoleLayout.workshop.tabs,
        );
      },
    );

    test('a link to a Center view opens the Center for everyone', () {
      for (final layout in AttendanceRoleLayout.values) {
        expect(
          layout.redirectFrom(AttendanceTab.overview, centerView: true),
          isNull,
          reason: layout.name,
        );
      }
      // Only the Center: the Site Engineer's other pages still move.
      expect(
        AttendanceRoleLayout.siteEngineer.redirectFrom(
          AttendanceTab.month,
          centerView: true,
        ),
        AttendanceTab.attendance,
      );
    });

    test('pages opened from a row stay open for engineers and the office', () {
      for (final role in [
        YorksV1Role.projectEngineer,
        YorksV1Role.documentController,
        YorksV1Role.accountant,
      ]) {
        for (final tab in AttendanceTab.values) {
          expect(
            AttendanceRoleLayout.of(role).redirectFrom(tab),
            isNull,
            reason: '${role.name} ${tab.name}',
          );
        }
      }
    });
  });

  group('router', () {
    String? go(String link, YorksV1Role role, {required bool center}) =>
        attendanceRoleRedirect(Uri.parse(link), role, center: center);

    test('the Workforce home opens each role\'s first screen', () {
      for (final center in [false, true]) {
        expect(
          go(
            RoutePaths.yorksV1Workforce,
            YorksV1Role.siteEngineer,
            center: center,
          ),
          RoutePaths.yorksV1WorkforceAttendance,
          reason: 'center $center',
        );
        expect(
          go(
            RoutePaths.yorksV1Workforce,
            YorksV1Role.workshopInCharge,
            center: center,
          ),
          RoutePaths.yorksV1WorkforceAttendance,
          reason: 'center $center',
        );
        expect(
          go(
            RoutePaths.yorksV1Workforce,
            YorksV1Role.projectEngineer,
            center: center,
          ),
          isNull,
          reason: 'center $center',
        );
      }
    });

    test('with the Center on, its views open for the Site Engineer and the '
        'Workshop In-Charge', () {
      for (final role in [
        YorksV1Role.siteEngineer,
        YorksV1Role.workshopInCharge,
      ]) {
        for (final view in ['requests', 'my_work', 'crews']) {
          expect(
            go('${RoutePaths.yorksV1Workforce}?view=$view', role, center: true),
            isNull,
            reason: '${role.name} $view',
          );
        }
        // Without the Center there is no view to open.
        expect(
          go(
            '${RoutePaths.yorksV1Workforce}?view=requests',
            role,
            center: false,
          ),
          RoutePaths.yorksV1WorkforceAttendance,
          reason: role.name,
        );
      }
      // A view link does not open the Site Engineer's other pages.
      expect(
        go(
          '${RoutePaths.yorksV1WorkforceMonth}?view=requests',
          YorksV1Role.siteEngineer,
          center: true,
        ),
        RoutePaths.yorksV1WorkforceAttendance,
      );
    });

    test('crew request pages are never moved', () {
      for (final role in YorksV1Role.values) {
        expect(
          go('/yorks/workforce/requests/new', role, center: true),
          isNull,
          reason: role.name,
        );
      }
    });
  });

  group('overview today', () {
    test('each place and the summary are read from the server', () {
      final overview = AttendanceOverview.fromJson({
        'today': '2026-11-14',
        'month': '2026-11-01',
        'crews': [
          {
            'id': 'c1',
            'name': 'Example site',
            'month': <String, Object?>{},
            'today': {
              'entered': true,
              'entered_by': 'Example Engineer',
              'last_saved_by': 'Example Office',
              'last_saved_at': '2026-11-14T04:10:00Z',
              'present': 7,
              'absent': 1,
              'leave': 2,
              'rest': 0,
            },
          },
        ],
        'feed': <Object>[],
        'today_summary': {
          'places': 3,
          'places_entered': 2,
          'present': 11,
          'absent': 1,
          'leave': 2,
        },
      });
      final today = overview.todayByCrew['c1']!;
      expect(today.entered, isTrue);
      expect(today.lastSavedBy, 'Example Office');
      expect(today.lastSavedAt, DateTime.utc(2026, 11, 14, 4, 10));
      expect((today.present, today.absent, today.leave), (7, 1, 2));
      final summary = overview.todaySummary!;
      expect(
        (summary.places, summary.placesEntered, summary.present),
        (3, 2, 11),
      );
    });

    test('a server before section 58 sends no today', () {
      final overview = AttendanceOverview.fromJson({
        'today': '2026-11-14',
        'month': '2026-11-01',
        'crews': [
          {'id': 'c1', 'name': 'Example site', 'month': <String, Object?>{}},
        ],
        'feed': <Object>[],
      });
      expect(overview.todayByCrew, isEmpty);
      expect(overview.todaySummary, isNull);
    });
  });
}

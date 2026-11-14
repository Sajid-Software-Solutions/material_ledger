// Attendance by role (PRODUCT_DECISIONS section 58): where each exact role
// lands and which old links move. The tabs each role sees are checked in
// yorks_v1_workspace_shell_test.dart.

import 'package:flutter_test/flutter_test.dart';
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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_workforce_dashboard_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_workforce_strings.dart';

void main() {
  group('T13 architecture hardening', () {
    test('only the repository owns the Workforce Supabase boundary', () {
      final dartFiles = Directory('lib/features/workforce')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList(growable: false);
      final backendOwners = dartFiles
          .where((file) {
            final source = file.readAsStringSync();
            return source.contains('package:supabase_flutter') ||
                source.contains('.rpc(');
          })
          .map((file) => file.path)
          .toList(growable: false);

      // Attendance V2 has its own repository over the same RPC client; it
      // reads PostgrestException only to map server errors.
      expect(backendOwners..sort(), [
        'lib/features/workforce/data/attendance_repository.dart',
        'lib/features/workforce/data/workforce_repository.dart',
      ]);
      expect(
        dartFiles.any(
          (file) => RegExp(
            r'(SUPABASE_SERVICE_ROLE_KEY|serviceRoleKey)\s*[:=]',
          ).hasMatch(file.readAsStringSync()),
        ),
        isFalse,
      );
    });

    test('critical controllers retain complete failure state families', () {
      const controllerFiles = <String>[
        'lib/features/workforce/application/workforce_daily_roster_controller.dart',
        'lib/features/workforce/application/workforce_monthly_period_controller.dart',
        'lib/features/workforce/application/workforce_review_controller.dart',
        'lib/features/workforce/application/workforce_collaboration_controller.dart',
        'lib/features/workforce/application/workforce_report_controller.dart',
        'lib/features/workforce/application/workforce_timesheet_controller.dart',
      ];
      const requiredStates = <String>[
        'loading',
        'offline',
        'conflict',
        'uncertain',
        'forbidden',
        'sessionExpired',
        'unavailable',
        'failure',
      ];

      for (final path in controllerFiles) {
        final source = File(path).readAsStringSync();
        for (final state in requiredStates) {
          expect(
            source.contains(state),
            isTrue,
            reason: '$path must retain the $state state',
          );
        }
        expect(
          source.contains('ready') || source.contains('success'),
          isTrue,
          reason: '$path must retain an explicit confirmed-success state',
        );
      }
    });

    test('large roster editors remain virtualized and controller-bounded', () {
      final roster = File(
        'lib/features/workforce/presentation/screens/'
        'yorks_workforce_daily_attendance_screen.dart',
      ).readAsStringSync();
      final monthly = File(
        'lib/features/workforce/presentation/screens/'
        'yorks_workforce_timesheets_screen.dart',
      ).readAsStringSync();

      expect(
        'ListView.builder'.allMatches(roster).length,
        greaterThanOrEqualTo(2),
      );
      expect(roster, contains('itemExtent: _rowHeight'));
      expect(roster, contains('class _RosterDataRow extends StatefulWidget'));
      expect(
        roster,
        contains('class _TabletWorkerEditor extends StatefulWidget'),
      );
      expect(
        RegExp(r'TextEditingController\(').allMatches(roster).length,
        lessThan(20),
        reason:
            'Controllers belong only to visible/active editors, never 500 rows',
      );
      expect(
        RegExp(r'\.dispose\(\);').allMatches(roster).length,
        greaterThanOrEqualTo(9),
      );
      expect(
        monthly,
        contains('for (final controller in activityControllers)'),
      );
      expect(monthly, contains('controller.dispose();'));
    });

    test(
      'every accepted surface records the nine-viewport boundary matrix',
      () {
        const files = <String>[
          'test/yorks_workforce_t05_daily_roster_widget_test.dart',
          'test/yorks_workforce_t06_monthly_widget_test.dart',
          'test/yorks_workforce_t07_review_widget_test.dart',
          'test/yorks_workforce_t08_collaboration_widget_test.dart',
          'test/yorks_workforce_t09_reports_widget_test.dart',
          'test/yorks_workforce_t10_dashboard_widget_test.dart',
        ];
        const viewports = <String>[
          'Size(1440, 900)',
          'Size(1366, 768)',
          'Size(1180, 820)',
          'Size(1024, 768)',
          'Size(820, 1180)',
          'Size(768, 1024)',
          'Size(430, 932)',
          'Size(390, 844)',
          'Size(360, 800)',
        ];

        for (final path in files) {
          final source = File(path).readAsStringSync();
          for (final viewport in viewports) {
            expect(
              source.contains(viewport),
              isTrue,
              reason: '$path must exercise $viewport',
            );
          }
        }
      },
    );

    test('critical state and dashboard copy is localized in all languages', () {
      const workforceKeys = <String>[
        'loading',
        'empty',
        'offline',
        'conflict',
        'uncertain',
        'forbidden',
        'session_expired',
        'unavailable',
        'retry',
      ];
      const dashboardKeys = <String>[
        'title',
        'server_confirmed',
        'read_only_mobile',
        'refresh',
      ];

      for (final language in AppLanguage.values) {
        for (final key in workforceKeys) {
          expect(
            YorksV1WorkforceStrings.text(language, key).trim(),
            isNotEmpty,
            reason: '${language.code}:$key',
          );
        }
        for (final key in dashboardKeys) {
          expect(
            YorksV1WorkforceDashboardStrings.text(language, key).trim(),
            isNotEmpty,
            reason: '${language.code}:$key',
          );
        }
      }
    });
  });
}

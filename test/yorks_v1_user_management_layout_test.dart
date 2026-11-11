import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ledger/features/admin/presentation/screens/user_management_screen.dart';
import 'package:material_ledger/shared/models/app_user.dart';
import 'package:material_ledger/shared/models/user_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_material_request_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('action badge follows the server action owner', () {
    final request = YorksV1MaterialRequest.fromRpcJson({
      'id': 'request-1',
      'project_id': 'project-1',
      'project_ref': 'YRA-001',
      'project_name': 'Test project',
      'scope_id': 'scope-1',
      'scope_name': 'Common / All Buildings',
      'state': 'submitted',
      'timing': 'normal',
      'record_version': 1,
      'created_at': '2026-08-05T00:00:00Z',
      'updated_at': '2026-08-05T00:00:00Z',
      'current_action_owner_role': 'procurement',
      'lines': <Object>[],
    });

    expect(
      yorksV1MaterialRequestNeedsAction(request, YorksV1Role.procurement),
      isTrue,
    );
    expect(
      yorksV1MaterialRequestNeedsAction(request, YorksV1Role.projectEngineer),
      isFalse,
    );
  });

  test('global Project Engineers receive canonical close-review work', () {
    final request = YorksV1MaterialRequest.fromRpcJson({
      'id': 'request-close',
      'project_id': 'project-1',
      'project_ref': 'YRA-001',
      'project_name': 'Test project',
      'scope_id': 'scope-1',
      'scope_name': 'Common / All Buildings',
      'state': 'received',
      'timing': 'normal',
      'record_version': 4,
      'created_at': '2026-08-05T00:00:00Z',
      'updated_at': '2026-08-05T00:00:00Z',
      'current_action_owner_role': 'project_engineer',
      'current_action_code': 'material_request_close_review',
      'lines': <Object>[],
    });

    expect(
      yorksV1MaterialRequestNeedsAction(
        request,
        YorksV1Role.seniorMechanicalEngineer,
      ),
      isTrue,
    );
    expect(
      yorksV1MaterialRequestNeedsAction(request, YorksV1Role.projectManager),
      isTrue,
    );
    expect(
      yorksV1MaterialRequestNeedsAction(request, YorksV1Role.procurement),
      isFalse,
    );
  });

  testWidgets('R35 user access stays usable at desktop and mobile widths', (
    tester,
  ) async {
    final users = [
      AppUser(
        id: 'admin-1',
        fullName: 'Khaled S. Sleiman',
        email: 'khaled.s@yorks.ae',
        role: UserRole.admin,
        createdAt: DateTime(2026, 8, 1),
      ),
      AppUser(
        id: 'engineer-1',
        fullName: 'Masaud Khan',
        email: 'masaud@yorks.ae',
        role: UserRole.engineer,
        createdAt: DateTime(2026, 8, 1),
      ),
    ];
    SharedPreferences.setMockInitialValues({
      'app_users_v3': jsonEncode(users.map((user) => user.toJson()).toList()),
    });
    final seededPreferences = await SharedPreferences.getInstance();

    for (final size in [const Size(1366, 768), const Size(360, 800)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(seededPreferences),
          ],
          child: const MaterialApp(home: UserManagementScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('User Management'), findsOneWidget);
      expect(find.text('Total accounts'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('user-management-search')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull, reason: 'viewport $size');
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

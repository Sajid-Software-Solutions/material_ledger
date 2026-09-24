import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/app/yorks_v1_workspace_shell.dart';
import 'package:material_ledger/features/materials/presentation/screens/yorks_v1_material_request_screens.dart';
import 'package:material_ledger/shared/models/yorks_v1_arrangement.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request_document.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_arrangement_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_material_request_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/yorks_v1_permission_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'named Procurement editor sees Edit beside Arrange across sizes',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final request = YorksV1MaterialRequest(
        id: 'post-edit-layout',
        projectId: 'project-layout',
        projectReference: 'YRA-123',
        projectName: 'Yorks Tower',
        scopeId: 'scope-layout',
        scopeName: 'Main Building',
        state: YorksV1MaterialRequestState.approvedForArrangement,
        recordVersion: 4,
        createdAt: DateTime.utc(2026, 9, 24),
        updatedAt: DateTime.utc(2026, 9, 24),
        timing: YorksV1MaterialRequestTiming.normal,
        requestNumber: 'YRA123-MR102',
        postApprovalEditEnabled: true,
        canEditBeforeApproval: false,
        canEditPostApproval: true,
        lines: const [
          YorksV1MaterialRequestLine(
            id: 'line-layout',
            displayOrder: 1,
            source: YorksV1MaterialRequestLineSource.custom,
            description: 'Duct fitting',
            quantity: '3',
            unit: 'Nos',
          ),
        ],
      );
      final workspace = YorksV1ArrangementWorkspace(
        requestId: request.id,
        requestState: 'approved_for_arrangement',
        requestRecordVersion: 4,
        canBegin: true,
        canSave: false,
        canDecide: false,
        arrangements: const [],
      );
      final preferences = await SharedPreferences.getInstance();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const YorksV1WorkspaceShell(
              child: YorksV1MaterialRequestDetailScreen(
                requestId: 'post-edit-layout',
              ),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1FeatureFlagsProvider.overrideWithValue(
              const YorksV1FeatureFlags(
                foundation: true,
                projects: true,
                boq: true,
                excel: true,
                requests: true,
                arrangement: true,
              ),
            ),
            yorksV1CurrentPermissionSnapshotProvider.overrideWith(
              (ref) => YorksV1TestPermissionController(
                yorksV1TrustedFeaturePermissionState(
                  role: YorksV1Role.procurement,
                ),
              ),
            ),
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.procurement,
            ),
            yorksV1MaterialRequestDetailProvider(
              request.id,
            ).overrideWith((ref) async => request),
            yorksV1MaterialRequestDocumentProvider(request.id).overrideWith(
              (ref) async =>
                  YorksV1MaterialRequestDocumentModel.fromRequest(request),
            ),
            yorksV1ArrangementWorkspaceProvider(
              request.id,
            ).overrideWith((ref) async => workspace),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final actions = find.byKey(
        const ValueKey('material-request-workflow-actions'),
      );
      expect(
        find.descendant(of: actions, matching: find.text('Edit request')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: actions, matching: find.text('Arrange Items')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(360, 800);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        find.byKey(const ValueKey('mobile-mr-request-approval-actions')),
        findsOneWidget,
      );
      expect(find.text('Edit request'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}

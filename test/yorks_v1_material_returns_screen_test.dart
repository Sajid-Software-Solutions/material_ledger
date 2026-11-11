import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/materials/presentation/screens/yorks_v1_material_returns_screen.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_return_workflow.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_logistics_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/yorks_v1_permission_test_support.dart';

final _now = DateTime.utc(2026, 8, 30, 9);

YorksV1MaterialReturnRegisterItem _item({
  required String id,
  String? number,
  required YorksV1ProjectMaterialReturnState state,
  String projectId = 'project-1',
  String projectReference = 'YRA-313',
  String projectName = '132/22kV Substation at Riyadh City',
  String scopeId = 'scope-1',
  String scopeName = 'Common',
  String? purpose,
  String drafter = 'Site Engineer',
  int lines = 4,
  String quantity = '18',
  required DateTime updatedAt,
}) => YorksV1MaterialReturnRegisterItem(
  id: id,
  number: number,
  state: state,
  recordVersion: 2,
  projectId: projectId,
  projectReference: projectReference,
  projectName: projectName,
  scopeId: scopeId,
  scopeName: scopeName,
  purpose: purpose,
  draftedByDisplayName: drafter,
  lineCount: lines,
  totalQuantity: quantity,
  updatedAt: updatedAt,
);

final _returns = [
  _item(
    id: 'return-1',
    number: 'YRA313-RTN001',
    state: YorksV1ProjectMaterialReturnState.awaitingApproval,
    purpose: 'Project close-out surplus materials',
    updatedAt: DateTime.utc(2026, 8, 24),
  ),
  _item(
    id: 'return-2',
    number: 'YRA313-RTN002',
    state: YorksV1ProjectMaterialReturnState.dispatched,
    scopeId: 'scope-2',
    scopeName: 'Building A',
    purpose: 'Wrong cable size delivered',
    lines: 2,
    quantity: '120',
    updatedAt: DateTime.utc(2026, 8, 29, 15),
  ),
  _item(
    id: 'return-3',
    state: YorksV1ProjectMaterialReturnState.draft,
    projectId: 'project-2',
    projectReference: 'YRA-401',
    projectName: 'Jeddah Grid Station Expansion',
    scopeId: 'scope-3',
    scopeName: 'Control Building',
    drafter: 'Store Keeper',
    lines: 1,
    quantity: '6',
    updatedAt: DateTime.utc(2026, 8, 28),
  ),
  _item(
    id: 'return-4',
    number: 'YRA401-RTN001',
    state: YorksV1ProjectMaterialReturnState.confirmed,
    projectId: 'project-2',
    projectReference: 'YRA-401',
    projectName: 'Jeddah Grid Station Expansion',
    scopeId: 'scope-3',
    scopeName: 'Control Building',
    purpose: 'Unused earthing materials',
    lines: 3,
    quantity: '40',
    updatedAt: DateTime.utc(2026, 8, 20),
  ),
];

Future<void> _pumpCentre(WidgetTester tester, Size size) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksV1CurrentRoleProvider.overrideWithValue(
          YorksV1Role.projectEngineer,
        ),
        yorksV1CurrentPermissionSnapshotProvider.overrideWith(
          (ref) => YorksV1TestPermissionController(
            yorksV1TrustedFeaturePermissionState(
              role: YorksV1Role.projectEngineer,
            ),
          ),
        ),
        yorksV1MaterialReturnRegisterProvider.overrideWith((ref, query) async {
          final search = query.search?.trim().toLowerCase() ?? '';
          if (search.isEmpty) return _returns;
          // Simulates the server matching an item description on return-4.
          return search == 'earth rod' ? [_returns[3]] : const [];
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: RepaintBoundary(
          key: const ValueKey('material-return-centre-evidence'),
          child: YorksV1MaterialReturnsScreen(now: _now),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Material Return Centre is usable on desktop and 360px mobile', (
    tester,
  ) async {
    for (final size in [const Size(1366, 768), const Size(360, 800)]) {
      await _pumpCentre(tester, size);

      expect(find.text('Material Return Centre'), findsOneWidget);
      expect(find.text('YRA313-RTN001'), findsOneWidget);
      expect(find.textContaining('132/22kV Substation'), findsWidgets);
      expect(
        find.byKey(const ValueKey('material-return-metric-awaitingApproval')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull, reason: 'viewport $size');
      await expectLater(
        find.byKey(const ValueKey('material-return-centre-evidence')),
        matchesGoldenFile(
          'goldens/r38/material_return_centre_${size.width.toInt()}x${size.height.toInt()}.png',
        ),
      );
    }
  });

  testWidgets('rows show owner, next action and waiting time', (tester) async {
    await _pumpCentre(tester, const Size(1366, 1400));

    expect(
      find.text('With: Engineering · Next: Approve or return for changes'),
      findsOneWidget,
    );
    expect(find.text('Waiting: 6 d'), findsOneWidget);
    expect(find.text('Draft'), findsWidgets);
    expect(find.text('Received by warehouse'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('metric cards filter the register and toggle off', (
    tester,
  ) async {
    await _pumpCentre(tester, const Size(1366, 1400));

    await tester.tap(
      find.byKey(const ValueKey('material-return-metric-dispatched')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('material-return-row-return-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('material-return-row-return-1')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('material-return-metric-dispatched')),
    );
    await tester.pumpAndSettle();
    for (final id in ['return-1', 'return-2', 'return-3', 'return-4']) {
      expect(
        find.byKey(ValueKey('material-return-row-$id')),
        findsOneWidget,
        reason: id,
      );
    }
  });

  testWidgets('projects view groups returns into folders', (tester) async {
    await _pumpCentre(tester, const Size(1366, 1400));

    await tester.tap(
      find.byKey(const ValueKey('material-return-centre-view-projects')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('material-return-project-project-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('material-return-project-project-2')),
      findsOneWidget,
    );
    expect(find.text('2 buildings'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('material-return-row-return-3')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('material-return-project-project-2')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('material-return-row-return-3')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('material-return-row-return-4')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('search matches local fields and server item matches', (
    tester,
  ) async {
    await _pumpCentre(tester, const Size(1366, 1400));
    final search = find.byKey(const ValueKey('material-return-centre-search'));

    await tester.enterText(search, 'close-out');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('material-return-row-return-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('material-return-row-return-2')),
      findsNothing,
    );

    await tester.enterText(search, 'earth rod');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('material-return-row-return-4')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('material-return-row-return-1')),
      findsNothing,
    );
  });

  testWidgets('attention filter keeps returns waiting three days or more', (
    tester,
  ) async {
    await _pumpCentre(tester, const Size(1366, 1400));

    await tester.tap(
      find.byKey(const ValueKey('material-return-centre-filter-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('material-return-filter-attention')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('material-return-row-return-1')),
      findsOneWidget,
    );
    for (final id in ['return-2', 'return-3', 'return-4']) {
      expect(
        find.byKey(ValueKey('material-return-row-$id')),
        findsNothing,
        reason: id,
      );
    }
  });
}

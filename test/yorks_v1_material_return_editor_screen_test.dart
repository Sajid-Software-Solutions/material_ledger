import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/materials/presentation/screens/yorks_v1_material_returns_screen.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_return_candidates.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_return_workflow.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_configuration_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_logistics_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_logistics_repository_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_logistics_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/yorks_v1_material_return_candidates_fixture.dart';
import 'support/yorks_v1_permission_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final size in [const Size(1440, 1400), const Size(390, 2100)]) {
    testWidgets(
      'New Material Return mirrors the Material Request draft at ${size.width.toInt()}px',
      (tester) async {
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
              yorksV1MaterialReturnProjectsProvider.overrideWith(
                (ref) async => const [
                  YorksV1MaterialRequestProjectOption(
                    id: 'project-1',
                    reference: 'YRA-313',
                    name: '132/22kV Substation at Riyadh City',
                    state: 'active',
                  ),
                ],
              ),
              yorksV1MaterialReturnCreationWorkspaceProvider((
                projectId: 'project-1',
                returnId: null,
              )).overrideWith(
                (ref) async => YorksV1MaterialReturnCreationWorkspace(
                  projectId: 'project-1',
                  projectReference: 'YRA-313',
                  projectName: '132/22kV Substation at Riyadh City',
                  scopes: const [
                    YorksV1MaterialReturnScope(
                      id: 'scope-common',
                      name: 'Common / All Buildings',
                      kind: 'common',
                    ),
                    YorksV1MaterialReturnScope(
                      id: 'scope-a',
                      name: 'Building A',
                      kind: 'building',
                    ),
                  ],
                  candidates: const [],
                  units: const ['Mtr', 'Pairs', 'Nos'],
                ),
              ),
              yorksV1LogisticsRepositoryProvider.overrideWithValue(
                _CandidatesRepository(),
              ),
              yorksV1ConfigurationUnitCodesProvider.overrideWith(
                (ref) async => const ['Mtr', 'Pairs', 'Nos'],
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: const RepaintBoundary(
                key: ValueKey('material-return-editor-evidence'),
                child: YorksV1MaterialReturnEditorScreen(
                  initialProjectId: 'project-1',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Return Information'), findsOneWidget);
        expect(find.text('Material Items'), findsOneWidget);
        expect(find.text('Stage 1 of 4'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('material-return-add-deliveries')),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const ValueKey('material-return-search')),
          'pipe',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Copper Pipe').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('material-return-add-custom')),
        );
        await tester.tap(
          find.byKey(const ValueKey('material-return-add-custom')),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('of 13 available'), findsOneWidget);
        final error = tester.takeException();
        expect(
          error,
          isNull,
          reason:
              'viewport $size: ${error is FlutterError ? error.toStringDeep() : error}',
        );
        await expectLater(
          find.byKey(const ValueKey('material-return-editor-evidence')),
          matchesGoldenFile(
            'goldens/r38/material_return_editor_${size.width.toInt()}x${size.height.toInt()}.png',
          ),
        );
      },
    );
  }
}

class _CandidatesRepository
    implements
        YorksV1LogisticsRepository,
        YorksV1MaterialReturnItemCandidatesRepository {
  @override
  Future<YorksV1MaterialReturnItemCandidates> getMaterialReturnItemCandidates(
    YorksV1MaterialReturnCandidatesQuery query,
  ) async => YorksV1MaterialReturnItemCandidates.fromRpcJson(
    yorksV1MaterialReturnCandidatesFixture(),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

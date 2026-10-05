import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/app/router.dart';
import 'package:material_ledger/app/yorks_v1_workspace_shell.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/projects/presentation/screens/yorks_v1_project_legacy_flow_screen.dart';
import 'package:material_ledger/features/projects/presentation/screens/yorks_v1_projects_screen.dart';
import 'package:material_ledger/features/projects/presentation/screens/yorks_v1_documents_screen.dart';
import 'package:material_ledger/features/materials/presentation/screens/yorks_v1_material_request_screens.dart';
import 'package:material_ledger/shared/models/yorks_v1_boq.dart';
import 'package:material_ledger/shared/models/yorks_v1_document.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_project.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_creation_draft.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_portfolio.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_team_directory_member.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_boq_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_documents_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_material_request_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_creation_draft_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_portfolio_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_repository_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_team_directory_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_team_directory_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/yorks_v1_permission_test_support.dart';

const _authUserId = 'mobile-project-user';
const _projectId = 'project-mobile-batch-2';

void main() {
  setUpAll(() async {
    final nexusFontLoader = FontLoader('NexusSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final arabicFontLoader = FontLoader('NotoSansArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
    final flutterCache = _flutterCacheDirectory();
    final iconBytes = await File(
      '${flutterCache.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    final iconFontLoader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(iconBytes)));
    await Future.wait([
      nexusFontLoader.load(),
      arabicFontLoader.load(),
      iconFontLoader.load(),
    ]);
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in [const Size(390, 844), const Size(360, 800)]) {
    final suffix = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('mobile Batch 2 project review $suffix', (tester) async {
      final repository = _ControlledProjectRepository();
      final container = await _createCreationContainer(repository);
      await _seedReviewDraft(container);

      await _setViewport(tester, size);
      await _pumpCreationShell(tester, container: container);

      expect(
        find.textContaining('YRA-321', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.text(YorksV1ProjectStrings.whatHappensNext.primary),
        findsOneWidget,
      );
      expect(find.text(YorksV1ProjectStrings.ready.primary), findsOneWidget);
      await expectLater(
        find.byType(YorksV1WorkspaceShell),
        matchesGoldenFile('goldens/mobile_batch2/project_review_$suffix.png'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile Batch 2 project overview $suffix', (tester) async {
      await _setViewport(tester, size);
      await _pumpWorkspaceShell(tester, role: YorksV1Role.projectEngineer);

      expect(find.text('Al Dhafra Project'), findsOneWidget);
      expect(find.text('18'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      await expectLater(
        find.byType(YorksV1WorkspaceShell),
        matchesGoldenFile('goldens/mobile_batch2/project_overview_$suffix.png'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile Batch 2 project BOQ scope overview $suffix', (
      tester,
    ) async {
      await _setViewport(tester, size);
      await _pumpWorkspaceShell(tester, role: YorksV1Role.projectEngineer);

      await tester.tap(find.text(YorksV1ProjectStrings.boq.primary));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('boq-mobile-embedded-workspace')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('boq-mobile-scope-overview')),
        findsOneWidget,
      );
      expect(find.text('Common / All Buildings'), findsWidgets);
      expect(find.text('Substation Building 3'), findsWidgets);
      await expectLater(
        find.byType(YorksV1WorkspaceShell),
        matchesGoldenFile(
          'goldens/mobile_batch2/project_boq_scope_overview_$suffix.png',
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile Batch 2 project details team $suffix', (tester) async {
      await _setViewport(tester, size);
      await _pumpWorkspaceShell(tester, role: YorksV1Role.projectEngineer);

      await tester.tap(
        find.byTooltip(YorksV1ProjectStrings.projectDetails.primary),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(YorksV1ProjectStrings.projectEngineers.primary),
        findsOneWidget,
      );
      expect(find.text('Omar Farooq'), findsOneWidget);
      expect(find.text('Saad Hassan'), findsOneWidget);
      expect(find.text(YorksV1ProjectStrings.manage.primary), findsNWidgets(2));
      await expectLater(
        find.byType(YorksV1WorkspaceShell),
        matchesGoldenFile(
          'goldens/mobile_batch2/project_details_team_$suffix.png',
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('project overview distinguishes loading, failure and true zero', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    final pending = Completer<List<YorksV1MaterialRequest>>();
    await _pumpWorkspaceShell(
      tester,
      role: YorksV1Role.projectEngineer,
      requestsFuture: pending.future,
      settle: false,
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('—'), findsNWidgets(4));
    expect(
      find.text(YorksV1ProjectStrings.requestsUnavailable.primary),
      findsNothing,
    );

    await _pumpWorkspaceShell(
      tester,
      role: YorksV1Role.projectEngineer,
      requestsError: StateError('fixture failure'),
      settle: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.text(YorksV1ProjectStrings.requestsUnavailable.primary),
      findsOneWidget,
    );

    await _pumpWorkspaceShell(
      tester,
      role: YorksV1Role.projectEngineer,
      requestsFuture: Future.value(const <YorksV1MaterialRequest>[]),
    );
    expect(
      find.text(YorksV1ProjectStrings.requestsUnavailable.primary),
      findsNothing,
    );
    expect(find.text('0'), findsAtLeastNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'project Requests and Documents tabs render their registers in place',
    (tester) async {
      await _setViewport(tester, const Size(390, 844));
      await _pumpWorkspaceShell(tester, role: YorksV1Role.projectEngineer);

      await tester.tap(
        find.byKey(const ValueKey('yorks-mobile-project-tab-requests')),
      );
      await tester.pump();
      expect(find.byType(YorksV1MaterialRequestsScreen), findsOneWidget);
      expect(
        find.text(YorksV1ProjectStrings.openRequests.primary),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('yorks-mobile-project-tab-documents')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(YorksV1DocumentsScreen), findsOneWidget);
      expect(
        find.text(YorksV1ProjectStrings.openDocuments.primary),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('team Manage follows actual project authority', (tester) async {
    await _setViewport(tester, const Size(390, 844));
    await _pumpWorkspaceShell(tester, role: YorksV1Role.projectEngineer);
    await tester.tap(
      find.byTooltip(YorksV1ProjectStrings.projectDetails.primary),
    );
    await tester.pumpAndSettle();

    expect(find.text(YorksV1ProjectStrings.manage.primary), findsNWidgets(2));
    expect(find.textContaining('@'), findsNothing);
    expect(find.textContaining('00000000-'), findsNothing);

    await _pumpWorkspaceShell(
      tester,
      role: YorksV1Role.siteEngineer,
      authUserId: 'site-auth-user',
    );
    await tester.tap(
      find.byTooltip(YorksV1ProjectStrings.projectDetails.primary),
    );
    await tester.pumpAndSettle();

    expect(find.text(YorksV1ProjectStrings.manage.primary), findsNothing);
    expect(find.text('Omar Farooq'), findsOneWidget);
    expect(find.textContaining('@'), findsNothing);
    expect(find.textContaining('00000000-'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'project review reports directory failure without a false stale-member warning',
    (tester) async {
      await _setViewport(tester, const Size(390, 844));
      final directoryRepository = _RecoveringTeamDirectoryRepository();
      final container = await _createCreationContainer(
        _ControlledProjectRepository(),
        teamDirectoryRepository: directoryRepository,
      );
      await _seedReviewDraft(container);
      await _pumpCreationShell(tester, container: container);

      expect(
        find.text(YorksV1ProjectStrings.teamDirectoryUnavailable.primary),
        findsOneWidget,
      );
      expect(find.text(YorksV1ProjectStrings.retry.primary), findsOneWidget);
      expect(
        find.text(YorksV1ProjectStrings.teamMemberNoLongerAvailable.primary),
        findsNothing,
      );
      expect(find.text(YorksV1ProjectStrings.ready.primary), findsNothing);

      directoryRepository.shouldFail = false;
      await tester.tap(find.text(YorksV1ProjectStrings.retry.primary));
      await tester.pumpAndSettle();

      expect(directoryRepository.callCount, 2);
      expect(
        find.text(YorksV1ProjectStrings.teamDirectoryUnavailable.primary),
        findsNothing,
      );
      expect(
        find.text(YorksV1ProjectStrings.teamMemberNoLongerAvailable.primary),
        findsNothing,
      );
      expect(find.text(YorksV1ProjectStrings.ready.primary), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('non-editable project lifecycle hides New Material Request', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    await _pumpWorkspaceShell(tester, role: YorksV1Role.projectEngineer);
    await _openProjectInformation(tester);

    expect(
      find.text(YorksV1MaterialRequestStrings.newRequest.primary),
      findsOneWidget,
    );

    await _pumpWorkspaceShell(
      tester,
      role: YorksV1Role.projectEngineer,
      portfolioItem: _portfolioWithLifecycle(YorksV1ProjectLifecycle.completed),
    );
    await _openProjectInformation(tester);

    expect(
      find.text(YorksV1MaterialRequestStrings.newRequest.primary),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('recent material request row opens the selected request', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    await _pumpWorkspaceShell(tester, role: YorksV1Role.projectEngineer);
    final requestNumber = _requestFixtures.first.requestNumber!;
    final row = find.text(requestNumber);

    expect(row, findsOneWidget);
    await Scrollable.ensureVisible(tester.element(row), alignment: .5);
    await tester.pumpAndSettle();
    final requestRow = find.byKey(
      ValueKey('mobile-project-request-${_requestFixtures.first.id}'),
    );
    expect(requestRow, findsOneWidget);
    tester.widget<InkWell>(requestRow).onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(
        ValueKey('selected-material-request-${_requestFixtures.first.id}'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('project create remains pending until the server confirms', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    final repository = _ControlledProjectRepository(controlCreate: true);
    final container = await _createCreationContainer(repository);
    await _seedReviewDraft(container, includeAttachmentMetadata: false);
    YorksV1Project? created;
    await _pumpCreationShell(
      tester,
      container: container,
      onProjectCreated: (value) => created = value,
    );

    await tester.tap(find.byKey(const ValueKey('yorks-v1-project-create')));
    await tester.pump();

    expect(repository.creationInputs, hasLength(1));
    expect(created, isNull);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(
      container
          .read(yorksV1ProjectCreationDraftProvider(_authUserId))
          .reference,
      'YRA-321',
    );

    repository.confirmCreate();
    await tester.pumpAndSettle();

    expect(created?.reference, 'YRA-321');
    expect(
      container
          .read(yorksV1ProjectCreationDraftProvider(_authUserId))
          .reference,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('project review remains usable at 2.5x text scale', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _setViewport(tester, const Size(360, 800));
    final container = await _createCreationContainer(
      _ControlledProjectRepository(),
    );
    await _seedReviewDraft(container);
    await _pumpCreationShell(tester, container: container);

    expect(find.text(YorksV1ProjectStrings.whatHappensNext.primary), findsOne);
    expect(
      find.byKey(const ValueKey('yorks-v1-project-create')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<ProviderContainer> _createCreationContainer(
  _ControlledProjectRepository repository, {
  YorksV1ProjectTeamDirectoryRepository teamDirectoryRepository =
      const _FixtureTeamDirectoryRepository(),
}) async {
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      yorksV1AuthUserIdProvider.overrideWithValue(_authUserId),
      yorksV1CurrentRoleProvider.overrideWithValue(YorksV1Role.projectEngineer),
      yorksV1CurrentPermissionSnapshotProvider.overrideWith(
        (ref) => YorksV1TestPermissionController(
          yorksV1TrustedFeaturePermissionState(
            role: YorksV1Role.projectEngineer,
          ),
        ),
      ),
      yorksV1ProjectRepositoryProvider.overrideWithValue(repository),
      yorksV1ProjectTeamDirectoryRepositoryProvider.overrideWithValue(
        teamDirectoryRepository,
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _seedReviewDraft(
  ProviderContainer container, {
  bool includeAttachmentMetadata = true,
}) async {
  final current = container.read(
    yorksV1ProjectCreationDraftProvider(_authUserId),
  );
  await container
      .read(yorksV1ProjectCreationDraftProvider(_authUserId).notifier)
      .save(
        current.copyWith(
          reference: 'YRA-321',
          name: 'Al Dhafra Project',
          clientName: 'Tava',
          siteLocation: 'Abu Dhabi',
          currentStage: YorksV1ProjectCreationStage.reviewAndCreate,
          initialMembers: const [
            YorksV1InitialProjectMemberInput(
              authUserId: _authUserId,
              projectRole: YorksV1ProjectMembershipRole.projectEngineer,
            ),
            YorksV1InitialProjectMemberInput(
              authUserId: 'project-auth-user-2',
              projectRole: YorksV1ProjectMembershipRole.projectEngineer,
            ),
            YorksV1InitialProjectMemberInput(
              authUserId: 'site-auth-user',
              projectRole: YorksV1ProjectMembershipRole.siteEngineer,
            ),
          ],
          buildings: const [
            YorksV1ProjectBuildingInput(code: 'DF3W', name: 'Building 3'),
            YorksV1ProjectBuildingInput(code: 'DF4W', name: 'Building 4'),
            YorksV1ProjectBuildingInput(code: 'DF6W', name: 'Building 6'),
          ],
          attachments: includeAttachmentMetadata
              ? const [
                  YorksV1ProjectAttachmentInput(fileName: 'contract.pdf'),
                  YorksV1ProjectAttachmentInput(fileName: 'drawing.pdf'),
                  YorksV1ProjectAttachmentInput(fileName: 'programme.xlsx'),
                ]
              : const [],
        ),
      );
}

Future<void> _pumpCreationShell(
  WidgetTester tester, {
  required ProviderContainer container,
  ValueChanged<YorksV1Project>? onProjectCreated,
}) async {
  final router = GoRouter(
    initialLocation: RoutePaths.engineerCreateProject,
    routes: [
      GoRoute(
        path: RoutePaths.engineerCreateProject,
        builder: (_, _) => YorksV1WorkspaceShell(
          child: YorksV1LegacyProjectCreateFlowScreen(
            onProjectCreated: onProjectCreated,
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<GoRouter> _pumpWorkspaceShell(
  WidgetTester tester, {
  required YorksV1Role role,
  String authUserId = _authUserId,
  Future<List<YorksV1MaterialRequest>>? requestsFuture,
  Object? requestsError,
  YorksV1ProjectPortfolioItem? portfolioItem,
  bool settle = true,
}) async {
  final preferences = await SharedPreferences.getInstance();
  final router = GoRouter(
    initialLocation: RoutePaths.yorksV1ProjectPath(_projectId),
    routes: [
      GoRoute(
        path: RoutePaths.yorksV1Project,
        builder: (_, _) => const YorksV1WorkspaceShell(
          child: YorksV1ProjectWorkspaceScreen(projectId: _projectId),
        ),
      ),
      GoRoute(
        path: RoutePaths.yorksV1MaterialRequest,
        builder: (_, state) => Scaffold(
          body: SizedBox(
            key: ValueKey(
              'selected-material-request-${state.pathParameters['requestId']}',
            ),
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksV1AuthUserIdProvider.overrideWithValue(authUserId),
        yorksV1CurrentRoleProvider.overrideWithValue(role),
        yorksV1CurrentPermissionSnapshotProvider.overrideWith(
          (ref) => YorksV1TestPermissionController(
            yorksV1TrustedFeaturePermissionState(role: role),
          ),
        ),
        yorksV1ProjectPortfolioProvider.overrideWith(
          (ref) async => [portfolioItem ?? _portfolioFixture],
        ),
        yorksV1MaterialRequestListProvider(_projectId).overrideWith((ref) {
          if (requestsError != null) throw requestsError;
          return requestsFuture ?? Future.value(_requestFixtures);
        }),
        yorksV1MaterialRequestScopesProvider(
          _projectId,
        ).overrideWith((ref) async => _scopeFixtures),
        yorksV1BoqGroupsProvider(
          _projectId,
        ).overrideWith((ref) async => _groupFixtures),
        yorksV1ScopedBoqGroupsProvider(
          const YorksV1BoqScopeQuery(projectId: _projectId),
        ).overrideWith((ref) async => _boqOverviewGroupFixtures),
        yorksV1DocumentWorkspaceProvider(_projectId).overrideWith(
          (ref) async => const YorksV1DocumentWorkspace(
            projectId: _projectId,
            documents: [],
            auditEntries: [],
          ),
        ),
        yorksV1ActiveProjectTeamDirectoryProvider.overrideWith(
          (ref) async => _teamDirectoryFixtures,
        ),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: router,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return router;
}

Future<void> _openProjectInformation(WidgetTester tester) async {
  await tester.tap(
    find.byTooltip(YorksV1ProjectStrings.projectDetails.primary),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(YorksV1ProjectStrings.information.primary));
  await tester.pumpAndSettle();
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 26);
  tester.view.viewPadding = const FakeViewPadding(top: 26);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });
}

final _portfolioFixture = YorksV1ProjectPortfolioItem(
  project: YorksV1Project(
    id: _projectId,
    reference: 'YRA-321',
    name: 'Al Dhafra Project',
    state: YorksV1ProjectLifecycle.active,
    version: 4,
    createdAt: DateTime.utc(2026, 8, 1, 8),
    updatedAt: DateTime.utc(2026, 8, 9, 10, 40),
    clientName: 'Tava',
    jobOrContractReference: 'N-19957.2',
    siteLocation: 'Abu Dhabi, UAE',
    createdByAuthUserId: _authUserId,
  ),
  clientName: 'Tava',
  activeBuildingCount: 4,
  activeProjectEngineerCount: 2,
  activeSiteEngineerCount: 1,
  activeMembers: [
    YorksV1ProjectMember(
      id: 'member-1',
      projectId: _projectId,
      memberAuthUserId: _authUserId,
      projectRole: YorksV1ProjectMembershipRole.projectEngineer,
      effectiveFrom: DateTime.utc(2026, 8, 1),
      createdAt: DateTime.utc(2026, 8, 1),
      displayName: 'Omar Farooq',
    ),
    YorksV1ProjectMember(
      id: 'member-2',
      projectId: _projectId,
      memberAuthUserId: 'project-auth-user-2',
      projectRole: YorksV1ProjectMembershipRole.projectEngineer,
      effectiveFrom: DateTime.utc(2026, 8, 1),
      createdAt: DateTime.utc(2026, 8, 1),
      displayName: 'Ahmed Raza',
    ),
    YorksV1ProjectMember(
      id: 'member-3',
      projectId: _projectId,
      memberAuthUserId: 'site-auth-user',
      projectRole: YorksV1ProjectMembershipRole.siteEngineer,
      effectiveFrom: DateTime.utc(2026, 8, 1),
      createdAt: DateTime.utc(2026, 8, 1),
      displayName: 'Saad Hassan',
    ),
  ],
  parties: const [
    YorksV1ProjectPartyInput(
      kind: YorksV1ProjectPartyKind.client,
      name: 'Tava',
    ),
  ],
  buildings: const [
    YorksV1ProjectBuildingInput(code: 'DF3W', name: 'Substation Building 3'),
    YorksV1ProjectBuildingInput(code: 'DF4W', name: 'Substation Building 4'),
    YorksV1ProjectBuildingInput(code: 'DF6W', name: 'Substation Building 6'),
    YorksV1ProjectBuildingInput(code: 'DF7W', name: 'Substation Building 7'),
  ],
);

YorksV1ProjectPortfolioItem _portfolioWithLifecycle(
  YorksV1ProjectLifecycle lifecycle,
) {
  final project = _portfolioFixture.project;
  return YorksV1ProjectPortfolioItem(
    project: YorksV1Project(
      id: project.id,
      reference: project.reference,
      name: project.name,
      state: lifecycle,
      version: project.version,
      createdAt: project.createdAt,
      updatedAt: project.updatedAt,
      clientName: project.clientName,
      jobOrContractReference: project.jobOrContractReference,
      siteLocation: project.siteLocation,
      createdByAuthUserId: project.createdByAuthUserId,
    ),
    clientName: _portfolioFixture.clientName,
    activeBuildingCount: _portfolioFixture.activeBuildingCount,
    activeProjectEngineerCount: _portfolioFixture.activeProjectEngineerCount,
    activeSiteEngineerCount: _portfolioFixture.activeSiteEngineerCount,
    activeMembers: _portfolioFixture.activeMembers,
    parties: _portfolioFixture.parties,
    buildings: _portfolioFixture.buildings,
  );
}

final _scopeFixtures = <YorksV1MaterialRequestScopeOption>[
  const YorksV1MaterialRequestScopeOption(
    id: 'scope-common',
    projectId: _projectId,
    name: 'Common / All Buildings',
    kind: 'common',
  ),
  for (final building in _portfolioFixture.buildings)
    YorksV1MaterialRequestScopeOption(
      id: 'scope-${building.code.toLowerCase()}',
      projectId: _projectId,
      name: building.name,
      kind: 'building',
    ),
];

final _groupFixtures = List<YorksV1BoqGroup>.generate(
  29,
  (index) => YorksV1BoqGroup(
    id: 'group-$index',
    projectId: _projectId,
    scopeId: 'scope-common',
    scopeKind: 'common',
    scopeName: 'Common / All Buildings',
    name: 'BOQ Group ${index + 1}',
    worksheetTitle: 'BOQ Group ${index + 1}',
    displayOrder: index + 1,
    isCustom: false,
    isArchived: false,
    version: 1,
    rowCount: index % 4,
    columnCount: 5,
    updatedAt: DateTime.utc(2026, 8, 8),
  ),
);

final _boqOverviewGroupFixtures = <YorksV1BoqGroup>[
  ..._scopeBoqGroups(_scopeFixtures[0], 2, 4),
  ..._scopeBoqGroups(_scopeFixtures[1], 6, 59),
  ..._scopeBoqGroups(_scopeFixtures[2], 2, 10),
];

List<YorksV1BoqGroup> _scopeBoqGroups(
  YorksV1MaterialRequestScopeOption scope,
  int count,
  int totalRows,
) => List<YorksV1BoqGroup>.generate(count, (index) {
  final base = totalRows ~/ count;
  final remainder = index < totalRows % count ? 1 : 0;
  return YorksV1BoqGroup(
    id: '${scope.id}-group-$index',
    projectId: _projectId,
    scopeId: scope.id,
    scopeKind: scope.kind,
    scopeName: scope.name,
    scopeCode: scope.kind == 'building'
        ? scope.id.replaceFirst('scope-', '').toUpperCase()
        : null,
    name: 'BOQ Group ${index + 1}',
    worksheetTitle: 'BOQ Group ${index + 1}',
    displayOrder: index + 1,
    isCustom: false,
    isArchived: false,
    version: 1,
    rowCount: base + remainder,
    columnCount: 5,
    updatedAt: DateTime.utc(2026, 8, 8),
  );
});

final _requestFixtures = List<YorksV1MaterialRequest>.generate(18, (index) {
  final state = switch (index) {
    < 7 => YorksV1MaterialRequestState.approved,
    < 10 => YorksV1MaterialRequestState.awaitingApproval,
    < 12 => YorksV1MaterialRequestState.arranging,
    < 16 => YorksV1MaterialRequestState.received,
    _ => YorksV1MaterialRequestState.closed,
  };
  return YorksV1MaterialRequest(
    id: 'request-$index',
    projectId: _projectId,
    projectReference: 'YRA-321',
    projectName: 'Al Dhafra Project',
    scopeId: 'scope-df3w',
    scopeName: 'DF3W',
    state: state,
    recordVersion: 1,
    createdAt: DateTime.utc(2026, 8, 1).add(Duration(hours: index)),
    updatedAt: DateTime.utc(
      2026,
      8,
      9,
      10,
      40,
    ).subtract(Duration(minutes: index * 15)),
    timing: YorksV1MaterialRequestTiming.normal,
    requestNumber: 'YRA321-MR${(index + 1).toString().padLeft(3, '0')}',
    requesterDisplayName: 'Omar Farooq',
    requesterProjectRole: 'project_engineer',
    currentActionOwnerRole:
        state == YorksV1MaterialRequestState.awaitingApproval
        ? 'project_engineer'
        : 'procurement',
    lines: [
      YorksV1MaterialRequestLine(
        id: 'request-$index-line-1',
        displayOrder: 1,
        source: YorksV1MaterialRequestLineSource.boq,
        description: 'HVAC material ${index + 1}',
        quantity: '1',
        unit: 'Nos',
      ),
    ],
  );
});

const _teamDirectoryFixtures = <YorksV1ProjectTeamDirectoryMember>[
  YorksV1ProjectTeamDirectoryMember(
    authUserId: _authUserId,
    displayName: 'Omar Farooq',
    eligibleRole: YorksV1Role.projectEngineer,
  ),
  YorksV1ProjectTeamDirectoryMember(
    authUserId: 'project-auth-user-2',
    displayName: 'Ahmed Raza',
    eligibleRole: YorksV1Role.projectEngineer,
  ),
  YorksV1ProjectTeamDirectoryMember(
    authUserId: 'site-auth-user',
    displayName: 'Saad Hassan',
    eligibleRole: YorksV1Role.siteEngineer,
  ),
];

class _FixtureTeamDirectoryRepository
    implements YorksV1ProjectTeamDirectoryRepository {
  const _FixtureTeamDirectoryRepository();

  @override
  Future<List<YorksV1ProjectTeamDirectoryMember>> listActiveMembers() async =>
      _teamDirectoryFixtures;
}

class _RecoveringTeamDirectoryRepository
    implements YorksV1ProjectTeamDirectoryRepository {
  bool shouldFail = true;
  int callCount = 0;

  @override
  Future<List<YorksV1ProjectTeamDirectoryMember>> listActiveMembers() async {
    callCount += 1;
    if (shouldFail) throw StateError('fixture directory failure');
    return _teamDirectoryFixtures;
  }
}

class _ControlledProjectRepository implements YorksV1ProjectRepository {
  _ControlledProjectRepository({this.controlCreate = false});

  final bool controlCreate;
  final List<YorksV1ProjectCreationInput> creationInputs = [];
  Completer<YorksV1ProjectCreationResult>? _pendingCreate;

  @override
  Future<YorksV1ProjectCreationResult> createProject(
    YorksV1ProjectCreationInput input,
  ) async {
    creationInputs.add(input);
    final result = _creationResult(input);
    if (!controlCreate) return result;
    _pendingCreate = Completer<YorksV1ProjectCreationResult>();
    return _pendingCreate!.future;
  }

  void confirmCreate() {
    final input = creationInputs.single;
    _pendingCreate!.complete(_creationResult(input));
  }

  YorksV1ProjectCreationResult _creationResult(
    YorksV1ProjectCreationInput input,
  ) => YorksV1ProjectCreationResult(
    project: YorksV1Project(
      id: _projectId,
      reference: input.reference,
      name: input.name,
      state: YorksV1ProjectLifecycle.draft,
      version: 1,
      createdAt: DateTime.utc(2026, 8, 9),
      updatedAt: DateTime.utc(2026, 8, 9),
      clientName: input.clientName,
      siteLocation: input.siteLocation,
    ),
    scopes: const [],
    members: const [],
    parties: input.parties,
    attachments: input.attachments,
    idempotencyKey: input.idempotencyKey,
  );

  @override
  Future<YorksV1ProjectMembershipResult> assignProjectMember(
    YorksV1AssignProjectMemberInput input,
  ) => throw UnimplementedError();

  @override
  Future<YorksV1ProjectMembershipResult> revokeProjectMember(
    YorksV1RevokeProjectMemberInput input,
  ) => throw UnimplementedError();

  @override
  Future<YorksV1Project> setProjectState(YorksV1SetProjectStateInput input) =>
      throw UnimplementedError();

  @override
  Future<YorksV1Project> updateProject(YorksV1ProjectUpdateInput input) =>
      throw UnimplementedError();

  @override
  Future<YorksV1Project> archiveProject(YorksV1ArchiveProjectInput input) =>
      throw UnimplementedError();
}

Directory _flutterCacheDirectory() {
  var directory = File(Platform.resolvedExecutable).parent;
  for (var level = 0; level < 8; level++) {
    if (directory.path.endsWith('${Platform.pathSeparator}cache')) {
      return directory;
    }
    directory = directory.parent;
  }
  throw StateError('Could not locate the Flutter cache from the test runner');
}

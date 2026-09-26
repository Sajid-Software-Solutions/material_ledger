import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/app/yorks_v1_workspace_shell.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/projects/presentation/screens/yorks_v1_projects_screen.dart';
import 'package:material_ledger/shared/models/yorks_v1_boq.dart';
import 'package:material_ledger/shared/models/yorks_v1_document.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request.dart';
import 'package:material_ledger/shared/models/yorks_v1_project.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_portfolio.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_team_directory_member.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_boq_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_documents_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_material_request_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_portfolio_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_team_directory_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/yorks_v1_permission_test_support.dart';

void main() {
  setUpAll(() async {
    final nexus = FontLoader('NexusSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final arabic = FontLoader('NotoSansArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
    final cache = _flutterCacheDirectory();
    final iconBytes = await File(
      '${cache.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(iconBytes)));
    await Future.wait([nexus.load(), arabic.load(), icons.load()]);
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('project workspace redesign matches all accepted viewports', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    for (final viewport in _viewports) {
      tester.view.physicalSize = viewport.size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = viewport.textScale;
      final router = GoRouter(
        initialLocation: '/projects/project-layout',
        routes: [
          GoRoute(
            path: '/projects/:projectId',
            builder: (_, _) => const YorksV1WorkspaceShell(
              child: YorksV1ProjectWorkspaceScreen(projectId: 'project-layout'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1FeatureFlagsProvider.overrideWithValue(_featureFlags),
            yorksV1CurrentPermissionSnapshotProvider.overrideWith(
              (ref) => YorksV1TestPermissionController(
                yorksV1TrustedFeaturePermissionState(),
              ),
            ),
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.projectEngineer,
            ),
            yorksV1AuthUserIdProvider.overrideWithValue('engineer-1'),
            yorksV1ProjectPortfolioProvider.overrideWith(
              (ref) async => [_portfolioItem],
            ),
            yorksV1BoqGroupsProvider(
              'project-layout',
            ).overrideWith((ref) async => _groups),
            yorksV1MaterialRequestListProvider(
              'project-layout',
            ).overrideWith((ref) async => _requests),
            yorksV1MaterialRequestScopesProvider(
              'project-layout',
            ).overrideWith((ref) async => _scopes),
            yorksV1DocumentWorkspaceProvider('project-layout').overrideWith(
              (ref) async => const YorksV1DocumentWorkspace(
                projectId: 'project-layout',
                documents: [],
                auditEntries: [],
              ),
            ),
            yorksV1ActiveProjectTeamDirectoryProvider.overrideWith(
              (ref) async => _directory,
            ),
          ],
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('N-19957.1 NEXUS'), findsOneWidget);
      expect(find.textContaining('BOQ'), findsWidgets);
      if (viewport.size.width > 720) {
        expect(find.text('Action required'), findsOneWidget);
        expect(find.text('Recent Material Requests'), findsOneWidget);
        expect(find.text('Project team'), findsWidgets);
      } else {
        expect(find.text('Needs attention'), findsOneWidget);
        expect(find.text('New Material Request'), findsOneWidget);
      }
      expect(tester.takeException(), isNull, reason: viewport.name);

      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/logo.png'),
          tester.element(find.byType(YorksV1WorkspaceShell)),
        ),
      );
      await tester.pump();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/project_workspace/redesign_${viewport.name}.png',
        ),
      );
    }
  });

  testWidgets('project BOQ redesign matches desktop tablet and mobile', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    for (final evidence
        in <
          ({String name, Size size, String? selectedScopeId, double textScale})
        >[
          (
            name: 'overview_desktop_1440x1066',
            size: const Size(1440, 1066),
            selectedScopeId: null,
            textScale: 1,
          ),
          (
            name: 'groups_desktop_1440x1066',
            size: const Size(1440, 1066),
            selectedScopeId: 'scope-common',
            textScale: 1,
          ),
          (
            name: 'groups_tablet_1024x768',
            size: const Size(1024, 768),
            selectedScopeId: 'scope-common',
            textScale: 1,
          ),
          (
            name: 'groups_tablet_portrait_820x1180',
            size: const Size(820, 1180),
            selectedScopeId: 'scope-common',
            textScale: 1,
          ),
          (
            name: 'overview_mobile_390x844',
            size: const Size(390, 844),
            selectedScopeId: null,
            textScale: 1,
          ),
          (
            name: 'groups_mobile_360x800',
            size: const Size(360, 800),
            selectedScopeId: 'scope-common',
            textScale: 1,
          ),
          (
            name: 'groups_mobile_390x844_text_2x',
            size: const Size(390, 844),
            selectedScopeId: 'scope-common',
            textScale: 2,
          ),
        ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      tester.view.physicalSize = evidence.size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = evidence.textScale;
      final router = GoRouter(
        initialLocation: '/projects/project-layout',
        routes: [
          GoRoute(
            path: '/projects/:projectId',
            builder: (_, _) => const YorksV1WorkspaceShell(
              child: YorksV1ProjectWorkspaceScreen(
                projectId: 'project-layout',
                initialTab: YorksV1ProjectWorkspaceTab.boq,
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1FeatureFlagsProvider.overrideWithValue(_featureFlags),
            yorksV1CurrentPermissionSnapshotProvider.overrideWith(
              (ref) => YorksV1TestPermissionController(
                yorksV1TrustedFeaturePermissionState(),
              ),
            ),
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.projectEngineer,
            ),
            yorksV1AuthUserIdProvider.overrideWithValue('engineer-1'),
            yorksV1ProjectPortfolioProvider.overrideWith(
              (ref) async => [_portfolioItem],
            ),
            yorksV1BoqGroupsProvider(
              'project-layout',
            ).overrideWith((ref) async => _groups),
            yorksV1ScopedBoqGroupsProvider(
              const YorksV1BoqScopeQuery(projectId: 'project-layout'),
            ).overrideWith((ref) async => _groups),
            yorksV1ScopedBoqGroupsProvider(
              const YorksV1BoqScopeQuery(
                projectId: 'project-layout',
                scopeId: 'scope-common',
              ),
            ).overrideWith((ref) async => _groups),
            yorksV1BoqScopeSelectionProvider(
              'project-layout',
            ).overrideWith((ref) => evidence.selectedScopeId),
            yorksV1MaterialRequestListProvider(
              'project-layout',
            ).overrideWith((ref) async => _requests),
            yorksV1MaterialRequestScopesProvider(
              'project-layout',
            ).overrideWith((ref) async => _scopes),
            yorksV1DocumentWorkspaceProvider('project-layout').overrideWith(
              (ref) async => const YorksV1DocumentWorkspace(
                projectId: 'project-layout',
                documents: [],
                auditEntries: [],
              ),
            ),
            yorksV1ActiveProjectTeamDirectoryProvider.overrideWith(
              (ref) async => _directory,
            ),
          ],
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (evidence.selectedScopeId != null &&
          find
              .byKey(const ValueKey('boq-desktop-group-browser'))
              .evaluate()
              .isEmpty &&
          find
              .byKey(const ValueKey('boq-mobile-folder-list'))
              .evaluate()
              .isEmpty) {
        if (evidence.size.width > 720) {
          await tester.tap(find.byType(DropdownButtonFormField<String>));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Common / All Buildings').last);
        } else {
          await tester.tap(
            find.byKey(const ValueKey('boq-mobile-scope-scope-common')),
          );
        }
        await tester.pumpAndSettle();
      }

      if (evidence.size.width > 720) {
        expect(find.textContaining('N-19957.1 NEXUS'), findsOneWidget);
      }
      expect(find.text('BOQ'), findsWidgets);
      if (evidence.selectedScopeId == null) {
        if (evidence.size.width > 720) {
          expect(find.text('Buildings / scopes'), findsOneWidget);
        } else {
          expect(
            find.byKey(const ValueKey('boq-mobile-embedded-workspace')),
            findsOneWidget,
          );
        }
      } else if (evidence.size.width > 720) {
        expect(
          find.byKey(const ValueKey('boq-desktop-group-browser')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('boq-group-search')), findsOneWidget);
      } else {
        expect(
          find.byKey(const ValueKey('boq-mobile-folder-list')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull, reason: evidence.name);

      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/logo.png'),
          tester.element(find.byType(YorksV1WorkspaceShell)),
        ),
      );
      await tester.pump();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/project_workspace/boq_${evidence.name}.png'),
      );
    }
  });
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

const _featureFlags = YorksV1FeatureFlags(
  foundation: true,
  projects: true,
  boq: true,
  excel: true,
  requests: true,
  arrangement: true,
  logistics: true,
  returnsDocuments: true,
  documents: true,
  accounts: true,
  teamChat: true,
);

const _viewports = <({String name, Size size, double textScale})>[
  (name: 'desktop_1440x1066', size: Size(1440, 1066), textScale: 1),
  (name: 'tablet_landscape_1024x768', size: Size(1024, 768), textScale: 1),
  (name: 'tablet_portrait_820x1180', size: Size(820, 1180), textScale: 1),
  (name: 'mobile_390x844', size: Size(390, 844), textScale: 1),
  (name: 'mobile_360x800', size: Size(360, 800), textScale: 1),
  (name: 'mobile_390x844_text_2x', size: Size(390, 844), textScale: 2),
];

final _portfolioItem = YorksV1ProjectPortfolioItem(
  project: YorksV1Project(
    id: 'project-layout',
    reference: 'YRA-324',
    name:
        'N-19957.1 NEXUS (POWER) BULK TRANSMISSION SCHEME PHASE 1: SUPPLY AND INSTALLATION OF 132/33kV SUBSTATIONS & RELATED INTERCONNECTION 132kV CABLE',
    state: YorksV1ProjectLifecycle.active,
    version: 1,
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 18, 10, 24),
    siteLocation: 'Al Dhafra, Sallam City, Abu Dhabi',
    createdByAuthUserId: 'engineer-1',
  ),
  activeBuildingCount: 2,
  activeProjectEngineerCount: 3,
  activeSiteEngineerCount: 2,
  activeMembers: _members,
);

final _members = <YorksV1ProjectMember>[
  _member(
    id: 'member-1',
    authUserId: 'engineer-1',
    name: 'Masaud Khan',
    role: YorksV1ProjectMembershipRole.projectEngineer,
  ),
  _member(
    id: 'member-2',
    authUserId: 'engineer-2',
    name: 'Arnal Palma',
    role: YorksV1ProjectMembershipRole.projectEngineer,
  ),
  _member(
    id: 'member-3',
    authUserId: 'engineer-3',
    name: 'Avelino Importante',
    role: YorksV1ProjectMembershipRole.projectEngineer,
  ),
  _member(
    id: 'member-4',
    authUserId: 'site-1',
    name: 'Tariq Mehdi',
    role: YorksV1ProjectMembershipRole.siteEngineer,
  ),
  _member(
    id: 'member-5',
    authUserId: 'site-2',
    name: 'Tanveer Ahmed',
    role: YorksV1ProjectMembershipRole.siteEngineer,
  ),
];

YorksV1ProjectMember _member({
  required String id,
  required String authUserId,
  required String name,
  required YorksV1ProjectMembershipRole role,
}) => YorksV1ProjectMember(
  id: id,
  projectId: 'project-layout',
  memberAuthUserId: authUserId,
  displayName: name,
  projectRole: role,
  effectiveFrom: DateTime.utc(2026, 9, 1),
  createdAt: DateTime.utc(2026, 9, 1),
);

const _directory = <YorksV1ProjectTeamDirectoryMember>[
  YorksV1ProjectTeamDirectoryMember(
    authUserId: 'engineer-1',
    displayName: 'Masaud Khan',
    eligibleRole: YorksV1Role.projectEngineer,
  ),
  YorksV1ProjectTeamDirectoryMember(
    authUserId: 'engineer-2',
    displayName: 'Arnal Palma',
    eligibleRole: YorksV1Role.projectEngineer,
  ),
  YorksV1ProjectTeamDirectoryMember(
    authUserId: 'engineer-3',
    displayName: 'Avelino Importante',
    eligibleRole: YorksV1Role.projectEngineer,
  ),
  YorksV1ProjectTeamDirectoryMember(
    authUserId: 'site-1',
    displayName: 'Tariq Mehdi',
    eligibleRole: YorksV1Role.siteEngineer,
  ),
  YorksV1ProjectTeamDirectoryMember(
    authUserId: 'site-2',
    displayName: 'Tanveer Ahmed',
    eligibleRole: YorksV1Role.siteEngineer,
  ),
];

final _groups = <YorksV1BoqGroup>[
  _group(id: 'group-1', name: 'Workshop Materials', rows: 20, order: 1),
  _group(id: 'group-2', name: 'Cable Schedule', rows: 17, order: 2),
  _group(id: 'group-3', name: 'Containment', rows: 15, order: 3),
];

YorksV1BoqGroup _group({
  required String id,
  required String name,
  required int rows,
  required int order,
}) => YorksV1BoqGroup(
  id: id,
  projectId: 'project-layout',
  name: name,
  worksheetTitle: name,
  displayOrder: order,
  isCustom: order > 1,
  isArchived: false,
  version: 1,
  rowCount: rows,
  columnCount: 7,
  updatedAt: DateTime.utc(2026, 9, 18, 15, 17 - order),
  lastEditedAt: DateTime.utc(2026, 9, 18, 15, 17 - order),
  lastEditedBy: 'Masaud Khan',
  lastEditedRole: 'project_engineer',
  scopeId: 'scope-common',
  scopeKind: 'common',
  scopeCode: 'COMMON',
  scopeName: 'Common / All Buildings',
);

const _scopes = <YorksV1MaterialRequestScopeOption>[
  YorksV1MaterialRequestScopeOption(
    id: 'scope-df1w',
    projectId: 'project-layout',
    name: 'DF1W-132/33kV BUILDING',
    kind: 'building',
  ),
  YorksV1MaterialRequestScopeOption(
    id: 'scope-df5w',
    projectId: 'project-layout',
    name: 'DF5W-132/33kV BUILDING',
    kind: 'building',
  ),
  YorksV1MaterialRequestScopeOption(
    id: 'scope-common',
    projectId: 'project-layout',
    name: 'Common / All Buildings',
    kind: 'common',
  ),
];

final _requests = List<YorksV1MaterialRequest>.generate(24, (index) {
  final state = switch (index) {
    0 || 6 || 7 || 8 => YorksV1MaterialRequestState.awaitingRequestApproval,
    1 => YorksV1MaterialRequestState.approvedForArrangement,
    2 || 9 => YorksV1MaterialRequestState.dispatched,
    3 => YorksV1MaterialRequestState.draft,
    >= 18 => YorksV1MaterialRequestState.closed,
    _ => YorksV1MaterialRequestState.approved,
  };
  final scope = switch (index % 3) {
    0 => _scopes[0],
    1 => _scopes[1],
    _ => _scopes[2],
  };
  return YorksV1MaterialRequest(
    id: 'request-$index',
    projectId: 'project-layout',
    projectReference: 'YRA-324',
    projectName: _portfolioItem.project.name,
    scopeId: scope.id,
    scopeName: scope.name,
    state: state,
    recordVersion: 1,
    createdAt: DateTime.utc(2026, 9, 18, 8),
    updatedAt: DateTime.utc(
      2026,
      9,
      18,
      10,
      24,
    ).subtract(Duration(minutes: index * 18)),
    submittedAt: state == YorksV1MaterialRequestState.draft
        ? null
        : DateTime.utc(
            2026,
            9,
            18,
            10,
            24,
          ).subtract(Duration(minutes: index * 18)),
    lines: [
      for (var line = 0; line < (index % 4) + 4; line++)
        YorksV1MaterialRequestLine(
          id: 'request-$index-line-$line',
          displayOrder: line + 1,
          source: YorksV1MaterialRequestLineSource.boq,
          description: 'Controlled material item ${line + 1}',
          quantity: '${line + 1}',
          unit: 'Nos',
        ),
    ],
    timing: YorksV1MaterialRequestTiming.normal,
    requestNumber: 'YRA324-MR${(23 - index).toString().padLeft(3, '0')}',
    requesterDisplayName: index.isEven ? 'Arnal Palma' : 'Masaud Khan',
    requesterProjectRole: 'project_engineer',
    currentActionOwnerRole: switch (state) {
      YorksV1MaterialRequestState.awaitingRequestApproval => 'project_engineer',
      YorksV1MaterialRequestState.approvedForArrangement ||
      YorksV1MaterialRequestState.approved => 'procurement',
      YorksV1MaterialRequestState.dispatched => 'site_engineer',
      _ => 'requester',
    },
  );
});

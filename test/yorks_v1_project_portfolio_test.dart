import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/projects/presentation/screens/yorks_v1_projects_screen.dart';
import 'package:material_ledger/shared/models/yorks_v1_boq.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_document.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request.dart';
import 'package:material_ledger/shared/models/yorks_v1_project.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_portfolio.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_boq_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_documents_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_material_request_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_portfolio_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_portfolio_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/yorks_v1_permission_test_support.dart';

void main() {
  test('project references use natural YRA ordering', () {
    final references = ['YRA-100', 'YRA-9', 'YRA-21', 'YRA-2'];

    references.sort(compareYorksProjectReferences);

    expect(references, ['YRA-2', 'YRA-9', 'YRA-21', 'YRA-100']);
  });

  test(
    'portfolio composes only authorized non-commercial project context',
    () async {
      final repository = YorksV1SupabaseProjectPortfolioRepository(
        featureFlags: _enabledFlags,
        dataClient: _FakePortfolioDataClient(),
      );

      final portfolio = await repository.listPortfolio();

      expect(portfolio, hasLength(1));
      expect(portfolio.single.project.reference, 'YRK-2601');
      expect(portfolio.single.clientName, 'Yorks Client');
      expect(portfolio.single.activeBuildingCount, 2);
      expect(portfolio.single.activeProjectEngineerCount, 1);
      expect(portfolio.single.activeSiteEngineerCount, 1);
      expect(portfolio.single.activeTeamCount, 2);
    },
  );

  test(
    'portfolio fails closed while the project rollout is disabled',
    () async {
      final repository = YorksV1SupabaseProjectPortfolioRepository(
        featureFlags: const YorksV1FeatureFlags(),
        dataClient: _FakePortfolioDataClient(),
      );

      await expectLater(
        repository.listPortfolio(),
        throwsA(
          isA<YorksV1DomainException>().having(
            (error) => error.code,
            'code',
            YorksV1DomainErrorCode.featureDisabled,
          ),
        ),
      );
    },
  );

  test('portfolio load coordinator shares only the active read', () async {
    final repository = _DeferredPortfolioRepository();
    final coordinator = YorksV1ProjectPortfolioLoadCoordinator(repository);

    final first = coordinator.load();
    final follower = coordinator.load();

    expect(identical(first, follower), isTrue);
    expect(repository.calls, 1);
    repository.responses.single.complete([_portfolioItem]);
    expect(await first, [_portfolioItem]);
    expect(await follower, [_portfolioItem]);

    final next = coordinator.load();
    expect(repository.calls, 2);
    repository.responses.last.complete(const []);
    expect(await next, isEmpty);
  });

  test('failed portfolio load is released for a clean retry', () async {
    final repository = _DeferredPortfolioRepository();
    final coordinator = YorksV1ProjectPortfolioLoadCoordinator(repository);

    final failed = coordinator.load();
    repository.responses.single.completeError(StateError('network'));
    await expectLater(failed, throwsStateError);

    final retry = coordinator.load();
    expect(repository.calls, 2);
    repository.responses.last.complete([_portfolioItem]);
    expect(await retry, [_portfolioItem]);
  });

  test(
    'portfolio invalidation joins the same authority-scoped in-flight read',
    () async {
      final repository = _DeferredPortfolioRepository();
      final container = _portfolioContainer(repository);
      addTearDown(container.dispose);
      final subscription = container.listen(
        yorksV1ProjectPortfolioProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      final first = container.read(yorksV1ProjectPortfolioProvider.future);
      expect(repository.calls, 1);
      final followers = <Future<List<YorksV1ProjectPortfolioItem>>>[];
      for (var index = 0; index < 20; index++) {
        container.invalidate(yorksV1ProjectPortfolioProvider);
        followers.add(container.read(yorksV1ProjectPortfolioProvider.future));
      }

      expect(repository.calls, 1);
      repository.responses.single.complete([_portfolioItem]);
      expect(await first, [_portfolioItem]);
      for (final follower in await Future.wait(followers)) {
        expect(follower, [_portfolioItem]);
      }
    },
  );

  test('short route gaps reuse the confirmed project context', () async {
    final repository = _ImmediatePortfolioRepository();
    final container = _portfolioContainer(repository);
    addTearDown(container.dispose);
    final firstSubscription = container.listen(
      yorksV1ProjectPortfolioProvider,
      (_, _) {},
      fireImmediately: true,
    );

    await container.read(yorksV1ProjectPortfolioProvider.future);
    expect(repository.calls, 1);
    firstSubscription.close();
    await container.pump();

    final secondSubscription = container.listen(
      yorksV1ProjectPortfolioProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(secondSubscription.close);
    await container.read(yorksV1ProjectPortfolioProvider.future);

    expect(repository.calls, 1);
  });

  test('Material Request revisions do not reload project context', () async {
    final repository = _ImmediatePortfolioRepository();
    final realtimeNotifier = _TestMaterialRequestRealtimeNotifier();
    final container = _portfolioContainer(
      repository,
      realtimeNotifier: realtimeNotifier,
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      yorksV1ProjectPortfolioProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await container.read(yorksV1ProjectPortfolioProvider.future);
    expect(repository.calls, 1);
    realtimeNotifier.bumpForTest();
    await container.pump();

    expect(repository.calls, 1);
  });

  test('Material Request revisions do not reload project totals', () async {
    final dataClient = _CountingOverviewDataClient();
    final realtimeNotifier = _TestMaterialRequestRealtimeNotifier();
    final container = ProviderContainer(
      overrides: [
        yorksV1FeatureFlagsProvider.overrideWithValue(_enabledFlags),
        yorksV1ProjectOverviewDataClientProvider.overrideWithValue(dataClient),
        yorksV1CurrentPermissionSnapshotProvider.overrideWith(
          (ref) => YorksV1TestPermissionController(
            yorksV1TrustedFeaturePermissionState(),
          ),
        ),
        yorksV1MaterialRequestRealtimeRevisionProvider.overrideWith(
          (ref) => realtimeNotifier,
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      yorksV1ProjectOverviewProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await container.read(yorksV1ProjectOverviewProvider.future);
    expect(dataClient.calls, 1);
    realtimeNotifier.bumpForTest();
    await container.pump();

    expect(dataClient.calls, 1);
  });

  test(
    'exact-role change cannot reuse or be overwritten by an older read',
    () async {
      final repository = _DeferredPortfolioRepository();
      final container = _portfolioContainer(repository);
      addTearDown(container.dispose);
      final subscription = container.listen(
        yorksV1ProjectPortfolioProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      final oldAuthority = container.read(
        yorksV1ProjectPortfolioProvider.future,
      );
      expect(repository.calls, 1);
      container.read(_testProjectRoleProvider.notifier).state =
          YorksV1Role.procurement;
      await container.pump();
      final currentAuthority = container.read(
        yorksV1ProjectPortfolioProvider.future,
      );

      expect(repository.calls, 2);
      expect(container.read(yorksV1ProjectPortfolioProvider).hasValue, isFalse);
      repository.responses[1].complete([_portfolioItem]);
      expect(await currentAuthority, [_portfolioItem]);
      repository.responses[0].complete(const []);
      // Riverpod forwards an already-observed `.future` to the replacement
      // provider after invalidation. Its value must therefore remain the new
      // authority result even when the abandoned backend call completes last.
      expect(await oldAuthority, [_portfolioItem]);
      await container.pump();
      expect(container.read(yorksV1ProjectPortfolioProvider).value, [
        _portfolioItem,
      ]);
    },
  );

  testWidgets(
    'project Accounts does not mount unrelated MR BOQ or document reads',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      var requestLoads = 0;
      var scopeLoads = 0;
      var boqLoads = 0;
      var documentLoads = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1FeatureFlagsProvider.overrideWithValue(
              _accountsEnabledFlags,
            ),
            yorksV1CurrentPermissionSnapshotProvider.overrideWith(
              (ref) => YorksV1TestPermissionController(
                yorksV1TrustedFeaturePermissionState(),
              ),
            ),
            yorksV1CurrentRoleProvider.overrideWithValue(YorksV1Role.admin),
            yorksV1AuthUserIdProvider.overrideWithValue('auth-user'),
            yorksV1ProjectPortfolioProvider.overrideWith(
              (ref) async => [_portfolioItem],
            ),
            yorksV1MaterialRequestListProvider('project-1').overrideWith((
              ref,
            ) async {
              requestLoads += 1;
              return const <YorksV1MaterialRequest>[];
            }),
            yorksV1MaterialRequestScopesProvider('project-1').overrideWith((
              ref,
            ) async {
              scopeLoads += 1;
              return const <YorksV1MaterialRequestScopeOption>[];
            }),
            yorksV1BoqGroupsProvider('project-1').overrideWith((ref) async {
              boqLoads += 1;
              return const <YorksV1BoqGroup>[];
            }),
            yorksV1DocumentWorkspaceProvider('project-1').overrideWith((
              ref,
            ) async {
              documentLoads += 1;
              return const YorksV1DocumentWorkspace(
                projectId: 'project-1',
                documents: [],
                auditEntries: [],
              );
            }),
          ],
          child: const MaterialApp(
            home: YorksV1ProjectWorkspaceScreen(
              projectId: 'project-1',
              initialTab: YorksV1ProjectWorkspaceTab.accounts,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(requestLoads, 0);
      expect(scopeLoads, 0);
      expect(boqLoads, 0);
      expect(documentLoads, 0);
    },
  );

  testWidgets('R35 portfolio is responsive and procurement is view only', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final item = _portfolioItem;

    for (final size in [const Size(1366, 768), const Size(360, 800)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.procurement,
            ),
            yorksV1CurrentPermissionSnapshotProvider.overrideWith(
              (ref) => YorksV1TestPermissionController(
                yorksV1TrustedFeaturePermissionState(
                  role: YorksV1Role.procurement,
                ),
              ),
            ),
            yorksV1ProjectPortfolioProvider.overrideWith((ref) async => [item]),
          ],
          child: const MaterialApp(home: YorksV1ProjectsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(item.project.name), findsOneWidget);
      expect(
        find.text(YorksV1ProjectStrings.viewOnlyPortfolio.primary),
        findsOneWidget,
      );
      expect(
        find.text(YorksV1ProjectStrings.createProject.primary),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

const _enabledFlags = YorksV1FeatureFlags(foundation: true, projects: true);

const _accountsEnabledFlags = YorksV1FeatureFlags(
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
);

final _portfolioItem = YorksV1ProjectPortfolioItem(
  project: YorksV1Project(
    id: 'project-1',
    reference: 'YRK-2601',
    name: 'Harbour Tower HVAC',
    state: YorksV1ProjectLifecycle.active,
    version: 3,
    createdAt: DateTime.utc(2026, 7, 1),
    updatedAt: DateTime.utc(2026, 8, 1),
    siteLocation: 'Abu Dhabi',
    currentActionOwnerRole: 'procurement',
  ),
  clientName: 'Yorks Client',
  activeBuildingCount: 2,
  activeProjectEngineerCount: 1,
  activeSiteEngineerCount: 1,
);

class _FakePortfolioDataClient implements YorksV1ProjectPortfolioDataClient {
  @override
  Future<List<Map<String, dynamic>>> listProjectMembers(
    List<String> projectIds,
  ) async => [
    {
      'project_id': 'project-1',
      'project_role': 'project_engineer',
      'effective_from': '2020-01-01T00:00:00.000Z',
      'effective_to': null,
    },
    {
      'project_id': 'project-1',
      'project_role': 'site_engineer',
      'effective_from': '2020-01-01T00:00:00.000Z',
      'effective_to': null,
    },
    {
      'project_id': 'project-1',
      'project_role': 'site_engineer',
      'effective_from': '2020-01-01T00:00:00.000Z',
      'effective_to': '2021-01-01T00:00:00.000Z',
    },
  ];

  @override
  Future<List<Map<String, dynamic>>> listProjectParties(
    List<String> projectIds,
  ) async => [
    {
      'project_id': 'project-1',
      'party_kind': 'client',
      'party_order': 0,
      'party_name': 'Yorks Client',
    },
  ];

  @override
  Future<List<Map<String, dynamic>>> listProjectScopes(
    List<String> projectIds,
  ) async => [
    {'project_id': 'project-1', 'scope_kind': 'building', 'is_active': true},
    {'project_id': 'project-1', 'scope_kind': 'building', 'is_active': true},
  ];

  @override
  Future<List<Map<String, dynamic>>> listProjects() async => [
    {
      'id': 'project-1',
      'project_ref': 'YRK-2601',
      'name': 'Harbour Tower HVAC',
      'project_site': 'Abu Dhabi',
      'state': 'active',
      'current_action_owner_role': 'procurement',
      'record_version': 3,
      'created_at': '2026-07-01T00:00:00.000Z',
      'updated_at': '2026-08-01T00:00:00.000Z',
    },
  ];
}

ProviderContainer _portfolioContainer(
  YorksV1ProjectPortfolioRepository repository, {
  _TestMaterialRequestRealtimeNotifier? realtimeNotifier,
}) => ProviderContainer(
  overrides: [
    yorksV1ProjectPortfolioRepositoryProvider.overrideWithValue(repository),
    yorksV1AuthUserIdProvider.overrideWithValue('auth-user'),
    yorksV1CurrentRoleProvider.overrideWith(
      (ref) => ref.watch(_testProjectRoleProvider),
    ),
    yorksV1CurrentPermissionSnapshotProvider.overrideWith(
      (ref) => YorksV1TestPermissionController(
        yorksV1TrustedFeaturePermissionState(),
      ),
    ),
    if (realtimeNotifier != null)
      yorksV1MaterialRequestRealtimeRevisionProvider.overrideWith(
        (ref) => realtimeNotifier,
      ),
  ],
);

final _testProjectRoleProvider = StateProvider<YorksV1Role?>(
  (ref) => YorksV1Role.admin,
);

class _DeferredPortfolioRepository
    implements YorksV1ProjectPortfolioRepository {
  final responses = <Completer<List<YorksV1ProjectPortfolioItem>>>[];
  int get calls => responses.length;

  @override
  Future<List<YorksV1ProjectPortfolioItem>> listPortfolio() {
    final response = Completer<List<YorksV1ProjectPortfolioItem>>();
    responses.add(response);
    return response.future;
  }
}

class _ImmediatePortfolioRepository
    implements YorksV1ProjectPortfolioRepository {
  int calls = 0;

  @override
  Future<List<YorksV1ProjectPortfolioItem>> listPortfolio() async {
    calls += 1;
    return [_portfolioItem];
  }
}

class _CountingOverviewDataClient implements YorksV1ProjectOverviewDataClient {
  int calls = 0;

  @override
  Future<Map<String, dynamic>> getOverview({required int limit}) async {
    calls += 1;
    return {
      'items': <Object?>[],
      'counts': {'total': 0, 'active': 0, 'on_hold': 0, 'completed': 0},
    };
  }
}

class _TestMaterialRequestRealtimeNotifier
    extends YorksV1MaterialRequestRealtimeNotifier {
  _TestMaterialRequestRealtimeNotifier()
    : super(enabled: false, authUserId: null, client: null);

  void bumpForTest() => state += 1;
}

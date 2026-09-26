import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/accounts/application/accounts_portfolio_providers.dart';
import 'package:material_ledger/features/accounts/application/accounts_providers.dart';
import 'package:material_ledger/features/accounts/application/accounts_receivables_providers.dart';
import 'package:material_ledger/features/accounts/application/accounts_records_providers.dart';
import 'package:material_ledger/features/accounts/application/accounts_supplier_providers.dart';
import 'package:material_ledger/features/accounts/data/accounts_portfolio_repository.dart';
import 'package:material_ledger/features/accounts/data/accounts_receivables_repository.dart';
import 'package:material_ledger/features/accounts/data/accounts_records_repository.dart';
import 'package:material_ledger/features/accounts/data/accounts_repository.dart';
import 'package:material_ledger/features/accounts/data/accounts_supplier_repository.dart';
import 'package:material_ledger/features/accounts/domain/accounts_decimal.dart';
import 'package:material_ledger/features/accounts/domain/accounts_models.dart';
import 'package:material_ledger/features/accounts/domain/accounts_portfolio_models.dart';
import 'package:material_ledger/features/accounts/domain/accounts_receivables_inputs.dart';
import 'package:material_ledger/features/accounts/domain/accounts_receivables_models.dart';
import 'package:material_ledger/features/accounts/domain/accounts_records_models.dart';
import 'package:material_ledger/features/accounts/domain/accounts_supplier_models.dart';
import 'package:material_ledger/features/accounts/presentation/screens/yorks_accounts_screens.dart';
import 'package:material_ledger/features/accounts/presentation/screens/yorks_project_accounts_overview.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_document.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_documents_repository_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_documents_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Use the shipped typeface so layout goldens reveal real wrapping and
    // density, rather than the rectangular Ahem test-font placeholders.
    final font = FontLoader('NexusSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final arabic = FontLoader('NotoSansArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
    await Future.wait([font.load(), arabic.load()]);
  });

  testWidgets('Accounts portfolio is a dense desktop register', (tester) async {
    await _pumpPortfolio(tester, const Size(1440, 1000));

    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Accounts Portfolio'), findsOneWidget);
    expect(find.textContaining('YRA-322'), findsWidgets);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(YorksAccountsPortfolioScreen),
      matchesGoldenFile('goldens/yorks_r39_accounts_t05_portfolio_desktop.png'),
    );
  });

  testWidgets('Accounts portfolio becomes project cards at 390px', (
    tester,
  ) async {
    await _pumpPortfolio(tester, const Size(390, 844));

    expect(find.byType(DataTable), findsNothing);
    await tester.scrollUntilVisible(
      find.text('YRA-322'),
      360,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('YRA-322'), findsOneWidget);
    expect(find.byIcon(Icons.folder_outlined), findsWidgets);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(YorksAccountsPortfolioScreen),
      matchesGoldenFile('goldens/yorks_r39_accounts_t05_portfolio_mobile.png'),
    );
  });

  testWidgets(
    'Accounts control centre matches the desktop overview hierarchy',
    (tester) async {
      await _pumpPortfolio(tester, const Size(1440, 1000), controlCentre: true);

      expect(find.text('Confirmed Work'), findsWidgets);
      expect(find.text('Available to Claim'), findsWidgets);
      expect(find.text('Claimed (Submitted)'), findsOneWidget);
      expect(find.text('Certified by Client'), findsOneWidget);
      expect(find.text('Paid to Yorks'), findsOneWidget);
      expect(find.text('Financial Health'), findsOneWidget);
      expect(find.text('Project Accounts'), findsOneWidget);
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('Alerts & Notifications'), findsOneWidget);
      expect(find.text('Recent Activities'), findsOneWidget);
      expect(find.text('My Action Queues'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(YorksAccountsPortfolioScreen),
        matchesGoldenFile('goldens/yorks_r39_accounts_overview_desktop.png'),
      );
    },
  );

  testWidgets('Accounts control centre is card-based and usable at 390px', (
    tester,
  ) async {
    await _pumpPortfolio(tester, const Size(390, 844), controlCentre: true);

    expect(find.byType(DataTable), findsNothing);
    expect(find.text('Financial Health'), findsOneWidget);
    await expectLater(
      find.byType(YorksAccountsPortfolioScreen),
      matchesGoldenFile('goldens/yorks_r39_accounts_overview_mobile.png'),
    );
    await tester.scrollUntilVisible(
      find.text('Project Accounts'),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Project Accounts'), findsOneWidget);
    expect(find.textContaining('YRA-322'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Accounts overview reloads after its protected permission epoch changes',
    (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final epoch = StateProvider<YorksAccountsPermissionEpoch>(
        (ref) => (
          revision: 1,
          trusted: true,
          stale: false,
          revisionSignalHealthy: true,
        ),
      );
      final repository = _CountingPortfolioRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1AuthUserIdProvider.overrideWithValue('accountant-1'),
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.accountant,
            ),
            yorksAccountsPermissionEpochProvider.overrideWith(
              (ref) => ref.watch(epoch),
            ),
            yorksAccountsPortfolioRepositoryProvider.overrideWithValue(
              repository,
            ),
          ],
          child: const MaterialApp(
            home: YorksAccountsPortfolioScreen(controlCentre: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.portfolioLoads, 1);
      expect(find.textContaining('YRA-322'), findsWidgets);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(YorksAccountsPortfolioScreen)),
      );
      container.read(epoch.notifier).state = (
        revision: 2,
        trusted: true,
        stale: false,
        revisionSignalHealthy: true,
      );
      await tester.pumpAndSettle();

      expect(repository.portfolioLoads, 2);
      expect(
        find.byKey(const ValueKey('accounts-overview-skeleton')),
        findsNothing,
      );
      expect(find.textContaining('YRA-322'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Billing Progress exposes protected office columns on desktop', (
    tester,
  ) async {
    await _pumpProjectBilling(tester, const Size(1366, 900));

    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Stage Value'), findsOneWidget);
    expect(find.text('Eligible Amount'), findsOneWidget);
    expect(find.text('Already Claimed'), findsOneWidget);
    expect(find.text('AED 8,400,000.00'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Project Accounts dashboard renders authorized desktop data', (
    tester,
  ) async {
    await _pumpProjectTab(
      tester,
      const Size(1366, 900),
      YorksProjectAccountsTab.overview,
    );

    expect(find.text('Commercial progress by building'), findsOneWidget);
    expect(find.text('Client collections'), findsOneWidget);
    expect(find.text('Position by building'), findsOneWidget);
    expect(find.text('Baseline snapshot'), findsOneWidget);
    expect(find.text('Substation Building'), findsWidgets);
    expect(find.text('AED 8,400,000.00'), findsWidgets);
    expect(find.text('Client Certified'), findsOneWidget);
    expect(find.text('Amount Paid Till Date'), findsWidgets);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(YorksProjectAccountsScreen),
      matchesGoldenFile(
        'goldens/yorks_r39_project_accounts_dashboard_desktop.png',
      ),
    );
  });

  testWidgets('Embedded project Accounts does not duplicate project chrome', (
    tester,
  ) async {
    await _pumpProjectTab(
      tester,
      const Size(1366, 900),
      YorksProjectAccountsTab.overview,
      overviewRepository: _Repository(projectOverview: _adminProjectOverview),
    );

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('BOQ'), findsNothing);
    expect(find.text('Material Requests'), findsNothing);
    expect(find.text('Material Movement'), findsNothing);
    expect(find.byTooltip('Project actions'), findsNothing);
    expect(find.text('Commercial progress by building'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Project Accounts dashboard stays usable at tablet width', (
    tester,
  ) async {
    await _pumpProjectTab(
      tester,
      const Size(820, 1180),
      YorksProjectAccountsTab.overview,
    );
    expect(find.text('Commercial progress by building'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(YorksProjectAccountsScreen),
      matchesGoldenFile(
        'goldens/yorks_r39_project_accounts_dashboard_tablet.png',
      ),
    );
  });

  for (final size in [const Size(1440, 900), const Size(1024, 768)]) {
    testWidgets(
      'Project Accounts dashboard has no overflow at ${size.width}px',
      (tester) async {
        await _pumpProjectTab(tester, size, YorksProjectAccountsTab.overview);
        expect(find.text('Commercial progress by building'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Project Accounts dashboard uses cards at 390px', (tester) async {
    await _pumpProjectTab(
      tester,
      const Size(390, 844),
      YorksProjectAccountsTab.overview,
    );
    expect(find.byType(DataTable), findsNothing);
    expect(find.text('Client collections'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(YorksProjectAccountsScreen),
      matchesGoldenFile(
        'goldens/yorks_r39_project_accounts_dashboard_mobile.png',
      ),
    );
  });

  testWidgets('Project Accounts dashboard shows building position at 360px', (
    tester,
  ) async {
    await _pumpProjectTab(
      tester,
      const Size(360, 800),
      YorksProjectAccountsTab.overview,
    );
    await tester.scrollUntilVisible(
      find.text('Position by building'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Substation Building'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Progress-only viewer sees no commercial dashboard amounts', (
    tester,
  ) async {
    await _pumpProjectTab(
      tester,
      const Size(1366, 900),
      YorksProjectAccountsTab.overview,
      overviewRepository: const _ProgressOnlyOverviewRepository(),
      projectRepository: const _ProgressOnlyProjectRepository(),
    );
    expect(find.text('Commercial progress by building'), findsOneWidget);
    expect(find.textContaining('AED'), findsNothing);
    expect(find.text('Client collections'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Uninitialized project Accounts offers baseline setup only to an authorized configurator',
    (tester) async {
      var opened = false;
      final emptyBaseline = YorksAccountsBaselineProjection(
        schemaVersion: 2,
        projectId: 'project-322',
        baseline: null,
        physicalBuildings: _baseline.physicalBuildings,
        stageTemplates: _baseline.stageTemplates,
        buildingAllocations: const [],
        stageAllocations: const [],
        capabilities: _accountsCapabilities,
        commands: YorksAccountsCommandAvailability.fromRpcJson(const {}),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: YorksProjectAccountsOverview(
              overview: _projectOverview,
              baseline: emptyBaseline,
              progress: _progress,
              language: AppLanguage.english,
              onBilling: () => opened = true,
              onClaims: () {},
              onReceipts: () {},
            ),
          ),
        ),
      );
      expect(find.text('Set commercial baseline'), findsNWidgets(2));
      expect(find.text('AED 8,400,000.00'), findsNothing);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Set commercial baseline'),
      );
      expect(opened, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Accounts refresh keeps confirmed page visible beneath its loading indicator',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final repository = _RefreshableOverviewRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1AuthUserIdProvider.overrideWithValue('accountant-1'),
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.accountant,
            ),
            yorksAccountsPermissionEpochProvider.overrideWith(
              (ref) => (
                revision: 1,
                trusted: true,
                stale: false,
                revisionSignalHealthy: true,
              ),
            ),
            yorksAccountsPortfolioRepositoryProvider.overrideWithValue(
              repository,
            ),
          ],
          child: const MaterialApp(
            home: YorksProjectAccountsScreen(projectId: 'project-322'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Billing Progress'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(YorksProjectAccountsScreen)),
      );
      repository.pending = Completer();
      unawaited(
        container
            .read(
              yorksAccountsProjectOverviewControllerProvider(
                'project-322',
              ).notifier,
            )
            .load(),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('accounts-background-loading')),
        findsOneWidget,
      );
      expect(find.text('Billing Progress'), findsOneWidget);
      repository.pending!.complete(_projectOverview);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('accounts-background-loading')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Billing Progress uses cards and a filter sheet at 390px', (
    tester,
  ) async {
    await _pumpProjectBilling(tester, const Size(390, 844));

    expect(find.byType(DataTable), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Design'),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Design'), findsOneWidget);
    expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
    expect(find.textContaining('Stage Value:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Claims and invoices remain actionable at 390px', (tester) async {
    await _pumpProjectTab(
      tester,
      const Size(390, 844),
      YorksProjectAccountsTab.invoices,
    );

    await tester.scrollUntilVisible(
      find.text('INV-YRA322-001'),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Prepare client claim'), findsOneWidget);
    expect(find.text('INV-YRA322-001'), findsOneWidget);
    expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Claims and invoices use the full commercial register on desktop',
    (tester) async {
      await _pumpProjectTab(
        tester,
        const Size(1366, 900),
        YorksProjectAccountsTab.invoices,
      );

      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('Claimed Ex VAT'), findsOneWidget);
      expect(find.text('Certified Ex VAT'), findsOneWidget);
      expect(find.text('Amount Paid Till Date'), findsOneWidget);
      expect(find.text('INV-YRA322-001'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Supplier bills remain searchable and actionable at 390px', (
    tester,
  ) async {
    await _pumpProjectTab(
      tester,
      const Size(390, 844),
      YorksProjectAccountsTab.supplierBills,
      overviewRepository: const _SupplierOverviewRepository(),
    );

    await tester.scrollUntilVisible(
      find.text('SUP-001'),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('New supplier bill'), findsOneWidget);
    expect(find.text('SUP-001'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Supplier bills expose evidence and payment states on desktop', (
    tester,
  ) async {
    await _pumpProjectTab(
      tester,
      const Size(1366, 900),
      YorksProjectAccountsTab.supplierBills,
      overviewRepository: const _SupplierOverviewRepository(),
    );

    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('PO / LPO'), findsOneWidget);
    expect(find.text('Accepted delivery'), findsOneWidget);
    expect(find.text('Invoice Evidence'), findsOneWidget);
    expect(find.text('SUP-001'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('T07 critical Accounts views fit every release viewport', (
    tester,
  ) async {
    for (final size in _releaseViewports) {
      await _pumpPortfolio(tester, size);
      expect(
        tester.takeException(),
        isNull,
        reason: 'Portfolio must fit ${size.width}x${size.height}.',
      );

      for (final tab in const [
        YorksProjectAccountsTab.billing,
        YorksProjectAccountsTab.invoices,
        YorksProjectAccountsTab.supplierBills,
        YorksProjectAccountsTab.documents,
        YorksProjectAccountsTab.activity,
      ]) {
        await _pumpProjectTab(
          tester,
          size,
          tab,
          overviewRepository: tab == YorksProjectAccountsTab.supplierBills
              ? const _SupplierOverviewRepository()
              : const _Repository(),
        );
        expect(
          tester.takeException(),
          isNull,
          reason:
              '${tab.name} must fit ${size.width}x${size.height} without overflow.',
        );
      }
    }
  });
}

const _releaseViewports = <Size>[
  Size(1440, 900),
  Size(1366, 768),
  Size(1024, 768),
  Size(820, 1180),
  Size(390, 844),
  Size(360, 800),
];

Future<void> _pumpPortfolio(
  WidgetTester tester,
  Size size, {
  bool controlCentre = false,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksV1AuthUserIdProvider.overrideWithValue('accountant-1'),
        yorksV1CurrentRoleProvider.overrideWithValue(YorksV1Role.accountant),
        yorksAccountsPermissionEpochProvider.overrideWith(
          (ref) => (
            revision: 1,
            trusted: true,
            stale: false,
            revisionSignalHealthy: true,
          ),
        ),
        yorksAccountsPortfolioRepositoryProvider.overrideWithValue(
          const _Repository(),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: YorksAccountsPortfolioScreen(controlCentre: controlCentre),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpProjectBilling(WidgetTester tester, Size size) async {
  await _pumpProjectTab(tester, size, YorksProjectAccountsTab.billing);
}

Future<void> _pumpProjectTab(
  WidgetTester tester,
  Size size,
  YorksProjectAccountsTab tab, {
  YorksAccountsPortfolioRepository overviewRepository = const _Repository(),
  YorksAccountsRepository projectRepository = const _ProjectRepository(),
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksV1AuthUserIdProvider.overrideWithValue('accountant-1'),
        yorksV1CurrentRoleProvider.overrideWithValue(YorksV1Role.accountant),
        yorksAccountsPermissionEpochProvider.overrideWith(
          (ref) => (
            revision: 1,
            trusted: true,
            stale: false,
            revisionSignalHealthy: true,
          ),
        ),
        yorksAccountsPortfolioRepositoryProvider.overrideWithValue(
          overviewRepository,
        ),
        yorksAccountsRepositoryProvider.overrideWithValue(projectRepository),
        yorksAccountsReceivablesRepositoryProvider.overrideWithValue(
          const _ReceivablesRepository(),
        ),
        yorksAccountsSupplierRepositoryProvider.overrideWithValue(
          const _SupplierRepository(),
        ),
        yorksAccountsRecordsRepositoryProvider.overrideWithValue(
          const _RecordsRepository(),
        ),
        yorksV1AccountsDocumentsRepositoryProvider.overrideWithValue(
          const _DocumentsRepository(),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: YorksProjectAccountsScreen(
          projectId: 'project-322',
          initialTab: tab,
        ),
      ),
    ),
  );
  await tester.pump();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(YorksProjectAccountsScreen)),
  );
  await container
      .read(yorksAccountsProjectControllerProvider('project-322').notifier)
      .load();
  if (tab == YorksProjectAccountsTab.invoices) {
    final receivables = container.read(
      yorksAccountsReceivablesControllerProvider('project-322').notifier,
    );
    await Future.wait([receivables.loadClaims(), receivables.loadInvoices()]);
  }
  if (tab == YorksProjectAccountsTab.supplierBills) {
    await container
        .read(yorksAccountsSupplierControllerProvider('project-322').notifier)
        .loadBills();
  }
  if (tab == YorksProjectAccountsTab.documents) {
    await container
        .read(yorksAccountsDocumentsControllerProvider('project-322').notifier)
        .load();
  }
  if (tab == YorksProjectAccountsTab.activity) {
    await container
        .read(yorksAccountsActivityControllerProvider('project-322').notifier)
        .load();
  }
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 250));
}

final class _Repository implements YorksAccountsPortfolioRepository {
  const _Repository({this.projectOverview});

  final YorksAccountsProjectOverviewProjection? projectOverview;

  @override
  Future<YorksAccountsPortfolioProjection> getPortfolio(
    YorksAccountsPortfolioFilters filters,
  ) async => _projection;

  @override
  Future<YorksAccountsProjectOverviewProjection> getProjectOverview(
    String projectId,
  ) async => projectOverview ?? _projectOverview;
}

final class _ProgressOnlyOverviewRepository
    implements YorksAccountsPortfolioRepository {
  const _ProgressOnlyOverviewRepository();

  @override
  Future<YorksAccountsPortfolioProjection> getPortfolio(
    YorksAccountsPortfolioFilters filters,
  ) async => _projection;

  @override
  Future<YorksAccountsProjectOverviewProjection> getProjectOverview(
    String projectId,
  ) async => YorksAccountsProjectOverviewProjection(
    projectId: projectId,
    projectReference: 'YRA-322',
    projectName: 'Nexus Power Transmission Phase 1',
    projectSite: 'Abu Dhabi',
    clientName: null,
    actorExactRole: 'project_engineer',
    capabilities: const YorksAccountsProjectUiCapabilities(
      viewProjectAccounts: true,
      viewValues: false,
      viewSupplierCosts: false,
      suggestProgress: false,
      confirmProgress: false,
      prepareClaim: false,
      manageInvoices: false,
      manageSupplierBills: false,
      approveSupplierPayment: false,
      canExport: false,
    ),
    baseline: const {'status': 'active'},
    progress: const {'confirmed_percent': '12.5', 'building_position': []},
    receivables: null,
    supplier: null,
  );
}

final class _ProgressOnlyProjectRepository implements YorksAccountsRepository {
  const _ProgressOnlyProjectRepository();

  @override
  Future<YorksAccountsBaselineProjection> getBaseline(String projectId) async =>
      _baseline.withoutProtectedValues();

  @override
  Future<YorksAccountsProgressProjection> listProgress(
    String projectId, {
    String? buildingScopeId,
    String? stageKey,
    String? actionOwner,
    bool? hasEvidence,
  }) async => _progress.withoutProtectedValues();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _CountingPortfolioRepository
    implements YorksAccountsPortfolioRepository {
  int portfolioLoads = 0;

  @override
  Future<YorksAccountsPortfolioProjection> getPortfolio(
    YorksAccountsPortfolioFilters filters,
  ) async {
    portfolioLoads++;
    return _projection;
  }

  @override
  Future<YorksAccountsProjectOverviewProjection> getProjectOverview(
    String projectId,
  ) async => _projectOverview;
}

final class _RefreshableOverviewRepository
    implements YorksAccountsPortfolioRepository {
  Completer<YorksAccountsProjectOverviewProjection>? pending;

  @override
  Future<YorksAccountsPortfolioProjection> getPortfolio(
    YorksAccountsPortfolioFilters filters,
  ) async => _projection;

  @override
  Future<YorksAccountsProjectOverviewProjection> getProjectOverview(
    String projectId,
  ) => pending?.future ?? Future.value(_projectOverview);
}

final class _ProjectRepository implements YorksAccountsRepository {
  const _ProjectRepository();

  @override
  Future<YorksAccountsBaselineProjection> getBaseline(String projectId) async =>
      _baseline;

  @override
  Future<YorksAccountsProgressProjection> listProgress(
    String projectId, {
    String? buildingScopeId,
    String? stageKey,
    String? actionOwner,
    bool? hasEvidence,
  }) async => _progress;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ReceivablesRepository
    implements YorksAccountsReceivablesRepository {
  const _ReceivablesRepository();

  @override
  Future<YorksAccountsClaimsProjection> listClaims(
    String projectId, {
    YorksAccountsClaimStatus? status,
    YorksAccountsCompositeCursor? before,
    int limit = 50,
  }) async => _claims;

  @override
  Future<YorksAccountsInvoicesProjection> listInvoices(
    String projectId, {
    YorksAccountsInvoiceStatus? status,
    YorksAccountsDueState? dueState,
    YorksAccountsCompositeCursor? before,
    int limit = 50,
  }) async => _invoices;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _SupplierRepository implements YorksAccountsSupplierRepository {
  const _SupplierRepository();

  @override
  Future<YorksAccountsSupplierBillsProjection> listBills(
    String projectId, {
    String? search,
    YorksAccountsSupplierMatchStatus? matchStatus,
    YorksAccountsSupplierPaymentStatus? paymentStatus,
    YorksAccountsSupplierBillCursor? before,
    int limit = 25,
  }) async => _supplierBills;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RecordsRepository implements YorksAccountsRecordsRepository {
  const _RecordsRepository();

  @override
  Future<YorksAccountsActivityProjection> getActivity(
    String projectId,
    YorksAccountsActivityFilters filters,
  ) async => YorksAccountsActivityProjection(
    projectId: projectId,
    total: 1,
    limit: 50,
    offset: 0,
    entries: [
      YorksAccountsActivityEntry(
        id: 'audit-1',
        eventType: 'accounts.client_invoice.submitted',
        entityType: 'accounts_client_invoice',
        entityId: 'invoice-1',
        projectId: projectId,
        actorAuthUserId: 'accountant-1',
        actorDisplayName: 'Accounts User',
        actorExactRole: 'accountant',
        occurredAt: DateTime.utc(2026, 8, 26, 10),
        reason: 'Submitted for certification review',
      ),
    ],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _DocumentsRepository implements YorksV1AccountsDocumentsRepository {
  const _DocumentsRepository();

  @override
  Future<YorksV1AccountsDocumentWorkspace> getAccountsWorkspace(
    String projectId, {
    String? search,
    YorksV1AccountsDocumentType? documentType,
    bool includeArchived = false,
  }) async => YorksV1AccountsDocumentWorkspace(
    projectId: projectId,
    documents: const [],
    uploadTargets: const [
      YorksV1AccountsDocumentTarget(
        entityType: YorksV1DocumentEntityType.accountsBaselineRevision,
        entityId: 'baseline-1',
        label: 'Baseline revision 1',
      ),
    ],
    canUpload: true,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _SupplierOverviewRepository
    implements YorksAccountsPortfolioRepository {
  const _SupplierOverviewRepository();

  @override
  Future<YorksAccountsPortfolioProjection> getPortfolio(
    YorksAccountsPortfolioFilters filters,
  ) async => _projection;

  @override
  Future<YorksAccountsProjectOverviewProjection> getProjectOverview(
    String projectId,
  ) async => _supplierProjectOverview;
}

final _zero = YorksAccountsDecimal.zero;
final _projection = YorksAccountsPortfolioProjection(
  actorExactRole: 'accountant',
  canExport: true,
  authorizedProjectCount: 2,
  filteredProjectCount: 2,
  totals: YorksAccountsPortfolioTotals(
    projectCount: 2,
    contractBaseline: YorksAccountsDecimal.parse('16800000'),
    confirmedEligible: YorksAccountsDecimal.parse('3104000'),
    availableToClaim: YorksAccountsDecimal.parse('654000'),
    claimed: YorksAccountsDecimal.parse('2450000'),
    certified: YorksAccountsDecimal.parse('1890000'),
    amountPaidTillDate: YorksAccountsDecimal.parse('1320000'),
    stillDue: YorksAccountsDecimal.parse('570000'),
    pdcExposure: YorksAccountsDecimal.parse('200000'),
    actionCount: 3,
  ),
  projects: [
    _project(
      id: 'project-322',
      reference: 'YRA-322',
      name: 'Nexus Power Transmission Phase 1',
      client: 'TAQA Transmission',
      percent: '68',
      certified: '720000',
      paid: '510000',
      due: '210000',
      actions: 2,
    ),
    _project(
      id: 'project-314',
      reference: 'YRA-314',
      name: 'New 220-33kV SS at ICAD-B',
      client: 'Abu Dhabi Distribution',
      percent: '21.3',
      certified: '1170000',
      paid: '810000',
      due: '360000',
      actions: 1,
    ),
  ],
  actionQueue: [
    YorksAccountsActionItem(
      projectId: 'project-322',
      projectReference: 'YRA-322',
      projectName: 'Nexus Power Transmission Phase 1',
      code: 'overdue_invoice',
      ownerRole: 'accountant',
      severity: 'critical',
      count: 2,
      occurredAt: DateTime.utc(2026, 8, 26, 10),
    ),
  ],
  nextActivityAt: null,
  nextProjectId: null,
);

const _uiCapabilities = YorksAccountsProjectUiCapabilities(
  viewProjectAccounts: true,
  viewValues: true,
  viewSupplierCosts: false,
  suggestProgress: false,
  confirmProgress: false,
  prepareClaim: false,
  manageInvoices: true,
  manageSupplierBills: false,
  approveSupplierPayment: false,
  canExport: true,
);

final _projectOverview = YorksAccountsProjectOverviewProjection(
  projectId: 'project-322',
  projectReference: 'YRA-322',
  projectName: 'Nexus Power Transmission Phase 1',
  projectSite: 'Abu Dhabi',
  clientName: 'TAQA Transmission',
  actorExactRole: 'accountant',
  capabilities: _uiCapabilities,
  baseline: {
    'revision_id': 'baseline-1',
    'revision_number': 1,
    'status': 'active',
    'effective_at': '2026-08-26T09:00:00Z',
    'contract_value': '8400000',
    'currency_code': 'AED',
    'payment_terms_days': 90,
    'reminder_lead_days': 10,
  },
  progress: {
    'confirmed_percent': '12.5',
    'suggested_percent': '15',
    'pending_review_count': 0,
    'confirmed_eligible': '1050000',
    'building_position': const [],
  },
  receivables: {
    'claimed': '250000',
    'certified': '200000',
    'amount_paid_till_date': '150000',
    'still_due': '50000',
    'pdc_exposure': '0',
    'recent_invoices': const [],
  },
  supplier: null,
);

final _adminProjectOverview = YorksAccountsProjectOverviewProjection(
  projectId: _projectOverview.projectId,
  projectReference: _projectOverview.projectReference,
  projectName: _projectOverview.projectName,
  projectSite: _projectOverview.projectSite,
  clientName: _projectOverview.clientName,
  actorExactRole: 'admin',
  capabilities: _projectOverview.capabilities,
  baseline: _projectOverview.baseline,
  progress: _projectOverview.progress,
  receivables: _projectOverview.receivables,
  supplier: null,
);

final _supplierProjectOverview = YorksAccountsProjectOverviewProjection(
  projectId: 'project-322',
  projectReference: 'YRA-322',
  projectName: 'Nexus Power Transmission Phase 1',
  projectSite: 'Abu Dhabi',
  clientName: 'TAQA Transmission',
  actorExactRole: 'procurement',
  capabilities: const YorksAccountsProjectUiCapabilities(
    viewProjectAccounts: false,
    viewValues: false,
    viewSupplierCosts: true,
    suggestProgress: false,
    confirmProgress: false,
    prepareClaim: false,
    manageInvoices: false,
    manageSupplierBills: true,
    approveSupplierPayment: false,
    canExport: true,
  ),
  baseline: null,
  progress: null,
  receivables: null,
  supplier: const {
    'total_bills': '105000',
    'paid_bills': '0',
    'outstanding': '105000',
    'matched_count': 0,
    'review_count': 1,
  },
);

const _receivablesCapabilities = YorksAccountsReceivablesCapabilities(
  canViewValues: true,
  prepareClientClaim: true,
  manageClientInvoices: true,
  recordClientCertification: true,
  recordClientPayment: true,
  managePdc: true,
);

const _receivablesCommands = YorksAccountsReceivablesCommands(
  createClaimDraft: true,
  editClaimDraft: true,
  submitClaimToAccounts: true,
  cancelClaim: true,
  createInvoiceDraft: true,
  submitInvoice: true,
  returnInvoice: true,
  cancelInvoice: true,
  recordCertification: true,
  recordPayment: true,
  reversePayment: true,
  createPdc: true,
  transitionPdc: true,
  replacePdc: true,
);

final _claims = YorksAccountsClaimsProjection(
  schemaVersion: 2,
  projectId: 'project-322',
  claims: [
    YorksAccountsClientClaimSummary(
      claimId: 'claim-1',
      claimReference: 'CLM-YRA322-001',
      periodStart: YorksAccountsDate.parse('2026-08-01'),
      periodEnd: YorksAccountsDate.parse('2026-08-25'),
      status: YorksAccountsClaimStatus.invoiced,
      claimedExVat: YorksAccountsDecimal.parse('100000'),
      isStale: false,
      recordVersion: 2,
      createdByAuthUserId: 'engineer-1',
      createdByExactRole: 'project_engineer',
      createdAt: DateTime.utc(2026, 8, 25, 9),
      updatedAt: DateTime.utc(2026, 8, 26, 9),
    ),
  ],
  nextCursor: null,
  capabilities: _receivablesCapabilities,
  commands: _receivablesCommands,
);

final _invoices = YorksAccountsInvoicesProjection(
  schemaVersion: 2,
  projectId: 'project-322',
  invoices: [
    YorksAccountsClientInvoiceSummary(
      invoiceId: 'invoice-1',
      claimId: 'claim-1',
      invoiceReference: 'INV-YRA322-001',
      status: YorksAccountsInvoiceStatus.partiallyCertified,
      claimedExVat: YorksAccountsDecimal.parse('100000'),
      certifiedExVat: YorksAccountsDecimal.parse('80000'),
      totalInclVat: YorksAccountsDecimal.parse('105000'),
      amountPaidTillDate: YorksAccountsDecimal.parse('50000'),
      stillDue: YorksAccountsDecimal.parse('34000'),
      pdcExposure: YorksAccountsDecimal.zero,
      submissionDate: YorksAccountsDate.parse('2026-08-25'),
      dueDate: YorksAccountsDate.parse('2026-11-23'),
      dueState: YorksAccountsDueState.onTrack,
      recordVersion: 3,
      updatedAt: DateTime.utc(2026, 8, 26, 10),
    ),
  ],
  nextCursor: null,
  capabilities: _receivablesCapabilities,
  commands: _receivablesCommands,
);

final _supplierBills = YorksAccountsSupplierBillsProjection(
  projectId: 'project-322',
  items: [
    YorksAccountsSupplierBill(
      supplierBillId: 'supplier-bill-1',
      projectId: 'project-322',
      supplierId: 'supplier-1',
      supplierName: 'Gulf Air Controls LLC',
      supplierInvoiceReference: 'SUP-001',
      invoiceDate: YorksAccountsDate.parse('2026-08-01'),
      dueDate: YorksAccountsDate.parse('2026-08-31'),
      exVatAmount: YorksAccountsDecimal.parse('100000'),
      vatRatePercent: YorksAccountsDecimal.parse('5'),
      vatAmount: YorksAccountsDecimal.parse('5000'),
      totalInclVat: YorksAccountsDecimal.parse('105000'),
      poLpoReference: 'PO-1074',
      poLpoDocumentId: 'document-po-1',
      acceptedReceiptReviewId: null,
      acceptedDeliveryReference: null,
      acceptedDelivery: null,
      supplierInvoiceDocumentId: 'document-invoice-1',
      explicitMismatchReason: 'Accepted delivery is pending',
      matchStatus: YorksAccountsSupplierMatchStatus.review,
      status: YorksAccountsSupplierBillStatus.draft,
      paymentStatus: YorksAccountsSupplierPaymentStatus.blocked,
      paidAmount: YorksAccountsDecimal.zero,
      outstandingAmount: YorksAccountsDecimal.parse('105000'),
      approvalAdminExceptionReason: null,
      approvedAt: null,
      approvedByAuthUserId: null,
      approvedByExactRole: null,
      cancelledAt: null,
      cancellationReason: null,
      notes: null,
      recordVersion: 1,
      createdByAuthUserId: 'procurement-1',
      createdByExactRole: 'procurement',
      createdAt: DateTime.utc(2026, 8, 26, 8),
      updatedAt: DateTime.utc(2026, 8, 26, 8),
    ),
  ],
  nextCursor: null,
  capabilities: const YorksAccountsSupplierCapabilities(
    manageSupplierBills: true,
    approveSupplierBillPayment: false,
    viewSupplierCosts: true,
  ),
  commands: const YorksAccountsSupplierCommands(
    createBill: true,
    editBill: true,
    approveBill: false,
    recordPayment: false,
    reversePayment: false,
    cancelBill: true,
  ),
);

final _accountsCapabilities = const YorksAccountsCapabilities(
  canView: true,
  canViewValues: true,
  canConfigure: true,
  canSuggest: false,
  canConfirm: false,
  canReview: false,
);

final _baseline = YorksAccountsBaselineProjection(
  schemaVersion: 2,
  projectId: 'project-322',
  baseline: YorksAccountsBaselineRevision(
    revisionId: 'baseline-1',
    revisionNumber: 1,
    recordVersion: 1,
    status: 'active',
    contractValue: YorksAccountsDecimal.parse('8400000'),
    currencyCode: 'AED',
    vatRate: YorksAccountsDecimal.parse('5'),
    paymentTermsDays: 90,
    reminderLeadDays: 10,
    reason: 'Approved contract baseline',
    createdAt: DateTime.utc(2026, 8, 26, 9),
    createdBy: 'admin-1',
    managementReviewPolicy: YorksAccountsManagementReviewPolicy(
      alwaysRequired: false,
      thresholdAmount: null,
      confirmingExactRoles: const [],
    ),
  ),
  physicalBuildings: const [
    YorksAccountsPhysicalBuilding(
      buildingScopeId: 'building-1',
      buildingName: 'Substation Building',
      scopeCode: 'SSB',
    ),
  ],
  stageTemplates: [
    YorksAccountsStageTemplate(
      stageKey: 'design',
      stageLabel: 'Design',
      position: 1,
      allocationPercent: YorksAccountsDecimal.parse('10'),
    ),
  ],
  buildingAllocations: [
    YorksAccountsBuildingAllocation(
      allocationId: 'allocation-1',
      buildingScopeId: 'building-1',
      buildingName: 'Substation Building',
      allocationPercent: YorksAccountsDecimal.parse('100'),
      allocatedValue: YorksAccountsDecimal.parse('8400000'),
    ),
  ],
  stageAllocations: [
    YorksAccountsStageAllocation(
      allocationId: 'stage-allocation-1',
      stageKey: 'design',
      stageLabel: 'Design',
      position: 1,
      allocationPercent: YorksAccountsDecimal.parse('10'),
      stageValue: YorksAccountsDecimal.parse('840000'),
    ),
  ],
  capabilities: _accountsCapabilities,
  commands: YorksAccountsCommandAvailability.fromRpcJson(const {
    'revise_baseline': true,
  }),
);

final _progress = YorksAccountsProgressProjection(
  schemaVersion: 2,
  projectId: 'project-322',
  baselineRevisionId: 'baseline-1',
  baselineRevisionNumber: 1,
  progress: [
    YorksAccountsProgressEntry(
      progressEntryId: 'progress-1',
      projectId: 'project-322',
      baselineRevisionId: 'baseline-1',
      buildingScopeId: 'building-1',
      buildingName: 'Substation Building',
      stageKey: 'design',
      stageLabel: 'Design',
      stagePosition: 1,
      recordVersion: 1,
      suggestedPercent: YorksAccountsDecimal.parse('15'),
      confirmedPercent: YorksAccountsDecimal.parse('12.5'),
      reviewStatus: YorksAccountsReviewStatus.notRequired,
      evidenceSummary: 'Approved design package',
      evidenceDocumentIds: const ['document-1'],
      actionOwner: 'accountant',
      stageValue: YorksAccountsDecimal.parse('840000'),
      confirmedEligible: YorksAccountsDecimal.parse('105000'),
      previouslyClaimedAmount: YorksAccountsDecimal.parse('25000'),
      availableToClaim: YorksAccountsDecimal.parse('80000'),
      revisions: const [],
      nextActions: const [],
      updatedAt: DateTime.utc(2026, 8, 26, 10),
    ),
  ],
  totals: YorksAccountsProgressTotals(
    confirmedPercent: YorksAccountsDecimal.parse('12.5'),
    contractValue: YorksAccountsDecimal.parse('8400000'),
    confirmedEligible: YorksAccountsDecimal.parse('105000'),
    availableToClaim: YorksAccountsDecimal.parse('80000'),
  ),
  capabilities: _accountsCapabilities,
  commands: YorksAccountsCommandAvailability.fromRpcJson(const {}),
  nextActions: const [],
);

YorksAccountsPortfolioProject _project({
  required String id,
  required String reference,
  required String name,
  required String client,
  required String percent,
  required String certified,
  required String paid,
  required String due,
  required int actions,
}) => YorksAccountsPortfolioProject(
  projectId: id,
  projectReference: reference,
  projectName: name,
  projectSite: 'Abu Dhabi',
  projectState: 'active',
  clientName: client,
  baselineRevisionNumber: 1,
  currencyCode: 'AED',
  contractBaseline: YorksAccountsDecimal.parse('8400000'),
  confirmedEligible: YorksAccountsDecimal.parse('1552000'),
  availableToClaim: YorksAccountsDecimal.parse('327000'),
  claimed: YorksAccountsDecimal.parse('1225000'),
  certified: YorksAccountsDecimal.parse(certified),
  amountPaidTillDate: YorksAccountsDecimal.parse(paid),
  stillDue: YorksAccountsDecimal.parse(due),
  pdcExposure: _zero,
  confirmedPercent: YorksAccountsDecimal.parse(percent),
  dueState: actions > 0 ? 'overdue' : 'current',
  paymentState: 'partially_paid',
  actionCount: actions,
  latestActivityAt: DateTime.utc(2026, 8, 26, actions),
  supplierReviewCount: actions,
  supplierOpenAmount: YorksAccountsDecimal.parse('250000'),
);

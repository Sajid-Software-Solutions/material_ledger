import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/app/router.dart';
import 'package:material_ledger/features/company_overview/application/company_analytics_providers.dart';
import 'package:material_ledger/features/company_overview/data/company_analytics_repository.dart';
import 'package:material_ledger/features/company_overview/domain/company_analytics_models.dart';
import 'package:material_ledger/features/company_overview/domain/company_analytics_strings.dart';
import 'package:material_ledger/features/company_overview/presentation/company_analytics_screen.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_portfolio_provider.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('strict projection parses confirmed zeroes and explicit coverage', () {
    final projection = CompanyAnalyticsProjection.fromRpcJson(_response());

    expect(projection.projects?.total, 4);
    expect(projection.projects?.register, hasLength(2));
    expect(projection.materialRequests?.open, 3);
    expect(projection.materialRequests?.monthlyFlow, hasLength(3));
    expect(projection.materialRequests?.attention, hasLength(1));
    expect(
      projection.coverage['accounts']?.state,
      CompanyAnalyticsCoverageState.available,
    );
    expect(
      projection.coverage['workforce']?.state,
      CompanyAnalyticsCoverageState.available,
    );
    expect(projection.accounts?.currencyGroups, hasLength(2));
    expect(projection.workforce?.confirmedRegularMinutes, 960);
    expect(projection.rentals?.totalProperties, 5);
    expect(projection.importantActionCount, 11);
    expect(projection.isPartial, true);
  });

  test('strict projection rejects internally inconsistent project totals', () {
    final response = _response();
    (response['projects'] as Map<String, dynamic>)['total'] = 99;

    expect(
      () => CompanyAnalyticsProjection.fromRpcJson(response),
      throwsA(
        isA<YorksV1DomainException>().having(
          (error) => error.code,
          'code',
          YorksV1DomainErrorCode.unexpectedResponse,
        ),
      ),
    );
  });

  test('strict projection rejects payloads outside their source authority', () {
    final response = _response();
    (response['coverage'] as Map<String, dynamic>)['projects'] = {
      'state': 'denied',
      'reason': 'missing_domain_capability',
    };
    response['is_partial'] = true;

    expect(
      () => CompanyAnalyticsProjection.fromRpcJson(response),
      throwsA(
        isA<YorksV1DomainException>().having(
          (error) => error.code,
          'code',
          YorksV1DomainErrorCode.unexpectedResponse,
        ),
      ),
    );
  });

  test('strict projection rejects incomplete coverage and month windows', () {
    final missingCoverage = _response();
    (missingCoverage['coverage'] as Map<String, dynamic>).remove('audit');
    final wrongMonths = _response();
    ((wrongMonths['material_requests'] as Map<String, dynamic>)['monthly_flow']
            as List)
        .removeLast();

    expect(
      () => CompanyAnalyticsProjection.fromRpcJson(missingCoverage),
      throwsA(isA<YorksV1DomainException>()),
    );
    expect(
      () => CompanyAnalyticsProjection.fromRpcJson(wrongMonths),
      throwsA(isA<YorksV1DomainException>()),
    );
  });

  test('strict projection never accepts merged or duplicate currencies', () {
    final duplicateCurrency = _response();
    final groups =
        (duplicateCurrency['accounts']
                as Map<String, dynamic>)['currency_groups']
            as List<dynamic>;
    (groups[1] as Map<String, dynamic>)['currency_code'] = 'AED';

    expect(
      () => CompanyAnalyticsProjection.fromRpcJson(duplicateCurrency),
      throwsA(isA<YorksV1DomainException>()),
    );
  });

  test('strict projection rejects unconfirmed workforce arithmetic', () {
    final response = _response();
    (response['workforce']
            as Map<String, dynamic>)['confirmed_regular_minutes'] =
        961;

    expect(
      () => CompanyAnalyticsProjection.fromRpcJson(response),
      throwsA(isA<YorksV1DomainException>()),
    );
  });

  test('retired Analytics never calls its projection', () async {
    // Analytics is retired (PRODUCT_DECISIONS.md section 31): even a build
    // that asks for it cannot reach the server projection.
    final rpc = _FakeRpcClient(_response());
    final repository = SupabaseCompanyAnalyticsRepository(
      featureFlags: _analyticsFlags,
      connectivity: _Connectivity(true),
      rpcClient: rpc,
    );

    await expectLater(
      repository.getProjection(const CompanyAnalyticsFilters()),
      _domainError(YorksV1DomainErrorCode.featureDisabled),
    );
    expect(rpc.calls, 0);
  });

  testWidgets('Analytics has a purpose-built 360px layout without overflow', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          yorksV1FeatureFlagsProvider.overrideWithValue(_analyticsFlags),
          yorksV1AuthorizedProjectPortfolioProvider.overrideWithValue(
            const AsyncData([]),
          ),
          companyAnalyticsProjectionProvider.overrideWith(
            (ref, filters) async =>
                CompanyAnalyticsProjection.fromRpcJson(_response()),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CompanyAnalyticsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(CompanyAnalyticsStrings.title.primary), findsOneWidget);
    expect(
      find.text(CompanyAnalyticsStrings.projectReview.primary),
      findsOneWidget,
    );
    expect(
      find.text(CompanyAnalyticsStrings.financialStatus.primary),
      findsOneWidget,
    );
    expect(
      find.text(CompanyAnalyticsStrings.approvedWorkforceEvidence.primary),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('company-analytics-domain-dropdown')),
      findsOneWidget,
    );
    expect(find.byType(ChoiceChip), findsNothing);
    final firstKpi = tester.getRect(
      find.byKey(const ValueKey('company-analytics-kpi-card-0')),
    );
    final secondKpi = tester.getRect(
      find.byKey(const ValueKey('company-analytics-kpi-card-1')),
    );
    final important = tester.getRect(
      find.text(CompanyAnalyticsStrings.importantForYou.primary),
    );
    expect(firstKpi.width, greaterThan(320));
    expect(secondKpi.top, greaterThan(firstKpi.bottom));
    expect(important.top, lessThan(firstKpi.top));
    expect(find.text('2'), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Analytics remains usable at 200 percent text scaling', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          yorksV1FeatureFlagsProvider.overrideWithValue(_analyticsFlags),
          yorksV1AuthorizedProjectPortfolioProvider.overrideWithValue(
            const AsyncData([]),
          ),
          companyAnalyticsProjectionProvider.overrideWith(
            (ref, filters) async =>
                CompanyAnalyticsProjection.fromRpcJson(_response()),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(body: CompanyAnalyticsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(CompanyAnalyticsStrings.title.primary), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Analytics respects the 720px mobile to tablet boundary', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> pumpAt(double width) async {
      tester.view.physicalSize = Size(width, 1000);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1FeatureFlagsProvider.overrideWithValue(_analyticsFlags),
            yorksV1AuthorizedProjectPortfolioProvider.overrideWithValue(
              const AsyncData([]),
            ),
            companyAnalyticsProjectionProvider.overrideWith(
              (ref, filters) async =>
                  CompanyAnalyticsProjection.fromRpcJson(_response()),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: CompanyAnalyticsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpAt(720);
    var firstKpi = tester.getRect(
      find.byKey(const ValueKey('company-analytics-kpi-card-0')),
    );
    var secondKpi = tester.getRect(
      find.byKey(const ValueKey('company-analytics-kpi-card-1')),
    );
    expect(firstKpi.width, greaterThan(650));
    expect(secondKpi.top, greaterThan(firstKpi.bottom));

    await pumpAt(721);
    firstKpi = tester.getRect(
      find.byKey(const ValueKey('company-analytics-kpi-card-0')),
    );
    secondKpi = tester.getRect(
      find.byKey(const ValueKey('company-analytics-kpi-card-1')),
    );
    expect(firstKpi.width, lessThan(340));
    expect(secondKpi.top, closeTo(firstKpi.top, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('domain selector narrows the investigation without refetching', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var projectionReads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          yorksV1FeatureFlagsProvider.overrideWithValue(_analyticsFlags),
          yorksV1AuthorizedProjectPortfolioProvider.overrideWithValue(
            const AsyncData([]),
          ),
          companyAnalyticsProjectionProvider.overrideWith((ref, filters) async {
            projectionReads += 1;
            return CompanyAnalyticsProjection.fromRpcJson(_response());
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CompanyAnalyticsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.text(CompanyAnalyticsStrings.accountsSource.primary).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.text(CompanyAnalyticsStrings.financialStatus.primary),
      findsOneWidget,
    );
    expect(
      find.text(CompanyAnalyticsStrings.projectReview.primary),
      findsNothing,
    );
    expect(
      find.text(CompanyAnalyticsStrings.materialPipeline.primary),
      findsNothing,
    );

    await tester.tap(
      find.text(CompanyAnalyticsStrings.projectSource.primary).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.text(CompanyAnalyticsStrings.projectReview.primary),
      findsOneWidget,
    );
    expect(
      find.text(CompanyAnalyticsStrings.financialStatus.primary),
      findsNothing,
    );
    expect(projectionReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Overview keeps currencies separate and selectable', (
    tester,
  ) async {
    final projection = CompanyAnalyticsProjection.fromRpcJson(_response());
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CompanyAnalyticsOverviewSummary(
              language: AppLanguage.english,
              projection: projection,
              flags: _analyticsFlags,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AED 125,000.00'), findsOneWidget);
    expect(find.text('EUR 90,000.00'), findsNothing);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EUR').last);
    await tester.pumpAndSettle();
    expect(find.text('EUR 90,000.00'), findsOneWidget);
    expect(find.text('AED 125,000.00'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Overview KPI cards open their authoritative workspaces', (
    tester,
  ) async {
    final projection = CompanyAnalyticsProjection.fromRpcJson(_response());
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final paths = [
      RoutePaths.yorksV1Accounts,
      RoutePaths.yorksV1Projects,
      RoutePaths.yorksV1MaterialRequests,
      RoutePaths.yorksV1Workforce,
      RoutePaths.rentals,
    ];
    late final GoRouter router;
    router = GoRouter(
      initialLocation: '/overview',
      routes: [
        GoRoute(
          path: '/overview',
          builder: (context, state) => Scaffold(
            body: SingleChildScrollView(
              child: CompanyAnalyticsOverviewSummary(
                language: AppLanguage.english,
                projection: projection,
                flags: _analyticsFlags,
              ),
            ),
          ),
        ),
        for (final path in paths)
          GoRoute(
            path: path,
            builder: (context, state) => Text(state.uri.path),
          ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    for (var index = 0; index < paths.length; index++) {
      await tester.tap(
        find.byKey(ValueKey('company-analytics-kpi-card-$index')),
      );
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, paths[index]);
      router.go('/overview');
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Workforce attention explains and opens the exact next task', (
    tester,
  ) async {
    final projection = CompanyAnalyticsProjection.fromRpcJson(_response());
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/overview',
      routes: [
        GoRoute(
          path: '/overview',
          builder: (context, state) => Scaffold(
            body: SingleChildScrollView(
              child: CompanyAnalyticsOverviewSummary(
                language: AppLanguage.english,
                projection: projection,
                flags: _analyticsFlags,
              ),
            ),
          ),
        ),
        GoRoute(
          path: RoutePaths.yorksV1WorkforceAttendance,
          builder: (context, state) => const Text('Attendance workspace'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final label = CompanyAnalyticsStrings.completeAttendance.primary;
    expect(find.text(label), findsOneWidget);
    expect(
      find.text(
        '2 ${CompanyAnalyticsStrings.workersWithoutAttendance.primary}',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      RoutePaths.yorksV1WorkforceAttendance,
    );
    expect(tester.takeException(), isNull);
  });
}

Matcher _domainError(YorksV1DomainErrorCode code) => throwsA(
  isA<YorksV1DomainException>().having((error) => error.code, 'code', code),
);

const _analyticsFlags = YorksV1FeatureFlags(
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
  workforce: true,
  analytics: true,
);

Map<String, dynamic> _response() => {
  'schema_version': 2,
  'generated_at': '2026-09-04T12:00:00Z',
  'requested_filters': {'project_id': null, 'months': 3},
  'effective_filters': {'project_id': null, 'months': 3, 'timezone': 'UTC'},
  'as_of': {'timezone': 'UTC', 'local_date': '2026-09-04', 'month_count': 3},
  'coverage': {
    'projects': {'state': 'available', 'reason': null},
    'material_requests': {'state': 'available', 'reason': null},
    'accounts': {'state': 'available', 'reason': null},
    'workforce': {'state': 'available', 'reason': null},
    'rentals': {'state': 'available', 'reason': null},
    'inventory': {
      'state': 'source_only',
      'reason': 'separate_protected_workspace',
    },
    'audit': {'state': 'source_only', 'reason': 'separate_protected_workspace'},
  },
  'is_partial': true,
  'warnings': <Object?>[],
  'projects': {
    'total': 4,
    'draft': 0,
    'active': 2,
    'on_hold': 1,
    'completed': 1,
    'archived': 0,
    'register': [
      {
        'project_id': 'project-1',
        'project_reference': 'YRA-101',
        'project_name': 'Central Plant Upgrade',
        'project_site': 'Abu Dhabi',
        'state': 'active',
        'current_owner_role': 'Project Engineer',
        'start_date': '2026-01-01',
        'target_completion_date': '2026-11-30',
        'open_request_count': 2,
        'request_action_count': 1,
        'latest_activity_at': '2026-09-04T10:00:00Z',
      },
      {
        'project_id': 'project-2',
        'project_reference': 'YRA-102',
        'project_name': 'Workshop Extension',
        'project_site': null,
        'state': 'on_hold',
        'current_owner_role': 'Project Engineer',
        'start_date': null,
        'target_completion_date': null,
        'open_request_count': 1,
        'request_action_count': 0,
        'latest_activity_at': '2026-09-03T10:00:00Z',
      },
    ],
  },
  'material_requests': {
    'total': 7,
    'open': 3,
    'needs_action': 1,
    'drafts': 1,
    'awaiting_engineering_approval': 1,
    'to_arrange': 1,
    'changes_requested': 0,
    'dispatch_ready': 1,
    'receipt_pending': 0,
    'delivery_exceptions': 1,
    'received': 1,
    'closed': 2,
    'cancelled': 0,
    'monthly_flow': [
      {'month': '2026-07', 'submitted': 2, 'closed': 1},
      {'month': '2026-08', 'submitted': 3, 'closed': 1},
      {'month': '2026-09', 'submitted': 0, 'closed': 0},
    ],
    'attention': [
      {
        'request_id': 'request-1',
        'request_number': 'MR-101',
        'title': 'Copper fittings',
        'project_id': 'project-1',
        'project_reference': 'YRA-101',
        'project_name': 'Central Plant Upgrade',
        'state': 'submitted',
        'timing': 'overdue',
        'scheduled_date': '2026-09-03',
        'current_owner_role': 'Procurement',
        'next_action_code': 'arrange_request',
        'actor_can_act': false,
        'exception_codes': ['overdue'],
        'age_hours': 26.5,
        'updated_at': '2026-09-03T09:30:00Z',
      },
    ],
  },
  'accounts': {
    'authorized_project_count': 3,
    'unconfigured_project_count': 1,
    'attention_count': 4,
    'currency_groups': [
      {
        'currency_code': 'AED',
        'project_count': 1,
        'contract_value': '125000.00',
        'claimed': '65000.00',
        'certified': '60000.00',
        'received': '45000.00',
        'outstanding': '15000.00',
        'overdue_count': 1,
        'due_soon_count': 1,
        'returned_count': 0,
        'pdc_attention_count': 1,
        'monthly_flow': [
          {
            'month': '2026-07',
            'claimed': '15000.00',
            'certified': '12000.00',
            'received': '10000.00',
          },
          {
            'month': '2026-08',
            'claimed': '25000.00',
            'certified': '23000.00',
            'received': '18000.00',
          },
          {
            'month': '2026-09',
            'claimed': '25000.00',
            'certified': '25000.00',
            'received': '17000.00',
          },
        ],
      },
      {
        'currency_code': 'EUR',
        'project_count': 1,
        'contract_value': '90000.00',
        'claimed': '20000.00',
        'certified': '18000.00',
        'received': '18000.00',
        'outstanding': '0.00',
        'overdue_count': 0,
        'due_soon_count': 1,
        'returned_count': 0,
        'pdc_attention_count': 0,
        'monthly_flow': [
          {
            'month': '2026-07',
            'claimed': '0.00',
            'certified': '0.00',
            'received': '0.00',
          },
          {
            'month': '2026-08',
            'claimed': '10000.00',
            'certified': '9000.00',
            'received': '9000.00',
          },
          {
            'month': '2026-09',
            'claimed': '10000.00',
            'certified': '9000.00',
            'received': '9000.00',
          },
        ],
      },
    ],
  },
  'workforce': {
    'active_worker_count': 18,
    'active_supervisor_count': 3,
    'missing_today_count': 2,
    'monthly_pending_count': 1,
    'returned_count': 0,
    'awaiting_final_count': 1,
    'locked_count': 2,
    'reopen_request_count': 0,
    'configuration_issue_count': 0,
    'confirmed_period_count': 3,
    'confirmed_regular_minutes': 960,
    'confirmed_overtime_minutes': 150,
    'monthly_flow': [
      {'month': '2026-07', 'regular_minutes': 300, 'overtime_minutes': 30},
      {'month': '2026-08', 'regular_minutes': 360, 'overtime_minutes': 60},
      {'month': '2026-09', 'regular_minutes': 300, 'overtime_minutes': 60},
    ],
  },
  'rentals': {
    'currency_code': 'AED',
    'total_properties': 5,
    'occupied': 4,
    'monthly_rent_roll': '42000.00',
    'collected_this_month': '39000.00',
    'outstanding': '3000.00',
    'security_deposits': '21000.00',
    'expiring_within_90': 1,
    'cheque_attention': 1,
    'monthly_flow': [
      {'month': '2026-07', 'collected': '40000.00'},
      {'month': '2026-08', 'collected': '41000.00'},
      {'month': '2026-09', 'collected': '39000.00'},
    ],
  },
};

class _FakeRpcClient implements CompanyAnalyticsRpcClient {
  _FakeRpcClient(this.response);

  final Object? response;
  int calls = 0;
  String? functionName;
  Map<String, Object?>? parameters;

  @override
  Future<Object?> invoke(
    String functionName, {
    required Map<String, Object?> parameters,
  }) async {
    calls += 1;
    this.functionName = functionName;
    this.parameters = parameters;
    return response;
  }
}

class _Connectivity implements ConnectivityService {
  _Connectivity(this.isOnline);

  @override
  final bool isOnline;

  @override
  Stream<bool> get onChange => const Stream.empty();
}

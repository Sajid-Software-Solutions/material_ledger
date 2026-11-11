import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/projects/presentation/screens/yorks_v1_executive_overview.dart';
import 'package:material_ledger/features/company_overview/domain/company_analytics_models.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_audit_workspace.dart';
import 'package:material_ledger/shared/models/yorks_v1_configuration.dart';
import 'package:material_ledger/shared/models/yorks_v1_logistics.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request.dart';
import 'package:material_ledger/shared/models/yorks_v1_project.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_portfolio.dart';
import 'package:material_ledger/shared/models/yorks_v1_rental.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/providers/yorks_v1_audit_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadGoldenFonts);

  for (final evidence in <({String name, Size size, YorksV1Role role})>[
    (
      name: 'admin_command_centre_desktop.png',
      size: const Size(1440, 900),
      role: YorksV1Role.admin,
    ),
    (
      name: 'admin_overview_mobile.png',
      size: const Size(390, 844),
      role: YorksV1Role.admin,
    ),
    (
      name: 'leadership_portfolio_mobile.png',
      size: const Size(390, 844),
      role: YorksV1Role.seniorMechanicalEngineer,
    ),
  ]) {
    testWidgets('executive overview visual evidence ${evidence.name}', (
      tester,
    ) async {
      tester.view.physicalSize = evidence.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: Scaffold(
              body: YorksV1ExecutiveOverview(
                language: AppLanguage.english,
                role: evidence.role,
                displayName: evidence.role == YorksV1Role.admin
                    ? 'Owner'
                    : 'Khaled S. Sleiman',
                projects: AsyncData(_projects),
                requests: AsyncData(_requests),
                inventory: AsyncData(
                  YorksV1InventoryWorkspace(
                    items: [],
                    summary: YorksV1InventorySummary(
                      totalActiveItems: 1240,
                      lowStockCount: 6,
                      outOfStockCount: 2,
                      reservedCount: 18,
                      incomingCount: 0,
                    ),
                  ),
                ),
                configuration: AsyncData(_configuration),
                rentals: AsyncData(_rentals),
                audit: _audit,
                activeUsers: 18,
                canBrowseInventory: true,
                canAccessRentals: true,
                canOpenAnalytics: evidence.role == YorksV1Role.admin,
                companyAnalytics: evidence.role == YorksV1Role.admin
                    ? AsyncData(_companyProjection)
                    : const AsyncData<CompanyAnalyticsProjection?>(null),
                featureFlags: _companyFlags,
                onRefresh: () async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      if (evidence.role == YorksV1Role.admin) {
        final action = tester.getRect(find.text('Important for you'));
        expect(action.top, lessThan(evidence.size.height / 2));
      }
      await expectLater(
        find.byType(YorksV1ExecutiveOverview),
        matchesGoldenFile('goldens/r38_10/${evidence.name}'),
      );
    });
  }
}

const _companyFlags = YorksV1FeatureFlags(
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

final _companyProjection = CompanyAnalyticsProjection(
  generatedAt: DateTime.utc(2026, 9, 4, 12),
  projectId: null,
  months: 6,
  timezone: 'UTC',
  isPartial: true,
  coverage: const {
    'projects': CompanyAnalyticsCoverageItem(
      domain: 'projects',
      state: CompanyAnalyticsCoverageState.available,
    ),
    'material_requests': CompanyAnalyticsCoverageItem(
      domain: 'material_requests',
      state: CompanyAnalyticsCoverageState.available,
    ),
    'accounts': CompanyAnalyticsCoverageItem(
      domain: 'accounts',
      state: CompanyAnalyticsCoverageState.available,
    ),
    'workforce': CompanyAnalyticsCoverageItem(
      domain: 'workforce',
      state: CompanyAnalyticsCoverageState.available,
    ),
    'rentals': CompanyAnalyticsCoverageItem(
      domain: 'rentals',
      state: CompanyAnalyticsCoverageState.available,
    ),
    'inventory': CompanyAnalyticsCoverageItem(
      domain: 'inventory',
      state: CompanyAnalyticsCoverageState.sourceOnly,
      reason: 'separate_protected_workspace',
    ),
    'audit': CompanyAnalyticsCoverageItem(
      domain: 'audit',
      state: CompanyAnalyticsCoverageState.sourceOnly,
      reason: 'separate_protected_workspace',
    ),
  },
  warnings: const [],
  projects: CompanyProjectAnalytics(
    total: 9,
    draft: 0,
    active: 6,
    onHold: 1,
    completed: 2,
    archived: 0,
    register: [
      CompanyProjectRegisterItem(
        projectId: 'p-1',
        reference: 'YRA-322',
        name: 'Nexus Power Bulk Transmission',
        site: 'Abu Dhabi',
        state: 'active',
        currentOwnerRole: 'Project Engineer',
        startDate: DateTime.utc(2026, 1),
        targetCompletionDate: DateTime.utc(2026, 12),
        openRequestCount: 8,
        requestActionCount: 2,
        latestActivityAt: DateTime.utc(2026, 9, 4, 11),
      ),
    ],
  ),
  materialRequests: CompanyMaterialRequestAnalytics(
    total: 25,
    open: 17,
    needsAction: 3,
    drafts: 2,
    awaitingEngineeringApproval: 3,
    toArrange: 4,
    changesRequested: 1,
    dispatchReady: 4,
    receiptPending: 5,
    deliveryExceptions: 3,
    received: 2,
    closed: 4,
    cancelled: 0,
    monthlyFlow: const [
      CompanyMaterialRequestMonth(month: '2026-04', submitted: 9, closed: 5),
      CompanyMaterialRequestMonth(month: '2026-05', submitted: 12, closed: 8),
      CompanyMaterialRequestMonth(month: '2026-06', submitted: 10, closed: 9),
      CompanyMaterialRequestMonth(month: '2026-07', submitted: 14, closed: 11),
      CompanyMaterialRequestMonth(month: '2026-08', submitted: 13, closed: 12),
      CompanyMaterialRequestMonth(month: '2026-09', submitted: 8, closed: 6),
    ],
    attention: [
      CompanyMaterialRequestAttentionItem(
        requestId: 'request-1',
        requestNumber: 'MR-1048',
        title: 'Copper fittings',
        projectId: 'p-1',
        projectReference: 'YRA-322',
        projectName: 'Nexus Power Bulk Transmission',
        state: 'partially_received',
        timing: 'overdue',
        currentOwnerRole: 'Project Engineer',
        nextActionCode: 'receipt_review_required',
        actorCanAct: true,
        exceptionCodes: const ['missing_quantity'],
        ageHours: 18,
        updatedAt: DateTime.utc(2026, 9, 3, 18),
      ),
    ],
  ),
  accounts: CompanyAccountAnalytics(
    authorizedProjectCount: 8,
    unconfiguredProjectCount: 0,
    attentionCount: 3,
    currencyGroups: [
      CompanyAccountCurrency(
        currencyCode: 'AED',
        projectCount: 8,
        contractValue: '28500000.00',
        claimed: '2100000.00',
        certified: '1660000.00',
        received: '1240000.00',
        outstanding: '420000.00',
        overdueCount: 1,
        dueSoonCount: 1,
        returnedCount: 0,
        pdcAttentionCount: 1,
        monthlyFlow: const [
          CompanyAccountMonth(
            month: '2026-04',
            claimed: '850000.00',
            certified: '650000.00',
            received: '510000.00',
          ),
          CompanyAccountMonth(
            month: '2026-05',
            claimed: '1050000.00',
            certified: '820000.00',
            received: '590000.00',
          ),
          CompanyAccountMonth(
            month: '2026-06',
            claimed: '920000.00',
            certified: '780000.00',
            received: '610000.00',
          ),
          CompanyAccountMonth(
            month: '2026-07',
            claimed: '1350000.00',
            certified: '1040000.00',
            received: '790000.00',
          ),
          CompanyAccountMonth(
            month: '2026-08',
            claimed: '1510000.00',
            certified: '1190000.00',
            received: '910000.00',
          ),
          CompanyAccountMonth(
            month: '2026-09',
            claimed: '2100000.00',
            certified: '1660000.00',
            received: '1240000.00',
          ),
        ],
      ),
    ],
  ),
  workforce: CompanyWorkforceAnalytics(
    activeWorkerCount: 46,
    activeSupervisorCount: 8,
    missingTodayCount: 4,
    monthlyPendingCount: 1,
    returnedCount: 0,
    awaitingFinalCount: 1,
    lockedCount: 18,
    reopenRequestCount: 0,
    configurationIssueCount: 0,
    confirmedPeriodCount: 24,
    confirmedRegularMinutes: 420000,
    confirmedOvertimeMinutes: 48000,
    monthlyFlow: const [
      CompanyWorkforceMonth(
        month: '2026-04',
        regularMinutes: 66000,
        overtimeMinutes: 7200,
      ),
      CompanyWorkforceMonth(
        month: '2026-05',
        regularMinutes: 69000,
        overtimeMinutes: 7500,
      ),
      CompanyWorkforceMonth(
        month: '2026-06',
        regularMinutes: 67500,
        overtimeMinutes: 7800,
      ),
      CompanyWorkforceMonth(
        month: '2026-07',
        regularMinutes: 72000,
        overtimeMinutes: 8400,
      ),
      CompanyWorkforceMonth(
        month: '2026-08',
        regularMinutes: 75000,
        overtimeMinutes: 9000,
      ),
      CompanyWorkforceMonth(
        month: '2026-09',
        regularMinutes: 70500,
        overtimeMinutes: 8100,
      ),
    ],
  ),
  rentals: CompanyRentalAnalytics(
    currencyCode: 'AED',
    totalProperties: 33,
    occupied: 31,
    monthlyRentRoll: '209000.00',
    collectedThisMonth: '185000.00',
    outstanding: '24000.00',
    securityDeposits: '142000.00',
    expiringWithin90: 1,
    chequeAttention: 1,
    monthlyFlow: const [
      CompanyRentalMonth(month: '2026-04', collected: '172000.00'),
      CompanyRentalMonth(month: '2026-05', collected: '178000.00'),
      CompanyRentalMonth(month: '2026-06', collected: '181000.00'),
      CompanyRentalMonth(month: '2026-07', collected: '187000.00'),
      CompanyRentalMonth(month: '2026-08', collected: '191000.00'),
      CompanyRentalMonth(month: '2026-09', collected: '185000.00'),
    ],
  ),
);

final _projects = <YorksV1ProjectPortfolioItem>[
  _project(
    'p-1',
    'YRA-322',
    'Nexus Power Bulk Transmission',
    YorksV1ProjectLifecycle.active,
    0,
  ),
  _project(
    'p-2',
    'YRA-314',
    'Independent Subsea HVDC System',
    YorksV1ProjectLifecycle.active,
    1,
  ),
  _project(
    'p-3',
    'YRA-324',
    'Nexus Interconnection Phase One',
    YorksV1ProjectLifecycle.onHold,
    2,
  ),
  _project(
    'p-4',
    'YRA-319',
    'Taiz Ruwais Derivative Park',
    YorksV1ProjectLifecycle.completed,
    3,
  ),
];

YorksV1ProjectPortfolioItem _project(
  String id,
  String reference,
  String name,
  YorksV1ProjectLifecycle state,
  int daysAgo,
) => YorksV1ProjectPortfolioItem(
  project: YorksV1Project(
    id: id,
    reference: reference,
    name: name,
    state: state,
    version: 1,
    createdAt: DateTime.utc(2026, 8, 1),
    updatedAt: DateTime.utc(2026, 8, 21).subtract(Duration(days: daysAgo)),
    siteLocation: 'Abu Dhabi, UAE',
  ),
  activeBuildingCount: 3,
  activeProjectEngineerCount: 2,
  activeSiteEngineerCount: 2,
);

final _requests = <YorksV1MaterialRequest>[
  _request('01', YorksV1MaterialRequestState.awaitingRequestApproval),
  _request('02', YorksV1MaterialRequestState.awaitingApproval),
  _request('03', YorksV1MaterialRequestState.changesRequested),
  _request('04', YorksV1MaterialRequestState.approved),
  _request('05', YorksV1MaterialRequestState.partiallyDispatched),
  _request('06', YorksV1MaterialRequestState.dispatched),
  _request('07', YorksV1MaterialRequestState.partiallyReceived),
  _request('08', YorksV1MaterialRequestState.received),
  _request('09', YorksV1MaterialRequestState.closed),
];

YorksV1MaterialRequest _request(String id, YorksV1MaterialRequestState state) =>
    YorksV1MaterialRequest(
      id: id,
      projectId: 'p-1',
      projectReference: 'YRA-322',
      projectName: 'Nexus Power Bulk Transmission',
      scopeId: 'scope-1',
      scopeName: 'DF6W 132/33kV Substation',
      state: state,
      recordVersion: 1,
      createdAt: DateTime.utc(2026, 8, 20),
      updatedAt: DateTime.utc(
        2026,
        8,
        21,
      ).subtract(Duration(minutes: int.parse(id) * 7)),
      lines: const [
        YorksV1MaterialRequestLine(
          id: 'line-1',
          displayOrder: 1,
          source: YorksV1MaterialRequestLineSource.custom,
          description: 'Controlled material package',
          quantity: '12',
          unit: 'Nos',
        ),
      ],
      timing: YorksV1MaterialRequestTiming.normal,
      requestNumber: 'YRA322-MR$id',
      title: 'Controlled material package',
      currentActionOwnerRole: 'project_engineer',
    );

final _configuration = YorksV1ConfigurationCentre(
  schemaVersion: 'r38',
  environment: 'production',
  publishedVersion: 13,
  publishedLabel: 'v1.3.0',
  publishedAt: DateTime.utc(2026, 8, 20),
  publishedBy: 'Owner',
  draftRevision: 2,
  draftBaseVersion: 13,
  draftUpdatedAt: DateTime.utc(2026, 8, 21),
  settings: const [],
  masterActions: const [],
  categories: const [],
  units: const [],
  boqTemplates: const [],
  history: const [],
  validation: const YorksV1ConfigurationValidation(
    status: YorksV1ConfigurationValidationStatus.recommendations,
    blocking: [],
    recommendations: [
      YorksV1ConfigurationIssue(
        code: 'review',
        area: YorksV1ConfigurationArea.securityAudit,
        message: 'Review access policy',
      ),
    ],
  ),
);

final _rentals = YorksV1RentalPortfolio(
  asOf: DateTime.utc(2026, 8, 21),
  summary: const YorksV1RentalSummary(
    totalProperties: 8,
    occupied: 7,
    monthlyRentRoll: 95000,
    collectedThisMonth: 88000,
    outstanding: 7000,
    securityDeposits: 120000,
    expiringWithin90: 1,
    chequeAttention: 1,
  ),
  properties: const [],
  recentPayments: const [],
  cheques: const [],
);

final _audit = YorksV1AuditViewState(
  isLoading: false,
  workspace: YorksV1AuditWorkspace(
    generatedAt: DateTime.utc(2026, 8, 21),
    summary: const YorksV1AuditSummary(
      totalActivities: 214,
      criticalActivities: 1,
      activeUsers: 18,
      entitiesMonitored: 64,
      auditAlerts: 1,
      dataIntegrityPercent: 100,
      currentPeriodActivities: 39,
      previousPeriodActivities: 35,
    ),
    filteredCount: 1,
    limit: 12,
    offset: 0,
    events: [
      YorksV1AuditEvent(
        id: 'audit-1',
        eventType: 'configuration_published',
        entityType: 'configuration',
        entityId: 'config-13',
        module: YorksV1AuditModule.system,
        severity: YorksV1AuditSeverity.warning,
        actorAuthUserId: 'owner',
        actorDisplayName: 'Owner',
        actorExactRole: 'admin',
        occurredAt: DateTime.utc(2026, 8, 21, 8, 30),
        reference: 'Configuration v1.3.0',
        facts: const {},
        attributionVerified: true,
      ),
    ],
    topEntities: const [],
    moduleActivity: const [],
    trend: const [],
    quickFilterCounts: const {},
    alerts: const [],
  ),
);

Future<void> _loadGoldenFonts() async {
  final nexus = FontLoader('NexusSans')
    ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
  final arabic = FontLoader('NotoSansArabic')
    ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
  final cache = _flutterCacheDirectory();
  final icons = await File(
    '${cache.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ).readAsBytes();
  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(icons)));
  await Future.wait([nexus.load(), arabic.load(), materialIcons.load()]);
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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/company_overview/application/company_analytics_providers.dart';
import 'package:material_ledger/features/company_overview/domain/company_analytics_models.dart';
import 'package:material_ledger/features/company_overview/domain/company_analytics_strings.dart';
import 'package:material_ledger/features/company_overview/presentation/company_analytics_screen.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadGoldenFonts);

  for (final evidence in <({String name, Size size, AppLanguage language})>[
    (
      name: 'company_analytics_desktop.png',
      size: const Size(1440, 1000),
      language: AppLanguage.english,
    ),
    (
      name: 'company_analytics_tablet.png',
      size: const Size(820, 1000),
      language: AppLanguage.english,
    ),
    (
      name: 'company_analytics_mobile.png',
      size: const Size(360, 800),
      language: AppLanguage.english,
    ),
    (
      name: 'company_analytics_rtl_mobile.png',
      size: const Size(390, 844),
      language: AppLanguage.arabic,
    ),
  ]) {
    testWidgets('Analytics visual evidence ${evidence.name}', (tester) async {
      SharedPreferences.setMockInitialValues({
        'selected_language': evidence.language.code,
      });
      final preferences = await SharedPreferences.getInstance();
      tester.view.physicalSize = evidence.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1FeatureFlagsProvider.overrideWithValue(_analyticsFlags),
            companyAnalyticsProjectOptionsProvider.overrideWith(
              (ref) async => [],
            ),
            companyAnalyticsProjectionProvider.overrideWith(
              (ref, filters) async => _projection,
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: Directionality(
              textDirection: evidence.language.isRtl
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: const Scaffold(body: CompanyAnalyticsScreen()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      if (evidence.size.width <= 390) {
        final firstKpi = tester.getRect(
          find.byKey(const ValueKey('company-analytics-kpi-card-0')),
        );
        final secondKpi = tester.getRect(
          find.byKey(const ValueKey('company-analytics-kpi-card-1')),
        );
        expect(firstKpi.width, greaterThan(evidence.size.width - 40));
        expect(secondKpi.top, greaterThan(firstKpi.bottom));
      }
      final action = tester.getRect(
        find.text(
          CompanyAnalyticsStrings.importantForYou.active(evidence.language),
        ),
      );
      expect(action.top, lessThan(evidence.size.height * .65));
      await expectLater(
        find.byType(CompanyAnalyticsScreen),
        matchesGoldenFile('goldens/analytics/${evidence.name}'),
      );
    });
  }
}

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
  analytics: true,
);

final _projection = CompanyAnalyticsProjection(
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
    total: 12,
    draft: 1,
    active: 8,
    onHold: 1,
    completed: 2,
    archived: 0,
    register: [
      CompanyProjectRegisterItem(
        projectId: 'project-1',
        reference: 'YRA-322',
        name: 'Reem Island Central Plant',
        site: 'Abu Dhabi',
        state: 'active',
        currentOwnerRole: 'Project Engineer',
        startDate: DateTime.utc(2026, 1, 5),
        targetCompletionDate: DateTime.utc(2026, 11, 30),
        openRequestCount: 9,
        requestActionCount: 3,
        latestActivityAt: DateTime.utc(2026, 9, 4, 11, 42),
      ),
      CompanyProjectRegisterItem(
        projectId: 'project-2',
        reference: 'YRA-318',
        name: 'Yas Bay Residential Towers',
        site: 'Yas Island',
        state: 'active',
        currentOwnerRole: 'Project Engineer',
        startDate: DateTime.utc(2025, 10, 18),
        targetCompletionDate: DateTime.utc(2026, 12, 20),
        openRequestCount: 7,
        requestActionCount: 2,
        latestActivityAt: DateTime.utc(2026, 9, 4, 10, 18),
      ),
      CompanyProjectRegisterItem(
        projectId: 'project-3',
        reference: 'YRA-311',
        name: 'Workshop Expansion',
        site: 'Mussafah',
        state: 'on_hold',
        currentOwnerRole: 'Project Engineer',
        startDate: DateTime.utc(2025, 7, 1),
        targetCompletionDate: DateTime.utc(2026, 10, 15),
        openRequestCount: 4,
        requestActionCount: 1,
        latestActivityAt: DateTime.utc(2026, 9, 3, 15, 5),
      ),
      CompanyProjectRegisterItem(
        projectId: 'project-4',
        reference: 'YRA-305',
        name: 'Corniche Office Retrofit',
        site: 'Corniche',
        state: 'completed',
        currentOwnerRole: 'Project Engineer',
        startDate: DateTime.utc(2025, 2, 1),
        targetCompletionDate: DateTime.utc(2026, 8, 31),
        openRequestCount: 0,
        requestActionCount: 0,
        latestActivityAt: DateTime.utc(2026, 9, 1, 8, 10),
      ),
    ],
  ),
  materialRequests: CompanyMaterialRequestAnalytics(
    total: 92,
    open: 31,
    needsAction: 7,
    drafts: 4,
    awaitingEngineeringApproval: 7,
    toArrange: 6,
    changesRequested: 0,
    dispatchReady: 8,
    receiptPending: 10,
    deliveryExceptions: 3,
    received: 21,
    closed: 36,
    cancelled: 0,
    monthlyFlow: const [
      CompanyMaterialRequestMonth(month: '2026-04', submitted: 12, closed: 8),
      CompanyMaterialRequestMonth(month: '2026-05', submitted: 18, closed: 12),
      CompanyMaterialRequestMonth(month: '2026-06', submitted: 15, closed: 14),
      CompanyMaterialRequestMonth(month: '2026-07', submitted: 22, closed: 16),
      CompanyMaterialRequestMonth(month: '2026-08', submitted: 17, closed: 15),
      CompanyMaterialRequestMonth(month: '2026-09', submitted: 8, closed: 5),
    ],
    attention: [
      CompanyMaterialRequestAttentionItem(
        requestId: 'request-1',
        requestNumber: 'MR-00491',
        title: 'Copper fittings and valves',
        projectId: 'project-1',
        projectReference: 'YRA-322',
        projectName: 'Reem Island Central Plant',
        state: 'submitted',
        timing: 'overdue',
        currentOwnerRole: 'Procurement',
        nextActionCode: 'arrange_request',
        actorCanAct: false,
        exceptionCodes: const ['overdue'],
        ageHours: 31,
        updatedAt: DateTime.utc(2026, 9, 3, 5),
      ),
      CompanyMaterialRequestAttentionItem(
        requestId: 'request-2',
        requestNumber: 'MR-00488',
        title: 'FCU supports',
        projectId: 'project-2',
        projectReference: 'YRA-318',
        projectName: 'Yas Bay Residential Towers',
        state: 'awaiting_engineering_approval',
        timing: 'due_soon',
        currentOwnerRole: 'Project Engineer',
        nextActionCode: 'review_arrangement',
        actorCanAct: false,
        exceptionCodes: const [],
        ageHours: 17,
        updatedAt: DateTime.utc(2026, 9, 3, 19),
      ),
      CompanyMaterialRequestAttentionItem(
        requestId: 'request-3',
        requestNumber: 'MR-00476',
        title: 'Insulation materials',
        projectId: 'project-3',
        projectReference: 'YRA-311',
        projectName: 'Workshop Expansion',
        state: 'receipt_pending',
        timing: 'on_track',
        currentOwnerRole: 'Project Engineer',
        nextActionCode: 'confirm_receipt',
        actorCanAct: false,
        exceptionCodes: const ['damaged_quantity'],
        ageHours: 8,
        updatedAt: DateTime.utc(2026, 9, 4, 4),
      ),
    ],
  ),
  accounts: CompanyAccountAnalytics(
    authorizedProjectCount: 9,
    unconfiguredProjectCount: 1,
    attentionCount: 5,
    currencyGroups: [
      CompanyAccountCurrency(
        currencyCode: 'AED',
        projectCount: 7,
        contractValue: '18450000.00',
        claimed: '10740000.00',
        certified: '9840000.00',
        received: '7315000.00',
        outstanding: '2525000.00',
        overdueCount: 2,
        dueSoonCount: 1,
        returnedCount: 0,
        pdcAttentionCount: 1,
        monthlyFlow: const [
          CompanyAccountMonth(
            month: '2026-04',
            claimed: '1150000.00',
            certified: '1050000.00',
            received: '920000.00',
          ),
          CompanyAccountMonth(
            month: '2026-05',
            claimed: '1320000.00',
            certified: '1210000.00',
            received: '1040000.00',
          ),
          CompanyAccountMonth(
            month: '2026-06',
            claimed: '980000.00',
            certified: '920000.00',
            received: '890000.00',
          ),
          CompanyAccountMonth(
            month: '2026-07',
            claimed: '1460000.00',
            certified: '1310000.00',
            received: '1180000.00',
          ),
          CompanyAccountMonth(
            month: '2026-08',
            claimed: '1710000.00',
            certified: '1590000.00',
            received: '1365000.00',
          ),
          CompanyAccountMonth(
            month: '2026-09',
            claimed: '1210000.00',
            certified: '1120000.00',
            received: '970000.00',
          ),
        ],
      ),
      CompanyAccountCurrency(
        currencyCode: 'USD',
        projectCount: 1,
        contractValue: '420000.00',
        claimed: '230000.00',
        certified: '205000.00',
        received: '175000.00',
        outstanding: '30000.00',
        overdueCount: 0,
        dueSoonCount: 1,
        returnedCount: 0,
        pdcAttentionCount: 0,
        monthlyFlow: const [
          CompanyAccountMonth(
            month: '2026-04',
            claimed: '30000.00',
            certified: '25000.00',
            received: '20000.00',
          ),
          CompanyAccountMonth(
            month: '2026-05',
            claimed: '35000.00',
            certified: '30000.00',
            received: '25000.00',
          ),
          CompanyAccountMonth(
            month: '2026-06',
            claimed: '40000.00',
            certified: '35000.00',
            received: '30000.00',
          ),
          CompanyAccountMonth(
            month: '2026-07',
            claimed: '45000.00',
            certified: '40000.00',
            received: '35000.00',
          ),
          CompanyAccountMonth(
            month: '2026-08',
            claimed: '45000.00',
            certified: '40000.00',
            received: '35000.00',
          ),
          CompanyAccountMonth(
            month: '2026-09',
            claimed: '35000.00',
            certified: '35000.00',
            received: '30000.00',
          ),
        ],
      ),
    ],
  ),
  workforce: CompanyWorkforceAnalytics(
    activeWorkerCount: 46,
    activeSupervisorCount: 8,
    missingTodayCount: 3,
    monthlyPendingCount: 2,
    returnedCount: 1,
    awaitingFinalCount: 1,
    lockedCount: 19,
    reopenRequestCount: 0,
    configurationIssueCount: 1,
    confirmedPeriodCount: 24,
    confirmedRegularMinutes: 425400,
    confirmedOvertimeMinutes: 51600,
    monthlyFlow: const [
      CompanyWorkforceMonth(
        month: '2026-04',
        regularMinutes: 68100,
        overtimeMinutes: 7200,
      ),
      CompanyWorkforceMonth(
        month: '2026-05',
        regularMinutes: 71400,
        overtimeMinutes: 8100,
      ),
      CompanyWorkforceMonth(
        month: '2026-06',
        regularMinutes: 69600,
        overtimeMinutes: 8400,
      ),
      CompanyWorkforceMonth(
        month: '2026-07',
        regularMinutes: 73800,
        overtimeMinutes: 9600,
      ),
      CompanyWorkforceMonth(
        month: '2026-08',
        regularMinutes: 75600,
        overtimeMinutes: 9900,
      ),
      CompanyWorkforceMonth(
        month: '2026-09',
        regularMinutes: 66900,
        overtimeMinutes: 8400,
      ),
    ],
  ),
  rentals: CompanyRentalAnalytics(
    currencyCode: 'AED',
    totalProperties: 18,
    occupied: 16,
    monthlyRentRoll: '148000.00',
    collectedThisMonth: '139500.00',
    outstanding: '8500.00',
    securityDeposits: '91000.00',
    expiringWithin90: 2,
    chequeAttention: 1,
    monthlyFlow: const [
      CompanyRentalMonth(month: '2026-04', collected: '135000.00'),
      CompanyRentalMonth(month: '2026-05', collected: '142000.00'),
      CompanyRentalMonth(month: '2026-06', collected: '138000.00'),
      CompanyRentalMonth(month: '2026-07', collected: '146000.00'),
      CompanyRentalMonth(month: '2026-08', collected: '144000.00'),
      CompanyRentalMonth(month: '2026-09', collected: '139500.00'),
    ],
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

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/workforce/application/workforce_dashboard_controller.dart';
import 'package:material_ledger/features/workforce/application/workforce_providers.dart';
import 'package:material_ledger/features/workforce/data/workforce_repository.dart';
import 'package:material_ledger/features/workforce/domain/workforce_dashboard_models.dart';
import 'package:material_ledger/features/workforce/presentation/screens/yorks_workforce_overview_screen.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_workforce_dashboard_strings.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _teamId = 'b1000000-0000-4000-8000-000000000001';
const _projectId = 'b1000000-0000-4000-8000-000000000002';
const _periodId = 'b1000000-0000-4000-8000-000000000003';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
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
  });

  testWidgets(
    'T10 overview is overflow-free across desktop and read-only mobile RTL',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      for (final (viewport, language) in const [
        (Size(1440, 900), AppLanguage.english),
        (Size(1366, 768), AppLanguage.english),
        (Size(1180, 820), AppLanguage.english),
        (Size(1024, 768), AppLanguage.arabic),
        (Size(820, 1180), AppLanguage.arabic),
        (Size(768, 1024), AppLanguage.urdu),
        (Size(430, 932), AppLanguage.hindi),
        (Size(390, 844), AppLanguage.arabic),
        (Size(360, 800), AppLanguage.arabic),
      ]) {
        await _pumpOverview(
          tester,
          viewport: viewport,
          language: language,
          repository: _Repository(YorksWorkforceOverviewKind.management),
          kind: YorksWorkforceOverviewKind.management,
        );

        expect(
          find.text(YorksV1WorkforceDashboardStrings.text(language, 'title')),
          findsOneWidget,
        );
        final titleContext = tester.element(
          find.text(YorksV1WorkforceDashboardStrings.text(language, 'title')),
        );
        expect(
          Directionality.of(titleContext),
          language.isRtl ? TextDirection.rtl : TextDirection.ltr,
        );
        expect(
          find.text(
            YorksV1WorkforceDashboardStrings.text(language, 'server_confirmed'),
          ),
          findsOneWidget,
        );
        if (viewport.width < 720) {
          final boundary = find.text(
            YorksV1WorkforceDashboardStrings.text(language, 'read_only_mobile'),
          );
          await tester.scrollUntilVisible(
            boundary,
            300,
            scrollable: find.byType(Scrollable).first,
          );
          expect(boundary, findsOneWidget);
          expect(
            find.byKey(const Key('workforce-overview-review-queue')),
            findsNothing,
          );
          expect(
            find.byKey(const Key('workforce-overview-final-approval-queue')),
            findsNothing,
          );
          expect(
            find.byKey(const Key('workforce-overview-complete-attendance')),
            findsNothing,
          );
          expect(
            find.byKey(const Key('workforce-overview-reopen-queue')),
            findsNothing,
          );
        } else {
          expect(
            find.byKey(const Key('workforce-overview-review-queue')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('workforce-overview-final-approval-queue')),
            findsNothing,
          );
          expect(
            find.byKey(const Key('workforce-overview-complete-attendance')),
            findsNothing,
          );
        }
        expect(
          tester.takeException(),
          isNull,
          reason: '${language.code} at $viewport',
        );
      }
    },
  );

  testWidgets('T10 state copy is explicit for empty, stale and denied states', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await _pumpOverview(
      tester,
      viewport: const Size(1024, 768),
      language: AppLanguage.english,
      repository: _Repository(YorksWorkforceOverviewKind.admin, empty: true),
      kind: YorksWorkforceOverviewKind.admin,
    );
    expect(
      find.text('No authorized Workforce scope is available.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    final connectivity = _MutableConnectivity(true);
    await _pumpOverview(
      tester,
      viewport: const Size(1024, 768),
      language: AppLanguage.english,
      repository: _Repository(YorksWorkforceOverviewKind.supervisor),
      kind: YorksWorkforceOverviewKind.supervisor,
      connectivity: connectivity,
      initiallyStale: true,
    );
    expect(
      find.text('Last confirmed — connection unavailable'),
      findsOneWidget,
    );
    expect(find.text('502'), findsWidgets);

    await _pumpOverview(
      tester,
      viewport: const Size(1024, 768),
      language: AppLanguage.english,
      repository: _DeniedRepository(),
      kind: YorksWorkforceOverviewKind.supervisor,
    );
    expect(
      find.text('Workforce overview access is unavailable.'),
      findsOneWidget,
    );
    expect(find.text('502'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('T10 acceptance viewports match deterministic goldens', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const cases = <(AppLanguage, Size, String)>[
      (AppLanguage.english, Size(1440, 900), 'en_1440x900'),
      (AppLanguage.english, Size(1366, 768), 'en_1366x768'),
      (AppLanguage.english, Size(1024, 768), 'en_1024x768'),
      (AppLanguage.english, Size(360, 800), 'en_360x800'),
      (AppLanguage.arabic, Size(1024, 768), 'ar_1024x768'),
    ];
    for (final (language, viewport, suffix) in cases) {
      await _pumpOverview(
        tester,
        viewport: viewport,
        language: language,
        repository: _Repository(YorksWorkforceOverviewKind.management),
        kind: YorksWorkforceOverviewKind.management,
      );
      await expectLater(
        find.byType(YorksWorkforceOverviewScreen),
        matchesGoldenFile('goldens/yorks_workforce_t10_overview_$suffix.png'),
      );
    }
  });

  testWidgets('T10 refresh is a named minimum-size semantic action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpOverview(
      tester,
      viewport: const Size(1366, 768),
      language: AppLanguage.english,
      repository: _Repository(YorksWorkforceOverviewKind.supervisor),
      kind: YorksWorkforceOverviewKind.supervisor,
    );
    final refresh = find.byTooltip('Refresh');
    expect(refresh, findsOneWidget);
    expect(tester.getSize(refresh).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(refresh).height, greaterThanOrEqualTo(44));
    expect(find.text('Under review'), findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets(
    'Supervisor renders exact metrics and only its server-authorized action',
    (tester) async {
      final router = await _pumpOverview(
        tester,
        viewport: const Size(1440, 900),
        language: AppLanguage.english,
        repository: _Repository(
          YorksWorkforceOverviewKind.supervisor,
          actionFlags: const {'can_complete_today_attendance': true},
        ),
        kind: YorksWorkforceOverviewKind.supervisor,
      );

      for (final label in const [
        'My Team',
        "Today's Date",
        'Workers',
        'Present',
        'Absent',
        'On leave',
        'Not entered',
        'Today completion',
        'Current Month Completion',
        'Warnings',
        'Returned Corrections',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text("Complete Today's Attendance"), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('workforce-overview-complete-attendance')),
      );
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/yorks/workforce/attendance',
      );

      await _pumpOverview(
        tester,
        viewport: const Size(1440, 900),
        language: AppLanguage.english,
        repository: _Repository(
          YorksWorkforceOverviewKind.supervisor,
          actionFlags: const {'can_complete_today_attendance': false},
        ),
        kind: YorksWorkforceOverviewKind.supervisor,
      );
      expect(find.text("Complete Today's Attendance"), findsNothing);
    },
  );

  testWidgets(
    'Management renders exact metrics and gates both queue links independently',
    (tester) async {
      GoRouter router = await _pumpOverview(
        tester,
        viewport: const Size(1440, 900),
        language: AppLanguage.english,
        repository: _Repository(
          YorksWorkforceOverviewKind.management,
          actionFlags: const {
            'can_open_review_queue': true,
            'can_open_final_approval_queue': true,
          },
        ),
        kind: YorksWorkforceOverviewKind.management,
      );
      for (final label in const [
        'Active Projects',
        'Workers Across Projects',
        'Attendance Completion',
        'Timesheets Awaiting Review',
        'Timesheets Awaiting Approval',
        'Missing Attendance',
        'Overtime Exceptions',
        'Returned Periods',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Review Queue'), findsOneWidget);
      expect(find.text('Final Approval Queue'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('workforce-overview-review-queue')),
      );
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/yorks/workforce/timesheets',
      );

      router = await _pumpOverview(
        tester,
        viewport: const Size(1440, 900),
        language: AppLanguage.english,
        repository: _Repository(
          YorksWorkforceOverviewKind.management,
          actionFlags: const {
            'can_open_review_queue': true,
            'can_open_final_approval_queue': true,
          },
        ),
        kind: YorksWorkforceOverviewKind.management,
      );
      await tester.tap(
        find.byKey(const Key('workforce-overview-final-approval-queue')),
      );
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/yorks/workforce/timesheets',
      );

      await _pumpOverview(
        tester,
        viewport: const Size(1440, 900),
        language: AppLanguage.english,
        repository: _Repository(
          YorksWorkforceOverviewKind.management,
          actionFlags: const {
            'can_open_review_queue': false,
            'can_open_final_approval_queue': false,
          },
        ),
        kind: YorksWorkforceOverviewKind.management,
      );
      expect(find.text('Review Queue'), findsNothing);
      expect(find.text('Final Approval Queue'), findsNothing);
    },
  );

  testWidgets(
    'Admin renders all nine metrics and gates reopen and final queues',
    (tester) async {
      GoRouter router = await _pumpOverview(
        tester,
        viewport: const Size(1440, 900),
        language: AppLanguage.english,
        repository: _Repository(
          YorksWorkforceOverviewKind.admin,
          actionFlags: const {
            'can_open_reopen_queue': true,
            'can_open_final_approval_queue': true,
          },
        ),
        kind: YorksWorkforceOverviewKind.admin,
      );
      for (final label in const [
        'Active Workers',
        'Active Supervisors',
        'Attendance Missing Today',
        'Monthly Reports Pending',
        'Returned for Correction',
        'Awaiting Final Approval',
        'Locked Periods',
        'Reopen Requests',
        'Configuration Issues',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      await tester.tap(
        find.byKey(const Key('workforce-overview-reopen-queue')),
      );
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/yorks/workforce/timesheets',
      );

      router = await _pumpOverview(
        tester,
        viewport: const Size(1440, 900),
        language: AppLanguage.english,
        repository: _Repository(
          YorksWorkforceOverviewKind.admin,
          actionFlags: const {
            'can_open_reopen_queue': true,
            'can_open_final_approval_queue': true,
          },
        ),
        kind: YorksWorkforceOverviewKind.admin,
      );
      await tester.tap(
        find.byKey(const Key('workforce-overview-final-approval-queue')),
      );
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/yorks/workforce/timesheets',
      );

      await _pumpOverview(
        tester,
        viewport: const Size(1440, 900),
        language: AppLanguage.english,
        repository: _Repository(
          YorksWorkforceOverviewKind.admin,
          actionFlags: const {
            'can_open_reopen_queue': false,
            'can_open_final_approval_queue': false,
          },
        ),
        kind: YorksWorkforceOverviewKind.admin,
      );
      expect(
        find.byKey(const Key('workforce-overview-reopen-queue')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('workforce-overview-final-approval-queue')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'desktop queue exposes every approved fact and typed policy state',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpOverview(
        tester,
        viewport: const Size(1440, 1100),
        language: AppLanguage.english,
        repository: _Repository(
          YorksWorkforceOverviewKind.management,
          typedEvidence: true,
        ),
        kind: YorksWorkforceOverviewKind.management,
      );
      await tester.scrollUntilVisible(
        find.text('Review & approval queue'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      for (final label in const [
        'Submitted by: Project Engineer',
        'Team: Dubai Workforce',
        'Month: 2026-08-01',
        'Workers: 502',
        'Regular / OT: 241000 / 0 min',
        'Warnings: 1',
        'Reviewer corrections: 0',
        'Missing Supporting Evidence: 3 · Typed validation issue',
        'High Overtime: 2 · Typed validation issue',
      ]) {
        expect(
          find.text(label, findRichText: true),
          findsOneWidget,
          reason: label,
        );
      }

      await _pumpOverview(
        tester,
        viewport: const Size(1440, 1100),
        language: AppLanguage.english,
        repository: _Repository(YorksWorkforceOverviewKind.management),
        kind: YorksWorkforceOverviewKind.management,
      );
      await tester.scrollUntilVisible(
        find.text('Review & approval queue'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Missing Supporting Evidence: 0 · Not configured',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.text('High Overtime: 0 · Not configured', findRichText: true),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'compact overview exposes only server-authorized workflow destinations',
    (tester) async {
      for (final repository in [
        _Repository(
          YorksWorkforceOverviewKind.supervisor,
          actionFlags: const {'can_complete_today_attendance': true},
        ),
        _Repository(
          YorksWorkforceOverviewKind.management,
          actionFlags: const {
            'can_open_review_queue': true,
            'can_open_final_approval_queue': true,
          },
        ),
        _Repository(
          YorksWorkforceOverviewKind.admin,
          actionFlags: const {
            'can_open_reopen_queue': true,
            'can_open_final_approval_queue': true,
          },
        ),
      ]) {
        await _pumpOverview(
          tester,
          viewport: const Size(360, 800),
          language: AppLanguage.english,
          repository: repository,
          kind: repository.kind,
        );
        final expected = switch (repository.kind) {
          YorksWorkforceOverviewKind.supervisor => {
            'workforce-overview-complete-attendance',
          },
          YorksWorkforceOverviewKind.management => {
            'workforce-overview-review-queue',
            'workforce-overview-final-approval-queue',
          },
          YorksWorkforceOverviewKind.admin => {
            'workforce-overview-reopen-queue',
            'workforce-overview-final-approval-queue',
          },
        };
        for (final key in const [
          'workforce-overview-complete-attendance',
          'workforce-overview-review-queue',
          'workforce-overview-final-approval-queue',
          'workforce-overview-reopen-queue',
        ]) {
          expect(
            find.byKey(Key(key)),
            expected.contains(key) ? findsOneWidget : findsNothing,
            reason: key,
          );
        }
        expect(tester.takeException(), isNull);
      }
    },
  );
}

Future<GoRouter> _pumpOverview(
  WidgetTester tester, {
  required Size viewport,
  required AppLanguage language,
  required YorksWorkforceDashboardRepository repository,
  required YorksWorkforceOverviewKind kind,
  ConnectivityService connectivity = const _Connectivity(true),
  bool initiallyStale = false,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  SharedPreferences.setMockInitialValues({'selected_language': language.code});
  final preferences = await SharedPreferences.getInstance();
  final controller = YorksWorkforceDashboardController(
    repository: repository,
    connectivity: connectivity,
    kind: kind,
  );
  if (initiallyStale) {
    await controller.load();
    (connectivity as _MutableConnectivity).setOnline(false);
    await controller.load();
  }
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const YorksWorkforceOverviewScreen(),
      ),
      GoRoute(
        path: '/yorks/workforce/attendance',
        builder: (context, state) =>
            const Scaffold(body: Text('attendance-destination')),
      ),
      GoRoute(
        path: '/yorks/workforce/timesheets',
        builder: (context, state) =>
            const Scaffold(body: Text('timesheets-destination')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksWorkforceDashboardControllerProvider.overrideWith(
          (ref) => controller,
        ),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: router,
        builder: (context, child) => Directionality(
          textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Map<String, dynamic> _overviewJson(
  YorksWorkforceOverviewKind kind, {
  bool empty = false,
  Map<String, bool>? actionFlags,
  bool typedEvidence = false,
}) => {
  'schema_version': 1,
  'authorization_mode': 'enforced_t10',
  'source_version': 'workforce_t10_v1',
  'overview_kind': kind.name,
  'generated_at': '2026-08-31T02:30:00Z',
  'as_of_mode': 'calendar_local_by_team',
  'as_of_groups': empty
      ? const []
      : const [
          {
            'calendar_timezone': 'Asia/Dubai',
            'local_date': '2026-08-31',
            'team_count': 1,
          },
        ],
  'summary': switch (kind) {
    YorksWorkforceOverviewKind.supervisor => _supervisorSummary(),
    YorksWorkforceOverviewKind.management => {
      ..._supervisorSummary(),
      'active_project_count': 1,
      'review_queue_count': 1,
      'approval_queue_count': 0,
      'returned_count': 0,
      'overtime_exception_count': 0,
    },
    YorksWorkforceOverviewKind.admin => const {
      'active_worker_count': 502,
      'active_supervisor_count': 1,
      'missing_today_count': 501,
      'monthly_pending_count': 1,
      'returned_count': 0,
      'awaiting_final_count': 0,
      'locked_count': 0,
      'reopen_request_count': 0,
      'configuration_issue_count': 0,
    },
  },
  'teams': empty ? const [] : [_teamJson()],
  'projects': empty || kind != YorksWorkforceOverviewKind.management
      ? const []
      : [_projectJson()],
  'review_queue': empty || kind != YorksWorkforceOverviewKind.management
      ? const []
      : [_queueJson(typedEvidence: typedEvidence)],
  'action_flags':
      actionFlags ??
      switch (kind) {
        YorksWorkforceOverviewKind.supervisor => const {
          'can_complete_today_attendance': true,
        },
        YorksWorkforceOverviewKind.management => const {
          'can_open_review_queue': true,
          'can_open_final_approval_queue': false,
        },
        YorksWorkforceOverviewKind.admin => const {
          'can_open_reopen_queue': true,
          'can_open_final_approval_queue': true,
        },
      },
  'policies': {
    'overtime_limit': typedEvidence
        ? 'typed_validation_issue'
        : 'not_configured',
    'supporting_evidence_requirement': typedEvidence
        ? 'typed_validation_issue'
        : 'not_configured',
  },
};

Map<String, Object> _supervisorSummary() => const {
  'team_count': 1,
  'worker_count': 502,
  'present_count': 1,
  'absent_count': 0,
  'leave_count': 0,
  'not_entered_count': 501,
  'warning_count': 1,
  'returned_correction_count': 0,
  'today_entered_count': 1,
  'today_completion_percent': 0.2,
  'month_entered_count': 1,
  'month_required_count': 502,
  'month_completion_percent': 0.2,
};

Map<String, dynamic> _teamJson() => {
  'team_id': _teamId,
  'team_code': 'DXB',
  'team_name': 'Dubai Workforce',
  'department': 'Operations',
  'project_id': _projectId,
  'project_ref': 'YRA-322',
  'project_name': 'Nexus 4 Station',
  'project_state': 'active',
  'internal_location_id': null,
  'internal_location_name': null,
  'supervisor_auth_user_id': 'b1000000-0000-4000-8000-000000000004',
  'supervisor_name': 'Supervisor One',
  'calendar_id': 'b1000000-0000-4000-8000-000000000005',
  'calendar_name': 'Dubai Calendar',
  'calendar_timezone': 'Asia/Dubai',
  'local_date': '2026-08-31',
  'period_month': '2026-08-01',
  'schedule_link_id': 'b1000000-0000-4000-8000-000000000006',
  'metrics': const {
    'worker_count': 502,
    'present_count': 1,
    'absent_count': 0,
    'leave_count': 0,
    'not_entered_count': 501,
    'today_entered_count': 1,
    'today_completion_percent': 0.2,
    'month_required_count': 502,
    'month_entered_count': 1,
    'month_completion_percent': 0.2,
    'warning_count': 1,
    'returned_correction_count': 0,
    'can_complete_today_attendance': true,
  },
};

Map<String, Object> _projectJson() => const {
  'project_id': _projectId,
  'project_ref': 'YRA-322',
  'project_name': 'Nexus 4 Station',
  'team_count': 1,
  'worker_count': 502,
  'missing_today_count': 501,
  'warning_count': 1,
};

Map<String, dynamic> _queueJson({bool typedEvidence = false}) => {
  'period_id': _periodId,
  'team_id': _teamId,
  'team_name': 'Dubai Workforce',
  'period_month': '2026-08-01',
  'status': 'under_review',
  'record_version': 2,
  'submitted_by_auth_user_id': 'b1000000-0000-4000-8000-000000000007',
  'submitted_by_name': 'Project Engineer',
  'worker_count': 502,
  'regular_minutes': 241000,
  'overtime_minutes': 0,
  'warning_count': 1,
  'blocking_issue_count': 0,
  'reviewer_correction_count': 0,
  'missing_supporting_evidence_count': typedEvidence ? 3 : 0,
  'supporting_evidence_policy': typedEvidence
      ? 'typed_validation_issue'
      : 'not_configured',
  'high_overtime_exception_count': typedEvidence ? 2 : 0,
  'overtime_limit_policy': typedEvidence
      ? 'typed_validation_issue'
      : 'not_configured',
  'can_return': true,
  'can_correct': true,
  'can_verify': true,
  'can_final_approve': false,
  'updated_at': '2026-08-31T02:00:00Z',
  'exception_priority': 10,
};

final class _Repository implements YorksWorkforceDashboardRepository {
  _Repository(
    this.kind, {
    this.empty = false,
    this.actionFlags,
    this.typedEvidence = false,
  });
  final YorksWorkforceOverviewKind kind;
  final bool empty;
  final Map<String, bool>? actionFlags;
  final bool typedEvidence;
  @override
  Future<YorksWorkforceOverviewProjection> getOverview(
    YorksWorkforceOverviewRequest request,
  ) async => YorksWorkforceOverviewProjection.fromRpcJson(
    _overviewJson(
      kind,
      empty: empty,
      actionFlags: actionFlags,
      typedEvidence: typedEvidence,
    ),
  );
}

final class _DeniedRepository implements YorksWorkforceDashboardRepository {
  @override
  Future<YorksWorkforceOverviewProjection> getOverview(
    YorksWorkforceOverviewRequest request,
  ) => throw const YorksV1DomainException(YorksV1DomainErrorCode.unauthorized);
}

class _Connectivity implements ConnectivityService {
  const _Connectivity(this.isOnline);
  @override
  final bool isOnline;
  @override
  Stream<bool> get onChange => const Stream.empty();
}

final class _MutableConnectivity implements ConnectivityService {
  _MutableConnectivity(this._online);
  bool _online;
  final _changes = StreamController<bool>.broadcast();
  @override
  bool get isOnline => _online;
  @override
  Stream<bool> get onChange => _changes.stream;
  void setOnline(bool value) {
    _online = value;
    _changes.add(value);
  }
}

Directory _flutterCacheDirectory() {
  var directory = File(Platform.resolvedExecutable).parent;
  for (var index = 0; index < 4; index += 1) {
    if (Directory('${directory.path}/artifacts').existsSync()) return directory;
    directory = directory.parent;
  }
  throw StateError('Flutter cache directory was not found');
}

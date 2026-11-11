import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/workforce/application/workforce_monthly_period_controller.dart';
import 'package:material_ledger/features/workforce/application/workforce_providers.dart';
import 'package:material_ledger/features/workforce/application/workforce_report_controller.dart';
import 'package:material_ledger/features/workforce/application/workforce_review_controller.dart';
import 'package:material_ledger/features/workforce/data/workforce_report_service.dart';
import 'package:material_ledger/features/workforce/data/workforce_repository.dart';
import 'package:material_ledger/features/workforce/domain/workforce_report_models.dart';
import 'package:material_ledger/features/workforce/presentation/screens/yorks_workforce_reports_panel.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_workforce_strings.dart';
import 'package:material_ledger/shared/services/yorks_v1_critical_command_key_store.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _artifactId = '91000000-0000-4000-8000-000000000001';
const _snapshotId = '91000000-0000-4000-8000-000000000002';
const _teamId = '91000000-0000-4000-8000-000000000003';
const _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'T09 Reports is overflow-free desktop and actionable mobile RTL',
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
        final controller = await _controller();
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              yorksWorkforceReportControllerProvider.overrideWith(
                (ref) => controller,
              ),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              home: Directionality(
                textDirection: language.isRtl
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                child: Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: YorksWorkforceReportsPanel(
                      language: language,
                      monthlyState: const YorksWorkforceMonthlyState(
                        status: YorksWorkforceMonthlyStatus.ready,
                        periodMonth: '2026-08-01',
                        selectedTeamId: _teamId,
                        selectedDate: '2026-08-01',
                      ),
                      reviewState: const YorksWorkforceReviewState(),
                      compact: viewport.width < 720,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(YorksV1WorkforceStrings.text(language, 'reports_title')),
          findsOneWidget,
        );
        final context = tester.element(
          find.text(YorksV1WorkforceStrings.text(language, 'reports_title')),
        );
        expect(
          Directionality.of(context),
          language.isRtl ? TextDirection.rtl : TextDirection.ltr,
        );
        expect(
          find.byKey(const Key('workforce-report-generate')),
          findsOneWidget,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '$viewport ${language.code}',
        );
      }
    },
  );

  for (final exportWidth in [360.0, 1366.0]) {
    testWidgets('history opens protected export actions at $exportWidth', (
      tester,
    ) async {
      tester.view.physicalSize = Size(exportWidth, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = await _controller();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksWorkforceReportControllerProvider.overrideWith(
              (ref) => controller,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: SingleChildScrollView(
                child: YorksWorkforceReportsPanel(
                  language: AppLanguage.english,
                  monthlyState: const YorksWorkforceMonthlyState(
                    status: YorksWorkforceMonthlyStatus.ready,
                    periodMonth: '2026-08-01',
                    selectedTeamId: _teamId,
                  ),
                  reviewState: const YorksWorkforceReviewState(),
                  compact: exportWidth < 720,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final reportLabel = YorksV1WorkforceStrings.text(
        AppLanguage.english,
        'report_supervisor_team_monthly',
      );
      await tester.tap(find.widgetWithText(ListTile, reportLabel));
      await tester.pumpAndSettle();
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('T09 Reports Team'), findsOneWidget);
      expect(find.text('Approved · Locked source'), findsOneWidget);
      expect(find.text('Download Excel'), findsOneWidget);
      expect(find.text('Download PDF'), findsOneWidget);
      expect(find.text('Print'), findsOneWidget);
      expect(find.text('Share PDF'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<YorksWorkforceReportController> _controller() async =>
    YorksWorkforceReportController(
      repository: _Repository(),
      binaryService: _Binary(),
      commandKeys: YorksV1CriticalCommandKeyStore(
        preferences: await SharedPreferences.getInstance(),
        actorAuthUserId: _teamId,
      ),
      connectivity: const _Connectivity(),
    );

final class _Repository implements YorksWorkforceReportRepository {
  @override
  Future<YorksWorkforceReportArtifact> generateReport(
    YorksWorkforceReportRequest request, {
    required String idempotencyKey,
  }) async => YorksWorkforceReportArtifact.fromRpcJson(_artifactJson());

  @override
  Future<YorksWorkforceReportHistory> listReportArtifacts({
    int limit = 25,
    int offset = 0,
  }) async => YorksWorkforceReportHistory.fromRpcJson({
    'schema_version': 1,
    'authorization_mode': 'enforced_t09',
    'limit': limit,
    'offset': offset,
    'total_count': 1,
    'items': [_artifactJson()],
  });

  @override
  Future<YorksWorkforceReportIssueReceipt> issueReportExport(
    YorksWorkforceReportIssueRequest request, {
    required String idempotencyKey,
  }) async => YorksWorkforceReportIssueReceipt.fromRpcJson({
    'schema_version': 1,
    'authorization_mode': 'enforced_t09',
    'artifact_id': request.artifactId,
    'format': request.format.name,
    'action': request.action.name,
    'source_hash': _hash,
    'report_payload_hash': _hash,
    'issued_at': '2026-08-31T00:05:00Z',
    'issued_by': _teamId,
    'issued_by_role': 'admin',
    'capability_key': 'workforce.reports.export',
    'scope_kind': 'team',
    'scope_reference': _teamId,
    'source_authority_hash': _hash,
  });
}

final class _Binary implements YorksWorkforceReportBinaryService {
  @override
  Uint8List buildExcel(YorksWorkforceReportArtifact report) =>
      Uint8List.fromList([1]);
  @override
  Future<Uint8List> buildPdf(YorksWorkforceReportArtifact report) async =>
      Uint8List.fromList([2]);
  @override
  Future<void> printPdfBytes(Uint8List bytes) async {}
  @override
  Future<void> saveExcelBytes(
    Uint8List bytes,
    YorksWorkforceReportArtifact report,
  ) async {}
  @override
  Future<void> savePdfBytes(
    Uint8List bytes,
    YorksWorkforceReportArtifact report,
  ) async {}
  @override
  Future<void> sharePdfBytes(
    Uint8List bytes,
    YorksWorkforceReportArtifact report,
  ) async {}
}

final class _Connectivity implements ConnectivityService {
  const _Connectivity();
  @override
  bool get isOnline => true;
  @override
  Stream<bool> get onChange => const Stream.empty();
}

Map<String, dynamic> _artifactJson() => {
  'schema_version': 1,
  'authorization_mode': 'enforced_t09',
  'artifact_id': _artifactId,
  'report_kind': 'supervisor_team_monthly',
  'source_kind': 'approved_snapshot',
  'source_status': 'approved_locked',
  'source_version': _snapshotId,
  'source_hash': _hash,
  'period_month': '2026-08-01',
  'work_date': null,
  'scope_kind': 'team',
  'scope_reference': _teamId,
  'generated_at': '2026-08-31T00:00:00Z',
  'generated_by': 'Local Admin',
  'generated_by_role': 'admin',
  'company_legal_name': 'Yorks Air Conditioning & Refrigeration LLC-SPC',
  'company_secondary_name': 'يوركس للتكييف والتبريد - ذ.م.م - ش.ش.و',
  'sources': const [
    {
      'snapshot_id': _snapshotId,
      'period_id': '59980000-0000-4000-8000-000000000001',
      'approval_revision_number': 1,
      'snapshot_hash': _hash,
      'approved_at': '2026-08-30T23:59:00Z',
      'approved_by': 'Local Admin',
      'approved_role': 'admin',
      'review_chain': [],
    },
  ],
  'columns': const [
    {'key': 'team', 'label': 'Team', 'type': 'text'},
    {'key': 'period_month', 'label': 'Period', 'type': 'date'},
    {'key': 'workers_managed', 'label': 'Workers Managed', 'type': 'integer'},
    {
      'key': 'attendance_summary',
      'label': 'Attendance Summary',
      'type': 'text',
    },
    {'key': 'regular_hours', 'label': 'Regular Hours', 'type': 'decimal'},
    {'key': 'overtime_hours', 'label': 'OT Hours', 'type': 'decimal'},
    {'key': 'absences', 'label': 'Absences', 'type': 'integer'},
    {'key': 'projects', 'label': 'Projects', 'type': 'text'},
    {'key': 'exceptions', 'label': 'Exceptions', 'type': 'text'},
    {
      'key': 'review_approval_status',
      'label': 'Review / Approval Status',
      'type': 'text',
    },
  ],
  'rows': const [
    {
      'team': 'T09 Reports Team',
      'period_month': '2026-08-01',
      'workers_managed': 1,
      'attendance_summary': 'Present 1',
      'regular_hours': 8,
      'overtime_hours': 0,
      'absences': 0,
      'projects': 'WF-T09',
      'exceptions': 'None',
      'review_approval_status': 'Approved & locked · R1',
    },
  ],
  'totals': const {
    'row_count': 1,
    'regular_minutes': 480,
    'overtime_minutes': 0,
    'man_days': 1,
  },
};

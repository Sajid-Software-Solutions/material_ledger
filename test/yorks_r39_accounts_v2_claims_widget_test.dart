import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/accounts/application/accounts_providers.dart';
import 'package:material_ledger/features/accounts/application/v2/accounts_workspace_v2_controllers.dart';
import 'package:material_ledger/features/accounts/data/accounts_repository.dart'
    show YorksAccountsRpcClient;
import 'package:material_ledger/features/accounts/data/v2/accounts_workspace_repository.dart';
import 'package:material_ledger/features/accounts/domain/v2/claim_workbench_models.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_claims_tab.dart';
import 'package:material_ledger/features/accounts/presentation/v2/yorks_accounts_workspace_v2_screen.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_common.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _workbenchJson({
  bool commercial = true,
  bool withClaim = true,
  bool confirm = false,
  String claimStatus = 'draft',
}) {
  Map<String, dynamic> cell({
    required String id,
    required String stageKey,
    required String stageLabel,
    required int pos,
    required String mode,
    required String confirmed,
    List<Map<String, dynamic>>? items,
  }) {
    return <String, dynamic>{
      'progress_entry_id': id,
      'building_scope_id': 'b01',
      'building_name': 'Block A',
      'stage_key': stageKey,
      'stage_label': stageLabel,
      'stage_position': pos,
      'measurement_mode': mode,
      'confirmed_percent': confirmed,
      'review_status': 'not_required',
      'record_version': 1,
      'over_claimed': false,
      'items': ?items,
      if (commercial) ...{
        'stage_value': '100000.00',
        'eligible': '50000.00',
        'claimed': '0.00',
        'available': '50000.00',
      },
    };
  }

  return <String, dynamic>{
    'schema_version': 1,
    'project_id': 'p1',
    'baseline_revision_id': 'rev1',
    'baseline_revision_number': 1,
    'capabilities': {
      'view_project_commercial_values': commercial,
      'can_confirm': confirm,
    },
    'commands': <String, dynamic>{},
    'cells': [
      cell(
        id: 'pe-design',
        stageKey: 'design',
        stageLabel: 'Design',
        pos: 1,
        mode: 'percent',
        confirmed: '50.0000',
      ),
      cell(
        id: 'pe-material',
        stageKey: 'material_supply',
        stageLabel: 'Material Supply',
        pos: 2,
        mode: 'items',
        confirmed: '25.0000',
        items: [
          {
            'stage_item_id': 'si1',
            'item_key': 'ahu',
            'item_label': 'AHU units',
            'display_order': 1,
            'quantity': '4.0000',
            'unit_code': 'Nos',
            'confirmed_qty': '1.0000',
            'needs_review': false,
            if (commercial) 'item_value': '250000.00',
          },
        ],
      ),
    ],
    'claim': withClaim
        ? {
            'claim_id': 'c1',
            'claim_reference': 'CLM-01',
            'status': claimStatus,
            'record_version': 2,
            'claim_period_start': '2026-08-01',
            'claim_period_end': '2026-08-25',
            if (commercial) 'claimed_ex_vat': '50000.00',
            'lines': [
              {'progress_entry_id': 'pe-design'},
            ],
          }
        : null,
  };
}

final class _FakeRpc implements YorksAccountsRpcClient {
  _FakeRpc(this.response);
  final Map<String, dynamic> response;

  @override
  Future<Map<String, dynamic>> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async => response;
}

void _wideSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  const en = AppLanguage.english;
  String t(String key) => accountsV2Text(en, key);

  group('AccountsV2ClaimsTab (direct)', () {
    testWidgets('renders the claim panel and the progress grid', (
      tester,
    ) async {
      _wideSurface(tester);
      final wb = YorksAccountsWorkbench.fromJson(_workbenchJson());
      await tester.pumpWidget(
        _wrap(AccountsV2ClaimsTab(workbench: wb, language: en)),
      );
      await tester.pumpAndSettle();

      expect(find.text('CLM-01'), findsOneWidget);
      expect(find.text(t('v2_claim_status_draft')), findsWidgets);
      expect(find.text('Design'), findsOneWidget);
      expect(find.text('Material Supply'), findsOneWidget);
      expect(find.text('Block A'), findsWidgets);
      expect(find.text('AHU units'), findsOneWidget);
      // Commercial columns present.
      expect(find.text('AED 50,000.00'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('omits money columns without the capability', (tester) async {
      _wideSurface(tester);
      final wb = YorksAccountsWorkbench.fromJson(
        _workbenchJson(commercial: false),
      );
      await tester.pumpWidget(
        _wrap(AccountsV2ClaimsTab(workbench: wb, language: en)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Design'), findsOneWidget);
      expect(find.textContaining('AED'), findsNothing);
      // Confirmed % is structural and still shown.
      expect(find.text('50%'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the no-claim note when nothing is open', (tester) async {
      _wideSurface(tester);
      final wb = YorksAccountsWorkbench.fromJson(
        _workbenchJson(withClaim: false),
      );
      await tester.pumpWidget(
        _wrap(AccountsV2ClaimsTab(workbench: wb, language: en)),
      );
      await tester.pumpAndSettle();

      expect(find.text(t('v2_claims_no_claim')), findsOneWidget);
      expect(find.text('CLM-01'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('AccountsV2ClaimsTab record progress', () {
    testWidgets('confirms an increase with evidence via onSaveWorkbench', (
      tester,
    ) async {
      _wideSurface(tester);
      final wb = YorksAccountsWorkbench.fromJson(_workbenchJson(confirm: true));
      List<Map<String, Object?>>? capturedEntries;
      List<String>? capturedEvidence;
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: wb,
            language: en,
            canRecordProgress: true,
            evidenceDocuments: const [(id: 'doc1', name: 'Signed sheet')],
            onSaveWorkbench:
                ({
                  String? claimReference,
                  required String periodStart,
                  required String periodEnd,
                  required List<Map<String, Object?>> entries,
                  required List<String> evidenceDocumentIds,
                  String? reason,
                }) async {
                  capturedEntries = entries;
                  capturedEvidence = evidenceDocumentIds;
                  return null;
                },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(t('v2_record_progress')), findsOneWidget);
      await tester.tap(find.text(t('v2_record_progress')));
      await tester.pumpAndSettle();

      // Fields: period start(0), end(1), the single percent cell(2), reason(3).
      await tester.enterText(find.byType(TextField).at(2), '75');
      await tester.pumpAndSettle();
      // Increase needs evidence — select the document, then save.
      await tester.tap(find.text('Signed sheet'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_save')));
      await tester.pumpAndSettle();

      expect(capturedEntries, isNotNull);
      expect(capturedEntries!.single['progress_entry_id'], 'pe-design');
      expect(capturedEntries!.single['confirmed_percent_to_date'], '75');
      expect(capturedEvidence, ['doc1']);
      expect(find.text(t('v2_progress_saved')), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no record-progress button without the capability', (
      tester,
    ) async {
      _wideSurface(tester);
      final wb = YorksAccountsWorkbench.fromJson(_workbenchJson());
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: wb,
            language: en,
            canRecordProgress: false,
            onSaveWorkbench:
                ({
                  String? claimReference,
                  required String periodStart,
                  required String periodEnd,
                  required List<Map<String, Object?>> entries,
                  required List<String> evidenceDocumentIds,
                  String? reason,
                }) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(t('v2_record_progress')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('AccountsV2ClaimsTab actions', () {
    testWidgets('checked claim issues an invoice through onIssue', (
      tester,
    ) async {
      _wideSurface(tester);
      final wb = YorksAccountsWorkbench.fromJson(
        _workbenchJson(claimStatus: 'ready_for_accounts'),
      );
      String? issuedId;
      int? issuedVersion;
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: wb,
            language: en,
            onIssue:
                ({
                  required String claimId,
                  required int expectedClaimVersion,
                  required String invoiceDate,
                  required String submissionDate,
                  String? invoiceReference,
                }) async {
                  issuedId = claimId;
                  issuedVersion = expectedClaimVersion;
                  return null;
                },
            onReopen:
                ({
                  required String claimId,
                  required int expectedVersion,
                  required String reason,
                }) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(t('v2_claim_issue')), findsOneWidget);
      expect(find.text(t('v2_claim_back_to_draft')), findsOneWidget);

      await tester.tap(find.text(t('v2_claim_issue')));
      await tester.pumpAndSettle();
      // Dialog pre-fills today's dates, so Confirm is enabled.
      await tester.tap(find.text(t('v2_confirm')));
      await tester.pumpAndSettle();

      expect(issuedId, 'c1');
      expect(issuedVersion, 2);
      expect(find.text(t('v2_claim_issued')), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('back to draft requires a reason and calls onReopen', (
      tester,
    ) async {
      _wideSurface(tester);
      final wb = YorksAccountsWorkbench.fromJson(
        _workbenchJson(claimStatus: 'ready_for_accounts'),
      );
      String? reopenReason;
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: wb,
            language: en,
            onIssue:
                ({
                  required String claimId,
                  required int expectedClaimVersion,
                  required String invoiceDate,
                  required String submissionDate,
                  String? invoiceReference,
                }) async => null,
            onReopen:
                ({
                  required String claimId,
                  required int expectedVersion,
                  required String reason,
                }) async {
                  reopenReason = reason;
                  return null;
                },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(t('v2_claim_back_to_draft')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Correction needed');
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_confirm')));
      await tester.pumpAndSettle();

      expect(reopenReason, 'Correction needed');
      expect(find.text(t('v2_claim_reopened')), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('YorksAccountsWorkspaceV2Screen (Progress & claims tab)', () {
    testWidgets('opening on claims loads the workbench from the repository', (
      tester,
    ) async {
      _wideSurface(tester);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final repo = YorksAccountsWorkspaceRepository(_FakeRpc(_workbenchJson()));
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          yorksV1CurrentRoleProvider.overrideWithValue(null),
          yorksAccountsPermissionEpochProvider.overrideWithValue((
            revision: 1,
            trusted: true,
            stale: false,
            revisionSignalHealthy: true,
          )),
          yorksAccountsWorkspaceRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _wrap(
            const YorksAccountsWorkspaceV2Screen(
              projectId: 'p1',
              initialTab: YorksAccountsWorkspaceV2Tab.claims,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CLM-01'), findsOneWidget);
      expect(find.text('Design'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/accounts/application/accounts_providers.dart';
import 'package:material_ledger/features/accounts/application/v2/accounts_workspace_v2_controllers.dart';
import 'package:material_ledger/features/accounts/data/accounts_repository.dart'
    show YorksAccountsRpcClient;
import 'package:material_ledger/features/accounts/data/v2/accounts_workspace_repository.dart';
import 'package:material_ledger/features/accounts/domain/v2/claim_workbench_models.dart';
import 'package:material_ledger/features/accounts/domain/v2/claims_list_models.dart';
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
    'capabilities': {'can_view_values': commercial, 'can_confirm': confirm},
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
            if (commercial) ...{
              'claimed_ex_vat': '50000.00',
              'vat_amount': '2500.00',
              'net_payable': '52500.00',
              'retention_percent': '10.0000',
              'retention_preview': '5000.00',
              'net_payable_after_retention': '47500.00',
            },
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

    testWidgets('claim panel previews the retention hold-back', (tester) async {
      _wideSurface(tester);
      final wb = YorksAccountsWorkbench.fromJson(_workbenchJson());
      await tester.pumpWidget(
        _wrap(AccountsV2ClaimsTab(workbench: wb, language: en)),
      );
      await tester.pumpAndSettle();

      // §28 R-1/R-4 preview: retention (shown as a deduction) and the resulting
      // net-after-retention payable.
      expect(
        find.text('${t('v2_claim_retention_preview')} · 10%'),
        findsOneWidget,
      );
      expect(find.text('− AED 5,000.00'), findsOneWidget);
      expect(find.text(t('v2_claim_net_after_retention')), findsOneWidget);
      expect(find.text('AED 47,500.00'), findsWidgets);
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

    testWidgets('claim cards switch the active claim via onSelectClaim', (
      tester,
    ) async {
      _wideSurface(tester);
      final wb = YorksAccountsWorkbench.fromJson(_workbenchJson());
      String? selected;
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: wb,
            language: en,
            claims: [
              YorksAccountsClaimSummary.fromJson(const {
                'claim_id': 'c1',
                'claim_reference': 'YRA322-CLM-02',
                'status': 'draft',
                'claim_period_start': '2026-08-01',
                'claim_period_end': '2026-08-25',
                'claimed_ex_vat': '1504300.00',
                'record_version': 2,
              }),
              YorksAccountsClaimSummary.fromJson(const {
                'claim_id': 'c0',
                'claim_reference': 'YRA322-CLM-01',
                'status': 'invoiced',
                'claim_period_start': '2026-07-01',
                'claim_period_end': '2026-07-25',
                'claimed_ex_vat': '1000000.00',
                'record_version': 3,
              }),
            ],
            onSelectClaim: (id) => selected = id,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Both claims appear as cards; tapping the older one selects it.
      expect(find.text('YRA322-CLM-01'), findsOneWidget);
      await tester.tap(find.text('YRA322-CLM-01'));
      await tester.pump();
      expect(selected, 'c0');
      expect(tester.takeException(), isNull);
    });
  });

  group('AccountsV2ClaimsTab record progress', () {
    testWidgets('confirms an item quantity for an items-mode stage', (
      tester,
    ) async {
      _wideSurface(tester);
      final wb = YorksAccountsWorkbench.fromJson(_workbenchJson(confirm: true));
      List<Map<String, Object?>>? capturedEntries;
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: wb,
            language: en,
            canRecordProgress: true,
            evidenceDocuments: const [(id: 'doc1', name: 'Delivery note')],
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
                  return null;
                },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(t('v2_record_progress')));
      await tester.pumpAndSettle();

      // Fields: start(0), end(1), design %(2), AHU item qty(3), reason(4).
      await tester.enterText(find.byType(TextField).at(3), '3');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delivery note'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_save')));
      await tester.pumpAndSettle();

      expect(capturedEntries, isNotNull);
      final itemEntry = capturedEntries!.firstWhere(
        (e) => e.containsKey('stage_item_id'),
        orElse: () => <String, Object?>{},
      );
      expect(itemEntry['stage_item_id'], 'si1');
      expect(itemEntry['confirmed_qty_to_date'], '3');
      expect(tester.takeException(), isNull);
    });

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

    testWidgets('Max fills a lump-sum cell to 100% and previews the delta', (
      tester,
    ) async {
      _wideSurface(tester);
      final wb = YorksAccountsWorkbench.fromJson(_workbenchJson(confirm: true));
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
                }) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_record_progress')));
      await tester.pumpAndSettle();

      // Two Max buttons: the Design lump-sum cell and the AHU item row.
      expect(find.text(t('v2_max')), findsNWidgets(2));
      await tester.tap(find.text(t('v2_max')).first);
      await tester.pumpAndSettle();

      // The percent field (index 2) is filled to 100 and a +50% delta previews.
      final field = tester.widget<TextField>(find.byType(TextField).at(2));
      expect(field.controller!.text, '100');
      expect(find.text('+50%'), findsOneWidget);
      expect(find.text('${t('v2_progress_changes')}: 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a value below the confirmed percent shows a decrease delta', (
      tester,
    ) async {
      _wideSurface(tester);
      final wb = YorksAccountsWorkbench.fromJson(_workbenchJson(confirm: true));
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: wb,
            language: en,
            canRecordProgress: true,
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
      await tester.tap(find.text(t('v2_record_progress')));
      await tester.pumpAndSettle();

      // Design confirmed is 50%; typing 30 shows a −20% decrease delta.
      await tester.enterText(find.byType(TextField).at(2), '30');
      await tester.pumpAndSettle();
      expect(find.text('−20%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('record-progress editor lays out at 360px wide', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final wb = YorksAccountsWorkbench.fromJson(_workbenchJson(confirm: true));
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
                }) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_record_progress')));
      await tester.pumpAndSettle();

      expect(find.text(t('v2_max')), findsNWidgets(2));
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

  group('AccountsV2ClaimsTab money visibility', () {
    test('reads the keys the server really sends', () {
      expect(
        YorksAccountsWorkbench.fromJson(_workbenchJson()).canViewValues,
        isTrue,
      );
      final old = _workbenchJson()
        ..['capabilities'] = {'view_project_commercial_values': true};
      expect(YorksAccountsWorkbench.fromJson(old).canViewValues, isFalse);
    });
  });

  group('AccountsV2ClaimsTab preview', () {
    testWidgets('previews the invoice before issuing', (tester) async {
      _wideSurface(tester);
      String? previewed;
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: YorksAccountsWorkbench.fromJson(
              _workbenchJson(claimStatus: 'ready_for_accounts'),
            ),
            language: en,
            onIssue:
                ({
                  required String claimId,
                  required int expectedClaimVersion,
                  required String invoiceDate,
                  required String submissionDate,
                  String? invoiceReference,
                }) async => null,
            onPreviewInvoice: (id) async {
              previewed = id;
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_claim_preview')));
      await tester.pumpAndSettle();
      expect(previewed, 'c1');
      expect(tester.takeException(), isNull);
    });
  });

  group('AccountsV2ClaimsTab mark checked', () {
    testWidgets('draft claim with lines marks checked via onMarkChecked', (
      tester,
    ) async {
      _wideSurface(tester);
      final wb = YorksAccountsWorkbench.fromJson(_workbenchJson());
      String? markReason;
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: wb,
            language: en,
            onMarkChecked:
                ({
                  required String claimId,
                  required int expectedVersion,
                  required String reason,
                }) async {
                  markReason = reason;
                  return null;
                },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final markButton = find.text(t('v2_claim_mark_checked'));
      expect(markButton, findsOneWidget);
      await tester.ensureVisible(markButton);
      await tester.pumpAndSettle();
      await tester.tap(markButton);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Looks good');
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_confirm')));
      await tester.pumpAndSettle();

      expect(markReason, 'Looks good');
      expect(find.text(t('v2_claim_checked_done')), findsWidgets);
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

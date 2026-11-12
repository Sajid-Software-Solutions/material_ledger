import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/accounts/application/accounts_providers.dart';
import 'package:material_ledger/features/accounts/application/v2/accounts_unsaved_drafts.dart';
import 'package:material_ledger/features/accounts/application/v2/accounts_workspace_v2_controllers.dart';
import 'package:material_ledger/features/accounts/data/accounts_repository.dart'
    show YorksAccountsRpcClient;
import 'package:material_ledger/features/accounts/data/v2/accounts_workspace_repository.dart';
import 'package:material_ledger/features/accounts/domain/v2/claim_workbench_models.dart';
import 'package:material_ledger/features/accounts/domain/v2/claims_list_models.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_claims_tab.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_common.dart';
import 'package:material_ledger/features/accounts/presentation/v2/kit/accounts_v2_kit.dart';
import 'package:material_ledger/features/accounts/presentation/v2/yorks_accounts_workspace_v2_screen.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/services/yorks_v1_procurement_unload_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One building (Block A), two stages:
/// - Design, lump sum: stage value 100,000; 50% confirmed, all of it in this
///   draft claim (AED 50,000).
/// - Material Supply, by items: AHU units 4 Nos worth 250,000; 1 done before
///   the claim, none in it.
Map<String, dynamic> _workbenchJson({
  bool commercial = true,
  bool withClaim = true,
  bool confirm = true,
  bool prepare = true,
  String claimStatus = 'draft',
  bool suggestion = false,
}) {
  return <String, dynamic>{
    'schema_version': 1,
    'project_id': 'p1',
    'baseline_revision_id': 'rev1',
    'baseline_revision_number': 1,
    'capabilities': {'can_view_values': commercial, 'can_confirm': confirm},
    'commands': {'create_claim_draft': prepare, 'cancel_claim': true},
    'cells': [
      {
        'progress_entry_id': 'pe-design',
        'building_scope_id': 'b01',
        'building_name': 'Block A',
        'stage_key': 'design',
        'stage_label': 'Design',
        'stage_position': 1,
        'measurement_mode': 'percent',
        'confirmed_percent': '50.0000',
        'review_status': 'not_required',
        'record_version': 1,
        'over_claimed': false,
        'percent_before_claim': '0',
        'percent_this_claim': '50.0000',
        if (suggestion) ...{
          'suggested_percent': '70.0000',
          'suggested_by': 'Site Sam',
          'suggested_evidence_document_ids': ['doc-sug'],
        },
        if (commercial) ...{
          // The real RPC sends stage values unrounded.
          'stage_value': '100000.000000000000',
          'eligible': '50000.00',
          'claimed': '50000.00',
          'available': '0.00',
          'claimed_before_claim': '0.00',
          'this_claim_amount': '50000.00',
        },
      },
      {
        'progress_entry_id': 'pe-material',
        'building_scope_id': 'b01',
        'building_name': 'Block A',
        'stage_key': 'material_supply',
        'stage_label': 'Material Supply',
        'stage_position': 2,
        'measurement_mode': 'items',
        'confirmed_percent': '25.0000',
        'review_status': 'not_required',
        'record_version': 1,
        'over_claimed': false,
        'percent_before_claim': '25.0000',
        'percent_this_claim': '0',
        if (commercial) ...{
          'stage_value': '400000.00',
          'eligible': '62500.00',
          'claimed': '62500.00',
          'available': '0.00',
          'claimed_before_claim': '62500.00',
          'this_claim_amount': '0.00',
        },
        'items': [
          {
            'stage_item_id': 'si1',
            'item_key': 'ahu',
            'item_label': 'AHU units',
            'display_order': 1,
            'quantity': '4.0000',
            'unit_code': 'Nos',
            'confirmed_qty': '1.0000',
            'needs_review': false,
            'qty_before_claim': '1.0000',
            'qty_this_claim': '0',
            if (commercial) 'item_value': '250000.00',
          },
        ],
      },
    ],
    'claim': withClaim
        ? {
            'claim_id': 'c1',
            'claim_reference': 'CLM-01',
            'status': claimStatus,
            'record_version': 2,
            'claim_period_start': '2026-08-01',
            'claim_period_end': '2026-08-25',
            'prepared_by': 'Pat Engineer',
            if (claimStatus != 'draft') 'checked_by': 'Morgan Manager',
            if (commercial) ...{
              'claimed_ex_vat': '50000.00',
              'vat_amount': '2500.00',
              'net_payable': '52500.00',
              'retention_percent': '10.0000',
              'retention_preview': '5000.00',
              'net_payable_after_retention': '47500.00',
              if (claimStatus == 'invoiced')
                'invoice': {
                  'invoice_id': 'inv1',
                  'invoice_reference': 'YRA32201',
                  'status': 'submitted',
                  'submission_date': '2026-08-26',
                },
            },
            'lines': [
              {'progress_entry_id': 'pe-design'},
            ],
          }
        : null,
  };
}

YorksAccountsWorkbench _wb({
  bool commercial = true,
  bool withClaim = true,
  bool confirm = true,
  bool prepare = true,
  String claimStatus = 'draft',
  bool suggestion = false,
}) => YorksAccountsWorkbench.fromJson(
  _workbenchJson(
    commercial: commercial,
    withClaim: withClaim,
    confirm: confirm,
    prepare: prepare,
    claimStatus: claimStatus,
    suggestion: suggestion,
  ),
);

final _claims = [
  YorksAccountsClaimSummary.fromJson(const {
    'claim_id': 'c1',
    'claim_reference': 'CLM-01',
    'status': 'draft',
    'claim_period_start': '2026-08-01',
    'claim_period_end': '2026-08-25',
    'claimed_ex_vat': '50000.00',
    'record_version': 2,
  }),
  YorksAccountsClaimSummary.fromJson(const {
    'claim_id': 'c0',
    'claim_reference': 'CLM-00',
    'status': 'invoiced',
    'claim_period_start': '2026-07-01',
    'claim_period_end': '2026-07-25',
    'claimed_ex_vat': '10000.00',
    'record_version': 4,
  }),
];

final class _FakeRpc implements YorksAccountsRpcClient {
  _FakeRpc(this.response);
  final Map<String, dynamic> response;

  @override
  Future<Map<String, dynamic>> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async => response;
}

void _surface(WidgetTester tester, {double width = 1400}) {
  tester.view.physicalSize = Size(width, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Finder _button(String label) => find.widgetWithText(AccountsV2Button, label);

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// The input of a workbench row: the Design lump input first, then items.
Finder _input(int index) => find.byType(AccountsV2CellInput).at(index);

void main() {
  const en = AppLanguage.english;
  String t(String key) => accountsV2Text(en, key);

  // YRA-322 after the contract correction: Design was 100% done and billed at
  // the old value (429,800); at the corrected value the stage is 452,136.70.
  YorksAccountsWorkbench corrected({required bool invoiced}) {
    final json = _workbenchJson(withClaim: invoiced, claimStatus: 'invoiced');
    final design = (json['cells'] as List).first as Map<String, dynamic>;
    design
      ..['confirmed_percent'] = '100.0000'
      ..['percent_before_claim'] = '100.0000'
      ..['percent_this_claim'] = '0'
      ..['stage_value'] = '452136.70'
      ..['eligible'] = '452136.70'
      ..['claimed'] = '429800.00'
      ..['available'] = '22336.70'
      ..['claimed_before_claim'] = '429800.00'
      ..['this_claim_amount'] = '0.00';
    if (invoiced) {
      (json['claim'] as Map<String, dynamic>)['lines'] = [
        {'progress_entry_id': 'pe-material'},
      ];
    }
    return YorksAccountsWorkbench.fromJson(json);
  }

  group('contract correction', () {
    testWidgets('a stage finished before it still reads 100% done', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: corrected(invoiced: true),
            language: en,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('100.0%'), findsWidgets);
      expect(find.text('95.1%'), findsNothing);
      // An invoiced claim shows what it billed; no top-up note.
      expect(find.textContaining('22,336.70'), findsNothing);
    });

    testWidgets('a new claim carries the top-up and says why', (tester) async {
      _surface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: corrected(invoiced: false),
            language: en,
            canRecordProgress: true,
            onSaveWorkbench: _noSave,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.textContaining(t('v2p_start_claim')).first);
      // Open Design to see its editor.
      await _tap(tester, find.text('Design').first);
      expect(find.text('100.0%'), findsWidgets);
      expect(
        find.text(t('v2p_topup_note').replaceAll('{amount}', 'AED 22,336.70')),
        findsOneWidget,
      );
      expect(find.text('22,336.70'), findsWidgets);

      // Discard goes back to the claim in view without the new claim's money.
      await _tap(tester, find.text(t('v2c_discard')).first);
      expect(
        find.text(t('v2p_topup_note').replaceAll('{amount}', 'AED 22,336.70')),
        findsNothing,
      );
      expect(find.textContaining('22,336.70'), findsNothing);
    });
  });

  group('AccountsV2ClaimsTab layout', () {
    testWidgets('renders KPIs, the workbench and the claim details', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
        _wrap(AccountsV2ClaimsTab(workbench: _wb(), language: en)),
      );
      await tester.pumpAndSettle();

      expect(find.text(t('v2p_kpi_this_claim')), findsWidgets);
      expect(find.text('AED 50,000.00'), findsWidgets);
      expect(find.text(t('v2p_wb_title')), findsOneWidget);
      expect(find.text('Block A'), findsOneWidget);
      expect(find.text('Design'), findsWidgets);
      expect(find.text('Material Supply'), findsWidgets);
      expect(find.text(t('v2p_claim_details')), findsOneWidget);
      expect(find.text('${t('v2p_claim')} #01'), findsOneWidget);
      expect(find.textContaining('Pat Engineer'), findsWidgets);
      // Net payable in words, as the prototype writes it.
      expect(find.textContaining('UAE Dirham Fifty Two Thousand'), findsOne);
      expect(tester.takeException(), isNull);
    });

    testWidgets('splits Design into done before and this claim', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
        _wrap(AccountsV2ClaimsTab(workbench: _wb(), language: en)),
      );
      await tester.pumpAndSettle();
      // Design has this claim's progress, so it opens by itself.
      expect(find.text(t('v2p_col_done_before').toUpperCase()), findsOneWidget);
      // Read-only here (no capability), so this claim's % is plain text.
      expect(find.byType(AccountsV2CellInput), findsNothing);
      expect(find.text('50'), findsWidgets);
      expect(find.text('50,000.00'), findsWidgets);
    });

    testWidgets('previews the retention hold-back in the claim panel', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
        _wrap(AccountsV2ClaimsTab(workbench: _wb(), language: en)),
      );
      await tester.pumpAndSettle();
      expect(find.text('${t('v2p_retention_held')} 10%'), findsOneWidget);
      expect(find.text('− AED 5,000.00'), findsOneWidget);
      expect(find.text(t('v2p_after_retention')), findsOneWidget);
      expect(find.text('AED 47,500.00'), findsOneWidget);
    });

    testWidgets('shows no money without the capability', (tester) async {
      _surface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(workbench: _wb(commercial: false), language: en),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Design'), findsWidgets);
      expect(find.textContaining('AED'), findsNothing);
      expect(find.text(t('v2p_kpi_net')), findsNothing);
      // Progress is not commercial and still shows.
      expect(find.text('50.0%'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lays out at 360px wide', (tester) async {
      _surface(tester, width: 360);
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: _wb(),
            language: en,
            canRecordProgress: true,
            onSaveWorkbench: _noSave,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(_input(0), '60');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('AccountsV2ClaimsTab with no claim', () {
    testWidgets('offers to start the first claim to someone who can', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: _wb(withClaim: false),
            language: en,
            canRecordProgress: true,
            onSaveWorkbench: _noSave,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(t('v2p_no_claims_title')), findsOneWidget);
      await _tap(tester, _button('${t('v2p_start_claim')} #01'));
      // A new claim opens the workbench locally; nothing is on the server yet.
      expect(find.text('${t('v2p_claim')} #01'), findsOneWidget);
      expect(find.text(t('v2p_status_new')), findsWidgets);
    });

    testWidgets('does not offer it to someone who cannot', (tester) async {
      _surface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(workbench: _wb(withClaim: false), language: en),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(t('v2p_no_claims_title')), findsOneWidget);
      expect(find.textContaining(t('v2p_start_claim')), findsNothing);
    });
  });

  group('AccountsV2ClaimsTab recording progress', () {
    testWidgets('sends a lump-sum change as a running total with evidence', (
      tester,
    ) async {
      _surface(tester);
      List<Map<String, Object?>>? sentEntries;
      List<String>? evidence;
      String? reference;
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: _wb(),
            language: en,
            canRecordProgress: true,
            evidenceDocuments: const [(id: 'doc1', name: 'site.pdf')],
            onSaveWorkbench:
                ({
                  String? claimReference,
                  required String periodStart,
                  required String periodEnd,
                  required List<Map<String, Object?>> entries,
                  required List<String> evidenceDocumentIds,
                  String? reason,
                }) async {
                  reference = claimReference;
                  sentEntries = entries;
                  evidence = evidenceDocumentIds;
                  return null;
                },
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 50 this claim → 60: the running total sent is before (0) + 60.
      await tester.enterText(_input(0), '60');
      await tester.pumpAndSettle();
      expect(find.text(t('v2p_unsaved')), findsOneWidget);
      // Live amount: 60% of 100,000.
      expect(find.text('60,000.00'), findsWidgets);
      // An increase needs a file.
      expect(find.text(t('v2p_evidence_needed')), findsOneWidget);
      final save = tester.widget<AccountsV2Button>(
        _button(t('v2p_save_progress')),
      );
      expect(save.onPressed, isNull);
      await _tap(tester, _button(t('v2p_add_file')));
      await tester.tap(find.text('site.pdf').last);
      await tester.pumpAndSettle();
      await _tap(tester, _button(t('v2p_save_progress')));

      expect(sentEntries, [
        {'progress_entry_id': 'pe-design', 'confirmed_percent_to_date': '60'},
      ]);
      expect(evidence, ['doc1']);
      // The open draft keeps its reference.
      expect(reference, 'CLM-01');
      expect(find.text(t('v2_progress_saved')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sends an item quantity as before + this claim', (
      tester,
    ) async {
      _surface(tester);
      List<Map<String, Object?>>? sent;
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: _wb(),
            language: en,
            canRecordProgress: true,
            evidenceDocuments: const [(id: 'doc1', name: 'site.pdf')],
            onSaveWorkbench:
                ({
                  String? claimReference,
                  required String periodStart,
                  required String periodEnd,
                  required List<Map<String, Object?>> entries,
                  required List<String> evidenceDocumentIds,
                  String? reason,
                }) async {
                  sent = entries;
                  return null;
                },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Material Supply').first);
      // 1 done before; 2 more this claim → 3 to date.
      await tester.enterText(_input(1), '2');
      await tester.pumpAndSettle();
      expect(find.textContaining('3 · 75%'), findsOneWidget);
      await _tap(tester, _button(t('v2p_add_file')));
      await tester.tap(find.text('site.pdf').last);
      await tester.pumpAndSettle();
      await _tap(tester, _button(t('v2p_save_progress')));
      expect(sent, [
        {'stage_item_id': 'si1', 'confirmed_qty_to_date': '3'},
      ]);
    });

    testWidgets('Max fills a lump-sum stage to what is left of 100%', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: _wb(),
            language: en,
            canRecordProgress: true,
            onSaveWorkbench: _noSave,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text(t('v2p_max')).first);
      expect(
        tester.widget<AccountsV2CellInput>(_input(0)).controller.text,
        '100',
      );
      expect(find.text('100,000.00'), findsWidgets);
    });

    testWidgets('more than the whole stage cannot be saved', (tester) async {
      _surface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: _wb(),
            language: en,
            canRecordProgress: true,
            evidenceDocuments: const [(id: 'doc1', name: 'site.pdf')],
            onSaveWorkbench: _noSave,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(_input(0), '120');
      await tester.pumpAndSettle();
      expect(find.textContaining('120.0% ⚠'), findsOneWidget);
      await _tap(tester, _button(t('v2p_add_file')));
      await tester.tap(find.text('site.pdf').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AccountsV2Button>(_button(t('v2p_save_progress')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('Discard puts the server figures back', (tester) async {
      _surface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: _wb(),
            language: en,
            canRecordProgress: true,
            onSaveWorkbench: _noSave,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(_input(0), '70');
      await tester.pumpAndSettle();
      await _tap(tester, _button(t('v2c_discard')));
      expect(
        tester.widget<AccountsV2CellInput>(_input(0)).controller.text,
        '50',
      );
      expect(find.text(t('v2p_unsaved')), findsNothing);
    });

    testWidgets('inputs are read-only without the capability', (tester) async {
      _surface(tester);
      await tester.pumpWidget(
        _wrap(AccountsV2ClaimsTab(workbench: _wb(), language: en)),
      );
      await tester.pumpAndSettle();
      // Read-only cells are text, not disabled boxes.
      expect(find.byType(AccountsV2CellInput), findsNothing);
      expect(find.text('50'), findsWidgets);
      expect(find.text(t('v2p_max')).hitTestable(), findsNothing);
    });

    testWidgets('a checked claim is read-only until it is back in draft', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: _wb(claimStatus: 'ready_for_accounts'),
            language: en,
            canRecordProgress: true,
            onSaveWorkbench: _noSave,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AccountsV2CellInput), findsNothing);
    });

    testWidgets('a site suggestion can be used in one tap', (tester) async {
      _surface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: _wb(suggestion: true),
            language: en,
            canRecordProgress: true,
            onSaveWorkbench: _noSave,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Site Sam'), findsOneWidget);
      await _tap(tester, _button(t('v2p_use')));
      // Suggested 70% to date, none before: 70 this claim.
      expect(
        tester.widget<AccountsV2CellInput>(_input(0)).controller.text,
        '70',
      );
    });
  });

  group('AccountsV2ClaimsTab unsaved progress', () {
    AccountsV2ClaimsTab tab(YorksAccountsUnsavedDrafts drafts) =>
        AccountsV2ClaimsTab(
          workbench: _wb(),
          language: en,
          canRecordProgress: true,
          onSaveWorkbench: _noSave,
          drafts: drafts,
        );

    testWidgets('typing comes back when the tab opens again', (tester) async {
      _surface(tester);
      final drafts = YorksAccountsUnsavedDrafts(unloadGuard: _NoGuard());
      addTearDown(drafts.dispose);
      await tester.pumpWidget(_wrap(tab(drafts)));
      await tester.pumpAndSettle();
      await tester.enterText(_input(0), '12.5');
      await tester.pumpAndSettle();
      expect(drafts.has(YorksAccountsDraftSection.claimsPrefix), isTrue);

      await tester.pumpWidget(_wrap(const SizedBox()));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_wrap(tab(drafts)));
      await tester.pumpAndSettle();
      expect(
        tester.widget<AccountsV2CellInput>(_input(0)).controller.text,
        '12.5',
      );
    });

    testWidgets('Discard can be undone', (tester) async {
      _surface(tester);
      final drafts = YorksAccountsUnsavedDrafts(unloadGuard: _NoGuard());
      addTearDown(drafts.dispose);
      await tester.pumpWidget(_wrap(tab(drafts)));
      await tester.pumpAndSettle();
      final before = tester
          .widget<AccountsV2CellInput>(_input(0))
          .controller
          .text;
      await tester.enterText(_input(0), '12.5');
      await tester.pumpAndSettle();
      await _tap(tester, _button(t('v2c_discard')));
      expect(
        tester.widget<AccountsV2CellInput>(_input(0)).controller.text,
        before,
      );
      await tester.tap(find.widgetWithText(SnackBarAction, t('v2_undo')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<AccountsV2CellInput>(_input(0)).controller.text,
        '12.5',
      );
    });
  });

  group('AccountsV2ClaimsTab claim commands', () {
    testWidgets('a draft claim marks checked with a reason', (tester) async {
      _surface(tester);
      String? captured;
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: _wb(),
            language: en,
            onMarkChecked:
                ({
                  required String claimId,
                  required int expectedVersion,
                  required String reason,
                }) async {
                  captured = reason;
                  return null;
                },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, _button(t('v2p_mark_checked')));
      await tester.enterText(find.byType(TextField).last, 'Checked on site');
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_confirm')));
      await tester.pumpAndSettle();
      expect(captured, 'Checked on site');
    });

    testWidgets('a refused issue stays open with the dates kept', (
      tester,
    ) async {
      _surface(tester);
      var attempts = 0;
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: _wb(claimStatus: 'ready_for_accounts'),
            language: en,
            onIssue:
                ({
                  required String claimId,
                  required int expectedClaimVersion,
                  required String invoiceDate,
                  required String submissionDate,
                  String? invoiceReference,
                }) async {
                  attempts++;
                  return attempts == 1
                      ? 'R39_ACCOUNTS_INVOICE_SETTINGS_REQUIRED'
                      : null;
                },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, _button(t('v2p_issue_invoice')).last);
      await tester.enterText(
        find.widgetWithText(TextField, t('v2_claim_reference_opt')),
        'REF-7',
      );
      await tester.tap(find.text(t('v2_confirm')));
      await tester.pumpAndSettle();
      expect(find.text(t('v2_err_settings_required')), findsOneWidget);
      expect(find.widgetWithText(TextField, 'REF-7'), findsOneWidget);
      expect(find.text(t('v2_claim_issued')), findsNothing);

      await tester.tap(find.text(t('v2_confirm')));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.text(t('v2_claim_issued')), findsOneWidget);
      expect(find.widgetWithText(TextField, 'REF-7'), findsNothing);
    });

    testWidgets('a checked claim issues its invoice', (tester) async {
      _surface(tester);
      String? issued;
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: _wb(claimStatus: 'ready_for_accounts'),
            language: en,
            onIssue:
                ({
                  required String claimId,
                  required int expectedClaimVersion,
                  required String invoiceDate,
                  required String submissionDate,
                  String? invoiceReference,
                }) async {
                  issued = '$claimId@$expectedClaimVersion';
                  return null;
                },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, _button(t('v2p_issue_invoice')).last);
      await tester.tap(find.text(t('v2_confirm')));
      await tester.pumpAndSettle();
      expect(issued, 'c1@2');
      expect(find.text(t('v2_claim_issued')), findsOneWidget);
    });

    testWidgets('a draft cannot be issued before it is checked', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: _wb(),
            language: en,
            onIssue:
                ({
                  required String claimId,
                  required int expectedClaimVersion,
                  required String invoiceDate,
                  required String submissionDate,
                  String? invoiceReference,
                }) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final b in tester.widgetList<AccountsV2Button>(
        _button(t('v2p_issue_invoice')),
      )) {
        expect(b.onPressed, isNull);
      }
    });

    testWidgets('back to draft needs a reason', (tester) async {
      _surface(tester);
      String? captured;
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: _wb(claimStatus: 'ready_for_accounts'),
            language: en,
            onReopen:
                ({
                  required String claimId,
                  required int expectedVersion,
                  required String reason,
                }) async {
                  captured = reason;
                  return null;
                },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, _button(t('v2p_back_to_draft')));
      final confirm = find.widgetWithText(FilledButton, t('v2_confirm'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.enterText(find.byType(TextField).last, 'Wrong quantity');
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(captured, 'Wrong quantity');
    });

    testWidgets('a draft can be deleted with a reason', (tester) async {
      _surface(tester);
      String? deleted;
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: _wb(),
            language: en,
            onCancelClaim:
                ({
                  required String claimId,
                  required int expectedVersion,
                  required String reason,
                }) async {
                  deleted = '$claimId:$reason';
                  return null;
                },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, _button(t('v2p_delete_draft')));
      await tester.enterText(find.byType(TextField).last, 'Started twice');
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_confirm')));
      await tester.pumpAndSettle();
      expect(deleted, 'c1:Started twice');
      expect(find.text(t('v2p_deleted')), findsOneWidget);
    });

    testWidgets('previews the invoice before issuing', (tester) async {
      _surface(tester);
      String? previewed;
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: _wb(claimStatus: 'ready_for_accounts'),
            language: en,
            onPreviewInvoice: (id) async {
              previewed = id;
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, _button(t('v2p_preview_invoice')));
      expect(previewed, 'c1');
    });

    testWidgets('an invoiced claim shows its invoice and opens it', (
      tester,
    ) async {
      _surface(tester);
      String? opened;
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: _wb(claimStatus: 'invoiced'),
            language: en,
            onOpenInvoice: (id, {bool revise = false}) =>
                opened = '$id${revise ? ':revise' : ''}',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining(t('v2p_invoiced_note_b')), findsOneWidget);
      await _tap(tester, _button(t('v2p_revise')));
      expect(opened, 'inv1:revise');
    });

    testWidgets('the Claim picker switches claims', (tester) async {
      _surface(tester);
      String? selected;
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: _wb(),
            language: en,
            claims: _claims,
            onSelectClaim: (id) => selected = id,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Oldest claim is #01.
      await _tap(tester, find.textContaining('${t('v2p_claim')} #02').first);
      await tester.tap(find.textContaining('${t('v2p_claim')} #01').last);
      await tester.pumpAndSettle();
      expect(selected, 'c0');
    });
  });

  group('AccountsV2ClaimsTab single-cell update', () {
    testWidgets('a suggester updates a lump-sum stage from its editor', (
      tester,
    ) async {
      _surface(tester);
      YorksAccountsWorkbenchCell? opened;
      await tester.pumpWidget(
        _wrap(
          AccountsV2ClaimsTab(
            workbench: _wb(commercial: false, confirm: false, prepare: false),
            language: en,
            onUpdateCell: (cell) => opened = cell,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, _button(t('v2_cell_update_progress')));
      expect(opened!.progressEntryId, 'pe-design');
    });
  });

  group('YorksAccountsWorkspaceV2Screen (Progress & claims tab)', () {
    testWidgets('opening on claims loads the workbench from the repository', (
      tester,
    ) async {
      _surface(tester);
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
          child: MaterialApp(
            home: Scaffold(
              body: const YorksAccountsWorkspaceV2Screen(
                projectId: 'p1',
                initialTab: YorksAccountsWorkspaceV2Tab.claims,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(t('v2p_wb_title')), findsOneWidget);
      expect(find.text('Design'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}

Future<String?> _noSave({
  String? claimReference,
  required String periodStart,
  required String periodEnd,
  required List<Map<String, Object?>> entries,
  required List<String> evidenceDocumentIds,
  String? reason,
}) async => null;

class _NoGuard implements YorksV1ProcurementUnloadGuard {
  @override
  void setActive(bool active) {}
  @override
  void dispose() {}
}

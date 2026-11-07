import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/accounts/domain/v2/claim_workbench_models.dart';
import 'package:material_ledger/features/accounts/domain/v2/commercial_setup_read_models.dart';
import 'package:material_ledger/features/accounts/domain/v2/material_sources_models.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_claims_tab.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_common.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_contract_tab.dart';
import 'package:material_ledger/features/accounts/presentation/v2/kit/accounts_v2_kit.dart';
import 'package:material_ledger/shared/models/app_language.dart';

const en = AppLanguage.english;
String t(String key) => accountsV2Text(en, key);

// ─── Fixtures ────────────────────────────────────────────────────────────────

const _b1 = 'scope-B1';
const _b2 = 'scope-B2';

Map<String, dynamic> _item(String scope, String key, String label, int order) =>
    {
      'project_scope_id': scope,
      'building_name': scope,
      'stage_key': 'material_supply',
      'item_key': key,
      'item_label': label,
      'display_order': order,
      'quantity': '6.0000',
      'unit_code': 'Nos',
      'weight_percent_of_contract': '12.5000',
      'value': '125000.00',
    };

/// Two buildings at 50%; Design by percent and Material Supply by three items.
YorksAccountsCommercialSetupRead _setup({bool installItems = false}) =>
    YorksAccountsCommercialSetupRead.fromJson({
      'schema_version': 1,
      'project_id': 'p1',
      'has_baseline': true,
      'can_configure': true,
      'capabilities': {
        'view_project_accounts': true,
        'view_project_commercial_values': true,
        'configure_project_commercials': true,
      },
      'profile_version': 3,
      'currency_code': 'AED',
      'contract_value': '1000000.00',
      'contract_incl_vat': '1050000.00',
      'vat_rate_percent': '5.0000',
      'buildings': [
        for (final s in [_b1, _b2])
          {
            'project_scope_id': s,
            'name': s == _b1 ? 'Building 1' : 'Building 2',
            'scope_kind': 'building',
            'allocation_percent': '50.0000',
            'value': '500000.00',
          },
      ],
      'stages': [
        {
          'stage_key': 'design',
          'stage_name': 'Design',
          'display_order': 1,
          'measurement_mode': 'percent',
          'allocation_percent': '50.0000',
          'value': '500000.00',
        },
        {
          'stage_key': 'material_supply',
          'stage_name': 'Material Supply',
          'display_order': 2,
          'measurement_mode': 'items',
          'allocation_percent': installItems ? '40.0000' : '50.0000',
          'value': '500000.00',
        },
        if (installItems)
          {
            'stage_key': 'installation',
            'stage_name': 'Installation',
            'display_order': 3,
            'measurement_mode': 'items',
            'allocation_percent': '10.0000',
            'value': '100000.00',
          },
      ],
      'items': [
        for (final s in [_b1, _b2]) ...[
          _item(s, 'ac', 'AC Units', 1),
          _item(s, 'duct', 'Ductwork', 2),
          _item(s, 'heater', 'Electrical Duct heater', 3),
          if (installItems)
            {..._item(s, 'ac', 'AC Units', 1), 'stage_key': 'installation'},
        ],
      ],
    });

Map<String, dynamic> _folder(String id, String scope, String name) => {
  'boq_group_id': id,
  'project_scope_id': scope,
  'name': name,
  'template_key': null,
  'row_count': 2,
  'unit': 'Nos',
  'quantity': '6',
};

/// Building 1 has AC Units and GI Ductwork, Building 2 only AC Units. AC
/// Units is linked in Building 1 alone; four units reached it.
Map<String, dynamic> _sourcesJson({
  bool canLink = true,
  bool folders = true,
  List<Map<String, dynamic>>? links,
  List<Map<String, dynamic>>? delivered,
}) => {
  'schema_version': 1,
  'project_id': 'p1',
  'can_link': canLink,
  'folders': folders
      ? [
          _folder('g1', _b1, 'AC Units'),
          _folder('g2', _b1, 'GI Ductwork'),
          _folder('g3', _b2, 'AC Units'),
        ]
      : const [],
  'links':
      links ??
      [
        {
          'project_scope_id': _b1,
          'stage_key': 'material_supply',
          'item_key': 'ac',
          'boq_group_id': 'g1',
        },
      ],
  'delivered':
      delivered ??
      [
        {
          'project_scope_id': _b1,
          'stage_key': 'material_supply',
          'item_key': 'ac',
          'basis': 'quantity',
          'delivered_qty': '4.0000',
          'deliveries': 2,
          'last_delivery_reference': 'DO-002',
          'last_delivery_date': '2026-10-05',
        },
      ],
};

YorksAccountsMaterialSources _sources({
  bool canLink = true,
  bool folders = true,
  List<Map<String, dynamic>>? links,
  List<Map<String, dynamic>>? delivered,
}) => YorksAccountsMaterialSources.fromJson(
  _sourcesJson(
    canLink: canLink,
    folders: folders,
    links: links,
    delivered: delivered,
  ),
);

void _surface(WidgetTester tester, {double width = 1400}) {
  tester.view.physicalSize = Size(width, 3000);
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

Widget _contract({
  YorksAccountsMaterialSources? sources,
  YorksSaveMaterialLinksAction? onSave,
  bool installItems = false,
}) => _wrap(
  AccountsV2ContractTab(
    setup: _setup(installItems: installItems),
    language: en,
    canEdit: true,
    onSave: (_) async => null,
    materialSources: sources,
    onSaveMaterialLinks: onSave,
  ),
);

/// One building, Material Supply by one item: AHU units, 4 Nos, 1 done before
/// the draft claim and none in it.
YorksAccountsWorkbench _workbench({String status = 'draft'}) =>
    YorksAccountsWorkbench.fromJson({
      'schema_version': 1,
      'project_id': 'p1',
      'baseline_revision_id': 'rev1',
      'baseline_revision_number': 1,
      'capabilities': {'can_view_values': false, 'can_confirm': true},
      'commands': {'create_claim_draft': true, 'cancel_claim': true},
      'cells': [
        {
          'progress_entry_id': 'pe-material',
          'building_scope_id': 'b01',
          'building_name': 'Block A',
          'stage_key': 'material_supply',
          'stage_label': 'Material Supply',
          'stage_position': 1,
          'measurement_mode': 'items',
          'confirmed_percent': '25.0000',
          'review_status': 'not_required',
          'record_version': 1,
          'over_claimed': false,
          'percent_before_claim': '25.0000',
          'percent_this_claim': '0',
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
            },
          ],
        },
      ],
      'claim': {
        'claim_id': 'c1',
        'claim_reference': 'CLM-01',
        'status': status,
        'record_version': 2,
        'claim_period_start': '2026-08-01',
        'claim_period_end': '2026-08-25',
        'prepared_by': 'Pat Engineer',
        if (status != 'draft') 'checked_by': 'Morgan Manager',
        'lines': const [],
      },
    });

YorksAccountsMaterialSources _delivered(
  String qty, {
  String basis = 'quantity',
}) => YorksAccountsMaterialSources.fromJson({
  'can_link': false,
  'folders': const [],
  'links': const [],
  'delivered': [
    {
      'project_scope_id': 'b01',
      'stage_key': 'material_supply',
      'item_key': 'ahu',
      'basis': basis,
      'delivered_qty': qty,
      'deliveries': 2,
      'last_delivery_reference': 'DO-002',
      'last_delivery_date': '2026-10-05',
    },
  ],
});

Widget _claims({
  YorksAccountsWorkbench? workbench,
  YorksAccountsMaterialSources? sources,
  bool canRecord = true,
  YorksSaveWorkbenchAction? onSave,
}) => _wrap(
  AccountsV2ClaimsTab(
    workbench: workbench ?? _workbench(),
    language: en,
    canRecordProgress: canRecord,
    materialSources: sources,
    onSaveWorkbench:
        onSave ??
        ({
          String? claimReference,
          required String periodStart,
          required String periodEnd,
          required List<Map<String, Object?>> entries,
          required List<String> evidenceDocumentIds,
          String? reason,
        }) async => null,
  ),
);

/// The workbench's item quantity input.
Finder get _qtyInput => find.byType(AccountsV2CellInput).first;

String _qtyText(WidgetTester tester) => tester
    .widget<TextField>(
      find.descendant(of: _qtyInput, matching: find.byType(TextField)),
    )
    .controller!
    .text;

void main() {
  group('material sources model', () {
    test('parses folders, links and deliveries', () {
      final s = _sources();
      expect(s.canLink, isTrue);
      expect(s.foldersFor(_b1).map((f) => f.name), ['AC Units', 'GI Ductwork']);
      expect(
        s.linkedFolders(_b1, 'material_supply', 'ac').single.boqGroupId,
        'g1',
      );
      expect(s.linkedFolders(_b2, 'material_supply', 'ac'), isEmpty);
      final d = s.deliveredFor(_b1, 'material_supply', 'ac')!;
      expect(d.deliveredQty.canonicalText, '4');
      expect(d.deliveries, 2);
      expect(d.isShare, isFalse);
      expect(s.deliveredFor(_b2, 'material_supply', 'ac'), isNull);
      expect(s.folders.first.quantity!.canonicalText, '6');
    });

    test('an empty read has nothing to link', () {
      final s = YorksAccountsMaterialSources.fromJson(const {});
      expect(s.canLink, isFalse);
      expect(s.hasFolders, isFalse);
      expect(YorksAccountsMaterialSources.empty.links, isEmpty);
    });

    test('rejects a delivered quantity that is not a decimal string', () {
      expect(
        () => _sources(
          delivered: [
            {
              'project_scope_id': _b1,
              'stage_key': 'material_supply',
              'item_key': 'ac',
              'delivered_qty': 4.0,
            },
          ],
        ),
        throwsFormatException,
      );
    });

    test('a link is sent with the keys the server reads', () {
      const link = YorksAccountsMaterialLink(
        projectScopeId: _b1,
        stageKey: 'material_supply',
        itemKey: 'ac',
        boqGroupId: 'g1',
      );
      expect(link.toJson(), {
        'project_scope_id': _b1,
        'stage_key': 'material_supply',
        'item_key': 'ac',
        'boq_group_id': 'g1',
      });
    });
  });

  group('Contract tab BOQ links', () {
    testWidgets('shows linked folders and what reached site', (tester) async {
      _surface(tester);
      await tester.pumpWidget(
        _contract(sources: _sources(), onSave: (_, _) async => null),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Material Supply — ${t('v2m_title_suffix')}'),
        findsOneWidget,
      );
      // Linked in one of the item's two buildings.
      expect(find.text('AC Units · 1/2'), findsOneWidget);
      expect(find.text(t('v2m_not_linked')), findsNWidgets(2));
      // 4 of 6 + 6 across the two buildings, from two deliveries.
      expect(find.text('4 ${t('v2o_of')} 12 Nos'), findsOneWidget);
      expect(find.text('2 ${t('v2m_deliveries')} · DO-002'), findsOneWidget);
      expect(_button(t('v2m_edit')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a building without the folder is no reason to stop', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
        _contract(
          sources: _sources(links: const [], delivered: const []),
          onSave: (_, _) async => null,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(t('v2m_not_linked')), findsNWidgets(3));
      expect(_button(t('v2m_link')), findsOneWidget);
    });

    testWidgets('without BOQ folders it says where they come from', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(_contract(sources: _sources(folders: false)));
      await tester.pumpAndSettle();
      expect(find.text(t('v2m_no_folders')), findsOneWidget);
      expect(_button(t('v2m_link')), findsNothing);
    });

    testWidgets('someone who cannot link sees no button', (tester) async {
      _surface(tester);
      await tester.pumpWidget(
        _contract(
          sources: _sources(canLink: false),
          onSave: (_, _) async => null,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('AC Units · 1/2'), findsOneWidget);
      expect(_button(t('v2m_edit')), findsNothing);
    });

    testWidgets('no card until the links are read', (tester) async {
      _surface(tester);
      await tester.pumpWidget(_contract());
      await tester.pumpAndSettle();
      expect(
        find.text('Material Supply — ${t('v2m_title_suffix')}'),
        findsNothing,
      );
    });

    testWidgets('links by folder name in every building, with a reason', (
      tester,
    ) async {
      _surface(tester);
      List<YorksAccountsMaterialLink>? sent;
      String? reason;
      await tester.pumpWidget(
        _contract(
          sources: _sources(),
          onSave: (links, why) async {
            sent = links;
            reason = why;
            return null;
          },
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, _button(t('v2m_edit')));
      expect(find.text(t('v2m_drawer_title')), findsOneWidget);

      // AC Units stands for the AC Units item, so Ductwork cannot take it.
      final taken = find.byKey(
        const ValueKey('v2m_choice_material_supply|duct_ac units'),
      );
      await tester.tap(taken);
      await tester.pumpAndSettle();
      Finder save() => find.byKey(const ValueKey('v2m_save'));
      expect(tester.widget<AccountsV2Button>(save()).onPressed, isNull);

      // Suggest by name: Ductwork → GI Ductwork, and nothing for the duct
      // heater, which only shares the word "duct" with it.
      await _tap(tester, find.byKey(const ValueKey('v2m_suggest')));
      expect(tester.widget<AccountsV2Button>(save()).onPressed, isNull);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('v2m_reason')),
          matching: find.byType(TextField),
        ),
        'Linked the BOQ',
      );
      await tester.pumpAndSettle();
      await _tap(tester, save());

      expect(reason, 'Linked the BOQ');
      String key(YorksAccountsMaterialLink l) =>
          '${l.projectScopeId}/${l.itemKey}/${l.boqGroupId}';
      expect(sent!.map(key).toSet(), {
        '$_b1/ac/g1',
        '$_b2/ac/g3',
        // Building 2 has no GI Ductwork folder.
        '$_b1/duct/g2',
      });
      expect(find.text(t('v2m_saved')), findsOneWidget);
      expect(find.text(t('v2m_drawer_title')), findsNothing);
    });

    testWidgets('only Material Supply is linked, other links are kept', (
      tester,
    ) async {
      _surface(tester);
      List<YorksAccountsMaterialLink>? sent;
      const kept = {
        'project_scope_id': _b1,
        'stage_key': 'installation',
        'item_key': 'ac',
        'boq_group_id': 'g1',
      };
      // A link to an archived folder (not offered) cannot be saved again.
      const stale = {
        'project_scope_id': _b1,
        'stage_key': 'installation',
        'item_key': 'ac',
        'boq_group_id': 'g-archived',
      };
      await tester.pumpWidget(
        _contract(
          installItems: true,
          sources: _sources(
            links: [
              ..._sourcesJson()['links'] as List<Map<String, dynamic>>,
              kept,
              stale,
            ],
          ),
          onSave: (links, _) async {
            sent = links;
            return null;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Installation — ${t('v2m_title_suffix')}'),
        findsNothing,
      );
      await _tap(tester, _button(t('v2m_edit')));
      expect(
        find.byKey(const ValueKey('v2m_item_installation|ac')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('v2m_item_material_supply|ac')),
        findsOneWidget,
      );
      await _tap(
        tester,
        find.byKey(
          const ValueKey('v2m_choice_material_supply|heater_gi ductwork'),
        ),
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('v2m_reason')),
          matching: find.byType(TextField),
        ),
        'Heater',
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('v2m_save')));
      String key(YorksAccountsMaterialLink l) =>
          '${l.stageKey}/${l.projectScopeId}/${l.itemKey}/${l.boqGroupId}';
      expect(sent!.map(key).toSet(), {
        'material_supply/$_b1/ac/g1',
        'material_supply/$_b2/ac/g3',
        'material_supply/$_b1/heater/g2',
        'installation/$_b1/ac/g1',
      });
    });

    testWidgets('a refused save stays open with the reason', (tester) async {
      _surface(tester);
      await tester.pumpWidget(
        _contract(
          sources: _sources(),
          onSave: (_, _) async => 'R39_ACCOUNTS_INVALID_MATERIAL_LINK',
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, _button(t('v2m_edit')));
      await _tap(
        tester,
        find.byKey(const ValueKey('v2m_choice_material_supply|ac_ac units')),
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('v2m_reason')),
          matching: find.byType(TextField),
        ),
        'Unlink',
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('v2m_save')));
      expect(find.text(t('v2_err_material_link')), findsOneWidget);
      expect(find.text(t('v2m_drawer_title')), findsOneWidget);
    });

    testWidgets('the editor fits a phone', (tester) async {
      _surface(tester, width: 360);
      await tester.pumpWidget(
        _contract(sources: _sources(), onSave: (_, _) async => null),
      );
      await tester.pumpAndSettle();
      await _tap(tester, _button(t('v2m_edit')));
      expect(find.text(t('v2m_drawer_title')), findsOneWidget);
      final chip = tester.getSize(
        find.byKey(const ValueKey('v2m_choice_material_supply|ac_ac units')),
      );
      expect(chip.height, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
    });
  });

  group('Progress & claims deliveries', () {
    testWidgets('shows what reached site under the item and uses it', (
      tester,
    ) async {
      _surface(tester);
      List<Map<String, Object?>>? sent;
      await tester.pumpWidget(
        _claims(
          sources: _delivered('3.0000'),
          onSave:
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
      );
      await tester.pumpAndSettle();
      // One site record waiting: three delivered, one claimed so far.
      expect(find.text('1'), findsWidgets);
      expect(
        find.textContaining('3 ${t('v2m_delivered')} · DO-002'),
        findsOneWidget,
      );
      expect(find.text('1 ${t('v2m_item_waiting')}'), findsOneWidget);
      await _tap(tester, find.text(t('v2p_use')));
      // 1 before + 2 this claim = the 3 delivered.
      expect(_qtyText(tester), '2');
      expect(find.textContaining('3 · 75%'), findsOneWidget);
      expect(find.text('1 ${t('v2m_item_waiting')}'), findsNothing);
      expect(find.text(t('v2p_use')), findsNothing);
      expect(sent, isNull);
    });

    testWidgets('Use site deliveries fills the stage at once', (tester) async {
      _surface(tester);
      await tester.pumpWidget(_claims(sources: _delivered('9.0000')));
      await tester.pumpAndSettle();
      await _tap(tester, _button(t('v2m_use_all')));
      // Never more than the item's 4: 3 more this claim.
      expect(_qtyText(tester), '3');
      expect(
        find.textContaining('4 ${t('v2m_delivered')} · DO-002'),
        findsOneWidget,
      );
    });

    testWidgets('a share of the BOQ rows is marked as approximate', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
        _claims(sources: _delivered('2.5000', basis: 'share')),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('≈ 2.50 ${t('v2m_delivered')} · DO-002'),
        findsOneWidget,
      );
      expect(find.byTooltip(t('v2m_share_hint')), findsOneWidget);
    });

    testWidgets('nothing beyond the claim leaves nothing to use', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(_claims(sources: _delivered('1.0000')));
      await tester.pumpAndSettle();
      // Nothing waiting, so the stage starts closed.
      await _tap(tester, find.text('Material Supply').first);
      expect(
        find.textContaining('1 ${t('v2m_delivered')} · DO-002'),
        findsOneWidget,
      );
      expect(find.text(t('v2p_use')), findsNothing);
      expect(_button(t('v2m_use_all')), findsNothing);
    });

    testWidgets('read-only claims show deliveries but offer no Use', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
        _claims(sources: _delivered('3.0000'), canRecord: false),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('3 ${t('v2m_delivered')} · DO-002'),
        findsOneWidget,
      );
      expect(find.text(t('v2p_use')), findsNothing);
    });

    testWidgets('an invoiced claim has no site records waiting', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
        _claims(
          workbench: _workbench(status: 'invoiced'),
          sources: _delivered('3.0000'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 ${t('v2m_item_waiting')}'), findsNothing);
      expect(find.text(t('v2p_use')), findsNothing);
    });

    testWidgets('fits a phone', (tester) async {
      _surface(tester, width: 360);
      await tester.pumpWidget(_claims(sources: _delivered('3.0000')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('3 ${t('v2m_delivered')} · DO-002'),
        findsOneWidget,
      );
      final use = find.ancestor(
        of: find.text(t('v2p_use')),
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(use.first).height, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
    });
  });
}

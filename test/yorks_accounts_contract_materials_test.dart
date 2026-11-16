// Contract materials — Accounts › Materials (PRODUCT_DECISIONS.md §61).
//
// The register's parse, the invoice-style numbering, the repository call and
// the tab at desktop and phone widths, with and without commercial values.
// Fixtures are fictional.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/accounts/application/accounts_providers.dart';
import 'package:material_ledger/features/accounts/application/v2/accounts_workspace_v2_controllers.dart';
import 'package:material_ledger/features/accounts/data/accounts_repository.dart'
    show YorksAccountsRpcClient;
import 'package:material_ledger/features/accounts/data/v2/accounts_workspace_repository.dart';
import 'package:material_ledger/features/accounts/domain/accounts_decimal.dart';
import 'package:material_ledger/features/accounts/domain/v2/material_register_models.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_common.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_materials_tab.dart';
import 'package:material_ledger/features/accounts/presentation/v2/yorks_accounts_workspace_v2_screen.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_permission_management.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_ledger/shared/models/app_language.dart';

import 'support/accounts_v2_golden_fonts.dart';
import 'support/yorks_v1_permission_test_support.dart';

const _en = AppLanguage.english;

Map<String, dynamic> _stage(
  String key,
  String qty,
  String unit,
  String confirmed, {
  String? amount,
  String? rate,
  String? done,
  String? weight,
  String? invoiced,
  Map<String, dynamic>? invoice,
}) => {
  'stage_key': key,
  'stage_item_id': 'si-$key-$qty-$confirmed',
  'quantity': qty,
  'unit_code': unit,
  'confirmed_qty': confirmed,
  'needs_review': false,
  'weight_percent': ?weight,
  'amount': ?amount,
  'rate': ?rate,
  'done_amount': ?done,
  'invoiced_qty': ?invoiced,
  'last_invoice': invoice,
};

const _invoice01 = {
  'invoice_id': 'inv-1',
  'invoice_reference': 'CM01',
  'status': 'certified',
};

List<Map<String, dynamic>> _linesA() => [
  {
    'item_key': '1',
    'item_label': 'AC Units (Package Unit)',
    'display_order': 1,
    'boq_row_id': 'row-1',
    'boq_group_id': 'grp-a',
    'site': {
      'basis': 'quantity',
      'delivered_qty': '6.0000',
      'deliveries': 2,
      'last_delivery_reference': 'DO-102',
      'last_delivery_date': '2026-10-03',
    },
    'stages': [
      _stage(
        'material_supply',
        '6.0000',
        'Nos',
        '6.0000',
        amount: '200000.00',
        rate: '33333.33',
        done: '200000.00',
        weight: '20.000000',
        invoiced: '6.0000',
        invoice: _invoice01,
      ),
      _stage(
        'installation',
        '6.0000',
        'Nos',
        '2.0000',
        amount: '100000.00',
        rate: '16666.67',
        done: '33333.33',
        weight: '10.000000',
        invoiced: '0',
      ),
    ],
  },
  {
    'item_key': '2',
    'item_label': 'Motorized Fire Dampers',
    'display_order': 2,
    'boq_row_id': 'row-2',
    'boq_group_id': 'grp-a',
    'site': null,
    'stages': [
      _stage(
        'material_supply',
        '55.0000',
        'Nos',
        '20.0000',
        amount: '50000.00',
        rate: '909.09',
        done: '18181.82',
        weight: '5.000000',
        invoiced: '20.0000',
        invoice: _invoice01,
      ),
      _stage(
        'installation',
        '55.0000',
        'Nos',
        '0',
        amount: '25000.00',
        rate: '454.55',
        done: '0.00',
        weight: '2.500000',
        invoiced: '0',
      ),
    ],
  },
  {
    'item_key': '10-1',
    'item_label': 'Ducting — Basement Floor',
    'display_order': 3,
    'boq_row_id': 'row-3',
    'boq_group_id': 'grp-a',
    // A lump-sum line whose rows came in another unit: a share of the line.
    'site': {
      'basis': 'share',
      'delivered_qty': '0.6200',
      'deliveries': 3,
      'last_delivery_reference': 'DO-108',
      'last_delivery_date': '2026-10-09',
    },
    'stages': [
      _stage(
        'material_supply',
        '1.0000',
        'Lot',
        '0.5000',
        amount: '30000.00',
        rate: '30000.00',
        done: '15000.00',
        weight: '3.000000',
        invoiced: '0',
      ),
      _stage(
        'installation',
        '1.0000',
        'Lot',
        '0',
        amount: '15000.00',
        rate: '15000.00',
        done: '0.00',
        weight: '1.500000',
        invoiced: '0',
      ),
    ],
  },
  {
    'item_key': '10-2',
    'item_label': 'Ducting — Ground Floor',
    'display_order': 4,
    'boq_row_id': null,
    'boq_group_id': null,
    'site': null,
    'stages': [
      _stage(
        'material_supply',
        '1.0000',
        'Lot',
        '0',
        amount: '20000.00',
        rate: '20000.00',
        done: '0.00',
        weight: '2.000000',
        invoiced: '0',
      ),
      _stage(
        'installation',
        '1.0000',
        'Lot',
        '0',
        amount: '10000.00',
        rate: '10000.00',
        done: '0.00',
        weight: '1.000000',
        invoiced: '0',
      ),
    ],
  },
  {
    'item_key': '11',
    'item_label': 'Ref. Pipes & Accessories',
    'display_order': 5,
    'boq_row_id': null,
    'boq_group_id': null,
    'site': null,
    'stages': [
      _stage(
        'material_supply',
        '1.0000',
        'Lot',
        '0',
        amount: '0.00',
        rate: '0.00',
        done: '0.00',
        weight: '0.000000',
        invoiced: '0',
      ),
      _stage(
        'installation',
        '1.0000',
        'Lot',
        '0',
        amount: '0.00',
        rate: '0.00',
        done: '0.00',
        weight: '0.000000',
        invoiced: '0',
      ),
    ],
  },
];

Map<String, dynamic> _registerJson({bool values = true}) {
  Map<String, dynamic> strip(Map<String, dynamic> m, List<String> keys) => {
    for (final e in m.entries)
      if (!keys.contains(e.key)) e.key: e.value,
  };
  const lineMoney = [
    'weight_percent',
    'amount',
    'rate',
    'done_amount',
    'invoiced_qty',
    'last_invoice',
  ];
  const cellMoney = [
    'stage_value',
    'done_amount',
    'invoiced_amount',
    'in_claim_amount',
    'not_invoiced_amount',
    'over_invoiced',
  ];
  List<Map<String, dynamic>> lines(List<Map<String, dynamic>> raw) => [
    for (final l in raw)
      {
        ...l,
        'stages': [
          for (final s in l['stages'] as List)
            values
                ? s as Map<String, dynamic>
                : strip(s as Map<String, dynamic>, lineMoney),
        ],
      },
  ];
  Map<String, dynamic> cell(Map<String, dynamic> c) =>
      values ? c : strip(c, cellMoney);
  final b2Lines = [
    for (final l in _linesA())
      {
        ...l,
        'boq_row_id': null,
        'boq_group_id': null,
        'site': null,
        'stages': [
          for (final s in l['stages'] as List)
            {
              ...(s as Map<String, dynamic>),
              'confirmed_qty': '0',
              'done_amount': '0.00',
              'invoiced_qty': '0',
              'last_invoice': null,
            },
        ],
      },
  ];
  return {
    'schema_version': 1,
    'project_id': 'p1',
    'baseline_revision_id': 'rev-1',
    'baseline_revision_number': 3,
    'can_view_values': values,
    if (values) 'currency_code': 'AED',
    if (values) 'contract_value': '1000000.00',
    'stages': [
      {
        'stage_key': 'material_supply',
        'stage_label': 'Material Supply',
        'display_order': 2,
      },
      {
        'stage_key': 'installation',
        'stage_label': 'Installation',
        'display_order': 3,
      },
    ],
    'buildings': [
      {
        'project_scope_id': 'b1',
        'building_name': 'Block A- Pump Station',
        'scope_code': 'a-b1',
        'stages': [
          cell({
            'stage_key': 'material_supply',
            'stage_label': 'Material Supply',
            'display_order': 2,
            'stage_value': '300000.00',
            'done_amount': '233181.82',
            'invoiced_amount': '200000.00',
            'in_claim_amount': '0.00',
            'not_invoiced_amount': '33181.82',
            'over_invoiced': false,
          }),
          cell({
            'stage_key': 'installation',
            'stage_label': 'Installation',
            'display_order': 3,
            'stage_value': '150000.00',
            'done_amount': '33333.33',
            'invoiced_amount': '0.00',
            'in_claim_amount': '0.00',
            'not_invoiced_amount': '33333.33',
            'over_invoiced': false,
          }),
        ],
        'lines': lines(_linesA()),
      },
      {
        'project_scope_id': 'b2',
        'building_name': 'Block B- Pump Station',
        'scope_code': 'b-b2',
        'stages': [
          cell({
            'stage_key': 'material_supply',
            'stage_label': 'Material Supply',
            'display_order': 2,
            'stage_value': '300000.00',
            'done_amount': '0.00',
            'invoiced_amount': '0.00',
            'in_claim_amount': '0.00',
            'not_invoiced_amount': '0.00',
            'over_invoiced': false,
          }),
          cell({
            'stage_key': 'installation',
            'stage_label': 'Installation',
            'display_order': 3,
            'stage_value': '150000.00',
            'done_amount': '0.00',
            'invoiced_amount': '0.00',
            'in_claim_amount': '0.00',
            'not_invoiced_amount': '0.00',
            'over_invoiced': false,
          }),
        ],
        'lines': lines(b2Lines),
      },
    ],
  };
}

final class _FakeClient implements YorksAccountsRpcClient {
  _FakeClient(this.response);

  final Map<String, dynamic> response;
  String? function;
  Map<String, Object?>? parameters;

  @override
  Future<Map<String, dynamic>> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async {
    function = functionName;
    this.parameters = parameters;
    return response;
  }
}

Future<void> _pump(
  WidgetTester tester,
  Size size,
  YorksAccountsMaterialRegister register, {
  AccountsV2OpenClaims? onOpenClaims,
  ValueChanged<String>? onOpenBoqSheet,
  String? initialBuildingScopeId,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: AccountsV2MaterialsTab(
            register: register,
            language: _en,
            initialBuildingScopeId: initialBuildingScopeId,
            onOpenClaims: onOpenClaims,
            onOpenBoqSheet: onOpenBoqSheet,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('register model', () {
    test('parses lines, cells and money with values', () {
      final r = YorksAccountsMaterialRegister.fromJson(_registerJson());
      expect(r.canViewValues, isTrue);
      expect(r.currencyCode, 'AED');
      expect(r.buildings, hasLength(2));
      final a = r.buildings.first;
      expect(a.shortName, 'Block A');
      final ac = a.lines.first;
      expect(ac.boqRowId, 'row-1');
      expect(ac.site!.deliveredQty, YorksAccountsDecimal.parse('6'));
      final supply = ac.stage('material_supply')!;
      expect(supply.amount, YorksAccountsDecimal.parse('200000.00'));
      expect(supply.progress, YorksAccountsLineProgress.done);
      expect(supply.billing, YorksAccountsLineBilling.invoiced);
      expect(supply.lastInvoice!.reference, 'CM01');
      expect(
        ac.stage('installation')!.progress,
        YorksAccountsLineProgress.part,
      );
      final dampers = a.lines[1].stage('material_supply')!;
      expect(dampers.progress, YorksAccountsLineProgress.part);
      final duct = a.lines[2].stage('material_supply')!;
      expect(duct.isLot, isTrue);
      expect(duct.billing, YorksAccountsLineBilling.ready);
      expect(
        a.cell('material_supply')!.notInvoicedAmount,
        YorksAccountsDecimal.parse('33181.82'),
      );
    });

    test('parses without values: no money, no billing', () {
      final r = YorksAccountsMaterialRegister.fromJson(
        _registerJson(values: false),
      );
      expect(r.canViewValues, isFalse);
      expect(r.currencyCode, isNull);
      final supply = r.buildings.first.lines.first.stage('material_supply')!;
      expect(supply.amount, isNull);
      expect(supply.rate, isNull);
      expect(supply.invoicedQty, isNull);
      expect(supply.billing, isNull);
      expect(supply.progress, YorksAccountsLineProgress.done);
      expect(r.buildings.first.cell('material_supply')!.stageValue, isNull);
    });

    test('numbers lines as the invoices do', () {
      YorksAccountsRegisterLine line(String key, String label, int order) =>
          YorksAccountsRegisterLine(
            itemKey: key,
            itemLabel: label,
            displayOrder: order,
            stages: const [],
          );
      final rows = yorksAccountsSheetRows('A', [
        line('1', 'AC Units (Package Unit)', 1),
        line('9', 'CU/FCU (Fire Pump Room)', 9),
        line('10-1', 'Ducting — Basement Floor', 10),
        line('10-2', 'Ducting — Ground Floor', 11),
        line('10-5', 'Ducting — Stairs 1–5', 14),
        line('11', 'Ref. Pipes & Accessories', 15),
      ]);
      expect(
        [for (final r in rows) '${r.code} ${r.label}'],
        [
          'A.1 AC Units (Package Unit)',
          'A.2 CU/FCU (Fire Pump Room)',
          'A.3 Ducting',
          'A.3.1 Basement Floor',
          'A.3.2 Ground Floor',
          'A.3.5 Stairs 1–5',
          'A.4 Ref. Pipes & Accessories',
        ],
      );
      expect(rows[2].isHeading, isTrue);
      expect(yorksAccountsBuildingLetter(3), 'D');
    });
  });

  test('repository reads the register', () async {
    final client = _FakeClient(_registerJson());
    final repository = YorksAccountsWorkspaceRepository(client);
    final register = await repository.getMaterialRegister('p1');
    expect(client.function, 'v1_get_accounts_material_register');
    expect(client.parameters, {'p_project_id': 'p1'});
    expect(register.buildings.first.lines, hasLength(5));
  });

  group('materials tab', () {
    testWidgets('desktop with values: prices, invoices and states', (
      tester,
    ) async {
      (String?, String)? claims;
      String? boqSheet;
      await _pump(
        tester,
        const Size(1440, 1400),
        YorksAccountsMaterialRegister.fromJson(_registerJson()),
        onOpenClaims: (building, stage) => claims = (building, stage),
        onOpenBoqSheet: (groupId) => boqSheet = groupId,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('A · Block A — Material Supply'), findsOneWidget);
      expect(find.text('RATE'), findsOneWidget);
      expect(find.text('33,333.33'), findsOneWidget);
      expect(find.text('6 · CM01'), findsOneWidget);
      expect(find.text('A.3'), findsOneWidget);
      expect(find.text('Ducting'), findsOneWidget);
      expect(find.text('Basement Floor'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('Ready to invoice'), findsOneWidget);
      expect(find.text('20 of 55'), findsOneWidget);
      expect(find.text('Part delivered'), findsNWidgets(2));
      expect(find.text('AED 33,181.82'), findsOneWidget);
      // A lump-sum line's On site reads as a share, like its delivery.
      expect(find.text('62%'), findsOneWidget);
      expect(find.text('0.62'), findsNothing);
      // Each building's sheet opens Progress & claims on that building and
      // stage, and its BOQ sheet.
      await tester.tap(find.byKey(const ValueKey('v2mat_open_claims_b1')));
      expect(claims, ('b1', 'material_supply'));
      await tester.tap(find.byKey(const ValueKey('v2mat_open_boq_b1')));
      expect(boqSheet, 'grp-a');

      await tester.tap(find.byKey(const ValueKey('v2mat_stage_installation')));
      await tester.pumpAndSettle();
      expect(find.text('A · Block A — Installation'), findsOneWidget);
      expect(find.text('Installing'), findsOneWidget);
      expect(find.text('2 of 6'), findsOneWidget);
      expect(find.text('ON SITE'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('v2mat_open_claims_b1')));
      expect(claims, ('b1', 'installation'));

      await tester.tap(find.byKey(const ValueKey('v2mat_building_all')));
      await tester.pumpAndSettle();
      expect(find.text('B · Block B — Installation'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('v2mat_open_claims_b2')),
        findsOneWidget,
      );
      // Block B has no Contract Materials sheet yet: nothing to open.
      expect(find.byKey(const ValueKey('v2mat_open_boq_b2')), findsNothing);
      expect(find.byKey(const ValueKey('v2mat_open_boq_b1')), findsOneWidget);
    });

    testWidgets('opens on the building a BOQ sheet asked for', (tester) async {
      await _pump(
        tester,
        const Size(1440, 1400),
        YorksAccountsMaterialRegister.fromJson(_registerJson()),
        initialBuildingScopeId: 'b2',
      );
      expect(find.text('B · Block B — Material Supply'), findsOneWidget);
      expect(find.text('A · Block A — Material Supply'), findsNothing);
      // Nothing delivered there yet, which the KPI says plainly.
      expect(find.text('Nothing delivered yet'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('v2mat_stage_installation')));
      await tester.pumpAndSettle();
      expect(find.text('Nothing installed yet'), findsOneWidget);

      // An unknown building falls back to the first.
      await tester.pumpWidget(const SizedBox());
      await _pump(
        tester,
        const Size(1440, 1400),
        YorksAccountsMaterialRegister.fromJson(_registerJson()),
        initialBuildingScopeId: 'gone',
      );
      expect(find.text('A · Block A — Material Supply'), findsOneWidget);
    });

    testWidgets('no links without a way to follow them', (tester) async {
      await _pump(
        tester,
        const Size(1440, 1400),
        YorksAccountsMaterialRegister.fromJson(_registerJson()),
      );
      expect(find.byKey(const ValueKey('v2mat_open_claims_b1')), findsNothing);
      expect(find.byKey(const ValueKey('v2mat_open_boq_b1')), findsNothing);
    });

    testWidgets('Site Engineer: quantities and states, never a price', (
      tester,
    ) async {
      await _pump(
        tester,
        const Size(1440, 1200),
        YorksAccountsMaterialRegister.fromJson(_registerJson(values: false)),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('RATE'), findsNothing);
      expect(find.text('AMOUNT'), findsNothing);
      expect(find.text('INVOICED'), findsNothing);
      expect(find.textContaining('AED'), findsNothing);
      expect(find.textContaining('200,000'), findsNothing);
      expect(find.text('20 of 55'), findsOneWidget);
      expect(find.text('ON SITE'), findsOneWidget);
      expect(
        find.textContaining(accountsV2Text(_en, 'v2mat_no_prices')),
        findsOneWidget,
      );
    });

    testWidgets('phone at 360px: one card per line, tall enough to tap', (
      tester,
    ) async {
      await _pump(
        tester,
        const Size(360, 1600),
        YorksAccountsMaterialRegister.fromJson(_registerJson()),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('v2mat_card_2')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('v2mat_card_2'))).height,
        greaterThanOrEqualTo(44),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('v2mat_building_0'))).height,
        greaterThanOrEqualTo(44),
      );
      expect(find.text('A.2  Motorized Fire Dampers'), findsOneWidget);
      expect(find.textContaining('Invoiced 20 · CM01'), findsOneWidget);
      expect(find.text('On site 62%'), findsOneWidget);
      // The building choices stay on one line and scroll sideways.
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('v2mat_building_all'))).dy,
        tester.getTopLeft(find.byKey(const ValueKey('v2mat_building_0'))).dy,
      );
    });

    testWidgets('empty contract', (tester) async {
      await _pump(
        tester,
        const Size(1440, 800),
        YorksAccountsMaterialRegister.fromJson(const {
          'project_id': 'p1',
          'can_view_values': true,
          'stages': [],
          'buildings': [],
        }),
      );
      expect(
        find.text(accountsV2Text(_en, 'v2mat_empty_title')),
        findsOneWidget,
      );
    });
  });

  test('the materials path opens the Materials tab', () {
    expect(
      yorksAccountsV2TabForPath('/yorks/projects/p1/accounts/materials'),
      YorksAccountsWorkspaceV2Tab.materials,
    );
    expect(
      yorksAccountsV2TabForPath('/yorks/projects/p1/accounts/contract'),
      YorksAccountsWorkspaceV2Tab.contract,
    );
  });

  group('workspace', () {
    Future<void> pumpWorkspace(
      WidgetTester tester,
      bool flagOn, {
      YorksV1Role? role,
      Set<String>? capabilities,
    }) async {
      tester.view.physicalSize = const Size(1440, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          yorksV1CurrentRoleProvider.overrideWithValue(role),
          if (capabilities != null)
            yorksV1CurrentPermissionSnapshotProvider.overrideWith(
              (ref) => YorksV1TestPermissionController(
                yorksV1TrustedFeaturePermissionState(
                  role: role ?? YorksV1Role.admin,
                  capabilities: capabilities,
                ),
              ),
            ),
          yorksAccountsPermissionEpochProvider.overrideWithValue((
            revision: 1,
            trusted: true,
            stale: false,
            revisionSignalHealthy: true,
          )),
          yorksAccountsWorkspaceRepositoryProvider.overrideWithValue(
            YorksAccountsWorkspaceRepository(_FakeClient(_registerJson())),
          ),
          yorksV1FeatureFlagsProvider.overrideWithValue(
            YorksV1FeatureFlags(
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
              accountsWorkspaceV2: true,
              contractMaterials: flagOn,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: YorksAccountsWorkspaceV2Screen(
                projectId: 'p1',
                initialTab: YorksAccountsWorkspaceV2Tab.materials,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('with the flag on, the tab opens on the register', (
      tester,
    ) async {
      await pumpWorkspace(tester, true);
      expect(
        find.text(accountsV2Text(_en, 'v2_tab_materials')),
        findsOneWidget,
      );
      expect(find.text('A · Block A — Material Supply'), findsOneWidget);
    });

    testWidgets('Open BOQ sheet: only for someone who may read the BOQ', (
      tester,
    ) async {
      const boqLink = ValueKey('v2mat_open_boq_b1');
      await pumpWorkspace(
        tester,
        true,
        role: YorksV1Role.projectEngineer,
        capabilities: {YorksV1CapabilityKeys.boqView},
      );
      expect(find.byKey(boqLink), findsOneWidget);
      expect(
        find.byKey(const ValueKey('v2mat_open_claims_b1')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox());
      await pumpWorkspace(
        tester,
        true,
        role: YorksV1Role.siteEngineer,
        capabilities: const {},
      );
      expect(find.byKey(boqLink), findsNothing);

      // An Accountant never reads the BOQ, whatever a snapshot says.
      await tester.pumpWidget(const SizedBox());
      await pumpWorkspace(
        tester,
        true,
        role: YorksV1Role.accountant,
        capabilities: {YorksV1CapabilityKeys.boqView},
      );
      expect(find.byKey(boqLink), findsNothing);
    });

    testWidgets('a deep link opens Materials on its building', (tester) async {
      tester.view.physicalSize = const Size(1440, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
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
          yorksAccountsWorkspaceRepositoryProvider.overrideWithValue(
            YorksAccountsWorkspaceRepository(_FakeClient(_registerJson())),
          ),
          yorksV1FeatureFlagsProvider.overrideWithValue(
            YorksV1FeatureFlags(
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
              accountsWorkspaceV2: true,
              contractMaterials: true,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: YorksAccountsWorkspaceV2Screen(
                projectId: 'p1',
                initialTab: YorksAccountsWorkspaceV2Tab.materials,
                initialMaterialsBuildingId: 'b2',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('B · Block B — Material Supply'), findsOneWidget);
    });

    testWidgets('with the flag off, there is no Materials tab', (tester) async {
      await pumpWorkspace(tester, false);
      expect(find.text(accountsV2Text(_en, 'v2_tab_materials')), findsNothing);
      expect(find.text('A · Block A — Material Supply'), findsNothing);
    });
  });

  group('goldens', () {
    setUpAll(loadAccountsV2GoldenFonts);
    final cases = <String, (Size, bool)>{
      'materials_desktop': (const Size(1440, 1200), true),
      'materials_mobile': (const Size(360, 1800), true),
      'materials_site_engineer_desktop': (const Size(1440, 1000), false),
    };
    for (final c in cases.entries) {
      testWidgets('accounts v2 ${c.key}', (tester) async {
        await _pump(
          tester,
          c.value.$1,
          YorksAccountsMaterialRegister.fromJson(
            _registerJson(values: c.value.$2),
          ),
          onOpenClaims: (_, _) {},
          onOpenBoqSheet: (_) {},
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/accounts_v2/${c.key}.png'),
        );
      });
    }
  });
}

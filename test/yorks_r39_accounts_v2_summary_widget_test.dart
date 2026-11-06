import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/accounts/application/accounts_providers.dart';
import 'package:material_ledger/features/accounts/application/v2/accounts_workspace_v2_controllers.dart';
import 'package:material_ledger/features/accounts/data/accounts_repository.dart'
    show YorksAccountsRpcClient;
import 'package:material_ledger/features/accounts/data/v2/accounts_workspace_repository.dart';
import 'package:material_ledger/features/accounts/domain/v2/accounts_workspace_models.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_common.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_summary_tab.dart';
import 'package:material_ledger/features/accounts/presentation/v2/yorks_accounts_workspace_v2_screen.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _workspaceJson({
  bool hasBaseline = true,
  bool commercial = true,
  bool supplier = true,
}) {
  return <String, dynamic>{
    'schema_version': 1,
    'project_id': 'p1',
    'project_reference': 'YRA-322',
    'project_name': 'Tower A',
    'has_baseline': hasBaseline,
    'capabilities': {
      'view_project_accounts': true,
      'view_project_commercial_values': commercial,
      'view_supplier_costs': supplier,
    },
    'steps': [
      {'key': 'setup', 'state': 'done'},
      {'key': 'progress', 'state': 'current'},
      {'key': 'invoice', 'state': ''},
      {'key': 'paid', 'state': ''},
    ],
    'attention': [
      {
        'severity': 'pri',
        'kind': 'no_claim',
        'action_key': 'start_claim',
        'target_type': 'project',
        'target_id': 'p1',
      },
    ],
    if (commercial) ...{
      'money_flow': {
        'paid': '1000000.00',
        'invoiced_waiting': '500000.00',
        'done_not_invoiced': '250000.00',
        'remaining': '15442000.00',
      },
      'kpis': {
        'contract_value': '17192000.00',
        'contract_incl_vat': '18051600.00',
        'invoiced': '1500000.00',
        'received': '1000000.00',
        'certified': '1400000.00',
        'outstanding': '500000.00',
        'cheques_in_hand': '200000.00',
        'done_not_invoiced': '250000.00',
      },
      'heatmap': [
        {
          'building_scope_id': 'b01',
          'building_name': 'Block A',
          'stage_key': 'material_supply',
          'stage_label': 'Material Supply',
          'stage_value': '2149000.00',
          'invoiced_amount': '1074500.00',
          'invoiced_percent': '50.00',
        },
        {
          'building_scope_id': 'b02',
          'building_name': 'Block B',
          'stage_key': 'material_supply',
          'stage_label': 'Material Supply',
          'stage_value': '2149000.00',
          'invoiced_amount': '0.00',
          'invoiced_percent': '0.00',
        },
      ],
    },
    if (supplier) ...{
      'supplier': {
        'billed': '900000.00',
        'paid': '600000.00',
        'unpaid': '300000.00',
        'overdue_count': 2,
      },
      'cash': {
        'received': '1000000.00',
        'paid_to_suppliers': '600000.00',
        'net': '400000.00',
      },
    },
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

Widget _wrap(Widget child, {Size size = const Size(1200, 2200)}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: size.width, height: size.height, child: child),
        ),
      ),
    ),
  );
}

Future<ProviderContainer> _pumpScreen(
  WidgetTester tester, {
  bool commercial = true,
  Size size = const Size(1200, 2200),
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final repo = YorksAccountsWorkspaceRepository(
    _FakeRpc(_workspaceJson(commercial: commercial, supplier: commercial)),
  );
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
        const YorksAccountsWorkspaceV2Screen(projectId: 'p1'),
        size: size,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  const en = AppLanguage.english;
  String t(String key) => accountsV2Text(en, key);

  group('AccountsV2SummaryTab (direct)', () {
    testWidgets('renders steps, KPIs, money flow, attention and heatmap', (
      tester,
    ) async {
      // Tall enough that the lazy list builds every card.
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ws = YorksAccountsWorkspace.fromJson(_workspaceJson());
      await tester.pumpWidget(
        _wrap(
          AccountsV2SummaryTab(
            workspace: ws,
            language: en,
            format: const AccountsV2Format(),
            onOpenTab: (_) {},
            onAttentionAction: (_) {},
            onOpenCell: (_, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(t('v2_kpi_contract')), findsOneWidget);
      expect(find.text('AED 17,192,000.00'), findsOneWidget);
      expect(find.text(t('v2_step_setup')), findsOneWidget);
      expect(find.text(t('v2_money_flow_title')), findsOneWidget);
      // The bar's segments really have size; they once collapsed to nothing.
      final segments = find.descendant(
        of: find.byKey(const ValueKey('accounts-v2-money-flow-bar')),
        matching: find.byType(ColoredBox),
      );
      expect(segments, findsWidgets);
      expect(tester.getSize(segments.first).height, 16);
      // Attention row for the open-claim prompt + its action.
      expect(find.text(t('v2_att_no_claim')), findsOneWidget);
      expect(find.text(t('v2_action_start_claim')), findsOneWidget);
      // Heatmap building header + stage row.
      expect(find.text('Block A'), findsOneWidget);
      expect(find.text('Material Supply'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hides commercial blocks without the capability', (
      tester,
    ) async {
      final ws = YorksAccountsWorkspace.fromJson(
        _workspaceJson(commercial: false, supplier: false),
      );
      await tester.pumpWidget(
        _wrap(
          AccountsV2SummaryTab(
            workspace: ws,
            language: en,
            format: const AccountsV2Format(),
            onOpenTab: (_) {},
            onAttentionAction: (_) {},
            onOpenCell: (_, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(t('v2_commercial_hidden')), findsOneWidget);
      // No commercial KPI values are shown.
      expect(find.text(t('v2_kpi_contract')), findsNothing);
      expect(find.text(t('v2_money_flow_title')), findsNothing);
      // The step strip and attention list still render.
      expect(find.text(t('v2_step_setup')), findsOneWidget);
      expect(find.text(t('v2_attention_title')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('YorksAccountsWorkspaceV2Screen (shell)', () {
    testWidgets('shows six tabs and loads the Summary from the repository', (
      tester,
    ) async {
      await _pumpScreen(tester);

      for (final tab in [
        'v2_tab_summary',
        'v2_tab_contract',
        'v2_tab_claims',
        'v2_tab_invoices',
        'v2_tab_supplier_bills',
        'v2_tab_history',
      ]) {
        expect(find.text(t(tab)), findsWidgets);
      }
      // Summary data loaded.
      expect(find.text('AED 17,192,000.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching tabs leaves the Summary surface', (tester) async {
      await _pumpScreen(tester);

      final contractTab = find.text(t('v2_tab_contract'));
      await tester.ensureVisible(contractTab);
      await tester.pumpAndSettle();
      await tester.tap(contractTab);
      await tester.pumpAndSettle();

      // Summary KPI is gone once we leave the Summary tab.
      expect(find.text('AED 17,192,000.00'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

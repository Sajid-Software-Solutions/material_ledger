import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/accounts/application/accounts_providers.dart';
import 'package:material_ledger/features/accounts/application/v2/accounts_workspace_v2_controllers.dart';
import 'package:material_ledger/features/accounts/data/accounts_repository.dart'
    show YorksAccountsRpcClient;
import 'package:material_ledger/features/accounts/data/v2/accounts_workspace_repository.dart';
import 'package:material_ledger/features/accounts/domain/v2/commercial_setup_read_models.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_common.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_contract_tab.dart';
import 'package:material_ledger/features/accounts/presentation/v2/yorks_accounts_workspace_v2_screen.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _setupJson({bool commercial = true}) {
  final base = <String, dynamic>{
    'schema_version': 1,
    'project_id': 'p1',
    'project_reference': 'YRA-322',
    'project_name': 'Tower A',
    'has_baseline': true,
    'can_configure': commercial,
    'capabilities': {
      'view_project_accounts': true,
      'view_project_commercial_values': commercial,
      'configure_project_commercials': commercial,
    },
  };
  if (!commercial) return base;
  return <String, dynamic>{
    ...base,
    'profile_version': 1,
    'revision_number': 1,
    'currency_code': 'AED',
    'contract_value': '1000000.00',
    'contract_incl_vat': '1050000.00',
    'vat_rate_percent': '5.0000',
    'payment_terms_days': 45,
    'reminder_lead_days': 10,
    'invoice_settings': {
      'invoice_prefix': 'YRA322',
      'next_sequence': 3,
      'scope_line': 'MEP works',
      'attention_name': 'Mr Client',
      'bill_to_party_id': null,
      'record_version': 1,
    },
    'buildings': [
      {
        'project_scope_id': 'b01',
        'name': 'Building 01',
        'scope_kind': 'building',
        'allocation_percent': '50.0000',
        'value': '500000.00',
      },
      {
        'project_scope_id': 'b02',
        'name': 'Building 02',
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
        'allocation_percent': '10.0000',
        'value': '100000.00',
      },
      {
        'stage_key': 'material_supply',
        'stage_name': 'Material Supply',
        'display_order': 2,
        'measurement_mode': 'items',
        'allocation_percent': '50.0000',
        'value': '500000.00',
      },
    ],
    'items': [
      {
        'project_scope_id': 'b01',
        'building_name': 'Building 01',
        'stage_key': 'material_supply',
        'item_key': 'ahu',
        'item_label': 'AHU units',
        'display_order': 1,
        'quantity': '4.0000',
        'unit_code': 'Nos',
        'weight_percent_of_contract': '25.000000',
        'value': '250000.00',
      },
    ],
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

/// Forces a wide surface so the Contract tab uses its two-column layout and the
/// whole page lays out within the viewport (the default 800x600 test surface
/// would stack it and lazily drop the aside).
void _wideSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  const en = AppLanguage.english;
  String t(String key) => accountsV2Text(en, key);

  group('AccountsV2ContractTab (direct)', () {
    testWidgets('renders the contract header, split, items and setup check', (
      tester,
    ) async {
      _wideSurface(tester);
      final setup = YorksAccountsCommercialSetupRead.fromJson(_setupJson());
      await tester.pumpWidget(
        _wrap(AccountsV2ContractTab(setup: setup, language: en)),
      );
      await tester.pumpAndSettle();

      expect(find.text('AED 1,000,000.00'), findsWidgets);
      expect(find.text(t('v2_buildings_title')), findsWidgets);
      expect(find.text('Building 01'), findsWidgets);
      expect(find.text('AED 500,000.00'), findsWidgets);
      expect(find.text('Material Supply'), findsOneWidget);
      expect(find.text(t('v2_mode_items')), findsOneWidget);
      expect(find.text('AHU units'), findsOneWidget);
      expect(find.text('AED 250,000.00'), findsOneWidget);
      expect(find.text(t('v2_setup_check_title')), findsOneWidget);
      expect(find.text(t('v2_how_amounts_title')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hides the commercial setup without the capability', (
      tester,
    ) async {
      _wideSurface(tester);
      final setup = YorksAccountsCommercialSetupRead.fromJson(
        _setupJson(commercial: false),
      );
      await tester.pumpWidget(
        _wrap(AccountsV2ContractTab(setup: setup, language: en)),
      );
      await tester.pumpAndSettle();

      expect(find.text(t('v2_commercial_hidden')), findsOneWidget);
      expect(find.text('AED 1,000,000.00'), findsNothing);
      expect(find.text(t('v2_setup_check_title')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('YorksAccountsWorkspaceV2Screen (Contract tab)', () {
    testWidgets('opening on Contract loads the setup from the repository', (
      tester,
    ) async {
      _wideSurface(tester);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final repo = YorksAccountsWorkspaceRepository(_FakeRpc(_setupJson()));
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
              initialTab: YorksAccountsWorkspaceV2Tab.contract,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AED 1,000,000.00'), findsWidgets);
      expect(find.text(t('v2_setup_check_title')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

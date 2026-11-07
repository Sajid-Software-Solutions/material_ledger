import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/accounts/domain/accounts_decimal.dart';
import 'package:material_ledger/features/accounts/domain/v2/accounts_master_file_parser.dart';
import 'package:material_ledger/features/accounts/domain/v2/commercial_setup_models.dart';
import 'package:material_ledger/features/accounts/domain/v2/commercial_setup_read_models.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_common.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_contract_tab.dart';
import 'package:material_ledger/shared/models/app_language.dart';

const en = AppLanguage.english;
String t(String key) => accountsV2Text(en, key);

Map<String, dynamic> _base({
  bool values = true,
  bool configure = true,
  bool baseline = false,
}) => {
  'schema_version': 1,
  'project_id': 'p1',
  'has_baseline': baseline,
  'can_configure': configure,
  'capabilities': {
    'view_project_accounts': true,
    'view_project_commercial_values': values,
    'configure_project_commercials': configure,
  },
  'buildings': const [],
  'stages': const [],
  'items': const [],
};

Map<String, dynamic> _withContract({
  List<Map<String, dynamic>> items = const [],
  String materialMode = 'percent',
}) => {
  ..._base(baseline: true),
  'profile_version': 3,
  'currency_code': 'AED',
  'contract_value': '1000000.00',
  'contract_incl_vat': '1050000.00',
  'vat_rate_percent': '5.0000',
  'payment_terms_days': 45,
  'reminder_lead_days': 7,
  'buildings': [
    for (final code in ['DF3W', 'DF4W'])
      {
        'project_scope_id': 'scope-$code',
        'name': 'Substation ($code)',
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
      'measurement_mode': materialMode,
      'allocation_percent': '50.0000',
      'value': '500000.00',
    },
  ],
  'items': items,
};

Map<String, dynamic> _item(
  String scope, {
  String weight = '25.0000',
  String label = 'AC Units',
}) => {
  'project_scope_id': scope,
  'building_name': scope,
  'stage_key': 'material_supply',
  'item_key': '1',
  'item_label': label,
  'display_order': 1,
  'quantity': '6.0000',
  'unit_code': 'Nos',
  'weight_percent_of_contract': weight,
  'value': '250000.00',
};

const _options = <YorksContractBuildingOption>[
  (scopeId: 'scope-DF3W', name: 'Substation (DF3W)', code: 'DF3W'),
  (scopeId: 'scope-DF4W', name: 'Substation (DF4W)', code: 'DF4W'),
];

final _stageOptions = <YorksContractStageOption>[
  (key: 'design', label: 'Design', percent: YorksAccountsDecimal.parse('10')),
  (key: 'install', label: 'Install', percent: YorksAccountsDecimal.parse('90')),
];

void _surface(WidgetTester tester, {double width = 1200}) {
  tester.view.physicalSize = Size(width, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// A small workbook in the real shape, through the real parser.
YorksAccountsMasterImportFile _workbook({
  String? current = '1000000',
  List<String> codes = const ['DF3W', 'DF4W'],
}) {
  List<Object?> row(Map<int, String> cells) {
    final r = List<Object?>.filled(8, '');
    cells.forEach((c, v) => r[c] = v);
    return r;
  }

  final draft = const YorksAccountsMasterFileParser().parse(
    expectedContractValue: current == null
        ? null
        : YorksAccountsDecimal.parse(current),
    sheets: {
      'Summery (Option)': [
        for (final code in codes) ...[
          row({2: 'Substation ($code)', 3: 'Contract Value', 5: '1200000'}),
          row({3: '1', 4: '0.5'}),
        ],
        row({3: 'CONTRACT VALUE', 5: '1200000'}),
        row({2: 'Cooling Load Design', 3: '0.5'}),
        row({2: 'Material Supply', 3: '0.5'}),
        row({2: 'TOTAL', 3: '1'}),
      ],
      'Material': [
        for (final code in codes) ...[
          row({1: 'DELIVERD MATERIAL SUMMARY  ($code)'}),
          row({1: 'Item', 4: 'Total Qty.', 5: 'WEIGHT'}),
          row({2: 'Material Supply', 5: '0.25'}),
          row({1: 'A.1', 3: 'AC Units', 4: '6', 5: '2.5000000000000001E-1'}),
        ],
      ],
    },
  );
  return (draft: draft, fileName: 'master.xlsx', sha256: 'abc123');
}

void main() {
  group('first contract', () {
    testWidgets('a new project is a setup screen, not a locked one', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2ContractTab(
            setup: YorksAccountsCommercialSetupRead.fromJson(_base()),
            language: en,
            canEdit: true,
            onSave: (_) async => null,
            buildingOptions: _options,
            stageOptions: _stageOptions,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(t('v2_first_title')), findsOneWidget);
      expect(find.text(t('v2_commercial_hidden')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('saves a first contract with even splits and the template', (
      tester,
    ) async {
      _surface(tester);
      YorksAccountsCommercialSetup? saved;
      await tester.pumpWidget(
        _wrap(
          AccountsV2ContractTab(
            setup: YorksAccountsCommercialSetupRead.fromJson(_base()),
            language: en,
            canEdit: true,
            onSave: (m) async {
              saved = m;
              return null;
            },
            buildingOptions: _options,
            stageOptions: _stageOptions,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_first_start')));
      await tester.pumpAndSettle();
      // Contract value is required, so Save starts disabled.
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, t('v2_save')),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField).first, '2000000');
      await tester.pumpAndSettle();
      final save = find.text(t('v2_save'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!.contractValue.canonicalText, '2000000');
      expect(saved!.buildings.map((b) => b.allocationPercent.canonicalText), [
        '50',
        '50',
      ]);
      expect(saved!.stages.map((s) => s.stageKey), ['design', 'install']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('someone without configure access gets a clear note', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2ContractTab(
            setup: YorksAccountsCommercialSetupRead.fromJson(
              _base(configure: false),
            ),
            language: en,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(t('v2_first_no_access')), findsOneWidget);
      expect(find.text(t('v2_first_start')), findsNothing);
    });

    testWidgets('no commercial access stays hidden', (tester) async {
      _surface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2ContractTab(
            setup: YorksAccountsCommercialSetupRead.fromJson(
              _base(values: false),
            ),
            language: en,
            canEdit: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(t('v2_commercial_hidden')), findsOneWidget);
      expect(find.text(t('v2_first_title')), findsNothing);
    });
  });

  group('item stages', () {
    Map<String, dynamic> itemsSetup({String df4wWeight = '25.0000'}) =>
        _withContract(
          materialMode: 'items',
          items: [
            _item('scope-DF3W'),
            _item('scope-DF4W', weight: df4wWeight),
          ],
        );

    testWidgets('edits and saves an item list instead of blocking', (
      tester,
    ) async {
      _surface(tester);
      YorksAccountsCommercialSetup? saved;
      await tester.pumpWidget(
        _wrap(
          AccountsV2ContractTab(
            setup: YorksAccountsCommercialSetupRead.fromJson(itemsSetup()),
            language: en,
            canEdit: true,
            onSave: (m) async {
              saved = m;
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_edit')).first);
      await tester.pumpAndSettle();
      expect(find.text('25% / 25%'), findsOneWidget);

      // Change the item's quantity (label, qty, unit, weight are in order).
      final qty = find.widgetWithText(TextField, t('v2_qty_label'));
      await tester.enterText(qty, '8');
      await tester.pumpAndSettle();
      final save = find.text(t('v2_save'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();

      final supply = saved!.stages.firstWhere(
        (s) => s.stageKey == 'material_supply',
      );
      expect(supply.measurementMode, 'items');
      expect(supply.items.single.itemKey, '1');
      expect(supply.items.single.quantity.canonicalText, '8');
      expect(tester.takeException(), isNull);
    });

    testWidgets('blocks saving while item weights miss the stage share', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2ContractTab(
            setup: YorksAccountsCommercialSetupRead.fromJson(itemsSetup()),
            language: en,
            canEdit: true,
            onSave: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_edit')).first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, t('v2_weight_label')),
        '20',
      );
      await tester.pumpAndSettle();
      expect(find.text('20% / 25%'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, t('v2_save')),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('lists that differ between buildings stay protected', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2ContractTab(
            setup: YorksAccountsCommercialSetupRead.fromJson(
              itemsSetup(df4wWeight: '20.0000'),
            ),
            language: en,
            canEdit: true,
            onSave: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(t('v2_edit_items_blocked')), findsOneWidget);
    });

    testWidgets('the editor lays out at 360px with items', (tester) async {
      _surface(tester, width: 360);
      await tester.pumpWidget(
        _wrap(
          AccountsV2ContractTab(
            setup: YorksAccountsCommercialSetupRead.fromJson(itemsSetup()),
            language: en,
            canEdit: true,
            onSave: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_edit')).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('import', () {
    Future<void> open(
      WidgetTester tester, {
      required YorksAccountsMasterImportFile? file,
      Object? throws,
      List<YorksContractBuildingOption> options = _options,
      YorksApplyMasterImportAction? onApply,
    }) async {
      _surface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2ContractTab(
            setup: YorksAccountsCommercialSetupRead.fromJson(_withContract()),
            language: en,
            canEdit: true,
            onSave: (_) async => null,
            buildingOptions: options,
            onImportMasterFile: () async {
              if (throws != null) throw throws;
              return file;
            },
            onApplyImport: onApply ?? (_, _) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_import_master')));
      await tester.pumpAndSettle();
    }

    testWidgets('shows both values and saves the one confirmed, with a note', (
      tester,
    ) async {
      YorksAccountsCommercialSetup? saved;
      String? note;
      await open(
        tester,
        file: _workbook(),
        onApply: (setup, n) async {
          saved = setup;
          note = n;
          return null;
        },
      );
      // Current value proposed; workbook value one tap away; mismatch explained.
      final value = tester.widget<TextField>(
        find.byKey(const Key('import-contract-value')),
      );
      expect(value.controller!.text, '1000000');
      expect(find.textContaining('AED 1,200,000.00'), findsWidgets);

      await tester.tap(find.text(t('v2_import_confirm')));
      await tester.pumpAndSettle();

      expect(saved!.contractValue.canonicalText, '1000000');
      expect(saved!.buildings.first.buildingScopeId, 'scope-DF3W');
      final supply = saved!.stages.firstWhere(
        (s) => s.stageKey == 'material_supply',
      );
      expect(supply.items.single.weightPercentOfContract.canonicalText, '25');
      expect(supply.items.single.unitCode, 'Nos');
      expect(note, contains('master.xlsx'));
      expect(note, contains('abc123'));
      expect(find.text(t('v2_import_saved')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('one tap adopts the workbook value', (tester) async {
      YorksAccountsCommercialSetup? saved;
      await open(
        tester,
        file: _workbook(),
        onApply: (setup, _) async {
          saved = setup;
          return null;
        },
      );
      await tester.tap(find.textContaining(t('v2_import_use_workbook')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_import_confirm')));
      await tester.pumpAndSettle();
      expect(saved!.contractValue.canonicalText, '1200000');
    });

    testWidgets('an unmatched building blocks saving', (tester) async {
      await open(
        tester,
        file: _workbook(codes: const ['ZZ1', 'ZZ2']),
        options: const [],
      );
      expect(
        find.text(
          t(
            'v2_import_issue_building_unmatched',
          ).replaceAll('{building}', 'ZZ1'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, t('v2_import_confirm')),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('a server rejection stays in the dialog with the reason', (
      tester,
    ) async {
      await open(
        tester,
        file: _workbook(),
        onApply: (_, _) async => 'R39_ACCOUNTS_INVALID_STAGE_ITEMS',
      );
      await tester.tap(find.text(t('v2_import_confirm')));
      await tester.pumpAndSettle();
      expect(find.text(t('v2_err_stage_items')), findsOneWidget);
      expect(find.text(t('v2_import_confirm')), findsOneWidget);
    });

    testWidgets('an unreadable file shows a clear message', (tester) async {
      await open(tester, file: null, throws: StateError('bad zip'));
      expect(find.text(t('v2_import_failed')), findsOneWidget);
    });

    testWidgets('cancelling the file picker does nothing', (tester) async {
      await open(tester, file: null);
      expect(find.text(t('v2_import_preview_title')), findsNothing);
    });

    testWidgets('a workbook that is not a master file cannot be saved', (
      tester,
    ) async {
      final draft = const YorksAccountsMasterFileParser().parse(
        sheets: {'Sheet1': const []},
      );
      await open(tester, file: (draft: draft, fileName: 'x.xlsx', sha256: 'z'));
      expect(find.text(t('v2_import_issue_summary_missing')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, t('v2_import_confirm')),
            )
            .onPressed,
        isNull,
      );
    });
  });

  group('invoice numbering', () {
    testWidgets('can be set when there is none yet', (tester) async {
      _surface(tester);
      String? prefix;
      await tester.pumpWidget(
        _wrap(
          AccountsV2ContractTab(
            setup: YorksAccountsCommercialSetupRead.fromJson(_withContract()),
            language: en,
            canManageInvoices: true,
            onSaveInvoiceSettings:
                ({
                  required String invoicePrefix,
                  String? scopeLine,
                  String? attentionName,
                  String? billToPartyId,
                  int? expectedVersion,
                }) async {
                  prefix = invoicePrefix;
                  return null;
                },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(t('v2_invoice_numbering_empty')), findsOneWidget);
      final edit = find.text(t('v2_edit')).last;
      await tester.ensureVisible(edit);
      await tester.pumpAndSettle();
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'YRA322');
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_save')));
      await tester.pumpAndSettle();
      expect(prefix, 'YRA322');
      expect(find.text(t('v2_saved')), findsOneWidget);
    });

    testWidgets('is read-only without invoice permission', (tester) async {
      _surface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2ContractTab(
            setup: YorksAccountsCommercialSetupRead.fromJson(_withContract()),
            language: en,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(t('v2_invoice_numbering_title')), findsNothing);
    });
  });
}

// R39 Accounts Workspace V2 — ways back from a mistake on the Contract tab:
// Undo after one-click changes, unsaved edits kept while the tab is closed,
// saving against the version the edits started from, and a partial save that
// says exactly what was saved.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/accounts/application/v2/accounts_unsaved_drafts.dart';
import 'package:material_ledger/features/accounts/domain/v2/commercial_setup_read_models.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_common.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_contract_tab.dart';
import 'package:material_ledger/features/accounts/presentation/v2/kit/accounts_v2_kit.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/services/yorks_v1_procurement_unload_guard.dart';

const en = AppLanguage.english;
String t(String key) => accountsV2Text(en, key);

class _Guard implements YorksV1ProcurementUnloadGuard {
  bool active = false;
  @override
  void setActive(bool value) => active = value;
  @override
  void dispose() {}
}

Map<String, dynamic> _contract({
  int version = 3,
  String value = '1000000.00',
  int terms = 45,
}) => {
  'schema_version': 1,
  'project_id': 'p1',
  'has_baseline': true,
  'can_configure': true,
  'capabilities': {
    'view_project_accounts': true,
    'view_project_commercial_values': true,
    'configure_project_commercials': true,
  },
  'profile_version': version,
  'currency_code': 'AED',
  'contract_value': value,
  'vat_rate_percent': '5.0000',
  'payment_terms_days': terms,
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
      'allocation_percent': '40.0000',
      'value': '400000.00',
    },
    {
      'stage_key': 'install',
      'stage_name': 'Installation',
      'display_order': 2,
      'measurement_mode': 'percent',
      'allocation_percent': '60.0000',
      'value': '600000.00',
    },
  ],
  'items': const [],
};

void _surface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Finder _field(String label) => find.widgetWithText(TextField, label);

String _text(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label)).controller!.text;

Future<void> _tapButton(WidgetTester tester, String label) async {
  final f = find.widgetWithText(AccountsV2Button, label);
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _undo(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(SnackBarAction, t('v2_undo')));
  await tester.pumpAndSettle();
}

typedef _Saved = ({String? value, int? version});

AccountsV2ContractTab _tab(
  Map<String, dynamic> json, {
  YorksAccountsUnsavedDrafts? drafts,
  List<_Saved>? saves,
  String? Function()? setupResult,
  String? Function()? referencesResult,
  List<String>? referenceSaves,
}) => AccountsV2ContractTab(
  setup: YorksAccountsCommercialSetupRead.fromJson(json),
  language: en,
  canEdit: true,
  drafts: drafts,
  onSave: (m, version) async {
    saves?.add((value: m.contractValue.canonicalText, version: version));
    return setupResult?.call();
  },
  onSaveReferences:
      ({
        String? clientTrn,
        String? workOrderNumber,
        String? workOrderDate,
        String? contractNumber,
        String? retentionPercent,
        int? expectedProfileVersion,
      }) async {
        referenceSaves?.add('$clientTrn@$expectedProfileVersion');
        return referencesResult?.call();
      },
);

void main() {
  group('Undo', () {
    testWidgets('Discard can be undone', (tester) async {
      _surface(tester);
      await tester.pumpWidget(_wrap(_tab(_contract())));
      await tester.pumpAndSettle();
      await tester.enterText(_field(t('v2c_contract_value')), '2000000');
      await tester.pumpAndSettle();

      await _tapButton(tester, t('v2c_discard'));
      expect(_text(tester, t('v2c_contract_value')), '1000000');
      expect(find.text(t('v2u_discarded')), findsOneWidget);

      await _undo(tester);
      expect(_text(tester, t('v2c_contract_value')), '2000000');
      expect(
        find.byKey(const ValueKey('accounts-v2-contract-save-bar')),
        findsOneWidget,
        reason: 'the restored edits are unsaved again',
      );
    });

    testWidgets('removing a stage can be undone', (tester) async {
      _surface(tester);
      await tester.pumpWidget(_wrap(_tab(_contract())));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Installation'), findsOneWidget);

      final remove = find.byWidgetPredicate(
        (w) => w is AccountsV2Button && w.tooltip == t('v2_remove'),
      );
      // Two buildings, then two stages: the last one is Installation.
      await tester.ensureVisible(remove.last);
      await tester.tap(remove.last);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Installation'), findsNothing);
      expect(find.text(t('v2u_removed_stage')), findsOneWidget);

      await _undo(tester);
      expect(find.widgetWithText(TextField, 'Installation'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('kept drafts', () {
    testWidgets('unsaved edits come back when the tab opens again', (
      tester,
    ) async {
      _surface(tester);
      final guard = _Guard();
      final drafts = YorksAccountsUnsavedDrafts(unloadGuard: guard);
      addTearDown(drafts.dispose);

      await tester.pumpWidget(_wrap(_tab(_contract(), drafts: drafts)));
      await tester.pumpAndSettle();
      await tester.enterText(_field(t('v2c_contract_value')), '2500000');
      await tester.pumpAndSettle();
      expect(drafts.has(YorksAccountsDraftSection.contract), isTrue);
      expect(guard.active, isTrue, reason: 'closing the page warns');

      // Another tab: the Contract form is gone.
      await tester.pumpWidget(_wrap(const SizedBox()));
      await tester.pumpAndSettle();
      expect(drafts.has(YorksAccountsDraftSection.contract), isTrue);

      await tester.pumpWidget(_wrap(_tab(_contract(), drafts: drafts)));
      await tester.pumpAndSettle();
      expect(_text(tester, t('v2c_contract_value')), '2500000');
      expect(find.textContaining(t('v2u_restored')), findsOneWidget);

      // Discarding forgets the draft and lets the page close quietly.
      await _tapButton(tester, t('v2c_discard'));
      expect(drafts.has(YorksAccountsDraftSection.contract), isFalse);
      expect(guard.active, isFalse);
    });

    testWidgets('a clean tab keeps nothing', (tester) async {
      _surface(tester);
      final drafts = YorksAccountsUnsavedDrafts(unloadGuard: _Guard());
      addTearDown(drafts.dispose);
      await tester.pumpWidget(_wrap(_tab(_contract(), drafts: drafts)));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_wrap(const SizedBox()));
      await tester.pumpAndSettle();
      expect(drafts.isEmpty, isTrue);
    });
  });

  group('someone else saved meanwhile', () {
    testWidgets('Save sends the version the edits started from', (
      tester,
    ) async {
      _surface(tester);
      final saves = <_Saved>[];
      await tester.pumpWidget(_wrap(_tab(_contract(), saves: saves)));
      await tester.pumpAndSettle();
      await tester.enterText(_field(t('v2c_contract_value')), '2000000');
      await tester.pumpAndSettle();
      await _tapButton(tester, t('v2c_save_changes'));
      expect(saves.single.version, 3);
    });

    testWidgets('a newer version offers to keep my changes on top of it', (
      tester,
    ) async {
      _surface(tester);
      final saves = <_Saved>[];
      await tester.pumpWidget(_wrap(_tab(_contract(), saves: saves)));
      await tester.pumpAndSettle();
      await tester.enterText(_field(t('v2c_contract_value')), '2000000');
      await tester.pumpAndSettle();

      // A background refresh brings version 4: payment terms changed.
      await tester.pumpWidget(
        _wrap(_tab(_contract(version: 4, terms: 60), saves: saves)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('accounts-v2-contract-stale-bar')),
        findsOneWidget,
      );
      expect(_text(tester, t('v2c_contract_value')), '2000000');

      await tester.tap(
        find.byKey(const ValueKey('accounts-v2-contract-keep-mine')),
      );
      await tester.pumpAndSettle();
      expect(_text(tester, t('v2c_contract_value')), '2000000');
      expect(_text(tester, t('v2c_terms_days')), '60', reason: 'theirs kept');
      expect(find.textContaining(t('v2c_merged')), findsWidgets);

      await _tapButton(tester, t('v2c_save_changes'));
      expect(saves.single, (value: '2000000', version: 4));
    });

    testWidgets('a field both people changed is named', (tester) async {
      _surface(tester);
      await tester.pumpWidget(_wrap(_tab(_contract())));
      await tester.pumpAndSettle();
      await tester.enterText(_field(t('v2c_contract_value')), '2000000');
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _wrap(_tab(_contract(version: 4, value: '1500000.00'))),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('accounts-v2-contract-keep-mine')),
      );
      await tester.pumpAndSettle();
      expect(_text(tester, t('v2c_contract_value')), '2000000');
      expect(find.textContaining(t('v2c_part_details')), findsWidgets);
    });

    testWidgets('their version can be taken, and that undone', (tester) async {
      _surface(tester);
      await tester.pumpWidget(_wrap(_tab(_contract())));
      await tester.pumpAndSettle();
      await tester.enterText(_field(t('v2c_contract_value')), '2000000');
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _wrap(_tab(_contract(version: 4, value: '1500000.00'))),
      );
      await tester.pumpAndSettle();
      await _tapButton(tester, t('v2c_stale_theirs'));
      expect(_text(tester, t('v2c_contract_value')), '1500000');

      await _undo(tester);
      expect(_text(tester, t('v2c_contract_value')), '2000000');
      expect(
        find.byKey(const ValueKey('accounts-v2-contract-stale-bar')),
        findsOneWidget,
      );
    });
  });

  testWidgets('a partial save says what was saved and retries only the rest', (
    tester,
  ) async {
    _surface(tester);
    final saves = <_Saved>[];
    final referenceSaves = <String>[];
    String? refuse = 'R39_ACCOUNTS_INVALID_TRN';
    await tester.pumpWidget(
      _wrap(
        _tab(
          _contract(),
          saves: saves,
          referenceSaves: referenceSaves,
          referencesResult: () => refuse,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(_field(t('v2c_contract_value')), '2000000');
    await tester.enterText(_field(t('v2c_client_trn')), '100200300400500');
    await tester.pumpAndSettle();

    await _tapButton(tester, t('v2c_save_changes'));
    expect(saves, hasLength(1));
    expect(find.textContaining('${t('v2c_part_setup')} saved'), findsOneWidget);
    expect(find.textContaining(t('v2c_part_references')), findsWidgets);

    refuse = null;
    await _tapButton(tester, t('v2c_save_changes'));
    expect(saves, hasLength(1), reason: 'the saved part is not sent again');
    expect(referenceSaves, hasLength(2));
  });
}

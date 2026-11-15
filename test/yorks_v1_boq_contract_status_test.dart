// Contract materials — BOQ › Contract Materials status
// (PRODUCT_DECISIONS.md section 61). Fixtures are fictional.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/projects/presentation/widgets/yorks_v1_boq_contract_status_view.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_boq.dart';
import 'package:material_ledger/shared/models/yorks_v1_boq_contract_status.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_boq_contract_status_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_boq_repository.dart'
    show YorksV1BoqRpcClient;

import 'support/accounts_v2_golden_fonts.dart';

const _en = AppLanguage.english;

final class _Rpc implements YorksV1BoqRpcClient {
  _Rpc(this.response);

  final Object? response;
  int calls = 0;
  String? function;
  Map<String, Object?>? parameters;

  @override
  Future<Object?> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async {
    calls += 1;
    function = functionName;
    this.parameters = parameters;
    return response;
  }
}

const _flagsOn = YorksV1FeatureFlags(
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
);

Map<String, dynamic> _stage(
  String key,
  String label,
  String qty,
  String unit,
  String done, {
  String? amount,
  String? rate,
}) => {
  'stage_key': key,
  'stage_label': label,
  'quantity': qty,
  'unit_code': unit,
  'confirmed_qty': done,
  'amount': ?amount,
  'rate': ?rate,
};

/// [level]: 0 Procurement (requests only), 1 Site Engineer (+ progress),
/// 2 Project Engineer (+ prices).
Map<String, dynamic> _statusJson(int level) {
  Map<String, dynamic> row(
    String id,
    String key,
    String requested,
    String received,
    List<Map<String, dynamic>> stages,
  ) => {
    'boq_row_id': id,
    'project_scope_id': 'b1',
    'item_key': key,
    'requested_qty': requested,
    'received_qty': received,
    'deliveries': received == '0' ? 0 : 1,
    'last_delivery_reference': received == '0' ? null : 'DO-101',
    'last_delivery_date': received == '0' ? null : '2026-10-01',
    if (level >= 1)
      'stages': [
        for (final s in stages)
          level >= 2
              ? s
              : ({...s}
                  ..remove('amount')
                  ..remove('rate')),
      ],
  };
  return {
    'schema_version': 1,
    'project_id': 'p1',
    'group_id': 'g1',
    'can_view_progress': level >= 1,
    'can_view_values': level >= 2,
    if (level >= 2) 'currency_code': 'AED',
    'rows': [
      row('r1', '1', '4.0000', '2.0000', [
        _stage(
          'material_supply',
          'Material Supply',
          '6.0000',
          'Nos',
          '6.0000',
          amount: '200000.00',
          rate: '33333.33',
        ),
        _stage(
          'installation',
          'Installation',
          '6.0000',
          'Nos',
          '2.0000',
          amount: '100000.00',
          rate: '16666.67',
        ),
      ]),
      row('r2', '2', '0', '0', [
        _stage(
          'material_supply',
          'Material Supply',
          '55.0000',
          'Nos',
          '20.0000',
          amount: '50000.00',
          rate: '909.09',
        ),
        _stage(
          'installation',
          'Installation',
          '55.0000',
          'Nos',
          '0',
          amount: '25000.00',
          rate: '454.55',
        ),
      ]),
      row('r3', '10-1', '0', '0', [
        _stage(
          'material_supply',
          'Material Supply',
          '1.0000',
          'Lot',
          '0.5000',
          amount: '30000.00',
          rate: '30000.00',
        ),
        _stage(
          'installation',
          'Installation',
          '1.0000',
          'Lot',
          '0',
          amount: '15000.00',
          rate: '15000.00',
        ),
      ]),
    ],
  };
}

final _group = YorksV1BoqGroup.fromRpcJson(const {
  'id': 'g1',
  'project_id': 'p1',
  'scope_id': 'b1',
  'name': 'Contract Materials',
  'display_order': 1,
  'is_custom': true,
  'record_version': 1,
  'updated_at': '2026-11-15T00:00:00Z',
});

YorksV1BoqWorksheet _worksheet() {
  YorksV1BoqRow row(
    String id,
    int order,
    String ref,
    String d,
    String q,
    String u,
  ) => YorksV1BoqRow(
    id: id,
    displayOrder: order,
    values: {'ref': ref, 'description': d, 'quantity': q, 'unit': u},
    canonicalValues: {'description': d, 'quantity': q, 'unit': u},
  );
  return YorksV1BoqWorksheet(
    group: _group,
    columns: const [
      YorksV1BoqColumn(id: 'ref', heading: 'Ref', displayOrder: 1),
      YorksV1BoqColumn(
        id: 'description',
        heading: 'Description',
        displayOrder: 2,
        canonicalField: YorksV1BoqCanonicalField.description,
      ),
      YorksV1BoqColumn(
        id: 'quantity',
        heading: 'Qty',
        displayOrder: 3,
        canonicalField: YorksV1BoqCanonicalField.quantity,
      ),
      YorksV1BoqColumn(
        id: 'unit',
        heading: 'Unit',
        displayOrder: 4,
        canonicalField: YorksV1BoqCanonicalField.unit,
      ),
    ],
    rows: [
      row('r1', 1, 'A.1', 'AC Units (Package Unit)', '6', 'Nos'),
      row('r2', 2, 'A.2', 'Motorized Fire Dampers', '55', 'Nos'),
      row('r3', 3, 'A.3.1', 'Ducting — Basement Floor', '1', 'Lot'),
      row('r9', 4, '', 'Spare line, not tied', '2', 'Nos'),
    ],
  );
}

Future<void> _pump(WidgetTester tester, Size size, int level) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: YorksV1BoqContractStatusView(
            worksheet: _worksheet(),
            status: YorksV1BoqContractStatus.fromJson(_statusJson(level)),
            language: _en,
            compact: size.width < 600,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses each level of access', () {
    final pe = YorksV1BoqContractStatus.fromJson(_statusJson(2));
    expect(pe.canViewValues, isTrue);
    expect(pe.row('r1')!.stage('material_supply')!.rate, '33333.33');
    final se = YorksV1BoqContractStatus.fromJson(_statusJson(1));
    expect(se.canViewValues, isFalse);
    expect(se.row('r1')!.stage('material_supply')!.amount, isNull);
    expect(se.row('r1')!.stage('installation')!.confirmedQty, '2.0000');
    final proc = YorksV1BoqContractStatus.fromJson(_statusJson(0));
    expect(proc.canViewProgress, isFalse);
    expect(proc.row('r1')!.stages, isNull);
    expect(proc.row('r1')!.receivedQty, '2.0000');
  });

  group('repository', () {
    test('asks nothing while contract materials are off', () async {
      final rpc = _Rpc(_statusJson(2));
      final repo = YorksV1BoqContractStatusRepository(
        featureFlags: const YorksV1FeatureFlags(),
        rpcClient: rpc,
      );
      expect(await repo.getStatus('g1'), isNull);
      expect(rpc.calls, 0);
    });

    test('reads the folder status when on', () async {
      final rpc = _Rpc(_statusJson(2));
      final repo = YorksV1BoqContractStatusRepository(
        featureFlags: _flagsOn,
        rpcClient: rpc,
      );
      final status = await repo.getStatus('g1');
      expect(rpc.function, 'v1_get_boq_contract_status');
      expect(rpc.parameters, {'p_group_id': 'g1'});
      expect(status!.rows, hasLength(3));
    });
  });

  group('view', () {
    testWidgets('Project Engineer: prices, requests, delivery and install', (
      tester,
    ) async {
      await _pump(tester, const Size(1366, 800), 2);
      expect(tester.takeException(), isNull);
      expect(find.text('RATE'), findsOneWidget);
      expect(find.text('200,000.00'), findsOneWidget);
      expect(find.text('Delivered'), findsWidgets);
      expect(find.text('Delivered 20 of 55'), findsOneWidget);
      expect(find.text('Installed 2 of 6'), findsOneWidget);
      expect(find.text('Delivered 50%'), findsOneWidget);
      expect(find.text('Spare line, not tied'), findsNothing);
    });

    testWidgets('Site Engineer: delivery and install, no price', (
      tester,
    ) async {
      await _pump(tester, const Size(1366, 800), 1);
      expect(tester.takeException(), isNull);
      expect(find.text('RATE'), findsNothing);
      expect(find.text('AMOUNT'), findsNothing);
      expect(find.textContaining('200,000'), findsNothing);
      expect(find.text('Delivered 20 of 55'), findsOneWidget);
    });

    testWidgets('Procurement: what was requested and received only', (
      tester,
    ) async {
      await _pump(tester, const Size(1366, 800), 0);
      expect(tester.takeException(), isNull);
      expect(find.text('REQUESTED'), findsOneWidget);
      expect(find.text('ON SITE'), findsOneWidget);
      expect(find.text('DELIVERED'), findsNothing);
      expect(find.text('INSTALLED'), findsNothing);
      expect(find.textContaining('of 55'), findsNothing);
    });

    testWidgets('phone at 360px: one card per tied line', (tester) async {
      await _pump(tester, const Size(360, 900), 2);
      expect(tester.takeException(), isNull);
      final card = find.byKey(const ValueKey('boq-contract-card-r2'));
      expect(card, findsOneWidget);
      expect(tester.getSize(card).height, greaterThanOrEqualTo(44));
      expect(find.text('A.2  Motorized Fire Dampers'), findsOneWidget);
      expect(find.textContaining('Rate 909.09'), findsOneWidget);
    });
  });

  group('goldens', () {
    setUpAll(loadAccountsV2GoldenFonts);
    final cases = <String, (Size, int)>{
      'boq_contract_status_desktop': (const Size(1366, 640), 2),
      'boq_contract_status_procurement_desktop': (const Size(1366, 560), 0),
      'boq_contract_status_mobile': (const Size(360, 900), 1),
    };
    for (final c in cases.entries) {
      testWidgets(c.key, (tester) async {
        await _pump(tester, c.value.$1, c.value.$2);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/accounts_v2/${c.key}.png'),
        );
      });
    }
  });
}

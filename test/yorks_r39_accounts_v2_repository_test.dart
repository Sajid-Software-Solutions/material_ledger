import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/accounts/data/accounts_repository.dart'
    show YorksAccountsRpcClient;
import 'package:material_ledger/features/accounts/data/v2/accounts_workspace_repository.dart';
import 'package:material_ledger/features/accounts/domain/accounts_decimal.dart';
import 'package:material_ledger/features/accounts/domain/v2/commercial_setup_models.dart';

YorksAccountsDecimal _d(String raw) => YorksAccountsDecimal.parse(raw);

final class _FakeRpc implements YorksAccountsRpcClient {
  _FakeRpc(this.response);
  final Map<String, dynamic> response;
  String? lastFunction;
  Map<String, Object?>? lastParams;

  @override
  Future<Map<String, dynamic>> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async {
    lastFunction = functionName;
    lastParams = parameters;
    return response;
  }
}

YorksAccountsCommercialSetup _setup({
  String buildingBShare = '75',
}) {
  return YorksAccountsCommercialSetup(
    contractValue: _d('1000000.00'),
    currencyCode: 'AED',
    vatRatePercent: _d('5.0000'),
    paymentTermsDays: 45,
    reminderLeadDays: 10,
    buildings: [
      YorksAccountsSetupBuilding(buildingScopeId: 'b01', allocationPercent: _d('25')),
      YorksAccountsSetupBuilding(buildingScopeId: 'b02', allocationPercent: _d(buildingBShare)),
    ],
    stages: [
      YorksAccountsSetupStage(
        stageKey: 'design', stageLabel: 'Design', allocationPercent: _d('10'),
        position: 1, measurementMode: 'percent', items: const [],
      ),
      YorksAccountsSetupStage(
        stageKey: 'material_supply', stageLabel: 'Material Supply',
        allocationPercent: _d('50'), position: 2, measurementMode: 'items',
        items: [
          YorksAccountsSetupItem(
            itemKey: 'a', itemLabel: 'Item A', displayOrder: 1,
            quantity: _d('10'), unitCode: 'Nos', weightPercentOfContract: _d('12.5'),
          ),
        ],
      ),
      YorksAccountsSetupStage(
        stageKey: 'installation', stageLabel: 'Installation',
        allocationPercent: _d('30'), position: 3, measurementMode: 'percent', items: const [],
      ),
      YorksAccountsSetupStage(
        stageKey: 'commissioning_handover', stageLabel: 'C&H',
        allocationPercent: _d('5'), position: 4, measurementMode: 'percent', items: const [],
      ),
      YorksAccountsSetupStage(
        stageKey: 'energizing', stageLabel: 'Energizing',
        allocationPercent: _d('5'), position: 5, measurementMode: 'percent', items: const [],
      ),
    ],
  );
}

void main() {
  group('YorksAccountsCommercialSetup', () {
    test('validates a 100%/100% setup', () {
      final checks = _setup().validate();
      expect(checks.every((c) => c.ok), isTrue);
      expect(_setup().isValid, isTrue);
    });

    test('flags buildings that do not total 100%', () {
      final setup = _setup(buildingBShare: '70'); // 25 + 70 = 95
      final buildings = setup.validate().firstWhere((c) => c.key == 'buildings_total');
      expect(buildings.ok, isFalse);
      expect(setup.isValid, isFalse);
    });

    test('builds the p_setup payload with decimal-string fields and items', () {
      final json = _setup().toSetupJson();
      expect(json['currency_code'], 'AED');
      expect(_d(json['contract_value'] as String), _d('1000000.00'));
      final buildings = json['buildings'] as List;
      expect(buildings.length, 2);
      expect(_d((buildings.first as Map)['allocation_percent'] as String), _d('25'));
      final stages = json['stages'] as List;
      final material = stages.firstWhere((s) => (s as Map)['stage_key'] == 'material_supply') as Map;
      expect(material['measurement_mode'], 'items');
      expect((material['items'] as List).single, isA<Map>());
      // Percent-mode stages carry no items array.
      final design = stages.firstWhere((s) => (s as Map)['stage_key'] == 'design') as Map;
      expect(design.containsKey('items'), isFalse);
    });
  });

  group('YorksAccountsWorkspaceRepository', () {
    test('getWorkspace calls the right RPC and parses the projection', () async {
      final fake = _FakeRpc({
        'project_id': 'p1',
        'has_baseline': false,
        'capabilities': {
          'view_project_accounts': true,
          'view_project_commercial_values': false,
          'view_supplier_costs': false,
        },
        'steps': <dynamic>[],
        'attention': <dynamic>[],
      });
      final repo = YorksAccountsWorkspaceRepository(fake);
      final ws = await repo.getWorkspace('p1');
      expect(fake.lastFunction, 'v1_get_project_accounts_workspace');
      expect(fake.lastParams!['p_project_id'], 'p1');
      expect(ws.projectId, 'p1');
      expect(ws.hasBaseline, isFalse);
    });

    test('saveClaimWorkbench shapes entries and evidence params', () async {
      final fake = _FakeRpc({'confirmed_rows': 1});
      final repo = YorksAccountsWorkspaceRepository(fake);
      await repo.saveClaimWorkbench(
        projectId: 'p1',
        claimReference: 'CLM-1',
        periodStart: '2026-08-01',
        periodEnd: '2026-08-25',
        entries: [
          {'progress_entry_id': 'pe1', 'confirmed_percent_to_date': '100.0000'},
        ],
        evidenceDocumentIds: ['doc1'],
        reason: 'Monthly',
        idempotencyKey: 'key-1',
      );
      expect(fake.lastFunction, 'v1_save_claim_workbench');
      expect(fake.lastParams!['p_entries'], isA<List>());
      expect(fake.lastParams!['p_evidence_document_ids'], ['doc1']);
      expect(fake.lastParams!['p_period_start'], '2026-08-01');
    });
  });
}

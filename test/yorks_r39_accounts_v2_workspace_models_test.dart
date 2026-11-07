import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/accounts/domain/accounts_decimal.dart';
import 'package:material_ledger/features/accounts/domain/v2/accounts_workspace_models.dart';

YorksAccountsDecimal _d(String raw) => YorksAccountsDecimal.parse(raw);

Map<String, dynamic> _fullWorkspace() => <String, dynamic>{
  'schema_version': 1,
  'project_id': '39d10000-0000-4000-8000-000000000001',
  'project_reference': 'YRA-322',
  'project_name': 'Nexus',
  'has_baseline': true,
  'capabilities': {
    'view_project_accounts': true,
    'view_project_commercial_values': true,
    'view_supplier_costs': true,
  },
  'steps': [
    {'key': 'setup', 'state': 'done'},
    {'key': 'progress', 'state': 'done'},
    {'key': 'invoice', 'state': 'done'},
    {'key': 'paid', 'state': 'current'},
  ],
  'attention': [
    {
      'severity': 'pri',
      'kind': 'awaiting_certification',
      'action_key': 'certify',
      'target_type': 'invoice',
      'target_id': '39d10000-0000-4000-8000-0000000000aa',
    },
  ],
  'money_flow': {
    'paid': '0.00',
    'invoiced_waiting': '50000.00',
    'done_not_invoiced': '0',
    'remaining': '950000.00',
  },
  'kpis': {
    'contract_value': '1000000.00',
    'contract_incl_vat': '1050000.00',
    'invoiced': '50000.00',
    'received': '0',
    'certified': '0',
    'outstanding': '0',
    'cheques_in_hand': '0',
    'done_not_invoiced': '0',
  },
  'heatmap': [
    {
      'building_scope_id': '39d10000-0000-4000-8000-000000000002',
      'building_name': 'Building 01',
      'stage_key': 'design',
      'stage_label': 'Design',
      'stage_value': '100000.00',
      'invoiced_amount': '50000.00',
      'invoiced_percent': '50.0',
    },
  ],
  'supplier': {'billed': '0', 'paid': '0', 'unpaid': '0', 'overdue_count': 0},
  'cash': {'received': '0', 'paid_to_suppliers': '0', 'net': '0'},
};

void main() {
  group('YorksAccountsWorkspace.fromJson', () {
    test('parses the full projection with decimal-string money fields', () {
      final ws = YorksAccountsWorkspace.fromJson(_fullWorkspace());
      expect(ws.projectId, '39d10000-0000-4000-8000-000000000001');
      expect(ws.hasBaseline, isTrue);
      expect(ws.capabilities.viewProjectCommercialValues, isTrue);
      expect(ws.steps.first.key, 'setup');
      expect(ws.steps.first.isDone, isTrue);
      expect(ws.steps.last.isCurrent, isTrue);
      expect(ws.attention.single.kind, 'awaiting_certification');
      expect(ws.kpis!.invoiced, _d('50000.00'));
      expect(ws.kpis!.contractValue, _d('1000000.00'));
      expect(ws.moneyFlow!.remaining, _d('950000.00'));
      expect(ws.heatmap.single.invoicedPercent, _d('50.0'));
      expect(ws.supplier!.overdueCount, 0);
      expect(ws.cash!.net, _d('0'));
    });

    test(
      'omits monetary and supplier blocks when the capability is absent',
      () {
        final json = _fullWorkspace()
          ..remove('money_flow')
          ..remove('kpis')
          ..remove('heatmap')
          ..remove('supplier')
          ..remove('cash');
        json['capabilities'] = {
          'view_project_accounts': true,
          'view_project_commercial_values': false,
          'view_supplier_costs': false,
        };
        final ws = YorksAccountsWorkspace.fromJson(json);
        expect(ws.moneyFlow, isNull);
        expect(ws.kpis, isNull);
        expect(ws.supplier, isNull);
        expect(ws.cash, isNull);
        expect(ws.heatmap, isEmpty);
        expect(ws.steps, isNotEmpty);
      },
    );

    test('rejects a money field delivered as a JSON number', () {
      final json = _fullWorkspace();
      // Inject a JSON number (not a decimal string) for a money field.
      json['kpis'] = Map<String, dynamic>.from(json['kpis'] as Map)
        ..['invoiced'] = 50000;
      expect(
        () => YorksAccountsWorkspace.fromJson(json),
        throwsFormatException,
      );
    });

    test('parses per-step detail figures and the tab badges', () {
      final json = _fullWorkspace();
      json['steps'] = [
        {
          'key': 'setup',
          'state': 'done',
          'detail': {
            'contract_value': '1000000.00',
            'building_count': 4,
            'stage_count': 5,
          },
        },
        {
          'key': 'progress',
          'state': 'current',
          'detail': {'claim_reference': 'Claim #03', 'claim_gross': '27507.00'},
        },
        {
          'key': 'invoice',
          'state': '',
          'detail': {'issued_count': 2, 'latest_reference': 'YRA32202R.1'},
        },
        {'key': 'paid', 'state': ''},
      ];
      json['badges'] = {'claims_draft': true, 'supplier_count': 3};
      final ws = YorksAccountsWorkspace.fromJson(json);
      final setup = ws.steps[0].detail!;
      expect(setup.contractValue, _d('1000000.00'));
      expect(setup.buildingCount, 4);
      expect(setup.stageCount, 5);
      expect(ws.steps[1].detail!.claimReference, 'Claim #03');
      expect(ws.steps[1].detail!.claimGross, _d('27507.00'));
      expect(ws.steps[2].detail!.issuedCount, 2);
      expect(ws.steps[2].detail!.latestReference, 'YRA32202R.1');
      expect(ws.steps[3].detail, isNull); // no detail → label-only
      expect(ws.badges.claimsDraft, isTrue);
      expect(ws.badges.supplierCount, 3);
    });

    test('defaults badges to empty and step detail to null when absent', () {
      final ws = YorksAccountsWorkspace.fromJson(_fullWorkspace());
      expect(ws.steps.first.detail, isNull);
      expect(ws.badges.claimsDraft, isFalse);
      expect(ws.badges.supplierCount, isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/accounts/data/v2/client_invoice_document_builder.dart';
import 'package:material_ledger/features/accounts/domain/v2/client_invoice_document_models.dart';

Map<String, dynamic> _docJson() => {
  'invoice_reference': 'YRA322-01',
  'invoice_date': '2026-08-26',
  'submission_date': '2026-08-26',
  'due_date': '2026-10-10',
  'payment_terms_days': 45,
  'currency_code': 'AED',
  'company': {
    'trn': '100123456700003',
    'address': 'P.O. Box 4757, Abu Dhabi',
    'phone': '02-5509788',
    'fax': '02-5509688',
    'email': 'yorks_sk@yorks.ae',
    'bank_name': 'First Abu Dhabi Bank',
    'bank_account_name': 'Yorks',
    'bank_iban': 'AE000000000000000000000',
  },
  'project': {'project_id': 'p1', 'project_ref': 'YRA-322', 'name': 'Tower A'},
  'claim': {
    'claim_id': 'c1',
    'claim_reference': 'CLM-01',
    'period_start': '2026-08-01',
    'period_end': '2026-08-25',
  },
  'settings': {
    'invoice_prefix': 'YRA322',
    'scope_line': 'MEP works',
    'attention_name': 'Mr Client',
  },
  'amounts': {
    'ex_vat': '1000000.00',
    'vat_rate_percent': '5.0000',
    'vat': '50000.00',
    'total_incl_vat': '1050000.00',
  },
  'lines': [
    {
      'building_scope_id': 'b01',
      'building_name': 'Block A',
      'stage_key': 'material_supply',
      'stage_label': 'Material Supply',
      'amount': '500000.00',
    },
    {
      'building_scope_id': 'b02',
      'building_name': 'Block B',
      'stage_key': 'material_supply',
      'stage_label': 'Material Supply',
      'amount': '500000.00',
    },
  ],
  'contract_value': '2000000.00',
  'summary': {
    'contract_total': '2000000.00',
    'previous_total': '0.00',
    'this_total': '1000000.00',
    'total_total': '1000000.00',
    'stages': [
      {
        'stage_key': 'material_supply',
        'stage_label': 'Material Supply',
        'contract_percent': '50',
        'contract_amount': '1000000.00',
        'previous_amount': '0.00',
        'this_amount': '1000000.00',
        'total_amount': '1000000.00',
      },
      {
        'stage_key': 'installation',
        'stage_label': 'Installation',
        'contract_percent': '50',
        'contract_amount': '1000000.00',
        'previous_amount': '0.00',
        'this_amount': '0.00',
        'total_amount': '0.00',
      },
    ],
  },
  'buildings': [
    {
      'building_scope_id': 'b01',
      'name': 'Block A',
      'share_percent': '50',
      'building_value': '1000000.00',
      'previous_amount': '0.00',
      'this_amount': '500000.00',
      'total_amount': '500000.00',
      'stages': [
        {
          'stage_key': 'material_supply',
          'stage_label': 'Material Supply',
          'stage_value': '500000.00',
          'previous_amount': '0.00',
          'this_amount': '500000.00',
          'total_amount': '500000.00',
        },
      ],
    },
    {
      'building_scope_id': 'b02',
      'name': 'Block B',
      'share_percent': '50',
      'building_value': '1000000.00',
      'previous_amount': '0.00',
      'this_amount': '500000.00',
      'total_amount': '500000.00',
      'stages': [
        {
          'stage_key': 'material_supply',
          'stage_label': 'Material Supply',
          'stage_value': '500000.00',
          'previous_amount': '0.00',
          'this_amount': '500000.00',
          'total_amount': '500000.00',
        },
      ],
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds a non-empty PDF from the frozen invoice snapshot', () async {
    final model = YorksClientInvoiceDocumentModel.fromJson(_docJson());
    final bytes = await YorksClientInvoiceDocumentBuilder.build(model);

    expect(bytes, isNotEmpty);
    // PDF magic header.
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('parses the summary matrix and per-building breakdown', () {
    final model = YorksClientInvoiceDocumentModel.fromJson(_docJson());

    expect(model.summary, isNotNull);
    expect(model.summary!.stages, hasLength(2));
    expect(model.summary!.thisTotal.canonicalText, '1000000');
    expect(model.buildings, hasLength(2));
    final a = model.buildings.firstWhere((b) => b.name == 'Block A');
    expect(a.buildingValue.canonicalText, '1000000');
    expect(a.thisAmount.canonicalText, '500000');
    expect(a.stages, hasLength(1));
    // Every printed % is a share of the whole contract (2,000,000), never of
    // the building (1,000,000): 500,000 is 25% of the contract, not 50%.
    expect(model.percentOfContract(a.totalAmount), closeTo(25.0, 0.001));
    expect(model.stageContractPercent('material_supply')?.canonicalText, '50');
  });

  group('percentages match the signed client invoice', () {
    // A four-building, 17,192,000 contract invoiced in two parts, with the
    // per-building Material Supply amounts of a real signed progress invoice.
    YorksClientInvoiceDocumentModel signedLike() {
      Map<String, dynamic> stage(
        String key,
        String value,
        String previous,
        String current,
        String total,
      ) => {
        'stage_key': key,
        'stage_label': key,
        'stage_value': value,
        'previous_amount': previous,
        'this_amount': current,
        'total_amount': total,
      };
      Map<String, dynamic> building(String id, String supply, String total) => {
        'building_scope_id': id,
        'name': 'Building $id',
        'share_percent': '25',
        'building_value': '4298000.00',
        'previous_amount': '429800.00',
        'this_amount': supply,
        'total_amount': total,
        'stages': [
          stage('design', '429800.00', '429800.00', '0.00', '429800.00'),
          stage('material_supply', '2149000.00', '0.00', supply, supply),
        ],
      };
      return YorksClientInvoiceDocumentModel.fromJson({
        ..._docJson(),
        'contract_value': '17192000.00',
        'summary': {
          'contract_total': '17192000.00',
          'previous_total': '1719200.00',
          'this_total': '5983597.45',
          'total_total': '7702797.45',
          'stages': [
            {
              'stage_key': 'design',
              'stage_label': 'Cooling Load Design',
              'contract_percent': '10',
              'contract_amount': '1719200.00',
              'previous_amount': '1719200.00',
              'this_amount': '0.00',
              'total_amount': '1719200.00',
            },
            {
              'stage_key': 'material_supply',
              'stage_label': 'Material Supply',
              'contract_percent': '50',
              'contract_amount': '8596000.00',
              'previous_amount': '0.00',
              'this_amount': '5983597.45',
              'total_amount': '5983597.45',
            },
          ],
        },
        'buildings': [
          building('A', '1549624.36', '1979424.36'),
          building('B', '1549624.36', '1979424.36'),
          building('C', '1463664.36', '1893464.36'),
          building('D', '1420684.36', '1850484.36'),
        ],
      });
    }

    String pct(
      YorksClientInvoiceDocumentModel m,
      YorksClientInvoiceBuildingStage s,
    ) => YorksClientInvoiceDocumentBuilder.pct(
      m.percentOfContract(s.totalAmount)!,
    );

    test('each building stage is a share of the contract', () {
      final m = signedLike();
      final supply = [
        for (final b in m.buildings)
          b.stages.firstWhere((s) => s.stageKey == 'material_supply'),
      ];
      // As printed on the signed invoice, building pages A to D.
      expect(supply.map((s) => pct(m, s)), [
        '9.01%',
        '9.01%',
        '8.51%',
        '8.26%',
      ]);
      final design = m.buildings.first.stages.first;
      expect(pct(m, design), '2.50%');
      // Not the building- or stage-based figures the PDF used to print.
      expect(pct(m, supply.first), isNot('72.11%'));
    });

    test('building values and totals are shares of the contract', () {
      final m = signedLike();
      final a = m.buildings.first;
      expect(m.percentOfContract(a.buildingValue), closeTo(25.0, 1e-9));
      expect(
        YorksClientInvoiceDocumentBuilder.pct(
          m.percentOfContract(a.totalAmount)!,
        ),
        '11.51%',
      );
      expect(
        YorksClientInvoiceDocumentBuilder.pct(
          m.percentOfContract(m.summary!.totalTotal)!,
        ),
        '44.80%',
      );
    });

    test('the building rows keep the signed invoice amounts exactly', () {
      final m = signedLike();
      final thisMonth = m.buildings
          .map((b) => double.parse(b.thisAmount.canonicalText))
          .reduce((a, b) => a + b);
      // The signed invoice's four buildings add to .44 against a .45 gross
      // (workbook rounding). The app reproduces both figures; it does not
      // invent a fils on either side.
      expect(thisMonth, closeTo(5983597.44, 0.001));
      expect(m.summary!.thisTotal.canonicalText, '5983597.45');
    });

    test('no contract value means no percentage, never a wrong one', () {
      final legacy = Map<String, dynamic>.from(_docJson())
        ..remove('summary')
        ..remove('contract_value');
      final m = YorksClientInvoiceDocumentModel.fromJson(legacy);
      expect(m.percentOfContract(m.buildings.first.totalAmount), isNull);
    });

    test('the PDF still builds with four buildings', () async {
      final bytes = await YorksClientInvoiceDocumentBuilder.build(signedLike());
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });
  });

  test(
    'legacy snapshot without summary still builds a single-page PDF',
    () async {
      final legacy = Map<String, dynamic>.from(_docJson())
        ..remove('summary')
        ..remove('buildings')
        ..remove('contract_value');
      final model = YorksClientInvoiceDocumentModel.fromJson(legacy);

      expect(model.summary, isNull);
      expect(model.buildings, isEmpty);
      final bytes = await YorksClientInvoiceDocumentBuilder.build(model);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    },
  );
}

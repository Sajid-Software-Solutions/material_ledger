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
    // Done% is a presentation-only double (500,000 / 1,000,000 = 50%).
    expect(a.donePercent, closeTo(50.0, 0.001));
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

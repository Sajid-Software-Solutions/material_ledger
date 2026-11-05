import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/accounts/domain/accounts_decimal.dart';
import 'package:material_ledger/features/accounts/domain/v2/claim_workbench_models.dart';
import 'package:material_ledger/features/accounts/domain/v2/client_invoice_document_models.dart';

YorksAccountsDecimal _d(String raw) => YorksAccountsDecimal.parse(raw);

Map<String, dynamic> _workbench() => <String, dynamic>{
  'schema_version': 1,
  'project_id': 'p1',
  'baseline_revision_id': 'rev1',
  'baseline_revision_number': 1,
  'cells': [
    {
      'progress_entry_id': 'pe-design',
      'building_scope_id': 'b01',
      'building_name': 'Building 01',
      'stage_key': 'design',
      'stage_label': 'Design',
      'stage_position': 1,
      'measurement_mode': 'percent',
      'confirmed_percent': '100.0000',
      'review_status': 'not_required',
      'record_version': 2,
      'stage_value': '100000.00',
      'eligible': '100000.00',
      'claimed': '50000.00',
      'available': '50000.00',
      'over_claimed': false,
    },
    {
      'progress_entry_id': 'pe-material',
      'building_scope_id': 'b01',
      'building_name': 'Building 01',
      'stage_key': 'material_supply',
      'stage_label': 'Material Supply',
      'stage_position': 2,
      'measurement_mode': 'items',
      'confirmed_percent': '100.0000',
      'review_status': 'not_required',
      'record_version': 2,
      'stage_value': '500000.00',
      'eligible': '500000.00',
      'claimed': '0',
      'available': '500000.00',
      'over_claimed': false,
      'items': [
        {
          'stage_item_id': 'it-a',
          'item_key': 'a',
          'item_label': 'Item A',
          'display_order': 1,
          'quantity': '10',
          'unit_code': 'Nos',
          'confirmed_qty': '10',
          'needs_review': false,
          'item_value': '300000.00',
        },
      ],
    },
  ],
  'claim': {'claim_id': 'c1', 'status': 'draft'},
  'capabilities': {'can_confirm': true},
  'commands': {'prepare_client_claim': true},
};

Map<String, dynamic> _invoiceDoc() => <String, dynamic>{
  'schema_version': 1,
  'project_id': 'p1',
  'invoice_id': 'inv1',
  'snapshot_sha256': 'abc',
  'controlled_document_id': null,
  'document': {
    'schema_version': 1,
    'invoice_reference': 'YRA32201',
    'invoice_date': '2026-08-26',
    'submission_date': '2026-08-26',
    'due_date': '2026-10-10',
    'payment_terms_days': 45,
    'currency_code': 'AED',
    'company': {'phone': '02-5509788', 'trn': '100026741700003'},
    'project': {'project_ref': 'YRA-322', 'name': 'Nexus'},
    'claim': {'claim_id': 'c1', 'claim_reference': 'CLM-A'},
    'settings': {'invoice_prefix': 'YRA322'},
    'amounts': {
      'ex_vat': '50000.00',
      'vat_rate_percent': '5.0000',
      'vat': '2500.00',
      'total_incl_vat': '52500.00',
    },
    'lines': [
      {
        'building_scope_id': 'b01',
        'building_name': 'Building 01',
        'stage_key': 'design',
        'stage_label': 'Design',
        'amount': '50000.00',
      },
    ],
  },
};

void main() {
  group('YorksAccountsWorkbench.fromJson', () {
    test('parses percent and items cells with gated money fields', () {
      final wb = YorksAccountsWorkbench.fromJson(_workbench());
      expect(wb.cells.length, 2);
      final design = wb.cells.firstWhere((c) => c.stageKey == 'design');
      expect(design.isItemsMode, isFalse);
      expect(design.eligible, _d('100000.00'));
      expect(design.available, _d('50000.00'));
      final material = wb.cells.firstWhere((c) => c.stageKey == 'material_supply');
      expect(material.isItemsMode, isTrue);
      expect(material.items.single.confirmedQty, _d('10'));
      expect(material.items.single.itemValue, _d('300000.00'));
      expect(wb.openClaimStatus, 'draft');
      expect(wb.openClaimId, 'c1');
    });

    test('omits per-cell money when values are not visible', () {
      final json = _workbench();
      for (final cell in (json['cells'] as List)) {
        final c = cell as Map<String, dynamic>;
        c.remove('stage_value');
        c.remove('eligible');
        c.remove('claimed');
        c.remove('available');
        if (c['items'] is List) {
          for (final item in (c['items'] as List)) {
            (item as Map<String, dynamic>).remove('item_value');
          }
        }
      }
      final wb = YorksAccountsWorkbench.fromJson(json);
      expect(wb.cells.first.eligible, isNull);
      expect(wb.cells.firstWhere((c) => c.isItemsMode).items.single.itemValue, isNull);
    });

    test('rejects a quantity delivered as a JSON number', () {
      final json = _workbench();
      final items = ((json['cells'] as List)[1] as Map<String, dynamic>)['items'] as List;
      (items.first as Map<String, dynamic>)['confirmed_qty'] = 10;
      expect(() => YorksAccountsWorkbench.fromJson(json), throwsFormatException);
    });
  });

  group('YorksClientInvoiceDocument.fromJson', () {
    test('parses the frozen document with exact amounts', () {
      final doc = YorksClientInvoiceDocument.fromJson(_invoiceDoc());
      expect(doc.invoiceId, 'inv1');
      expect(doc.isPreview, isFalse);
      expect(doc.document.invoiceReference, 'YRA32201');
      expect(doc.document.amounts.exVat, _d('50000.00'));
      expect(doc.document.amounts.vat, _d('2500.00'));
      expect(doc.document.amounts.totalInclVat, _d('52500.00'));
      expect(doc.document.company['phone'], '02-5509788');
      expect(doc.document.lines.single.amount, _d('50000.00'));
    });

    test('parses a preview (no invoice id)', () {
      final json = _invoiceDoc()
        ..remove('invoice_id')
        ..remove('snapshot_sha256')
        ..['preview'] = true;
      final doc = YorksClientInvoiceDocument.fromJson(json);
      expect(doc.isPreview, isTrue);
      expect(doc.invoiceId, isNull);
      expect(doc.document.amounts.totalInclVat, _d('52500.00'));
    });
  });
}

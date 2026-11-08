// R39 Accounts Workspace V2 — the Excel rounding rule on screen, the signed
// invoice layout, and History dated by when things happened.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/accounts/data/v2/client_invoice_document_builder.dart';
import 'package:material_ledger/features/accounts/domain/accounts_decimal.dart';
import 'package:material_ledger/features/accounts/domain/accounts_receivables_models.dart';
import 'package:material_ledger/features/accounts/domain/accounts_records_models.dart';
import 'package:material_ledger/features/accounts/domain/v2/claim_workbench_models.dart';
import 'package:material_ledger/features/accounts/domain/v2/claims_list_models.dart';
import 'package:material_ledger/features/accounts/domain/v2/client_invoice_document_models.dart';
import 'package:material_ledger/features/accounts/domain/v2/commercial_setup_read_models.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_history_tab.dart';
import 'package:material_ledger/features/accounts/presentation/v2/kit/accounts_v2_kit.dart';
import 'package:material_ledger/shared/models/app_language.dart';

const _en = AppLanguage.english;

/// The signed YRA32202R.1, as the server freezes it (schema 3).
Map<String, dynamic> _signedDocument() => {
  'schema_version': 3,
  'invoice_reference': 'YRA32202R.1',
  'invoice_date': '2026-09-29',
  'submission_date': '2026-09-29',
  'due_date': '2026-11-13',
  'payment_terms_days': 45,
  'currency_code': 'AED',
  'company': {
    'legal_name': 'Yorks Air Conditioning & Refrigeration LLC-SPC',
    'arabic_name': 'يوركس للتكييف والتبريد',
    'trn': '100026741700003',
    'phone': '02-5509788',
    'bank_name': 'The National Bank of Ras Al Khaimah',
    'bank_iban': 'AE640400000333702314001',
  },
  'project': {
    'project_ref': 'YRA-322',
    'name': 'SS Nexus – 132/33kV Substations',
    'contract_reference': 'N-19957.2',
  },
  'claim': {'claim_reference': 'CLM-02'},
  'settings': {
    'attention_name': 'Milan Bharatbhai',
    'scope_line': 'Supply & Installation of HVAC System',
  },
  'bill_to': {
    'name': 'M/S. Larsen & Toubro Ltd',
    'address': 'P.O. Box 30803, Abu Dhabi, U.A.E',
  },
  'references': {
    'client_trn': '100054379100003',
    'work_order_number': 'LE/LE25M294/WOD/25/000036',
    'work_order_date': '2025-08-13',
    'contract_number': 'N-19957.2',
  },
  'amounts': {
    'ex_vat': '5983597.45',
    'vat_rate_percent': '5.0000',
    'vat': '299179.87',
    'total_incl_vat': '6282777.33',
  },
  'contract_value': '17192000.00',
  'summary': {
    'contract_total': '17192000.00',
    'previous_total': '1719200.00',
    'this_total': '5983597.45',
    'total_total': '7702797.45',
    'contract_vat': '859600.00',
    'contract_grand': '18051600.00',
    'previous_vat': '85960.00',
    'previous_grand': '1805160.00',
    'this_vat': '299179.87',
    'this_grand': '6282777.33',
    'total_vat': '385139.87',
    'total_grand': '8087937.33',
    'stages': [
      {
        'stage_key': 'design',
        'stage_label': 'Cooling Load Design',
        'contract_percent': '10.0000',
        'contract_amount': '1719200.00',
        'previous_amount': '1719200.00',
        'this_amount': '0.00',
        'total_amount': '1719200.00',
      },
      {
        'stage_key': 'material_supply',
        'stage_label': 'Material Supply',
        'contract_percent': '50.0000',
        'contract_amount': '8596000.00',
        'previous_amount': '0.00',
        'this_amount': '5983597.45',
        'total_amount': '5983597.45',
      },
    ],
  },
  'buildings': [
    for (final (name, amount) in [
      ('DF3W', '1549624.36'),
      ('DF4W', '1549624.36'),
    ])
      {
        'building_scope_id': name,
        'name': name,
        'share_percent': '25.0000',
        'building_value': '4298000.00',
        'previous_amount': '429800.00',
        'this_amount': amount,
        'total_amount': '1979424.36',
        'stages': [
          {
            'stage_key': 'material_supply',
            'stage_label': 'Material Supply',
            'stage_value': '2149000.00',
            'previous_amount': '0.00',
            'this_amount': amount,
            'total_amount': amount,
          },
        ],
      },
  ],
  'lines': const [],
};

YorksAccountsActivityEntry _entry(
  String id,
  String eventType, {
  String entityId = 'x',
  String? businessDate,
  Map<String, dynamic>? context,
  Map<String, dynamic>? afterData,
  String? reason,
  DateTime? at,
}) => YorksAccountsActivityEntry(
  id: id,
  eventType: eventType,
  entityType: 'accounts_client_invoice',
  entityId: entityId,
  projectId: 'p1',
  actorAuthUserId: 'u1',
  actorDisplayName: 'Owner',
  actorExactRole: 'admin',
  occurredAt: at ?? DateTime(2026, 11, 8, 9, 30),
  reason: reason,
  afterData: afterData,
  businessDate: businessDate,
  // As the server sends it: a date the record names is also in the context.
  context: context == null
      ? null
      : {...context, 'business_date': ?businessDate},
);

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  group('Excel rounding', () {
    test('the signed YRA32202R.1 figures come out exactly', () {
      final a = accountsV2ExcelAmounts(5983597.454545454545, 5);
      expect(a.gross, 5983597.45);
      expect(a.vat, 299179.87);
      expect(a.net, 6282777.33);
      // As on the signed invoice, the total is not gross + VAT.
      expect(a.gross + a.vat, closeTo(6282777.32, 0.0001));
    });

    test('invoice #01 has no rounding to do', () {
      final a = accountsV2ExcelAmounts(1719200, 5);
      expect((a.gross, a.vat, a.net), (1719200.0, 85960.0, 1805160.0));
    });

    test('fils round halves away from zero', () {
      expect(accountsV2RoundFils(1.005), 1.01);
      expect(accountsV2RoundFils(-1.005), -1.01);
      expect(accountsV2RoundFils(62516.363636), 62516.36);
    });
  });

  group('signed invoice document', () {
    test('reads the schema-3 bill-to, references and VAT rows', () {
      final doc = YorksClientInvoiceDocumentModel.fromJson(_signedDocument());
      expect(doc.billTo['name'], 'M/S. Larsen & Toubro Ltd');
      expect(doc.references['work_order_number'], 'LE/LE25M294/WOD/25/000036');
      expect(doc.summary!.hasVatRows, isTrue);
      expect(doc.summary!.previousGrand!.canonicalText, '1805160');
      expect(doc.summary!.totalGrand!.canonicalText, '8087937.33');
    });

    test('an older document without them still reads', () {
      final json = _signedDocument()
        ..remove('bill_to')
        ..remove('references');
      (json['summary'] as Map).remove('this_vat');
      final doc = YorksClientInvoiceDocumentModel.fromJson(json);
      expect(doc.billTo, isEmpty);
      expect(doc.summary!.hasVatRows, isFalse);
    });

    test('amount in words and dates read as on the signed invoices', () {
      expect(
        YorksClientInvoiceDocumentBuilder.amountInWords(
          YorksAccountsDecimal.parse('6282777.33'),
        ),
        'UAE Dirham Six Million Two Hundred Eighty Two Thousand Seven Hundred '
        'Seventy Seven & 33/100 Only',
      );
      expect(
        YorksClientInvoiceDocumentBuilder.amountInWords(
          YorksAccountsDecimal.parse('1805160.00'),
        ),
        'UAE Dirham One Million Eight Hundred Five Thousand One Hundred Sixty Only',
      );
      expect(
        YorksClientInvoiceDocumentBuilder.dotDate('2026-09-29'),
        '29.09.2026',
      );
    });

    test('builds the invoice, main summary and building pages', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final bytes = await YorksClientInvoiceDocumentBuilder.build(
        YorksClientInvoiceDocumentModel.fromJson(_signedDocument()),
      );
      expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
      expect(bytes.length, greaterThan(20000));
    });
  });

  group('models', () {
    test('exact amounts, claim numbers, invoice dates and party ids parse', () {
      final cell = YorksAccountsWorkbenchCell.fromJson({
        'progress_entry_id': 'p',
        'building_scope_id': 'b',
        'building_name': 'DF3W',
        'stage_key': 'material_supply',
        'stage_position': 2,
        'measurement_mode': 'items',
        'confirmed_percent': '72.1091',
        'review_status': 'not_required',
        'record_version': 1,
        'available_exact': '1549624.363636363636',
        'this_claim_amount_exact': '1549624.363636363636',
      });
      expect(cell.thisClaimAmountExact!.canonicalText, '1549624.363636363636');

      final claim = YorksAccountsClaimSummary.fromJson({
        'claim_id': 'c',
        'claim_number': 2,
      });
      expect(claim.claimNumber, 2);

      final party = YorksAccountsSetupReadParty.fromJson({
        'party_id': 'lt',
        'name': 'L&T',
      });
      expect(party.partyId, 'lt');

      final entry = YorksAccountsActivityEntry.fromRpcJson({
        'id': '1',
        'event_type': 'accounts.client_invoice.submitted',
        'entity_type': 'accounts_client_invoice',
        'entity_id': 'i',
        'project_id': 'p',
        'actor_auth_user_id': 'u',
        'actor_display_name': 'Owner',
        'actor_exact_role': 'admin',
        'occurred_at': '2026-11-08T05:00:00Z',
        'business_date': '2026-01-19',
        'context': {'invoice_reference': 'YRA32201'},
      });
      expect(entry.businessDate, '2026-01-19');
      expect(entry.context!['invoice_reference'], 'YRA32201');
    });

    test('an invoice read carries its invoice date', () {
      final json = <String, dynamic>{
        'invoice_id': 'i',
        'project_id': 'p',
        'claim_id': 'c',
        'invoice_reference': 'YRA32201',
        'status': 'submitted',
        'submission_date': '2026-01-19',
        'due_date': '2026-03-05',
        'invoice_date': '2026-01-19',
        'record_version': 1,
        'created_by_auth_user_id': 'u',
        'created_by_exact_role': 'admin',
        'created_at': '2026-11-08T05:00:00Z',
        'updated_at': '2026-11-08T05:00:00Z',
      };
      final invoice = YorksAccountsClientInvoice.fromRpcJson(
        json,
        canViewValues: false,
      );
      expect(invoice.invoiceDate?.postgresText, '2026-01-19');
    });
  });

  group('History', () {
    YorksAccountsActivityProjection projection() =>
        YorksAccountsActivityProjection(
          projectId: 'p1',
          total: 9,
          limit: 100,
          offset: 0,
          entries: [
            _entry(
              'c1',
              'accounts.client_pdc.received',
              entityId: 'pdc1',
              businessDate: '2026-11-01',
              context: {
                'cheque_number': '004893',
                'invoice_reference': 'YRA32202R.1',
                'cheque_date': '2026-11-13',
                'amount': '6282777.33',
              },
            ),
            _entry(
              'c0',
              'accounts.client_pdc.created',
              entityId: 'pdc1',
              businessDate: '2026-11-01',
              context: {
                'cheque_number': '004893',
                'invoice_reference': 'YRA32202R.1',
              },
            ),
            _entry(
              'v1',
              'accounts.client_certification.recorded',
              businessDate: '2026-10-20',
              context: {
                'invoice_reference': 'YRA32202R.1',
                'bill_to': 'M/S. Larsen & Toubro Ltd',
                'certified_ex_vat': '5983597.45',
                'invoiced_ex_vat': '5983597.45',
              },
            ),
            _entry(
              'i2',
              'accounts.client_invoice.submitted',
              entityId: 'inv1',
              businessDate: '2026-01-19',
              context: {
                'invoice_reference': 'YRA32201',
                'claim_number': 1,
                'total_incl_vat': '1805160.00',
              },
            ),
            _entry(
              'i1',
              'accounts.client_invoice.draft_created',
              entityId: 'inv1',
              businessDate: '2026-01-19',
              context: {'invoice_reference': 'YRA32201', 'claim_number': 1},
            ),
            for (final n in ['p1', 'p2', 'p3', 'p4'])
              _entry(
                n,
                'accounts_progress_confirmed',
                entityId: n,
                businessDate: '2026-01-19',
                context: {'claim_number': 1},
              ),
          ],
        );

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1300, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _wrap(AccountsV2HistoryTab(projection: projection(), language: _en)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('names entries by their invoice, cheque and claim', (
      tester,
    ) async {
      await pump(tester);
      expect(
        find.text('Cheque 004893 received for YRA32202R.1'),
        findsOneWidget,
      );
      expect(
        find.text('YRA32202R.1 certified by M/S. Larsen & Toubro Ltd'),
        findsOneWidget,
      );
      expect(find.text('Invoice YRA32201 issued'), findsOneWidget);
      expect(
        find.textContaining('Certified AED 5,983,597.45 (full amount)'),
        findsOneWidget,
      );
      expect(find.textContaining('dated 13 Nov 2026'), findsOneWidget);
    });

    testWidgets('folds the steps a later entry covers', (tester) async {
      await pump(tester);
      // The cheque's "added" step and the invoice's draft step fold away.
      expect(find.textContaining('Cheque 004893 added'), findsNothing);
      expect(find.text('Invoice prepared'), findsNothing);
      // Four building stages of claim #01 are one line.
      expect(find.text('Progress confirmed for claim #01'), findsOneWidget);
      expect(find.textContaining('4 building stages'), findsOneWidget);
    });

    testWidgets('dates entries by when they happened', (tester) async {
      await pump(tester);
      expect(find.textContaining('19 Jan 2026'), findsWidgets);
      expect(find.textContaining('Recorded 08 Nov 2026'), findsWidgets);
    });

    Future<void> pumpOne(
      WidgetTester tester,
      YorksAccountsActivityEntry entry,
    ) async {
      tester.view.physicalSize = const Size(1300, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _wrap(
          AccountsV2HistoryTab(
            projection: YorksAccountsActivityProjection(
              projectId: 'p1',
              total: 1,
              limit: 100,
              offset: 0,
              entries: [entry],
            ),
            language: _en,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('an entry with no date of its own shows when it was recorded', (
      tester,
    ) async {
      // Exported at 00:58 local time on 27 Sep; the server dates it 26 Sep
      // (UAE time) because the export names no date of its own.
      await pumpOne(
        tester,
        YorksAccountsActivityEntry(
          id: 'e1',
          eventType: 'accounts.export.generated',
          entityType: 'accounts_export',
          entityId: 'x1',
          projectId: 'p1',
          actorAuthUserId: 'u1',
          actorDisplayName: 'Owner',
          actorExactRole: 'admin',
          occurredAt: DateTime(2026, 9, 27, 0, 58),
          businessDate: '2026-09-26',
        ),
      );
      expect(find.textContaining('27 Sep 2026'), findsOneWidget);
      expect(find.textContaining('00:58'), findsOneWidget);
      expect(find.textContaining('26 Sep 2026'), findsNothing);
      expect(find.textContaining('Recorded'), findsNothing);
    });

    testWidgets('an import names the workbook it came from', (tester) async {
      await pumpOne(
        tester,
        _entry(
          's1',
          'accounts.source_import.applied',
          reason: 'YRA-322 history from the signed invoices',
          afterData: {'original_file_name': 'INVOICE#02R.1.xlsx'},
        ),
      );
      expect(
        find.text(
          'INVOICE#02R.1.xlsx · YRA-322 history from the signed invoices',
        ),
        findsOneWidget,
      );
    });
  });

  group('KPI row', () {
    testWidgets('six tiles that do not fit one row sit 3 + 3', (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountsV2KpiRow(
              children: [
                for (var i = 0; i < 6; i++)
                  SizedBox(key: ValueKey('k$i'), height: 40),
              ],
            ),
          ),
        ),
      );
      final first = tester.getTopLeft(find.byKey(const ValueKey('k0')));
      final third = tester.getTopLeft(find.byKey(const ValueKey('k2')));
      final fourth = tester.getTopLeft(find.byKey(const ValueKey('k3')));
      expect(third.dy, first.dy);
      expect(fourth.dy, greaterThan(first.dy));
      expect(fourth.dx, first.dx);
    });
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/accounts/domain/accounts_decimal.dart';
import 'package:material_ledger/features/accounts/domain/accounts_receivables_inputs.dart';
import 'package:material_ledger/features/accounts/domain/accounts_receivables_models.dart';
import 'package:material_ledger/features/accounts/domain/accounts_supplier_models.dart';
import 'package:material_ledger/features/accounts/domain/v2/accounts_workspace_models.dart';
import 'package:material_ledger/features/accounts/domain/v2/claim_workbench_models.dart';
import 'package:material_ledger/features/accounts/domain/v2/claims_list_models.dart';
import 'package:material_ledger/features/accounts/domain/v2/variations_models.dart';
import 'package:material_ledger/features/accounts/domain/v2/commercial_setup_read_models.dart';
import 'package:material_ledger/features/accounts/domain/accounts_records_models.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_claims_tab.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_common.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_contract_tab.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_history_tab.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_invoices_tab.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_summary_tab.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_supplier_tab.dart';
import 'package:material_ledger/shared/models/app_language.dart';

const _en = AppLanguage.english;

Map<String, dynamic> _summaryJson() => {
  'schema_version': 1,
  'project_id': 'p1',
  'project_reference': 'YRA-322',
  'project_name': 'Tower A',
  'has_baseline': true,
  'capabilities': {
    'view_project_accounts': true,
    'view_project_commercial_values': true,
    'view_supplier_costs': true,
  },
  'steps': [
    {
      'key': 'setup',
      'state': 'done',
      'detail': {
        'contract_value': '17192000.00',
        'building_count': 4,
        'stage_count': 5,
      },
    },
    {
      'key': 'progress',
      'state': 'done',
      'detail': {'claim_reference': 'Claim #03', 'claim_gross': '27507.00'},
    },
    {
      'key': 'invoice',
      'state': 'current',
      'detail': {'issued_count': 2, 'latest_reference': 'YRA32202R.1'},
    },
    {
      'key': 'paid',
      'state': '',
      'detail': {'received': '1000000.00', 'to_come': '17051600.00'},
    },
  ],
  'badges': {'claims_draft': true, 'supplier_count': 2},
  'attention': [
    {
      'severity': 'pri',
      'kind': 'awaiting_certification',
      'action_key': 'certify',
      'target_type': 'invoice',
      'target_id': 'i1',
    },
  ],
  'money_flow': {
    'paid': '1000000.00',
    'invoiced_waiting': '700000.00',
    'done_not_invoiced': '250000.00',
    'remaining': '15242000.00',
  },
  'kpis': {
    'contract_value': '17192000.00',
    'contract_incl_vat': '18051600.00',
    'invoiced': '1700000.00',
    'received': '1000000.00',
    'certified': '1600000.00',
    'outstanding': '700000.00',
    'cheques_in_hand': '200000.00',
    'done_not_invoiced': '250000.00',
  },
  'heatmap': [
    {
      'building_scope_id': 'b01',
      'building_name': 'Block A',
      'stage_key': 'material_supply',
      'stage_label': 'Material Supply',
      'stage_value': '2149000.00',
      'invoiced_amount': '1074500.00',
      'invoiced_percent': '50.00',
    },
    {
      'building_scope_id': 'b02',
      'building_name': 'Block B',
      'stage_key': 'material_supply',
      'stage_label': 'Material Supply',
      'stage_value': '2149000.00',
      'invoiced_amount': '0.00',
      'invoiced_percent': '0.00',
    },
  ],
  'supplier': {
    'billed': '900000.00',
    'paid': '600000.00',
    'unpaid': '300000.00',
    'overdue_count': 2,
  },
  'cash': {
    'received': '1000000.00',
    'paid_to_suppliers': '600000.00',
    'net': '400000.00',
  },
};

Map<String, dynamic> _contractJson() => {
  'schema_version': 1,
  'project_id': 'p1',
  'project_reference': 'YRA-322',
  'project_name': 'Tower A',
  'has_baseline': true,
  'can_configure': true,
  'capabilities': {
    'view_project_accounts': true,
    'view_project_commercial_values': true,
    'configure_project_commercials': true,
  },
  'profile_version': 1,
  'revision_number': 1,
  'currency_code': 'AED',
  'contract_value': '17192000.00',
  'contract_incl_vat': '18051600.00',
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
    for (final b in ['Block A', 'Block B', 'Block C', 'Block D'])
      {
        'project_scope_id': b,
        'name': b,
        'scope_kind': 'building',
        'allocation_percent': '25.0000',
        'value': '4298000.00',
      },
  ],
  'stages': [
    {
      'stage_key': 'design',
      'stage_name': 'Design',
      'display_order': 1,
      'measurement_mode': 'percent',
      'allocation_percent': '10.0000',
      'value': '1719200.00',
    },
    {
      'stage_key': 'material_supply',
      'stage_name': 'Material Supply',
      'display_order': 2,
      'measurement_mode': 'percent',
      'allocation_percent': '50.0000',
      'value': '8596000.00',
    },
    {
      'stage_key': 'installation',
      'stage_name': 'Installation',
      'display_order': 3,
      'measurement_mode': 'percent',
      'allocation_percent': '30.0000',
      'value': '5157600.00',
    },
    {
      'stage_key': 'commissioning_handover',
      'stage_name': 'Commissioning and Handover',
      'display_order': 4,
      'measurement_mode': 'percent',
      'allocation_percent': '5.0000',
      'value': '859600.00',
    },
    {
      'stage_key': 'energizing',
      'stage_name': 'Energizing',
      'display_order': 5,
      'measurement_mode': 'percent',
      'allocation_percent': '5.0000',
      'value': '859600.00',
    },
  ],
  'items': <dynamic>[],
  'parties': {
    'client': {
      'name': 'M/S. Larsen & Toubro Ltd',
      'address': 'P.O. Box 23200, Abu Dhabi',
      'contact_name': 'Eng. Rashid',
      'contact_phone': '+971 2 555 0100',
      'contact_email': null,
    },
    'main_contractor': {
      'name': 'Yorks AC & Ref.',
      'address': 'P.O. Box 4757, Abu Dhabi',
      'contact_name': 'Omar',
      'contact_phone': null,
      'contact_email': 'omar@yorks.ae',
    },
  },
  'references': {
    'client_trn': '100123456700003',
    'work_order_number': 'WO-2026-0042',
    'work_order_date': '2026-06-01',
    'contract_number': 'N-19957.2',
    'retention_percent': '10.0000',
  },
};

Map<String, dynamic> _workbenchJson() => {
  'schema_version': 1,
  'project_id': 'p1',
  'baseline_revision_id': 'rev1',
  'baseline_revision_number': 1,
  'capabilities': {'can_view_values': true, 'can_confirm': true},
  'commands': <String, dynamic>{},
  'cells': [
    {
      'progress_entry_id': 'pe-design',
      'building_scope_id': 'b01',
      'building_name': 'Block A',
      'stage_key': 'design',
      'stage_label': 'Design',
      'stage_position': 1,
      'measurement_mode': 'percent',
      'confirmed_percent': '100.0000',
      'review_status': 'not_required',
      'record_version': 1,
      'over_claimed': false,
      'stage_value': '429800.00',
      'eligible': '429800.00',
      'claimed': '429800.00',
      'available': '0.00',
    },
    {
      'progress_entry_id': 'pe-material',
      'building_scope_id': 'b01',
      'building_name': 'Block A',
      'stage_key': 'material_supply',
      'stage_label': 'Material Supply',
      'stage_position': 2,
      'measurement_mode': 'percent',
      'confirmed_percent': '50.0000',
      'review_status': 'not_required',
      'record_version': 1,
      'over_claimed': false,
      'stage_value': '2149000.00',
      'eligible': '1074500.00',
      'claimed': '0.00',
      'available': '1074500.00',
    },
  ],
  'claim': {
    'claim_id': 'c1',
    'claim_reference': 'YRA322-CLM-02',
    'status': 'draft',
    'record_version': 1,
    'claim_period_start': '2026-08-01',
    'claim_period_end': '2026-08-25',
    'claimed_ex_vat': '1504300.00',
    'vat_amount': '75215.00',
    'net_payable': '1579515.00',
    'contract_value': '17192000.00',
    'this_claim_percent': '8.8',
    'lines': [
      {'progress_entry_id': 'pe-material'},
    ],
  },
};

Map<String, dynamic> _historyJson() => {
  'project_id': 'p1',
  'total': 3,
  'limit': 50,
  'offset': 0,
  'entries': [
    {
      'id': '1',
      'event_type': 'claim_submitted',
      'entity_type': 'accounts_client_claim',
      'entity_id': 'c1',
      'project_id': 'p1',
      'actor_auth_user_id': 'u1',
      'actor_display_name': 'Sara (PM)',
      'actor_exact_role': 'project_manager',
      'occurred_at': '2026-08-26T10:30:00Z',
      'reason': 'Monthly claim #02',
    },
    {
      'id': '2',
      'event_type': 'invoice_issued',
      'entity_type': 'accounts_client_invoice',
      'entity_id': 'i1',
      'project_id': 'p1',
      'actor_auth_user_id': 'u2',
      'actor_display_name': 'Omar (Accountant)',
      'actor_exact_role': 'accountant',
      'occurred_at': '2026-08-26T11:00:00Z',
      'reason': 'YRA322-02 issued',
    },
    {
      'id': '3',
      'event_type': 'supplier_bill_approved',
      'entity_type': 'accounts_supplier_bill',
      'entity_id': 'sb1',
      'project_id': 'p1',
      'actor_auth_user_id': 'u2',
      'actor_display_name': 'Omar (Accountant)',
      'actor_exact_role': 'accountant',
      'occurred_at': '2026-08-27T09:15:00Z',
      'reason': 'Cool Air Co INV-5001',
    },
  ],
};

Widget _summaryTab() => AccountsV2SummaryTab(
  workspace: YorksAccountsWorkspace.fromJson(_summaryJson()),
  language: _en,
  format: const AccountsV2Format(),
  onOpenTab: (_) {},
  onAttentionAction: (_) {},
  onOpenCell: (_, _) {},
);

Widget _contractTab() => AccountsV2ContractTab(
  setup: YorksAccountsCommercialSetupRead.fromJson(_contractJson()),
  language: _en,
  canEdit: true,
  onSave: (_) async => null,
  onSaveReferences:
      ({
        String? clientTrn,
        String? workOrderNumber,
        String? workOrderDate,
        String? contractNumber,
        String? retentionPercent,
        int? expectedProfileVersion,
      }) async => null,
  variations: [
    YorksAccountsVariation.fromJson(const {
      'variation_id': 'v1',
      'vo_number': 'VO-01',
      'description': 'Extra ductwork to Block C',
      'amount': '45000.00',
      'status': 'approved',
      'record_version': 1,
    }),
    YorksAccountsVariation.fromJson(const {
      'variation_id': 'v2',
      'vo_number': 'VO-02',
      'description': 'Revised BMS controls',
      'amount': '12000.00',
      'status': 'pending',
      'record_version': 1,
    }),
  ],
  onSaveVariation:
      ({
        String? variationId,
        required String voNumber,
        String? description,
        String? amount,
        required String status,
        int? expectedVersion,
      }) async => null,
);

Widget _claimsTab() => AccountsV2ClaimsTab(
  workbench: YorksAccountsWorkbench.fromJson(_workbenchJson()),
  language: _en,
  claims: [
    YorksAccountsClaimSummary.fromJson(const {
      'claim_id': 'c1',
      'claim_reference': 'YRA322-CLM-02',
      'status': 'draft',
      'claim_period_start': '2026-08-01',
      'claim_period_end': '2026-08-25',
      'claimed_ex_vat': '1504300.00',
      'record_version': 2,
    }),
    YorksAccountsClaimSummary.fromJson(const {
      'claim_id': 'c0',
      'claim_reference': 'YRA322-CLM-01',
      'status': 'invoiced',
      'claim_period_start': '2026-07-01',
      'claim_period_end': '2026-07-25',
      'claimed_ex_vat': '1000000.00',
      'record_version': 3,
    }),
  ],
  onSelectClaim: (_) {},
);

Widget _historyTab() => AccountsV2HistoryTab(
  projection: YorksAccountsActivityProjection.fromRpcJson(_historyJson()),
  language: _en,
  files: const [
    (
      name: 'YRA322-02 tax invoice.pdf',
      reference: 'YRA322-02',
      uploadedBy: 'Omar (Accountant)',
    ),
    (
      name: 'Cool Air Co INV-5001.pdf',
      reference: 'INV-5001',
      uploadedBy: 'Omar (Accountant)',
    ),
  ],
);

YorksAccountsDecimal _d(String raw) => YorksAccountsDecimal.parse(raw);

YorksAccountsInvoicesProjection _invoicesProjection() =>
    YorksAccountsInvoicesProjection(
      schemaVersion: 1,
      projectId: 'p1',
      invoices: [
        YorksAccountsClientInvoiceSummary(
          invoiceId: 'i1',
          claimId: 'c1',
          invoiceReference: 'YRA322-01',
          status: YorksAccountsInvoiceStatus.certified,
          claimedExVat: _d('1000000.00'),
          certifiedExVat: _d('900000.00'),
          totalInclVat: _d('1050000.00'),
          amountPaidTillDate: _d('500000.00'),
          stillDue: _d('550000.00'),
          pdcExposure: _d('200000.00'),
          submissionDate: YorksAccountsDate.parse('2026-08-26'),
          dueDate: YorksAccountsDate.parse('2026-10-10'),
          dueState: YorksAccountsDueState.overdue,
          recordVersion: 1,
          updatedAt: DateTime.utc(2026, 8, 26),
        ),
        YorksAccountsClientInvoiceSummary(
          invoiceId: 'i2',
          claimId: 'c0',
          invoiceReference: 'YRA322-00',
          status: YorksAccountsInvoiceStatus.paid,
          claimedExVat: _d('800000.00'),
          certifiedExVat: _d('800000.00'),
          totalInclVat: _d('840000.00'),
          amountPaidTillDate: _d('840000.00'),
          stillDue: _d('0.00'),
          pdcExposure: _d('0.00'),
          submissionDate: YorksAccountsDate.parse('2026-07-10'),
          dueDate: YorksAccountsDate.parse('2026-08-24'),
          dueState: YorksAccountsDueState.onTrack,
          recordVersion: 3,
          updatedAt: DateTime.utc(2026, 8, 20),
        ),
      ],
      nextCursor: null,
      capabilities: const YorksAccountsReceivablesCapabilities(
        canViewValues: true,
        prepareClientClaim: false,
        manageClientInvoices: false,
        recordClientCertification: false,
        recordClientPayment: false,
        managePdc: false,
      ),
      commands: const YorksAccountsReceivablesCommands(
        createClaimDraft: false,
        editClaimDraft: false,
        submitClaimToAccounts: false,
        cancelClaim: false,
        createInvoiceDraft: false,
        submitInvoice: false,
        returnInvoice: false,
        cancelInvoice: false,
        recordCertification: false,
        recordPayment: false,
        reversePayment: false,
        createPdc: false,
        transitionPdc: false,
        replacePdc: false,
      ),
    );

YorksAccountsSupplierBillsProjection _supplierProjection() =>
    YorksAccountsSupplierBillsProjection(
      projectId: 'p1',
      items: [
        YorksAccountsSupplierBill(
          supplierBillId: 'sb1',
          projectId: 'p1',
          supplierId: 'sup1',
          supplierName: 'Cool Air Co',
          supplierInvoiceReference: 'INV-5001',
          invoiceDate: YorksAccountsDate.parse('2026-08-01'),
          dueDate: YorksAccountsDate.parse('2026-09-01'),
          exVatAmount: _d('100000.00'),
          vatRatePercent: _d('5.0000'),
          vatAmount: _d('5000.00'),
          totalInclVat: _d('105000.00'),
          poLpoReference: 'PO-77',
          poLpoDocumentId: null,
          acceptedReceiptReviewId: null,
          acceptedDeliveryReference: 'DO-3001',
          acceptedDelivery: null,
          supplierInvoiceDocumentId: null,
          explicitMismatchReason: null,
          matchStatus: YorksAccountsSupplierMatchStatus.matched,
          status: YorksAccountsSupplierBillStatus.approved,
          paymentStatus: YorksAccountsSupplierPaymentStatus.partiallyPaid,
          paidAmount: _d('40000.00'),
          outstandingAmount: _d('65000.00'),
          approvalAdminExceptionReason: null,
          approvedAt: DateTime.utc(2026, 8, 2),
          approvedByAuthUserId: 'u',
          approvedByExactRole: 'accountant',
          cancelledAt: null,
          cancellationReason: null,
          notes: null,
          recordVersion: 1,
          createdByAuthUserId: 'u',
          createdByExactRole: 'accountant',
          createdAt: DateTime.utc(2026, 8, 1),
          updatedAt: DateTime.utc(2026, 8, 2),
        ),
      ],
      nextCursor: null,
      capabilities: const YorksAccountsSupplierCapabilities(
        manageSupplierBills: false,
        approveSupplierBillPayment: false,
        viewSupplierCosts: true,
      ),
      commands: const YorksAccountsSupplierCommands(
        createBill: false,
        editBill: false,
        approveBill: false,
        recordPayment: false,
        reversePayment: false,
        cancelBill: false,
      ),
    );

Widget _invoicesTab() =>
    AccountsV2InvoicesTab(projection: _invoicesProjection(), language: _en);

Widget _supplierTab() => AccountsV2SupplierTab(
  projection: _supplierProjection(),
  language: _en,
  invoicedTotal: YorksAccountsDecimal.parse('300000.00'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadGoldenFonts);

  final tabs = <String, Widget Function()>{
    'summary': _summaryTab,
    'contract': _contractTab,
    'claims': _claimsTab,
    'invoices': _invoicesTab,
    'supplier': _supplierTab,
    'history': _historyTab,
  };
  final viewports = <String, Size>{
    'desktop': const Size(1440, 1200),
    'mobile': const Size(360, 1200),
  };

  for (final tab in tabs.entries) {
    for (final vp in viewports.entries) {
      testWidgets('accounts v2 ${tab.key} ${vp.key}', (tester) async {
        tester.view.physicalSize = vp.value;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(body: tab.value()),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/accounts_v2/${tab.key}_${vp.key}.png'),
        );
      });
    }
  }
}

Future<void> _loadGoldenFonts() async {
  final nexus = FontLoader('NexusSans')
    ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
  final arabic = FontLoader('NotoSansArabic')
    ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
  final cache = _flutterCacheDirectory();
  final icons = await File(
    '${cache.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ).readAsBytes();
  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(icons)));
  await Future.wait([nexus.load(), arabic.load(), materialIcons.load()]);
}

Directory _flutterCacheDirectory() {
  var directory = File(Platform.resolvedExecutable).parent;
  for (var level = 0; level < 8; level++) {
    if (directory.path.endsWith('${Platform.pathSeparator}cache')) {
      return directory;
    }
    directory = directory.parent;
  }
  throw StateError('Could not locate the Flutter cache from the test runner');
}

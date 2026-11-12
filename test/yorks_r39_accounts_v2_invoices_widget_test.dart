import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/features/accounts/application/accounts_providers.dart';
import 'package:material_ledger/features/accounts/application/accounts_receivables_providers.dart';
import 'package:material_ledger/features/accounts/data/accounts_receivables_repository.dart';
import 'package:material_ledger/features/accounts/domain/accounts_decimal.dart';
import 'package:material_ledger/features/accounts/domain/accounts_receivables_inputs.dart';
import 'package:material_ledger/features/accounts/domain/accounts_receivables_models.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_common.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_invoices_tab.dart';
import 'package:material_ledger/features/accounts/presentation/v2/kit/accounts_v2_kit.dart';
import 'package:material_ledger/features/accounts/presentation/v2/yorks_accounts_workspace_v2_screen.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/accounts_v2_golden_fonts.dart';

YorksAccountsDecimal _d(String raw) => YorksAccountsDecimal.parse(raw);

YorksAccountsReceivablesCapabilities _caps({
  bool values = true,
  bool cert = false,
  bool pay = false,
  bool pdc = false,
}) => YorksAccountsReceivablesCapabilities(
  canViewValues: values,
  prepareClientClaim: false,
  manageClientInvoices: false,
  recordClientCertification: cert,
  recordClientPayment: pay,
  managePdc: pdc,
);

const _cmds = YorksAccountsReceivablesCommands(
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
);

YorksAccountsClientInvoiceSummary _invoice({
  YorksAccountsInvoiceStatus status = YorksAccountsInvoiceStatus.certified,
  String certified = '900000.00',
  String id = 'i1',
  String reference = 'YRA322-01',
  String? replaces,
}) => YorksAccountsClientInvoiceSummary(
  invoiceId: id,
  claimId: 'c1',
  invoiceReference: reference,
  replacesReference: replaces,
  status: status,
  claimedExVat: _d('1000000.00'),
  certifiedExVat: _d(certified),
  totalInclVat: _d('1050000.00'),
  amountPaidTillDate: _d('500000.00'),
  stillDue: _d('550000.00'),
  pdcExposure: _d('200000.00'),
  submissionDate: YorksAccountsDate.parse('2026-08-26'),
  dueDate: YorksAccountsDate.parse('2026-10-10'),
  dueState: YorksAccountsDueState.overdue,
  recordVersion: 1,
  updatedAt: DateTime.utc(2026, 8, 26),
);

YorksAccountsInvoicesProjection _projection({
  bool values = true,
  bool cert = false,
  bool pay = false,
  bool pdc = false,
  List<YorksAccountsClientInvoiceSummary>? invoices,
}) => YorksAccountsInvoicesProjection(
  schemaVersion: 1,
  projectId: 'p1',
  invoices: invoices ?? [_invoice()],
  nextCursor: null,
  capabilities: _caps(values: values, cert: cert, pay: pay, pdc: pdc),
  commands: _cmds,
);

Map<String, dynamic> _detailClaimJson() => {
  'claim_id': 'c1',
  'project_id': 'p1',
  'baseline_revision_id': 'rev1',
  'claim_reference': 'CLM-01',
  'claim_period_start': '2026-08-01',
  'claim_period_end': '2026-08-25',
  'status': 'invoiced',
  'admin_exception_reason': null,
  'notes': null,
  'is_stale': false,
  'stale_reason': null,
  'record_version': 2,
  'created_by_auth_user_id': 'actor-1',
  'created_by_exact_role': 'project_engineer',
  'ready_for_accounts_at': null,
  'cancelled_at': null,
  'cancellation_reason': null,
  'claimed_ex_vat': '1000000.00',
  'lines': const <Map<String, dynamic>>[],
  'created_at': '2026-08-26T09:00:00Z',
  'updated_at': '2026-08-26T09:15:00Z',
};

Map<String, dynamic> _detailInvoiceJson({required String status}) => {
  'invoice_id': 'i1',
  'project_id': 'p1',
  'claim_id': 'c1',
  'invoice_reference': 'YRA322-01',
  'status': status,
  'claimed_ex_vat': '1000000.00',
  'vat_rate_percent_snapshot': '5.0000',
  'vat_amount_snapshot': '50000.00',
  'total_incl_vat_snapshot': '1050000.00',
  'payment_terms_days_snapshot': 45,
  'reminder_lead_days_snapshot': 7,
  'submission_date': '2026-08-26',
  'due_date': '2026-10-10',
  'due_state': 'on_track',
  'record_version': 2,
  'certified_ex_vat': '0.00',
  'certified_incl_vat': '0.00',
  'paid_amount': '0.00',
  'still_due': '1050000.00',
  'pdc_exposure': '0.00',
  'retention_snapshot': '0.00',
  'created_at': '2026-08-26T09:00:00Z',
  'updated_at': '2026-08-26T09:15:00Z',
};

Map<String, dynamic> _paymentJson({
  String id = 'pay1',
  String? pdcId,
  String method = 'bank_transfer',
}) => {
  'payment_id': id,
  'entry_kind': 'receipt',
  'original_payment_id': null,
  'pdc_id': pdcId,
  'payment_date': '2026-09-25',
  'payment_method': method,
  'payment_reference': 'BANK-1',
  'amount': '1000.00',
  'reason': null,
  'actor_auth_user_id': null,
  'actor_exact_role': 'accountant',
  'created_at': '2026-09-25T10:00:00Z',
};

Map<String, dynamic> _certificationJson({
  required String id,
  required int revision,
  required String reference,
}) => {
  'certification_id': id,
  'revision_number': revision,
  'certification_reference': reference,
  'certification_date': '2026-09-20',
  'certified_ex_vat': '5000.00',
  'certified_vat': '250.00',
  'certified_incl_vat': '5250.00',
  'difference_reason': null,
  'actor_auth_user_id': null,
  'actor_exact_role': 'accountant',
  'created_at': '2026-09-20T10:00:00Z',
};

YorksAccountsInvoiceDetailProjection _detail({
  required String status,
  List<Map<String, dynamic>> payments = const [],
  List<Map<String, dynamic>> certifications = const [],
  List<Map<String, dynamic>> pdcs = const [],
}) => YorksAccountsInvoiceDetailProjection.fromRpcJson({
  'schema_version': 3,
  'project_id': 'p1',
  'invoice': _detailInvoiceJson(status: status),
  'claim': _detailClaimJson(),
  'certifications': certifications,
  'payments': payments,
  'pdcs': pdcs,
  'due_state': 'on_track',
  'capabilities': const {
    'view_project_commercial_values': true,
    'prepare_client_claim': true,
    'manage_client_invoices': true,
    'record_client_certification': true,
    'record_client_payment': true,
    'manage_pdc': true,
  },
  'commands': const {
    'create_claim_draft': true,
    'edit_claim_draft': true,
    'submit_claim_to_accounts': true,
    'cancel_claim': true,
    'create_invoice_draft': true,
    'submit_invoice': true,
    'return_invoice': true,
    'cancel_invoice': true,
    'record_certification': true,
    'record_payment': true,
    'reverse_payment': true,
    'create_pdc': true,
    'transition_pdc': true,
    'replace_pdc': true,
    'edit_pdc': true,
    'correct_payment': true,
    'correct_certification': true,
  },
});

final class _FakeReceivables implements YorksAccountsReceivablesRepository {
  _FakeReceivables(this.projection);
  final YorksAccountsInvoicesProjection projection;

  @override
  Future<YorksAccountsInvoicesProjection> listInvoices(
    String projectId, {
    YorksAccountsInvoiceStatus? status,
    YorksAccountsDueState? dueState,
    YorksAccountsCompositeCursor? before,
    int limit = 50,
  }) async => projection;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RefusingReceivables implements YorksAccountsReceivablesRepository {
  @override
  Future<YorksAccountsInvoicesProjection> listInvoices(
    String projectId, {
    YorksAccountsInvoiceStatus? status,
    YorksAccountsDueState? dueState,
    YorksAccountsCompositeCursor? before,
    int limit = 50,
  }) async =>
      throw const YorksV1DomainException(YorksV1DomainErrorCode.unauthorized);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _surface(WidgetTester tester, {double width = 1400}) {
  tester.view.physicalSize = Size(width, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Map<String, dynamic> _pdcJson() => {
  'pdc_id': 'pdc1',
  'project_id': 'p1',
  'invoice_id': 'i1',
  'cheque_number': '004517',
  'cheque_date': '2026-09-20',
  'amount': '1000.00',
  'bank_name': 'Sample bank',
  'received_date': '2026-09-10',
  'status': 'cleared',
  'replaces_pdc_id': null,
  'replaced_by_pdc_id': null,
  'action_required': false,
  'last_action_reason': null,
  'record_version': 3,
  'created_at': '2026-09-10T10:00:00Z',
  'updated_at': '2026-09-25T10:00:00Z',
};

Finder _button(String label) => find.widgetWithText(AccountsV2Button, label);

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Pumps the tab and opens the invoice drawer.
Future<void> _openDrawer(
  WidgetTester tester, {
  YorksAccountsInvoicesProjection? projection,
  YorksAccountsInvoiceDetailProjection? detail,
  YorksCertifyAction? onCertify,
  YorksPayAction? onPay,
  YorksReversePaymentAction? onReverse,
  YorksCorrectPaymentAction? onCorrect,
  YorksCorrectCertificationAction? onCorrectCertification,
  YorksCancelInvoiceAction? onCancel,
  YorksReviseInvoiceAction? onRevise,
  YorksCreatePdcAction? onCreatePdc,
  Future<String?> Function(String)? onPrint,
}) async {
  _surface(tester);
  await tester.pumpWidget(
    _wrap(
      AccountsV2InvoicesTab(
        projection: projection ?? _projection(),
        language: AppLanguage.english,
        onOpenDetail: (id) async => detail ?? _detail(status: 'partially_paid'),
        onCertify: onCertify,
        onPay: onPay,
        onReversePayment: onReverse,
        onCorrectPayment: onCorrect,
        onCorrectCertification: onCorrectCertification,
        onCancelInvoice: onCancel,
        onRevise: onRevise,
        onCreatePdc: onCreatePdc,
        onPrintInvoice: onPrint,
        today: DateTime(2026, 11, 7),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('YRA322-01'));
  await tester.pumpAndSettle();
}

Finder _rowMenu() =>
    find.byWidgetPredicate((w) => w is AccountsV2Icon && w.name == 'dots');

void main() {
  const en = AppLanguage.english;
  String t(String key) => accountsV2Text(en, key);

  group('AccountsV2InvoicesTab layout', () {
    testWidgets('renders report actions, KPIs, filters and the tracker', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(
        _wrap(AccountsV2InvoicesTab(projection: _projection(), language: en)),
      );
      await tester.pumpAndSettle();

      expect(find.text(t('v2i_report_actions')), findsOneWidget);
      expect(find.text(t('v2i_kpi_cheques')), findsOneWidget);
      expect(find.text('AED 1,050,000.00'), findsWidgets);
      expect(find.text(t('v2i_tracker')), findsOneWidget);
      expect(find.text('YRA322-01'), findsOneWidget);
      // Past its due date with money still due: overdue.
      expect(find.text(t('v2i_st_overdue')), findsWidgets);
      expect(find.text('+ 200,000.00 ${t('v2i_cheque_word')}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('omits money without the capability', (tester) async {
      _surface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2InvoicesTab(
            projection: _projection(values: false),
            language: en,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('YRA322-01'), findsOneWidget);
      expect(find.textContaining('AED'), findsNothing);
      expect(find.text('1,050,000.00'), findsNothing);
      expect(find.text(t('v2i_kpi_cheques')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the empty state with no invoices', (tester) async {
      _surface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2InvoicesTab(
            projection: _projection(invoices: const []),
            language: en,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(t('v2i_no_records')), findsOneWidget);
    });

    testWidgets('the status filter narrows the tracker', (tester) async {
      _surface(tester);
      await tester.pumpWidget(
        _wrap(AccountsV2InvoicesTab(projection: _projection(), language: en)),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text(t('v2i_all')).first);
      await tester.tap(find.text(t('v2i_st_paid')).last);
      await tester.pumpAndSettle();
      expect(find.text(t('v2i_no_match')), findsOneWidget);
      await _tap(tester, _button(t('v2i_clear_filters')));
      expect(find.text('YRA322-01'), findsOneWidget);
    });

    testWidgets('lays out at 360px with the tracker scrolling sideways', (
      tester,
    ) async {
      _surface(tester, width: 360);
      await tester.pumpWidget(
        _wrap(AccountsV2InvoicesTab(projection: _projection(), language: en)),
      );
      await tester.pumpAndSettle();
      expect(find.text('YRA322-01'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('AccountsV2InvoicesTab drawer', () {
    testWidgets('a row opens the drawer with its figures and progress', (
      tester,
    ) async {
      await _openDrawer(tester);
      expect(find.text(t('v2i_invoice_total')), findsOneWidget);
      expect(find.text(t('v2i_tl_submitted')), findsOneWidget);
      expect(find.text(t('v2i_payments').toUpperCase()), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed detail read says so', (tester) async {
      _surface(tester);
      String? opened;
      await tester.pumpWidget(
        _wrap(
          AccountsV2InvoicesTab(
            projection: _projection(),
            language: en,
            onOpenDetail: (id) async {
              opened = id;
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('YRA322-01'));
      await tester.pumpAndSettle();
      expect(opened, 'i1');
      expect(find.text(t('v2_inv_detail_failed')), findsOneWidget);
    });

    testWidgets('records a payment through onPay', (tester) async {
      YorksAccountsPaymentInput? captured;
      await _openDrawer(
        tester,
        projection: _projection(cert: true, pay: true),
        onPay: (i) async {
          captured = i;
          return null;
        },
      );
      await _tap(tester, _button(t('v2i_record_payment')));
      // Reference is the third text field (amount, date, reference, note).
      await tester.enterText(find.byType(TextField).at(2), 'PAY-1');
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('accounts-v2-dialog-confirm')),
      );
      await tester.pumpAndSettle();
      expect(captured!.invoiceId, 'i1');
      expect(captured!.paymentMethod, 'bank_transfer');
      expect(captured!.paymentReference, 'PAY-1');
      expect(find.text(t('v2_pay_saved')), findsOneWidget);
    });

    testWidgets('a rejected payment explains why and keeps the drawer', (
      tester,
    ) async {
      await _openDrawer(
        tester,
        projection: _projection(pay: true),
        onPay: (_) async => 'R39_ACCOUNTS_PAYMENT_CAP_EXCEEDED',
      );
      await _tap(tester, _button(t('v2i_record_payment')));
      await tester.enterText(find.byType(TextField).at(2), 'PAY-1');
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('accounts-v2-dialog-confirm')),
      );
      await tester.pumpAndSettle();
      expect(find.text(t('v2_err_over_due')), findsOneWidget);
    });

    testWidgets('records the first certification through onCertify', (
      tester,
    ) async {
      YorksAccountsCertificationInput? captured;
      await _openDrawer(
        tester,
        projection: _projection(
          cert: true,
          invoices: [
            _invoice(
              status: YorksAccountsInvoiceStatus.submitted,
              certified: '0.00',
            ),
          ],
        ),
        detail: _detail(status: 'submitted'),
        onCertify: (i) async {
          captured = i;
          return null;
        },
      );
      // Not certified yet: payments wait for it.
      expect(
        tester
            .widgetList<AccountsV2Button>(_button(t('v2i_record_payment')))
            .every((b) => b.onPressed == null),
        isTrue,
      );
      await _tap(tester, _button(t('v2i_record_cert')));
      await tester.enterText(find.byType(TextField).at(2), 'CERT-1');
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('accounts-v2-dialog-confirm')),
      );
      await tester.pumpAndSettle();
      expect(captured!.certificationReference, 'CERT-1');
      expect(find.text(t('v2_cert_saved')), findsOneWidget);
    });

    testWidgets('only the latest certification is edited', (tester) async {
      YorksAccountsCertificationCorrectionInput? captured;
      await _openDrawer(
        tester,
        detail: _detail(
          status: 'partially_paid',
          certifications: [
            _certificationJson(id: 'c1', revision: 1, reference: 'CERT-1'),
            _certificationJson(id: 'c2', revision: 2, reference: 'CERT-2'),
          ],
        ),
        onCorrectCertification: (input) async {
          captured = input;
          return null;
        },
      );
      await _tap(tester, _button(t('v2i_edit_cert')));
      expect(find.text(t('v2_cert_edit_hint')), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, t('v2_cert_amount')),
        '0',
      );
      await tester.enterText(
        find.widgetWithText(TextField, t('v2_pay_reverse_reason')),
        'Certified in error',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('accounts-v2-dialog-confirm')),
      );
      await tester.pumpAndSettle();
      expect(captured!.certificationReference, 'CERT-2');
      expect(captured!.certifiedExVat.isPositive, isFalse);
    });

    testWidgets('view / print opens the invoice PDF', (tester) async {
      String? printed;
      await _openDrawer(
        tester,
        onPrint: (id) async {
          printed = id;
          return null;
        },
      );
      await _tap(tester, _button(t('v2i_view_print')));
      expect(printed, 'i1');
    });

    testWidgets('no actions without the capabilities', (tester) async {
      await _openDrawer(
        tester,
        onCertify: (_) async => null,
        onPay: (_) async => null,
      );
      expect(_button(t('v2i_record_payment')), findsNothing);
      expect(_button(t('v2i_record_cert')), findsNothing);
      expect(_button(t('v2i_record_cheque')), findsNothing);
    });

    testWidgets('records a cheque, prefilled with what is still open', (
      tester,
    ) async {
      YorksAccountsPdcCreateInput? captured;
      await _openDrawer(
        tester,
        projection: _projection(pdc: true),
        onCreatePdc: (input) async {
          captured = input;
          return null;
        },
      );
      await _tap(tester, _button(t('v2i_record_cheque')));
      // Due 550,000 less 200,000 already covered by cheques.
      expect(find.widgetWithText(TextField, '350000'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('accounts-v2-dialog-confirm')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          t('v2b_need_text').replaceAll('{field}', t('v2_pdc_add_number')),
        ),
        findsOneWidget,
        reason: 'A cheque number is required',
      );
      await tester.enterText(find.byType(TextField).first, '004517');
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('accounts-v2-dialog-confirm')),
      );
      await tester.pumpAndSettle();
      expect(captured!.chequeNumber, '004517');
      expect(captured!.amount.canonicalText, '350000');
      expect(find.text(t('v2_pdc_saved')), findsOneWidget);
    });

    testWidgets('revises a submitted invoice', (tester) async {
      String? revised;
      await _openDrawer(
        tester,
        projection: _projection(
          invoices: [_invoice(status: YorksAccountsInvoiceStatus.submitted)],
        ),
        detail: _detail(status: 'submitted'),
        onRevise:
            ({
              required String invoiceId,
              required int expectedVersion,
              required String reason,
            }) async {
              revised = '$invoiceId@$expectedVersion:$reason';
              return null;
            },
      );
      await _tap(tester, _button('${t('v2i_revise')} (R.1)'));
      await tester.enterText(find.byType(TextField).last, 'Wrong quantity');
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('accounts-v2-dialog-confirm')),
      );
      await tester.pumpAndSettle();
      expect(revised, 'i1@2:Wrong quantity');
      expect(find.text(t('v2_inv_revised')), findsOneWidget);
    });

    testWidgets('hides Revise once the invoice is certified', (tester) async {
      await _openDrawer(
        tester,
        detail: _detail(
          status: 'certified',
          certifications: [
            _certificationJson(id: 'c1', revision: 1, reference: 'CERT-1'),
          ],
        ),
        onRevise:
            ({
              required String invoiceId,
              required int expectedVersion,
              required String reason,
            }) async => null,
      );
      expect(find.textContaining(t('v2i_revise')), findsNothing);
    });

    testWidgets('reverses a payment with only a reason typed', (tester) async {
      YorksAccountsPaymentReversalInput? captured;
      await _openDrawer(
        tester,
        detail: _detail(status: 'partially_paid', payments: [_paymentJson()]),
        onReverse: (input) async {
          captured = input;
          return null;
        },
      );
      await _tap(tester, _rowMenu());
      await tester.tap(find.text(t('v2i_reverse')));
      await tester.pumpAndSettle();
      // Not from a cheque, so there is no cheque question.
      expect(find.text(t('v2_pay_reverse_cheque')), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, t('v2_pay_reverse_reason')),
        'Bank recalled it',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('accounts-v2-dialog-confirm')),
      );
      await tester.pumpAndSettle();
      expect(captured!.originalPaymentId, 'pay1');
      expect(captured!.reason, 'Bank recalled it');
      expect(captured!.chequeOutcome, isNull);
      expect(find.text(t('v2_pay_reversed')), findsOneWidget);
    });

    testWidgets('a cleared cheque\'s payment is reversed from its row', (
      tester,
    ) async {
      YorksAccountsPaymentReversalInput? captured;
      await _openDrawer(
        tester,
        detail: _detail(
          status: 'partially_paid',
          payments: [_paymentJson(pdcId: 'pdc1', method: 'PDC')],
          pdcs: [_pdcJson()],
        ),
        onReverse: (input) async {
          captured = input;
          return null;
        },
      );
      // One row for the cheque, not a second one for its payment.
      expect(find.text('004517'), findsOneWidget);
      await _tap(tester, _rowMenu());
      await tester.tap(find.text(t('v2i_reverse')));
      await tester.pumpAndSettle();
      expect(find.text(t('v2_pay_reverse_cheque')), findsOneWidget);
      await tester.tap(find.text(t('v2_pay_reverse_cheque_deposited')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_pay_reverse_cheque_bounced')).last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, t('v2_pay_reverse_reason')),
        'Bank returned it',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('accounts-v2-dialog-confirm')),
      );
      await tester.pumpAndSettle();
      expect(captured!.chequeOutcome, YorksAccountsPdcStatus.bounced);
    });

    testWidgets('edits a payment, prefilled, in one step', (tester) async {
      YorksAccountsPaymentCorrectionInput? captured;
      await _openDrawer(
        tester,
        detail: _detail(status: 'partially_paid', payments: [_paymentJson()]),
        onCorrect: (input) async {
          captured = input;
          return null;
        },
      );
      await _tap(tester, _rowMenu());
      await tester.tap(find.text(t('v2i_edit')));
      await tester.pumpAndSettle();
      final amount = find.widgetWithText(TextField, t('v2_pay_amount'));
      expect(tester.widget<TextField>(amount).controller!.text, '1000');
      await tester.enterText(amount, '1200.00');
      await tester.enterText(
        find.widgetWithText(TextField, t('v2_pay_reverse_reason')),
        'Amount typed wrong',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('accounts-v2-dialog-confirm')),
      );
      await tester.pumpAndSettle();
      expect(captured!.amount.postgresText, '1200');
      expect(captured!.paymentReference, 'BANK-1');
      expect(find.text(t('v2_pay_edit_done')), findsOneWidget);
    });

    testWidgets('a cheque payment keeps its amount when edited', (
      tester,
    ) async {
      await _openDrawer(
        tester,
        detail: _detail(
          status: 'partially_paid',
          payments: [_paymentJson(pdcId: 'pdc1', method: 'PDC')],
          pdcs: [_pdcJson()],
        ),
        onCorrect: (_) async => null,
      );
      await _tap(tester, _rowMenu());
      await tester.tap(find.text(t('v2i_edit')));
      await tester.pumpAndSettle();
      expect(find.text(t('v2_pay_edit_cheque_hint')), findsOneWidget);
      expect(find.widgetWithText(TextField, t('v2_pay_amount')), findsNothing);
    });

    testWidgets('cancels an invoice and explains a refusal', (tester) async {
      await _openDrawer(
        tester,
        detail: _detail(status: 'submitted'),
        onCancel: (_) async => 'R39_ACCOUNTS_INVOICE_HAS_DOWNSTREAM_FACTS',
      );
      await _tap(tester, _button(t('v2i_cancel_invoice')));
      await tester.enterText(
        find.widgetWithText(TextField, t('v2_pay_reverse_reason')),
        'Wrong client',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('accounts-v2-dialog-confirm')),
      );
      await tester.pumpAndSettle();
      expect(find.text(t('v2_err_has_facts')), findsOneWidget);
      // The refusal is shown in the dialog, which stays open with the reason
      // still typed, so it can be corrected or cancelled without retyping.
      expect(
        find.byKey(const ValueKey('accounts-v2-dialog-error')),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, 'Wrong client'), findsOneWidget);
    });

    testWidgets('a greyed-out Record payment says why', (tester) async {
      await _openDrawer(
        tester,
        projection: _projection(
          pay: true,
          invoices: [_invoice(status: YorksAccountsInvoiceStatus.submitted)],
        ),
        detail: _detail(status: 'submitted'),
        onPay: (_) async => null,
      );
      expect(
        find.byKey(const ValueKey('accounts-v2-pay-blocked')),
        findsOneWidget,
      );
      expect(find.text(t('v2b_pay_blocked_cert')), findsOneWidget);
    });

    testWidgets('the payment dialog names the invoice and what is due', (
      tester,
    ) async {
      await _openDrawer(
        tester,
        projection: _projection(pay: true),
        onPay: (_) async => null,
      );
      await _tap(tester, _button(t('v2i_record_payment')));
      expect(
        find.text(
          t('v2b_sum_due')
              .replaceAll('{ref}', 'YRA322-01')
              .replaceAll('{amount}', 'AED 550,000.00'),
        ),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, t('v2_pay_title')),
        findsOneWidget,
      );
    });

    group('restoring a cancelled invoice', () {
      YorksAccountsInvoicesProjection cancelled({
        List<YorksAccountsClientInvoiceSummary>? invoices,
      }) => YorksAccountsInvoicesProjection(
        schemaVersion: 1,
        projectId: 'p1',
        invoices:
            invoices ??
            [_invoice(status: YorksAccountsInvoiceStatus.cancelled)],
        nextCursor: null,
        capabilities: const YorksAccountsReceivablesCapabilities(
          canViewValues: true,
          prepareClientClaim: true,
          manageClientInvoices: true,
          recordClientCertification: false,
          recordClientPayment: false,
          managePdc: false,
        ),
        commands: _cmds,
      );

      Future<void> open(
        WidgetTester tester,
        YorksAccountsInvoicesProjection projection,
        YorksCancelInvoiceAction onRestore,
      ) async {
        _surface(tester);
        await tester.pumpWidget(
          _wrap(
            AccountsV2InvoicesTab(
              projection: projection,
              language: AppLanguage.english,
              onOpenDetail: (id) async => _detail(status: 'cancelled'),
              onRestoreInvoice: onRestore,
              focusInvoiceId: 'i1',
              today: DateTime(2026, 11, 7),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      testWidgets('restores with a reason, and says so', (tester) async {
        YorksAccountsEntityActionInput? sent;
        await open(tester, cancelled(), (input) async {
          sent = input;
          return null;
        });
        await _tap(
          tester,
          find.byKey(const ValueKey('accounts-v2-restore-invoice')),
        );
        await tester.enterText(
          find.widgetWithText(TextField, t('v2r_restore_reason')),
          'Cancelled by mistake',
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('accounts-v2-dialog-confirm')),
        );
        await tester.pumpAndSettle();
        expect(sent?.entityId, 'i1');
        expect(sent?.reason, 'Cancelled by mistake');
        expect(find.text(t('v2r_invoice_restored')), findsOneWidget);
      });

      testWidgets('progress claimed again is explained in the dialog', (
        tester,
      ) async {
        await open(
          tester,
          cancelled(),
          (_) async => 'R39_ACCOUNTS_CLAIM_CAP_EXCEEDED',
        );
        await _tap(
          tester,
          find.byKey(const ValueKey('accounts-v2-restore-invoice')),
        );
        await tester.enterText(
          find.widgetWithText(TextField, t('v2r_restore_reason')),
          'Mistake',
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('accounts-v2-dialog-confirm')),
        );
        await tester.pumpAndSettle();
        expect(find.text(t('v2r_err_claimed_again')), findsOneWidget);
        expect(find.widgetWithText(TextField, 'Mistake'), findsOneWidget);
      });

      testWidgets('an invoice a revision replaced offers no Restore', (
        tester,
      ) async {
        final successor = _invoice(
          id: 'i2',
          reference: 'YRA322-01R.1',
          replaces: 'YRA322-01',
        );
        await open(
          tester,
          cancelled(
            invoices: [
              _invoice(status: YorksAccountsInvoiceStatus.cancelled),
              successor,
            ],
          ),
          (_) async => null,
        );
        expect(
          find.byKey(const ValueKey('accounts-v2-restore-invoice')),
          findsNothing,
        );
      });
    });

    testWidgets('the drawer lays out at 360px', (tester) async {
      _surface(tester, width: 360);
      await tester.pumpWidget(
        _wrap(
          AccountsV2InvoicesTab(
            projection: _projection(cert: true, pay: true, pdc: true),
            language: en,
            onOpenDetail: (id) async =>
                _detail(status: 'partially_paid', payments: [_paymentJson()]),
            onPay: (_) async => null,
            onCreatePdc: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text('YRA322-01'));
      expect(find.text(t('v2i_invoice_total')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('phone screenshots', () {
    setUpAll(loadAccountsV2GoldenFonts);

    testWidgets('the invoice drawer on a phone', (tester) async {
      tester.view.physicalSize = const Size(360, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: AccountsV2InvoicesTab(
              projection: _projection(cert: true, pay: true, pdc: true),
              language: en,
              onOpenDetail: (id) async =>
                  _detail(status: 'partially_paid', payments: [_paymentJson()]),
              onPay: (_) async => null,
              onCreatePdc: (_) async => null,
              focusInvoiceId: 'i1',
              today: DateTime(2026, 11, 7),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/accounts_v2/phone_invoice_drawer.png'),
      );
    });
  });

  group('YorksAccountsWorkspaceV2Screen (Invoices tab)', () {
    testWidgets('opening on invoices loads the tracker from the repository', (
      tester,
    ) async {
      _surface(tester);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          yorksV1CurrentRoleProvider.overrideWithValue(null),
          yorksAccountsPermissionEpochProvider.overrideWithValue((
            revision: 1,
            trusted: true,
            stale: false,
            revisionSignalHealthy: true,
          )),
          yorksAccountsReceivablesRepositoryProvider.overrideWithValue(
            _FakeReceivables(_projection()),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: YorksAccountsWorkspaceV2Screen(
                projectId: 'p1',
                initialTab: YorksAccountsWorkspaceV2Tab.invoices,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('YRA322-01'), findsOneWidget);
      expect(find.text('AED 1,050,000.00'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a refusal says there is no access, with nothing to retry', (
      tester,
    ) async {
      _surface(tester);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          yorksV1CurrentRoleProvider.overrideWithValue(null),
          yorksAccountsPermissionEpochProvider.overrideWithValue((
            revision: 1,
            trusted: true,
            stale: false,
            revisionSignalHealthy: true,
          )),
          yorksAccountsReceivablesRepositoryProvider.overrideWithValue(
            _RefusingReceivables(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: YorksAccountsWorkspaceV2Screen(
                projectId: 'p1',
                initialTab: YorksAccountsWorkspaceV2Tab.invoices,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(t('v2_commercial_hidden')), findsOneWidget);
      expect(find.text(t('v2_retry')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

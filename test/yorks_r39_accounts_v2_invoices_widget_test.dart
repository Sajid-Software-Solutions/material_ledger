import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/features/accounts/application/accounts_providers.dart';
import 'package:material_ledger/features/accounts/application/accounts_receivables_providers.dart';
import 'package:material_ledger/features/accounts/data/accounts_receivables_repository.dart';
import 'package:material_ledger/features/accounts/domain/accounts_decimal.dart';
import 'package:material_ledger/features/accounts/domain/accounts_receivables_inputs.dart';
import 'package:material_ledger/features/accounts/domain/accounts_receivables_models.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_common.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_invoices_tab.dart';
import 'package:material_ledger/features/accounts/presentation/v2/yorks_accounts_workspace_v2_screen.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}) => YorksAccountsClientInvoiceSummary(
  invoiceId: 'i1',
  claimId: 'c1',
  invoiceReference: 'YRA322-01',
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

YorksAccountsInvoiceDetailProjection _detail({required String status}) =>
    YorksAccountsInvoiceDetailProjection.fromRpcJson({
      'schema_version': 3,
      'project_id': 'p1',
      'invoice': _detailInvoiceJson(status: status),
      'claim': _detailClaimJson(),
      'certifications': const <Map<String, dynamic>>[],
      'payments': const <Map<String, dynamic>>[],
      'pdcs': const <Map<String, dynamic>>[],
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

void _wideSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  const en = AppLanguage.english;
  String t(String key) => accountsV2Text(en, key);

  group('AccountsV2InvoicesTab (direct)', () {
    testWidgets('renders KPIs and the invoice tracker', (tester) async {
      _wideSurface(tester);
      await tester.pumpWidget(
        _wrap(AccountsV2InvoicesTab(projection: _projection(), language: en)),
      );
      await tester.pumpAndSettle();

      expect(find.text('YRA322-01'), findsOneWidget);
      expect(find.text(t('v2_inv_kpi_cheques')), findsOneWidget);
      // Invoiced-incl-VAT KPI (with currency).
      expect(find.text('AED 1,050,000.00'), findsWidgets);
      // Overdue invoice flagged.
      expect(find.text(t('v2_inv_overdue')), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('omits money without the capability', (tester) async {
      _wideSurface(tester);
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
      expect(find.text(t('v2_inv_kpi_cheques')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the empty state with no invoices', (tester) async {
      _wideSurface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2InvoicesTab(
            projection: _projection(invoices: const []),
            language: en,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(t('v2_inv_empty')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('AccountsV2InvoicesTab actions', () {
    testWidgets('records a payment through onPay', (tester) async {
      _wideSurface(tester);
      YorksAccountsPaymentInput? captured;
      await tester.pumpWidget(
        _wrap(
          AccountsV2InvoicesTab(
            projection: _projection(cert: true, pay: true),
            language: en,
            onCertify: (i) async => null,
            onPay: (i) async {
              captured = i;
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(t('v2_inv_record_payment')), findsOneWidget);
      await tester.ensureVisible(find.text(t('v2_inv_record_payment')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_inv_record_payment')));
      await tester.pumpAndSettle();
      // Reference is the third text field (amount, date, reference, note).
      await tester.enterText(find.byType(TextField).at(2), 'PAY-1');
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_confirm')));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.invoiceId, 'i1');
      expect(captured!.paymentMethod, 'bank_transfer');
      expect(captured!.paymentReference, 'PAY-1');
      expect(find.text(t('v2_pay_saved')), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('records certification through onCertify', (tester) async {
      _wideSurface(tester);
      YorksAccountsCertificationInput? captured;
      await tester.pumpWidget(
        _wrap(
          AccountsV2InvoicesTab(
            projection: _projection(cert: true, pay: true),
            language: en,
            onCertify: (i) async {
              captured = i;
              return null;
            },
            onPay: (i) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Certified already: the next step leads, correcting it is in the menu.
      expect(find.text(t('v2_inv_record_payment')), findsOneWidget);
      expect(find.text(t('v2_inv_recertify')), findsNothing);
      await tester.ensureVisible(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_inv_recertify')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(2), 'CERT-1');
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_confirm')));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.invoiceId, 'i1');
      expect(captured!.certificationReference, 'CERT-1');
      expect(find.text(t('v2_cert_saved')), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a phone shows a card, not a table to scroll sideways', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _wrap(
          AccountsV2InvoicesTab(
            projection: _projection(cert: true, pay: true),
            language: en,
            onCertify: (i) async => null,
            onPay: (i) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DataTable), findsNothing);
      await tester.scrollUntilVisible(
        find.text(t('v2_inv_record_payment')),
        200,
      );
      expect(find.text(t('v2_inv_record_payment')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an uncertified invoice leads with Certify', (tester) async {
      _wideSurface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2InvoicesTab(
            projection: _projection(
              cert: true,
              pay: true,
              invoices: [
                _invoice(
                  status: YorksAccountsInvoiceStatus.submitted,
                  certified: '0.00',
                ),
              ],
            ),
            language: en,
            onCertify: (i) async => null,
            onPay: (i) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(t('v2_inv_certify')), findsOneWidget);
      expect(find.text(t('v2_inv_recertify')), findsNothing);
      expect(find.text(t('v2_inv_record_payment')), findsNothing);
    });

    testWidgets('view/print invokes onPrintInvoice for an issued invoice', (
      tester,
    ) async {
      _wideSurface(tester);
      String? printedId;
      await tester.pumpWidget(
        _wrap(
          AccountsV2InvoicesTab(
            projection: _projection(),
            language: en,
            onPrintInvoice: (id) async {
              printedId = id;
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final btn = find.text(t('v2_inv_view_print'));
      expect(btn, findsOneWidget);
      await tester.ensureVisible(btn);
      await tester.pumpAndSettle();
      await tester.tap(btn);
      await tester.pumpAndSettle();

      expect(printedId, 'i1');
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping the invoice reference requests the detail', (
      tester,
    ) async {
      _wideSurface(tester);
      String? openedId;
      await tester.pumpWidget(
        _wrap(
          AccountsV2InvoicesTab(
            projection: _projection(),
            language: en,
            onOpenDetail: (id) async {
              openedId = id;
              return null; // null -> the tab shows the detail-failed toast
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('YRA322-01'));
      await tester.pumpAndSettle();

      expect(openedId, 'i1');
      expect(find.text(t('v2_inv_detail_failed')), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no action buttons without the capabilities', (tester) async {
      _wideSurface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2InvoicesTab(
            projection: _projection(),
            language: en,
            onCertify: (i) async => null,
            onPay: (i) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(t('v2_inv_record_payment')), findsNothing);
      expect(find.text(t('v2_inv_certify')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('AccountsV2InvoicesTab cheques', () {
    testWidgets('records a cheque, prefilled with what is still open', (
      tester,
    ) async {
      _wideSurface(tester);
      YorksAccountsPdcCreateInput? captured;
      await tester.pumpWidget(
        _wrap(
          AccountsV2InvoicesTab(
            projection: _projection(pdc: true),
            language: en,
            onCreatePdc: (input) async {
              captured = input;
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.text(t('v2_pdc_add'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      // Due 550,000 less 200,000 already covered by cheques.
      expect(find.widgetWithText(TextField, '350000'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, t('v2_confirm')),
            )
            .onPressed,
        isNull,
        reason: 'A cheque number is required',
      );
      await tester.enterText(find.byType(TextField).first, '004517');
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_confirm')));
      await tester.pumpAndSettle();
      expect(captured!.chequeNumber, '004517');
      expect(captured!.amount.canonicalText, '350000');
      expect(find.text(t('v2_pdc_saved')), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no cheque button without manage_pdc', (tester) async {
      _wideSurface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2InvoicesTab(
            projection: _projection(),
            language: en,
            onCreatePdc: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(t('v2_pdc_add')), findsNothing);
    });

    testWidgets('a rejected payment explains why', (tester) async {
      _wideSurface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2InvoicesTab(
            projection: _projection(pay: true),
            language: en,
            onPay: (_) async => 'R39_ACCOUNTS_PAYMENT_CAP_EXCEEDED',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pay = find.text(t('v2_inv_record_payment'));
      await tester.ensureVisible(pay);
      await tester.pumpAndSettle();
      await tester.tap(pay);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(2), 'PAY-1');
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_confirm')));
      await tester.pumpAndSettle();
      expect(find.text(t('v2_err_over_due')), findsOneWidget);
    });
  });

  group('AccountsV2InvoicesTab revise', () {
    testWidgets('revises a submitted invoice from the drawer', (tester) async {
      _wideSurface(tester);
      String? revisedId;
      int? revisedVersion;
      String? revisedReason;
      await tester.pumpWidget(
        _wrap(
          AccountsV2InvoicesTab(
            projection: _projection(
              invoices: [
                _invoice(status: YorksAccountsInvoiceStatus.submitted),
              ],
            ),
            language: en,
            onOpenDetail: (id) async => _detail(status: 'submitted'),
            onRevise:
                ({
                  required String invoiceId,
                  required int expectedVersion,
                  required String reason,
                }) async {
                  revisedId = invoiceId;
                  revisedVersion = expectedVersion;
                  revisedReason = reason;
                  return null;
                },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('YRA322-01'));
      await tester.pumpAndSettle();

      // Drawer offers Revise for a still-revisable invoice.
      final revise = find.text(t('v2_inv_revise'));
      expect(revise, findsOneWidget);
      await tester.tap(revise);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, 'Wrong quantity');
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_confirm')));
      await tester.pumpAndSettle();

      expect(revisedId, 'i1');
      expect(revisedVersion, 2);
      expect(revisedReason, 'Wrong quantity');
      expect(find.text(t('v2_inv_revised')), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hides Revise once the invoice is certified', (tester) async {
      _wideSurface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2InvoicesTab(
            projection: _projection(),
            language: en,
            onOpenDetail: (id) async => _detail(status: 'certified'),
            onRevise:
                ({
                  required String invoiceId,
                  required int expectedVersion,
                  required String reason,
                }) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('YRA322-01'));
      await tester.pumpAndSettle();

      // Drawer opened (certifications section visible) but Revise is gated out.
      expect(find.text(t('v2_inv_certifications')), findsOneWidget);
      expect(find.text(t('v2_inv_revise')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('YorksAccountsWorkspaceV2Screen (Invoices tab)', () {
    testWidgets('opening on invoices loads the tracker from the repository', (
      tester,
    ) async {
      _wideSurface(tester);
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
          child: _wrap(
            const YorksAccountsWorkspaceV2Screen(
              projectId: 'p1',
              initialTab: YorksAccountsWorkspaceV2Tab.invoices,
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
      _wideSurface(tester);
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
          child: _wrap(
            const YorksAccountsWorkspaceV2Screen(
              projectId: 'p1',
              initialTab: YorksAccountsWorkspaceV2Tab.invoices,
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

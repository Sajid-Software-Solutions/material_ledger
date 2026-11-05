import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
}) => YorksAccountsReceivablesCapabilities(
  canViewValues: values,
  prepareClientClaim: false,
  manageClientInvoices: false,
  recordClientCertification: cert,
  recordClientPayment: pay,
  managePdc: false,
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

YorksAccountsClientInvoiceSummary _invoice() =>
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
    );

YorksAccountsInvoicesProjection _projection({
  bool values = true,
  bool cert = false,
  bool pay = false,
  List<YorksAccountsClientInvoiceSummary>? invoices,
}) => YorksAccountsInvoicesProjection(
  schemaVersion: 1,
  projectId: 'p1',
  invoices: invoices ?? [_invoice()],
  nextCursor: null,
  capabilities: _caps(values: values, cert: cert, pay: pay),
  commands: _cmds,
);

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

      await tester.ensureVisible(find.text(t('v2_inv_certify')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_inv_certify')));
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
  });
}

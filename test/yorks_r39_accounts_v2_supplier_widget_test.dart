import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/accounts/application/accounts_providers.dart';
import 'package:material_ledger/features/accounts/application/accounts_supplier_providers.dart';
import 'package:material_ledger/features/accounts/data/accounts_supplier_repository.dart';
import 'package:material_ledger/features/accounts/domain/accounts_decimal.dart';
import 'package:material_ledger/features/accounts/domain/accounts_receivables_inputs.dart';
import 'package:material_ledger/features/accounts/domain/accounts_supplier_models.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_common.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_supplier_tab.dart';
import 'package:material_ledger/features/accounts/presentation/v2/kit/accounts_v2_kit.dart';
import 'package:material_ledger/features/accounts/presentation/v2/yorks_accounts_workspace_v2_screen.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

YorksAccountsDecimal _d(String raw) => YorksAccountsDecimal.parse(raw);

const _caps = YorksAccountsSupplierCapabilities(
  manageSupplierBills: false,
  approveSupplierBillPayment: false,
  viewSupplierCosts: true,
);
const _capsPay = YorksAccountsSupplierCapabilities(
  manageSupplierBills: true,
  approveSupplierBillPayment: true,
  viewSupplierCosts: true,
);
const _capsNoCosts = YorksAccountsSupplierCapabilities(
  manageSupplierBills: false,
  approveSupplierBillPayment: false,
  viewSupplierCosts: false,
);
const _cmds = YorksAccountsSupplierCommands(
  createBill: false,
  editBill: false,
  approveBill: false,
  recordPayment: false,
  reversePayment: false,
  cancelBill: false,
);

YorksAccountsSupplierBill _bill({
  YorksAccountsSupplierBillStatus status =
      YorksAccountsSupplierBillStatus.approved,
  YorksAccountsSupplierMatchStatus match =
      YorksAccountsSupplierMatchStatus.matched,
  String id = 'sb1',
  String reference = 'INV-5001',
  String supplier = 'Cool Air Co',
  String? receiptReview,
  String paid = '40000.00',
  String outstanding = '65000.00',
}) => YorksAccountsSupplierBill(
  supplierBillId: id,
  projectId: 'p1',
  supplierId: 'sup1',
  supplierName: supplier,
  supplierInvoiceReference: reference,
  invoiceDate: YorksAccountsDate.parse('2026-08-01'),
  dueDate: YorksAccountsDate.parse('2026-09-01'),
  exVatAmount: _d('100000.00'),
  vatRatePercent: _d('5.0000'),
  vatAmount: _d('5000.00'),
  totalInclVat: _d('105000.00'),
  poLpoReference: 'PO-77',
  poLpoDocumentId: null,
  acceptedReceiptReviewId: receiptReview,
  acceptedDeliveryReference: receiptReview == null ? null : 'DO-3001',
  acceptedDelivery: null,
  supplierInvoiceDocumentId: null,
  explicitMismatchReason: null,
  matchStatus: match,
  status: status,
  paymentStatus: YorksAccountsSupplierPaymentStatus.partiallyPaid,
  paidAmount: _d(paid),
  outstandingAmount: _d(outstanding),
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
);

YorksAccountsSupplierBillsProjection _projection({
  bool costs = true,
  bool pay = false,
  List<YorksAccountsSupplierBill>? items,
}) => YorksAccountsSupplierBillsProjection(
  projectId: 'p1',
  items: items ?? [_bill()],
  nextCursor: null,
  capabilities: pay ? _capsPay : (costs ? _caps : _capsNoCosts),
  commands: _cmds,
);

final class _FakeSupplier implements YorksAccountsSupplierRepository {
  _FakeSupplier(this.projection);
  final YorksAccountsSupplierBillsProjection projection;

  @override
  Future<YorksAccountsSupplierBillsProjection> listBills(
    String projectId, {
    String? search,
    YorksAccountsSupplierMatchStatus? matchStatus,
    YorksAccountsSupplierPaymentStatus? paymentStatus,
    YorksAccountsSupplierBillCursor? before,
    int limit = 25,
  }) async => projection;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _surface(WidgetTester tester, {double width = 1400}) {
  tester.view.physicalSize = Size(width, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

/// Two bills: an overdue one with no delivery linked, and a linked one paid.
List<YorksAccountsSupplierBill> _two() => [
  _bill(),
  _bill(
    id: 'sb2',
    reference: 'EDF-0817',
    supplier: 'Emirates Duct Fab',
    receiptReview: 'rr1',
    paid: '105000.00',
    outstanding: '0.00',
  ),
];

void main() {
  const en = AppLanguage.english;
  String t(String key) => accountsV2Text(en, key);

  Future<void> pump(
    WidgetTester tester, {
    YorksAccountsSupplierBillsProjection? projection,
    VoidCallback? onAddBill,
    ValueChanged<YorksAccountsSupplierBill>? onOpenBill,
    YorksAccountsDecimal? invoiced,
    double width = 1400,
  }) async {
    _surface(tester, width: width);
    await tester.pumpWidget(
      _wrap(
        AccountsV2SupplierTab(
          projection: projection ?? _projection(items: _two()),
          language: en,
          onAddBill: onAddBill,
          onOpenBill: onOpenBill,
          invoicedTotal: invoiced,
          today: DateTime(2026, 11, 7),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('AccountsV2SupplierTab', () {
    testWidgets('renders report actions, KPIs and the bills table', (
      tester,
    ) async {
      await pump(tester, invoiced: _d('420000.00'));
      expect(find.text(t('v2i_report_actions')), findsOneWidget);
      expect(find.text(t('v2s_kpi_bills')), findsOneWidget);
      expect(find.text('AED 210,000'), findsOneWidget);
      expect(find.text(t('v2s_kpi_paid')), findsOneWidget);
      expect(find.text('AED 145,000'), findsOneWidget);
      // 200,000 of supplier cost against 420,000 invoiced.
      expect(find.text('48%'), findsOneWidget);
      expect(find.text('INV-5001'), findsOneWidget);
      expect(find.text('Cool Air Co'), findsOneWidget);
      expect(find.text(t('v2s_no_delivery')), findsOneWidget);
      expect(find.text('PO-77 · DO-3001'), findsOneWidget);
      // Past its due date with money left: overdue; the other is paid.
      expect(find.text(t('v2s_st_overdue')), findsOneWidget);
      expect(find.text(t('v2s_st_paid')), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('counts open bills with no delivery linked', (tester) async {
      await pump(tester);
      final card = find.ancestor(
        of: find.text(t('v2s_kpi_unlinked')),
        matching: find.byType(AccountsV2KpiCard),
      );
      expect(
        find.descendant(of: card, matching: find.text('1')),
        findsOneWidget,
      );
      expect(find.textContaining(t('v2s_waiting_proof')), findsOneWidget);
    });

    testWidgets('searches and filters the bills', (tester) async {
      await pump(tester);
      await tester.enterText(
        find.widgetWithText(TextField, t('v2s_search')),
        'duct',
      );
      await tester.pumpAndSettle();
      expect(find.text('INV-5001'), findsNothing);
      expect(find.text('EDF-0817'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, t('v2s_search')),
        '',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2i_all')).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2s_not_linked')).last);
      await tester.pumpAndSettle();
      expect(find.text('INV-5001'), findsOneWidget);
      expect(find.text('EDF-0817'), findsNothing);
    });

    testWidgets('says when nothing matches', (tester) async {
      await pump(tester);
      await tester.enterText(
        find.widgetWithText(TextField, t('v2s_search')),
        'zzz',
      );
      await tester.pumpAndSettle();
      expect(find.text(t('v2s_no_match')), findsOneWidget);
    });

    testWidgets('blocks the surface without supplier-cost access', (
      tester,
    ) async {
      await pump(tester, projection: _projection(costs: false));
      expect(find.text(t('v2_sup_no_access')), findsOneWidget);
      expect(find.text('INV-5001'), findsNothing);
      expect(find.textContaining('AED'), findsNothing);
    });

    testWidgets('shows the empty state with no bills', (tester) async {
      await pump(tester, projection: _projection(items: const []));
      expect(find.text(t('v2s_empty_title')), findsOneWidget);
    });

    testWidgets('a project with no bills can still add the first one', (
      tester,
    ) async {
      var added = 0;
      await pump(
        tester,
        projection: _projection(items: const []),
        onAddBill: () => added++,
      );
      await tester.tap(
        find.widgetWithText(AccountsV2Button, t('v2s_new_bill')).last,
      );
      await tester.pumpAndSettle();
      expect(added, 1);
    });

    testWidgets('no add button without the capability', (tester) async {
      await pump(tester);
      expect(find.text(t('v2s_new_bill')), findsNothing);
    });

    testWidgets('a bill row opens the bill', (tester) async {
      YorksAccountsSupplierBill? opened;
      await pump(tester, onOpenBill: (b) => opened = b);
      await tester.tap(find.text('INV-5001'));
      await tester.pumpAndSettle();
      expect(opened!.supplierBillId, 'sb1');
    });

    testWidgets('a draft bill reads as a draft', (tester) async {
      await pump(
        tester,
        projection: _projection(
          items: [_bill(status: YorksAccountsSupplierBillStatus.draft)],
        ),
      );
      expect(find.text(t('v2s_st_draft')), findsOneWidget);
    });

    testWidgets('lays out at 360px', (tester) async {
      await pump(tester, width: 360, onAddBill: () {});
      expect(find.text('INV-5001'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('YorksAccountsWorkspaceV2Screen (Supplier bills tab)', () {
    testWidgets('opening on supplier bills loads from the repository', (
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
          yorksAccountsSupplierRepositoryProvider.overrideWithValue(
            _FakeSupplier(_projection()),
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
                initialTab: YorksAccountsWorkspaceV2Tab.supplierBills,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('INV-5001'), findsOneWidget);
      expect(find.text('Cool Air Co'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

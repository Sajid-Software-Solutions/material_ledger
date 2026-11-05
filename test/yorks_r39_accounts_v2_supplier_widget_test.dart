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

YorksAccountsSupplierBill _bill() => YorksAccountsSupplierBill(
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
);

YorksAccountsSupplierBillsProjection _projection({
  bool costs = true,
  List<YorksAccountsSupplierBill>? items,
}) => YorksAccountsSupplierBillsProjection(
  projectId: 'p1',
  items: items ?? [_bill()],
  nextCursor: null,
  capabilities: costs ? _caps : _capsNoCosts,
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

  group('AccountsV2SupplierTab (direct)', () {
    testWidgets('renders KPIs and the bills table', (tester) async {
      _wideSurface(tester);
      await tester.pumpWidget(
        _wrap(AccountsV2SupplierTab(projection: _projection(), language: en)),
      );
      await tester.pumpAndSettle();

      expect(find.text('INV-5001'), findsOneWidget);
      expect(find.text('Cool Air Co'), findsOneWidget);
      expect(find.text('DO-3001'), findsOneWidget);
      expect(find.text(t('v2_sup_kpi_billed')), findsOneWidget);
      expect(find.text('AED 105,000.00'), findsWidgets);
      expect(find.text(t('v2_sup_pay_partially_paid')), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('blocks the surface without supplier-cost access', (
      tester,
    ) async {
      _wideSurface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2SupplierTab(
            projection: _projection(costs: false),
            language: en,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(t('v2_sup_no_access')), findsOneWidget);
      expect(find.text('INV-5001'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the empty state with no bills', (tester) async {
      _wideSurface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2SupplierTab(
            projection: _projection(items: const []),
            language: en,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(t('v2_sup_empty')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('YorksAccountsWorkspaceV2Screen (Supplier bills tab)', () {
    testWidgets('opening on supplier bills loads from the repository', (
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
          yorksAccountsSupplierRepositoryProvider.overrideWithValue(
            _FakeSupplier(_projection()),
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
              initialTab: YorksAccountsWorkspaceV2Tab.supplierBills,
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

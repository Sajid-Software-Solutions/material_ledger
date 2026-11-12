// R39 Accounts Workspace V2 — a supplier bill in the side drawer, on the same
// pattern as a client invoice: figures, one button per action, papers in plain
// words, payments with their own actions, and dialogs that keep a refusal.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/accounts/application/accounts_providers.dart';
import 'package:material_ledger/features/accounts/application/accounts_supplier_providers.dart';
import 'package:material_ledger/features/accounts/data/accounts_supplier_repository.dart';
import 'package:material_ledger/features/accounts/domain/accounts_decimal.dart';
import 'package:material_ledger/features/accounts/domain/accounts_receivables_inputs.dart';
import 'package:material_ledger/features/accounts/domain/accounts_supplier_inputs.dart';
import 'package:material_ledger/features/accounts/domain/accounts_supplier_models.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_common.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_supplier_drawer.dart';
import 'package:material_ledger/features/accounts/presentation/v2/kit/accounts_v2_kit.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/accounts_v2_golden_fonts.dart';

const en = AppLanguage.english;
String t(String key) => accountsV2Text(en, key);
YorksAccountsDecimal _d(String raw) => YorksAccountsDecimal.parse(raw);

YorksAccountsSupplierBill _bill({
  YorksAccountsSupplierBillStatus status =
      YorksAccountsSupplierBillStatus.approved,
  YorksAccountsSupplierMatchStatus match =
      YorksAccountsSupplierMatchStatus.matched,
  String paid = '40000.00',
  String outstanding = '65000.00',
}) => YorksAccountsSupplierBill(
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
  acceptedDeliveryReference: null,
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
  notes: 'Chillers for Block A',
  recordVersion: 3,
  createdByAuthUserId: 'u',
  createdByExactRole: 'accountant',
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 2),
);

YorksAccountsSupplierPayment _payment() => YorksAccountsSupplierPayment(
  paymentId: 'pay1',
  entryKind: YorksAccountsSupplierPaymentEntryKind.payment,
  originalPaymentId: null,
  paymentDate: YorksAccountsDate.parse('2026-08-10'),
  paymentMethod: 'bank_transfer',
  paymentReference: 'TT-0042',
  amount: _d('40000.00'),
  reason: null,
  adminExceptionReason: null,
  actorAuthUserId: 'u',
  actorExactRole: 'accountant',
  createdAt: DateTime.utc(2026, 8, 10),
);

const _all = YorksAccountsSupplierCommands(
  createBill: true,
  editBill: true,
  approveBill: true,
  recordPayment: true,
  reversePayment: true,
  cancelBill: true,
  correctPayment: true,
  reopenBill: true,
);

const _caps = YorksAccountsSupplierCapabilities(
  manageSupplierBills: true,
  approveSupplierBillPayment: true,
  viewSupplierCosts: true,
);

YorksAccountsSupplierCommandResult _ok() => YorksAccountsSupplierCommandResult(
  projectId: 'p1',
  entityId: 'sb1',
  supplierBillId: 'sb1',
  paymentId: null,
  reversalId: null,
  recordVersion: 4,
  status: null,
  matchStatus: null,
  paymentStatus: null,
  amount: null,
  replayed: false,
  updatedAt: DateTime.utc(2026, 8, 3),
);

final class _Fake implements YorksAccountsSupplierRepository {
  _Fake(this.bill, {this.payments = const [], this.refusePayment});
  final YorksAccountsSupplierBill bill;
  final List<YorksAccountsSupplierPayment> payments;
  final String? refusePayment;
  YorksAccountsSupplierBillApprovalInput? approved;
  YorksAccountsSupplierPaymentInput? paid;
  YorksAccountsSupplierPaymentReversalInput? reversed;

  @override
  Future<YorksAccountsSupplierBillDetailProjection> getBill(
    String projectId,
    String supplierBillId,
  ) async => YorksAccountsSupplierBillDetailProjection(
    projectId: 'p1',
    supplierBill: bill,
    payments: payments,
    capabilities: _caps,
    commands: _all,
  );

  @override
  Future<YorksAccountsSupplierBillsProjection> listBills(
    String projectId, {
    String? search,
    YorksAccountsSupplierMatchStatus? matchStatus,
    YorksAccountsSupplierPaymentStatus? paymentStatus,
    YorksAccountsSupplierBillCursor? before,
    int limit = 25,
  }) async => YorksAccountsSupplierBillsProjection(
    projectId: 'p1',
    items: [bill],
    nextCursor: null,
    capabilities: _caps,
    commands: _all,
  );

  @override
  Future<YorksAccountsSupplierCommandResult> approveBill(
    YorksAccountsSupplierBillApprovalInput input, {
    required String idempotencyKey,
  }) async {
    approved = input;
    return _ok();
  }

  @override
  Future<YorksAccountsSupplierCommandResult> recordPayment(
    YorksAccountsSupplierPaymentInput input, {
    required String idempotencyKey,
  }) async {
    if (refusePayment != null) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.serverRejected,
        serverMessage: refusePayment,
      );
    }
    paid = input;
    return _ok();
  }

  @override
  Future<YorksAccountsSupplierCommandResult> reversePayment(
    YorksAccountsSupplierPaymentReversalInput input, {
    required String idempotencyKey,
  }) async {
    reversed = input;
    return _ok();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester,
  _Fake fake, {
  Size size = const Size(600, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
      yorksAccountsSupplierRepositoryProvider.overrideWithValue(fake),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showAccountsV2SupplierBillDrawer(
                  context,
                  projectId: 'p1',
                  bill: fake.bill,
                  language: en,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows figures, papers in plain words and the payments', (
    tester,
  ) async {
    await _pump(tester, _Fake(_bill(), payments: [_payment()]));
    expect(find.text('105,000.00'), findsOneWidget);
    expect(find.text('65,000.00'), findsOneWidget);
    expect(find.text(t('v2sd_docs').toUpperCase()), findsOneWidget);
    expect(find.text(t('v2sd_doc_delivery')), findsOneWidget);
    expect(find.textContaining('PO-77'), findsOneWidget);
    // No internal words, and no raw amounts.
    expect(find.textContaining('Three-way'), findsNothing);
    expect(find.textContaining('Admin exception'), findsNothing);
    expect(find.text('65000'), findsNothing);
    expect(find.text('TT-0042'), findsOneWidget);
    expect(find.text(t('v2i_type_bank')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a draft names why it cannot be paid yet and approves', (
    tester,
  ) async {
    final fake = _Fake(
      _bill(
        status: YorksAccountsSupplierBillStatus.draft,
        match: YorksAccountsSupplierMatchStatus.review,
      ),
    );
    await _pump(tester, fake);
    expect(find.text(t('v2sd_pay_blocked_draft')), findsOneWidget);
    await _tap(
      tester,
      find.byKey(const ValueKey('accounts-v2-supplier-approve')),
    );
    // Papers are missing: the dialog says so and takes the reason.
    expect(find.text(t('v2sd_approve_missing')), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, t('v2sd_approve_reason')),
      'Delivery note to follow',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('accounts-v2-dialog-confirm')));
    await tester.pumpAndSettle();
    expect(fake.approved?.adminExceptionReason, 'Delivery note to follow');
    expect(fake.approved?.expectedVersion, 3);
    expect(find.text(t('v2sd_approved')), findsOneWidget);
  });

  testWidgets('a refused payment stays in the dialog with the reason', (
    tester,
  ) async {
    final fake = _Fake(_bill(), refusePayment: 'R39_ACCOUNTS_PAYMENT_CAP');
    await _pump(tester, fake);
    await _tap(tester, find.byKey(const ValueKey('accounts-v2-supplier-pay')));
    expect(
      find.byKey(const ValueKey('accounts-v2-dialog-summary')),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextField, t('v2sd_reference')),
      'TT-0099',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('accounts-v2-dialog-confirm')));
    await tester.pumpAndSettle();
    expect(find.text(t('v2_err_over_due')), findsOneWidget);
    expect(find.widgetWithText(TextField, 'TT-0099'), findsOneWidget);
  });

  testWidgets('a payment is reversed from its own row, in red', (tester) async {
    final fake = _Fake(_bill(), payments: [_payment()]);
    await _pump(tester, fake);
    await _tap(tester, find.byTooltip(t('v2sd_reverse')));
    final confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey('accounts-v2-dialog-confirm')),
    );
    expect(confirm.style?.backgroundColor?.resolve({}), AccountsV2Colors.bad);
    await tester.enterText(
      find.widgetWithText(TextField, t('v2_pay_reverse_reason')),
      'Paid twice',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('accounts-v2-dialog-confirm')));
    await tester.pumpAndSettle();
    expect(fake.reversed?.originalPaymentId, 'pay1');
    expect(fake.reversed?.reason, 'Paid twice');
  });

  group('on a phone', () {
    setUpAll(loadAccountsV2GoldenFonts);

    testWidgets('fits a phone', (tester) async {
      await _pump(
        tester,
        _Fake(_bill(), payments: [_payment()]),
        size: const Size(360, 1200),
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/accounts_v2/phone_supplier_drawer.png'),
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/accounts/domain/accounts_decimal.dart';
import 'package:material_ledger/features/accounts/domain/accounts_receivables_inputs.dart';
import 'package:material_ledger/features/accounts/domain/accounts_receivables_models.dart';
import 'package:material_ledger/features/accounts/domain/accounts_supplier_inputs.dart';
import 'package:material_ledger/features/accounts/domain/accounts_supplier_models.dart';
import 'package:material_ledger/features/accounts/domain/v2/pdc_register_models.dart';

YorksAccountsDecimal _d(String raw) => YorksAccountsDecimal.parse(raw);
final _date = YorksAccountsDate.parse('2026-09-25');

YorksAccountsProjectPdc _cheque(YorksAccountsPdcStatus status) =>
    YorksAccountsProjectPdc(
      pdcId: 'pdc1',
      invoiceId: 'i1',
      invoiceReference: 'YRA32201',
      chequeNumber: 'CHQ-1',
      chequeDate: _date,
      receivedDate: null,
      bankName: null,
      amount: _d('100.00'),
      status: status,
      actionRequired: false,
      recordVersion: 1,
    );

void main() {
  group('payment reversal', () {
    YorksAccountsPaymentReversalInput reversal({
      String reference = '',
      String reason = 'Wrong entry',
    }) => YorksAccountsPaymentReversalInput(
      projectId: 'p1',
      invoiceId: 'i1',
      expectedVersion: 2,
      originalPaymentId: 'pay1',
      reversalDate: _date,
      reversalReference: reference,
      reason: reason,
    );

    test('needs only a reason; the server picks the reference', () {
      expect(reversal().isValid, isTrue);
      expect(reversal(reason: '  ').isValid, isFalse);
    });

    test('a retry with a different cheque outcome is a different command', () {
      final bounced = YorksAccountsPaymentReversalInput(
        projectId: 'p1',
        invoiceId: 'i1',
        expectedVersion: 2,
        originalPaymentId: 'pay1',
        reversalDate: _date,
        reversalReference: '',
        reason: 'Wrong entry',
        chequeOutcome: YorksAccountsPdcStatus.bounced,
      );
      expect(bounced.idempotencyPayload()['cheque_outcome'], 'bounced');
      expect(reversal().idempotencyPayload()['cheque_outcome'], isNull);
    });
  });

  group('corrections need a reason and valid values', () {
    test('payment', () {
      YorksAccountsPaymentCorrectionInput input({
        String amount = '10.00',
        String reference = 'P-1',
        String reason = 'Typed wrong',
      }) => YorksAccountsPaymentCorrectionInput(
        projectId: 'p1',
        invoiceId: 'i1',
        expectedVersion: 2,
        originalPaymentId: 'pay1',
        paymentDate: _date,
        paymentMethod: 'cash',
        paymentReference: reference,
        amount: _d(amount),
        reason: reason,
      );
      expect(input().isValid, isTrue);
      expect(input(amount: '0').isValid, isFalse);
      expect(input(reference: ' ').isValid, isFalse);
      expect(input(reason: ' ').isValid, isFalse);
    });

    test('certification may be zero, which undoes it', () {
      YorksAccountsCertificationCorrectionInput input(
        String amount, {
        String reason = 'Consultant cut it',
      }) => YorksAccountsCertificationCorrectionInput(
        projectId: 'p1',
        invoiceId: 'i1',
        expectedVersion: 2,
        certificationReference: 'CERT-2',
        certificationDate: _date,
        certifiedExVat: _d(amount),
        reason: reason,
      );
      expect(input('0').isValid, isTrue);
      expect(input('-1').isValid, isFalse);
      expect(input('10', reason: ' ').isValid, isFalse);
    });

    test('cheque', () {
      YorksAccountsPdcEditInput input({
        String number = 'CHQ-1',
        String amount = '10',
        String reason = 'Typed wrong',
      }) => YorksAccountsPdcEditInput(
        projectId: 'p1',
        pdcId: 'pdc1',
        expectedVersion: 2,
        chequeNumber: number,
        chequeDate: _date,
        amount: _d(amount),
        bankName: null,
        reason: reason,
      );
      expect(input().isValid, isTrue);
      expect(input(number: ' ').isValid, isFalse);
      expect(input(amount: '0').isValid, isFalse);
      expect(input(reason: ' ').isValid, isFalse);
    });

    test('supplier payment', () {
      YorksAccountsSupplierPaymentCorrectionInput input({
        String reason = 'x',
      }) => YorksAccountsSupplierPaymentCorrectionInput(
        projectId: 'p1',
        supplierBillId: 'b1',
        expectedVersion: 2,
        originalPaymentId: 'sp1',
        paymentDate: _date,
        paymentMethod: 'cash',
        paymentReference: 'SP-1',
        amount: _d('10'),
        reason: reason,
      );
      expect(input().isValid, isTrue);
      expect(input(reason: ' ').isValid, isFalse);
    });

    test('a supplier reversal needs only a reason', () {
      final input = YorksAccountsSupplierPaymentReversalInput(
        projectId: 'p1',
        supplierBillId: 'b1',
        expectedVersion: 2,
        originalPaymentId: 'sp1',
        reversalDate: _date,
        reversalReference: '',
        reason: 'Paid twice',
      );
      expect(input.isValid, isTrue);
    });
  });

  group('cheque steps', () {
    test('stepping back is told apart from moving on', () {
      expect(
        _cheque(
          YorksAccountsPdcStatus.received,
        ).isBackwardMove(YorksAccountsPdcStatus.deposited),
        isFalse,
      );
      expect(
        _cheque(
          YorksAccountsPdcStatus.received,
        ).isBackwardMove(YorksAccountsPdcStatus.expected),
        isTrue,
      );
      expect(
        _cheque(
          YorksAccountsPdcStatus.deposited,
        ).isBackwardMove(YorksAccountsPdcStatus.received),
        isTrue,
      );
      expect(
        _cheque(
          YorksAccountsPdcStatus.cleared,
        ).isBackwardMove(YorksAccountsPdcStatus.deposited),
        isTrue,
      );
      expect(
        _cheque(
          YorksAccountsPdcStatus.cancelled,
        ).isBackwardMove(YorksAccountsPdcStatus.expected),
        isTrue,
      );
    });

    test('details can be edited unless cleared or replaced', () {
      for (final status in YorksAccountsPdcStatus.values) {
        expect(
          _cheque(status).canEditDetails,
          status != YorksAccountsPdcStatus.cleared &&
              status != YorksAccountsPdcStatus.replaced,
          reason: status.name,
        );
      }
    });

    test('moving a cheque back to expected is a valid command', () {
      final input = YorksAccountsPdcTransitionInput(
        projectId: 'p1',
        pdcId: 'pdc1',
        expectedVersion: 2,
        targetStatus: YorksAccountsPdcStatus.expected,
        actionDate: _date,
        clearanceReference: null,
        reason: 'Not in hand',
      );
      expect(input.isValid, isTrue);
    });
  });

  group('commands stay readable from an older server', () {
    Map<String, dynamic> receivables() => {
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
    };

    test('receivables', () {
      final old = YorksAccountsReceivablesCommands.fromRpcJson(receivables());
      expect(old.correctPayment, isFalse);
      expect(old.correctCertification, isFalse);
      expect(old.editPdc, isFalse);
      final current = YorksAccountsReceivablesCommands.fromRpcJson({
        ...receivables(),
        'correct_payment': true,
        'correct_certification': true,
        'edit_pdc': true,
      });
      expect(current.correctPayment, isTrue);
      expect(current.correctCertification, isTrue);
      expect(current.editPdc, isTrue);
    });

    test('supplier', () {
      const base = {
        'create_bill': true,
        'edit_bill': true,
        'approve_bill': true,
        'record_payment': true,
        'reverse_payment': true,
        'cancel_bill': true,
      };
      final old = YorksAccountsSupplierCommands.fromRpcJson(base);
      expect(old.correctPayment, isFalse);
      expect(old.reopenBill, isFalse);
      final current = YorksAccountsSupplierCommands.fromRpcJson({
        ...base,
        'correct_payment': true,
        'reopen_bill': true,
      });
      expect(current.correctPayment, isTrue);
      expect(current.reopenBill, isTrue);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/accounts/domain/accounts_decimal.dart';
import 'package:material_ledger/features/accounts/domain/accounts_receivables_inputs.dart';
import 'package:material_ledger/features/accounts/domain/v2/pdc_register_models.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_common.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_pdc_register_card.dart';
import 'package:material_ledger/shared/models/app_language.dart';

YorksAccountsProjectPdc _pdc({
  String chequeNumber = 'CHQ-001',
  String invoiceReference = 'YRA32201',
  String amount = '52500.00',
  YorksAccountsPdcStatus status = YorksAccountsPdcStatus.expected,
  int recordVersion = 1,
  bool actionRequired = false,
}) => YorksAccountsProjectPdc(
  pdcId: 'pdc1',
  invoiceId: 'i1',
  invoiceReference: invoiceReference,
  chequeNumber: chequeNumber,
  chequeDate: YorksAccountsDate.parse('2026-09-15'),
  receivedDate: null,
  bankName: 'Test Bank',
  amount: YorksAccountsDecimal.parse(amount),
  status: status,
  actionRequired: actionRequired,
  recordVersion: recordVersion,
);

YorksAccountsProjectPdcRegister _register(List<YorksAccountsProjectPdc> pdcs) =>
    YorksAccountsProjectPdcRegister(
      schemaVersion: 1,
      projectId: 'p1',
      pdcs: pdcs,
    );

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

  group('AccountsV2PdcRegisterCard', () {
    testWidgets('lists cheques joined to their invoice reference', (
      tester,
    ) async {
      _wideSurface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2PdcRegisterCard(
            projectId: 'p1',
            register: _register([_pdc()]),
            language: en,
            canManage: true,
            onTransition: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(t('v2_pdc_register_title')), findsOneWidget);
      expect(find.text('CHQ-001'), findsOneWidget);
      expect(find.text('YRA32201'), findsOneWidget);
      expect(find.text('52,500.00'), findsOneWidget);
      // A freshly recorded cheque is "Expected" (in hand, not yet deposited).
      expect(find.text(t('v2_pdc_expected')), findsWidgets);
      expect(find.text(t('v2_pdc_update')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the empty state with no cheques', (tester) async {
      _wideSurface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2PdcRegisterCard(
            projectId: 'p1',
            register: _register(const []),
            language: en,
            canManage: true,
            onTransition: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(t('v2_pdc_empty')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hides the Update control without manage_pdc', (tester) async {
      _wideSurface(tester);
      await tester.pumpWidget(
        _wrap(
          AccountsV2PdcRegisterCard(
            projectId: 'p1',
            register: _register([_pdc()]),
            language: en,
            canManage: false,
            onTransition: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(t('v2_pdc_update')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('deposits a cheque through the transition dialog', (
      tester,
    ) async {
      _wideSurface(tester);
      YorksAccountsPdcTransitionInput? captured;
      await tester.pumpWidget(
        _wrap(
          AccountsV2PdcRegisterCard(
            projectId: 'p1',
            register: _register([
              _pdc(status: YorksAccountsPdcStatus.received, recordVersion: 2),
            ]),
            language: en,
            canManage: true,
            onTransition: (i) async {
              captured = i;
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(t('v2_pdc_update')));
      await tester.pumpAndSettle();
      // Move to Deposited (a received cheque's first option, no extra fields).
      await tester.tap(find.text(t('v2_pdc_deposited')).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_confirm')));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.pdcId, 'pdc1');
      expect(captured!.expectedVersion, 2);
      expect(captured!.targetStatus, YorksAccountsPdcStatus.deposited);
      expect(find.text(t('v2_pdc_saved')), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('clearing a cheque requires a clearance reference', (
      tester,
    ) async {
      _wideSurface(tester);
      YorksAccountsPdcTransitionInput? captured;
      await tester.pumpWidget(
        _wrap(
          AccountsV2PdcRegisterCard(
            projectId: 'p1',
            register: _register([
              _pdc(status: YorksAccountsPdcStatus.deposited, recordVersion: 3),
            ]),
            language: en,
            canManage: true,
            onTransition: (i) async {
              captured = i;
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(t('v2_pdc_update')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_pdc_cleared')).last);
      await tester.pumpAndSettle();

      // Confirm is disabled until the clearance reference is filled.
      final confirm = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, t('v2_confirm')),
      );
      expect(confirm.onPressed, isNull);

      await tester.enterText(
        find.widgetWithText(TextField, t('v2_pdc_clearance_ref')),
        'BANK-REF-9',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_confirm')));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.targetStatus, YorksAccountsPdcStatus.cleared);
      expect(captured!.clearanceReference, 'BANK-REF-9');
      expect(tester.takeException(), isNull);
    });
  });
}

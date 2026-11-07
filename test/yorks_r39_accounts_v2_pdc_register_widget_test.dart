import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/accounts/domain/accounts_decimal.dart';
import 'package:material_ledger/features/accounts/domain/accounts_receivables_inputs.dart';
import 'package:material_ledger/features/accounts/domain/v2/pdc_register_models.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_common.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_pdc_register_card.dart';
import 'package:material_ledger/features/accounts/presentation/v2/kit/accounts_v2_kit.dart';
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

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

/// The row's "⋯" menu: every move that is not the next step.
Finder _menu() =>
    find.byWidgetPredicate((w) => w is AccountsV2Icon && w.name == 'dots');

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

      expect(find.text(t('v2i_pdc_title')), findsOneWidget);
      expect(find.text('CHQ-001'), findsOneWidget);
      expect(find.text('YRA32201'), findsOneWidget);
      expect(find.text('52,500.00'), findsOneWidget);
      // A cheque recorded before it arrives is "Expected"; its next step leads.
      expect(find.text(t('v2i_ps_expected')), findsWidgets);
      expect(find.text(t('v2i_mark_received')), findsOneWidget);
      expect(_menu(), findsOneWidget);
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

      expect(find.text(t('v2i_no_records')), findsOneWidget);
      expect(find.text(t('v2i_pdc_empty_body')), findsOneWidget);
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

      expect(find.text(t('v2i_mark_received')), findsNothing);
      expect(_menu(), findsNothing);
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

      // An in-hand cheque's next step is Mark deposited, right on the row.
      expect(find.text(t('v2i_ps_inhand')), findsOneWidget);
      await tester.tap(find.text(t('v2i_mark_deposited')));
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

    testWidgets(
      'undoing clearing needs a reason and says the money comes back',
      (tester) async {
        _wideSurface(tester);
        YorksAccountsPdcTransitionInput? captured;
        await tester.pumpWidget(
          _wrap(
            AccountsV2PdcRegisterCard(
              projectId: 'p1',
              register: _register([
                _pdc(status: YorksAccountsPdcStatus.cleared, recordVersion: 4),
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

        expect(find.text(t('v2i_done')), findsOneWidget);
        await tester.tap(_menu());
        await tester.pumpAndSettle();
        expect(find.text(t('v2_pdc_bounced_after')), findsOneWidget);
        // A cleared cheque has its clearing undone before its details change.
        expect(find.text(t('v2_pdc_edit')), findsNothing);
        await tester.tap(find.text(t('v2_pdc_undo_clearing')));
        await tester.pumpAndSettle();

        expect(find.text(t('v2_pdc_undo_money_hint')), findsOneWidget);
        final confirm = find.widgetWithText(FilledButton, t('v2_confirm'));
        expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
        await tester.enterText(find.byType(TextField).last, 'Wrong cheque');
        await tester.pumpAndSettle();
        await tester.tap(confirm);
        await tester.pumpAndSettle();

        expect(captured!.targetStatus, YorksAccountsPdcStatus.deposited);
        expect(captured!.reason, 'Wrong cheque');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a bounced cheque can be re-presented or replaced', (
      tester,
    ) async {
      _wideSurface(tester);
      YorksAccountsPdcTransitionInput? captured;
      await tester.pumpWidget(
        _wrap(
          AccountsV2PdcRegisterCard(
            projectId: 'p1',
            register: _register([
              _pdc(
                status: YorksAccountsPdcStatus.bounced,
                recordVersion: 3,
                actionRequired: true,
              ),
            ]),
            language: en,
            canManage: true,
            onTransition: (i) async {
              captured = i;
              return null;
            },
            onReplace: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_menu());
      await tester.pumpAndSettle();
      expect(find.text(t('v2_pdc_replace')), findsOneWidget);
      // Close the menu; Re-presented is the row's own button.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2i_represented')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Client asked');
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_confirm')));
      await tester.pumpAndSettle();

      expect(captured!.targetStatus, YorksAccountsPdcStatus.received);
      expect(tester.takeException(), isNull);
    });

    testWidgets('edits a cheque, prefilled, and only with a reason', (
      tester,
    ) async {
      _wideSurface(tester);
      YorksAccountsPdcEditInput? captured;
      await tester.pumpWidget(
        _wrap(
          AccountsV2PdcRegisterCard(
            projectId: 'p1',
            register: _register([
              _pdc(status: YorksAccountsPdcStatus.received, recordVersion: 2),
            ]),
            language: en,
            canManage: true,
            onTransition: (_) async => null,
            onEdit: (i) async {
              captured = i;
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_menu());
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_pdc_edit')));
      await tester.pumpAndSettle();

      expect(find.text('CHQ-001'), findsWidgets);
      final confirm = find.widgetWithText(FilledButton, t('v2_confirm'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.enterText(find.byType(TextField).last, 'Typed it wrong');
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(captured!.pdcId, 'pdc1');
      expect(captured!.expectedVersion, 2);
      expect(captured!.chequeNumber, 'CHQ-001');
      expect(captured!.amount.postgresText, '52500');
      expect(captured!.reason, 'Typed it wrong');
      expect(tester.takeException(), isNull);
    });

    test('every state but replaced has a way out', () {
      for (final status in YorksAccountsPdcStatus.values) {
        final next = _pdc(status: status).nextStatuses;
        if (status == YorksAccountsPdcStatus.replaced) {
          expect(next, isEmpty);
        } else {
          expect(next, isNotEmpty, reason: status.name);
        }
      }
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

      await tester.tap(find.text(t('v2i_cleared_btn')));
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

    testWidgets('replaces a bounced cheque with a re-presented one', (
      tester,
    ) async {
      _wideSurface(tester);
      YorksAccountsPdcReplacementInput? captured;
      await tester.pumpWidget(
        _wrap(
          AccountsV2PdcRegisterCard(
            projectId: 'p1',
            register: _register([
              _pdc(
                status: YorksAccountsPdcStatus.bounced,
                recordVersion: 4,
                actionRequired: true,
              ),
            ]),
            language: en,
            canManage: true,
            onTransition: (_) async => null,
            onReplace: (i) async {
              captured = i;
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A bounced cheque can be replaced from the same menu as its other steps.
      await tester.tap(_menu());
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_pdc_replace')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, t('v2_pdc_replace_cheque')),
        'CHQ-002',
      );
      await tester.enterText(
        find.widgetWithText(TextField, t('v2_pdc_reason')),
        'Re-presented after bounce',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2_confirm')));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.originalPdcId, 'pdc1');
      expect(captured!.expectedVersion, 4);
      expect(captured!.chequeNumber, 'CHQ-002');
      expect(captured!.reason, 'Re-presented after bounce');
      // Amount defaults to the original cheque's value (52,500.00).
      expect(captured!.amount, YorksAccountsDecimal.parse('52500.00'));
      expect(find.text(t('v2_pdc_saved')), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}

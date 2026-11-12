import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/accounts/application/accounts_providers.dart';
import 'package:material_ledger/features/accounts/application/accounts_records_providers.dart';
import 'package:material_ledger/features/accounts/data/accounts_records_repository.dart';
import 'package:material_ledger/features/accounts/domain/accounts_records_models.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_common.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_history_tab.dart';
import 'package:material_ledger/features/accounts/presentation/v2/accounts_v2_summary_tab.dart';
import 'package:material_ledger/features/accounts/presentation/v2/yorks_accounts_workspace_v2_screen.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

YorksAccountsActivityEntry _entry({
  required String id,
  required String eventType,
  required String entityType,
  required String actor,
}) => YorksAccountsActivityEntry(
  id: id,
  eventType: eventType,
  entityType: entityType,
  entityId: 'e-$id',
  projectId: 'p1',
  actorAuthUserId: 'u-$id',
  actorDisplayName: actor,
  actorExactRole: 'accountant',
  occurredAt: DateTime.utc(2026, 8, 26, 10, 30),
  reason: 'reason $id',
);

YorksAccountsActivityProjection _projection() =>
    YorksAccountsActivityProjection(
      projectId: 'p1',
      total: 3,
      limit: 50,
      offset: 0,
      entries: [
        _entry(
          id: '1',
          eventType: 'claim_submitted',
          entityType: 'accounts_client_claim',
          actor: 'Sara PM',
        ),
        _entry(
          id: '2',
          eventType: 'invoice_issued',
          entityType: 'accounts_client_invoice',
          actor: 'Omar Acc',
        ),
        _entry(
          id: '3',
          eventType: 'supplier_bill_approved',
          entityType: 'accounts_supplier_bill',
          actor: 'Omar Acc',
        ),
      ],
    );

final class _FakeRecords implements YorksAccountsRecordsRepository {
  _FakeRecords(this.projection);
  final YorksAccountsActivityProjection projection;

  @override
  Future<YorksAccountsActivityProjection> getActivity(
    String projectId,
    YorksAccountsActivityFilters filters,
  ) async => projection;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _wideSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  group('history event titles', () {
    Future<void> pump(WidgetTester tester, String eventType) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AccountsV2HistoryTab(
                language: AppLanguage.english,
                projection: YorksAccountsActivityProjection(
                  projectId: 'p1',
                  total: 1,
                  limit: 50,
                  offset: 0,
                  entries: [
                    _entry(
                      id: '1',
                      eventType: eventType,
                      entityType: 'accounts_client_pdc',
                      actor: 'Omar Acc',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

    testWidgets('a known event reads as a sentence', (tester) async {
      await pump(tester, 'accounts.client_pdc.cleared');
      expect(find.text('Cheque cleared'), findsOneWidget);
      expect(find.textContaining('accounts.'), findsNothing);
    });

    testWidgets('an unknown event still never shows a raw key', (tester) async {
      await pump(tester, 'accounts.some_future.event_name');
      expect(find.text('Some future event name'), findsOneWidget);
    });

    test('every known event has its own text in each language', () {
      for (final key in yorksAccountsV2HistoryEventKeys.values) {
        for (final language in AppLanguage.values) {
          expect(accountsV2Text(language, key), isNot(key), reason: key);
        }
      }
    });
  });

  const en = AppLanguage.english;
  String t(String key) => accountsV2Text(en, key);

  group('AccountsV2HistoryTab (direct)', () {
    testWidgets('renders the timeline and the files panel', (tester) async {
      _wideSurface(tester);
      await tester.pumpWidget(
        _wrap(AccountsV2HistoryTab(projection: _projection(), language: en)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Claim submitted'), findsOneWidget);
      expect(find.text('Invoice issued'), findsOneWidget);
      expect(find.text('Supplier bill approved'), findsOneWidget);
      expect(find.text(t('v2h_activity')), findsOneWidget);
      // Internal wording such as "Append-only" is not shown.
      expect(find.text(t('v2h_append_only')), findsNothing);
      expect(find.text(t('v2h_register')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an entry opens the record it is about', (tester) async {
      _wideSurface(tester);
      final opened = <AccountsV2OverviewTarget>[];
      await tester.pumpWidget(
        _wrap(
          AccountsV2HistoryTab(
            projection: _projection(),
            language: en,
            onOpenRecord: opened.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.chevron_right), findsNWidgets(3));
      await tester.tap(find.text('Invoice issued'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supplier bill approved'));
      await tester.pumpAndSettle();
      expect(opened.first.tab, YorksAccountsWorkspaceV2Tab.invoices);
      expect(opened.first.invoiceId, isNotNull);
      expect(opened.last.tab, YorksAccountsWorkspaceV2Tab.supplierBills);
      expect(opened.last.billId, isNotNull);
    });

    testWidgets('the search finds an entry by person or words', (tester) async {
      _wideSurface(tester);
      await tester.pumpWidget(
        _wrap(AccountsV2HistoryTab(projection: _projection(), language: en)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, t('v2h_search')),
        'invoice',
      );
      await tester.pumpAndSettle();
      expect(find.text('Invoice issued'), findsOneWidget);
      expect(find.text('Claim submitted'), findsNothing);
    });

    testWidgets('lays out at 360px', (tester) async {
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _wrap(AccountsV2HistoryTab(projection: _projection(), language: en)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Claim submitted'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the record type narrows the timeline', (tester) async {
      _wideSurface(tester);
      await tester.pumpWidget(
        _wrap(AccountsV2HistoryTab(projection: _projection(), language: en)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(t('v2h_all')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('v2h_claims')).last);
      await tester.pumpAndSettle();

      expect(find.text('Claim submitted'), findsOneWidget);
      expect(find.text('Invoice issued'), findsNothing);
      expect(find.text('Supplier bill approved'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('YorksAccountsWorkspaceV2Screen (History tab)', () {
    testWidgets('opening on history loads the activity from the repository', (
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
          yorksAccountsRecordsRepositoryProvider.overrideWithValue(
            _FakeRecords(_projection()),
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
                initialTab: YorksAccountsWorkspaceV2Tab.history,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Claim submitted'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

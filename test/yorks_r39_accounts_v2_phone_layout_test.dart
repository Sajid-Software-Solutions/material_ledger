// R39 Accounts Workspace V2 — the phone experience: figures never cut short,
// tables as cards, compact filters, a save bar always in reach and tap
// targets of at least 44px.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/accounts/presentation/v2/kit/accounts_v2_kit.dart';

void _phone(WidgetTester tester, {double height = 800}) {
  tester.view.physicalSize = Size(360, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('a KPI figure is shown in full, never with an ellipsis', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(
        const AccountsV2KpiRow(
          children: [
            AccountsV2KpiCard(
              icon: 'doc',
              label: 'Contract value',
              value: 'AED 117,192,000.00',
              caption: 'Excluding VAT',
            ),
            AccountsV2KpiCard(
              icon: 'doc',
              label: 'Invoiced',
              value: 'AED 1,700,000.00',
              caption: '',
            ),
            AccountsV2KpiCard(
              icon: 'doc',
              label: 'Received',
              value: 'AED 1,000,000.00',
              caption: '',
            ),
          ],
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('AED 117,192,000.00'));
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    expect(
      find.ancestor(
        of: find.text('AED 117,192,000.00'),
        matching: find.byType(FittedBox),
      ),
      findsOneWidget,
    );
    // Three cards: two share a row, the last takes a whole row.
    final first = tester.getSize(find.byType(AccountsV2KpiCard).first);
    final last = tester.getSize(find.byType(AccountsV2KpiCard).last);
    expect(last.width, greaterThan(first.width * 1.8));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a table becomes cards on a phone', (tester) async {
    _phone(tester);
    var opened = 0;
    await tester.pumpWidget(
      _app(
        AccountsV2Table(
          phoneCards: true,
          minWidth: 900,
          columns: const [
            AccountsV2Column('Invoice'),
            AccountsV2Column('Due', width: 110),
            AccountsV2Column('Balance', width: 120, numeric: true),
            AccountsV2Column('Status', width: 100, cardBadge: true),
          ],
          rows: [
            AccountsV2Row(const [
              Text('YRA322-01'),
              Text('10 Oct 2026'),
              Text('550,000.00'),
              Text('Overdue'),
            ], onTap: () => opened++),
          ],
        ),
      ),
    );
    // No sideways scrolling, every column labelled, the row opens.
    expect(
      find.descendant(
        of: find.byType(AccountsV2Table),
        matching: find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
      ),
      findsNothing,
    );
    expect(find.text('Due'), findsOneWidget);
    expect(find.text('Balance'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    await tester.tap(find.text('YRA322-01'));
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the same table stays a table on a desktop', (tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(
        AccountsV2Table(
          phoneCards: true,
          columns: const [AccountsV2Column('Invoice'), AccountsV2Column('Due')],
          rows: [
            AccountsV2Row(const [Text('YRA322-01'), Text('10 Oct 2026')]),
          ],
        ),
      ),
    );
    expect(find.text('INVOICE'), findsOneWidget, reason: 'the header band');
  });

  testWidgets('phone filters sit two to a row, none hidden', (tester) async {
    _phone(tester);
    Widget select(String label) => AccountsV2Select<String>(
      label: label,
      value: 'all',
      options: const [('all', 'All')],
      onChanged: (_) {},
    );
    await tester.pumpWidget(
      _app(
        AccountsV2PhoneFilters(
          selects: [select('Building'), select('Stage'), select('Show')],
        ),
      ),
    );
    final a = tester.getRect(find.text('Building'));
    final b = tester.getRect(find.text('Stage'));
    final c = tester.getRect(find.text('Show'));
    expect(a.top, closeTo(b.top, 1), reason: 'the first two share a row');
    expect(c.top, greaterThan(a.bottom), reason: 'the third has its own row');
    expect(c.right, lessThanOrEqualTo(360), reason: 'nothing off-screen');
  });

  testWidgets('the bottom bar host keeps a bar in reach and removes it', (
    tester,
  ) async {
    _phone(tester, height: 600);
    final show = ValueNotifier(true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountsV2BottomBarHost(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 2000),
                  ValueListenableBuilder<bool>(
                    valueListenable: show,
                    builder: (_, visible, _) => visible
                        ? const AccountsV2BottomBar(child: Text('Save bar'))
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Visible without scrolling, pinned at the bottom of the screen.
    final bar = tester.getRect(find.text('Save bar'));
    expect(bar.bottom, lessThanOrEqualTo(600));
    expect(bar.top, greaterThan(500));
    show.value = false;
    await tester.pumpAndSettle();
    expect(find.text('Save bar'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('buttons and fields are 44px tap targets on a phone', (
    tester,
  ) async {
    _phone(tester);
    final field = TextEditingController();
    addTearDown(field.dispose);
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            AccountsV2Button(
              label: 'Small',
              size: AccountsV2ButtonSize.small,
              onPressed: () {},
            ),
            AccountsV2TextField(label: 'Reference', controller: field),
          ],
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(AccountsV2Button)).height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester.getSize(find.byType(TextField)).height,
      greaterThanOrEqualTo(44),
    );
  });
}

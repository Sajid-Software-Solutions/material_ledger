import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/app/yorks_v1_workspace_shell.dart';
import 'package:material_ledger/core/widgets/yorks_mobile_ui.dart';
import 'package:material_ledger/shared/models/app_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_shell_strings.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _shellContentKey = Key('mobile-shell-content');
const _scrollKey = Key('mobile-shell-scroll');
const _lastActionKey = Key('mobile-shell-last-action');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    '720px shell navigation is one equal-width row with 44px targets',
    (tester) async {
      await _setViewport(tester, const Size(720, 800));

      await _pumpShell(
        tester,
        child: const ColoredBox(key: _shellContentKey, color: Colors.white),
      );

      expect(find.byType(YorksMobileAppBar), findsOneWidget);
      expect(
        find.byKey(const ValueKey('yorks-mobile-navigation')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('yorks-compact-navigation-legacy')),
        findsNothing,
      );

      final itemBounds = <Rect>[];
      for (final label in _engineerNavigationLabels) {
        final item = _navigationSemantics(label);
        expect(item, findsOneWidget);

        final semanticBounds = tester.getRect(item);
        final tapTarget = find.descendant(
          of: item,
          matching: find.byType(InkWell),
        );
        expect(tapTarget, findsOneWidget);
        final tapBounds = tester.getRect(tapTarget);

        expect(semanticBounds.width, greaterThanOrEqualTo(44));
        expect(semanticBounds.height, greaterThanOrEqualTo(44));
        expect(tapBounds.width, greaterThanOrEqualTo(44));
        expect(tapBounds.height, greaterThanOrEqualTo(44));
        itemBounds.add(semanticBounds);
      }

      expect(itemBounds.map((rect) => rect.top).toSet(), hasLength(1));
      expect(itemBounds.map((rect) => rect.bottom).toSet(), hasLength(1));
      for (final bounds in itemBounds.skip(1)) {
        expect(bounds.width, closeTo(itemBounds.first.width, 0.01));
      }
      for (var index = 1; index < itemBounds.length; index++) {
        expect(
          itemBounds[index].left,
          closeTo(itemBounds[index - 1].right, 0.01),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('721px keeps the accepted compact-tablet navigation', (
    tester,
  ) async {
    await _setViewport(tester, const Size(721, 800));

    await _pumpShell(
      tester,
      child: const ColoredBox(key: _shellContentKey, color: Colors.white),
    );

    expect(
      find.byKey(const ValueKey('yorks-compact-navigation-legacy')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('yorks-mobile-navigation')), findsNothing);
    expect(
      _navigationSemantics(YorksV1ShellStrings.overview.primary),
      findsOneWidget,
    );
    expect(_navigationSemantics(AppStrings.home.primary), findsNothing);
    expect(find.byType(YorksMobileAppBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scroll content finishes fully above the mobile navigation', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));

    await _pumpShell(tester, child: const _LongScrollableContent());

    final lastAction = find.byKey(_lastActionKey);
    await tester.scrollUntilVisible(
      lastAction,
      320,
      scrollable: find.descendant(
        of: find.byKey(_scrollKey),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();

    final navigationTop = _engineerNavigationLabels
        .map((label) => tester.getRect(_navigationSemantics(label)).top)
        .reduce((left, right) => left < right ? left : right);
    final scrollBounds = tester.getRect(find.byKey(_scrollKey));
    final actionBounds = tester.getRect(lastAction);

    expect(scrollBounds.bottom, lessThanOrEqualTo(navigationTop));
    expect(actionBounds.bottom, lessThanOrEqualTo(scrollBounds.bottom));
    expect(actionBounds.bottom, lessThanOrEqualTo(navigationTop));
    expect(actionBounds.height, greaterThanOrEqualTo(44));
    expect(lastAction.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('project Accounts keeps one focused mobile top bar', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));

    await _pumpShell(
      tester,
      path: '/yorks/projects/project-1/accounts/overview',
      child: const Column(
        children: [
          YorksMobileAppBar(title: 'Accounts'),
          Expanded(
            child: ColoredBox(key: _shellContentKey, color: Colors.white),
          ),
        ],
      ),
    );

    expect(find.byType(YorksMobileAppBar), findsOneWidget);
    expect(find.text('Accounts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('1024px shell keeps the existing desktop sidebar/topbar branch', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1024, 768));

    await _pumpShell(
      tester,
      child: const SizedBox.expand(
        key: _shellContentKey,
        child: ColoredBox(color: Colors.white),
      ),
    );

    final contentBounds = tester.getRect(find.byKey(_shellContentKey));
    expect(find.byType(YorksMobileAppBar), findsNothing);
    expect(
      find.byTooltip(YorksV1ShellStrings.collapsePanel.primary),
      findsOneWidget,
    );
    expect(_navigationSemantics(AppStrings.more.primary), findsNothing);
    expect(contentBounds.width, greaterThan(0));
    expect(contentBounds.height, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}

final _engineerNavigationLabels = <String>[
  AppStrings.home.primary,
  YorksV1ShellStrings.projects.primary,
  YorksV1ShellStrings.materialRequests.primary,
  AppStrings.more.primary,
];

Finder _navigationSemantics(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.button == true &&
      widget.properties.label == label,
);

class _LongScrollableContent extends StatelessWidget {
  const _LongScrollableContent();

  @override
  Widget build(BuildContext context) => ListView(
    key: _scrollKey,
    padding: EdgeInsets.zero,
    children: const [
      SizedBox(height: 1200),
      SizedBox(
        key: _lastActionKey,
        height: 44,
        child: ColoredBox(color: Colors.blue),
      ),
    ],
  );
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required Widget child,
  String path = '/',
}) async {
  final preferences = await SharedPreferences.getInstance();
  final router = GoRouter(
    initialLocation: path,
    routes: [
      GoRoute(
        path: path,
        builder: (_, _) => YorksV1WorkspaceShell(child: child),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksV1CurrentRoleProvider.overrideWithValue(
          YorksV1Role.projectEngineer,
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

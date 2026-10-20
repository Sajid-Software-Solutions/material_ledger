import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/app/router.dart';
import 'package:material_ledger/app/yorks_v1_workspace_shell.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/rentals/presentation/screens/yorks_v1_rental_screens.dart';
import 'package:material_ledger/shared/models/user_role.dart';
import 'package:material_ledger/shared/models/app_user.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_rental.dart';
import 'package:material_ledger/shared/models/yorks_v1_rental_action.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_rental_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: unused_import
import 'package:material_ledger/features/rentals/presentation/screens/yorks_v1_rental_screens.dart'
    deferred as rental_library;

Map<String, dynamic> _property({String id = 'office-1'}) => {
  'id': id,
  'unit_code': 'OFFICE-1',
  'property_name': 'Office 1',
  'property_type': 'office',
  'occupancy_state': 'occupied',
  'record_version': 1,
  'lease_id': 'lease-1',
  'tenant_name': 'Example Tenant',
  'rent_frequency': 'annual',
  'annual_rent': 24000,
  'billing_setup_pending': true,
  'lease_end': '2026-10-01',
  'days_to_lease_end': -19,
  'renewal_notice_days': 90,
  'missing_fields': ['location', 'contact_number', 'billing_start'],
};
final _portfolio = YorksV1RentalPortfolio.fromJson({
  'properties': [_property()],
  'summary': {'total_properties': 1},
});
final _detail = YorksV1RentalPropertyDetail.fromJson({'property': _property()});

void main() {
  final scenarios = <(String, WidgetTesterCallback)>[];
  void rentalScenario(String name, WidgetTesterCallback body) =>
      scenarios.add((name, body));
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await rental_library.loadLibrary();
    var cache = File(Platform.resolvedExecutable).parent;
    while (!cache.path.endsWith('${Platform.pathSeparator}cache')) {
      if (cache.parent.path == cache.path) {
        throw StateError('Flutter cache missing');
      }
      cache = cache.parent;
    }
    final icons = await File(
      '${cache.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(icons)))).load();
    await (FontLoader(
      'NexusSans',
    )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
    await (FontLoader('NotoSansArabic')
          ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf')))
        .load();
  });

  test('guidance separates confirmed rent, optional fields and vacancy', () {
    expect(rentalActions(YorksV1RentalProperty.fromJson(_property())), [
      YorksRentalAction.expiredLease,
      YorksRentalAction.billing,
      YorksRentalAction.details,
    ]);
    expect(
      rentalActions(
        YorksV1RentalProperty.fromJson({
          ..._property(),
          'occupancy_state': 'vacant',
          'missing_fields': [],
          'billing_setup_pending': false,
          'lease_end': null,
        }),
      ),
      isEmpty,
    );
    expect(
      rentalActions(
        YorksV1RentalProperty.fromJson({
          ..._property(),
          'outstanding': 500,
          'is_archived': true,
        }),
      ),
      isEmpty,
    );
    expect(
      rentalActions(
        YorksV1RentalProperty.fromJson({
          ..._property(),
          'outstanding': 500,
          'billing_setup_pending': false,
          'is_archived': true,
        }),
      ),
      [YorksRentalAction.rent],
    );
    expect(YorksRentalAction.fromName('delete'), isNull);
  });

  for (final size in [const Size(1366, 768), const Size(360, 800)]) {
    rentalScenario(
      'real rental routes keep shell, action context and back/forward $size',
      (tester) async {
        final router = _router('/rentals');
        addTearDown(router.dispose);
        await _mount(tester, router, size);
        expect(find.byType(YorksV1WorkspaceShell), findsOneWidget);
        expect(find.text('Lease expired'), findsOneWidget);
        expect(find.textContaining('01 Oct 2026'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('rental-attention-office-1')),
        );
        await tester.tap(
          find.byKey(const ValueKey('rental-attention-office-1')),
        );
        await _settle(tester);
        expect(find.byType(YorksV1WorkspaceShell), findsOneWidget);
        expect(find.byType(YorksV1RentalPropertyScreen), findsOneWidget);
        expect(
          find.byKey(const ValueKey('rental-action-expiredLease')),
          findsOneWidget,
        );
        expect(
          find.textContaining('Site location, Contact number'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/r38_4/rental_action_shell_${size.width.toInt()}.png',
          ),
        );

        // Native root stack is preserved, so the universal header uses its
        // existing behavior. No global navigation helper is changed.
        final back = size.width > 720
            ? find.byKey(const ValueKey('yorks-workspace-back'))
            : find.byTooltip('Back');
        await tester.tap(back.first);
        await _settle(tester);
        expect(router.routerDelegate.currentConfiguration.uri.path, '/rentals');
        expect(find.byType(YorksV1RentalDashboardScreen), findsOneWidget);
        expect(find.byType(YorksV1RentalPropertyScreen), findsNothing);
        if (size.width > 720) {
          await tester.tap(
            find.byKey(const ValueKey('yorks-workspace-forward')),
          );
          await _settle(tester);
          expect(find.byType(YorksV1RentalPropertyScreen), findsOneWidget);
          expect(await tester.binding.handlePopRoute(), isTrue);
          await _settle(tester);
          expect(
            router.routerDelegate.currentConfiguration.uri.path,
            '/rentals',
          );
          expect(find.byType(YorksV1RentalDashboardScreen), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );

    rentalScenario('direct rental link falls back to register $size', (
      tester,
    ) async {
      final router = _router('/rentals/office-1?action=details');
      addTearDown(router.dispose);
      await _mount(tester, router, size);
      expect(find.byType(YorksV1WorkspaceShell), findsOneWidget);
      final back = size.width > 720
          ? find.byKey(const ValueKey('yorks-workspace-back'))
          : find.byTooltip('Back');
      await tester.tap(back.first);
      await _settle(tester);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/rentals');
      expect(find.byType(YorksV1RentalDashboardScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  rentalScenario(
    'explicit missing-detail action opens editable form without saving',
    (tester) async {
      final router = _router('/rentals/office-1?action=details');
      addTearDown(router.dispose);
      await _mount(tester, router, const Size(1366, 768));
      final action = find.byKey(const ValueKey('rental-action-details'));
      await tester.ensureVisible(action);
      await tester.tap(action);
      await _settle(tester);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(TextFormField), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  rentalScenario('invalid action is ignored and resolved action is explained', (
    tester,
  ) async {
    final router = _router('/rentals/office-1?action=rent');
    addTearDown(router.dispose);
    await _mount(tester, router, const Size(1366, 768));
    expect(
      find.textContaining('This item no longer needs attention'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('rental-action-rent')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  rentalScenario(
    'rent and cheque shortcuts select and reveal the correct phone section',
    (tester) async {
      final router = _router('/rentals/office-1?action=rent');
      addTearDown(router.dispose);
      final financial = YorksV1RentalPropertyDetail.fromJson({
        'property': {
          ..._property(),
          'billing_setup_pending': false,
          'outstanding': 200,
          'cheque_attention': true,
        },
      });
      await _mount(tester, router, const Size(360, 800), detail: financial);
      final rentAction = find.byKey(const ValueKey('rental-action-rent'));
      await tester.ensureVisible(rentAction);
      await tester.tap(rentAction);
      await _settle(tester);
      expect(find.text('Rent Schedule').hitTestable(), findsWidgets);
      final chequeAction = find.byKey(const ValueKey('rental-action-cheque'));
      await tester.ensureVisible(chequeAction);
      await tester.pump();
      await tester.tap(chequeAction);
      await _settle(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/r38_4/rental_action_cheques_360.png'),
      );
      expect(find.text('CDC / PDC').hitTestable(), findsWidgets);
      expect(find.text('Add cheque').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  rentalScenario('Arabic phone actions wrap at larger text size', (
    tester,
  ) async {
    final router = _router('/rentals/office-1?action=details');
    addTearDown(router.dispose);
    SharedPreferences.setMockInitialValues({'selected_language': 'ar'});
    await _mount(
      tester,
      router,
      const Size(360, 800),
      locale: const Locale('ar'),
      textScale: 1.3,
    );
    expect(find.text('إضافة البيانات الناقصة'), findsOneWidget);
    expect(find.text('استكمال البيانات'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/r38_4/rental_action_shell_ar_360.png'),
    );
  });

  for (final size in [const Size(1366, 768), const Size(360, 800)]) {
    rentalScenario(
      'action filters count overlapping issues and retain context $size',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final financial = {
          ..._property(),
          'billing_setup_pending': false,
          'outstanding': 200,
          'cheque_attention': true,
        };
        final portfolio = YorksV1RentalPortfolio.fromJson({
          'properties': [
            financial,
            {
              ..._property(id: 'office-2'),
              'unit_code': 'OFFICE-2',
              'lease_end': null,
              'missing_fields': [],
            },
          ],
          'summary': {'total_properties': 2},
        });
        final router = _router('/rentals');
        addTearDown(router.dispose);
        await _mount(
          tester,
          router,
          size,
          portfolio: portfolio,
          detail: YorksV1RentalPropertyDetail.fromJson({'property': financial}),
        );
        await _chooseFilter(tester, 'all', 'Rent (1)');
        expect(find.text('Rent balance to review'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('rental-attention-office-2')),
          findsNothing,
        );
        await _chooseFilter(tester, 'rent', 'Cheques (1)');
        expect(find.text('Cheque needs review'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('rental-attention-office-1')),
        );
        await _settle(tester);
        expect(find.byType(YorksV1RentalPropertyScreen), findsOneWidget);
        final back = size.width > 720
            ? find.byKey(const ValueKey('yorks-workspace-back'))
            : find.byTooltip('Back');
        await tester.tap(back.first);
        await _settle(tester);
        expect(
          find.byKey(const ValueKey('rental-action-filter-cheques')),
          findsOneWidget,
        );
        await _chooseFilter(tester, 'cheques', 'Billing setup (1)');
        expect(
          find.byKey(const ValueKey('rental-attention-office-1')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('rental-attention-office-2')),
          findsOneWidget,
        );
        await _chooseFilter(tester, 'billing', 'Missing details (1)');
        expect(find.text('Add missing details'), findsOneWidget);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/r38_4/rental_action_filter_${size.width.toInt()}.png',
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );

    rentalScenario(
      'missing-field shortcuts reveal collapsed groups and preserve edits $size',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final router = _router('/rentals/office-1?action=details');
        addTearDown(router.dispose);
        await _mount(
          tester,
          router,
          size,
          detail: YorksV1RentalPropertyDetail.fromJson({
            'property': {
              ..._property(),
              'occupancy_state': 'vacant',
              'lease_id': null,
            },
          }),
        );
        final action = find.byKey(const ValueKey('rental-action-details'));
        await tester.ensureVisible(action);
        await tester.tap(action);
        await _settle(tester);
        expect(
          find.widgetWithText(TextFormField, 'Location').hitTestable(),
          findsOneWidget,
        );
        expect(tester.testTextInput.isVisible, isFalse);
        final location = find.widgetWithText(TextFormField, 'Location');
        await tester.enterText(location, 'Draft location');
        tester.testTextInput.hide();
        await tester.tap(
          find.byKey(const ValueKey('rental-review-target-location')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Contact number').last);
        await _settle(tester);
        expect(
          find.widgetWithText(TextFormField, 'Contact Number').hitTestable(),
          findsOneWidget,
        );
        expect(find.text('Draft location'), findsOneWidget);
        expect(tester.testTextInput.isVisible, isFalse);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/r38_4/rental_review_contact_${size.width.toInt()}.png',
          ),
        );
        await tester.tap(find.text('Cancel'));
        await _settle(tester);
        expect(find.byType(Dialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  rentalScenario(
    'empty filter can reset and billing/lease actions reveal their fields',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final router = _router('/rentals');
      addTearDown(router.dispose);
      await _mount(tester, router, const Size(360, 800));
      await _chooseFilter(tester, 'all', 'Cheques (0)');
      expect(
        find.text('No properties need this action right now.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Show all actions'));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('rental-attention-office-1')));
      await _settle(tester);
      for (final entry in [
        ('billing', 'billingStart', 'First rent date to track'),
        ('expiredLease', 'leaseEnd', 'Lease End'),
      ]) {
        final action = find.byKey(ValueKey('rental-action-${entry.$1}'));
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        await tester.tap(action);
        await _settle(tester);
        expect(
          find.byKey(ValueKey('rental-review-target-${entry.$2}')),
          findsOneWidget,
        );
        expect(
          find
              .byWidgetPredicate(
                (widget) =>
                    widget is InputDecorator &&
                    widget.decoration.labelText == entry.$3,
              )
              .hitTestable(),
          findsOneWidget,
        );
        if (entry.$1 == 'billing') {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/r38_4/rental_review_billing_360.png'),
          );
        }
        await tester.tap(find.text('Cancel'));
        await _settle(tester);
      }
      expect(tester.takeException(), isNull);
    },
  );

  rentalScenario(
    'Arabic phone field review remains usable at larger text size',
    (tester) async {
      SharedPreferences.setMockInitialValues({'selected_language': 'ar'});
      final router = _router('/rentals/office-1?action=details');
      addTearDown(router.dispose);
      await _mount(
        tester,
        router,
        const Size(360, 800),
        locale: const Locale('ar'),
        textScale: 1.3,
      );
      final action = find.byKey(const ValueKey('rental-action-details'));
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      await tester.tap(action);
      await _settle(tester);
      expect(find.text('موقع العقار'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/r38_4/rental_review_ar_360.png'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  // The production deferred loader is shared for the app lifetime. Exercise
  // the route journeys in one test zone, matching that lifetime.
  testWidgets('rental route journeys at desktop and phone widths', (
    tester,
  ) async {
    for (final scenario in scenarios) {
      debugPrint('Rental journey: ${scenario.$1}');
      await scenario.$2(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}

GoRouter _router(String location) => createAppRouter(
  restoredLocation: location,
  isOnboarded: true,
  isLoggedIn: true,
  role: UserRole.admin,
  user: AppUser(
    id: 'rental-ux-admin',
    fullName: 'Owner',
    email: 'owner@example.test',
    role: UserRole.admin,
    createdAt: DateTime.utc(2026),
    yorksV1RoleCache: YorksV1Role.admin,
  ),
  yorksV1Role: YorksV1Role.admin,
  yorksV1ProjectsEnabled: true,
);

Future<void> _mount(
  WidgetTester tester,
  GoRouter router,
  Size size, {
  YorksV1RentalPropertyDetail? detail,
  YorksV1RentalPortfolio? portfolio,
  Locale locale = const Locale('en'),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksV1CurrentRoleProvider.overrideWithValue(YorksV1Role.admin),
        yorksV1FeatureFlagsProvider.overrideWithValue(
          const YorksV1FeatureFlags(foundation: true, projects: true),
        ),
        yorksV1RentalPortfolioProvider.overrideWith(
          (ref) async => portfolio ?? _portfolio,
        ),
        yorksV1RentalPropertyProvider(
          'office-1',
        ).overrideWith((ref) async => detail ?? _detail),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        theme: AppTheme.light,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [
          Locale('en'),
          Locale('ar'),
          Locale('ur'),
          Locale('hi'),
        ],
        routerConfig: router,
      ),
    ),
  );
  await tester.runAsync(() async {
    await rental_library.loadLibrary();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pump(const Duration(milliseconds: 100));

  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() async {
    await rental_library.loadLibrary();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

Future<void> _chooseFilter(
  WidgetTester tester,
  String current,
  String label,
) async {
  final field = find.byKey(ValueKey('rental-action-filter-$current'));
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await _settle(tester);
}

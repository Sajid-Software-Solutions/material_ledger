import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/rentals/presentation/screens/yorks_v1_rental_screens.dart';
import 'package:material_ledger/shared/models/yorks_v1_rental.dart';
import 'package:material_ledger/shared/models/yorks_v1_rental_save_receipt.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/providers/yorks_v1_rental_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_rental_repository.dart';

YorksV1RentalPropertyInput _input({
  String location = '',
  String contact = '',
  String contract = '',
}) => YorksV1RentalPropertyInput(
  propertyId: 'office-1',
  leaseId: 'lease-1',
  unitCode: 'OFFICE-1',
  propertyName: 'Office 1',
  propertyType: 'Office',
  location: location,
  contactNumber: contact,
  contractNumber: contract,
  occupancy: YorksV1RentalOccupancy.occupied,
  tenantName: 'Example Tenant',
  contractType: 'Tenancy Contract',
  contractStatus: 'Active',
  leaseStart: DateTime(2026, 1, 1),
  leaseEnd: DateTime(2026, 12, 31),
  monthlyRent: null,
  annualRent: 24000,
  securityDeposit: 0,
  monthlyDueDay: 1,
  gracePeriodDays: 5,
  defaultPaymentMethod: 'Bank Transfer',
  paymentFrequency: 'Annual',
  contractCheques: 0,
  annualEscalationPercent: 0,
  renewalNoticeDays: 90,
);

YorksV1RentalPropertyDetail _detail(
  YorksV1RentalPropertyInput input,
  int version, {
  bool billing = true,
}) => YorksV1RentalPropertyDetail.fromJson({
  'property': {
    ...input.toRpcPayload(),
    'id': 'office-1',
    'lease_id': 'lease-1',
    'record_version': version,
    'billing_setup_pending': billing,
    'missing_fields': [
      if (input.location.isEmpty) 'location',
      if (input.contactNumber?.isEmpty != false) 'contact_number',
      if (input.contractNumber.isEmpty) 'contract_number',
    ],
  },
  'lease': {'id': 'lease-1', 'contract_cheque_count': 0},
});

class _Repository implements YorksV1RentalRepository {
  YorksV1RentalPropertyInput current = _input();
  int version = 1;
  bool billing = true;
  bool failReadAfterSave = false;
  Object? saveFailure;
  Completer<YorksV1RentalPropertyDetail>? pendingRead;
  final savedVersions = <int?>[];

  @override
  Future<YorksV1RentalPropertyDetail> getProperty(String propertyId) async {
    if (savedVersions.isNotEmpty) {
      if (failReadAfterSave) throw StateError('Projection unavailable');
      if (pendingRead != null) return pendingRead!.future;
    }
    return _detail(current, version, billing: billing);
  }

  @override
  Future<String> saveProperty(
    YorksV1RentalPropertyInput input, {
    required int? expectedVersion,
    required String idempotencyKey,
  }) async {
    if (saveFailure != null) throw saveFailure!;
    expect(expectedVersion, version);
    savedVersions.add(expectedVersion);
    current = input;
    version++;
    return 'office-1';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _mount(
  WidgetTester tester,
  _Repository repo,
  Size size, {
  String locale = 'en',
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [yorksV1RentalRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: Locale(locale),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const YorksV1RentalPropertyScreen(propertyId: 'office-1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.text(locale == 'ar' ? 'تعديل العقار' : 'Edit property'),
  );
  await tester.pumpAndSettle();
}

Future<void> _setField(WidgetTester tester, String label, String value) async {
  final field = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester, {String locale = 'en'}) async {
  await tester.tap(find.text(locale == 'ar' ? 'حفظ العقار' : 'Save property'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    var cache = File(Platform.resolvedExecutable).parent;
    while (!cache.path.endsWith('${Platform.pathSeparator}cache')) {
      if (cache.parent.path == cache.path) {
        throw StateError('Flutter cache missing');
      }
      cache = cache.parent;
    }
    await (FontLoader('MaterialIcons')..addFont(
          Future.value(
            ByteData.sublistView(
              await File(
                '${cache.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytes(),
            ),
          ),
        ))
        .load();
    await (FontLoader(
      'NexusSans',
    )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
    await (FontLoader('NotoSansArabic')
          ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf')))
        .load();
  });

  test(
    'receipt compares normalized fields, includes clearing and omits source metadata',
    () {
      final before = _detail(_input(contact: '0500000000'), 1);
      final receipt = YorksRentalSaveReceipt(
        propertyId: 'office-1',
        before: before,
        input: _input(location: 'Abu Dhabi'),
      );
      expect(receipt.updatedFields(_detail(_input(location: 'Abu Dhabi'), 2)), [
        'location',
        'contact_number',
      ]);
      expect(receipt.clearedFields(_detail(_input(location: 'Abu Dhabi'), 2)), [
        'contact_number',
      ]);
      final unchanged = YorksRentalSaveReceipt(
        propertyId: 'office-1',
        before: _detail(_input(), 1),
        input: _input(),
      );
      expect(unchanged.updatedFields(_detail(_input(), 2)), isEmpty);
    },
  );

  test(
    'receipt reports persisted facts and never attributes a later version to this save',
    () {
      final receipt = YorksRentalSaveReceipt(
        propertyId: 'office-1',
        before: _detail(_input(), 1),
        input: _input(location: 'Requested location'),
      );
      expect(receipt.updatedFields(_detail(_input(), 2)), isEmpty);
      expect(
        receipt.matchesVersion(_detail(_input(location: 'Later edit'), 3)),
        isFalse,
      );
      expect(
        receipt.updatedFields(_detail(_input(location: 'Later edit'), 3)),
        isEmpty,
      );
      final vacant = YorksV1RentalPropertyDetail.fromJson({
        'property': {
          'id': 'office-1',
          'record_version': 1,
          'unit_code': 'OFFICE-1',
          'property_name': 'Office 1',
          'property_type': 'office',
          'occupancy_state': 'vacant',
        },
      });
      final created = YorksRentalSaveReceipt(
        propertyId: 'office-1',
        before: null,
        input: _input(),
      );
      expect(created.updatedFields(vacant), [
        'unit_code',
        'property_name',
        'property_type',
        'occupancy_state',
      ]);
    },
  );

  for (final size in [const Size(1366, 768), const Size(360, 800)]) {
    testWidgets(
      'save shows changes and current missing fields then continues with fresh version $size',
      (tester) async {
        final repo = _Repository();
        await _mount(tester, repo, size);
        await _setField(tester, 'Location', 'Abu Dhabi');
        await _save(tester);
        final receipt = find.byKey(const ValueKey('rental-save-confirmation'));
        expect(receipt, findsOneWidget);
        expect(find.text('Rental property saved.'), findsOneWidget);
        expect(find.text('Updated in this save'), findsOneWidget);
        expect(find.text('Site location'), findsOneWidget);
        expect(find.text('Still missing (2)'), findsOneWidget);
        expect(find.text('Contact number'), findsOneWidget);
        expect(find.text('Contract number'), findsOneWidget);
        expect(
          find.textContaining('Billing setup still needs review.'),
          findsOneWidget,
        );
        expect(find.text('Done').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/r38_4/rental_save_summary_${size.width.toInt()}.png',
          ),
        );
        await tester.tap(find.text('Complete remaining details'));
        await tester.pumpAndSettle();
        expect(find.text('Go to field'), findsOneWidget);
        expect(
          find.widgetWithText(TextFormField, 'Contact Number').hitTestable(),
          findsOneWidget,
        );
        expect(
          tester
              .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Location'),
              )
              .controller!
              .text,
          'Abu Dhabi',
        );
        await _setField(tester, 'Contact Number', '0500000000');
        await _save(tester);
        expect(repo.savedVersions, [1, 2]);
        expect(find.text('Still missing (1)'), findsOneWidget);
        expect(find.text('Site location'), findsNothing);
        expect(find.text('Contact number'), findsOneWidget);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(receipt, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'saved remains confirmed when refresh fails; retry reads without writing',
    (tester) async {
      final repo = _Repository()..failReadAfterSave = true;
      await _mount(tester, repo, const Size(360, 800));
      await _setField(tester, 'Location', 'Abu Dhabi');
      await _save(tester);
      expect(find.text('Rental property saved.'), findsOneWidget);
      expect(find.textContaining('We could not refresh'), findsOneWidget);
      expect(find.text('Complete remaining details'), findsNothing);
      expect(find.text('Still missing (3)'), findsNothing);
      repo.failReadAfterSave = false;
      await tester.tap(find.text('Refresh details'));
      await tester.pumpAndSettle();
      expect(find.text('Still missing (2)'), findsOneWidget);
      expect(repo.savedVersions, [1]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('no-change save and no remaining details are explicit', (
    tester,
  ) async {
    final repo = _Repository()
      ..current = _input(
        location: 'Abu Dhabi',
        contact: '0500000000',
        contract: 'LEASE-1',
      )
      ..billing = false;
    await _mount(tester, repo, const Size(360, 800));
    await _save(tester);
    expect(find.text('No field values changed.'), findsOneWidget);
    expect(find.text('No recommended details are missing.'), findsOneWidget);
    expect(find.text('Complete remaining details'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'confirmed save can be dismissed while projection is still loading',
    (tester) async {
      final repo = _Repository()
        ..pendingRead = Completer<YorksV1RentalPropertyDetail>();
      await _mount(tester, repo, const Size(360, 800));
      await tester.tap(find.text('Save property'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Rental property saved.'), findsOneWidget);
      expect(
        find.text('Checking saved changes and remaining details…'),
        findsOneWidget,
      );
      await tester.tap(find.text('Done'));
      await tester.pump();
      repo.pendingRead!.complete(_detail(repo.current, repo.version));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('rental-save-confirmation')),
        findsNothing,
      );
      expect(repo.savedVersions, [1]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rejected save never shows a success receipt', (tester) async {
    final repo = _Repository()
      ..saveFailure = const YorksV1DomainException(
        YorksV1DomainErrorCode.conflict,
      );
    await _mount(tester, repo, const Size(360, 800));
    await _save(tester);
    expect(
      find.byKey(const ValueKey('rental-save-confirmation')),
      findsNothing,
    );
    expect(find.textContaining('changed'), findsWidgets);
    expect(find.text('Save property'), findsOneWidget);
  });

  testWidgets('Arabic mobile save summary wraps at enlarged text scale', (
    tester,
  ) async {
    final repo = _Repository();
    await _mount(tester, repo, const Size(360, 800), locale: 'ar', scale: 1.3);
    await _setField(tester, 'Location', 'Abu Dhabi');
    await _save(tester, locale: 'ar');
    expect(find.text('تم حفظ العقار.'), findsOneWidget);
    expect(find.text('تم').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/r38_4/rental_save_summary_ar_360.png'),
    );
  });
}

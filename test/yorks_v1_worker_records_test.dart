import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/admin/presentation/screens/user_management_screen.dart';
import 'package:material_ledger/features/admin/presentation/widgets/yorks_v1_worker_records_tab.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_permission_management.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_worker_record.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_worker_record_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_worker_record_repository.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';

import 'support/yorks_v1_permission_test_support.dart';

Map<String, dynamic> _row(
  int n, {
  String name = 'MD RAJA MD MAINUDDIN',
  String company = 'Al Badawi Central AC Maint. LLC-SPC',
  bool hasRecord = true,
  String basic = '700.00',
  String housing = '500.00',
  String other = '0.00',
  String total = '1200.00',
}) => {
  'worker_id': '7a000000-0000-4000-8000-00000000000$n',
  'worker_number': 'W-00$n',
  'full_name': name,
  'designation': 'Technician',
  'employer_company': company,
  'worker_type': 'yorks_employee',
  'current_status': 'active',
  'joining_date': '2026-01-01',
  'worker_version': 1,
  'has_record': hasRecord,
  'trade_license_no': hasRecord ? 'CN-106632$n' : null,
  'passport_no': hasRecord ? 'AW90932$n' : null,
  'basic_salary': hasRecord ? basic : null,
  'housing_allowance': hasRecord ? housing : null,
  'other_allowance': hasRecord ? other : null,
  'total_salary': hasRecord ? total : null,
  'currency_code': 'AED',
  'photo_object_path': null,
  'record_version': hasRecord ? 1 : 0,
  'updated_at': hasRecord ? '2026-11-10T08:00:00Z' : null,
  'updated_by_name': hasRecord ? 'Local Accountant' : null,
  'updated_by_role': hasRecord ? 'accountant' : null,
};

Map<String, dynamic> _page(List<Map<String, dynamic>> items, {int? total}) => {
  'schema_version': 1,
  'total_count': total ?? items.length,
  'with_record_count': items.where((item) => item['has_record'] == true).length,
  'limit': 50,
  'offset': 0,
  'totals': {
    'basic_salary': '2350.00',
    'housing_allowance': '1500.00',
    'other_allowance': '150.00',
    'total_salary': '4000.00',
  },
  'companies': [
    'Al Badawi Central AC Maint. LLC-SPC',
    'Yorks Airconditioning & Refrigeration WLL-Dubai Branch',
  ],
  'items': items,
};

final _sheet = [
  _row(1),
  _row(
    2,
    name: 'MD TALIB REZA',
    company: 'Yorks Airconditioning & Refrigeration WLL-Dubai Branch',
    basic: '950.00',
    other: '150.00',
    total: '1600.00',
  ),
  _row(
    3,
    name: 'PARWEZ ALAM',
    company: 'Yorks Airconditioning & Refrigeration WLL-Dubai Branch',
  ),
  _row(4, name: 'NEW JOINER WITHOUT RECORD', hasRecord: false),
];

class _DataClient implements YorksV1WorkerRecordDataClient {
  _DataClient(this.response);

  Object? response;
  final calls = <Map<String, Object?>>[];

  @override
  Future<Object?> rpc(
    String functionName,
    Map<String, Object?> parameters,
  ) async {
    calls.add({'fn': functionName, ...parameters});
    final value = response;
    if (value is Exception) throw value;
    return value;
  }

  @override
  Future<String> signedPhotoUrl(String objectPath, {required int seconds}) =>
      Future.value('https://example.invalid/$objectPath');
}

class _Repository implements YorksV1WorkerRecordRepository {
  _Repository(this.pages);

  final List<Object> pages;
  final queries = <YorksV1WorkerRecordQuery>[];

  @override
  Future<YorksV1WorkerRecordPage> listRecords(
    YorksV1WorkerRecordQuery query,
  ) async {
    queries.add(query);
    final next = pages.length > 1 ? pages.removeAt(0) : pages.first;
    if (next is YorksV1DomainException) throw next;
    return next as YorksV1WorkerRecordPage;
  }

  @override
  Future<YorksV1WorkerRecord> getRecord(String workerId) =>
      throw UnimplementedError();

  @override
  Future<String> photoUrl(String objectPath) => throw UnimplementedError();
}

YorksV1SupabaseWorkerRecordRepository _repository(
  _DataClient client, {
  bool enabled = true,
  bool online = true,
}) => YorksV1SupabaseWorkerRecordRepository(
  featureFlags: YorksV1FeatureFlags(foundation: true, workerRecords: enabled),
  connectivity: DefaultConnectivity(online: online),
  dataClient: client,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('model', () {
    test('parses the sheet columns and keeps money as decimal text', () {
      final page = YorksV1WorkerRecordPage.fromRpcJson(_page(_sheet));
      expect(page.totalCount, 4);
      expect(page.withRecordCount, 3);
      expect(page.items[1].totalSalary, '1600.00');
      expect(page.items[1].otherAllowance, '150.00');
      expect(page.totals.totalSalary, '4000.00');
    });

    test('a worker without a record has no amounts, never zero', () {
      final record = YorksV1WorkerRecord.fromRpcJson(_row(4, hasRecord: false));
      expect(record.hasRecord, isFalse);
      expect(record.basicSalary, isNull);
      expect(record.totalSalary, isNull);
      expect(yorksV1FormatWorkerMoney(record.totalSalary), '—');
    });

    test('malformed amounts and unknown statuses are rejected', () {
      expect(
        () =>
            YorksV1WorkerRecord.fromRpcJson({..._row(1), 'basic_salary': 700}),
        throwsFormatException,
      );
      expect(
        () => YorksV1WorkerRecord.fromRpcJson({
          ..._row(1),
          'basic_salary': '-5.00',
        }),
        throwsFormatException,
      );
      expect(
        () => YorksV1WorkerRecord.fromRpcJson({
          ..._row(1),
          'current_status': 'retired',
        }),
        throwsFormatException,
      );
    });

    test('money is grouped with two decimals', () {
      expect(yorksV1FormatWorkerMoney('1200'), '1,200.00');
      expect(yorksV1FormatWorkerMoney('950.5'), '950.50');
      expect(yorksV1FormatWorkerMoney('1234567.89'), '1,234,567.89');
      expect(yorksV1FormatWorkerMoney('0.00'), '0.00');
    });
  });

  group('repository', () {
    test('sends filters and parses the page', () async {
      final client = _DataClient(_page(_sheet));
      final page = await _repository(client).listRecords(
        const YorksV1WorkerRecordQuery(
          search: '  talib ',
          status: YorksV1WorkerStatus.active,
        ),
      );
      expect(page.items, hasLength(4));
      expect(client.calls.single, {
        'fn': 'v1_list_worker_records',
        'p_search': 'talib',
        'p_company': null,
        'p_status': 'active',
        'p_limit': 50,
        'p_offset': 0,
      });
    });

    test('flag off and offline stop before any request', () async {
      final client = _DataClient(_page(_sheet));
      await expectLater(
        _repository(
          client,
          enabled: false,
        ).listRecords(const YorksV1WorkerRecordQuery()),
        throwsA(
          isA<YorksV1DomainException>().having(
            (error) => error.code,
            'code',
            YorksV1DomainErrorCode.featureDisabled,
          ),
        ),
      );
      await expectLater(
        _repository(
          client,
          online: false,
        ).listRecords(const YorksV1WorkerRecordQuery()),
        throwsA(
          isA<YorksV1DomainException>().having(
            (error) => error.code,
            'code',
            YorksV1DomainErrorCode.offline,
          ),
        ),
      );
      expect(client.calls, isEmpty);
    });

    test('a malformed response is an error, not an empty register', () async {
      await expectLater(
        _repository(
          _DataClient({'schema_version': 1, 'items': 'none'}),
        ).listRecords(const YorksV1WorkerRecordQuery()),
        throwsA(
          isA<YorksV1DomainException>().having(
            (error) => error.code,
            'code',
            YorksV1DomainErrorCode.unexpectedResponse,
          ),
        ),
      );
    });
  });

  group('controller', () {
    test('loads, pages without duplicates and keeps rows on failure', () async {
      final first = YorksV1WorkerRecordPage.fromRpcJson(
        _page(_sheet.take(2).toList(), total: 4),
      );
      final second = YorksV1WorkerRecordPage.fromRpcJson(
        _page([_sheet[1], _sheet[2], _sheet[3]], total: 4),
      );
      final repository = _Repository([
        first,
        second,
        const YorksV1DomainException(YorksV1DomainErrorCode.backendUnavailable),
      ]);
      final controller = YorksV1WorkerRecordsController(repository);
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.state.items, hasLength(2));
      expect(controller.state.hasMore, isTrue);

      await controller.loadMore();
      expect(controller.state.items, hasLength(4));
      expect(repository.queries.last.offset, 2);
      expect(controller.state.hasMore, isFalse);

      await controller.refresh();
      expect(controller.state.error, YorksV1DomainErrorCode.backendUnavailable);
      expect(controller.state.items, hasLength(4));
    });
  });

  group('User Management access', () {
    YorksV1UserManagementAccess resolve(
      YorksV1Role role,
      Iterable<String> capabilities, {
      bool enabled = true,
    }) => YorksV1UserManagementAccess.resolve(
      connectedV1: true,
      role: role,
      permissionState: yorksV1TrustedFeaturePermissionState(
        role: role,
        capabilities: capabilities,
      ),
      workerRecordsEnabled: enabled,
    );

    test('Accountant sees worker records but no login accounts', () {
      final access = resolve(YorksV1Role.accountant, const [
        YorksV1CapabilityKeys.workerRecordsView,
        YorksV1CapabilityKeys.workerRecordsManage,
      ]);
      expect(access.canViewWorkerRecords, isTrue);
      expect(access.canManageWorkerRecords, isTrue);
      expect(access.canView, isFalse);
      expect(access.canCreate, isFalse);
      expect(access.canManageUser, isFalse);
      expect(access.canViewPermissions, isFalse);
    });

    test('a per-person view grant does not allow managing', () {
      final access = resolve(YorksV1Role.siteEngineer, const [
        YorksV1CapabilityKeys.workerRecordsView,
      ]);
      expect(access.canViewWorkerRecords, isTrue);
      expect(access.canManageWorkerRecords, isFalse);
    });

    test('no grant, or the flag off, shows nothing', () {
      expect(
        resolve(YorksV1Role.projectEngineer, const []).canViewWorkerRecords,
        isFalse,
      );
      expect(
        resolve(YorksV1Role.accountant, const [
          YorksV1CapabilityKeys.workerRecordsView,
        ], enabled: false).canViewWorkerRecords,
        isFalse,
      );
    });
  });

  group('Workers tab', () {
    setUpAll(() async {
      final font = FontLoader('NexusSans')
        ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
      var cache = File(Platform.resolvedExecutable).parent;
      for (
        var i = 0;
        i < 5 && !Directory('${cache.path}/artifacts').existsSync();
        i++
      ) {
        cache = cache.parent;
      }
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              await File(
                '${cache.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytes(),
            ),
          ),
        );
      await Future.wait([font.load(), icons.load()]);
    });

    Future<void> pump(WidgetTester tester, double width, Object page) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1WorkerRecordRepositoryProvider.overrideWithValue(
              _Repository([page]),
            ),
            yorksV1AuthUserIdProvider.overrideWithValue('auth-accountant'),
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.accountant,
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: YorksV1WorkerRecordsTab(language: AppLanguage.english),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final (width, name) in [(1366.0, 'desktop'), (360.0, 'mobile')]) {
      testWidgets('shows the register at $name width', (tester) async {
        await pump(
          tester,
          width,
          YorksV1WorkerRecordPage.fromRpcJson(_page(_sheet)),
        );
        expect(find.textContaining('MD TALIB REZA'), findsOneWidget);
        expect(find.text('4 workers'), findsOneWidget);
        expect(find.text('3 with a record'), findsOneWidget);
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('worker-records-grand-total')),
              )
              .data,
          '4,000.00',
        );
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/yorks_v1_worker_records_$name.png'),
        );
      });
    }

    testWidgets('opens a read-only record with actor, role and time', (
      tester,
    ) async {
      await pump(
        tester,
        1366,
        YorksV1WorkerRecordPage.fromRpcJson(_page(_sheet)),
      );
      await tester.tap(find.text('MD TALIB REZA'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('worker-record-dialog')),
        findsOneWidget,
      );
      expect(find.text('AED 1,600.00'), findsOneWidget);
      expect(find.textContaining('Local Accountant (Accountant)'), findsOne);
    });

    testWidgets('a failed load shows an error, never an empty register', (
      tester,
    ) async {
      await pump(
        tester,
        1366,
        const YorksV1DomainException(YorksV1DomainErrorCode.backendUnavailable),
      );
      expect(find.byKey(const ValueKey('worker-records-error')), findsOne);
      expect(find.text('Worker records could not be loaded.'), findsOne);
      expect(find.text('No workers match these filters.'), findsNothing);
    });
  });
}

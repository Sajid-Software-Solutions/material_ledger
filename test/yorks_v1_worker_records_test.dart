import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart' show StorageException;
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
import 'package:material_ledger/shared/services/yorks_v1_worker_photo_service.dart';
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

  Object? uploadError;
  final uploads = <String>[];

  @override
  Future<void> uploadPhoto(String objectPath, Uint8List jpegBytes) async {
    uploads.add(objectPath);
    final error = uploadError;
    if (error is Exception) throw error;
  }
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

  final saves = <YorksV1SaveWorkerRecordInput>[];
  final photos = <({String workerId, int expectedVersion, String key})>[];
  Object? saveError;
  Object? photoError;

  @override
  Future<YorksV1WorkerRecord> saveRecord(
    YorksV1SaveWorkerRecordInput input,
  ) async {
    saves.add(input);
    final error = saveError;
    if (error is YorksV1DomainException) throw error;
    return YorksV1WorkerRecord.fromRpcJson({
      ..._row(9, name: input.fullName, company: input.employerCompany),
      'record_version': (input.expectedVersion ?? 0) + 1,
    });
  }

  @override
  Future<YorksV1WorkerRecord> setPhoto({
    required String workerId,
    required Uint8List jpegBytes,
    required int expectedVersion,
    required String idempotencyKey,
  }) async {
    photos.add((
      workerId: workerId,
      expectedVersion: expectedVersion,
      key: idempotencyKey,
    ));
    final error = photoError;
    if (error is YorksV1DomainException) throw error;
    return YorksV1WorkerRecord.fromRpcJson({
      ..._row(9),
      'record_version': expectedVersion + 1,
    });
  }
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

  group('amounts and photos', () {
    test('sums entered amounts exactly', () {
      expect(yorksV1SumWorkerAmounts(['950.50', '500', '150']), '1600.50');
      expect(yorksV1SumWorkerAmounts(['0.1', '0.2']), '0.30');
      expect(yorksV1SumWorkerAmounts(['', ' ']), isNull);
      expect(yorksV1SumWorkerAmounts(['700', 'abc']), isNull);
      expect(yorksV1IsValidWorkerAmount('1000.999'), isFalse);
      expect(yorksV1IsValidWorkerAmount('-1'), isFalse);
      expect(yorksV1IsValidWorkerAmount(''), isTrue);
    });

    test('a photo is stored square, 512 px, as JPEG', () {
      final source = Uint8List.fromList(
        img.encodePng(img.Image(width: 900, height: 600)),
      );
      final prepared = yorksV1PrepareWorkerPhoto(source)!;
      final decoded = img.decodeJpg(prepared)!;
      expect((decoded.width, decoded.height), (512, 512));
      expect(prepared.take(2), [0xFF, 0xD8]);
    });

    test('a file that is not an accepted image is refused', () {
      expect(
        yorksV1PrepareWorkerPhoto(Uint8List.fromList('%PDF-1.7'.codeUnits)),
        isNull,
      );
      expect(yorksV1PrepareWorkerPhoto(Uint8List(0)), isNull);
    });

    test('a photo retry reuses its stored object', () async {
      final client = _DataClient(_row(1));
      final repository = _repository(client);
      client.uploadError = const StorageException(
        'The resource already exists',
        statusCode: '409',
      );
      final record = await repository.setPhoto(
        workerId: '7a000000-0000-4000-8000-000000000001',
        jpegBytes: Uint8List(4),
        expectedVersion: 1,
        idempotencyKey: '7b000000-0000-4000-8000-000000000001',
      );
      expect(record.workerId, '7a000000-0000-4000-8000-000000000001');
      expect(
        client.uploads.single,
        endsWith('/7b000000-0000-4000-8000-000000000001.jpg'),
      );
      expect(client.calls.single['fn'], 'v1_set_worker_photo');

      client.uploadError = const StorageException('denied', statusCode: '403');
      await expectLater(
        repository.setPhoto(
          workerId: '7a000000-0000-4000-8000-000000000001',
          jpegBytes: Uint8List(4),
          expectedVersion: 1,
          idempotencyKey: '7b000000-0000-4000-8000-000000000002',
        ),
        throwsA(isA<YorksV1DomainException>()),
      );
      expect(client.calls, hasLength(1), reason: 'no attach after a refusal');
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

    Future<_Repository> pump(
      WidgetTester tester,
      double width,
      Object page, {
      bool canManage = false,
      Uint8List? pickedPhoto,
    }) async {
      final repository = _Repository([page]);
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1WorkerRecordRepositoryProvider.overrideWithValue(repository),
            yorksV1WorkerPhotoPickerProvider.overrideWithValue(
              () async => (picked: true, bytes: pickedPhoto),
            ),
            yorksV1AuthUserIdProvider.overrideWithValue('auth-accountant'),
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.accountant,
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: YorksV1WorkerRecordsTab(
                  language: AppLanguage.english,
                  canManage: canManage,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return repository;
    }

    Future<void> fillNewWorker(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('worker-records-add')));
      await tester.pumpAndSettle();
      Future<void> enter(String key, String text) =>
          tester.enterText(find.byKey(ValueKey('worker-record-$key')), text);
      await enter('name', 'SADIL HASIM');
      await enter('designation', 'Technician');
      await enter('joining-date', '2026-11-01');
      await enter('company', 'Yorks Airconditioning and Refrigeration LLC');
      await enter('license', 'CN-6772173');
      await enter('passport', 'AW437776');
      await enter('basic', '800');
      await enter('housing', '550');
      await enter('other', '0');
      FocusManager.instance.primaryFocus?.unfocus();
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

    testWidgets('a view-only holder sees no Add or Edit control', (
      tester,
    ) async {
      await pump(
        tester,
        1366,
        YorksV1WorkerRecordPage.fromRpcJson(_page(_sheet)),
      );
      expect(find.byKey(const ValueKey('worker-records-add')), findsNothing);
      await tester.tap(find.text('MD TALIB REZA'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('worker-record-edit')), findsNothing);
    });

    for (final (width, name) in [(1366.0, 'desktop'), (360.0, 'mobile')]) {
      testWidgets('adds a worker with a live total at $name width', (
        tester,
      ) async {
        final repository = await pump(
          tester,
          width,
          YorksV1WorkerRecordPage.fromRpcJson(_page(_sheet)),
          canManage: true,
        );
        await tester.tap(find.byKey(const ValueKey('worker-records-add')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('worker-record-save')));
        await tester.pumpAndSettle();
        expect(find.text('Required'), findsNWidgets(4));
        expect(repository.saves, isEmpty);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        await fillNewWorker(tester);
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('worker-record-total')))
              .data,
          'AED 1,350.00',
        );
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/yorks_v1_worker_record_form_$name.png'),
        );
        await tester.tap(find.byKey(const ValueKey('worker-record-save')));
        await tester.pumpAndSettle();

        final input = repository.saves.single;
        expect(input.workerId, isNull);
        expect(input.expectedVersion, isNull);
        expect(input.toRpcPayload(), {
          'full_name': 'SADIL HASIM',
          'designation': 'Technician',
          'employer_company': 'Yorks Airconditioning and Refrigeration LLC',
          'joining_date': '2026-11-01',
          'trade_license_no': 'CN-6772173',
          'passport_no': 'AW437776',
          'basic_salary': '800',
          'housing_allowance': '550',
          'other_allowance': '0',
        });
        expect(find.byKey(const ValueKey('worker-record-form')), findsNothing);
        expect(find.text('Worker record saved'), findsOneWidget);
        // The register reloaded from the server after the confirmed save.
        expect(repository.queries.length, 2);
      });
    }

    testWidgets('edits at the opened version and rejects a bad amount', (
      tester,
    ) async {
      final repository = await pump(
        tester,
        1366,
        YorksV1WorkerRecordPage.fromRpcJson(_page(_sheet)),
        canManage: true,
      );
      await tester.tap(find.text('MD TALIB REZA'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('worker-record-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('worker-record-basic')),
        '1000.999',
      );
      await tester.tap(find.byKey(const ValueKey('worker-record-save')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a number with up to 2 decimals'), findsOne);
      expect(repository.saves, isEmpty);

      await tester.enterText(
        find.byKey(const ValueKey('worker-record-basic')),
        '1000',
      );
      await tester.tap(find.byKey(const ValueKey('worker-record-save')));
      await tester.pumpAndSettle();
      final input = repository.saves.single;
      expect(input.workerId, '7a000000-0000-4000-8000-000000000002');
      expect(input.expectedVersion, 1);
      expect(input.toRpcPayload().containsKey('joining_date'), isFalse);
      expect(input.basicSalary, '1000');
    });

    testWidgets('a refused save changes nothing and a retry reuses its key', (
      tester,
    ) async {
      final repository = await pump(
        tester,
        1366,
        YorksV1WorkerRecordPage.fromRpcJson(_page(_sheet)),
        canManage: true,
      );
      repository.saveError = const YorksV1DomainException(
        YorksV1DomainErrorCode.invalidInput,
        serverMessage: 'V1_WORKER_RECORD_PASSPORT_DUPLICATE',
      );
      await fillNewWorker(tester);
      await tester.tap(find.byKey(const ValueKey('worker-record-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('This passport number already belongs to another worker.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('worker-record-form')), findsOneWidget);

      repository.saveError = const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
      await tester.tap(find.byKey(const ValueKey('worker-record-save')));
      await tester.pumpAndSettle();
      expect(
        repository.saves[1].idempotencyKey,
        repository.saves[0].idempotencyKey,
        reason: 'the same input must retry under the same key',
      );
      await tester.enterText(
        find.byKey(const ValueKey('worker-record-passport')),
        'AW437777',
      );
      repository.saveError = null;
      await tester.tap(find.byKey(const ValueKey('worker-record-save')));
      await tester.pumpAndSettle();
      expect(
        repository.saves[2].idempotencyKey,
        isNot(repository.saves[0].idempotencyKey),
        reason: 'a changed input must use a new key',
      );
    });

    testWidgets('a failed photo keeps the saved record and can be retried', (
      tester,
    ) async {
      final repository = await pump(
        tester,
        1366,
        YorksV1WorkerRecordPage.fromRpcJson(_page(_sheet)),
        canManage: true,
        pickedPhoto: Uint8List.fromList(
          img.encodeJpg(img.Image(width: 8, height: 8)),
        ),
      );
      repository.photoError = const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
      await fillNewWorker(tester);
      await tester.tap(find.byKey(const ValueKey('worker-record-photo')));
      await tester.pumpAndSettle();
      expect(find.text('New photo ready to save'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('worker-record-save')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The record was saved, but the photo was not.'),
        findsOneWidget,
      );

      repository.photoError = null;
      await tester.tap(find.byKey(const ValueKey('worker-record-save')));
      await tester.pumpAndSettle();
      // The retry updates the already-created worker; it never creates two.
      expect(repository.saves, hasLength(2));
      expect(repository.saves[1].workerId, isNotNull);
      expect(repository.saves[1].expectedVersion, 1);
      expect(repository.photos, hasLength(2));
      expect(repository.photos[1].key, repository.photos[0].key);
      expect(find.byKey(const ValueKey('worker-record-form')), findsNothing);
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

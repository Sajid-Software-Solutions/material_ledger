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
import 'package:material_ledger/shared/models/yorks_v1_boq_workbook.dart';
import 'package:material_ledger/shared/services/yorks_v1_boq_workbook_service.dart';
import 'package:material_ledger/shared/services/yorks_v1_worker_photo_service.dart';
import 'package:material_ledger/shared/services/yorks_v1_worker_workbook_service.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';

import 'support/yorks_v1_permission_test_support.dart';

Map<String, dynamic> _row(
  int n, {
  String name = 'AHMED TEST ONE',
  String company = 'Example Cooling Services LLC',
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
  'trade_license_no': hasRecord ? 'CN-TEST-0$n' : null,
  'passport_no': hasRecord ? 'TP100000$n' : null,
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
    'Example Cooling Services LLC',
    'Example Contracting WLL - Dubai Branch',
  ],
  'items': items,
};

final _sheet = [
  _row(1),
  _row(
    2,
    name: 'CHAND TEST THREE',
    company: 'Example Contracting WLL - Dubai Branch',
    basic: '950.00',
    other: '150.00',
    total: '1600.00',
  ),
  _row(
    3,
    name: 'DANISH TEST FOUR',
    company: 'Example Contracting WLL - Dubai Branch',
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

  YorksV1WorkerImportPreview? preview;
  Object? importError;
  final imports =
      <
        ({
          List<Map<String, Object?>> rows,
          List<Map<String, dynamic>> expected,
          String? designation,
          String? joiningDate,
          String key,
        })
      >[];
  final previews = <List<Map<String, Object?>>>[];

  @override
  Future<YorksV1WorkerImportPreview> previewImport(
    List<Map<String, Object?>> rows,
  ) async {
    previews.add(rows);
    return preview!;
  }

  @override
  Future<YorksV1WorkerImportResult> importRecords({
    required List<Map<String, Object?>> rows,
    required List<Map<String, dynamic>> expected,
    String? newWorkerDesignation,
    String? newWorkerJoiningDate,
    required String idempotencyKey,
  }) async {
    imports.add((
      rows: rows,
      expected: expected,
      designation: newWorkerDesignation,
      joiningDate: newWorkerJoiningDate,
      key: idempotencyKey,
    ));
    final error = importError;
    if (error is YorksV1DomainException) throw error;
    return const YorksV1WorkerImportResult(
      createdCount: 1,
      updatedCount: 1,
      unchangedCount: 1,
    );
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

class _Files implements YorksV1WorkerWorkbookFiles {
  _Files(this.workbook);

  final YorksV1PickedWorkerWorkbook? workbook;
  int templates = 0;

  @override
  Future<YorksV1PickedWorkerWorkbook?> pickWorkbook() async => workbook;

  @override
  Future<bool> saveTemplate() async {
    templates++;
    return true;
  }
}

/// Rows shaped like the owner's sheet, including a title line above the
/// headings, a totals line at the foot and Excel float noise.
YorksV1BoqWorkbookSheet _ownerSheet({List<List<String>> extra = const []}) =>
    YorksV1BoqWorkbookSheet(
      name: 'Workers',
      rows: [
        ['Yorks workforce — November'],
        [
          'Nos',
          'Names',
          'Company',
          'Trade License No.',
          'Passport No.',
          'Basic Salary',
          'Housing',
          'Others',
          'Total Salary',
        ],
        [
          '1',
          'AHMED  TEST ONE',
          'Example Cooling Services LLC',
          'CN-TEST-01',
          'TP0000001',
          '700',
          '500',
          '0',
          'AED 1,200.00',
        ],
        [
          '2',
          'BILAL TEST TWO',
          'Example Contracting LLC - Branch',
          'CN-TEST-02',
          'TP0000002',
          '700',
          '500',
          '0',
          '1200',
        ],
        [
          '3',
          'CHAND TEST THREE',
          'Example Contracting WLL - Dubai Branch',
          'TL-TEST-03',
          'TP0000003',
          '949.99999999999989',
          '500',
          '150',
          '1600',
        ],
        ['', '', '', '', '', '', '', '', ''],
        ...extra,
        ['', 'Total', '', '', '', '2350', '1500', '150', '4000'],
      ],
    );

YorksV1WorkerImportPreview _previewOf(List<String> actions) =>
    YorksV1WorkerImportPreview.fromRpcJson({
      'schema_version': 1,
      'rows': [
        for (final (index, action) in actions.indexed)
          {
            'index': index + 1,
            'row_number': index + 3,
            'action': action,
            'worker_id': action == 'create' || action == 'error'
                ? null
                : '7a000000-0000-4000-8000-00000000000${index + 1}',
            'record_version': action == 'create' || action == 'error'
                ? null
                : 1,
            'errors': action == 'error' ? ['passport_other_worker'] : [],
            'changed_fields': action == 'update'
                ? ['basic_salary', 'other_allowance']
                : [],
          },
      ],
      'create_count': actions.where((a) => a == 'create').length,
      'update_count': actions.where((a) => a == 'update').length,
      'unchanged_count': actions.where((a) => a == 'unchanged').length,
      'error_count': actions.where((a) => a == 'error').length,
    });

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

  group('Excel sheet', () {
    test(
      'reads the owner sheet: headings below a title, totals line skipped',
      () {
        final sheet = yorksV1ReadWorkerSheet(_ownerSheet());
        expect(sheet.readable, isTrue);
        expect(sheet.rows.map((row) => row.rowNumber), [3, 4, 5]);
        final first = sheet.rows.first;
        expect(first.fullName, 'AHMED TEST ONE');
        expect(first.passportNo, 'TP0000001');
        expect(first.issues, isEmpty);
        expect(sheet.rows[2].basicSalary, '950.00');
        expect(sheet.rows[2].issues, isEmpty);
        expect(sheet.rows[2].toRpcJson()['other_allowance'], '150');
      },
    );

    test('flags a wrong total and a non-numeric amount', () {
      final sheet = yorksV1ReadWorkerSheet(
        _ownerSheet(
          extra: [
            [
              '4',
              'DANISH TEST FOUR',
              'Yorks WLL',
              'TL-TEST-03',
              'TP0000004',
              '700',
              '500',
              '0',
              '1300',
            ],
            [
              '5',
              'EHSAN TEST FIVE',
              'Yorks WLL',
              'TL-TEST-03',
              'TP0000005',
              'seven hundred',
              '500',
              '0',
              '1200',
            ],
          ],
        ),
      );
      expect(sheet.rows[3].issues, [YorksV1WorkerSheetIssue.totalMismatch]);
      expect(sheet.rows[4].issues, [YorksV1WorkerSheetIssue.amountInvalid]);
    });

    test('a sheet without Names and Company headings is not readable', () {
      final sheet = yorksV1ReadWorkerSheet(
        YorksV1BoqWorkbookSheet(
          name: 'Other',
          rows: [
            ['Item', 'Qty'],
            ['Pipe', '3'],
          ],
        ),
      );
      expect(sheet.readable, isFalse);
      expect(sheet.missingColumns, isNotEmpty);
    });

    test('more than 500 workers is refused', () {
      final sheet = yorksV1ReadWorkerSheet(
        YorksV1BoqWorkbookSheet(
          name: 'Big',
          rows: [
            ['Names', 'Company'],
            for (var index = 0; index < 501; index++) ['W$index', 'Co'],
          ],
        ),
      );
      expect(sheet.tooManyRows, isTrue);
      expect(sheet.readable, isFalse);
    });

    test('amounts accept currency text and Excel float noise only', () {
      expect(yorksV1ParseWorkerAmount('AED 1,200.00'), '1200.00');
      expect(yorksV1ParseWorkerAmount(' 950 '), '950');
      expect(yorksV1ParseWorkerAmount('1199.9999999999998'), '1200.00');
      expect(yorksV1ParseWorkerAmount('1.2E3'), '1200.00');
      expect(yorksV1ParseWorkerAmount(''), '');
      expect(yorksV1ParseWorkerAmount('12.345'), isNull);
      expect(yorksV1ParseWorkerAmount('-5'), isNull);
      expect(yorksV1ParseWorkerAmount('abc'), isNull);
    });

    test('the template reopens with the nine sheet headings', () {
      final workbook = const YorksV1BoqWorkbookCodec().decode(
        bytes: yorksV1WorkerImportTemplate(),
        fileName: 'template.xlsx',
      );
      expect(workbook.sheets.single.rows.first, [
        for (final column in YorksV1WorkerSheetColumn.values)
          column.templateHeading,
      ]);
      expect(
        yorksV1ReadWorkerSheet(workbook.sheets.single).missingColumns,
        isEmpty,
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

    Future<_Repository> pump(
      WidgetTester tester,
      double width,
      Object page, {
      bool canManage = false,
      Uint8List? pickedPhoto,
      YorksV1WorkerImportPreview? importPreview,
      YorksV1BoqWorkbookSheet? importSheet,
    }) async {
      final repository = _Repository([page])..preview = importPreview;
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
            yorksV1WorkerWorkbookFilesProvider.overrideWithValue(
              _Files(
                YorksV1PickedWorkerWorkbook(
                  fileName: 'Workers November.xlsx',
                  sheets: [importSheet ?? _ownerSheet()],
                ),
              ),
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
      await enter('name', 'FARHAN TEST SIX');
      await enter('designation', 'Technician');
      await enter('joining-date', '2026-11-01');
      await enter('company', 'Example Contracting LLC');
      await enter('license', 'CN-TEST-06');
      await enter('passport', 'TP0000006');
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
        expect(find.textContaining('CHAND TEST THREE'), findsOneWidget);
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
      await tester.tap(find.text('CHAND TEST THREE'));
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
      await tester.tap(find.text('CHAND TEST THREE'));
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
          'full_name': 'FARHAN TEST SIX',
          'designation': 'Technician',
          'employer_company': 'Example Contracting LLC',
          'joining_date': '2026-11-01',
          'trade_license_no': 'CN-TEST-06',
          'passport_no': 'TP0000006',
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
      await tester.tap(find.text('CHAND TEST THREE'));
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
        'TP0000007',
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

    for (final (width, name) in [(1366.0, 'desktop'), (360.0, 'mobile')]) {
      testWidgets('previews and imports a sheet at $name width', (
        tester,
      ) async {
        final repository = await pump(
          tester,
          width,
          YorksV1WorkerRecordPage.fromRpcJson(_page(_sheet)),
          canManage: true,
          importPreview: _previewOf(['update', 'create', 'unchanged']),
        );
        await tester.tap(find.byKey(const ValueKey('worker-records-import')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('worker-import-choose')));
        await tester.pumpAndSettle();

        expect(repository.previews.single, hasLength(3));
        expect(find.text('1 new'), findsOneWidget);
        expect(find.text('1 to update'), findsOneWidget);
        expect(find.text('1 unchanged'), findsOneWidget);
        expect(find.text('0 with problems'), findsOneWidget);
        expect(find.text('Update: Basic Salary, Others'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/yorks_v1_worker_import_$name.png'),
        );

        await tester.tap(find.byKey(const ValueKey('worker-import-confirm')));
        await tester.pumpAndSettle();
        expect(repository.imports, isEmpty, reason: 'defaults are required');
        expect(find.text('Required'), findsNWidgets(2));

        await tester.enterText(
          find.byKey(const ValueKey('worker-import-designation')),
          'Technician',
        );
        await tester.enterText(
          find.byKey(const ValueKey('worker-import-joining-date')),
          '2026-11-01',
        );
        await tester.tap(find.byKey(const ValueKey('worker-import-confirm')));
        await tester.pumpAndSettle();

        final sent = repository.imports.single;
        expect(sent.rows, hasLength(3));
        expect(sent.expected.map((row) => row['action']), [
          'update',
          'create',
          'unchanged',
        ]);
        expect(sent.designation, 'Technician');
        expect(sent.joiningDate, '2026-11-01');
        expect(
          find.byKey(const ValueKey('worker-import-dialog')),
          findsNothing,
        );
        expect(find.text('Imported: 1 new, 1 updated'), findsOneWidget);
        expect(repository.queries.length, 2, reason: 'register reloaded');
      });
    }

    testWidgets('any problem blocks the whole import', (tester) async {
      final repository = await pump(
        tester,
        1366,
        YorksV1WorkerRecordPage.fromRpcJson(_page(_sheet)),
        canManage: true,
        importPreview: _previewOf(['update', 'error', 'unchanged', 'create']),
        importSheet: _ownerSheet(
          extra: [
            [
              '4',
              'DANISH TEST FOUR',
              'Yorks WLL',
              'TL-TEST-03',
              'TP0000004',
              '700',
              '500',
              '0',
              '1300',
            ],
          ],
        ),
      );
      await tester.tap(find.byKey(const ValueKey('worker-records-import')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('worker-import-choose')));
      await tester.pumpAndSettle();
      expect(find.text('2 with problems'), findsOneWidget);
      expect(find.text('This passport belongs to another worker'), findsOne);
      expect(
        find.text('Total does not equal Basic + Housing + Others'),
        findsOne,
      );
      expect(find.byKey(const ValueKey('worker-import-fix')), findsOne);
      final confirm = tester.widget<FilledButton>(
        find.byKey(const ValueKey('worker-import-confirm')),
      );
      expect(confirm.onPressed, isNull);
      expect(repository.imports, isEmpty);
    });

    testWidgets('a stale preview asks to check again with a new key', (
      tester,
    ) async {
      final repository = await pump(
        tester,
        1366,
        YorksV1WorkerRecordPage.fromRpcJson(_page(_sheet)),
        canManage: true,
        importPreview: _previewOf(['update', 'update', 'unchanged']),
      );
      repository.importError = const YorksV1DomainException(
        YorksV1DomainErrorCode.conflict,
      );
      await tester.tap(find.byKey(const ValueKey('worker-records-import')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('worker-import-choose')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('worker-import-confirm')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Records changed after this check. Check again before importing.',
        ),
        findsOneWidget,
      );
      final blocked = tester.widget<FilledButton>(
        find.byKey(const ValueKey('worker-import-confirm')),
      );
      expect(blocked.onPressed, isNull);

      repository.importError = null;
      await tester.tap(find.byKey(const ValueKey('worker-import-recheck')));
      await tester.pumpAndSettle();
      expect(repository.previews, hasLength(2));
      await tester.tap(find.byKey(const ValueKey('worker-import-confirm')));
      await tester.pumpAndSettle();
      expect(repository.imports, hasLength(2));
      expect(repository.imports[1].key, isNot(repository.imports[0].key));
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

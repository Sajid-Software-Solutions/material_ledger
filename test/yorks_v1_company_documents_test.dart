// Company documents: the tracker reader and exporter, and the home, record,
// form, document dialog and import dialog against a fake server. Every name
// and number here is fictional.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/app/router.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/company_documents/presentation/company_centre_screen.dart';
import 'package:material_ledger/features/company_documents/presentation/company_form_screen.dart';
import 'package:material_ledger/features/company_documents/presentation/company_record_screen.dart';
import 'package:material_ledger/features/people_records/presentation/record_attachments.dart'
    show yorksV1OpenLinkProvider;
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_boq_workbook.dart';
import 'package:material_ledger/shared/models/yorks_v1_company_documents.dart';
import 'package:material_ledger/shared/models/yorks_v1_company_documents_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_boq_workbook_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_company_documents_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_document_file_service_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_company_documents_repository.dart';
import 'package:material_ledger/shared/services/yorks_v1_boq_workbook_service.dart';
import 'package:material_ledger/shared/services/yorks_v1_company_workbook.dart';
import 'package:material_ledger/shared/services/yorks_v1_document_file_service.dart';
import 'package:material_ledger/shared/services/yorks_v1_multi_file_service.dart';
import 'package:material_ledger/shared/services/yorks_v1_people_workbook.dart'
    show peopleEncodeWorkbook;
import 'package:material_ledger/shared/sync/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'support/accounts_v2_golden_fonts.dart';

const _flags = YorksV1FeatureFlags(
  foundation: true,
  projects: true,
  boq: true,
  excel: true,
  requests: true,
  arrangement: true,
  logistics: true,
  returnsDocuments: true,
  documents: true,
  peopleRecords: true,
  companyDocuments: true,
);

const _entityId = '7c000000-0000-4000-8000-000000000001';
const _vehicleId = '7c000000-0000-4000-8000-000000000002';
const _contractId = '7c000000-0000-4000-8000-000000000003';

Map<String, Object?> _doc(
  String id,
  String kind, {
  String recordId = _entityId,
  String status = 'ok',
  String? label,
  String? number,
  String? expiry,
  int? days,
  String? sites,
}) => {
  'id': id,
  'record_id': recordId,
  'kind': kind,
  'status': status,
  'record_version': 1,
  'label': label,
  'number': number,
  'expiry_date': expiry,
  'days_left': days,
  'sites': sites,
  'is_current': true,
  'updated_at': '2026-10-01T08:00:00Z',
  'updated_by': 'Local PR',
};

Map<String, Object?> _entity({bool canManage = true, bool archived = false}) =>
    {
      'id': _entityId,
      'kind': 'entity',
      'name': 'EXAMPLE MAIN',
      'reference': 'CN-0000001',
      'owner': null,
      'details': <String, Object?>{},
      'status': archived ? 'archived' : 'active',
      'archived_at': archived ? '2026-11-01T08:00:00Z' : null,
      'archived_reason': archived ? 'Branch closed' : null,
      'record_version': 2,
      'attention': 'expired',
      'documents': [
        _doc(
          'd-licence',
          'licence',
          status: 'expired',
          expiry: '2026-11-01',
          days: -12,
        ),
        _doc(
          'd-est',
          'establishment_card',
          status: 'expiring',
          expiry: '2026-12-20',
          days: 37,
        ),
        _doc('d-file', 'labour_file', status: 'no_expiry', number: '12345'),
        _doc(
          'd-pro',
          'pro_card',
          label: 'PRO card Test A',
          expiry: '2028-07-12',
          days: 607,
        ),
      ],
      'next_expiry': {
        'kind': 'establishment_card',
        'expiry_date': '2026-12-20',
        'days_left': 37,
      },
      'previous_documents': [
        {
          ..._doc(
            'd-licence-old',
            'licence',
            status: 'expired',
            expiry: '2025-11-01',
            days: -377,
          ),
          'is_current': false,
          'ended_at': '2025-11-02T08:00:00Z',
          'ended_reason': 'renewed',
        },
      ],
      'history': [
        {
          'entity': 'record',
          'action': 'imported',
          'actor_name': 'Local PR',
          'actor_role': 'pr',
          'at': '2026-11-10T08:00:00Z',
        },
        {
          'entity': 'document',
          'action': 'renewed',
          'kind': 'licence',
          'actor_name': 'Local PR',
          'actor_role': 'pr',
          'at': '2026-11-11T09:30:00Z',
        },
      ],
      'can_manage': canManage,
    };

Map<String, Object?> _vehicle() => {
  'id': _vehicleId,
  'kind': 'vehicle',
  'name': 'TEST PICKUP 11111',
  'reference': '11111',
  'owner': 'EXAMPLE MAIN',
  'details': <String, Object?>{},
  'status': 'active',
  'record_version': 1,
  'attention': 'ok',
  'documents': [
    _doc(
      'd-reg',
      'registration',
      recordId: _vehicleId,
      expiry: '2027-06-01',
      days: 200,
    ),
    _doc(
      'd-asateel',
      'asateel_permit',
      recordId: _vehicleId,
      expiry: '2027-01-06',
      days: 54,
      status: 'expiring',
    ),
    _doc(
      'd-cicpa',
      'cicpa_pass',
      recordId: _vehicleId,
      number: '9000001',
      expiry: '2027-02-05',
      days: 84,
      sites: 'Test Plant',
    ),
  ],
  'can_manage': true,
};

Map<String, Object?> _contract() => {
  'id': _contractId,
  'kind': 'contract',
  'name': 'LOA 900001 · TEST PLANT',
  'reference': '900001',
  'owner': 'EXAMPLE MAIN',
  'details': {
    'job': 'TEST PLANT',
    'people': 12,
    'vehicles': 2,
    'applied_people': 8,
  },
  'status': 'active',
  'record_version': 1,
  'attention': 'ok',
  'documents': [
    _doc(
      'd-loa',
      'contract',
      recordId: _contractId,
      number: '900001',
      expiry: '2027-08-19',
      days: 279,
    ),
  ],
  'can_manage': true,
};

Map<String, Object?> _overview({bool canManage = true}) => {
  'today': '2026-11-13',
  'can_manage': canManage,
  'counts': {
    'total': 56,
    'entity': 5,
    'item': 15,
    'vehicle': 19,
    'policy': 6,
    'contract': 11,
    'expired': 11,
    'expiring': 4,
  },
  'owners': [
    {'name': 'EXAMPLE MAIN', 'count': 20},
    {'name': 'EXAMPLE BRANCH', 'count': 9},
  ],
  'attention': [
    {
      'document': _doc(
        'd-licence',
        'licence',
        status: 'expired',
        expiry: '2026-11-01',
        days: -12,
      ),
      'record': {
        'id': _entityId,
        'kind': 'entity',
        'name': 'EXAMPLE MAIN',
        'reference': 'CN-0000001',
      },
    },
    {
      'document': _doc(
        'd-asateel',
        'asateel_permit',
        recordId: _vehicleId,
        status: 'expiring',
        expiry: '2027-01-06',
        days: 54,
      ),
      'record': {
        'id': _vehicleId,
        'kind': 'vehicle',
        'name': 'TEST PICKUP 11111',
        'reference': '11111',
        'owner': 'EXAMPLE MAIN',
      },
    },
  ],
};

final class _FakeRpc implements YorksV1CompanyDocumentsRpcClient {
  _FakeRpc(this.handlers);

  final Map<String, FutureOr<Object?> Function(Map<String, Object?>)> handlers;
  final calls = <(String, Map<String, Object?>)>[];

  List<Map<String, Object?>> callsTo(String name) => [
    for (final (function, parameters) in calls)
      if (function == name) parameters,
  ];

  @override
  Future<Object?> rpc(
    String functionName,
    Map<String, Object?> parameters,
  ) async {
    calls.add((functionName, parameters));
    final handler = handlers[functionName];
    if (handler == null) throw StateError('unexpected $functionName');
    return handler(parameters);
  }
}

final class _Online implements ConnectivityService {
  const _Online();
  @override
  bool get isOnline => true;
  @override
  Stream<bool> get onChange => const Stream.empty();
}

final class _Files implements YorksV1BoqWorkbookFileService {
  _Files([this.selected]);

  final YorksV1BoqSelectedWorkbook? selected;
  Uint8List? saved;
  String? savedName;

  @override
  Future<YorksV1BoqSelectedWorkbook?> selectWorkbook() async => selected;

  @override
  Future<bool> saveWorkbook({
    required Uint8List bytes,
    required String suggestedName,
  }) async {
    saved = bytes;
    savedName = suggestedName;
    return true;
  }
}

Map<String, Object?> _attachment({
  String id = 'a-licence',
  String? documentId = 'd-licence',
  String fileName = 'Trade licence.pdf',
}) => {
  'id': id,
  'document_id': documentId,
  'document_kind': documentId == null ? null : 'licence',
  'document_number': null,
  'document_current': documentId != null,
  'title': null,
  'file_name': fileName,
  'content_type': 'application/pdf',
  'size_bytes': 512000,
  'object_path': 'company/$_entityId/$id.pdf',
  'uploaded_by': 'Test PR',
  'uploaded_by_role': 'pr',
  'uploaded_at': '2026-11-14T08:00:00Z',
};

Map<String, Object?> _attachments({
  bool canManage = true,
  List<Map<String, Object?>>? items,
}) => {
  'record_id': _entityId,
  'can_manage': canManage,
  'attachments': items ?? [_attachment()],
};

/// Storage for attachments: records uploads, hands out links.
final class _StoredFiles implements YorksV1RecordFileClient {
  final uploads = <(String, int, String)>[];
  final links = <String>[];

  @override
  Future<void> upload(
    String objectPath,
    Uint8List bytes,
    String contentType,
  ) async => uploads.add((objectPath, bytes.length, contentType));

  @override
  Future<String> signedUrl(String objectPath, {required int seconds}) async {
    links.add(objectPath);
    return 'https://files.example.test/$objectPath?expires=$seconds';
  }
}

/// The file picker: always the same fictional scan.
final class _PickedDocument implements YorksV1DocumentFileService {
  @override
  Future<YorksV1SelectedDocument?> selectDocument() async =>
      YorksV1SelectedDocument(
        fileName: 'Licence scan.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList(List.filled(4096, 1)),
      );

  @override
  Future<YorksV1SelectedDocument?> selectImage() async => null;

  @override
  Future<bool> saveDocument({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async => false;
}

/// A folder of scans, as (file name, size). Bytes are zeros.
final class _PickedFiles implements YorksV1MultiFileService {
  _PickedFiles(this.files);

  final List<(String, int)> files;

  @override
  Future<List<YorksV1PickedFile>> selectFiles() async => [
    for (final (name, size) in files)
      YorksV1PickedFile(
        name: name,
        size: size,
        read: () async => Uint8List(size),
      ),
  ];
}

_FakeRpc _server({bool canManage = true}) => _FakeRpc({
  'v1_company_docs_list_attachments': (parameters) =>
      parameters['p_record_id'] == _entityId
      ? _attachments(canManage: canManage)
      : {
          'record_id': parameters['p_record_id'],
          'can_manage': canManage,
          'attachments': <Object>[],
        },
  'v1_company_docs_attachment_counts': (_) => {
    'counts': {_entityId: 1},
  },
  'v1_company_docs_add_attachment': (_) => _attachments(
    items: [
      _attachment(id: 'a-new', fileName: 'Licence scan.png'),
      _attachment(),
    ],
  ),
  'v1_company_docs_remove_attachment': (_) => _attachments(items: []),
  'v1_company_docs_overview': (_) => _overview(canManage: canManage),
  'v1_company_docs_list': (parameters) {
    final query = parameters['p_query'] as Map<String, Object?>;
    final kinds = (query['kinds'] as List?)?.cast<String>();
    return {
      'today': '2026-11-13',
      'offset': 0,
      'limit': 25,
      'rows': [
        if (kinds == null || kinds.contains('entity'))
          _entity(canManage: canManage),
        if (kinds == null || kinds.contains('vehicle')) _vehicle(),
        if (kinds == null || kinds.contains('contract')) _contract(),
      ],
      'total': kinds == null ? 3 : 1,
    };
  },
  'v1_company_docs_get': (parameters) => switch (parameters['p_record_id']) {
    _vehicleId => _vehicle(),
    _contractId => _contract(),
    _ => _entity(canManage: canManage),
  },
  'v1_company_docs_save_record': (_) => _contract(),
  'v1_company_docs_save_document': (_) => _entity(),
  'v1_company_docs_end_document': (_) => _vehicle(),
  'v1_company_docs_set_archived': (_) => _entity(archived: true),
});

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(
  WidgetTester tester,
  _FakeRpc rpc,
  String location, {
  _Files? files,
  _StoredFiles? stored,
  List<Uri>? opened,
  _PickedFiles? folder,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: RoutePaths.yorksV1CompanyDocuments,
        builder: (_, state) =>
            CompanyCentreScreen(initialView: state.uri.queryParameters['view']),
      ),
      GoRoute(
        path: RoutePaths.yorksV1CompanyDocumentsNew,
        builder: (_, state) =>
            CompanyFormScreen(initialKind: state.uri.queryParameters['kind']),
      ),
      GoRoute(
        path: RoutePaths.yorksV1CompanyDocument,
        builder: (_, state) =>
            CompanyRecordScreen(recordId: state.pathParameters['recordId']!),
      ),
      GoRoute(
        path: RoutePaths.yorksV1CompanyDocumentEdit,
        builder: (_, state) =>
            CompanyFormScreen(recordId: state.pathParameters['recordId']),
      ),
      GoRoute(
        path: RoutePaths.yorksV1People,
        builder: (_, _) => const Scaffold(body: Text('people')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksV1AuthUserIdProvider.overrideWithValue('actor-pr'),
        yorksV1FeatureFlagsProvider.overrideWithValue(_flags),
        yorksV1CompanyDocumentsRepositoryProvider.overrideWithValue(
          YorksV1CompanyDocumentsRepository(
            featureFlags: _flags,
            connectivity: const _Online(),
            client: rpc,
            files: stored ?? _StoredFiles(),
          ),
        ),
        yorksV1BoqWorkbookFileServiceProvider.overrideWithValue(
          files ?? _Files(),
        ),
        yorksV1DocumentFileServiceProvider.overrideWithValue(_PickedDocument()),
        yorksV1MultiFileServiceProvider.overrideWithValue(
          folder ?? _PickedFiles(const []),
        ),
        yorksV1OpenLinkProvider.overrideWithValue((uri) async {
          opened?.add(uri);
          return true;
        }),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A small tracker in the owner's layout: licences, vehicles, contracts,
/// an insurance line between the people and a vehicle gate pass.
YorksV1BoqParsedWorkbook _tracker() => YorksV1BoqParsedWorkbook(
  fileName: 'tracker.xlsx',
  sheets: [
    YorksV1BoqWorkbookSheet(
      name: 'Staff Documents',
      rows: [
        ['STAFF DOCUMENTS'],
        [
          'Company',
          'Employee Name',
          'Profession',
          'Visa Expiry',
          'Passport Number',
          'Passport Expiry',
          'Labour Card Expiry',
        ],
        ['Example Main', 'RAVI TEST KUMAR', 'Technician', '46418', 'TP1'],
        ['', 'TEST BASIC INSURANCE', '', '46418'],
      ],
    ),
    YorksV1BoqWorkbookSheet(
      name: 'Company Licenses & Permits',
      rows: [
        ['EXAMPLE — Company Licenses'],
        ['Item', 'Value 1', 'Value 2', 'Value 3'],
        [
          'LICENSES',
          'EXAMPLE MAIN   CN-0000001',
          'EXAMPLE BADAWI CN-0000002',
          'EXAMPLE DUBAI 7000001',
        ],
        ['COMMERCIAL LICENSE', '46418', '46418', '46000'],
        ['LABOUR FILE NUMBER', '12345.0', '67890.0', ''],
        ['PRO CARD LABOR TEST A', '47000', '47000', '47000'],
        ['ISO 9001', '46000', '47000'],
        ['P.O. BOX 4757', '46387', '46387'],
        ['(COURT)', '3 spas'],
        ['EXAMPLE CAR REGISTRATION', '', 'ASATEEL PERMIT'],
        ['TEST PICKUP 11111', '46418', '46000'],
        ['TEST BUS 22222', '46418'],
        ['PERSONAL CARS'],
        ['TOYOTA TEST CAR'],
        ['WORKMENS INSURANCE(TEST HOUSE)', '46418'],
      ],
    ),
    YorksV1BoqWorkbookSheet(
      name: 'CICPA  Contracts',
      rows: [
        ['', 'CONTRACTS FOR EXAMPLE MAIN'],
        [
          '',
          'LOA #',
          'JOB',
          'PEOPLE',
          'VEHICLE',
          "APPLIED PEOPLE'S PASSES",
          "APPLIED VEHICLE'S PASSES",
          'EXPIRY DATE',
        ],
        ['1', '900001.0', 'TEST PLANT', '12', '2', '8', '', '46418'],
        ['2'],
      ],
    ),
    YorksV1BoqWorkbookSheet(
      name: 'Gate Passes',
      rows: [
        ['EXPIRY', 'NAME', 'CNI NO', 'SITES'],
        ['EXAMPLE'],
        ['20270205', 'TEST PICKUP 11111', '9000001', 'Test Plant'],
      ],
    ),
  ],
);

void main() {
  group('Company tracker reader', () {
    test('reads licences, vehicles, contracts, insurance and passes', () {
      final read = companyReadTracker(_tracker());
      expect(read.issueCount, 0);
      // A note row and the postal address are reported, not imported.
      expect(read.skippedRows.map((row) => row.text), [
        '(COURT) 3 spas',
        'P.O. BOX 4757',
      ]);
      expect(
        read.records.where((record) => record.name.contains('BOX')),
        isEmpty,
      );
      CompanyTrackerRecord named(String name) =>
          read.records.firstWhere((record) => record.name == name);

      final main = named('EXAMPLE MAIN');
      expect(main.kind, CompanyRecordKind.entity);
      expect(main.reference, 'CN-0000001');
      expect(
        main.documents.map((document) => document.kind),
        containsAll([
          CompanyDocumentKind.licence,
          CompanyDocumentKind.labourFile,
          CompanyDocumentKind.proCard,
        ]),
      );
      expect(
        main.documents
            .firstWhere((d) => d.kind == CompanyDocumentKind.labourFile)
            .number,
        '12345',
      );
      expect(named('EXAMPLE DUBAI').reference, '7000001');

      final iso = named('ISO 9001');
      expect(iso.kind, CompanyRecordKind.item);
      expect(iso.documents.map((d) => d.label), [null, 'Value 2']);

      final pickup = named('TEST PICKUP 11111');
      expect(pickup.kind, CompanyRecordKind.vehicle);
      expect(pickup.reference, '11111');
      expect(pickup.owner, 'EXAMPLE');
      expect(pickup.documents.map((d) => d.kind), [
        CompanyDocumentKind.registration,
        CompanyDocumentKind.asateelPermit,
        CompanyDocumentKind.cicpaPass,
      ]);
      expect(pickup.documents.last.number, '9000001');
      expect(pickup.documents.last.expiryDate, '2027-02-05');
      expect(named('TOYOTA TEST CAR').owner, 'Personal');
      expect(
        named('WORKMENS INSURANCE(TEST HOUSE)').kind,
        CompanyRecordKind.policy,
      );

      final contract = named('LOA 900001 · TEST PLANT');
      expect(contract.owner, 'EXAMPLE MAIN');
      expect(contract.details.toJson(), {
        'job': 'TEST PLANT',
        'people': 12,
        'vehicles': 2,
        'applied_people': 8,
      });
      expect(contract.documents.single.expiryDate, '2027-01-31');

      final policy = named('TEST BASIC INSURANCE');
      expect(policy.owner, 'Example Main');
      expect(policy.documents.single.kind, CompanyDocumentKind.insurance);
    });

    test('an export reads back into the same records', () {
      final records = [
        CompanyRecord.fromJson(_entity()),
        CompanyRecord.fromJson(_vehicle()),
        CompanyRecord.fromJson(_contract()),
      ];
      final bytes = peopleEncodeWorkbook(
        companyExportSheets(records, today: '2026-11-13'),
      );
      final workbook = const YorksV1BoqWorkbookCodec().decode(
        bytes: bytes,
        fileName: 'Company.xlsx',
      );
      expect(workbook.sheets.map((sheet) => sheet.name), [
        'Company Documents',
        'Needs Attention',
      ]);
      final read = companyReadTracker(workbook);
      expect(read.issueCount, 0);
      expect(read.records.map((record) => record.name), [
        'EXAMPLE MAIN',
        'TEST PICKUP 11111',
        'LOA 900001 · TEST PLANT',
      ]);
      final main = read.records.first;
      expect(main.documents.length, 4);
      expect(
        main.documents
            .firstWhere((d) => d.kind == CompanyDocumentKind.proCard)
            .label,
        'PRO card Test A',
      );
      expect(read.records.last.details.people, 12);
      expect(
        workbook.sheets.first.rows.any((row) => row.first == 'CICPA pass'),
        isTrue,
        reason: 'the register is called CICPA passes',
      );
      expect(
        read.records[1].documents
            .firstWhere((d) => d.kind == CompanyDocumentKind.cicpaPass)
            .sites,
        'Test Plant',
      );
    });
  });

  group('CICPA passes and addresses', () {
    test('an older export that says CICPA contract still reads back', () {
      final bytes = peopleEncodeWorkbook(
        companyExportSheets([
          CompanyRecord.fromJson(_contract()),
        ], today: '2026-11-13'),
      );
      final exported = const YorksV1BoqWorkbookCodec().decode(
        bytes: bytes,
        fileName: 'Company.xlsx',
      );
      final older = YorksV1BoqParsedWorkbook(
        fileName: 'Company.xlsx',
        sheets: [
          for (final sheet in exported.sheets)
            YorksV1BoqWorkbookSheet(
              name: sheet.name,
              rows: [
                for (final row in sheet.rows)
                  [
                    for (final cell in row)
                      cell == 'CICPA pass' ? 'CICPA contract' : cell,
                  ],
              ],
            ),
        ],
      );
      expect(
        older.sheets.first.rows.any((row) => row.first == 'CICPA contract'),
        isTrue,
      );
      final read = companyReadTracker(older);
      expect(read.issueCount, 0);
      expect(read.records.single.kind, CompanyRecordKind.contract);
    });

    test('postal addresses are never documents', () {
      for (final name in [
        'P.O. BOX 4757',
        'PO Box 12',
        'p. o. box 9',
        'POST BOX 77',
      ]) {
        expect(companyIsPostalAddress(name), isTrue, reason: name);
      }
      for (final name in ['ISO 9001', 'CIVIL DEFENCE', 'BOX TRUCK 12345']) {
        expect(companyIsPostalAddress(name), isFalse, reason: name);
      }
    });

    test('every language names the register CICPA passes', () {
      for (final language in AppLanguage.values) {
        for (final label in [
          CompanyStrings.viewContracts,
          CompanyStrings.kindContract,
        ]) {
          expect(label.active(language), contains('CICPA'));
          expect(
            label.active(language).toLowerCase(),
            isNot(contains('contract')),
          );
        }
      }
    });
  });

  group('attachments (PRODUCT_DECISIONS 48)', () {
    setUpAll(loadAccountsV2GoldenFonts);
    const recordAt = '/yorks/company-documents/$_entityId';

    testWidgets('the record lists files and marks the documents they copy', (
      tester,
    ) async {
      _size(tester, const Size(1440, 1400));
      await _pump(tester, _server(), recordAt);
      expect(
        find.byKey(const ValueKey('company-attachment-a-licence')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('company-document-attached-d-licence')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('PR attaches a copy straight from the document', (
      tester,
    ) async {
      _size(tester, const Size(1440, 1400));
      final rpc = _server();
      final stored = _StoredFiles();
      await _pump(tester, rpc, recordAt, stored: stored);
      await tester.tap(
        find.byKey(const ValueKey('company-document-attach-d-licence')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('company-attachment-choose')));
      await tester.pumpAndSettle();
      expect(find.text('Licence scan.png'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('company-attachment-save')));
      await tester.pumpAndSettle();
      final (path, size, type) = stored.uploads.single;
      expect(
        path,
        matches(RegExp('^company/$_entityId/[0-9a-f-]{36}\\.png\$')),
      );
      expect(size, 4096);
      expect(type, 'image/png');
      final sent = rpc.callsTo('v1_company_docs_add_attachment').single;
      expect(sent['p_record_id'], _entityId);
      expect(sent['p_payload'], {
        'object_path': path,
        'file_name': 'Licence scan.png',
        'document_id': 'd-licence',
        'title': null,
      });
      expect(find.text('Attachment added.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opening and removing a file', (tester) async {
      _size(tester, const Size(1440, 1400));
      final rpc = _server();
      final stored = _StoredFiles();
      final opened = <Uri>[];
      await _pump(tester, rpc, recordAt, stored: stored, opened: opened);
      await tester.tap(
        find.byKey(const ValueKey('company-attachment-open-a-licence')),
      );
      await tester.pumpAndSettle();
      expect(stored.links, ['company/$_entityId/a-licence.pdf']);
      expect(opened.single.path, contains('a-licence.pdf'));

      await tester.tap(
        find.byKey(const ValueKey('company-attachment-remove-a-licence')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('attendance-text-dialog-field')),
        'Superseded by the renewed licence',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('attendance-text-dialog-confirm')),
      );
      await tester.pumpAndSettle();
      final sent = rpc.callsTo('v1_company_docs_remove_attachment').single;
      expect(sent['p_attachment_id'], 'a-licence');
      expect(sent['p_reason'], 'Superseded by the renewed licence');
    });

    testWidgets('a reader sees and opens files but cannot add or remove', (
      tester,
    ) async {
      _size(tester, const Size(1440, 1400));
      await _pump(tester, _server(canManage: false), recordAt);
      expect(
        find.byKey(const ValueKey('company-attachment-a-licence')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('company-attachment-add')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('company-attachment-remove-a-licence')),
        findsNothing,
      );
    });

    for (final (size, name) in [
      (const Size(1440, 1000), 'desktop'),
      (const Size(360, 800), 'phone'),
    ]) {
      testWidgets('the registers show a paperclip beside records ($name)', (
        tester,
      ) async {
        _size(tester, size);
        await _pump(
          tester,
          _server(),
          '${RoutePaths.yorksV1CompanyDocuments}?view=licences',
        );
        expect(
          find.byKey(const ValueKey('company-attached-$_entityId')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the phone record shows the Attachments section', (
      tester,
    ) async {
      _size(tester, const Size(360, 800));
      await _pump(tester, _server(), recordAt);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('company-attachment-a-licence')),
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('company-record')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/company_documents_phone_attachments.png'),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('bulk upload (PRODUCT_DECISIONS 49)', () {
    testWidgets('licence numbers and plates find their records and documents', (
      tester,
    ) async {
      _size(tester, const Size(1440, 1000));
      final rpc = _server();
      await _pump(
        tester,
        rpc,
        RoutePaths.yorksV1CompanyDocuments,
        folder: _PickedFiles(const [
          ('CN-0000001 trade licence.pdf', 2048),
          ('11111 mulkiya.jpg', 4096),
        ]),
      );
      await tester.tap(find.byKey(const ValueKey('company-bulk-attach')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('company-bulk-choose')));
      await tester.pumpAndSettle();
      expect(find.text('Matched by number'), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('company-bulk-upload')));
      await tester.pumpAndSettle();
      final sent = rpc.callsTo('v1_company_docs_add_attachment');
      expect(sent.map((call) => call['p_record_id']), [_entityId, _vehicleId]);
      expect((sent.first['p_payload'] as Map)['document_id'], 'd-licence');
      expect(find.text('2 attached'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Company screens', () {
    setUpAll(loadAccountsV2GoldenFonts);

    for (final (size, name) in [
      (const Size(1440, 1000), 'desktop'),
      (const Size(360, 800), 'phone'),
    ]) {
      testWidgets('home shows what needs attention ($name)', (tester) async {
        _size(tester, size);
        await _pump(tester, _server(), RoutePaths.yorksV1CompanyDocuments);
        expect(
          find.byKey(const ValueKey('company-attention-d-licence')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/company_documents_${name}_home.png'),
        );
      });

      testWidgets('record ($name)', (tester) async {
        _size(tester, size);
        await _pump(tester, _server(), '/yorks/company-documents/$_entityId');
        expect(find.byKey(const ValueKey('company-record')), findsOneWidget);
        expect(
          find.text('Trade licence expired on 1 Nov 2026'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/company_documents_${name}_record.png'),
        );
      });
    }

    testWidgets('new contract form (desktop)', (tester) async {
      _size(tester, const Size(1440, 1000));
      await _pump(
        tester,
        _server(),
        '${RoutePaths.yorksV1CompanyDocumentsNew}?kind=contract',
      );
      expect(
        find.byKey(const ValueKey('company-form-contract-card')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/company_documents_desktop_form.png'),
      );
    });

    testWidgets('the vehicles register opens a vehicle', (tester) async {
      _size(tester, const Size(1440, 1000));
      final rpc = _server();
      await _pump(
        tester,
        rpc,
        '${RoutePaths.yorksV1CompanyDocuments}?view=vehicles',
      );
      expect(rpc.callsTo('v1_company_docs_list').last['p_query'], {
        'kinds': ['vehicle'],
        'sort': 'name',
        'limit': 25,
        'offset': 0,
      });
      await tester.tap(find.byKey(const ValueKey('company-row-$_vehicleId')));
      await tester.pumpAndSettle();
      expect(find.text('TEST PICKUP 11111'), findsWidgets);
      expect(find.text('Asateel permit'), findsWidgets);
    });

    testWidgets('a viewer sees no edit commands', (tester) async {
      _size(tester, const Size(1440, 1000));
      await _pump(
        tester,
        _server(canManage: false),
        '/yorks/company-documents/$_entityId',
      );
      expect(find.byKey(const ValueKey('company-record-edit')), findsNothing);
      expect(
        find.byKey(const ValueKey('company-document-renew-d-licence')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('company-add')), findsNothing);
    });

    testWidgets('renewing the trade licence sends the renewal', (tester) async {
      _size(tester, const Size(1440, 1000));
      final rpc = _server();
      await _pump(tester, rpc, '/yorks/company-documents/$_entityId');
      await tester.tap(
        find.byKey(const ValueKey('company-document-renew-d-licence')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('company-doc-renew-hint')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('company-doc-expiry')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('company-doc-save')));
      await tester.pumpAndSettle();
      final now = DateTime.now();
      final today =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final call = rpc.callsTo('v1_company_docs_save_document').single;
      expect(call['p_payload'], {
        'record_id': _entityId,
        'document_id': 'd-licence',
        'renew': true,
        'expiry_date': today,
      });
      expect(call['p_expected_version'], 1);
      expect(find.text('Trade licence renewed'), findsOneWidget);
    });

    testWidgets('a vehicle pass may name only its sites', (tester) async {
      _size(tester, const Size(1440, 1000));
      final rpc = _server();
      rpc.handlers['v1_company_docs_get'] = (_) => {
        ..._vehicle(),
        'documents': <Object>[],
      };
      await _pump(tester, rpc, '/yorks/company-documents/$_vehicleId');
      await tester.tap(
        find.byKey(const ValueKey('company-record-add-document')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('company-doc-save')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a number or an expiry date.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('company-doc-kind')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CICPA pass').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('company-doc-sites')),
        'Test Plant',
      );
      await tester.tap(find.byKey(const ValueKey('company-doc-save')));
      await tester.pumpAndSettle();
      expect(rpc.callsTo('v1_company_docs_save_document').single['p_payload'], {
        'record_id': _vehicleId,
        'kind': 'cicpa_pass',
        'sites': 'Test Plant',
      });
    });

    testWidgets('ending a pass needs a reason', (tester) async {
      _size(tester, const Size(1440, 1000));
      final rpc = _server();
      await _pump(tester, rpc, '/yorks/company-documents/$_vehicleId');
      await tester.tap(
        find.byKey(const ValueKey('company-document-end-d-cicpa')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'End'));
      await tester.pumpAndSettle();
      expect(rpc.callsTo('v1_company_docs_end_document'), isEmpty);
      await tester.enterText(find.byType(TextField).last, 'Vehicle sold');
      await tester.tap(find.widgetWithText(FilledButton, 'End'));
      await tester.pumpAndSettle();
      final call = rpc.callsTo('v1_company_docs_end_document').single;
      expect(call['p_document_id'], 'd-cicpa');
      expect(call['p_reason'], 'Vehicle sold');
    });

    testWidgets('archiving a record needs a reason', (tester) async {
      _size(tester, const Size(1440, 1000));
      final rpc = _server();
      await _pump(tester, rpc, '/yorks/company-documents/$_entityId');
      await tester.tap(find.byKey(const ValueKey('company-record-archive')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
      await tester.pumpAndSettle();
      expect(rpc.callsTo('v1_company_docs_set_archived'), isEmpty);
      await tester.enterText(find.byType(TextField).last, 'Branch closed');
      await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
      await tester.pumpAndSettle();
      final call = rpc.callsTo('v1_company_docs_set_archived').single;
      expect(call['p_archived'], true);
      expect(call['p_reason'], 'Branch closed');
      expect(call['p_expected_version'], 2);
    });

    testWidgets('a new contract keeps its job and counts', (tester) async {
      _size(tester, const Size(1440, 1000));
      final rpc = _server();
      await _pump(
        tester,
        rpc,
        '${RoutePaths.yorksV1CompanyDocumentsNew}?kind=contract',
      );
      await tester.tap(find.byKey(const ValueKey('company-form-save')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name.'), findsOneWidget);
      expect(rpc.callsTo('v1_company_docs_save_record'), isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('company-form-name')),
        'LOA 900001 · TEST PLANT',
      );
      await tester.enterText(
        find.byKey(const ValueKey('company-form-reference')),
        '900001',
      );
      await tester.enterText(
        find.byKey(const ValueKey('company-form-job')),
        'TEST PLANT',
      );
      await tester.enterText(
        find.byKey(const ValueKey('company-form-people')),
        '12',
      );
      await tester.tap(find.byKey(const ValueKey('company-form-save')));
      await tester.pumpAndSettle();
      final call = rpc.callsTo('v1_company_docs_save_record').single;
      expect(call['p_payload'], {
        'kind': 'contract',
        'name': 'LOA 900001 · TEST PLANT',
        'reference': '900001',
        'details': {'job': 'TEST PLANT', 'people': 12},
      });
      expect(call['p_expected_version'], 0);
      expect(find.byKey(const ValueKey('company-record')), findsOneWidget);
    });

    testWidgets('editing shows a conflict in place', (tester) async {
      _size(tester, const Size(1440, 1000));
      final rpc = _server();
      rpc.handlers['v1_company_docs_save_record'] = (_) =>
          throw const PostgrestException(message: 'conflict', code: '40001');
      await _pump(tester, rpc, '/yorks/company-documents/$_entityId/edit');
      expect(find.text('Edit EXAMPLE MAIN'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('company-form-save')));
      await tester.pumpAndSettle();
      final call = rpc.callsTo('v1_company_docs_save_record').single;
      expect((call['p_payload'] as Map)['record_id'], _entityId);
      expect(call['p_expected_version'], 2);
      expect(
        find.text('Someone else changed this. Refresh and try again.'),
        findsOneWidget,
      );
    });

    testWidgets('import previews, then imports once', (tester) async {
      _size(tester, const Size(1440, 1000));
      final rpc = _server();
      Map<String, Object?> result() => {
        'counts': {
          'new': 3,
          'update': 0,
          'unchanged': 0,
          'problem': 0,
          'documents_new': 8,
          'documents_renewed': 0,
          'documents_updated': 0,
        },
        'rows': [
          {
            'row': 2,
            'sheet': 'Company Documents',
            'kind': 'entity',
            'name': 'EXAMPLE MAIN',
            'action': 'new',
            'changes': <String>[],
            'problems': <String>[],
          },
        ],
      };
      rpc.handlers['v1_company_docs_preview_import'] = (_) => result();
      rpc.handlers['v1_company_docs_import'] = (_) => result();
      final files = _Files(
        YorksV1BoqSelectedWorkbook(
          fileName: 'Company.xlsx',
          bytes: peopleEncodeWorkbook(
            companyExportSheets([
              CompanyRecord.fromJson(_entity()),
              CompanyRecord.fromJson(_vehicle()),
              CompanyRecord.fromJson(_contract()),
            ], today: '2026-11-13'),
          ),
        ),
      );
      await _pump(
        tester,
        rpc,
        RoutePaths.yorksV1CompanyDocuments,
        files: files,
      );
      await tester.tap(find.byKey(const ValueKey('company-import')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('company-import-choose')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('company-import-rows')), findsOneWidget);
      final preview = rpc.callsTo('v1_company_docs_preview_import').single;
      expect(((preview['p_payload'] as Map)['records'] as List).length, 3);
      await tester.tap(find.byKey(const ValueKey('company-import-commit')));
      await tester.pumpAndSettle();
      expect(
        rpc.callsTo('v1_company_docs_import').single['p_idempotency_key'],
        isNotEmpty,
      );
      expect(find.byKey(const ValueKey('company-import-dialog')), findsNothing);
    });

    testWidgets('export saves every record', (tester) async {
      _size(tester, const Size(1440, 1000));
      final files = _Files();
      await _pump(
        tester,
        _server(),
        RoutePaths.yorksV1CompanyDocuments,
        files: files,
      );
      await tester.tap(find.byKey(const ValueKey('company-export')));
      await tester.pumpAndSettle();
      expect(files.savedName, startsWith('Company_Documents_'));
      final read = companyReadTracker(
        const YorksV1BoqWorkbookCodec().decode(
          bytes: files.saved!,
          fileName: files.savedName!,
        ),
      );
      expect(read.records.length, 3);
    });

    testWidgets('a refused reader is told so', (tester) async {
      _size(tester, const Size(1440, 1000));
      final rpc = _server();
      rpc.handlers['v1_company_docs_overview'] = (_) =>
          throw const PostgrestException(message: 'denied', code: '42501');
      await _pump(tester, rpc, RoutePaths.yorksV1CompanyDocuments);
      expect(
        find.text('You do not have access to company documents.'),
        findsOneWidget,
      );
    });
  });
}
